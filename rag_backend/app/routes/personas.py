"""
페르소나 라우터

AI 페르소나 CRUD, 파일 업로드, 대화(질문/응답), 대화 기록 조회를 제공합니다.

엔드포인트:
  - GET    /personas              : 내 페르소나 목록
  - POST   /personas              : 페르소나 생성
  - GET    /personas/{id}         : 페르소나 상세
  - DELETE /personas/{id}         : 페르소나 삭제
  - POST   /personas/{id}/upload  : 파일 업로드 → 텍스트 추출 → 벡터 임베딩 → Qdrant 저장
  - POST   /personas/{id}/ask     : 질문 → RAG 검색 → LLM 응답
  - GET    /personas/{id}/ask/stream : 질문 → RAG 검색 → SSE 스트리밍 응답
  - GET    /personas/{id}/history : 대화 기록 조회

모든 엔드포인트는 JWT Bearer 토큰 인증이 필요합니다.
"""

from fastapi import APIRouter, HTTPException, status, Depends, UploadFile, File, Form, Query
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timezone
from sqlalchemy.orm import Session
import logging

from ..auth import decode_token
from ..database import (
    get_db,
    UserDB,
    PersonaDB,
    UploadedFileDB,
    ChatSessionDB,
    MessageDB,
    RagEvaluationDB,
)
from ..rag_service import rag_service, ollama_client, LLM_MODEL
from ..cache import redis_cache

router = APIRouter(prefix="/personas", tags=["personas"])
security = HTTPBearer()
logger = logging.getLogger(__name__)


# ─── 요청/응답 스키마 ──────────────────────────────────────

class PersonaCreate(BaseModel):
    """페르소나 생성 요청"""
    name: str
    description: Optional[str] = ""


class PersonaResponse(BaseModel):
    """페르소나 응답"""
    id: str
    name: str
    description: str
    uploaded_file_ids: List[str]
    created_at: str
    message_count: int


class MessageResponse(BaseModel):
    """메시지 응답"""
    id: str
    content: str
    is_user: bool
    timestamp: str
    persona_id: Optional[str] = None


class SessionResponse(BaseModel):
    """대화 세션 응답"""
    id: str
    title: str
    created_at: str
    message_count: int


# ─── 인증 의존성 ──────────────────────────────────────────

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> dict:
    """
    JWT 토큰을 검증하고 페이로드(사용자 정보)를 반환합니다.

    토큰이 만료되었거나 유효하지 않으면 401 에러를 발생시킵니다.
    """
    token = credentials.credentials
    payload = decode_token(token)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )
    return payload


# ─── 헬퍼 함수 ───────────────────────────────────────────

def _ensure_user_exists(db: Session, payload: dict) -> str:
    """
    JWT 페이로드의 user_id가 DB에 존재하는지 확인하고, 없으면 생성합니다.
    DB 초기화 등으로 사용자 레코드가 사라진 경우를 방어합니다.
    """
    user_id = payload.get("sub")
    if not db.query(UserDB).filter(UserDB.id == user_id).first():
        user = UserDB(
            id=user_id,
            username=payload.get("email", "unknown").split("@")[0],
            email=payload.get("email", "unknown@unknown.com"),
            google_id=f"restored_{user_id}",
        )
        db.add(user)
        db.commit()
        logger.info("Auto-created missing user record: %s", user_id)
    return user_id

def _persona_to_response(persona: PersonaDB) -> PersonaResponse:
    """PersonaDB ORM 객체를 API 응답 스키마로 변환"""
    file_ids = [f.id for f in persona.uploaded_files]
    # 모든 세션의 메시지 수 합산
    message_count = sum(len(s.messages) for s in persona.sessions)
    return PersonaResponse(
        id=persona.id,
        name=persona.name,
        description=persona.description or "",
        uploaded_file_ids=file_ids,
        created_at=persona.created_at.isoformat(),
        message_count=message_count,
    )


def _get_user_persona(db: Session, persona_id: str, user_id: str) -> PersonaDB:
    """
    사용자 소유의 페르소나를 조회합니다.
    존재하지 않거나 다른 사용자의 것이면 404 에러를 발생시킵니다.
    """
    persona = db.query(PersonaDB).filter(
        PersonaDB.id == persona_id,
        PersonaDB.user_id == user_id,
    ).first()
    if not persona:
        raise HTTPException(status_code=404, detail="Persona not found")
    return persona


