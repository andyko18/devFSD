#!/usr/bin/env bash
# gate-preflight.sh — 보안·통합·성능 게이트의 적용 여부를 한 번에 사전 판정한다 (20261112 speed)
#
# Usage: gate-preflight.sh <FID>                              판정 + 해당 없는 게이트의 SKIP 기록(evidence.md · session-progress)
#        gate-preflight.sh <FID> --next-after <security|integration>   저장된 판정으로 다음 skill 만 답한다(쓰지 않는다)
#        (cwd = 대상 repo 루트 또는 그 linked worktree)
# stdout: `GATE <gate> APPLY|SKIP|RECORDED <사유>` 3줄 + `NEXT: <skill>` 1줄 · --next-after 는 `NEXT:` 1줄만
# Exit:   0 판정함 · 1 판정 불가(FID·spec 부재 · §batch · 저장된 판정 없음) — 호출자는 종전 경로(skill 을 차례로 호출)로 간다
#
# 왜 필요한가: 세 게이트 skill(합 810줄)은 "해당 없음"을 판정하러 통째로 로드됐다. 과거 137건 중 실결함은 4건이고
#   integration 72%·performance 55% 가 SKIP 이었다(release-ready.sh 주석의 실측). 표면이 **분명히 없는** 경우만 여기서 SKIP 을
#   기록하고 skill 을 부르지 않는다.
# 판정 계약 — **생략 방향 오판 경로가 없어야 한다**: 근거 절을 찾지 못하거나, 변경 파일을 알 수 없거나, 신호가 하나라도 보이면
#   APPLY 다(skill 이 종전대로 로드돼 스스로 판정한다). SKIP 은 아래 조건이 모두 확인될 때만 낸다.
#     security    : 변경 파일이 전부 문서(file-class SoT — 플러그인 repo 의 skill·command·agent·hook 은 코드)
#     integration : 변경 파일이 전부 문서 · 또는 spec 전체와 변경 경로에 통합 표면 낱말이 하나도 없다
#     performance : spec 에 비기능(NFR) 절이 있고 그 절에 성능 임계값 낱말이 하나도 없다
#   SKIP 근거에는 spec.md 절 이름과 줄 범위를 인용한다(release-ready.sh 가 인용 없는 SKIP 을 NOT_READY 로 본다).
#   성능 게이트 skill 은 PR 생성 게이트를 담고 있어 SKIP 이어도 마지막에 호출된다 — 판정만 다시 하지 않는다.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 1
PLUGIN=$(cd "$HERE/../.." && pwd) || exit 1
FID="${1:-}"; MODE="${2:-}"; AFTER="${3:-}"

_no() { printf 'gate-preflight: %s — 종전 경로(게이트 skill 을 차례로 호출)로 진행\n' "$1" >&2; exit 1; }

printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || _no "FID 인자 오류"
case "$MODE" in ""|--next-after) ;; *) _no "알 수 없는 인자: $MODE" ;; esac

# worktree 에서 불려도 메인 worktree 의 .specops 로 판정·기록한다(review-skip-pass.sh 와 같다). 자기 경로는 이동 전에 잡았다.
# shellcheck source=/dev/null
. "$HERE/specops-root.sh" 2>/dev/null && specops_root_enter "$FID" 2>/dev/null || true
SPECOPS="${SPECOPS_ROOT:-.specops}"
D="$SPECOPS/$FID"
SPEC="$D/spec.md"; EV="$D/evidence.md"; STATE="$D/gate-preflight.txt"
[ -d "$D" ] || _no "FID 디렉터리 부재"

_next_from() {  # <security 판정> <integration 판정> <어느 게이트 뒤인가: verify|security|integration>
  case "$3" in
    verify)      [ "$1" = SKIP ] || { echo security-review-ko; return; }
                 [ "$2" = SKIP ] || { echo integration-test-ko; return; }
                 echo performance-test-ko ;;
    security)    [ "$2" = SKIP ] || { echo integration-test-ko; return; }
                 echo performance-test-ko ;;
    integration) echo performance-test-ko ;;
  esac
}

if [ "$MODE" = "--next-after" ]; then
  case "$AFTER" in security|integration) ;; *) _no "--next-after 는 security 또는 integration" ;; esac
  [ -f "$STATE" ] || _no "저장된 판정 없음"
  s=$(sed -n 's/^security=//p' "$STATE" | head -1); i=$(sed -n 's/^integration=//p' "$STATE" | head -1)
  case "$s/$i" in APPLY/APPLY|APPLY/SKIP|SKIP/APPLY|SKIP/SKIP) ;; *) _no "저장된 판정을 읽을 수 없음" ;; esac
  printf 'NEXT: %s\n' "$(_next_from "$s" "$i" "$AFTER")"
  exit 0
