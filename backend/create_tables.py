"""루트 .env 의 DATABASE_URL 로 연결한 RDS(PostgreSQL)에 users·checklists·photos 테이블을 생성한다.

실행 (저장소 루트의 .env 사용):

    cd backend
    python create_tables.py

이미 테이블이 있으면 SQLAlchemy create_all 은 해당 테이블을 건드리지 않는다(컬럼 변경은 Alembic 등으로 처리).
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv


def _load_env() -> None:
    """backend 상위 디렉터리(프로젝트 루트)의 .env 를 우선 로드한다."""
    backend_dir = Path(__file__).resolve().parent
    root_dir = backend_dir.parent
    # 루트 .env → backend/.env 순, 먼저 로드한 값이 우선(override=False)
    load_dotenv(root_dir / ".env")
    load_dotenv(backend_dir / ".env", override=False)


def _mask_database_url(url: str) -> str:
    """로그에 비밀번호가 노출되지 않도록 호스트만 남긴다."""
    try:
        parsed = urlparse(url)
        if parsed.password:
            netloc = parsed.netloc.split("@")[-1]
            return f"{parsed.scheme}://***:***@{netloc}{parsed.path or ''}"
        return url
    except Exception:
        return "(unparseable DATABASE_URL)"


def main() -> int:
    _load_env()

    if not os.getenv("DATABASE_URL"):
        print("오류: DATABASE_URL 이 설정되지 않았습니다. 프로젝트 루트의 .env 를 확인하세요.", file=sys.stderr)
        return 1

    # DATABASE_URL 이 os.environ 에 반영된 뒤 database / models 를 불러야 한다.
    from database import Base, engine
    from models import Checklist, Photo, User
    from sqlalchemy import inspect

    url = os.environ["DATABASE_URL"]
    print("연결 대상:", _mask_database_url(url))

    # users → checklists → photos 순 (외래키 의존)
    Base.metadata.create_all(engine)

    insp = inspect(engine)
    for name in ("users", "checklists", "photos"):
        if insp.has_table(name):
            print(f"확인: 테이블 '{name}' 존재")
        else:
            print(f"경고: 테이블 '{name}' 가 보이지 않습니다.", file=sys.stderr)
            return 1

    print("완료: users, checklists, photos 테이블 생성(또는 이미 존재) 처리됨.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
