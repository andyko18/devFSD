#!/usr/bin/env bash
# check-plugin-paths.sh — 프롬프트(skill·agent·command·template) 속 "실행 지시"와 스크립트 안내문의 plugin 상대 경로 적발 (20261008)
# Usage: check-plugin-paths.sh [ROOT]   (기본 플러그인 루트)  ·  Exit: 0 = 깨끗 · 1 = 위반 있음
#
# 왜 필요한가: `bash scripts/...`·`source hooks/...` 는 cwd 가 플러그인 repo 일 때만 동작한다. 하류 repo 에서는 파일이 없어
#   조용히 실패한다(실측: clarifying-ko 의 evaluator 회전·타임스탬프 주입, decomposing-ko 의 DAG 초기화 등).
#   하류에서도 맞는 표기는 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/...` 이다.
# 대상: `bash|source` + (선택적 따옴표) + `scripts/|hooks/|skills/` 로 시작하는 경로. 설명용 언급(판정 SoT = `scripts/...`)은 실행 지시가 아니라 대상 아님.
# 허용(plugin repo 자체에서만 도는 도구/예시):
#   skills/release-ko·commands/release.md(릴리즈는 plugin repo 에서만) · skills/e2e-test-ko(plugin 개발자 수동 E2E) ·
#   `scripts/tests/test-*` (하류 프로젝트의 테스트 명령 "예시" 표기) · `bash scripts/*.sh` 처럼 glob 인 러너 패턴 설명
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 2
hits=$(command grep -rnE '(bash|source) +"?(\./)?(scripts|hooks|skills)/' skills agents commands templates 2>/dev/null \
  | command grep -vE '^(skills/release-ko/|commands/release\.md:|skills/e2e-test-ko/)' \
  | command grep -vE '(bash|source) +"?(\./)?scripts/tests/(test-|run-all)' \
  | command grep -vE '(bash|source) +"?(\./)?scripts/\*' \
  | command grep -v 'CLAUDE_PLUGIN_ROOT')
