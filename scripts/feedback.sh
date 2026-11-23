#!/usr/bin/env bash
# feedback.sh — 사용 중 겪은 불편을 플러그인 저장소에 전하는 통로 (읽기 전용 집계 + 초안 파일 1개)
#
#   feedback.sh summary [--days N]              사용 요약 — 숫자만 (갈래별 건수·소요·중단 지점·차단·리뷰). 기본 최근 30일, 0 = 전체
#   feedback.sh context                         지금 상태 몇 줄 — 플러그인 버전·OS·최근 작업의 갈래와 마지막 단계·최근 차단 규칙 번호
#   feedback.sh draft [--summary] "<본문>"      초안 파일을 만든다(.specops/feedback/<시각>.md) — 본문 + context (+ summary)
#   feedback.sh draft [--summary] --stdin       본문을 표준 입력으로 받는다(따옴표·백틱이 든 본문에 안전하다)
#   feedback.sh submit <초안 파일>              GitHub 이슈로 올린다(gh 로그인 필요) — 못 올리면 직접 올릴 주소를 알려 준다
#
# rc: 0 = 성공 · 2 = 인자 오류·입력 없음 · 3 = .specops 없음(쓴 기록이 없다) · 4 = 올리지 못함(주소 안내는 한다)
#
# ★ 무엇을 싣지 않는가 — 올라가는 곳은 공개 저장소다. summary·context 는 **숫자와, 아래 목록에 있는 이름**만 낸다.
#   기록에서 읽은 글자를 그대로 내보내는 자리는 없다: 단계는 KNOWN_STAGES, 규칙은 KNOWN_RULES(또는 `R-숫자` 꼴),
#   종류는 block·warn·info 에 있을 때만 그 이름으로 내고 나머지는 전부 `(기타)` 로 센다(독립 리뷰 20261117 —
#   손으로 고친 기록의 `/secretword`·임의 rule_id 가 그대로 나갔다). 작업(FID) 이름 · 요청 문장 · 파일 경로 ·
#   프로젝트·저장소 이름 · 코드 · 차단된 명령 원문 · 리뷰 지적 본문은 읽어도 내보내지 않는다.
#   사용자가 직접 쓴 본문은 걸러낼 수 없다 — draft 와 submit 이 경로·주소·메일·비밀 값·작업 이름처럼 보이는 글자를
#   찾아 `WARN:` 으로 알리고, 올리기 전에 사람이 초안을 본다(commands/feedback.md — 자동 제출 없음).
#   초안 폴더에는 `.gitignore`(`*`)를 함께 둔다 — `.specops/` 를 git 으로 추적하는 프로젝트에서 초안이 커밋되지 않게.
#   test-feedback.sh F3 가 이 약속을 잠근다.
# awk 정규식에 구간 반복({n})을 쓰지 않는다 — mawk 에서 매칭 0건이다(test-hooks.sh T8.q).
set -u
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/.." && pwd)"
DEFAULT_REPO="andyko18/devFSD"
TAB="$(printf '\t')"
# 진행 기록(session-progress.md)에 실제로 쓰이는 단계 명령 — 이 밖의 낱말은 `(기타)` 로 센다
KNOWN_STAGES=" /specify /specify-review /clarify /analyze /plan /plan-draft /plan-expert /plan-review /tasks /decompose /approve /implement /review /request-review /receive-review /verify /security /security-review /integration /integration-test /performance /performance-test /demo /pr /lifecycle /finishing /basic /quick-fix /maintain /freework /init-project /design-screen /design-interface /release /merge /operate "
KNOWN_RULES=" BYPASS-ENV RELEASE_READY REVIEW-PRESENCE "
D4='[0-9][0-9][0-9][0-9]'; D2='[0-9][0-9]'

_die() { echo "feedback: $1" >&2; exit "${2:-2}"; }

