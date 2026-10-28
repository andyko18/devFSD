#!/usr/bin/env bash
# SAST 래퍼 — semgrep + gitleaks, graceful skip (critic-ask.sh 패턴)
set -u
# ── 대상 인자 (FID 20261003-ops-debt) ──
# 0개 = "." · 1개 이상 = 전부 스캔(변경 파일 목록을 인자로 줄 수 있다). 문자열 완전 일치 중복은 첫 위치만.
# 존재하지 않는 인자(빈 문자열·공백/개행으로 이은 목록 문자열 포함)는 침묵 통과가 아니라 사용 오류(rc 2) —
#   스캔 전에 판정하므로 부분 스캔이 없다. 종전엔 첫 인자만 스캔하고 나머지를 침묵 무시했다(둘째 인자의 secret 을 놓침).
[ "$#" -gt 0 ] || set -- .
TARGETS=(); nt=0
for _a in "$@"; do
  _dup=0; _i=0
  while [ "$_i" -lt "$nt" ]; do [ "${TARGETS[$_i]}" = "$_a" ] && { _dup=1; break; }; _i=$((_i+1)); done
  [ "$_dup" = 1 ] || { TARGETS[nt]="$_a"; nt=$((nt+1)); }
done
for _t in "${TARGETS[@]}"; do
  [ -e "$_t" ] || { echo "SECURITY: 대상 없음 — ${_t} (파일 여러 개는 별도 인자로 넘기세요)" >&2; exit 2; }
done
# 한계: (1) 인자 `""`(빈 문자열)은 종전에 `.` 로 대체돼 repo 전체를 스캔했지만 이제 사용 오류(rc 2)다 — 빈 변수가 조용히 전체 스캔으로
#   번지는 것도 같은 부류의 침묵이다. (2) `git diff --name-only` 목록을 넘길 때 삭제된 파일이 섞이면 존재 검증이 rc 2 로 거절하니
#   `--diff-filter=d` 로 거른다. (3) gitleaks 는 인자별 호출이라 총 시간이 호출당 상한(SPECOPS_SAST_TIMEOUT) x 인자 수까지 늘 수 있다.
# 외부 스캐너 건수 집계용 숫자 가드 — 빈 출력·비숫자가 `crit + ` 산술 구문 오류로 새지 않게 한다.
_num() { local v="${1%%$'\n'*}"; case "$v" in ''|*[!0-9]*) v=0;; esac; printf '%s' "$v"; }
crit=0; high=0; med=0; ran=0

# ── 외부 스캐너 상한·차단 스위치 (FID 20260828-sast-timeout) ──
# SPECOPS_SAST_TIMEOUT : 외부 스캐너 1개당 초 상한 (기본 180 · 0 = 무제한, 종전 동작)
# SPECOPS_SAST_EXTERNAL: 0 이면 외부 스캐너를 아예 안 부른다 (오프라인·테스트용)
# 왜 기본값이 180 인가: 외부 스캐너 1개의 최악 소요를 끊는 안전망이다. 로컬 룰셋 + version-check
#   차단 배선에서 semgrep 은 이 상한에 닿지 않는다 — 상한은 gitleaks 와 향후 추가 스캐너를 위해 남긴다.
# 종전 근거(레지스트리 왕복 99초)는 배선 교체로 소멸했다. 그 99초의 실체는 룰 수신이 아니라
#   semgrep.dev version-check 였다 — 같은 대상(1파일)·같은 스크립트 전체 소요가
#   **배선 전 98.1s / 배선 후 1.8s** 다(약 54배, 이 FID 실측). 배선이 SEMGREP_ENABLE_VERSION_CHECK=0
#   을 넘겨 그 왕복을 없앤다.
SAST_TIMEOUT="${SPECOPS_SAST_TIMEOUT:-180}"
SAST_EXTERNAL="${SPECOPS_SAST_EXTERNAL:-1}"
_sast_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/run-bounded.sh"
if [ -f "$_sast_lib" ]; then
  # shellcheck source=/dev/null
  . "$_sast_lib"
