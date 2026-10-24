#!/usr/bin/env bash
# 단일 검증 상태 머신 — NOT_RUN/PASS/PARTIAL/FAIL/WAIVED + 계산형 STALE
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
STATE="$PLUGIN/scripts/_internal/verification-state.sh"

TD=$(mktemp -d) || exit 1
trap 'rm -rf "$TD"' EXIT
git -C "$TD" init -q
printf 'base\n' > "$TD/app.sh"
git -C "$TD" add app.sh
git -C "$TD" -c user.name=test -c user.email=test@example.com commit -qm init
mkdir -p "$TD/.specops/20260803-state"

# 미실행은 빈 문자열이 아니라 명시적 NOT_RUN이다.
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "NOT_RUN" ] && ok "S1 상태 부재 → NOT_RUN" || nope "S1" "out=$out"

# PASS 기록 직후 현재 소스와 일치한다.
(cd "$TD" && bash "$STATE" record 20260803-state PASS --executed 2 --skipped 0 --failed 0 --duration-ms 12)
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "PASS" ] && ok "S2 PASS 기록·조회" || nope "S2" "out=$out"

# 검증 뒤 코드 변경은 저장 상태를 덮지 않고 조회 시 STALE로 계산한다.
printf 'changed\n' >> "$TD/app.sh"
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "STALE" ] && ok "S3 코드 변경 후 PASS → STALE" || nope "S3" "out=$out"
git -C "$TD" restore app.sh

# 비-PASS 상태는 정규 상태 그대로 보존한다.
for verdict in PARTIAL FAIL NOT_RUN; do
  (cd "$TD" && bash "$STATE" record 20260803-state "$verdict")
  out=$(cd "$TD" && bash "$STATE" current 20260803-state)
  [ "$out" = "$verdict" ] && ok "S4 $verdict 보존" || nope "S4 $verdict" "out=$out"
done

# WAIVED는 승인자·사유·만료가 모두 있어야 한다.
if (cd "$TD" && bash "$STATE" record 20260803-state WAIVED >/dev/null 2>&1); then
  nope "S4 waiver" "승인 메타데이터 없는 WAIVED가 수락됨"
else
  ok "S4 승인 메타데이터 없는 WAIVED 거부"
fi
waiver_recorded=0
# ★ 만료일은 **상대 날짜**로 만든다. 미래 날짜를 하드코딩하면 그 시각이 지나는 순간
#   WAIVED 가 NOT_RUN 으로 계산돼 스위트가 스스로 터진다 — 2026-08-10 실발화:
#   "2026-08-10T00:00:00Z" 가 자정에 만료돼 본 스위트와 test-verdict-board 가 동시에 FAIL 했다.
#   (프로덕션은 정상 — verification-state.sh 가 조회 시점에 만료를 계산하는 게 설계다.)
_future=$(date -u -v+1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+1 day" +%Y-%m-%dT%H:%M:%SZ)
(cd "$TD" && bash "$STATE" record 20260803-state WAIVED \
  --waiver-reason "외부 시스템 점검" --waiver-approved-by "owner@example.com" \
  --waiver-expires-at "$_future") && waiver_recorded=1
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
if [ "$waiver_recorded" -eq 1 ] && [ "$out" = "WAIVED" ] \
   && jq -e '.waiver.reason != "" and .waiver.approved_by != "" and .waiver.expires_at != ""' \
    "$TD/.specops/20260803-state/verification-state.json" >/dev/null; then
  ok "S4 승인된 WAIVED 보존"
else
  nope "S4 waiver" "out=$out"
fi

# S5b WAIVED 필드 **길이 상한** — reason 200 · approved_by 120 (verification-state.sh:169)
# ★ 종전엔 양성 경로(정상 길이)만 돌아서, 상한 검사의 `&&` 를 끊는 변이가 살아남았다.
#   "메타데이터 부재 거부"(S4)와는 다른 분기다 — 값은 있는데 **너무 긴** 경우를 본다.
_long_reason=$(printf 'x%.0s' $(seq 1 201))
if (cd "$TD" && bash "$STATE" record 20260803-state WAIVED \
      --waiver-reason "$_long_reason" --waiver-approved-by "owner@example.com" \
      --waiver-expires-at "$_future" >/dev/null 2>&1); then
  nope "S5b 과길이 waiver-reason 거부" "201자 reason 이 수락됨"
else
  ok "S5b 과길이 waiver-reason 거부"
fi
_long_by=$(printf 'y%.0s' $(seq 1 121))
if (cd "$TD" && bash "$STATE" record 20260803-state WAIVED \
      --waiver-reason "정상 사유" --waiver-approved-by "$_long_by" \
      --waiver-expires-at "$_future" >/dev/null 2>&1); then
  nope "S5c 과길이 waiver-approved-by 거부" "121자 approved_by 가 수락됨"
else
  ok "S5c 과길이 waiver-approved-by 거부"
fi

# 허용 상태 외 문자열은 기록할 수 없다.
if (cd "$TD" && bash "$STATE" record 20260803-state SKIP >/dev/null 2>&1); then
  nope "S5" "잘못된 SKIP 상태가 수락됨"
else
  ok "S5 허용하지 않은 상태 거부"
fi

# 기존 FID는 evidence stamp를 읽어 하위 호환한다.
rm -f "$TD/.specops/20260803-state/verification-state.json"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$TD/.specops/20260803-state/evidence.md"
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "PASS" ] && ok "S6 legacy evidence PASS 호환" || nope "S6" "out=$out"

# 만료된 WAIVED는 저장값을 덮지 않고 조회 시 NOT_RUN으로 계산한다.
(cd "$TD" && bash "$STATE" record 20260803-state WAIVED \
  --waiver-reason "일시 예외" --waiver-approved-by "owner@example.com" \
  --waiver-expires-at "2020-01-01T00:00:00Z")
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "NOT_RUN" ] && ok "S7 만료 WAIVED → NOT_RUN" || nope "S7" "out=$out"
stored=$(jq -r '.verdict' "$TD/.specops/20260803-state/verification-state.json")
[ "$stored" = "WAIVED" ] && ok "S7b 저장 verdict는 WAIVED 유지" || nope "S7b" "stored=$stored"

# D-1: 검증된 내용의 순수 커밋은 STALE이 아니다 (false-block → BYPASS 방지).
printf 'verified\n' >> "$TD/app.sh"
(cd "$TD" && bash "$STATE" record 20260803-state PASS)
git -C "$TD" add app.sh
git -C "$TD" -c user.name=test -c user.email=test@example.com commit -qm "verified content"
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "PASS" ] && ok "S8 커밋만으로는 STALE 아님" || nope "S8" "out=$out"
git -C "$TD" -c user.name=test -c user.email=test@example.com commit --allow-empty -qm empty
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "PASS" ] && ok "S8b 빈 커밋도 STALE 아님" || nope "S8b" "out=$out"

# 커밋 후 새 편집은 STALE이다.
printf 'after-commit\n' >> "$TD/app.sh"
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "STALE" ] && ok "S9 커밋 후 새 편집 → STALE" || nope "S9" "out=$out"
git -C "$TD" restore app.sh

# source 호출 시 전역 fid 오염이 경로를 바꾸지 않는다 (SC2318).
source "$STATE"
fid="20260803-polluted"
out=$(cd "$TD" && vs::current 20260803-state)
[ "$out" = "PASS" ] && ok "S10 source 호출 시 fid 오염 무영향" || nope "S10" "out=$out"

# git 없는 디렉토리는 NO_GIT로 STALE이 발생하지 않는다.
NG=$(mktemp -d) || exit 1
mkdir -p "$NG/.specops/20260803-nogit"
(cd "$NG" && SPECOPS_ROOT=.specops bash "$STATE" record 20260803-nogit PASS)
out=$(cd "$NG" && SPECOPS_ROOT=.specops bash "$STATE" current 20260803-nogit)
[ "$out" = "PASS" ] && ok "S11 NO_GIT → STALE 미발생" || nope "S11" "out=$out"
rm -rf "$NG"

