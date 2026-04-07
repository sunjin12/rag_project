"""
인증 라우터

Google OAuth 2.0 기반 로그인 엔드포인트를 제공합니다.
- POST /auth/google : Google ID 토큰으로 로그인
- POST /auth/code  : Google Authorization Code로 로그인
- POST /auth/login, /auth/register : 비활성(Google OAuth만 지원)

사용자 정보는 PostgreSQL users 테이블에 저장됩니다.
"""

from fastapi import APIRouter, HTTPException, status, Depends
from datetime import timedelta
from sqlalchemy.orm import Session

from ..models import (
    GoogleSignInRequest,
    GoogleAuthCodeRequest,
    UserResponse,
    LoginRequest,
    RegisterRequest,
)
from ..auth import (
    verify_google_token,
    create_access_token,
    exchange_google_authorization_code,
)
from ..config import settings
from ..database import get_db, UserDB

router = APIRouter(prefix="/auth", tags=["auth"])


def _get_or_create_user(db: Session, user_info: dict) -> UserDB:
    """
    Google ID로 기존 사용자를 찾거나, 없으면 새로 생성합니다.

    Args:
        db: SQLAlchemy 세션
        user_info: verify_google_token()이 반환한 사용자 정보 dict

    Returns:
        UserDB: 사용자 ORM 객체
    """
    google_id = user_info["google_id"]

    # 기존 사용자 검색
    user = db.query(UserDB).filter(UserDB.google_id == google_id).first()
    if user:
        return user

    # 신규 사용자 생성
    user = UserDB(
        username=user_info["username"],
        email=user_info["email"],
        google_id=google_id,
        picture=user_info.get("picture"),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.post("/google", response_model=UserResponse)
async def google_sign_in(
    request: GoogleSignInRequest,
    db: Session = Depends(get_db),
):
    """
    Google ID 토큰을 검증하고 사용자를 생성/로그인합니다.

    모바일(Android/iOS)에서 GoogleSignIn SDK가 반환한 idToken을 받아 처리합니다.
    """
    try:
        user_info = verify_google_token(request.id_token)
        user = _get_or_create_user(db, user_info)

        access_token_expires = timedelta(minutes=settings.access_token_expire_minutes)
        access_token = create_access_token(
            data={"sub": user.id, "email": user.email},
            expires_delta=access_token_expires,
        )

        return UserResponse(
            id=user.id,
            username=user.username,
            email=user.email,
            token=access_token,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Google authentication failed: {str(e)}",
        )


@router.post("/code", response_model=UserResponse)
async def google_sign_in_code(
    request: GoogleAuthCodeRequest,
    db: Session = Depends(get_db),
):
    """
    Google Authorization Code를 받아 토큰으로 교환 후 사용자 인증을 수행합니다.

    데스크톱(Windows/macOS/Linux) 앱에서 브라우저 OAuth 후 받은 code를 처리합니다.
    """
    if not settings.google_client_secret:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google client secret is not configured",
        )

    try:
        token_data = await exchange_google_authorization_code(
            request.code, request.redirect_uri
        )
        id_token_str = token_data.get("id_token")
        if not id_token_str:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Google did not return an ID token.",
            )

        user_info = verify_google_token(id_token_str)
        user = _get_or_create_user(db, user_info)

        access_token_expires = timedelta(minutes=settings.access_token_expire_minutes)
        access_token = create_access_token(
            data={"sub": user.id, "email": user.email},
            expires_delta=access_token_expires,
        )

        return UserResponse(
            id=user.id,
            username=user.username,
            email=user.email,
            token=access_token,
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Google token exchange failed: {str(e)}",
        )


@router.post("/login", response_model=UserResponse)
async def login(request: LoginRequest):
    """
    이 엔드포인트는 사용되지 않습니다. Google Sign-In만 지원합니다.
    """
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Email/Password login is deprecated. Please use Google Sign-In."
    )


@router.post("/register", response_model=UserResponse)
async def register(request: RegisterRequest):
    """
    이 엔드포인트는 사용되지 않습니다. Google Sign-In만 지원합니다.
    """
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Email/Password registration is deprecated. Please use Google Sign-In."
    )
