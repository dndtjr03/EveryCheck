"""임대차 계약(RealEstate) 비즈니스 로직."""

from typing import List, Optional

from sqlalchemy.orm import Session

import schemas
from models import RealEstate, User


def create(db: Session, *, owner: User, payload: schemas.RealEstateCreate) -> RealEstate:
    re = RealEstate(
        owner_id=owner.id,
        address=payload.address,
        contract_start_date=payload.contract_start_date,
        contract_end_date=payload.contract_end_date,
        memo=payload.memo,
    )
    db.add(re)
    db.commit()
    db.refresh(re)
    return re


def list_for_owner(db: Session, *, owner: User) -> List[RealEstate]:
    return (
        db.query(RealEstate)
        .filter(RealEstate.owner_id == owner.id)
        .order_by(RealEstate.created_at.desc())
        .all()
    )


def get_owned(db: Session, *, owner: User, real_estate_id: int) -> Optional[RealEstate]:
    return (
        db.query(RealEstate)
        .filter(
            RealEstate.id == real_estate_id,
            RealEstate.owner_id == owner.id,
        )
        .first()
    )
