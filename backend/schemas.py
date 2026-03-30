"""FastAPI 요청/응답에 사용되는 Pydantic 스키마 정의."""

from datetime import date, datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, EmailStr

from models import DamageTypeEnum


# -----------------------------
# 공통 스키마
# -----------------------------


class UserBase(BaseModel):
    """사용자 공통 필드 스키마."""

    email: EmailStr
    full_name: Optional[str] = None


class UserCreate(UserBase):
    """회원 가입 시 사용하는 스키마."""

    password: str


class UserRead(UserBase):
    """API 응답용 사용자 정보 스키마."""

    id: int
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class Token(BaseModel):
    """JWT 액세스 토큰 응답 스키마."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    """JWT 페이로드에서 추출한 정보 스키마."""

    sub: Optional[str] = None


# -----------------------------
# RealEstate (임대차 계약)
# -----------------------------


class RealEstateBase(BaseModel):
    """임대차 계약 공통 필드 스키마."""

    address: str
    contract_start_date: date
    contract_end_date: Optional[date] = None
    memo: Optional[str] = None


class RealEstateCreate(RealEstateBase):
    """임대차 계약 생성 시 사용하는 스키마."""

    pass


class RealEstateRead(RealEstateBase):
    """API 응답용 임대차 계약 스키마."""

    id: int
    owner_id: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# -----------------------------
# DamageImage (손상 이미지)
# -----------------------------


class DamageImageBase(BaseModel):
    """손상 이미지 공통 필드 스키마."""

    s3_url: str
    damage_type: DamageTypeEnum
    ai_result: Optional[str] = None
    file_hash: str


class DamageImageRead(DamageImageBase):
    """API 응답용 손상 이미지 스키마."""

    id: int
    real_estate_id: int
    uploaded_at: datetime

    model_config = ConfigDict(from_attributes=True)


# -----------------------------
# RepairEstimate (수리비/감가상각)
# -----------------------------


class RepairEstimateBase(BaseModel):
    """수리비/감가상각 결과 공통 필드 스키마."""

    total_repair_cost: float
    useful_life_years: float
    elapsed_years: float
    tenant_cost: float
    depreciation_rate: float


class RepairEstimateCreate(BaseModel):
    """수리비 및 경과 연수 정보를 입력받는 스키마."""

    total_repair_cost: float
    elapsed_years: float
    useful_life_years: float = 10.0  # 기본값: 10년 (벽지/장판 내구연수)


class RepairEstimateRead(RepairEstimateBase):
    """API 응답용 수리비/감가상각 결과 스키마."""

    id: int
    real_estate_id: int
    damage_image_id: Optional[int] = None
    part: Optional[str] = None
    damage_type: Optional[str] = None
    estimated_cost: Optional[float] = None
    ai_confidence: Optional[float] = None
    image_hash: Optional[str] = None
    analysis_status: Optional[str] = None
    celery_task_id: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AnalyzeJobResponse(BaseModel):
    """비동기 AI 분석 요청 접수 응답."""

    status: Literal["analyzing"] = "analyzing"
    task_id: str
    repair_estimate_id: int


# -----------------------------
# 복합 응답 예시 (선택적 확장용)
# -----------------------------


class RealEstateDetail(RealEstateRead):
    """임대차 계약과 관련된 이미지/견적을 함께 내려줄 때 사용할 수 있는 상세 스키마."""

    damage_images: List[DamageImageRead] = []
    repair_estimates: List[RepairEstimateRead] = []

