"""사진(Photo) API."""

import asyncio
import logging
from pathlib import Path
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status
from sqlalchemy.orm import Session

import schemas
from auth import get_current_active_user
from config import get_settings
from core.rate_limit import limiter
from database import get_db
from models import Checklist, Photo, PhotoTypeEnum, User
from photo_storage import (
    DEFAULT_PRESIGNED_EXPIRES,
    PhotoStorageBackend,
    PresignedUrlError,
    StoredPhoto,
    UploadSizeTracker,
    create_photo_storage,
    resolve_storage_file_key,
    storage_backend_label,
)
from utils import (
    compute_image_hash_sha256,
    upload_image_to_s3,
    validate_and_read_image_file,
)

router = APIRouter()
logger = logging.getLogger(__name__)

_BACKEND_DIR = Path(__file__).resolve().parent.parent
_UPLOAD_DIR = _BACKEND_DIR / "uploads"
_MAX_FILES_PER_REQUEST = 30
_SAVE_CONCURRENCY = 5

_storage: PhotoStorageBackend | None = None


def _get_storage() -> PhotoStorageBackend:
    global _storage
    if _storage is None:
        _storage = create_photo_storage(_UPLOAD_DIR)
    return _storage


def _parse_photo_type(raw: str) -> PhotoTypeEnum:
    key = (raw or "").strip().upper()
    if key == PhotoTypeEnum.INITIAL.value:
        return PhotoTypeEnum.INITIAL
    if key == PhotoTypeEnum.DAMAGED.value:
        return PhotoTypeEnum.DAMAGED
    raise HTTPException(
        status_code=400,
        detail="photo_type 은 INITIAL 또는 DAMAGED 여야 합니다.",
    )


def _assert_photo_owner(photo: Photo, current_user: User) -> None:
    if photo.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="해당 사진에 접근할 권한이 없습니다.",
        )


async def _build_display_item(
    photo: Photo,
    storage: PhotoStorageBackend,
    *,
    expires_in: int = DEFAULT_PRESIGNED_EXPIRES,
) -> schemas.PhotoDisplayItem:
    try:
        file_key = resolve_storage_file_key(photo.image_url)
        display_url = await storage.aget_display_url(file_key, expires_in)
    except PresignedUrlError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc)) from exc

    return schemas.PhotoDisplayItem(
        photo_id=photo.id,
        display_url=display_url,
        expires_in=expires_in,
        original_name=photo.original_name,
        photo_type=photo.photo_type.value
        if hasattr(photo.photo_type, "value")
        else str(photo.photo_type),
        checklist_id=photo.checklist_id,
        created_at=photo.created_at,
    )


async def _cleanup_saved_files(saved: List[StoredPhoto]) -> None:
    storage = _get_storage()
    await asyncio.gather(*[storage.delete_saved(item) for item in saved])


