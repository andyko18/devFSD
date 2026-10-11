#!/usr/bin/env bash
# /start-lite · /maintain-lite 계약 — 마커·불변식·승격·NL 금지
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

SL="$PLUGIN/commands/start-lite.md"
ML="$PLUGIN/commands/maintain-lite.md"
SP="$PLUGIN/skills/specifying-ko/SKILL.md"
AN="$PLUGIN/skills/analyzing-ko/SKILL.md"
IMP="$PLUGIN/skills/implementing-ko/SKILL.md"
DEC="$PLUGIN/skills/decomposing-ko/SKILL.md"
US="$PLUGIN/skills/using-specops-ko/SKILL.md"

for f in "$SL" "$ML" "$SP" "$AN" "$IMP" "$DEC" "$US"; do
  [ -f "$f" ] || { nope "T0 파일 존재" "부재: $f"; finish; }
done
ok "T0 명령·스킬 파일 존재"

# 마커
grep -q 'entry: lite' "$SL" \
  && ok "T1 start-lite 마커 entry: lite" || nope "T1" "entry: lite 없음"

grep -q 'entry: maintain-lite' "$ML" \
  && ok "T2 maintain-lite 마커" || nope "T2" "entry: maintain-lite 없음"

grep -q 'entry: maintain-lite' "$SP" && grep -q 'entry: lite' "$SP" \
  && ok "T3 specifying 분기 마커" || nope "T3" "specifying lite 마커 부재"

# maintain-lite 를 maintain 보다 먼저
ml_line=$(grep -n 'entry: maintain-lite' "$SP" | head -1 | cut -d: -f1)
m_line=$(grep -n 'entry: maintain -->' "$SP" | head -1 | cut -d: -f1)
[ -n "$ml_line" ] && [ -n "$m_line" ] && [ "$ml_line" -lt "$m_line" ] \
  && ok "T4 maintain-lite 선매칭" || nope "T4" "ml=$ml_line m=$m_line"

# clarify/plan skip
grep -qE 'clarifying·planning \*\*호출 금지\*\*|clarifying-ko·planning-ko' "$SL" \
  && grep -qE 'clarifying·planning \*\*호출 금지\*\*|호출 금지' "$ML" \
  && grep -qE 'clarifying-ko·planning-ko \*\*호출 금지\*\*|호출하지 않음' "$SP" \
  && ok "T5 clarify/plan skip" || nope "T5" "clarify/plan skip 산문 부재"

# 화면 5.5 / IF 5.6 유지
grep -q '화면·IF 생략' "$SL" \
  && grep -qE '제외 금지|동일 유지' "$SP" \
  && grep -qE 'Step 5\.5|5\.5·5\.6' "$SP" \
  && ok "T6 화면/IF 유지 불변식" || nope "T6" "5.5/5.6 유지 문구 부재"

# Phase B/C 필수
grep -qE 'Phase B/C' "$SL" \
  && grep -q '§lite 불변' "$IMP" \
  && grep -qE '생략 금지|필수' "$IMP" \
  && ok "T7 Phase B/C 필수" || nope "T7" "B/C 불변식 부재"

# analyzing-mini
grep -q 'lite-mini' "$AN" && grep -q 'HARD GATE' "$AN" \
  && grep -qE 'analyzing-mini|lite-mini' "$ML" \
  && ok "T8 maintain-lite analyzing-mini" || nope "T8" "lite-mini 부재"

# strict 승격
grep -qE '/start' "$SL" && grep -qE 'strict' "$SL" \
  && grep -qE '/maintain' "$ML" && grep -qE 'strict' "$ML" \
  && grep -qE 'strict 승격' "$SP" \
  && ok "T9 strict 승격" || nope "T9" "strict 승격 문구 부재"

# decomposing 단일 태스크 / §lite
grep -qE '§lite|trivial / §lite' "$DEC" \
  && grep -q '1 task' "$SL" \
  && ok "T10 decompose §lite 단일 태스크" || nope "T10" "decompose lite 분기 부재"

# NL 추론 금지
grep -q '자연어로 lite 추론 금지' "$SL" \
  && grep -q '자연어로 lite 추론 금지' "$ML" \
  && grep -qE 'lite 추론 금지' "$US" \
  && ok "T11 NL lite 추론 금지" || nope "T11" "NL 금지 산문 부재"

# §lite 라벨
grep -q '§lite' "$SP" && grep -q 'trivial' "$SP" \
  && grep -q '유지보수' "$SP" \
  && ok "T12 §lite·유형 라벨" || nope "T12" "§lite 라벨 부재"

# baseline commands 카운트 ↔ 실제 파일 수 정합
#   ⚠️ 구 구현은 `grep -q '"count":23'` 였다 — **하드코딩 지뢰**다:
#     ① 커맨드가 늘 때마다 반드시 터진다(20260807 실측: /doctor 추가 시 T5 차단)
#     ② 카테고리 무범위 substring 이라 **templates 카운트가 23 이어도 오탐 통과**한다
#   실측 대조로 바꿔 재발 클래스와 오탐을 함께 제거한다.
_bl_cmds=$(jq -rs 'map(select(.category=="commands")) | .[0].count' \
  "$PLUGIN/scripts/_internal/.structure-baseline" 2>/dev/null)
_actual_cmds=$(ls "$PLUGIN"/commands/*.md 2>/dev/null | grep -c .)
[ -n "$_bl_cmds" ] && [ "$_bl_cmds" = "$_actual_cmds" ] \
  && ok "T13 baseline commands=$_bl_cmds ↔ 실제 $_actual_cmds 정합" \
  || nope "T13" "baseline=$_bl_cmds actual=$_actual_cmds — --update-baseline 필요"

finish
