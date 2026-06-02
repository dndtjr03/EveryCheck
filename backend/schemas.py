"""FastAPI 요청/응답에 사용되는 Pydantic 스키마 정의."""

from datetime import date, datetime
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, EmailStr, field_validator


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

    @field_validator("password")
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("비밀번호는 8자 이상이어야 합니다.")
        if len(v) > 128:
            raise ValueError("비밀번호는 128자 이하여야 합니다.")
        if not any(c.isdigit() for c in v):
            raise ValueError("비밀번호에 숫자를 1개 이상 포함해야 합니다.")
        if not any(c.isalpha() for c in v):
            raise ValueError("비밀번호에 영문자를 1개 이상 포함해야 합니다.")
        return v


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
# Checklist (체크리스트)
# -----------------------------


class ChecklistCreate(BaseModel):
    """체크리스트 생성 요청 스키마."""

    title: str


class ChecklistRead(BaseModel):
    """API 응답용 체크리스트 스키마."""

    id: int
    user_id: int
    title: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# -----------------------------
# Photo (체크리스트·사용자 연동 사진)
# -----------------------------


class PhotoRead(BaseModel):
    """API 응답용 사진 메타데이터 스키마."""

    id: int
    user_id: int
    checklist_id: Optional[int] = None
    image_url: str
    original_name: str
    description: Optional[str] = None
    photo_type: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


_PRESIGNED_URL_EXAMPLE = (
    "https://your-bucket.s3.ap-northeast-2.amazonaws.com/checklist-photos/abc.jpg"
    "?AWSAccessKeyId=AKIA...&Signature=...&Expires=1710000000"
)


class PhotoDisplayItem(BaseModel):
    """Presigned URL 등 클라이언트 조회용 사진 응답."""

    photo_id: int
    display_url: str
    expires_in: int = 300
    original_name: str
    photo_type: str
    checklist_id: Optional[int] = None
    created_at: datetime

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "photo_id": 1,
                    "display_url": _PRESIGNED_URL_EXAMPLE,
                    "expires_in": 300,
                    "original_name": "room.jpg",
                    "photo_type": "INITIAL",
                    "checklist_id": 10,
                    "created_at": "2026-05-15T12:00:00Z",
                }
            ]
        }
    )


class PhotoDisplayListResponse(BaseModel):
    """소유자 인증 후 목록 조회 응답."""

    count: int
    photos: List[PhotoDisplayItem]


class PhotoUploadItem(BaseModel):
    """다중 업로드 응답용 개별 사진 요약 (Presigned 조회 URL 포함)."""

    photo_id: int
    display_url: str
    expires_in: int = 300

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "photo_id": 1,
                    "display_url": _PRESIGNED_URL_EXAMPLE,
                    "expires_in": 300,
                }
            ]
        }
    )


class PhotoUploadBatchResponse(BaseModel):
    """다중 사진 업로드 응답."""

    count: int
    photos: List[PhotoUploadItem]


class PhotoCompareResponse(BaseModel):
    """체크리스트별 INITIAL / DAMAGED 사진을 한 번에 내려줄 때 사용하는 스키마."""

    checklist_id: int
    initial: List[PhotoDisplayItem]
    damaged: List[PhotoDisplayItem]


# -----------------------------
# Analysis (분석 세션 — Flutter SQLite 이식)
# -----------------------------


AnalysisStatusLiteral = Literal["pending", "in_progress", "completed"]
PhotoGroupLiteral = Literal["move_in", "move_out"]
ChatRoleLiteral = Literal["user", "ai", "system"]
PhotoAnalysisStatusLiteral = Literal["pending", "analyzing", "completed", "failed"]


class AnalysisCreate(BaseModel):
    contract_id: int
    contract_addr: str


class AnalysisUpdate(BaseModel):
    status: Optional[AnalysisStatusLiteral] = None
    summary: Optional[str] = None
    estimated_cost: Optional[int] = None


class AnalysisRead(BaseModel):
    id: int
    owner_id: int
    contract_id: int
    contract_addr: str
    status: AnalysisStatusLiteral
    started_at: datetime
    completed_at: Optional[datetime] = None
    summary: Optional[str] = None
    estimated_cost: Optional[int] = None

    model_config = ConfigDict(from_attributes=True)


class AnalysisPhotoCreate(BaseModel):
    s3_url: str
    group_type: PhotoGroupLiteral
    order_index: int = 0
    file_hash: Optional[str] = None


class AnalysisPhotoUpdate(BaseModel):
    analyzed: Optional[bool] = None
    ai_result: Optional[str] = None
    s3_url: Optional[str] = None
    # 구 RepairEstimate 흡수 필드 — PATCH로 직접 갱신 가능
    file_hash: Optional[str] = None
    damage_type: Optional[str] = None
    part: Optional[str] = None
    ai_confidence: Optional[float] = None
    analysis_status: Optional[PhotoAnalysisStatusLiteral] = None
    celery_task_id: Optional[str] = None
    total_repair_cost: Optional[float] = None
    tenant_cost: Optional[float] = None
    depreciation_rate: Optional[float] = None
    useful_life_years: Optional[float] = None
    elapsed_years: Optional[float] = None


class AnalysisPhotoRead(BaseModel):
    id: int
    analysis_id: int
    s3_url: str
    group_type: PhotoGroupLiteral
    order_index: int
    analyzed: bool
    ai_result: Optional[str] = None
    created_at: datetime
    # 구 DamageImage/RepairEstimate에서 흡수한 필드
    file_hash: Optional[str] = None
    damage_type: Optional[str] = None
    part: Optional[str] = None
    ai_confidence: Optional[float] = None
    analysis_status: Optional[str] = None
    celery_task_id: Optional[str] = None
    total_repair_cost: Optional[float] = None
    tenant_cost: Optional[float] = None
    depreciation_rate: Optional[float] = None
    useful_life_years: Optional[float] = None
    elapsed_years: Optional[float] = None

    model_config = ConfigDict(from_attributes=True)


class AnalysisMessageCreate(BaseModel):
    role: ChatRoleLiteral
    content: str
    photo_id: Optional[int] = None


class AnalysisMessageRead(BaseModel):
    id: int
    analysis_id: int
    role: ChatRoleLiteral
    content: str
    photo_id: Optional[int] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