@router.get(
    "/",
    response_model=schemas.PhotoDisplayListResponse,
    summary="내 사진 목록 조회 (Presigned URL)",
    description=(
        "로그인한 사용자가 소유한 사진만 반환합니다. "
        "S3 비공개 버킷의 경우 ``display_url`` 에 Presigned GET URL(기본 5분)이 포함됩니다."
    ),
)
async def list_my_photos(
    checklist_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> schemas.PhotoDisplayListResponse:
    query = db.query(Photo).filter(Photo.user_id == current_user.id)
    if checklist_id is not None:
        query = query.filter(Photo.checklist_id == checklist_id)
    rows = query.order_by(Photo.id.asc()).all()

    storage = _get_storage()
    items = await asyncio.gather(*[_build_display_item(row, storage) for row in rows])
    return schemas.PhotoDisplayListResponse(count=len(items), photos=list(items))


@router.post(
    "/upload",
    response_model=schemas.PhotoUploadBatchResponse,
    summary="사진 다중 업로드 (S3 Private + Presigned 조회)",
    description=(
        "multipart 로 JPEG/PNG 이미지를 최대 30장까지 업로드합니다. "
        "개별 파일 10MB, 전체 합계 150MB 제한. "
        "소유자는 JWT 로그인 사용자로 자동 기록됩니다. "
        "S3 비공개 저장 후 응답의 display_url 은 Presigned URL 입니다."
    ),
)
async def upload_photos(
    files: List[UploadFile] = File(..., description="이미지 파일 목록 (JPEG/PNG)"),
    checklist_id: int = Form(..., description="연결할 체크리스트 ID"),
    photo_type: str = Form(
        PhotoTypeEnum.INITIAL.value,
        description="INITIAL(처음 상태) 또는 DAMAGED(손상 상태)",
    ),
    description: Optional[str] = Form(None, description="모든 사진에 공통 적용할 설명(선택)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> schemas.PhotoUploadBatchResponse:
    if not files:
        raise HTTPException(status_code=400, detail="업로드할 파일이 없습니다.")
    if len(files) > _MAX_FILES_PER_REQUEST:
        raise HTTPException(
            status_code=400,
            detail=f"한 번에 최대 {_MAX_FILES_PER_REQUEST}장까지 업로드할 수 있습니다.",
        )

    checklist = db.query(Checklist).filter(Checklist.id == checklist_id).first()
    if checklist is None:
        raise HTTPException(status_code=404, detail="체크리스트를 찾을 수 없습니다.")
    if checklist.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="해당 체크리스트에 사진을 업로드할 권한이 없습니다.",
        )

    ptype = _parse_photo_type(photo_type)
    desc_value = description[:1024] if description else None
    total_files = len(files)
    storage = _get_storage()
    logger.info(
        "Batch upload start: user_id=%s files=%s -> %s",
        current_user.id,
        total_files,
        storage_backend_label(storage),
    )
    size_tracker = UploadSizeTracker()
    sem = asyncio.Semaphore(_SAVE_CONCURRENCY)
    saved: List[StoredPhoto] = []

    async def _save_one(index: int, upload: UploadFile) -> StoredPhoto:
        async with sem:
            logger.info("Processing photo %s/%s...", index + 1, total_files)

            async def _track_chunk(n: int) -> None:
                await size_tracker.add(n)

            return await storage.save_upload(upload, on_bytes_read=_track_chunk)

    try:
        results = await asyncio.gather(
            *[_save_one(i, f) for i, f in enumerate(files)],
            return_exceptions=True,
        )
        for result in results:
            if isinstance(result, Exception):
                if isinstance(result, ValueError):
                    raise HTTPException(status_code=400, detail=str(result)) from result
                raise HTTPException(
                    status_code=500,
                    detail="파일 저장 중 오류가 발생했습니다.",
                ) from result
            saved.append(result)
    except HTTPException:
        await _cleanup_saved_files(saved)
        raise
    except Exception as exc:
        await _cleanup_saved_files(saved)
        raise HTTPException(
            status_code=500,
            detail="파일 저장 중 오류가 발생했습니다.",
        ) from exc

    rows: List[Photo] = []
    try:
        for item in saved:
            row = Photo(
                user_id=current_user.id,
                checklist_id=checklist_id,
                image_url=item.image_url,
                original_name=item.original_name,
                description=desc_value,
                photo_type=ptype,
            )
            db.add(row)
            rows.append(row)
        db.commit()
        for row in rows:
            db.refresh(row)
    except Exception as exc:
        db.rollback()
        await _cleanup_saved_files(saved)
        raise HTTPException(
            status_code=500,
            detail="DB 저장 중 오류가 발생했습니다.",
        ) from exc

    logger.info(
        "Upload complete: user_id=%s photos=%s total_bytes=%s",
        current_user.id,
        len(rows),
        size_tracker.total_bytes,
    )

    upload_items: List[schemas.PhotoUploadItem] = []
    for row in rows:
        item = await _build_display_item(row, storage)
        upload_items.append(
            schemas.PhotoUploadItem(
                photo_id=item.photo_id,
                display_url=item.display_url,
                expires_in=item.expires_in,
            )
        )

    return schemas.PhotoUploadBatchResponse(count=len(upload_items), photos=upload_items)


@router.get(
    "/compare/{checklist_id}",
    response_model=schemas.PhotoCompareResponse,
    summary="체크리스트별 INITIAL vs DAMAGED 비교 조회 (Presigned URL)",
    description="체크리스트 소유자만 조회할 수 있으며, 각 사진에 Presigned URL을 포함합니다.",
)
async def compare_photos_for_checklist(
    checklist_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> schemas.PhotoCompareResponse:
    cl = db.query(Checklist).filter(Checklist.id == checklist_id).first()
    if cl is None:
        raise HTTPException(status_code=404, detail="체크리스트를 찾을 수 없습니다.")
    if cl.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="해당 체크리스트를 조회할 권한이 없습니다.",
        )

    storage = _get_storage()
    initial_rows = (
        db.query(Photo)
        .filter(
            Photo.checklist_id == checklist_id,
            Photo.photo_type == PhotoTypeEnum.INITIAL,
        )
        .order_by(Photo.id.asc())
        .all()
    )
    damaged_rows = (
        db.query(Photo)
        .filter(
            Photo.checklist_id == checklist_id,
            Photo.photo_type == PhotoTypeEnum.DAMAGED,
        )
        .order_by(Photo.id.asc())
        .all()
    )

    initial = await asyncio.gather(*[_build_display_item(row, storage) for row in initial_rows])
    damaged = await asyncio.gather(*[_build_display_item(row, storage) for row in damaged_rows])

    return schemas.PhotoCompareResponse(
        checklist_id=checklist_id,
        initial=list(initial),
        damaged=list(damaged),
    )


@router.get(
    "/{photo_id}",
    response_model=schemas.PhotoDisplayItem,
    summary="사진 상세 조회 (Presigned URL)",
    description="소유자만 조회 가능하며, S3 객체는 Presigned URL로 임시 접근합니다.",
)
async def get_photo(
    photo_id: int,
    expires_in: int = DEFAULT_PRESIGNED_EXPIRES,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> schemas.PhotoDisplayItem:
    photo = db.query(Photo).filter(Photo.id == photo_id).first()
    if photo is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사진을 찾을 수 없습니다.")

    _assert_photo_owner(photo, current_user)
    if expires_in < 60 or expires_in > 3600:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="expires_in 은 60~3600 초 사이여야 합니다.",
        )

    return await _build_display_item(photo, _get_storage(), expires_in=expires_in)


@router.post(
    "/upload-single",
    summary="단순 사진 업로드 → S3 (분석·체크리스트와 무관)",
    description=(
        "Flutter 분석 화면이 사용하는 단일 사진 S3 업로드 엔드포인트. "
        "DB에 별도 행을 만들지 않고 S3 URL만 반환한다."
    ),
)
@limiter.limit("30/minute")
async def upload_single_photo(
    request: Request,
    file: UploadFile = File(..., description="JPEG/PNG/WEBP 이미지 1장"),
    current_user: User = Depends(get_current_active_user),
) -> dict:
    """분석 모델과 분리된 단일 사진 S3 업로드.

    Flutter 측은 받은 s3_url 을 `/analyses/{id}/photos` POST 본문의 `s3_url` 에 넣어 등록한다.
    """
    try:
        file_bytes, detected_mime = await validate_and_read_image_file(file)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    bucket_name = get_settings().s3_bucket_name or ""
    if not bucket_name:
        raise HTTPException(
            status_code=503,
            detail="S3_BUCKET_NAME 환경 변수가 비어 있습니다.",
        )

    try:
        s3_url = await upload_image_to_s3(
            file,
            bucket_name=bucket_name,
            body=file_bytes,
            content_type=detected_mime,
        )
    except ValueError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "s3_url": s3_url,
        "image_hash": compute_image_hash_sha256(file_bytes),
        "content_type": detected_mime,
        "bytes": len(file_bytes),
    }
