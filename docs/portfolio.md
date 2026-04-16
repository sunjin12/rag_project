# RAG Chat

사용자가 AI 페르소나를 생성하고, 문서(PDF/텍스트/오디오)를 업로드한 뒤,
해당 문서를 기반으로 질의응답(Q&A)을 할 수 있는 RAG 채팅 애플리케이션입니다.

| 구분 | 내용 |
|------|------|
| 개발 기간 | 2026.04.01 ~ 2026.04.07 |
| 개발 인원 | 1인 |
| 담당 역할 | 기획, 백엔드, 프론트엔드, 인프라 전체 |

---

## Overview: 프로젝트 개요

### 기획 배경 및 목표

사용자가 직접 업로드한 문서들을 바탕으로 특색있는 페르소나를 지닌 챗봇과 대화할 수 있는 RAG 파이프라인을 구축했습니다. 단일 봇이 아닌 **페르소나 단위로 문서 컨텍스트를 격리**하여, 용도별 전문 AI를 만들 수 있는 풀스택 프로젝트입니다.

### 핵심 기능

| 기능 | 설명 |
|------|------|
| 페르소나 생성 | 사용자가 직접 AI 페르소나를 생성하고 문서 컨텍스트를 격리 |
| RAG 기반 대화 | 업로드된 문서를 벡터 검색하여 근거 있는 답변 생성 |
| SSE 스트리밍 | 토큰 단위 실시간 스트리밍으로 자연스러운 대화 경험 |
| 다중 세션 관리 | 페르소나마다 독립된 대화 세션을 여러 개 유지 |
| 문서 업로드 | PDF, TXT, MD, CSV, 오디오 파일 지원 (오디오는 STT 변환) |
| Google 로그인 | OAuth 2.0 기반 인증, JWT로 모든 API 보호 |
| 품질 모니터링 | RAG 검색 유사도를 자동 기록하고 리포트로 시각화 |

---

### 기술 스택

| 레이어 | 기술 |
|--------|------|
| Frontend | Flutter Desktop (Windows), Provider, Dio, Google Sign-In |
| Backend API | FastAPI, Uvicorn, SQLAlchemy, Pydantic, LangChain |
| LLM | Ollama (qwen3:8b), NVIDIA GPU 가속 |
| Embedding | BAAI/bge-m3 (1024차원), sentence-transformers |
| Vector DB | Qdrant (COSINE similarity) |
| Database | PostgreSQL 15 (대화 기록), Redis 7 (캐시) |
| Auth | Google OAuth 2.0, JWT (HS256) |
| Infra | Docker Compose, NVIDIA Container Toolkit, Nginx (프로덕션) |

---

## System Architecture

### 시스템 구성도

![시스템 구성도](images/RAGChat시스템구성도.png)

### 데이터 흐름도

**문서 업로드 파이프라인**

![문서 업로드 파이프라인](images/RAGChat문서업로드.png)

**실시간 질의 파이프라인**

![실시간 질의 파이프라인](images/RAGChat실시간질의.png)

---

## 기술적 의사결정

### Qdrant — 벡터 데이터베이스

| 비교 항목 | Qdrant | Chroma | FAISS |
|-----------|--------|--------|-------|
| 운영 방식 | 독립 서버 (Docker) | 인메모리/로컬 파일 | 라이브러리 |
| 필터링 | 페이로드 기반 필터 지원 | 메타데이터 필터 | 별도 구현 필요 |
| 확장성 | 분산 클러스터 지원 | 제한적 | 없음 |
| 삭제 | 포인트 단위 삭제 가능 | 가능 | 인덱스 재빌드 필요 |

**선택 이유**: 페르소나별 벡터 격리가 핵심 요구사항이었습니다. Qdrant의 페이로드 필터(`persona_id`)로 컬렉션 하나에서 페르소나별 검색을 격리할 수 있고, 파일 삭제 시 해당 벡터만 포인트 단위로 제거할 수 있어 선택했습니다.

### Ollama + qwen3:8b — LLM 서빙