# .specops 위치 — 지정(SPECOPS_ROOT) → 현재 폴더 → 저장소 최상위. 하위 폴더에서 불러도 찾는다.
_specops() {
  local top
  if [ -n "${SPECOPS_ROOT:-}" ]; then [ -d "$SPECOPS_ROOT" ] && { printf '%s' "$SPECOPS_ROOT"; return 0; }; return 1; fi
  [ -d .specops ] && { printf '%s' "$PWD/.specops"; return 0; }
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -d "$top/.specops" ] && { printf '%s' "$top/.specops"; return 0; }
  return 1
}

# linked worktree 에서 불렀는가 — 기록이 메인 폴더에 있으면 여기서는 일부만 보인다
_in_linked_worktree() {
  local g c
  g=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  c=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
  [ "$g" != "$c" ]
}

_version() {
  local v
  v=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)
  case "$v" in ''|*[!0-9A-Za-z.+-]*) echo "unknown" ;; *) printf '%s\n' "$v" ;; esac
}

# 올릴 저장소 — [host/]owner/name. FEEDBACK_REPO → plugin.json 의 repository·homepage → 기본값. 꼴이 아니면 rc 1
_repo() {
  local r
  r=$(sed -nE 's#^[[:space:]]*"(repository|homepage)"[[:space:]]*:[[:space:]]*"https://github\.com/([^"/]+/[^"/#]+).*#\2#p' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)
  r=${r%.git}
  r="${FEEDBACK_REPO:-${r:-$DEFAULT_REPO}}"
  printf '%s' "$r" | grep -Eq '^([A-Za-z0-9.-]+/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || return 1
  printf '%s' "$r"
}
_repo_host() { case "$1" in */*/*) printf '%s' "${1%%/*}" ;; *) printf 'github.com' ;; esac; }
_repo_path() { case "$1" in */*/*) printf '%s' "${1#*/}" ;; *) printf '%s' "$1" ;; esac; }

# FID 폴더의 갈래 — 폴더에 있는 산출물 이름만 본다(내용은 읽지 않는다)
_lane_of() {  # <FID 폴더>
  local d="$1"
  if [ -e "$d/basic-draft" ]; then echo promoted
  elif [ -f "$d/spec.md" ] && [ -f "$d/intent.md" ]; then echo full
  elif [ -f "$d/spec.md" ]; then echo basic
  elif [ -f "$d/tasks.md" ]; then echo quick
  else echo other; fi
}
_lane_ko() { case "$1" in basic) echo "기본" ;; promoted) echo "기본→풀 승격" ;; full) echo "풀" ;; quick) echo "quick-fix" ;; -) echo "-" ;; *) echo "기타" ;; esac; }

_stage_safe() { case "$KNOWN_STAGES" in *" $1 "*) printf '%s' "$1" ;; *) printf '(기타)' ;; esac; }
_rule_safe() {
  case "$KNOWN_RULES" in *" $1 "*) printf '%s' "$1"; return ;; esac
  if printf '%s' "$1" | grep -Eq '^R-[0-9]{1,2}(-[A-Z]{1,12})?$'; then printf '%s' "$1"; else printf '(기타)'; fi
}
_sev_safe() { case "$1" in block|warn|info) printf '%s' "$1" ;; *) printf '(기타)' ;; esac; }

