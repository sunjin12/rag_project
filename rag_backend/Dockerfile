FROM python:3.10-slim

# 시스템 의존성 설치 (ffmpeg: 오디오 처리용)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 작업 디렉토리 설정
WORKDIR /app

# 1. 먼저 requirements.txt를 명시적으로 복사 (경로 주의!)
# 현재 Dockerfile이 있는 위치에 requirements.txt가 있어야 합니다.
COPY requirements.txt /app/requirements.txt

# 2. 패키지 설치 (설치 과정을 로그로 보기 위해 --no-cache-dir 제거하고 실행)
RUN pip install -r /app/requirements.txt

# 3. 코드 복사 (어차피 volume으로 연결되지만 빌드 시점에 필요함)
COPY ./app /app

# Python 패키지 경로 설정
ENV PYTHONPATH=/app

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]