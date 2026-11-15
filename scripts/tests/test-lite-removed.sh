#!/usr/bin/env bash
# lite 진입 분기 제거 잠금 (20261114) — `/start-lite`·`/maintain-lite` 명령과 내부 진입 분기
#   (`<!-- entry: lite -->`·`<!-- entry: maintain-lite -->`·[lite-mini 분기])는 없다. 되살아나면 여기서 잡는다.
#   남긴 것: ① 위험 등급 lite(risk-profile 의 lite|standard|strict) ② 명확화 경량 모드(clarifications.md 의 mode: lite)
#   ③ 옛 spec 의 `§lite: true` 를 읽는 가드(check-review-presence · risk-profile LITE-STRICT-GUARD · split-session · decomposing 단축 분기).
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

SP="$PLUGIN/skills/specifying-ko/SKILL.md"
AN="$PLUGIN/skills/analyzing-ko/SKILL.md"
IMP="$PLUGIN/skills/implementing-ko/SKILL.md"
DEC="$PLUGIN/skills/decomposing-ko/SKILL.md"
US="$PLUGIN/skills/using-specops-ko/SKILL.md"

for f in "$SP" "$AN" "$IMP" "$DEC" "$US"; do
  [ -f "$f" ] || { nope "T0 파일 존재" "부재: $f"; finish; }
done
ok "T0 스킬 파일 존재"

# T1 명령 파일이 없다
[ ! -e "$PLUGIN/commands/start-lite.md" ] && [ ! -e "$PLUGIN/commands/maintain-lite.md" ] \
  && ok "T1 ★ /start-lite·/maintain-lite 명령 파일이 없다" || nope "T1" "lite 명령 파일 잔존"

# T2 진입 약속어·분기 이름이 실행 본문(명령·skill·에이전트·훅·템플릿)에 없다
hits=$(grep -rnE 'entry: (maintain-)?lite|\[(maintain-)?lite 분기\]|lite-mini|/(start|maintain)-lite' \
  "$PLUGIN/commands" "$PLUGIN/skills" "$PLUGIN/agents" "$PLUGIN/hooks" "$PLUGIN/templates" 2>/dev/null | head -5)
[ -z "$hits" ] && ok "T2 ★ lite 진입 약속어·분기·명령 이름이 실행 본문에 없다" || nope "T2" "$hits"

# T3 사용자 문서(README·CLAUDE.md)도 명령을 안내하지 않는다
hits=$(grep -nE '/(start|maintain)-lite|entry: (maintain-)?lite' "$PLUGIN/README.md" "$PLUGIN/CLAUDE.md" 2>/dev/null | head -3)
[ -z "$hits" ] && ok "T3 README·CLAUDE.md 가 lite 명령·약속어를 안내하지 않는다" || nope "T3" "$hits"

# T4 남은 진입 분기 순서 — maintain → foundation → batch
m=$(grep -n 'args 첫 줄이 `<!-- entry: maintain -->`' "$SP" | head -1 | cut -d: -f1)
f=$(grep -n 'args 첫 줄이 `<!-- entry: foundation -->`' "$SP" | head -1 | cut -d: -f1)
b=$(grep -n "     - args 첫 줄이 \`<!-- entry: batch -->\`" "$SP" | head -1 | cut -d: -f1)
[ -n "$m" ] && [ -n "$f" ] && [ -n "$b" ] && [ "$m" -lt "$f" ] && [ "$f" -lt "$b" ] \
  && ok "T4 specifying 진입 분기 maintain → foundation → batch" || nope "T4" "m=$m f=$f b=$b"

# T5 단축 경로(trivial · 옛 §lite spec)도 Phase B/C 생략 금지 — implementing 의 계약 문장
grep -qE '단축 경로 불변.*Phase B.*Phase C.*생략 금지' "$IMP" \
  && ok "T5 ★ 단축 경로 Phase B/C 필수" || nope "T5" "B/C 불변식 부재"

# T6 옛 §lite spec 호환 — decomposing 단축 분기가 표지를 읽고, strict 면 rc=3 가드
grep -qE '§lite\*\*: true.*옛 FID 호환' "$DEC" && grep -qF 'LITE-STRICT-GUARD' "$DEC" \
  && ok "T6 decomposing 이 옛 §lite spec 을 읽는다(단축 분기 · LITE-STRICT-GUARD)" || nope "T6" "옛 spec 호환 문구 부재"

# T7 읽는 쪽 가드 스크립트는 그대로다
grep -q '§lite' "$PLUGIN/scripts/_internal/check-review-presence.sh" \
  && grep -q 'LITE-STRICT-GUARD' "$PLUGIN/scripts/_internal/risk-profile.sh" \
  && grep -q '§lite' "$PLUGIN/scripts/split-session.sh" \
  && ok "T7 옛 §lite spec 가드 3종 유지(review-presence · risk-profile · split-session)" || nope "T7" "가드 스크립트에서 §lite 판정이 빠졌다"

# T8 갈래는 자연어로 추론하지 않고 스크립트 판정이 고른다
grep -qF '갈래 추론 금지' "$US" && grep -qF '**스크립트 판정**' "$US" \
  && ok "T8 메타 skill — 갈래는 스크립트 판정" || nope "T8" "NL 금지 산문 부재"

# T9 baseline commands 카운트 ↔ 실제 파일 수 정합 (하드코딩 금지 — 실측 대조)
_bl_cmds=$(jq -rs 'map(select(.category=="commands")) | .[0].count' \
  "$PLUGIN/scripts/_internal/.structure-baseline" 2>/dev/null)
_actual_cmds=$(ls "$PLUGIN"/commands/*.md 2>/dev/null | grep -c .)
[ -n "$_bl_cmds" ] && [ "$_bl_cmds" = "$_actual_cmds" ] \
  && ok "T9 baseline commands=$_bl_cmds ↔ 실제 $_actual_cmds 정합" \
  || nope "T9" "baseline=$_bl_cmds actual=$_actual_cmds — --update-baseline 필요"

finish
