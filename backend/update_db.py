"""RDS(PostgreSQL)의 photos 테이블에 photo_type 컬럼과 비교용 인덱스를 추가한다.

실행:

    cd backend
    python update_db.py

루트 .env 의 DATABASE_URL 을 사용한다. 이미 컬럼·인덱스가 있으면 IF NOT EXISTS 로 건너뛴다.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv


def _load_env() -> None:
    backend_dir = Path(__file__).resolve().parent
    root_dir = backend_dir.parent
    load_dotenv(root_dir / ".env")
    load_dotenv(backend_dir / ".env", override=False)


def _mask_database_url(url: str) -> str:
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
        print("오류: DATABASE_URL 이 없습니다. 프로젝트 루트 .env 를 확인하세요.", file=sys.stderr)
        return 1

    from sqlalchemy import create_engine, text

    url = os.environ["DATABASE_URL"]
    print("연결 대상:", _mask_database_url(url))

    engine = create_engine(url, future=True)

    ddl_column = text(
        """
        ALTER TABLE photos
        ADD COLUMN IF NOT EXISTS photo_type VARCHAR(16) NOT NULL DEFAULT 'INITIAL'
        """
    )
    ddl_index = text(
        """
        CREATE INDEX IF NOT EXISTS ix_photos_checklist_photo_type
        ON photos (checklist_id, photo_type)
        """
    )

    try:
        with engine.begin() as conn:
            conn.execute(ddl_column)
            print("실행: ALTER TABLE photos ... photo_type (없을 때만 추가)")
            conn.execute(ddl_index)
            print("실행: CREATE INDEX ix_photos_checklist_photo_type (없을 때만 생성)")
    except Exception as exc:
        print(f"오류: {exc}", file=sys.stderr)
        return 1

    print("완료: photos.photo_type 컬럼 및 인덱스 적용을 시도했습니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
