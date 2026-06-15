"""인증·회원 라우터 (`/auth/*`, `/users/me`)."""

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

import schemas
from auth import get_current_active_user
from core.rate_limit import limiter
from database import get_db
from models import User
from services import auth_service

router = APIRouter()


@router.post(
    "/auth/register",
    response_model=schemas.UserRead,
    summary="회원 가입",
    description="신규 사용자를 등록합니다. 이메일 중복을 검사하고 비밀번호는 bcrypt로 해시하여 저장합니다.",
)
def register_user(
    user_in: schemas.UserCreate,
    db: Session = Depends(get_db),
) -> User:
    try:
        return auth_service.register(db, user_in)
    except auth_service.EmailAlreadyExists as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post(
    "/auth/token",
    response_model=schemas.Token,
    summary="액세스 토큰 발급",
    description="이메일/비밀번호로 로그인하여 JWT 액세스 토큰을 발급합니다. (OAuth2 Password Grant)",
)
@limiter.limit("5/minute")
def login_for_access_token(
    request: Request,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
) -> schemas.Token:
    try:
        return auth_service.issue_tokens_for_login(
            db, email=form_data.username, password=form_data.password
        )
    except auth_service.InvalidCredentials as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        )


@router.post(
    "/auth/refresh",
    response_model=schemas.Token,
    summary="리프레시 토큰으로 재발급",
    description="리프레시 토큰을 검증한 뒤 새로운 액세스 토큰을 발급합니다. 운영에서는 토큰 회전·블랙리스트 전략을 추가하세요.",
)
def refresh_access_token(
    refresh_token: str = Body(..., embed=True, description="리프레시 토큰 문자열"),
    db: Session = Depends(get_db),
) -> schemas.Token:
    try:
        return auth_service.rotate_tokens(db, refresh_token)
    except auth_service.InvalidRefreshToken as exc:
        raise HTTPException(status_code=401, detail=exc.message)


@router.get(
    "/users/me",
    response_model=schemas.UserRead,
    summary="내 정보 조회",
    description="현재 인증된 사용자 정보를 반환합니다. Authorization 헤더에 Bearer 토큰이 필요합니다.",
)
async def read_users_me(
    current_user: User = Depends(get_current_active_user),
) -> User:
    return current_user