# ── 파일 클래스 구분 (20260912-verify-stale-docs-scope) ──────────────────────
# 문서 전용 변경은 verify 판정을 무효화하지 않는다. 런타임 .md 는 종전대로 무효화한다.
# ★ 양성 대조군을 **쌍으로** 둔다 — 한쪽만 두면 분류기를 "전부 문서" 또는 "전부 코드" 로
#   비워도 통과한다(공허 통과).
mkdir -p "$TD/skills/foo" "$TD/.claude-plugin"
printf '{"name":"x"}\n' > "$TD/.claude-plugin/plugin.json"
printf 'doc\n' > "$TD/CHANGELOG.md"
printf 'body\n' > "$TD/skills/foo/SKILL.md"
git -C "$TD" add -A
git -C "$TD" -c user.name=test -c user.email=test@example.com commit -qm cls
(cd "$TD" && bash "$STATE" record 20260803-state PASS)

# S12 문서 전용 변경 → PASS 유지 (AC-1)
printf 'doc changed\n' > "$TD/CHANGELOG.md"
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "PASS" ] && ok "S12 문서 전용 변경 → PASS 유지" || nope "S12" "out=$out"
printf 'doc\n' > "$TD/CHANGELOG.md"

# S13 런타임 SKILL.md 변경 → STALE (AC-2 · 양성 대조)
printf 'body changed\n' > "$TD/skills/foo/SKILL.md"
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "STALE" ] && ok "S13 런타임 SKILL.md 변경 → STALE 유지" || nope "S13" "out=$out"
printf 'body\n' > "$TD/skills/foo/SKILL.md"

# S14 nondoc_hash 부재(구버전 기록) → 종전 전체 지문 비교 (AC-5 · fail-safe 방향)
jq 'del(.nondoc_hash)' "$TD/.specops/20260803-state/verification-state.json" > "$TD/vs.tmp"
mv "$TD/vs.tmp" "$TD/.specops/20260803-state/verification-state.json"
printf 'doc changed again\n' > "$TD/CHANGELOG.md"
out=$(cd "$TD" && bash "$STATE" current 20260803-state)
[ "$out" = "STALE" ] && ok "S14 구버전 기록 → 종전 동작(fail-safe)" || nope "S14" "out=$out"
printf 'doc\n' > "$TD/CHANGELOG.md"

# ── S15 지문의 cwd 무관성 (Phase C 재판정 I-3) ───────────────────────────────
# 왜 함수 레벨인가: 소비자 4곳이 전부 **source 후 함수 직접 호출**이다 —
#   run-all.sh:29 · .githooks/pre-push:54 · record-task-receipt.sh:61 · check-task-receipt.sh:56.
#   앞 둘은 루트에서 돌지만 **receipt 둘은 사용자 cwd 에서 돈다** — 서브디렉터리에서 receipt 를
#   기록·조회하면 지문이 갈려 가짜 `tree stale` 이 난다. 도달 가능한 경로다(이론 아님).
#   (vs::current CLI 는 state 파일을 cwd 상대로 찾으므로 그 층에서는 재현되지 않는다.)
# ★ 양방향이어야 한다 — ①만 두면 함수가 **상수를 반환해도** 통과한다.
#   실제로 그 구멍으로 결함이 한 번 빠져나갔다: read-tree·add 만 루트에 앵커하고
#   `ls-files` 를 빠뜨려 열거가 cwd 하위로 잘렸는데, 회귀가 없어 스위트가 전건 통과했다.
mkdir -p "$TD/sub/deep"
printf 'x\n' > "$TD/code.sh"
printf 'y\n' > "$TD/sub/deep/inner.sh"
git -C "$TD" add -A
git -C "$TD" -c user.name=test -c user.email=test@example.com commit -qm anchor

_nd() { (cd "$1" && bash -c ". \"$STATE\"; vs::nondoc_fingerprint"); }
_root0=$(_nd "$TD")
_sub0=$(_nd "$TD/sub/deep")
if [ -n "$_root0" ] && [ "$_root0" != "NO_GIT" ] && [ "$_root0" = "$_sub0" ]; then
  ok "S15.a 비문서 지문이 cwd 와 무관 (루트 == 서브디렉터리)"
else
  nope "S15.a 지문 cwd 무관" "root=$_root0 sub=$_sub0"
fi

# S15.b 양성 대조 — 루트 코드 변경이 **서브디렉터리 조회에서도** 보여야 한다.
printf 'x changed\n' > "$TD/code.sh"
_sub1=$(_nd "$TD/sub/deep")
if [ -n "$_sub1" ] && [ "$_sub1" != "$_sub0" ]; then
  ok "S15.b 루트 코드 변경이 서브디렉터리 조회에서 보인다 (양성 대조)"
else
  nope "S15.b 바깥 변경 가시성" "sub0=$_sub0 sub1=$_sub1"
fi
printf 'x\n' > "$TD/code.sh"

# S15.c 음성 대조 — 문서 변경은 서브디렉터리 조회에서도 지문을 바꾸지 않는다 (AC-1 과 같은 의미).
# ★ 문서 픽스처를 **서브디렉터리 안**에 둔다. 루트 CHANGELOG.md 를 쓰면 cwd 절단 변이에서는
#   그 파일이 애초에 안 보여 **자명하게** 통과해 음성 대조가 공허해진다(chain 코드리뷰 M-3).
printf 'doc\n' > "$TD/sub/deep/note.md"
git -C "$TD" add -A
git -C "$TD" -c user.name=test -c user.email=test@example.com commit -qm subdoc
_sub0=$(_nd "$TD/sub/deep")
printf 'doc changed in sub view\n' > "$TD/sub/deep/note.md"
_sub2=$(_nd "$TD/sub/deep")
if [ "$_sub2" = "$_sub0" ]; then
  ok "S15.c 서브디렉터리 내부 문서 변경도 지문 불변"
else
  nope "S15.c 서브 내부 문서 변경 불변" "sub0=$_sub0 sub2=$_sub2"
fi
printf 'doc\n' > "$TD/sub/deep/note.md"

# ── S15.d 는 두지 않는다 (의도적 부재 — chain 코드리뷰 I-1) ───────────────────
# exclude pathspec(`:(exclude,glob,top).specops/**`)이 무효였던 적이 있다. 그때도 `fc::is_doc` 의
#   `^\.specops/` 가 가려 준 덕에 **지문은 불변이었고 아무 테스트도 실패하지 않았다**.
# "`.specops` 미추적 파일 추가 → 지문 불변" 형태의 회귀를 써 보았으나, 되돌려-관찰에서
#   pathspec 을 무효형으로 되돌려도 **28/28 전건 PASS** 했다 — pathspec 과 무관하게 항상 참인
#   **공허한 테스트**다. 공허한 테스트는 거짓 안전을 주므로 남기지 않는다.
#   (같은 병을 바로 위 S15.c 가 M-3 로 지적받았다: 자명하게 통과하는 음성 대조.)
# 이 층을 잠그려면 `vs::nondoc_fingerprint` 에서 **인덱스 구성**을 분리해 관측 가능하게 만들어야 한다.
#   함수가 해시만 반환하는 한 pathspec 층은 블랙박스다 — 그 리팩터는 이 FID 범위 밖이다.

# ── S16 비ASCII 경로 (chain 코드리뷰 M-2 / core.quotePath) ────────────────────
# `ls-files` 는 기본적으로 비ASCII 를 `"\355\225\234..."` 로 **인용**한다. 인용된 이름은 끝이 `"` 라
#   `*.md` 매칭이 깨져 **문서가 코드로 분류**된다 — 그러면 문서 한 줄이 다시 커밋을 막는다.
#   `-c core.quotePath=false` 가 그걸 막는데, 잠그는 회귀가 없으면 조용히 되돌아간다.
printf 'k\n' > "$TD/한글문서.md"
printf 'k\n' > "$TD/한글코드.sh"
git -C "$TD" add -A
git -C "$TD" -c user.name=test -c user.email=test@example.com commit -qm nonascii
_na0=$(_nd "$TD")

