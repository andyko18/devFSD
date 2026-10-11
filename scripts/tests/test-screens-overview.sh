#!/usr/bin/env bash
# test-screens-overview.sh — 화면 목록 마스터 대조·동기화 판정기 계약
# 실 screens/·마스터 미변경 — tmpdir 픽스처로 결정적 검증 (test-check-screen-quality.sh 선례)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PLUGIN=$(cd "$PLUGIN/.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CHK="$PLUGIN/scripts/_internal/check-screens-overview.sh"

_fixture() {  # $1=dir — 마스터(fence 안 2 + fence 밖 유령 1) + screens 2개
  mkdir -p "$1/.specops/memory" "$1/screens"
  cat > "$1/.specops/memory/screens-overview.md" <<'EOF'
# 화면 목록 마스터
| name | 제목 | 목적 | 상세 | 미리보기 |
|---|---|---|---|---|
<!-- screens-table:start -->
| dashboard | 대시보드 | 메인 | [x](y) | [x](y) |
| settings | 설정 | 환경 | [x](y) | [x](y) |
<!-- screens-table:end -->

작성 예시 (표 밖 — 실데이터 아님):
| ghost-example | 유령 | 세면 안 됨 | [x](y) | [x](y) |
EOF
  : > "$1/screens/dashboard.md"; : > "$1/screens/login.md"
}
_run() { SPECOPS_SCREENS_OVERVIEW="$2/.specops/memory/screens-overview.md" \
         SPECOPS_SCREENS_DIR="$2/screens" bash "$CHK" "$1" 2>&1; }

# S1: list 가 fence 안 2개만 (유령 행 제외 — 07ef42e 재발 방지)
d=$(mktemp -d); _fixture "$d"
out=$(_run list "$d")
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "2" ] && ! printf '%s' "$out" | grep -q 'ghost-example' \
  && ok "S1 list 가 fence 안 2개만 (유령 제외)" || nope "S1" "out=$out"

# S2: diff 가 양방향 차집합 + DIFF 요약, rc=0
out=$(_run diff "$d"); rc=$?
printf '%s' "$out" | grep -q 'MASTER-ONLY: settings' \
  && printf '%s' "$out" | grep -q 'SCREENS-ONLY: login' \
  && printf '%s' "$out" | grep -q 'SCREENS-OVERVIEW: DIFF' && [ "$rc" -eq 0 ] \
  && ok "S2 diff 양방향 + rc=0" || nope "S2" "rc=$rc out=$out"

# S3: sync 가 실제로 행을 추가한다 (added 보고만 하고 안 쓰는 결함 차단) + rc=0
#   ★ rc 단언은 sync **성공 경로**(유일한 쓰기 모드 · Phase 2.5-A Step 4 호출부)의
#     "전 모드 rc=0" 계약을 잠근다 — S6 은 마스터 부재 SKIP 경로만 통과해 여기 닿지 않는다.
_run sync "$d" >/dev/null; rc3=$?
after=$(_run list "$d")
printf '%s' "$after" | grep -qx 'login' && [ "$rc3" -eq 0 ] \
  && ok "S3 sync 가 마스터에 실제 기록 (rc=0)" || nope "S3" "after=$after rc=$rc3"

# S4: sync 멱등 — 2회차 added=0, 행 수 불변, rc=0
n1=$(_run list "$d" | wc -l | tr -d ' ')
out=$(_run sync "$d"); rc4=$?; n2=$(_run list "$d" | wc -l | tr -d ' ')
printf '%s' "$out" | grep -q 'added=0' && [ "$n1" = "$n2" ] && [ "$rc4" -eq 0 ] \
  && ok "S4 sync 멱등 (added=0 · 행수 $n1 유지 · rc=0)" || nope "S4" "out=$out n1=$n1 n2=$n2 rc=$rc4"

# S5: fence 밖 무접촉
grep -q 'ghost-example' "$d/.specops/memory/screens-overview.md" \
  && grep -q '^# 화면 목록 마스터' "$d/.specops/memory/screens-overview.md" \
  && ok "S5 fence 밖 무접촉" || nope "S5" "fence 밖 손상"
rm -rf "$d"

