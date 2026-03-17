"""서비스 도메인에 대한 SQLAlchemy ORM 모델 정의."""

import enum
from datetime import datetime, date

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import relationship

from database import Base


class DamageTypeEnum(str, enum.Enum):
    """손상 종류를 표현하는 열거형 (벽지, 바닥 등)."""

    wallpaper = "wallpaper"  # 벽지
    floor = "floor"  # 바닥(장판 등)
    other = "other"  # 기타 손상


class User(Base):
    """서비스 사용자 정보를 저장하는 테이블."""

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(255), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # 한 사용자는 여러 개의 임대차 계약을 가질 수 있다.
    real_estates = relationship("RealEstate", back_populates="owner")


class RealEstate(Base):
    """임대차 계약 정보(주소, 입주/퇴거일 등)를 저장하는 테이블."""

    __tablename__ = "real_estates"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)

    address = Column(String(255), nullable=False)
    contract_start_date = Column(Date, nullable=False)
    contract_end_date = Column(Date, nullable=True)
    memo = Column(Text, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

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

    uploaded_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    real_estate = relationship("RealEstate", back_populates="damage_images")
    repair_estimates = relationship("RepairEstimate", back_populates="damage_image")


class RepairEstimate(Base):
    """국토부 가이드라인을 반영한 수리비 및 감가상각 산출 결과를 저장하는 테이블."""

    __tablename__ = "repair_estimates"

    id = Column(Integer, primary_key=True, index=True)

    real_estate_id = Column(Integer, ForeignKey("real_estates.id"), nullable=False, index=True)
    damage_image_id = Column(Integer, ForeignKey("damage_images.id"), nullable=True, index=True)

    # 총 수리비 (원 단위)
    total_repair_cost = Column(Float, nullable=False)

    # 내용연수(내구연수) - 기본 10년 (벽지/장판 기준), 상황에 따라 변경 가능
    useful_life_years = Column(Float, nullable=False, default=10.0)

    # 경과 연수 (년 단위, 소수점 허용)
    elapsed_years = Column(Float, nullable=False)

    # 임차인 부담 비용 (공식에 따라 계산된 결과)
    tenant_cost = Column(Float, nullable=False)

    # 감가상각 비율(예: 0.3 이면 30%만 임차인 부담)
    depreciation_rate = Column(Float, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    real_estate = relationship("RealEstate", back_populates="repair_estimates")
    damage_image = relationship("DamageImage", back_populates="repair_estimates")

