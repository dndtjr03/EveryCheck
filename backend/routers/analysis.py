"""분석 세션·사진·메시지 REST API (Flutter SQLite 대체 + 구 RepairEstimate 흡수).

라우터는 HTTP 입출력 변환 + 소유권 확인만 담당. 도메인 로직은 services/analysis_service에 위치.
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import schemas
from auth import get_current_active_user
from database import get_db
from models import Analysis, AnalysisMessage, AnalysisPhoto, User
from services import analysis_service

router = APIRouter()


def _own_or_404(db: Session, analysis_id: int, user: User) -> Analysis:
    a = analysis_service.get_owned(db, owner=user, analysis_id=analysis_id)
    if a is None:
        raise HTTPException(status_code=404, detail="analysis not found")
    return a


# ── Analysis ────────────────────────────────────────────────────────────


@router.post("", response_model=schemas.AnalysisRead, status_code=201)
@router.post("/", response_model=schemas.AnalysisRead, status_code=201, include_in_schema=False)
def create_analysis(
    body: schemas.AnalysisCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> Analysis:
    a = analysis_service.create_for_contract(db, owner=user, payload=body)
    if a is None:
        raise HTTPException(status_code=404, detail="contract not found")
    return a


@router.get("", response_model=List[schemas.AnalysisRead])
@router.get("/", response_model=List[schemas.AnalysisRead], include_in_schema=False)
def list_analyses(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> List[Analysis]:
    return analysis_service.list_for_owner(db, owner=user)


@router.get("/{analysis_id}", response_model=schemas.AnalysisRead)
def get_analysis(
    analysis_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> Analysis:
    return _own_or_404(db, analysis_id, user)


@router.patch("/{analysis_id}", response_model=schemas.AnalysisRead)
def update_analysis(
    analysis_id: int,
    body: schemas.AnalysisUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> Analysis:
    a = _own_or_404(db, analysis_id, user)
    return analysis_service.update(db, a, body)


@router.delete("/{analysis_id}", status_code=204)
def delete_analysis(
    analysis_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> None:
    a = _own_or_404(db, analysis_id, user)
    analysis_service.delete(db, a)


# ── Photos ─────────────────────────────────────────────────────────────


@router.post(
    "/{analysis_id}/photos",
    response_model=schemas.AnalysisPhotoRead,
    status_code=201,
)
def add_photo(
    analysis_id: int,
    body: schemas.AnalysisPhotoCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> AnalysisPhoto:
    _own_or_404(db, analysis_id, user)
    return analysis_service.add_photo(db, analysis_id=analysis_id, payload=body)


@router.get(
    "/{analysis_id}/photos",
    response_model=List[schemas.AnalysisPhotoRead],
)
def list_photos(
    analysis_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> List[AnalysisPhoto]:
    _own_or_404(db, analysis_id, user)
    return analysis_service.list_photos(db, analysis_id)


@router.patch(
    "/{analysis_id}/photos/{photo_id}",
    response_model=schemas.AnalysisPhotoRead,
)
def update_photo(
    analysis_id: int,
    photo_id: int,
    body: schemas.AnalysisPhotoUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> AnalysisPhoto:
    _own_or_404(db, analysis_id, user)
    p = analysis_service.get_photo(db, analysis_id=analysis_id, photo_id=photo_id)
    if p is None:
        raise HTTPException(status_code=404, detail="photo not found")
    return analysis_service.update_photo(db, p, body)


# ── Messages ───────────────────────────────────────────────────────────


@router.post(
    "/{analysis_id}/messages",
    response_model=schemas.AnalysisMessageRead,
    status_code=201,
)
def add_message(
    analysis_id: int,
    body: schemas.AnalysisMessageCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> AnalysisMessage:
    _own_or_404(db, analysis_id, user)
    return analysis_service.add_message(db, analysis_id=analysis_id, payload=body)


@router.get(
    "/{analysis_id}/messages",
    response_model=List[schemas.AnalysisMessageRead],
)
def list_messages(
    analysis_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> List[AnalysisMessage]:
    _own_or_404(db, analysis_id, user)
    return analysis_service.list_messages(db, analysis_id)
