#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
SH="$PLUGIN/scripts/doctor.sh"
unset CLAUDE_CODE_EFFORT_LEVEL   # 호스트 셸의 env 가 새 effort_env 행을 ⚠️ 로 만들어 기존 "전부 ✅" 단언을 환경 의존으로 깨지 않게 한다

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

_mkrepo() {  # $1=repo 경로 — git init + .specops 생성
  mkdir -p "$1/.specops"
  git -C "$1" init -q 2>/dev/null
  git -C "$1" config user.email t@t.io; git -C "$1" config user.name t
}
_plugin_shape() {  # $1=repo — 플러그인 repo 형상 부여 (처방 대상 실재)
  # doctor 의 관할 판정은 "처방(install-git-hooks.sh)이 이 repo 에서 실행 가능한가" 다.
  # 실물 installer 를 복사하지 않고 존재만 만든다 — 판정은 존재만 본다.
  mkdir -p "$1/scripts/_internal" "$1/.githooks"
  printf '#!/bin/sh\nexit 0\n' > "$1/scripts/_internal/install-git-hooks.sh"
}
_noop_hooks() {  # $1=repo — 실행가능 훅 2개 + hooksPath. **installer 없음**(= 하류 형상)
  mkdir -p "$1/.githooks"
  printf '#!/bin/sh\nexit 0\n' > "$1/.githooks/pre-commit"
  printf '#!/bin/sh\nexit 0\n' > "$1/.githooks/pre-push"
  chmod +x "$1/.githooks/pre-commit" "$1/.githooks/pre-push"
  git -C "$1" config core.hooksPath .githooks
}
_hooks_ok() {  # $1=repo — 2단 hook 완비 (플러그인 repo 형상 포함)
  # ★ 형상을 여기 내장한다 — 사용처가 7곳이라 호출부마다 한 줄씩 더하면 누락이 재발한다
  #   (실측: T11 누락 시 rows=8 oks=7 FAIL). 하류 no-op 픽스처는 _noop_hooks 를 쓴다.
  _plugin_shape "$1"
  _noop_hooks "$1"
}
_run() { _OUT=$(cd "$1" && SPECOPS_ROOT=".specops" bash "$SH" "${@:2}" 2>&1); _RC=$?; }

# T1 (AC-1): hooksPath 미설정 → git hook ⚠️ + 조치 명령
R="$TMP/r1"; _mkrepo "$R"; _plugin_shape "$R"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| git_hooks ' | grep -q '⚠️' \
  && printf '%s' "$_OUT" | grep -q 'install-git-hooks.sh' \
  && ok "T1 hook 미설치 → ⚠️ + 조치" || nope "T1" "out=$_OUT"

# T2 (AC-2): 2단 hook 완비 → ✅
R="$TMP/r2"; _mkrepo "$R"; _hooks_ok "$R"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| git_hooks ' | grep -q '✅' \
  && ok "T2 hook 완비 → ✅" || nope "T2" "out=$_OUT"

# T12 (AC-12): pre-push 만 누락 → ⚠️ + pre-push 지목
R="$TMP/r12"; _mkrepo "$R"; _hooks_ok "$R"; rm -f "$R/.githooks/pre-push"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| git_hooks ' | grep -q '⚠️' \
  && printf '%s' "$_OUT" | grep -q 'pre-push' \
  && ok "T12 pre-push 누락 검출" || nope "T12" "out=$_OUT"

# T-ds.a (AC-1): 하류 repo(처방 대상 부재) → ⚠️ + 부재를 기술 + install-git-hooks.sh 미처방
R="$TMP/rds1"; _mkrepo "$R"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| git_hooks ' | grep -q '⚠️' \
  && printf '%s' "$_OUT" | grep -q 'specops 2단 게이트 미설치' \
  && ! printf '%s' "$_OUT" | grep -q 'install-git-hooks.sh' \
  && ok "T-ds.a 하류 → ⚠️ + 부재 기술 + 죽은 처방 없음" || nope "T-ds.a" "out=$_OUT"

# T-ds.b (AC-2·AC-4): 하류 --json 계약 — status=warn · fix 빈 문자열 · 4키 유지
R="$TMP/rds2"; _mkrepo "$R"
_run "$R" --json
printf '%s' "$_OUT" | jq -e '(.checks[]|select(.id=="git_hooks")|.status)=="warn"
  and ((.checks[]|select(.id=="git_hooks")|.fix)=="")
  and ((.checks[]|select(.id=="git_hooks")|keys|sort)==["detail","fix","id","status"])' >/dev/null 2>&1 \
  && ok "T-ds.b 하류 JSON: warn · fix 빈 문자열 · 4키" || nope "T-ds.b" "out=$_OUT"

# T-ds.c (AC-R-2): 하류에 no-op 훅이 걸려 있어도 ✅ 로 보고하지 않는다
#   현 코드는 core.hooksPath=.githooks + 실행가능 훅 2개면 ✅ 였다. 그 훅이 자기면제 본문(exit 0)
#   이어도 마찬가지였다 — 즉 죽은 처방을 따라간 사용자가 **거짓 ✅** 를 받는 경로가 있었다.
R="$TMP/rds3"; _mkrepo "$R"; _noop_hooks "$R"   # .githooks + hooksPath 설정, installer 는 없음(=하류)
_run "$R"
! printf '%s' "$_OUT" | grep -E '^\| git_hooks ' | grep -q '✅' \
  && ok "T-ds.c 하류 no-op 훅 → ✅ 아님 (거짓 ✅ 경로 차단)" || nope "T-ds.c" "out=$_OUT"

# T-ds.e (AC-1): installer 는 있으나 `.githooks/` 가 없는 repo 도 하류다
#   관할 판정은 `! -f installer || ! -d .githooks` 라 **OR 의 두 피연산자**를 다 덮어야 한다.
#   T-ds.a/b/c 는 installer 부재 쪽만 밟아서, `|| [ ! -d ".githooks" ]` 를 통째로 지우는 변이가
#   생존했다(Phase C 실측 M1). 이 픽스처가 그 변이를 죽인다.
#   실무 근거: installer 자신이 `.githooks/` 부재 시 설치를 거부하므로(2df6de6), 이 형상에
#   처방을 내면 그 처방은 반드시 실패한다 — 정확히 이 FID 가 없애려는 죽은 처방이다.
R="$TMP/rds5"; _mkrepo "$R"
mkdir -p "$R/scripts/_internal"
printf '#!/bin/sh\nexit 0\n' > "$R/scripts/_internal/install-git-hooks.sh"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| git_hooks ' | grep -q '⚠️' \
  && printf '%s' "$_OUT" | grep -q 'specops 2단 게이트 미설치' \
  && ! printf '%s' "$_OUT" | grep -q 'install-git-hooks.sh' \
  && ok "T-ds.e installer 만 있고 .githooks 부재 → 하류 판정" || nope "T-ds.e" "out=$_OUT"

# T3 (AC-3): memory 에 placeholder 잔존 → ⚠️
R="$TMP/r3"; _mkrepo "$R"; mkdir -p "$R/.specops/memory"
printf '# IF 설계서\n\n- **버전**: <버전>\n' > "$R/.specops/memory/api-spec.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| memory ' | grep -q '⚠️' \
  && ok "T3 memory placeholder 검출" || nope "T3" "out=$_OUT"

# T3b (AC-3): 판정은 scan-enrich-placeholders.sh 호출로 재사용 — 중복 로직 금지
grep -q 'scan-enrich-placeholders\.sh' "$SH" \
  && ok "T3b scan-enrich-placeholders 재사용 배선" \
  || nope "T3b" "doctor.sh 내부 중복 판정 로직 — 드리프트 위험"

# T4 (AC-4): spec 만 있고 tasks·evidence 없는 FID 2건 → ⚠️ 2건 + 이름 노출
R="$TMP/r4"; _mkrepo "$R"
for f in 20260101-alpha 20260102-beta; do
  mkdir -p "$R/.specops/$f"; printf '# spec\n' > "$R/.specops/$f/spec.md"
done
mkdir -p "$R/.specops/20260103-done"
printf '# spec\n' > "$R/.specops/20260103-done/spec.md"
printf '# tasks\n' > "$R/.specops/20260103-done/tasks.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| orphan_fid ' | grep -q '2건' \
  && printf '%s' "$_OUT" | grep -q '20260101-alpha' \
  && ok "T4 고아 FID 2건 검출 + 이름" || nope "T4" "out=$_OUT"

# T5 (AC-5): /verify PASS 기록인데 evidence.md 부재 → ⚠️ + FID 지목
R="$TMP/r5"; _mkrepo "$R"
mkdir -p "$R/.specops/20260201-gap"
printf '# spec\n' > "$R/.specops/20260201-gap/spec.md"
printf '# tasks\n' > "$R/.specops/20260201-gap/tasks.md"
printf '# Session Progress\n\n## 20260201-gap\n\n- 2026-02-01 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '⚠️' \
  && printf '%s' "$_OUT" | grep -q '20260201-gap' \
  && ok "T5 progress 불일치 검출" || nope "T5" "out=$_OUT"

