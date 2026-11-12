#!/usr/bin/env bash
# /basic 경로 — basic-path.sh (20261112 speed)
#   계약: 풀 신호(인증·스키마·데이터 삭제/이관·API 응답 형태·비가역 외부 작업)는 세 지점(start·approve·seal)에서 rc 3 으로 막고,
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
out=$(_bp "$d" design-scope 0); printf '%s' "$out" | grep -q '^DESIGN: none' && ok "L3a 화면 0개 → none" || no "L3a" "$out"
out=$(_bp "$d" design-scope 2); printf '%s' "$out" | grep -q '^DESIGN: update' && ok "L3b 화면 2개 일부 수정 → update" || no "L3b" "$out"
out=$(_bp "$d" design-scope 3); printf '%s' "$out" | grep -q '^DESIGN: approve' && ok "L3c ★ 화면 3개 → approve(스펙·목업 먼저)" || no "L3c" "$out"
out=$(_bp "$d" design-scope 1 new); printf '%s' "$out" | grep -q '^DESIGN: approve' && ok "L3d ★ 새 화면은 1개여도 approve" || no "L3d" "$out"
out=$(_bp "$d" design-scope 1 flow); printf '%s' "$out" | grep -q '^DESIGN: approve' && ok "L3e ★ 흐름 변경은 1개여도 approve" || no "L3e" "$out"
grep -q '^BASIC_SCREEN_APPROVAL_MIN=3 ' "$BP" && ok "L3f 기준값은 스크립트 상수 한 곳(3)" || no "L3f"

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

# ── D 문서 잠금 ──
C="$PLUGIN/commands/basic.md"
has() { local f="$1" p; shift; for p in "$@"; do grep -qF -- "$p" "$f" || return 1; done; }
has "$C" 'disable-model-invocation: true' '/basic' && ok "D1 슬래시 전용 명령(모델 자동 호출 금지)" || no "D1"
has "$C" '**주 세션이 직접 구현**' '서브에이전트에게 구현을 맡기지 않는다' '**실패하는 테스트를 먼저**' '**관련 테스트만**' \
  && ok "D2 주 세션 직접 구현 · 테스트 먼저 · 관련 테스트만" || no "D2"
has "$C" '한 메시지에서 함께 보낸다' 'devfsd:spec-reviewer-ko' 'devfsd:code-reviewer-ko' 'security-scan.sh' '**PR 본문을 준비**' '재리뷰는 없다' \
  && ok "D3 스펙·코드 리뷰 + 보안 스캔 동시 1회 · 그동안 PR 본문 준비 · 재리뷰 없음" || no "D3"
has "$C" 'basic-path.sh start' 'basic-path.sh approve' 'basic-path.sh seal' 'run-verification.sh <FID>' '/verify PASS' '우회하지 않고' \
  && ok "D4 start → approve → seal → 검증 러너 → 진행 기록 · 훅 우회 금지" || no "D4"
has "$C" '인증·권한 변경 · DB 스키마 변경 · 데이터 삭제·이관 · 기존 API 응답 형태 변경 · 되돌릴 수 없는 외부 작업' '**애매하면 무거운 쪽**' '종료 코드 3' \
  && ok "D5 풀 신호 5종 · 애매하면 무거운 쪽 · 승격(rc 3)" || no "D5"
has "$C" '갈래를 바꾸지 않고 **설계 확인 범위만**' 'DESIGN: none' 'DESIGN: update' 'DESIGN: approve' \
  && ok "D6 화면 변경량은 설계 확인 범위만 정한다(3단계)" || no "D6"
has "$C" '**자연어로 이 경로를 추론**' '**아직 재지 않았다**' '미실행 게이트' && ok "D7 자연어 추론 금지 · 미측정 고지 · 미실행 게이트 표기" || no "D7"
grep -qF '(`/basic` 도 같다)' "$PLUGIN/skills/using-specops-ko/SKILL.md" && grep -qF '넷 다 슬래시 전용' "$PLUGIN/skills/using-specops-ko/SKILL.md" \
  && ok "D8 메타 skill: /basic 도 자연어로 추론하지 않는다" || no "D8"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