# 실행 경로는 플러그인 루트인데 **인자**가 플러그인 상대경로인 경우 — `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/x.sh templates/y.md`.
#   위 검사는 bash|source 바로 뒤 경로만 봐서 이 형태가 통과했다(외부 critic 이 하류에서 "prompt-file 부재" 로 끝났다).
#   인자 토큰마다 본다: 따옴표·`./`·`--opt=` 를 벗긴 값이 `templates/|scripts/|hooks/|skills/` 로 시작하고 **이 플러그인에 실제로 있는
#   파일**일 때만 위반이다. 낱말 모양만 보면 하류 프로젝트의 경로를 넘기는 정상 호출(`security-scan.sh src scripts/deploy` ·
#   `--files templates/email.md`)과 줄 끝 주석의 낱말이 걸린다. `#` 뒤와 닫는 백틱 뒤는 인자가 아니다.
ahits=""
set -f
while IFS= read -r _hit; do
  [ -n "$_hit" ] || continue
  _rest=${_hit#*CLAUDE_PLUGIN_ROOT}; _rest=${_rest#*[[:space:]]}
  for _tok in $_rest; do
    case "$_tok" in '#'*|'|'*|'&&'|';'|'||') break ;; esac
    _t=${_tok#--*=}; _t=${_t#[\"\']}; _t=${_t%\`*}; _t=${_t%[\"\']}; _t=${_t#./}
    case "$_t" in
      scripts/tests/test-*|scripts/tests/run-all*) ;;
      templates/*|scripts/*|hooks/*|skills/*) [ -f "$_t" ] && { ahits="${ahits}${_hit}"$'\n'; break; } ;;
    esac
    case "$_tok" in *\`*) break ;; esac
  done
done <<EOF_AH
$(command grep -rnE '(bash|source|sh) +"?\$\{?CLAUDE_PLUGIN_ROOT\}?"?/' skills agents commands templates 2>/dev/null \
  | command grep -vE '^(skills/release-ko/|commands/release\.md:|skills/e2e-test-ko/)')
EOF_AH
set +f
if [ -n "$ahits" ]; then
  echo "PLUGIN-PATHS: FAIL — 플러그인 스크립트에 넘기는 인자가 plugin 상대 경로(하류 repo 에는 그 파일이 없다):"
  printf '%s' "$ahits" | cut -c1-220 | sed 's/^/  /'
  echo "  → 인자에도 \"\${CLAUDE_PLUGIN_ROOT}\"/<경로> 를 붙이세요."
  exit 1
fi
if [ -n "$hits" ]; then
  echo "PLUGIN-PATHS: FAIL — 하류 repo 에서 깨지는 plugin 상대 경로 실행 지시:"
  printf '%s\n' "$hits" | cut -c1-200 | sed 's/^/  /'
  echo "  → bash \"\${CLAUDE_PLUGIN_ROOT}\"/<경로> 로 바꾸세요."
  exit 1
fi

# 둘째 표면 — 스크립트·훅이 사용자에게 **출력하는** 안내문 (20261009).
#   게이트가 "해법: bash scripts/_internal/x.sh …" 를 찍으면 하류 저장소에는 그 파일이 없다. 프롬프트만 보던 위 검사는
#   이 표면을 보지 못했다(실측: 3개 스크립트의 FAIL·NOTE 안내가 하류에서 `No such file`).
#   주석 줄은 대상이 아니다. 맞는 표기는 그 스크립트가 아는 플러그인 루트 변수를 앞에 붙이는 것이다(`bash "$PLUGIN/scripts/…"`).
# 허용: plugin repo 에서만 도는 도구(release.sh·install-git-hooks.sh) · doctor 의 git_hooks 조치(그 줄은 `.githooks/` 가 있는
#   저장소에서만 도달한다) · 하류 테스트 명령의 "예시" 표기(`bash scripts/tests/…`).
shits=""
#   하위 디렉토리까지 본다(`scripts/_internal/init-project/` 가 하류 사용자에게 안내문을 가장 많이 낸다). 테스트 트리는 제외.
for _d in scripts hooks; do
  [ -d "$_d" ] || continue
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    case "$_f" in scripts/tests/*|scripts/release.sh|scripts/_internal/install-git-hooks.sh|scripts/_internal/check-plugin-paths.sh) continue ;; esac
    _h=$(command grep -nE '(bash|source) +"?(\./)?(scripts|hooks|skills)/' "$_f" 2>/dev/null \
      | command grep -vE '^[0-9]+:[[:space:]]*#' \
      | command grep -vE '(bash|source) +"?(\./)?scripts/tests/' \
      | command grep -vE '(bash|source) +"?(\./)?scripts/\*' \
      | command grep -vE 'git_hooks .*install-git-hooks\.sh' \
      | sed "s|^|$_f:|")
    [ -n "$_h" ] && shits="${shits}${_h}"$'\n'
  done <<EOF
$(find "$_d" -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)
EOF
done
if [ -n "$shits" ]; then
  echo "PLUGIN-PATHS: FAIL — 스크립트 안내문의 plugin 상대 경로(하류 repo 에는 그 파일이 없다):"
  printf '%s' "$shits" | cut -c1-200 | sed 's/^/  /'
  echo "  → 그 스크립트의 플러그인 루트 변수를 앞에 붙이세요 (예: bash \"\$PLUGIN/scripts/_internal/<이름>.sh\")."
  exit 1
fi
# 다섯째 표면 — Read 로 읽는 보조 문서 (20261115).
#   Skill 도구·슬래시 명령으로 실리는 본문은 플러그인 루트 변수가 치환되지만, **Read 로 읽는 파일은 치환되지 않고 Bash 환경에도
#   그 변수가 없다**(실측 unset). 모델이 적힌 대로 치면 `bash /scripts/x.sh` 가 된다(승인 기록·세션 분리 명령이 첫 실행에서 실패).
#   대상: skills/<x>/ 의 SKILL.md 가 아닌 .md · `basic-path.sh route` 가 Read 시키는 commands/basic.md · templates/screen-design-guide.md.
#   그 변수를 쓰는 문서는 "플러그인 루트 절대경로"로 바꿔 실행하라는 안내를 가져야 한다.
rhits=""
while IFS= read -r _f; do
  [ -f "$_f" ] || continue
  command grep -q 'CLAUDE_PLUGIN_ROOT' "$_f" 2>/dev/null || continue
  command grep -q '플러그인 루트 절대경로' "$_f" 2>/dev/null || rhits="${rhits}${_f}"$'\n'
done <<EOF_RD
$( { find skills -type f -name '*.md' ! -name 'SKILL.md' ! -name 'CLAUDE.md' 2>/dev/null \
      | command grep -vE '^skills/(release-ko|e2e-test-ko)/'; echo commands/basic.md; echo templates/screen-design-guide.md; } | LC_ALL=C sort)
EOF_RD
if [ -n "$rhits" ]; then
  echo "PLUGIN-PATHS: FAIL — Read 로 읽는 보조 문서가 플러그인 루트 변수를 쓰는데 치환 안내가 없다(Read 는 치환하지 않는다):"
  printf '%s' "$rhits" | sed 's/^/  /'
  echo "  → 문서 머리에 '명령의 플러그인 루트 변수는 플러그인 루트 절대경로(이 파일 경로에서 /skills/ 앞까지)로 바꿔 실행한다' 를 적으세요."
  exit 1
fi
echo "PLUGIN-PATHS: OK"
exit 0
