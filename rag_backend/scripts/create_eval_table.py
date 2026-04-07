import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.database import engine, Base, RagEvaluationDB
from sqlalchemy import inspect

insp = inspect(engine)
if "rag_evaluations" not in insp.get_table_names():
    RagEvaluationDB.__table__.create(engine)
    print("rag_evaluations 테이블 생성 완료")
else:
    print("rag_evaluations 테이블 이미 존재")
