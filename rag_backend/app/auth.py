"""
인증 유틸리티 모듈

Google OAuth 2.0 토큰 검증과 JWT 액세스 토큰 생성/디코드를 담당합니다.
모든 설정값은 config.py의 Settings 인스턴스에서 가져옵니다.
"""

import httpx
import jwt
from datetime import datetime, timedelta, timezone
from typing import Optional
from google.auth.transport import requests
from google.oauth2 import id_token

from .config import settings


def verify_google_token(token: str) -> dict:
    """
    Google ID 토큰을 검증하고 사용자 정보를 반환합니다.

    Args:
        token: Google OAuth에서 발급받은 ID 토큰 문자열

    Returns:
        dict: google_id, email, username, picture 키를 포함한 사용자 정보

    Raises:
        ValueError: 토큰이 유효하지 않거나, issuer/audience가 맞지 않을 때
    """
    try:
        # Google의 공개 키로 토큰 검증 (audience는 아래에서 별도 확인)
        idinfo = id_token.verify_oauth2_token(
            token,
            requests.Request(),
            audience=None,
        )

        # 발급자(issuer) 확인
        if idinfo["iss"] not in [
            "accounts.google.com",
            "https://accounts.google.com",
        ]:
            raise ValueError("Wrong issuer.")

        # 클라이언트 ID(audience) 확인
        if idinfo.get("aud") not in settings.valid_google_client_ids:
            raise ValueError("Invalid audience / client ID.")

        return {
            "google_id": idinfo["sub"],
            "email": idinfo["email"],
            "username": idinfo.get("name", idinfo["email"].split("@")[0]),
            "picture": idinfo.get("picture"),
        }
    except Exception as e:
        print(f"Token verification error: {str(e)}")
        raise ValueError(f"Invalid token: {str(e)}")


def create_access_token(
    data: dict, expires_delta: Optional[timedelta] = None
) -> str:
    """
    JWT 액세스 토큰을 생성합니다.

    Args:
        data: 토큰 페이로드 (예: {"sub": user_id, "email": email})
        expires_delta: 만료 시간 (None이면 설정의 기본값 사용)

    Returns:
        str: 인코딩된 JWT 문자열
    """
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(
            minutes=settings.access_token_expire_minutes
        )

    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(
        to_encode, settings.secret_key, algorithm=settings.algorithm
    )
    return encoded_jwt


def decode_token(token: str) -> Optional[dict]:
    """
    JWT 액세스 토큰을 디코드하여 페이로드를 반환합니다.

    Args:
        token: JWT 문자열

    Returns:
        dict | None: 유효하면 페이로드 dict, 만료/무효 시 None
    """
    try:
        payload = jwt.decode(
            token, settings.secret_key, algorithms=[settings.algorithm]
        )
        return payload
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None


async def exchange_google_authorization_code(
    code: str, redirect_uri: str
) -> dict:
    """
    Google Authorization Code를 액세스 토큰으로 교환합니다.

    데스크톱 앱에서 브라우저 OAuth 후 받은 authorization code를
    Google 토큰 엔드포인트에 전송하여 id_token을 받아옵니다.

    Args:
        code: Google에서 발급한 authorization code
        redirect_uri: OAuth 콜백 URI (Google Console에 등록된 것과 일치해야 함)

    Returns:
        dict: id_token, access_token 등을 포함한 Google 응답

    Raises:
        ValueError: client_secret 미설정이거나 Google 토큰 교환 실패 시
    """
    if not settings.google_client_secret:
        raise ValueError("Google client secret is not configured.")

    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(
            "https://oauth2.googleapis.com/token",
            data={
                "code": code,
                "client_id": settings.google_web_client_id,
                "client_secret": settings.google_client_secret,
                "redirect_uri": redirect_uri,
                "grant_type": "authorization_code",
            },
        )
        if response.status_code != 200:
            error_body = response.text
            print(
                f"[Google Token Exchange] FAILED: "
                f"status={response.status_code}, body={error_body}"
            )
            raise ValueError(
                f"Google token endpoint {response.status_code}: {error_body}"
            )
        result = response.json()
        print(f"[Google Token Exchange] SUCCESS: keys={list(result.keys())}")
        return result