| 비교 항목 | Ollama + qwen3:8b | vLLM | OpenAI API |
|-----------|-------------------|------|------------|
| 비용 | 무료 (로컬) | 무료 (로컬) | 토큰 과금 |
| 한국어 성능 | 우수 (다국어 모델) | 모델에 따라 다름 | 최상 |
| GPU 요구 | 6GB VRAM 이상 | 16GB+ 권장 | 없음 |
| 설치 난이도 | Docker 한 줄 | 복잡 | API 키만 필요 |

**선택 이유**: 개인 개발 환경(RTX 2060 6GB)에서 운영 가능한 한국어 LLM이 필요했습니다. qwen3:8b는 6GB VRAM에서 구동 가능하면서 한국어 품질이 양호하고, Ollama를 통해 Docker 컨테이너 하나로 GPU 가속 서빙이 가능하여 선택했습니다.

### BGE-M3 — 임베딩 모델

| 비교 항목 | BGE-M3 | OpenAI text-embedding-3 | KoSimCSE |
|-----------|--------|--------------------------|----------|
| 다국어 지원 | 100+ 언어 | 다국어 | 한국어 특화 |
| 차원 | 1024 | 1536 / 3072 | 768 |
| 비용 | 무료 (로컬) | 토큰 과금 | 무료 (로컬) |
| 성능 | MTEB 상위권 | 최상위 | 한국어 우수 |

**선택 이유**: 한국어와 영어가 혼재된 문서를 처리해야 했습니다. BGE-M3는 다국어 임베딩에서 MTEB 벤치마크 상위권 성능을 보이면서, 로컬에서 무료로 사용할 수 있어 선택했습니다.

### Flutter Desktop — 프론트엔드

| 비교 항목 | Flutter Desktop | React (Web) | Electron |
|-----------|----------------|-------------|----------|
| 크로스 플랫폼 | Windows/macOS/Linux/Web | Web only | Windows/macOS/Linux |
| 번들 크기 | ~20MB | 수 MB | ~100MB+ |
| 네이티브 느낌 | Material 3 | 브라우저 의존 | Chromium 기반 |
| 학습 목적 | Dart + 모바일 확장 가능 | 익숙함 | JS/TS |

**선택 이유**: 데스크톱 네이티브 앱을 단일 코드베이스로 구현하면서, 향후 모바일(Android/iOS)로도 확장 가능한 프레임워크가 필요했습니다. Flutter는 Provider 기반의 깔끔한 상태 관리와 Dio를 통한 SSE 스트리밍 처리가 가능하여 선택했습니다.

---

## 주요 구현 상세

### RAG 파이프라인

```python
# 1. 문서 업로드 시: 텍스트 추출 → 청크 분할 → 임베딩 → 벡터 저장
텍스트 추출    →  PyMuPDF (PDF), 직접 읽기 (TXT/MD/CSV), faster-whisper (오디오)
청크 분할      →  RecursiveCharacterTextSplitter (512자, 64 오버랩)
임베딩         →  sentence-transformers (BGE-M3, 1024차원)
벡터 저장      →  Qdrant (COSINE, 페이로드에 persona_id/file_id 포함)

# 2. 질의 시: 임베딩 → 유사도 검색 → 컨텍스트 주입 → LLM 응답
질문 임베딩    →  동일 BGE-M3 모델
유사도 검색    →  Qdrant (Top-5, persona_id 필터)
프롬프트 구성  →  시스템 프롬프트 + 검색된 컨텍스트 + 대화 기록 + 사용자 질문
응답 생성      →  Ollama (qwen3:8b) 스트리밍
```

- Redis 캐시로 동일 질문 반복 시 LLM 호출 없이 즉시 응답
- 검색 유사도(avg/min/max)를 `rag_evaluations` 테이블에 자동 기록

### SSE 스트리밍

