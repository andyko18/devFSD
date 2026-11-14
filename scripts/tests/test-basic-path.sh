#!/usr/bin/env bash
# /basic 경로 — basic-path.sh (20261112 speed)
#   계약: 풀 신호(인증·스키마·데이터 삭제/이관·API 응답 형태·비가역 외부 작업)는 세 지점(start·approve·seal)에서 rc 3 으로 막고(막힌 FID 는 promote 로 풀 경로에 올린다),
#   /start·/maintain·자연어 진입은 route 가 같은 판정으로 갈래를 고르고(G), 유지보수는 spec 1장이 AC-R-1 을 받고(M), seal 은 러너가 받지 않는 명령을 거부한다(W).
#   통과한 FID 는 **기존** 검증 러너·리뷰 감사가 그대로 PASS 하는 정식 구조(spec + AC + tasks + dispatch-log)가 된다 — 훅을 고치지 않는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BP="$PLUGIN/scripts/basic-path.sh"
ok() { PASS=$((PASS+1)); echo "PASS $1"; }
no() { FAIL=$((FAIL+1)); echo "FAIL $1 — ${2:-}"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FID=20261112-bp-fixture

_repo() {  # <이름> → 작업 브랜치 위의 specops 관할 저장소
  local d="$TMP/$1"
  mkdir -p "$d/.specops" "$d/scripts/tests"
  ( cd "$d" && git init -q -b main && printf 'x\n' > README.md && printf '.specops/\n' > .gitignore \
    && git add README.md .gitignore && git -c user.name=t -c user.email=t@e.com commit -qm init && git checkout -q -b work ) || return 1
  printf '%s' "$d"
}
_bp() { ( cd "$1" && shift && bash "$BP" "$@" 2>&1 ); }
_fill_spec() {  # <repo> [<범위 줄>] [<범위 밖 줄>]
  cat > "$1/.specops/$FID/spec.md" <<SPEC
# $FID — spec (기본 경로)

**§기본**: true

## 1. 목표

줄 수 세기 명령에 빈 줄 제외 옵션을 더한다.

## 2. 범위

- ${2:-scripts/count.sh 에 옵션을 더한다}

### 범위 밖

- ${3:-다른 명령은 고치지 않는다}

### 화면 변경

없음

## 3. 수용 기준

### AC-1: 빈 줄을 세지 않는다

**우선순위**: must
**Given** 빈 줄 2개와 글자 줄 3개가 든 파일
**When** 옵션을 주고 실행한다
**Then** 3 을 출력한다
**검증 방법**: bash scripts/tests/test-count.sh

## 4. 비기능 요구 (NFR)

없음
SPEC
}

has() { local f="$1" p; shift; for p in "$@"; do grep -qF -- "$p" "$f" || return 1; done; }

# 종전 규칙 구간 — 통합 절차 스위치를 끄고 본다(신호가 하나라도 있으면 풀). 통합 절차(기본값)는 파일 끝 N 구간이 본다.
#   이 구간이 잠그는 것: 끈 스위치의 종전 동작 전부 + 두 방식이 함께 쓰는 기계 절차(골격·승인 검사·봉인·승격·종결).
export SPECOPS_UNIFIED_PATH=0

# ── L 갈래 판정 ──
d=$(_repo lane)
out=$(_bp "$d" lane "목록 화면에 정렬 버튼 추가"); rc=$?
[ "$rc" = 0 ] && [ "$out" = "LANE: basic" ] && ok "L1 위험 신호 없는 요청 → basic (rc 0)" || no "L1" "rc=$rc $out"
i=0
for q in "로그인 권한 검사를 바꾼다" "주문 테이블 컬럼 추가" "오래된 데이터 삭제 배치" "주문 조회 응답 형식을 바꾼다" "결제 취소 시 환불 호출" \
         "add oauth callback" "run ALTER TABLE orders" "update Dockerfile for deploy"; do
  i=$((i+1)); out=$(_bp "$d" lane "$q"); rc=$?
  [ "$rc" = 3 ] && printf '%s' "$out" | grep -q '^LANE: full ' && ok "L2.$i ★ 풀 신호 → full (rc 3): $q" || no "L2.$i" "rc=$rc $out [$q]"
done
# `토큰` 오판 (20261112 실측 — spec 의 "VERIFY 토큰" 이 인증 신호로 잡혀 승인 단계에서 풀 경로가 됐다). 인증과 무관한 쓰임만 빼고, 맨 `토큰` 은 종전대로 풀이다(애매하면 무거운 쪽).
i=0
for q in "러너가 마지막 줄에 VERIFY 토큰을 낸다" "검증 러너의 \`VERIFY:\` 토큰과 종료 코드는 그대로다" "토큰 비용을 줄이려고 재읽기를 없앤다" "캐시 읽기 12M 토큰 · 출력 토큰 37K" \
         "LLM eval 은 토큰 비용이 든다" "실행-근거 토큰(VERIFY: PASS)만 인정한다"; do
  i=$((i+1)); out=$(_bp "$d" lane "$q"); rc=$?
  [ "$rc" = 0 ] && [ "$out" = "LANE: basic" ] && ok "L2b.$i ★ 인증과 무관한 토큰(판정 줄·비용·사용량) → basic: $q" || no "L2b.$i" "rc=$rc $out [$q]"
done
i=0
for q in "토큰 처리 로직을 바꾼다" "액세스 토큰 만료 시 갱신한다" "API 토큰을 헤더에 싣는다" "VERIFY 토큰은 그대로 두고 로그인 토큰 검증을 바꾼다" "토큰 비용 화면에 세션 토큰 재발급 버튼 추가"; do
  i=$((i+1)); out=$(_bp "$d" lane "$q"); rc=$?
  [ "$rc" = 3 ] && printf '%s' "$out" | grep -q '^LANE: full .*auth' && ok "L2c.$i ★ 인증 토큰·맨 토큰은 여전히 full(auth): $q" || no "L2c.$i" "rc=$rc $out [$q]"
done
out=$(_bp "$d" design-scope 0); printf '%s' "$out" | grep -q '^DESIGN: none' && ok "L3a 화면 0개 → none" || no "L3a" "$out"
out=$(_bp "$d" design-scope 2); printf '%s' "$out" | grep -q '^DESIGN: update' && ok "L3b 화면 2개 일부 수정 → update" || no "L3b" "$out"
out=$(_bp "$d" design-scope 3); printf '%s' "$out" | grep -q '^DESIGN: approve' && ok "L3c ★ 화면 3개 → approve(스펙·목업 먼저)" || no "L3c" "$out"
out=$(_bp "$d" design-scope 1 new); printf '%s' "$out" | grep -q '^DESIGN: approve' && ok "L3d ★ 새 화면은 1개여도 approve" || no "L3d" "$out"
out=$(_bp "$d" design-scope 1 flow); printf '%s' "$out" | grep -q '^DESIGN: approve' && ok "L3e ★ 흐름 변경은 1개여도 approve" || no "L3e" "$out"
grep -q '^BASIC_SCREEN_APPROVAL_MIN=3 ' "$BP" && ok "L3f 기준값은 스크립트 상수 한 곳(3)" || no "L3f"
# 화면을 건드리면 설계 확인 범위와 별개로 구현 품질 두 가지(목업 CSS 이식 · 브라우저 점검)를 항상 알린다 — 하류 실측 생존율 8%·33% (20261114)
i=0
for args in "0" "2" "3" "1 new" "1 flow"; do
  i=$((i+1)); out=$(_bp "$d" design-scope $args)
  [ "$(printf '%s\n' "$out" | grep -c '^UI: ')" = 1 ] && printf '%s\n' "$out" | grep '^UI: ' | grep -q '목업 CSS 이식' && printf '%s\n' "$out" | grep '^UI: ' | grep -q '브라우저 점검' \
    && [ "$(printf '%s\n' "$out" | grep -c '^DESIGN: ')" = 1 ] && ok "L3g.$i ★ design-scope $args → UI 줄 1개(이식·브라우저 점검) + DESIGN 줄 1개" || no "L3g.$i" "$out"
done

# ── S start ──
out=$(_bp "$d" start "$FID" "결제 모듈 교체"); rc=$?
[ "$rc" = 3 ] && [ ! -e "$d/.specops/$FID" ] && ok "S1 ★ 풀 신호 요청 → rc 3 · 아무것도 만들지 않는다" || no "S1" "rc=$rc $out"
out=$(_bp "$d" start "$FID" "빈 줄 제외 옵션 추가"); rc=$?
[ "$rc" = 0 ] && [ -f "$d/.specops/$FID/spec.md" ] && grep -q "$FID" "$d/.specops/$FID/spec.md" && grep -q '/basic 시작' "$d/.specops/session-progress.md" \
  && ok "S2 start → spec 골격 · 진행 기록" || no "S2" "rc=$rc $out"
nd="$TMP/nospec"; mkdir -p "$nd"; ( cd "$nd" && git init -q -b main )
_bp "$nd" start "$FID" "옵션 추가" >/dev/null; rc=$?
[ "$rc" = 1 ] && [ ! -e "$nd/.specops" ] && ok "S3 ★ .specops 없는 저장소 → rc 1 · 관할을 열지 않는다" || no "S3" "rc=$rc"
# 골격 자체가 풀 신호를 내지 않아야 한다(안내 문구의 낱말 때문에 모든 FID 가 풀이 되는 사고 방지)
out=$(_bp "$d" lane "" "$FID" 2>&1); [ "$out" = "LANE: basic" ] || out=$(_bp "$d" lane "옵션 추가" "$FID")
[ "$out" = "LANE: basic" ] && ok "S4 ★ spec 골격만으로는 풀 신호가 나지 않는다" || no "S4" "$out"

# ── A approve ──
out=$(_bp "$d" approve "$FID"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '자리표시' && ok "A1 채우지 않은 골격 → rc 1" || no "A1" "rc=$rc $out"
_fill_spec "$d" "로그인 권한 검사를 고친다"
out=$(_bp "$d" approve "$FID"); rc=$?
[ "$rc" = 3 ] && [ ! -e "$d/.specops/$FID/acceptance-criteria.md" ] && ok "A2 ★ spec 범위에 풀 신호 → rc 3 · AC 파일 없음" || no "A2" "rc=$rc $out"
_fill_spec "$d" "scripts/count.sh 에 옵션을 더한다" "로그인·권한·결제는 건드리지 않는다"
out=$(_bp "$d" approve "$FID"); rc=$?
[ "$rc" = 0 ] && grep -q '^### AC-1: ' "$d/.specops/$FID/acceptance-criteria.md" && grep -q '/approve 완료' "$d/.specops/session-progress.md" \
  && ok "A3 ★ '범위 밖' 절의 낱말은 신호가 아니다 → 승인 · acceptance-criteria.md 도출" || no "A3" "rc=$rc $out"
( cd "$d" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/check-ac-format.sh" "$FID" >/dev/null 2>&1 ) \
  && ok "A4 도출한 AC 가 기존 형식 검사(check-ac-format)를 통과" || no "A4"
sed -i.bak '/^\*\*우선순위\*\*/d' "$d/.specops/$FID/spec.md"
_bp "$d" approve "$FID" >/dev/null; rc=$?; mv "$d/.specops/$FID/spec.md.bak" "$d/.specops/$FID/spec.md"
[ "$rc" = 1 ] && ok "A5 수용 기준에 우선순위가 없으면 승인 거부(rc 1)" || no "A5" "rc=$rc"
_bp "$d" approve "$FID" >/dev/null

# ── Z seal → 기존 검증 러너 ──
# 관제판 단계 기록 (20261112) — review 는 구현 완료·리뷰 진행 줄만 남긴다(판정·산출물 없음). 승인 전에는 거부한다.
SP="$d/.specops/session-progress.md"
d0=$(_repo prog); _bp "$d0" start "$FID" "줄 수 세기 명령에 옵션 추가" >/dev/null
out=$(_bp "$d0" review "$FID"); rc=$?
[ "$rc" = 1 ] && ! grep -qE '^- [0-9-]+ [0-9:]+ /implement ' "$d0/.specops/session-progress.md" && ok "P1 승인 전 review → rc 1 · 기록 없음" || no "P1" "rc=$rc $out"
out=$(_bp "$d" review "$FID"); rc=$?
[ "$rc" = 0 ] && [ "$(grep -cE '^- [0-9-]+ [0-9:]+ /(review 진행|implement 완료) ' "$SP")" = 2 ] \
  && [ "$(grep -nE ' /(review|implement) ' "$SP" | head -1 | grep -c '/review 진행')" = 1 ] \
  && ok "P2 review → 구현 완료 · 리뷰 진행 기록(리뷰 줄이 위)" || no "P2" "rc=$rc $out"
[ ! -e "$d/.specops/$FID/tasks.md" ] && ok "P3 review 는 태스크 문서를 만들지 않는다" || no "P3"
printf '#!/usr/bin/env bash\ngrep -c . "$1"\n' > "$d/scripts/count.sh"
printf '#!/usr/bin/env bash\nf=$(mktemp); printf "a\\n\\nb\\n" > "$f"; [ "$(bash scripts/count.sh "$f")" = 2 ]; rc=$?; rm -f "$f"; exit $rc\n' > "$d/scripts/tests/test-count.sh"
chmod +x "$d/scripts/count.sh" "$d/scripts/tests/test-count.sh"
out=$(_bp "$d" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 4 ] && [ ! -e "$d/.specops/$FID/tasks.md" ] && ok "Z1 ★ 리뷰 보고서 없이 seal → rc 4 · 태스크 문서 없음" || no "Z1" "rc=$rc $out"
mkdir -p "$d/.specops/$FID/reviews"
printf '# B\n**판정**: PASS\n' > "$d/.specops/$FID/reviews/T1-B-report.md"
printf '# C\n**Phase B 상태**: PENDING(병렬 dispatch)\n**판정**: READY_TO_MERGE\n' > "$d/.specops/$FID/reviews/T1-C-report.md"
mkdir -p "$d/db/migrations"; printf 'x\n' > "$d/db/migrations/001.sql"
out=$(_bp "$d" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 3 ] && [ ! -e "$d/.specops/$FID/tasks.md" ] && ok "Z2 ★ 구현 중 생긴 풀 신호(migrations 경로) → seal rc 3 (풀 승격)" || no "Z2" "rc=$rc $out"
rm -rf "$d/db"
out=$(_bp "$d" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
t="$d/.specops/$FID/tasks.md"
[ "$rc" = 0 ] && grep -q '^review_mode: end-loaded' "$t" && grep -q '"scripts/count.sh"' "$t" && grep -q 'ac: \[AC-1\]' "$t" \
  && grep -q 'test_command: "bash scripts/tests/test-count.sh"' "$t" && ! grep -q '\.specops/' "$t" \
  && ok "Z3 seal → 1-태스크 문서(outputs=변경 파일 · AC · test_command · .specops 제외)" || no "Z3" "rc=$rc $out"
[ "$(grep -cE '^- [0-9-]+ [0-9:]+ /review 완료 ' "$SP")" = 1 ] && [ "$(grep -cE ' /review 완료 ' "$SP")" = 1 ] \
  && ok "P4 seal 성공 → 리뷰 완료 기록 1줄(rc 4·rc 3 으로 막힌 seal 은 남기지 않았다)" || no "P4" "$(grep -c '/review 완료' "$SP")"
( cd "$d" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/check-review-audit.sh" "$FID" 2>&1 ) | grep -q '^REVIEW-AUDIT: PASS' \
  && ok "Z4 ★ 기존 리뷰 감사(check-review-audit — 병렬 쌍 사후 대조 포함) PASS" || no "Z4" "$(cd "$d" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/check-review-audit.sh" "$FID" 2>&1)"
vout=$( cd "$d" && bash "$PLUGIN/scripts/_internal/run-verification.sh" "$FID" 2>&1 ); vrc=$?
[ "$vrc" = 0 ] && printf '%s\n' "$vout" | grep -qx 'VERIFY: PASS' \
  && ok "Z5 ★ 기존 검증 러너(run-verification.sh)가 고치지 않은 채 VERIFY: PASS" || no "Z5" "rc=$vrc $(printf '%s' "$vout" | tail -5)"
st=$( cd "$d" && bash "$PLUGIN/scripts/_internal/verification-state.sh" current "$FID" 2>/dev/null )
printf '%s' "$st" | grep -q 'PASS' && ok "Z6 판정 SoT(verification-state) = PASS" || no "Z6" "$st"
# quick 구조(tasks 있고 spec 없음)가 아니다 — 훅이 quick 판정(범위 상한)으로 보내지 않는다
[ -f "$d/.specops/$FID/spec.md" ] && [ -f "$t" ] && ok "Z7 정식 FID 구조(spec + tasks) — quick 구조 아님" || no "Z7"
out=$(_bp "$d" seal "$FID" "bash scripts/tests/test-count.sh"); [ "$(grep -c 'BC-PAR-CHECK:T1' "$d/.specops/$FID/dispatch-log.md")" = 1 ] \
  && ok "Z8 다시 seal 해도 감사 행이 중복되지 않는다" || no "Z8"
_bp "$d" seal "$FID" 'bash "x".sh' >/dev/null; [ $? = 1 ] && ok "Z9 test_command 의 따옴표 거부" || no "Z9"
out=$(_bp "$d" "done" "$FID" "빈 줄 제외 옵션"); grep -q '/lifecycle DONE' "$d/.specops/session-progress.md" && ok "Z10 done → 종결 기록" || no "Z10" "$out"

# ── R 관련 스위트로 검증 (20261112 speed) ──
#   매핑(scripts/tests/run-related.sh)이 없는 저장소는 종전대로다. 있는 저장소는 변경 파일이 닿는 스위트만 검증 러너가 돌린다.
out=$(_bp "$d" related); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '^RELATED: none — ' && ok "R1 ★ 매핑 없는 저장소(하류) → RELATED: none (프로젝트 테스트 명령 전체 — 종전 동작)" || no "R1" "rc=$rc $out"
FID_R=20261112-bp-related
r=$(_repo rel)
: > "$r/scripts/tests/run-all.sh"; cp "$PLUGIN/scripts/tests/run-related.sh" "$r/scripts/tests/run-related.sh"
printf '#!/usr/bin/env bash\ngrep -c . "$1"\n' > "$r/scripts/count.sh"
printf '#!/usr/bin/env bash\necho other\n' > "$r/scripts/other.sh"
printf '#!/usr/bin/env bash\nf=$(mktemp); printf "a\\n\\nb\\n" > "$f"; [ "$(bash scripts/count.sh "$f")" = 2 ]; rc=$?; rm -f "$f"; echo "PASS=1 FAIL=$rc"; exit $rc\n' > "$r/scripts/tests/test-count.sh"
printf '#!/usr/bin/env bash\n# scripts/other.sh\necho "PASS=1 FAIL=0"\n' > "$r/scripts/tests/test-other.sh"
( cd "$r" && git add scripts && git -c user.name=t -c user.email=t@e.com commit -qm base && git branch -f main HEAD ) >/dev/null   # 기준 브랜치에 이미 있는 파일 — 이번 변경이 아니다
printf '#!/usr/bin/env bash\ngrep -c . "$1"  # 빈 줄 제외\n' > "$r/scripts/count.sh"
out=$(_bp "$r" related)
REL="bash scripts/tests/run-related.sh scripts/tests/test-count.sh"
[ "$out" = "RELATED: $REL" ] && ok "R2 ★ 매핑 있는 저장소 → 변경 파일(count.sh)이 닿는 스위트만 담은 명령" || no "R2" "$out"
FID_KEEP=$FID; FID=$FID_R
_bp "$r" start "$FID" "빈 줄 제외 옵션 추가" >/dev/null; _fill_spec "$r"; _bp "$r" approve "$FID" >/dev/null
mkdir -p "$r/.specops/$FID/reviews"
printf '# B\n**판정**: PASS\n' > "$r/.specops/$FID/reviews/T1-B-report.md"
printf '# C\n**Phase B 상태**: PENDING(병렬 dispatch)\n**판정**: READY_TO_MERGE\n' > "$r/.specops/$FID/reviews/T1-C-report.md"
out=$(_bp "$r" seal "$FID" "$REL"); rc=$?
[ "$rc" = 0 ] && grep -qF "test_command: \"$REL\"" "$r/.specops/$FID/tasks.md" && ok "R3 관련 스위트 명령으로 seal → test_command 에 그대로" || no "R3" "rc=$rc $out"
vout=$( cd "$r" && bash "$PLUGIN/scripts/_internal/run-verification.sh" "$FID" 2>&1 ); vrc=$?
[ "$vrc" = 0 ] && printf '%s\n' "$vout" | grep -qx 'VERIFY: PASS' && grep -q 'run-related: suites PASS=1 FAIL=0 (total=1)' "$r/.specops/$FID/evidence.md" \
  && ok "R4 ★ 고치지 않은 검증 러너가 관련 스위트 1개만 돌리고 VERIFY: PASS (evidence 에 실행 출력)" || no "R4" "rc=$vrc $(printf '%s' "$vout" | tail -5)"
[ ! -e "$r/.specops/.full-suite-pass" ] && ok "R5 ★ 전체 스위트 통과 기록은 생기지 않는다 — push 전 게이트는 전체를 돌린다" || no "R5"
# related 뒤에 다른 파일을 더 고쳤다 → 옛 명령으로는 봉인되지 않는다
printf '#!/usr/bin/env bash\necho other2\n' > "$r/scripts/other.sh"
out=$(_bp "$r" seal "$FID" "$REL"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '관련 스위트가 빠졌다: scripts/tests/test-other.sh' && ok "R6 ★ 지금 변경이 닿는 스위트가 빠진 명령은 seal 거부(rc 1)" || no "R6" "rc=$rc $out"
out=$(_bp "$r" seal "$FID" "$REL scripts/tests/test-other.sh"); rc=$?
[ "$rc" = 0 ] && ok "R7 빠진 스위트를 더하면 seal 통과" || no "R7" "rc=$rc $out"
# 어느 스위트도 언급하지 않는 코드 파일 → 관련을 특정할 수 없다: none · 관련 명령으로는 봉인 불가 · 전체 명령으로는 가능
printf '#!/usr/bin/env bash\necho lonely\n' > "$r/scripts/lonely.sh"
out=$(_bp "$r" related)
printf '%s' "$out" | grep -q '^RELATED: none — .*특정할 수 없다: scripts/lonely.sh' && ok "R8 ★ 관련 테스트를 특정할 수 없는 변경 → RELATED: none (전체 명령)" || no "R8" "$out"
out=$(_bp "$r" seal "$FID" "$REL scripts/tests/test-other.sh"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '고를 수 없는 변경' && ok "R9 ★ 특정할 수 없는 변경을 관련 명령으로 seal → 거부(rc 1)" || no "R9" "rc=$rc $out"
out=$(_bp "$r" seal "$FID" "bash ./scripts/tests/run-related.sh scripts/tests/test-count.sh"); rc1=$?
out2=$(_bp "$r" seal "$FID" "cd . && bash scripts/tests/run-related.sh scripts/tests/test-count.sh"); rc2=$?
[ "$rc1" = 1 ] && [ "$rc2" = 1 ] && printf '%s' "$out" | grep -q '형태만 받는다' && ok "R9b ★ 관련 러너를 다른 형태(./ · cd 접두)로 불러 검사를 비껴가는 명령은 거부" || no "R9b" "rc=$rc1/$rc2 $out"
out=$(_bp "$r" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 0 ] && ok "R10 관련 명령이 아닌 test_command 는 종전대로 받는다(판정 없음)" || no "R10" "rc=$rc $out"
FID=$FID_KEEP

# ── G 갈래 고르기 (20261112 auto-lane) — /start·/maintain·자연어 진입이 부르는 route ──
#   판정은 lane 과 같은 함수다. 풀: 위험 신호 · --full · --step · 진입 약속어 · .specops 없음. 그 밖은 기본. 쓰지 않는다.
g=$(_repo route)
_route() { _bp "$g" route "$@"; }
out=$(_route start "목록 화면에 정렬 버튼 추가"); rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "ROUTE: basic — 위험 신호 없음" ] \
  && printf '%s\n' "$out" | grep -qxF 'NOTICE: 기본 경로로 진행 — 위험 신호 없음. 풀 경로는 `--full`.' \
  && printf '%s\n' "$out" | grep -qxF "PROCEDURE: $PLUGIN/commands/basic.md" && printf '%s\n' "$out" | grep -qxF 'REQUEST: 목록 화면에 정렬 버튼 추가' \
  && ok "G1 ★ 신호 없는 신규 → 기본 경로 · 1줄 고지 · 절차 파일 절대경로" || no "G1" "rc=$rc $out"
out=$(_route maintain "목록 정렬이 최신순이 아닌 버그"); printf '%s\n' "$out" | grep -qx 'ROUTE: basic — 위험 신호 없음' && printf '%s\n' "$out" | grep -qx 'KIND: maintain' \
  && printf '%s\n' "$out" | grep -qxF "ENTRY: $PLUGIN/commands/maintain.md" && ok "G2 ★ 신호 없는 유지보수 → 기본 경로(KIND: maintain)" || no "G2" "$out"
out=$(_route start "로그인 권한 검사를 바꾼다"); printf '%s\n' "$out" | head -1 | grep -q '^ROUTE: full — 위험 신호(.*인증·권한' \
  && printf '%s\n' "$out" | grep -q '^NOTICE: 풀 경로로 진행 — 위험 신호(' && ! printf '%s\n' "$out" | grep -q '^PROCEDURE:' \
  && ok "G3 ★ 위험 신호 → 풀 경로 · 이유 고지 · 기본 절차 안내 없음" || no "G3" "$out"
out=$(_route maintain "--full 목록 정렬 버그"); printf '%s\n' "$out" | grep -qx 'ROUTE: full — --full 지정' && printf '%s\n' "$out" | grep -qx 'REQUEST: 목록 정렬 버그' \
  && ok "G4 ★ --full → 신호가 없어도 풀 · 요청에서 옵션을 뗀다" || no "G4" "$out"
out=$(_route start "--no-split --full --step 정렬 버튼 추가"); printf '%s\n' "$out" | grep -qx 'ROUTE: full — --full 지정' \
  && printf '%s\n' "$out" | grep -qx 'OPTIONS: --no-split --full --step' && printf '%s\n' "$out" | grep -qx 'REQUEST: 정렬 버튼 추가' \
  && ok "G5 --full 은 --step·--no-split 과 함께 쓸 수 있다(순서 무관 · 나머지 옵션은 OPTIONS 로 넘긴다)" || no "G5" "$out"
out=$(_route start "--step 정렬 버튼 추가"); printf '%s\n' "$out" | head -1 | grep -q '^ROUTE: full — --step 지정' && ok "G6 --step → 풀(단계별 확인은 풀 경로의 기능)" || no "G6" "$out"
out=$(_route start "--no-split 정렬 버튼 추가"); printf '%s\n' "$out" | grep -qx 'ROUTE: basic — 위험 신호 없음' && ok "G7 --no-split 만으로는 갈래가 바뀌지 않는다" || no "G7" "$out"
i=0
for a in '<!-- entry: batch -->
<!-- batch-id: b1 -->
정렬 버튼 추가' '<!-- entry: foundation -->
공통 레이아웃' '<!-- entry: batch -->
<!-- batch-id: b1 -->
<!-- auto: true -->
정렬 버튼 추가'; do
  i=$((i+1)); out=$(_route start "$a"); printf '%s\n' "$out" | head -1 | grep -q '^ROUTE: full — ' && ok "G8.$i ★ 일괄·공통부 약속어가 든 인자 → 풀(종전 경로)" || no "G8.$i" "$out"
done
for c in start-all start-all-auto start-foundation; do
  ! grep -q 'basic-path.sh' "$PLUGIN/commands/$c.md" && ok "G9.$c ★ /$c 는 갈래 판정을 부르지 않는다(종전 풀 경로 그대로)" || no "G9.$c" "배선이 있다"
done
( cd "$PLUGIN" && git diff --quiet main -- commands/start-all.md commands/start-all-auto.md commands/start-foundation.md 2>/dev/null ); rc=$?
[ "$rc" != 1 ] && ok "G9.diff 일괄·무인·공통부 명령 파일은 main 과 같다(비교 불가면 건너뜀 rc=$rc)" || no "G9.diff" "main 과 다르다"
out=$(_bp "$nd" route start "정렬 버튼 추가"); printf '%s\n' "$out" | head -1 | grep -q '^ROUTE: full — .*\.specops 가 없다' && [ ! -e "$nd/.specops" ] \
  && ok "G10 .specops 없는 저장소 → 풀(관할은 풀 경로가 연다) · 아무것도 만들지 않는다" || no "G10" "$out"
_route start "" >/dev/null 2>&1; rc1=$?; _route start "--full" >/dev/null 2>&1; rc2=$?; _route other "x" >/dev/null 2>&1; rc3=$?
[ "$rc1" = 1 ] && [ "$rc2" = 1 ] && [ "$rc3" = 1 ] && ok "G11 빈 요청·옵션뿐인 요청·모르는 종류 → rc 1" || no "G11" "$rc1/$rc2/$rc3"
[ -z "$(ls -A "$g/.specops")" ] && ok "G12 route 는 아무것도 쓰지 않는다" || no "G12" "$(ls -A "$g/.specops")"
( cd "$g" && touch zz1 zz2 ); out=$(_route start "z* 파일 정리 화면"); printf '%s\n' "$out" | grep -qxF 'REQUEST: z* 파일 정리 화면' && ok "G13 요청의 * 가 파일 이름으로 풀리지 않는다" || no "G13" "$out"
for c in start maintain; do
  has "$PLUGIN/commands/$c.md" "basic-path.sh route $c " '`ROUTE: basic`' '`ROUTE: full`' '`NOTICE:` 줄을 사용자에게 그대로 보인다' '`--full`' \
    && ok "G14.$c /$c 가 갈래 판정을 부르고 고지 1줄 · --full 을 안내" || no "G14.$c"
done
US="$PLUGIN/skills/using-specops-ko/SKILL.md"
has "$US" 'scripts/basic-path.sh route <start|maintain>' '`ROUTE: basic` 이면 `PROCEDURE:` 줄의 파일을 Read' '갈래 추론 금지' \
  && ok "G15 ★ 메타 skill — 자연어 진입도 같은 스크립트 판정을 탄다(추론 아님)" || no "G15"

# ── M 유지보수 기본 경로 — 분석 단계 대신 spec 1장이 현재 동작 절과 AC-R-1 을 받는다 ──
FID_KEEP=$FID; FID=20261112-bp-maint
m=$(_repo maint)
_bp "$m" start "$FID" "목록 정렬이 최신순이 아닌 버그" maintain >/dev/null; rc=$?
MS="$m/.specops/$FID/spec.md"
[ "$rc" = 0 ] && grep -qx '\*\*§유형\*\*: 유지보수' "$MS" && grep -q '^### 현재 동작과 영향' "$MS" && grep -q '^### AC-R-1: ' "$MS" && grep -q '^### AC-1: ' "$MS" \
  && ok "M1 ★ start … maintain → 유지보수 골격(§유형 · 현재 동작과 영향 · AC-R-1)" || no "M1" "rc=$rc"
out=$(_bp "$m" lane "정렬 버그" "$FID"); [ "$out" = "LANE: basic" ] && ok "M2 유지보수 골격만으로는 풀 신호가 나지 않는다" || no "M2" "$out"
_bp "$m" start 20261112-bp-bad "정렬 버그" other >/dev/null 2>&1; [ $? = 1 ] && ok "M3 모르는 넷째 인자 거부" || no "M3"
_fill_spec "$m"
sed -i.bak 's/^\*\*§기본\*\*: true$/&\
**§유형**: 유지보수/' "$MS"; rm -f "$MS.bak"
out=$(_bp "$m" approve "$FID"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '현재 동작과 영향' && [ ! -e "$m/.specops/$FID/acceptance-criteria.md" ] && ok "M4 ★ 유지보수인데 현재 동작 절이 없으면 승인 거부" || no "M4" "rc=$rc $out"
awk '/^### 범위 밖/ { print "### 현재 동작과 영향\n\n- scripts/count.sh 는 빈 줄도 센다. 호출자는 없다.\n" } { print }' "$MS" > "$MS.t" && mv "$MS.t" "$MS"
out=$(_bp "$m" approve "$FID"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'AC-R-1' && ok "M5 ★ 유지보수인데 AC-R-1 이 없으면 승인 거부" || no "M5" "rc=$rc $out"
awk '/^## 4\. / { print "### AC-R-1: 옵션 없이는 종전대로 센다\n\n**우선순위**: must\n**Given** {{기존 전제}}\n**When** 옵션 없이 실행한다\n**Then** 종전과 같은 수를 출력한다\n**검증 방법**: bash scripts/tests/test-count.sh\n" } { print }' "$MS" > "$MS.t" && mv "$MS.t" "$MS"
out=$(_bp "$m" approve "$FID"); rc=$?
[ "$rc" = 1 ] && ok "M6 AC-R-1 에 자리표시가 남으면 승인 거부" || no "M6" "rc=$rc $out"
sed -i.bak 's/{{기존 전제}}/빈 줄이 든 파일/' "$MS"; rm -f "$MS.bak"
out=$(_bp "$m" approve "$FID"); rc=$?
[ "$rc" = 0 ] && grep -q '^### AC-R-1: ' "$m/.specops/$FID/acceptance-criteria.md" \
  && ( cd "$m" && bash "$PLUGIN/scripts/_internal/check-regression-ac.sh" "$FID" 2>&1 | grep -q '^REGRESSION-AC: PASS' ) \
  && ok "M7 ★ 채운 유지보수 spec → 승인 · 풀 경로와 같은 회귀 AC 검사(check-regression-ac) PASS" || no "M7" "rc=$rc $out"
printf '#!/usr/bin/env bash\ngrep -c . "$1"\n' > "$m/scripts/count.sh"
printf '#!/usr/bin/env bash\nf=$(mktemp); printf "a\\n\\nb\\n" > "$f"; [ "$(bash scripts/count.sh "$f")" = 2 ]; rc=$?; rm -f "$f"; exit $rc\n' > "$m/scripts/tests/test-count.sh"
mkdir -p "$m/.specops/$FID/reviews"
printf '# B\n**판정**: PASS\n' > "$m/.specops/$FID/reviews/T1-B-report.md"
printf '# C\n**Phase B 상태**: PENDING(병렬 dispatch)\n**판정**: READY_TO_MERGE\n' > "$m/.specops/$FID/reviews/T1-C-report.md"
out=$(_bp "$m" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
vout=$( cd "$m" && bash "$PLUGIN/scripts/_internal/run-verification.sh" "$FID" 2>&1 ); vrc=$?
[ "$rc" = 0 ] && grep -q 'ac: \[AC-1, AC-R-1\]' "$m/.specops/$FID/tasks.md" && [ "$vrc" = 0 ] && printf '%s\n' "$vout" | grep -qx 'VERIFY: PASS' \
  && ok "M8 ★ 유지보수 기본 경로 FID 도 고치지 않은 검증 러너가 VERIFY: PASS (태스크가 AC-R-1 을 담는다)" || no "M8" "seal=$rc verify=$vrc $(printf '%s' "$vout" | tail -4)"

# ── W seal — 검증 러너가 받지 않는 test_command 거부 (20261112 실측: related 의 `none — …` 안내문이 봉인됐다) ──
rm -f "$m/.specops/$FID/tasks.md"
i=0
for c in "none — 이 저장소에는 관련 스위트 매핑이 없다 (프로젝트의 테스트 명령 전체를 test_command 로 쓴다)" "RELATED: none" "make test" "bash scripts/tests/test-count.sh && rm -rf x" "bash ../x.sh" "echo ok"; do
  i=$((i+1)); out=$(_bp "$m" seal "$FID" "$c"); rc=$?
  [ "$rc" = 1 ] && printf '%s' "$out" | grep -q '검증 러너가 받지 않는다' && [ ! -e "$m/.specops/$FID/tasks.md" ] \
    && ok "W1.$i ★ 실행할 수 없는 test_command 거부(rc 1 · 태스크 문서 없음): $c" || no "W1.$i" "rc=$rc $out"
done
i=0
for c in "bash scripts/tests/test-count.sh" "pytest tests/unit" "npm test" "cd web && pnpm run test:unit" "go test ./pkg/a"; do
  i=$((i+1)); out=$(_bp "$m" seal "$FID" "$c"); rc=$?
  [ "$rc" = 0 ] && ok "W2.$i 검증 러너가 받는 형식은 seal 도 받는다: $c" || no "W2.$i" "rc=$rc $out"
done
grep -q "grep -m1 '^_WHITELIST_PAT=' \"\$BP_ROOT/scripts/_internal/run-verification.sh\"" "$BP" && ! grep -q "^_WHITELIST_PAT='" "$BP" \
  && ok "W3 허용 형식은 검증 러너의 정의를 읽는다(사본 없음)" || no "W3"
# 되돌려-관찰의 반대쪽: seal 이 받은 명령은 러너도 받는다(같은 정규식) — 러너 쪽 판정과 직접 대조
RVPAT=$(grep -m1 '^_WHITELIST_PAT=' "$PLUGIN/scripts/_internal/run-verification.sh" | sed -E "s/^_WHITELIST_PAT='(.*)'\$/\1/")
[[ "bash scripts/tests/test-count.sh" =~ $RVPAT ]] && [[ ! "none — x" =~ $RVPAT ]] && ok "W4 러너의 정규식으로 직접 대조(받음 1 · 거부 1)" || no "W4"

# ── U 승격 — 기본 경로에서 풀 경로로 올린다(만든 것을 버리지 않는다) ──
FID=20261112-bp-promote
u=$(_repo promo)
out=$(_bp "$u" promote "$FID" "인증 변경"); [ $? = 1 ] && ok "U1 spec 없는 FID 는 올릴 것이 없다(rc 1)" || no "U1" "$out"
_bp "$u" start "$FID" "줄 수 세기 옵션 추가" >/dev/null
_fill_spec "$u" "로그인 권한 검사를 고친다"
_bp "$u" approve "$FID" >/dev/null 2>&1; rc=$?
out=$(_bp "$u" approve "$FID" 2>&1); printf '%s' "$out" | grep -qF "basic-path.sh promote $FID" && [ "$rc" = 3 ] \
  && ok "U2 ★ approve 의 풀 신호(rc 3) 안내가 promote 를 가리킨다" || no "U2" "rc=$rc $out"
out=$(_bp "$u" promote "$FID" "위험 신호 인증·권한"); rc=$?
UD="$u/.specops/$FID"
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx "BASIC: PROMOTED $FID stage=spec kind=new" \
  && printf '%s\n' "$out" | grep -qx 'NOTICE: 위험 신호 인증·권한 — 풀 경로로 올림.' \
  && printf '%s\n' "$out" | grep -qx 'NEXT: devfsd:specifying-ko' && printf '%s\n' "$out" | grep -qx "ARGS: <!-- promoted-from-basic: $FID -->" \
  && ! printf '%s\n' "$out" | grep -q 'split: false' && printf '%s\n' "$out" | grep -qxF "PROCEDURE: $PLUGIN/skills/specifying-ko/basic-promote.md" \
  && ok "U3 ★ 승인 전 승격(stage=spec) — 1줄 고지 · 이어 갈 skill·args · 절차 파일" || no "U3" "rc=$rc $out"
[ -f "$UD/spec.md" ] && cmp -s "$UD/spec.md" "$UD/basic-draft/spec.md" && grep -q '^- 단계: spec' "$UD/basic-draft/promoted.md" \
  && grep -qE '^- [0-9-]+ [0-9:]+ /full 승격 ' "$u/.specops/session-progress.md" \
  && ok "U4 ★ spec 1장은 제자리에 남고 사본을 보존 · 승격 기록 · 진행 기록(/full 승격)" || no "U4"
before=$(grep -c '/full 승격' "$u/.specops/session-progress.md"); out2=$(_bp "$u" promote "$FID" "다른 사유")
[ "$(grep -c '/full 승격' "$u/.specops/session-progress.md")" = "$before" ] && printf '%s\n' "$out2" | grep -qx 'NOTICE: 위험 신호 인증·권한 — 풀 경로로 올림.' \
  && ok "U5 다시 promote 해도 기록이 중복되지 않고 같은 안내를 낸다" || no "U5" "$out2"
# 구현 뒤(봉인) 승격 — 리뷰 보고서·코드가 있다. 유지보수.
FID=20261112-bp-promote2
_bp "$u" start "$FID" "줄 수 세기 버그" maintain >/dev/null; _fill_spec "$u"
US2="$u/.specops/$FID/spec.md"
sed -i.bak 's/^\*\*§기본\*\*: true$/&\
**§유형**: 유지보수/' "$US2"; rm -f "$US2.bak"
awk '/^### 범위 밖/ { print "### 현재 동작과 영향\n\n- 빈 줄도 센다.\n" } /^## 4\. / { print "### AC-R-1: 종전대로 센다\n\n**우선순위**: must\n**Given** 파일\n**When** 옵션 없이 실행\n**Then** 종전과 같다\n**검증 방법**: bash scripts/tests/test-count.sh\n" } { print }' "$US2" > "$US2.t" && mv "$US2.t" "$US2"
_bp "$u" approve "$FID" >/dev/null || no "U6.pre" "approve 실패"
UD="$u/.specops/$FID"; mkdir -p "$UD/reviews" "$u/db/migrations"
printf '# B\n**판정**: PASS\n' > "$UD/reviews/T1-B-report.md"; printf '# C\n**판정**: READY_TO_MERGE\n' > "$UD/reviews/T1-C-report.md"
printf '#!/usr/bin/env bash\ngrep -c . "$1"\n' > "$u/scripts/count.sh"; printf 'x\n' > "$u/db/migrations/001.sql"
out=$(_bp "$u" seal "$FID" "bash scripts/tests/test-count.sh" 2>&1); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -qF "basic-path.sh promote $FID" && ok "U6 ★ seal 의 풀 신호(rc 3) 안내가 promote 를 가리킨다" || no "U6" "rc=$rc $out"
out=$(_bp "$u" promote "$FID" "위험 신호 DB 스키마(db/migrations)"); rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx "BASIC: PROMOTED $FID stage=code kind=maintain" \
  && [ "$(printf '%s\n' "$out" | grep '^ARGS: ' | head -3 | paste -sd'|' -)" = "ARGS: <!-- entry: maintain -->|ARGS: <!-- promoted-from-basic: $FID -->|ARGS: <!-- split: false -->" ] \
  && printf '%s\n' "$out" | grep -qx 'NEXT: devfsd:analyzing-ko' \
  && ok "U7 ★ 구현 뒤 승격(stage=code · 유지보수) — analyzing-ko 부터 · 약속어가 첫 줄 · 세션 분리 끔" || no "U7" "rc=$rc $out"
[ ! -e "$UD/reviews" ] && [ -f "$UD/basic-draft/reviews/T1-B-report.md" ] && [ -f "$UD/basic-draft/reviews/T1-C-report.md" ] && [ ! -e "$UD/tasks.md" ] \
  && grep -qx -- '- scripts/count.sh' "$UD/basic-draft/promoted.md" && grep -qx -- '- db/migrations/001.sql' "$UD/basic-draft/promoted.md" \
  && [ -f "$u/scripts/count.sh" ] && [ -f "$u/db/migrations/001.sql" ] \
  && ok "U8 ★ 기본 경로 리뷰 보고서는 보존 폴더로 · 이미 쓴 코드는 작업 트리에 그대로 · 목록을 기록" || no "U8" "$(ls "$UD" "$UD/basic-draft" 2>&1 | tr '\n' ' ')"
( cd "$u" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/check-review-audit.sh" "$FID" 2>&1 ) | grep -q '^REVIEW-AUDIT: \(PASS\|SKIP\)' \
  && ok "U9 ★ 승격 뒤 리뷰 감사가 기본 경로 보고서를 풀 경로 것으로 읽지 않는다(감사 행 없는 보고서 0)" || no "U9" "$(cd "$u" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/check-review-audit.sh" "$FID" 2>&1 | tail -3)"
# 봉인까지 끝난 FID(1-태스크 문서·감사 기록 있음)를 올려도 그 둘이 풀 경로 자리에 남지 않는다
FID=$FID_KEEP
out=$(_bp "$d" promote "$FID" "검증에서 계약 변경 필요"); rc=$?
[ "$rc" = 0 ] && [ ! -e "$d/.specops/$FID/tasks.md" ] && [ ! -e "$d/.specops/$FID/dispatch-log.md" ] && grep -q '(/basic)' "$d/.specops/$FID/basic-draft/tasks.md" \
  && ok "U10 봉인된 FID 승격 — 1-태스크 문서·감사 기록도 보존 폴더로(분해가 새로 쓴다)" || no "U10" "rc=$rc $out"
q="$TMP/quickfid"; mkdir -p "$q/.specops/$FID"; ( cd "$q" && git init -q -b main ); printf '# spec\n' > "$q/.specops/$FID/spec.md"
_bp "$q" promote "$FID" "x" >/dev/null 2>&1; [ $? = 1 ] && [ ! -e "$q/.specops/$FID/basic-draft" ] && ok "U11 기본 경로가 아닌 FID 는 올리지 않는다(rc 1 · 아무것도 옮기지 않는다)" || no "U11"
PR="$PLUGIN/skills/specifying-ko/basic-promote.md"
has "$PLUGIN/skills/specifying-ko/SKILL.md" '<!-- promoted-from-basic: <FID> -->' '`basic-promote.md`' && has "$PLUGIN/skills/analyzing-ko/SKILL.md" '<!-- promoted-from-basic: <FID> -->' 'basic-promote.md' \
  && ok "U12 specifying-ko·analyzing-ko 는 승격 진입을 보조 문서로 넘긴다(본문은 포인터 1줄)" || no "U12"
has "$PR" 'FID·브랜치를 새로 만들지 않는다' '**다시 묻지 않는다**' '풀 형식으로 다시 쓴다' '`intent.md`' 'Step 5.6' '승인은 풀 형식으로 1회' '`clarifying-ko` → `planning-ko`' \
  '## 이미 작성된 코드' '`plan-reviewer-ko`' '`<!-- split: false -->`' '전체 diff' '`§lite`·trivial 단축 경로를 쓰지 않는다' '실측은 아직 없다' \
  && ok "U13 승격 절차 문서 — FID 재사용 · spec 풀 형식 · 승인 1회 · clarify/plan 부터 · 이미 쓴 코드를 plan 리뷰·구현 뒤 리뷰가 본다 · 미주행 고지" || no "U13"
has "$PLUGIN/commands/basic.md" '## 풀 경로로 올리기 (승격)' 'basic-path.sh promote <FID>' '`NOTICE:` 줄을 사용자에게 그대로 보인다' '멈추고 안내만 하지 않는다' \
  && ok "U14 /basic 문서 — 풀 신호는 멈춤이 아니라 승격" || no "U14"
grep -qF "const PROMOTED_CMD = '/full'" "$PLUGIN/hooks/progress-pane.tsx" && grep -qF '!recs.some(r => r.cmd === PROMOTED_CMD)' "$PLUGIN/hooks/progress-pane.tsx" \
  && ok "U15 관제판 — 승격 기록(/full)이 있으면 풀 경로 단계로 표시" || no "U15"
FID=$FID_KEEP

# ── D 문서 잠금 ──
C="$PLUGIN/commands/basic.md"
has "$C" 'disable-model-invocation: true' '/basic' && ok "D1 슬래시 전용 명령(모델 자동 호출 금지)" || no "D1"
has "$C" '**주 세션이 직접 구현**' '서브에이전트에게 구현을 맡기지 않는다' '**실패하는 테스트를 먼저**' '**관련 테스트만**' \
  && ok "D2 주 세션 직접 구현 · 테스트 먼저 · 관련 테스트만" || no "D2"
has "$C" '한 메시지에서 함께 보낸다' 'devfsd:spec-reviewer-ko' 'devfsd:code-reviewer-ko' 'security-scan.sh' '**PR 본문을 준비**' '재리뷰는 없다' \
  && ok "D3 스펙·코드 리뷰 + 보안 스캔 동시 1회 · 그동안 PR 본문 준비 · 재리뷰 없음" || no "D3"
has "$C" 'basic-path.sh start' 'basic-path.sh approve' 'basic-path.sh seal' 'run-verification.sh <FID>' '/verify PASS' '우회하지 않고' \
  && ok "D4 start → approve → seal → 검증 러너 → 진행 기록 · 훅 우회 금지" || no "D4"
has "$C" '데이터 삭제·이관 · 되돌릴 수 없는 외부 작업 · 결제·개인정보 · 태스크 4개 이상' '**애매하면 무거운 쪽**' '종료 코드 3' \
  && ok "D5 풀 조건(무거운 신호 3종 · 태스크 4개 이상) · 애매하면 무거운 쪽 · 승격(rc 3)" || no "D5"
has "$C" '### 켜지는 단계' 'basic-path.sh plan <FID> <태스크 수>' '`ANALYSIS: doc <경로>`' '`PLAN: yes <경로>`' '`EXPERTS: <에이전트…>`' '**결정만 적는다**' '**한 메시지에서 동시에**' 'unified_path: false' '봉인은 이 보고서가 없으면 받지 않는다' \
  && ok "D5b 통합 절차 — 켜지는 단계 표 · plan 하위 명령 · 분석·계획·전문가 · 끄는 스위치" || no "D5b"
has "$C" '갈래를 바꾸지 않고 **설계 확인 범위만**' 'DESIGN: none' 'DESIGN: update' 'DESIGN: approve' \
  && ok "D6 화면 변경량은 설계 확인 범위만 정한다(3단계)" || no "D6"
has "$C" '**모델이 갈래를 고르기**' '**표본 2건**' '아직 재지 않았다' '미실행 게이트' && ok "D7 모델이 갈래를 고르지 않는다 · 표본·미측정 고지 · 미실행 게이트 표기" || no "D7"
has "$C" 'basic-path.sh review <FID>' && grep -qF "cmds: ['/approve', BASIC_CMD]" "$PLUGIN/hooks/progress-pane.tsx" \
  && for c in /implement /review /verify /lifecycle; do grep -qF "cmds: ['$c']" "$PLUGIN/hooks/progress-pane.tsx" || exit 1; done \
  && ok "D10 리뷰 dispatch 전 review 기록 · 관제판 기본 경로 단계가 이 스크립트의 기록 이름을 읽는다" || no "D10"
has "$C" '`UI:` 줄' '**목업 CSS 이식**' 'Tailwind' '최소 구현(YAGNI)으로 줄이지 않는다' \
  && ok "D11 ★ 화면을 건드리면 구현 첫 일은 목업 CSS 이식(풀 경로 planning 과 같은 규칙)" || no "D11"
has "$C" '**화면 점검**' 'ui-probe.cjs --out .specops/<FID>/ui' '.specops/memory/ui-probe.json' 'check-mock-css.sh' '`UI-PROBE: FAIL`' '**PASS 로 적지 않는다**' \
  '**브라우저**: 실행(' '**브라우저**: 미실행(' '**접근성 기준선 첫 실행**' '방금 만든 위반을 기준선에 넣지 않는다' && ok "D12 ★ 봉인 전 브라우저 점검 1회 · 생존율 계측 · FAIL 은 고친다 · SKIP 은 PASS 아님 · evidence 브라우저 줄" || no "D12"
has "$C" '서버 시작 명령·포트·화면 경로' && ok "D13 화면 기록이 없으면 질문 묶음에서 한 번에 묻는다(승인 뒤 무질문 유지)" || no "D13"
has "$C" 'basic-path.sh related' 'RELATED: none' '**프로젝트의 테스트 명령 전체**' '**전체 스위트는 여기서 돌리지 않는다**' 'push 전 게이트' \
  && ok "D9 검증 명령은 related 의 답 · 매핑 없으면 전체 명령 · 전체 스위트는 push 전 게이트와 CI" || no "D9"
grep -qF '`/quick-fix`·`--full`·`--step` 은 슬래시 전용' "$PLUGIN/skills/using-specops-ko/SKILL.md" \
  && ok "D8 메타 skill: /quick-fix·--full·--step 은 슬래시 전용" || no "D8"

# ── K 판정 방향 잠금 (20261113 변이 실측에서 살아남은 4건 + 낱말 표) ──
# K1 "범위 밖" 절은 **그 절만** 가린다 — 뒤따르는 같은 깊이의 절(화면 변경)에 든 위험 낱말은 신호다 (변이: lvl <= depth → <)
g=$(_repo gap); _bp "$g" start "$FID" "줄 수 세기 명령에 옵션 추가" >/dev/null
_fill_spec "$g"
awk 'f && $0 == "없음" { print "로그인 화면의 권한 안내 문구를 바꾼다"; f = 0; next } /^### 화면 변경/ { f = 1 } { print }' "$g/.specops/$FID/spec.md" > "$g/.specops/$FID/spec.new" \
  && mv "$g/.specops/$FID/spec.new" "$g/.specops/$FID/spec.md"
out=$(_bp "$g" approve "$FID"); rc=$?
[ "$rc" = 3 ] && [ ! -e "$g/.specops/$FID/acceptance-criteria.md" ] && ok "K1 ★ '범위 밖' 뒤 같은 깊이 절의 위험 낱말 → rc 3 (가림은 그 절에서 끝난다)" || no "K1" "rc=$rc $out"

# ── C 판정 대상 절 (20261114) — 무엇을 바꾸는지 적는 절(목표·범위)만 본다 ──
c=$(_repo corpus); _bp "$c" start "$FID" "줄 수 세기 명령에 옵션 추가" maintain >/dev/null
_cspec() {  # <awk 치환 프로그램> — 기본 spec 을 채운 뒤 한 줄을 바꾼다
  _fill_spec "$c"
  awk '/^### 범위 밖/ { print "### 현재 동작과 영향\n\n- scripts/count.sh 는 빈 줄도 센다.\n" } /^## 4\. / { print "### AC-R-1: 종전대로 센다\n\n**우선순위**: must\n**Given** 파일\n**When** 옵션 없이 실행한다\n**Then** 전체 줄 수를 출력한다\n**검증 방법**: bash scripts/tests/test-count.sh\n" } { print }' "$c/.specops/$FID/spec.md" \
    | sed 's/^\*\*§기본\*\*: true$/**§기본**: true\n**§유형**: 유지보수/' | awk "$1" > "$c/.specops/$FID/spec.new" && mv "$c/.specops/$FID/spec.new" "$c/.specops/$FID/spec.md"
  rm -f "$c/.specops/$FID/acceptance-criteria.md"
}
_cspec '{ sub(/^\*\*Given\*\* 빈 줄 2개/, "**Given** 로그인한 관리자 권한 사용자가 빈 줄 2개"); print }'
out=$(_bp "$c" approve "$FID"); rc=$?
[ "$rc" = 0 ] && ok "C1 ★ 수용 기준의 전제에 나온 낱말(로그인·권한)은 신호가 아니다 → 승인" || no "C1" "rc=$rc $out"
_cspec '{ sub(/^- scripts\/count.sh 는 빈 줄도 센다\./, "- scripts/count.sh 는 인증 토큰 검사 뒤에 불리고 테이블 추가 마이그레이션과는 무관하다."); print }'
out=$(_bp "$c" approve "$FID"); rc=$?
[ "$rc" = 0 ] && ok "C2 ★ '현재 동작과 영향' 절의 낱말은 신호가 아니다 → 승인" || no "C2" "rc=$rc $out"
_cspec 'f && $0 == "없음" { print "응답 형태와 하위 호환은 해당 없다"; f = 0; next } /^## 4\. / { f = 1 } { print }'
out=$(_bp "$c" approve "$FID"); rc=$?
[ "$rc" = 0 ] && ok "C3 ★ 비기능 요구 절의 낱말은 신호가 아니다 → 승인" || no "C3" "rc=$rc $out"
_cspec '{ sub(/^줄 수 세기 명령에 빈 줄 제외 옵션을 더한다\./, "줄 수 세기 명령의 권한 검사를 고친다."); print }'
out=$(_bp "$c" approve "$FID"); rc=$?
[ "$rc" = 3 ] && ok "C4 ★ 목표 절의 풀 신호 → rc 3 (변이: 목표 절을 판정에서 빼면 통과한다)" || no "C4" "rc=$rc $out"
_cspec '{ print }'
out=$(_bp "$c" approve "$FID"); rc=$?
[ "$rc" = 0 ] || no "C5.pre" "rc=$rc $out"
( cd "$c" && mkdir -p src/auth && printf 'x\n' > src/auth/guard.sh && git add src/auth/guard.sh )
out=$(_bp "$c" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 3 ] && ok "C5 ★ 목표·범위에 적지 않은 변경은 봉인이 바뀐 파일로 잡는다 → rc 3" || no "C5" "rc=$rc $out"
# C6 목표·범위 절이 없는 문서는 전문을 본다 — 모르면 무거운 쪽 (변이: found 폴백 삭제 → basic)
printf '# x\n\n## 개요\n\n로그인 권한 검사를 고친다.\n' > "$c/.specops/$FID/spec.md"
out=$(_bp "$c" lane "x" "$FID"); rc=$?
[ "$rc" = 3 ] && ok "C6 ★ 목표·범위 절이 없는 spec 은 전문으로 판정 → full" || no "C6" "rc=$rc $out"

# C7~C9 가림이 목표·범위 절을 통째로 지우지 않는다 (코드 리뷰 실측 — 셋 다 고치기 전에는 basic 이었다)
_cspec '{ sub(/^줄 수 세기 명령에 빈 줄 제외 옵션을 더한다\./, "줄 수 세기 명령의 권한 검사를 고친다."); sub(/^## 1\. 목표$/, "## 1. 목표 (현재 동작 개선 · 일부 제외)"); print }'
out=$(_bp "$c" approve "$FID"); rc=$?
[ "$rc" = 3 ] && ok "C7 ★ 2단계 제목에 제외 낱말이 붙어도 목표 절은 본다 → rc 3" || no "C7" "rc=$rc $out"
_cspec '{ sub(/^줄 수 세기 명령에 빈 줄 제외 옵션을 더한다\./, "줄 수 세기 명령의 권한 검사를 고친다."); sub(/^# .*spec \(기본 경로\)$/, "# 빈 줄 제외 옵션 — spec (기본 경로)"); print }'
out=$(_bp "$c" approve "$FID"); rc=$?
[ "$rc" = 3 ] && ok "C8 ★ 1단계 제목의 제외 낱말은 가림을 열지 않는다 → rc 3" || no "C8" "rc=$rc $out"
_cspec '/^- scripts\/count.sh 에 옵션을 더한다/ { print "```bash"; print "# 빈 줄 제외 예시"; print "```"; print "- 로그인 권한 검사를 고친다"; next } { print }'
out=$(_bp "$c" approve "$FID"); rc=$?
[ "$rc" = 3 ] && ok "C9 ★ 코드 펜스 안 # 줄은 제목이 아니다 — 뒤따르는 범위 줄의 풀 신호 → rc 3" || no "C9" "rc=$rc $out"
# C10 봉인의 경로 신호 — 인증·스키마 이름이 든 경로는 풀, 평범한 경로는 기본
_cspec '{ print }'; _bp "$c" approve "$FID" >/dev/null
for pth in prisma/schema.prisma db/schema.sql src/models/user.py src/lib/session.ts src/AuthService.ts src/middleware/guard.ts; do
  ( cd "$c" && git reset -q && git clean -fdq -e .specops && mkdir -p "$(dirname "$pth")" && printf 'x\n' > "$pth" && git add "$pth" )
  out=$(_bp "$c" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
  [ "$rc" = 3 ] && ok "C10 ★ 봉인: $pth → rc 3" || no "C10 $pth" "rc=$rc $out"
done
( cd "$c" && git reset -q && git clean -fdq -e .specops && mkdir -p src/routes scripts && printf 'x\n' > src/routes/orders.ts && printf 'x\n' > scripts/count.sh && git add src scripts )
out=$(cd "$c" && bash "$BP" lane "x" "$FID" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "C11 평범한 spec 은 lane basic (경로 신호는 봉인에서만 본다)" || no "C11" "rc=$rc $out"
# C12 경로 신호의 오탐 방지 — 글쓴이(author)·session-progress·새 라우트 파일은 인증·스키마가 아니다
( cd "$c" && git reset -q && git clean -fdq -e .specops && mkdir -p src/routes scripts && printf 'x\n' > src/routes/authors.ts && printf 'x\n' > scripts/session-progress-append.sh && git add src scripts )
out=$(_bp "$c" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" != 3 ] && ok "C12 ★ 봉인: authors.ts · session-progress-append.sh 는 풀 신호가 아니다" || no "C12" "rc=$rc $out"

# K2 판정기를 읽을 수 없으면 가벼운 쪽으로 열리지 않는다 — route 는 풀, lane 은 rc 1 (변이: 판정 불가 가지 삭제)
mkdir -p "$TMP/plug/scripts"; cp "$BP" "$TMP/plug/scripts/basic-path.sh"
out=$( cd "$g" && bash "$TMP/plug/scripts/basic-path.sh" route start "목록 화면에 정렬 버튼 추가" 2>&1 ); rc=$?
printf '%s\n' "$out" | grep -q '^ROUTE: full — 위험 신호 판정 불가' && ! printf '%s\n' "$out" | grep -q '^ROUTE: basic' \
  && ok "K2 ★ 판정기 부재 → ROUTE: full(판정 불가) — basic 으로 열리지 않는다" || no "K2" "rc=$rc $out"
out=$( cd "$g" && bash "$TMP/plug/scripts/basic-path.sh" lane "목록 화면에 정렬 버튼 추가" 2>&1 ); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^LANE: full ' && ok "K2b 판정기 부재 → lane rc 1 · LANE: full" || no "K2b" "rc=$rc $out"

# K4 변경 파일이 없으면 봉인하지 않는다 (변이: 빈 목록 검사 삭제) · K3 리뷰 보고서는 둘 다 있어야 한다 (변이: && → ||)
_fill_spec "$g"; _bp "$g" approve "$FID" >/dev/null
out=$(_bp "$g" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '변경된 파일이 없다' && [ ! -e "$g/.specops/$FID/tasks.md" ] && ok "K4 ★ 변경 파일 없이 seal → rc 1 · 태스크 문서 없음" || no "K4" "rc=$rc $out"
printf '#!/usr/bin/env bash\ngrep -c . "$1"\n' > "$g/scripts/count.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$g/scripts/tests/test-count.sh"; chmod +x "$g/scripts/count.sh" "$g/scripts/tests/test-count.sh"
mkdir -p "$g/.specops/$FID/reviews"
printf '# B\n**판정**: PASS\n' > "$g/.specops/$FID/reviews/T1-B-report.md"
out=$(_bp "$g" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 4 ] && [ ! -e "$g/.specops/$FID/tasks.md" ] && ok "K3a ★ 스펙 리뷰 보고서만 있고 코드 리뷰 보고서가 없으면 seal rc 4" || no "K3a" "rc=$rc $out"
rm -f "$g/.specops/$FID/reviews/T1-B-report.md"
printf '# C\n**판정**: READY_TO_MERGE\n' > "$g/.specops/$FID/reviews/T1-C-report.md"
out=$(_bp "$g" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 4 ] && [ ! -e "$g/.specops/$FID/tasks.md" ] && ok "K3b ★ 코드 리뷰 보고서만 있고 스펙 리뷰 보고서가 없으면 seal rc 4" || no "K3b" "rc=$rc $out"

# K5 위험 낱말 표 — 낱말 하나만 든 문장이 그 종류의 신호로 풀 판정이 나는가 (20261113: 95개 중 55개가 어느 스위트에도 없었다 — 낱말 삭제·오타가 통과했다)
#   한 줄 = `<신호 이름>|<그 낱말만 위험한 문장>`. 판정기(basic-path.sh _ko_signals · risk-profile.sh rp::detect_strict_signals)에 낱말을 더하면 여기에도 더한다.
kw_total=0; kw_bad=""
while IFS='|' read -r kc kq; do
  [ -n "$kc" ] || continue
  kw_total=$((kw_total+1))
  out=$(_bp "$d" lane "$kq"); rc=$?
  { [ "$rc" = 3 ] && printf ' %s ' "${out#LANE: full }" | grep -qF " $kc "; } || kw_bad="$kw_bad [$kc|$kq → rc=$rc $out]"
done <<'KW'
auth|화면에 인증 안내를 더한다
auth|인가 규칙 설명을 고친다
auth|권한 안내를 고친다
auth|로그인 문구를 고친다
auth|비밀번호 안내를 고친다
auth|세션 토큰 설명을 고친다
auth|auth 모듈 주석을 고친다
auth|oauth 설명을 고친다
auth|jwt 설명을 고친다
auth|rbac 설명을 고친다
auth|permission 표를 고친다
auth|credential 설명을 고친다
auth|secret 이름을 바꾼다
auth|값을 .env 에서 읽는다
db_schema|스키마 설명을 고친다
db_schema|마이그레이션 안내를 고친다
db_schema|컬럼 이름을 고친다
db_schema|주문 테이블 추가
db_schema|주문 테이블 변경
db_schema|주문 테이블 삭제
db_schema|주문 테이블 생성
db_schema|주문 인덱스 추가
db_schema|주문 인덱스 삭제
db_migration|migration 파일을 본다
db_migration|alembic 설정을 본다
db_migration|prisma/migrations 를 본다
db_migration|supabase/migrations 를 본다
db_migration|CREATE TABLE orders
db_migration|ALTER TABLE orders
db_migration|DROP TABLE orders
db_migration|data-model.md 를 고친다
data_move|오래된 데이터 삭제
data_move|주문 데이터 이관
data_move|주문 데이터 이전
data_move|주문 데이터 정리
data_move|주문 일괄 삭제
data_move|주문 백필
data_move|orders backfill
data_move|truncate orders
data_move|purge orders
api_shape|주문 조회 응답 형태를 본다
api_shape|주문 조회 응답 형식을 본다
api_shape|주문 조회 응답 구조를 본다
api_shape|주문 조회 응답 필드를 본다
api_shape|주문 조회 응답 스키마를 본다
api_shape|하위 호환 설명을 고친다
api_shape|breaking 표시를 더한다
api_shape|주문 API 변경
api_shape|주문 API 수정
api_shape|주문 API 삭제
irreversible_ext|운영 배포 안내를 고친다
irreversible_ext|운영 반영 안내를 고친다
irreversible_ext|결제 화면 문구를 고친다
irreversible_ext|과금 문구를 고친다
irreversible_ext|환불 문구를 고친다
irreversible_ext|가입 메일 발송
irreversible_ext|가입 문자 발송
irreversible_ext|가입 푸시 발송
irreversible_ext|가입 알림 발송
irreversible_ext|되돌릴 수 없는 작업 안내
destructive_fs|irreversible: true 표시
destructive_fs|Delete: 항목을 본다
destructive_fs|unlink( 호출을 본다
destructive_fs|rm -rf 를 쓴다
destructive_fs|path.join 을 쓴다
destructive_fs|filesystem 접근을 본다
destructive_fs|fs.unlink 를 쓴다
destructive_fs|fs.rm 을 쓴다
payment_pii|payment 화면을 본다
payment_pii|billing 화면을 본다
payment_pii|pii 필드를 본다
payment_pii|개인정보 안내를 고친다
payment_pii|주민등록 번호 칸을 본다
payment_pii|credit card 칸을 본다
public_api|api-spec.md 를 고친다
public_api|/api/ 경로를 본다
public_api|openapi 문서를 본다
public_api|public api 문서를 본다
public_api|엔드포인트 설명을 고친다
infra|.github/workflows 를 본다
infra|Dockerfile 을 본다
infra|terraform 설정을 본다
infra|kubernetes 설정을 본다
infra|k8s 설정을 본다
infra|helm 차트를 본다
infra|deploy 안내를 고친다
external_exec|subprocess 를 쓴다
external_exec|child_process 를 쓴다
external_exec|os.system 을 쓴다
external_exec|exec( 호출을 본다
external_exec|bash -c 로 돌린다
external_exec|Runtime.exec 를 쓴다
cross_service|cross-service 호출을 본다
cross_service|microservice 구성을 본다
cross_service|message queue 를 쓴다
cross_service|sqs 를 쓴다
cross_service|kafka 를 쓴다
cross_service|external api 를 부른다
KW
[ -z "$kw_bad" ] && [ "$kw_total" -ge 95 ] && ok "K5 ★ 위험 낱말 ${kw_total}개 — 낱말마다 그 종류의 신호로 풀 판정(rc 3)" || no "K5" "total=$kw_total 빠짐:$kw_bad"


# ── N 통합 절차 (20261114 · 기본값) — 위험 신호는 갈래가 아니라 켤 단계를 정한다 ──
export SPECOPS_UNIFIED_PATH=1
n=$(_repo uni)
out=$(_bp "$n" lane "로그인 권한 검사를 바꾼다"); rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx 'LANE: basic' && printf '%s\n' "$out" | grep -q '^SIGNALS: .*auth' && ok "N1 ★ 가벼운 신호(인증) → basic + SIGNALS 줄 (rc 0)" || no "N1" "rc=$rc $out"
# 신호 → 전문가 매핑 (변이: 매핑 가지를 비우면 전문가 없이 지나간다)
nm=$(_repo unimap); i=0
for pair in "주문 테이블 컬럼 추가|devfsd:db-designer-ko" "주문 조회 응답 형식을 바꾼다|devfsd:api-designer-ko" "add kafka consumer|devfsd:arch-designer-ko" "run child_process for lint|devfsd:security-designer-ko"; do
  i=$((i+1)); q="${pair%%|*}"; want="${pair##*|}"
  _bp "$nm" start "$FID" "$q" >/dev/null; _fill_spec "$nm" "$q"; out=$(_bp "$nm" approve "$FID"); rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "^EXPERTS: .*$want" && ok "N1b.$i ★ 신호 → 전문가: $q → $want" || no "N1b.$i" "rc=$rc $out"
  rm -rf "$nm/.specops/$FID"
done
i=0
for q in "오래된 데이터 삭제 배치" "결제 취소 시 환불 호출" "개인정보 필드를 내려준다" "rm -rf 로 캐시를 지운다" "deploy 스크립트를 고친다"; do
  i=$((i+1)); out=$(_bp "$n" lane "$q"); rc=$?
  [ "$rc" = 3 ] && printf '%s' "$out" | grep -q '^LANE: full ' && ok "N2.$i ★ 무거운 신호 → full (rc 3): $q" || no "N2.$i" "rc=$rc $out"
done
out=$(_bp "$n" route maintain "로그인 권한 검사를 바꾼다")
printf '%s\n' "$out" | grep -q '^ROUTE: basic — 위험 신호(인증·권한)' && printf '%s\n' "$out" | grep -q '^NOTICE: .*계획과 전문가 검토를 켠다' && printf '%s\n' "$out" | grep -q '^PROCEDURE: ' \
  && ok "N3 ★ route — 가벼운 신호는 기본 경로 + 켤 단계 고지" || no "N3" "$out"
out=$(_bp "$n" route start "오래된 데이터 삭제 배치")
printf '%s\n' "$out" | grep -q '^ROUTE: full — 위험 신호(데이터 삭제·이관)' && ok "N4 route — 무거운 신호는 풀" || no "N4" "$out"
out=$(_bp "$n" route start "--full 목록 화면에 정렬 버튼 추가")
printf '%s\n' "$out" | grep -q '^ROUTE: full — --full 지정' && ok "N4b route — --full 은 종전 풀 경로" || no "N4b" "$out"

# 분석 문서 — 위험 신호가 걸린 유지보수만
out=$(_bp "$n" start "$FID" "로그인 권한 검사를 바꾼다" maintain); rc=$?
A="$n/.specops/$FID/analysis.md"
[ "$rc" = 0 ] && [ -f "$A" ] && grep -q '^## 1. 현재 동작' "$A" && grep -q '^## 3. 깨질 수 있는 기존 동작' "$A" && printf '%s\n' "$out" | grep -q '^ANALYSIS: doc ' \
  && ok "N5 ★ 신호 있는 유지보수 → analysis.md 골격 + ANALYSIS: doc" || no "N5" "rc=$rc $out"
n2=$(_repo uni2); out=$(_bp "$n2" start "$FID" "로그인 권한 검사를 바꾼다"); rc=$?
[ "$rc" = 0 ] && [ ! -e "$n2/.specops/$FID/analysis.md" ] && printf '%s\n' "$out" | grep -qx 'ANALYSIS: none' && ok "N5b 신규는 분석 문서 없음" || no "N5b" "rc=$rc $out"
n3=$(_repo uni3); out=$(_bp "$n3" start "$FID" "줄 수 세기 명령에 옵션 추가" maintain); rc=$?
[ "$rc" = 0 ] && [ ! -e "$n3/.specops/$FID/analysis.md" ] && printf '%s\n' "$out" | grep -q '^ANALYSIS: section' && ok "N5c 신호 없는 유지보수는 spec 의 절로 (분석 문서 없음)" || no "N5c" "rc=$rc $out"

_mspec() {  # <repo> <범위 줄> — 유지보수 spec 을 채운다
  _fill_spec "$1" "$2"
  awk '/^### 범위 밖/ { print "### 현재 동작과 영향\n\n- analysis.md 참조.\n" } /^## 4\. / { print "### AC-R-1: 종전대로 센다\n\n**우선순위**: must\n**Given** 파일\n**When** 옵션 없이 실행한다\n**Then** 전체 줄 수를 출력한다\n**검증 방법**: bash scripts/tests/test-count.sh\n" } { print }' "$1/.specops/$FID/spec.md" \
    | sed 's/^\*\*§기본\*\*: true$/**§기본**: true\n**§유형**: 유지보수/' > "$1/.specops/$FID/spec.new" && mv "$1/.specops/$FID/spec.new" "$1/.specops/$FID/spec.md"
}
_mspec "$n" "로그인 권한 검사를 고친다"
out=$(_bp "$n" approve "$FID"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'analysis.md 에 채우지 않은' && [ ! -e "$n/.specops/$FID/acceptance-criteria.md" ] && ok "N6 ★ 채우지 않은 분석 문서 → approve rc 1" || no "N6" "rc=$rc $out"
printf '# 분석\n\n## 1. 현재 동작\n\n- x\n' > "$A"
out=$(_bp "$n" approve "$FID"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "영향 범위" && ok "N6a ★ 분석 문서에 절이 빠지면 approve rc 1" || no "N6a" "rc=$rc $out"
printf '# 분석\n\n## 1. 현재 동작\n\n- check() 가 역할을 본다.\n\n## 2. 영향 범위\n\n- 호출자 2곳.\n\n## 3. 깨질 수 있는 기존 동작\n\n- 관리자 통과.\n' > "$A"
out=$(_bp "$n" approve "$FID"); rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx 'EXPERTS: devfsd:security-designer-ko' && grep -q '/analyze 완료' "$n/.specops/session-progress.md" \
  && ok "N6b ★ 승인 → EXPERTS 줄(인증 → 보안 전문가) · 분석 완료 기록" || no "N6b" "rc=$rc $out"

# plan — 켤 단계 판정
for bad in 0 abc "" 00 07 1000 99999999999999999999; do out=$(_bp "$n" plan "$FID" "$bad"); [ $? = 1 ] || no "N7.bad[$bad]" "$out"; done; ok "N7 ★ plan — 태스크 수는 1~999 의 정수(0 시작·큰 수 거부 — 큰 수가 상한 검사를 지나가지 않는다)"
out=$(_bp "$n" plan "$FID" 4); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'PLAN: full' && [ ! -e "$n/.specops/$FID/plan.md" ] && [ ! -e "$n/.specops/$FID/steps.txt" ] \
  && ok "N7b ★ 태스크 4개 이상 → rc 3 (풀 경로로) · 계획·판정 기록 없음" || no "N7b" "rc=$rc $out"
out=$(_bp "$n" plan "$FID" 1); rc=$?
P="$n/.specops/$FID/plan.md"
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^PLAN: yes ' && printf '%s\n' "$out" | grep -qx 'EXPERTS: devfsd:security-designer-ko' \
  && [ "$(grep -c '^### Task ' "$P")" = 1 ] && grep -q '^## 3. 위험 신호 대응' "$P" && grep -q '^signals=.*auth' "$n/.specops/$FID/steps.txt" \
  && ok "N7c ★ 신호가 있으면 태스크 1개여도 계획 + 위험 신호 대응 절 · 판정 기록" || no "N7c" "rc=$rc $out"
out=$(_bp "$n" review "$FID"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'plan.md 에 채우지 않은' && ok "N8 ★ 채우지 않은 계획으로는 review 로 못 간다 (rc 1)" || no "N8" "rc=$rc $out"
_fill_spec "$n3" "scripts/count.sh 에 옵션을 더한다"; _mspec "$n3" "scripts/count.sh 에 옵션을 더한다"; _bp "$n3" approve "$FID" >/dev/null
out=$(_bp "$n3" plan "$FID" 1); rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^PLAN: skip' && printf '%s\n' "$out" | grep -qx 'EXPERTS: none' && [ ! -e "$n3/.specops/$FID/plan.md" ] && [ -f "$n3/.specops/$FID/steps.txt" ] \
  && ok "N7d ★ 태스크 1개 · 신호 없음 → 계획 건너뜀 · 전문가 없음" || no "N7d" "rc=$rc $out"
rm -f "$n3/.specops/$FID/steps.txt"; out=$(_bp "$n3" plan "$FID" 2); rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^PLAN: yes ' && [ "$(grep -c '^### Task ' "$n3/.specops/$FID/plan.md")" = 2 ] && ok "N7d2 ★ 경계 — 태스크 2개면 신호 없어도 계획" || no "N7d2" "rc=$rc $out"
rm -f "$n3/.specops/$FID/plan.md"
out=$(_bp "$n3" plan "$FID" 3); rc=$?
[ "$rc" = 0 ] && [ "$(grep -c '^### Task ' "$n3/.specops/$FID/plan.md")" = 3 ] && ! grep -q '위험 신호 대응' "$n3/.specops/$FID/plan.md" \
  && ok "N7e 태스크 3개 · 신호 없음 → 계획(태스크 3칸 · 신호 절 없음)" || no "N7e" "rc=$rc $out"

# seal 안전망
sed 's/{{[^}]*}}/x/g' "$P" > "$P.t" && mv "$P.t" "$P"
printf '#!/usr/bin/env bash\ngrep -c . "$1"\n' > "$n/scripts/count.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$n/scripts/tests/test-count.sh"; chmod +x "$n/scripts/count.sh" "$n/scripts/tests/test-count.sh"
_bp "$n" review "$FID" >/dev/null
mkdir -p "$n/.specops/$FID/reviews"
printf '# B\n**판정**: PASS\n' > "$n/.specops/$FID/reviews/T1-B-report.md"
printf '# C\n**Phase B 상태**: PENDING(병렬 dispatch)\n**판정**: READY_TO_MERGE\n' > "$n/.specops/$FID/reviews/T1-C-report.md"
out=$(_bp "$n" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '전문가 보고서가 없다: experts/security.md' && [ ! -e "$n/.specops/$FID/tasks.md" ] \
  && ok "N9 ★ 켜기로 한 전문가의 보고서 없이 seal → rc 1" || no "N9" "rc=$rc $out"
mkdir -p "$n/.specops/$FID/experts"; : > "$n/.specops/$FID/experts/security.md"
out=$(_bp "$n" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '전문가 보고서가 없다' && ok "N9a ★ 빈 전문가 보고서 → rc 1" || no "N9a" "rc=$rc $out"
printf '# 보안\n지적 1건\n' > "$n/.specops/$FID/experts/security.md"
out=$(_bp "$n" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q "'## 반영' 절이 없다" && ok "N9a2 ★ 반영 절 없는 전문가 보고서 → rc 1" || no "N9a2" "rc=$rc $out"
printf '# 보안\n## 반영\n- 반영\n' > "$n/.specops/$FID/experts/security.md"
sed 's/^experts=.*/experts=/' "$n/.specops/$FID/steps.txt" > "$n/.specops/$FID/steps.t" && mv "$n/.specops/$FID/steps.t" "$n/.specops/$FID/steps.txt"
mv "$n/.specops/$FID/experts/security.md" "$n/.specops/$FID/experts/sec.bak"
out=$(_bp "$n" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q '전문가 보고서가 없다' && ok "N9a3 ★ 판정 기록의 전문가 줄을 비워도 spec 신호로 다시 구해 막는다" || no "N9a3" "rc=$rc $out"
mv "$n/.specops/$FID/experts/sec.bak" "$n/.specops/$FID/experts/security.md"
printf '\n### Task 2: x\n\n### Task 3: x\n\n### Task 4: x\n' >> "$P"
out=$(_bp "$n" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q 'plan.md 의 태스크가 4개' && ok "N9a4 ★ 계획에 태스크 칸이 4개 이상이면 seal rc 3 (작게 보고한 수를 믿지 않는다)" || no "N9a4" "rc=$rc $out"
awk '/^### Task [234]: x$/ { skip = 1; next } { print }' "$P" > "$P.t" && mv "$P.t" "$P"
mkdir -p "$n/prisma"; printf 'x\n' > "$n/prisma/schema.prisma"
out=$(_bp "$n" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 3 ] && printf '%s' "$out" | grep -q '계획 때 없던 위험 신호' && [ ! -e "$n/.specops/$FID/tasks.md" ] \
  && ok "N9b ★ 계획 때 없던 신호(스키마 경로)가 구현에서 나오면 seal rc 3" || no "N9b" "rc=$rc $out"
rm -rf "$n/prisma"
out=$(_bp "$n" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 0 ] && grep -q 'test_command: "bash scripts/tests/test-count.sh"' "$n/.specops/$FID/tasks.md" && ok "N9c 신호·전문가 보고서가 계획과 맞으면 seal 통과" || no "N9c" "rc=$rc $out"
mv "$n/.specops/$FID/steps.txt" "$n/.specops/$FID/steps.bak"
out=$(_bp "$n" seal "$FID" "bash scripts/tests/test-count.sh"); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'steps.txt' && ok "N9d ★ plan 을 건너뛴 seal → rc 1" || no "N9d" "rc=$rc $out"
mv "$n/.specops/$FID/steps.bak" "$n/.specops/$FID/steps.txt"

# 스위치
unset SPECOPS_UNIFIED_PATH
out=$(_bp "$n2" lane "로그인 권한 검사를 바꾼다"); rc=$?
[ "$rc" = 0 ] && ok "N10 스위치를 정하지 않으면 통합 절차(기본값)" || no "N10" "rc=$rc $out"
for v in '"false"' 'False' 'no' 'off  # 끔'; do
  printf 'unified_path: %s\n' "$v" > "$n2/.specops/config.yaml"
  out=$(_bp "$n2" lane "로그인 권한 검사를 바꾼다"); [ $? = 3 ] || no "N10a[$v]" "$out"
done; ok "N10a 스위치 값의 따옴표·대소문자·no·주석을 끈 것으로 읽는다"
printf 'unified_path: false\n' > "$n2/.specops/config.yaml"
out=$(_bp "$n2" lane "로그인 권한 검사를 바꾼다"); rc=$?
[ "$rc" = 3 ] && ok "N10b ★ config.yaml unified_path: false → 종전 규칙(신호 하나면 풀)" || no "N10b" "rc=$rc $out"
out=$(cd "$n2" && SPECOPS_UNIFIED_PATH=1 bash "$BP" lane "로그인 권한 검사를 바꾼다" 2>&1); rc=$?
[ "$rc" = 0 ] && ok "N10c 환경 변수가 config 보다 앞선다" || no "N10c" "rc=$rc $out"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
