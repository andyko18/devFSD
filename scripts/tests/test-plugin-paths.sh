#!/usr/bin/env bash
# check-plugin-paths.sh — 프롬프트 속 plugin 상대 경로 실행 지시 적발 (20261008)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-plugin-paths.sh"

# P1: 실제 트리는 깨끗하다(회귀 잠금)
out=$(bash "$CHK" "$PLUGIN" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "P1 실 트리 깨끗" || nope "P1" "rc=$rc out=$out"

_fx() {  # $1=상대경로 $2=내용 → 샌드박스 루트 출력
  local d; d=$(mktemp -d); mkdir -p "$d/$(dirname "$1")" "$d/skills" "$d/agents" "$d/commands" "$d/templates"
  printf '%s\n' "$2" > "$d/$1"; printf '%s' "$d"
}
# P2: 맨몸 `bash hooks/…` → 위반
d=$(_fx skills/x-ko/SKILL.md 'run: `bash hooks/rotate.sh a`'); out=$(bash "$CHK" "$d" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'x-ko/SKILL.md' && ok "P2 bash hooks/ 맨몸 → FAIL" || nope "P2" "rc=$rc"
rm -rf "$d"
# P3: `source scripts/…` 맨몸 → 위반
d=$(_fx agents/a.md 'x
      source scripts/dag/parse-dag.sh'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "P3 source scripts/ 맨몸 → FAIL" || nope "P3" "rc=$rc"
rm -rf "$d"
# P4: CLAUDE_PLUGIN_ROOT 접두 → 통과
d=$(_fx skills/x-ko/SKILL.md 'run: `bash "${CLAUDE_PLUGIN_ROOT}"/hooks/rotate.sh a`'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P4 CLAUDE_PLUGIN_ROOT 접두 → OK" || nope "P4" "rc=$rc"
rm -rf "$d"
# P5: 설명용 언급(실행 지시 아님)은 대상 아님
d=$(_fx skills/x-ko/SKILL.md '판정 SoT = `scripts/_internal/check-x.sh` 가 한다'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P5 설명용 경로 언급은 통과" || nope "P5" "rc=$rc"
rm -rf "$d"
# P6: 허용 목록(release-ko·하류 테스트 명령 예시)은 통과
d=$(_fx skills/release-ko/SKILL.md 'bash scripts/release.sh'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P6a release-ko 허용" || nope "P6a" "rc=$rc"
rm -rf "$d"
d=$(_fx templates/CLAUDE.md '`bash scripts/tests/test-x.sh`'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P6b 하류 테스트 명령 예시 허용" || nope "P6b" "rc=$rc"
rm -rf "$d"

# ── 둘째 표면: 스크립트·훅이 출력하는 안내문 ──────────────────────────────
_sfx() {  # $1=상대경로 $2=내용 → 샌드박스 루트 출력 (프롬프트 디렉토리는 비워 둔다)
  local d; d=$(mktemp -d); mkdir -p "$d/$(dirname "$1")" "$d/skills" "$d/agents" "$d/commands" "$d/templates"
  printf '%s\n' "$2" > "$d/$1"; printf '%s' "$d"
}
# P7: 게이트의 해법 안내가 plugin 상대 경로 → 위반 (하류에는 그 파일이 없다)
d=$(_sfx scripts/_internal/check-x.sh 'echo "  해법: bash scripts/_internal/fix-x.sh <FID>"'); out=$(bash "$CHK" "$d" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'check-x.sh:1:' && ok "P7 스크립트 안내문 상대 경로 → FAIL" || nope "P7" "rc=$rc out=$out"
rm -rf "$d"
# P7b: heredoc 본문(echo 가 아닌 줄)도 같은 표면이다
d=$(_sfx hooks/h.sh 'cat <<EOF
  확인: bash scripts/_internal/list.sh --list
EOF'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "P7b heredoc 안내문 상대 경로 → FAIL" || nope "P7b" "rc=$rc"
rm -rf "$d"
# P8: 플러그인 루트 변수를 붙이면 통과
d=$(_sfx scripts/_internal/check-x.sh 'echo "  해법: bash \"$PLUGIN/scripts/_internal/fix-x.sh\" <FID>"'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P8 플러그인 루트 변수 접두 → OK" || nope "P8" "rc=$rc"
rm -rf "$d"
# P9: 주석 줄·하류 테스트 명령 예시는 대상 아님
d=$(_sfx scripts/a.sh '# 사용 예: bash scripts/a.sh <FID>
echo "test_command 를 bash scripts/tests/… 형태로 고치세요"'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P9 주석·테스트 명령 예시는 통과" || nope "P9" "rc=$rc"
rm -rf "$d"
# P10: plugin repo 에서만 도는 도구는 허용
d=$(_sfx scripts/release.sh 'echo "릴리즈 전 bash scripts/x.sh 권장"'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P10 release.sh 허용" || nope "P10" "rc=$rc"
rm -rf "$d"
# P10b: 하위 디렉토리의 스크립트도 본다 (init-project 계열이 안내문을 가장 많이 낸다)
d=$(_sfx scripts/_internal/init-project/lib.sh 'echo "해법: bash scripts/_internal/x.sh"'); out=$(bash "$CHK" "$d" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'init-project/lib.sh:1:' && ok "P10b 하위 디렉토리 스크립트 → FAIL" || nope "P10b" "rc=$rc out=$out"
rm -rf "$d"
# P10c: 테스트 트리는 대상 아님 (테스트는 plugin repo 에서만 돈다)
d=$(_sfx scripts/tests/test-x.sh 'echo "bash scripts/_internal/x.sh"'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P10c scripts/tests/ 는 통과" || nope "P10c" "rc=$rc"
rm -rf "$d"
# P11: 들여쓴 주석이 아닌 줄의 `#` 뒤 문구는 주석이 아니다 — 출력 문자열 안의 `#` 를 주석으로 읽지 않는다
d=$(_sfx scripts/b.sh 'echo "# 해법: bash scripts/_internal/y.sh"'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "P11 문자열 안의 # 는 주석 아님 → FAIL" || nope "P11" "rc=$rc"
rm -rf "$d"

# ── 셋째 표면: 플러그인 스크립트에 넘기는 **인자**의 상대 경로 ──────────────
# P12: 실행 경로는 플러그인 루트인데 인자가 plugin 상대 경로 → 위반 (하류에는 templates/ 가 없다)
d=$(_fx skills/x-ko/SKILL.md 'run: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/critic-ask.sh templates/critic-prompt-plan.md --files .specops/<FID>/plan.md`'); : > "$d/templates/critic-prompt-plan.md"; out=$(bash "$CHK" "$d" 2>&1); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'x-ko/SKILL.md' && ok "P12 플러그인 스크립트의 인자가 상대 경로 → FAIL" || nope "P12" "rc=$rc out=$out"
rm -rf "$d"
# P13: 인자에도 플러그인 루트를 붙이면 통과 · 프로젝트 쪽 경로(.specops/…)는 인자로 그대로 둔다
d=$(_fx skills/x-ko/SKILL.md 'run: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/critic-ask.sh "${CLAUDE_PLUGIN_ROOT}"/templates/critic-prompt-plan.md --files .specops/<FID>/plan.md`'); bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "P13 인자에 플러그인 루트 접두 → OK" || nope "P13" "rc=$rc"
rm -rf "$d"
# P14: 하류 테스트 명령 예시를 인자로 넘기는 표기는 대상 아님
d=$(_fx skills/x-ko/SKILL.md '`bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/record-task-receipt.sh <FID> scripts/tests/test-x.sh`'); mkdir -p "$d/scripts/tests"; : > "$d/scripts/tests/test-x.sh"; bash "$CHK" "$d" >/dev/null 2>&1; rc=$?   # 같은 이름의 파일이 플러그인에 있어도 예시 표기는 통과
[ "$rc" -eq 0 ] && ok "P14 인자가 하류 테스트 경로 예시 → 통과" || nope "P14" "rc=$rc"
rm -rf "$d"
# P15: 플러그인에 없는 경로는 하류 프로젝트의 것이다 — 낱말 모양(scripts/·templates/)만으로 막지 않는다
d=$(_fx skills/x-ko/SKILL.md '`bash "${CLAUDE_PLUGIN_ROOT}"/scripts/security-scan.sh src scripts/deploy`
`bash "${CLAUDE_PLUGIN_ROOT}"/scripts/critic-ask.sh "${CLAUDE_PLUGIN_ROOT}"/templates/critic-prompt-diff.md --files templates/email.md`'); : > "$d/templates/critic-prompt-diff.md"; out=$(bash "$CHK" "$d" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "P15 하류 프로젝트 경로(플러그인에 없는 파일)를 인자로 → 통과" || nope "P15" "rc=$rc out=$out"
rm -rf "$d"
# P16: 줄 끝 주석·닫는 백틱 뒤의 낱말은 인자가 아니다
d=$(_fx skills/x-ko/SKILL.md 'bash "${CLAUDE_PLUGIN_ROOT}"/scripts/x.sh <FID>   # templates/y.md 에서 읽음
`bash "${CLAUDE_PLUGIN_ROOT}"/scripts/x.sh <FID>` 는 templates/y.md 를 읽는다'); : > "$d/templates/y.md"; out=$(bash "$CHK" "$d" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "P16 주석·백틱 밖의 낱말 → 통과" || nope "P16" "rc=$rc out=$out"
rm -rf "$d"
# P17: 표기가 달라도 같은 위반이다 — 작은따옴표 · ./ · --opt= · 중괄호 없는 변수
for _v in "'templates/y.md'" './templates/y.md' '--prompt=templates/y.md' '"templates/y.md"'; do
  d=$(_fx skills/x-ko/SKILL.md "\`bash \"\${CLAUDE_PLUGIN_ROOT}\"/scripts/x.sh $_v\`"); : > "$d/templates/y.md"; bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && ok "P17 인자 표기 $_v → FAIL" || nope "P17 $_v" "rc=$rc"
  rm -rf "$d"
done
d=$(_fx skills/x-ko/SKILL.md '`bash $CLAUDE_PLUGIN_ROOT/scripts/x.sh templates/y.md`'); : > "$d/templates/y.md"; bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "P17b 중괄호 없는 변수로 부른 스크립트의 인자 → FAIL" || nope "P17b" "rc=$rc"
# P18: 한 줄에 하류 테스트 경로 예시가 있어도 **다른 인자**의 위반은 잡는다 (종전 예외는 줄 전체를 면제했다)
rm -rf "$d"
d=$(_fx skills/x-ko/SKILL.md '`bash "${CLAUDE_PLUGIN_ROOT}"/scripts/critic-ask.sh templates/y.md --files scripts/tests/test-a.sh`'); : > "$d/templates/y.md"; bash "$CHK" "$d" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "P18 테스트 경로 예시가 같은 줄에 있어도 다른 인자 위반 → FAIL" || nope "P18" "rc=$rc"
rm -rf "$d"

finish