printf 'k changed\n' > "$TD/한글문서.md"
_na_doc=$(_nd "$TD")
if [ "$_na_doc" = "$_na0" ]; then
  ok "S16.a 비ASCII 문서 변경 → 지문 불변"
else
  nope "S16.a 비ASCII 문서 변경 불변" "before=$_na0 after=$_na_doc"
fi
printf 'k\n' > "$TD/한글문서.md"

# S16.b 양성 대조 — 비ASCII **코드** 변경은 보여야 한다. 없으면 "전부 불변" 으로도 S16.a 가 통과한다.
printf 'k changed\n' > "$TD/한글코드.sh"
_na_code=$(_nd "$TD")
if [ "$_na_code" != "$_na0" ]; then
  ok "S16.b 비ASCII 코드 변경 → 지문 변함 (양성 대조)"
else
  nope "S16.b 비ASCII 코드 변경 가시" "before=$_na0 after=$_na_code"
fi
printf 'k\n' > "$TD/한글코드.sh"

# ── S17 full-suite-fresh.sh (20261005-dedupe-test-runs) ─────────────────
# pre-push 와 verify 단계가 공유하는 신선도 판정. 생략(FRESH)은 오직 지문 일치 한 경로뿐이고
# 그 밖 전부가 STALE(재실행)이어야 한다 — 양성 1 + 음성 다수 쌍으로 잠근다.
FRESH="$PLUGIN/scripts/_internal/full-suite-fresh.sh"
TF=$(mktemp -d) || exit 1
_NL=$(mktemp -d) || exit 1
trap 'rm -rf "$TD" "$TF" "$_NL"' EXIT
git -C "$TF" init -q
printf 'base\n' > "$TF/app.sh"
git -C "$TF" add app.sh
git -C "$TF" -c user.name=test -c user.email=test@example.com commit -qm init
mkdir -p "$TF/.specops"
MK="$TF/.specops/.full-suite-pass"
# env -u 로 호출 환경의 SPECOPS_FORCE_FULL 을 지운다 — 값이 새면 FRESH 케이스가 공허하게 STALE 이 된다.
_fr() { ( cd "$TF" && env -u SPECOPS_FORCE_FULL "$@" bash "$FRESH" ); }
_fr_case() { # $1=id $2=설명 $3=기대 rc $4=stdout 정규식 $5...=추가 env
  local _id="$1" _d="$2" _rc="$3" _re="$4" _out _got; shift 4
  _out=$(_fr "$@"); _got=$?
  if [ "$_got" = "$_rc" ] && printf '%s' "$_out" | grep -qE "$_re"; then
    ok "$_id $_d"
  else
    nope "$_id $_d" "rc=$_got out=$_out"
  fi
}

_fp=$(_nd "$TF")
printf '%s\n' "$_fp" > "$MK"
_fr_case S17.a "마커 == 지문 → FRESH (rc 0 · fp 앞 12자)" 0 "^full-suite FRESH \(fp=${_fp:0:12}\)$"

rm -f "$MK"
_fr_case S17.b "마커 부재 → STALE" 1 "^full-suite STALE"
: > "$MK"
_fr_case S17.c "빈 마커 → STALE" 1 "^full-suite STALE"
printf 'not-a-tree-hash\n' > "$MK"
_fr_case S17.d "지문 불일치 → STALE" 1 "^full-suite STALE"

printf '%s\n' "$_fp" > "$MK"
printf 'changed\n' >> "$TF/app.sh"
_fr_case S17.e "비문서 변경 → STALE" 1 "^full-suite STALE"
git -C "$TF" restore app.sh
printf 'doc\n' > "$TF/NOTES.md"
_fr_case S17.f "문서 전용 변경 → 여전히 FRESH (양성 대조)" 0 "^full-suite FRESH"
rm -f "$TF/NOTES.md"

# 지문 산출 불가(NO_GIT) 는 마커가 같은 문자열이어도 생략 근거가 될 수 없다
printf 'NO_GIT\n' > "$MK"
_fr_case S17.g "지문 NO_GIT + 마커 NO_GIT → STALE" 1 "^full-suite STALE" TMPDIR=/nonexistent/zz
printf '%s\n' "$_fp" > "$MK"
_fr_case S17.g2 "지문 NO_GIT(마커는 정상 지문) → STALE" 1 "^full-suite STALE" TMPDIR=/nonexistent/zz

# SPECOPS_FORCE_FULL 은 값 무관 — 비어있지 않으면 강제 재실행 (=0 포함)
_fr_case S17.h "FORCE_FULL=1 → STALE" 1 "^full-suite STALE" SPECOPS_FORCE_FULL=1
_fr_case S17.h2 "FORCE_FULL=0 도 STALE (값 무관)" 1 "^full-suite STALE" SPECOPS_FORCE_FULL=0

# verification-state.sh 부재 — 헬퍼만 복사한 디렉터리에서 실행
cp "$FRESH" "$_NL/full-suite-fresh.sh"
_nl_out=$( cd "$TF" && env -u SPECOPS_FORCE_FULL bash "$_NL/full-suite-fresh.sh" ); _nl_rc=$?
if [ "$_nl_rc" = "1" ] && printf '%s' "$_nl_out" | grep -q '^full-suite STALE'; then
  ok "S17.i verification-state.sh 부재 → STALE"
else
  nope "S17.i verification-state.sh 부재 → STALE" "rc=$_nl_rc out=$_nl_out"
fi

# 읽기 권한 없음 (root 는 읽히므로 skip)
chmod 000 "$MK" 2>/dev/null
if [ "$(id -u)" = "0" ]; then
  skip "S17.j 마커 읽기 불가 → STALE (root 는 읽힌다)"
else
  _fr_case S17.j "마커 읽기 불가 → STALE" 1 "^full-suite STALE"
