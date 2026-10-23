#!/usr/bin/env bash
# prompt-kinds.sh — 사람 프롬프트를 종류별로 센다 (읽기 전용 관측 · 20261023-speed-foundation)
# Usage: bash scripts/prompt-kinds.sh [--since YYYYMMDD] [--transcript-dir DIR]...
#   기본 디렉터리 = ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<현재 실경로의 영숫자 아닌 글자를 '-' 로>
# 출력: 종류별 "<종류> <건수> <비율%>" 줄 + "전체 N · 무정보 M (P%)" 줄 + 판정 규칙 요약 — 프롬프트·assistant 본문은 내지 않는다.
# 대상: type=user · origin.kind=human · isMeta 거짓 · message.content 가 문자열. 앞뒤 공백을 뗀 길이 20자 이하만 분류한다(긴 프롬프트는 "정보 있음").
# 외부승인 = 짧은 승인인데 직전 assistant 글에 PR(낱말)·머지·merge·발행·릴리즈·release·push·비용 이 있다.
# rc: 0 집계(0건 포함) · 2 인자 오류·디렉터리 없음 · 3 jq 없음 · 읽지 못한 파일은 빼고 "읽기 실패 N 파일" 줄 + stderr 경고(rc 0)
set -u
die() { echo "prompt-kinds: $1" >&2; exit 2; }
SINCE=""; DIRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --since) [ $# -ge 2 ] || die "--since 값 없음"; [[ "$2" =~ ^[0-9]{8}$ ]] || die "--since 는 YYYYMMDD"; SINCE=$2; shift 2 ;;
    --transcript-dir) [ $# -ge 2 ] || die "--transcript-dir 값 없음"; DIRS+=("$2"); shift 2 ;;
    *) die "알 수 없는 인자: $1" ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "prompt-kinds: jq 없음" >&2; exit 3; }
if [ "${#DIRS[@]}" -eq 0 ]; then
  DIRS+=("${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')")
fi
for d in "${DIRS[@]}"; do [ -d "$d" ] || die "디렉터리 없음: $d"; done
SINCE_ISO=""; [ -n "$SINCE" ] && SINCE_ISO="${SINCE:0:4}-${SINCE:4:2}-${SINCE:6:2}"
kinds=$(for d in "${DIRS[@]}"; do
  for f in "$d"/*.jsonl; do
    [ -f "$f" ] || continue
    jq -rn --arg since "$SINCE_ISO" '
      def short: (gsub("^\\s+|\\s+$"; "")) as $t | ($t | length) <= 20;
      def kind($t; $prev):
        ($t | gsub("^\\s+|\\s+$"; "")) as $s
        | if ($s | test("의견대로|추천대로|알아서|너의 의견|네 의견")) then "결정위임"
          elif ($s | test("진행\\s*중|아직")) then "진행확인"
          elif ($s | test("이제 뭐|이제 무엇|다음은|뭐 해|무엇을 해")) then "다음단계"
          elif ($s | test("^(y|Y|yes|Yes|ok|OK|응|네|넵|ㅇㅇ|ㅇ|좋아|승인|[0-9]|진행|진행해|계속|계속해|계속진행해|이어서.*|추천대로)[.!]?$")) then
            (if ($prev | test("(^|[^A-Za-z])PR([^A-Za-z]|$)|머지|merge|발행|릴리즈|release|push|비용")) then "외부승인" else "단계승인" end)
          else "기타짧음" end;
      reduce (inputs) as $r ({prev:"", out:[]};
        if $r.type == "assistant" then
          (([$r.message.content[]? | select(.type=="text") | .text] | join(" ")) as $t | if ($t | length) > 0 then .prev = $t else . end)
        elif ($r.type == "user" and ($r.origin.kind? == "human") and ($r.isMeta != true) and (($r.message.content | type) == "string")
              and ($since == "" or (($r.timestamp // "") >= $since))) then
          .out += [ if ($r.message.content | short) then kind($r.message.content; .prev) else "정보있음" end ]
        else . end)
      | .out[]' "$f" 2>/dev/null || echo "읽기실패"   # 잘린 줄 등 — 0건으로 위장하지 않고 센다
  done
done)
bad=$(printf '%s\n' "$kinds" | grep -cx '읽기실패' || true)
kinds=$(printf '%s\n' "$kinds" | grep -vx '읽기실패' || true)
total=$(printf '%s\n' "$kinds" | grep -c . || true)
pct() { [ "$total" -gt 0 ] && awk -v a="$1" -v b="$total" 'BEGIN{printf "%.1f", a*100/b}' || echo "0.0"; }
info=0
for k in 단계승인 외부승인 결정위임 진행확인 다음단계 기타짧음; do
  n=$(printf '%s\n' "$kinds" | grep -cx "$k" || true)
  info=$((info + n))
  echo "$k $n $(pct "$n")%"
done
echo "전체 $total · 무정보 $info ($(pct "$info")%)"
echo "규칙: 사람 프롬프트(origin=human·isMeta 아님)만 · 20자 이하만 분류 · 외부승인 = 직전 assistant 글에 PR·머지·merge·발행·릴리즈·release·push·비용 · 본문 미출력"
if [ "$bad" -gt 0 ]; then
  echo "읽기 실패 $bad 파일"
  echo "prompt-kinds: 읽기 실패 $bad 파일 — 집계에서 빠졌다" >&2
fi
