"""인증·회원 관련 비즈니스 로직."""

from typing import Optional

from jose import JWTError, jwt
from sqlalchemy.orm import Session

import schemas
from auth import (
    ALGORITHM,
    SECRET_KEY,
    authenticate_user,
    create_access_token,
    create_refresh_token,
    get_password_hash,
    get_user_by_email,
)
from models import User


class EmailAlreadyExists(Exception):
    pass


class InvalidCredentials(Exception):
    pass


class InvalidRefreshToken(Exception):
    def __init__(self, message: str = "리프레시 토큰 검증에 실패했습니다."):
        super().__init__(message)
        self.message = message


def register(db: Session, payload: schemas.UserCreate) -> User:
    if get_user_by_email(db, email=payload.email) is not None:
        raise EmailAlreadyExists("이미 가입된 이메일입니다.")
    user = User(
        email=payload.email,
        full_name=payload.full_name,
        hashed_password=get_password_hash(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def issue_tokens_for_login(db: Session, *, email: str, password: str) -> schemas.Token:
    user = authenticate_user(db, email=email, password=password)
    if not user:
        raise InvalidCredentials("이메일 또는 비밀번호가 올바르지 않습니다.")
    return _make_token_pair(user.email)


def rotate_tokens(db: Session, refresh_token: str) -> schemas.Token:
    try:
        payload = jwt.decode(refresh_token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "refresh":
            raise InvalidRefreshToken("리프레시 토큰이 아닙니다.")
        sub: Optional[str] = payload.get("sub")
        if not sub:
            raise InvalidRefreshToken("리프레시 토큰이 올바르지 않습니다.")
    except JWTError:
        raise InvalidRefreshToken("리프레시 토큰 검증에 실패했습니다.")

    user = get_user_by_email(db, email=sub)
    if not user or not user.is_active:
        raise InvalidRefreshToken("사용자를 찾을 수 없거나 비활성화되었습니다.")
    return _make_token_pair(user.email)


def _make_token_pair(email: str) -> schemas.Token:
    return schemas.Token(
        access_token=create_access_token(data={"sub": email}),
        refresh_token=create_refresh_token(data={"sub": email}),
        token_type="bearer",
    )
