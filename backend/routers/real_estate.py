"""임대차 계약(RealEstate) 라우터."""

from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

import schemas
from auth import get_current_active_user
from database import get_db
from models import RealEstate, User
from services import real_estate_service

router = APIRouter()


@router.post(
    "",
    response_model=schemas.RealEstateRead,
    summary="임대차 계약 등록",
)
@router.post(
    "/",
    response_model=schemas.RealEstateRead,
    include_in_schema=False,
)
def create_real_estate(
    body: schemas.RealEstateCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> RealEstate:
    return real_estate_service.create(db, owner=current_user, payload=body)


@router.get(
    "",
    response_model=List[schemas.RealEstateRead],
    summary="내 임대차 계약 목록",
)
@router.get(
    "/",
    response_model=List[schemas.RealEstateRead],
    include_in_schema=False,
)
def list_real_estates(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> List[RealEstate]:
    return real_estate_service.list_for_owner(db, owner=current_user)


@router.get(
    "/{real_estate_id}",
    response_model=schemas.RealEstateRead,
    summary="임대차 계약 상세",
)
def get_real_estate_detail(
    real_estate_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
) -> RealEstate:
    re = real_estate_service.get_owned(
        db, owner=current_user, real_estate_id=real_estate_id
    )
    if re is None:
        raise HTTPException(status_code=404, detail="임대차 계약을 찾을 수 없습니다.")
    return re
