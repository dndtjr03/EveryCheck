"""서비스 도메인에 대한 SQLAlchemy ORM 모델 정의."""

import enum
from datetime import datetime, date, timezone
from typing import Optional

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
)
from sqlalchemy.orm import Session, relationship

from database import Base


class PhotoTypeEnum(str, enum.Enum):
    """사진 구분: 입주·점검 시점(최초) vs 손상 후."""

    INITIAL = "INITIAL"
    DAMAGED = "DAMAGED"


class PhotoTypeEnum(str, enum.Enum):
    """사진 구분: 입주·점검 시점(최초) vs 손상 후."""

    INITIAL = "INITIAL"
    DAMAGED = "DAMAGED"


class User(Base):
    """서비스 사용자 정보를 저장하는 테이블."""

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(255), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    real_estates = relationship("RealEstate", back_populates="owner")
    checklists = relationship("Checklist", back_populates="user")
    photos = relationship("Photo", back_populates="owner")


class Checklist(Base):
    """사용자별 체크리스트(퇴거 점검 등)를 저장하는 테이블."""

    __tablename__ = "checklists"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(255), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    user = relationship("User", back_populates="checklists")
    photos = relationship("Photo", back_populates="checklist")


class Photo(Base):
    """체크리스트·사용자에 연결된 사진 메타데이터(S3 URL 등)를 저장하는 테이블."""

    __tablename__ = "photos"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    checklist_id = Column(
        Integer,
        ForeignKey("checklists.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )

    image_url = Column(String(1024), nullable=False)
    original_name = Column(String(255), nullable=False)
    description = Column(String(1024), nullable=True)
    photo_type = Column(
        Enum(PhotoTypeEnum, native_enum=False, length=16),
        nullable=False,
        default=PhotoTypeEnum.INITIAL,
    )
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    __table_args__ = (Index("ix_photos_checklist_photo_type", "checklist_id", "photo_type"),)

    owner = relationship("User", back_populates="photos")
    checklist = relationship("Checklist", back_populates="photos")


class RealEstate(Base):
    """임대차 계약 정보(주소, 입주/퇴거일 등)를 저장하는 테이블."""

    __tablename__ = "real_estates"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)

    address = Column(String(255), nullable=False)
    contract_start_date = Column(Date, nullable=False)
    contract_end_date = Column(Date, nullable=True)
    memo = Column(Text, nullable=True)

    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    owner = relationship("User", back_populates="real_estates")
    analyses = relationship(
        "Analysis", back_populates="contract", cascade="all, delete-orphan"
    )


class Analysis(Base):
    """분석 세션(한 계약에 대한 손상 분석 묶음). Flutter SQLite의 `analyses` 이식."""

    __tablename__ = "analyses"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    contract_id = Column(
        Integer,
        ForeignKey("real_estates.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    contract_addr = Column(String(255), nullable=False)
    status = Column(String(32), nullable=False, default="pending")  # pending/in_progress/completed
    started_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)
    completed_at = Column(DateTime, nullable=True)
    summary = Column(Text, nullable=True)
    estimated_cost = Column(Integer, nullable=True)

    contract = relationship("RealEstate", back_populates="analyses")
    photos = relationship(
        "AnalysisPhoto", back_populates="analysis", cascade="all, delete-orphan"
    )
    messages = relationship(
        "AnalysisMessage", back_populates="analysis", cascade="all, delete-orphan"
    )


class AnalysisPhoto(Base):
    """분석 세션에 속한 손상 사진. Flutter `damage_photos` 이식 — S3 URL이 진실 소스.

    구 `DamageImage` + `RepairEstimate`의 유용한 필드(SHA-256 해시, AI 분석 상태,
    Celery 태스크 ID, 감가상각 결과 등)를 흡수하여 한 행으로 통합한다.
    """

    __tablename__ = "analysis_photos"

    id = Column(Integer, primary_key=True, index=True)
    analysis_id = Column(
        Integer,
        ForeignKey("analyses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    s3_url = Column(String(1024), nullable=False)
    group_type = Column(String(16), nullable=False)  # move_in / move_out
    order_index = Column(Integer, nullable=False, default=0)
    analyzed = Column(Boolean, nullable=False, default=False)
    ai_result = Column(Text, nullable=True)  # JSON 문자열
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    # ── 구 DamageImage / RepairEstimate에서 흡수한 필드 ──
    # SHA-256 무결성 해시 (구 DamageImage.file_hash)
    file_hash = Column(String(64), nullable=True, index=True)
    # 손상 종류 자유 문자열 (구 DamageImage.damage_type — enum → string 단순화)
    damage_type = Column(String(64), nullable=True)
    # 손상 부위 (구 RepairEstimate.part)
    part = Column(String(255), nullable=True)
    # AI 분석 신뢰도 (구 RepairEstimate.ai_confidence)
    ai_confidence = Column(Float, nullable=True)
    # 비동기 분석 상태 pending / analyzing / completed / failed
    analysis_status = Column(String(32), nullable=False, default="pending")
    # Celery 태스크 ID (구 RepairEstimate.celery_task_id)
    celery_task_id = Column(String(128), nullable=True, index=True)

    # 감가상각 계산 결과 (구 RepairEstimate 필드 흡수)
    total_repair_cost = Column(Numeric(12, 0), nullable=True)
    tenant_cost = Column(Numeric(12, 0), nullable=True)
    depreciation_rate = Column(Float, nullable=True)
    useful_life_years = Column(Float, nullable=True)
    elapsed_years = Column(Float, nullable=True)

    analysis = relationship("Analysis", back_populates="photos")


class AnalysisMessage(Base):
    """분석 세션 채팅 메시지. Flutter `messages` 이식."""

    __tablename__ = "analysis_messages"

    id = Column(Integer, primary_key=True, index=True)
    analysis_id = Column(
        Integer,
        ForeignKey("analyses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role = Column(String(16), nullable=False)  # user / ai / system
    content = Column(Text, nullable=False)
    photo_id = Column(
        Integer,
        ForeignKey("analysis_photos.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    analysis = relationship("Analysis", back_populates="messages")


def apply_ai_analysis_result(
    db: Session,
    analysis_photo_id: int,
    *,
    part: Optional[str],
    damage_type: Optional[str],
    cost_total: float,
    estimated_cost: float,
    confidence: Optional[float],
    image_hash: Optional[str],
) -> Optional[AnalysisPhoto]:
    """Gemini 등 AI 분석이 끝난 뒤 analysis_photos 행을 갱신한다.

    - cost_total: AI가 산출한 총 수리비(Cost_total)
    - estimated_cost: worker에서 `utils.compute_moliti_depreciation_tenant_cost`로 산출한
      감가상각 반영 후 임차인 부담액(최종 추정)
    """
    from utils import calculate_depreciation_rate

    photo = (
        db.query(AnalysisPhoto).filter(AnalysisPhoto.id == analysis_photo_id).first()
    )
    if photo is None:
        return None

    cost_total = max(float(cost_total), 0.0)
    estimated_cost = max(float(estimated_cost), 0.0)
    photo.part = part
    photo.damage_type = damage_type
    photo.total_repair_cost = cost_total
    photo.tenant_cost = estimated_cost
    photo.ai_confidence = confidence
    if image_hash is not None:
        photo.file_hash = image_hash
    photo.analysis_status = "completed"
    photo.analyzed = True
    if photo.elapsed_years is not None and photo.useful_life_years is not None:
        photo.depreciation_rate = calculate_depreciation_rate(
            elapsed_years=photo.elapsed_years,
            useful_life_years=photo.useful_life_years,
        )
    return photo


def mark_analysis_failed(db: Session, analysis_photo_id: int) -> None:
    """AI 분석 실패 시 상태만 failed로 둔다."""
    photo = (
        db.query(AnalysisPhoto).filter(AnalysisPhoto.id == analysis_photo_id).first()
    )
    if photo is not None:
        photo.analysis_status = "failed"