fi
chmod 644 "$MK" 2>/dev/null
# ── S19 --any-worktree (20261024-speed-release-fresh-task-record) ─────────
# 자기 마커가 없어도 같은 저장소의 다른 worktree 마커 **첫 줄이 지금 지문과 완전히 같을 때만** FRESH.
#   옵션 없는 호출은 종전 그대로(STALE) — pre-push·verify·거버넌스 소비가 바뀌지 않는다.
TW=$(mktemp -d) || exit 1
rmdir "$TW"
git -C "$TF" worktree add -q -b s19-wt "$TW" 2>/dev/null
mkdir -p "$TW/.specops"
WM="$TW/.specops/.full-suite-pass"
_fa() { ( cd "$TF" && env -u SPECOPS_FORCE_FULL "$@" bash "$FRESH" --any-worktree ); }
_fa_case() { # $1=id $2=설명 $3=기대 rc $4=stdout 정규식 $5...=추가 env
  local _id="$1" _d="$2" _rc="$3" _re="$4" _out _got; shift 4
  _out=$(_fa "$@"); _got=$?
  if [ "$_got" = "$_rc" ] && printf '%s' "$_out" | grep -qE "$_re"; then ok "$_id $_d"; else nope "$_id $_d" "rc=$_got out=$_out"; fi
}
rm -f "$MK"
printf '%s\n' "$_fp" > "$WM"
_twb=$(basename "$(cd "$TW" && pwd -P)")
_fa_case S19.a "자기 마커 부재 + 다른 worktree 마커 == 지문 → FRESH(worktree 경로)" 0 "^full-suite FRESH \(fp=${_fp:0:12}, worktree=.*${_twb}\)$"
_fr_case S19.b "같은 상황 · 옵션 없음 → STALE(종전 동작 · 사유 그대로)" 1 "^full-suite STALE \(마커 부재\)$"
printf 'not-a-tree-hash\n' > "$WM"
_fa_case S19.c "다른 worktree 마커 지문 불일치 → STALE" 1 "^full-suite STALE"
printf '%sX\n' "$_fp" > "$WM"
_fa_case S19.c2 "다른 worktree 마커 = 지문+접미 → STALE(포함 일치 금지)" 1 "^full-suite STALE"
printf '%s\n' "${_fp:0:12}" > "$WM"
_fa_case S19.c3 "다른 worktree 마커 = 지문 앞 12자 → STALE(접두 일치 금지)" 1 "^full-suite STALE"
printf 'junk\n%s\n' "$_fp" > "$WM"
_fa_case S19.c4 "다른 worktree 마커 둘째 줄만 지문 → STALE(첫 줄만 본다)" 1 "^full-suite STALE"
printf '%s\n' "$_fp" > "$WM"
_fa_case S19.d "FORCE_FULL 은 옵션이 있어도 STALE" 1 "^full-suite STALE" SPECOPS_FORCE_FULL=1
printf 'NO_GIT\n' > "$WM"
_fa_case S19.d2 "옵션 + 지문 NO_GIT + 다른 worktree 마커 NO_GIT → STALE" 1 "^full-suite STALE \(현재 지문 산출 불가\)$" TMPDIR=/nonexistent/zz
printf '%s\n' "$_fp" > "$WM"
printf 'changed\n' >> "$TF/app.sh"
_fa_case S19.e "지금 트리 비문서 변경 → 다른 worktree 마커가 옛 지문이라 STALE" 1 "^full-suite STALE"
git -C "$TF" restore app.sh
# 역방향 — linked worktree 셸에서 메인 worktree 마커를 본다(porcelain 첫 항목을 self 로 건너뛰지 않는다)
rm -f "$WM"; printf '%s\n' "$_fp" > "$MK"
_rv=$( cd "$TW" && env -u SPECOPS_FORCE_FULL bash "$FRESH" --any-worktree ); _rv_rc=$?
{ [ "$_rv_rc" = 0 ] && printf '%s' "$_rv" | grep -qE "^full-suite FRESH \(fp=${_fp:0:12}, worktree=.*$(basename "$(cd "$TF" && pwd -P)")\)$"; } \
  && ok "S19.f 역방향 — worktree 셸 + 메인 마커 == 지문 → FRESH(메인 경로)" || nope "S19.f" "rc=$_rv_rc out=$_rv"
_fa_case S19.g "자기 마커 FRESH 면 종전 출력 그대로(worktree 표기 없음)" 0 "^full-suite FRESH \(fp=${_fp:0:12}\)$"
_ar_out=$( cd "$TF" && env -u SPECOPS_FORCE_FULL bash "$FRESH" --bogus ); _ar_rc=$?
{ [ "$_ar_rc" = 1 ] && printf '%s' "$_ar_out" | grep -q '^full-suite STALE' && printf '%s' "$_ar_out" | grep -qF '알 수 없는 인자' && printf '%s' "$_ar_out" | grep -qF -- '--bogus'; } && ok "S19.h 알 수 없는 인자 → STALE" || nope "S19.h" "rc=$_ar_rc out=$_ar_out"
git -C "$TF" worktree remove --force "$TW" 2>/dev/null; rm -rf "$TW"

# 읽을 수 없는 untracked 파일 — git add -A 가 통째로 실패해 지문이 HEAD 로 퇴행한다(vs 공유 SoT 의 기존 한계).
# 이때 비문서 변경이 있어도 마커와 일치해 FRESH 가 되는 생략 방향 오판을 헬퍼가 따로 막는다.
printf '%s\n' "$_fp" > "$MK"
printf 'x\n' > "$TF/locked.dat"; chmod 000 "$TF/locked.dat" 2>/dev/null
printf 'changed\n' >> "$TF/app.sh"
if [ "$(id -u)" = "0" ]; then
  skip "S17.k 읽을 수 없는 untracked 파일 → STALE (root 는 읽힌다)"
else
  _fr_case S17.k "읽을 수 없는 untracked 파일 → STALE (지문 퇴행 방어)" 1 "^full-suite STALE"
fi
chmod 644 "$TF/locked.dat" 2>/dev/null; rm -f "$TF/locked.dat"
git -C "$TF" restore app.sh

# ── S18 지문 계산 실패 fail-closed — UNHASHABLE (20261005-fingerprint-add-failclosed) ──
# 읽을 수 없는 파일이 있으면 임시 인덱스 git add -A 가 fatal(rc 128)로 실패해 지문이 HEAD 로 퇴행했다.
# ★ 이 repo 처럼 .specops 가 gitignore 인 repo 는 정상 상태에서도 같은 명령이 rc 1 을 낸다 — rc 1 은 정상이다.
_chmod_inert() { local f; f=$(mktemp) || return 0; chmod 000 "$f"; if [ -r "$f" ]; then rm -f "$f"; return 0; fi; rm -f "$f"; return 1; }   # root·ACL·비-POSIX FS 에서는 chmod 000 이 파일을 막지 못한다
TG=$(mktemp -d) || exit 1
trap 'rm -rf "$TD" "$TF" "$_NL" "$TG"' EXIT
git -C "$TG" init -q
printf '.specops/\n' > "$TG/.gitignore"
printf 'a\n' > "$TG/app.sh"
printf 'k\n' > "$TG/locked.dat"
git -C "$TG" add -A
git -C "$TG" -c user.name=test -c user.email=test@example.com commit -qm init
mkdir -p "$TG/.specops/20261005-probe"
_g_ws() { (cd "$TG" && bash -c ". \"$STATE\"; vs::workspace_fingerprint"); }
_g_nd() { (cd "$TG" && bash -c ". \"$STATE\"; vs::nondoc_fingerprint"); }
_g_vs() { (cd "$TG" && SPECOPS_ROOT=.specops bash "$STATE" "$@"); }
_g_hex() { printf '%s' "$1" | grep -qE '^[0-9a-f]{40,64}$'; }

# S18.a 정상 상태 — .specops ignore 로 add 가 rc 1 을 내도 정상 지문이다 (rc 1 허용 분기의 양성 대조)
_g_rc1=$( cd "$TG" && idx=$(mktemp) && GIT_INDEX_FILE="$idx" git read-tree HEAD \
  && GIT_INDEX_FILE="$idx" git add -A -- . ':(exclude).specops' >/dev/null 2>&1; echo $?; rm -f "$idx" )
if [ "$_g_rc1" = "1" ]; then
  if _g_hex "$(_g_ws)" && _g_hex "$(_g_nd)"; then
    ok "S18.a .specops ignore(add rc 1) 에서도 정상 지문 (두 함수)"
  else
    nope "S18.a .specops ignore(add rc 1) 에서도 정상 지문" "ws=$(_g_ws) nd=$(_g_nd)"
  fi
else
  skip "S18.a 전제 불성립 — 이 git 은 .specops ignore 에서 add rc=$_g_rc1 (기대 1)"
fi

# S18.b·c 읽을 수 없는 tracked / untracked 파일 → 두 함수 모두 정확히 UNHASHABLE (root 는 읽히므로 skip)
if _chmod_inert; then
  skip "S18.b~g 읽을 수 없는 파일 — chmod 000 이 파일을 막지 못한다(root·ACL 등)"
