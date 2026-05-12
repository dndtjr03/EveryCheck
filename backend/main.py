"""퇴거의 정석 - FastAPI 메인 애플리케이션.

- JWT 기반 인증/인가
- 임대차 계약(RealEstate) CRUD 골격
- 손상 이미지(DamageImage) 업로드 (S3 + SHA-256 해시 저장)
- 수리비/감가상각(RepairEstimate) 계산 및 저장
"""

import os
from pathlib import Path
from typing import List, Optional

from fastapi import (
    Body,
    Depends,
    FastAPI,
    File,
    Form,
    HTTPException,
    Request,
    Response,
    UploadFile,
    status,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import (
    get_swagger_ui_html,
    get_swagger_ui_oauth2_redirect_html,
)
from fastapi.security import OAuth2PasswordRequestForm
from fastapi.staticfiles import StaticFiles
from jose import JWTError, jwt
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address
from sqlalchemy import text
from sqlalchemy.orm import Session

import models
import schemas
from auth import (
    ALGORITHM,
    SECRET_KEY,
    authenticate_user,
    create_access_token,
    create_refresh_token,
    get_current_active_user,
    get_password_hash,
    get_user_by_email,
)
from database import Base, engine, get_db
from security_audit import init_security_audit_logger, log_sensitive_endpoint_access
from models import DamageTypeEnum, DamageImage, RealEstate, RepairEstimate, User
from utils import (
    calculate_depreciation_rate,
    calculate_tenant_cost,
    compute_image_hash_sha256,
    upload_image_to_s3,
    validate_and_read_image_file,
)


# -----------------------------
# 애플리케이션 및 보안 설정
# -----------------------------

app = FastAPI(
    title="퇴거의 정석 API",
    description="임대차 원상복구 비용 분석 서비스 백엔드 예시 구현",
    version="0.1.0",
    openapi_url="/openapi.json",
    docs_url=None,
    redoc_url=None,
)

_STATIC_ROOT = Path(__file__).resolve().parent / "static"
app.mount(
    "/static",
    StaticFiles(directory=str(_STATIC_ROOT)),
    name="static",
)


@app.get("/docs", include_in_schema=False)
async def swagger_ui_html():
    """Swagger UI — JS/CSS는 로컬 /static 만 사용 (CDN 없음)."""
    return get_swagger_ui_html(
        openapi_url="/openapi.json",
        title=f"{app.title} - Swagger UI",
        swagger_js_url="/static/swagger-ui/swagger-ui-bundle.js",
        swagger_css_url="/static/swagger-ui/swagger-ui.css",
        swagger_favicon_url="/static/swagger-ui/favicon-32x32.png",
        oauth2_redirect_url="/docs/oauth2-redirect",
    )


@app.get("/docs/oauth2-redirect", include_in_schema=False)
async def swagger_ui_oauth2_redirect():
    """Swagger UI 'Authorize' OAuth2 리다이렉트용."""
    return get_swagger_ui_oauth2_redirect_html()

# CORS (프론트 Origin은 환경 변수로만 지정 — 운영에서는 와일드카드 * 지양)
_raw_cors = os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000")
if _raw_cors.strip() == "*":
    allow_origins = ["*"]
else:
    allow_origins = [o.strip() for o in _raw_cors.split(",") if o.strip()]
    if not allow_origins:
        allow_origins = ["http://localhost:3000"]

cors_allow_credentials = os.getenv("CORS_ALLOW_CREDENTIALS", "true").lower() in (
    "1",
    "true",
    "yes",
)
if allow_origins == ["*"]:
    cors_allow_credentials = False

app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=cors_allow_credentials,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Requested-With"],
    expose_headers=["Retry-After"],
)


