#!/usr/bin/env bash
# specops-ko save-review-report — SubagentStop 훅 (matcher: spec-reviewer-ko|code-reviewer-ko) + PreToolUse 훅 (matcher: SubagentHandback — 두 리뷰어만).
# 리뷰어 최종 메시지의 <<<REVIEW …>>> ~ <<<END>>> 블록을 .specops/<FID>/reviews/<tid>-<phase>-report.md 로
#   tid 별 저장하고(통과 판정이 아니면 -feedback.md 병기) exit 2 로 요약 재종료를 지시한다.
#   반환 도구(PreToolUse) 경로는 같은 저장 뒤 exit 0 이다 — exit 2 는 반환 자체를 막으므로 요약 재종료를 지시하지 않는다.
# stdin: SubagentStop JSON (cwd · stop_hook_active · last_assistant_message) 또는 PreToolUse JSON (cwd · tool_name · agent_type · tool_input.message — 저장 뒤 exit 0)
# Exit: 2 = 전 블록 저장 + 요약 지시(stderr → 서브에이전트) · 1 = 계약 위반 fail-open(사유 1줄 → 사용자 · 전문은 부모로) · 0 = 무동작 fail-open(인프라·파일 조작 · stderr 없음) · PreToolUse 경로는 2 를 쓰지 않는다
# 전부 아니면 무 (clarify Q1): 블록 하나라도 형식 오류면 _bail(exit 1 · 사유 1줄) · 대상 경로가 일반 파일 아님 ·
#   임시 쓰기 실패 · 이동 실패면 reviews/ 를 실행 전 상태로 되돌리고(이동 실패는 백업 복원) exit 0 —
#   요약을 요구하면 그 전문이 소실된다. 1·0 어느 쪽이든 비차단이라 전문은 부모에게 그대로 간다.
#   단 복원 cp 까지 실패한 파일은 되돌리지 못한다: 대상에는 이번 본문이 남고 옛 내용은 백업
#   (.<name>.bak.<pid>)으로 reviews/ 에 남긴다(지우지 않음).
# 본문은 자르거나 고치지 않고 옮긴다 — release-ready.sh 가 report 본문의 🔴 절·판정 메뉴를 읽는다.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(dirname "$script_dir")

bash "$plugin_root/scripts/_internal/is-hook-enabled.sh" save-review-report >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat 2>/dev/null || true)
_j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null || true; }
cwd=$(_j '.cwd // empty')
handback=0
if [ "$(_j '.hook_event_name // empty')" = "PreToolUse" ]; then
  # 반환 도구(SubagentHandback) 경로 — 반환 도구로 끝난 리뷰어는 보고서가 last_assistant_message 가 아니라
  #   이 도구의 tool_input.message 로 온다(공식 hooks 문서 SubagentStop 절). transcript 는 비동기 기록이라 읽지 않는다.
  #   matcher 가 도구 이름이라 모든 서브에이전트의 반환이 여기 온다 — 두 리뷰어가 아니거나 블록이 없으면 조용히 지나간다.
  #   저장 뒤에도 exit 0: PreToolUse 의 exit 2 는 반환 자체를 막는다(요약 재종료 지시 없음).
  [ "$(_j '.tool_name // empty')" = "SubagentHandback" ] || exit 0
  case "$(_j '.agent_type // empty')" in
    specops-ko:spec-reviewer-ko|specops-ko:code-reviewer-ko) ;;
    *) exit 0 ;;
  esac
  msg=$(_j '.tool_input.message // empty')
  grep -q '^<<<REVIEW ' <<<"$msg" || exit 0   # 파이프 금지 — pipefail 아래 grep -q 가 먼저 끝나면 printf 가 SIGPIPE 로 실패해 큰 메시지를 조용히 건너뛴다
  handback=1
else
  [ "$(_j '.stop_hook_active // false')" = "true" ] && exit 0
  msg=$(_j '.last_assistant_message // empty')
