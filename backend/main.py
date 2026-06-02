"""퇴거의 정석 - FastAPI 메인 애플리케이션.

- JWT 기반 인증/인가
- 임대차 계약(RealEstate) CRUD 골격
- 분석 세션(Analysis) / 분석 사진(AnalysisPhoto) / 채팅(AnalysisMessage)
"""

# auth 등 프로젝트 모듈이 import 될 때 os.environ 에 JWT·DB 값이 있어야 하므로,
# 반드시 먼저 저장소 루트의 .env 를 로드한다 (backend/.env 는 보조).
from pathlib import Path

from dotenv import load_dotenv

_backend_dir = Path(__file__).resolve().parent
_root_dir = _backend_dir.parent
load_dotenv(_root_dir / ".env")
load_dotenv(_backend_dir / ".env", override=False)

import os
from typing import List, Optional

from utils import normalize_aws_credentials

normalize_aws_credentials()

from fastapi import (
    Body,
    Depends,
    FastAPI,
    File,
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
from fastapi.openapi.utils import get_openapi
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
from routers import photo
from routers.checklist import router as checklist_router
from routers.analysis import router as analysis_router
from security_audit import init_security_audit_logger, log_sensitive_endpoint_access
from models import RealEstate, User
from utils import (
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
_UPLOADS_ROOT = Path(__file__).resolve().parent / "uploads"
_UPLOADS_ROOT.mkdir(parents=True, exist_ok=True)

# 업로드 파일: /static/uploads/<파일명> (Swagger UI 정적 파일 /static/swagger-ui/* 와 충돌 방지를 위해 하위 경로 사용)
app.mount(
    "/static/uploads",
    StaticFiles(directory=str(_UPLOADS_ROOT)),
    name="uploads",
)
app.mount(
    "/static",
    StaticFiles(directory=str(_STATIC_ROOT)),
    name="static",
)

app.include_router(
    checklist_router,
    prefix="/checklists",
    tags=["checklists"],
)

app.include_router(
    photo.router,
    prefix="/photos",
    tags=["photos"],
)

app.include_router(
    analysis_router,
    prefix="/analyses",
    tags=["analyses"],
)

# Flutter 앱이 Gemini 키를 들고 다니지 않게 백엔드가 대신 호출하는 프록시 라우터
from analysis_proxy_router import router as analysis_proxy_router  # noqa: E402
app.include_router(analysis_proxy_router)

# RAG (법제처 OpenAPI + ChromaDB) 검색 라우터
from routers.precedents import router as precedents_router  # noqa: E402
app.include_router(precedents_router)


def _patch_file_upload_property(prop: dict) -> None:
    if prop.get("contentMediaType") == "application/octet-stream":
        prop["format"] = "binary"
        return
    items = prop.get("items")
    if isinstance(items, dict) and items.get("contentMediaType") == "application/octet-stream":
        items["format"] = "binary"


def _patch_multipart_file_binary_format(openapi_schema: dict) -> None:
    """로컬 Swagger UI가 multipart file 필드를 file input으로 렌더링하도록 format 추가."""
    schemas = (openapi_schema.get("components") or {}).get("schemas") or {}
    for schema in schemas.values():
        if not isinstance(schema, dict):
            continue
        for key in ("file", "files"):
            prop = schema.get("properties", {}).get(key)
            if isinstance(prop, dict):
                _patch_file_upload_property(prop)


def custom_openapi():
    if app.openapi_schema:
        return app.openapi_schema
    openapi_schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )
    _patch_multipart_file_binary_format(openapi_schema)
    app.openapi_schema = openapi_schema
    return app.openapi_schema


app.openapi = custom_openapi


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


@app.on_event("startup")
def _startup_warmup_rag() -> None:
    """RAG 임베딩 모델·ChromaDB를 백그라운드에서 미리 로드.

    첫 채팅 요청 시 ko-sroberta 모델(약 400MB)을 처음 메모리에 올리느라
    1~3초가 추가로 걸리는 현상을 제거하기 위함. 메인 startup을 블로킹하지
    않도록 별도 스레드에서 dummy query를 1회 실행하고, 실패해도 채팅은
    on-demand 로드로 계속 동작한다.
    """
    import threading
    import logging

    log = logging.getLogger("rag.warmup")

    def _warm() -> None:
        try:
            from rag import get_default_index

            idx = get_default_index()
            # 임베딩 + Chroma 쿼리 경로를 모두 한 번씩 실행해 캐시 적재.
            idx.query("워밍업", n_results=1)
            log.info("RAG warmup done — chunks=%d", idx.count())
        except Exception as exc:  # noqa: BLE001
            log.warning("RAG warmup skipped (will load on first chat): %s", exc)

    threading.Thread(target=_warm, name="rag-warmup", daemon=True).start()


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
    response_model=schemas.RealEstateRead,
    summary="임대차 계약 상세",
    description="임대차 계약 1건의 상세 정보를 반환합니다.",
)
def get_real_estate_detail(
    request: Request,
    real_estate_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> RealEstate:
    """임대차 계약 정보를 조회한다."""

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

    return real_estate


# NOTE: 구 DamageImage/RepairEstimate 기반 엔드포인트는 Analysis* 모델 통합으로 폐기됨
# (/real-estates/{id}/images, /analyze, /real-estates/{id}/repair-estimates)
# 사진 업로드는 /photos/upload-single, 분석 세션 CRUD는 /analyses/* 사용.


@app.post(
    "/photos/upload-single",
    summary="단순 사진 업로드 → S3 (분석·체크리스트와 무관)",
    description=(
        "Flutter 분석 화면이 폰 로컬 SQLite에 저장한 사진을 백엔드 S3에 백업할 때 사용. "
        "DB에 별도 행을 만들지 않고 S3 URL만 반환한다. 클라이언트는 로컬 DB의 "
        "damage_photos.s3_url 컬럼에 받은 URL을 저장한다."
    ),
)
@limiter.limit("30/minute")
async def upload_single_photo(
    request: Request,
    file: UploadFile = File(..., description="JPEG/PNG/WEBP 이미지 1장"),
    current_user: User = Depends(get_current_active_user),
) -> dict:
    """체크리스트/분석 모델과 분리된 단일 사진 S3 업로드 엔드포인트.

    Flutter 측 로컬 SQLite가 진실 소스이고, S3는 백업·공유용으로만 사용된다.
    검증·해시·업로드 절차는 기존 /analyze 엔드포인트의 패턴을 그대로 따른다.
    """
    try:
        file_bytes, detected_mime = await validate_and_read_image_file(file)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    bucket_name = os.getenv("S3_BUCKET_NAME", "")
    if not bucket_name:
        raise HTTPException(
            status_code=503,
            detail="S3_BUCKET_NAME 환경 변수가 비어 있습니다.",
        )

    try:
        s3_url = await upload_image_to_s3(
            file,
            bucket_name=bucket_name,
            body=file_bytes,
            content_type=detected_mime,
        )
    except ValueError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "s3_url": s3_url,
        "image_hash": compute_image_hash_sha256(file_bytes),
        "content_type": detected_mime,
        "bytes": len(file_bytes),
    }


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