@app.middleware("http")
async def sensitive_endpoint_audit_middleware(request: Request, call_next):
    """로그인(/auth/token)·AI 분석(/analyze) POST 접근을 IP 기준으로 파일 감사 로그에 남긴다."""
    path = request.url.path
    if request.method == "POST" and path in ("/auth/token", "/analyze"):
        try:
            log_sensitive_endpoint_access(request, path=path)
        except OSError:
            pass
    return await call_next(request)


@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    """XSS·클릭재킹 등 기본 보안 응답 헤더.

    /docs* (Swagger UI)만 아래 고정 CSP를 `Content-Security-Policy`에 설정한다.
    """
    response = await call_next(request)
    path = request.url.path
    is_docs = path == "/docs" or path.startswith("/docs/")

    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    if not is_docs:
        response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("X-XSS-Protection", "1; mode=block")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault(
        "Permissions-Policy",
        "geolocation=(), microphone=(), camera=(), payment=()",
    )
    if is_docs:
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline'; "
            "style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:;"
        )
    else:
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'none'; frame-ancestors 'none'",
        )
    if os.getenv("ENABLE_HSTS", "").strip() in ("1", "true", "yes"):
        response.headers.setdefault(
            "Strict-Transport-Security",
            "max-age=31536000; includeSubDomains",
        )
    return response


# Rate Limiting: 기본 분당 20회 — 로그인·AI 분석은 별도로 더 엄격
limiter = Limiter(key_func=get_remote_address, default_limits=["20/minute"])
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)
from slowapi import _rate_limit_exceeded_handler  # noqa: E402

app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# 스키마 관리는 Alembic 마이그레이션으로 일원화한다.
# (이전: Base.metadata.create_all(bind=engine) — Alembic과 혼용 시 이력 추적 실패)
# 배포 시: alembic upgrade head 를 컨테이너 진입점/CI에서 실행할 것.


@app.on_event("startup")
def _startup_init_audit_log() -> None:
    init_security_audit_logger()


def _check_database() -> tuple[bool, Optional[str]]:
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True, None
    except Exception as exc:
        return False, str(exc)


def _check_redis() -> tuple[bool, Optional[str]]:
    try:
        import redis

        url = os.getenv("REDIS_URL") or os.getenv(
            "CELERY_BROKER_URL", "redis://localhost:6379/0"
        )
        r = redis.from_url(url, socket_connect_timeout=3)
        r.ping()
        return True, None
    except Exception as exc:
        return False, str(exc)


def _check_celery_workers() -> tuple[bool, Optional[str], Optional[dict]]:
    try:
        from celery_app import celery_app

        insp = celery_app.control.inspect(timeout=3.0)
        if insp is None:
            return False, "inspect unavailable", None
        ping = insp.ping()
        if not ping:
            return False, "no worker responded to ping", None
        return True, None, ping
    except Exception as exc:
        return False, str(exc), None


# -----------------------------
# 인증/회원 관련 엔드포인트
# -----------------------------


@app.post(
    "/auth/register",
    response_model=schemas.UserRead,
    summary="회원 가입",
    description="신규 사용자를 등록합니다. 이메일 중복을 검사하고 비밀번호는 bcrypt로 해시하여 저장합니다.",
)
def register_user(
    request: Request,
    user_in: schemas.UserCreate,
    db: Session = Depends(get_db),
) -> User:
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