# S6: 마스터 부재 → 3모드 전부 SKIP·rc=0 (미부트스트랩 batch 차단 금지)
e=$(mktemp -d); mkdir -p "$e/screens"
r=0
for m in list diff sync; do
  SPECOPS_SCREENS_OVERVIEW="$e/none.md" SPECOPS_SCREENS_DIR="$e/screens" bash "$CHK" "$m" >/dev/null 2>&1 || r=1
done
[ "$r" -eq 0 ] && ok "S6 마스터 부재 3모드 rc=0" || nope "S6" "rc!=0"
rm -rf "$e"

# S7: ★ env 없이 cwd 기본 경로로 동작하는가 (C1 — 하류 repo 영구 no-op 차단)
#   S1~S6 은 전부 env 로 경로를 주입하므로 **기본 경로가 틀려도 통과한다**.
#   실측(되돌려-관찰): 기본 경로를 플러그인 설치 루트로 되돌리면
#     S7 = list 0줄 FAIL(격추 ✓) · S1 = list 2줄 PASS(못 잡음 ✗).
#   즉 이 축이 C1 을 잡는 **유일한** 어서션이다. 지우지 마라.
g=$(mktemp -d); _fixture "$g"
out=$( cd "$g" && env -u SPECOPS_SCREENS_OVERVIEW -u SPECOPS_SCREENS_DIR bash "$CHK" list 2>&1 )
[ "$(printf '%s\n' "$out" | grep -c .)" = "2" ] \
  && ok "S7 env 없이 cwd 기본 경로로 마스터를 찾는다" || nope "S7" "out=$out"
rm -rf "$g"

# S8: ★ start 마커 부재 → sync 는 SKIP · 행 추가 0 · rc=0 (I1 격추 축)
#   end 만 보고 append 하면 추가분을 _master_names 가 못 읽어(fence 미형성) 매 실행 재추가된다 —
#   start-all.md 의 "멱등(2회 실행해도 중복 없음)" 계약이 degenerate 마스터에서 거짓이 되고,
#   기록분은 `list` 에도 안 잡혀 Phase 2.5-A Step 1 합류에서 사라진다.
#   실측(되돌려-관찰): sync 의 fence start 가드를 지우면 sync ×3 → login 3행·dashboard 4행 → 이 축 FAIL.
h=$(mktemp -d); _fixture "$h"
M8="$h/.specops/memory/screens-overview.md"
grep -v '^<!-- screens-table:start -->' "$M8" > "$M8.x" && mv "$M8.x" "$M8"
o8=""; rc8=0
for _i in 1 2 3; do o8=$(_run sync "$h"); [ $? -eq 0 ] || rc8=1; done
n8_login=$(grep -c '^| login' "$M8" || true)
n8_dash=$(grep -c '^| dashboard' "$M8" || true)
printf '%s' "$o8" | grep -q 'SCREENS-OVERVIEW: SKIP' \
  && [ "$n8_login" = "0" ] && [ "$n8_dash" = "1" ] && [ "$rc8" -eq 0 ] \
  && ok "S8 start 부재 → sync SKIP · 행 추가 0 · rc=0" \
  || nope "S8" "out=$o8 login=$n8_login dashboard=$n8_dash rc=$rc8"
rm -rf "$h"

# S9: ★ end 마커 부재 → list 빈 출력 · sync SKIP · rc=0 (_master_names end 가드 잠금)
#   end 가 없으면 fence 가 파일 끝까지 열려 표 밖 ghost-example 을 실 화면으로 읽는다(07ef42e 클래스).
#   실측(되돌려-관찰): _master_names 의 end 가드를 지우면 list 가 3줄(ghost 포함) → 이 축 FAIL.
k=$(mktemp -d); _fixture "$k"
M9="$k/.specops/memory/screens-overview.md"
grep -v '^<!-- screens-table:end -->' "$M9" > "$M9.x" && mv "$M9.x" "$M9"
l9=$(_run list "$k"); rc9l=$?
o9=$(_run sync "$k"); rc9s=$?
[ "$(printf '%s' "$l9" | grep -c .)" = "0" ] && [ "$rc9l" -eq 0 ] \
  && printf '%s' "$o9" | grep -q 'SCREENS-OVERVIEW: SKIP' && [ "$rc9s" -eq 0 ] \
  && ok "S9 end 부재 → list 빈 출력 · sync SKIP · rc=0" \
  || nope "S9" "list=$l9 out=$o9 rc=$rc9l/$rc9s"
rm -rf "$k"

finish
