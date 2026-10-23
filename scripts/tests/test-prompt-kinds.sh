#!/usr/bin/env bash
# test-prompt-kinds.sh — prompt-kinds.sh 종류별 집계 · 본문 미출력 (20261023-speed-foundation)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 1
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
S="$PLUGIN/scripts/prompt-kinds.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
mkdir -p "$TD/proj"
F="$TD/proj/s1.jsonl"
_SECRETS=()   # 3자 이상 픽스처 문자열 — 출력 누출 검사(T1.d)
_a() { [ "${#1}" -ge 3 ] && _SECRETS+=("$1"); jq -nc --arg t "$1" --arg ts "$2" '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:$t}]}}' >> "$F"; }
_h() { [ "${#1}" -ge 3 ] && _SECRETS+=("$1"); jq -nc --arg t "$1" --arg ts "$2" '{type:"user",timestamp:$ts,origin:{kind:"human"},message:{content:$t}}' >> "$F"; }
_a "설계를 진행할까요?" "2026-10-23T01:00:00Z";  _h "진행해" "2026-10-23T01:01:00Z"
_a "다음 단계로 갈까요?" "2026-10-23T01:02:00Z"; _h "응" "2026-10-23T01:03:00Z"
_a "명세를 승인하시겠습니까?" "2026-10-23T01:04:00Z"; _h "Y" "2026-10-23T01:05:00Z"
_a "PR 을 생성할까요? [y/n]" "2026-10-23T01:06:00Z"; _h "y" "2026-10-23T01:07:00Z"
_a "머지할까요?" "2026-10-23T01:08:00Z"; _h "진행해" "2026-10-23T01:09:00Z"
_h "너의 의견대로 진행해" "2026-10-23T01:10:00Z"
_h "진행중이야?" "2026-10-23T01:11:00Z"
_h "아직 진행 중?" "2026-10-23T01:12:00Z"
_h "이제 무엇을 해야해?" "2026-10-23T01:13:00Z"
_h "이 함수가 왜 빈 값을 돌려주는지 원인을 찾아서 고쳐 줘" "2026-10-23T01:14:00Z"
jq -nc '{type:"user",timestamp:"2026-10-23T01:15:00Z",origin:{kind:"human"},isMeta:true,message:{content:"메타"}}' >> "$F"
OUT=$(bash "$S" --transcript-dir "$TD/proj" 2>&1); RC=$?
[ "$RC" = 0 ] && ok "T1.a rc 0" || nope "T1.a" "rc=$RC $OUT"
EXP=$'단계승인 3 30.0%\n외부승인 2 20.0%\n결정위임 1 10.0%\n진행확인 2 20.0%\n다음단계 1 10.0%\n기타짧음 0 0.0%\n전체 10 · 무정보 9 (90.0%)'
[ "$(printf '%s\n' "$OUT" | head -7)" = "$EXP" ] && ok "T1.b 종류 6줄 + 합계 줄 — 건수·비율 등가 (AC-3)" || nope "T1.b" "$OUT"
{ [ "$(printf '%s\n' "$OUT" | grep -c .)" = 8 ] && printf '%s\n' "$OUT" | sed -n 8p | grep -q '^규칙: '; } \
  && ok "T1.c 출력 정확히 8줄 · 끝 줄 규칙 요약" || nope "T1.c" "$OUT"
_leak() { local s l=""; for s in "${_SECRETS[@]}"; do printf '%s' "$1" | grep -qF -- "$s" && l="$l [$s]"; done; printf '%s' "$l"; }
{ [ -z "$(_leak "$OUT")" ] && [ -n "$(_leak "$OUT 설계를 진행할까요?")" ]; } \
  && ok "T1.d 출력에 픽스처 본문 없음 · 검사기 양성 대조 (AC-3)" || nope "T1.d" "$(_leak "$OUT")"
bash "$S" --transcript-dir "$TD/없음" >/dev/null 2>&1; [ $? = 2 ] && ok "T1.i 디렉터리 없음 rc 2" || nope "T1.i" "rc"
bash "$S" --bogus >/dev/null 2>&1; [ $? = 2 ] && ok "T1.j 알 수 없는 인자 rc 2" || nope "T1.j" "rc"
OUT2=$(bash "$S" --transcript-dir "$TD/proj" --since 20261024 2>&1)
printf '%s\n' "$OUT2" | grep -qx '전체 0 · 무정보 0 (0.0%)' && ok "T1.k --since 이후만 센다" || nope "T1.k" "$OUT2"
# 읽기 실패 — 끝 줄이 잘린 파일(쓰는 중인 transcript)은 집계에서 빼고 수를 보고한다(0건 위장 금지)
mkdir -p "$TD/projbad"; cp "$F" "$TD/projbad/ok.jsonl"
printf '%s' '{"type":"user","timestamp":"2026-10-23T03:00:00Z","origin":{"kind":"human"},"message":{"content":"y"' > "$TD/projbad/bad.jsonl"
OUT3=$(bash "$S" --transcript-dir "$TD/projbad" 2>/dev/null); ERR3=$(bash "$S" --transcript-dir "$TD/projbad" 2>&1 >/dev/null)
{ printf '%s\n' "$OUT3" | grep -q '^전체 10 · 무정보 9 ' && printf '%s\n' "$OUT3" | grep -qx '읽기 실패 1 파일' && printf '%s' "$ERR3" | grep -qF '읽기 실패 1 파일'; } \
  && ok "T1.l 읽지 못한 파일 수 보고 · 나머지는 집계 (spec §4)" || nope "T1.l" "out=$OUT3 err=$ERR3"
