#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
H="$PLUGIN/scripts/promote-validate.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

# T0a: fid=".." → REJECT:bad-format (경로 traversal 방어)
out=$(bash "$H" ".." 2>/dev/null)
[ "$out" = "REJECT:bad-format" ] && { PASS=$((PASS+1)); echo "PASS T0a bad-format(..)"; } || { FAIL=$((FAIL+1)); echo "FAIL T0a ($out)"; }

# T0b: fid="../x" → REJECT:bad-format
out=$(bash "$H" "../x" 2>/dev/null)
[ "$out" = "REJECT:bad-format" ] && { PASS=$((PASS+1)); echo "PASS T0b bad-format(../x)"; } || { FAIL=$((FAIL+1)); echo "FAIL T0b ($out)"; }

# T1: 인자 없음 → REJECT:usage
out=$(bash "$H" 2>/dev/null)
[ "$out" = "REJECT:usage" ] && { PASS=$((PASS+1)); echo "PASS T1 usage"; } || { FAIL=$((FAIL+1)); echo "FAIL T1 ($out)"; }

# T2: 디렉토리 없음 → REJECT:no-dir
out=$(bash "$H" 20260625-nope 2>/dev/null)
[ "$out" = "REJECT:no-dir" ] && { PASS=$((PASS+1)); echo "PASS T2 no-dir"; } || { FAIL=$((FAIL+1)); echo "FAIL T2 ($out)"; }

# T3: freework.md 없음 → REJECT:not-mini-fid
mkdir -p "$TMP/.specops/20260625-plain"
out=$(bash "$H" 20260625-plain 2>/dev/null)
[ "$out" = "REJECT:not-mini-fid" ] && { PASS=$((PASS+1)); echo "PASS T3 not-mini-fid"; } || { FAIL=$((FAIL+1)); echo "FAIL T3 ($out)"; }

# T4: spec.md 이미 존재 → REJECT:already-promoted
mkdir -p "$TMP/.specops/20260625-done"
: > "$TMP/.specops/20260625-done/freework.md"
: > "$TMP/.specops/20260625-done/spec.md"
out=$(bash "$H" 20260625-done 2>/dev/null)
[ "$out" = "REJECT:already-promoted" ] && { PASS=$((PASS+1)); echo "PASS T4 already-promoted"; } || { FAIL=$((FAIL+1)); echo "FAIL T4 ($out)"; }

# T5: freework.md 있고 spec.md 없음 → OK
mkdir -p "$TMP/.specops/20260625-mini"
: > "$TMP/.specops/20260625-mini/freework.md"
out=$(bash "$H" 20260625-mini 2>/dev/null)
[ "$out" = "OK" ] && { PASS=$((PASS+1)); echo "PASS T5 OK"; } || { FAIL=$((FAIL+1)); echo "FAIL T5 ($out)"; }

# T6: promote.md frontmatter + 헬퍼 호출 + 거부 문구 (AC-1,4,12)
CMD="$PLUGIN/commands/promote.md"
if [ -f "$CMD" ] && grep -q 'name: promote' "$CMD" \
   && grep -q 'promote-validate.sh' "$CMD" \
   && grep -q 'promote-fid' "$CMD" \
   && grep -q 'entry: maintain' "$CMD"; then
  PASS=$((PASS+1)); echo "PASS T6 promote.md 규약"
else
  FAIL=$((FAIL+1)); echo "FAIL T6 promote.md"
fi

# T7: analyzing-ko Step 0 promote-fid 분기 지시 존재 (AC-5,6,11)
ANA="$PLUGIN/skills/analyzing-ko/SKILL.md"
if grep -q 'promote-fid' "$ANA" && grep -q 'freework.md' "$ANA" \
   && grep -q 'git diff HEAD' "$ANA"; then
  PASS=$((PASS+1)); echo "PASS T7 analyzing promote-fid 분기"
else
  FAIL=$((FAIL+1)); echo "FAIL T7 analyzing 분기"
fi

# T8 (G5): Step 1 에 promote-fid 시드 로직 구현 — Step 0 선언이 Step 1 본문에 연결됐는가
# (선언만 있고 시드 절차 없던 갭 회귀 차단). Step 1 섹션 내에 promote-fid 분기 + files 1차 + 경계 한계고백.
step1=$(awk '/^### Step 1:/{f=1} f&&/^### Step 2:/{f=0} f' "$ANA")
if printf '%s' "$step1" | grep -q 'promote-fid 분기' \
   && printf '%s' "$step1" | grep -q 'files.*1차 소스\|1차 소스' \
   && printf '%s' "$step1" | grep -q '변경 대상 미확정'; then
  PASS=$((PASS+1)); echo "PASS T8 Step1 promote-fid 시드 로직 (files 1차 + 경계 한계고백)"
else
  FAIL=$((FAIL+1)); echo "FAIL T8 Step1 시드 로직 미구현"
fi

# T9 (20260806 /promote 정밀분석): analyzing promote-fid 분기의 검증 재실행
# 갭: promote-validate 는 command 레이어(Process 1)에만 배선돼 있었다. 재개 세션·
#   스킬 직접 호출로 analyzing 에 promote-fid 가 도달하면 재검증 없이 진행 —
#   already-promoted FID(spec.md 존재)면 specifying 유지보수 분기가 **진행 중
#   lifecycle 의 spec.md 를 덮어쓴다**. 분기 첫 동작으로 재검증을 요구한다.
step0p=$(awk '/\[promote-fid 분기\]/{f=1} f&&/^args에서/{f=0} f' "$ANA")
if printf '%s' "$step0p" | grep -q 'promote-validate.sh' \
   && printf '%s' "$step0p" | grep -qE 'REJECT.*중단|중단.*REJECT'; then
  PASS=$((PASS+1)); echo "PASS T9 analyzing 분기 검증 재실행 + REJECT 중단"
else
  FAIL=$((FAIL+1)); echo "FAIL T9 재검증 부재 — already-promoted spec.md 덮어쓰기 표면"
fi

echo "---"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
