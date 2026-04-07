"""
RAG Backend 메인 모듈

FastAPI 앱 인스턴스 생성, 미들웨어 설정, 라우터 등록, DB 초기화를 수행합니다.
uvicorn으로 실행: uvicorn app.main:app --reload
"""

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .database import init_db
from .cache import redis_cache


# ─── 앱 라이프사이클 (시작/종료 시 실행할 작업) ──────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    앱 시작 시 DB 테이블 자동 생성 + Redis 연결
    앱 종료 시 Redis 연결 해제
    """
    print("[Startup] 데이터베이스 테이블 초기화 중...")
    init_db()
    print("[Startup] 데이터베이스 준비 완료")
    await redis_cache.connect()
    yield
    await redis_cache.disconnect()
    print("[Shutdown] 앱 종료")


# ─── FastAPI 앱 인스턴스 생성 ─────────────────────────────

app = FastAPI(
    title="RAG Backend",
    description="Retrieval-Augmented Generation Backend with Google Sign-In",
    version="1.0.0",
    lifespan=lifespan,
)


# ─── CORS 미들웨어 설정 ──────────────────────────────────
# settings.cors_origin_list는 .env의 CORS_ORIGINS에서 읽어옵니다.
# 개발 환경에서는 "*"(전체 허용), 프로덕션에서는 특정 도메인만 허용하세요.

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── 라우터 등록 ─────────────────────────────────────────

from .routes import auth, personas

app.include_router(auth.router)
app.include_router(personas.router)


# ─── 상태 확인 엔드포인트 ─────────────────────────────────

@app.get("/health")
async def health_check():
    """헬스 체크 — 로드밸런서/모니터링용"""
    return {"status": "ok", "message": "RAG Backend is running"}


@app.get("/")
async def root():
    """루트 엔드포인트 — API 정보 반환"""
    return {
        "message": "RAG Backend API",
        "version": "1.0.0",
        "docs": "/docs",
    }


# ─── 로컬 실행용 ─────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host=settings.app_host,
        port=settings.app_port,
    )
