"""퇴거의 정석 - FastAPI 메인 애플리케이션.

- JWT 기반 인증/인가
- 임대차 계약(RealEstate) CRUD 골격
- 손상 이미지(DamageImage) 업로드 (S3 + SHA-256 해시 저장)
- 수리비/감가상각(RepairEstimate) 계산 및 저장
"""

import os
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import (
    Body,
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    UploadFile,
    status,
)
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

import models
import schemas
from database import Base, engine, get_db
from models import DamageTypeEnum, DamageImage, RealEstate, RepairEstimate, User
from utils import (
    calculate_depreciation_rate,
    calculate_tenant_cost,
    calculate_file_sha256,
    upload_image_to_s3,
)


# -----------------------------
# 애플리케이션 및 보안 설정
# -----------------------------

app = FastAPI(
    title="퇴거의 정석 API",
    description="임대차 원상복구 비용 분석 서비스 백엔드 예시 구현",
    version="0.1.0",
)

# DB 테이블 생성 (간단한 예제에서는 앱 시작 시 자동 생성)
Base.metadata.create_all(bind=engine)


# JWT 관련 설정 (환경 변수에서 가져오되 기본값 제공)
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "change-me-in-production")
ALGORITHM = os.getenv("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "60"))

# 비밀번호 해싱 설정 (bcrypt)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# OAuth2 비밀번호 그랜트용 토큰 엔드포인트 경로 정의
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")


# -----------------------------
# 보안/인증 유틸 함수
# -----------------------------


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """사용자가 입력한 비밀번호와 저장된 해시값이 일치하는지 검증한다."""

    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """비밀번호를 안전한 해시값으로 변환한다."""

    return pwd_context.hash(password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """JWT 액세스 토큰을 생성한다."""

    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def get_user_by_email(db: Session, email: str) -> Optional[User]:
    """이메일을 기준으로 사용자를 조회한다."""

    return db.query(User).filter(User.email == email).first()


def authenticate_user(db: Session, email: str, password: str) -> Optional[User]:
    """이메일/비밀번호를 이용해 사용자를 인증한다."""

    user = get_user_by_email(db, email=email)
    if not user:
        return None
    if not verify_password(password, user.hashed_password):
        return None
    return user


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """JWT 토큰에서 사용자 정보를 추출해 현재 사용자 객체를 반환한다."""

    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="자격 증명 검증에 실패했습니다.",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        sub: str = payload.get("sub")
        if sub is None:
            raise credentials_exception
        token_data = schemas.TokenData(sub=sub)
    except JWTError:
        raise credentials_exception

    user = get_user_by_email(db, email=token_data.sub) if token_data.sub else None
    if user is None:
        raise credentials_exception
    return user


async def get_current_active_user(current_user: User = Depends(get_current_user)) -> User:
    """비활성화된 사용자를 차단하기 위한 헬퍼."""

    if not current_user.is_active:
        raise HTTPException(status_code=400, detail="비활성화된 사용자입니다.")
    return current_user


# -----------------------------
# 인증/회원 관련 엔드포인트
# -----------------------------


@app.post("/auth/register", response_model=schemas.UserRead, summary="회원 가입")
def register_user(user_in: schemas.UserCreate, db: Session = Depends(get_db)) -> User:
    """간단한 회원 가입 엔드포인트.

    - 이메일 중복 여부를 체크한다.
    - 비밀번호는 bcrypt로 해시 후 저장한다.
    """

    existing = get_user_by_email(db, email=user_in.email)
    if existing:
        raise HTTPException(status_code=400, detail="이미 가입된 이메일입니다.")

    hashed_password = get_password_hash(user_in.password)
    user = User(
        email=user_in.email,
        full_name=user_in.full_name,
        hashed_password=hashed_password,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@app.post("/auth/token", response_model=schemas.Token, summary="액세스 토큰 발급")
def login_for_access_token(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
) -> schemas.Token:
    """OAuth2 비밀번호 그랜트 방식으로 액세스 토큰을 발급한다."""

    user = authenticate_user(db, email=form_data.username, password=form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="이메일 또는 비밀번호가 올바르지 않습니다.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = create_access_token(data={"sub": user.email})
    return schemas.Token(access_token=access_token, token_type="bearer")


@app.get("/users/me", response_model=schemas.UserRead, summary="내 정보 조회")
async def read_users_me(current_user: User = Depends(get_current_active_user)) -> User:
    """현재 인증된 사용자의 정보를 반환한다."""

    return current_user


# -----------------------------
# 임대차 계약(RealEstate) 관련 엔드포인트
# -----------------------------


@app.post(
    "/real-estates",
    response_model=schemas.RealEstateRead,
    summary="임대차 계약 등록",
)
def create_real_estate(
    real_estate_in: schemas.RealEstateCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> RealEstate:
    """현재 로그인한 사용자의 임대차 계약 정보를 등록한다."""

    real_estate = RealEstate(
        owner_id=current_user.id,
        address=real_estate_in.address,
        contract_start_date=real_estate_in.contract_start_date,
        contract_end_date=real_estate_in.contract_end_date,
        memo=real_estate_in.memo,
    )
    db.add(real_estate)
    db.commit()
    db.refresh(real_estate)
    return real_estate


@app.get(
    "/real-estates",
    response_model=List[schemas.RealEstateRead],
    summary="내 임대차 계약 목록",
)
def list_real_estates(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> List[RealEstate]:
    """현재 로그인한 사용자의 임대차 계약 목록을 조회한다."""

    q = (
        db.query(RealEstate)
        .filter(RealEstate.owner_id == current_user.id)
        .order_by(RealEstate.created_at.desc())
    )
    return q.all()


@app.get(
    "/real-estates/{real_estate_id}",
    response_model=schemas.RealEstateDetail,
    summary="임대차 계약 상세 (이미지/견적 포함)",
)
def get_real_estate_detail(
    real_estate_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> schemas.RealEstateDetail:
    """임대차 계약 정보와 관련 이미지/견적을 함께 조회한다."""

    real_estate = (
        db.query(RealEstate)
        .filter(
            RealEstate.id == real_estate_id,
            RealEstate.owner_id == current_user.id,
        )
        .first()
    )
    if not real_estate:
        raise HTTPException(status_code=404, detail="임대차 계약을 찾을 수 없습니다.")

    # Pydantic 스키마로 변환 (관계 포함)
    return schemas.RealEstateDetail(
        id=real_estate.id,
        owner_id=real_estate.owner_id,
        address=real_estate.address,
        contract_start_date=real_estate.contract_start_date,
        contract_end_date=real_estate.contract_end_date,
        memo=real_estate.memo,
        created_at=real_estate.created_at,
        damage_images=real_estate.damage_images,
        repair_estimates=real_estate.repair_estimates,
    )


# -----------------------------
# 손상 이미지(DamageImage) 업로드 엔드포인트
# -----------------------------


@app.post(
    "/real-estates/{real_estate_id}/images",
    response_model=schemas.DamageImageRead,
    summary="손상 이미지 업로드",
)
async def upload_damage_image(
    real_estate_id: int,
    file: UploadFile = File(..., description="손상 이미지 파일"),
    damage_type: DamageTypeEnum = Form(..., description="손상 종류 (wallpaper/floor/other)"),
    ai_result: Optional[str] = Form(
        None,
        description="AI 분석 결과 (선택, 추후 AI 파이프라인과 연동 가능)",
    ),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> DamageImage:
    """손상 이미지를 업로드하고 S3 URL, SHA-256 해시, AI 결과를 DB에 저장한다."""

    # 요청한 임대차 계약이 현재 사용자 소유인지 검증
    real_estate = (
        db.query(RealEstate)
        .filter(
            RealEstate.id == real_estate_id,
            RealEstate.owner_id == current_user.id,
        )
        .first()
    )
    if not real_estate:
        raise HTTPException(status_code=404, detail="임대차 계약을 찾을 수 없습니다.")

    # 1) 파일 SHA-256 해시값 계산 (무결성 검증용)
    file_hash = await calculate_file_sha256(file)

    # 2) S3 업로드
    bucket_name = os.getenv("S3_BUCKET_NAME", "")
    try:
        s3_url = await upload_image_to_s3(file, bucket_name=bucket_name)
    except ValueError as e:
        # 설정 오류 등으로 인한 예외는 서버 오류로 응답
        raise HTTPException(status_code=500, detail=str(e))

    # 3) DB에 메타데이터 저장
    damage_image = DamageImage(
        real_estate_id=real_estate.id,
        s3_url=s3_url,
        damage_type=damage_type,
        ai_result=ai_result,
        file_hash=file_hash,
    )

    db.add(damage_image)
    db.commit()
    db.refresh(damage_image)

    return damage_image


# -----------------------------
# 수리비/감가상각(RepairEstimate) 엔드포인트
# -----------------------------


@app.post(
    "/real-estates/{real_estate_id}/repair-estimates",
    response_model=schemas.RepairEstimateRead,
    summary="수리비 및 감가상각 계산/저장",
)
def create_repair_estimate(
    real_estate_id: int,
    estimate_in: schemas.RepairEstimateCreate,
    damage_image_id: Optional[int] = Body(
        None,
        description="관련 손상 이미지 ID (선택)",
    ),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> RepairEstimate:
    """국토부 가이드라인(벽지/장판 내구연수 10년 기준)에 따라 임차인 부담 비용을 계산하고 결과를 저장한다."""

    real_estate = (
        db.query(RealEstate)
        .filter(
            RealEstate.id == real_estate_id,
            RealEstate.owner_id == current_user.id,
        )
        .first()
    )
    if not real_estate:
        raise HTTPException(status_code=404, detail="임대차 계약을 찾을 수 없습니다.")

    # 선택적으로 damage_image_id가 주어진 경우, 해당 이미지가 이 임대차 계약에 속하는지 검증
    damage_image: Optional[DamageImage] = None
    if damage_image_id is not None:
        damage_image = (
            db.query(DamageImage)
            .filter(
                DamageImage.id == damage_image_id,
                DamageImage.real_estate_id == real_estate.id,
            )
            .first()
        )
        if not damage_image:
            raise HTTPException(status_code=400, detail="해당 임대차 계약에 속하지 않는 이미지입니다.")

    # 감가상각 비율 및 임차인 부담 비용 계산
    depreciation_rate = calculate_depreciation_rate(
        elapsed_years=estimate_in.elapsed_years,
        useful_life_years=estimate_in.useful_life_years,
    )
    tenant_cost = calculate_tenant_cost(
        total_repair_cost=estimate_in.total_repair_cost,
        elapsed_years=estimate_in.elapsed_years,
        useful_life_years=estimate_in.useful_life_years,
    )

    estimate = RepairEstimate(
        real_estate_id=real_estate.id,
        damage_image_id=damage_image.id if damage_image else None,
        total_repair_cost=estimate_in.total_repair_cost,
        useful_life_years=estimate_in.useful_life_years,
        elapsed_years=estimate_in.elapsed_years,
        tenant_cost=tenant_cost,
        depreciation_rate=depreciation_rate,
    )

    db.add(estimate)
    db.commit()
    db.refresh(estimate)

    return estimate


@app.get(
    "/health",
    summary="헬스체크",
)
def health_check() -> dict:
    """간단한 헬스체크 엔드포인트."""

    return {"status": "ok"}

