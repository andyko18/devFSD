#!/usr/bin/env bash
# test-review-saved.sh — review-saved.sh 판정 + implementing-ko 지시 잠금 (20261023-speed-l1-single)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 1
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
S="$PLUGIN/scripts/_internal/review-saved.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
FID=20261023-demo; R="$TD/.specops/$FID/reviews"; mkdir -p "$TD/.specops/$FID"
_rs() { OUT=$(SPECOPS_ROOT="$TD/.specops" bash "$S" "$@" 2>&1); RC=$?; }
_rs mark "$FID" B
{ [ "$RC" = 0 ] && [ -f "$R/.dispatched-B" ]; } && ok "R1.a mark 가 표지를 만든다" || nope "R1.a" "rc=$RC $OUT"
touch -t 202601010000 "$R/.dispatched-B"
printf 'x\n' > "$R/T1-B-report.md"
printf 'x\n' > "$R/T2-B-report.md"; touch -t 202501010000 "$R/T2-B-report.md"
_rs check "$FID" B T1 T2
{ [ "$RC" = 1 ] && [ "$OUT" = "T2" ]; } && ok "R1.b 낡은 T2 만 출력 · rc 1 (AC-6)" || nope "R1.b" "rc=$RC out=[$OUT]"
touch "$R/T2-B-report.md"
_rs check "$FID" B T1 T2
{ [ "$RC" = 0 ] && [ -z "$OUT" ]; } && ok "R1.c 둘 다 새것 → rc 0 · 출력 없음 (AC-6)" || nope "R1.c" "rc=$RC out=[$OUT]"
{ [ -f "$R/.dispatched-B" ] && [ -f "$R/T1-B-report.md" ] && [ -f "$R/T2-B-report.md" ]; } && ok "R1.c2 check 는 파일을 지우지 않는다" || nope "R1.c2"
_rs check "$FID" B T1 T3
{ [ "$RC" = 1 ] && [ "$OUT" = "T3" ]; } && ok "R1.d 없는 report 는 빠진 것" || nope "R1.d" "rc=$RC out=[$OUT]"
# 재dispatch — mark 가 기존 표지를 새로 고치고, 빠진 tid 여럿을 모두 순서대로 낸다
touch -t 202601020000 "$R/T1-B-report.md" "$R/T2-B-report.md"
_rs mark "$FID" B; _rs check "$FID" B T1 T2
{ [ "$RC" = 1 ] && [ "$OUT" = "$(printf 'T1\nT2')" ]; } && ok "R1.k 재dispatch: mark 가 표지를 새로 고친다 · 빠진 tid 2개 모두 (AC-6)" || nope "R1.k" "rc=$RC out=[$OUT]"
# 같은 초 — 표지보다 새것이 아니면 저장된 것으로 보지 않는다
touch -t 202601030000 "$R/.dispatched-B" "$R/T1-B-report.md"
_rs check "$FID" B T1
{ [ "$RC" = 1 ] && [ "$OUT" = "T1" ]; } && ok "R1.l 같은 시각 → 빠진 것(안전 방향)" || nope "R1.l" "rc=$RC out=[$OUT]"
printf 'x\n' > "$R/T1-C-report.md"
_rs check "$FID" C T1
{ [ "$RC" = 1 ] && [ "$OUT" = "T1" ]; } && ok "R1.e 표지 없음 + 보고서 있음 → rc 1 · 전 tid (AC-6)" || nope "R1.e" "rc=$RC out=[$OUT]"
_rs; [ "$RC" = 2 ] && ok "R1.f 인자 없음 rc 2" || nope "R1.f" "rc=$RC"
_rs check "$FID" X T1; [ "$RC" = 2 ] && ok "R1.g phase 오류 rc 2" || nope "R1.g" "rc=$RC"
_rs check 20261023-none B T1; [ "$RC" = 2 ] && ok "R1.h FID 디렉터리 없음 rc 2" || nope "R1.h" "rc=$RC"
_rs check "$FID" B; [ "$RC" = 2 ] && ok "R1.i tid 없음 rc 2" || nope "R1.i" "rc=$RC"
_rs check "$FID" B T1a; [ "$RC" = 2 ] && ok "R1.j tid 형식 오류 rc 2" || nope "R1.j" "rc=$RC"
mkdir -p "$TD/.specops/x"; _rs mark "../.specops/x" B
{ [ "$RC" = 2 ] && [ ! -d "$TD/.specops/x/reviews" ]; } && ok "R1.m ../ FID 거부 rc 2" || nope "R1.m" "rc=$RC"
mkdir -p "$TD/.specops/20261023-ro"; : > "$TD/.specops/20261023-ro/reviews"; _rs mark 20261023-ro B
[ "$RC" = 2 ] && ok "R1.n reviews 를 만들 수 없으면 rc 2" || nope "R1.n" "rc=$RC"
# implementing-ko 지시 — end-loaded 산출물 규약 절 안에 mark·check 와 rc 0 이면 다시 쓰지 않는다는 문장 (AC-6)
IMP="$PLUGIN/skills/implementing-ko/SKILL.md"
_s=$(awk '/^### end-loaded B\/C 산출물 규약/{f=1;next} f&&/^## /{exit} f' "$IMP")
{ printf '%s' "$_s" | grep -qF 'review-saved.sh mark <FID> <B|C>' && printf '%s' "$_s" | grep -qF 'review-saved.sh check <FID> <B|C> <tid>...' && printf '%s' "$_s" | grep -qF 'rc 0 이면 반환 도구 경로의 훅' && printf '%s' "$_s" | grep -qF 'rc 1 이면 출력된 tid 만'; } \
  && ok "R2.a implementing-ko 규약 절이 mark·check 를 지시 (AC-6)" || nope "R2.a" "절 안에 문장 없음"
grep -qF '반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장' "$IMP" && ok "R2.b 종전 fallback 문장 보존 (AC-R-1)" || nope "R2.b"
printf '%s\n' "$_s" | awk '{i=index($0,"review-saved.sh check"); j=index($0,"반환에 훅 요약이 없으면"); if(i&&j&&i<j) f=1} END{exit !f}' \
  && ok "R2.d 새 확인이 종전 덮어쓰기 문장보다 앞 (AC-6)" || nope "R2.d" "순서"
grep -qF 'review-saved.sh check' "$PLUGIN/skills/file-based-communication-ko/SKILL.md" && ok "R2.c file-based-communication-ko 도 같은 확인" || nope "R2.c"
{ grep -F '옛 report 를 반환 전문으로 교체)' "$IMP" | grep -qF '단 `review-saved.sh check` rc 0 이면 다시 쓰지 않는다' \
  && grep -F '일 때만 저장' "$IMP" | grep -qF '`review-saved.sh check` rc 0 이면 저장하지 않는다' \
  && printf '%s' "$_s" | grep -qF 'rc 2(인자 오류·FID 디렉터리 없음)면 rc 1 처럼'; } \
  && ok "R2.e 흐름 블록·경로 규약에도 같은 예외 · rc 2 처리 (AC-6)" || nope "R2.e" "예외 문구 없음"
finish