else
  chmod 000 "$TG/locked.dat"; printf 'chg\n' >> "$TG/app.sh"
  [ "$(_g_ws)" = "UNHASHABLE" ] && [ "$(_g_nd)" = "UNHASHABLE" ] \
    && ok "S18.b 읽을 수 없는 tracked 파일 → UNHASHABLE (두 함수)" \
    || nope "S18.b 읽을 수 없는 tracked 파일 → UNHASHABLE" "ws=$(_g_ws) nd=$(_g_nd)"
  chmod 644 "$TG/locked.dat"; git -C "$TG" checkout -q -- app.sh
  printf 'z\n' > "$TG/un.txt"; chmod 000 "$TG/un.txt"
  [ "$(_g_ws)" = "UNHASHABLE" ] && [ "$(_g_nd)" = "UNHASHABLE" ] \
    && ok "S18.c 읽을 수 없는 untracked 파일 → UNHASHABLE (두 함수)" \
    || nope "S18.c 읽을 수 없는 untracked 파일 → UNHASHABLE" "ws=$(_g_ws) nd=$(_g_nd)"
  chmod 644 "$TG/un.txt"; rm -f "$TG/un.txt"

  # S18.d vs::current — 정상 PASS 기록 뒤 읽을 수 없는 파일 + 변경 → STALE (종전: PASS 가 샜다)
  _g_vs record 20261005-probe PASS --executed 1 >/dev/null 2>&1
  [ "$(_g_vs current 20261005-probe)" = "PASS" ] || nope "S18.d-pre" "픽스처가 PASS 가 아니다"
  chmod 000 "$TG/locked.dat"; printf 'chg\n' >> "$TG/app.sh"
  [ "$(_g_vs current 20261005-probe)" = "STALE" ] \
    && ok "S18.d PASS 뒤 읽을 수 없는 파일 + 변경 → STALE" \
    || nope "S18.d PASS 뒤 읽을 수 없는 파일 + 변경 → STALE" "current=$(_g_vs current 20261005-probe)"

  # S18.e 읽을 수 없는 상태에서 기록 → UNHASHABLE 기록 + stderr 경고, 두 값이 같아도 STALE, 파일이 읽혀도 STALE
  _g_err=$( _g_vs record 20261005-probe PASS --executed 1 2>&1 >/dev/null )
  [ "$(jq -r .nondoc_hash "$TG/.specops/20261005-probe/verification-state.json")" = "UNHASHABLE" ] \
    && ok "S18.e1 읽을 수 없는 상태의 기록 → nondoc_hash UNHASHABLE" \
    || nope "S18.e1 읽을 수 없는 상태의 기록 → nondoc_hash UNHASHABLE"
  printf '%s' "$_g_err" | grep -q 'UNHASHABLE' \
    && ok "S18.e2 기록 시 stderr 경고" || nope "S18.e2 기록 시 stderr 경고" "stderr=$_g_err"
  [ "$(_g_vs current 20261005-probe)" = "STALE" ] \
    && ok "S18.e3 기록·현재가 모두 UNHASHABLE 이어도 STALE" \
    || nope "S18.e3 기록·현재가 모두 UNHASHABLE 이어도 STALE" "current=$(_g_vs current 20261005-probe)"
  chmod 644 "$TG/locked.dat"
  [ "$(_g_vs current 20261005-probe)" = "STALE" ] \
    && ok "S18.e4 파일이 다시 읽혀도 UNHASHABLE 기록은 STALE (재검증 필요)" \
    || nope "S18.e4 파일이 다시 읽혀도 UNHASHABLE 기록은 STALE" "current=$(_g_vs current 20261005-probe)"
  git -C "$TG" checkout -q -- app.sh
fi

# S18.f NO_GIT 의미 불변 — git 저장소가 아니면 여전히 NO_GIT 이고 PASS 가 STALE 로 뒤집히지 않는다 (S11 과 대칭)
_g_nogit=$(mktemp -d)
[ "$(cd "$_g_nogit" && bash -c ". \"$STATE\"; vs::nondoc_fingerprint")" = "NO_GIT" ] \
  && ok "S18.f git 아님 → 여전히 NO_GIT (UNHASHABLE 과 구분)" \
  || nope "S18.f git 아님 → 여전히 NO_GIT"
rm -rf "$_g_nogit"

# S18.g 신선도 헬퍼 — 읽을 수 없는 tracked 파일이면 HEAD 지문 마커와 일치해도 STALE
#   (종전: tracked 경로는 헬퍼의 untracked 방어를 지나쳐 HEAD 지문 마커와 일치해 FRESH 로 샜다)
if ! _chmod_inert; then
  mkdir -p "$TG/.specops"
  _g_head_fp=$(_g_nd)   # 읽을 수 있는 상태의 지문 = 정상 마커
  chmod 000 "$TG/locked.dat"; printf 'chg\n' >> "$TG/app.sh"
  printf '%s\n' "$_g_head_fp" > "$TG/.specops/.full-suite-pass"
  _g_o=$( cd "$TG" && env -u SPECOPS_FORCE_FULL bash "$FRESH" ); _g_r=$?
  [ "$_g_r" = "1" ] && printf '%s' "$_g_o" | grep -q '^full-suite STALE' \
    && ok "S18.g 읽을 수 없는 tracked 파일 + 정상 마커 → STALE" \
    || nope "S18.g 읽을 수 없는 tracked 파일 + 정상 마커 → STALE" "rc=$_g_r out=$_g_o"
  chmod 644 "$TG/locked.dat"; git -C "$TG" checkout -q -- app.sh
fi

# S18.h unborn HEAD(첫 커밋 전) — mktemp 가 만든 0바이트 인덱스를 git 이 손상으로 보아 add 가 fatal(rc 128)이 된다.
#   읽을 수 없는 파일 때문이 아니므로 UNHASHABLE 로 분류하면 안 된다(AC-R-1 — 새 repo 의 첫 커밋을 R-1 이 STALE 로 막는다).
#   종전 값(workspace NO_GIT·nondoc EMPTY — 퇴행 지문)을 유지한다: 이 케이스의 값은 고정하지 않고 UNHASHABLE 만 금지한다.
_g_ub=$(mktemp -d)
git -C "$_g_ub" init -q
printf 'a\n' > "$_g_ub/app.sh"
_g_ub_ws=$(cd "$_g_ub" && bash -c ". \"$STATE\"; vs::workspace_fingerprint")
_g_ub_nd=$(cd "$_g_ub" && bash -c ". \"$STATE\"; vs::nondoc_fingerprint")
[ -n "$_g_ub_ws" ] && [ "$_g_ub_ws" != "UNHASHABLE" ] && [ -n "$_g_ub_nd" ] && [ "$_g_ub_nd" != "UNHASHABLE" ] \
  && ok "S18.h unborn HEAD 는 UNHASHABLE 이 아니다 (ws=$_g_ub_ws nd=${_g_ub_nd:0:12})" \
  || nope "S18.h unborn HEAD 는 UNHASHABLE 이 아니다" "ws=$_g_ub_ws nd=$_g_ub_nd"
rm -rf "$_g_ub"

# S18.i add.ignoreErrors=true 설정이 있어도 읽을 수 없는 tracked 파일은 UNHASHABLE 이다
#   (설정이 켜지면 git add 가 실패 대신 rc 1 로 끝나 파일을 조용히 건너뛴다 — 그 파일의 변경이 지문에 안 보인다)
if ! _chmod_inert; then
  git -C "$TG" config add.ignoreErrors true
  chmod 000 "$TG/locked.dat"; printf 'chg\n' >> "$TG/app.sh"
  [ "$(_g_ws)" = "UNHASHABLE" ] && [ "$(_g_nd)" = "UNHASHABLE" ] \
    && ok "S18.i add.ignoreErrors=true 에서도 읽을 수 없는 tracked 파일 → UNHASHABLE" \
    || nope "S18.i add.ignoreErrors=true 에서도 UNHASHABLE" "ws=$(_g_ws) nd=$(_g_nd)"
  chmod 644 "$TG/locked.dat"; git -C "$TG" checkout -q -- app.sh; git -C "$TG" config --unset add.ignoreErrors
else
  skip "S18.i add.ignoreErrors — chmod 000 이 파일을 막지 못한다(root·ACL 등)"
fi

