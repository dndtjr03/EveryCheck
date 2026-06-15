"""분석 세션·사진·메시지 비즈니스 로직."""

from datetime import datetime, timezone
from decimal import Decimal
from typing import List, Optional

from sqlalchemy.orm import Session

import schemas
from models import Analysis, AnalysisMessage, AnalysisPhoto, RealEstate, User


# ── Analysis ────────────────────────────────────────────────────────────


def get_owned(db: Session, *, owner: User, analysis_id: int) -> Optional[Analysis]:
    a = db.query(Analysis).filter(Analysis.id == analysis_id).first()
    if a is None or a.owner_id != owner.id:
        return None
    return a


def list_for_owner(db: Session, *, owner: User) -> List[Analysis]:
    return (
        db.query(Analysis)
        .filter(Analysis.owner_id == owner.id)
        .order_by(Analysis.started_at.desc())
        .all()
    )


def create_for_contract(
    db: Session, *, owner: User, payload: schemas.AnalysisCreate
) -> Optional[Analysis]:
    """계약 소유권 확인 후 분석 세션을 생성. 계약을 못 찾으면 None."""
    contract = (
        db.query(RealEstate)
        .filter(RealEstate.id == payload.contract_id, RealEstate.owner_id == owner.id)
        .first()
    )
    if contract is None:
        return None
    a = Analysis(
        owner_id=owner.id,
        contract_id=payload.contract_id,
        contract_addr=payload.contract_addr,
        status="pending",
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def update(db: Session, a: Analysis, payload: schemas.AnalysisUpdate) -> Analysis:
    if payload.status is not None:
        a.status = payload.status
        if payload.status == "completed" and a.completed_at is None:
            a.completed_at = datetime.now(timezone.utc)
    if payload.summary is not None:
        a.summary = payload.summary
    if payload.estimated_cost is not None:
        a.estimated_cost = payload.estimated_cost
    db.commit()
    db.refresh(a)
    return a


def delete(db: Session, a: Analysis) -> None:
    db.delete(a)
    db.commit()


# ── Photos ──────────────────────────────────────────────────────────────


def add_photo(
    db: Session, *, analysis_id: int, payload: schemas.AnalysisPhotoCreate
) -> AnalysisPhoto:
    p = AnalysisPhoto(
        analysis_id=analysis_id,
        s3_url=payload.s3_url,
        group_type=payload.group_type,
        order_index=payload.order_index,
        analyzed=False,
        file_hash=payload.file_hash,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return p


def list_photos(db: Session, analysis_id: int) -> List[AnalysisPhoto]:
    return (
        db.query(AnalysisPhoto)
        .filter(AnalysisPhoto.analysis_id == analysis_id)
        .order_by(AnalysisPhoto.order_index.asc())
        .all()
    )


def get_photo(
    db: Session, *, analysis_id: int, photo_id: int
) -> Optional[AnalysisPhoto]:
    return (
        db.query(AnalysisPhoto)
        .filter(
            AnalysisPhoto.id == photo_id,
            AnalysisPhoto.analysis_id == analysis_id,
        )
        .first()
    )


def update_photo(
    db: Session, p: AnalysisPhoto, payload: schemas.AnalysisPhotoUpdate
) -> AnalysisPhoto:
    if payload.analyzed is not None:
        p.analyzed = payload.analyzed
    if payload.ai_result is not None:
        p.ai_result = payload.ai_result
    if payload.s3_url is not None:
        p.s3_url = payload.s3_url
    # 구 RepairEstimate/DamageImage 흡수 필드
    if payload.file_hash is not None:
        p.file_hash = payload.file_hash
    if payload.damage_type is not None:
        p.damage_type = payload.damage_type
    if payload.part is not None:
        p.part = payload.part
    if payload.ai_confidence is not None:
        p.ai_confidence = payload.ai_confidence
    if payload.analysis_status is not None:
        p.analysis_status = payload.analysis_status
    if payload.celery_task_id is not None:
        p.celery_task_id = payload.celery_task_id
    if payload.total_repair_cost is not None:
        p.total_repair_cost = Decimal(str(payload.total_repair_cost))
    if payload.tenant_cost is not None:
        p.tenant_cost = Decimal(str(payload.tenant_cost))
    if payload.depreciation_rate is not None:
        p.depreciation_rate = payload.depreciation_rate
    if payload.useful_life_years is not None:
        p.useful_life_years = payload.useful_life_years
    if payload.elapsed_years is not None:
        p.elapsed_years = payload.elapsed_years
    db.commit()
    db.refresh(p)
    return p


# ── Messages ────────────────────────────────────────────────────────────


def add_message(
    db: Session, *, analysis_id: int, payload: schemas.AnalysisMessageCreate
) -> AnalysisMessage:
    m = AnalysisMessage(
        analysis_id=analysis_id,
        role=payload.role,
        content=payload.content,
        photo_id=payload.photo_id,
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    return m


def list_messages(db: Session, analysis_id: int) -> List[AnalysisMessage]:
    return (
        db.query(AnalysisMessage)
        .filter(AnalysisMessage.analysis_id == analysis_id)
        .order_by(AnalysisMessage.created_at.asc(), AnalysisMessage.id.asc())
        .all()
    )