else
  # 헬퍼 부재 = 상한 없음. 조용히 무제한이 되지 않도록 fallback 을 명시 정의한다.
  bounded_run() { shift; "$@"; }
  bounded_timed_out() { return 1; }
fi
sast_timeout_note=""
ruleset_note=""

# ── self-check 1단계 (설치 0, 항상 실행) — secret 전 파일·위험함수/SQL 비-bash·비-문서 ──
# 언어 판별: .sh/.bash 확장자 또는 bash shebang → bash (위험함수 룰 제외, secret 만)
_is_bash() { case "$1" in *.sh|*.bash) return 0;; esac; head -1 "$1" 2>/dev/null | grep -q '^#!.*\(bash\|sh\)' && return 0; return 1; }
# 문서 확장자 — 실행되지 않는 산문이라 아래 위험함수·SQL 룰을 걸지 않는다(서술문 속 `eval(` 낱말이 high 가 되던 오탐, 파일 인자일 때만).
#   .json 도 같다 — 실행되지 않는 데이터다. llm-eval 의 evals.json 은 한 줄 수천 자짜리 문자열에 Python 계획 문안을 담아
#   `execute(` … 산문 `+` … `params` 가 한 줄에 놓이면 SQL 룰이 high 를 냈다(FID 20261021-api-designer-agent 에서 분류).
#   정규식 창을 좁히는 대신 확장자로 뺀 것은 코드 파일의 탐지를 그대로 두기 위해서다(긴 SQL 문자열 줄이 창 밖으로 빠진다).
#   package.json scripts 는 셸 명령이고 셸(.sh)도 이 룰 밖이다.
#   secret 룰은 문서에도 건다(붙여 넣은 키). 목록은 이 함수 한 곳에만 둔다. 대소문자 무시는 대괄호 패턴 — bash 3.2(macOS 기본)에 ${v,,} 가 없고,
#   tr 같은 외부 프로세스는 디렉토리 스캔이 비-bash 파일마다 이 함수를 평가하므로 파일 수만큼 포크가 늘어난다(2000개 .py 실측 +29%).
_is_doc() { case "$1" in *.[Mm][Dd]|*.[Mm][Aa][Rr][Kk][Dd][Oo][Ww][Nn]|*.[Tt][Xx][Tt]|*.[Rr][Ss][Tt]|*.[Aa][Dd][Oo][Cc]|*.[Jj][Ss][Oo][Nn]) return 0;; esac; return 1; }
_selfcheck_file() {
  local f="$1"
  # secret (전 파일) → crit
  grep -Eq 'AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{36}|sk-[0-9A-Za-z]{20,}|-----BEGIN[^-]*PRIVATE KEY|(password|api_key|secret)[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']{6,}' "$f" 2>/dev/null && crit=$((crit+1))
  # 위험함수·SQL (비-bash·비-문서 만) → high
  if ! _is_bash "$f" && ! _is_doc "$f"; then
    grep -Eq '\beval\(|\bexec\(|os\.system|subprocess[^)]*shell[[:space:]]*=[[:space:]]*True|dangerouslySetInnerHTML|\.innerHTML[[:space:]]*=' "$f" 2>/dev/null && high=$((high+1))
    grep -Eq '(query|execute).*\+.*(req\.|request\.|params)|f["'"'"'][^"'"'"']*SELECT[^"'"'"']*\{' "$f" 2>/dev/null && high=$((high+1))
  fi
}
ran=1
for _t in "${TARGETS[@]}"; do
  if [ -f "$_t" ]; then _selfcheck_file "$_t"
  else
    # 디렉토리: 텍스트 파일 순회 (.git·node_modules·.specops 제외)
    # */tests/* 제외 (C-1) — 보안 테스트 fixture 가 의도적 가짜 secret 보유 → 자기 오탐 방지
    while IFS= read -r f; do _selfcheck_file "$f"; done < <(find "$_t" -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.sh' -o -name '*.bash' -o -name '*.go' -o -name '*.rb' -o -name '*.java' -o -name '*.php' \) -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.specops/*' -not -path '*/tests/*' 2>/dev/null)
  fi
done

