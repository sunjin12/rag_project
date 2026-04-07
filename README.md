# RAG Chat Project

**Retrieval-Augmented Generation** 기반의 AI 채팅 애플리케이션입니다.

사용자가 직접 AI 페르소나를 생성하고, 문서(PDF/텍스트/오디오)를 업로드한 뒤,
해당 문서를 기반으로 질의응답(Q&A)을 할 수 있는 풀스택 프로젝트입니다.

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Client (Desktop)                   │
│  Google OAuth → Provider 상태관리 → Dio HTTP → SSE 스트리밍   │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTP / SSE
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                   FastAPI Gateway (Python)                    │
│  JWT 인증 → LangChain RAG 파이프라인 → SSE StreamingResponse  │
└──────┬──────────┬──────────┬──────────┬─────────────────────┘
       │          │          │          │
       ▼          ▼          ▼          ▼
   PostgreSQL   Qdrant     Redis     Ollama
   (대화기록)  (벡터DB)   (캐시)    (LLM 추론)
```

### 기술 스택

| 레이어 | 기술 |
|--------|------|
| **프론트엔드** | Flutter/Dart, Provider, Dio, Google Sign-In |
| **백엔드** | FastAPI, SQLAlchemy, Pydantic, LangChain |
| **데이터베이스** | PostgreSQL 15 (대화 기록), Qdrant (벡터), Redis 7 (캐시) |
| **AI/ML** | Ollama + qwen2.5:7b (LLM), BGE-M3 (임베딩), sentence-transformers |
| **인증** | Google OAuth 2.0, JWT (HS256) |
| **인프라** | Docker Compose, NVIDIA GPU 가속 |

---

## 프로젝트 구조

```
rag_project/
├── rag_backend/                 # FastAPI 백엔드
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py              # 앱 엔트리포인트, CORS, 라이프사이클
│   │   ├── config.py            # pydantic-settings 환경 설정
│   │   ├── auth.py              # JWT + Google OAuth 유틸리티
│   │   ├── database.py          # SQLAlchemy ORM 모델 + 세션 관리
│   │   ├── models.py            # Pydantic 요청/응답 스키마
│   │   ├── rag_service.py       # RAG 파이프라인 (임베딩, Qdrant, Ollama)
│   │   ├── cache.py             # Redis 캐시 서비스
│   │   └── routes/
│   │       ├── auth.py          # /auth/* 인증 엔드포인트
│   │       └── personas.py      # /personas/* CRUD + 채팅 + 파일 관리
│   ├── docker-compose.yml       # 개발용 (Ollama GPU, Qdrant, PostgreSQL, Redis)
│   ├── docker-compose.prod.yml  # 프로덕션용 (Nginx + SSL)
│   ├── Dockerfile
│   ├── nginx/                   # Nginx 리버스 프록시 설정
│   ├── requirements.txt
│   ├── .env.example             # 환경 변수 템플릿
│   └── .env                     # 실제 환경 변수 (git 제외)
│
├── rag_frontend/                # Flutter 프론트엔드
│   ├── lib/
│   │   ├── main.dart            # 앱 진입점, Provider DI 설정
│   │   ├── config/
│   │   │   └── app_config.dart  # 환경별 API URL, OAuth 설정
│   │   ├── models/
│   │   │   ├── user_model.dart
│   │   │   ├── persona_model.dart
│   │   │   ├── message_model.dart
│   │   │   └── session_model.dart
│   │   ├── providers/
│   │   │   ├── auth_provider.dart     # 인증 상태 관리
│   │   │   ├── chat_provider.dart     # 채팅 상태 관리
│   │   │   └── persona_provider.dart  # 페르소나 상태 관리
│   │   ├── services/
│   │   │   ├── api_service.dart       # Dio HTTP 클라이언트
│   │   │   └── auth_service.dart      # Google OAuth 흐름
│   │   ├── screens/
│   │   │   ├── login_screen.dart
│   │   │   ├── home_screen.dart
│   │   │   ├── create_persona_screen.dart
│   │   │   └── chat_screen.dart
│   │   ├── widgets/
│   │   │   ├── message_bubble.dart
│   │   │   └── file_upload_widget.dart
│   │   └── theme/
│   │       └── app_theme.dart
│   └── pubspec.yaml
│
├── .gitignore
└── README.md
```

---

## 시작하기

### 사전 요구사항

- **Python** 3.10+
- **Flutter** 3.11+
- **Docker** & **Docker Compose** (APT Docker CE 권장)
- **NVIDIA GPU** + **nvidia-container-toolkit** (GPU 가속 사용 시)
- **Google Cloud Console** 프로젝트 (OAuth 2.0 클라이언트 ID)

### 1. 인프라 서비스 실행

```bash
cd rag_backend
docker compose up -d
```

이 명령으로 다음 서비스가 시작됩니다:

| 서비스 | 포트 | 설명 |
|--------|------|------|
| Ollama | 11434 | LLM 추론 엔진 (GPU 가속) |
| Qdrant | 6333 | 벡터 데이터베이스 |
| PostgreSQL | 5432 | 대화 기록 저장 |
| Redis | 6380 | 세션 캐시 |

```bash
# LLM 모델 다운로드
docker exec rag_ollama ollama pull qwen2.5:7b
```

### 2. 백엔드 설정

```bash
cd rag_backend