# 진행 기록에서 FID 마다 한 줄: <FID>\t<첫 시각 분>\t<마지막 시각 분>\t<끝났나 0|1>\t<마지막 단계 명령>
#   기록 규약: "## <FID> …" 절 아래 "- YYYY-MM-DD HH:MM /명령 상태 (…)". 괄호 안 본문은 읽지 않는다.
#   같은 FID 의 절이 둘이어도 한 작업으로 합친다. 마지막 단계 = 시각이 가장 늦은 줄(같으면 먼저 나온 줄 — 새 줄이 위다).
_ledger_rows() {  # <진행 기록 파일>
  awk -v FIDRE="^$D4$D4-[a-z0-9-]+\$" -v LINERE="^- $D4-$D2-$D2 $D2:$D2 /" '
    function mins(d, t,   a, b, y, m, dd, n) {
      split(d, a, "-"); split(t, b, ":"); y = a[1] + 0; m = a[2] + 0; dd = a[3] + 0
      if (m < 3) { y--; m += 12 }
      n = 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + dd
      return n * 1440 + b[1] * 60 + b[2]
    }
    /^## / { fid = ""; if ($2 ~ FIDRE) fid = $2; next }
    fid != "" && $0 ~ LINERE {
      t = mins($2, $3)
      if (!(fid in n)) { n[fid] = 0; lo[fid] = t; hi[fid] = t; last[fid] = $4; order[++k] = fid }
      if (t > hi[fid]) { hi[fid] = t; last[fid] = $4 }
      if (t < lo[fid]) lo[fid] = t
      n[fid]++
      if ($0 ~ /\/lifecycle DONE|\/finishing 완료|PR #[0-9]+ 생성|DONE \(PR/) done[fid] = 1
    }
    END { for (i = 1; i <= k; i++) { f = order[i]; printf "%s\t%d\t%d\t%d\t%s\n", f, lo[f], hi[f], done[f] + 0, last[f] } }
  ' "$1" 2>/dev/null
}

_median() {  # stdin: 숫자 한 줄씩 → 중앙값(없으면 -)
  sort -n | awk '{ a[NR] = $1 } END { if (NR == 0) { print "-"; exit } if (NR % 2) print a[(NR + 1) / 2]; else printf "%d\n", (a[NR / 2] + a[NR / 2 + 1]) / 2 }'
}

_cutoff() {  # <days> → YYYYMMDD (0·계산 불가면 00000000 = 전부)
  local n="$1"
  [ "$n" -gt 0 ] 2>/dev/null || { echo 00000000; return; }
  date -v-"$n"d +%Y%m%d 2>/dev/null || date -d "$n days ago" +%Y%m%d 2>/dev/null || echo 00000000
}

# friction-log 여러 파일(stdin) → "<ts>\t<rule_id>\t<severity>" — 규칙 번호·종류·시각만 읽는다(evidence_snippet 은 읽지 않는다).
#   jq 가 있으면 줄마다 JSON 으로 읽는다(필드 순서·한 줄 여러 객체·이스케이프에 안전). 없으면 정해진 필드 순서의 줄만 읽는다.
#   어느 쪽이든 값은 내보내기 전에 _rule_safe·_sev_safe 를 거친다.
_friction_rows() {
  if command -v jq >/dev/null 2>&1; then
    jq -Rr 'fromjson? | select(type == "object") | [(.ts // "" | tostring), (.rule_id // "" | tostring), (.severity // "" | tostring)] | @tsv' 2>/dev/null
  else
    sed -n 's/^{"ts":"\([0-9TZ:.+-]*\)","fid":"[^"]*","rule_id":"\([A-Za-z0-9_-]*\)","principle":[0-9]*,"severity":"\([a-z]*\)".*/\1	\2	\3/p'
  fi | awk -F'\t' 'NF == 3 && $1 ~ /^[0-9TZ:.+-]*$/'
}

cmd_summary() {
  local days=30 sp cut lane d fid n_all=0 tmp n dn r s
  while [ $# -gt 0 ]; do
    case "$1" in
      --days) [ $# -ge 2 ] || _die "--days 에 숫자가 필요하다"; days="$2"; shift 2 ;;
      *) _die "summary: 모르는 인자" ;;
    esac
  done
  case "$days" in ''|*[!0-9]*) _die "--days 는 0 이상의 정수다" ;; esac
  sp=$(_specops) || _die ".specops 가 없다 — 이 프로젝트에는 쓴 기록이 없다" 3
  cut=$(_cutoff "$days")
  tmp=$(mktemp -d) || _die "임시 폴더를 만들 수 없다"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  : > "$tmp/fids"; : > "$tmp/rows"; : > "$tmp/fr"; : > "$tmp/mt"; : > "$tmp/rv"
  [ -f "$sp/session-progress.md" ] && [ ! -L "$sp/session-progress.md" ] && _ledger_rows "$sp/session-progress.md" > "$tmp/rows"
  for d in "$sp"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*/; do
    d=${d%/}
    [ -d "$d" ] && [ ! -L "$d" ] || continue          # 링크는 바깥을 가리킬 수 있다 — 읽지 않는다
    fid=${d##*/}
    printf '%s' "$fid" | grep -Eq '^[0-9]{8}-[a-z0-9-]+$' || continue
    [ "${fid%%-*}" -ge "$cut" ] 2>/dev/null || continue
    printf '%s\t%s\n' "$fid" "$(_lane_of "$d")" >> "$tmp/fids"
    n_all=$((n_all + 1))
    [ -f "$d/friction-log.jsonl" ] && [ ! -L "$d/friction-log.jsonl" ] && cat "$d/friction-log.jsonl" >> "$tmp/fr"
    [ -f "$d/metrics.jsonl" ] && [ ! -L "$d/metrics.jsonl" ] && cat "$d/metrics.jsonl" >> "$tmp/mt"
    [ -d "$d/reviews" ] && [ ! -L "$d/reviews" ] && ls "$d/reviews" 2>/dev/null >> "$tmp/rv"
  done

  echo "## 사용 요약"
  echo
  echo "- 플러그인 버전: $(_version)"
  echo "- 환경: $(uname -s 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
  if [ "$days" -gt 0 ]; then echo "- 기간: 최근 ${days}일"; else echo "- 기간: 전체"; fi
  echo "- 작업 수: $n_all"
  echo
  echo "### 갈래별"
  echo
  echo "| 갈래 | 작업 | 진행 기록 있음 | 끝냄 | 소요 중앙값(분) |"
  echo "|---|---|---|---|---|"
  for lane in basic promoted full quick other; do
    awk -F'\t' -v L="$lane" -v DUR="$tmp/dur" '
         BEGIN { printf "" > DUR }
         NR == FNR { if ($2 == L) { want[$1] = 1; n++ } next }
         ($1 in want) { rec++; if ($4 == 1) dn++; print $3 - $2 >> DUR }
         END { printf "%d\t%d\t%d\n", n + 0, rec + 0, dn + 0 }' "$tmp/fids" "$tmp/rows" > "$tmp/cnt"
    IFS="$TAB" read -r n r dn < "$tmp/cnt"
    [ "$n" -gt 0 ] || continue
    echo "| $(_lane_ko "$lane") | $n | $r | $dn | $(_median < "$tmp/dur") |"
  done
  echo
  echo "끝냄·소요는 진행 기록이 있는 작업만 센다. 소요는 기록의 첫 줄부터 마지막 줄까지다 — 사람이 자리를 비운 시간이 섞인다."
  echo
  echo "### 끝내지 못한 작업의 마지막 단계"
  echo
  awk -F'\t' 'NR == FNR { want[$1] = 1; next } ($1 in want) && $4 == 0 { print $5 }' "$tmp/fids" "$tmp/rows" > "$tmp/stuck0"
  : > "$tmp/stuck1"
  while IFS= read -r s; do _stage_safe "$s"; echo; done < "$tmp/stuck0" >> "$tmp/stuck1"
  if [ -s "$tmp/stuck1" ]; then
    echo "| 단계 | 작업 |"; echo "|---|---|"
    sort "$tmp/stuck1" | uniq -c | sort -rn | head -12 | while read -r n s; do echo "| \`$s\` | $n |"; done
  else
    echo "없음"
  fi
  echo
  echo "### 차단·경고 (규칙별)"
  echo
  _friction_rows < "$tmp/fr" > "$tmp/frr"
  if [ -s "$tmp/frr" ]; then
    : > "$tmp/frs"
    while IFS="$TAB" read -r s r lane; do printf '%s\t%s\n' "$(_rule_safe "$r")" "$(_sev_safe "$lane")"; done < "$tmp/frr" >> "$tmp/frs"
    echo "| 규칙 | 종류 | 횟수 |"; echo "|---|---|---|"
    sort "$tmp/frs" | uniq -c | while read -r n r lane; do echo "| $r | $lane | $n |"; done
  else
    echo "없음"
  fi
  echo
  echo "### 검증·리뷰"
  echo
  echo "- 검증 실행: 통과 $(grep -c '"phase":"verify".*"verdict":"PASS"' "$tmp/mt") · 실패 $(grep -c '"phase":"verify".*"verdict":"FAIL"' "$tmp/mt")"
  echo "- 훅 우회(BYPASS): $(grep -c '"phase":"governance-bypass"' "$tmp/mt")"
  echo "- 리뷰 보고서: 스펙 $(grep -c -- '-B-report\.md$' "$tmp/rv") · 코드 $(grep -c -- '-C-report\.md$' "$tmp/rv")"
  if _in_linked_worktree; then
    echo
    echo "worktree 에서 불렀다 — 기록이 메인 폴더에 있으면 이 표에 빠진다. 메인 폴더에서 다시 부른다."
  fi
  return 0
}

cmd_context() {
  local sp stage="-" lane="-" recent="없음" fid r out="" row d
  echo "## 상태"
  echo
  echo "- 플러그인 버전: $(_version)"
  echo "- 환경: $(uname -s 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
  if sp=$(_specops); then
    if [ -f "$sp/session-progress.md" ] && [ ! -L "$sp/session-progress.md" ]; then
      # 가장 위(최근) FID 절 — 그 작업의 마지막 단계
      row=$(_ledger_rows "$sp/session-progress.md" | head -1)
      fid=$(printf '%s' "$row" | cut -f1)
      if [ -n "$fid" ]; then
        stage=$(_stage_safe "$(printf '%s' "$row" | cut -f5)")
        [ -d "$sp/$fid" ] && [ ! -L "$sp/$fid" ] && lane=$(_lane_of "$sp/$fid")
      fi
    fi
    for r in $(
      for d in "$sp"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*/; do
        d=${d%/}
        [ -d "$d" ] && [ ! -L "$d" ] && [ -f "$d/friction-log.jsonl" ] && [ ! -L "$d/friction-log.jsonl" ] && cat "$d/friction-log.jsonl"
      done 2>/dev/null | _friction_rows | awk -F'\t' '$3 == "block"' | sort | tail -5 | cut -f2 | tr -cd 'A-Za-z0-9_\n-'
    ); do out="$out $(_rule_safe "$r")"; done
    [ -n "${out// /}" ] && recent="${out# }"
  else
    stage="(기록 없음)"
  fi
  echo "- 최근 작업의 갈래: $(_lane_ko "$lane")"
  echo "- 최근 작업의 마지막 단계: \`$stage\`"
  echo "- 최근 차단 규칙(최대 5): $recent"
}

# 사용자가 쓴 본문에서 공개하면 안 될 것처럼 보이는 글자를 찾는다 — 막지 않고 알린다(오탐이 잦은 추정으로 막으면 우회만 는다)
_scan_body() {
  local b="$1"
  printf '%s' "$b" | grep -Eq '(/Users/|/home/|/var/|/opt/|/root/|/tmp/|/private/|/Volumes/|/mnt/|~/|[A-Za-z]:\\|\\\\[A-Za-z0-9]|(^|[^A-Za-z0-9])[A-Za-z]:/[^/])' && echo "WARN: 본문에 파일 경로처럼 보이는 글자가 있다"
  printf '%s' "$b" | grep -Eq '[A-Za-z][A-Za-z0-9+.-]*://' && echo "WARN: 본문에 주소(URL·접속 문자열)가 있다"
  printf '%s' "$b" | grep -Eq '(^|[^0-9])[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)' && echo "WARN: 본문에 IP 주소처럼 보이는 글자가 있다"
  printf '%s' "$b" | grep -Eq '[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@.]{2,}' && echo "WARN: 본문에 메일 주소처럼 보이는 글자가 있다"
  printf '%s' "$b" | grep -Eq '(^|[^0-9])[0-9]{8}-[a-z0-9]+(-[a-z0-9]+)+' && echo "WARN: 본문에 작업 이름(FID)처럼 보이는 글자가 있다 — 하는 일이 드러난다"
  printf '%s' "$b" | grep -Eqi '(gh[pousr]_[A-Za-z0-9]{20,}|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{12,}|xox[abprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.|bearer[[:space:]]+[A-Za-z0-9._-]{12,}|github_pat_[A-Za-z0-9_]{20,}|sk_(live|test)_[A-Za-z0-9]{10,}|AIza[A-Za-z0-9_-]{20,}|glpat-[A-Za-z0-9_-]{16,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|basic[[:space:]]+[A-Za-z0-9+/=]{12,}|(token|secret|password|passwd|api[_-]?key|(secret|access|private)[_-]?key)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[^[:space:]"'"'"']{6,})' && echo "WARN: 본문에 비밀 값처럼 보이는 글자가 있다 — 지우고 올린다"
  return 0
}

# 초안 폴더 — .specops/feedback(커밋되지 않게 .gitignore 를 함께 둔다). .specops 가 없으면 나만 읽는 임시 폴더.
_draft_dir() {
  local sp dir
  if sp=$(_specops); then
    dir="$sp/feedback"
    mkdir -p "$dir" || return 1
    [ -f "$dir/.gitignore" ] || printf '*\n' > "$dir/.gitignore" || return 1
  else
    dir=$(mktemp -d "${TMPDIR:-/tmp}/devfsd-feedback.XXXXXX") || return 1
  fi
  printf '%s' "$dir"
}

cmd_draft() {
  local body="" with_sum=0 from_stdin=0 got=0 dir f title n loc probe
  while [ $# -gt 0 ]; do
    case "$1" in
      --summary) with_sum=1 ;;
      --stdin) from_stdin=1 ;;
      *) [ "$got" = 0 ] || _die "draft: 본문은 한 인자로 준다"; body="$1"; got=1 ;;   # `-` 로 시작하는 본문도 본문이다
    esac
    shift
  done
  if [ "$from_stdin" = 1 ]; then [ "$got" = 0 ] || _die "draft: --stdin 과 본문 인자를 함께 줄 수 없다"; body=$(cat); fi
  [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || _die "본문이 비었다 — /feedback <겪은 일> 로 적는다"
  _repo >/dev/null || _die "올릴 저장소 이름이 [host/]owner/name 꼴이 아니다 (FEEDBACK_REPO)"
  dir=$(_draft_dir) || _die "초안 폴더를 만들 수 없다"
  # 같은 초에 두 번 불려도 앞 초안을 덮지 않는다
  f="$dir/$(date +%Y%m%d-%H%M%S).md"; n=1
  while [ -e "$f" ]; do n=$((n + 1)); f="$dir/$(date +%Y%m%d-%H%M%S)-$n.md"; done
  # 제목 — 본문 첫 줄의 앞 60자. 글자 단위로 자른다(바이트로 자르면 한글 한 글자가 반으로 갈린다).
  #   UTF-8 로케일을 못 쓰는 환경이면 자르지 않는다 — 깨진 글자를 올리느니 긴 제목이 낫다.
  title=$(printf '%s\n' "$body" | sed -n '/[^[:space:]]/{p;q;}' | tr -d '\r')
  title=$(
    for loc in en_US.UTF-8 C.UTF-8; do
      LC_ALL=$loc; probe="가"
      if [ "${#probe}" = 1 ]; then
        [ "${#title}" -gt 60 ] && title="${title:0:60}…"
        break
      fi
    done 2>/dev/null
    printf '%s' "$title"
  )
  {
    printf 'title: [feedback] %s\n\n' "$title"
    printf '## 겪은 일\n\n%s\n\n' "$body"
    cmd_context
    # 요약은 서브셸에서 — .specops 가 없어 요약이 끝나도(exit 3) 초안은 마저 쓴다
    if [ "$with_sum" = 1 ]; then echo; ( cmd_summary ) 2>/dev/null || echo "(사용 요약 없음 — 쓴 기록이 없다)"; fi
  } > "$f" || _die "초안을 쓸 수 없다"
  echo "DRAFT: $f"
  echo "REPO: $(_repo) (공개 저장소 — 올리면 누구나 본다)"
  _scan_body "$body"
}

