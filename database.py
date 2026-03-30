"""데이터베이스 연결 및 세션 관리를 담당하는 모듈."""

import os

from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# 환경 변수에서 DATABASE_URL을 가져오고, 설정되지 않은 경우 Docker-compose 기본 값을 사용한다.
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg2://app:app@localhost:5432/teogeo",
)

# SQLAlchemy 엔진 생성
engine = create_engine(DATABASE_URL, future=True, echo=False)

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

