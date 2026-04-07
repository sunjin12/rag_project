"""
Pydantic 요청/응답 스키마

API 엔드포인트의 입출력 데이터 검증 및 직렬화를 담당합니다.
DB ORM 모델은 database.py에 별도 정의되어 있습니다.
"""

from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


# ─── 인증 관련 스키마 ─────────────────────────────────────

class LoginRequest(BaseModel):
    """이메일/비밀번호 로그인 요청 (비활성 — Google OAuth만 사용)"""
    email: str
    password: str


class RegisterRequest(BaseModel):
    """회원 가입 요청 (비활성 — Google OAuth만 사용)"""
    username: str
    email: str
    password: str


class GoogleSignInRequest(BaseModel):
    """Google ID 토큰 기반 로그인 요청 (모바일용)"""
    id_token: str


class GoogleAuthCodeRequest(BaseModel):
    """Google Authorization Code 기반 로그인 요청 (데스크톱용)"""
    code: str
    redirect_uri: str


class UserResponse(BaseModel):
    """사용자 정보 응답 (로그인 성공 시 반환)"""
    id: str
    username: str
    email: str
    token: str


# ─── 사용자 모델 ──────────────────────────────────────────

class User(BaseModel):
    """사용자 정보 (DB ORM → Pydantic 변환용)"""
    id: str
    username: str
    email: str
    password: Optional[str] = None
    google_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ─── 채팅 관련 스키마 ─────────────────────────────────────

class ChatRequest(BaseModel):
    """채팅 질문 요청"""
    question: str


class ChatResponse(BaseModel):
    """채팅 응답 (SSE 스트리밍이 아닌 일반 응답용)"""
    id: str
    content: str
    is_user: bool
    timestamp: str
    persona_id: Optional[str] = None
    retrieved_documents: Optional[List[str]] = None
