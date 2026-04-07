"""
RAG 검색 품질 리포트 생성기

rag_evaluations 테이블의 데이터를 기반으로 시각화 차트를 생성합니다.

생성 차트:
  1. 시간별 평균 유사도 추이 (라인 차트)
  2. 페르소나별 검색 품질 분포 (박스플롯)
  3. 저품질 검색 비율 추이 (유사도 < 0.3)

사용법:
    cd rag_backend
    python -m scripts.eval_report
    # 또는
    python scripts/eval_report.py
"""

import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# 프로젝트 루트를 path에 추가 (스크립트 직접 실행 시)
BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from sqlalchemy import func, case, text
from sqlalchemy.orm import Session
from app.database import SessionLocal, RagEvaluationDB, PersonaDB

# matplotlib 설정 (한글 폰트 + 비-GUI 백엔드)
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

plt.rcParams["font.family"] = "DejaVu Sans"
plt.rcParams["figure.dpi"] = 150
plt.rcParams["figure.figsize"] = (10, 5)

REPORTS_DIR = BACKEND_DIR / "reports"
LOW_QUALITY_THRESHOLD = 0.3


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def print_summary(db: Session):
    """터미널에 텍스트 요약 출력"""
    total = db.query(func.count(RagEvaluationDB.id)).scalar() or 0
    if total == 0:
        print("\n⚠  평가 데이터가 없습니다. 채팅을 먼저 진행하세요.\n")
        return False

    avg = db.query(func.avg(RagEvaluationDB.avg_similarity)).scalar() or 0
    low_count = db.query(func.count(RagEvaluationDB.id)).filter(
        RagEvaluationDB.avg_similarity < LOW_QUALITY_THRESHOLD
    ).scalar() or 0
    avg_chunks = db.query(func.avg(RagEvaluationDB.num_chunks)).scalar() or 0

    print("\n" + "=" * 50)
    print("  RAG 검색 품질 리포트")
    print("=" * 50)
    print(f"  총 평가 수       : {total}")
    print(f"  평균 유사도       : {avg:.4f}")
    print(f"  평균 청크 수      : {avg_chunks:.1f}")
    print(f"  저품질 비율       : {low_count}/{total} ({low_count / total * 100:.1f}%)")
    print(f"  저품질 임계값     : {LOW_QUALITY_THRESHOLD}")
    print("=" * 50 + "\n")
    return True


def chart_similarity_trend(db: Session):
    """차트 1: 시간별 평균 유사도 추이"""
    rows = (
        db.query(
            func.date(RagEvaluationDB.created_at).label("day"),
            func.avg(RagEvaluationDB.avg_similarity).label("avg_sim"),
            func.count(RagEvaluationDB.id).label("cnt"),
        )
        .group_by(func.date(RagEvaluationDB.created_at))
        .order_by(func.date(RagEvaluationDB.created_at))
        .all()
    )
    if not rows:
        return

    days = [r.day for r in rows]
    avgs = [r.avg_sim for r in rows]
    counts = [r.cnt for r in rows]

    fig, ax1 = plt.subplots()
    ax1.set_xlabel("Date")
    ax1.set_ylabel("Avg Similarity", color="tab:blue")
    ax1.plot(days, avgs, "o-", color="tab:blue", linewidth=2, markersize=6, label="Avg Similarity")
    ax1.tick_params(axis="y", labelcolor="tab:blue")
    ax1.set_ylim(0, 1)
    ax1.axhline(y=LOW_QUALITY_THRESHOLD, color="red", linestyle="--", alpha=0.5, label=f"Threshold ({LOW_QUALITY_THRESHOLD})")

    ax2 = ax1.twinx()
    ax2.set_ylabel("Query Count", color="tab:gray")
    ax2.bar(days, counts, alpha=0.2, color="tab:gray", label="Queries")
    ax2.tick_params(axis="y", labelcolor="tab:gray")

    ax1.legend(loc="upper left")
    fig.suptitle("RAG Search Quality Trend", fontweight="bold")
    fig.autofmt_xdate()
    plt.tight_layout()

    path = REPORTS_DIR / "similarity_trend.png"
    fig.savefig(path)
    plt.close(fig)
    print(f"  📊 {path}")


def chart_persona_distribution(db: Session):
    """차트 2: 페르소나별 검색 품질 분포 (박스플롯)"""
    rows = (
        db.query(
            PersonaDB.name.label("persona_name"),
            RagEvaluationDB.avg_similarity,
        )
        .join(PersonaDB, RagEvaluationDB.persona_id == PersonaDB.id)
        .all()
    )
    if not rows:
        return

    # 페르소나별로 그룹핑
    data = {}
    for r in rows:
        name = r.persona_name
        if name not in data:
            data[name] = []
        data[name].append(r.avg_similarity)

    labels = list(data.keys())
    values = [data[name] for name in labels]

    fig, ax = plt.subplots()
    bp = ax.boxplot(values, tick_labels=labels, patch_artist=True)
    for patch in bp["boxes"]:
        patch.set_facecolor("lightblue")
    ax.set_ylabel("Avg Similarity")
    ax.set_ylim(0, 1)
    ax.axhline(y=LOW_QUALITY_THRESHOLD, color="red", linestyle="--", alpha=0.5)
    ax.set_title("Search Quality by Persona", fontweight="bold")
    plt.xticks(rotation=30, ha="right")
    plt.tight_layout()

    path = REPORTS_DIR / "persona_distribution.png"
    fig.savefig(path)
    plt.close(fig)
    print(f"  📊 {path}")


def chart_low_quality_trend(db: Session):
    """차트 3: 저품질 검색 비율 추이"""
    rows = (
        db.query(
            func.date(RagEvaluationDB.created_at).label("day"),
            func.count(RagEvaluationDB.id).label("total"),
            func.sum(
                case(
                    (RagEvaluationDB.avg_similarity < LOW_QUALITY_THRESHOLD, 1),
                    else_=0,
                )
            ).label("low_count"),
        )
        .group_by(func.date(RagEvaluationDB.created_at))
        .order_by(func.date(RagEvaluationDB.created_at))
        .all()
    )
    if not rows:
        return

    days = [r.day for r in rows]
    ratios = [(r.low_count / r.total * 100) if r.total > 0 else 0 for r in rows]

    fig, ax = plt.subplots()
    ax.fill_between(days, ratios, alpha=0.3, color="red")
    ax.plot(days, ratios, "o-", color="red", linewidth=2, markersize=6)
    ax.set_xlabel("Date")
    ax.set_ylabel("Low Quality Rate (%)")
    ax.set_ylim(0, 100)
    ax.set_title(f"Low Quality Search Rate (similarity < {LOW_QUALITY_THRESHOLD})", fontweight="bold")
    fig.autofmt_xdate()
    plt.tight_layout()

    path = REPORTS_DIR / "low_quality_trend.png"
    fig.savefig(path)
    plt.close(fig)
    print(f"  📊 {path}")


def main():
    REPORTS_DIR.mkdir(exist_ok=True)
    db = SessionLocal()

    try:
        has_data = print_summary(db)
        if not has_data:
            return

        print("차트 생성 중...")
        chart_similarity_trend(db)
        chart_persona_distribution(db)
        chart_low_quality_trend(db)
        print(f"\n✅ 리포트 저장 완료: {REPORTS_DIR}/\n")
    finally:
        db.close()


if __name__ == "__main__":
    main()