# S20 STALE 의 범위 — 차이가 추적하지 않는 파일뿐인가 (20261009)
#   R-1 훅이 묻는다: 검증 뒤 생긴 로그·캐시(.DS_Store·build.log)는 커밋에 실리지 않으므로 그것만으로 커밋을 막지 않는다.
#   `current` 의 답(STALE)은 그대로다 — 범위만 따로 답한다. 조금이라도 불확실하면 changed(막는 쪽)다.
_s20=$(mktemp -d)
( cd "$_s20" && git init -q && printf 'echo a\n' > app.sh && printf 'echo b\n' > lib.sh && git add app.sh lib.sh \
  && git -c user.name=t -c user.email=t@e.com commit -qm init && mkdir -p .specops sub ) >/dev/null 2>&1
_s20_cur() { ( cd "$_s20" && SPECOPS_ROOT=.specops bash "$STATE" current 20260101-s20 ); }
_s20_scope() { ( cd "$_s20/${1:-.}" && SPECOPS_ROOT="$_s20/.specops" bash "$STATE" stale-scope 20260101-s20 ); }
[ "$(_s20_scope)" = "changed" ] && ok "S20.a 상태 기록 없음 → changed" || nope "S20.a 상태 기록 없음 → changed" "$(_s20_scope)"
( cd "$_s20" && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 PASS --executed 1 --failed 0 ) >/dev/null 2>&1
printf 'log\n' > "$_s20/build.log"
[ "$(_s20_cur)" = "STALE" ] && [ "$(_s20_scope)" = "untracked-only" ] \
  && ok "S20.b 검증 뒤 untracked 파일만 생김 → current STALE · 범위 untracked-only" \
  || nope "S20.b untracked 파일만" "current=$(_s20_cur) scope=$(_s20_scope)"
[ "$(_s20_scope sub)" = "untracked-only" ] && ok "S20.b2 서브디렉터리에서 물어도 같은 답" || nope "S20.b2 서브디렉터리" "$(_s20_scope sub)"
printf 'echo CHANGED\n' > "$_s20/app.sh"
[ "$(_s20_scope)" = "changed" ] && ok "S20.c untracked + 추적 파일 수정 → changed" || nope "S20.c 추적 파일 수정" "$(_s20_scope)"
git -C "$_s20" checkout -q -- app.sh
git -C "$_s20" add build.log
[ "$(_s20_scope)" = "changed" ] && ok "S20.d 그 파일을 인덱스에 올림(staged 신규) → changed" || nope "S20.d staged 신규" "$(_s20_scope)"
git -C "$_s20" reset -q build.log; git -C "$_s20" add -N build.log
[ "$(_s20_scope)" = "changed" ] && ok "S20.e intent-to-add → changed" || nope "S20.e intent-to-add" "$(_s20_scope)"
git -C "$_s20" reset -q build.log
rm -f "$_s20/lib.sh"
[ "$(_s20_scope)" = "changed" ] && ok "S20.f 추적 파일 삭제(unstaged) → changed" || nope "S20.f 추적 파일 삭제" "$(_s20_scope)"
git -C "$_s20" checkout -q -- lib.sh
# 인덱스에 오른 것과 **같은 초에 같은 크기로** 고친 파일 — stat 만으로는 안 바뀐 것처럼 보인다. git 은 인덱스 파일의
#   mtime 으로 이 경우를 가려 내용을 다시 비교하는데, 인덱스 사본의 mtime 이 "지금" 이면 그 보호가 꺼진다.
#   세 동작(add·기록·수정)이 한 초 안에 끝난 회차만 판정한다(초 경계에 걸리면 다시 — 5회 안에 못 맞추면 SKIP).
_s20r=""
for _try in 1 2 3 4 5; do
  _t0=$(date +%s)
  printf 'echo v2\n' > "$_s20/app.sh"; git -C "$_s20" add app.sh
  ( cd "$_s20" && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 PASS --executed 1 --failed 0 ) >/dev/null 2>&1
  printf 'echo v3\n' > "$_s20/app.sh"
  [ "$(date +%s)" = "$_t0" ] && { _s20r=same; break; }
done
if [ "$_s20r" = same ]; then
  sleep 1.2
  [ "$(_s20_scope)" = "changed" ] && ok "S20.f1 같은 초·같은 크기 수정(인덱스 사본의 mtime 보존) → changed" || nope "S20.f1 racy 수정" "$(_s20_scope)"
else
  skip "S20.f1 — add·기록·수정을 한 초 안에 맞추지 못함(부하)"
fi
printf 'echo a\n' > "$_s20/app.sh"; git -C "$_s20" add app.sh
( cd "$_s20" && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 PASS --executed 1 --failed 0 ) >/dev/null 2>&1
# 인덱스에서 뺀 파일 — 커밋이 그 파일을 저장소에서 지운다. 임시 인덱스를 HEAD 에서 시작하면 이걸 못 본다.
git -C "$_s20" rm -q --cached lib.sh
[ "$(_s20_scope)" = "changed" ] && ok "S20.f2 git rm --cached(파일은 남고 인덱스에서 빠짐) → changed" || nope "S20.f2 git rm --cached" "$(_s20_scope)"
git -C "$_s20" reset -q HEAD -- lib.sh
git -C "$_s20" rm -q lib.sh
[ "$(_s20_scope)" = "changed" ] && ok "S20.f3 git rm(staged 삭제) → changed" || nope "S20.f3 git rm" "$(_s20_scope)"
git -C "$_s20" reset -q HEAD -- lib.sh; git -C "$_s20" checkout -q -- lib.sh
git -C "$_s20" mv lib.sh lib2.sh
[ "$(_s20_scope)" = "changed" ] && ok "S20.f4 git mv → changed" || nope "S20.f4 git mv" "$(_s20_scope)"
git -C "$_s20" mv lib2.sh lib.sh
chmod +x "$_s20/app.sh"
[ "$(_s20_scope)" = "changed" ] && ok "S20.f5 실행 권한만 바뀜 → changed" || nope "S20.f5 chmod +x" "$(_s20_scope)"
chmod -x "$_s20/app.sh"
[ "$(_s20_scope)" = "untracked-only" ] && ok "S20.g 되돌리면 다시 untracked-only (앞 단계가 상태를 남기지 않는다)" || nope "S20.g 복원" "$(_s20_scope)"
# 판정이 PASS 가 아닌 기록은 범위를 따지지 않는다 — 지문은 지금과 **같게** 만들어 둔다(달라서 changed 가 되면 이 판정을 보지 못한다)
rm -f "$_s20/build.log"
( cd "$_s20" && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 FAIL --executed 1 --failed 1 ) >/dev/null 2>&1
[ "$(_s20_scope)" = "changed" ] && ok "S20.h 기록이 FAIL → changed" || nope "S20.h 기록이 FAIL" "$(_s20_scope)"
# 기록 시점에 이미 untracked 파일이 있었어도 성립한다 — 그 파일이 바뀌거나 다른 untracked 가 생겨도 추적 파일은 그대로다
#   (검증 때부터 있던 로그에 덧붙는 것이 가장 흔한 형태다. 전체 지문과 비교하면 이 경우가 전부 changed 가 된다)
printf 'log\n' > "$_s20/build.log"
( cd "$_s20" && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 PASS --executed 1 --failed 0 ) >/dev/null 2>&1
printf 'more\n' >> "$_s20/build.log"; printf 'more\n' > "$_s20/other.log"
[ "$(_s20_cur)" = "STALE" ] && [ "$(_s20_scope)" = "untracked-only" ] \
  && ok "S20.i 기록 때부터 있던 untracked 가 바뀜 + 새 untracked → untracked-only" || nope "S20.i 기존 untracked 변경" "current=$(_s20_cur) scope=$(_s20_scope)"
printf 'echo CHANGED\n' > "$_s20/app.sh"
[ "$(_s20_scope)" = "changed" ] && ok "S20.i2 그 상태에서 추적 파일 수정 → changed" || nope "S20.i2" "$(_s20_scope)"
git -C "$_s20" checkout -q -- app.sh
# 추적 지문 필드가 없는 기록(구버전)은 범위를 답할 근거가 없다
jq 'del(.tracked_nondoc_hash)' "$_s20/.specops/20260101-s20/verification-state.json" > "$_s20/.specops/vs.tmp" \
  && mv "$_s20/.specops/vs.tmp" "$_s20/.specops/20260101-s20/verification-state.json"