fi
{ [ -n "$cwd" ] && [ -n "$msg" ]; } || exit 0

work=$(mktemp -d 2>/dev/null) || exit 0
trap 'rm -rf "$work"' EXIT

# 계약 위반 — 사유를 stderr 1줄로 남기고 fail-open 종료한다.
#   exit 0 은 stderr 가 아무에게도 보이지 않는다(설치본: "Exit code 0 - stdout/stderr not shown").
#   exit 1 은 비차단 오류라 리뷰어 전문이 그대로 부모에게 가면서 사유만 사용자 transcript 에 뜬다.
#   transcript 에는 첫 줄만 표시되므로 사유는 1줄에 완결한다. stdout 은 쓰지 않는다
#   (stdout 에 JSON 을 쓰면 종료 코드가 통째로 무시된다).
_bail() { echo "save-review-report: $1 — 저장 건너뜀" >&2; exit 1; }

# 블록 분리 — <n>.meta(속성) · <n>.body(본문). 출력: 블록 수 또는 BAD(중첩·짝 없음)
count=$(printf '%s\n' "$msg" | awk -v dir="$work" '
  BEGIN { n = 0; inb = 0; bad = 0 }
  /^<<<REVIEW .*>>>[[:space:]]*$/ {
    if (inb) bad = 1
    n++; inb = 1
    hdr = $0; sub(/^<<<REVIEW /, "", hdr); sub(/>>>[[:space:]]*$/, "", hdr)
    print hdr > (dir "/" n ".meta"); close(dir "/" n ".meta")
    printf "" > (dir "/" n ".body")
    next
  }
  /^<<<END>>>[[:space:]]*$/ {
    if (!inb) bad = 1; else close(dir "/" n ".body")
    inb = 0; next
  }
  inb { print > (dir "/" n ".body") }
  END { if (inb) bad = 1; print (bad ? "BAD" : n) }')
case "$count" in ''|BAD|0) _bail "REVIEW 블록 없음 또는 열림·닫힘 짝 불일치" ;; esac

# 검증 — 속성 정규식 · 단일 FID · tid-phase 중복 · 빈(공백만) 본문 (하나라도 걸리면 _bail — exit 1 + 사유)
re='^fid=([0-9]{8}-[a-z0-9-]+) tid=(T[0-9]+) phase=([BC]) verdict=(PASS|READY_TO_MERGE|NEEDS_FIX|NEEDS_DISCUSSION)$'
fid=""; seen=" "; i=1
while [ "$i" -le "$count" ]; do
  meta=$(cat "$work/$i.meta")
  [[ "$meta" =~ $re ]] || _bail "meta 형식 불일치(fid·tid·phase·verdict 필요)"
  b_fid=${BASH_REMATCH[1]}; b_tid=${BASH_REMATCH[2]}; b_phase=${BASH_REMATCH[3]}; b_verdict=${BASH_REMATCH[4]}
  [ -n "$fid" ] || fid=$b_fid
  [ "$b_fid" = "$fid" ] || _bail "블록 간 FID 불일치"
  case "$seen" in *" $b_tid-$b_phase "*) _bail "tid-phase 중복" ;; esac
  seen="$seen$b_tid-$b_phase "
  body=$(<"$work/$i.body")
  [[ $body =~ [^[:space:]] ]] || _bail "본문이 비어 있음"
  printf '%s %s %s\n' "$b_tid" "$b_phase" "$b_verdict" > "$work/$i.key"
  i=$((i+1))
done

[ -d "$cwd/.specops/$fid" ] || _bail "FID 디렉터리 없음(cwd 확인)"
reviews="$cwd/.specops/$fid/reviews"
mkdir -p "$reviews" 2>/dev/null || exit 0

