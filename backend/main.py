"""다봐드림(EveryCheck) FastAPI 애플리케이션 부트스트랩.

이 파일은 다음 책임만 가진다:
- FastAPI 앱 인스턴스 생성
- 정적 파일 마운트
- CORS / 미들웨어 / OpenAPI / startup 훅 등록
- 도메인 라우터 등록 (`routers/*`)

도메인 로직은 모두 `routers/`, `services/`, `core/` 모듈로 분리되어 있다.
"""

from pathlib import Path

from dotenv import load_dotenv

# 프로젝트 루트 .env 우선 로드 — auth 등 다른 모듈이 import 되기 전에 환경값을 채워야 함.
_BACKEND_DIR = Path(__file__).resolve().parent
_ROOT_DIR = _BACKEND_DIR.parent
load_dotenv(_ROOT_DIR / ".env")
load_dotenv(_BACKEND_DIR / ".env", override=False)

from utils import normalize_aws_credentials  # noqa: E402

normalize_aws_credentials()

from fastapi import FastAPI  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402
from fastapi.staticfiles import StaticFiles  # noqa: E402
from slowapi import _rate_limit_exceeded_handler  # noqa: E402
from slowapi.errors import RateLimitExceeded  # noqa: E402
from slowapi.middleware import SlowAPIMiddleware  # noqa: E402

from config import get_settings  # noqa: E402
from core.middleware import install_middlewares  # noqa: E402
from core.openapi import install_openapi  # noqa: E402
from core.rate_limit import limiter  # noqa: E402
from core.startup import install_startup_hooks  # noqa: E402


settings = get_settings()


# -----------------------------
# 애플리케이션
# -----------------------------

app = FastAPI(
    title="다봐드림 API",
    description="임대차 원상복구 비용 분석 서비스 백엔드",
    version="0.2.0",
    openapi_url="/openapi.json",
    docs_url=None,  # core.openapi 가 커스텀 /docs 등록
    redoc_url=None,
)


# -----------------------------
# 정적 파일
# -----------------------------

_STATIC_ROOT = _BACKEND_DIR / "static"
_UPLOADS_ROOT = _BACKEND_DIR / "uploads"
_UPLOADS_ROOT.mkdir(parents=True, exist_ok=True)

# /static/uploads 가 /static/swagger-ui 와 충돌하지 않도록 먼저 마운트.
app.mount("/static/uploads", StaticFiles(directory=str(_UPLOADS_ROOT)), name="uploads")
app.mount("/static", StaticFiles(directory=str(_STATIC_ROOT)), name="static")


# -----------------------------
# CORS
# -----------------------------

_raw_cors = settings.cors_allow_origins
if _raw_cors.strip() == "*":
    _allow_origins = ["*"]
    _allow_credentials = False  # wildcard 와 credentials 동시 사용 금지
else:
    _allow_origins = [o.strip() for o in _raw_cors.split(",") if o.strip()] or [
        "http://localhost:3000"
    ]
    _allow_credentials = settings.cors_allow_credentials

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allow_origins,
    allow_credentials=_allow_credentials,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept", "X-Requested-With"],
    expose_headers=["Retry-After"],
)


# -----------------------------
# 미들웨어 · OpenAPI · 레이트 리미터 · startup
# -----------------------------

install_middlewares(app)
install_openapi(app)
install_startup_hooks(app)

app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)


# -----------------------------
# 도메인 라우터
# -----------------------------

from routers.analysis import router as analysis_router  # noqa: E402
from routers.auth import router as auth_router  # noqa: E402
from routers.checklist import router as checklist_router  # noqa: E402
from routers.health import router as health_router  # noqa: E402
from routers.photo import router as photo_router  # noqa: E402
from routers.real_estate import router as real_estate_router  # noqa: E402

app.include_router(auth_router, tags=["auth"])  # /auth/*, /users/me
app.include_router(health_router, tags=["health"])  # /health
app.include_router(real_estate_router, prefix="/real-estates", tags=["real-estates"])
app.include_router(checklist_router, prefix="/checklists", tags=["checklists"])
app.include_router(photo_router, prefix="/photos", tags=["photos"])
app.include_router(analysis_router, prefix="/analyses", tags=["analyses"])

# Flutter 앱이 Gemini 키를 들고 다니지 않게 백엔드가 대신 호출하는 프록시.
from analysis_proxy_router import router as analysis_proxy_router  # noqa: E402

app.include_router(analysis_proxy_router)

# RAG (법제처 OpenAPI + ChromaDB) 검색.
from routers.precedents import router as precedents_router  # noqa: E402

app.include_router(precedents_router)
