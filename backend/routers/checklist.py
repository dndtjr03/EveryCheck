"""체크리스트 API (테스트용 공개 조회 + 본인 소유 생성/조회)."""

from typing import List

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

import schemas
from auth import get_current_active_user
from database import get_db
from models import Checklist, User

router = APIRouter()


@router.get(
    "/",
    response_model=List[schemas.ChecklistRead],
    summary="체크리스트 전체 조회 (테스트, 인증 없음)",
    description="DB에 저장된 모든 체크리스트를 id 오름차순으로 반환합니다. seed_data.py 결과 확인용입니다.",
)
def list_all_checklists(db: Session = Depends(get_db)) -> List[Checklist]:
    return db.query(Checklist).order_by(Checklist.id.asc()).all()


@router.get(
    "/me",
    response_model=List[schemas.ChecklistRead],
    summary="내 체크리스트 목록 (로그인 필요)",
)
def list_my_checklists(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> List[Checklist]:
    return (
        db.query(Checklist)
        .filter(Checklist.user_id == current_user.id)
        .order_by(Checklist.id.asc())
        .all()
    )


@router.post(
    "/",
    response_model=schemas.ChecklistRead,
    status_code=201,
    summary="체크리스트 생성 (로그인 사용자 본인 소유)",
)
def create_checklist(
    body: schemas.ChecklistCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> Checklist:
    title = (body.title or "").strip() or "체크리스트"
    cl = Checklist(user_id=current_user.id, title=title)
    db.add(cl)
    db.commit()
    db.refresh(cl)
    return cl
