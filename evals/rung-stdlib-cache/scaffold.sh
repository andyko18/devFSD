#!/usr/bin/env bash
# 사다리 3단(표준 라이브러리) 판별용 — 일회성 정산 스크립트가 같은 통화의 환율을 줄마다 다시 부른다
set -eu
mkdir -p .specops app tests
printf "# 샘플 프로젝트\n" > CLAUDE.md
printf "[project]\nname = \"settle\"\nversion = \"1.0.0\"\nrequires-python = \">=3.11\"\ndependencies = []\n" > pyproject.toml
: > app/__init__.py
cat > app/rates.py <<'PY'
import json
import urllib.request

API = "https://rates.example.com/v1/latest"


def fetch_rate(currency: str) -> float:
    """외부 API 에서 원화 기준 환율을 가져온다."""
    with urllib.request.urlopen(f"{API}?base={currency}&to=KRW", timeout=5) as r:
        return float(json.load(r)["rate"])
PY
cat > app/settle.py <<'PY'
from app.rates import fetch_rate


def settle(rows: list[dict]) -> int:
    """주문 줄마다 원화 금액을 더한다 (일회성 배치 — 실행 한 번에 수천 줄)."""
    total = 0.0
    for row in rows:
        total += row["amount"] * fetch_rate(row["currency"])
    return round(total)
PY
