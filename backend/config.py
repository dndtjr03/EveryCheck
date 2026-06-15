"""애플리케이션 설정 통합 모듈.

`pydantic-settings`의 `BaseSettings`를 기반으로 환경변수와 `.env` 파일에서
설정을 일괄적으로 로드한다. 모든 환경값은 `get_settings()` 싱글턴을 통해 조회한다.

- `.env` 파일은 **프로젝트 루트** (`backend/`의 상위 디렉터리)를 우선 로드한다.
- 필수값(JWT_SECRET_KEY 등)이 누락되면 `ValidationError`가 발생한다.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal, Optional

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


# 프로젝트 루트의 .env 절대경로 (backend/config.py → backend/ → 프로젝트 루트)
_PROJECT_ROOT_ENV = str(Path(__file__).resolve().parent.parent / ".env")


class Settings(BaseSettings):
    """전역 환경설정 컨테이너."""

    # --- Database ---
    database_url: str = "postgresql+psycopg2://app:app@localhost:5432/teogeo"
    db_pool_size: int = 5
    db_max_overflow: int = 10
    db_pool_recycle: int = 3600

    # --- JWT / Auth ---
    jwt_secret_key: SecretStr
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 14

    # --- CORS ---
    cors_allow_origins: str = "http://localhost:3000,http://127.0.0.1:3000"
    cors_allow_credentials: bool = True

    # --- Redis / Celery ---
    redis_url: str = "redis://localhost:6379/0"

    # --- AWS / S3 ---
    aws_region: Optional[str] = None
    s3_bucket_name: Optional[str] = None

    # --- External APIs ---
    google_api_key: Optional[SecretStr] = None

    # --- Runtime profile ---
    environment: Literal["dev", "staging", "prod"] = "dev"

    # --- HTTP security ---
    # HSTS는 HTTPS 운영에서만 켤 것. dev 로컬은 false 유지.
    enable_hsts: bool = False

    model_config = SettingsConfigDict(
        env_file=_PROJECT_ROOT_ENV,
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """프로세스 단위 싱글턴 Settings 인스턴스를 반환한다."""
    return Settings()  # type: ignore[call-arg]
