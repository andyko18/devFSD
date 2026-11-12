#!/usr/bin/env bash
# /start-lite · /maintain-lite 계약 — 명령은 /start·/maintain 의 별칭(다음 메이저에서 제거)이고,
#   내부 lite 분기(약속어·skill 분기)는 아직 남아 있다(이번에 지우지 않았다 — 지울 목록은 CHANGELOG [Unreleased]).
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

# 별칭 (20261112) — 고지 1줄 · 갈래 판정은 /start·/maintain 과 같은 스크립트 · 종전 lite 절차로 들어가지 않는다
for pair in "start-lite:start:$SL" "maintain-lite:maintain:$ML"; do
  n=${pair%%:*}; rest=${pair#*:}; k=${rest%%:*}; f=${rest#*:}
  grep -qF "\`/$n\` 는 다음 메이저에서 제거됩니다 — \`/$k\` 가 자동으로 고릅니다." "$f" \
    && ok "T1.$n ★ 실행 시 제거 예고 1줄 고지" || nope "T1.$n" "고지 문구 없음"
  grep -qF "basic-path.sh route $k " "$f" && grep -qF 'PROCEDURE:' "$f" && grep -qF 'ENTRY:' "$f" \
    && ok "T2.$n ★ /$k 와 같은 갈래 판정(route $k) — 기본은 PROCEDURE, 풀은 ENTRY 파일" || nope "T2.$n" "route 배선 없음"
  ! grep -qE '^[0-9]+\. .*(prepend|devfsd:(specifying|analyzing)-ko. 호출)' "$f" \
    && ok "T2b.$n 종전 lite 절차(약속어 prepend → skill 직접 호출) 단계가 없다" || nope "T2b.$n" "lite 절차 잔존"
done

grep -q 'entry: maintain-lite' "$SP" && grep -q 'entry: lite' "$SP" \
  && ok "T3 specifying 분기 마커" || nope "T3" "specifying lite 마커 부재"

# maintain-lite 를 maintain 보다 먼저
ml_line=$(grep -n 'entry: maintain-lite' "$SP" | head -1 | cut -d: -f1)
m_line=$(grep -n 'entry: maintain -->' "$SP" | head -1 | cut -d: -f1)
[ -n "$ml_line" ] && [ -n "$m_line" ] && [ "$ml_line" -lt "$m_line" ] \
  && ok "T4 maintain-lite 선매칭" || nope "T4" "ml=$ml_line m=$m_line"

# clarify/plan skip
grep -qE 'clarifying-ko·planning-ko \*\*호출 금지\*\*|호출하지 않음' "$SP" \
  && ok "T5 clarify/plan skip" || nope "T5" "clarify/plan skip 산문 부재"

# 화면 5.5 / IF 5.6 유지
grep -qE '제외 금지|동일 유지' "$SP" \
  && grep -qE 'Step 5\.5|5\.5·5\.6' "$SP" \
  && ok "T6 화면/IF 유지 불변식" || nope "T6" "5.5/5.6 유지 문구 부재"

# Phase B/C 필수
grep -q '§lite 불변' "$IMP" \
  && grep -qE '생략 금지|필수' "$IMP" \
  && ok "T7 Phase B/C 필수" || nope "T7" "B/C 불변식 부재"

# analyzing-mini
grep -q 'lite-mini' "$AN" && grep -q 'HARD GATE' "$AN" \
  && ok "T8 maintain-lite analyzing-mini" || nope "T8" "lite-mini 부재"

# strict 승격
grep -qE 'strict 승격' "$SP" \
  && ok "T9 strict 승격" || nope "T9" "strict 승격 문구 부재"

# decomposing 단일 태스크 / §lite
grep -qE '§lite|trivial / §lite' "$DEC" \
  && ok "T10 decompose §lite 단일 태스크" || nope "T10" "decompose lite 분기 부재"

# NL 추론 금지
grep -qF '갈래 추론 금지' "$US" && grep -qF '**스크립트 판정**' "$US" \
  && ok "T11 메타 skill — 갈래는 자연어로 추론하지 않고 스크립트 판정이 고른다" || nope "T11" "NL 금지 산문 부재"

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
