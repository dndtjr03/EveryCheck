"""데이터베이스 연결 및 세션 관리를 담당하는 모듈."""

import os
from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, declarative_base, sessionmaker

# 환경 변수에서 DATABASE_URL을 가져오고, 설정되지 않은 경우 Docker-compose 기본 값을 사용한다.
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg2://app:app@localhost:5432/teogeo",
)

# 웹(FastAPI)과 Celery 워커가 동시에 사용할 때를 고려한 연결 풀 설정
# - pool_pre_ping: 끊긴 연결 재사용 방지 (워커 장기 실행에 유리)
# - pool_recycle: PostgreSQL idle 타임아웃 회피
_pool_size = int(os.getenv("DB_POOL_SIZE", "5"))
_max_overflow = int(os.getenv("DB_MAX_OVERFLOW", "10"))

engine = create_engine(
    DATABASE_URL,
    future=True,
    echo=False,
    pool_pre_ping=True,
    pool_recycle=int(os.getenv("DB_POOL_RECYCLE", "3600")),
    pool_size=_pool_size,
    max_overflow=_max_overflow,
)

# 세션 팩토리 설정
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 베이스 클래스 (모든 ORM 모델이 상속)
Base = declarative_base()


def get_db():
    """요청마다 독립적인 DB 세션을 제공하기 위한 FastAPI 의존성 함수."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@contextmanager
def session_scope() -> Generator[Session, None, None]:
    """Celery 태스크 등에서 사용할 세션 컨텍스트 (commit/rollback/close 일괄 처리)."""
    session = SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
