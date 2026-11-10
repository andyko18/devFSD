#!/usr/bin/env bash
# transcript-turns.sh — Claude Code transcript 에서 허용 필드만 뽑아 "epoch초 탭 종류 탭 값" 줄로 낸다 (프라이버시 경계 · 읽기 전용)
# Usage: transcript-turns.sh [--local] 파일...
# 종류: D = system/turn_duration (값 = durationMs, 없거나 음수·비숫자·7일(604800000) 초과면 0 — 깨진 큰 값이 구간 루프를 폭주시키지 않게) · H = 사람 프롬프트(origin.kind=human)
#       N = 알림이 연 턴(origin.kind=task-notification) · U = 그 밖(origin 부재·미인식 값) · F = 파일 경계(파일 사이에만, 값 0)
#       H·N·U 는 user 레코드 중 isMeta 가 거짓이고 message.content 가 문자열인 것만(도구 결과 배열·메타 주입은 제외), 값은 0.
#       E = 턴 끝 표지(system/stop_hook_summary) · A = 어시스턴트 기록(연속분은 첫 줄만) — 둘 다 값 0 이고, **D 가 한 건도 없는 파일에서만** 낸다
#         (Claude Code 2.1.312 무렵부터 turn_duration 이 기록되지 않는다 — 20261110 실측. D 가 있는 파일은 종전 출력 그대로다: 파일 단위 판정).
#         E 는 Stop 훅이 하나라도 있는 세션에만 남는다. 호출자는 E 마다 '직전 트리거(없으면 직전 E 뒤 첫 A) ~ E' 를 작업 구간으로 쓴다.
# 파일마다 시간순으로 정렬해 내고, 둘째 파일부터는 앞에 F 한 줄을 둔다 — 호출자가 세션 사이를 짝짓지 않게 하는 경계다.
# 한계: jq 는 여러 파일의 raw 입력을 이어 읽는다 — 끝 개행 없는 파일(기록 중인 활성 세션)의 마지막 줄은 다음 파일의 첫 줄과 합쳐져 둘 다 유실될 수 있다(파일별 기동은 AC-7 위반이라 감수).
# --local: epoch 대신 TZ 환경변수의 로컬 벽시계 초(jq localtime) — 원장(로컬 분)과 같은 기준으로 조인할 때 쓴다.
# rc: 0 · 2 = 인자 없음·알 수 없는 옵션·읽을 수 없는 파일 · 3 = jq 없음
#
# 프라이버시 계약: 읽는 키는 type·subtype·timestamp·durationMs·isMeta·isSidechain·origin.kind 와 message.content 의 **타입 검사**뿐이다.
#   턴 끝 표지(stop_hook_summary)와 어시스턴트 기록은 type·subtype **값**과 timestamp 만으로 판별한다 — 새로 읽는 키는 없고, 어시스턴트 본문·도구 입력·훅 요약의 다른 필드는 읽지 않는다.
#   출력은 파생값(종류 글자·숫자)만이고, 값 연산은 전부 try 로 감싸며 jq 의 stderr 는 버린다(jq 오류 문구는 문제 값을 그대로 찍는다).
set -u
LOCAL=0
case "${1:-}" in
  --local) LOCAL=1; shift ;;
  -*) echo "transcript-turns: 알 수 없는 옵션" >&2; exit 2 ;;
esac
[ "$#" -ge 1 ] || { echo "usage: transcript-turns.sh [--local] 파일..." >&2; exit 2; }
for f in "$@"; do
  { [ -f "$f" ] && [ -r "$f" ]; } || { echo "transcript-turns: 읽을 수 없는 파일" >&2; exit 2; }
done
command -v jq >/dev/null 2>&1 || { echo "transcript-turns: jq 없음" >&2; exit 3; }

# JQ-PROGRAM-BEGIN
jq -nRr --argjson loc "$LOCAL" '
  def kind:
    if .type == "user" then
      if ((.isMeta // false) == false) and ((.message | type) == "object") and ((.message.content | type) == "string") then
        (if (.origin | type) == "object" and .origin.kind == "human" then "H"
         elif (.origin | type) == "object" and .origin.kind == "task-notification" then "N"
         else "U" end)
      else empty end
    elif .type == "system" and .subtype == "turn_duration" then "D"
    elif .type == "system" and .subtype == "stop_hook_summary" then "E"
    elif .type == "assistant" then "A"
    else empty end;
  def norm:
    if any(.[]; .[1] == "D") then map(select(.[1] != "A" and .[1] != "E"))
    else . as $a | [ range(0; length) | select($a[.][1] != "A" or . == 0 or $a[. - 1][1] != "A") | $a[.] ]
    end;
  def ev:
    if type != "object" or ((.isSidechain // false) != false) then empty
    else
      (try (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null) as $t
      | if $t == null then empty else
          kind as $k
          | [ (if $loc == 1 then ($t | localtime | mktime) else $t end), $k,
              (if $k == "D" then (try (.durationMs | if type == "number" and . >= 0 and . <= 604800000 then floor else 0 end) catch 0) else 0 end) ]
        end
    end;
  reduce inputs as $l ({cur: null, buf: [], out: []};
    input_filename as $fn
    | (if .cur != null and .cur != $fn then .out += [(.buf | sort_by(.[0]) | norm)] | .buf = [] else . end)
    | .cur = $fn
    | .buf += [ ($l | try fromjson catch null) | ev ])
  | [ (.out + [.buf | sort_by(.[0]) | norm])[] | select(length > 0) ] as $g
  | $g | to_entries[]
  | (if .key > 0 then "0\tF\t0" else empty end), (.value[] | "\(.[0])\t\(.[1])\t\(.[2])")
' "$@" 2>/dev/null
# JQ-PROGRAM-END
