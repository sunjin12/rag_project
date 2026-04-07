"""
RAG 서비스 모듈

문서 처리, 벡터 임베딩, 검색, LLM 추론을 담당합니다.

파이프라인:
  1. 문서 수집: PDF/텍스트 파일 → 텍스트 추출 (PyMuPDF)
  2. 청킹: 텍스트를 의미 단위로 분할 (RecursiveCharacterTextSplitter)
  3. 임베딩: 텍스트 청크 → 벡터 변환 (sentence-transformers / BGE-M3)
  4. 저장: 벡터 + 메타데이터 → Qdrant 컬렉션에 저장
  5. 검색: 사용자 질문 → 유사 벡터 검색(top-k) → 관련 문맥 추출
  6. 생성: 질문 + 검색 문맥 → Ollama LLM → 응답 생성 (스트리밍 지원)

사용 예시:
    from app.rag_service import rag_service
    # 파일 임베딩
    chunks = await rag_service.process_and_store(persona_id, file_bytes, filename)
    # RAG 질의
    answer = await rag_service.query(persona_id, "질문 내용")
    # 스트리밍 질의
    async for token in rag_service.query_stream(persona_id, "질문 내용"):
        print(token, end="")
"""

import io
import os
import uuid
import tempfile
import logging
from typing import AsyncGenerator

import fitz  # PyMuPDF
import ollama as ollama_client
from langchain_text_splitters import RecursiveCharacterTextSplitter
from qdrant_client import QdrantClient
from qdrant_client.models import (
    Distance,
    VectorParams,
    PointStruct,
    Filter,
    FieldCondition,
    MatchValue,
)
from sentence_transformers import SentenceTransformer

from .config import settings
from .cache import redis_cache

logger = logging.getLogger(__name__)

# ─── 상수 ─────────────────────────────────────────────────

EMBEDDING_MODEL_NAME = "BAAI/bge-m3"
EMBEDDING_DIMENSION = 1024  # BGE-M3 출력 차원
COLLECTION_NAME = "rag_documents"
CHUNK_SIZE = 512
CHUNK_OVERLAP = 64
TOP_K = 5
LLM_MODEL = settings.llm_model
AUDIO_EXTENSIONS = (".mp3", ".wav", ".m4a", ".ogg", ".flac", ".webm")
WHISPER_MODEL_SIZE = "base"  # tiny, base, small, medium, large-v3


# ─── RAG 서비스 ───────────────────────────────────────────