# T6 (AC-6): 점검 9항목 중 6항목이 ⚠️ 인 악상태에서도 exit 0
#   "전부" 가 아니다 — governance·deps 는 픽스처가 아니라 **호스트 환경**(훅 활성·jq/python3 설치)에
#   달려 있어 이 repo 픽스처로는 ✅ 로만 나온다. 그 둘의 ⚠️ 경로는 T-gov.* · T-deps.* 가 전담한다.
# 픽스처가 Given 을 실제로 재현해야 한다 — 고아 FID 가 없으면 orphan_fid 가 ✅ 라 6항목 ⚠️ 가 아니다.
R="$TMP/r6"; _mkrepo "$R"
mkdir -p "$R/.specops/20260101-orphan"; printf '# spec\n' > "$R/.specops/20260101-orphan/spec.md"
mkdir -p "$R/.specops/memory"; printf '# doc\n\n- **버전**: <버전>\n' > "$R/.specops/memory/x.md"
printf '# Session Progress\n\n## 20260101-orphan\n\n- 2026-01-01 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
# stale 도 **진짜 warn** 으로 재현한다 — 소스 3종 부재면 unknown 이라 ⚠️ 개수는 6이 되지만
#   T6 의 의도("6항목이 진짜 warn")와 어긋나 픽스처 충실도가 떨어진다. 8일 전 pending 1건.
printf '{"ts":"%s","files":["a.sh"],"prompt":"","type":"fix","fid":""}\n' \
  "$(python3 -c "import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=8)).strftime('%Y-%m-%dT%H:%M:%SZ'))")" \
  > "$R/.specops/pending-capture.jsonl"
_run "$R"
# 픽스처 재현과 본 단언을 **한 어서션**으로 묶는다 — 분리하면 미재현 시 총 개수가 12→13 으로 흔들린다.
warns=$(printf '%s' "$_OUT" | grep -c '⚠️')
[ "$_RC" -eq 0 ] && [ "${warns:-0}" -eq 6 ] \
  && ok "T6 9항목 중 6항목 ⚠️ 인 악상태에서도 exit 0" || nope "T6" "rc=$_RC warns=$warns"

# T7 (AC-7): .specops 부재 → 안내 + exit 0
R="$TMP/r7"; mkdir -p "$R"; git -C "$R" init -q 2>/dev/null
_run "$R"
[ "$_RC" -eq 0 ] && printf '%s' "$_OUT" | grep -q 'specops 미사용' \
  && ok "T7 비-specops repo 면제" || nope "T7" "rc=$_RC out=$_OUT"
# T7.b: 부트스트랩 전에도 환경 항목(deps·effort_env)은 점검한다.
#   README 가 "설치 직후 /doctor 로 deps 확인" 을 안내하는데 설치 직후에는 .specops 가 없다 —
#   종전에는 그 시점에 아무 항목도 내지 않아, jq 부재(훅 전면 fail-open)를 도입 전에 알 길이 없었다.
printf '%s' "$_OUT" | grep -qE '^\| deps ' && printf '%s' "$_OUT" | grep -qE '^\| effort_env ' \
  && ok "T7.b .specops 부재 → deps·effort_env 는 점검" || nope "T7.b" "out=$_OUT"
# T7.c: 프로젝트 항목은 내지 않는다 (없는 프로젝트를 진단하지 않는다) + 무엇을 건너뛰었는지 말한다
if printf '%s' "$_OUT" | grep -qE '^\| (memory|orphan_fid|progress|bootstrap|stale|governance|git_hooks) '; then
  nope "T7.c" "프로젝트 항목이 섞임: $_OUT"
else
  printf '%s' "$_OUT" | grep -q '프로젝트 항목은 건너' \
    && ok "T7.c .specops 부재 → 프로젝트 항목 생략 + 생략 사실 고지" || nope "T7.c" "생략 고지 없음: $_OUT"
fi
# T7.d: --json 도 같은 범위 — checks 는 deps·effort_env 2건, scope 로 범위를 밝힌다
_run "$R" --json
printf '%s' "$_OUT" | jq -e '.schema_version == 1 and .scope == "env-only" and ([.checks[].id] | sort) == ["deps","effort_env"] and (.warn_count | type) == "number"' >/dev/null 2>&1 \
  && ok "T7.d .specops 부재 --json → env-only 2항목" || nope "T7.d" "out=$_OUT"
# T7.e: jq 가 없으면 부트스트랩 전에도 ⚠️ 로 보인다 (이 항목의 존재 이유)
_nojq="$TMP/nojq-bin"; mkdir -p "$_nojq"
for _b in bash sh git python3 grep sed awk cat printf dirname basename date tr cut head tail sort uniq wc env mktemp rm ls find; do
  _p=$(command -v "$_b" 2>/dev/null) && [ -n "$_p" ] && ln -sf "$_p" "$_nojq/$_b"
done
_OUT=$(cd "$R" && PATH="$_nojq" SPECOPS_ROOT=".specops" bash "$SH" 2>&1); _RC=$?
[ "$_RC" -eq 0 ] && printf '%s' "$_OUT" | grep -E '^\| deps ' | grep -q '⚠️' \
  && ok "T7.e .specops 부재 + jq 없음 → deps ⚠️" || nope "T7.e" "rc=$_RC out=$_OUT"
# T7.e2: jq 없이 --json — 빈 checks 로 "문제 없음" 을 흉내내지 않는다. 유효한 한 줄 JSON 에 jq 부재를 싣는다.
_OUT=$(cd "$R" && PATH="$_nojq" SPECOPS_ROOT=".specops" bash "$SH" --json 2>&1); _RC=$?
[ "$_RC" -eq 0 ] && printf '%s' "$_OUT" | jq -e '.schema_version == 1 and .scope == "env-only" and .warn_count == 1 and .checks[0].id == "deps" and (.checks[0].detail | test("jq"))' >/dev/null 2>&1 \
  && ok "T7.e2 jq 없음 --json → 유효 JSON + deps warn 1건" || nope "T7.e2" "rc=$_RC out=$_OUT"
# T7.e3: pyyaml 설치 안내는 externally-managed(PEP 668) 환경의 길을 같이 적는다 — 맨 `pip3 install` 은 거기서 거부된다
_nopy="$TMP/nopy-bin"; mkdir -p "$_nopy"
for _b in bash sh git jq grep sed awk cat printf dirname basename date tr cut head tail sort uniq wc env mktemp rm ls find; do
  _p=$(command -v "$_b" 2>/dev/null) && [ -n "$_p" ] && ln -sf "$_p" "$_nopy/$_b"
done
_OUT=$(cd "$R" && PATH="$_nopy" SPECOPS_ROOT=".specops" bash "$SH" 2>&1); _RC=$?
_d7=$(printf '%s\n' "$_OUT" | grep '^| deps |')
printf '%s' "$_d7" | grep -q 'python3/pyyaml' && printf '%s' "$_d7" | grep -q 'pip3 install pyyaml' && printf '%s' "$_d7" | grep -q 'externally-managed' \
  && ok "T7.e3 pyyaml 부재 → 설치 안내 + externally-managed 대안" || nope "T7.e3" "행='$_d7'"
# T7.f: jq 가 없으면 governance 는 ✅ 가 아니다 — 훅이 켜져 있어도 jq 없이는 전면 fail-open 이다.
#   종전에는 한 표에 `governance ✅ 훅 4종 활성` 과 `deps ⚠️ … 거버넌스 비활성` 이 같이 나왔다(서로 반대 말).
R7f="$TMP/r7f"; mkdir -p "$R7f/.specops"; git -C "$R7f" init -q 2>/dev/null
_OUT=$(cd "$R7f" && PATH="$_nojq" SPECOPS_ROOT=".specops" bash "$SH" 2>&1); _RC=$?
_g7=$(printf '%s\n' "$_OUT" | grep '^| governance |')
if [ -z "$_g7" ]; then nope "T7.f" "governance 행 부재 — 단언 대상이 없다: $_OUT"
elif printf '%s' "$_g7" | grep -q '⚠️' && printf '%s' "$_g7" | grep -q 'jq' && ! printf '%s' "$_g7" | grep -q '✅'; then
  ok "T7.f jq 없음 → governance ⚠️ (켜져 있어도 동작하지 않는다고 말한다)"
else nope "T7.f" "행='$_g7'"; fi
# T7.h: memory 도 FID 도 없는 `.specops/` — 이전 버전 훅이 남긴 흔적일 수 있음을 알리고 빠져나가는 길을 말한다
_b7=$(printf '%s\n' "$_OUT" | grep '^| bootstrap |')
printf '%s' "$_b7" | grep -q '관할에서 빠진다' \
  && ok "T7.h 빈 .specops → 흔적 가능성·제거 안내" || nope "T7.h" "행='$_b7'"
# T7.i 대조: FID 디렉토리가 있으면 그 안내를 붙이지 않는다 (쓰는 저장소에 "지우라" 고 하지 않는다)
mkdir -p "$R7f/.specops/20260101-real"
_OUT=$(cd "$R7f" && PATH="$_nojq" SPECOPS_ROOT=".specops" bash "$SH" 2>&1)
! printf '%s\n' "$_OUT" | grep '^| bootstrap |' | grep -q '관할에서 빠진다' \
  && ok "T7.i FID 있음 → 제거 안내 없음" || nope "T7.i" "$(printf '%s\n' "$_OUT" | grep '^| bootstrap |')"
# T7.g 대조: jq 가 있으면 같은 저장소에서 governance ✅ (T7.f 가 PATH 축소 자체에 반응한 것이 아님)
_run "$R7f"
printf '%s\n' "$_OUT" | grep '^| governance |' | grep -q '✅' \
  && ok "T7.g 대조 — jq 있음 → governance ✅" || nope "T7.g" "out=$(printf '%s\n' "$_OUT" | grep governance)"

# T8 (AC-8): --json 9항목 status  ← governance·deps 2항목 추가(FID 20260830 T3)
R="$TMP/r8"; _mkrepo "$R"
_OUT=$(cd "$R" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>&1); _RC=$?
if [ "$_RC" -eq 0 ] && printf '%s' "$_OUT" | jq -e '(.checks|length)==9 and all(.checks[]; has("status"))' >/dev/null 2>&1; then
  ok "T8 --json 스키마"
else
  nope "T8" "rc=$_RC out=$_OUT"
fi