@app.post(
    "/auth/token",
    response_model=schemas.Token,
    summary="액세스 토큰 발급",
    description="이메일/비밀번호로 로그인하여 JWT 액세스 토큰을 발급합니다. (OAuth2 Password Grant)",
)
@limiter.limit("5/minute")
def login_for_access_token(
    request: Request,
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
    refresh_token = create_refresh_token(data={"sub": user.email})
    return schemas.Token(access_token=access_token, refresh_token=refresh_token, token_type="bearer")


@app.post(
    "/auth/refresh",
    response_model=schemas.Token,
    summary="리프레시 토큰으로 재발급",
    description="리프레시 토큰을 검증한 뒤 새로운 액세스 토큰(및 리프레시 토큰)을 발급합니다. 운영 환경에서는 토큰 회전/폐기 전략을 추가하세요.",
)
def refresh_access_token(
    request: Request,
    refresh_token: str = Body(..., embed=True, description="리프레시 토큰 문자열"),
    db: Session = Depends(get_db),
) -> schemas.Token:
    """리프레시 토큰을 이용해 액세스 토큰을 재발급한다."""

    try:
        payload = jwt.decode(refresh_token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="리프레시 토큰이 아닙니다.")
        sub: str = payload.get("sub")
        if not sub:
            raise HTTPException(status_code=401, detail="리프레시 토큰이 올바르지 않습니다.")
    except JWTError:
        raise HTTPException(status_code=401, detail="리프레시 토큰 검증에 실패했습니다.")

    # 사용자 존재 여부 확인 (계정이 삭제/비활성화된 경우 토큰 재발급 차단 목적)
    user = get_user_by_email(db, email=sub)
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="사용자를 찾을 수 없거나 비활성화되었습니다.")

    new_access = create_access_token(data={"sub": user.email})
    new_refresh = create_refresh_token(data={"sub": user.email})
    return schemas.Token(access_token=new_access, refresh_token=new_refresh, token_type="bearer")


@app.get(
    "/users/me",
    response_model=schemas.UserRead,
    summary="내 정보 조회",
    description="현재 인증된 사용자 정보를 반환합니다. Authorization 헤더에 Bearer 토큰이 필요합니다.",
)
async def read_users_me(
    request: Request,
    current_user: User = Depends(get_current_active_user),
) -> User:
    """현재 인증된 사용자의 정보를 반환한다."""

    return current_user


# -----------------------------
# 임대차 계약(RealEstate) 관련 엔드포인트
# -----------------------------


