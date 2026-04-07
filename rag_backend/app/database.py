"""
데이터베이스 모듈 (SQLAlchemy ORM)

PostgreSQL 연결, 테이블 정의, 세션 관리를 담당합니다.

테이블 구조:
  - users          : Google OAuth 인증 사용자 정보
  - personas       : 사용자별 AI 페르소나 (RAG 컨텍스트 단위)
  - uploaded_files  : 페르소나에 업로드된 문서/오디오 파일 메타데이터
  - chat_sessions  : 페르소나별 대화 세션
  - messages       : 대화 내 개별 메시지 (사용자 질문 + AI 응답)

사용 예시:
    from app.database import get_db, init_db
    # FastAPI 의존성 주입으로 세션 획득
    async def some_route(db: Session = Depends(get_db)):
        ...
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Column,
    String,
    Text,
    Boolean,
    Integer,
    DateTime,
    ForeignKey,
    create_engine,
)
from sqlalchemy.orm import (
    DeclarativeBase,
    sessionmaker,
    relationship,
    Session,
)

from .config import settings


# ─── 엔진 & 세션 팩토리 ───────────────────────────────────

engine = create_engine(
    settings.postgres_url,
    pool_pre_ping=True,       # 커넥션 유효성 사전 검사
    pool_size=10,             # 커넥션 풀 크기
    max_overflow=20,          # 풀 초과 시 추가 허용 수
    echo=False,               # SQL 로그 출력 (디버깅 시 True)
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
)


# ─── Base 클래스 ──────────────────────────────────────────

class Base(DeclarativeBase):
    """모든 ORM 모델의 부모 클래스"""
    pass


# ─── 헬퍼 함수 ───────────────────────────────────────────

def _utcnow() -> datetime:
    """현재 UTC 시각 반환 (timezone-aware)"""
    return datetime.now(timezone.utc)


def _new_uuid() -> str:
    """새 UUID4 문자열 생성"""
    return str(uuid.uuid4())


# ─── ORM 모델 정의 ────────────────────────────────────────

class UserDB(Base):
    """
    사용자 테이블

    Google OAuth로 인증된 사용자 정보를 저장합니다.
    google_id를 통해 중복 가입을 방지합니다.
    """
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=_new_uuid)
    username = Column(String(255), nullable=False)
    email = Column(String(255), nullable=False, unique=True, index=True)
    google_id = Column(String(255), nullable=False, unique=True, index=True)
    picture = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)

    # 관계: 사용자 → 페르소나 (1:N)
    personas = relationship("PersonaDB", back_populates="owner", cascade="all, delete-orphan")


class PersonaDB(Base):
    """
    페르소나 테이블

    사용자가 생성한 AI 페르소나입니다.
    각 페르소나는 독립적인 RAG 컨텍스트(업로드 파일, 대화 기록)를 가집니다.
    """
    __tablename__ = "personas"

    id = Column(String, primary_key=True, default=_new_uuid)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, default="")
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    # 관계
    owner = relationship("UserDB", back_populates="personas")
    uploaded_files = relationship("UploadedFileDB", back_populates="persona", cascade="all, delete-orphan")
    sessions = relationship("ChatSessionDB", back_populates="persona", cascade="all, delete-orphan")


class UploadedFileDB(Base):
    """
    업로드 파일 메타데이터 테이블

    PDF, 텍스트, 오디오 등 업로드된 파일의 메타 정보를 저장합니다.
    실제 벡터 임베딩은 Qdrant에 저장하며, 여기에는 파일 이름·타입만 보관합니다.
    """
    __tablename__ = "uploaded_files"

    id = Column(String, primary_key=True, default=_new_uuid)
    persona_id = Column(String, ForeignKey("personas.id", ondelete="CASCADE"), nullable=False, index=True)
    filename = Column(String(512), nullable=False)
    file_type = Column(String(50), nullable=False)  # pdf, text, audio, document
    uploaded_at = Column(DateTime(timezone=True), default=_utcnow)

    # 관계
    persona = relationship("PersonaDB", back_populates="uploaded_files")


class ChatSessionDB(Base):
    """
    대화 세션 테이블

    페르소나와의 대화를 세션 단위로 관리합니다.
    하나의 페르소나에 여러 세션(대화 스레드)이 존재할 수 있습니다.
    """
    __tablename__ = "chat_sessions"

    id = Column(String, primary_key=True, default=_new_uuid)
    persona_id = Column(String, ForeignKey("personas.id", ondelete="CASCADE"), nullable=False, index=True)
    title = Column(String(255), default="New Chat")
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    # 관계
    persona = relationship("PersonaDB", back_populates="sessions")
    messages = relationship("MessageDB", back_populates="session", cascade="all, delete-orphan",
                            order_by="MessageDB.created_at")


class MessageDB(Base):
    """
    메시지 테이블

    대화 세션 내 개별 메시지를 저장합니다.
    is_user=True이면 사용자 질문, False이면 AI 응답입니다.
    """
    __tablename__ = "messages"

    id = Column(String, primary_key=True, default=_new_uuid)
    session_id = Column(String, ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    content = Column(Text, nullable=False)
    is_user = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    # 관계
    session = relationship("ChatSessionDB", back_populates="messages")


# ─── DB 초기화 & 세션 의존성 ──────────────────────────────

def init_db():
    """
    데이터베이스 테이블 생성

    앱 시작 시 호출하여 테이블이 없으면 자동 생성합니다.
    이미 존재하는 테이블은 건드리지 않습니다(CREATE IF NOT EXISTS).
    """
    Base.metadata.create_all(bind=engine)


def get_db():
    """
    FastAPI 의존성 주입용 DB 세션 제너레이터

    사용 예시:
        @router.get("/items")
        def read_items(db: Session = Depends(get_db)):
            return db.query(Item).all()
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
