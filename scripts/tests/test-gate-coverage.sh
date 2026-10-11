#!/usr/bin/env bash
# test-gate-coverage — AC-1·2·3·4·8 (게이트 판정 보유율 · 다중 root · 기본 root · 읽기 전용)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
GC="$PLUGIN/scripts/gate-coverage.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
ng() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
ck() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 — exp '$3' got '$2'"; fi; }
field() { printf '%s\n' "$1" | awk -v l="$2" -v n="$3" '$1==l {print $n; exit}'; }
mkfid() {  # <root> <fid> <4파일 1|0> <evidence 본문>
  mkdir -p "$1/$2"
  printf '%s\n' "$4" > "$1/$2/evidence.md"
  if [ "$3" = 1 ]; then : > "$1/$2/spec.md"; : > "$1/$2/plan.md"; : > "$1/$2/tasks.md"; fi
}
SEC_P=$'## /security-review — 2026-09-15\n**결과**: PASS'
INT_S=$'## /integration-test — 2026-09-15\n**결과**: SKIP\n**근거**: §2 L1'
INT_P=$'## /integration-test — 2026-09-15\n**결과**: PASS'
PERF_P=$'## /performance-test — 2026-09-15\n**결과**: PASS'
SEC_U=$'## /security-review — 2026-09-15\n보고서 본문만 있고 판정 줄이 없다'

# AC-1 fixture: (a) 세 게이트 판정 (b) security 헤더 없음 (c) security 판정 불가 (d) evidence 만
R1="$TD/r1"
mkfid "$R1" 20260915-a 1 "$SEC_P"$'\n'"$INT_S"$'\n'"$PERF_P"
mkfid "$R1" 20260915-b 1 "$INT_P"$'\n'"$PERF_P"
mkfid "$R1" 20260915-c 1 "$SEC_U"$'\n'"$INT_P"$'\n'"$PERF_P"
mkfid "$R1" 20260915-d 0 "$INT_P"
sum1=$(find "$R1" -type f -exec cat {} + | cksum)
out1=$(bash "$GC" "$R1"); rc1=$?
ck "T1.a AC-1 evidence=4" "$(field "$out1" r1 2)" "4"
ck "T1.b AC-1 verified=3" "$(field "$out1" r1 3)" "3"
ck "T1.c AC-1 held=1" "$(field "$out1" r1 5)" "1"
ck "T1.d AC-1 rate=33%" "$(field "$out1" r1 6)" "33%"
ck "T1.e AC-1 security P/S/F/M/U" "$(field "$out1" r1 7)" "1/0/0/1/1"
ck "T1.f AC-1 rc=0" "$rc1" "0"

# AC-2: 다중 root 합계 (r2 = verified 2 · held 2)
R2="$TD/r2"
mkfid "$R2" 20260915-e 1 "$SEC_P"$'\n'"$INT_P"$'\n'"$PERF_P"
mkfid "$R2" 20260915-f 1 "$SEC_P"$'\n'"$INT_S"$'\n'"$PERF_P"
out2=$(bash "$GC" "$R1" "$R2")
ck "T2.a AC-2 합계 verified=5" "$(field "$out2" 합계 3)" "5"
ck "T2.b AC-2 합계 held=3" "$(field "$out2" 합계 5)" "3"
ck "T2.c AC-2 합계 rate=60%" "$(field "$out2" 합계 6)" "60%"
if printf '%s\n' "$out1" | grep -q '^합계'; then ng "T2.d AC-2 단일 경로에 합계 줄"; else ok "T2.d AC-2 단일 경로는 합계 없음"; fi

# AC-3: (a) 인자 없음 = git 루트 .specops (b) 경로 없음 (c) 분모 0 · 읽기 전용
P3="$TD/proj"; mkdir -p "$P3/sub"; git -C "$P3" init -q
mkfid "$P3/.specops" 20260915-g 1 "$SEC_P"$'\n'"$INT_P"$'\n'"$PERF_P"
out3=$(cd "$P3/sub" && bash "$GC")
ck "T3.a AC-3 무인자 → git 루트 .specops (label=proj verified=1)" "$(field "$out3" proj 3)" "1"
out3b=$(bash "$GC" "$TD/nope" "$R1"); rc3b=$?
if printf '%s' "$out3b" | grep -q "경로 없음" && [ "$(field "$out3b" r1 2)" = 4 ] && [ "$rc3b" -eq 0 ]; then ok "T3.b AC-3 경로 없음 표기 후 계속"; else ng "T3.b ($out3b)"; fi
mkdir -p "$TD/empty"
ck "T3.c AC-3 분모 0 → rate '-'" "$(field "$(bash "$GC" "$TD/empty")" empty 6)" "-"
ck "T3.d AC-3 대상 파일 불변" "$(find "$R1" -type f -exec cat {} + | cksum)" "$sum1"

# AC-4: verifyPASS — state PASS 1 + evidence /verify FAIL 1
P4="$TD/proj4"; mkdir -p "$P4"; git -C "$P4" init -q
printf 'base\n' > "$P4/app.sh"; git -C "$P4" add app.sh
git -C "$P4" -c user.name=t -c user.email=t@example.com commit -qm init
mkfid "$P4/.specops" 20260915-pass 1 "$SEC_P"
mkfid "$P4/.specops" 20260915-fail 1 $'## /verify — 2026-09-15\n**결과**: FAIL'
(cd "$P4" && bash "$PLUGIN/scripts/_internal/verification-state.sh" record 20260915-pass PASS >/dev/null)
ck "T4.a AC-4 verifyPASS=1" "$(field "$(bash "$GC" "$P4")" proj4 4)" "1"

# AC-8: archive 하위 미집계 · repo 라벨 = 폴더명 (repo 루트 / .specops 인자 둘 다)
A8="$TD/alpha-repo"
mkfid "$A8/.specops" 20260915-one 1 "$SEC_P"
mkfid "$A8/.specops/archive" 20260101-old 1 "$SEC_P"
ck "T5.a AC-8 repo 루트 인자 verified=1" "$(field "$(bash "$GC" "$A8")" alpha-repo 3)" "1"
# 중첩 .specops/.specops (이 repo 실재 — git-ignore 된 session-progress 잔재) 가 있어도 바깥 root 를 본다
mkdir -p "$A8/.specops/.specops"; : > "$A8/.specops/.specops/session-progress.md"
ck "T5.b AC-8 .specops 인자 label=alpha-repo (중첩 .specops 무시)" "$(field "$(bash "$GC" "$A8/.specops")" alpha-repo 3)" "1"
git -C "$A8" init -q
ck "T5.c AC-3/8 무인자 + 중첩 .specops → 바깥 root" "$(field "$(cd "$A8" && bash "$GC")" alpha-repo 3)" "1"

echo "--- SUMMARY ---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