[ "$(_s20_scope)" = "changed" ] && ok "S20.i3 추적 지문이 없는 기록(구버전) → changed" || nope "S20.i3 구버전 기록" "$(_s20_scope)"
( cd "$_s20" && SPECOPS_ROOT=.specops bash "$STATE" stale-scope 'bad fid' ) >/dev/null 2>&1 \
  && nope "S20.j 잘못된 FID → rc 1" "rc 0" || ok "S20.j 잘못된 FID → rc 1"
# 비교 근거가 없는 기록(퇴행 지문)은 "같다" 로 읽지 않는다 — 양쪽이 같은 퇴행값이어도 changed 다
_s20u=$(mktemp -d)   # unborn HEAD(첫 커밋 전): 실 인덱스 기반이라 여기서도 답이 성립한다(전체 지문은 이 구간에서 퇴행값이다)
( cd "$_s20u" && git init -q && printf 'echo a\n' > app.sh && git add app.sh && mkdir -p .specops \
  && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 PASS --executed 1 --failed 0 && printf 'log\n' > build.log ) >/dev/null 2>&1
_s20u_o=$( cd "$_s20u" && SPECOPS_ROOT=.specops bash "$STATE" stale-scope 20260101-s20 )
printf 'echo CHANGED\n' > "$_s20u/app.sh"
_s20u_o2=$( cd "$_s20u" && SPECOPS_ROOT=.specops bash "$STATE" stale-scope 20260101-s20 )
[ "$_s20u_o" = "untracked-only" ] && [ "$_s20u_o2" = "changed" ] \
  && ok "S20.k unborn HEAD — untracked 만 생김 → untracked-only · staged 파일 수정 → changed" || nope "S20.k unborn HEAD" "a=$_s20u_o b=$_s20u_o2"
# 첫 커밋 전이라도 지문 산출 실패는 실패다 — 전체 지문의 unborn 예외(퇴행값 허용)를 이 모드에 물려주지 않는다
if ! _chmod_inert; then
  ( cd "$_s20u" && git add app.sh && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 PASS --executed 1 --failed 0 ) >/dev/null 2>&1
  printf 'echo AGAIN\n' > "$_s20u/app.sh"; chmod 000 "$_s20u/app.sh"
  _s20u_o3=$( cd "$_s20u" && SPECOPS_ROOT=.specops bash "$STATE" stale-scope 20260101-s20 )
  chmod 644 "$_s20u/app.sh"
  [ "$_s20u_o3" = "changed" ] && ok "S20.k3 unborn HEAD + 고쳐졌는데 읽을 수 없는 파일 → changed" || nope "S20.k3 unborn + 읽기 실패" "$_s20u_o3"
else
  skip "S20.k3 — chmod 000 이 파일을 막지 못한다(root·ACL 등)"
fi
# 추적 중인 비문서 파일이 하나도 없는 저장소(문서만 추적) — 지문 EMPTY 는 퇴행값이 아니라 실제 값이다
_s20d=$(mktemp -d)
( cd "$_s20d" && git init -q && printf '# doc\n' > README.md && git add README.md && git -c user.name=t -c user.email=t@e.com commit -qm init \
  && mkdir -p .specops && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 PASS --executed 1 --failed 0 && printf 'echo x\n' > new.sh ) >/dev/null 2>&1
_s20d_o=$( cd "$_s20d" && SPECOPS_ROOT=.specops bash "$STATE" stale-scope 20260101-s20 )
git -C "$_s20d" add new.sh
_s20d_o2=$( cd "$_s20d" && SPECOPS_ROOT=.specops bash "$STATE" stale-scope 20260101-s20 )
[ "$_s20d_o" = "untracked-only" ] && [ "$_s20d_o2" = "changed" ] \
  && ok "S20.k2 문서만 추적하는 저장소 — untracked 코드 → untracked-only · 그 파일을 올리면 changed" || nope "S20.k2 문서만 추적" "a=$_s20d_o b=$_s20d_o2"
_s20n=$(mktemp -d)   # git 저장소가 아님: 조회 지문이 NO_GIT
mkdir -p "$_s20n/.specops/20260101-s20"
printf '{"schema_version":1,"fid":"20260101-s20","verdict":"PASS","nondoc_hash":"NO_GIT","tracked_nondoc_hash":"NO_GIT"}\n' > "$_s20n/.specops/20260101-s20/verification-state.json"
_s20n_o=$( cd "$_s20n" && GIT_CEILING_DIRECTORIES="$_s20n" SPECOPS_ROOT=.specops bash "$STATE" stale-scope 20260101-s20 )
[ "$_s20n_o" = "changed" ] && ok "S20.l 기록 지문 NO_GIT → changed" || nope "S20.l 기록 지문 NO_GIT" "$_s20n_o"
if ! _chmod_inert; then   # 고쳐졌는데 읽을 수 없는 추적 파일 — 지문을 낼 수 없다
  ( cd "$_s20" && git checkout -q -- . && rm -f other.log build.log && printf 'k\n' > locked.dat && git add locked.dat \
    && git -c user.name=t -c user.email=t@e.com commit -qm lock \
    && SPECOPS_ROOT=.specops bash "$STATE" record 20260101-s20 PASS --executed 1 --failed 0 ) >/dev/null 2>&1
  printf 'log\n' > "$_s20/build.log"
  _s20y_a=$(_s20_scope)
  # 내용을 바꾼 뒤 읽기를 막는다(권한만 바꾸면 git 은 인덱스의 stat 으로 "안 바뀜" 을 알아 읽지 않는다 — 그건 실제로 안 바뀐 것이다).
  #   지문을 못 내면 "달라지지 않았다" 가 아니라 changed 다 — 실패를 성공으로 치면 옛 내용이 임시 인덱스에 남아 기록과 같아진다.
  printf 'k2\n' > "$_s20/locked.dat"; chmod 000 "$_s20/locked.dat"
  _s20y_b=$(_s20_scope)
  # 기록 쪽이 UNHASHABLE 이면 조회 쪽도 UNHASHABLE 이어도 "같다" 가 아니다
  jq '.tracked_nondoc_hash = "UNHASHABLE"' "$_s20/.specops/20260101-s20/verification-state.json" > "$_s20/.specops/vs.tmp" \
    && mv "$_s20/.specops/vs.tmp" "$_s20/.specops/20260101-s20/verification-state.json"
  _s20x_o=$(_s20_scope)
  chmod 644 "$_s20/locked.dat"
  [ "$_s20y_a" = "untracked-only" ] && [ "$_s20y_b" = "changed" ] \
    && ok "S20.n 고쳐졌는데 읽을 수 없는 추적 파일 → changed (그 전엔 untracked-only)" \
    || nope "S20.n 조회 시 지문 산출 실패" "readable=$_s20y_a unreadable=$_s20y_b"
  [ "$_s20x_o" = "changed" ] && ok "S20.m 기록 지문 UNHASHABLE(조회도 UNHASHABLE) → changed" || nope "S20.m 기록 지문 UNHASHABLE" "$_s20x_o"
else
  skip "S20.m·n UNHASHABLE — chmod 000 이 파일을 막지 못한다(root·ACL 등)"
fi
rm -rf "$_s20" "$_s20u" "$_s20n" "$_s20d"

# ── S21 변이 생존 2건 (20261010-mutation-survivors-rest) ─────────────────────
# S21.a 지문 필드가 하나도 없는 PASS 기록은 STALE 이다 (20261010-hashless-pass-stale).
#   지금 트리와 같은지 확인할 수단이 없는 PASS 는 유효 PASS 가 아니다. record 는 지문을 항상 쓰므로 이 상태는 손으로 쓴
#   (또는 깨진) 기록에서만 나온다 — 종전에는 빈 값이 "비교 생략" 으로 흘러 그런 기록이 영영 STALE 이 되지 않았다
#   (하류 실측 88건 중 1건). 같은 기록을 stale-scope 는 이미 `changed` 로 읽었다(S20.i3) — 두 조회의 방향을 맞춘다.
_s21=$(mktemp -d) || exit 1
( cd "$_s21" && git init -q && printf 'echo x\n' > a.sh && git add a.sh \
    && git -c user.name=t -c user.email=t@e.com commit -qm init ) >/dev/null 2>&1
