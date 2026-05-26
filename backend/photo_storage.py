"""체크리스트 사진 저장 백엔드 (로컬 디스크 · AWS S3)."""

from __future__ import annotations

import asyncio
import logging
import os
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Awaitable, Callable, Optional

from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError
from fastapi import UploadFile

from utils import delete_object_from_s3, generate_presigned_get_url, put_bytes_to_s3

logger = logging.getLogger(__name__)

CHUNK_SIZE = 1024 * 1024
MAX_FILE_BYTES = 10 * 1024 * 1024
MAX_TOTAL_BYTES = 150 * 1024 * 1024
DEFAULT_PRESIGNED_EXPIRES = 300
ALLOWED_CONTENT_TYPES = frozenset({"image/jpeg", "image/png"})
_MIME_TO_EXT = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
}


class PresignedUrlError(Exception):
    """Presigned URL 생성 실패."""


@dataclass(frozen=True)
class StoredPhoto:
    """저장 완료된 사진 메타데이터 (스토리지 구현체 공통)."""

    original_name: str
    stored_name: str
    image_url: str
    size_bytes: int
    local_path: Optional[Path] = None
    s3_bucket: Optional[str] = None
    s3_key: Optional[str] = None


class PhotoStorageBackend(ABC):
    """사진 저장 백엔드 추상 인터페이스 (로컬 · S3 교체용)."""

    @abstractmethod
    async def save_upload(
        self,
        upload: UploadFile,
        *,
        on_bytes_read: Optional[Callable[[int], Awaitable[None]]] = None,
    ) -> StoredPhoto:
        """업로드 파일을 저장하고 DB에 기록할 참조 경로/키를 반환한다."""

    @abstractmethod
    async def delete_saved(self, stored: StoredPhoto) -> None:
        """저장된 객체를 삭제한다 (롤백·정리용)."""

    @abstractmethod
    def get_display_url(self, file_key: str, expires_in: int = DEFAULT_PRESIGNED_EXPIRES) -> str:
        """클라이언트 조회용 URL (S3: Presigned GET, 로컬: 정적 경로)."""

    async def aget_display_url(
        self, file_key: str, expires_in: int = DEFAULT_PRESIGNED_EXPIRES
    ) -> str:
        """비동기 핸들러에서 Presigned URL 생성 등 블로킹 작업을 스레드 풀로 실행한다."""

        return await asyncio.to_thread(self.get_display_url, file_key, expires_in)


def _normalize_content_type(upload: UploadFile) -> str:
    raw = (upload.content_type or "").split(";")[0].strip().lower()
    return raw


def _validate_content_type(upload: UploadFile) -> str:
    content_type = _normalize_content_type(upload)
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise ValueError(
            "허용되지 않은 이미지 형식입니다. image/jpeg 또는 image/png 만 업로드할 수 있습니다."
        )
    return content_type


def _secure_stored_name(content_type: str) -> str:
    ext = _MIME_TO_EXT[content_type]
    return f"{uuid.uuid4().hex}{ext}"


async def _read_upload_with_limits(
    upload: UploadFile,
    *,
    on_bytes_read: Optional[Callable[[int], Awaitable[None]]] = None,
) -> bytes:
    chunks: list[bytes] = []
    file_total = 0
    while True:
        chunk = await upload.read(CHUNK_SIZE)
        if not chunk:
            break
        file_total += len(chunk)
        if file_total > MAX_FILE_BYTES:
            raise ValueError("개별 파일 크기는 10MB 를 넘을 수 없습니다.")
        if on_bytes_read is not None:
            await on_bytes_read(len(chunk))
        chunks.append(chunk)
    return b"".join(chunks)


class LocalPhotoStorage(PhotoStorageBackend):
    """``uploads/`` 디렉터리에 파일을 저장하는 구현체."""

    def __init__(self, upload_dir: Path, *, url_prefix: str = "/static/uploads") -> None:
        self.upload_dir = upload_dir
        self.url_prefix = url_prefix.rstrip("/")

    async def save_upload(
        self,
        upload: UploadFile,
        *,
        on_bytes_read: Optional[Callable[[int], Awaitable[None]]] = None,
    ) -> StoredPhoto:
        content_type = _validate_content_type(upload)
        original_name = (upload.filename or "upload").replace("\\", "/").split("/")[-1][:255]
        stored_name = _secure_stored_name(content_type)
        dest = self.upload_dir / stored_name

        self.upload_dir.mkdir(parents=True, exist_ok=True)
        try:
            data = await _read_upload_with_limits(upload, on_bytes_read=on_bytes_read)
            await asyncio.to_thread(dest.write_bytes, data)
        except Exception:
            dest.unlink(missing_ok=True)
            raise
        finally:
            await upload.close()

        static_path = f"{self.url_prefix}/{stored_name}"
        return StoredPhoto(
            original_name=original_name,
            stored_name=stored_name,
            image_url=static_path,
            size_bytes=len(data),
            local_path=dest,
        )

    async def delete_saved(self, stored: StoredPhoto) -> None:
        if stored.local_path is not None:

            def _unlink() -> None:
                stored.local_path.unlink(missing_ok=True)  # type: ignore[union-attr]

            await asyncio.to_thread(_unlink)

    def get_display_url(self, file_key: str, expires_in: int = DEFAULT_PRESIGNED_EXPIRES) -> str:
        _ = expires_in
        name = Path(file_key).name
        if file_key.startswith("/"):
            return file_key
        return f"{self.url_prefix}/{name}"


