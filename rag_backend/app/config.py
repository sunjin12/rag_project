"""
환경 설정 모듈 (pydantic-settings 기반)

.env 파일 또는 시스템 환경변수에서 설정값을 읽어옵니다.
모든 설정은 Settings 인스턴스를 통해 접근하세요.

사용 예시:
    from app.config import settings
    print(settings.secret_key)
"""

from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    """
    애플리케이션 전역 설정

    .env 파일 또는 환경변수에서 자동으로 값을 읽습니다.
    환경변수가 .env 파일보다 우선합니다.
    """

    # --- 앱 서버 ---
    app_host: str = "0.0.0.0"
    app_port: int = 8000

    # --- 보안 ---
    secret_key: str = "change-this-to-a-random-secret-key"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 7 * 24 * 60  # 7일 (기존 30일에서 축소)

    # --- Google OAuth 2.0 ---
    google_web_client_id: str = ""
    google_android_client_id: str = ""
    google_client_secret: str = ""

    # --- PostgreSQL ---
    postgres_url: str = "postgresql://admin:adminpassword@localhost:5432/rag_history"

    # --- Redis ---
    redis_url: str = "redis://localhost:6380"

    # --- Ollama ---
    ollama_url: str = "http://localhost:11434"
    llm_model: str = "qwen3:8b"

    # --- Qdrant ---
    qdrant_url: str = "http://localhost:6333"

    # --- CORS ---
    cors_origins: str = "*"

    @property
    def cors_origin_list(self) -> List[str]:
        """CORS 허용 도메인 목록을 리스트로 반환"""
        if self.cors_origins == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",")]

    @property
    def valid_google_client_ids(self) -> List[str]:
        """유효한 Google Client ID 목록"""
        ids = []
        if self.google_web_client_id:
            ids.append(self.google_web_client_id)
        if self.google_android_client_id:
            ids.append(self.google_android_client_id)
        return ids

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


# 싱글톤 인스턴스 — 앱 전체에서 이 객체를 import하여 사용
settings = Settings()