# T9 (AC-9): read-only — 실행 전후 파일 스냅샷 동일
R="$TMP/r9"; _mkrepo "$R"; mkdir -p "$R/.specops/20260101-x"
printf '# spec\n' > "$R/.specops/20260101-x/spec.md"
_snap() {  # $1=repo → 파일별 **내용** 해시. 목록만 해시하면 in-place 수정을 놓친다(리뷰 지적).
  #   `A || cd B && C` 는 (A||B)&&C 로 파싱돼 macOS 에서 두 해시기가 모두 실행된다(리뷰 실측)
  #   → command -v 분기로 명시한다.
  local h
  if command -v md5sum >/dev/null 2>&1; then h=md5sum; else h=md5; fi
  (cd "$1" && find . -not -path './.git/*' -type f | sort | xargs "$h" 2>/dev/null)
}
before=$(_snap "$R")
_run "$R"
after=$(_snap "$R")
[ "$before" = "$after" ] && ok "T9 read-only 보장" || nope "T9" "파일 변경 발생"

# T10 (AC-10): /doctor 슬래시 진입점 — frontmatter + 스크립트 호출 명시
CMD="$PLUGIN/commands/doctor.md"
if [ -f "$CMD" ] \
   && grep -q '^name: doctor' "$CMD" \
   && grep -q '^description:' "$CMD" \
   && grep -q 'scripts/doctor\.sh' "$CMD"; then
  ok "T10 /doctor 진입점"
else
  nope "T10" "commands/doctor.md 누락·필드 미비"
fi