```
[클라이언트]                    [서버]
    │                              │
    │  GET /ask/stream?query=...   │
    │─────────────────────────────▶│
    │                              │  Qdrant 검색
    │  data: [STATUS] searching    │◀─────────────
    │◀─────────────────────────────│
    │                              │  Ollama 스트리밍 시작
    │  data: 안                    │◀─────────────
    │◀─────────────────────────────│
    │  data: 녕                    │
    │◀─────────────────────────────│
    │  data: 하                    │
    │◀─────────────────────────────│
    │  ...                         │
    │  data: [DONE]                │
    │◀─────────────────────────────│
```

- FastAPI `StreamingResponse`로 토큰 단위 SSE 전송
- `[STATUS]` 이벤트로 단계별 로딩 상태 전달 (검색 중 → 응답 생성 중)
- Flutter Dio의 `responseType: ResponseType.stream`으로 실시간 수신 및 렌더링

### 페르소나 격리 구조

```
페르소나 A                    페르소나 B
┌──────────────┐             ┌──────────────┐
│ 업로드 문서   │             │ 업로드 문서   │
│  doc1.pdf    │             │  spec.md     │
│  doc2.txt    │             │  data.csv    │
├──────────────┤             ├──────────────┤
│ Qdrant 벡터  │             │ Qdrant 벡터  │
│ (persona_id  │             │ (persona_id  │
│  = A 필터)   │             │  = B 필터)   │
├──────────────┤             ├──────────────┤
│ 대화 세션     │             │ 대화 세션     │
│  세션 1, 2   │             │  세션 1      │
├──────────────┤             ├──────────────┤
│ Redis 캐시   │             │ Redis 캐시   │
│ (persona:A:) │             │ (persona:B:) │
└──────────────┘             └──────────────┘
```

- 하나의 Qdrant 컬렉션에서 `persona_id` 페이로드 필터로 검색 범위 격리
- 페르소나 삭제 시 캐스케이드: PostgreSQL 레코드 + Qdrant 벡터 + Redis 캐시 일괄 정리
- 각 페르소나가 독립된 대화 맥락을 유지

### GPU 가속

| 컴포넌트 | GPU 활용 | 설정 |
|----------|---------|------|
| Ollama (LLM 추론) | NVIDIA GPU 전용 할당 | Docker `deploy.resources.reservations.devices` |
| faster-whisper (STT) | CUDA + int8 양자화 | `device="cuda"`, `compute_type="int8"` |
| sentence-transformers (임베딩) | CPU | 배치 인코딩, GPU 대비 충분한 속도 |

---

## 화면 구성

<!-- TODO: 스크린샷 추가 -->

| 화면 | 설명 |
|------|------|
| 로그인 | Google OAuth 2.0 로그인 |
| 홈 | 페르소나 목록, 생성/삭제 |
| 페르소나 생성 | 이름, 설명 입력 |
| 채팅 | SSE 스트리밍 대화, 세션 관리, 파일 업로드 |

---

## 데이터베이스 스키마

```
users ──1:N──▶ personas ──1:N──▶ chat_sessions ──1:N──▶ messages
                   │
                   └──1:N──▶ uploaded_files

rag_evaluations ──▶ messages (FK, nullable)
                ──▶ personas (FK)
```

| 테이블 | 설명 |
|--------|------|
| `users` | Google OAuth 인증 사용자 |
| `personas` | AI 페르소나 (RAG 컨텍스트 단위) |
| `uploaded_files` | 업로드 파일 메타데이터 |
| `chat_sessions` | 대화 세션 |
| `messages` | 개별 메시지 (질문/응답) |
| `rag_evaluations` | RAG 검색 품질 평가 로그 |

---

## 개발 환경

| 구성 요소 | 버전/사양 |
|-----------|-----------|
| Python | 3.12 |
| Flutter | 3.11+ |
| Docker CE | 29.3+ (APT 설치) |
| GPU | NVIDIA RTX 2060 6GB |
| LLM | qwen3:8b (Ollama) |
| 임베딩 모델 | BAAI/bge-m3 (1024차원) |
| OS | Windows 10 + WSL2 (Ubuntu) |

---

## 라이선스

이 프로젝트는 학습 및 개인 프로젝트 목적으로 작성되었습니다.