cmd_submit() {
  local f="${1:-}" repo title body_f url out host path
  [ -n "$f" ] && [ -f "$f" ] && [ ! -L "$f" ] || _die "submit: 초안 파일이 없다 — 먼저 feedback.sh draft 로 만든다"
  # draft 가 만든 파일만 올린다 — 첫 줄이 제목 줄이고 "겪은 일"·"상태" 절이 있어야 한다(아무 파일이나 올리지 않는다)
  sed -n '1p' "$f" | grep -q '^title: \[feedback\] ' && grep -q '^## 겪은 일$' "$f" && grep -q '^## 상태$' "$f" \
    || _die "submit: feedback.sh draft 가 만든 초안이 아니다"
  repo=$(_repo) || _die "올릴 저장소 이름이 [host/]owner/name 꼴이 아니다 (FEEDBACK_REPO)"
  host=$(_repo_host "$repo"); path=$(_repo_path "$repo")
  title=$(sed -n '1s/^title: //p' "$f")
  body_f=$(mktemp) || _die "임시 파일을 만들 수 없다"
  # shellcheck disable=SC2064
  trap "rm -f '$body_f'" EXIT
  sed '1d' "$f" | sed '1{/^$/d;}' > "$body_f"
  # 올리기 직전에 한 번 더 본다 — 초안을 만든 뒤 손으로 고쳤을 수 있다
  #   제목 줄과 본문 전체를 본다 — 본문 안에 `## 상태` 줄이 있어도 거기서 끊기지 않게(20261123)
  _scan_body "$title"$'\n'"$(cat "$body_f")"
  url="https://$host/$path/issues/new?template=feedback.md"
  if command -v gh >/dev/null 2>&1 && gh auth status --hostname "$host" >/dev/null 2>&1; then
    # 라벨이 그 저장소에 없으면 gh 가 실패한다 — 라벨 없이 한 번 더 한다
    if out=$(gh issue create --repo "$host/$path" --title "$title" --body-file "$body_f" --label feedback 2>&1) \
       || out=$(gh issue create --repo "$host/$path" --title "$title" --body-file "$body_f" 2>&1); then
      rm -f "$f"          # 올린 초안은 남기지 않는다
      echo "SUBMITTED: $(printf '%s\n' "$out" | grep -E '^https://' | tail -1)"
      return 0
    fi
    echo "feedback: gh 로 올리지 못했다" >&2
  else
    echo "feedback: gh 가 없거나 $host 에 로그인돼 있지 않다" >&2
  fi
  echo "MANUAL: $url"
  echo "MANUAL-FILE: $f"
  echo "위 주소를 열어 초안 파일의 내용을 붙여 넣는다. GitHub 을 쓸 수 없으면 초안 파일을 그대로 전한다."
  return 4
}

case "${1:-}" in
  summary) shift; cmd_summary "$@" ;;
  context) shift; cmd_context ;;
  draft)   shift; cmd_draft "$@" ;;
  submit)  shift; cmd_submit "$@" ;;
  *) _die "사용법: feedback.sh summary [--days N] | context | draft [--summary] \"<본문>\"|--stdin | submit <초안 파일>" ;;
esac