class RAGService:
    """RAG 파이프라인 전체를 관리하는 서비스 클래스"""

    def __init__(self):
        self._embedder: SentenceTransformer | None = None
        self._qdrant: QdrantClient | None = None
        self._whisper = None
        self._splitter = RecursiveCharacterTextSplitter(
            chunk_size=CHUNK_SIZE,
            chunk_overlap=CHUNK_OVERLAP,
            separators=["\n\n", "\n", ". ", " ", ""],
        )

    # ── 지연 초기화 (첫 사용 시 로드) ──────────────────────

    @property
    def embedder(self) -> SentenceTransformer:
        """임베딩 모델 — 첫 호출 시 다운로드/로드"""
        if self._embedder is None:
            logger.info("[RAG] 임베딩 모델 로드 중: %s", EMBEDDING_MODEL_NAME)
            self._embedder = SentenceTransformer(EMBEDDING_MODEL_NAME)
            logger.info("[RAG] 임베딩 모델 로드 완료")
        return self._embedder

    @property
    def qdrant(self) -> QdrantClient:
        """Qdrant 클라이언트 — 첫 호출 시 연결 & 컬렉션 생성"""
        if self._qdrant is None:
            logger.info("[RAG] Qdrant 연결: %s", settings.qdrant_url)
            self._qdrant = QdrantClient(url=settings.qdrant_url)
            self._ensure_collection()
        return self._qdrant

    def _ensure_collection(self):
        """Qdrant 컬렉션이 없으면 생성"""
        collections = [c.name for c in self._qdrant.get_collections().collections]
        if COLLECTION_NAME not in collections:
            self._qdrant.create_collection(
                collection_name=COLLECTION_NAME,
                vectors_config=VectorParams(
                    size=EMBEDDING_DIMENSION,
                    distance=Distance.COSINE,
                ),
            )
            logger.info("[RAG] Qdrant 컬렉션 생성: %s", COLLECTION_NAME)

    @property
    def whisper(self):
        """Whisper STT 모델 — 첫 호출 시 로드"""
        if self._whisper is None:
            from faster_whisper import WhisperModel
            logger.info("[RAG] Whisper 모델 로드 중: %s", WHISPER_MODEL_SIZE)
            self._whisper = WhisperModel(
                WHISPER_MODEL_SIZE,
                device="cpu",
                compute_type="int8",
            )
            logger.info("[RAG] Whisper 모델 로드 완료")
        return self._whisper

    # ── 1. 텍스트 추출 ────────────────────────────────────

    def extract_text(self, file_bytes: bytes, filename: str) -> str:
        """
        파일에서 텍스트를 추출합니다.

        지원 형식: PDF (.pdf), 텍스트 (.txt, .md, .csv), 오디오 (.mp3, .wav, .m4a 등)
        """
        lower = filename.lower()
        if lower.endswith(".pdf"):
            return self._extract_pdf(file_bytes)
        elif lower.endswith(AUDIO_EXTENSIONS):
            return self._extract_audio(file_bytes, filename)
        elif lower.endswith((".txt", ".md", ".csv", ".log", ".json")):
            return file_bytes.decode("utf-8", errors="replace")
        else:
            # 알 수 없는 형식은 바이너리를 텍스트로 디코딩 시도
            return file_bytes.decode("utf-8", errors="replace")

    def _extract_pdf(self, file_bytes: bytes) -> str:
        """PyMuPDF로 PDF → 텍스트 추출"""
        text_parts = []
        with fitz.open(stream=file_bytes, filetype="pdf") as doc:
            for page in doc:
                text_parts.append(page.get_text())
        return "\n".join(text_parts)

    def _extract_audio(self, file_bytes: bytes, filename: str) -> str:
        """faster-whisper로 오디오 → 텍스트 변환 (STT)"""
        ext = os.path.splitext(filename)[1] or ".wav"
        with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
            tmp.write(file_bytes)
            tmp_path = tmp.name

        try:
            logger.info("[RAG] 오디오 STT 시작: %s (%d bytes)", filename, len(file_bytes))
            segments, info = self.whisper.transcribe(tmp_path, beam_size=5)
            text_parts = [segment.text for segment in segments]
            full_text = " ".join(text_parts)
            logger.info(
                "[RAG] 오디오 STT 완료: %s (언어=%s, %.1f초, %d자)",
                filename, info.language, info.duration, len(full_text),
            )
            return full_text
        finally:
            os.unlink(tmp_path)

    # ── 2. 청킹 ──────────────────────────────────────────

    def chunk_text(self, text: str) -> list[str]:
        """텍스트를 의미 단위 청크로 분할"""
        chunks = self._splitter.split_text(text)
        return [c.strip() for c in chunks if c.strip()]

    # ── 3. 임베딩 + Qdrant 저장 ──────────────────────────

    async def process_and_store(
        self, persona_id: str, file_bytes: bytes, filename: str, file_id: str
    ) -> int:
        """
        파일을 처리하여 Qdrant에 벡터로 저장합니다.

        Returns:
            저장된 청크 수
        """
        # 텍스트 추출
        text = self.extract_text(file_bytes, filename)
        if not text.strip():
            logger.warning("[RAG] 빈 텍스트: %s", filename)
            return 0

        # 청킹
        chunks = self.chunk_text(text)
        if not chunks:
            return 0

        logger.info("[RAG] %s → %d 청크 생성", filename, len(chunks))

        # 임베딩 (CPU에서 배치 처리)
        vectors = self.embedder.encode(chunks, show_progress_bar=False).tolist()

        # Qdrant에 저장
        points = [
            PointStruct(
                id=str(uuid.uuid4()),
                vector=vec,
                payload={
                    "persona_id": persona_id,
                    "file_id": file_id,
                    "filename": filename,
                    "chunk_index": i,
                    "text": chunk,
                },
            )
            for i, (chunk, vec) in enumerate(zip(chunks, vectors))
        ]

        self.qdrant.upsert(collection_name=COLLECTION_NAME, points=points)
        logger.info("[RAG] Qdrant에 %d 벡터 저장 완료 (persona=%s)", len(points), persona_id)
        return len(points)

    # ── 4. 유사 문맥 검색 ─────────────────────────────────

    async def retrieve(self, persona_id: str, query: str, top_k: int = TOP_K) -> list[dict]:
        """
        질문과 유사한 문서 청크를 Qdrant에서 검색합니다.
        Redis 캐시가 있으면 캐시 우선 사용합니다.

        Returns:
            [{"text": str, "score": float}, ...] 유사도 순
        """
        # 캐시 확인
        cached = await redis_cache.get_context(persona_id, query)
        if cached is not None:
            return cached

        query_vec = self.embedder.encode(query).tolist()
        results = self.qdrant.query_points(
            collection_name=COLLECTION_NAME,
            query=query_vec,
            query_filter=Filter(
                must=[
                    FieldCondition(
                        key="persona_id",
                        match=MatchValue(value=persona_id),
                    )
                ]
            ),
            limit=top_k,
        )
        chunks = [
            {"text": hit.payload["text"], "score": hit.score}
            for hit in results.points if hit.payload
        ]

        # 캐시에 저장
        await redis_cache.set_context(persona_id, query, chunks)

        return chunks

    # ── 5. 프롬프트 구성 ──────────────────────────────────

    @staticmethod
    def _extract_texts(chunks: list[dict]) -> list[str]:
        """검색 결과에서 텍스트만 추출"""
        return [c["text"] if isinstance(c, dict) else c for c in chunks]

    @staticmethod
    def _build_prompt(question: str, context_chunks: list, persona_name: str) -> str:
        """RAG 프롬프트 생성 — 검색된 문맥 + 사용자 질문"""
        # dict(text+score) 또는 str 모두 지원
        texts = [
            c["text"] if isinstance(c, dict) else c for c in context_chunks
        ] if context_chunks else []
        if texts:
            context_block = "\n\n---\n\n".join(texts)
            return (
                f"당신은 '{persona_name}'이라는 AI 어시스턴트입니다.\n"
                f"아래의 참고 문서를 바탕으로 사용자의 질문에 답변하세요.\n"
                f"참고 문서에 관련 정보가 없으면 '관련 정보를 찾지 못했습니다'라고 답하세요.\n\n"
                f"=== 참고 문서 ===\n{context_block}\n\n"
                f"=== 질문 ===\n{question}\n\n"
                f"=== 답변 ===\n"
            )
        else:
            return (
                f"당신은 '{persona_name}'이라는 AI 어시스턴트입니다.\n"
                f"현재 업로드된 참고 문서가 없습니다.\n"
                f"일반 지식을 바탕으로 사용자의 질문에 답변하세요.\n\n"
                f"=== 질문 ===\n{question}\n\n"
                f"=== 답변 ===\n"
            )

    # ── 6. LLM 질의 (일반) ────────────────────────────────

    async def query(self, persona_id: str, question: str, persona_name: str = "AI") -> str:
        """
        RAG 파이프라인 전체 실행 — 검색 → 프롬프트 → LLM → 전체 응답 반환
        """
        results = await self.retrieve(persona_id, question)
        prompt = self._build_prompt(question, results, persona_name)

        response = ollama_client.chat(
            model=LLM_MODEL,
            messages=[{"role": "user", "content": prompt}],
        )
        return response["message"]["content"]

    # ── 7. LLM 질의 (스트리밍) ────────────────────────────

    async def query_stream(
        self, persona_id: str, question: str, persona_name: str = "AI"
    ) -> AsyncGenerator[str, None]:
        """
        RAG 파이프라인 + SSE 스트리밍 — 토큰 단위로 yield

        사용 예시:
            async for token in rag_service.query_stream(pid, "질문"):
                yield f"data: {token}\\n\\n"
        """
        results = await self.retrieve(persona_id, question)
        prompt = self._build_prompt(question, results, persona_name)

        stream = ollama_client.chat(
            model=LLM_MODEL,
            messages=[{"role": "user", "content": prompt}],
            stream=True,
        )
        for chunk in stream:
            token = chunk["message"]["content"]
            if token:
                yield token

    # ── 8. 페르소나 벡터 삭제 ─────────────────────────────

    def delete_persona_vectors(self, persona_id: str):
        """페르소나에 속한 모든 벡터를 Qdrant에서 삭제"""
        self.qdrant.delete(
            collection_name=COLLECTION_NAME,
            points_selector=Filter(
                must=[
                    FieldCondition(
                        key="persona_id",
                        match=MatchValue(value=persona_id),
                    )
                ]
            ),
        )
        logger.info("[RAG] 페르소나 벡터 삭제 완료: %s", persona_id)

    def delete_file_vectors(self, file_id: str):
        """특정 파일에 속한 벡터를 Qdrant에서 삭제"""
        self.qdrant.delete(
            collection_name=COLLECTION_NAME,
            points_selector=Filter(
                must=[
                    FieldCondition(
                        key="file_id",
                        match=MatchValue(value=file_id),
                    )
                ]
            ),
        )
        logger.info("[RAG] 파일 벡터 삭제 완료: %s", file_id)


# 싱글톤 인스턴스
rag_service = RAGService()
