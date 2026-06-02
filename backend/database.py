"""데이터베이스 연결 및 세션 관리를 담당하는 모듈."""

from contextlib import contextmanager
from typing import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from config import get_settings

_settings = get_settings()

# 전역에서 재사용 가능하도록 DATABASE_URL을 노출 (기존 import 호환)
DATABASE_URL = _settings.database_url

# 웹(FastAPI)과 Celery 워커가 동시에 사용할 때를 고려한 연결 풀 설정
# - pool_pre_ping: 끊긴 연결 재사용 방지 (워커 장기 실행에 유리)
# - pool_recycle: PostgreSQL idle 타임아웃 회피
engine = create_engine(
    DATABASE_URL,
    future=True,
    echo=False,
    pool_pre_ping=True,
    pool_recycle=_settings.db_pool_recycle,
    pool_size=_settings.db_pool_size,
    max_overflow=_settings.db_max_overflow,
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