# 기본 디렉터리 — 실경로의 영숫자 아닌 글자(. _ / 포함)를 '-' 로
mkdir -p "$TD/a.b_c"; _enc=$(cd "$TD/a.b_c" && pwd -P | sed 's/[^A-Za-z0-9]/-/g')
mkdir -p "$TD/cfg/projects/$_enc"; cp "$F" "$TD/cfg/projects/$_enc/s1.jsonl"
o=$(cd "$TD/a.b_c" && CLAUDE_CONFIG_DIR="$TD/cfg" bash "$S" 2>&1 | sed -n 7p)
[ "$o" = "전체 10 · 무정보 9 (90.0%)" ] && ok "T1.m 기본 디렉터리 유도(. _ 도 '-')" || nope "T1.m" "$o"
mkdir -p "$TD/bin"; for c in bash sed grep awk cat; do ln -s "$(command -v "$c")" "$TD/bin/$c"; done
PATH="$TD/bin" "$TD/bin/bash" "$S" --transcript-dir "$TD/proj" >/dev/null 2>&1; [ $? = 3 ] && ok "T1.n jq 없음 rc 3" || nope "T1.n" "rc"
# 2차 픽스처 — 필터·직전 글·20자 경계·trim·여러 파일·여러 디렉터리·--since 경계 (손 계산 기대값)
F="$TD/proj2/s2.jsonl"; mkdir -p "$TD/proj2" "$TD/proj3"
_a2() { jq -nc --arg t "$1" '{type:"assistant",timestamp:"2026-10-23T02:00:00Z",message:{content:[{type:"text",text:$t}]}}' >> "$F"; }
_h2() { jq -nc --arg t "$1" --arg ts "${2:-2026-10-23T02:00:00Z}" '{type:"user",timestamp:$ts,origin:{kind:"human"},message:{content:$t}}' >> "$F"; }
_h2 "y" "2026-10-22T23:00:00Z"                       # --since 경계: 전날 → --since 20261023 에서 빠진다
_a2 "PR 을 생성할까요?"
jq -nc '{type:"assistant",timestamp:"2026-10-23T02:00:00Z",message:{content:[{type:"tool_use",name:"Bash",input:{command:"ls"}}]}}' >> "$F"
jq -nc '{type:"assistant",timestamp:"2026-10-23T02:00:00Z",message:{content:[{type:"thinking",thinking:"..."}]}}' >> "$F"
_h2 "y"                                               # 직전 글 = PR (tool_use·thinking 행은 글이 아니다) → 외부승인
jq -nc '{type:"user",timestamp:"2026-10-23T02:00:00Z",origin:{kind:"task-notification"},message:{content:"y"}}' >> "$F"   # human 아님 → 제외
jq -nc '{type:"user",timestamp:"2026-10-23T02:00:00Z",origin:{kind:"human"},message:{content:[{type:"text",text:"응"},{type:"image",source:{}}]}}' >> "$F"   # content 배열 → 제외
_a2 "테스트를 다시 돌릴까요?"
_h2 "응"                                              # 직전 글에 PR 없음 → 단계승인 (누적 글 변이면 외부승인)
_h2 $'  응 \n'                                        # 앞뒤 공백 → trim 후 단계승인
_h2 "가나다라마바사아자차카타파하거너더러머버"           # 정확히 20자 → 기타짧음
_h2 "가나다라마바사아자차카타파하거너더러머버서"         # 21자 → 정보있음
_a2 "PRD 를 검토할까요?"
_h2 "y"                                               # PR 은 낱말 단위 — PRD 는 외부승인 아님 → 단계승인
F="$TD/proj2/s3.jsonl"; _h2 "알아서 해"                # 같은 디렉터리의 둘째 파일 → 결정위임
F="$TD/proj3/s4.jsonl"; _h2 "다음은?"                  # 둘째 --transcript-dir → 다음단계
EXP2a=$'단계승인 4 44.4%\n외부승인 1 11.1%\n결정위임 1 11.1%\n진행확인 0 0.0%\n다음단계 1 11.1%\n기타짧음 1 11.1%\n전체 9 · 무정보 8 (88.9%)'
EXP2b=$'단계승인 3 37.5%\n외부승인 1 12.5%\n결정위임 1 12.5%\n진행확인 0 0.0%\n다음단계 1 12.5%\n기타짧음 1 12.5%\n전체 8 · 무정보 7 (87.5%)'
o=$(bash "$S" --transcript-dir "$TD/proj2" --transcript-dir "$TD/proj3" 2>&1 | head -7)
[ "$o" = "$EXP2a" ] && ok "T2.a 필터·직전 글·20자 경계·trim·PR 낱말·여러 파일·여러 디렉터리" || nope "T2.a" "$o"
o=$(bash "$S" --transcript-dir "$TD/proj2" --transcript-dir "$TD/proj3" --since 20261023 2>&1 | head -7)
[ "$o" = "$EXP2b" ] && ok "T2.b --since 당일 포함 · 전날 제외" || nope "T2.b" "$o"
finish