@app.post(
    "/real-estates",
    response_model=schemas.RealEstateRead,
    summary="임대차 계약 등록",
    description="현재 로그인한 사용자의 임대차 계약(주소, 입주/퇴거일, 메모)을 등록합니다.",
)
def create_real_estate(
    request: Request,
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
    description="현재 로그인한 사용자가 등록한 임대차 계약 목록을 최신순으로 조회합니다.",
)
def list_real_estates(
    request: Request,
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
    description="임대차 계약 1건의 상세 정보와, 연관된 손상 이미지/수리비 산출 결과 목록을 함께 반환합니다.",
)
def get_real_estate_detail(
    request: Request,
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
    description="손상 이미지를 업로드합니다. 10MB 제한 및 확장자/실제 MIME 검증을 수행하고, SHA-256 해시를 저장한 뒤 S3에 업로드합니다.",
)
async def upload_damage_image(
    request: Request,
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

    # 1) 업로드 파일 보안 검증(확장자/MIME/용량) 및 바이트 읽기
    try:
        file_bytes, detected_mime = await validate_and_read_image_file(file)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # 2) 무결성용 SHA-256(image_hash) — S3 업로드 전에 바이트 기준으로 먼저 계산
    file_hash = compute_image_hash_sha256(file_bytes)

    # 3) S3 업로드
    bucket_name = os.getenv("S3_BUCKET_NAME", "")
    try:
        s3_url = await upload_image_to_s3(
            file,
            bucket_name=bucket_name,
            body=file_bytes,
            content_type=detected_mime,
        )
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
# AI 비동기 분석 (/analyze)
# -----------------------------


@app.post(
    "/analyze",
    response_model=schemas.AnalyzeJobResponse,
    summary="손상 이미지 AI 비동기 분석",
    description=(
        "손상 이미지를 업로드하면 즉시 분석 작업을 큐에 넣고 task_id와 repair_estimate_id를 반환합니다. "
        "실제 Gemini 분석은 Celery 워커에서 수행되며, 완료 시 repair_estimates 행이 갱신됩니다."
    ),
)
@limiter.limit("5/minute")
async def analyze_damage_image(
    request: Request,
    real_estate_id: int = Form(..., description="임대차 계약 ID"),
    file: UploadFile = File(..., description="손상 이미지 파일"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> schemas.AnalyzeJobResponse:
    """이미지를 S3에 저장하고 RepairEstimate(분석 중)를 만든 뒤 백그라운드 분석 태스크를 실행한다."""

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

    try:
        file_bytes, detected_mime = await validate_and_read_image_file(file)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    image_hash = compute_image_hash_sha256(file_bytes)

    bucket_name = os.getenv("S3_BUCKET_NAME", "")
    try:
        s3_url = await upload_image_to_s3(
            file,
            bucket_name=bucket_name,
            body=file_bytes,
            content_type=detected_mime,
        )
    except ValueError as e:
        raise HTTPException(status_code=500, detail=str(e))

    damage_image = DamageImage(
        real_estate_id=real_estate.id,
        s3_url=s3_url,
        damage_type=DamageTypeEnum.other,
        ai_result=None,
        file_hash=image_hash,
    )
    db.add(damage_image)
    db.flush()

    depreciation_rate = calculate_depreciation_rate(
        elapsed_years=0.0,
        useful_life_years=10.0,
    )
    tenant_cost = calculate_tenant_cost(
        total_repair_cost=0.0,
        elapsed_years=0.0,
        useful_life_years=10.0,
    )

    estimate = RepairEstimate(
        real_estate_id=real_estate.id,
        damage_image_id=damage_image.id,
        total_repair_cost=0.0,
        useful_life_years=10.0,
        elapsed_years=0.0,
        tenant_cost=tenant_cost,
        depreciation_rate=depreciation_rate,
        image_hash=image_hash,
        analysis_status="analyzing",
    )
    db.add(estimate)
    db.commit()  # commit 먼저 → Celery 워커가 DB에서 행을 확실히 찾을 수 있음

    from worker import analyze_image_task

    async_result = analyze_image_task.delay(estimate.id)
    estimate.celery_task_id = async_result.id

    db.commit()

    return schemas.AnalyzeJobResponse(
        status="analyzing",
        task_id=str(async_result.id),
        repair_estimate_id=estimate.id,
    )


# -----------------------------
# 수리비/감가상각(RepairEstimate) 엔드포인트
# -----------------------------


@app.post(
    "/real-estates/{real_estate_id}/repair-estimates",
    response_model=schemas.RepairEstimateRead,
    summary="수리비 및 감가상각 계산/저장",
    description="총 수리비, 경과연수, 내용연수(기본 10년)를 받아 국토부 가이드라인 공식으로 임차인 부담비용과 감가상각 비율을 계산해 저장합니다.",
)
def create_repair_estimate(
    request: Request,
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
    summary="헬스체크·준비 상태",
    description=(
        "프로세스·DB·Redis·Celery 워커 상태를 반환합니다. "
        "DB 연결 실패 시 503을 반환하며, Docker/K8s 헬스 프로브에 사용할 수 있습니다."
    ),
)
@limiter.limit("120/minute")
def health_check(request: Request, response: Response) -> dict:
    """DB·Redis·Celery 점검 결과를 한 번에 반환한다."""

    ok_db, err_db = _check_database()
    ok_redis, err_redis = _check_redis()
    ok_celery, err_celery, ping = _check_celery_workers()

    body: dict = {
        "status": "healthy",
        "service": "dabadrim-teogeo",
        "checks": {
            "database": {"ok": ok_db, "error": err_db},
            "redis": {"ok": ok_redis, "error": err_redis},
            "celery_workers": {
                "ok": ok_celery,
                "error": err_celery,
                "workers": list(ping.keys()) if ping else [],
            },
        },
    }

    if not ok_db:
        body["status"] = "unhealthy"
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return body

    if not ok_redis or not ok_celery:
        body["status"] = "degraded"

    return body