# jq 부재 가드 (code-reviewer I-2) — 외부 스캐너 결과는 jq 없으면 집계 불가라 SKIP 하되,
# self-check(grep, jq 무관) 결과는 보존: early-exit 0 으로 self-check crit 폐기하지 않음.
ext_skip=0
if { command -v semgrep >/dev/null 2>&1 || command -v gitleaks >/dev/null 2>&1; } && ! command -v jq >/dev/null 2>&1; then
  echo "SECURITY: 외부 스캐너 jq 미설치 — self-check 결과로만 판정 (외부 집계 skip)" >&2
  ext_skip=1
fi
[ "$SAST_EXTERNAL" = 0 ] && ext_skip=1
# semgrep (변경 코드 SAST)
SEMGREP_RULES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/semgrep-rules/bash-injection.yml"
if [ "$ext_skip" = 0 ] && command -v semgrep >/dev/null 2>&1; then
  ran=1
  if [ ! -f "$SEMGREP_RULES" ]; then
    # 룰셋 부재를 분기 조건으로 처리하면 semgrep 층이 조용히 사라진다 — gitleaks 가 설치된
    #   환경에서는 ran=1 이라 SECURITY: SKIP 도 안 나오고 crit=0 이 깨끗하게 통과한다(무음 통과).
    sast_timeout_note="${sast_timeout_note} semgrep(룰셋 부재)"
    j='{}'
  else
    j=$(bounded_run "$SAST_TIMEOUT" env SEMGREP_ENABLE_VERSION_CHECK=0 \
          semgrep --config "$SEMGREP_RULES" --json --quiet -- "${TARGETS[@]}" 2>/dev/null); src=$?
    # 한 경로가 semgrep 을 실패시키면(예: 심볼릭 링크 인자 rc=2) 나머지 경로의 탐지까지 사라진다 — 경로별로 다시 돌려 성한 경로의
    #   결과를 살린다. 실패한 경로가 하나라도 있으면 아래 강등 표기가 남고 룰셋 receipt 는 붙지 않는다(부분 스캔을 완전 스캔으로 오인 방지).
    _sg_partial=0
    if [ "$src" -gt 1 ] && [ "$nt" -gt 1 ] && ! bounded_timed_out "$src" && command -v jq >/dev/null 2>&1; then
      _sg_partial=1; j='{"results":[]}'; src_fail=0; _i=0
      while [ "$_i" -lt "$nt" ]; do
        _j1=$(bounded_run "$SAST_TIMEOUT" env SEMGREP_ENABLE_VERSION_CHECK=0 \
              semgrep --config "$SEMGREP_RULES" --json --quiet -- "${TARGETS[$_i]}" 2>/dev/null); _rc1=$?
        if [ "$_rc1" -gt 1 ]; then [ "$src_fail" -gt 1 ] || src_fail=$_rc1
        else j=$(printf '%s\n%s' "$j" "$_j1" | jq -s '{results: (map(.results // []) | add)}' 2>/dev/null || printf '%s' "$j"); fi
        _i=$((_i+1))
      done
      src=$src_fail   # 0 = 전부 성공(receipt 허용) · 2 = 일부 실패(강등 표기)
    fi
    if bounded_timed_out "$src"; then
      sast_timeout_note="${sast_timeout_note} semgrep(시간초과)"
      j='{}'
    elif [ "$src" -gt 1 ]; then
      # 하드 실패(rc≥2 = semgrep 에러: 네트워크 두절·설정 거부·인증 요구)도 표기한다.
      #   왜: 실패하면 j 가 비고 crit 이 0 인 채로 "SECURITY: crit=0" 이 나간다 — 스캔을 안 한 것과
      #   통과한 것이 구분되지 않는 **무음 통과**다. 시간초과와 같은 축으로 강등 표기한다.
      #   rc=1 은 제외 — semgrep 은 findings 존재를 1 로 낼 수 있어 정상 결과다.
      sast_timeout_note="${sast_timeout_note} semgrep(실행실패 rc=$src)"
      [ "$_sg_partial" = 1 ] || j='{}'
    else
      # 실행 receipt — 스캔이 실제로 끝난 뒤에만 룰셋을 표기한다.
      #   분기 진입 시점에 표기하면 rc=2·시간초과에도 표기가 남아 "룰셋이 보이면 돌았다"가 거짓이 된다.
      ruleset_note=" (룰셋: 로컬 bash-injection)"
    fi
  fi
  [ -n "$j" ] || j='{}'
  if command -v jq >/dev/null 2>&1; then
    crit=$((crit + $(_num "$(printf '%s' "$j" | jq '[.results[]?|select(.extra.severity=="ERROR")]|length' 2>/dev/null)")))
    high=$((high + $(_num "$(printf '%s' "$j" | jq '[.results[]?|select(.extra.severity=="WARNING")]|length' 2>/dev/null)")))
  fi
