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


class DamageTypeEnum(str, enum.Enum):
    """손상 종류를 표현하는 열거형 (벽지, 바닥 등)."""

    wallpaper = "wallpaper"  # 벽지
    floor = "floor"  # 바닥(장판 등)
    other = "other"  # 기타 손상


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

    # 한 사용자는 여러 개의 임대차 계약을 가질 수 있다.
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
    damage_images = relationship("DamageImage", back_populates="real_estate")
    repair_estimates = relationship("RepairEstimate", back_populates="real_estate")


class DamageImage(Base):
    """손상 이미지를 저장하는 테이블 (S3 URL, 해시, AI 분석 결과 등)."""

    __tablename__ = "damage_images"

    id = Column(Integer, primary_key=True, index=True)
    real_estate_id = Column(Integer, ForeignKey("real_estates.id"), nullable=False, index=True)

    # S3에 저장된 실제 이미지 파일 URL
    s3_url = Column(String(512), nullable=False)

    # 손상 종류 (벽지, 바닥, 기타 등)
    damage_type = Column(Enum(DamageTypeEnum, name="damage_type_enum"), nullable=False)

    # AI 분석 결과(예: 손상 영역, 손상 정도 등)를 텍스트로 보관
    ai_result = Column(Text, nullable=True)

    # 파일 무결성 검증을 위한 SHA-256 해시값
    file_hash = Column(String(64), nullable=False, index=True)

    uploaded_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    real_estate = relationship("RealEstate", back_populates="damage_images")
    repair_estimates = relationship("RepairEstimate", back_populates="damage_image")


class RepairEstimate(Base):
    """국토부 가이드라인을 반영한 수리비 및 감가상각 산출 결과를 저장하는 테이블."""

    __tablename__ = "repair_estimates"

    id = Column(Integer, primary_key=True, index=True)

    real_estate_id = Column(Integer, ForeignKey("real_estates.id"), nullable=False, index=True)
    damage_image_id = Column(Integer, ForeignKey("damage_images.id"), nullable=True, index=True)

    # 총 수리비 (원 단위) — 부동소수점 오차 방지를 위해 NUMERIC 사용
    total_repair_cost = Column(Numeric(12, 0), nullable=False)

    # 내용연수(내구연수) - 기본 10년 (벽지/장판 기준), 상황에 따라 변경 가능
    useful_life_years = Column(Float, nullable=False, default=10.0)

    # 경과 연수 (년 단위, 소수점 허용)
    elapsed_years = Column(Float, nullable=False)

    # 임차인 부담 비용 (원 단위) — 부동소수점 오차 방지를 위해 NUMERIC 사용
    tenant_cost = Column(Numeric(12, 0), nullable=False)

    # 감가상각 비율(예: 0.3 이면 30%만 임차인 부담)
    depreciation_rate = Column(Float, nullable=False)

    # AI 비동기 분석 결과 (Celery 파이프라인에서 갱신)
    part = Column(String(255), nullable=True)
    damage_type = Column(String(128), nullable=True)
    estimated_cost = Column(Numeric(12, 0), nullable=True)  # 원 단위 추정 부담액
    ai_confidence = Column(Float, nullable=True)

    # 분석 대상 이미지 바이트 무결성(SHA-256 등), 중복·변조 검증용
    image_hash = Column(String(64), nullable=True, index=True)

    # 비동기 AI 분석 상태: pending / analyzing / completed / failed
    analysis_status = Column(String(32), nullable=False, default="pending")
    celery_task_id = Column(String(128), nullable=True, index=True)

    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    __table_args__ = (
        Index("ix_repair_estimates_real_estate_created", "real_estate_id", "created_at"),
    )

    real_estate = relationship("RealEstate", back_populates="repair_estimates")
    damage_image = relationship("DamageImage", back_populates="repair_estimates")


def apply_ai_analysis_result(
    db: Session,
    repair_estimate_id: int,
    *,
    part: Optional[str],
    damage_type: Optional[str],
    cost_total: float,
    estimated_cost: float,
    confidence: Optional[float],
    image_hash: Optional[str],
) -> Optional[RepairEstimate]:
    """Gemini 등 AI 분석이 끝난 뒤 repair_estimates 행을 갱신한다.

    - cost_total: AI가 산출한 총 수리비(Cost_total)
    - estimated_cost: worker에서 `utils.compute_moliti_depreciation_tenant_cost`로 산출한
      감가상각 반영 후 임차인 부담액(최종 추정)
    """
    from utils import calculate_depreciation_rate

    est = db.query(RepairEstimate).filter(RepairEstimate.id == repair_estimate_id).first()
    if est is None:
        return None

    cost_total = max(float(cost_total), 0.0)
    estimated_cost = max(float(estimated_cost), 0.0)
    est.part = part
    est.damage_type = damage_type
    est.total_repair_cost = cost_total
    est.estimated_cost = estimated_cost
    est.tenant_cost = estimated_cost
    est.ai_confidence = confidence
    est.image_hash = image_hash
    est.analysis_status = "completed"
    est.depreciation_rate = calculate_depreciation_rate(
        elapsed_years=est.elapsed_years,
        useful_life_years=est.useful_life_years,
    )
    return est


def mark_analysis_failed(db: Session, repair_estimate_id: int) -> None:
    """AI 분석 실패 시 상태만 failed로 둔다."""
    est = db.query(RepairEstimate).filter(RepairEstimate.id == repair_estimate_id).first()
    if est is not None:
        est.analysis_status = "failed"

