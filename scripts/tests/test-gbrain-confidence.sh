#!/usr/bin/env bash
# test-gbrain-confidence.sh — confidence 기록·가중 회귀 (20260807, 학습 루프 B)
#
# 실측 근거 (20260807):
#   learnings.jsonl 167건 중 confidence 기재는 **10건(6%)** 뿐이고,
#   그 10건은 **2026-06-29~30 이틀에 몰려** 있다. 7/1~7/24 는 0건.
#   원인은 "모델이 게을러서" 가 아니라 **문서화된 호출 예시 4곳이 전부
#   `--confidence` 를 빼고 있어서**다 — 모델은 예시를 그대로 복사한다.
#     performance-test-ko:316 (자동 경로) · using-specops-ko/freework-pending.md (freelog 자동 — 20260911 메타 skill 에서 이관) ·
#     gbrain-ko · commands/gbrain.md
#
#   2차 피해: `gbrain-recall.sh` 는 confidence 를 동점 가중치로 쓴다
#     (high 3 · medium 2 · low 1 · **미기재 0**).
#     미기재를 0으로 두면 **저자가 "확신 낮음"이라 명시한 인사이트가
#     아무 평가도 없는 인사이트보다 위로 올라간다** — 순위가 뒤집힌다.
#     94% 가 미기재라 이 역전이 코퍼스 대부분에 적용된다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
RECALL="$PLUGIN/scripts/gbrain-recall.sh"
APPEND="$PLUGIN/scripts/gbrain-append.sh"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ── T1: 문서화된 호출 예시가 --confidence 를 포함하는가 (근본 원인 잠금) ──
# 예시에 없으면 모델이 안 쓴다. 이게 6% 의 원인이므로 여기를 잠근다.
_ex() {  # $1=파일 $2=라벨
  local f="$PLUGIN/$1"
  # gbrain-append.sh 를 호출하는 줄마다 --confidence 가 붙어 있어야 한다
  #  (usage/주석 줄은 스크립트 자신뿐이라 대상 밖)
  # 실제 **호출 예시**만 대상 — 산문 언급(`gbrain-append.sh 경유만` 등)은 제외한다.
  #   판별: 인사이트 인자를 따옴표로 넘기는 형태(`gbrain-append.sh "`).
  local bad calls
  # 호출 예시 0건이면 "누락 없음" 은 아무것도 증명하지 않는다 — 예시가 다른 파일로 옮겨지면 무음 PASS 였다
  calls=$(grep -c 'gbrain-append\.sh "' "$f" 2>/dev/null || true)
  bad=$(grep -n 'gbrain-append\.sh "' "$f" 2>/dev/null | grep -v -- '--confidence' || true)
  if [ "${calls:-0}" -eq 0 ]; then
    nope "T1 $2" "호출 예시 0건 — 대상 파일이 틀렸거나 예시가 이동됨"
  elif [ -z "$bad" ]; then
    ok "T1 호출 예시에 --confidence: $2"
  else
    nope "T1 $2" "누락 줄: $(printf '%s' "$bad" | head -2 | tr '\n' ' ')"
  fi
}
_ex skills/performance-test-ko/SKILL.md 'performance-test-ko(자동)'
_ex skills/using-specops-ko/freework-pending.md 'using-specops-ko/freework-pending(freelog 자동)'
_ex skills/gbrain-ko/SKILL.md           'gbrain-ko'
_ex commands/gbrain.md                  '/gbrain'

# ── T2: 미기재가 explicit low 보다 아래로 밀리지 않는다 (순위 역전 차단) ──
# 동일 토큰 스코어로 맞춰 confidence 가중만 비교한다.
GB="$TMP/l.jsonl"
cat > "$GB" <<'EOF'
{"ts":"2026-01-01T00:00:00Z","fid":"20260101-a","insight":"캐시 만료 재조회 처리","tags":["cache"],"confidence":"low"}
{"ts":"2026-01-02T00:00:00Z","fid":"20260102-b","insight":"캐시 만료 재조회 처리","tags":["cache"]}
EOF
out=$(GBRAIN_FILE="$GB" bash "$RECALL" "캐시 만료 재조회" --top 2 2>/dev/null)
first=$(printf '%s' "$out" | head -1 | jq -r '.fid' 2>/dev/null)
# 미기재(20260102-b)가 low 와 동급이면 동점 → 후순 라인(최신) 우선 규약에 따라 b 가 위
[ "$first" = "20260102-b" ] \
  && ok "T2 미기재가 explicit low 아래로 밀리지 않음" \
  || nope "T2" "first=$first out=$(printf '%s' "$out" | tr '\n' ' ')"

# ── T3: high > 미기재 순서는 유지 (가중치 자체를 죽이지 않았는가) ────────
# T2 의 수정이 confidence 를 통째로 무력화하는 방향으로 가면 안 된다 — 축 분리.
cat > "$GB" <<'EOF'
{"ts":"2026-01-01T00:00:00Z","fid":"20260101-h","insight":"캐시 만료 재조회 처리","tags":["cache"],"confidence":"high"}
{"ts":"2026-01-02T00:00:00Z","fid":"20260102-n","insight":"캐시 만료 재조회 처리","tags":["cache"]}
EOF
out=$(GBRAIN_FILE="$GB" bash "$RECALL" "캐시 만료 재조회" --top 2 2>/dev/null)
first=$(printf '%s' "$out" | head -1 | jq -r '.fid' 2>/dev/null)
[ "$first" = "20260101-h" ] \
  && ok "T3 high 가 미기재보다 우선 (가중 유지)" \
  || nope "T3" "first=$first"

# ── T4: 토큰 스코어가 confidence 보다 우선 (주 정렬축 무손상) ───────────
cat > "$GB" <<'EOF'
{"ts":"2026-01-01T00:00:00Z","fid":"20260101-h","insight":"무관한 내용","tags":["zzz"],"confidence":"high"}
{"ts":"2026-01-02T00:00:00Z","fid":"20260102-n","insight":"캐시 만료 재조회 처리","tags":["cache"]}
EOF
out=$(GBRAIN_FILE="$GB" bash "$RECALL" "캐시 만료 재조회" --top 2 2>/dev/null)
first=$(printf '%s' "$out" | head -1 | jq -r '.fid' 2>/dev/null)
[ "$first" = "20260102-n" ] \
  && ok "T4 토큰 스코어 우선 (confidence 는 동점 가중)" \
  || nope "T4" "first=$first"

# ── T5: append 의 값 검증 유지 (회귀) ──────────────────────────────────
if ! (cd "$TMP" && GBRAIN_FILE="$TMP/x.jsonl" bash "$APPEND" "테스트" --fid 20260101-a --confidence 아주높음) >/dev/null 2>&1; then
  ok "T5 --confidence 규약 밖 값 거부"
else
  nope "T5" "잘못된 값이 통과"
fi

finish
