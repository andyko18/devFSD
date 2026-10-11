#!/usr/bin/env bash
# specops-ko governance-capture 공용 함수 라이브러리 테스트
# source hooks/governance-lib.sh 후 detect_fid / read_recent_tool_events / log_friction / load_rules 검증
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
FIXTURES="$PLUGIN/scripts/tests/governance/fixtures"

# T1.a detect_fid: 최신 FID 헤더 반환
tmp=$(mktemp -d); cd "$tmp"; mkdir -p .specops
cp "$FIXTURES/session-progress-basic.md" .specops/session-progress.md
source "$PLUGIN/hooks/governance-lib.sh"
out=$(detect_fid); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "20260424-newest-feature" ]; then
  PASS=$((PASS+1)); echo "PASS T1.a detect_fid 최신 헤더"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.a (rc=$rc out=$out)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T1.b detect_fid: session-progress.md 부재 시 빈 문자열
tmp=$(mktemp -d); cd "$tmp"
out=$(detect_fid); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  PASS=$((PASS+1)); echo "PASS T1.b 부재 시 빈 문자열"
else
  FAIL=$((FAIL+1)); echo "FAIL T1.b (rc=$rc out=[$out])"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T2.a read_recent_tool_events: 최근 3 개 tool_use
out=$(read_recent_tool_events "$FIXTURES/transcripts/basic-tools.jsonl" 3); rc=$?
count=$(echo "$out" | grep -c '^{')
last_has_skill=$(echo "$out" | tail -1 | grep -c '"tool_name":"Skill"')
if [ "$rc" -eq 0 ] && [ "$count" -eq 3 ] && [ "$last_has_skill" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T2.a read_recent_tool_events 3건 + Skill 마지막"
else
  FAIL=$((FAIL+1)); echo "FAIL T2.a (rc=$rc count=$count skill=$last_has_skill)"
fi

# T3.a log_friction: FID 제공 → .specops/<FID>/friction-log.jsonl
tmp=$(mktemp -d); cd "$tmp"
source "$PLUGIN/hooks/governance-lib.sh"
log_friction "20260424-x" "R-1" 5 "git commit" 7
log_path=".specops/20260424-x/friction-log.jsonl"
if [ -f "$log_path" ] && jq -e '.rule_id == "R-1" and .principle == 5 and .fid == "20260424-x"' "$log_path" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T3.a log_friction FID 스코프"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.a"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T3.b log_friction: FID 빈 문자열 → .specops/friction-log.jsonl, fid=null
tmp=$(mktemp -d); cd "$tmp"
source "$PLUGIN/hooks/governance-lib.sh"
log_friction "" "R-2" 5 "gh pr create" 3
if [ -f ".specops/friction-log.jsonl" ] && jq -e '.fid == null and .rule_id == "R-2"' ".specops/friction-log.jsonl" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS T3.b log_friction 전역 fallback"
else
  FAIL=$((FAIL+1)); echo "FAIL T3.b"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T4.a load_rules: matcher + enabled 필터
out=$(load_rules "$FIXTURES/rules-test.jsonl" "posttool"); rc=$?
count=$(echo "$out" | grep -c '^{')
has_ra=$(echo "$out" | jq -e 'select(.id == "R-A")' >/dev/null 2>&1 && echo 1 || echo 0)
if [ "$rc" -eq 0 ] && [ "$count" -eq 1 ] && [ "$has_ra" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T4.a load_rules 필터"
else
  FAIL=$((FAIL+1)); echo "FAIL T4.a (rc=$rc count=$count has_ra=$has_ra)"
fi

# T-M1 log_friction: 잘못된 FID → rc=1, 파일 생성 없음
tmp=$(mktemp -d); cd "$tmp"
source "$PLUGIN/hooks/governance-lib.sh"
log_friction "../evil" "R-X" 5 "x" 0 2>/dev/null; rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "../evil" ] && [ ! -d ".specops/../evil" ]; then
  PASS=$((PASS+1)); echo "PASS T-M1 FID 경로 탈출 가드"
else
  FAIL=$((FAIL+1)); echo "FAIL T-M1 (rc=$rc)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T-M2 log_friction: 공백·특수문자 FID → rc=1
tmp=$(mktemp -d); cd "$tmp"
source "$PLUGIN/hooks/governance-lib.sh"
log_friction "bad fid" "R-X" 5 "x" 0 2>/dev/null; rc=$?
if [ "$rc" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T-M2 공백 FID 거부"
else
  FAIL=$((FAIL+1)); echo "FAIL T-M2 (rc=$rc)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T-M3 log_friction: 유효 FID (20260424-x) → rc=0 + 파일 생성 (회귀 방지)
tmp=$(mktemp -d); cd "$tmp"
source "$PLUGIN/hooks/governance-lib.sh"
log_friction "20260424-valid" "R-X" 5 "x" 0; rc=$?
if [ "$rc" -eq 0 ] && [ -f ".specops/20260424-valid/friction-log.jsonl" ]; then
  PASS=$((PASS+1)); echo "PASS T-M3 유효 FID 수용"
else
  FAIL=$((FAIL+1)); echo "FAIL T-M3 (rc=$rc)"
fi
cd "$PLUGIN"; rm -rf "$tmp"

# T-docs.a is_docs_only_change: .md만 staged → 면제(0)
td=$(mktemp -d); ( cd "$td" && git init -q && echo x > a.md && git add a.md
  source "$PLUGIN/hooks/governance-lib.sh"; is_docs_only_change ); rc=$?
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); echo "PASS T-docs.a .md-only 면제"; else FAIL=$((FAIL+1)); echo "FAIL T-docs.a"; fi
rm -rf "$td"
# T-docs.b 코드 혼합 → 비면제(1) [보안 불변식]
td=$(mktemp -d); ( cd "$td" && git init -q && echo x > a.md && echo y > b.sh && git add a.md b.sh
  source "$PLUGIN/hooks/governance-lib.sh"; is_docs_only_change ); rc=$?
if [ "$rc" -eq 1 ]; then PASS=$((PASS+1)); echo "PASS T-docs.b 코드혼합 비면제"; else FAIL=$((FAIL+1)); echo "FAIL T-docs.b 보안회귀!"; fi
rm -rf "$td"
# T-docs.c 빈 목록(변경 없음) → 비면제(1) [fail-safe]
td=$(mktemp -d); ( cd "$td" && git init -q && git commit -q --allow-empty -m init
  source "$PLUGIN/hooks/governance-lib.sh"; is_docs_only_change ); rc=$?
if [ "$rc" -eq 1 ]; then PASS=$((PASS+1)); echo "PASS T-docs.c 빈목록 fail-safe"; else FAIL=$((FAIL+1)); echo "FAIL T-docs.c"; fi
rm -rf "$td"
# T-docs.d staged=docs + unstaged tracked 코드 → 비면제(1) [git commit -am 우회 차단]
td=$(mktemp -d); ( cd "$td" && git init -q && echo "echo orig" > tracked.sh && git add tracked.sh && git commit -q -m init
  echo doc > README.md && git add README.md && echo "echo changed" > tracked.sh
  source "$PLUGIN/hooks/governance-lib.sh"; is_docs_only_change ); rc=$?
if [ "$rc" -eq 1 ]; then PASS=$((PASS+1)); echo "PASS T-docs.d staged-docs+unstaged-code 비면제(commit -am 우회 차단)"; else FAIL=$((FAIL+1)); echo "FAIL T-docs.d 보안우회!"; fi
rm -rf "$td"

# T-docs.e~i: is_docs_only_change PR-범위 fallback (R-2 비대칭 해소) — sandbox 함수 단위
_docs_case() {  # $1 expect_rc(0=allow/1=deny) $2 label $3 준비 함수 이름(명령 문자열을 받아 실행하지 않는다 · rc 97·98 = 준비 실패)
  local exp="$1" label="$2" setup="$3" rc
  ( source "$PLUGIN/hooks/governance-lib.sh"; C=commit
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
    sb=$(mktemp -d) || exit 2; cd "$sb" || exit 2
    declare -F "$setup" >/dev/null || exit 97; "$setup" || exit 98
    is_docs_only_change; rc=$?
    cd /; rm -rf "$sb"; exit $rc )
  rc=$?
  if [ "$rc" -eq "$exp" ]; then PASS=$((PASS+1)); echo "PASS $label"; else FAIL=$((FAIL+1)); echo "FAIL $label (rc=$rc exp=$exp)"; fi
}
_su_docs_e() { git init -q; git checkout -q -b main 2>/dev/null; echo b>b.md; git add b.md; git "$C" -q -m i; git checkout -q -b feat; echo c>CHANGELOG.md; git add CHANGELOG.md; git "$C" -q -m d; }
_docs_case 0 "T-docs.e docs-only PR(커밋완료) 면제" _su_docs_e
_su_docs_f() { git init -q; git checkout -q -b main 2>/dev/null; echo b>b.md; git add b.md; git "$C" -q -m i; git checkout -q -b feat; echo c>CHANGELOG.md; git add CHANGELOG.md; echo x>s.sh; git add s.sh; git "$C" -q -m m; }
_docs_case 1 "T-docs.f 코드혼합 PR 차단" _su_docs_f
_su_docs_g() { git init -q; git checkout -q -b odd 2>/dev/null; echo d>d.md; git add d.md; git "$C" -q -m i; git checkout -q -b f2; echo e>e.md; git add e.md; git "$C" -q -m m; }
_docs_case 1 "T-docs.g base없음 안전측 차단" _su_docs_g
_su_docs_h() { git init -q; echo m>m.md; git add m.md; }
_docs_case 0 "T-docs.h R-1 staged docs 면제" _su_docs_h
_su_docs_i() { git init -q; echo m>m.md; git add m.md; echo y>c.sh; git add c.sh; }
_docs_case 1 "T-docs.i R-1 코드혼합 차단" _su_docs_i
# T-docs.j~m: rename 우회 차단 (--no-renames — code→docs rename 을 docs-only 로 오인면제 차단)
_su_docs_j() { git init -q; echo x>a.sh; git add a.sh; git "$C" -q -m i; git mv a.sh a.md; }
_docs_case 1 "T-docs.j code→docs rename 차단(불변식)" _su_docs_j
_su_docs_k() { git init -q; echo x>a.md; git add a.md; git "$C" -q -m i; git mv a.md b.md; }
_docs_case 0 "T-docs.k docs→docs rename 무회귀" _su_docs_k
_su_docs_l() { git init -q; echo x>a.md; git add a.md; git "$C" -q -m i; git mv a.md a.sh; }
_docs_case 1 "T-docs.l docs→code rename 유지" _su_docs_l
_su_docs_m() { git init -q; git checkout -q -b main 2>/dev/null; echo x>a.sh; git add a.sh; git "$C" -q -m i; git checkout -q -b feat; git mv a.sh a.md; git "$C" -q -m r; }
_docs_case 1 "T-docs.m PR범위 code→docs rename 차단" _su_docs_m
# T-docs.n~q: design/아티팩트 면제 확장 (dogfood 20260716 — Phase 2.5 design 커밋(screens/*.html)이
#   .md 한정 whitelist 에 걸려 false-block → BYPASS 남발 유발. screens/ 미리보기·.specops/ 아티팩트는 실행 코드 아님)
_su_docs_n() { git init -q; mkdir screens; echo x>screens/login.html; echo s>screens/login.md; git add screens; }
_docs_case 0 "T-docs.n screens/*.html 설계 미리보기 면제" _su_docs_n
_su_docs_o() { git init -q; mkdir src; echo x>src/index.html; git add src; }
_docs_case 1 "T-docs.o screens/ 밖 .html 비면제(앱 코드 가능)" _su_docs_o
_su_docs_p() { git init -q; mkdir screens; echo x>screens/a.html; echo y>b.sh; git add screens b.sh; }
_docs_case 1 "T-docs.p screens/*.html + 코드 혼합 차단(불변식)" _su_docs_p
_su_docs_q() { git init -q; mkdir -p .specops/20260101-x; echo sha>.specops/20260101-x/review-base.sha; git add .specops; }
_docs_case 0 "T-docs.q .specops/ 아티팩트(비 .md 포함) 면제" _su_docs_q

# T-docs.r~: _commit_scope_is_staged 분류 (20260813-r1-docs-only-scope)
#   실행 명령에 git+commit 리터럴을 직접 쓰면 R-1 훅이 프로브 자체를 차단하므로 변수로 조립한다.
#   헬퍼명은 `_clsf_case` 다 — 아래 `_scope_case`(:은 is_docs_only_audit_scope 용 4인자)와 이름이
#   겹치면 정의 순서에 기대는 그림자(shadowing)가 생겨, 이후 누가 케이스를 추가할 때 조용히 깨진다.
_G=$(printf 'g%sit' ''); _C=$(printf 'c%sommit' '')
_clsf_case() {  # $1 expect_rc  $2 label  $3 cmd
  ( source "$PLUGIN/hooks/governance-lib.sh"; _commit_scope_is_staged "$3" ); local rc=$?
  if [ "$rc" -eq "$1" ]; then PASS=$((PASS+1)); echo "PASS $2 (rc=$rc)"
  else FAIL=$((FAIL+1)); echo "FAIL $2 rc=$rc 기대=$1"; fi
}
_clsf_case 0 "T-docs.r plain -m 축소"        "$_G $_C -m 'docs: x'"
_clsf_case 0 "T-docs.s -q -m 축소"           "$_G $_C -q -m 'x'"
_clsf_case 0 "T-docs.t --message= 축소"      "$_G $_C --message=x"
_clsf_case 1 "T-docs.u -am 보수"             "$_G $_C -am 'x'"
_clsf_case 1 "T-docs.v -a -m 보수"           "$_G $_C -a -m 'x'"
_clsf_case 1 "T-docs.w --all 보수"           "$_G $_C --all -m 'x'"
_clsf_case 0 "T-docs.t2 -q -F - heredoc 축소(AC-7)" "$_G $_C -q -F - <<'HD'
docs: x
HD"
_clsf_case 1 "T-docs.x compound && 보수"     "$_G add -A && $_G $_C -m 'x'"
_clsf_case 1 "T-docs.y compound ; 보수"      "$_G add -A ; $_G $_C -m 'x'"
_clsf_case 1 "T-docs.y2 compound | 보수"     "$_G log | $_G $_C -m 'x'"
_clsf_case 1 "T-docs.y3 compound || 보수"    "$_G add -A || $_G $_C -m 'x'"
_clsf_case 1 "T-docs.z 경로인자 보수"        "$_G $_C README.md"
_clsf_case 1 "T-docs.aa --amend 보수"        "$_G $_C --amend -m 'x'"
_clsf_case 1 "T-docs.ab git -c 보수"         "$_G -c user.email=a@b $_C -m 'x'"
_clsf_case 1 "T-docs.ac --only 보수"         "$_G $_C --only README.md"
_clsf_case 1 "T-docs.ad -s signoff 보수"     "$_G $_C -s -m 'x'"
_clsf_case 1 "T-docs.ae env 접두 보수"       "FOO=1 $_G $_C -m 'x'"
_clsf_case 1 "T-docs.af gh pr create 보수"   "gh pr create --title x"
_clsf_case 1 "T-docs.ag 빈 문자열 보수"      ""
# T-docs.am~as: 개행 분리 compound (Phase B false-allow — 개행은 `;` 와 동등한 명령 분리자다.
#   첫 줄만 보고 잔여 줄을 무검증 폐기하면 C1·C2 가 둘째 줄부터 적용되지 않는다)
_clsf_case 1 "T-docs.am 개행 compound(첫줄 안전형) 보수" "$_G $_C -m 'docs'
$_G add -A
$_G $_C -am 'code'"
_clsf_case 1 "T-docs.an 개행 compound(첫줄 add) 보수"    "$_G add -A
$_G $_C -m 'x'"
_clsf_case 1 "T-docs.ao 첫줄 << 없는 2줄 보수"           "$_G $_C -m 'x'
ls"
_clsf_case 1 "T-docs.ap heredoc 종결자 뒤 추가명령 보수" "$_G $_C -q -F - <<'HD'
docs: x
HD
$_G add -A"
_clsf_case 0 "T-docs.aq 후행 개행만 축소 유지"           "$_G $_C -m 'x'
"
_clsf_case 0 "T-docs.ar heredoc <<- 탭 종결자 축소"      "$_G $_C -q -F - <<-HD
	docs: x
	HD"
_clsf_case 0 "T-docs.as 멀티라인 인용 -m 축소(false-block 방지)" "$_G $_C -m 'feat: x

body'"

# T-docs.pre.*: C-1 안전 prelude 소비 (20260910-commit-scope-prelude)
_HERE=$(pwd)
_clsf_case 0 "T-docs.pre.a cd 절대(현재 repo) 선행 축소"  "cd $_HERE
$_G $_C -m 'docs: x'"
_clsf_case 0 "T-docs.pre.b cd 상대 선행 축소"             "cd skills
$_G $_C -m 'docs: x'"
# `$PWD/` 접두 벗김 경로(:cd 분기 `"$PWD"/*`)를 잠근다 — 이 줄을 지우면 그 밖의 `/*` 규칙에
#   걸려 보수로 떨어진다(false-block 방향, MD 변이 실측). 한글·공백 repo 경로 사용자의 회수율 축.
_clsf_case 0 "T-docs.pre.a2 cd \$PWD/하위 선행 축소"      "cd $_HERE/skills
$_G $_C -m 'docs: x'"
_clsf_case 0 "T-docs.pre.c VAR= 선행 축소"                "MSG=/tmp/m.txt
$_G $_C -F \"\$MSG\""
_clsf_case 0 "T-docs.pre.d cd+VAR 2줄 선행 축소"          "cd $_HERE
MSG=/tmp/m.txt
$_G $_C -F \"\$MSG\""
_clsf_case 1 "T-docs.pre.e cd .. 보수"                    "cd ..
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.f cd - 보수"                     "cd -
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.g bare cd 보수"                  "cd
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.h cd 타repo 절대 보수"           "cd /tmp/other-repo
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.i VAR=명령치환 보수"             "MSG=\$(pwd)
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.i2 VAR=백틱 보수"                "MSG=\`pwd\`
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.j cd 다중토큰 보수"              "cd a b
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.k cd 뒤 add -A 보수(false-open 축)" "cd $_HERE
$_G add -A
$_G $_C -m x"
_clsf_case 0 "T-docs.pre.l prelude 8줄 축소"              "$(for i in 1 2 3 4 5 6 7 8; do echo "V$i=$i"; done)
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.m prelude 9줄 보수(상한)"        "$(for i in 1 2 3 4 5 6 7 8 9; do echo "V$i=$i"; done)
$_G $_C -m x"
# 인용 껍데기·변수 경로 — Critical-1 실측으로 추가된 false-open 축
_clsf_case 1 "T-docs.pre.n cd 인용 타repo 보수"           "cd \"/tmp/other-repo\"
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.o VAR= 뒤 cd \$VAR 보수"         "DIR=/tmp/other-repo
cd \$DIR
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.p cd 빈인용 보수"                "cd \"\"
$_G $_C -m x"
# 역슬래시 **1개**. 앞선 `*'\\'*` 패턴은 2개만 잡아 이 줄이 안전으로 새어나갔다(실측 rc=0).
_clsf_case 1 "T-docs.pre.p2 VAR= 단일 역슬래시 보수"      "VAR=a\\b
$_G $_C -m x"
# spec §3 주 시나리오 — prelude ↔ heredoc 멀티라인 검사 상호작용 (current-state §5 회귀 표면)
_clsf_case 0 "T-docs.pre.q cd + heredoc -F - 축소"        "cd $_HERE
$_G $_C -q -F - <<'HD'
docs: x
HD"
_clsf_case 1 "T-docs.pre.r cd + heredoc 뒤 add -A 보수"   "cd $_HERE
$_G $_C -q -F - <<'HD'
docs: x
HD
$_G add -A"
# T-docs.pre.s: `*=*` 분기의 `[ -z "$rest" ] || return 1` 를 잠근다 (Phase C Important-1 실측 —
#   그 줄을 지운 변이에서 test-lib 140/140 이 그대로 생존했고, `VAR=x git add -A` ⏎ `git commit`
#   이 축소 승인(false-open)으로 뚫렸다). 기존 T-docs.ae 는 **단일 줄**이라 prelude 루프에
#   진입조차 하지 않아 이 축을 보지 못한다 — 반드시 2줄이어야 판별력이 생긴다.
_clsf_case 1 "T-docs.pre.s env 접두+명령 prelude 보수(false-open 축)" "VAR=x $_G add -A
$_G $_C -m x"
# T-docs.pre.t·u: prelude 가 약속한 불변식(어느 git · 어디서)을 직접 깨는 두 이름 (Important-3,
#   사용자 결정). 수정 전에는 둘 다 안전 prelude 로 통과해 `PATH=/tmp/evil` ⏎ 커밋이 rc=0 이었다.
_clsf_case 1 "T-docs.pre.t PATH= 선행 보수(어느 git 인지 변조)"  "PATH=/tmp/evil
$_G $_C -m x"
_clsf_case 1 "T-docs.pre.u CDPATH= 선행 보수(cd 목적지 변조)"    "CDPATH=/tmp
cd other-repo
$_G $_C -m x"

# T-docs.ah~ak: is_docs_only_change 스코프 분기 (sandbox — staged=docs + unstaged 코드)
_scope_sandbox() {  # $1 expect_rc  $2 label  $3 cmd(빈 문자열이면 무인자 호출)
  local td rc; td=$(mktemp -d)
  ( cd "$td" && git init -q \
    && echo "echo orig" > tracked.sh && git add tracked.sh \
    && git -c user.email=e@t -c user.name=t commit -q -m init \
    && echo doc > README.md && git add README.md \
    && echo "echo changed" > tracked.sh \
    && source "$PLUGIN/hooks/governance-lib.sh" \
    && if [ -n "$3" ]; then is_docs_only_change "$3"; else is_docs_only_change; fi ); rc=$?
  rm -rf "$td"
  if [ "$rc" -eq "$1" ]; then PASS=$((PASS+1)); echo "PASS $2 (rc=$rc)"
  else FAIL=$((FAIL+1)); echo "FAIL $2 rc=$rc 기대=$1"; fi
}
_scope_sandbox 0 "T-docs.ah plain 커밋 → 면제(AC-1)"   "$_G $_C -m 'docs'"
_scope_sandbox 1 "T-docs.ai -am → 비면제(AC-2)"        "$_G $_C -am 'x'"
_scope_sandbox 1 "T-docs.aj compound → 비면제(AC-3)"   "$_G add -A && $_G $_C -m 'x'"
_scope_sandbox 1 "T-docs.ak 무인자 → 현행 보존(AC-5)"  ""
# AC-3 은 개행 분리 compound 도 포함한다 — 연산자 4변형(`&&`·`;`·`|`·`||`)만 잠그면 개행이 뚫린다.
# T-docs.au~aw: 명령치환 토큰 보수화 (Phase C Important-2 — 20260813)
#   _strip_quoted_strings 는 `$(`·백틱을 "실제 실행됨" 이유로 보존하는데, C3 의 skip 이 그 보존을
#   무검사 소비하던 구멍. 치환은 커밋 前 실행이라 staged 를 바꿀 수 있다.
_clsf_case 1 "T-docs.au 단일토큰 명령치환 -m 보수"   "$_G $_C -m \"\$(ga)\""
_clsf_case 1 "T-docs.av 백틱 치환 -m 보수"           "$_G $_C -m \"\`ga\`\""
_clsf_case 1 "T-docs.aw --file= 치환 보수"           "$_G $_C --file=\"\$(f)\""

_scope_sandbox 1 "T-docs.at 개행 compound → 비면제(AC-3)" "$_G $_C -m 'docs'
$_G add -A
$_G $_C -am 'code'"

# T-docs.al: staged 에 코드 혼합이면 형태 무관 비면제 (AC-6 — 매처 불변식)
_td=$(mktemp -d)
( cd "$_td" && git init -q && echo x > a.md && echo y > b.sh && git add a.md b.sh
  source "$PLUGIN/hooks/governance-lib.sh"; is_docs_only_change "$_G $_C -m 'x'" ); _rc=$?
rm -rf "$_td"
if [ "$_rc" -eq 1 ]; then PASS=$((PASS+1)); echo "PASS T-docs.al staged 코드혼합 비면제(AC-6)"
else FAIL=$((FAIL+1)); echo "FAIL T-docs.al 보안회귀! rc=$_rc"; fi

# T-scope.a~d: is_docs_only_audit_scope — posttool 감사 스코프 (방금 액션 범위, 20260718-posttool-audit-silence)
_scope_case() {  # $1 expect_rc $2 label $3 rule_id $4 준비 함수 이름(rc 97·98 = 준비 실패)
  local exp="$1" label="$2" rid="$3" setup="$4" rc
  ( source "$PLUGIN/hooks/governance-lib.sh"; C=commit
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
    sb=$(mktemp -d) || exit 3; cd "$sb" || exit 3
    declare -F "$setup" >/dev/null || exit 97; "$setup" || exit 98
    is_docs_only_audit_scope "$rid"; rc=$?
    cd /; rm -rf "$sb"; exit $rc )
  rc=$?
  if [ "$rc" -eq "$exp" ]; then PASS=$((PASS+1)); echo "PASS $label"; else FAIL=$((FAIL+1)); echo "FAIL $label (rc=$rc exp=$exp)"; fi
}
_su_scope_a() { git init -q; mkdir .specops; echo p>.specops/session-progress.md; echo x>a.sh; git add -A; git "$C" -q -m i; echo y>a.sh; git add a.sh; git "$C" -q -m c; echo d>>.specops/session-progress.md; }
_scope_case 1 "T-scope.a R-1 코드 커밋 + .specops 잔여 dirty → 비면제(감사)" R-1 _su_scope_a
_su_scope_b() { git init -q; echo x>a.sh; git add -A; git "$C" -q -m i; echo d>R.md; git add R.md; git "$C" -q -m d; echo z>b.sh; }
_scope_case 0 "T-scope.b R-1 docs-only 커밋 + 코드 dirt → 면제(커밋 기준)" R-1 _su_scope_b
_su_scope_c() { git init -q; echo x>a.sh; git add -A; git "$C" -q -m i; }
_scope_case 1 "T-scope.c R-1 최초 커밋(HEAD~1 부재) → 비면제(fail-safe)" R-1 _su_scope_c
_su_scope_d() { git init -q; git checkout -q -b main 2>/dev/null; echo b>b.md; git add b.md; git "$C" -q -m i; git checkout -q -b feat; echo c>c.sh; git add c.sh; git "$C" -q -m f; echo d>>b.md; }
_scope_case 1 "T-scope.d R-2 base...HEAD 코드 포함 → 비면제(감사)" R-2 _su_scope_d

# T-base.a~c: _detect_base_branch 직접 단위 (main 우선 / master 차선 / 둘 다 부재 실패) [code-review Minor]
_base_case() {  # $1 expect_out("" = 실패) $2 label $3 준비 함수 이름(준비가 실패하면 SETUP-FAILED 를 내서 기대값 "" 와 구분한다)
  local exp="$1" label="$2" setup="$3" out
  out=$( ( source "$PLUGIN/hooks/governance-lib.sh"; C=commit
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
    sb=$(mktemp -d) || exit 2; cd "$sb" || exit 2
    declare -F "$setup" >/dev/null && "$setup" >/dev/null || { echo "SETUP-FAILED"; cd /; rm -rf "$sb"; exit 9; }
    _detect_base_branch 2>/dev/null
    cd /; rm -rf "$sb" ) )
  if [ "$out" = "$exp" ]; then PASS=$((PASS+1)); echo "PASS $label"; else FAIL=$((FAIL+1)); echo "FAIL $label (out='$out' exp='$exp')"; fi
}
_su_base_a() { git init -q; git checkout -q -b main 2>/dev/null; echo a>a.md; git add a.md; git "$C" -q -m i; }
_base_case "main"   "T-base.a main 우선" _su_base_a
_su_base_b() { git init -q; git checkout -q -b master 2>/dev/null; echo a>a.md; git add a.md; git "$C" -q -m i; }
_base_case "master" "T-base.b master 차선" _su_base_b
_su_base_c() { git init -q; git checkout -q -b dev 2>/dev/null; echo a>a.md; git add a.md; git "$C" -q -m i; }
_base_case ""       "T-base.c 둘 다 부재 실패" _su_base_c
# T-base.d~e: 로컬 main 이 낡고 origin/main 이 HEAD 에 더 가까우면 origin/main (20261008 — 낡은 기준이 PR 범위·위험도를 부풀렸다)
_su_base_d() { git init -q; git checkout -q -b main 2>/dev/null; echo a>a.md; git add a.md; git "$C" -q -m i; git checkout -q -b up; echo b>b.md; git add b.md; git "$C" -q -m u; git update-ref refs/remotes/origin/main HEAD; git checkout -q -b feat; echo c>c.md; git add c.md; git "$C" -q -m f; }
_base_case "origin/main" "T-base.d 낡은 로컬 main → origin/main(HEAD 에 더 가까움)" _su_base_d
_su_base_e() { git init -q; git checkout -q -b main 2>/dev/null; echo a>a.md; git add a.md; git "$C" -q -m i; git update-ref refs/remotes/origin/main HEAD; git checkout -q -b feat; echo c>c.md; git add c.md; git "$C" -q -m f; }
_base_case "main"        "T-base.e 로컬 main 과 origin/main 이 같으면 로컬 우선" _su_base_e

# T-symlink: log_friction — .specops 가 symlink 면 쓰기 거부 (path-escape 차단)
tmp=$(mktemp -d); real=$(mktemp -d); cd "$tmp"; ln -s "$real" .specops
log_friction "20260424-sl" "R-1" 5 "x" 7 2>/dev/null
if [ ! -e "$real/20260424-sl/friction-log.jsonl" ]; then
  PASS=$((PASS+1)); echo "PASS T-symlink log_friction symlink 거부"
else
  FAIL=$((FAIL+1)); echo "FAIL T-symlink (REAL 타겟 write-through 누출)"
fi
cd "$PLUGIN"; rm -rf "$tmp" "$real"

# T-symlink-file: friction-log.jsonl *파일* 자체가 symlink 면 append 거부.
# 디렉토리(.specops/<fid>)는 정상이라 _specops_fid_dir_safe 통과 — 파일 symlink 는 별개 표면.
# 악성 repo clone 후 .specops/<fid>/friction-log.jsonl → 외부 파일 symlink 시 >> 따라감 차단.
tmp=$(mktemp -d); real=$(mktemp -d); cd "$tmp"
mkdir -p ".specops/20260630-fsl"
ln -s "$real/leak.jsonl" ".specops/20260630-fsl/friction-log.jsonl"
log_friction "20260630-fsl" "R-1" 5 "x" 7 2>/dev/null
log_friction_sev "20260630-fsl" "R-1" 5 "x" 7 "block" 2>/dev/null
if [ ! -e "$real/leak.jsonl" ]; then
  PASS=$((PASS+1)); echo "PASS T-symlink-file friction-log 파일 symlink 거부"
else
  FAIL=$((FAIL+1)); echo "FAIL T-symlink-file (파일 symlink write-through 누출)"
fi
cd "$PLUGIN"; rm -rf "$tmp" "$real"

# T-hd _strip_heredoc_bodies 단위 (20260713-heredoc-false-block)
#   문자열 in/out 대조 — heredoc **본문만** 제거되는가. 정규식은 무변경, **입력만 전처리**한다.
cd "$PLUGIN" || exit 1
source "$PLUGIN/hooks/governance-lib.sh"

# T-hd.1 (AC-2) 본문만 제거 — 시작 줄·종료 줄·종료 후 명령은 유지
_in=$'cat > f.md <<EOF\ngit commit -m x\nEOF\nls -la'
_exp=$'cat > f.md <<EOF\nEOF\nls -la'
_got=$(_strip_heredoc_bodies "$_in")
if [ "$_got" = "$_exp" ]; then
  PASS=$((PASS+1)); echo "PASS T-hd.1 (AC-2) heredoc 본문만 제거"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hd.1 (AC-2) — got: $(printf '%s' "$_got" | tr '\n' '|')"
fi

# T-hd.2 (AC-R-1 identity) heredoc 없는 입력은 **바이트 동일** — 기존 51 케이스 보호의 근거
_in='cd /tmp && git commit -m x'
_got=$(_strip_heredoc_bodies "$_in")
if [ "$_got" = "$_in" ]; then
  PASS=$((PASS+1)); echo "PASS T-hd.2 (AC-R-1) heredoc 부재 입력 무변경(identity)"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hd.2 identity 깨짐 — got: $_got"
fi

# T-hd.3 (AC-5) 셸 실행자 heredoc → 본문 **제외 안 함**(passthrough). F-3 표면 불변.
_in=$'bash <<EOF\ngit commit -m x\nEOF'
_got=$(_strip_heredoc_bodies "$_in")
if [ "$_got" = "$_in" ]; then
  PASS=$((PASS+1)); echo "PASS T-hd.3 (AC-5) bash <<EOF 본문 유지(passthrough)"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hd.3 (AC-5) 실행자 본문이 제거됨 — got: $(printf '%s' "$_got" | tr '\n' '|')"
fi

# T-hd.4 (AC-8 fail-safe) 미종료 heredoc → **원본 반환**(차단 우세로 후퇴)
_in=$'cat > f.md <<EOF\ngit commit -m x'
_got=$(_strip_heredoc_bodies "$_in")
if [ "$_got" = "$_in" ]; then
  PASS=$((PASS+1)); echo "PASS T-hd.4 (AC-8) 미종료 heredoc → 원본 반환(fail-safe)"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hd.4 (AC-8) 미종료 heredoc 본문이 제거됨 — got: $(printf '%s' "$_got" | tr '\n' '|')"
fi

# T-hd.5 (AC-6) python3 heredoc → 본문 제외 (셸 명령 아님)
_in=$'python3 <<EOF\ngit commit -m x\nEOF'
_exp=$'python3 <<EOF\nEOF'
_got=$(_strip_heredoc_bodies "$_in")
if [ "$_got" = "$_exp" ]; then
  PASS=$((PASS+1)); echo "PASS T-hd.5 (AC-6) python3 본문 제외"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hd.5 (AC-6) — got: $(printf '%s' "$_got" | tr '\n' '|')"
fi

# ── T-task.* : _infer_commit_task 명시 선언 우선 (20260807 실사용 검증 12호) ──
# 구 구현은 `Task:...|T[0-9]+` 교대를 한 번에 스캔해 **문서 순서상 먼저 나온 쪽**을 집었다.
#   제목 "출력층 (T1~T4 집약)" + 본문 `Task: T4` 인 커밋이 T1 으로 오인돼,
#   훅이 deny 메시지로 안내한 **receipt 탈출구가 실제로는 열리지 않았다**.
#   FID 20260807-specops-doctor 실사용 중 실측 — 합성 픽스처로는 안 나온 결함.
_infer_case() {  # $1=라벨 $2=커밋메시지 $3=기대
  local got; got=$(_infer_commit_task "$2")
  if [ "$got" = "$3" ]; then
    PASS=$((PASS+1)); echo "PASS $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL $1 — got '$got' want '$3'"
  fi
}
_infer_case "T-task.1 명시 Task: 가 제목 산문보다 우선" $'feat: 출력층 (T1~T4 집약)\n\nTask: T4' T4
_infer_case "T-task.2 명시 선언 단독" $'fix: something\n\nTask: T7' T7
_infer_case "T-task.3 산문 T# fallback 보존" 'feat: T3 구현' T3
_infer_case "T-task.4 선언·산문 모두 없으면 빈값" 'feat: 그냥 커밋' ''

# T-cls.a~h: _commit_scope_class 분류 (20260813-friction-staged-record)
_cls_case() {  # $1 expect  $2 label  $3 files(인자, 생략 시 무인자 호출)
  local got
  if [ "$#" -ge 3 ]; then got=$( ( source "$PLUGIN/hooks/governance-lib.sh"; _commit_scope_class "$3" ) )
  else got=$( ( source "$PLUGIN/hooks/governance-lib.sh"; _commit_scope_class ) ); fi
  if [ "$got" = "$1" ]; then PASS=$((PASS+1)); echo "PASS $2 ($got)"
  else FAIL=$((FAIL+1)); echo "FAIL $2 got=$got 기대=$1"; fi
}
_cls_case docs-only "T-cls.a .md 단독"        "README.md"
_cls_case code      "T-cls.b .md+.sh 혼합"    "$(printf 'README.md\napp.sh')"
_cls_case empty     "T-cls.c 빈 목록"          ""
_cls_case docs-only "T-cls.d .specops/* 면제"  ".specops/x/friction-log.jsonl"
_cls_case docs-only "T-cls.e screens/*.html"   "screens/a.html"
_cls_case code      "T-cls.f src/*.html 비면제" "src/a.html"

# T-cls.g~h: 무인자 자체 계산 (sandbox)
_cls_sandbox() {  # $1 expect  $2 label  $3 staged(docs|code|none)
  # ★ bash 3.2 파서 버그 회피: `$( … case … docs) … )` 는 3.2.57 에서 `;;` syntax error 다(실측).
  #   패턴을 괄호형 `(docs)` 로 쓰면 통과하지만, 더 안전하게 case 를 $() **밖**으로 뺀다.
  local td got; td=$(mktemp -d)
  ( cd "$td" && git init -q && echo x > seed.md && git add seed.md \
    && git -c user.email=e@t -c user.name=t commit -q -m init ) >/dev/null 2>&1
  case "$3" in
    (docs) echo y > "$td/README.md"; git -C "$td" add README.md ;;
    (code) echo y > "$td/app.sh";    git -C "$td" add app.sh ;;
    (*) : ;;
  esac
  got=$( cd "$td" && source "$PLUGIN/hooks/governance-lib.sh" && _commit_scope_class )
  rm -rf "$td"
  if [ "$got" = "$1" ]; then PASS=$((PASS+1)); echo "PASS $2 ($got)"
  else FAIL=$((FAIL+1)); echo "FAIL $2 got=$got 기대=$1"; fi
}
_cls_sandbox docs-only "T-cls.g 무인자 staged=docs" docs
_cls_sandbox code      "T-cls.h 무인자 staged=code" code
_cls_sandbox empty     "T-cls.i 무인자 staged=none" none

# T-acls.a~h: _audit_scope_class — posttool 감사 스코프 분류 (20260814-friction-scope-posttool)
#   ★ is_docs_only_audit_scope 와 **같은 범위**(R-1 HEAD~1..HEAD / R-2 base...HEAD)를 쓰되
#     boolean 이 아니라 분류를 낸다. _commit_scope_class(staged 기준)는 posttool 이 커밋 **후**
#     발화하므로 쓸 수 없다 — --cached 가 비어 empty 로 오분류된다.
#   ★ 기대값 "" 는 **무출력 = 판정불가**다. 'empty'(커밋 범위가 실제로 빔)와 다른 축이다.
_acls_case() {  # $1 expect(""=무출력)  $2 label  $3 rule_id  $4 준비 함수 이름
  local td got
  td=$(mktemp -d) || { FAIL=$((FAIL+1)); echo "FAIL $2 mktemp"; return; }
  ( cd "$td" && declare -F "$4" >/dev/null && "$4" ) >/dev/null 2>&1 \
    || { FAIL=$((FAIL+1)); echo "FAIL $2 — 준비 실패($4)"; rm -rf "$td"; return; }
  got=$( cd "$td" && source "$PLUGIN/hooks/governance-lib.sh" && _audit_scope_class "$3" )
  rm -rf "$td"
  if [ "$got" = "$1" ]; then PASS=$((PASS+1)); echo "PASS $2 (${got:-<무출력>})"
  else FAIL=$((FAIL+1)); echo "FAIL $2 got=${got:-<무출력>} 기대=${1:-<무출력>}"; fi
}
_GC='-c user.email=e@t -c user.name=t'
_su_acls_a() {
  git init -q; echo x > seed.md; git add seed.md; git $_GC commit -q -m init;
  echo y > a.sh; git add a.sh; git $_GC commit -q -m code
}
_acls_case code "T-acls.a R-1 코드 커밋" R-1 _su_acls_a
_su_acls_b() {
  git init -q; echo x > seed.md; git add seed.md; git $_GC commit -q -m init;
  echo y > R.md; git add R.md; git $_GC commit -q -m docs
}
_acls_case docs-only "T-acls.b R-1 docs-only 커밋" R-1 _su_acls_b
_su_acls_c() {
  git init -q; echo x > seed.md; git add seed.md; git $_GC commit -q -m init;
  echo y > a.sh; git add a.sh; git $_GC commit -q -m code; echo z > b.md
}
_acls_case code "T-acls.c R-1 working-tree dirt 무영향" R-1 _su_acls_c
_su_acls_d() { git init -q; echo x > a.sh; git add a.sh; git $_GC commit -q -m init; }
_acls_case "" "T-acls.d R-1 최초 커밋(HEAD~1 부재) → 판정불가" R-1 _su_acls_d
_su_acls_e() {
  git init -q; echo x > seed.md; git add seed.md; git $_GC commit -q -m init;
  git $_GC commit -q --allow-empty -m nothing
}
_acls_case empty "T-acls.e R-1 빈 커밋 → empty(판정불가 아님)" R-1 _su_acls_e
_su_acls_f() {
  git init -q; git checkout -q -b main 2>/dev/null; echo b > b.md; git add b.md;
  git $_GC commit -q -m init; git checkout -q -b feat; echo c > c.sh; git add c.sh;
  git $_GC commit -q -m feat
}
_acls_case code "T-acls.f R-2 base...HEAD 코드" R-2 _su_acls_f
_su_acls_g() {
  git init -q; git checkout -q -b solo 2>/dev/null; echo b > b.md; git add b.md;
  git $_GC commit -q -m init
}
_acls_case "" "T-acls.g R-2 base 부재 → 판정불가" R-2 _su_acls_g
_su_acls_h() { git init -q; echo x > a.sh; git add a.sh; git $_GC commit -q -m init; }
_acls_case "" "T-acls.h 미지원 rule_id(R-3) → 판정불가" R-3 _su_acls_h

# T-cls.j~m: log_friction_sev scope_class 선택 인자 (AC-5·AC-6)
_td=$(mktemp -d)
( cd "$_td" && mkdir -p .specops
  source "$PLUGIN/hooks/governance-lib.sh"
  log_friction_sev "20260101-cls" "R-1" 5 "snip-a" 7 "block" "code"
  log_friction_sev "20260101-cls" "R-1" 5 "snip-b" 7 "block" )
_L="$_td/.specops/20260101-cls/friction-log.jsonl"
# j: 7번째 인자 전달 시 기록
if jq -e 'select(.evidence_snippet=="snip-a" and .scope_class=="code")' "$_L" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T-cls.j scope_class 기록"
else FAIL=$((FAIL+1)); echo "FAIL T-cls.j scope_class 미기록"; fi
# k: 인자 부재 시 필드 자체가 없어야 한다 (빈 문자열 기록 금지 — AC-6)
if jq -e 'select(.evidence_snippet=="snip-b" and (has("scope_class")|not))' "$_L" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T-cls.k 인자 부재 → 필드 생략"
else FAIL=$((FAIL+1)); echo "FAIL T-cls.k 필드 생략 안 됨"; fi
# l: 기존 7필드 불변 (AC-5)
if [ "$(jq -r 'select(.evidence_snippet=="snip-b")|keys|join(",")' "$_L")" \
     = "evidence_snippet,fid,principle,rule_id,severity,transcript_offset,ts" ]; then
  PASS=$((PASS+1)); echo "PASS T-cls.l 기존 7필드 불변"
else FAIL=$((FAIL+1)); echo "FAIL T-cls.l 필드 구성 변경됨"; fi
rm -rf "$_td"

# m: dedup 키 불변 — scope_class 만 달라도 중복 제거 (AC-5)
_td=$(mktemp -d)
( cd "$_td" && mkdir -p .specops
  source "$PLUGIN/hooks/governance-lib.sh"
  log_friction_sev "20260101-dd" "R-1" 5 "same" 7 "block" "code"
  log_friction_sev "20260101-dd" "R-1" 5 "same" 7 "block" "docs-only" )
_n=$(grep -c . "$_td/.specops/20260101-dd/friction-log.jsonl" 2>/dev/null || echo 0)
rm -rf "$_td"
if [ "$_n" -eq 1 ]; then PASS=$((PASS+1)); echo "PASS T-cls.m dedup 키 불변 (1행)"
else FAIL=$((FAIL+1)); echo "FAIL T-cls.m dedup 깨짐 (${_n}행)"; fi

# T-cls.n2: log_friction(6번째 인자) 도 동일 동작 + 전역 fallback 보존 (AC-5·AC-7)
_td=$(mktemp -d)
( cd "$_td" && mkdir -p .specops
  source "$PLUGIN/hooks/governance-lib.sh"
  log_friction ""             "BYPASS-ENV" 1 "glob-a" 0 "docs-only"   # fid 빈값 → 전역 파일
  log_friction "20260101-lf"  "BYPASS-ENV" 1 "fid-a"  0 )             # 인자 부재 → 필드 생략
if jq -e 'select(.evidence_snippet=="glob-a" and .scope_class=="docs-only")' \
     "$_td/.specops/friction-log.jsonl" >/dev/null 2>&1 \
   && jq -e 'select(.evidence_snippet=="fid-a" and (has("scope_class")|not))' \
     "$_td/.specops/20260101-lf/friction-log.jsonl" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T-cls.n2 log_friction 선택 인자 + 전역 fallback 보존"
else FAIL=$((FAIL+1)); echo "FAIL T-cls.n2 log_friction 확장 실패"; fi
rm -rf "$_td"

# T-cls.o: 분류 불가(git 아님) 상황에서도 기록은 성립하고 필드만 생략된다 (AC-6)
_td=$(mktemp -d)   # git init 하지 않음 → git diff 실패
( cd "$_td" && mkdir -p .specops
  source "$PLUGIN/hooks/governance-lib.sh"
  log_friction "20260101-ng" "BYPASS-ENV" 1 "no-git" 0 "$(_commit_scope_class)" ) 2>/dev/null
# ★ git 실패 = 판정 불가 → 필드 **생략**(빈 문자열 기록 금지). 'empty'(빈 커밋범위)와 구별된다.
#   기록 자체는 성립해야 한다 — 분류 실패가 감사 기록을 막지 않는다.
if jq -e 'select(.evidence_snippet=="no-git" and (has("scope_class")|not))' "$_td/.specops/20260101-ng/friction-log.jsonl" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS T-cls.o git 부재 → 필드 생략 + 기록 성립 (AC-6)"
else FAIL=$((FAIL+1)); echo "FAIL T-cls.o git 부재 처리 실패 (empty 로 뭉갰거나 미기록)"; fi
rm -rf "$_td"

# T-cls.p: 계측 전역이 이른 반환 경로에서 stale 로 남지 않는다 (Phase C Important 회귀 락)
#   선행 무인자 호출(batch 게이트)이 working-tree 목록으로 전역을 채운 뒤, staged 폼 본판정이
#   이른 반환하면 deny 경로가 **직전 목록**을 분류하던 결함. 실측: staged 빈데 code 로 기록됐다.
_td=$(mktemp -d)
_got=$( cd "$_td" && git init -q \
  && echo "echo orig" > app.sh && git add app.sh \
  && git -c user.email=e@t -c user.name=t commit -q -m init \
  && echo "echo changed" > app.sh \
  && ( source "$PLUGIN/hooks/governance-lib.sh"
       is_docs_only_change >/dev/null 2>&1                  # ① batch 게이트 = 무인자
       is_docs_only_change "$_G $_C -m x" >/dev/null 2>&1    # ② 본판정 = 이른 반환
       _commit_scope_class "${_SPECOPS_SCOPE_FILES:-}" ) )   # ③ deny 경로 분류
rm -rf "$_td"
if [ "$_got" = "empty" ]; then
  PASS=$((PASS+1)); echo "PASS T-cls.p 이른 반환 후 전역 stale 없음 ($_got)"
else
  FAIL=$((FAIL+1)); echo "FAIL T-cls.p stale 오염 — got=$_got 기대=empty"
fi

# T-cls.n: is_docs_only_change 가 판정 대상 목록을 노출한다
_td=$(mktemp -d)
_got=$( cd "$_td" && git init -q \
  && echo x > a.md && echo y > b.sh && git add a.md b.sh \
  && ( source "$PLUGIN/hooks/governance-lib.sh"; is_docs_only_change >/dev/null 2>&1
       printf '%s' "${_SPECOPS_SCOPE_FILES:-MISSING}" | tr '\n' ',' ) )
rm -rf "$_td"
case "$_got" in
  *a.md*|*b.sh*) PASS=$((PASS+1)); echo "PASS T-cls.n 목록 노출 ($_got)" ;;
  *) FAIL=$((FAIL+1)); echo "FAIL T-cls.n 목록 미노출 ($_got)" ;;
esac

# ── T-plug.a~k: 플러그인 런타임 .md 는 문서가 아니다 (FID 20260828-md-runtime-scope) ──
# 왜: 이 플러그인의 **실행 로직은 산문**이다(skills/*/SKILL.md·commands/*.md·agents/*.md).
#   `*.md` 를 무조건 문서로 보면 verify 강제가 제품 본체에서 통째로 면제된다 — 실측으로
#   최근 60커밋 중 41건이 면제 클래스였고 그중 22건이 실제 행동 변경이었다(릴리즈 스탬프 19 제외).
#   §auto 자기발급 면제표(v1.45.0 제거)보다 넓다 — 모델이 라벨을 쓸 필요조차 없었다.
# ★ 왜 플러그인 repo 조건을 다는가: 이 경로 지식은 Claude Code **플러그인 규약**이지 앱 규약이
#   아니다. 조건 없이 걸면 하류 앱 repo 의 `templates/email.md`·`docs/agents/x.md` 가 문서 커밋에서
#   차단되고, false-deny 는 정확히 BYPASS 관성을 만든다(마찰로그 24건/30일이 그 증거다).
#   `.claude-plugin/plugin.json` 존재 = "이 repo 에서 .md 는 런타임" 의 기계 판정이다.
# plugin.json 은 **먼저 커밋**한다 — staged 에 남기면 비-.md 파일이라 그것만으로 비면제가 되어
#   아래 케이스가 무엇을 증명하는지 알 수 없게 된다(초안에서 실제로 그렇게 새 PASS 가 났다).
_plug() { mkdir -p .claude-plugin; echo "{}" > .claude-plugin/plugin.json; git add .claude-plugin; git "$C" -q -m plug; }
_su_plug_a() { git init -q; _plug; mkdir -p skills/foo; echo x>skills/foo/SKILL.md; git add skills; }
_docs_case 1 "T-plug.a 플러그인 repo skills/*/SKILL.md 비면제" _su_plug_a
_su_plug_b() { git init -q; _plug; mkdir -p commands; echo x>commands/start.md; git add commands; }
_docs_case 1 "T-plug.b 플러그인 repo commands/*.md 비면제" _su_plug_b
_su_plug_c() { git init -q; _plug; mkdir -p agents; echo x>agents/r.md; git add agents; }
_docs_case 1 "T-plug.c 플러그인 repo agents/*.md 비면제" _su_plug_c
_su_plug_d() { git init -q; _plug; mkdir -p templates; echo x>templates/spec.md; git add templates; }
_docs_case 1 "T-plug.d 플러그인 repo templates/*.md 비면제(하류로 배포되는 산출물)" _su_plug_d
_su_plug_e() { git init -q; mkdir -p .claude-plugin; echo '{}'>.claude-plugin/plugin.json; git add .claude-plugin; }
_docs_case 1 "T-plug.e 플러그인 repo .claude-plugin/* 비면제" _su_plug_e
# 면제 유지 축 — 진짜 문서까지 막으면 BYPASS 관성이 생긴다
_su_plug_f() { git init -q; _plug; mkdir -p docs; echo x>docs/a.md; git add docs; }
_docs_case 0 "T-plug.f 플러그인 repo docs/*.md 면제 유지" _su_plug_f
_su_plug_g() { git init -q; _plug; echo x>README.md; echo y>CHANGELOG.md; echo z>CLAUDE.md; git add README.md CHANGELOG.md CLAUDE.md; }
_docs_case 0 "T-plug.g 플러그인 repo 루트 README/CHANGELOG/CLAUDE 면제 유지" _su_plug_g
_su_plug_h() { git init -q; _plug; mkdir -p skills/foo; echo x>skills/foo/README.md; git add skills; }
_docs_case 0 "T-plug.h 플러그인 repo skills/*/README.md 면제(SKILL.md 만 런타임)" _su_plug_h
# ★ 하류 오차단 방지 축 — plugin.json 없으면 종전과 동일하게 동작한다
_su_plug_i() { git init -q; mkdir -p templates; echo x>templates/email.md; git add templates; }
_docs_case 0 "T-plug.i 비플러그인 repo templates/*.md 면제(하류 오차단 방지)" _su_plug_i
_su_plug_j() { git init -q; mkdir -p skills/foo; echo x>skills/foo/SKILL.md; git add skills; }
_docs_case 0 "T-plug.j 비플러그인 repo skills/*/SKILL.md 면제(경로 지식 미주입)" _su_plug_j
# ★ 면제 클래스 ≡ 분류 클래스 불변식 (governance-lib.sh:481) — posttool 계측 축도 함께 움직여야 한다
_td=$(mktemp -d)
_got=$( cd "$_td" && git init -q && mkdir -p .claude-plugin skills/foo \
  && echo '{}' > .claude-plugin/plugin.json && git add .claude-plugin \
  && git -c user.email=t@e -c user.name=t commit -q -m plug \
  && echo x > skills/foo/SKILL.md && git add skills \
  && ( source "$PLUGIN/hooks/governance-lib.sh"; _commit_scope_class ) )
rm -rf "$_td"
if [ "$_got" = "code" ]; then PASS=$((PASS+1)); echo "PASS T-plug.k _commit_scope_class 도 code (면제≡분류 불변식)"
else FAIL=$((FAIL+1)); echo "FAIL T-plug.k 분류=$_got 기대=code (계측이 면제 클래스와 어긋남)"; fi

# ── T-fx.a~e: 테스트 fixture FID 는 활성 FID 후보에서 제외한다 (FID 20260829-fixture-fid-hijack) ──
# 왜: /e2e-test 는 session-progress 에 fixture FID 섹션을 **prepend** 하고, detect_fid 의 2순위
#   fallback 은 "첫 ## <FID> 헤더" 다. 그래서 e2e 를 한 번 돌리면 fixture 가 repo 의 활성 FID 가
#   되고, **이후 모든 커밋이 fixture 의 verify 상태를 대신 answer** 해야 한다(R-1 ②앵커).
#   게다가 fixture 테스트는 `.specops/<FID>/*.sh` 라 run-verification 실행 whitelist 밖이어서
#   구조적으로 PASS 를 낼 수 없다 → 빠져나갈 정직 경로가 없다(이번 세션 BYPASS 3건의 원인).
# 판별자는 `.specops/<FID>/.fixture` 마커 파일이다 — 산문·헤더 파싱이 아니라 파일 존재라서
#   섹션 포맷 변화에 영향받지 않고, 후보당 test 1회라 hot path 비용이 없다.
# ★ 1순위 active-fid 마커는 건드리지 않는다: 사용자가 fixture 를 **명시적으로** 지목했다면
#   그건 의도다(주권). 제외는 "아무도 지목 안 했을 때의 추측"인 2순위에만 적용한다.
_fid_case() {  # $1 expect $2 label $3 준비 함수 이름(준비가 실패하면 SETUP-FAILED 를 내서 기대값 "" 와 구분한다)
  local exp="$1" label="$2" setup="$3" got
  got=$( sb=$(mktemp -d) && cd "$sb" && { declare -F "$setup" >/dev/null && "$setup" || { echo "SETUP-FAILED"; false; }; } \
         && ( source "$PLUGIN/hooks/governance-lib.sh"; detect_fid ) ; cd /; rm -rf "$sb" )
  if [ "$got" = "$exp" ]; then PASS=$((PASS+1)); echo "PASS $label"
  else FAIL=$((FAIL+1)); echo "FAIL $label — got='$got' 기대='$exp'"; fi
}

_sp() {  # 섹션 헤더들을 순서대로 써 넣는다
  mkdir -p .specops
  : > .specops/session-progress.md
  for f in "$@"; do
    printf '## %s\n\n- 2026-01-01 10:00 /verify PASS\n\n' "$f" >> .specops/session-progress.md
  done
}

_su_fx_a() { _sp 20260101-real 20260102-other; mkdir -p .specops/20260101-real; }
_fid_case 20260101-real "T-fx.a fixture 마커 없으면 종전대로 첫 헤더" _su_fx_a

_su_fx_b() { _sp 20260101-e2e 20260102-real; mkdir -p .specops/20260101-e2e .specops/20260102-real; : > .specops/20260101-e2e/.fixture; }
_fid_case 20260102-real "T-fx.b ★ 선두가 fixture 면 건너뛰고 다음 실작업 FID" _su_fx_b

_su_fx_c() { _sp 20260101-e2e 20260102-e2e; mkdir -p .specops/20260101-e2e .specops/20260102-e2e; : > .specops/20260101-e2e/.fixture; : > .specops/20260102-e2e/.fixture; }
_fid_case "" "T-fx.c 전부 fixture 면 빈 값 (없는 FID 를 지어내지 않는다)" _su_fx_c

_su_fx_d() { _sp 20260102-real; mkdir -p .specops/20260101-e2e; : > .specops/20260101-e2e/.fixture; printf "<!-- active-fid: 20260101-e2e -->\n%s" "$(cat .specops/session-progress.md)" > .specops/session-progress.md; }
_fid_case 20260101-e2e "T-fx.d 명시 active-fid 마커는 fixture 라도 존중 (주권)" _su_fx_d

_su_fx_e() { _sp 20260101-real 20260102-other; }
_fid_case 20260101-real "T-fx.e .specops/<FID> 디렉토리 부재는 fixture 아님 (오탐 차단)" _su_fx_e

# ── T-bcat: _bypass_category 사유 분류 (면제 남용 축소 1 — 판정 불변, 기록 축만) ──
_bcat_case() {  # <want> <label> <reason...>
  local want="$1" label="$2"; shift 2
  local got
  got=$(_bypass_category "$*")
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); echo "PASS $label"
  else
    FAIL=$((FAIL+1)); echo "FAIL $label (want=$want got=$got)"
  fi
}
_bcat_case "implement-commit" "T-bcat.a 태스크 중간 커밋" "태스크 중간 커밋"
_bcat_case "implement-commit" "T-bcat.b 대괄호 태그" "[implement-commit] T1 receipt 후 커밋"
_bcat_case "session-boundary" "T-bcat.c 세션 경계" "이전 세션에서 verify PASS"
_bcat_case "stale-reverify" "T-bcat.d stale" "stale 후 재실행 생략"
_bcat_case "tool-limit" "T-bcat.e 도구 한계" "jq 판정 불가로 우회"
_bcat_case "urgent" "T-bcat.f 긴급" "긴급 hotfix 먼저 머지"
_bcat_case "unclassified" "T-bcat.g 미분류는 unclassified(차단 아님)" "그냥 넘어감"
_bcat_case "unclassified" "T-bcat.h 빈 사유도 unclassified" ""
_bcat_case "urgent" "T-bcat.i 명시 태그가 키워드(receipt)보다 우선" "[urgent] receipt 대기 중 장애"
_bcat_case "tool-limit" "T-bcat.j 명시 태그가 키워드(session)보다 우선" "[tool-limit] jq 없음 (session 중)"
_bcat_case "stale-reverify" "T-bcat.k 명시 태그가 키워드(session)보다 우선 2" "[stale-reverify] session 재개 후 stale"

# ══════════════════════════════════════════════════════════════════════════
# T-mut: 변이 측정에서 살아남던 가드 (20261010-govlib-mutation-survivors)
#   주간 변이 게이트가 처음 끝까지 돈 결과(60%), 아래 가드들은 꺼도 어떤 테스트도 실패하지 않았다.
#   케이스 하나가 가드 하나를 겨눈다. 대조 케이스는 그 픽스처가 공허하지 않음을 보인다.
# ══════════════════════════════════════════════════════════════════════════
_mut_ok() {  # $1 label  $2 조건 결과(0=참)  [$3 실패 시 덧붙일 말]
  if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "PASS $1"
  else FAIL=$((FAIL+1)); echo "FAIL $1${3:+ ($3)}"; fi
}

# T-mut.a 안전 prelude 줄 판정 — 붙여 쓴 `&&` 는 한 토큰이라 `이름=값` 가지의 나머지 검사를 비껴간다.
#   그 줄을 안전 줄로 소비하면 `X=1&&<임의 명령>` 뒤의 커밋이 staged 범위로 좁혀진다(임의 명령은 커밋 전에 돈다).
_clsf_case 1 "T-mut.a ★ prelude 줄의 붙여 쓴 && (X=1&&cmd) → 보수" "X=1&&ga
$_G $_C -m 'x'"
_clsf_case 0 "T-mut.a0 대조 — 같은 자리의 X=1 단독 줄 → 축소" "X=1
$_G $_C -m 'x'"

# T-mut.b 커밋 줄의 compound 판정 — 메시지 값에 붙여 쓴 `&&` 는 값 소비(skip)·`--message=` 가지가 삼킨다.
_clsf_case 1 "T-mut.b ★ -m 값에 붙여 쓴 && (-m x&&cmd) → 보수"            "$_G $_C -m docs&&ga"
_clsf_case 1 "T-mut.b2 ★ --message= 값에 붙여 쓴 && → 보수"                "$_G $_C --message=docs&&ga"

# T-mut.c log_friction 중복 판정 — 파일이 이미 있다는 이유만으로 건너뛰면 둘째 위반부터 기록이 사라진다.
_md=$(mktemp -d)
( cd "$_md" && source "$PLUGIN/hooks/governance-lib.sh" \
  && log_friction "20260101-two" "R-1" 5 "snip-one" 1 \
  && log_friction "20260101-two" "R-1" 5 "snip-two" 2 \
  && log_friction "20260101-two" "R-1" 5 "snip-one" 3 ) >/dev/null 2>&1
_mn=$(grep -c . "$_md/.specops/20260101-two/friction-log.jsonl" 2>/dev/null || true)
[ "$_mn" = "2" ]; _mut_ok "T-mut.c ★ 서로 다른 위반 2건 + 중복 1건 → 2줄" $? "줄 수=$_mn"
rm -rf "$_md"

# T-mut.d _tasks_has_id — id 가 비면 "이 id 가 없다"(1)가 아니라 판정 불가(2)다.
_mt=$(mktemp); printf 'tasks:\n  - id: T1\n  - id: T2\n' > "$_mt"
( source "$PLUGIN/hooks/governance-lib.sh"; _tasks_has_id "$_mt" "" ); _mrc=$?
[ "$_mrc" -eq 2 ]; _mut_ok "T-mut.d ★ 빈 id → 판정 불가(rc 2)" $? "rc=$_mrc"
( source "$PLUGIN/hooks/governance-lib.sh"; _tasks_has_id "$_mt" "T1" ); _mrc=$?
[ "$_mrc" -eq 0 ]; _mut_ok "T-mut.d0 대조 — 있는 id → rc 0" $? "rc=$_mrc"
( source "$PLUGIN/hooks/governance-lib.sh"; _tasks_has_id "$_mt" "T9" ); _mrc=$?
[ "$_mrc" -eq 1 ]; _mut_ok "T-mut.d1 대조 — 없는 id → rc 1" $? "rc=$_mrc"
rm -f "$_mt"

# T-mut.e·f 인용 제거기의 fail-safe 반환 — awk 가 죽거나 빈 출력을 내면 원문을 돌려주고 **rc 0** 이어야 한다.
#   20261010 전까지 이 rc 는 판정에 닿았다: 트리거 판정이 `_trigger_scan_text … | grep` 을 pipefail 아래에서 돌려,
#   앞단이 0 이 아니면 grep 이 커밋을 찾아도 파이프 전체가 실패해 훅이 "커밋 아님" 으로 통과시켰다. 지금은 파이프 없이
#   읽지만(here-string) rc 0 은 이 함수의 계약으로 남긴다 — 누가 다시 파이프 앞단에 세워도 같은 구멍이 나지 않게.
_mq_cmd="$_G \\
$_C -m 'x'"
_mq_out=$( source "$PLUGIN/hooks/governance-lib.sh"; awk() { return 1; }; _trigger_scan_text "$_mq_cmd" ); _mrc=$?
[ "$_mrc" -eq 0 ] && printf '%s' "$_mq_out" | grep -Fq -- "-m 'x'"
_mut_ok "T-mut.e ★ awk 실패 → 원문 반환 + rc 0 (트리거 판정 유지)" $? "rc=$_mrc"
_mq_out=$( source "$PLUGIN/hooks/governance-lib.sh"; awk() { cat >/dev/null; }; _trigger_scan_text "$_mq_cmd" ); _mrc=$?
[ "$_mrc" -eq 0 ] && printf '%s' "$_mq_out" | grep -Fq -- "-m 'x'"
_mut_ok "T-mut.f ★ awk 빈 출력 → 원문 반환 + rc 0 (트리거 판정 유지)" $? "rc=$_mrc"
_mq_out=$( source "$PLUGIN/hooks/governance-lib.sh"; _strip_quoted_strings "$_G $_C -m x" ); _mrc=$?
[ "$_mrc" -eq 0 ] && [ "$_mq_out" = "$_G $_C -m x" ]
_mut_ok "T-mut.f0 인용이 없는 빠른 경로 → 원문 그대로 + rc 0 (인용 제거기를 직접 부른다)" $? "rc=$_mrc out=$_mq_out"

# T-mut.g·h 꺼진 차단 훅의 흔적(_note_governance_disabled)
_mk_in() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
#   g: CLAUDE_PROJECT_DIR 이 없는 경로를 가리켜도(낡은 환경변수) 지금 자리의 저장소에 기록한다.
_mg=$(mktemp -d); mkdir -p "$_mg/.specops"
( cd "$_mg" && source "$PLUGIN/hooks/governance-lib.sh" \
  && _mk_in "$_G $_C -m x" | CLAUDE_PROJECT_DIR="$_mg/no-such-dir" _note_governance_disabled "$PLUGIN" ) >/dev/null 2>&1
grep -qs '"rule_id":"GOVERNANCE-DISABLED"' "$_mg/.specops/friction-log.jsonl"
_mut_ok "T-mut.g ★ CLAUDE_PROJECT_DIR 이 없는 경로 → 현재 저장소에 기록" $?
rm -rf "$_mg"
#   h: 규칙 파일을 못 읽으면 커밋인지 알 수 없다 — 아무 명령에나 기록하지 않는다.
_mh=$(mktemp -d); mkdir -p "$_mh/.specops" "$_mh/emptyroot"
( cd "$_mh" && source "$PLUGIN/hooks/governance-lib.sh" \
  && _mk_in "ls -la" | CLAUDE_PROJECT_DIR="$_mh" _note_governance_disabled "$_mh/emptyroot" ) >/dev/null 2>&1
[ ! -e "$_mh/.specops/friction-log.jsonl" ]
_mut_ok "T-mut.h ★ 규칙 파일 부재 → 기록 없음 (무관한 명령에 흔적 금지)" $?
( cd "$_mh" && source "$PLUGIN/hooks/governance-lib.sh" \
  && _mk_in "$_G $_C -m x" | CLAUDE_PROJECT_DIR="$_mh" _note_governance_disabled "$PLUGIN" ) >/dev/null 2>&1
grep -qs '"rule_id":"GOVERNANCE-DISABLED"' "$_mh/.specops/friction-log.jsonl"
_mut_ok "T-mut.h0 대조 — 규칙 파일이 있고 커밋이면 기록" $?
rm -rf "$_mh"

# T-mut.i STALE 예외 ① — 통과 마커가 없으면 신선도 판정기의 답을 쓰지 않는다.
#   판정기를 "항상 신선"(exit 0)이라 답하는 대역으로 바꿔 두고, 마커 유무만 바꿔 본다.
_ms=$(mktemp -d)
( cd "$_ms" && git init -q && mkdir -p .specops spy \
  && printf '#!/usr/bin/env bash\nexit 0\n' > spy/full-suite-fresh.sh ) >/dev/null 2>&1
_ms_call() {
  ( cd "$_ms" && source "$PLUGIN/hooks/governance-lib.sh"
    _VERIFICATION_STATE_SH="$_ms/spy/verification-state.sh"
    _vs_stale_blocks "20260101-x" "$_G add -A && $_G $_C -m 'x'" ) >/dev/null 2>&1
}
_ms_call; _mrc=$?
[ "$_mrc" -eq 0 ]; _mut_ok "T-mut.i ★ 통과 마커 없음 → 판정기가 신선이라 해도 막는다(rc 0)" $? "rc=$_mrc"
: > "$_ms/.specops/.full-suite-pass"
_ms_call; _mrc=$?
[ "$_mrc" -eq 1 ]; _mut_ok "T-mut.i0 대조 — 마커가 있으면 판정기의 답을 쓴다(rc 1)" $? "rc=$_mrc"
rm -rf "$_ms"

# T-mut.j 거부 사유의 receipt 축 — PR(R-2)에는 receipt 경로가 없다. FID·tasks.md 가 있고 verify 가 PASS 여도 n/a 다.
#   R-1 이면 같은 상태가 closed-verified 다(대조) — R-2 에 그 값이 새면 "verify 가 이미 유효 PASS" 라는 엉뚱한 안내가 붙는다.
_mr=$(mktemp -d); mkdir -p "$_mr/.specops/20260101-rc"
printf '# Session Progress\n\n## 20260101-rc\n\n' > "$_mr/.specops/session-progress.md"
printf 'tasks:\n  - id: T1\n' > "$_mr/.specops/20260101-rc/tasks.md"
printf '# spec\n' > "$_mr/.specops/20260101-rc/spec.md"   # 정식 FID — 명세가 없으면 quick 구조라 창이 닫히지 않는다(20261010-quick-fix-path)
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$_mr/.specops/20260101-rc/evidence.md"
_mr_r1=$(jq -c 'select(.id == "R-1")' "$PLUGIN/hooks/rules.jsonl")
_mr_r2=$(jq -c 'select(.id == "R-2")' "$PLUGIN/hooks/rules.jsonl")
_mr_tr="$FIXTURES/transcripts/r1-commit-without-verify.jsonl"
_mr_o2=$( cd "$_mr" && source "$PLUGIN/hooks/governance-lib.sh" \
  && apply_lookback_rule "$_mr_r2" "$_mr_tr" "Bash" 'gh pr create --title "x"' 2>/dev/null )
_mr_o1=$( cd "$_mr" && source "$PLUGIN/hooks/governance-lib.sh" \
  && apply_lookback_rule "$_mr_r1" "$_mr_tr" "Bash" "$_G $_C -m 'feat: x'" 2>/dev/null )
[ "$(printf '%s' "$_mr_o2" | jq -r '.cause.receipt' 2>/dev/null)" = "n/a" ]
_mut_ok "T-mut.j ★ R-2 + FID·tasks.md·verify PASS → receipt=n/a" $? "$(printf '%s' "$_mr_o2" | jq -c '.cause' 2>/dev/null)"
[ "$(printf '%s' "$_mr_o1" | jq -r '.cause.receipt' 2>/dev/null)" = "closed-verified" ]
_mut_ok "T-mut.j0 대조 — 같은 상태의 R-1 → receipt=closed-verified" $? "$(printf '%s' "$_mr_o1" | jq -c '.cause' 2>/dev/null)"
rm -rf "$_mr"

# ── T-pipe (20261010-hook-sigpipe-test-eval): 일치 판정을 "파이프 뒤 grep -q" 로 읽지 않는다 ──────────
# 왜: 훅은 `set -uo pipefail` 이다. `producer | grep -q` 는 grep 이 첫 일치에서 끝나는 순간 앞단이 아직 쓰는 중이면
#   앞단이 SIGPIPE(141)로 죽고 파이프 전체가 실패가 된다 — "일치" 가 "불일치" 로 읽혔다(커밋 전 훅이 인용 메시지 +
#   줄 연속 커밋과 큰 여러 줄 명령을 통째로 통과시켰다). 아래는 훅과 같은 셸 옵션(pipefail)에서 lib 함수를 직접 잰다.
#   a: 꺼진 훅의 흔적 — 인용 메시지 + 줄 연속. 이은 문자열과 원문을 두 덩어리로 내는 자리라 경합으로 샜다(3회 전부 기록돼야 한다).
_pa_ok=0; _pa_i=0
while [ "$_pa_i" -lt 3 ]; do
  _pa=$(mktemp -d); mkdir -p "$_pa/.specops"
  ( set -uo pipefail; cd "$_pa" && source "$PLUGIN/hooks/governance-lib.sh" \
    && jq -nc --arg c "$_G $_C -m \"x\" \\
  --no-verify" '{tool_name:"Bash",tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$_pa" _note_governance_disabled "$PLUGIN" ) >/dev/null 2>&1
  grep -qs '"rule_id":"GOVERNANCE-DISABLED"' "$_pa/.specops/friction-log.jsonl" && _pa_ok=$((_pa_ok+1))
  rm -rf "$_pa"; _pa_i=$((_pa_i+1))
done
[ "$_pa_ok" -eq 3 ]
_mut_ok "T-pipe.a ★ 인용 메시지 + 줄 연속 커밋도 꺼진 훅의 기록에 남는다 (3/3)" $? "기록된 횟수=$_pa_ok/3"
#   b: 규칙 적용 — 커밋 뒤에 여러 줄이 파이프 버퍼보다 크게 붙은 명령(heredoc 아님). 사전 차단·사후 감사가 같이 쓰는 자리다.
#   크기는 약 103KB 로 둔다: 파이프 버퍼(64KB)보다 커야 재현되고, Linux 가 exec 인자 1개에 두는 한도(131072바이트)보다는
#   작아야 한다 — 이 문자열이 jq --arg 의 인자로 넘어간다(넘으면 입력이 만들어지지 않아 CI 의 ubuntu 에서만 거짓 결과가 난다).
_pb_big=$(_pb_i=0; while [ "$_pb_i" -lt 2000 ]; do echo "echo line-$_pb_i-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; _pb_i=$((_pb_i+1)); done)
_pb=$(mktemp -d)
_pb_r1=$(jq -c 'select(.id == "R-1")' "$PLUGIN/hooks/rules.jsonl")
_pb_o=$( set -uo pipefail; cd "$_pb" && source "$PLUGIN/hooks/governance-lib.sh" \
  && apply_lookback_rule "$_pb_r1" "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" "Bash" "$_G $_C -m x
$_pb_big" 2>/dev/null )
[ "$(printf '%s' "$_pb_o" | jq -r '.rule_id' 2>/dev/null)" = "R-1" ]
_mut_ok "T-pipe.b ★ 커밋 뒤에 큰 여러 줄(${#_pb_big}바이트)이 붙어도 규칙이 적용된다" $? "출력=$(printf '%s' "$_pb_o" | cut -c1-80)"
_pb_o0=$( set -uo pipefail; cd "$_pb" && source "$PLUGIN/hooks/governance-lib.sh" \
  && apply_lookback_rule "$_pb_r1" "$FIXTURES/transcripts/r1-commit-without-verify.jsonl" "Bash" "ls -la
$_pb_big" 2>/dev/null )
[ -z "$_pb_o0" ]
_mut_ok "T-pipe.b0 대조 — 커밋이 없는 큰 명령은 위반이 아니다" $? "출력=$(printf '%s' "$_pb_o0" | cut -c1-80)"
rm -rf "$_pb"

# ── T-setup: 준비가 실패하면 그 단언이 실패한다 (20261010-hook-sigpipe-test-eval) ──
#   왜: 헬퍼 5개는 준비(격리 저장소 만들기)를 한 뒤 판정 함수를 부른다. 준비가 조용히 실패하면 빈 디렉토리에서 판정하게 되고,
#   기대값이 "거부" · "무출력" 인 단언은 그대로 통과한다 — 아무것도 재지 않으면서 초록이다.
#   헬퍼를 서브셸에서 불러(이 스위트의 PASS/FAIL 을 건드리지 않는다) 출력 줄만 본다. 기대값은 양쪽을 다 준다.
_sf_fail() { return 1; }
_sf_bad=""
_sf() {  # <라벨> <헬퍼 호출…> — 그 호출은 FAIL 줄을 내야 한다
  local l="$1" o; shift
  o=$( "$@" 2>/dev/null )
  case "$o" in FAIL*) ;; *) _sf_bad="$_sf_bad [$l → $o]" ;; esac
}
_sf "docs 기대 0"  _docs_case 0 "x" _sf_fail
_sf "docs 기대 1"  _docs_case 1 "x" _sf_fail
_sf "scope 기대 0" _scope_case 0 "x" R-1 _sf_fail
_sf "scope 기대 1" _scope_case 1 "x" R-1 _sf_fail
_sf "base"         _base_case "" "x" _sf_fail
_sf "acls"         _acls_case "" "x" R-1 _sf_fail
_sf "fid"          _fid_case "" "x" _sf_fail
_sf "없는 함수"    _docs_case 1 "x" _sf_no_such_fn
[ -z "$_sf_bad" ]
_mut_ok "T-setup.a ★ 준비가 실패하면(준비 함수가 없어도) 헬퍼 5개가 그 단언을 실패로 낸다" $? "통과로 낸 호출:$_sf_bad"

echo
echo "==== Results: PASS=$PASS FAIL=$FAIL ===="
[ "$FAIL" -eq 0 ]