def _get_or_create_session(db: Session, persona_id: str, session_id: str = None) -> ChatSessionDB:
    """
    지정된 세션을 가져오거나, session_id가 없으면 가장 최근 세션을 반환합니다.
    세션이 하나도 없으면 새로 생성합니다.
    """
    if session_id:
        session = (
            db.query(ChatSessionDB)
            .filter(
                ChatSessionDB.id == session_id,
                ChatSessionDB.persona_id == persona_id,
            )
            .first()
        )
        if session:
            return session
        # session_id가 유효하지 않으면 최근 세션으로 폴백

    session = (
        db.query(ChatSessionDB)
        .filter(ChatSessionDB.persona_id == persona_id)
        .order_by(ChatSessionDB.created_at.desc())
        .first()
    )
    if not session:
        session = ChatSessionDB(persona_id=persona_id, title="Default Chat")
        db.add(session)
        db.commit()
        db.refresh(session)
    return session


# ─── 엔드포인트 ──────────────────────────────────────────

@router.get("", response_model=dict)
async def list_personas(
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """현재 사용자의 모든 페르소나 목록을 반환합니다."""
    user_id = user.get("sub")
    personas = db.query(PersonaDB).filter(PersonaDB.user_id == user_id).all()
    return {"personas": [_persona_to_response(p) for p in personas]}


@router.post("", response_model=PersonaResponse)
async def create_persona(
    body: PersonaCreate,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """새 페르소나를 생성합니다."""
    user_id = _ensure_user_exists(db, user)
    persona = PersonaDB(
        user_id=user_id,
        name=body.name,
        description=body.description or "",
    )
    db.add(persona)
    db.commit()
    db.refresh(persona)
    return _persona_to_response(persona)


@router.get("/{persona_id}", response_model=PersonaResponse)
async def get_persona(
    persona_id: str,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """페르소나 상세 정보를 반환합니다."""
    persona = _get_user_persona(db, persona_id, user.get("sub"))
    return _persona_to_response(persona)


@router.delete("/{persona_id}")
async def delete_persona(
    persona_id: str,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """페르소나와 관련된 모든 데이터(파일, 대화, 벡터)를 삭제합니다."""
    persona = _get_user_persona(db, persona_id, user.get("sub"))

    # Qdrant 벡터 삭제 (DB 삭제 전에 수행)
    try:
        rag_service.delete_persona_vectors(persona.id)
    except Exception as e:
        logger.warning("[Delete] Qdrant 벡터 삭제 실패 (무시): %s", e)

    # Redis 캐시 무효화
    await redis_cache.invalidate_persona(persona.id)

    db.delete(persona)
    db.commit()
    return {"message": "Persona deleted"}


@router.post("/{persona_id}/upload")
async def upload_file(
    persona_id: str,
    file: UploadFile = File(...),
    file_type: str = Form("unknown"),
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    페르소나에 파일을 업로드합니다.

    파일 내용을 텍스트로 추출 → 청킹 → 임베딩 → Qdrant에 벡터 저장합니다.
    지원 형식: PDF, TXT, MD, CSV 등
    """
    persona = _get_user_persona(db, persona_id, user.get("sub"))

    # 메타데이터 DB 저장
    uploaded_file = UploadedFileDB(
        persona_id=persona.id,
        filename=file.filename or "unknown",
        file_type=file_type,
    )
    db.add(uploaded_file)
    db.commit()
    db.refresh(uploaded_file)

    # 파일 바이트 읽기
    file_bytes = await file.read()

    # RAG 파이프라인: 텍스트 추출 → 청킹 → 임베딩 → Qdrant 저장
    try:
        chunk_count = await rag_service.process_and_store(
            persona_id=persona.id,
            file_bytes=file_bytes,
            filename=uploaded_file.filename,
            file_id=uploaded_file.id,
        )
    except Exception as e:
        logger.error("[Upload] 벡터 임베딩 실패: %s — %s", uploaded_file.filename, e)
        # 메타데이터는 유지하되 임베딩 실패를 알림
        return {
            "file_id": uploaded_file.id,
            "message": f"파일 '{uploaded_file.filename}' 업로드됨 (임베딩 실패: {e})",
            "chunk_count": 0,
        }

    # 문서가 변경되었으므로 해당 페르소나 캐시 무효화
    await redis_cache.invalidate_persona(persona.id)

    return {
        "file_id": uploaded_file.id,
        "message": f"파일 '{uploaded_file.filename}' — {chunk_count}개 청크 벡터화 완료",
        "chunk_count": chunk_count,
    }


@router.delete("/{persona_id}/files/{file_id}")
async def delete_file(
    persona_id: str,
    file_id: str,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """페르소나의 업로드 파일을 삭제합니다. Qdrant 벡터도 함께 삭제됩니다."""
    persona = _get_user_persona(db, persona_id, user.get("sub"))

    uploaded_file = (
        db.query(UploadedFileDB)
        .filter(UploadedFileDB.id == file_id, UploadedFileDB.persona_id == persona.id)
        .first()
    )
    if not uploaded_file:
        raise HTTPException(status_code=404, detail="File not found")

    # Qdrant에서 해당 file_id의 벡터 삭제
    try:
        rag_service.delete_file_vectors(file_id)
    except Exception as e:
        logger.warning("[Delete] 파일 벡터 삭제 실패 (무시): %s", e)

    # Redis 캐시 무효화
    await redis_cache.invalidate_persona(persona.id)

    db.delete(uploaded_file)
    db.commit()
    return {"message": f"파일 '{uploaded_file.filename}' 삭제 완료"}


@router.get("/{persona_id}/files")
async def list_files(
    persona_id: str,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """페르소나에 업로드된 파일 목록을 반환합니다."""
    persona = _get_user_persona(db, persona_id, user.get("sub"))
    files = db.query(UploadedFileDB).filter(UploadedFileDB.persona_id == persona.id).all()
    return {
        "files": [
            {
                "id": f.id,
                "filename": f.filename,
                "file_type": f.file_type,
                "created_at": f.uploaded_at.isoformat() if f.uploaded_at else None,
            }
            for f in files
        ]
    }


@router.post("/{persona_id}/ask", response_model=MessageResponse)
async def ask_persona(
    persona_id: str,
    body: dict,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    페르소나에게 질문을 보내고 AI 응답을 받습니다.

    RAG 파이프라인: Qdrant 검색 → 문맥 구성 → Ollama LLM 추론 → 전체 응답 반환
    """
    persona = _get_user_persona(db, persona_id, user.get("sub"))
    question = body.get("question", "")
    session_id = body.get("session_id")

    # 대화 세션 획득 (없으면 자동 생성)
    session = _get_or_create_session(db, persona.id, session_id)

    # 사용자 메시지 저장
    user_msg = MessageDB(
        session_id=session.id,
        content=question,
        is_user=True,
    )
    db.add(user_msg)
    db.commit()
    db.refresh(user_msg)

    # RAG 파이프라인으로 AI 응답 생성
    try:
        ai_content = await rag_service.query(
            persona_id=persona.id,
            question=question,
            persona_name=persona.name,
        )
    except Exception as e:
        logger.error("[Ask] RAG 질의 실패: %s", e)
        ai_content = f"죄송합니다, 응답 생성 중 오류가 발생했습니다: {e}"

    # AI 응답 저장
    ai_msg = MessageDB(
        session_id=session.id,
        content=ai_content,
        is_user=False,
    )
    db.add(ai_msg)
    db.commit()
    db.refresh(ai_msg)

    # 검색 품질 평가 로깅 (비동기적으로 실패해도 응답에 영향 없음)
    try:
        retrieve_results = await rag_service.retrieve(persona.id, question)
        scores = [r["score"] for r in retrieve_results if isinstance(r, dict) and "score" in r]
        if scores:
            evaluation = RagEvaluationDB(
                message_id=ai_msg.id,
                persona_id=persona.id,
                question=question,
                avg_similarity=sum(scores) / len(scores),
                min_similarity=min(scores),
                max_similarity=max(scores),
                num_chunks=len(scores),
            )
            db.add(evaluation)
            db.commit()
    except Exception as e:
        logger.warning("[Eval] 평가 로깅 실패: %s", e)

    return MessageResponse(
        id=ai_msg.id,
        content=ai_msg.content,
        is_user=False,
        timestamp=ai_msg.created_at.isoformat(),
        persona_id=persona.id,
    )


@router.get("/{persona_id}/ask/stream")
async def ask_persona_stream(
    persona_id: str,
    question: str = Query(..., description="사용자 질문"),
    session_id: Optional[str] = Query(None, description="대화 세션 ID"),
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    페르소나에게 질문을 보내고 SSE 스트리밍으로 응답을 받습니다.

    Server-Sent Events 형식으로 토큰 단위 실시간 응답을 전송합니다.
    프론트엔드에서 EventSource 또는 Dio stream으로 수신합니다.
    """
    persona = _get_user_persona(db, persona_id, user.get("sub"))

    # 대화 세션 획득
    session = _get_or_create_session(db, persona.id, session_id)

    # 사용자 메시지 저장
    user_msg = MessageDB(
        session_id=session.id,
        content=question,
        is_user=True,
    )
    db.add(user_msg)
    db.commit()
    db.refresh(user_msg)

    async def event_generator():
        """SSE 이벤트 생성기 — 단계별 상태 + 토큰 단위 data: 라인 전송"""
        collected = []
        retrieve_results = []
        try:
            # 1단계: 문서 검색
            yield "data: [STATUS] 문서 검색 중...\n\n"
            retrieve_results = await rag_service.retrieve(persona.id, question)

            # 2단계: 응답 생성
            yield "data: [STATUS] 응답 생성 중...\n\n"
            prompt = rag_service._build_prompt(question, retrieve_results, persona.name)
            stream = ollama_client.chat(
                model=LLM_MODEL,
                messages=[{"role": "user", "content": prompt}],
                stream=True,
            )
            for chunk in stream:
                token = chunk["message"]["content"]
                if token:
                    collected.append(token)
                    yield f"data: {token}\n\n"

            # 스트림 완료 후 전체 응답을 DB에 저장
            full_response = "".join(collected)
            ai_msg = MessageDB(
                session_id=session.id,
                content=full_response,
                is_user=False,
            )
            db.add(ai_msg)
            db.commit()
            db.refresh(ai_msg)

            # 검색 품질 평가 로깅
            try:
                scores = [r["score"] for r in retrieve_results if isinstance(r, dict) and "score" in r]
                if scores:
                    evaluation = RagEvaluationDB(
                        message_id=ai_msg.id,
                        persona_id=persona.id,
                        question=question,
                        avg_similarity=sum(scores) / len(scores),
                        min_similarity=min(scores),
                        max_similarity=max(scores),
                        num_chunks=len(scores),
                    )
                    db.add(evaluation)
                    db.commit()
            except Exception as eval_err:
                logger.warning("[Eval] 스트리밍 평가 로깅 실패: %s", eval_err)

            # 완료 이벤트 전송
            yield "data: [DONE]\n\n"
        except Exception as e:
            logger.error("[Stream] RAG 스트리밍 실패: %s", e)
            yield f"data: [ERROR] {e}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/{persona_id}/history")
async def get_chat_history(
    persona_id: str,
    session_id: Optional[str] = Query(None, description="대화 세션 ID (없으면 최근 세션)"),
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    페르소나의 대화 기록을 반환합니다.

    session_id가 지정되면 해당 세션, 없으면 가장 최근 세션의 메시지를 반환합니다.
    """
    persona = _get_user_persona(db, persona_id, user.get("sub"))
    session = _get_or_create_session(db, persona.id, session_id)

    messages = (
        db.query(MessageDB)
        .filter(MessageDB.session_id == session.id)
        .order_by(MessageDB.created_at.asc())
        .all()
    )

    return {
        "session_id": session.id,
        "messages": [
            {
                "id": msg.id,
                "content": msg.content,
                "is_user": msg.is_user,
                "timestamp": msg.created_at.isoformat(),
                "persona_id": persona.id,
            }
            for msg in messages
        ]
    }


# ─── 세션 관리 엔드포인트 ────────────────────────────────

@router.get("/{persona_id}/sessions", response_model=dict)
async def list_sessions(
    persona_id: str,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """페르소나의 모든 대화 세션 목록을 반환합니다 (최신순)."""
    persona = _get_user_persona(db, persona_id, user.get("sub"))

    sessions = (
        db.query(ChatSessionDB)
        .filter(ChatSessionDB.persona_id == persona.id)
        .order_by(ChatSessionDB.created_at.desc())
        .all()
    )

    return {
        "sessions": [
            SessionResponse(
                id=s.id,
                title=s.title,
                created_at=s.created_at.isoformat(),
                message_count=len(s.messages),
            ).model_dump()
            for s in sessions
        ]
    }


@router.post("/{persona_id}/sessions", response_model=SessionResponse)
async def create_session(
    persona_id: str,
    body: dict = None,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """새 대화 세션을 생성합니다."""
    persona = _get_user_persona(db, persona_id, user.get("sub"))

    title = (body or {}).get("title", "New Chat")
    session = ChatSessionDB(persona_id=persona.id, title=title)
    db.add(session)
    db.commit()
    db.refresh(session)

    return SessionResponse(
        id=session.id,
        title=session.title,
        created_at=session.created_at.isoformat(),
        message_count=0,
    )


@router.delete("/{persona_id}/sessions/{session_id}")
async def delete_session(
    persona_id: str,
    session_id: str,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """대화 세션과 해당 메시지를 삭제합니다."""
    persona = _get_user_persona(db, persona_id, user.get("sub"))

    session = (
        db.query(ChatSessionDB)
        .filter(
            ChatSessionDB.id == session_id,
            ChatSessionDB.persona_id == persona.id,
        )
        .first()
    )
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    db.delete(session)
    db.commit()
    return {"message": "Session deleted"}


@router.put("/{persona_id}/sessions/{session_id}")
async def update_session(
    persona_id: str,
    session_id: str,
    body: dict,
    user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """대화 세션 제목을 수정합니다."""
    persona = _get_user_persona(db, persona_id, user.get("sub"))

    session = (
        db.query(ChatSessionDB)
        .filter(
            ChatSessionDB.id == session_id,
            ChatSessionDB.persona_id == persona.id,
        )
        .first()
    )
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    title = body.get("title")
    if title:
        session.title = title
        db.commit()
        db.refresh(session)

    return SessionResponse(
        id=session.id,
        title=session.title,
        created_at=session.created_at.isoformat(),
        message_count=len(session.messages),
    )
