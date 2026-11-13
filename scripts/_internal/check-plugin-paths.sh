#!/usr/bin/env bash
# check-plugin-paths.sh — 프롬프트(skill·agent·command·template) 속 "실행 지시"와 스크립트 안내문의 plugin 상대 경로 적발 (20261008)
# Usage: check-plugin-paths.sh [ROOT]   (기본 플러그인 루트)  ·  Exit: 0 = 깨끗 · 1 = 위반 있음
#
# 왜 필요한가: `bash scripts/...`·`source hooks/...` 는 cwd 가 플러그인 repo 일 때만 동작한다. 하류 repo 에서는 파일이 없어
#   조용히 실패한다(실측: clarifying-ko 의 evaluator 회전·타임스탬프 주입, decomposing-ko 의 DAG 초기화 등).
#   하류에서도 맞는 표기는 `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/...` 이다.
# 대상(첫 표면): `bash|source` + (선택적 따옴표) + `scripts/|hooks/|skills/` 로 시작하는 경로. 설명용 언급(판정 SoT = `scripts/...`)은 실행 지시가 아니라 대상 아님.
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
# 넷째 표면 — `bash` 없이 적은 실행 표기 (20261113).
#   "계측기: `scripts/_internal/x.sh` (직접 실행)" 처럼 bash|source 가 없으면 첫 검사가 못 본다. 하류에서 이 표기를 받은
#   리뷰어 에이전트가 경로를 짐작했다(실측 20261113: 플러그인 캐시를 찾아 실행). 백틱이 plugin 상대 스크립트 경로로 시작하고
#   ① 백틱 안에 인자가 붙었거나(명령 형태 — `scripts/x.sh --rules`) ② 닫는 백틱 바로 뒤(12바이트 안 — 한글 4자)에 실행·호출이 오면 위반이다.
#   로케일마다 `{0,N}` 이 글자·바이트로 갈려 판정이 달라지므로 그 grep 은 LC_ALL=C(바이트)로 고정한다.
#   알려진 오탐(막는 쪽): 바로 뒤의 "실행하지 않는다"·"실행 결과" 도 걸린다 — 접두를 붙이면 풀린다.
#   Read 로 읽히는 보조 문서(SKILL.md 가 아닌 skills/**.md)는 변수가 치환되지 않는다 — 거기서는 인자를 백틱 밖으로 뺀다.
#   인자도 실행 동사도 없는 언급(판정 SoT = `scripts/...`)은 종전대로 대상이 아니다. 이 플러그인에 실제로 있는 파일만 본다
#   (없는 경로는 하류 프로젝트의 것). 허용 목록은 첫 검사와 같다.
_XP='(\./)?(scripts|hooks)/[A-Za-z0-9_./-]+\.(sh|cjs|js|py)'
xhits=""
while IFS= read -r _hit; do
  [ -n "$_hit" ] || continue
  _t=${_hit#*:*:\`}; _t=${_t%%[\` ]*}; _t=${_t#./}
  case "$_t" in scripts/tests/test-*|scripts/tests/run-all*) continue ;; esac
  [ -f "$_t" ] && xhits="${xhits}${_hit}"$'\n'
done <<EOF_XH
$(LC_ALL=C command grep -rnoE "\`$_XP( +[^\`]+\`|\`[^\`]{0,12}(실행|호출))" skills agents commands templates 2>/dev/null \
  | command grep -vE '^(skills/release-ko/|commands/release\.md:|skills/e2e-test-ko/)')
EOF_XH
if [ -n "$xhits" ]; then
  echo "PLUGIN-PATHS: FAIL — bash 없이 적은 plugin 상대 경로 실행 표기(하류 repo 에는 그 파일이 없어 경로를 짐작하게 된다):"
  printf '%s' "$xhits" | cut -c1-200 | sed 's/^/  /'
  echo "  → \`bash \"\${CLAUDE_PLUGIN_ROOT}\"/<경로>\` 로 바꾸세요 (설명용 언급이면 인자·실행 동사를 백틱 밖으로)."
  exit 1
fi
echo "PLUGIN-PATHS: OK"
exit 0