fi

[ -f "$SPEC" ] || _no "spec.md 부재"
grep -qE '^\*\*§batch\*\*:' "$SPEC" && _no "§batch FID (게이트는 /start-all 오케스트레이터 관할)"

# shellcheck source=/dev/null
. "$PLUGIN/scripts/_internal/file-class.sh" 2>/dev/null || _no "file-class.sh 를 읽을 수 없다"
# shellcheck source=/dev/null
. "$PLUGIN/scripts/_internal/risk-profile.sh" 2>/dev/null || _no "risk-profile.sh 를 읽을 수 없다"
# shellcheck source=/dev/null
. "$PLUGIN/scripts/skip-tracker.sh" 2>/dev/null || true
# skip-tracker.sh 는 source 되면 pipefail 을 켠다 — 그대로 두면 `printf … | grep -q` 가 SIGPIPE 로 "없음"이 되어
#   신호를 놓친다(생략 방향 오판). 이 스크립트의 판정 파이프는 pipefail 없이 돈다.
set +o pipefail
APPEND="$PLUGIN/scripts/session-progress-append.sh"

# 절 찾기 — `<시작줄> <끝줄> <제목>` · 못 찾으면 빈 출력. 같은 깊이 이상의 다음 제목 앞까지가 절이다.
_section() {  # <제목 정규식(ERE)>
  awk -v re="$1" '
    function lvl(s,  n) { n = 0; while (substr(s, n + 1, 1) == "#") n++; return n }
    /^#+ / {
      if (start && lvl($0) <= depth) { print start, NR - 1, title; done = 1; exit }
      if (!start && $0 ~ re) { start = NR; depth = lvl($0); title = $0; sub(/^#+ */, "", title) }
    }
    END { if (start && !done) print start, NR, title }
  ' "$SPEC"
}
_cite() {  # <_section 출력> → `§제목 L시작-끝`
  local a b t; a=${1%% *}; t=${1#* }; b=${t%% *}; t=${t#* }
  printf '§%s L%s-%s' "$(printf '%s' "$t" | cut -c1-40)" "$a" "$b"
}

scope_sec=$(_section '(범위|[Ss]cope)')
[ -n "$scope_sec" ] || scope_sec=$(_section '^#+ *2[.)]')
nfr_sec=$(_section '(NFR|비기능|[Nn]on-?[Ff]unctional)')

files=$(rp::collect_files 2>/dev/null | sed '/^$/d' | sort -u)
docs_all=no
if [ -n "$files" ]; then
  docs_all=yes
  if fc::is_plugin_repo; then _prc=0; else _prc=1; fi
  while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    fc::is_doc "$_f" "$_prc" || { docs_all=no; break; }
  done <<< "$files"
fi
nfiles=$(printf '%s\n' "$files" | sed '/^$/d' | wc -l | tr -d ' ')

# 통합 표면 낱말 — 하나라도 보이면 APPLY (skill 이 판정한다). 짧은 영문 낱말은 낱말 경계로만 잡는다.
INTEG_RE='(^|[^a-z])(api|ui|db|sql|rest|http|https|jwt|grpc|graphql|oauth|e2e)([^a-z]|$)|endpoint|엔드포인트|database|데이터베이스|테이블|쿼리|migration|마이그레이션|화면|페이지|컴포넌트|브라우저|렌더|라우팅|라우트|인증|인가|세션|토큰|외부|연동|webhook|웹훅|queue|메시지 큐|서버|서비스 간|모듈 간|playwright|cypress'
INTEG_PATH_RE='(routes?|controllers?|api|migrations?|pages|components|models|schema|views)/|\.(sql|tsx|jsx|vue|svelte|html)$'
# 성능 임계값 낱말 (performance-test-ko 의 신호 목록과 같은 종류)
PERF_RE='[0-9] ?ms([^a-z]|$)|(^|[^a-z])(rps|tps|qps|p50|p9[059]|lcp|cls|fcp|ttfb)([^a-z]|$)|latency|throughput|응답 ?시간|처리량|동시|부하|대용량|고트래픽|번들 크기|[0-9] ?초 (이내|이하|미만)|[0-9] ?(kb|mb)([^a-z]|$)'

sec=APPLY; sec_why=""; integ=APPLY; integ_why=""; perf=APPLY; perf_why=""

if [ -z "$files" ]; then
  sec_why="변경 파일을 알 수 없다"; integ_why="$sec_why"
elif [ -z "$scope_sec" ]; then
  sec_why="spec.md 에서 범위 절을 찾지 못했다"; integ_why="$sec_why"
else
  cite=$(_cite "$scope_sec")
  if [ "$docs_all" = yes ]; then
    sec=SKIP;   sec_why="$cite — 변경 파일 ${nfiles}개가 모두 문서, 실행 코드 표면 없음"
    integ=SKIP; integ_why="$cite — 변경 파일 ${nfiles}개가 모두 문서, 통합 표면 없음"
  else
    sec_why="코드 변경 있음(${nfiles}개 파일 중 비문서 포함)"
    if grep -qiE "$INTEG_RE" "$SPEC" 2>/dev/null || printf '%s\n' "$files" | grep -qiE "$INTEG_PATH_RE"; then
      integ_why="통합 표면 낱말·경로가 보인다"
    else
      integ=SKIP; integ_why="$cite — spec 과 변경 경로 ${nfiles}개에 API·DB·화면·외부 연동 낱말이 없다"
    fi
  fi
fi

if [ -z "$nfr_sec" ]; then
  perf_why="spec.md 에서 비기능(NFR) 절을 찾지 못했다"
else
  a=${nfr_sec%% *}; r=${nfr_sec#* }; b=${r%% *}
  if sed -n "${a},${b}p" "$SPEC" | grep -qiE "$PERF_RE"; then
    perf_why="NFR 절에 성능 임계값 낱말이 보인다"
  else
    perf=SKIP; perf_why="$(_cite "$nfr_sec") — 성능 임계값 없음"
  fi
fi

# 기록 — 이미 그 게이트의 판정이 evidence 에 있으면 다시 쓰지 않는다(재실행·재개 안전).
_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_record() {  # <gate> <evidence 제목> <진행 기록 단계> <접두> <사유>
  local gate="$1" hdr="$2" step="$3" tag="$4" why="$5"
  local prev=""
  command -v skip::verdicts >/dev/null 2>&1 && prev=$(skip::verdicts "$EV" "$gate" 2>/dev/null | tail -1)
  case "$prev" in
    "") ;;
    FAIL) return 1 ;;   # 실패 기록이 마지막이면 건너뛰지 않는다 — skill 이 다시 돈다
    *) return 2 ;;
  esac
  printf '\n## /%s — %s\n\n**결과**: SKIP\n**근거**: %s: SKIP — %s (gate-preflight.sh 사전 판정)\n' \
    "$hdr" "$(_ts)" "$tag" "$why" >> "$EV" || return 1
  [ -f "$APPEND" ] && bash "$APPEND" "$FID" "/$step" SKIP "$why (사전 판정)" >/dev/null 2>&1
  return 0
}
_emit() {  # <gate> <판정> <사유> <evidence 제목> <진행 기록 단계> <접두>
  local v="$2"
  if [ "$v" = SKIP ]; then
    _record "$1" "$4" "$5" "$6" "$3"
    case $? in
      1) v=APPLY; set -- "$1" "$v" "기록할 수 없거나 직전 판정이 FAIL — skill 이 판정한다" ;;
      2) printf 'GATE %s RECORDED 이미 판정 기록이 있다\n' "$1"; printf '%s' SKIP; return ;;
    esac
  fi
  printf 'GATE %s %s %s\n' "$1" "$v" "$3"
  printf '%s' "$v"
}

# _emit 은 마지막 줄 없이 최종 판정을 덧붙인다 — 표시 줄과 판정을 한 번에 받는다.
out=$(_emit security "$sec" "$sec_why" security-review security-review SECURITY);       sec=${out##*$'\n'};   printf '%s\n' "${out%$'\n'*}"
out=$(_emit integration "$integ" "$integ_why" integration-test integration-test INTEGRATION); integ=${out##*$'\n'}; printf '%s\n' "${out%$'\n'*}"
out=$(_emit performance "$perf" "$perf_why" performance-test performance-test PERFORMANCE);  perf=${out##*$'\n'};  printf '%s\n' "${out%$'\n'*}"

printf 'security=%s\nintegration=%s\nperformance=%s\n' "$sec" "$integ" "$perf" > "$STATE" 2>/dev/null || true
printf 'NEXT: %s\n' "$(_next_from "$sec" "$integ" verify)"
exit 0