fi
# gitleaks (secret) — --no-git: 작업트리 파일시스템 스캔(git 히스토리 아님, code-reviewer I-1).
#   tmp 리포트는 mktemp + trap 정리(고정 /tmp 경로 race·심볼릭링크 회피, code-reviewer I-2).
if [ "$ext_skip" = 0 ] && command -v gitleaks >/dev/null 2>&1; then
  ran=1
  glrep=$(mktemp "${TMPDIR:-/tmp}/specops-gl.XXXXXX") || glrep=""
  if [ -n "$glrep" ]; then
    trap 'rm -f "$glrep"' EXIT
    # gitleaks --source 는 경로 하나만 받는다 — 인자별로 부르고 건수를 합산한다(강등 표기는 1회만).
    for _t in "${TARGETS[@]}"; do
      : > "$glrep"   # 이전 인자의 리포트가 남아 이중 계상되지 않게 비운다
      bounded_run "$SAST_TIMEOUT" gitleaks detect --source "$_t" --no-git --no-banner --exit-code 0 --report-format json --report-path "$glrep" >/dev/null 2>&1
      glrc=$?
      # gitleaks 는 --exit-code 0 이라 정상 경로 rc 가 항상 0 — 0 이 아니면 시간초과이거나 실행 실패다.
      case "$sast_timeout_note" in
        *gitleaks\(*) ;;
        *)
          if bounded_timed_out "$glrc"; then
            sast_timeout_note="${sast_timeout_note} gitleaks(시간초과)"
          elif [ "$glrc" -ne 0 ]; then
            sast_timeout_note="${sast_timeout_note} gitleaks(실행실패 rc=$glrc)"
          fi ;;
      esac
      if [ -f "$glrep" ] && command -v jq >/dev/null 2>&1; then
        crit=$((crit + $(_num "$(jq 'length' "$glrep" 2>/dev/null)")))  # secret = Critical
      fi
    done
  fi
fi
if [ "$ran" = 0 ]; then
  echo "SECURITY: SKIP (semgrep·gitleaks 미설치 — graceful skip)"
  exit 0
fi
# 외부 SAST 미실행 표기 — self-check 만 ran=1 일 때 crit=0 을 full SAST 통과로 오인 방지 (M6)
# 강등 사유 3종을 **전부** 표기한다 (20260828-sast-timeout 이 시간초과를 추가):
#   상한만 걸고 표기를 빠뜨리면 무한 정지가 "조용한 crit=0 통과" 로 바뀐다 — 정지보다 나쁘다.
ext_note=""
if [ -n "$sast_timeout_note" ]; then
  ext_note=" (외부 SAST 미반영 —${sast_timeout_note}, 상한 ${SAST_TIMEOUT}s)"
elif [ "$SAST_EXTERNAL" = 0 ]; then
  ext_note=" (self-check only — 외부 스캐너 비활성 SPECOPS_SAST_EXTERNAL=0)"
elif ! { command -v semgrep >/dev/null 2>&1 || command -v gitleaks >/dev/null 2>&1; }; then
  ext_note=" (self-check only — semgrep·gitleaks 미설치)"
fi
echo "SECURITY: crit=$crit high=$high med=$med$ruleset_note$ext_note"
{ [ "$crit" -gt 0 ] || [ "$high" -gt 0 ]; } && exit 1 || exit 0