# T11 (AC-11): 정상 상태에서도 9행 전부 출력
R="$TMP/r11"; _mkrepo "$R"; _hooks_ok "$R"
mkdir -p "$R/.specops/memory"; printf '# doc\n\n실제 내용\n' > "$R/.specops/memory/x.md"
printf '# Session Progress\n' > "$R/.specops/session-progress.md"
# stale 은 소스 3종이 전부 없으면 unknown(⚠️ 렌더) 이라 oks 가 5에 머문다.
#   Given("정상 상태")을 재현하려면 최신 pending 1건(0일 전)이 필요하다.
printf '{"ts":"%s","files":["a.sh"],"prompt":"","type":"fix","fid":""}\n' \
  "$(python3 -c "import datetime;print(datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")" \
  > "$R/.specops/pending-capture.jsonl"
# bootstrap 은 "memory 존재 ∧ chore(init) 커밋 0" 이면 warn 이다 — 정상 상태 픽스처가
#   커밋 0건이면 ✅ 6행이 되지 않는다. Given("정상 상태")을 실제로 재현한다.
git -C "$R" add -A >/dev/null 2>&1
git -C "$R" commit -q -m "chore(init): /init-project 부트스트랩 (픽스처)" >/dev/null 2>&1
_run "$R"
rows=$(printf '%s' "$_OUT" | grep -cE '^\| (git_hooks|memory|orphan_fid|progress|bootstrap|stale|governance|deps|effort_env) ')
oks=$(printf '%s' "$_OUT" | grep -c '✅')
# AC-11 Then 은 2절이다 — "9행 출력" AND "각 행이 ✅". 행 수만 세면 ⚠️ 9행도 통과한다.
[ "${rows:-0}" -eq 9 ] && [ "${oks:-0}" -eq 9 ] \
  && ok "T11 정상 상태 9행 전부 ✅" || nope "T11" "rows=$rows oks=$oks out=$_OUT"

# ── Phase C 수습 (리뷰 T3-C / T4-C) ─────────────────────────────────────────

# T13 (Important 1 · 변이 M5): "/verify FAIL — PASSWORD" 오탐 금지
#   실측 근거: 실 repo session-progress.md 는 "/verify.*PASS" 113줄 = "/verify PASS" 113줄
#   (loose-only 0줄) — 패턴을 조여도 실데이터 검출력 손실이 없다.
#   이 픽스처는 변이 M5(패턴에서 "/verify" 삭제 → *PASS*)도 함께 격추한다.
R="$TMP/r13"; _mkrepo "$R"
mkdir -p "$R/.specops/20260302-falsepos"
printf '# spec\n' > "$R/.specops/20260302-falsepos/spec.md"
printf '# tasks\n' > "$R/.specops/20260302-falsepos/tasks.md"
printf '# Session Progress\n\n## 20260302-falsepos\n\n- 2026-03-02 11:00 /verify FAIL — PASSWORD 마스킹 회귀\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '✅' \
  && ! printf '%s' "$_OUT" | grep -q '20260302-falsepos' \
  && ok "T13 /verify FAIL — PASSWORD 는 불일치 아님 (부분문자열 오탐 차단)" \
  || nope "T13" "out=$_OUT"

# T14 (Important 2): 디렉토리명의 파이프가 표·JSON 필드를 밀지 못한다
#   --json 은 schema_version 있는 기계 계약 — fix 필드 오염은 소비자 오동작.
R="$TMP/r14"; _mkrepo "$R"
mkdir -p "$R/.specops/20260401-a|b|c"; printf '# spec\n' > "$R/.specops/20260401-a|b|c/spec.md"
_OUT=$(cd "$R" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>&1); _RC=$?
if [ "$_RC" -eq 0 ] && printf '%s' "$_OUT" \
   | jq -e '(.checks|length)==9
            and ((.checks[]|select(.id=="orphan_fid")|.fix)=="진행하거나 정리하세요")' >/dev/null 2>&1; then
  ok "T14 파이프 인젝션에도 JSON 필드 정합 유지 (fix 문구 무손실)"
else
  nope "T14" "rc=$_RC out=$_OUT"
fi

# T14c (AC-1): `|` 는 단일 `/` 로 표시된다 — bash 3.2 의 `${a//|/\/}` 는 `\/` 를 남긴다
if [ "$_RC" -eq 0 ] && printf '%s' "$_OUT" \
   | jq -e '((.checks[]|select(.id=="orphan_fid")|.detail)|test("20260401-a/b/c"))' >/dev/null 2>&1; then
  ok "T14c 파이프가 단일 / 로 표시됨 (백슬래시 잔존 없음)"
else
  nope "T14c" "rc=$_RC out=$_OUT"
fi

# T14b (Important 2 동일 근원): 디렉토리명의 개행이 행 자체를 위조하지 못한다
NLDIR=$(printf '20260402-x\ny')
R="$TMP/r14b"; _mkrepo "$R"
mkdir -p "$R/.specops/$NLDIR"; printf '# spec\n' > "$R/.specops/$NLDIR/spec.md"
_OUT=$(cd "$R" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>&1); _RC=$?
# 행 수만 세면 mkdir 실패로 픽스처가 재현 안 돼도 9행이라 헛통과한다 — 고아 검출까지 함께 고정.
if [ "$_RC" -eq 0 ] && printf '%s' "$_OUT" \
   | jq -e '(.checks|length)==9
            and ((.checks[]|select(.id=="orphan_fid")|.status)=="warn")
            and ((.checks[]|select(.id=="orphan_fid")|.detail)|test("20260402-x"))' >/dev/null 2>&1; then
  ok "T14b 개행 포함 FID 에도 행 위조 없음 (checks 9행 고정)"
else
  nope "T14b" "rc=$_RC out=$_OUT"
fi

# T8b (Important 3 · 변이 M2): warn_count 가 실제 ⚠️ 개수와 일치
#   픽스처: git_hooks=warn · memory=unknown · orphan_fid=ok · progress=unknown · bootstrap=unknown
#           · stale=unknown(적체 소스 3종 전부 부재) → 5
R="$TMP/r8b"; _mkrepo "$R"
_run "$R"                                   # 표 렌더 — ⚠️ 실개수
warns8=$(printf '%s' "$_OUT" | grep -c '⚠️')
wc8=$(cd "$R" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>&1 | jq -r '.warn_count' 2>/dev/null)
[ "${wc8:-x}" = "5" ] && [ "${wc8:-x}" = "${warns8:-0}" ] \
  && ok "T8b --json warn_count == 표 ⚠️ 개수 (5)" || nope "T8b" "warn_count=$wc8 warns=$warns8"

# T16 (Minor 4): "## ../../outside-fid" 헤더가 .specops 밖을 프로브하지 않는다
R="$TMP/r16"; _mkrepo "$R"
printf '# Session Progress\n\n## ../../outside-fid\n\n- 2026-03-03 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '✅' \
  && ! printf '%s' "$_OUT" | grep -q 'outside-fid' \
  && ok "T16 경로 이탈 FID 헤더 무시" || nope "T16" "out=$_OUT"

# T17 (Minor 5 · 변이 M3): unknown 상태는 ⚠️ 로 렌더된다
#   git repo 아닌 디렉터리 → git_hooks=unknown. JSON status 도 함께 고정해야
#   (환경이 git repo 로 바뀌어 warn 이 돼도) 단언이 헛통과하지 않는다.
R="$TMP/r17"; mkdir -p "$R/.specops"
_OUT=$(cd "$R" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>&1)
json_unknown=0
printf '%s' "$_OUT" | jq -e '(.checks[]|select(.id=="git_hooks")|.status)=="unknown"' >/dev/null 2>&1 \
  && json_unknown=1
_run "$R"
[ "$json_unknown" -eq 1 ] \
  && printf '%s' "$_OUT" | grep -E '^\| git_hooks ' | grep -q '⚠️' \
  && ok "T17 unknown → JSON status unknown + 표 ⚠️" || nope "T17" "json_unknown=$json_unknown out=$_OUT"

# ─────────────────────────────────────────────────────────────
# T18~T26: progress 아카이브 분리 (FID 20260808-doctor-progress-archive)
#   판정 3분류 — 디렉터리 부재=아카이브 / 디렉터리 있음+evidence 부재=불일치 / 정상
#   ⚠️ T1~T17 은 건드리지 않는다 (AC-R-1 — diff 가 +N/-0 여야 한다)
# ─────────────────────────────────────────────────────────────

# T18 (AC-1): 디렉터리 자체가 없는 FID 는 불일치가 아니다 → ✅
R="$TMP/r18"; _mkrepo "$R"
printf '# Session Progress\n\n## 20260101-archived\n\n- 2026-01-01 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '✅' \
  && ! printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '20260101-archived' \
  && ok "T18 아카이브 FID → ✅ · 미지목" || nope "T18" "out=$_OUT"

# T19 (AC-2): 디렉터리 있음 + evidence.md 부재 → 여전히 ⚠️ + 지목
#   (T5 와 같은 축이나, 아카이브 분기 도입 후에도 살아있음을 명시 고정한다)
R="$TMP/r19"; _mkrepo "$R"
mkdir -p "$R/.specops/20260202-real"; printf '# spec\n' > "$R/.specops/20260202-real/spec.md"
printf '# Session Progress\n\n## 20260202-real\n\n- 2026-02-02 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '⚠️' \
  && printf '%s' "$_OUT" | grep -q '20260202-real' \
  && ok "T19 dir 존재 + evidence 부재 → ⚠️ 유지" || nope "T19" "out=$_OUT"

# T21 (AC-5): 혼재 — 불일치가 아카이브에 가려지지 않는다
#   카운트는 dir-exists 만, 지목도 dir-exists 만, 아카이브 FID 이름은 안 나온다
R="$TMP/r21"; _mkrepo "$R"
mkdir -p "$R/.specops/20260202-real"; printf '# spec\n' > "$R/.specops/20260202-real/spec.md"
printf '# Session Progress\n\n## 20260101-archived\n\n- 2026-01-01 10:00 /verify PASS\n\n## 20260202-real\n\n- 2026-02-02 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
_row=$(printf '%s' "$_OUT" | grep -E '^\| progress ')
printf '%s' "$_row" | grep -q '⚠️' \
  && printf '%s' "$_row" | grep -q '1건 불일치' \
  && printf '%s' "$_row" | grep -q '20260202-real' \
  && ! printf '%s' "$_row" | grep -q '20260101-archived' \
  && printf '%s' "$_row" | grep -q '아카이브 1건' \
  && ok "T21 혼재 → 불일치 1건만 카운트·지목 + 아카이브 건수 표기" || nope "T21" "row=$_row"

# T20 (AC-3): 아카이브 건수가 ✅ 경로에도 명시된다
R="$TMP/r20"; _mkrepo "$R"
printf '# Session Progress\n\n## 20260101-a\n\n- 2026-01-01 10:00 /verify PASS\n\n## 20260101-b\n\n- 2026-01-01 11:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '✅' \
  && printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '아카이브 2건 제외' \
  && ok "T20 ✅ 경로에 아카이브 건수 명시" || nope "T20" "out=$_OUT"

# T22 (AC-4): 아카이브 0건이면 그 문구가 아예 없다 (잡음 금지)
#   경고 포화를 고치면서 새 잡음을 만들지 않는다는 것이 이 FID 의 절반이다.
R="$TMP/r22"; _mkrepo "$R"
mkdir -p "$R/.specops/20260303-done"
printf '# spec\n' > "$R/.specops/20260303-done/spec.md"
printf '# evidence\n' > "$R/.specops/20260303-done/evidence.md"
printf '# Session Progress\n\n## 20260303-done\n\n- 2026-03-03 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '✅' \
  && ! printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '아카이브' \
  && ok "T22 아카이브 0건 → 문구 없음" || nope "T22" "out=$_OUT"

# T26 (AC-3 하위 · dedup 대칭): 같은 FID 헤더가 두 번이어도 아카이브는 1건
#   기존 bad 는 dedup 하는데 arch 만 안 하면 건수가 부풀고, 그걸 잡는 어서션이 없다.
R="$TMP/r26"; _mkrepo "$R"
printf '# Session Progress\n\n## 20260101-dup\n\n- 2026-01-01 10:00 /verify PASS\n\n## 20260101-dup\n\n- 2026-01-02 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '아카이브 1건' \
  && ok "T26 중복 헤더 → 아카이브 dedup (1건)" || nope "T26" "out=$_OUT"

# T24 (AC-7): 판정 의미가 문서에 기술됐는가 — 계약서가 지정한 ID 다
grep -q '아카이브' "$PLUGIN/commands/doctor.md" \
  && ok "T24 doctor.md 에 아카이브 판정 기술" || nope "T24" "commands/doctor.md 아카이브 문구 부재"

# T25 (AC-10): 원 AC-5 승계 명시 + 원 FID 계약서 무수정
#   계약서 AC-10 의 두 번째 절("git diff 에 원 FID 경로 부재")은 .gitignore:5 가 .specops/* 를
#   통째로 제외해 **구조상 영원히 통과**한다(vacuous — plan §4.3 실측). 의도(원 FID 아티팩트
#   무수정)를 실제로 검증하는 형태로 읽는다 — 원 계약서에 승계 문구가 들어가지 않았음을 확인.
grep -q 'AC-5' "$PLUGIN/commands/doctor.md" && t25_doc=1 || t25_doc=0
_OLD_AC="$PLUGIN/.specops/20260807-specops-doctor/acceptance-criteria.md"
if [ -f "$_OLD_AC" ]; then
  grep -qE 'supersede|20260808' "$_OLD_AC" && t25_old=0 || t25_old=1
else
  t25_old=1   # .specops/* 는 gitignore — 신규 clone·CI 에는 없다 (GH-8 선례의 SKIP 동형)
fi
[ "$t25_doc" -eq 1 ] && [ "$t25_old" -eq 1 ] \
  && ok "T25 승계 명시 + 원 FID 계약서 무수정" \
  || nope "T25" "doc=$t25_doc old_untouched=$t25_old"

# T23 (AC-6): 아카이브 상태에서도 --json 스키마 불변 (checks 9건 · schema_version 1 · warn_count 정합)
R="$TMP/r23"; _mkrepo "$R"
mkdir -p "$R/.specops/20260202-real"; printf '# spec\n' > "$R/.specops/20260202-real/spec.md"
printf '# Session Progress\n\n## 20260101-archived\n\n- 2026-01-01 10:00 /verify PASS\n\n## 20260202-real\n\n- 2026-02-02 10:00 /verify PASS\n' \
  > "$R/.specops/session-progress.md"
_run "$R" --json
_n=$(printf '%s' "$_OUT" | jq -r '.checks|length' 2>/dev/null)
_sv=$(printf '%s' "$_OUT" | jq -r '.schema_version' 2>/dev/null)
_wc=$(printf '%s' "$_OUT" | jq -r '.warn_count' 2>/dev/null)
_actual=$(printf '%s' "$_OUT" | jq -r '[.checks[]|select(.status=="warn" or .status=="unknown")]|length' 2>/dev/null)
[ "$_n" = "9" ] && [ "$_sv" = "1" ] && [ "$_wc" = "$_actual" ] \
  && ok "T23 아카이브 상태에서 --json 스키마 불변 (checks=9 · warn_count=$_wc)" \
  || nope "T23" "n=$_n sv=$_sv wc=$_wc actual=$_actual"

# T27 (Phase C Important 2): CRLF 헤더에서도 dir 존재 판정이 어긋나지 않는다
#   `\r` 가 FID 문자열에 남으면 `[ -d ]` 가 실패해 **존재하는 dir 이 아카이브로 오분류**된다.
#   main 에서 ⚠️ 로 시끄럽던 진짜 결함이 ✅ 로 조용해지는 **실패 방향 반전** — 가장 위험한 형태다.
R="$TMP/r27"; _mkrepo "$R"
mkdir -p "$R/.specops/20260202-crlf"; printf '# spec\n' > "$R/.specops/20260202-crlf/spec.md"
printf '# Session Progress\r\n\r\n## 20260202-crlf\r\n\r\n- 2026-02-02 10:00 /verify PASS\r\n' \
  > "$R/.specops/session-progress.md"
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| progress ' | grep -q '⚠️' \
  && printf '%s' "$_OUT" | grep -q '20260202-crlf' \
  && ok "T27 CRLF 헤더 → dir 존재 인식 유지 (아카이브 오분류 없음)" || nope "T27" "out=$_OUT"

# T28 (Phase C Important 1): **본문**의 chore(init) 언급은 부트스트랩 종결이 아니다
#   실 repo 실측: `git log --grep='chore(init)'` 3건 매치가 전부 오탐(190544d·a375648·23a4943)
#   — 미종결 부트스트랩이 조용히 ✅ 되는 **실패 방향 반전**.
#   두 번째 픽스처 커밋이 결정적이다: git 의 --grep 은 **행 단위** 매칭이라
#   `--grep='^chore(init): '` 앵커도 본문 줄머리를 잡는다(실측 — 아래 커밋이 매치됐다).
#   그래서 판정은 subject(%s) 만 보고 해야 한다.
R="$TMP/r28"; _mkrepo "$R"
mkdir -p "$R/.specops/memory"; printf '# doc\n\n실제 내용\n' > "$R/.specops/memory/x.md"
git -C "$R" add -A >/dev/null 2>&1
git -C "$R" commit -q -m "feat(x): 다른 작업" -m "본문 참조: chore(init) 커밋을 보라" >/dev/null 2>&1
printf 'b\n' > "$R/b.txt"; git -C "$R" add -A >/dev/null 2>&1
git -C "$R" commit -q -m "docs(y): 회고" -m "chore(init): 이 줄은 본문의 줄머리다" >/dev/null 2>&1
_run "$R"
if printf '%s' "$_OUT" | grep -E '^\| bootstrap ' | grep -q '⚠️' \
   && printf '%s' "$_OUT" | grep -E '^\| bootstrap ' | grep -q 'init-finalize\.sh'; then
  ok "T28 본문 언급뿐인 chore(init) → bootstrap ⚠️ 유지 (subject 앵커)"
else
  nope "T28" "row=$(printf '%s' "$_OUT" | grep -E '^\| bootstrap ')"
fi

# T29 (T28 짝) — subject 가 진짜 `chore(init): ` 이면 ✅ (검출력 손실 없음)
R="$TMP/r29"; _mkrepo "$R"
mkdir -p "$R/.specops/memory"; printf '# doc\n\n실제 내용\n' > "$R/.specops/memory/x.md"
git -C "$R" add -A >/dev/null 2>&1
git -C "$R" commit -q -m "chore(init): /init-project 부트스트랩+enrich (13종)" >/dev/null 2>&1
_run "$R"
printf '%s' "$_OUT" | grep -E '^\| bootstrap ' | grep -q '✅' \
  && ok "T29 subject 가 chore(init): → bootstrap ✅" \
  || nope "T29" "row=$(printf '%s' "$_OUT" | grep -E '^\| bootstrap ')"

# ── T-stale (FID 20260815-doctor-stale-detect) ──────────────────────────────
# 무음 실패 감지 — pending 적체 / freelog 정체 / 우회 상시화.
# 날짜 픽스처는 timezone-aware python3 로 만든다(utcfromtimestamp 는 deprecated).
_iso_ago() { python3 -c "import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=$1)).strftime('%Y-%m-%dT%H:%M:%SZ'))"; }
_ymd_ago() { python3 -c "import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=$1)).strftime('%Y%m%d'))"; }

_stale_status() { ( cd "$1" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>/dev/null ) | jq -r '.checks[]|select(.id=="stale")|.status'; }
_stale_detail() { ( cd "$1" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>/dev/null ) | jq -r '.checks[]|select(.id=="stale")|.detail'; }
# ※ repo 픽스처는 파일 상단 `_mkrepo` 를 재사용한다 — 한 글자 다른 `_mk_repo` 를 따로 두면
#   호출부에서 혼동만 낳는다(Phase C Suggestion). 둘의 차이는 user.email 값뿐이었다.
_byp() { # $1=dir $2=일수 $3=건수
  local i
  for i in $(seq 1 "$3"); do
    printf '{"ts":"%s","rule_id":"BYPASS-ENV"}\n' "$(_iso_ago "$2")" >> "$1/.specops/friction-log.jsonl"
  done
}

SB_A=$(mktemp -d); SB_B=$(mktemp -d); SB_C=$(mktemp -d)
SB_D=$(mktemp -d); SB_E=$(mktemp -d); SB_F=$(mktemp -d); SB_G=$(mktemp -d); SB_H=$(mktemp -d)
# 뒤에서 mktemp 하는 샌드박스도 trap 에 병기한다(Phase C Suggestion) — 인라인 rm 은 유지하되
#   어서션 중도 종료 시 누수를 막는다. `set -u` 아래 미할당 참조가 trap 안에서 터지지 않도록
#   빈 문자열로 선초기화하고 `${V:+"$V"}` 로 넘긴다.
SB_I=""; SB_J=""; SB_K=""; SB_L=""; SB_M=""
# ★ 기존 trap(:9 `rm -rf "$TMP"`)을 덮어쓰지 않도록 "$TMP" 를 병기한다.
#   bash 는 동일 시그널 trap 을 **대체**하므로 누락 시 r1~r29 픽스처가 매 실행 누수된다(실측).
trap 'rm -rf "$TMP" "$SB_A" "$SB_B" "$SB_C" "$SB_D" "$SB_E" "$SB_F" "$SB_G" "$SB_H" \
  ${SB_I:+"$SB_I"} ${SB_J:+"$SB_J"} ${SB_K:+"$SB_K"} ${SB_L:+"$SB_L"} ${SB_M:+"$SB_M"}' EXIT
for _d in "$SB_A" "$SB_B" "$SB_C" "$SB_D" "$SB_E" "$SB_F" "$SB_G" "$SB_H"; do _mkrepo "$_d"; done

# T-stale.a (AC-1): stale 행 정확히 1개 + 4필드
_rows=$( ( cd "$SB_A" && SPECOPS_ROOT=".specops" bash "$SH" 2>/dev/null ) | grep -c '^| stale ')
_flds=$( ( cd "$SB_A" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>/dev/null ) \
  | jq -r '[.checks[]|select(.id=="stale")] as $s
           | "\($s|length) \($s[0] | (has("id") and has("status") and has("detail") and has("fix")))"' 2>/dev/null)
[ "$_rows" = "1" ] && [ "$_flds" = "1 true" ] \
  && ok "T-stale.a stale 1행 + 4필드" || nope "T-stale.a" "rows=$_rows flds=$_flds"

# T-stale.f (AC-4): 데이터 소스 전부 부재 → unknown
[ "$(_stale_status "$SB_A")" = "unknown" ] \
  && ok "T-stale.f 소스 전부 부재 → unknown" || nope "T-stale.f" "got=$(_stale_status "$SB_A")"

# T-stale.b (AC-2): pending 최고령 8일 → warn
printf '{"ts":"%s","files":["a.sh"],"prompt":"","type":"fix","fid":""}\n' "$(_iso_ago 8)" \
  > "$SB_B/.specops/pending-capture.jsonl"
[ "$(_stale_status "$SB_B")" = "warn" ] \
  && ok "T-stale.b pending 8일 → warn" || nope "T-stale.b" "got=$(_stale_status "$SB_B")"

# T-stale.n (AC-2 Then 후단): detail 에 지표 수치(건수·경과일)가 실제로 담긴다
#   T-stale 전 항목이 status 만 본다 — "detail 에 수치 포함" 절을 잠그는 유일한 어서션이다.
_det=$( ( cd "$SB_B" && SPECOPS_ROOT=".specops" bash "$SH" --json 2>/dev/null ) \
  | jq -r '.checks[]|select(.id=="stale")|.detail')
printf '%s' "$_det" | grep -q '1건' && printf '%s' "$_det" | grep -q '8일' \
  && ok "T-stale.n detail 에 건수·경과일 포함" || nope "T-stale.n" "detail=$_det"

# T-stale.c (AC-2 경계): pending 7일 → warn 아님 (ok)
printf '{"ts":"%s","files":["a.sh"],"prompt":"","type":"fix","fid":""}\n' "$(_iso_ago 7)" \
  > "$SB_C/.specops/pending-capture.jsonl"
[ "$(_stale_status "$SB_C")" = "ok" ] \
  && ok "T-stale.c pending 7일 경계 → ok" || nope "T-stale.c" "got=$(_stale_status "$SB_C")"

# T-stale.d (AC-2): 최근 5일 우회 3건 → warn
_byp "$SB_D" 5 3
[ "$(_stale_status "$SB_D")" = "warn" ] \
  && ok "T-stale.d 최근 우회 3건 → warn" || nope "T-stale.d" "got=$(_stale_status "$SB_D")"

# T-stale.h (F-1 음성 대조군): 31일 전 우회 3건 → ok
#   clarify F-1 이 잡은 결함 — jq 필터가 30일 창을 실제로 적용하지 않으면 여기서만 걸린다.
#   T-stale.d(양성)만으로는 통과하므로 본 어서션이 유일한 락이다.
_byp "$SB_E" 31 3
[ "$(_stale_status "$SB_E")" = "ok" ] \
  && ok "T-stale.h 31일 전 우회 3건 → ok (30일 창 적용)" || nope "T-stale.h" "got=$(_stale_status "$SB_E")"

# T-stale.e (AC-3): freelog 30일 정체 + 그 이후 커밋 0 → ok
printf '# freelog\n\n## %s\n\n- 00:00 [fix] (x) a.sh — x\n' "$(_ymd_ago 30)" > "$SB_F/.specops/freelog.md"
[ "$(_stale_status "$SB_F")" = "ok" ] \
  && ok "T-stale.e freelog 정체 + 커밋 0 → ok" || nope "T-stale.e" "got=$(_stale_status "$SB_F")"

# T-stale.i (AC-2 ② 양성): freelog 15일 정체 + 그 이후 커밋 1건 → warn
#   T-stale.e 는 음성(커밋 0)만 본다 — 이 어서션이 없으면 FR-3 의 warn 경로가 무테스트다.
printf '# freelog\n\n## %s\n\n- 00:00 [fix] (x) a.sh — x\n' "$(_ymd_ago 15)" > "$SB_G/.specops/freelog.md"
( cd "$SB_G" && echo x > f.txt && git add -A >/dev/null 2>&1 \
  && git commit -q -m "픽스처 커밋" >/dev/null 2>&1 )
[ "$(_stale_status "$SB_G")" = "warn" ] \
  && ok "T-stale.i freelog 15일 + 커밋 1 → warn" || nope "T-stale.i" "got=$(_stale_status "$SB_G")"

# T-stale.m (AC-2 ② 경계): freelog 14일 + 그 이후 커밋 1건 → ok (15일부터 warn)
#   T-stale.i(15일→warn)와 짝. 이 어서션이 없으면 -gt 14 를 -gt 0 으로 바꿔도 전 스위트 생존한다(변이 실측).
SB_J=$(mktemp -d); _mkrepo "$SB_J"
printf '# freelog\n\n## %s\n\n- 00:00 [fix] (x) a.sh — x\n' "$(_ymd_ago 14)" > "$SB_J/.specops/freelog.md"
( cd "$SB_J" && echo x > f.txt && git add -A >/dev/null 2>&1 \
  && git commit -q -m "픽스처 커밋" >/dev/null 2>&1 )
[ "$(_stale_status "$SB_J")" = "ok" ] \
  && ok "T-stale.m freelog 14일 경계 + 커밋 1 → ok" || nope "T-stale.m" "got=$(_stale_status "$SB_J")"
rm -rf "$SB_J"

# T-stale.j (AC-2 ③ 경계): 최근 우회 2건 → ok (3건 미만)
_byp "$SB_H" 5 2
[ "$(_stale_status "$SB_H")" = "ok" ] \
  && ok "T-stale.j 최근 우회 2건 경계 → ok" || nope "T-stale.j" "got=$(_stale_status "$SB_H")"

# T-stale.g (AC-R-1 ②): read-only — 실행 전후 .specops 파일 목록 동일
_before=$( (cd "$SB_B" && find .specops -type f | sort) )
( cd "$SB_B" && SPECOPS_ROOT=".specops" bash "$SH" >/dev/null 2>&1 )
_after=$( (cd "$SB_B" && find .specops -type f | sort) )
[ "$_before" = "$_after" ] \
  && ok "T-stale.g read-only 불변" || nope "T-stale.g" "파일 목록 변경됨"

# T-stale.l (AC-4 ok 절 literal): 3소스 **동시** 존재 + 전부 임계 미만 → ok
#   기존 ok 케이스(c·e·j)는 단일 소스라 합집합 커버일 뿐이다. AC-4 Then 후단이
#   "셋 다 존재하고 임계 미만이면 ok" 를 literal 로 요구하므로 동시 픽스처를 1건 둔다.
SB_I=$(mktemp -d); _mkrepo "$SB_I"
printf '{"ts":"%s","files":["a.sh"],"prompt":"","type":"fix","fid":""}\n' "$(_iso_ago 1)" \
  > "$SB_I/.specops/pending-capture.jsonl"
printf '# freelog\n\n## %s\n\n- 00:00 [fix] (x) a.sh — x\n' "$(_ymd_ago 1)" > "$SB_I/.specops/freelog.md"
_byp "$SB_I" 5 1
[ "$(_stale_status "$SB_I")" = "ok" ] \
  && ok "T-stale.l 3소스 동시 + 전부 임계 미만 → ok" || nope "T-stale.l" "got=$(_stale_status "$SB_I")"
rm -rf "$SB_I"

# T-stale.k (AC-R-1 ①·품질): stderr 오염 없음 — fl_commits 류 정수 비교 에러 검출
#   T-stale.e 계열은 2>/dev/null 이라 이 클래스를 영원히 못 잡는다(plan-reviewer 지적).
_err=$( ( cd "$SB_G" && SPECOPS_ROOT=".specops" bash "$SH" >/dev/null ) 2>&1 )
[ -z "$_err" ] && ok "T-stale.k stderr 무오염" || nope "T-stale.k" "stderr=$_err"

# T-stale.o (Phase C Important 1): 유효 우회 3건 + 손상 라인 1줄 → warn + 손상 줄 수 노출
#   `jq -rs`(전체 슬럽)는 1줄만 깨져도 전량이 사라져 "적체 없음" 으로 오판한다(Phase C probeB).
#   detail 까지 보는 이유 — status 만 보면 손상 카운터가 죽어도(bad=0) warn 이라 통과한다.
SB_K=$(mktemp -d); _mkrepo "$SB_K"
_byp "$SB_K" 5 3
printf 'CORRUPT LINE not-json\n' >> "$SB_K/.specops/friction-log.jsonl"
if [ "$(_stale_status "$SB_K")" = "warn" ] && _stale_detail "$SB_K" | grep -q '손상 라인 1줄'; then
  ok "T-stale.o 손상 라인 혼재해도 유효 우회 검출 + 손상 1줄 보고"
else
  nope "T-stale.o" "st=$(_stale_status "$SB_K") detail=$(_stale_detail "$SB_K")"
fi
rm -rf "$SB_K"; SB_K=""

# T-stale.p (Phase C Important 2): 손상 라인만 있으면 ok 가 아니라 unknown
#   훅 append 중단으로 부분 라인이 실제로 생긴다 — 못 읽은 줄을 "적체 없음" 으로 낙관 보고 금지.
SB_L=$(mktemp -d); _mkrepo "$SB_L"
printf 'CORRUPT\n' > "$SB_L/.specops/pending-capture.jsonl"
[ "$(_stale_status "$SB_L")" = "unknown" ] \
  && ok "T-stale.p 손상 전용 입력 → unknown (낙관 ok 금지)" || nope "T-stale.p" "got=$(_stale_status "$SB_L")"
rm -rf "$SB_L"; SB_L=""

# T-stale.q (Phase C 2회차 Important 1): jq 판독 자체가 실패해도 unknown 으로 강등
#   T-stale.p 의 `CORRUPT\n` 은 jq -Rsr 가 **성공**하는 경로라(손상 카운트는 jq 가 세 준다)
#   doctor.sh 의 jq 실패 fallback(`case ''|0) pend_bad=1`)에 닿지 못한다 — 그 강등을 잠그는
#   유일한 어서션이 이것이다(없으면 pend_bad=1 → 0 변이가 전 스위트 생존, 실측).
#   픽스처는 JSONL 경로를 **디렉토리**로 만든다 — jq·grep 모두 uid 무관 결정적 실패라
#   chmod 000(root 에서 무력) 대비 CI 안정적이다.
#   ※ 전제: 디렉토리가 `[ -s "$SPECOPS/pending-capture.jsonl" ]`(size>0)를 통과해야 해당 분기에
#     진입한다. APFS·ext4·tmpfs·XFS 는
#     참이지만 POSIX 보장은 아니다 — 이 어서션이 특정 FS 에서만 깨지면 그 전제를 먼저 의심할 것.
SB_M=$(mktemp -d); _mkrepo "$SB_M"
mkdir "$SB_M/.specops/pending-capture.jsonl"
if [ "$(_stale_status "$SB_M")" = "unknown" ] && _stale_detail "$SB_M" | grep -q '손상 라인'; then
  ok "T-stale.q jq 판독 불가(디렉토리) → unknown + 손상 라인 보고"
else
  nope "T-stale.q" "st=$(_stale_status "$SB_M") detail=$(_stale_detail "$SB_M")"
fi
rm -rf "$SB_M"; SB_M=""

# ── T-bs.a~e: 정체 batch 를 stale 축이 본다 (FID 20260829-batch-stall-visibility) ──
# 왜: argus 실측에서 FR 31건이 IMPL_DONE 에 멈춘 채 ~30일 방치됐다. v1.81.0 의
#   batch-resume-check 가 SessionStart 에 표면화하지만 **두 구멍**이 남았다:
#     ① 나이가 없다 — 매 세션 같은 줄이 나와 2주면 벽지가 된다(이 repo 가 skip-tracker
#        advisory 에서 이미 겪은 형태다).
#     ② ACTIVE 마커에만 의존한다 — 마커 없이 방치된 미완 queue 는 **아예 안 보인다**.
#   doctor 의 stale 축은 이미 "적체·정체" 를 일수 임계로 모으는 자리다. 여기 얹는다.
# ★ 문제 A 자체는 도구로 완전히 닫히지 않는다 — "세션이 끝나면 이어받을 주체가 없다" 는
#   모델이 들고 있는 오케스트레이션 루프의 성질이다. 도구가 살 수 있는 건 탐지·재개성뿐이다.
_mk_batch() {  # $1=repo $2=batch-id $3=queue본문 $4=ACTIVE(1/0) $5=mtime일수전
  local r="$1" b="$2" body="$3" act="$4" age="$5" d="$1/.specops/$2"
  mkdir -p "$d"
  printf '%s' "$body" > "$d/queue.md"
  [ "$act" = 1 ] && : > "$d/ACTIVE"
  # mtime 을 과거로 — 나이 판정 대상
  local ts; ts=$(date -u -v-"${age}"d +%Y%m%d%H%M 2>/dev/null || date -u -d "${age} days ago" +%Y%m%d%H%M)
  touch -t "$ts" "$d/queue.md"
}
_QBODY_INC='| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-1 | 20260101-a | a | IMPL_DONE |
| FR-2 | 20260101-b | b | PLAN_DONE |
'
_QBODY_DONE='| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-1 | 20260101-a | a | IMPL_DONE |
| FR-2 | 20260101-b | b | IMPL_DONE |
'

R="$TMP/bs1"; _mkrepo "$R"; _hooks_ok "$R"
_mk_batch "$R" batch-20260101 "$_QBODY_INC" 1 40
_run "$R"
printf '%s' "$_OUT" | grep -q 'batch' \
  && ok "T-bs.a ★ 40일 정체 batch → stale 축에 보고" || nope "T-bs.a" "$(printf '%s' "$_OUT" | grep stale)"
printf '%s' "$_OUT" | grep -qE 'batch-20260101.*(40|3[0-9])일|(40|3[0-9])일.*batch-20260101' \
  && ok "T-bs.b ★ 나이를 함께 보고 (벽지화 차단)" || nope "T-bs.b 나이" "$(printf '%s' "$_OUT" | grep stale)"

# ★ ACTIVE 마커 없이 방치된 미완 queue 도 본다 (구멍 ②)
R2="$TMP/bs2"; _mkrepo "$R2"; _hooks_ok "$R2"
_mk_batch "$R2" batch-20260102 "$_QBODY_INC" 0 40
_run "$R2"
printf '%s' "$_OUT" | grep -q 'batch-20260102' \
  && ok "T-bs.c ★ ACTIVE 마커 없어도 미완 queue 탐지 (마커 의존 탈피)" \
  || nope "T-bs.c 마커의존" "$(printf '%s' "$_OUT" | grep stale)"

# 되돌려-관찰 ①: 최근 batch 는 경고하지 않는다 (진행 중인 작업을 정체로 부르지 않는다)
R3="$TMP/bs3"; _mkrepo "$R3"; _hooks_ok "$R3"
_mk_batch "$R3" batch-20260103 "$_QBODY_INC" 1 1
_run "$R3"
printf '%s' "$_OUT" | grep -q 'batch-20260103' \
  && nope "T-bs.d 오탐" "1일된 batch 를 정체로 보고" || ok "T-bs.d 최근 batch 는 무보고 (오탐 차단)"

# 되돌려-관찰 ②: 전 FR 완료 + 마커 없음 = 정상 종결 → 무보고
R4="$TMP/bs4"; _mkrepo "$R4"; _hooks_ok "$R4"
_mk_batch "$R4" batch-20260104 "$_QBODY_DONE" 0 40
_run "$R4"
printf '%s' "$_OUT" | grep -q 'batch-20260104' \
  && nope "T-bs.e 오탐" "종결된 batch 를 정체로 보고" || ok "T-bs.e 종결 batch 는 무보고 (Step D 정상경로)"

# ── T-gov (AC-1): 거버넌스 비활성이 doctor 에 ⚠️ 로 보인다 ──
# 종전엔 어떤 항목도 이걸 보지 않아, config.yaml 4줄로 전 훅이 꺼져도 표가 정상 보고했다.
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  _mkrepo "$TMP/gov-off"
  printf 'profile: none\nprofiles:\n  none:\n    enforce_all_disabled: true\n' \
    > "$TMP/gov-off/.specops/config.yaml"
  _run "$TMP/gov-off"
  gline=$(printf '%s\n' "$_OUT" | grep '^| governance |')
  if printf '%s' "$gline" | grep -q '⚠️' && printf '%s' "$gline" | grep -q '비활성'; then
    ok "T-gov.a config 킬스위치 → governance ⚠️ + 비활성 표기 (AC-1)"
  else
    nope "T-gov.a" "행='$gline' — 거버넌스가 꺼져도 정상 보고한다"
  fi
  if printf '%s' "$gline" | grep -q 'config.yaml'; then
    ok "T-gov.b 조치란이 config.yaml 을 지목 (AC-1 조치)"
  else
    nope "T-gov.b" "조치 부재 — 사용자가 해제 방법을 모른다"
  fi

  _mkrepo "$TMP/gov-on"
  _run "$TMP/gov-on"
  gline2=$(printf '%s\n' "$_OUT" | grep '^| governance |')
  if printf '%s' "$gline2" | grep -q '✅'; then
    ok "T-gov.c config 부재 → governance ✅ (오탐 없음)"
  else
    nope "T-gov.c" "행='$gline2' — 정상 상태를 경고로 오탐한다"
  fi

  # T-gov.d/e (Phase C Minor 4): **부분** 비활성 경로. 전부-off/전부-on 만 잠그면
  #   N/4 카운트와 대상 훅 지목이 무검증으로 남는다 — 전부-off 픽스처는 카운트 로직이
  #   틀려도(예: n 을 항상 4로) 4/4 로 맞아떨어져 T-gov.a 가 그대로 통과하기 때문이다.
  _mkrepo "$TMP/gov-partial"
  printf 'hooks:\n  stop-governance:\n    enabled: false\n' \
    > "$TMP/gov-partial/.specops/config.yaml"
  _run "$TMP/gov-partial"
  gline3=$(printf '%s\n' "$_OUT" | grep '^| governance |')
  if [ -z "$gline3" ]; then
    nope "T-gov.d" "governance 행 부재 — 단언 대상이 없다(공허 통과 방지)"
  elif printf '%s' "$gline3" | grep -q '⚠️' \
     && printf '%s' "$gline3" | grep -q '1/4' \
     && printf '%s' "$gline3" | grep -q 'stop-governance'; then
    ok "T-gov.d 부분 비활성 → '훅 1/4 비활성: stop-governance' (Minor 4)"
  else
    nope "T-gov.d" "행='$gline3' — 부분 비활성의 개수·대상이 정확히 표기되지 않는다"
  fi
  # ★ 음성 단언이 있어야 이빨이 선다 — 이게 없으면 4종을 전부 나열하는 망가진 카운트도
  #   위 단언(1/4·stop-governance 부분일치)을 통과한다. 활성 훅을 비활성으로 지목하면
  #   사용자는 멀쩡한 설정을 뒤진다. 행 부재 시엔 명시 실패(T-deps.e 와 같은 이유).
  if [ -z "$gline3" ]; then
    nope "T-gov.e" "governance 행 부재 — 음성 단언의 대상이 없다"
  elif printf '%s' "$gline3" | grep -q 'pretool-governance'; then
    nope "T-gov.e" "행='$gline3' — 꺼지지 않은 훅까지 비활성으로 지목한다"
  else
    ok "T-gov.e 활성 훅은 비활성 목록에 없음 (부분 비활성 오탐 없음)"
  fi

  # T-gov.f (Phase C Important 1): SPECOPS_ROOT 가 cwd 밖을 가리켜도 **그 프로젝트의**
  #   config 를 본다. 다른 전 케이스는 cwd == 프로젝트 루트라 is-hook-enabled 의 자기
  #   기본값과 우연히 일치해, root 불일치 시의 거짓 ✅ 를 아무도 잡지 못했다(리뷰어 실측).
  #   _run 은 cd 하므로 여기서는 의도적으로 **상위 디렉토리에서** 호출한다.
  mkdir -p "$TMP/govroot"; _mkrepo "$TMP/govroot/proj"
  printf 'profile: none\nprofiles:\n  none:\n    enforce_all_disabled: true\n' \
    > "$TMP/govroot/proj/.specops/config.yaml"
  _OUT=$(cd "$TMP/govroot" && SPECOPS_ROOT="proj/.specops" bash "$SH" 2>&1)
  gline4=$(printf '%s\n' "$_OUT" | grep '^| governance |')
  if [ -z "$gline4" ]; then
    nope "T-gov.f" "governance 행 부재 — 단언 대상이 없다(공허 통과 방지)"
  elif printf '%s' "$gline4" | grep -q '⚠️' && printf '%s' "$gline4" | grep -q '비활성'; then
    ok "T-gov.f SPECOPS_ROOT 불일치에서도 킬스위치 탐지 (Important 1)"
  else
    nope "T-gov.f" "행='$gline4' — 꺼진 프로젝트를 ✅ 로 보고한다(표면화 장치의 거짓 ✅)"
  fi
  # ★ 사용자가 export 한 SPECOPS_CONFIG 는 존중해야 한다 — `:-` 를 무조건 대입으로 바꾸면
  #   이 단언이 깨진다(명시 지정이 SPECOPS_ROOT 파생값에 덮이는 조용한 무시).
  _OUT=$(cd "$TMP/govroot" && SPECOPS_CONFIG="$TMP/govroot/absent.yaml" \
    SPECOPS_ROOT="proj/.specops" bash "$SH" 2>&1)
  gline5=$(printf '%s\n' "$_OUT" | grep '^| governance |')
  if [ -z "$gline5" ]; then
    nope "T-gov.g" "governance 행 부재 — 단언 대상이 없다"
  elif printf '%s' "$gline5" | grep -q '✅'; then
    ok "T-gov.g 사용자 지정 SPECOPS_CONFIG 를 존중 (덮어쓰기 없음)"
  else
    nope "T-gov.g" "행='$gline5' — 명시 지정한 SPECOPS_CONFIG 가 무시된다"
  fi
else
  skip "T-gov (python3+pyyaml 부재 — config 킬스위치 시뮬레이션 불가)"
  skip "T-gov.b (동상)"
  skip "T-gov.c (동상)"
  skip "T-gov.d (동상)"
  skip "T-gov.e (동상)"
  skip "T-gov.f (동상)"
  skip "T-gov.g (동상)"
fi

# T-gov.h (Phase C Minor 1): 판정기 실행 실패는 "비활성" 이 아니라 **판정 불가**다.
#   rc 를 뭉뚱그리면 rc=127(판정기 부재)도 4/4 비활성으로 계상돼 조치란이 config.yaml 을
#   지목하고, 사용자는 멀쩡한 config 를 뒤진다 — 무음은 아니나 원인 귀속이 틀린 보고다.
#   doctor.sh 를 scripts/_internal 형제 없는 곳에 복사하면 그 호출이 rc=127 이 된다.
#   (pyyaml 불요 — 판정기가 애초에 실행되지 않는다.)
mkdir -p "$TMP/nojudge/scripts" "$TMP/nojudge/run/.specops"
cp "$SH" "$TMP/nojudge/scripts/doctor.sh"
_OUT=$(cd "$TMP/nojudge/run" && SPECOPS_ROOT=".specops" bash "$TMP/nojudge/scripts/doctor.sh" 2>&1)
gline6=$(printf '%s\n' "$_OUT" | grep '^| governance |')
if [ -z "$gline6" ]; then
  nope "T-gov.h" "governance 행 부재 — 단언 대상이 없다(공허 통과 방지)"
elif ! printf '%s' "$gline6" | grep -q '판정 불가'; then
  nope "T-gov.h" "행='$gline6' — 판정 실패가 판정 불가로 표기되지 않는다"
elif printf '%s' "$gline6" | grep -q '비활성'; then
  nope "T-gov.h" "행='$gline6' — 판정 실패를 '비활성' 으로 오귀속한다(config 를 뒤지게 만든다)"
else
  ok "T-gov.h 판정기 실행 실패 → '판정 불가' (비활성으로 오귀속 없음, Minor 1)"
fi
# 기계 계약(--json)에서도 status 가 warn 이 아니라 unknown 이어야 한다.
_JOUT=$(cd "$TMP/nojudge/run" && SPECOPS_ROOT=".specops" bash "$TMP/nojudge/scripts/doctor.sh" --json 2>&1)
if printf '%s' "$_JOUT" | jq -e '.checks[]|select(.id=="governance")|.status=="unknown"' >/dev/null 2>&1; then
  ok "T-gov.i --json status=unknown (기계 계약도 판정 불가를 구분)"
else
  nope "T-gov.i" "json='$_JOUT' — 판정 불가가 기계 계약에서 구분되지 않는다"
fi

# ── T-deps (AC-2·AC-7): 필수 의존 부재가 보인다 ──
_mkrepo "$TMP/deps"
_run "$TMP/deps"
dline=$(printf '%s\n' "$_OUT" | grep '^| deps |')
if printf '%s' "$dline" | grep -q '✅'; then
  ok "T-deps.a 의존 완비 → deps ✅ (AC-7 정상 경로)"
else
  nope "T-deps.a" "행='$dline' — 개발기는 jq·pyyaml 이 있어야 한다"
fi

# jq 만 제외한 최소 PATH — 통째 교체는 bash 자체를 못 찾는다(과거 실측 함정).
# python3 를 **포함**해야 "jq 단독 부재" 분기가 실제로 실행된다 — 빼면 jq+pyyaml 동시 부재가 되어
# 단독 분기(`미설치: jq — 거버넌스 비활성`)를 어느 테스트도 밟지 않는다(plan-review 3회차 Minor).
maskdir=$(mktemp -d) || exit 1
for b in bash sh cat grep sed awk date mkdir rm git dirname basename tr head tail wc cut sort uniq find printf ls stat python3; do
  bp=$(command -v "$b" 2>/dev/null) && ln -sf "$bp" "$maskdir/$b"
done
_MOUT=$(cd "$TMP/deps" && SPECOPS_ROOT=".specops" PATH="$maskdir" bash "$SH" 2>&1)
mline=$(printf '%s\n' "$_MOUT" | grep '^| deps |')
if printf '%s' "$mline" | grep -q '⚠️' && printf '%s' "$mline" | grep -q 'jq'; then
  ok "T-deps.b jq 가림 → deps ⚠️ + jq 지목 (AC-2)"
else
  nope "T-deps.b" "행='$mline' — jq 부재가 표면화되지 않는다"
fi
if printf '%s' "$mline" | grep -q '거버넌스 비활성'; then
  ok "T-deps.c jq 부재의 귀결(거버넌스 비활성)을 명시 (AC-2 Then)"
else
  nope "T-deps.c" "귀결 미표기 — 사용자가 심각도를 모른다"
fi

# ── T-deps.d/e (AC-7 3번째 케이스): python3 단독 가림 — jq 는 있다 ──
# 두 부재의 귀결이 다르다. jq 가 있으면 훅은 정상 동작하므로 "거버넌스 비활성" 은 거짓 보고다.
pydir=$(mktemp -d) || exit 1
for b in bash sh cat grep sed awk date mkdir rm git dirname basename tr head tail wc cut sort uniq find printf ls stat jq; do
  bp=$(command -v "$b" 2>/dev/null) && ln -sf "$bp" "$pydir/$b"
done
_POUT=$(cd "$TMP/deps" && SPECOPS_ROOT=".specops" PATH="$pydir" bash "$SH" 2>&1)
pline=$(printf '%s\n' "$_POUT" | grep '^| deps |')
if printf '%s' "$pline" | grep -q '⚠️' && printf '%s' "$pline" | grep -q '탐지 못 함'; then
  ok "T-deps.d python3 가림 → deps ⚠️ + 탐지 무력화 명시 (AC-7)"
else
  nope "T-deps.d" "행='$pline' — pyyaml 부재의 귀결이 표면화되지 않는다"
fi
# ★ 음성 단언은 대상이 존재할 때만 의미가 있다 — 행이 없으면 grep 불매치로 **공허 통과**한다.
# 현행 doctor 엔 deps 행이 아예 없으므로, 전제조건 없이 쓰면 RED 에서 거짓 PASS 가 난다
# (plan-review 3회차 실측: 예상 8건 vs 실제 7건의 원인이 정확히 이것이었다).
if [ -z "$pline" ]; then
  nope "T-deps.e" "deps 행 부재 — 음성 단언의 대상이 없다(공허 통과 방지)"
elif printf '%s' "$pline" | grep -q '거버넌스 비활성'; then
  nope "T-deps.e" "행='$pline' — jq 가 있는데 '거버넌스 비활성' 은 거짓 보고다"
else
  ok "T-deps.e pyyaml 단독 부재를 '거버넌스 비활성' 으로 오보하지 않음 (AC-7 구분)"
fi
rm -rf "$pydir"
rm -rf "$maskdir"

# ── T-effort (AC-1~3): effort_env — CLAUDE_CODE_EFFORT_LEVEL 설정 시 frontmatter effort 무력화 경고 ──
R="$TMP/reff"; _mkrepo "$R"
_effout() { _EO=$(cd "$R" && SPECOPS_ROOT=".specops" CLAUDE_CODE_EFFORT_LEVEL="$1" bash "$SH" "${@:2}" 2>&1); _ER=$?; }
_run "$R"
eline=$(printf '%s\n' "$_OUT" | grep '^| effort_env |')
last=$(printf '%s\n' "$_OUT" | grep -E '^\| [a-z_]+ \|' | tail -1)
if [ "$_RC" -eq 0 ] && printf '%s' "$eline" | grep -q '✅' && printf '%s' "$eline" | grep -q '미설정' \
   && printf '%s' "$last" | grep -q '^| effort_env '; then
  ok "T-effort.a env 미설정 → effort_env ✅ · 표 맨 끝(9번째) 행 (AC-1)"
else nope "T-effort.a" "rc=$_RC 행='$eline' 마지막='$last'"; fi
_effout high
eline=$(printf '%s\n' "$_EO" | grep '^| effort_env |')
if [ "$_ER" -eq 0 ] && printf '%s' "$eline" | grep -q '⚠️' && printf '%s' "$eline" | grep -q 'high' \
   && printf '%s' "$eline" | grep -q '무력화' && printf '%s' "$eline" | grep -q 'unset'; then
  ok "T-effort.b env=high → ⚠️ · 값 표시 · 무력화 · 조치(unset) · exit 0 (AC-2)"
else nope "T-effort.b" "rc=$_ER 행='$eline'"; fi
LONG=$(printf '%040d' 0)
_effout "$LONG"
eline=$(printf '%s\n' "$_EO" | grep '^| effort_env |')
if printf '%s' "$eline" | grep -q "=${LONG:0:24} " && ! printf '%s' "$eline" | grep -q "${LONG:0:25}"; then
  ok "T-effort.c 값은 앞 24자까지만 표시 (Q1)"
else nope "T-effort.c" "행='$eline'"; fi
_effout ""
eline=$(printf '%s\n' "$_EO" | grep '^| effort_env |')
if printf '%s' "$eline" | grep -q '✅'; then
  ok "T-effort.e 빈 값은 미설정과 동일(✅) (Q2)"
else nope "T-effort.e" "행='$eline'"; fi
for _lv in "" high; do
  _effout "$_lv" --json
  _wc=$(printf '%s' "$_EO" | jq -r '.warn_count' 2>/dev/null)
  _act=$(printf '%s' "$_EO" | jq -r '[.checks[]|select(.status!="ok")]|length' 2>/dev/null)
  if printf '%s' "$_EO" | jq -e '(.checks|length)==9 and .schema_version==1 and (.checks[-1].id=="effort_env")' >/dev/null 2>&1 \
     && [ "$_wc" = "$_act" ]; then
    ok "T-effort.d --json 9건·schema 1·마지막 effort_env·warn_count 정합 (env='${_lv:-빈}') (AC-3)"
  else nope "T-effort.d" "env='$_lv' wc=$_wc act=$_act"; fi
done
# 값에 구분자·개행이 있어도 표·JSON 행이 위조·분열되지 않고 `|` 는 단일 `/` 로 표시된다 (bash 3.2 에서도)
_effout $'x|y\nz'
if [ "$(printf '%s\n' "$_EO" | grep -c '^| effort_env |')" = "1" ] && printf '%s\n' "$_EO" | grep '^| effort_env |' | grep -qF '=x/y z '; then
  ok "T-effort.f 값의 | · 개행이 표 행을 위조·분열시키지 않음 (표)"
else nope "T-effort.f" "표='$(printf '%s\n' "$_EO" | grep -c '^| effort_env |')'행"; fi
_effout $'x|y\nz' --json
if printf '%s' "$_EO" | jq -e '(.checks|length)==9 and (.checks[-1].detail|test("=x/y z "))' >/dev/null 2>&1; then
  ok "T-effort.g 값의 | · 개행이 --json 필드를 오염시키지 않음 (checks 9건 유지)"
else nope "T-effort.g" "out=$_EO"; fi

# T-ds.d (AC-5): 문서 SoT 가 관할 축을 기술한다
DOC="$PLUGIN/commands/doctor.md"
grep -qE '^\|[[:space:]]*`git_hooks`[[:space:]]*\|' "$DOC" \
  && grep -q '플러그인 관할 밖' "$DOC" \
  && ok "T-ds.d 문서 SoT 가 하류 관할 판정을 기술" || nope "T-ds.d" "doc 미동기"

# T-ds.e 문구가 단위·한계를 말한다 (20261009) — 미채움은 "문서 수" · 하류 git_hooks 경고는 조치할 것이 없다
grep -q '미채움 문서 \${bad}개 (자리표시자가 남은 문서 수)' "$PLUGIN/scripts/doctor.sh" \
  && grep -q "scan-enrich-placeholders.sh' <문서>" "$PLUGIN/scripts/doctor.sh" \
  && grep -q '알려진 한계, 조치 없음' "$PLUGIN/scripts/doctor.sh" \
  && ok "T-ds.e memory 경고의 단위·가리킴 · git_hooks 경고의 한계 고지" || nope "T-ds.e" "doctor.sh 문구 누락"

finish