class S3PhotoStorage(PhotoStorageBackend):
    """AWS S3에 체크리스트 사진을 저장한다."""

    def __init__(
        self,
        *,
        bucket_name: str,
        key_prefix: str = "checklist-photos",
        region: Optional[str] = None,
    ) -> None:
        if not bucket_name.strip():
            raise ValueError("S3_BUCKET_NAME 이 비어 있습니다.")
        self.bucket_name = bucket_name.strip()
        self.key_prefix = key_prefix.strip().strip("/")
        self.region = (region or os.getenv("AWS_REGION", "ap-northeast-2")).strip()

    def _object_key(self, stored_name: str) -> str:
        return f"{self.key_prefix}/{stored_name}"

    async def save_upload(
        self,
        upload: UploadFile,
        *,
        on_bytes_read: Optional[Callable[[int], Awaitable[None]]] = None,
    ) -> StoredPhoto:
        content_type = _validate_content_type(upload)
        original_name = (upload.filename or "upload").replace("\\", "/").split("/")[-1][:255]
        stored_name = _secure_stored_name(content_type)
        key = self._object_key(stored_name)

        try:
            data = await _read_upload_with_limits(upload, on_bytes_read=on_bytes_read)
            await asyncio.to_thread(
                put_bytes_to_s3,
                bucket_name=self.bucket_name,
                key=key,
                body=data,
                content_type=content_type,
            )
        except Exception:
            try:
                await asyncio.to_thread(
                    delete_object_from_s3,
                    bucket_name=self.bucket_name,
                    key=key,
                )
            except Exception:
                logger.warning("S3 partial upload cleanup failed for key=%s", key, exc_info=True)
            raise
        finally:
            await upload.close()

        return StoredPhoto(
            original_name=original_name,
            stored_name=stored_name,
            image_url=key,
            size_bytes=len(data),
            s3_bucket=self.bucket_name,
            s3_key=key,
        )

    async def delete_saved(self, stored: StoredPhoto) -> None:
        if not stored.s3_bucket or not stored.s3_key:
            return
        await asyncio.to_thread(
            delete_object_from_s3,
            bucket_name=stored.s3_bucket,
            key=stored.s3_key,
        )

    def get_display_url(self, file_key: str, expires_in: int = DEFAULT_PRESIGNED_EXPIRES) -> str:
        try:
            return generate_presigned_get_url(
                bucket_name=self.bucket_name,
                key=file_key,
                expires_in=expires_in,
            )
        except (NoCredentialsError, ClientError, BotoCoreError) as exc:
            logger.exception("Presigned URL generation failed for key=%s", file_key)
            raise PresignedUrlError("임시 조회 URL 생성에 실패했습니다.") from exc
        except ValueError as exc:
            raise PresignedUrlError(str(exc)) from exc


class UploadSizeTracker:
    """요청 단위 전체 업로드 용량(최대 150MB)을 추적한다."""

    def __init__(self, max_total_bytes: int = MAX_TOTAL_BYTES) -> None:
        self._max_total = max_total_bytes
        self._total = 0
        self._lock = asyncio.Lock()

    async def add(self, nbytes: int) -> None:
        async with self._lock:
            if self._total + nbytes > self._max_total:
                raise ValueError(
                    f"전체 업로드 용량은 {self._max_total // (1024 * 1024)}MB 를 넘을 수 없습니다."
                )
            self._total += nbytes

    @property
    def total_bytes(self) -> int:
        return self._total


def create_photo_storage(upload_dir: Path) -> PhotoStorageBackend:
    bucket = os.getenv("S3_BUCKET_NAME", "").strip()
    if bucket:
        prefix = os.getenv("S3_PHOTO_KEY_PREFIX", "checklist-photos").strip() or "checklist-photos"
        storage = S3PhotoStorage(
            bucket_name=bucket,
            key_prefix=prefix,
            region=os.getenv("AWS_REGION"),
        )
        logger.info(
            "Photo storage: S3 bucket=%s prefix=%s region=%s (private, presigned GET)",
            storage.bucket_name,
            storage.key_prefix,
            storage.region,
        )
        return storage

    logger.info("Photo storage: local directory %s", upload_dir)
    return LocalPhotoStorage(upload_dir)


def storage_backend_label(storage: PhotoStorageBackend) -> str:
    if isinstance(storage, S3PhotoStorage):
        return f"s3://{storage.bucket_name}/{storage.key_prefix}"
    return "local:uploads/"


def resolve_storage_file_key(photo_image_url: str) -> str:
    """DB ``image_url`` 값에서 스토리지 조회용 file_key 를 추출한다."""

    value = (photo_image_url or "").strip()
    if not value:
        raise ValueError("image_url 이 비어 있습니다.")
    if value.startswith("http://") or value.startswith("https://"):
        from utils import parse_s3_public_bucket_key

        _, key = parse_s3_public_bucket_key(value)
        return key
    if value.startswith("/static/uploads/"):
        return value.removeprefix("/static/uploads/").lstrip("/")
    return value
