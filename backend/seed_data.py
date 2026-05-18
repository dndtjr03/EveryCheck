"""테스트용 유저 1명과 체크리스트 2건을 RDS에 저장한 뒤, 다시 조회해 터미널에 출력한다.

루트 .env 의 DATABASE_URL·JWT_SECRET_KEY( auth 모듈 로드용 )가 필요하다.

    cd backend
    python seed_data.py

동일 이메일의 시드 유저가 이미 있으면 그 행을 재사용하고, 제목이 [SEED] 로 시작하는
기존 시드 체크리스트만 지운 뒤 2건을 다시 넣어 재실행해도 같은 모양이 된다.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

SEED_EMAIL = "seed_user@everycheck.com"
SEED_PASSWORD = "TestSeed!123"
SEED_FULL_NAME = "시드 테스트 유저"
SEED_CHECKLIST_TITLES = ("[SEED] 퇴거 전 점검", "[SEED] 원상복구 항목 확인")


def _load_env() -> None:
    backend_dir = Path(__file__).resolve().parent
    root_dir = backend_dir.parent
    load_dotenv(root_dir / ".env")
    load_dotenv(backend_dir / ".env", override=False)


def _print_section(title: str) -> None:
    print()
    print("=" * 60)
    print(title)
    print("=" * 60)


def main() -> int:
    _load_env()

    if not os.getenv("DATABASE_URL"):
        print("오류: DATABASE_URL 이 없습니다. 프로젝트 루트 .env 를 확인하세요.", file=sys.stderr)
        return 1

    if not (os.getenv("JWT_SECRET_KEY") or os.getenv("SECRET_KEY")):
        print(
            "오류: auth.get_password_hash 를 쓰려면 JWT_SECRET_KEY 또는 SECRET_KEY 가 필요합니다.",
            file=sys.stderr,
        )
        return 1

    from auth import get_password_hash
    from database import session_scope
    from models import Checklist, User

    with session_scope() as db:
        user = db.query(User).filter(User.email == SEED_EMAIL).first()
        if user is None:
            user = User(
                email=SEED_EMAIL,
                hashed_password=get_password_hash(SEED_PASSWORD),
                full_name=SEED_FULL_NAME,
                is_active=True,
            )
            db.add(user)
            db.flush()

        db.query(Checklist).filter(
            Checklist.user_id == user.id,
            Checklist.title.like("[SEED]%"),
        ).delete(synchronize_session=False)

        for title in SEED_CHECKLIST_TITLES:
            db.add(Checklist(user_id=user.id, title=title))

    _print_section("저장 완료 (커밋 후 새 세션에서 조회)")

    with session_scope() as db:
        user = db.query(User).filter(User.email == SEED_EMAIL).first()
        if user is None:
            print("오류: 저장 후 유저를 찾을 수 없습니다.", file=sys.stderr)
            return 1

        checklists = (
            db.query(Checklist)
            .filter(
                Checklist.user_id == user.id,
                Checklist.title.like("[SEED]%"),
            )
            .order_by(Checklist.id.asc())
            .all()
        )

        user_out = {
            "id": user.id,
            "email": user.email,
            "full_name": user.full_name,
            "is_active": user.is_active,
            "created_at": user.created_at,
        }
        checklists_out = [
            {"id": cl.id, "user_id": cl.user_id, "title": cl.title, "created_at": cl.created_at}
            for cl in checklists
        ]

    print("User")
    print(f"  id           : {user_out['id']}")
    print(f"  email        : {user_out['email']}")
    print(f"  full_name    : {user_out['full_name']}")
    print(f"  is_active    : {user_out['is_active']}")
    print(f"  created_at   : {user_out['created_at']}")
    print(f"  (plain 비밀번호는 DB에 저장하지 않음, 로그인 테스트용: {SEED_PASSWORD})")

    print()
    print(f"Checklists (count={len(checklists_out)})")
    for i, cl in enumerate(checklists_out, start=1):
        print(
            f"  [{i}] id={cl['id']} user_id={cl['user_id']} "
            f"title={cl['title']!r} created_at={cl['created_at']}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