mkdir -p "$_s21/.specops/20261010-nohash"
_s21j="$_s21/.specops/20261010-nohash/verification-state.json"
printf '{"verdict":"PASS"}\n' > "$_s21j"
out=$(cd "$_s21" && bash "$STATE" current 20261010-nohash)
[ "$out" = "STALE" ] && ok "S21.a ★ 지문 필드 없는 PASS 기록 → STALE" || nope "S21.a" "out=$out"
# 빈 문자열로 적힌 지문도 같다 (필드는 있는데 값이 빈 경우)
printf '{"verdict":"PASS","nondoc_hash":"","tree_hash":""}\n' > "$_s21j"
out=$(cd "$_s21" && bash "$STATE" current 20261010-nohash)
[ "$out" = "STALE" ] && ok "S21.a1 빈 문자열 지문 → STALE" || nope "S21.a1" "out=$out"
# 두 조회가 같은 방향이다 — current 는 STALE, stale-scope 는 changed (막는 쪽)
out=$(cd "$_s21" && bash "$STATE" stale-scope 20261010-nohash)
[ "$out" = "changed" ] && ok "S21.a2 같은 기록의 stale-scope → changed (current 와 같은 방향)" || nope "S21.a2" "out=$out"
# PASS 가 아닌 판정은 지문이 없어도 그대로다 — 가드는 PASS 에만 걸린다
printf '{"verdict":"FAIL"}\n' > "$_s21j"
out=$(cd "$_s21" && bash "$STATE" current 20261010-nohash)
[ "$out" = "FAIL" ] && ok "S21.a3 지문 없는 FAIL 기록 → FAIL (PASS 한정)" || nope "S21.a3" "out=$out"
# 대조 — 지문이 있고 다르면 STALE, 같으면 PASS (구버전 기록: nondoc 없이 tree_hash 만)
printf '{"verdict":"PASS","tree_hash":"0000000000000000000000000000000000000000"}\n' > "$_s21j"
out=$(cd "$_s21" && bash "$STATE" current 20261010-nohash)
[ "$out" = "STALE" ] && ok "S21.a0 대조 — 다른 지문이 적힌 기록 → STALE" || nope "S21.a0" "out=$out"
_s21t=$( cd "$_s21" && . "$STATE" && vs::workspace_fingerprint )
printf '{"verdict":"PASS","tree_hash":"%s"}\n' "$_s21t" > "$_s21j"
out=$(cd "$_s21" && bash "$STATE" current 20261010-nohash)
[ "$out" = "PASS" ] && ok "S21.a4 대조 — tree_hash 만 있고 지금 트리와 같다 → PASS (구버전 기록은 그대로 읽힌다)" || nope "S21.a4" "out=$out tree=$_s21t"

# S21.c NO_GIT 으로 적힌 기록은 git 저장소 안에서도 STALE 을 만들지 않는다 — "비교 수단 없음" 은 "지문 없음" 과 다르다.
#   git 없이 검증한 프로젝트를 위한 면제다. 이 단언이 없으면 `[ != NO_GIT ] && [ != 현재 지문 ]` 의 결합을 풀어도 아무도 울지 않는다.
printf '{"verdict":"PASS","nondoc_hash":"NO_GIT","tree_hash":"NO_GIT"}\n' > "$_s21j"
out=$(cd "$_s21" && bash "$STATE" current 20261010-nohash)
[ "$out" = "PASS" ] && ok "S21.c NO_GIT 기록 → PASS (git 저장소 안에서도)" || nope "S21.c" "out=$out"

# S21.d git 이 없는 프로젝트 — 러너가 쓴 기록(NO_GIT)은 종전대로 PASS, 손으로 쓴 지문 없는 기록은 여기서도 STALE.
#   ★ GIT_CEILING_DIRECTORIES: 임시 디렉토리의 상위에 저장소가 있으면 git 이 그것을 찾아 "git 없음" 픽스처가 성립하지 않는다.
_s21n=$(mktemp -d) || exit 1
mkdir -p "$_s21n/.specops/20261010-nogit"
( cd "$_s21n" && GIT_CEILING_DIRECTORIES="$_s21n" bash "$STATE" record 20261010-nogit PASS --executed 1 --failed 0 ) >/dev/null 2>&1
_s21r=$(jq -r '.tree_hash' "$_s21n/.specops/20261010-nogit/verification-state.json" 2>/dev/null)
out=$(cd "$_s21n" && GIT_CEILING_DIRECTORIES="$_s21n" bash "$STATE" current 20261010-nogit)
[ "$_s21r" = "NO_GIT" ] && [ "$out" = "PASS" ] && ok "S21.d git 없는 프로젝트의 러너 기록(NO_GIT) → PASS" || nope "S21.d" "tree_hash=$_s21r out=$out"
printf '{"verdict":"PASS"}\n' > "$_s21n/.specops/20261010-nogit/verification-state.json"
out=$(cd "$_s21n" && GIT_CEILING_DIRECTORIES="$_s21n" bash "$STATE" current 20261010-nogit)
[ "$out" = "STALE" ] && ok "S21.d2 git 없는 프로젝트에서도 지문 없는 PASS 기록 → STALE" || nope "S21.d2" "out=$out"
rm -rf "$_s21n"

# S21.b WAIVED 필수 3필드는 **하나만 빠져도** 거부한다 — S4 는 "전부 부재" 만 봤다.
#   필수 3필드 결합(`[ -n reason ] && [ -n approved-by ] && …`)을 잠그는 것은 reason·approved-by 누락 두 조합이다.
#   expires-at 누락은 그 결합이 풀려도 바로 뒤 형식 검사(invalid waiver expiry)가 거부한다 — 계약 확인용으로 함께 둔다.
_s21f=$(date -u -v+1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+1 day" +%Y-%m-%dT%H:%M:%SZ)
_s21bad=""
( cd "$_s21" && bash "$STATE" record 20261010-w1 WAIVED --waiver-approved-by "o@e.com" --waiver-expires-at "$_s21f" ) >/dev/null 2>&1 && _s21bad="$_s21bad reason"
( cd "$_s21" && bash "$STATE" record 20261010-w2 WAIVED --waiver-reason "점검" --waiver-expires-at "$_s21f" ) >/dev/null 2>&1 && _s21bad="$_s21bad approved-by"
( cd "$_s21" && bash "$STATE" record 20261010-w3 WAIVED --waiver-reason "점검" --waiver-approved-by "o@e.com" ) >/dev/null 2>&1 && _s21bad="$_s21bad expires-at"
_s21n=$(ls "$_s21/.specops"/20261010-w*/verification-state.json 2>/dev/null | wc -l | tr -d ' ')
[ -z "$_s21bad" ] && [ "$_s21n" = "0" ] && ok "S21.b WAIVED 필드 하나만 빠져도 거부 (reason · approved-by · expires-at 각각) + 기록 없음" \
  || nope "S21.b" "수락된 누락 조합:${_s21bad:- 없음} · 기록 파일 ${_s21n}개"
# 대조 — 셋 다 있으면 수락한다 (거부가 인자 형식 탓이 아님)
( cd "$_s21" && bash "$STATE" record 20261010-w4 WAIVED --waiver-reason "점검" --waiver-approved-by "o@e.com" --waiver-expires-at "$_s21f" ) >/dev/null 2>&1 \
  && ok "S21.b0 대조 — 세 필드가 다 있으면 수락" || nope "S21.b0" "정상 WAIVED 가 거부됨"
rm -rf "$_s21"

finish