# 환경 변수 설정
cp .env.example .env
# .env 파일을 열어 Google OAuth 정보와 SECRET_KEY를 수정하세요

# Python 가상환경 생성
python -m venv .venv
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate   # Windows

# 의존성 설치
pip install -r requirements.txt

# 서버 실행
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

> **주의 (WSL 환경)**: `/mnt/c/` 등 cross-filesystem에서는 `--reload` 옵션이 파일 변경을 감지하지 못합니다.
> 코드 수정 후 수동으로 서버를 재시작하세요.

서버 시작 시 PostgreSQL에 테이블이 자동 생성됩니다.
API 문서: http://localhost:8000/docs

### 3. 프론트엔드 설정

```bash
cd rag_frontend
flutter pub get
flutter run -d windows
```

### 4. Google OAuth 설정

1. [Google Cloud Console](https://console.cloud.google.com/) 접속
2. OAuth 2.0 클라이언트 ID 생성 (웹 애플리케이션 유형)
3. 승인된 리디렉션 URI에 `http://127.0.0.1:4242/callback` 추가
4. 발급된 클라이언트 ID와 시크릿을 `.env` 파일에 입력

---

## 환경 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `SECRET_KEY` | JWT 서명 키 (반드시 변경) | `change-this-...` |
| `GOOGLE_WEB_CLIENT_ID` | Google OAuth 웹 클라이언트 ID | - |
| `GOOGLE_CLIENT_SECRET` | Google OAuth 클라이언트 시크릿 | - |
| `POSTGRES_URL` | PostgreSQL 연결 문자열 | `postgresql://admin:adminpassword@localhost:5432/rag_history` |
| `REDIS_URL` | Redis 연결 문자열 | `redis://localhost:6380` |
| `OLLAMA_URL` | Ollama 서버 URL | `http://localhost:11434` |
| `QDRANT_URL` | Qdrant 서버 URL | `http://localhost:6333` |
| `CORS_ORIGINS` | CORS 허용 도메인 (콤마 구분) | `*` |

---

## API 엔드포인트

### 인증

| Method | Path | 설명 |
|--------|------|------|
| POST | `/auth/google` | Google ID 토큰 로그인 (모바일) |
| POST | `/auth/code` | Google Authorization Code 로그인 (데스크톱) |

### 페르소나

| Method | Path | 설명 |
|--------|------|------|
| GET | `/personas` | 내 페르소나 목록 |
| POST | `/personas` | 페르소나 생성 |
| GET | `/personas/{id}` | 페르소나 상세 |
| DELETE | `/personas/{id}` | 페르소나 삭제 |

### 파일 관리

| Method | Path | 설명 |
|--------|------|------|
| POST | `/personas/{id}/upload` | 파일 업로드 (PDF/TXT/MD/CSV) |
| GET | `/personas/{id}/files` | 업로드된 파일 목록 조회 |
| DELETE | `/personas/{id}/files/{file_id}` | 파일 삭제 (벡터 포함) |

### 채팅

| Method | Path | 설명 |
|--------|------|------|
| POST | `/personas/{id}/ask` | 질문 전송 (전체 응답) |
| GET | `/personas/{id}/ask/stream` | SSE 스트리밍 질문 전송 |
| GET | `/personas/{id}/history` | 대화 기록 조회 |

### 대화 세션

| Method | Path | 설명 |
|--------|------|------|
| GET | `/personas/{id}/sessions` | 세션 목록 |
| POST | `/personas/{id}/sessions` | 새 세션 생성 |
| DELETE | `/personas/{id}/sessions/{sid}` | 세션 삭제 |

### 시스템

| Method | Path | 설명 |
|--------|------|------|
| GET | `/health` | 헬스 체크 |
| GET | `/docs` | Swagger UI 문서 |

---

## 데이터베이스 스키마

```
users ──1:N──▶ personas ──1:N──▶ chat_sessions ──1:N──▶ messages
                   │
                   └──1:N──▶ uploaded_files
```

| 테이블 | 설명 |
|--------|------|
| `users` | Google OAuth 인증 사용자 |
| `personas` | AI 페르소나 (RAG 컨텍스트 단위) |
| `uploaded_files` | 업로드 파일 메타데이터 |
| `chat_sessions` | 대화 세션 |
| `messages` | 개별 메시지 (질문/응답) |

---

## 주요 기능

### RAG 파이프라인
1. **문서 업로드** → PyMuPDF/텍스트 추출 → 청크 분할
2. **임베딩** → BGE-M3 (sentence-transformers) → Qdrant 벡터 저장
3. **질의** → 유사도 검색 → 컨텍스트 주입 → Ollama LLM 응답 생성
4. **스트리밍** → SSE로 토큰 단위 실시간 응답

### 채팅 UX
- **Enter** = 메시지 전송, **Shift+Enter** = 줄바꿈
- SSE 스트리밍으로 실시간 응답 렌더링
- 메시지 텍스트 선택/복사 가능 (SelectableText)
- 다중 대화 세션 관리 (사이드 드로어)
- Redis 캐시를 통한 응답 캐싱

### 파일 관리
- 다중 파일 동시 업로드 (PDF, TXT, MD, CSV)
- 파일 목록 조회 및 개별 삭제
- 파일 삭제 시 Qdrant 벡터도 함께 정리

### GPU 가속
- Docker Compose에서 NVIDIA GPU 런타임 설정
- Ollama 컨테이너가 GPU를 활용하여 LLM 추론 가속
- 오디오 파일 STT 변환 (faster-whisper, GPU 지원)

---

## 구현 상태

### 완료 ✅

- [x] Google OAuth 2.0 인증 (Authorization Code 방식)
- [x] JWT 토큰 발급 및 검증
- [x] PostgreSQL 기반 사용자/페르소나/대화 저장
- [x] 페르소나 CRUD API
- [x] 대화 기록 및 다중 세션 관리
- [x] 파일 업로드 (PDF/TXT/MD/CSV) → 벡터 임베딩 저장
- [x] 파일 목록 조회 및 삭제 (벡터 정리 포함)
- [x] RAG 파이프라인 (Qdrant 검색 → 컨텍스트 주입 → Ollama 응답)
- [x] SSE 스트리밍 응답 + Flutter 실시간 렌더링
- [x] 한국어 LLM 지원 (qwen2.5:7b) + UTF-8 스트리밍
- [x] NVIDIA GPU 가속 (Docker + nvidia-container-toolkit)
- [x] Redis 캐시
- [x] 오디오 파일 STT (faster-whisper)
- [x] Enter=전송 / Shift+Enter=줄바꿈
- [x] 메시지 텍스트 선택/복사
- [x] 다중 파일 업로드 스크롤 UI
- [x] Flutter 데스크톱 앱 (Windows)
- [x] 프로덕션 배포 설정 (Docker Compose + Nginx)

---

## 개발 환경

| 구성 요소 | 버전/사양 |
|-----------|-----------|
| Python | 3.12 |
| Flutter | 3.11+ |
| Docker CE | 29.3+ (APT 설치) |
| GPU | NVIDIA RTX 2060 6GB |
| LLM | qwen2.5:7b (Ollama) |
| 임베딩 모델 | BAAI/bge-m3 |
| OS | Windows 11 + WSL2 (Ubuntu) |

---

## 라이선스

이 프로젝트는 학습/개인 프로젝트 목적으로 작성되었습니다.
