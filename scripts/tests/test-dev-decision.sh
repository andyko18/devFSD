#!/usr/bin/env bash
# dev-decision.sh — 개발 구간에서 묻지 않고 정한 결정의 기록·끝 보고 (20261008-dev-no-ask)
#   개발 중 질문을 없애는 대신, 정한 것을 빠짐없이 남겨 PR 게이트에서 보여 준다. 기록이 빠지면 사용자는
#   무엇이 자기 대신 정해졌는지 모른 채 PR 을 승인한다 — 그래서 기록·출력 형식을 스크립트로 고정한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

DD="$PLUGIN/scripts/dev-decision.sh"
[ -f "$DD" ] || { nope "T0 스크립트 존재" "부재: $DD"; finish; }
ok "T0 스크립트 존재"

TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
FID=20261008-dd-case
mkdir -p "$TD/.specops/$FID"
F="$TD/.specops/$FID/dev-decisions.md"
run() { ( cd "$TD" && bash "$DD" "$@" ); }

# T1: add — 파일 생성 + 1줄
out=$(run add "$FID" backlog "대문자 확장자 파일 누락은 다음 FID 로 넘김" "이번 FID 이전부터 있던 결함" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -f "$F" ] && grep -q '^# 개발 중 결정' "$F" \
  && grep -qE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z \[backlog\] 대문자 확장자 파일 누락은 다음 FID 로 넘김 — 이번 FID 이전부터 있던 결함$' "$F" \
  && ok "T1 add → 머리말 + 기록 1줄(시각·종류·결정·근거)" || nope "T1" "rc=$rc out=$out $(cat "$F" 2>/dev/null)"

# T2: 두 번째 add 는 덧붙인다(덮어쓰지 않는다) · 근거 생략 허용
run add "$FID" order "리뷰를 적재보다 먼저 진행" >/dev/null 2>&1
[ "$(grep -c '^- ' "$F")" = 2 ] && grep -qE '\[order\] 리뷰를 적재보다 먼저 진행$' "$F" \
  && [ "$(grep -c '^# 개발 중 결정' "$F")" = 1 ] \
  && ok "T2 덧붙이기 · 근거 생략 · 머리말 1회" || nope "T2" "$(cat "$F")"

# T3: 종류는 정해진 목록만
for k in fixed backlog order retry skip approval; do
  run add "$FID" "$k" "종류 $k" >/dev/null 2>&1 || { nope "T3 종류 $k" "거부됨"; }
done
out=$(run add "$FID" whatever "x" 2>&1); rc=$?
[ "$rc" != 0 ] && ! grep -q '\[whatever\]' "$F" \
  && ok "T3 허용 종류 6개 통과 · 그 밖은 거부" || nope "T3" "rc=$rc out=$out"

# T4: 줄바꿈이 든 입력은 한 줄로 접는다(기록 1건 = 1줄 — 끝 보고의 건수가 틀어지지 않게)
before=$(grep -c '^- ' "$F")
run add "$FID" fixed "$(printf '첫 줄\n둘째 줄')" "$(printf '근거\n- 2099-01-01T00:00:00Z [approval] 위조')" >/dev/null 2>&1
after=$(grep -c '^- ' "$F")
[ "$after" = $((before + 1)) ] && ! grep -q '^- 2099' "$F" \
  && ok "T4 줄바꿈 입력 → 1줄 (기록 위조 줄 불가)" || nope "T4" "before=$before after=$after"

# T5: 잘못된 입력 — FID 형식·빈 결정·FID 디렉터리 부재
#   형식 위반 FID 는 **그 이름의 디렉터리가 실제로 있어도** 거부해야 한다 — 디렉터리 검사가 대신 막아 주는 입력(../evil)만으로는
#   FID 정규식을 지워도 통과한다(리뷰 M2).
mkdir -p "$TD/.specops/BADFID" "$TD/.specops/memory"
out=$(run add "BADFID" backlog "x" 2>&1); r1=$?
o1b=$(run add "memory" backlog "x" 2>&1); r1b=$?
out=$(run add "$FID" backlog "" 2>&1); r2=$?
o3=$(run add 20261008-no-such-dir backlog "x" 2>&1); r3=$?
[ "$r1" != 0 ] && [ "$r1b" != 0 ] && [ ! -e "$TD/.specops/BADFID/dev-decisions.md" ] && [ ! -e "$TD/.specops/memory/dev-decisions.md" ] \
  && printf '%s' "$o1b" | grep -q 'invalid FID' \
  && ok "T5a FID 형식 위반 → 그 디렉터리가 있어도 거부(memory/ 등에 쓰지 않는다)" || nope "T5a" "r1=$r1 r1b=$r1b o=$o1b"
