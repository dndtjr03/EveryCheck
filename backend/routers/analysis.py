"""분석 세션·사진·메시지 REST API (Flutter SQLite 대체 + 구 RepairEstimate 흡수)."""

from datetime import datetime, timezone
from decimal import Decimal
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import schemas
from auth import get_current_active_user
from database import get_db
from models import Analysis, AnalysisMessage, AnalysisPhoto, RealEstate, User

router = APIRouter()


def _own_analysis_or_404(db: Session, analysis_id: int, user: User) -> Analysis:
    a = db.query(Analysis).filter(Analysis.id == analysis_id).first()
    if a is None or a.owner_id != user.id:
        raise HTTPException(status_code=404, detail="analysis not found")
    return a


# ── Analysis ────────────────────────────────────────────────────────────


@router.post("/", response_model=schemas.AnalysisRead, status_code=201)
def create_analysis(
    body: schemas.AnalysisCreate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> Analysis:
    contract = (
        db.query(RealEstate)
        .filter(RealEstate.id == body.contract_id, RealEstate.owner_id == user.id)
        .first()
    )
    if contract is None:
        raise HTTPException(status_code=404, detail="contract not found")
    a = Analysis(
        owner_id=user.id,
        contract_id=body.contract_id,
        contract_addr=body.contract_addr,
        status="pending",
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


@router.get("/", response_model=List[schemas.AnalysisRead])
def list_analyses(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> List[Analysis]:
    return (
        db.query(Analysis)
        .filter(Analysis.owner_id == user.id)
        .order_by(Analysis.started_at.desc())
        .all()
    )


@router.get("/{analysis_id}", response_model=schemas.AnalysisRead)
def get_analysis(
    analysis_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> Analysis:
    return _own_analysis_or_404(db, analysis_id, user)


@router.patch("/{analysis_id}", response_model=schemas.AnalysisRead)
def update_analysis(
    analysis_id: int,
    body: schemas.AnalysisUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> Analysis:
    a = _own_analysis_or_404(db, analysis_id, user)
    if body.status is not None:
        a.status = body.status
        if body.status == "completed" and a.completed_at is None:
            a.completed_at = datetime.now(timezone.utc)
    if body.summary is not None:
        a.summary = body.summary
    if body.estimated_cost is not None:
        a.estimated_cost = body.estimated_cost
    db.commit()
    db.refresh(a)
    return a


@router.delete("/{analysis_id}", status_code=204)
def delete_analysis(
    analysis_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> None:
    a = _own_analysis_or_404(db, analysis_id, user)
    db.delete(a)
    db.commit()


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
    _own_analysis_or_404(db, analysis_id, user)
    p = AnalysisPhoto(
        analysis_id=analysis_id,
        s3_url=body.s3_url,
        group_type=body.group_type,
        order_index=body.order_index,
        analyzed=False,
        file_hash=body.file_hash,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


@router.get(
    "/{analysis_id}/photos",
    response_model=List[schemas.AnalysisPhotoRead],
)
def list_photos(
    analysis_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> List[AnalysisPhoto]:
    _own_analysis_or_404(db, analysis_id, user)
    return (
        db.query(AnalysisPhoto)
        .filter(AnalysisPhoto.analysis_id == analysis_id)
        .order_by(AnalysisPhoto.order_index.asc())
        .all()
    )


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
    _own_analysis_or_404(db, analysis_id, user)
    p = (
        db.query(AnalysisPhoto)
        .filter(
            AnalysisPhoto.id == photo_id,
            AnalysisPhoto.analysis_id == analysis_id,
        )
        .first()
    )
    if p is None:
        raise HTTPException(status_code=404, detail="photo not found")

    # 기본 필드
    if body.analyzed is not None:
        p.analyzed = body.analyzed
    if body.ai_result is not None:
        p.ai_result = body.ai_result
    if body.s3_url is not None:
        p.s3_url = body.s3_url

    # 구 RepairEstimate/DamageImage 흡수 필드
    if body.file_hash is not None:
        p.file_hash = body.file_hash
    if body.damage_type is not None:
        p.damage_type = body.damage_type
    if body.part is not None:
        p.part = body.part
    if body.ai_confidence is not None:
        p.ai_confidence = body.ai_confidence
    if body.analysis_status is not None:
        p.analysis_status = body.analysis_status
    if body.celery_task_id is not None:
        p.celery_task_id = body.celery_task_id
    if body.total_repair_cost is not None:
        p.total_repair_cost = Decimal(str(body.total_repair_cost))
    if body.tenant_cost is not None:
        p.tenant_cost = Decimal(str(body.tenant_cost))
    if body.depreciation_rate is not None:
        p.depreciation_rate = body.depreciation_rate
    if body.useful_life_years is not None:
        p.useful_life_years = body.useful_life_years
    if body.elapsed_years is not None:
        p.elapsed_years = body.elapsed_years

    db.commit()
    db.refresh(p)
    return p


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
    _own_analysis_or_404(db, analysis_id, user)
    m = AnalysisMessage(
        analysis_id=analysis_id,
        role=body.role,
        content=body.content,
        photo_id=body.photo_id,
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


@router.get(
    "/{analysis_id}/messages",
    response_model=List[schemas.AnalysisMessageRead],
)
def list_messages(
    analysis_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_active_user),
) -> List[AnalysisMessage]:
    _own_analysis_or_404(db, analysis_id, user)
    return (
        db.query(AnalysisMessage)
        .filter(AnalysisMessage.analysis_id == analysis_id)
        .order_by(AnalysisMessage.created_at.asc(), AnalysisMessage.id.asc())
        .all()
    )
