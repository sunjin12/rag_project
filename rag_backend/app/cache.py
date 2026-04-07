"""
Redis 캐시 모듈

Qdrant 검색 결과 캐싱으로 동일 질문 반복 시 응답 속도를 개선합니다.

캐시 전략:
  - 키: persona_id:question_hash → 검색된 context chunks (JSON)
  - TTL: 1시간 (문서 업로드 시 해당 페르소나 캐시 무효화)
  - 문서 업로드/삭제 시 해당 페르소나의 캐시를 모두 삭제

사용 예시:
    from app.cache import redis_cache
    await redis_cache.connect()
    cached = await redis_cache.get_context("pid", "question")
    await redis_cache.set_context("pid", "question", ["chunk1", "chunk2"])
"""

import hashlib
import json
import logging
from typing import Optional

import redis.asyncio as aioredis

from .config import settings

logger = logging.getLogger(__name__)

CACHE_TTL = 3600  # 1시간
CONTEXT_PREFIX = "rag:ctx:"
PERSONA_PREFIX = "rag:persona:"


class RedisCache:
    """비동기 Redis 캐시 클라이언트"""

    def __init__(self):
        self._redis: Optional[aioredis.Redis] = None

    async def connect(self):
        """Redis 연결 초기화"""
        try:
            self._redis = aioredis.from_url(
                settings.redis_url,
                decode_responses=True,
                socket_connect_timeout=5,
            )
            await self._redis.ping()
            logger.info("[Cache] Redis 연결 성공: %s", settings.redis_url)
        except Exception as e:
            logger.warning("[Cache] Redis 연결 실패 (캐시 비활성화): %s", e)
            self._redis = None

    async def disconnect(self):
        """Redis 연결 종료"""
        if self._redis:
            await self._redis.close()
            self._redis = None
            logger.info("[Cache] Redis 연결 종료")

    @property
    def available(self) -> bool:
        return self._redis is not None

    @staticmethod
    def _context_key(persona_id: str, question: str) -> str:
        """컨텍스트 캐시 키 생성"""
        q_hash = hashlib.sha256(question.encode()).hexdigest()[:16]
        return f"{CONTEXT_PREFIX}{persona_id}:{q_hash}"

    @staticmethod
    def _persona_pattern(persona_id: str) -> str:
        """페르소나별 캐시 키 패턴"""
        return f"{CONTEXT_PREFIX}{persona_id}:*"

    async def get_context(self, persona_id: str, question: str) -> Optional[list]:
        """캐시된 검색 컨텍스트 조회"""
        if not self._redis:
            return None
        try:
            key = self._context_key(persona_id, question)
            data = await self._redis.get(key)
            if data:
                logger.debug("[Cache] HIT: %s", key)
                return json.loads(data)
            return None
        except Exception as e:
            logger.warning("[Cache] 조회 실패: %s", e)
            return None

    async def set_context(self, persona_id: str, question: str, chunks: list):
        """검색 컨텍스트를 캐시에 저장"""
        if not self._redis:
            return
        try:
            key = self._context_key(persona_id, question)
            await self._redis.setex(key, CACHE_TTL, json.dumps(chunks, ensure_ascii=False))
            logger.debug("[Cache] SET: %s", key)
        except Exception as e:
            logger.warning("[Cache] 저장 실패: %s", e)

    async def invalidate_persona(self, persona_id: str):
        """페르소나의 모든 캐시를 삭제 (문서 업로드/삭제 시)"""
        if not self._redis:
            return
        try:
            pattern = self._persona_pattern(persona_id)
            cursor = 0
            deleted = 0
            while True:
                cursor, keys = await self._redis.scan(cursor, match=pattern, count=100)
                if keys:
                    await self._redis.delete(*keys)
                    deleted += len(keys)
                if cursor == 0:
                    break
            if deleted:
                logger.info("[Cache] 페르소나 캐시 삭제: %s (%d keys)", persona_id, deleted)
        except Exception as e:
            logger.warning("[Cache] 캐시 무효화 실패: %s", e)


# 싱글톤 인스턴스
redis_cache = RedisCache()