[ "$r2" != 0 ] && ok "T5b 빈 결정 → 거부" || nope "T5b" "r2=$r2"
[ "$r3" != 0 ] && [ ! -e "$TD/.specops/20261008-no-such-dir" ] && printf '%s' "$o3" | grep -q 'FID 디렉터리 부재' \
  && ok "T5c FID 디렉터리 부재 → 사유를 밝혀 거부(디렉터리를 새로 만들지 않는다)" || nope "T5c" "r3=$r3 o=$o3"

# T6: 심볼릭 링크 대상에는 쓰지 않는다
FID2=20261008-dd-link
mkdir -p "$TD/.specops/$FID2"; printf 'keep\n' > "$TD/outside.md"
ln -s "$TD/outside.md" "$TD/.specops/$FID2/dev-decisions.md"
out=$(run add "$FID2" backlog "x" 2>&1); rc=$?
[ "$rc" != 0 ] && [ "$(cat "$TD/outside.md")" = keep ] \
  && ok "T6 심볼릭 링크 → 거부(링크 밖 파일 무변경)" || nope "T6" "rc=$rc $(cat "$TD/outside.md")"

# T7: show — 종류별 건수 요약 + 전 줄. 이 스크립트가 쓴 형식의 줄만 센다(손으로 끼운 줄·모르는 종류는 건수·요약·목록 어디에도 없다)
n=$(grep -c '^- ' "$F")
printf -- '- 손으로 쓴 줄\n- 2026-10-08T00:00:00Z [foo] 모르는 종류\n' >> "$F"
out=$(run show "$FID" 2>&1); rc=$?
printf '%s' "$out" | grep -q '손으로 쓴 줄\|모르는 종류' && { nope "T7 형식 밖 줄" "show 에 섞임: $out"; }
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "개발 중 결정 ${n}건" \
  && printf '%s' "$out" | grep -q 'backlog' && [ "$(printf '%s\n' "$out" | grep -c '^- ')" = "$n" ] \
  && ok "T7 show → 총 건수 + 기록 전 줄(요약으로 줄이지 않는다)" || nope "T7" "rc=$rc n=$n out=$out"

# T8: show — 기록이 없으면 '없음' 을 명시한다("0건" 과 "집계 안 함" 은 다르다)
FID3=20261008-dd-empty; mkdir -p "$TD/.specops/$FID3"
out=$(run show "$FID3" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '개발 중 결정 0건' \
  && ok "T8 기록 없음 → '0건' 명시 · rc 0" || nope "T8" "rc=$rc out=$out"

# T10: 남는 인자·모르는 옵션은 조용히 무시하지 않는다
o1=$(run show "$FID" --bogus 2>&1); r1=$?
o2=$(run add "$FID" order 따옴표 없이 쓴 긴 결정 문장 2>&1); r2=$?
[ "$r1" != 0 ] && [ "$r2" != 0 ] && ok "T10 모르는 옵션·남는 인자 → 거부" || nope "T10" "r1=$r1 r2=$r2"

# T11: 하위 디렉터리에서 불러도 repo 의 .specops 에 쓴다 (구현자는 src/ 아래에서 작업한다)
G=$(mktemp -d); FIDG=20261008-dd-sub
( cd "$G" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git init -q && mkdir -p ".specops/$FIDG" src/deep ) >/dev/null 2>&1
( cd "$G/src/deep" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && bash "$DD" add "$FIDG" order "하위 디렉터리에서 기록" ) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q '하위 디렉터리에서 기록' "$G/.specops/$FIDG/dev-decisions.md" 2>/dev/null && [ ! -e "$G/src/deep/.specops" ] \
  && ok "T11 하위 디렉터리 호출 → repo 루트의 .specops 에 기록" || nope "T11" "rc=$rc"
rm -rf "$G"

# T9: show --backlog — 다음 작업으로 넘긴 것만(PR 본문용)
out=$(run show "$FID" --backlog 2>&1)
[ -n "$out" ] && ! printf '%s' "$out" | grep -q '\[order\]' && printf '%s' "$out" | grep -q '\[backlog\]' \
  && ok "T9 show --backlog → backlog 줄만" || nope "T9" "out=$out"

finish