# 0단계: 저장 대상 이름 목록 + 대상 경로 검사 — 일반 파일이 아닌 기존 경로(디렉토리 등)면 mv 가 그 안으로
#   옮겨 거짓 "저장" 보고가 되므로 아무것도 쓰기 전에 전부 포기한다
names=""; i=1
while [ "$i" -le "$count" ]; do
  read -r tid phase verdict < "$work/$i.key"
  printf '%s %s\n' "$i" "$tid-$phase-report.md" >> "$work/plan"
  case "$verdict" in PASS|READY_TO_MERGE) ;; *) printf '%s %s\n' "$i" "$tid-$phase-feedback.md" >> "$work/plan" ;; esac
  i=$((i+1))
done
while read -r i name; do
  if [ -e "$reviews/$name" ] || [ -L "$reviews/$name" ]; then
    [ -f "$reviews/$name" ] || exit 0
  fi
  names="$names $name"
done < "$work/plan"

# 정리 — 이번 실행($$)의 임시·백업 파일만 지운다 (이름 목록 기준, glob 아님)
#   $1 = 백업을 남길 이름 목록(공백 구분 · 복원 실패분) — 그 이름의 임시 파일은 지운다
_cleanup() {
  local n keep=" ${1:-} "
  for n in $names; do
    rm -f "$reviews/.$n.tmp.$$" 2>/dev/null
    case "$keep" in *" $n "*) ;; *) rm -f "$reviews/.$n.bak.$$" 2>/dev/null ;; esac
  done
}

# 1단계: 임시 파일에 전부 쓰고, 기존 대상은 cp 로 백업한다 — 하나라도 실패하면 기존 파일 무접촉으로 종료
#   (백업·복원은 cp 만 쓴다: 복원 경로가 실패한 mv 와 같은 목적지라 mv 로 되돌리면 같은 이유로 또 실패할 수 있다)
while read -r i name; do
  if ! cp "$work/$i.body" "$reviews/.$name.tmp.$$" 2>/dev/null; then _cleanup; exit 0; fi
  if [ -f "$reviews/$name" ] && ! cp -p "$reviews/$name" "$reviews/.$name.bak.$$" 2>/dev/null; then _cleanup; exit 0; fi
done < "$work/plan"

# 2단계: 같은 디렉토리 안 이동(rename). 한 건이라도 실패하면 이미 옮긴 파일을 되돌리고(백업 있으면 복원 ·
#   없던 파일은 삭제) 요약을 요구하지 않고 exit 0 — 리뷰어 전문이 그대로 부모에게 가서 부모가 fallback 저장한다.
#   (되돌리지 않으면 옛 판정 report 가 남아 부모 fallback 이 발동하지 않는다)
saved=""; moved=""
for name in $names; do
  if ! mv -f "$reviews/.$name.tmp.$$" "$reviews/$name" 2>/dev/null; then
    keep=""
    for m in $moved $name; do
      if [ -f "$reviews/.$m.bak.$$" ]; then
        # 복원까지 실패하면 옛 내용은 그 백업에만 있다 — 지우지 않고 남긴다
        cp -p "$reviews/.$m.bak.$$" "$reviews/$m" 2>/dev/null || keep="$keep $m"
      elif [ "$m" != "$name" ]; then
        rm -f "$reviews/$m" 2>/dev/null
      fi
    done
    _cleanup "$keep"; exit 0
  fi
  moved="$moved $name"
  saved="$saved
- .specops/$fid/reviews/$name"
done
_cleanup
[ -n "$saved" ] || exit 0
[ "$handback" = 0 ] || exit 0

cat >&2 <<EOF
리뷰 보고서 전문을 저장했다:$saved

이제 부모에게 돌려줄 요약만 출력하고 끝내라. 보고서 본문을 다시 쓰지 말고 300토큰 이내로:
판정: <tid·phase 별 verdict>
Critical: <항목 1줄씩, 없으면 없음>
Important: <항목 1줄씩, 없으면 없음>
저장: <위 경로>
EOF
exit 2
