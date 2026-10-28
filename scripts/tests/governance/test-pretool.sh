#!/usr/bin/env bash
# pretool-governance.sh 단위 — 4종 모드 + R-2 + 미매칭 + fail-open
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN=$(cd "$script_dir/../../.." && pwd)
HOOK="$PLUGIN/hooks/pretool-governance.sh"
FIX="$script_dir/fixtures/transcripts"
pass=0; fail=0
check() { if printf '%s' "$3" | grep -q "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1 — expected '$2' in: $3"; fail=$((fail+1)); fi; }
# 명령 출력 검사 = check · **파일 문안 검사 = checkf** (파일을 변수에 담지 마라 — macOS CI 간헐 절단)
#   `$(cat file)` 로 캡처하면 그 명령치환이 첫 줄만 반환하는 일이 있어 정적 문안 검사가 거짓 FAIL 을
#   낸다(FID 20260912-pretool-src-capture-flaky). 실패 메시지도 본문이 아니라 경로만 찍는다.
checkf() {  # $1=label $2=pattern $3=file
  if grep -q "$2" "$3"; then echo "PASS $1"; pass=$((pass+1));
  else echo "FAIL $1 — expected '$2' in file: $3"; fail=$((fail+1)); fi
}
mkstdin() { jq -nc --arg c "$1" --arg t "$2" '{tool_name:"Bash", tool_input:{command:$c}, transcript_path:$t}'; }
# 실행 증거 픽스처를 샌드박스의 FID 에 맞추는 도우미(_tr_for) — 다른 FID 의 PASS 는 실행 증거가 아니다(T-fidbind)
# shellcheck source=/dev/null
source "$PLUGIN/scripts/tests/lib/exec-transcript.sh"

# deny 테스트 격리용 공유 sandbox — 코드(.sh) staged 로 is_docs_only_change 면제 미발동 유도
# (실 repo working tree 의 .md dirty 오염과 분리 — pretool-governance L19 CLAUDE_PROJECT_DIR cd)
codesandbox=$(mktemp -d) || exit 1
# .specops 보유 = specops 관할 repo (M2 가드 통과 → verify 강제 검사 진입). deny 의도 유지.
( cd "$codesandbox" && git init -q && echo "echo x" > a.sh && git add a.sh && mkdir .specops )
trap 'rm -rf "$codesandbox"' EXIT

# 자기오염 회귀 락 — 어떤 케이스도 실제 repo 의 active-FID friction-log 에 BYPASS-ENV 를 쓰면 안 된다.
#   세션-env BYPASS 케이스가 CLAUDE_PROJECT_DIR 격리를 빠뜨리면 run-all(cd $PLUGIN) 실행 시 실제
#   .specops/<FID>/friction-log.jsonl 을 오염시킨다(감사 무결성 훼손). suite 시작 count 를 기록해 끝에서 대조.
_repo_fl=$(ls "$PLUGIN/.specops"/*/friction-log.jsonl 2>/dev/null)
_repo_bypass_before=0
[ -n "$_repo_fl" ] && _repo_bypass_before=$(cat $_repo_fl 2>/dev/null | grep -c 'BYPASS-ENV')

out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T1 commit no-verify → deny" '"permissionDecision":"deny"' "$out"
# T2: Skill 호출 + 실제 실행증거 = 정직한 경로 → allow
#   (20260713-verify-exec-gate fixture 보강 — 조임 후 Skill 호출'만'으로는 부족. 구 fixture 는 T2b 로 이관)
# ★ 격리 필수 (20260807 실사용 검증 11호) — 형제 T1·T2b·T2d 는 전부 CLAUDE_PROJECT_DIR 를
#   붙였는데 **T2 만 빠져** 실 repo 루트에서 돌았다. 그래서 훅이 repo 의 **실제 활성 FID** 를
#   해석하고 그 FID 의 진행 기록을 봤다 — 활성 FID 가 verify 미완료면 T2 가 red 가 된다.
#   평소엔 활성 FID 가 우연히 verify PASS 라 통과했고, **실제 lifecycle 을 돌리는 순간 red**.
#   allow 케이스라 ②진행기록 앵커까지 필요하므로 전용 sandbox 를 만든다.
allowsandbox=$(mktemp -d) || exit 1
( cd "$allowsandbox" && git init -q && echo "echo x" > a.sh && git add a.sh \
  && mkdir -p .specops/20260101-t2allow \
  && printf '# Session Progress\n\n## 20260101-t2allow\n\n- 2026-01-01 10:00 /verify PASS\n' \
     > .specops/session-progress.md )
trap 'rm -rf "$codesandbox" "$allowsandbox"' EXIT
out=$(mkstdin "git commit -m x" "$(_tr_for "$allowsandbox" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$allowsandbox" bash "$HOOK" 2>/dev/null)
check "T2 commit with-verify(+exec) → allow" '"continue":true' "$out"
# TC.5a/5b/5n (AC-2) R-1 pretool Skill 앵커 — 진행기록 앵커가 없는 전용 sandbox: Skill 호출 접두사가 열림을 가른다
#   (T2 의 allowsandbox 는 /verify PASS 줄이 있어 접두사와 무관하게 열린다). 옛·other 접두사 픽스처는 런타임 sed.
skillsandbox=$(mktemp -d) || exit 1
( cd "$skillsandbox" && git init -q && echo "echo x" > a.sh && git add a.sh && mkdir -p .specops/20260101-t2allow )
trap 'rm -rf "$codesandbox" "$allowsandbox" "$skillsandbox"' EXIT
_tc5_base=$(_tr_for "$skillsandbox" "$FIX/pretool-with-verify-exec.jsonl")
_tc5_old=$(printf 'specops-%s' ko)
sed "s/devfsd:/$_tc5_old:/g" "$_tc5_base" > "$_TRF_DIR/tc5b.jsonl"
sed "s/devfsd:/other:/g" "$_tc5_base" > "$_TRF_DIR/tc5n.jsonl"
out=$(mkstdin "git commit -m x" "$_tc5_base" | CLAUDE_PROJECT_DIR="$skillsandbox" bash "$HOOK" 2>/dev/null)
check "TC.5a R-1 pretool 새 접두사 Skill+exec → allow" '"continue":true' "$out"
out=$(mkstdin "git commit -m x" "$_TRF_DIR/tc5b.jsonl" | CLAUDE_PROJECT_DIR="$skillsandbox" bash "$HOOK" 2>/dev/null)
check "TC.5b R-1 pretool 옛 접두사 Skill+exec → allow" '"continue":true' "$out"
out=$(mkstdin "git commit -m x" "$_TRF_DIR/tc5n.jsonl" | CLAUDE_PROJECT_DIR="$skillsandbox" bash "$HOOK" 2>/dev/null)
check "TC.5n R-1 pretool other 접두사 Skill+exec → deny(양성 대조)" '"permissionDecision":"deny"' "$out"
# T2b ★ 조임 — Skill 호출만(실행증거 없음) → deny (구 T2 가 allow 하던 것)
out=$(mkstdin "git commit -m x" "$FIX/pretool-with-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T2b ★ Skill 호출만(실행증거 없음) → deny" '"permissionDecision":"deny"' "$out"
# T2c·T2d 심층 필터 통합 잠금 (verify-exec-gate 잔여 backlog — 단위 T9·T10 은 인라인 fixture 라
#   pretool 통합 경로(훅 전체 파이프)의 is_error·negative guard 배선은 별도 파일 fixture 로 잠근다)
# ── T-stale.a~c: deny 사유가 stale 을 stale 이라고 말한다 (FID 20260828-deny-cause-truth) ──
# 왜: 러너를 정직하게 완주하고 그 뒤 파일을 고치면 stale 로 막히는데(설계상 옳다), 메시지는
#   "이 세션에 러너 실행 기록이 없습니다" 라고 **거짓 원인**을 말했다. 사용자는 방금 돌린 러너를
#   또 돌리거나(수분대 낭비) 게이트를 결함으로 의심하고 BYPASS 로 간다.
#   실측: 마찰로그 BYPASS 24건 중 **15건이 "이 세션에서 verify PASS" 를 사유로 적었다** —
#   증거가 있었는데 막힌 것이고, 4건은 아예 "게이트 결함 의심" 이라고 썼다.
#   틀린 deny 문안이 BYPASS 를 유도한 것은 이번이 **두 번째**다(v1.45.0 이 같은 이유로 문안 교체).
out=$(mkstdin "git commit -m x" "$FIX/pretool-verify-then-edit.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-stale.a 러너 PASS 후 코드 편집 → deny 유지(판정은 불변)" '"permissionDecision":"deny"' "$out"
# 'stale' 단어만 요구하면 안 된다 — 구 문안에도 "stale 위험도 있습니다" 가 있어 tautology 다(실측).
#   원인을 **구별해서** 말하는 고유 문구를 요구한다.
check "T-stale.b ★ 사유가 '러너 실행 후 코드 수정' 을 명시" '그 뒤 코드가 수정' "$out"
if printf '%s' "$out" | grep -q '러너 실행 기록이 없습니다'; then
  echo "FAIL T-stale.c 거짓 원인 잔존 — 증거가 있는데 '실행 기록이 없습니다' 라고 말함"; fail=$((fail+1))
else
  echo "PASS T-stale.c 거짓 원인 제거"; pass=$((pass+1))
fi
# 되돌려-관찰: 증거가 **정말로** 없는 경로는 종전 문안을 유지해야 한다(과잉 일반화 차단)
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-stale.d 증거 부재 경로는 종전 문안 유지" '러너 실행 기록이 없습니다' "$out"

out=$(mkstdin "git commit -m x" "$FIX/pretool-verify-exec-error.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T2c 러너 is_error 결과(PASS 문자열) → deny (에러 실행 불인정)" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "git commit -m x" "$FIX/pretool-verify-exec-partial-mixed.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T2d PASS/PARTIAL 혼재 출력 → deny (negative guard)" '"permissionDecision":"deny"' "$out"
# T3 는 CLAUDE_PROJECT_DIR 격리 필수 — repo 루트서 실행(run-all cd $PLUGIN)하면
#   세션-env BYPASS 가 실제 active-FID friction-log 에 BYPASS-ENV 를 기록해 자기오염(감사 무결성 훼손).
#   T-bypass-log.a 와 동일 격리 패턴(mktemp -d + .specops + CLAUDE_PROJECT_DIR override) 적용. 훅 로직은 불변.
bs_t3=$(mktemp -d); mkdir -p "$bs_t3/.specops"
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | SPECOPS_GOVERNANCE_BYPASS=1 CLAUDE_PROJECT_DIR="$bs_t3" bash "$HOOK" 2>/dev/null)
check "T3 env bypass → allow" '"continue":true' "$out"
rm -rf "$bs_t3"
out=$(mkstdin "gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T4 pr no-verify → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "ls -la" "$FIX/pretool-no-verify.jsonl" | bash "$HOOK" 2>/dev/null)
check "T5 unmatched → allow" '"continue":true' "$out"
out=$(printf 'NOT JSON' | bash "$HOOK" 2>/dev/null)
check "T6 bad json → allow" '"continue":true' "$out"
# T7 §auto — 실행증거 없으면 더 이상 면제되지 않는다 (AC-11 — 20260713-verify-exec-gate 조임).
#   구 기대값은 "§auto exempt → allow" 였다. 근거: `§auto: true` 라벨은 모델이 spec.md 에 쓰는 자기발급
#   면제표라, 무인 진입(/start-auto·/start-all-auto)이면 실행-근거 gate 가 통째로 무효화됐다.
#   §auto 의 의미는 "가역 게이트 자동 통과"(사용자 확인 생략)이지 "검증 면제"가 아니다.
tmproot=$(mktemp -d) || exit 1
( cd "$tmproot" && git init -q && echo "echo x" > a.sh && git add a.sh )
mkdir -p "$tmproot/.specops/20260101-auto-fixture"
printf '## 20260101-auto-fixture\n' > "$tmproot/.specops/session-progress.md"
printf '# spec\n**§auto**: true\n' > "$tmproot/.specops/20260101-auto-fixture/spec.md"
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$tmproot" bash "$HOOK" 2>/dev/null)
check "T7 ★ §auto + 실행증거 없음 → deny" '"permissionDecision":"deny"' "$out"
# T7b §auto + 실행증거 있음 → allow (정직한 무인 흐름 무손상 — AC-12)
out=$(mkstdin "git commit -m x" "$(_tr_for "$tmproot" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$tmproot" bash "$HOOK" 2>/dev/null)
check "T7b §auto + 실행증거 → allow" '"continue":true' "$out"
rm -rf "$tmproot"

# T-auto-removed: §auto 무조건 면제 블록이 코드에서 제거됐는지 구조 검사 (AC-10)
#   패턴은 **코드형**(`grep -qE '...§auto...spec.md'` 호출 라인)만 매치한다 — 단순 '§auto.*spec.md' 로
#   하면 제거 자리에 남긴 근거 주석과도 매치되어 영원히 FAIL 한다.
if grep -qE "grep -qE .*§auto.*spec\.md" "$PLUGIN/hooks/pretool-governance.sh" 2>/dev/null; then
  echo "FAIL T-auto-removed — §auto 무조건 면제 블록 잔존"; fail=$((fail+1))
else
  echo "PASS T-auto-removed §auto 면제 블록 제거됨"; pass=$((pass+1))
fi

# T8~T12 evasion 우회 deny (no-verify fixture)
out=$(mkstdin "cd /tmp && git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T8 compound commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "git -C . commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T9 -C commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin " git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T10 선행공백 commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "env FOO=1 git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T11 env-prefix commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "cd /x && gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T12 compound pr create → deny" '"permissionDecision":"deny"' "$out"
# T13~T15 오탐 allow (commit/pr 아님)
out=$(mkstdin 'echo "git commit"' "$FIX/pretool-no-verify.jsonl" | bash "$HOOK" 2>/dev/null)
check "T13 echo string → allow" '"continue":true' "$out"
out=$(mkstdin "mygit commit" "$FIX/pretool-no-verify.jsonl" | bash "$HOOK" 2>/dev/null)
check "T14 mygit → allow" '"continue":true' "$out"
out=$(mkstdin "git committed --amend" "$FIX/pretool-no-verify.jsonl" | bash "$HOOK" 2>/dev/null)
check "T15 committed 단어경계 → allow" '"continue":true' "$out"
out=$(mkstdin "git commit-tree abc123" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T15b commit-tree plumbing(over-match 해소) → allow" '"continue":true' "$out"

# T15c~f 래퍼 접두 인식 (20260905-r12-wrapper-prefix)
#   왜: 트리거 정규식이 git/gh 앞에 VAR=값·env 만 허용해, 명령 래퍼가 붙으면
#   governance-lib.sh:985 가 미매칭으로 즉시 return 0 한다 — 강제층이 조용히 사라진다.
for _w in "rtk" "rtk proxy" "sudo" "nice" "time" "command"; do
  out=$(mkstdin "$_w git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
  check "T15c 래퍼 접두 deny ($_w)" '"permissionDecision":"deny"' "$out"
done

# T15d 오탐 대조군 — 래퍼 이름이 접두 위치가 아니면 걸리지 않는다
out=$(mkstdin "echo rtk git commit" "$FIX/pretool-no-verify.jsonl" | bash "$HOOK" 2>/dev/null)
check "T15d echo 안 래퍼 문자열 → allow" '"continue":true' "$out"

# T15e R-1·R-2 접두 절 동일성 — R-1 에서 파생한 접두로 R-2 를 검사(자르는 위치 하드코딩 없음)
#   왜 LCP+grep 이 아닌가: LCP 에 'rtk' 포함만 보면 그룹 뒷부분 비대칭을 놓친다
#   (실측: R-2 에서만 |command 제거 → LCP 151, rtk 잔존 → 오판 PASS).
_r1=$(jq -rs '.[]|select(.id=="R-1")|.trigger_pattern' "$PLUGIN/hooks/rules.jsonl")
_r2=$(jq -rs '.[]|select(.id=="R-2")|.trigger_pattern' "$PLUGIN/hooks/rules.jsonl")
_pre="${_r1%%git\[\[:space:\]\]+*}"
_grp='(env|rtk|proxy|sudo|nice|time|command|exec|nohup|builtin)|then|do|else|elif|if|while|until|!)[[:space:]]+'
case "$_pre" in
  *"$_grp"*)
    case "$_r2" in
      "$_pre"*) echo "PASS T15e R-1·R-2 접두 절 동일 + 래퍼 그룹 존재"; pass=$((pass+1)) ;;
      *)        echo "FAIL T15e R-2 가 R-1 접두 절로 시작하지 않음 (drift)"; fail=$((fail+1)) ;;
    esac ;;
  *) echo "FAIL T15e R-1 접두 절에 래퍼 그룹 부재"; fail=$((fail+1)) ;;
esac

# T15f R-2 래퍼 대칭 — gh pr create 쪽도 잠근다
out=$(mkstdin "rtk gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T15f 래퍼 접두 pr create → deny" '"permissionDecision":"deny"' "$out"

# T16 docs-only(.md staged) → allow [면제, AC-R-1]
dgit=$(mktemp -d) || exit 1; ( cd "$dgit" && git init -q && echo x > CHANGELOG.md && git add CHANGELOG.md )
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$dgit" bash "$HOOK" 2>/dev/null)
check "T16 docs-only → allow" '"continue":true' "$out"
rm -rf "$dgit"
# T17 코드 혼합(.md+.sh staged) → deny [보안 불변식, AC-R-2]
mgit=$(mktemp -d) || exit 1; ( cd "$mgit" && git init -q && echo x > a.md && echo y > b.sh && git add a.md b.sh && mkdir .specops )
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$mgit" bash "$HOOK" 2>/dev/null)
check "T17 코드혼합 → deny" '"permissionDecision":"deny"' "$out"
rm -rf "$mgit"
# T18 staged docs + unstaged tracked 코드 + `git commit -am` → deny [commit -am 우회 차단, 보안 Critical]
agit=$(mktemp -d) || exit 1; ( cd "$agit" && git init -q && echo "echo orig" > tracked.sh && git add tracked.sh && git commit -q -m init
  echo doc > README.md && git add README.md && echo "echo changed" > tracked.sh && mkdir .specops )
out=$(mkstdin "git commit -am wip" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$agit" bash "$HOOK" 2>/dev/null)
check "T18 commit -am unstaged-code 우회 → deny" '"permissionDecision":"deny"' "$out"
rm -rf "$agit"

# T19~T22 F-1/F-2 신규 우회 deny (codesandbox 코드-staged 로 docs-only 면제 미발동)
out=$(mkstdin "git -c k=v commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T19 git -c k=v commit 우회 → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "git --no-pager commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T20 git --no-pager commit 우회 → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "FOO=bar git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T21 bare VAR=val prefix commit 우회 → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "GH_TOKEN=t gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T22 bare VAR=val prefix gh pr create 우회 → deny" '"permissionDecision":"deny"' "$out"
# T21b~T22b 인용 공백값 prefix 우회 차단 (20260716-batch-dogfood widening — `FOO='a b'` 가 prefix 체인을
#   끊어 트리거를 통째로 비껴갔다. rules.jsonl R-1/R-2 도 동기 수정)
out=$(mkstdin "FOO='a b' git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T21b 인용(single) 공백값 prefix commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin 'FOO="a b" gh pr create --fill' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T22b 인용(double) 공백값 prefix gh pr create → deny" '"permissionDecision":"deny"' "$out"
# T21c~T22d 무인용 공백값 prefix 우회 차단 (20260912-trigger-prefix-unquoted-space)
#   방아쇠는 "명령치환" 이 아니라 **값 안의 공백**이다 — 값 대안이 [^[:space:]]+ 라 `$(gh` 에서 끊겼다.
#   ★ `FOO=$(date) git commit` 로 쓰지 마라: 값에 공백이 없어 **수정 전에도 통과**하는 tautology 다.
#   한계 (F-3 클래스 — 정규식으로 무한확장 닫기 불가. 자기정직 스캐폴드지 적대적 경계가 아니다):
#     · 중첩 명령치환 `FOO=$(a $(b)) git commit`
#     · 값 대안 **뒤 접미 연결** — `FOO=$(x y)bar` · `FOO=${VAR:-a b}${X}` · ``FOO=`a b`x``
#     · 줄바꿈(백슬래시 연속) 포함 치환 — `grep -E` 가 줄 단위라 조각으로만 본다
#     위 형태는 **종전에도 불매칭**이라 회귀가 아니다(확대 전후 동일). 닫은 척하지 않으려고 적는다.
#   mkstdin 인자는 **싱글쿼트** — 더블쿼트면 셸이 치환·백틱을 실제 실행해 입력이 토큰으로 바뀐다.
#   ★ 라벨 규약: T21* = `git commit` · T22* = `gh pr create` (T21·T21b·T22·T22b 와 동일).
out=$(mkstdin 'GH_TOKEN=$(gh auth token) git commit -m x' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T21c 무인용 공백값 prefix commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin 'GH_TOKEN=$(gh auth token --user x) gh pr create --fill' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T22c 무인용 공백값 prefix gh pr create → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin 'FOO=${VAR:-a b} git commit -m x' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T21d 중괄호확장 공백값 prefix commit → deny" '"permissionDecision":"deny"' "$out"
# ★ T22d 는 **수정 전에도 PASS** 한다 — 닫는 백틱이 트리거 앵커 클래스 `[;&|({`]` 에 포함돼
#   "명령 시작" 으로 읽히기 때문이고, 설계된 방어가 아니라 **우연**이다. 즉 이 케이스는 값 대안을
#   잠그지 않는다 — **앵커 클래스가 좁아지는 회귀**를 잡는 용도로만 유효하다(Phase C I-1/I-2).
out=$(mkstdin 'FOO=`gh auth token` gh pr create --fill' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T22d 백틱 공백값 prefix gh pr create → deny (앵커 클래스 회귀 잠금)" '"permissionDecision":"deny"' "$out"
# T23~T24 신규 false-positive 보존 (서브커맨드 인자 commit — trigger 미매칭 allow)
out=$(mkstdin "git config commit.gpgsign true" "$FIX/pretool-no-verify.jsonl" | bash "$HOOK" 2>/dev/null)
check "T23 git config commit.X → allow" '"continue":true' "$out"
out=$(mkstdin "git log --grep=commit" "$FIX/pretool-no-verify.jsonl" | bash "$HOOK" 2>/dev/null)
check "T24 git log --grep=commit → allow" '"continue":true' "$out"

# T25~T26 over-match 제거 (commit=ref명 — allow 목표)
out=$(mkstdin "git --no-pager log commit" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T25 over-match git <opt> log commit → allow" '"continue":true' "$out"
out=$(mkstdin "git -p show commit" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T26 over-match git -p show commit → allow" '"continue":true' "$out"
# T27~T28 정당 deny 보존 (=형 옵션 + 다중 옵션)
out=$(mkstdin "git --git-dir=/x commit" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T27 git --git-dir=/x commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "git --work-tree /w --bare commit" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T28 git --work-tree /w --bare commit → deny" '"permissionDecision":"deny"' "$out"
# T29 VAL 경로 over-match (값받음 옵션 뒤 서브커맨드 — allow) [code-review Minor]
out=$(mkstdin "git -C /repo log commit" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T29 over-match git -C /repo log commit → allow" '"continue":true' "$out"
# T30 --no-advice under-match 해소 (valueless 글로벌 플래그 deny 보존) [code-review Minor]
out=$(mkstdin "git --no-advice commit" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T30 git --no-advice commit → deny" '"permissionDecision":"deny"' "$out"

# T31~T35 선행자 우회 5종 deny (subshell·brace·cmd-subst·백틱 + gh 대칭) [governance-evasion-residual]
out=$(mkstdin "(git commit -m x)" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T31 subshell commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "{ git commit -m x; }" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T32 brace commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "\$(git commit -m x)" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T33 cmd-subst commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "\`git commit -m x\`" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T34 backtick commit → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "(gh pr create --fill)" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T35 subshell pr create → deny" '"permissionDecision":"deny"' "$out"

# T36 ★ inline prefix bypass — 사유(SPECOPS_BYPASS_REASON) 없으면 면제 안 됨 (F-2 조임 — dogfood 20260716:
#   첫 deny 후 모델이 무사유 BYPASS 를 커밋 3회+PR 생성에 관성 사용. 사유 없는 friction-log 는 무정보 감사 기록)
out=$(mkstdin "SPECOPS_GOVERNANCE_BYPASS=1 git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T36 ★ inline bypass 무사유 → deny" '"permissionDecision":"deny"' "$out"
check "T36-msg deny 메시지가 사유 병기 형식 안내" 'SPECOPS_BYPASS_REASON' "$out"
# T36b 사유 병기 → allow (감사 가능한 우회 — 사유가 friction-log evidence_snippet 에 명령 원문으로 잔존)
out=$(mkstdin "SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='design 커밋 — verify 선행 단계' git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T36b inline bypass + 사유 → allow" '"continue":true' "$out"
# T36c REASON 선행 순서도 인정 (형식 순서 함정으로 false-deny 금지)
out=$(mkstdin "SPECOPS_BYPASS_REASON='태스크 중간 커밋' SPECOPS_GOVERNANCE_BYPASS=1 git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T36c REASON-선행 순서 + 사유 → allow" '"continue":true' "$out"
# T36d~f 선행자 클래스 정합 (dogfood 20260717 test2: 사유까지 정직 병기한 compound·함수 wrapper BYPASS 가
#   ^줄시작 앵커에 걸려 false-deny — 트리거는 [;&|({`] 선행자를 인식하는데 bypass 인정만 좁던 비대칭 해소)
out=$(mkstdin "git add a.sh && SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='T4 14/14 PASS 실측' git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T36d compound(&&) bypass + 사유 → allow" '"continue":true' "$out"
out=$(mkstdin 'B() { SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON="$1" git commit -m "$2"; }; B "사유" "msg"' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T36e 함수 wrapper bypass + 사유 → allow" '"continue":true' "$out"
out=$(mkstdin "git add a.sh && SPECOPS_GOVERNANCE_BYPASS=1 git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T36f compound bypass 무사유 → deny (사유 강제 보존)" 'SPECOPS_BYPASS_REASON' "$out"
# T37 메시지 내 토큰 언급은 면제 안 됨 → deny (F-2 우발면제 차단)
out=$(mkstdin 'git commit -m "docs SPECOPS_GOVERNANCE_BYPASS=1 flag"' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T37 message token → deny" '"permissionDecision":"deny"' "$out"

# T38~T39 통합 wiring (F-1) — transcript 에 verify skill 부재(lookback 밖 시뮬)인 상태에서
# session-progress 의 /verify PASS 자기보고가 어떻게 취급되는지.
# spgit: 코드(.sh) staged 로 docs-only 면제 차단 + .specops/session-progress.md FID 섹션 주입.
# T38 ★ 기대값 뒤집기 (20260713-verify-exec-gate — 구 기대값 allow):
#   session-progress 는 모델이 쓰는 self-report 라 실행증거 없이는 단독 면제 불가.
#   /verify PASS 가 최신이어도(vp=0) 실행증거(rc=1)가 없으면 deny.
#   정직한 경로(같은 session-progress + 실행증거 → allow)는 T-exec.b 가 커버한다.
spgit=$(mktemp -d) || exit 1
( cd "$spgit" && git init -q && echo "echo x" > a.sh && git add a.sh && mkdir -p .specops )
printf '## 20260626-wire\n- 2026-06-26 10:05 /verify PASS (evidence.md, AC 5/5)\n- 2026-06-26 10:00 /implement DONE (T1)\n' > "$spgit/.specops/session-progress.md"
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$spgit" bash "$HOOK" 2>/dev/null)
check "T38 ★ session-progress verify 최신 + 실행증거 없음 → deny (조임)" '"permissionDecision":"deny"' "$out"
# T39 negative: /implement 가 /verify 보다 위(최신) → 무효 → transcript fallback(verify 없음) → deny
printf '## 20260626-wire\n- 2026-06-26 10:10 /implement DONE (재구현)\n- 2026-06-26 10:05 /verify PASS (AC 5/5)\n' > "$spgit/.specops/session-progress.md"
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$spgit" bash "$HOOK" 2>/dev/null)
check "T39 session-progress implement 최신 → deny (R-1 보존)" '"permissionDecision":"deny"' "$out"
# T39b 통합 (거짓면제 0 불변식): T39 와 동일 stale(implement 최신) 상태 + evidence PASS stamp 동시.
# vp=2(affirmative-stale)면 evidence stamp 무시하고 deny — stamp fallback 은 vp=1(inconclusive)만.
# apply_lookback_rule 의 `_vp -eq 1` 가드 제거 시 이 케이스가 allow 로 회귀(red) → 단위(test-verify-progress)가 못 잡는 구멍 보강.
mkdir -p "$spgit/.specops/20260626-wire"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$spgit/.specops/20260626-wire/evidence.md"
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$spgit" bash "$HOOK" 2>/dev/null)
check "T39b stale + evidence PASS stamp → deny (vp=2 stamp 무시, 거짓면제 0)" '"permissionDecision":"deny"' "$out"
rm -rf "$spgit"

# T40 .specops 부재 repo(specops 관할 밖) → verify 강제 면제 → allow [M2 스코프 가드]
# codesandbox 와 동일 구성이나 .specops 없음 — 차이는 오직 M2 가드. 가드 없으면 deny(red).
nosg=$(mktemp -d) || exit 1; ( cd "$nosg" && git init -q && echo "echo x" > a.sh && git add a.sh )
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$nosg" bash "$HOOK" 2>/dev/null)
check "T40 .specops 부재 repo → allow (M2 관할 가드)" '"continue":true' "$out"
rm -rf "$nosg"

# T-exec 자기보고 3경로 균일 gate (20260713-verify-exec-gate — AC-5·AC-6·AC-R-2)
#   자기보고 3경로(session-progress /verify PASS · evidence stamp · Skill 호출)는 전부 모델이 쓰는 것이라
#   실행 증거(하네스 작성 tool_result)를 선행 조건으로 요구한다.
execroot=$(mktemp -d) || exit 1
( cd "$execroot" && git init -q && echo "echo x" > a.sh && git add a.sh )
mkdir -p "$execroot/.specops/20260101-forge"
# T-exec.a ★★ AC-R-2 (지배 경로 red): session-progress 에 수기 /verify PASS + 실행증거 없음 → deny
printf '## 20260101-forge\n\n- 2026-01-01 10:00 /verify PASS (evidence.md)\n' > "$execroot/.specops/session-progress.md"
out=$(mkstdin "git commit -m x" "$FIX/pretool-progress-forged.jsonl" | CLAUDE_PROJECT_DIR="$execroot" bash "$HOOK" 2>/dev/null)
check "T-exec.a ★ session-progress 위조 + 실행증거 없음 → deny" '"permissionDecision":"deny"' "$out"
# T-exec.b (AC-6): 같은 session-progress + 실행증거 있음 → allow (정직한 경로 무손상)
out=$(mkstdin "git commit -m x" "$(_tr_for "$execroot" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$execroot" bash "$HOOK" 2>/dev/null)
check "T-exec.b session-progress + 실행증거 → allow" '"continue":true' "$out"
# T-exec.c (AC-5): evidence stamp 위조 + 실행증거 없음 → deny
printf '## 20260101-forge\n' > "$execroot/.specops/session-progress.md"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$execroot/.specops/20260101-forge/evidence.md"
out=$(mkstdin "git commit -m x" "$FIX/pretool-progress-forged.jsonl" | CLAUDE_PROJECT_DIR="$execroot" bash "$HOOK" 2>/dev/null)
check "T-exec.c evidence stamp 위조 + 실행증거 없음 → deny" '"permissionDecision":"deny"' "$out"
# T-exec.d (AC-6 stamp-positive): 같은 stamp + 실행증거 있음 → allow
out=$(mkstdin "git commit -m x" "$(_tr_for "$execroot" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$execroot" bash "$HOOK" 2>/dev/null)
check "T-exec.d evidence stamp + 실행증거 → allow" '"continue":true' "$out"
rm -rf "$execroot"

# T-msg deny 메시지 정확성 (T3 Phase C — false-block 표면)
#   deny 는 의도된 동작이나, 메시지가 작동하지 않는 해법(Skill 호출)을 안내하면 사용자는 BYPASS 를 남발한다.
#   실제로 게이트를 여는 유일한 행동 = run-verification.sh 재실행 → 메시지가 그것을 안내해야 한다.
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-msg.a ★ deny 메시지가 run-verification.sh 재실행을 안내" 'run-verification.sh' "$out"
check "T-msg.b deny 메시지가 '실행 증거 부재'로 정확히 진술" '실행 증거' "$out"
check "T-msg.c deny 메시지에 BYPASS 안내 유지" 'SPECOPS_GOVERNANCE_BYPASS=1' "$out"
# T-msg.d 틀린 해법(Skill 선행) 안내 잔존 금지 — negative
if printf '%s' "$out" | grep -q 'verifying-evidence-ko 선행'; then
  echo "FAIL T-msg.d 틀린 해법(verifying-evidence-ko 선행) 잔존 — in: $out"; fail=$((fail+1))
else
  echo "PASS T-msg.d 틀린 해법 안내 제거됨"; pass=$((pass+1))
fi

# T-qs 인용 문자열 false-block (20260717-quoted-falseblock — dogfood test2 모델 backlog "R-1 블록주석
#   내부 오검출" probe 실재 확정: printf/echo 인용 인자 속 프로즈의 (·| 선행자가 트리거와 오매칭)
qs1='printf "%s\n" "/*" " * 배포 절차: build 후 (git commit 으로 기록)" " */" > note.js'
out=$(mkstdin "$qs1" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-qs.1 ★ 인용 인자 괄호 프로즈 → allow (false-block 해소)" '"continue":true' "$out"
qs2='printf "%s\n" "// pipeline: build | git commit -m x" >> note.js'
out=$(mkstdin "$qs2" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-qs.2 ★ 인용 인자 파이프 주석 프로즈 → allow" '"continue":true' "$out"
qs3='echo "$(git commit -m x)"'
out=$(mkstdin "$qs3" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-qs.3 ★★ 더블쿼트 내 \$() 실행 → deny (보안 불변식 — 제거 금지)" '"permissionDecision":"deny"' "$out"
qs4='git commit -m "back\\slash \" 포함"'
out=$(mkstdin "$qs4" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-qs.4 이스케이프(\\\\·\\\") 포함 메시지의 진짜 commit → deny (트리거 보존)" '"permissionDecision":"deny"' "$out"
qs4b='printf "%s\n" "escape 문서: build 후 (git commit 으로 기록)" > note.md'
out=$(mkstdin "$qs4b" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-qs.4b ★ \\n 포함 printf 프로즈 → allow (blanket-bail 무력화 방지)" '"continue":true' "$out"
qs5='git commit -m "미종결 인용'
out=$(mkstdin "$qs5" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-qs.5 미종결 인용 bail → deny (fail-safe)" '"permissionDecision":"deny"' "$out"
qs6="git commit -m 'fix: 정상 메시지'"
out=$(mkstdin "$qs6" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-qs.6 인용 메시지의 진짜 commit → deny (트리거 보존)" '"permissionDecision":"deny"' "$out"

# T-mp 커밋 메시지 BYPASS 표식 오염 가드 (dogfood test2 61f9e0d "BYPASS fix: ..." — 우회 표식이
#   git 히스토리에 유입. 우회 기록은 REASON+friction-log 담당, conventional commit 훼손 금지)
out=$(mkstdin "SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='중간 커밋' git commit -m \"BYPASS fix: x\"" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-mp.a ★ bypass + -m \"BYPASS...\" 메시지 오염 → deny" '"permissionDecision":"deny"' "$out"
check "T-mp.b 오염 deny 메시지가 정상 메시지 재작성 안내" 'conventional commit' "$out"
out=$(mkstdin "SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='중간 커밋' git commit -m \"fix: 정상\"" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-mp.c bypass + 정상 메시지 → allow (오염 가드 오탐 0)" '"continue":true' "$out"

# T-hd heredoc false-block (20260713-heredoc-false-block)
#   grep -E 는 줄 단위 → 멀티라인 Bash command 의 heredoc **본문** 줄도 트리거에 매칭됐다.
#   → 정직한 문서 작성(spec.md 에 git 예시)이 차단되고 BYPASS 를 남발하게 만들었다.
#   전부 codesandbox(코드-staged + .specops) 로 격리한다: docs-only 면제가 발동하지 않으므로
#   **allow 는 오직 트리거 미매칭(=strip 성공)에서만 나온다** (tautology 차단).
hd_doc='cat > /tmp/spec.md <<EOF
커밋 예시:
git commit -m "feat: x"
EOF'
out=$(mkstdin "$hd_doc" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-hd.a ★ heredoc 문서 본문의 git 예시 → allow (AC-1 false-block 해소)" '"continue":true' "$out"
# T-hd.b (AC-3) heredoc 시작 줄에 결합된 진짜 명령은 유지 → deny
hd_start='cat > /tmp/f.md <<EOF; git commit -m x
본문
EOF'
out=$(mkstdin "$hd_start" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-hd.b ★ heredoc 시작 줄 결합 commit → deny (AC-3)" '"permissionDecision":"deny"' "$out"
# T-hd.c (AC-4) heredoc 종료 후의 진짜 명령은 유지 → deny
hd_after='cat > /tmp/f.md <<EOF
본문
EOF
git commit -m x'
out=$(mkstdin "$hd_after" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-hd.c ★ heredoc 종료 후 commit → deny (AC-4)" '"permissionDecision":"deny"' "$out"
# T-hd.d (AC-5 ★ F-3 표면 불변) 셸 실행자 heredoc 은 본문이 **실제 실행**된다 → 제외 금지 → deny
hd_bash='bash <<EOF
git commit -m x
EOF'
out=$(mkstdin "$hd_bash" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-hd.d ★★ bash <<EOF 본문 commit → deny (AC-5 F-3 표면 불변)" '"permissionDecision":"deny"' "$out"
hd_sh='sh <<'"'"'EOF'"'"'
git commit -m x
EOF'
out=$(mkstdin "$hd_sh" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-hd.e ★ sh <<'EOF' 본문 commit → deny (AC-5)" '"permissionDecision":"deny"' "$out"
# T-hd.f (AC-6) python3 본문은 셸 명령이 아니다(내부 subprocess 는 이미 F-3 클래스) → 제외 → allow
hd_py='python3 <<EOF
git commit -m x
EOF'
out=$(mkstdin "$hd_py" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-hd.f python3 <<EOF 본문 → allow (AC-6)" '"continue":true' "$out"
# T-hd.g (AC-8 fail-safe) 미종료 heredoc → 원본 유지 → 차단 보존 (제거 로직 버그가 차단을 뚫으면 안 된다)
hd_unterm='cat > /tmp/f.md <<EOF
git commit -m x'
out=$(mkstdin "$hd_unterm" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-hd.g ★ 미종료 heredoc → deny (AC-8 fail-safe: 원본 후퇴)" '"permissionDecision":"deny"' "$out"
# T-hd.h <<-'EOF' (탭 들여쓰기 + 인용 delimiter) 문서 → allow
hd_dash=$'cat > /tmp/f.md <<-\'EOF\'\n\tgit commit -m "예시"\n\tEOF'
out=$(mkstdin "$hd_dash" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-hd.h <<-'EOF' 탭 들여쓰기 문서 → allow (AC-1 변형)" '"continue":true' "$out"

# ══════════════════════════════════════════════════════════════════════════
# batch PR 뭉개짐 게이트 (20260721-batch-pr-teeth)
#   dogfood test1: 무인 batch 가 7개 per-FR FID 를 BATCH_ID 하나로 뭉갠 채 PR 을 냈고,
#   teeth(batch-state.sh)는 start-all.md 산문에만 있어 아무도 호출하지 않았다.
#   근거: .specops/audit/dogfood-test1-20260721.md HIGH-3
# ══════════════════════════════════════════════════════════════════════════

# batch sandbox 빌더 — $1=라벨, $2=산출물 생성 여부(1/0), $3=ACTIVE 마커 여부(기본 1)
_mk_batch_sandbox() {
  local label="$1" arts="$2" active="${3:-1}" root
  root=$(mktemp -d) || return 1
  ( cd "$root" && git init -q && echo "echo x" > a.sh && git add a.sh )
  mkdir -p "$root/.specops/batch-p" "$root/.specops/memory"
  cat > "$root/.specops/batch-p/queue.md" <<EOF
| FR-ID | FID | 설명 | Status |
|---|---|---|---|
| FR-4 | 20260721-login | 로그인 | $label |
EOF
  printf '| FR-4 | a | M1 | must | s | f |\n' > "$root/.specops/memory/requirements.md"
  [ "$active" = "1" ] && : > "$root/.specops/batch-p/ACTIVE"
  # batch PR 은 feat/<BATCH_ID> 에서 난다 (start-all.md Phase 0). 게이트 판정 조건이므로 기본값으로 맞춘다.
  ( cd "$root" && git checkout -q -b "feat/batch-p" 2>/dev/null )
  if [ "$arts" = "1" ]; then
    mkdir -p "$root/.specops/20260721-login"
    : > "$root/.specops/20260721-login/review-base.sha"
    : > "$root/.specops/20260721-login/review-request.md"
    # Wave B: ACTIVE batch PR 는 RELEASE_READY hard — 정직 fixture는 축 충족해야 false-block 금지
    # 20260829-bare-skip-teeth: SKIP 근거는 라인 인용 필수(skip_cite 축) — 무인용이면 정직 fixture 가
    #   NOT_READY 로 떨어져 T-batch.b 가 red 가 된다. 계약 변경에 fixture 를 맞춘 것이지 완화가 아니다.
    cat > "$root/.specops/20260721-login/evidence.md" <<'EOF'
RUN-VERIFICATION-RESULT: PASS

## /security-review PASS
**결과**: PASS

## /integration-test PASS
**결과**: PASS

## /performance-test SKIP
**결과**: SKIP
**근거**: §NFR L8-12 — 성능 임계값 없음
EOF
    # reconcile DESYNC 방지 — review-request 있으면 evidence=70, 기록도 review 이상
    printf '## 20260721-login\n\n- 2026-07-21 13:53 /verify PASS (evidence.md)\n- 2026-07-21 14:00 /request-review DONE\n' \
      > "$root/.specops/session-progress.md"
  else
    printf '# session progress\n' > "$root/.specops/session-progress.md"
  fi
  printf '%s' "$root"
}

# ── T-batch.a ★ test1 실물: 라벨 DONE + 산출물 부재 batch → PR deny ──
bs_bad=$(_mk_batch_sandbox "DONE" 0)
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$bs_bad" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$bs_bad" bash "$HOOK" 2>/dev/null)
check "T-batch.a ★ 뭉개진 batch PR → deny" '"permissionDecision":"deny"' "$out"
check "T-batch.a2 deny 사유에 batch 게이트 명시" 'BATCH-GATE' "$out"

# ── T-batch.b ★ 정직한 batch(per-FR 산출물·진행기록 완비) → allow (false-block 금지) ──
#   이 케이스가 열리지 않으면 게이트는 BYPASS 를 강요하는 함정이 된다 — test1 이 겪은 바로 그것.
bs_ok=$(_mk_batch_sandbox "IMPL_DONE" 1)
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$bs_ok" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$bs_ok" bash "$HOOK" 2>/dev/null)
check "T-batch.b ★ 정직한 batch PR → allow" '"continue":true' "$out"

# ── T-batch.b2·deg (20261010-mutation-survivors-rest): batch-state 판정 불가(rc 2)는 통과시키되 **기록한다** ──
#   `[ "$grc" -eq 2 ] && _log_degraded …` 의 -eq·&& 변이가 살아남았다 — 판정 불가일 때만 남아야 할 기록이
#   정상 batch 에 남아도(거짓 경보), 판정 불가인데 안 남아도(무음 fail-open) 아무 테스트도 울지 않았다.
if grep -rqs "batch-state 판정 불가" "$bs_ok/.specops"; then
  echo "FAIL T-batch.b2 — 정상 batch(판정 0)에 degraded 기록이 남았다"; fail=$((fail+1))
else
  echo "PASS T-batch.b2 정상 batch(판정 0) → degraded 기록 없음"; pass=$((pass+1))
fi
bs_deg=$(_mk_batch_sandbox "IMPL_DONE" 1)
rm -f "$bs_deg/.specops/memory/requirements.md"   # batch-state.sh 가 requirements 를 못 찾으면 rc 2(판정 불가)
# ★ 샌드박스 안에서 부른다 — batch-state.sh 는 requirements 를 **cwd 기준**으로 찾는다(훅도 CLAUDE_PROJECT_DIR 로 cd 한 뒤 부른다).
#   테스트 cwd 에서 부르면 "샌드박스에서 지웠다" 가 아니라 "테스트 cwd 에 마침 없다" 를 재게 된다.
( cd "$bs_deg" && bash "$PLUGIN/scripts/batch-state.sh" --gate "$bs_deg/.specops/batch-p" ) >/dev/null 2>&1; _bdrc=$?
[ "$_bdrc" = "2" ] && { echo "PASS T-batch.deg-0 픽스처 rc=2(판정 불가) 성립"; pass=$((pass+1)); } \
  || { echo "FAIL T-batch.deg-0 픽스처 batch-state --gate rc=$_bdrc (2 아님)"; fail=$((fail+1)); }
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$bs_deg" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$bs_deg" bash "$HOOK" 2>/dev/null)
if [ -z "$out" ] || printf '%s' "$out" | grep -q 'BATCH-GATE'; then   # 빈 출력(훅이 죽음)을 "막지 않았다" 로 읽지 않는다
  echo "FAIL T-batch.deg 판정 불가를 batch 게이트가 차단함(또는 훅 출력 없음) — fail-open 이어야 한다: $out"; fail=$((fail+1))
else
  echo "PASS T-batch.deg 판정 불가 → batch 게이트는 막지 않는다(fail-open)"; pass=$((pass+1))
fi
if grep -rqs "batch-state 판정 불가" "$bs_deg/.specops"; then
  echo "PASS T-batch.deg2 ★ 판정 불가 fail-open 을 GOVERNANCE-DEGRADED 로 기록"; pass=$((pass+1))
else
  echo "FAIL T-batch.deg2 — 판정 불가인데 기록이 없다(무음 fail-open)"; fail=$((fail+1))
fi
rm -rf "$bs_deg"

# ── T-mut.a~c: mutation 생존분 봉쇄 (FID 20260829-pretool-mutation-triage) ──
# 왜: pretool 은 **차단 판정 본체**(R-1/R-2 deny)인데 mutation score 가 36% 였다(실측
#   killed=9 survived=16). 생존 중 관찰 불가(호출부가 rc 를 안 쓰는 return 0 10건)는
#   equivalent 로 등재하고, **행동이 실제로 갈리는** 것만 여기서 테스트로 죽인다.
#   equivalent 로 몰아 점수를 올리는 것은 자기발급 면제표다 — 그 경계를 지킨다.

# T-mut.a (L219 `[ -n $transcript ] && [ -f $transcript ] || allow`) — transcript 부재 = fail-open.
#   변이(&&→||)는 경로 문자열이 비어있지 않다는 이유만으로 allow 를 건너뛰고 게이트로 진입시킨다.
#   fail-open 은 보안 계약이다("판정 불가는 차단하지 않는다") — 뒤집히면 정직한 사용자가
#   transcript 없는 환경에서 통째로 막힌다.
out=$(mkstdin "git commit -m x" "/nonexistent/transcript.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-mut.a ★ transcript 부재 → allow (fail-open 계약)" '"continue":true' "$out"

# T-mut.b (같은 줄) — 경로가 **빈 문자열**일 때도 fail-open 이어야 한다(원본 첫 조건 false 경로).
out=$(mkstdin "git commit -m x" "" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-mut.b transcript 빈 경로 → allow (fail-open)" '"continue":true' "$out"

# T-mut.c (L397 `[ "$hard" -eq 1 ]`) — RELEASE_READY **hard deny 분기 자체**가 무테스트였다.
#   T-batch.b 는 정직 batch(any_not_ready=0)라 L395 에서 반환해 397 에 닿지 않는다.
#   변이(-eq→-ne)는 hard 를 warn 으로, warn 을 hard 로 뒤집는다 — 차단 여부가 통째로 반전되는데
#   아무 테스트도 울지 않았다. 뭉개진 batch(=NOT_READY + hard) 로 deny 를 직접 잠근다.
#   ★ 초안은 tautology 였다(되돌려-관찰로 적발): 산출물 없는 batch 를 쓰면 _batch_pr_gate 가
#     **먼저** deny 해서 L397 에 닿지도 않는다 — 변이를 넣어도 테스트가 통과했다.
#     그래서 batch 게이트는 **통과**하되(산출물 완비) release-ready 축 하나만 깨뜨려
#     (bare SKIP) NOT_READY + hard 상태로 L397 에 정확히 도달시킨다.
_rr=$(_mk_batch_sandbox "IMPL_DONE" 1 1)
python3 - "$_rr" <<'PYEOF'
import sys, glob, os
root=sys.argv[1]
for ev in glob.glob(os.path.join(root, '.specops', '*', 'evidence.md')):
    s=open(ev, encoding='utf-8').read()
    # 라인 인용을 지워 bare SKIP 으로 만든다 → skip_cite 축 미충족 → NOT_READY
    s=s.replace('§NFR L8-12 — 성능 임계값 없음', '성능 임계값 없음')
    open(ev,'w',encoding='utf-8').write(s)
PYEOF
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$_rr" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$_rr" bash "$HOOK" 2>/dev/null)
check "T-mut.c ★ NOT_READY + hard 분기 → deny (차단 판정 본체)" '"permissionDecision":"deny"' "$out"
check "T-mut.c2 사유가 RELEASE_READY 경로임을 명시 (batch 게이트 오통과 아님)" 'RELEASE_READY' "$out"
rm -rf "$_rr"

# ── T-batch.c ★ 인라인 BYPASS 로는 못 뚫는다 (비가역 불변식) ──
#   security Critical/High 와 동급 — start-all-auto.md L56 선례. 없으면 test1 이 한 그대로 우회된다.
out=$(mkstdin "SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='배치 PR 승인' gh pr create --fill" \
  "$(_tr_for "$bs_bad" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$bs_bad" bash "$HOOK" 2>/dev/null)
check "T-batch.c ★ 인라인 BYPASS + 뭉개진 batch → deny (불인정)" '"permissionDecision":"deny"' "$out"

# ── T-batch.d 세션 env BYPASS 는 인정 (사용자 주권 — 5원칙 4) ──
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$bs_bad" "$FIX/pretool-with-verify-exec.jsonl")" | SPECOPS_GOVERNANCE_BYPASS=1 CLAUDE_PROJECT_DIR="$bs_bad" bash "$HOOK" 2>/dev/null)
check "T-batch.d 세션 env BYPASS → allow (주권 보존)" '"continue":true' "$out"

# ── T-batch.e batch 컨텍스트 아님 → 기존 동작 불변 (회귀) ──
out=$(mkstdin "gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-batch.e 비-batch PR → 기존 deny 사유 유지(batch 무관)" '"permissionDecision":"deny"' "$out"
if printf '%s' "$out" | grep -q 'BATCH-GATE'; then
  echo "FAIL T-batch.e2 — 비-batch PR 에 batch 게이트 오발화"; fail=$((fail+1))
else
  echo "PASS T-batch.e2 비-batch PR 에 batch 게이트 미발화"; pass=$((pass+1))
fi

# ── T-batch.f commit 은 batch 게이트 대상 아님 (PR 전용 — 중간 커밋은 설계된 비용) ──
out=$(mkstdin "git commit -m x" "$(_tr_for "$bs_bad" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$bs_bad" bash "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q 'BATCH-GATE'; then
  echo "FAIL T-batch.f — commit 에 batch 게이트 오발화(PR 전용이어야)"; fail=$((fail+1))
else
  echo "PASS T-batch.f commit 에 batch 게이트 미발화 (PR 전용)"; pass=$((pass+1))
fi
# ── T-batch.g ★★ ghost-block 금지 — 진행 중이 아닌 과거 batch 는 무관한 PR 을 막지 않는다 ──
#   .specops/* 는 gitignore 라 뭉개진 batch 디렉토리가 디스크에 무기한 남는다. glob-latest 로
#   아무 batch 나 집으면, 그 batch 와 **아무 상관 없는** 단일 FID 작업의 PR 이 과거 라벨 오염으로
#   차단된다. 실측 재현(specops-test1): 무관한 PR 이 batch-20260721b 의 `DONE` 때문에 deny.
#   게다가 이 게이트는 인라인 BYPASS 앞이라, 탈출구가 "세션 전체 거버넌스 해제"뿐이 된다 —
#   false-block 의 유일한 출구가 보호 장치 무력화라는 최악의 형태다.
#   따라서 게이트는 **진행 중(ACTIVE 마커) batch 만** 판정한다.
bs_stale=$(_mk_batch_sandbox "DONE" 0 0)
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$bs_stale" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$bs_stale" bash "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q 'BATCH-GATE'; then
  echo "FAIL T-batch.g ★★ ghost-block — 진행 중 아닌 과거 batch 가 무관한 PR 차단"; fail=$((fail+1))
else
  echo "PASS T-batch.g ★★ ACTIVE 마커 없는 과거 batch → 게이트 미발화 (ghost-block 금지)"; pass=$((pass+1))
fi
# ── T-batch.h ★★ 마커가 있어도 이 PR 이 그 batch 의 PR 이 아니면 판정하지 않는다 ──
#   마커는 "batch 가 진행 중인가"에만 답한다. 게이트가 필요한 답은 "이 PR 이 그 batch 의 PR 인가"다.
#   특히 **중단된 batch**: 마커는 PR 성공(Step D)에서만 지워지는데, 게이트는 뭉개진 batch 를 막는 것이
#   목적이라 막힌 batch 는 Step D 에 도달하지 못한다 → 마커가 영구히 남는다 → 이후 모든 무관한 PR 이
#   영구 차단된다. 게이트가 잘 막을수록 오염 마커가 쌓이는 역설.
#   판별자는 브랜치다 — batch PR 은 feat/<BATCH_ID> 에서 난다(start-all.md Phase 0).
#   불일치는 skip(fail-open) — false-block 회피가 옳은 오류 방향이다.
bs_other=$(_mk_batch_sandbox "DONE" 0)
( cd "$bs_other" && git checkout -q -b "feat/20260721-unrelated" )
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$bs_other" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$bs_other" bash "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q 'BATCH-GATE'; then
  echo "FAIL T-batch.h ★★ 마커 있으나 무관한 브랜치 PR 차단 (중단 batch 영구 ghost-block)"; fail=$((fail+1))
else
  echo "PASS T-batch.h ★★ 무관한 브랜치 PR → 게이트 미발화 (batch PR 만 판정)"; pass=$((pass+1))
fi
rm -rf "$bs_bad" "$bs_ok" "$bs_stale" "$bs_other"

# ── T-msg deny 메시지 정확성 (HIGH-1) ──
#   기존 문안은 "러너를 실행한 뒤 재시도하세요"만 안내한다. 그런데 실행 증거는 **필요조건일 뿐**이고,
#   FID-scoped 진행 기록 앵커가 없으면 여전히 열리지 않는다(governance-lib.sh:481-500).
#   test1 은 안내대로 러너를 재실행하고도 같은 메시지로 또 막혀 BYPASS 로 갔다.
out=$(mkstdin "gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-msg ★ deny 메시지가 진행 기록 앵커 요건도 안내" 'session-progress' "$out"
# ① 누락 deny 는 VERIFY: PARTIAL 의 뜻을 알려야 한다 — 구현 뒤 whitelist 미통과로 PARTIAL 이 되고도 원인을 몰라 훅·verification 소스를 읽는 턴 낭비가 실측됐다(FID 20261005-implement-bookkeeping)
check "T-msg.b ★ ① 누락 deny 가 VERIFY: PARTIAL 은 실행 증거로 인정되지 않는다고 안내" 'VERIFY: PARTIAL' "$out"
check "T-msg.c ★ ① 누락 deny 가 PARTIAL 의 원인(whitelist 미통과)을 안내" 'whitelist 미통과' "$out"
check "T-msg.d ★ ① 누락 deny 가 고치는 방법(test_command 를 허용 형태로)을 안내" 'test_command 를 허용 형태' "$out"

# ── T-bypass-log: 세션-env BYPASS friction-log 기록 (감사 상한 3호) ──
bslog=$(mktemp -d); mkdir -p "$bslog/.specops"
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | SPECOPS_GOVERNANCE_BYPASS=1 CLAUDE_PROJECT_DIR="$bslog" bash "$HOOK" 2>/dev/null)
check "T-bypass-log.a 세션-env BYPASS → allow" '"continue":true' "$out"
if [ -f "$bslog/.specops/friction-log.jsonl" ] && grep -q "BYPASS-ENV" "$bslog/.specops/friction-log.jsonl"; then
  echo "PASS T-bypass-log.b friction-log BYPASS-ENV 기록 생성"; pass=$((pass+1))
else echo "FAIL T-bypass-log.b — 기록 없음"; fail=$((fail+1)); fi
rm -rf "$bslog"
bsno=$(mktemp -d)
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | SPECOPS_GOVERNANCE_BYPASS=1 CLAUDE_PROJECT_DIR="$bsno" bash "$HOOK" 2>/dev/null)
check "T-bypass-log.c 비-specops BYPASS → allow" '"continue":true' "$out"
if [ ! -d "$bsno/.specops" ]; then echo "PASS T-bypass-log.d .specops 미생성(관할 한정)"; pass=$((pass+1))
else echo "FAIL T-bypass-log.d — .specops 생성됨(월권)"; fail=$((fail+1)); fi
rm -rf "$bsno"

# ── T-inline-bypass-log: **인라인** BYPASS 사유의 friction-log 감사 기록 (실사용 검증 3호) ──
# 20260807 실측 결함: deny 메시지(pretool:159)와 주석(:135)이 "사유는 **명령 원문째**
#   friction-log evidence_snippet 에 남는다" 고 약속하는데, 인라인 경로(:151-158)는
#   `_record_bypass_metric` 만 부르고 `log_friction` 을 **부르지 않았다**.
#   실측: 실제 bypass 커밋 전후 BYPASS-ENV 기록 0 → 0, metrics 만 1건
#   (`{"phase":"governance-bypass","fallback":true}` — 사유·명령 원문 없음).
#   세션-env 경로(T-bypass-log.b)는 부르는데 인라인만 빠졌다 — 우회의 **책임 추적이 통째로 공백**.
ibl=$(mktemp -d); mkdir -p "$ibl/.specops"
_inline_cmd="SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='게이트 결함 수정 부트스트랩' git commit -m x"
out=$(mkstdin "$_inline_cmd" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$ibl" bash "$HOOK" 2>/dev/null)
check "T-inline-bypass-log.a 사유 병기 인라인 BYPASS → allow" '"continue":true' "$out"
if [ -f "$ibl/.specops/friction-log.jsonl" ] && grep -q "BYPASS-ENV" "$ibl/.specops/friction-log.jsonl"; then
  echo "PASS T-inline-bypass-log.b 인라인 BYPASS friction-log 기록 생성"; pass=$((pass+1))
else echo "FAIL T-inline-bypass-log.b — 기록 없음 (deny 메시지의 감사 약속 불이행)"; fail=$((fail+1)); fi
# ★ 핵심: 기록만이 아니라 **사유 문자열이 실제로** 들어 있어야 한다.
#   식별자만 남기면 "우회 횟수만 아는 무정보 감사"(:134 주석이 지적한 바로 그것)가 된다.
if grep -q "게이트 결함 수정 부트스트랩" "$ibl/.specops/friction-log.jsonl" 2>/dev/null; then
  echo "PASS T-inline-bypass-log.c 사유 원문이 evidence_snippet 에 보존"; pass=$((pass+1))
else echo "FAIL T-inline-bypass-log.c — 사유 원문 유실 (식별자만 남음 = 무정보 감사)"; fail=$((fail+1)); fi
rm -rf "$ibl"
# 관할 한정 — 비-specops repo 는 인라인 BYPASS 여도 .specops 를 만들지 않는다 (세션-env T-bypass-log.d 와 대칭)
ibno=$(mktemp -d)
out=$(mkstdin "$_inline_cmd" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$ibno" bash "$HOOK" 2>/dev/null)
if [ ! -d "$ibno/.specops" ]; then
  echo "PASS T-inline-bypass-log.d 비-specops 는 .specops 미생성(관할 한정)"; pass=$((pass+1))
else echo "FAIL T-inline-bypass-log.d — .specops 생성됨(월권)"; fail=$((fail+1)); fi
rm -rf "$ibno"

# ── T-inline-bypass-log.e: 사유가 명령 **뒤쪽**에 있어도 evidence 에 남는가 (4호) ──
# 20260807 실측: 3호 수정이 `${tool_cmd:0:200}` **앞부분 절단**이라, 앞에 cd·echo 같은
#   전처리가 붙으면 200자가 거기서 소진돼 **사유가 통째로 잘렸다**.
#   실제 기록: "inline SPECOPS_GOVERNANCE_BYPASS: cd /Users/… echo …건 ===\"\nSPE" ← 여기서 끝
#   "사유는 명령 앞쪽에 온다"는 3호 커밋의 근거 자체가 틀렸다 — compound·전처리가 붙으면 뒤로 밀린다.
#   위치 무관 **추출**이어야 한다.
ible=$(mktemp -d); mkdir -p "$ible/.specops"
# ⚠️ 200자를 **실제로** 넘겨야 결함이 재현된다. 짧은 pad 로는 테스트가 공허해진다(첫 시도 실측 — PASS 로 통과했다).
#    bash ${var:0:200} 은 문자 단위라 한글도 1자로 센다. 넉넉히 250자+ 를 만든다.
_pad="echo AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA && echo BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB && echo CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC && echo DDDDDDDDDDDDDDDDDDDDDDDDDDDDDD && echo EEEEEEEEEEEEEEEEEEEEEEEEEEEEEE && echo FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF && echo GGGGGGGGGGGGGGGGGGGGGGGGGGGGGG &&"
[ "${#_pad}" -gt 200 ] || { echo "FAIL T-inline-bypass-log.e0 — pad 가 200자 미만(${#_pad}) 이라 결함 미재현"; fail=$((fail+1)); }
_late_cmd="$_pad SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='사유가뒤쪽에온다' git commit -m x"
out=$(mkstdin "$_late_cmd" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$ible" bash "$HOOK" 2>/dev/null)
check "T-inline-bypass-log.e1 뒤쪽 사유 인라인 BYPASS → allow" '"continue":true' "$out"
if grep -q "사유가뒤쪽에온다" "$ible/.specops/friction-log.jsonl" 2>/dev/null; then
  echo "PASS T-inline-bypass-log.e2 위치 무관 사유 추출 (앞부분 절단 아님)"; pass=$((pass+1))
else
  echo "FAIL T-inline-bypass-log.e2 — 사유 유실. evidence=$(grep -h 'BYPASS-ENV' "$ible/.specops/friction-log.jsonl" 2>/dev/null | head -c 200)"; fail=$((fail+1))
fi
rm -rf "$ible"
# 큰따옴표·무따옴표 형식도 동일하게 추출되는가 (형식 함정 false-negative 금지)
for _q in 'dq' 'bare'; do
  _d=$(mktemp -d); mkdir -p "$_d/.specops"
  case "$_q" in
    dq)   _c="SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON=\"큰따옴표사유\" git commit -m x"; _want='큰따옴표사유' ;;
    bare) _c="SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON=무따옴표사유 git commit -m x";     _want='무따옴표사유' ;;
  esac
  out=$(mkstdin "$_c" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_d" bash "$HOOK" 2>/dev/null)
  # ★ substring 이 아니라 `reason=<값>` 정확 매칭 — 따옴표가 **벗겨졌는지**까지 본다.
  #   느슨하게 보면 무따옴표 fallback 이 `reason="값"` 으로 뽑아도 통과해
  #   따옴표 분기가 무검증 코드가 된다(변이 생존 실측 20260807).
  if grep -q "reason=$_want " "$_d/.specops/friction-log.jsonl" 2>/dev/null; then
    echo "PASS T-inline-bypass-log.e3-$_q $_q 형식 사유 추출(따옴표 제거)"; pass=$((pass+1))
  else
    echo "FAIL T-inline-bypass-log.e3-$_q — $_q 형식 미정규화. got=$(grep -o 'reason=[^|]*' "$_d/.specops/friction-log.jsonl" 2>/dev/null | head -1)"; fail=$((fail+1))
  fi
  rm -rf "$_d"
done

# ── T-compound-split: Wave C — git add&&commit deny 사유에 분리 안내 포함 ──
out=$(mkstdin "git add a.sh && git commit -m x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-compound-split.a compound add+commit → deny" '"permissionDecision":"deny"' "$out"
check "T-compound-split.b deny 사유에 분리 안내" '별도 Bash 호출' "$out"
# commit-only deny 에는 compound 안내가 없어야 한다 (오안내 방지)
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q '"permissionDecision":"deny"' \
   && ! printf '%s' "$out" | grep -q '별도 Bash 호출'; then
  echo "PASS T-compound-split.c commit-only 에 compound 안내 없음"; pass=$((pass+1))
else
  echo "FAIL T-compound-split.c — unexpected compound hint or allow: $out"; fail=$((fail+1))
fi

# ── T-bypass-metric: BYPASS 시 metrics.jsonl에 식별자만 기록 (사유 원문 없음) ──
bsm=$(mktemp -d)
mkdir -p "$bsm/.specops/20260803-bypass-metric"
printf '<!-- active-fid: 20260803-bypass-metric -->\n## 20260803-bypass-metric\n' \
  > "$bsm/.specops/session-progress.md"
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" \
  | SPECOPS_GOVERNANCE_BYPASS=1 CLAUDE_PROJECT_DIR="$bsm" bash "$HOOK" 2>/dev/null)
check "T-bypass-metric.a 세션-env BYPASS → allow" '"continue":true' "$out"
if [ -f "$bsm/.specops/20260803-bypass-metric/metrics.jsonl" ] \
   && jq -e '.phase=="governance-bypass" and .fallback==true' \
        "$bsm/.specops/20260803-bypass-metric/metrics.jsonl" >/dev/null; then
  echo "PASS T-bypass-metric.b phase=governance-bypass 기록"; pass=$((pass+1))
else
  echo "FAIL T-bypass-metric.b — metric=$(cat "$bsm/.specops/20260803-bypass-metric/metrics.jsonl" 2>/dev/null)"
  fail=$((fail+1))
fi
rm -rf "$bsm"

# ── T-no-selfcontam: suite 전체가 실제 repo friction-log 를 오염시키지 않았는지 최종 락 ──
# 재-glob: suite 중간에 새로 생긴 friction-log 도 잡는다(baseline glob 은 부재 시 빈값 → 0 이므로 신규 오염이 여전히 count>0 로 검출됨).
_repo_fl=$(ls "$PLUGIN/.specops"/*/friction-log.jsonl 2>/dev/null)
_repo_bypass_after=0
[ -n "$_repo_fl" ] && _repo_bypass_after=$(cat $_repo_fl 2>/dev/null | grep -c 'BYPASS-ENV')
if [ "$_repo_bypass_after" -eq "$_repo_bypass_before" ]; then
  echo "PASS T-no-selfcontam repo friction-log BYPASS-ENV 무변경 (${_repo_bypass_before}->${_repo_bypass_after})"; pass=$((pass+1))
else
  echo "FAIL T-no-selfcontam — repo friction-log 자기오염 (${_repo_bypass_before}->${_repo_bypass_after})"; fail=$((fail+1))
fi

# ── deny 안내문 보강 (20260807-bg-verify-evidence) ──
# 백그라운드 실행이 증거로 인정되게 바뀌면서, "왜 막혔는지" 를 원인별로 구분해 안내해야 한다.
# 구분이 없으면 사용자는 방금 러너를 돌리고도 "실행 기록이 없습니다" 를 보고 원인을 모른다.
_PT_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/hooks/pretool-governance.sh"

# P-bg1 — 포그라운드 timeout 지침 (AC-5) · 판정은 `checkf`(파일 직접 grep — 정의는 파일 상단)
checkf "P-bg1 deny 메시지에 포그라운드 timeout 지침" 'timeout' "$_PT_SH"
checkf "P-bg1b 포그라운드 문구" '포그라운드' "$_PT_SH"

# P-bg2 — 백그라운드 미회수 구분 안내 (AC-7) — **behavioral**
#   ★ 소스 문자열 grep 으로 검사하면 배선이 끊겨도 통과한다(Phase B 적발: _EXEC_BG_PENDING_PATH 를
#   서브셸에서 설정해 부모로 전파되지 않았는데 정적 grep 은 PASS 했다). 훅을 실제로 실행해
#   deny 메시지를 검사한다.
_PT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
_bgtr=$(mktemp)
_BGOUT='/private/tmp/x/tasks/pbg2.output'
_BGSTUB="Command running in background with ID: pbg2. Output is being written to: ${_BGOUT}. You will be notified when it completes."
jq -nc --arg cmd 'bash scripts/tests/run-all.sh' \
  '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_PB1",name:"Bash",input:{command:$cmd}}]}}' > "$_bgtr"
jq -nc --arg out "$_BGSTUB" \
  '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_PB1",is_error:false,content:$out}]}}' >> "$_bgtr"
# ★ codesandbox 격리 — 실 repo working tree 가 docs-only dirty 이면 docs 면제로 allow 가 나와
#   위양성 FAIL 이 된다(Phase B 2회차 Important). 파일 상단 격리 규약을 동일 적용.
_bgres=$(CLAUDE_PROJECT_DIR="$codesandbox" mkstdin 'git commit -m "x"' "$_bgtr" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$_PT_ROOT/hooks/pretool-governance.sh" 2>&1)
check "P-bg2 bg 스텁만 있으면 미회수 구분 안내" '백그라운드 실행은 감지됐으나' "$_bgres"
check "P-bg2b 회수할 경로 안내" "$_BGOUT" "$_bgres"
rm -f "$_bgtr"

# T-cscope.a/b: R-1 커밋 게이트 스코프 축소 end-to-end (20260813-r1-docs-only-scope)
#   verify 증거 없는 픽스처를 써야 게이트가 실제로 판정한다(빈 transcript = fail-open allow).
_G=$(printf 'g%sit' ''); _C=$(printf 'c%sommit' '')
scopesandbox=$(mktemp -d) || exit 1
# 기존 trap(:40 codesandbox·allowsandbox)에 병합한다 — 스위트 중단 시 임시 디렉토리 누수 방지.
trap 'rm -rf "$codesandbox" "$allowsandbox" "${scopesandbox:-}" "${scopefid:-}"' EXIT
( cd "$scopesandbox" && git init -q && mkdir -p .specops \
  && echo "echo orig" > tracked.sh && git add tracked.sh \
  && git -c user.email=e@t -c user.name=t commit -q -m init \
  && echo doc > README.md && git add README.md \
  && echo "echo changed" > tracked.sh ) >/dev/null 2>&1

_out=$(mkstdin "$_G $_C -m x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$scopesandbox" bash "$HOOK" 2>&1)
check "T-cscope.a plain 커밋 → allow(AC-1 e2e)" '"continue":true' "$_out"

_out=$(mkstdin "$_G $_C -am x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$scopesandbox" bash "$HOOK" 2>&1)
check "T-cscope.b -am → deny 보존(AC-2 e2e)" 'deny' "$_out"

# T-cscope.c: 축소 적용 allow 시 info 1행 기록 + rule_id 가 R-1 이 아님 (AC-8)
#   ★ detect_fid(governance-lib.sh:52-57)는 .specops/session-progress.md 의 `## <FID>` 헤더를 읽는다.
#     sandbox 에 이 파일이 없으면 FID 가 빈 문자열이라 기록이 설계대로 생략돼 케이스가 영구 FAIL 한다.
scopefid=$(mktemp -d) || exit 1
( cd "$scopefid" && git init -q && mkdir -p .specops/20260101-scopetest \
  && printf '## 20260101-scopetest\n' > .specops/session-progress.md \
  && echo "echo orig" > tracked.sh && git add tracked.sh \
  && git -c user.email=e@t -c user.name=t commit -q -m init \
  && echo doc > README.md && git add README.md \
  && echo "echo changed" > tracked.sh ) >/dev/null 2>&1

mkstdin "$_G $_C -m x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$scopefid" bash "$HOOK" >/dev/null 2>&1
_log=$(cat "$scopefid"/.specops/*/friction-log.jsonl 2>/dev/null)
_hit=$(printf '%s' "$_log" | jq -s '[.[]|select(.severity=="info" and .rule_id!="R-1")]|length' 2>/dev/null || echo 0)
check "T-cscope.c info 기록 + R-1 미오염(AC-8)" '^1$' "$_hit"

# T-cscope.d: FID 미검출(session-progress.md 부재)에도 allow 는 성립 — 기록은 조용히 생략 (AC-8 후단)
_out=$(mkstdin "$_G $_C -m x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$scopesandbox" bash "$HOOK" 2>&1)
check "T-cscope.d FID 부재에도 allow(AC-8 후단)" '"continue":true' "$_out"
# T-cscope.e: 그 allow 가 기록을 남기지 않았음 — d 는 allow 만 보므로 로깅 블록이 통째로 없어도 통과한다.
#   AC-8 후단의 "조용히 생략" 절반은 이 줄이 잠근다 (파일 자체가 생기지 않아야 한다).
_none=$(ls "$scopesandbox"/.specops/*/friction-log.jsonl 2>/dev/null | wc -l | tr -d ' ')
check "T-cscope.e FID 부재 → 기록 생략(AC-8 후단)" '^0$' "$_none"
# 정리는 위 trap 이 담당한다 (중단 시에도 실행).

# T-fsc.a~d: scope_class 배선 e2e (20260813-friction-staged-record)
_G=$(printf 'g%sit' ''); _C=$(printf 'c%sommit' '')
_fsc_sandbox() {  # $1 staged(docs|code|none) → stdout=sandbox 경로
  local td; td=$(mktemp -d)
  ( cd "$td" && git init -q && mkdir -p .specops/20260101-fsc \
    && printf '## 20260101-fsc\n' > .specops/session-progress.md \
    && echo x > seed.md && git add seed.md \
    && git -c user.email=e@t -c user.name=t commit -q -m init
    case "$1" in docs) echo y > README.md; git add README.md ;;
                 code) echo y > app.sh; git add app.sh ;;
                 *) : ;; esac ) >/dev/null 2>&1
  printf '%s' "$td"
}
_fsc_class() {  # $1 sandbox  $2 rule_id → stdout=scope_class
  jq -r --arg r "$2" 'select(.rule_id==$r)|.scope_class // "ABSENT"' \
    "$1"/.specops/*/friction-log.jsonl 2>/dev/null | tail -1
}

# a~c: BYPASS-ENV 는 3값 전부 도달 가능 (AC-2)
for _st in docs code none; do
  case "$_st" in docs) _exp=docs-only ;; code) _exp=code ;; *) _exp=empty ;; esac
  _sb=$(_fsc_sandbox "$_st")
  mkstdin "$_G $_C -m x" "$FIX/pretool-no-verify.jsonl" \
    | SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON=test \
      CLAUDE_PROJECT_DIR="$_sb" bash "$HOOK" >/dev/null 2>&1
  check "T-fsc BYPASS staged=$_st → $_exp (AC-2)" "^$_exp\$" "$(_fsc_class "$_sb" BYPASS-ENV)"
  rm -rf "$_sb"
done

# d: R-1 block 은 code (AC-3)
_sb=$(_fsc_sandbox code)
mkstdin "$_G $_C -m x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$_sb" bash "$HOOK" >/dev/null 2>&1
check "T-fsc.d R-1 block → code (AC-3)" '^code$' "$(_fsc_class "$_sb" R-1)"
_d_all=$(jq -r 'select(.rule_id=="R-1")|.scope_class // "ABSENT"' "$_sb"/.specops/*/friction-log.jsonl 2>/dev/null | sort -u | tr '\n' ',')
rm -rf "$_sb"

# e: block 지점에 docs-only 는 구조적으로 나올 수 없다 (AC-3 후단 — 나오면 버그 신호)
if printf '%s' "$_d_all" | grep -q 'docs-only'; then
  echo "FAIL T-fsc.e block 에 docs-only 출현 — :191 이 allow 했어야 함 (버그 신호)"; fail=$((fail+1))
else
  echo "PASS T-fsc.e block docs-only 미출현 (AC-3)"; pass=$((pass+1))
fi

# g: ★ 인라인 BYPASS 경로(:165) 배선 검증 — env 미설정 + 명령 내 인라인 토큰
#   T-fsc.a~c 는 env 를 세팅해 :56 세션-env 경로에서 단락되므로 :165 에 도달하지 않는다.
#   실측상 인라인 BYPASS 가 태스크 중간커밋의 지배 경로라(:213 주석), 이 배선이 빠지면
#   1차 표적의 최대 데이터원이 무검증으로 남는다(plan-reviewer 2회차 Important).
_sb=$(_fsc_sandbox docs)
mkstdin "SPECOPS_BYPASS_REASON=t SPECOPS_GOVERNANCE_BYPASS=1 $_G $_C -m x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$_sb" bash "$HOOK" >/dev/null 2>&1
check "T-fsc.g 인라인 BYPASS(:165) → docs-only (AC-2)" '^docs-only$' "$(_fsc_class "$_sb" BYPASS-ENV)"
rm -rf "$_sb"

# f: staged·working-tree 모두 빈 상태 → empty (AC-3)
_sb=$(_fsc_sandbox none)
mkstdin "$_G $_C -m x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$_sb" bash "$HOOK" >/dev/null 2>&1
check "T-fsc.f R-1 block staged 없음 → empty (AC-3)" '^empty$' "$(_fsc_class "$_sb" R-1)"
rm -rf "$_sb"

# ── P-jq (AC-3): jq 부재를 정확히 보고하고 fail-open 유지 — 훅 3종 각각 ──
# PATH 통째 교체는 bash·dirname 자체를 못 찾는다. 훅은 :7-8 에서 dirname 을 쓰므로
# 그것이 빠지면 plugin_root 가 비어 :10 에서 무음 종료하고 가드 지점(:24)에 영원히 미도달한다(실측).
jqdir=$(mktemp -d) || exit 1
for b in bash sh cat grep sed awk date mkdir rm git dirname basename tr head tail wc cut sort uniq find printf ls stat; do
  bp=$(command -v "$b" 2>/dev/null) && ln -sf "$bp" "$jqdir/$b"
done

# 도입 저장소에서 잰다 — posttool·stop 은 `.specops/` 가 없으면 jq 를 보기 전에 빠진다(관할 한정).
#   cwd 의 `.specops` 에 기대면 이 저장소의 로컬 작업본에서만 통과하고 CI(깨끗한 체크아웃)에서는 실패한다.
jqsb=$(mktemp -d) || exit 1; mkdir -p "$jqsb/.specops"
for hk in pretool-governance posttool-governance stop-governance; do
  jout=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | PATH="$jqdir" CLAUDE_PROJECT_DIR="$jqsb" bash "$PLUGIN/hooks/$hk.sh" 2>"$jqdir/err.$hk"); jrc=$?
  jerr=$(cat "$jqdir/err.$hk")

  check "P-jq.a.$hk jq 부재 원인 명시" "jq" "$jerr"
  check "P-jq.a2.$hk 미설치 표기" "미설치" "$jerr"

  # 음성 단언 — check() 는 양성 grep 전용이라 인라인으로 카운터를 직접 증감한다(:9 규약과 동형)
  if printf '%s' "$jerr" | grep -q 'stdin JSON parse 실패'; then
    echo "FAIL P-jq.b.$hk — 여전히 오진: $jerr"; fail=$((fail+1))
  else
    echo "PASS P-jq.b.$hk 오진 메시지 미출력"; pass=$((pass+1))
  fi

  # fail-open 유지 (clarify Q1) — fail-closed 로 바뀌면 jq 없는 사용자의 모든 커밋이 막힌다
  if [ "$jrc" -eq 0 ] && printf '%s' "$jout" | grep -q '"continue"'; then
    echo "PASS P-jq.c.$hk fail-open 유지 (rc=0 + continue)"; pass=$((pass+1))
  else
    echo "FAIL P-jq.c.$hk — rc=$jrc out='$jout'"; fail=$((fail+1))
  fi
done
rm -rf "$jqdir"

# T-dry.*: SPECOPS_DRYRUN 은 실행하지 않는 조회다 — 항상 deny + 판정 1줄 (AC-6)
#   ★ 대조군 필수: 어서션이 "구조적 항상통과" 가 아님을 baseline deny 로 먼저 보인다.
_dry_in=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl")
_dry_base=$(printf '%s' "$_dry_in" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-dry.0 baseline deny(대조군)" '"permissionDecision":"deny"' "$_dry_base"

_dry_out=$(printf '%s' "$_dry_in" | SPECOPS_DRYRUN=1 CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-dry.a DRYRUN deny 유지" '"permissionDecision":"deny"' "$_dry_out"

_dry_err=$(printf '%s' "$_dry_in" | SPECOPS_DRYRUN=1 CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>&1 >/dev/null)
check "T-dry.b 판정 1줄 stderr" 'SCOPE=.* EXEMPT=' "$_dry_err"

# T-dry.c: **면제 대상**(docs-only staged) 이어도 DRYRUN 이면 실행되지 않는다 = allow 확대 0
_drydocs=$(mktemp -d)
( cd "$_drydocs" && git init -q && echo x > a.md && git add a.md && mkdir .specops )
_dry_allow=$(printf '%s' "$_dry_in" | CLAUDE_PROJECT_DIR="$_drydocs" bash "$HOOK" 2>/dev/null)
if printf '%s' "$_dry_allow" | grep -q '"permissionDecision":"deny"'; then
  echo "FAIL T-dry.c-pre 면제형 baseline 이 deny — 대조군 무효"; fail=$((fail+1))
else
  echo "PASS T-dry.c-pre 면제형 baseline allow(대조군)"; pass=$((pass+1))
fi
_dry_docs_out=$(printf '%s' "$_dry_in" | SPECOPS_DRYRUN=1 CLAUDE_PROJECT_DIR="$_drydocs" bash "$HOOK" 2>/dev/null)
check "T-dry.c 면제형도 DRYRUN 이면 deny" '"permissionDecision":"deny"' "$_dry_docs_out"
rm -rf "$_drydocs"

# T-dry.d: 인라인 문자열 형태도 동일 판정 (env 미설정)
_dry_inline=$(mkstdin "SPECOPS_DRYRUN=1 git commit -m x" "$FIX/pretool-no-verify.jsonl")
_dry_inl_out=$(printf '%s' "$_dry_inline" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
check "T-dry.d 인라인 형태 deny" '"permissionDecision":"deny"' "$_dry_inl_out"

# T-dry.d2: 인라인 형태의 **판정이 실제 커밋과 같은가** (deny 만 보면 못 잡는 축)
_dry2=$(mktemp -d)
( cd "$_dry2" && git init -q && echo x > a.md && git add a.md && mkdir .specops )
_dry_inl_err=$(printf '%s' "$_dry_inline" | CLAUDE_PROJECT_DIR="$_dry2" bash "$HOOK" 2>&1 >/dev/null)
check "T-dry.d2 인라인도 SCOPE=staged" 'SCOPE=staged ' "$_dry_inl_err"
rm -rf "$_dry2"

# T-dry.d3: **prelude + 인라인** 조합 (3회차 Important-2 실측). 접두 벗김이 명령 **첫 줄**만 보던
#   판본에서는, 인식기(_is_cmd_pos_env = grep, 줄 단위)가 둘째 줄의 인라인을 조회로 인정하면서도
#   접두가 남은 채 판정돼 `cd sub` ⏎ `SPECOPS_DRYRUN=1 git commit` 이 **항상 conservative** 였다
#   (실측 BEFORE: `SCOPE=conservative` / AFTER: `SCOPE=staged`, 실제 커밋은 allow=staged 쪽).
#   ★ `SCOPE=staged` 를 하드코딩하지 않고 **prelude 없는 형태와 1줄 전체를 대조**한다:
#     _dry_cmd 의 둘째 소비자가 is_docs_only_change 라 같은 결함이 EXEMPT·REASON 도 움직인다.
#     "prelude 가 답을 바꾸지 않는다"가 곧 이 케이스의 계약이므로 대조가 정확한 어서션이다.
_dry3=$(mktemp -d)
( cd "$_dry3" && git init -q && echo x > a.md && git add a.md && mkdir -p .specops sub )
_d3_base=$(printf '%s' "$_dry_inline" | CLAUDE_PROJECT_DIR="$_dry3" bash "$HOOK" 2>&1 >/dev/null | grep '^SCOPE=')
_dry_pre_in=$(mkstdin "cd sub
SPECOPS_DRYRUN=1 git commit -m x" "$FIX/pretool-no-verify.jsonl")
_d3_pre=$(printf '%s' "$_dry_pre_in" | CLAUDE_PROJECT_DIR="$_dry3" bash "$HOOK" 2>&1 >/dev/null | grep '^SCOPE=')
if [ -z "$_d3_base" ]; then
  echo "FAIL T-dry.d3-pre 기준선 판정 1줄 부재 — 대조 무효"; fail=$((fail+1))
elif [ "$_d3_pre" = "$_d3_base" ]; then
  echo "PASS T-dry.d3 prelude+인라인이 prelude 없는 형태와 동일 판정 ($_d3_pre)"; pass=$((pass+1))
else
  echo "FAIL T-dry.d3 판정 불일치 — prelude=[$_d3_pre] 기준=[$_d3_base]"; fail=$((fail+1))
fi
rm -rf "$_dry3"

# T-dry.f: **비인용 언급은 조회가 아니다** — 무앵커 glob false-deny 차단 (T37 과 같은 클래스)
#   `echo SPECOPS_DRYRUN=1 && git commit -m x` 는 실제 커밋이다. 이걸 조회로 오인해 deny 하면
#   사용자는 왜 막혔는지 모른 채 BYPASS 로 간다. 여기서는 **면제형 sandbox** 를 쓴다 —
#   codesandbox 는 어차피 deny 라 오인해도 결과가 같아 이 축을 관측할 수 없기 때문이다.
_dryf=$(mktemp -d)
( cd "$_dryf" && git init -q && echo x > a.md && git add a.md && mkdir .specops )
_dry_mention=$(mkstdin "echo SPECOPS_DRYRUN=1 && git commit -m x" "$FIX/pretool-no-verify.jsonl")
_dry_mention_out=$(printf '%s' "$_dry_mention" | CLAUDE_PROJECT_DIR="$_dryf" bash "$HOOK" 2>/dev/null)
if printf '%s' "$_dry_mention_out" | grep -q 'SPECOPS_DRYRUN 조회'; then
  echo "FAIL T-dry.f 비인용 언급을 조회로 오인 — false-deny: $_dry_mention_out"; fail=$((fail+1))
else
  echo "PASS T-dry.f 비인용 언급은 조회 아님"; pass=$((pass+1))
fi
# T-dry.f2 양성 대조군 — 같은 sandbox·같은 어서션에서 **정상 인라인**은 조회로 인식돼야 한다
#   (f 가 "아무것도 조회로 안 봄" 으로 통과하는 구조적 항상통과를 배제한다)
_dry_pos_out=$(printf '%s' "$_dry_inline" | CLAUDE_PROJECT_DIR="$_dryf" bash "$HOOK" 2>/dev/null)
check "T-dry.f2 정상 인라인은 조회로 인식(양성 대조군)" 'SPECOPS_DRYRUN 조회' "$_dry_pos_out"
rm -rf "$_dryf"

# T-dry.g: **판정불가 ≠ 빈 커밋범위** — 두 상태가 같은 문자열로 나오면 안 된다 (AC-5 위장 금지 동형)
#   g-1 non-git + .specops → git 판정 실패 = 판정불가 · g-2 빈 git repo → 커밋 범위 실제로 빔 = empty
_drynog=$(mktemp -d); mkdir -p "$_drynog/.specops"          # git init 없음 — git 판정 실패 유도
_dry_nog_err=$(printf '%s' "$_dry_in" | SPECOPS_DRYRUN=1 CLAUDE_PROJECT_DIR="$_drynog" bash "$HOOK" 2>&1 >/dev/null)
check "T-dry.g1 git 판정 실패는 판정불가로 표기" 'REASON=판정불가' "$_dry_nog_err"
rm -rf "$_drynog"
_dryempty=$(mktemp -d)
( cd "$_dryempty" && git init -q && mkdir .specops )        # git repo 지만 staged 0건
_dry_emp_err=$(printf '%s' "$_dry_in" | SPECOPS_DRYRUN=1 CLAUDE_PROJECT_DIR="$_dryempty" bash "$HOOK" 2>&1 >/dev/null)
# check() 는 grep(BRE) 이라 괄호는 리터럴이다 — `\(` 로 이스케이프하면 그룹이 되어 매칭 실패한다(실측)
check "T-dry.g2 빈 커밋범위는 empty 로 표기" 'REASON=empty(0 files)' "$_dry_emp_err"
if printf '%s' "$_dry_emp_err" | grep -q '판정불가'; then
  echo "FAIL T-dry.g3 빈 범위를 판정불가로 오표기: $_dry_emp_err"; fail=$((fail+1))
else
  echo "PASS T-dry.g3 두 상태가 구별됨"; pass=$((pass+1))
fi
rm -rf "$_dryempty"

# T-dry.e: 분기 순서 — BYPASS 가 DRYRUN 보다 앞이다 (게이트 무음 무력화 금지)
_ln_bypass=$(grep -n 'SPECOPS_GOVERNANCE_BYPASS:-' "$HOOK" | head -1 | cut -d: -f1)
_ln_dry=$(grep -n 'SPECOPS_DRYRUN:-' "$HOOK" | head -1 | cut -d: -f1)   # env 판정 줄만 — 주석 오판 방지
if [ -n "$_ln_bypass" ] && [ -n "$_ln_dry" ] && [ "$_ln_bypass" -lt "$_ln_dry" ]; then
  echo "PASS T-dry.e BYPASS < DRYRUN 순서"; pass=$((pass+1))
else
  echo "FAIL T-dry.e (bypass=$_ln_bypass dry=$_ln_dry)"; fail=$((fail+1))
fi

# === 축 B (20260910-receipt-window-close): 조건부 렌더 + fallback ===
# 공용: 훅을 격리 샌드박스에서 돌린다
# ★ 이 파일은 harness 를 source 하지 않는다 — 헬퍼는 check/pass/fail/mkstdin, 픽스처는 $FIX 다.
#   ok·nope·$FIXTURES·finish 는 **없다**. 쓰면 `command not found` 로 어서션이 조용히 증발하고
#   RED 가 green 이 된다(plan-reviewer 실측: 7개 어서션 증발 + PASS=169 FAIL=0 rc=0).
# ★ CLAUDE_PROJECT_DIR 필수 — pretool-governance.sh:19-21 이 그 변수로 cd 한다. 누락하면 실 repo 를 판정한다.
_deny_msg() {   # $1=프로젝트 디렉토리 $2=훅 파일 $3=입력 JSON
  printf '%s' "$3" | CLAUDE_PROJECT_DIR="$1" bash "$2" 2>/dev/null \
    | jq -r '.hookSpecificOutput.permissionDecisionReason // ""'
}
_nocheck() {   # $1=id $2=없어야 할 문자열 $3=대상  — check 의 음성판
  if printf '%s' "$3" | grep -q "$2"; then echo "FAIL $1 — unexpected '$2' in: $3"; fail=$((fail+1));
  else echo "PASS $1"; pass=$((pass+1)); fi
}

# ①=ok ②=missing 상태: 러너 PASS 가 transcript 에 있고 session-progress 에 /verify PASS 줄이 없다
_PTC=$(mktemp -d) || exit 1
mkdir -p "$_PTC/.specops/20260910-y"
: > "$_PTC/.specops/20260910-y/tasks.md"
# 정식 lifecycle 의 FID 다 — 명세가 있다. 명세 없이 태스크 문서만 있으면 quick 구조라 verify 상태와 무관하게
#   영수증 가지를 탄다(20261010-quick-fix-path — 아래 '창 닫힘' 단언들은 정식 FID 의 것이다).
printf '# spec\n' > "$_PTC/.specops/20260910-y/spec.md"
printf '# ok\n' > "$_PTC/.specops/20260910-y/evidence.md"
printf '<!-- active-fid: 20260910-y -->\n## 20260910-y\n- 2026-09-10 10:00 /implement DONE (T1)\n' \
  > "$_PTC/.specops/session-progress.md"
# ★ 초기 커밋 필수 — unborn HEAD 면 vs::workspace_fingerprint 가 NO_GIT 을 돌리고
#   vs::current 는 recorded=NO_GIT 일 때 STALE 검사를 **건너뛴다** → STALE 픽스처가 성립하지 않는다
#   (부모 로컬 실측에서 T-cause.e-1 이 이 이유로 FAIL 했다 — 판정이 아니라 픽스처가 틀렸었다).
( cd "$_PTC" && git init -q && printf 'echo x\n' > a.sh && git add a.sh \
    && git -c user.name=t -c user.email=t@e.com commit -qm init >/dev/null )
_in=$(mkstdin 'git commit -m "feat: x"' "$(_tr_for "$_PTC" "$FIX/exec-evidence-pass.jsonl")")
msg=$(_deny_msg "$_PTC" "$HOOK" "$_in")
check "T-cause.pre deny 발생" 'verify 면제 조건' "$msg"

# === AC-4: ① 충족 시 거짓 안내를 하지 않고, 충족 사실을 표시한다 ===
# 왜: 이 문안이 거짓일 때 사용자는 방금 돌린 수분대 러너를 또 돌리거나 게이트를 결함으로
#   의심해 BYPASS 한다(20260828 실측 24건 중 15건). 이번 FID 의 분석자 본인도 같은 함정에 빠졌다.
_nocheck "T-cause.a ①충족 시 거짓 안내 미출력" '이 세션에 러너 실행 기록이 없습니다' "$msg"
# ★ 금지문구 부재만으로는 부족하다 — stale 분기도 그 문구가 없다. 충족 표기를 **양성으로** 단언한다.
check "T-cause.b ① 충족 표기 양성" '✔ ① 실행 증거' "$msg"
check "T-cause.c ② 미충족 표기 양성" '✘ ② 진행 기록 앵커' "$msg"
# ① 이 충족이면 러너 실행 방법 안내(포그라운드·백그라운드)는 소음이다 — 붙이지 않는다 (대조는 T-cause.k-4)
_nocheck "T-cause.b2 ① 충족이면 포그라운드 실행 안내를 붙이지 않는다" '포그라운드' "$msg"
# ② 앵커 누락 deny 는 복구 명령 2개(러너 선행 · session-progress-append /verify PASS)를 항상 줘야 한다 — 두 번째 이후 거부에서 명령이 없어 모델이 훅 소스를 읽었다
check "T-cause.c2 ② 앵커 누락 deny 가 복구 명령 session-progress-append /verify PASS 를 안내" 'scripts/session-progress-append.sh 20260910-y /verify PASS' "$msg"
check "T-cause.c3 ② 앵커 누락 deny 가 앵커 기록 전 러너 PASS 확인을 안내" 'run-verification.sh 20260910-y' "$msg"

# === AC-5: 창이 열렸으면 receipt 안내를 하고, 닫혔으면 하지 않는다 ===
check "T-cause.d 창 열림(NOT_RUN) → receipt 안내" 'record-task-receipt.sh' "$msg"
( cd "$_PTC" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" \
    record 20260910-y PASS --executed 1 --failed 0 ) >/dev/null 2>&1
( cd "$_PTC" && printf 'stale\n' >> a.sh && git add a.sh )   # 기록 이후 변경 → STALE, staged 유지
msg2=$(_deny_msg "$_PTC" "$HOOK" "$_in")
# ★ 픽스처가 실제로 STALE 인지 먼저 확인한다 — 아니면 아래 두 어서션이 다른 상태를 재게 된다.
_v=$(cd "$_PTC" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" current 20260910-y)
[ "$_v" = "STALE" ] && { echo "PASS T-cause.e-0 픽스처 STALE 성립"; pass=$((pass+1)); } \
  || { echo "FAIL T-cause.e-0 픽스처 verdict=$_v (STALE 아님)"; fail=$((fail+1)); }
# ★ 빈 msg2(=allow 회귀)를 PASS 로 흡수하지 않는다 — deny 는 유지돼야 한다.
check "T-cause.e-1 창 닫힘에서도 deny 유지" 'verify 면제 조건' "$msg2"
_nocheck "T-cause.e-2 창 닫힘(STALE) → receipt 안내 미출력" 'record-task-receipt.sh' "$msg2"

# === M-truth 잠금: 창이 닫힌 **이유**를 단정하지 않는다 (PASS·STALE·WAIVED 공통 참) ===
# 왜: _receipt_window_open 은 PASS·STALE·WAIVED(+판정불가) 전부에서 닫는데, 초안 문안은
#   "verify 가 이미 유효 PASS 이므로" 라고 단정했다 — STALE 에서는 거짓(PASS 후 코드가 바뀐 상태),
#   WAIVED 에서도 거짓(verify 가 돌지 않았다). 세 상태 중 하나에서만 참인 문장을 전부에 출력했다.
#   그 거짓이 곧 이 FID 가 없애려는 병이다(deny 메시지가 거짓을 말한다 → BYPASS).
#   T-cause.f 는 verdict 가 NOT_RUN 이라 이 모순을 못 잡는다 → STALE + 앵커 stale 조합으로 잡는다.
printf '<!-- active-fid: 20260910-y -->\n## 20260910-y\n- 2026-09-10 09:00 /verify PASS (evidence.md)\n- 2026-09-10 11:00 /implement DONE (T1)\n' \
  > "$_PTC/.specops/session-progress.md"
# verification-state.json 은 **그대로 둔다** — PASS 기록 + 트리 변조 = STALE(창 닫힘 유지).
# ★ e-0 과 같은 선검사 — 픽스처가 실제로 STALE 인지 먼저 확인한다(NOT_RUN 이면 다른 상태를 재게 된다).
_v2=$(cd "$_PTC" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" current 20260910-y)
[ "$_v2" = "STALE" ] && { echo "PASS T-cause.i-0 픽스처 STALE+앵커stale 성립"; pass=$((pass+1)); } \
  || { echo "FAIL T-cause.i-0 픽스처 verdict=$_v2 (STALE 아님)"; fail=$((fail+1)); }
msg2b=$(_deny_msg "$_PTC" "$HOOK" "$_in")
check "T-cause.i-1 창 닫힘 표기 유지" 'receipt 경로는 이 FID 에서' "$msg2b"
check "T-cause.i-2 앵커 stale 동시 표기(모순 성립 조건)" '더 최신인 코드 변경 기록' "$msg2b"
# 핵심 음성 단언: 어느 verdict 인지 **단정**하지 않는다. STALE 에서 "유효 PASS" 는 거짓이다.
_nocheck "T-cause.i-3 verdict 단정 문구 미출력" '유효 PASS' "$msg2b"

# === AC-4/M4: 앵커 stale 을 stale 이라 말한다 ===
# /verify PASS 줄보다 /implement 줄이 더 최신이면 _verify_passed_in_progress rc=2(affirmative-stale).
printf '<!-- active-fid: 20260910-y -->\n## 20260910-y\n- 2026-09-10 09:00 /verify PASS (evidence.md)\n- 2026-09-10 11:00 /implement DONE (T1)\n' \
  > "$_PTC/.specops/session-progress.md"
rm -f "$_PTC/.specops/20260910-y/verification-state.json"
msg3=$(_deny_msg "$_PTC" "$HOOK" "$_in")
check "T-cause.f 앵커 stale 을 stale 로 표기" '더 최신인 코드 변경 기록' "$msg3"

# === I-2 잠금: rc=2(판정 불가)를 "실행 확인" 으로 단정하지 않는다 ===
# 왜: exec 축은 `rc≠1` 을 ok 로 접는다(AC-8 의 2값 열거 `ok|missing` — 유지). 그런데 rc=2 는
#   transcript 부재·tool_use 0건·jq 실패 = **판정 불가**(fail-open)지 "러너가 돌았다" 가 아니다.
#   실제 도달 경로: 새 세션의 첫 Bash 호출이 커밋이면 tool_use 0건 → rc=2. 그 상태에서 "러너 PASS 가
#   확인됩니다" 는 거짓이고, 거짓 deny 문안이 곧 이 FID 가 없애려는 병이다(BYPASS 관성).
printf '%s\n' \
  '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"커밋해줘"}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"네, 커밋하겠습니다."}]}}' \
  > "$_PTC/no-tooluse.jsonl"
# ★ 선검사 — 픽스처가 실제로 rc=2 인지 먼저 확인한다. rc=1 이면 아래 단언이 다른 상태를 재게 된다.
_ercc=$(. "$PLUGIN/hooks/governance-lib.sh" >/dev/null 2>&1; \
        _verify_exec_evidence "$_PTC/no-tooluse.jsonl" "" >/dev/null 2>&1; echo $?)
[ "$_ercc" = "2" ] && { echo "PASS T-cause.j-0 픽스처 rc=2(판정 불가) 성립"; pass=$((pass+1)); } \
  || { echo "FAIL T-cause.j-0 픽스처 _verify_exec_evidence rc=$_ercc (2 아님)"; fail=$((fail+1)); }
_in_j=$(mkstdin 'git commit -m "feat: x"' "$_PTC/no-tooluse.jsonl")
msgj=$(_deny_msg "$_PTC" "$HOOK" "$_in_j")
# 양성 대조 2건 — 빈 msgj(allow 회귀)나 ① 블록 증발을 음성 단언이 흡수하지 못하게 한다.
check "T-cause.j-1 rc=2 에서도 deny 유지" 'verify 면제 조건' "$msgj"
check "T-cause.j-2 ① 축 표기 양성(대조군)" '✔ ① 실행 증거' "$msgj"
# 핵심 음성 단언: 판정 불가를 확인으로 단정하는 문구가 없다.
_nocheck "T-cause.j-3 rc=2 를 실행 확인으로 단정 안 함" '러너 PASS 가 확인' "$msgj"

# === 20261010-mutation-survivors-rest: ②=ok ①=missing — 앵커가 확인되면 확인된다고 말한다 ===
# 왜: 지금까지의 픽스처는 전부 ② 가 missing·stale 이었다. "✔ ② 확인됩니다" 분기의 조건을 뒤집어도(-eq→-ne)
#   아무 테스트도 울지 않았다 — 앵커를 남긴 사용자에게 "앵커가 필요합니다" 라고 거짓 원인을 말하게 된다.
_PTA=$(mktemp -d) || exit 1
mkdir -p "$_PTA/.specops/20260910-y"
: > "$_PTA/.specops/20260910-y/tasks.md"
printf '<!-- active-fid: 20260910-y -->\n## 20260910-y\n- 2099-01-01 10:00 /verify PASS (evidence.md)\n' \
  > "$_PTA/.specops/session-progress.md"
( cd "$_PTA" && git init -q && printf 'echo x\n' > a.sh && git add a.sh \
    && git -c user.name=t -c user.email=t@e.com commit -qm init >/dev/null \
    && printf 'echo y\n' >> a.sh && git add a.sh )
msga=$(_deny_msg "$_PTA" "$HOOK" "$(mkstdin 'git commit -m "feat: x"' "$FIX/pretool-no-verify.jsonl")")
check "T-cause.k-1 ②만 충족 → deny 유지 (①은 필요조건)" 'verify 면제 조건' "$msga"
check "T-cause.k-2 ★ ② 충족 표기 양성" '✔ ② 진행 기록 앵커: 확인됩니다' "$msga"
check "T-cause.k-3 ① 미충족 표기 양성" '✘ ① 실행 증거' "$msga"
check "T-cause.k-4 ① 미충족이면 포그라운드 실행 안내를 붙인다 (T-cause.b2 의 대조)" '포그라운드' "$msga"
rm -rf "$_PTA"

# === AC-6: cause 부재 → 종전 문안 + deny 유지 (행동 검증 — 소스 grep 아님) ===
# 왜 사본인가: 프로덕션에 테스트용 뒷문(env 로 cause 제거)을 내면 그 자체가 우회 표면이다.
#   hooks 만 복사하고 scripts/templates 는 심볼릭으로 붙인다(governance-lib 이 ../scripts 를 참조).
_FB=$(mktemp -d) || exit 1
cp -R "$PLUGIN/hooks" "$_FB/hooks"
ln -sfn "$PLUGIN/scripts" "$_FB/scripts"; ln -sfn "$PLUGIN/templates" "$_FB/templates" 2>/dev/null || true
cat >> "$_FB/hooks/governance-lib.sh" <<'FBEOF'
# 테스트 전용 재정의 — cause 없는 legacy emit 재현 (뒤 정의가 이긴다)
_emit_violation() {
  jq -nc --arg id "$1" --arg snippet "$2" --argjson offset "$3" \
    '{ rule_id: $id, evidence_snippet: $snippet, offset: $offset }'
}
FBEOF
printf '<!-- active-fid: 20260910-y -->\n## 20260910-y\n- 2026-09-10 10:00 /implement DONE (T1)\n' \
  > "$_PTC/.specops/session-progress.md"
msg4=$(_deny_msg "$_PTC" "$_FB/hooks/pretool-governance.sh" "$_in")
check "T-cause.g-1 cause 부재에도 deny 유지" 'verify 면제 조건' "$msg4"
check "T-cause.g-2 cause 부재 → ① 종전 문안" '러너 실행 기록이 없습니다' "$msg4"
check "T-cause.g-3 cause 부재 → receipt 종전 안내" 'record-task-receipt.sh' "$msg4"
rm -rf "$_FB"

# cause 가 **일부만** 온 경우도 종전 문안이다 (20261010-mutation-survivors-rest) — 세 축이 다 있어야 진단을 쓴다.
#   `[ -n exec ] && [ -n anchor ] && [ -n receipt ] && _cause_ok=1` 의 결합을 풀어도 살아남았다: 한 축이 빈 채로
#   나머지 축의 값을 믿으면 "✔ ② 확인됩니다" 같은 문장이 반쪽 근거로 나간다. 생산자(_emit_violation)는 지금 세 축을
#   함께 싣지만, 이 가드는 그 계약이 깨졌을 때의 방어다 — 같은 사본 방식으로 깨진 emit 을 재현한다.
_FB2=$(mktemp -d) || exit 1
cp -R "$PLUGIN/hooks" "$_FB2/hooks"
ln -sfn "$PLUGIN/scripts" "$_FB2/scripts"; ln -sfn "$PLUGIN/templates" "$_FB2/templates" 2>/dev/null || true
cat >> "$_FB2/hooks/governance-lib.sh" <<'FBEOF'
# 테스트 전용 재정의 — exec 축만 빈 cause 재현 (뒤 정의가 이긴다)
_emit_violation() {
  jq -nc --arg id "$1" --arg snippet "$2" --argjson offset "$3" \
    '{ rule_id: $id, evidence_snippet: $snippet, offset: $offset, cause: { exec: "", anchor: "ok", receipt: "n/a" } }'
}
FBEOF
msg4b=$(_deny_msg "$_PTC" "$_FB2/hooks/pretool-governance.sh" "$_in")
check "T-cause.g-4 cause 일부 부재에도 deny 유지" 'verify 면제 조건' "$msg4b"
check "T-cause.g-5 cause 일부 부재 → ① 종전 문안" '러너 실행 기록이 없습니다' "$msg4b"
_nocheck "T-cause.g-6 ★ 반쪽 cause 의 anchor 값을 믿지 않는다" '✔ ② 진행 기록 앵커: 확인됩니다' "$msg4b"
rm -rf "$_FB2"

# === M5b 잠금: receipt 부재와 무효를 구별한다 (1회차 I2 수정분) ===
# 왜: _cr 매핑을 뒤집는 변이가 세 스위트를 전부 통과했다(plan-reviewer 실측 M5b 생존).
#   없는 receipt 를 "무효" 라 부르면 "staged 를 확인하라" 는 오안내가 된다 — 축 B 의 재발.
_PTI=$(mktemp -d) || exit 1
mkdir -p "$_PTI/.specops/20260910-z/receipts" "$_PTI/scripts/tests" "$_PTI/src"
printf 'echo ok\n' > "$_PTI/scripts/tests/test-foo.sh"; chmod +x "$_PTI/scripts/tests/test-foo.sh"
printf 'x\n' > "$_PTI/src/foo.sh"; printf 'y\n' > "$_PTI/other.sh"
# ★ `## 의존 그래프` 헤더를 넣지 않는다 — 픽스처 소비측(record-task-receipt)은 2단 fallback 이
#   `tasks:` 키로 찾으므로 헤더가 불필요하다(헤더가 있으면 dag::extract_yaml 오인 위험).
cat > "$_PTI/.specops/20260910-z/tasks.md" <<'TKEOF'
```yaml
tasks:
  - id: T1
    test_command: "bash scripts/tests/test-foo.sh"
    depends_on: []
    inputs: []
    outputs: [src/foo.sh]
    ac: [AC-1]
```
TKEOF
printf '<!-- active-fid: 20260910-z -->\n## 20260910-z\n- 2026-09-10 10:00 /implement DONE (T1)\n' \
  > "$_PTI/.specops/session-progress.md"
( cd "$_PTI" && git init -q && git add src scripts other.sh \
    && git -c user.name=t -c user.email=t@e.com commit -qm init \
    && printf 'z\n' >> src/foo.sh && git add src \
    && bash "$PLUGIN/scripts/_internal/record-task-receipt.sh" 20260910-z T1 ) >/dev/null 2>&1
# receipt 는 유효하게 기록됐다. 이제 outputs **밖** 파일을 staged 해 무효화한다.
( cd "$_PTI" && printf 'w\n' >> other.sh && git add other.sh ) >/dev/null 2>&1
_in_i=$(mkstdin 'git commit -m "fix: x (Task: T1)"' "$(_tr_for "$_PTI" "$FIX/exec-evidence-pass.jsonl")")
msg5=$(_deny_msg "$_PTI" "$HOOK" "$_in_i")
check "T-cause.h-1 receipt 무효 → 무효 문안" '기록된 receipt 가 유효하지 않습니다' "$msg5"
# 대조군: receipt 자체가 없으면 무효 문안이 아니라 기록 안내가 나와야 한다.
rm -f "$_PTI/.specops/20260910-z/receipts/T1.json"
msg6=$(_deny_msg "$_PTI" "$HOOK" "$_in_i")
_nocheck "T-cause.h-2 receipt 부재 → 무효 문안 미출력" '기록된 receipt 가 유효하지 않습니다' "$msg6"
check "T-cause.h-3 receipt 부재 → 기록 안내" 'record-task-receipt.sh' "$msg6"
# ── 20261001-task-id-guard — open-id-mismatch 문안 (원인별 분기: 거짓 원인 방지) ──
# ★ 이 시점 _PTI 는 receipts/T1.json 이 제거된 상태다(위 h-2) — 유효 receipt 가 있으면
#   `Task: T1a`→T1 이 허용되어 아래 deny 단언이 성립하지 않는다.
_in_a=$(mkstdin $'git commit -m "feat: x\n\nTask: T1a"' "$(_tr_for "$_PTI" "$FIX/exec-evidence-pass.jsonl")")
msg_a=$(_deny_msg "$_PTI" "$HOOK" "$_in_a")
check "T5.a (AC-4) 선언≠해석 → 원인 표시" '원인: 커밋 메시지의 task id' "$msg_a"
check "T5.a2 선언값 표시" 'Task: T1a' "$msg_a"
check "T5.a3 절단 안내(숫자 전용)" '접미사는 T1 로 잘려' "$msg_a"
_in_d=$(mkstdin $'git commit -m "feat: x\n\nTask: T9"' "$(_tr_for "$_PTI" "$FIX/exec-evidence-pass.jsonl")")
msg_d=$(_deny_msg "$_PTI" "$HOOK" "$_in_d")
check "T5.d 선언=해석인데 tasks.md 에 없음 → id 없음 원인" '해당 task id(T9)가 없습니다' "$msg_d"
_nocheck "T5.d2 절단이 일어나지 않았으면 절단 문구를 말하지 않는다(거짓 원인 방지)" '접미사는 T1 로 잘려' "$msg_d"
_in_f=$(mkstdin $'git commit -m "feat: x\n\nTask: task-3"' "$(_tr_for "$_PTI" "$FIX/exec-evidence-pass.jsonl")")
msg_f=$(_deny_msg "$_PTI" "$HOOK" "$_in_f")
check "T5.f 선언은 있는데 해석 빈값 → 미해석 원인" '해석되지 않았습니다' "$msg_f"
_nocheck "T5.f2 미해석에는 절단 문구를 말하지 않는다" '접미사는 T1 로 잘려' "$msg_f"
# 회귀: 기존 open-missing 문안 불변 — 새 원인 문구가 끼지 않고 기록 안내가 유지된다 (AC-R-2)
_nocheck "T5.b (AC-R-2) 정상 선언 + receipt 부재 → 새 원인 문구 없음" '원인: 커밋 메시지의 task id' "$msg6"
check "T5.b2 (AC-R-2) 기록 안내 유지" 'record-task-receipt.sh' "$msg6"
# 거짓 원인 방지 (a1): 선언이 T숫자 형식이 아니고 해석 id 는 산문 fallback 에서 왔다 — 절단이 아니다.
_in_g=$(mkstdin $'git commit -m "feat: x (T1)\n\nTask: fix the parser"' "$(_tr_for "$_PTI" "$FIX/exec-evidence-pass.jsonl")")
msg_g=$(_deny_msg "$_PTI" "$HOOK" "$_in_g")
check "T5.g0 (a1) deny 유지" 'verify 면제 조건' "$msg_g"
_nocheck "T5.g 선언 fix + 산문 (T1) → 절단 문구 미출력(거짓 원인 방지)" '접미사는 T1 로 잘려' "$msg_g"
check "T5.g2 (a1) 사실 진술 — 형식 아님 + 다른 id 로 해석" 'task id 형식(T숫자)이 아니며, 훅은 본문의 다른 id(T1)로 해석' "$msg_g"
# 선언 없음 (b'): 산문 (T7) 만 있고 tasks.md 에 T7 없음 — 존재하지 않는 Task: 줄을 언급하지 않는다.
_in_h=$(mkstdin 'git commit -m "fix: y (T7)"' "$(_tr_for "$_PTI" "$FIX/exec-evidence-pass.jsonl")")
msg_h=$(_deny_msg "$_PTI" "$HOOK" "$_in_h")
check "T5.h 산문 (T7) 만 → id 없음 원인" '해당 task id(T7)가 없습니다' "$msg_h"
_nocheck "T5.h2 선언 없음 → 'Task: 값이' 미출력" 'Task: 값이' "$msg_h"
check "T5.h3 선언 없음을 사실대로 진술" 'Task: 선언이 없어' "$msg_h"
# R-2(PR, receipt=n/a) 는 `*)` 로 같은 헬퍼를 지나간다 — open-id-mismatch 가 아니면 원인 문안을 내지 않는다.
_in_i2=$(mkstdin 'gh pr create --title "fix: y (T7)" --body x' "$(_tr_for "$_PTI" "$FIX/exec-evidence-pass.jsonl")")
msg_i2=$(_deny_msg "$_PTI" "$HOOK" "$_in_i2")
check "T5.i0 R-2 deny 유지(대조군)" 'verify 면제 조건' "$msg_i2"
_nocheck "T5.i R-2(n/a) 에는 receipt 원인 문안 미출력" 'receipt 경로가 열리지 않는 원인' "$msg_i2"
rm -rf "$_PTI" "$_PTC"


# === I-A/I-B 잠금 (Phase C 2회차 지적) ===
# I-A: ① 축 문안이 "러너 재실행 무용" 을 단정하면 거짓이다 — 러너는 verification-state 를
#   기록하므로 PASS 시 _verify_evidence_stamp 경로로 실제로 열린다(리뷰어 P1→P2 프로브 반증).
#   거짓 deny 문안은 BYPASS 관성을 만든다 — 본 FID 가 없애려는 병이다.
# I-B: 캐시 변수를 훅 프로세스 env 로 선주입하면 사유·감사 기록 없이 게이트가 열렸다.
#   SPECOPS_GOVERNANCE_BYPASS 보다 약한 통제라 무조건 초기화로 막는다.
_IAB=$(mktemp -d) || exit 1
mkdir -p "$_IAB/.specops/20260910-p"
cat > "$_IAB/.specops/20260910-p/tasks.md" <<'IABTK'
```yaml
tasks:
  - id: T1
    test_command: "bash scripts/tests/test-foo.sh"
    depends_on: []
    inputs: []
    outputs: [a.sh]
    ac: [AC-1]
```
IABTK
printf '<!-- active-fid: 20260910-p -->\n## 20260910-p\n- 2026-09-10 10:00 /implement DONE (T1)\n' \
  > "$_IAB/.specops/session-progress.md"
( cd "$_IAB" && git init -q && printf 'echo x\n' > a.sh && git add a.sh \
    && git -c user.name=t -c user.email=t@e.com commit -qm init >/dev/null \
    && printf 'zz\n' >> a.sh && git add a.sh )
: > "$_IAB/empty.jsonl"        # tool_use 0건 → _verify_exec_evidence rc=2 (판정 불가)
( cd "$_IAB" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" \
    record 20260910-p FAIL --executed 1 --failed 1 ) >/dev/null 2>&1
_in_iab=$(mkstdin 'git commit -m x' "$_IAB/empty.jsonl")
msg_ia=$(_deny_msg "$_IAB" "$HOOK" "$_in_iab")
check "T-cause.j-4a rc=2 창 열림에서 deny 유지" 'verify 면제 조건' "$msg_ia"
check "T-cause.j-4b ① 축 표기 존재(대조군)" '✔ ① 실행 증거' "$msg_ia"
_nocheck "T-cause.j-4c ① 이 러너 재실행 무용을 단정 안 함" '풀리지 않습니다' "$msg_ia"
_nocheck "T-cause.j-4d receipt 를 '유일한' 경로라 단정 안 함" '유일한 경로' "$msg_ia"
# I-B: env 선주입이 게이트를 열지 못한다
_msg_env=$(printf '%s' "$_in_iab" | _VS_VERDICT_CACHE=PASS _VS_VERDICT_CACHE_FID=20260910-p \
  CLAUDE_PROJECT_DIR="$_IAB" bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
check "T-cause.j-4e 캐시 env 선주입으로 열리지 않는다" 'verify 면제 조건' "$_msg_env"
rm -rf "$_IAB"

# ── T-bypass-cat: BYPASS 사유 분류 기록 (면제 남용 축소 1 — 판정 불변) ──
_catsb=$(mktemp -d); mkdir -p "$_catsb/.specops"
out=$(mkstdin "SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='태스크 중간 커밋' git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_catsb" bash "$HOOK" 2>/dev/null)
check "T-bypass-cat.a 분류 키워드 → allow 유지" '"continue":true' "$out"
if grep -q "cat=implement-commit" "$_catsb/.specops/friction-log.jsonl" 2>/dev/null; then
  echo "PASS T-bypass-cat.b cat=implement-commit 기록"; pass=$((pass+1))
else echo "FAIL T-bypass-cat.b — cat 미기록"; fail=$((fail+1)); fi
rm -rf "$_catsb"
_catsb2=$(mktemp -d); mkdir -p "$_catsb2/.specops"
out=$(mkstdin "SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='그냥 넘어감' git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_catsb2" bash "$HOOK" 2>/dev/null)
check "T-bypass-cat.c 미분류 사유 → allow 유지" '"continue":true' "$out"
if grep -q "cat=unclassified" "$_catsb2/.specops/friction-log.jsonl" 2>/dev/null; then
  echo "PASS T-bypass-cat.d cat=unclassified 기록"; pass=$((pass+1))
else echo "FAIL T-bypass-cat.d — cat 미기록"; fail=$((fail+1)); fi
rm -rf "$_catsb2"
_catsb3=$(mktemp -d); mkdir -p "$_catsb3/.specops"
out=$(mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | SPECOPS_GOVERNANCE_BYPASS=1 CLAUDE_PROJECT_DIR="$_catsb3" bash "$HOOK" 2>/dev/null)
check "T-bypass-cat.e 세션-env → allow 유지" '"continue":true' "$out"
if grep -q "cat=unclassified | session-env" "$_catsb3/.specops/friction-log.jsonl" 2>/dev/null; then
  echo "PASS T-bypass-cat.f 세션-env cat 기록"; pass=$((pass+1))
else echo "FAIL T-bypass-cat.f — cat 미기록"; fail=$((fail+1)); fi
rm -rf "$_catsb3"

# ── T-docs-unstaged-log: working-tree 범위 docs-only 면제도 기록 (면제 남용 축소 2) ──
_docu=$(mktemp -d) || exit 1
( cd "$_docu" && git init -q && mkdir -p .specops/20260101-docu \
  && printf '## 20260101-docu\n' > .specops/session-progress.md \
  && echo doc > README.md && echo "echo x" > tracked.sh \
  && git add -A && git -c user.email=e@t -c user.name=t commit -q -m init \
  && echo more >> README.md ) >/dev/null 2>&1
_out=$(mkstdin "git commit -am x" "$FIX/pretool-no-verify.jsonl" \
  | CLAUDE_PROJECT_DIR="$_docu" bash "$HOOK" 2>&1)
check "T-docs-unstaged-log.a working-tree docs-only → allow 유지" '"continue":true' "$_out"
if grep -q "R-1-SCOPE" "$_docu/.specops/20260101-docu/friction-log.jsonl" 2>/dev/null \
   && grep -q "working-tree 범위" "$_docu/.specops/20260101-docu/friction-log.jsonl" 2>/dev/null; then
  echo "PASS T-docs-unstaged-log.b working-tree 범위 R-1-SCOPE 기록"; pass=$((pass+1))
else echo "FAIL T-docs-unstaged-log.b — 기록 없음"; fail=$((fail+1)); fi
rm -rf "$_docu"

# ── T-degraded-log: fail-open 판정 불가도 기록 (면제 남용 축소 3 — allow 불변) ──
_dgd=$(mktemp -d); mkdir -p "$_dgd/.specops"
out=$(printf 'not-json' | CLAUDE_PROJECT_DIR="$_dgd" bash "$HOOK" 2>/dev/null)
check "T-degraded-log.a 파싱 실패 → allow 유지" '"continue":true' "$out"
if grep -q "GOVERNANCE-DEGRADED" "$_dgd/.specops/friction-log.jsonl" 2>/dev/null; then
  echo "PASS T-degraded-log.b degraded 기록 생성"; pass=$((pass+1))
else echo "FAIL T-degraded-log.b — 기록 없음"; fail=$((fail+1)); fi
rm -rf "$_dgd"
_dgd2=$(mktemp -d)
out=$(printf 'not-json' | CLAUDE_PROJECT_DIR="$_dgd2" bash "$HOOK" 2>/dev/null)
check "T-degraded-log.c 비-specops 파싱 실패 → allow 유지" '"continue":true' "$out"
if [ ! -f "$_dgd2/.specops/friction-log.jsonl" ]; then
  echo "PASS T-degraded-log.d 비-specops 는 기록 없음(관할 한정)"; pass=$((pass+1))
else echo "FAIL T-degraded-log.d — 관할 밖 기록"; fail=$((fail+1)); fi
rm -rf "$_dgd2"

# ── T-prscope: `gh pr create` 면제는 **작업트리가 아니라 PR 커밋 범위(base...HEAD)** 로 판정한다 ──
# 왜: is_docs_only_change 는 작업트리(git diff HEAD)를 먼저 봤다. 추적 중인 .specops/session-progress.md
#   하나만 dirty 여도 작업트리가 all-docs 로 판정돼, **이미 커밋된 미검증 코드**가 든 PR 이 면제됐다
#   (PR 에 실리는 건 커밋된 base...HEAD 뿐이다). posttool 감사(is_docs_only_audit_scope)는 이미 범위 기준이다.
_prs_mk() {  # $1=dir $2=feat 브랜치에 커밋할 파일(코드면 a.sh, 문서면 notes.md)
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$1" && git init -q -b main \
    && mkdir -p .specops && echo "# SP" > .specops/session-progress.md && echo base > README.md \
    && git add -A && git -c user.email=e@t -c user.name=t commit -q -m base \
    && git checkout -q -b feat \
    && echo "echo x" > "$2" && git add "$2" && git -c user.email=e@t -c user.name=t commit -q -m "feat: $2" \
    && echo "dirty" >> .specops/session-progress.md ) >/dev/null 2>&1
}
_prs_code=$(mktemp -d)
_prs_mk "$_prs_code" a.sh
out=$(mkstdin "gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_prs_code" bash "$HOOK" 2>/dev/null)
check "T-prscope.a 커밋된 코드 + 작업트리 docs dirty → PR deny (범위=base...HEAD)" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "cd $_prs_code && gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_prs_code" bash "$HOOK" 2>/dev/null)
check "T-prscope.b compound(cd &&) PR 도 deny" '"permissionDecision":"deny"' "$out"
rm -rf "$_prs_code"

# ── T-prscope.e~f: batch PR 게이트(_batch_pr_gate)도 같은 범위 기준이어야 한다 ──
# 왜: 게이트는 `is_docs_only_change` 를 무인자로 불러 작업트리 기준 면제를 탔다. 뭉개진 batch 라도 추적 중인
#   문서 하나가 dirty 면 "docs-only" 로 보고 통과해, 가장 되돌리기 비싼 batch PR 이 새고 있었다.
_prs_batch() {  # $1=dir — feat/batch-p 브랜치에 코드 커밋 + 뭉개진 queue(DONE·산출물 없음) + 작업트리 docs dirty
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$1" && git init -q -b main \
    && mkdir -p .specops/batch-p .specops/memory && echo "# SP" > .specops/session-progress.md && echo base > README.md \
    && git add -A && git -c user.email=e@t -c user.name=t commit -q -m base \
    && git checkout -q -b feat/batch-p \
    && echo "echo x" > a.sh && git add a.sh && git -c user.email=e@t -c user.name=t commit -q -m "feat: a" \
    && printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n| FR-4 | 20260721-login | 로그인 | DONE |\n' > .specops/batch-p/queue.md \
    && printf '| FR-4 | a | M1 | must | s | f |\n' > .specops/memory/requirements.md \
    && : > .specops/batch-p/ACTIVE && echo "dirty" >> README.md ) >/dev/null 2>&1
}
_prs_b=$(mktemp -d); _prs_batch "$_prs_b"
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$_prs_b" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$_prs_b" bash "$HOOK" 2>/dev/null)
check "T-prscope.e ★ 뭉개진 batch + 커밋된 코드 + 작업트리 docs dirty → BATCH-GATE deny" 'BATCH-GATE' "$out"
# 대조: 범위가 문서뿐이면(코드 커밋 없음) batch 게이트는 면제 유지
_prs_d=$(mktemp -d)
( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  cd "$_prs_d" && git init -q -b main && mkdir -p .specops/batch-p .specops/memory && echo "# SP" > .specops/session-progress.md && echo base > README.md \
  && git add -A && git -c user.email=e@t -c user.name=t commit -q -m base && git checkout -q -b feat/batch-p \
  && echo notes > notes.md && git add notes.md && git -c user.email=e@t -c user.name=t commit -q -m "docs: n" \
  && printf '| FR-ID | FID | 설명 | Status |\n|---|---|---|---|\n| FR-4 | 20260721-login | 로그인 | DONE |\n' > .specops/batch-p/queue.md \
  && printf '| FR-4 | a | M1 | must | s | f |\n' > .specops/memory/requirements.md && : > .specops/batch-p/ACTIVE ) >/dev/null 2>&1
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$_prs_d" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$_prs_d" bash "$HOOK" 2>/dev/null)
check "T-prscope.f 범위가 문서뿐인 batch PR → 게이트 면제(allow)" '"continue":true' "$out"
rm -rf "$_prs_b" "$_prs_d"
# c: 대조군 — PR 범위가 진짜 all-docs 면 작업트리 dirty 와 무관하게 면제 유지(과잉 차단 방지)
_prs_doc=$(mktemp -d)
_prs_mk "$_prs_doc" notes.md
out=$(mkstdin "gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_prs_doc" bash "$HOOK" 2>/dev/null)
check "T-prscope.c PR 범위 all-docs → 면제 유지(allow)" '"continue":true' "$out"
rm -rf "$_prs_doc"
# d: base 브랜치(main/master) 부재 → 판정 불가는 비면제로 떨어져 종전 경로(transcript verify 검사)로 간다 = deny 유지
_prs_nb=$(mktemp -d)
( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  cd "$_prs_nb" && git init -q -b trunk && mkdir -p .specops && echo "# SP" > .specops/session-progress.md \
  && git add -A && git -c user.email=e@t -c user.name=t commit -q -m base \
  && echo "dirty" >> .specops/session-progress.md ) >/dev/null 2>&1
out=$(mkstdin "gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_prs_nb" bash "$HOOK" 2>/dev/null)
check "T-prscope.d base 미검출 → 비면제(verify 검사로 진행, deny)" '"permissionDecision":"deny"' "$out"
rm -rf "$_prs_nb"

# ── T-untracked: compound `git add ... && git commit` 은 untracked 신규 코드도 커밋 범위로 본다 ──
# 왜: `git diff HEAD` 는 untracked 를 못 본다. 추적 중 README dirty + untracked 신규 코드 + `git add -A && git commit`
#   이면 작업트리 목록이 README 뿐이라 docs-only 로 면제됐다(실제 커밋엔 신규 코드가 실린다).
_unt_mk() {  # $1=dir $2=untracked 파일명
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd "$1" && git init -q -b main && mkdir -p .specops && echo base > README.md \
    && git add -A && git -c user.email=e@t -c user.name=t commit -q -m base \
    && echo more >> README.md && mkdir -p src && echo "echo n" > "src/$2" ) >/dev/null 2>&1
}
_unt=$(mktemp -d); _unt_mk "$_unt" new.sh
out=$(mkstdin "git add -A && git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_unt" bash "$HOOK" 2>/dev/null)
check "T-untracked.a git add -A && commit + untracked 코드 → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "git add . && git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_unt" bash "$HOOK" 2>/dev/null)
check "T-untracked.b git add . && commit + untracked 코드 → deny" '"permissionDecision":"deny"' "$out"
# c: 대조군 — `commit -am` 은 untracked 를 싣지 않는다 → 종전대로 working-tree docs-only 면제(과잉 차단 방지)
out=$(mkstdin "git commit -am x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_unt" bash "$HOOK" 2>/dev/null)
check "T-untracked.c commit -am (untracked 미포함) → docs-only 면제 유지" '"continue":true' "$out"
rm -rf "$_unt"
# d: 대조군 — untracked 가 문서뿐이면 add -A 여도 면제
_unt2=$(mktemp -d); _unt_mk "$_unt2" x.md
out=$(mkstdin "git add -A && git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_unt2" bash "$HOOK" 2>/dev/null)
check "T-untracked.d untracked 가 문서뿐 → 면제 유지" '"continue":true' "$out"
rm -rf "$_unt2"

# ══════════════════════════════════════════════════════════════════════════
# T-form: 커밋·PR 인식이 **표기에 따라** 빠지지 않는다 (20261009 — 10회차 평가)
#   왜: 트리거가 `git` 글자 앞을 줄머리·구분자·env·래퍼 4종으로만 인정해, 아래 형태가 차단도 감사도 거치지 않았다.
#   전부 정직한 사용에서 나오는 형태다 — 출력 필터를 피하려는 절대경로, 조건문·반복문 안의 커밋, 줄 연속.
#   실측: 이 저장소의 커밋 80건 중 17건이 절대경로 표기라 게이트를 한 번도 거치지 않았다.
#   범위 밖(종전 그대로 — pretool 머리의 F-3): sh -c·eval·xargs·alias·변수에 든 명령.
# ══════════════════════════════════════════════════════════════════════════
_form_deny() {  # $1=id $2=명령
  local o; o=$(mkstdin "$2" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
  check "$1 → deny" '"permissionDecision":"deny"' "$o"
}
_form_allow() {  # $1=id $2=명령 — 커밋이 아닌 명령은 그대로 통과한다(거짓 차단 금지)
  local o; o=$(mkstdin "$2" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
  if printf '%s' "$o" | grep -q '"permissionDecision":"deny"'; then echo "FAIL $1 — 커밋이 아닌 명령이 막힘: $2"; fail=$((fail+1));
  else check "$1 → allow" '"continue":true' "$o"; fi
}
_form_deny "T-form.a 절대경로 /usr/bin/git commit" '/usr/bin/git commit -m x'
_form_deny "T-form.a2 상대경로 ./bin/git commit" './bin/git commit -m x'
_form_deny "T-form.a3 역슬래시 \\git commit" '\git commit -m x'
_form_deny "T-form.a4 절대경로 + heredoc 메시지" "/usr/bin/git commit -q -F - <<'EOF'
feat: x
EOF"
_form_deny "T-form.b if…then 안의 커밋" 'if true; then git commit -m x; fi'
_form_deny "T-form.b2 else 안의 커밋" 'if false; then :; else git commit -m x; fi'
_form_deny "T-form.b3 if 조건 자리의 커밋" 'if git commit -m x; then echo ok; fi'
_form_deny "T-form.c for…do 안의 커밋" 'for f in a b; do git commit -m x; done'
_form_deny "T-form.c2 while…do 안의 커밋" 'while read -r l; do git commit -m x; done < list'
_form_deny "T-form.d 부정 ! git commit" 'cd sub && ! git commit -m x'
_form_deny "T-form.e exec git commit" 'exec git commit -m x'
_form_deny "T-form.e2 nohup git commit" 'nohup git commit -m x'
_form_deny "T-form.e3 timeout 10 git commit" 'timeout 10 git commit -m x'
_form_deny "T-form.e4 sudo -u u git commit" 'sudo -u u git commit -m x'
_form_deny "T-form.e5 래퍼 겹침 time nice git commit" 'time nice git commit -m x'
_form_deny "T-form.f 붙여 쓴 -c 옵션" 'git -ccore.x=1 commit -m x'
_form_deny "T-form.g 줄 연속 git \\⏎ commit" 'git \
  commit -m x'
_form_deny "T-form.g2 줄 연속 + -C" 'git -C . \
  commit -m x'
_form_deny "T-form.h then + 절대경로 + env 겹침" 'if x; then FOO=1 /usr/bin/git commit -m x; fi'
_form_deny "T-form.e6 time -p git commit" 'time -p git commit -m x'
_form_deny "T-form.e7 sudo -E git commit" 'sudo -E git commit -m x'
_form_deny "T-form.e8 env -i git commit" 'env -i git commit -m x'
_form_deny "T-form.e9 env -u FOO git commit" 'env -u FOO git commit -m x'
_form_deny "T-form.e10 sudo -u u -g g git commit" 'sudo -u u -g g git commit -m x'
_form_deny "T-form.i case 가지의 커밋" 'case x in x) git commit -m x;; esac'
_form_deny "T-form.e11 경로로 부른 래퍼 /usr/bin/env git commit" '/usr/bin/env git commit -m x'
_form_deny "T-form.e12 timeout -k 5 30s git commit" 'timeout -k 5 30s git commit -m x'
_form_deny "T-form.e13 timeout -s KILL 10 git commit" 'timeout -s KILL 10 git commit -m x'
_form_deny "T-form.e14 /usr/bin/sudo -E /usr/bin/git commit" '/usr/bin/sudo -E /usr/bin/git commit -m x'
# 줄 연속을 **이은 문자열만** 보면 놓치는 실커밋 — 주석 끝의 `\` 와 `\\` 는 줄을 잇지 않는다(다음 줄은 실제로 실행된다).
#   잇기 전 원문도 함께 본다: 종전에 막히던 명령이 새 전처리 때문에 열리면 안 된다.
_form_deny "T-form.g3 ★ 주석 줄 끝 \\ 다음 줄의 커밋" '# note \
git commit -m x'
_form_deny "T-form.g4 ★ \\\\ 로 끝난 줄 다음의 커밋" 'echo foo\\
git commit -m x'
_form_deny "T-form.g5 ★ 주석 줄 끝 \\ 다음 줄의 PR 생성" '# note \
gh pr create --fill'
_form_deny "T-form.r gh pr -R o/r create" 'gh pr -R o/r create --fill'
_form_deny "T-form.r2 gh -R o/r pr create" 'gh -R o/r pr create --fill'
_form_deny "T-form.r3 gh --repo=o/r pr create" 'gh --repo=o/r pr create --fill'
_form_deny "T-form.r4 절대경로 gh pr create" '/opt/homebrew/bin/gh pr create --fill'
_form_deny "T-form.r5 then gh pr create" 'if x; then gh pr create --fill; fi'
# 음성 — 커밋·PR 생성이 아닌 명령
_form_allow "T-form.n1 경로 인자에 든 git" 'ls /usr/bin/git commit'
_form_allow "T-form.n2 echo 인자의 then" 'echo then git commit'
_form_allow "T-form.n11 time -p 뒤 다른 명령의 인자" 'time -p ls git commit'
_form_allow "T-form.n12 env -i 뒤 다른 명령의 인자" 'env -i ls git commit'
_form_allow "T-form.n13 timeout 뒤 다른 명령의 인자" 'timeout -k 5 30s ls git commit'
_form_allow "T-form.n14 경로로 부른 env 뒤 다른 명령의 인자" '/usr/bin/env ls git commit'
_form_allow "T-form.n3 인용 문자열 안의 제어문" 'printf "%s\n" "if x; then git commit; fi"'
_form_allow "T-form.n4 grep 패턴" "grep -rn 'do git commit' ."
_form_allow "T-form.n5 commit-graph" '/usr/bin/git commit-graph write'
_form_allow "T-form.n6 래퍼 + 다른 하위명령" 'timeout 10 git status'
_form_allow "T-form.n7 heredoc 데이터 안의 절대경로 커밋" "cat > notes.md <<'EOF'
/usr/bin/git commit -m x
if x; then git commit; fi
EOF"
_form_allow "T-form.n8 gh pr view" 'gh pr -R o/r view 3'
_form_allow "T-form.n9 gh pr created 접두 단어" 'gh pr created-list'
_form_allow "T-form.n10 줄 연속 뒤가 commit 이 아님" 'git \
  status'
# 사후 감사도 같은 패턴을 쓴다 — 절대경로 커밋이 감사 기록에 남는다 (종전 0건)
_pa=$(mktemp -d) || exit 1
( cd "$_pa" && git init -q -b main && git config user.email a@b && git config user.name a && mkdir .specops \
  && echo base > README.md && git add README.md && git commit -qm base && echo 'echo x' > a.sh && git add a.sh && git commit -qm "feat: code" ) >/dev/null 2>&1
jq -nc --arg t "$FIX/pretool-no-verify.jsonl" '{tool_name:"Bash",tool_input:{command:"/usr/bin/git commit -m \"feat: code\""},tool_response:{},transcript_path:$t}' \
  | CLAUDE_PROJECT_DIR="$_pa" bash "$PLUGIN/hooks/posttool-governance.sh" >/dev/null 2>&1
if grep -qs '"rule_id":"R-1"' "$_pa/.specops/friction-log.jsonl"; then
  echo "PASS T-form.p 절대경로 커밋 → 사후 감사 R-1 기록"; pass=$((pass+1))
else echo "FAIL T-form.p 절대경로 커밋이 사후 감사에 남지 않음"; fail=$((fail+1)); fi
# 사후 감사도 잇기 전 원문을 함께 본다 — 주석 줄 끝 `\` 다음 줄의 커밋
rm -f "$_pa/.specops/friction-log.jsonl"
jq -nc --arg t "$FIX/pretool-no-verify.jsonl" --arg c '# note \
git commit -m "feat: code"' '{tool_name:"Bash",tool_input:{command:$c},tool_response:{},transcript_path:$t}' \
  | CLAUDE_PROJECT_DIR="$_pa" bash "$PLUGIN/hooks/posttool-governance.sh" >/dev/null 2>&1
if grep -qs '"rule_id":"R-1"' "$_pa/.specops/friction-log.jsonl"; then
  echo "PASS T-form.p2 ★ 주석 줄 끝 \\ 다음 줄의 커밋 → 사후 감사 R-1 기록"; pass=$((pass+1))
else echo "FAIL T-form.p2 주석 줄 끝 \\ 다음 줄의 커밋이 사후 감사에 남지 않음"; fail=$((fail+1)); fi
rm -rf "$_pa"
# docs-only 면제는 표기와 무관하다 — 절대경로로 문서만 staged 해 커밋하면 작업트리의 코드 변경에 막히지 않는다
_fd=$(mktemp -d) || exit 1
( cd "$_fd" && git init -q && git config user.email a@b && git config user.name a && mkdir .specops && echo 'echo v1' > a.sh && git add a.sh \
  && git commit -qm base && echo 'echo v2' > a.sh && echo doc > NOTES.md && git add NOTES.md ) >/dev/null 2>&1
out=$(mkstdin '/usr/bin/git commit -m "docs: notes"' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_fd" bash "$HOOK" 2>/dev/null)
check "T-form.s 절대경로 + 문서만 staged(코드는 작업트리에만) → allow" '"continue":true' "$out"
out=$(mkstdin 'git commit -m "docs: notes"' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_fd" bash "$HOOK" 2>/dev/null)
check "T-form.s2 대조 — 같은 상태의 맨 git commit → allow" '"continue":true' "$out"
( cd "$_fd" && git add a.sh ) >/dev/null 2>&1
out=$(mkstdin '/usr/bin/git commit -m "docs: notes"' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_fd" bash "$HOOK" 2>/dev/null)
check "T-form.s3 절대경로 + 코드까지 staged → deny" '"permissionDecision":"deny"' "$out"
rm -rf "$_fd"
# batch PR 게이트도 같은 인식을 쓴다 — `gh pr -R … create` 로 뭉개진 batch PR 이 빠져나가지 않는다
_bsf=$(_mk_batch_sandbox "DONE" 0)   # 새 샌드박스 — 앞선 batch 테스트들이 bs_bad 를 정리했다
out=$(mkstdin "gh pr -R o/r create --fill" "$(_tr_for "$_bsf" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$_bsf" bash "$HOOK" 2>/dev/null)
check "T-form.t 뭉개진 batch + gh pr -R … create → BATCH-GATE deny" 'BATCH-GATE' "$out"
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$_bsf" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$_bsf" bash "$HOOK" 2>/dev/null)
check "T-form.t2 대조 — 같은 샌드박스의 gh pr create → BATCH-GATE deny" 'BATCH-GATE' "$out"
rm -rf "$_bsf"

# PR 생성으로 인식된 뒤의 세 판정(PR 범위·batch 게이트·release-ready)도 같은 표기를 읽는다 —
#   인식만 되고 범위는 작업트리로 판정되면, 문서 하나만 dirty 해도 커밋된 미검증 코드의 PR 이 면제된다.
_pg=$(mktemp -d); _prs_mk "$_pg" a.sh
out=$(mkstdin "gh pr -R o/r create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_pg" bash "$HOOK" 2>/dev/null)
check "T-form.u ★ gh pr -R … create + 커밋된 코드 + 작업트리 docs dirty → deny (PR 범위로 판정)" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "gh -R o/r pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_pg" bash "$HOOK" 2>/dev/null)
check "T-form.u2 gh -R … pr create 도 같다" '"permissionDecision":"deny"' "$out"
rm -rf "$_pg"
_pg=$(mktemp -d); _prs_mk "$_pg" notes.md
out=$(mkstdin "gh pr -R o/r create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_pg" bash "$HOOK" 2>/dev/null)
check "T-form.u3 대조 — PR 범위가 문서뿐이면 같은 표기로도 면제" '"continue":true' "$out"
# 커밋을 함께 하는 compound 는 PR 범위가 아니라 종전 경로(작업트리)로 본다 — 범위가 아직 확정 전이다.
#   PR 범위는 문서뿐이지만 staged 에 코드가 있다. PR 범위로 보면 면제되고(틀림), 작업트리로 보면 막힌다(맞음).
( cd "$_pg" && echo "echo y" > b.sh && git add b.sh ) >/dev/null 2>&1
out=$(mkstdin "git commit -m x && gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_pg" bash "$HOOK" 2>/dev/null)
check "T-form.w ★ commit && pr create (PR 범위는 문서뿐 · staged 에 코드) → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin "git stage b.sh && gh pr create --fill" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_pg" bash "$HOOK" 2>/dev/null)
check "T-form.w2 git stage 를 함께 하는 compound 도 종전 경로 → deny" '"permissionDecision":"deny"' "$out"
rm -rf "$_pg"
# `git stage` 는 `git add` 와 같다 — untracked 신규 코드가 커밋에 실린다
_ug=$(mktemp -d); _unt_mk "$_ug" new.sh
out=$(mkstdin "git stage -A && git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_ug" bash "$HOOK" 2>/dev/null)
check "T-form.x ★ git stage -A && commit + untracked 코드 → deny" '"permissionDecision":"deny"' "$out"
rm -rf "$_ug"
# release-ready 게이트도 같은 표기를 읽는다 (T-mut.c 와 같은 픽스처 — batch 게이트는 통과하고 release-ready 축 하나만 깨뜨린다)
_rg=$(_mk_batch_sandbox "IMPL_DONE" 1 1)
sed -i.bak 's/§NFR L8-12 — 성능 임계값 없음/성능 임계값 없음/' "$_rg"/.specops/*/evidence.md
out=$(mkstdin "gh pr -R o/r create --fill" "$(_tr_for "$_rg" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$_rg" bash "$HOOK" 2>/dev/null)
check "T-form.v ★ gh pr -R … create + NOT_READY batch → RELEASE_READY deny" 'RELEASE_READY' "$out"
rm -rf "$_rg"
# batch 의 IMPL_DONE FID **전부**를 본다 — 활성 FID 하나로 대신하지 않는다.
#   둘째 FID 만 게이트 기록이 없다. 활성 FID(첫 헤더)는 완비라, 목록을 못 읽고 활성 FID 로 떨어지면 통과해 버린다.
_rb=$(_mk_batch_sandbox "IMPL_DONE" 1 1)
printf '| FR-5 | 20260722-second | 둘째 | IMPL_DONE |\n' >> "$_rb/.specops/batch-p/queue.md"
printf '| FR-5 | b | M1 | must | s | f |\n' >> "$_rb/.specops/memory/requirements.md"
mkdir -p "$_rb/.specops/20260722-second"
: > "$_rb/.specops/20260722-second/review-base.sha"; : > "$_rb/.specops/20260722-second/review-request.md"
printf 'RUN-VERIFICATION-RESULT: PASS\n' > "$_rb/.specops/20260722-second/evidence.md"
printf '\n## 20260722-second\n\n- 2026-07-22 13:53 /verify PASS (evidence.md)\n- 2026-07-22 14:00 /request-review DONE\n' >> "$_rb/.specops/session-progress.md"
out=$(mkstdin "gh pr create --fill" "$(_tr_for "$_rb" "$FIX/pretool-with-verify-exec.jsonl")" | CLAUDE_PROJECT_DIR="$_rb" bash "$HOOK" 2>/dev/null)
check "T-form.y ★ batch 의 둘째 FID 만 미완 → deny" '"permissionDecision":"deny"' "$out"
check "T-form.y2 사유가 그 FID 를 지목한다" 'FID 20260722-second' "$out"
rm -rf "$_rb"

# ══════════════════════════════════════════════════════════════════════════
# T-vstale: 검증 PASS 뒤 **셸로** 코드를 고친 커밋은 통과하지 않는다 (20261009)
#   왜: 검증 무효화는 transcript 의 Edit/Write 이벤트로만 판정했다. `sed -i`·`echo >`·포매터·코드 생성기·
#   서브에이전트의 수정은 그 이벤트가 없어, 판정 SoT(verification-state)가 STALE 이라고 답하는데도 커밋이 열렸다.
# ══════════════════════════════════════════════════════════════════════════
_VS=$(mktemp -d) || exit 1
mkdir -p "$_VS/.specops/20260101-x"
( cd "$_VS" && git init -q && printf 'echo v1\n' > a.sh && git add a.sh && git -c user.name=t -c user.email=t@e.com commit -qm init ) >/dev/null 2>&1
( cd "$_VS" && printf 'echo v2\n' > a.sh && git add a.sh \
  && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" record 20260101-x PASS --executed 1 --failed 0 ) >/dev/null 2>&1
printf '<!-- active-fid: 20260101-x -->\n## 20260101-x\n- 2099-01-01 10:00 /verify PASS (evidence.md)\n' > "$_VS/.specops/session-progress.md"
_vin=$(mkstdin 'git commit -m "feat: v2"' "$FIX/exec-evidence-pass.jsonl")
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.a 대조 — 검증한 그대로 커밋 → allow" '"continue":true' "$out"
( cd "$_VS" && printf 'echo UNVERIFIED\n' > a.sh && git add a.sh )   # 셸로 수정 — transcript 에 Edit 이벤트 없음
_vv=$(cd "$_VS" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" current 20260101-x)
[ "$_vv" = "STALE" ] && { echo "PASS T-vstale.b-0 픽스처 STALE 성립"; pass=$((pass+1)); } \
  || { echo "FAIL T-vstale.b-0 픽스처 verdict=$_vv (STALE 아님)"; fail=$((fail+1)); }
msg=$(_deny_msg "$_VS" "$HOOK" "$_vin")
check "T-vstale.b ★ 검증 뒤 셸 수정 → deny" 'verify 면제 조건' "$msg"
check "T-vstale.b2 사유가 '검증 이후 코드가 바뀌었다' 고 말한다" '검증 이후 코드가 바뀌었습니다' "$msg"
_nocheck "T-vstale.b3 '러너 실행 기록이 없다' 는 거짓 원인을 말하지 않는다" '이 세션에 러너 실행 기록이 없습니다' "$msg"
# 안내가 "막히는 표기" 를 글자 그대로 적는다 — 이 줄의 `&&` 가 `||` 로 바뀌어도 살아남았다(문안 변이).
#   거부 사유가 틀린 표기를 가리키면 사용자는 막히지 않는 명령을 고치느라 헤맨다.
check "T-vstale.b5 사유가 한 번에 실행하는 표기(&&·;·파이프)를 그대로 적는다" '`&&`·`;`·파이프' "$msg"
# PR 생성(R-2)은 이 검사의 대상이 아니다 — R-2 는 커밋 범위를 보고, 작업트리의 미커밋 변경은 PR 에 실리지 않는다
out=$(mkstdin 'gh pr create --fill' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
if printf '%s' "$out" | grep -q '검증 이후 코드가 바뀌었습니다'; then
  echo "FAIL T-vstale.b4 작업트리 STALE 이 PR 생성을 막음 — R-1 한정이어야 한다"; fail=$((fail+1))
else echo "PASS T-vstale.b4 STALE 검사는 R-1 한정 (PR 생성에는 적용하지 않는다)"; pass=$((pass+1)); fi
# 전체 스위트가 **지금 이 트리**에서 통과했으면 STALE 이어도 막지 않는다.
#   run-all.sh 는 `VERIFY: PASS` 를 내는 정식 러너인데 판정 상태(verification-state)를 갱신하지 않는다 —
#   리뷰 지적을 고치고 전체 스위트를 다시 통과시킨 정직한 흐름이 "검증 이후 코드가 바뀌었다" 로 막혔다.
_fp=$( cd "$_VS" && . "$PLUGIN/scripts/_internal/verification-state.sh" && vs::nondoc_fingerprint )
printf '%s\n' "$_fp" > "$_VS/.specops/.full-suite-pass"
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.e ★ STALE 이지만 전체 스위트가 이 트리에서 통과 → allow" '"continue":true' "$out"
printf 'deadbeef\n' > "$_VS/.specops/.full-suite-pass"
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.e2 통과 마커가 다른 트리의 것 → deny" '"permissionDecision":"deny"' "$out"
rm -f "$_VS/.specops/.full-suite-pass"
# 문서만 고친 것은 STALE 이 아니다 — 그대로 통과한다 (거짓 차단 금지)
( cd "$_VS" && printf 'echo v2\n' > a.sh && git add a.sh && printf '# notes\n' > NOTES.md )
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.c 검증 뒤 문서만 추가 → allow" '"continue":true' "$out"
# 검증 뒤 생긴 **추적하지 않는 파일**(로그·캐시·.DS_Store)은 이 커밋에 실리지 않는다 — 막지 않는다.
#   판정 SoT 는 그대로 STALE 이다(작업트리 전체를 본다). R-1 이 묻는 것은 "커밋되는 내용이 검증됐는가" 다.
( cd "$_VS" && printf 'log\n' > build.log )
_vv=$(cd "$_VS" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" current 20260101-x)
[ "$_vv" = "STALE" ] && { echo "PASS T-vstale.f-0 픽스처 STALE 성립(untracked 파일)"; pass=$((pass+1)); } \
  || { echo "FAIL T-vstale.f-0 픽스처 verdict=$_vv (STALE 아님)"; fail=$((fail+1)); }
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f ★ 검증 뒤 untracked 파일만 생김 → allow" '"continue":true' "$out"
# 커밋 메시지에 든 낱말(add·stage)은 git add 가 아니다 — 영문 저장소의 기본형(`feat: add …`)이 면제를 끄면 안 된다
out=$(mkstdin 'git commit -m "feat: add login"' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f1 ★ 메시지에 add 가 든 커밋 → allow" '"continue":true' "$out"
out=$(mkstdin "git commit -m 'stage 2 of the add flow' -m \"git add later\"" "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f1b 메시지에 stage·git add 글자 → allow" '"continue":true' "$out"
out=$(mkstdin "git commit -F - <<'EOF'
feat: x

git add was the wrong call here
EOF" "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f1e heredoc 메시지 줄머리의 git add → allow" '"continue":true' "$out"
# 이미 있던 untracked 파일이 **바뀐** 경우도 같다 (검증 때부터 있던 로그에 덧붙음 — 가장 흔한 형태)
( cd "$_VS" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" record 20260101-x PASS --executed 1 --failed 0 ) >/dev/null 2>&1
( cd "$_VS" && printf 'more\n' >> build.log )
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f1d ★ 검증 때부터 있던 untracked 파일이 바뀜 → allow" '"continue":true' "$out"
# `-a` 는 받는다 — 추적 파일의 작업트리 내용은 추적 지문이 이미 본다. 안전 prelude(cd 한 줄) 뒤의 커밋도 같다.
out=$(mkstdin 'git commit -am "feat: v2"' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f1g git commit -am → allow" '"continue":true' "$out"
out=$(mkstdin 'cd .
/usr/bin/git commit -q -m x' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f1h cd 한 줄 뒤 경로로 부른 git commit → allow" '"continue":true' "$out"
# 커밋을 다른 명령과 한 번에 실행하면 적용하지 않는다 — 무엇이 안전한지 명령 글자로 가려내지 않는다(조회용 명령이어도 같다)
out=$(mkstdin 'git status --short && git commit -m x' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f1f ★ 조회용 명령과 함께여도 compound → deny" '"permissionDecision":"deny"' "$out"
# 같은 명령에서 git add 를 하면 그 파일이 커밋에 실린다 — 막는다
out=$(mkstdin 'git add -A && git commit -m x' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f2 ★ 같은 명령에서 git add → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin '/usr/bin/git -C . stage build.log; git commit -m x' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f2b 경로로 부른 git stage 도 같다 → deny" '"permissionDecision":"deny"' "$out"
out=$(mkstdin 'if true; then git -C . add -N build.log; fi
git commit -am x' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f2c then 안의 git -C . add → deny" '"permissionDecision":"deny"' "$out"
# add·stage 말고도 인덱스에 올리는 길이 있다 — 조회용이 아닌 하위명령은 전부 같은 취급이다
out=$(mkstdin 'git update-index --add build.log && git commit -m x' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f2d ★ git update-index --add 를 함께 → deny" '"permissionDecision":"deny"' "$out"
# 감싼 git·설정 변경·출력 옵션 — 명령 글자를 해석하는 방식이 놓치던 표기들(독립 리뷰가 재현했다)
for _c in 'git ls-files -o --exclude-standard | xargs git add && git commit -m x' \
          'find . -name build.log -exec git add {} \; && git commit -m x' \
          'sh -c "git add -A" && git commit -m x' \
          'git config core.hooksPath hk && git commit -m x' \
          'git diff --output=a.sh; git commit -am x' \
          'git --no-lazy-fetch add -A && git commit -m x' \
          'git commit -m x build.log' \
          'git commit -m "$(git add -A)"'; do
  out=$(mkstdin "$_c" "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
  check "T-vstale.f2e ★ 커밋만 하는 명령이 아님 → deny ($_c)" '"permissionDecision":"deny"' "$out"
done
msg=$(_deny_msg "$_VS" "$HOOK" "$(mkstdin 'git add -A && git commit -m x' "$FIX/exec-evidence-pass.jsonl")")
check "T-vstale.f2f 사유가 '커밋만 따로 실행' 을 안내한다" '만 따로 실행하세요' "$msg"
( cd "$_VS" && git add build.log )
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f3 ★ 그 파일을 인덱스에 올림(staged 신규) → deny" '"permissionDecision":"deny"' "$out"
( cd "$_VS" && git reset -q build.log && git add -N build.log )
out=$(mkstdin 'git commit -am x' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f4 ★ intent-to-add(git add -N) + commit -a → deny" '"permissionDecision":"deny"' "$out"
( cd "$_VS" && git reset -q build.log && printf 'echo CHANGED\n' > a.sh )
out=$(mkstdin 'git commit -am x' "$FIX/exec-evidence-pass.jsonl" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.f5 ★ untracked 파일 + 추적 파일 수정 → deny" '"permissionDecision":"deny"' "$out"
( cd "$_VS" && rm -f build.log && printf 'echo v2\n' > a.sh && git add a.sh )
# 검증 상태 기록이 없는 FID(진행 기록 앵커만 쓰는 흐름)는 종전대로다
rm -f "$_VS/.specops/20260101-x/verification-state.json"
( cd "$_VS" && printf 'echo other\n' > a.sh && git add a.sh )
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.d 상태 기록 없는 FID → 종전 판정(allow)" '"continue":true' "$out"
# 지문 없는 PASS 기록(손으로 쓴 것)은 STALE 이다 — 진행 기록과 실행 증거가 있어도 커밋이 열리지 않는다 (20261010-hashless-pass-stale).
#   바로 위(기록 파일 자체가 없음 → 종전 판정)와 다르다: 파일이 있으면 그 파일이 판정 SoT 이고, 비교할 지문이 없는 PASS 는 유효하지 않다.
printf '{"schema_version":1,"fid":"20260101-x","verdict":"PASS","executed":2,"skipped":0,"failed":0}\n' \
  > "$_VS/.specops/20260101-x/verification-state.json"
msg=$(_deny_msg "$_VS" "$HOOK" "$_vin")
check "T-vstale.g ★ 지문 없는 PASS 기록 + 커밋 → deny" 'verify 면제 조건' "$msg"
check "T-vstale.g2 사유가 지문 없는 기록도 STALE 이라고 말한다" '검증 기록에 지문이 없어' "$msg"
# 전체 스위트가 지금 이 트리에서 통과했으면 종전 STALE 과 같은 예외로 열린다 (정직한 흐름의 출구는 같다)
_fp=$( cd "$_VS" && . "$PLUGIN/scripts/_internal/verification-state.sh" && vs::nondoc_fingerprint )
printf '%s\n' "$_fp" > "$_VS/.specops/.full-suite-pass"
out=$(printf '%s' "$_vin" | CLAUDE_PROJECT_DIR="$_VS" bash "$HOOK" 2>/dev/null)
check "T-vstale.g3 지문 없는 PASS 기록이어도 전체 스위트가 이 트리에서 통과 → allow" '"continue":true' "$out"
rm -rf "$_VS"

# ══════════════════════════════════════════════════════════════════════════
# T-fidbind: 다른 FID 의 run-verification 출력은 이 FID 의 실행 증거가 아니다 (20261009)
#   왜: 실행 증거는 "러너가 돌았다" 만 보고 **어느 FID 를** 검증했는지 보지 않았다. 한 세션에서 FID 여럿을 다루면
#   (batch) 앞 FID 의 PASS 가 뒤 FID 의 커밋을 열었다 — 뒤 FID 의 진행 기록 한 줄만 쓰면 된다.
#   FID 가 글자로 적힌 경우만 대조한다 — 변수(`"$FID"`)·run-all.sh 는 판단하지 않는다(거짓 차단 금지).
# ══════════════════════════════════════════════════════════════════════════
_FB=$(mktemp -d) || exit 1
mkdir -p "$_FB/.specops/20260202-mine"
( cd "$_FB" && git init -q && printf 'echo x\n' > a.sh && git add a.sh ) >/dev/null 2>&1
printf '<!-- active-fid: 20260202-mine -->\n## 20260202-mine\n- 2099-01-01 10:00 /verify PASS (evidence.md)\n' > "$_FB/.specops/session-progress.md"
_fb_tr() {  # $1=러너 명령 → transcript 경로
  local f; f=$(mktemp)
  jq -nc --arg c "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_A",name:"Bash",input:{command:$c}}]}}' > "$f"
  jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_A",is_error:false,content:"VERIFY: PASS"}]}}' >> "$f"
  printf '%s' "$f"
}
_t=$(_fb_tr 'bash /p/scripts/_internal/run-verification.sh 20260101-other')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.a ★ 다른 FID 의 러너 PASS → deny" '"permissionDecision":"deny"' "$out"
msg=$(_deny_msg "$_FB" "$HOOK" "$(mkstdin 'git commit -m x' "$_t")")
check "T-fidbind.a2 사유가 '다른 FID' 라고 말한다" '다른 FID' "$msg"
_nocheck "T-fidbind.a3 '러너 실행 기록이 없다' 는 거짓 원인을 말하지 않는다" '이 세션에 러너 실행 기록이 없습니다' "$msg"; rm -f "$_t"
_t=$(_fb_tr 'bash /p/scripts/_internal/run-verification.sh 20260202-mine')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.b 대조 — 이 FID 의 러너 PASS → allow" '"continue":true' "$out"; rm -f "$_t"
_t=$(_fb_tr 'bash "/p/scripts/_internal/run-verification.sh" "20260202-mine"')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.b2 인용된 FID → allow" '"continue":true' "$out"; rm -f "$_t"
_t=$(_fb_tr 'FID=20260202-mine
bash /p/scripts/_internal/run-verification.sh "$FID"')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.c FID 가 변수 → 판단하지 않는다(allow)" '"continue":true' "$out"; rm -f "$_t"
_t=$(_fb_tr 'bash scripts/tests/run-all.sh')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.d run-all.sh(FID 인자 없음) → allow" '"continue":true' "$out"; rm -f "$_t"
_t=$(_fb_tr 'bash /p/scripts/_internal/run-verification.sh 20260101-other
bash /p/scripts/_internal/run-verification.sh 20260202-mine')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.e 여러 FID 를 한 명령에서 — 이 FID 가 들어 있으면 allow" '"continue":true' "$out"; rm -f "$_t"
_t=$(_fb_tr 'bash /p/scripts/_internal/run-verification.sh 20260202-mine-two')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.f 접두만 같은 다른 FID → deny" '"permissionDecision":"deny"' "$out"; rm -f "$_t"
# 백그라운드로 띄우고 출력 파일을 Read 로 회수한 경로에도 같은 대조가 걸린다
_fb_bg() {  # $1=러너 명령 → transcript 경로 (bg 스텁 → 그 경로를 Read → VERIFY: PASS)
  local f; f=$(mktemp)
  jq -nc --arg c "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_B",name:"Bash",input:{command:$c,run_in_background:true}}]}}' > "$f"
  jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_B",is_error:false,content:"Command running in background with ID: b1. Output is being written to: /tmp/bg-out.txt. You will be notified."}]}}' >> "$f"
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_R",name:"Read",input:{file_path:"/tmp/bg-out.txt"}}]}}' >> "$f"
  jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_R",is_error:false,content:"VERIFY: PASS"}]}}' >> "$f"
  printf '%s' "$f"
}
_t=$(_fb_bg 'bash /p/scripts/_internal/run-verification.sh 20260202-mine')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.g 대조 — 이 FID 의 백그라운드 러너 + Read 회수 → allow" '"continue":true' "$out"; rm -f "$_t"
_t=$(_fb_bg 'bash /p/scripts/_internal/run-verification.sh 20260101-other')
out=$(mkstdin 'git commit -m x' "$_t" | CLAUDE_PROJECT_DIR="$_FB" bash "$HOOK" 2>/dev/null)
check "T-fidbind.h ★ 다른 FID 의 백그라운드 러너 + Read 회수 → deny" '"permissionDecision":"deny"' "$out"; rm -f "$_t"
rm -rf "$_FB"

# ══════════════════════════════════════════════════════════════════════════
# T-off: 설정 파일로 차단 훅을 끄면 그 사실이 기록에 남는다 (20261009)
#   왜: 인라인 우회는 사유를 요구하고 기록되는데, `.specops/config.yaml` 한 줄로 끄는 길은 아무 기록도 남기지 않았다.
#   그 파일은 모델도 쓸 수 있고 문서 면제 클래스다. 끄는 것은 막지 않는다(사용자 주권) — 꺼져 있었다는 사실만 남긴다.
# ══════════════════════════════════════════════════════════════════════════
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  _OF=$(mktemp -d) || exit 1
  ( cd "$_OF" && git init -q && echo "echo x" > a.sh && git add a.sh && mkdir .specops \
    && printf 'hooks:\n  pretool-governance:\n    enabled: false\n' > .specops/config.yaml ) >/dev/null 2>&1
  # 킬스위치 판정(is-hook-enabled)은 훅의 cwd 기준이다 — CLAUDE_PROJECT_DIR 앵커보다 앞에서 돈다. 그래서 cd 한다.
  out=$(cd "$_OF" && mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_OF" bash "$HOOK" 2>/dev/null)
  check "T-off.a 꺼진 훅 → allow (끄는 것은 막지 않는다)" '"continue":true' "$out"
  if grep -q '"rule_id":"GOVERNANCE-DISABLED"' "$_OF/.specops/friction-log.jsonl" 2>/dev/null; then
    echo "PASS T-off.b ★ 꺼진 채 커밋 → GOVERNANCE-DISABLED 기록"; pass=$((pass+1))
  else echo "FAIL T-off.b 꺼진 훅이 기록을 남기지 않음"; fail=$((fail+1)); fi
  if grep -q 'SPECOPS_GOVERNANCE_PROFILE' "$_OF/.specops/friction-log.jsonl" 2>/dev/null; then
    echo "FAIL T-off.b2 기록이 프로파일 환경변수를 원인으로 든다 — 그 변수로는 차단 훅이 꺼지지 않는다"; fail=$((fail+1))
  else echo "PASS T-off.b2 기록 문안이 실제 원인(설정 파일)만 말한다"; pass=$((pass+1)); fi
  # 꺼진 훅의 기록도 잇기 전 원문을 함께 본다 — 주석 줄 끝 `\` 다음 줄의 커밋
  rm -f "$_OF/.specops/friction-log.jsonl"
  ( cd "$_OF" && mkstdin '# note \
git commit -m x' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_OF" bash "$HOOK" >/dev/null 2>&1 )
  grep -qs '"rule_id":"GOVERNANCE-DISABLED"' "$_OF/.specops/friction-log.jsonl" \
    && { echo "PASS T-off.b3 주석 줄 끝 \\ 다음 줄의 커밋도 기록"; pass=$((pass+1)); } \
    || { echo "FAIL T-off.b3 주석 줄 끝 \\ 다음 줄의 커밋이 기록되지 않음"; fail=$((fail+1)); }
  # 커밋·PR 이 아닌 명령에는 남기지 않는다 (기록 폭주 방지)
  rm -f "$_OF/.specops/friction-log.jsonl"
  ( cd "$_OF" && mkstdin "ls -la" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_OF" bash "$HOOK" >/dev/null 2>&1 )
  [ ! -f "$_OF/.specops/friction-log.jsonl" ] && { echo "PASS T-off.c 커밋이 아닌 명령 → 기록 없음"; pass=$((pass+1)); } \
    || { echo "FAIL T-off.c 무관한 명령에도 기록"; fail=$((fail+1)); }
  # .specops 가 없는 저장소에는 남기지 않는다 (관할 한정)
  _OF2=$(mktemp -d) || exit 1
  ( cd "$_OF2" && git init -q && echo "echo x" > a.sh && git add a.sh ) >/dev/null 2>&1
  ( cd "$_OF2" && mkstdin "git commit -m x" "$FIX/pretool-no-verify.jsonl" | SPECOPS_CONFIG="$_OF/.specops/config.yaml" CLAUDE_PROJECT_DIR="$_OF2" bash "$HOOK" >/dev/null 2>&1 )
  [ ! -e "$_OF2/.specops" ] && { echo "PASS T-off.d .specops 부재 → 기록·디렉토리 없음"; pass=$((pass+1)); } \
    || { echo "FAIL T-off.d 비도입 저장소에 흔적"; fail=$((fail+1)); }
  rm -rf "$_OF" "$_OF2"
else
  echo "SKIP T-off (python3+pyyaml 부재 — 설정 파일 킬스위치 시뮬레이션 불가)"
fi

# ══════════════════════════════════════════════════════════════════════════
# T-pipe: 첫 관문이 일치를 "파이프 뒤 grep -q" 로 읽지 않는다 (20261010-hook-sigpipe-test-eval)
#   왜: 훅은 `set -uo pipefail` 이다. `producer | grep -q` 는 grep 이 첫 일치에서 끝나는 순간 앞단이 아직 쓰는 중이면
#   앞단이 SIGPIPE(141)로 죽고 파이프 전체가 실패가 된다 — 커밋을 찾고도 "커밋이 아니다" 로 읽어 통째로 통과시켰다.
#   실측(수정 전 main · 각 5회): 인용 메시지 + 줄 연속 커밋 5/5 통과 · gh pr create 5/5 통과 · 커밋 뒤 큰 여러 줄 5/5 통과.
#   경합으로 새던 자리라 형태마다 5회 반복하고 전부 막혀야 통과다.
# ══════════════════════════════════════════════════════════════════════════
_form_deny5() {  # $1=id $2=명령
  local i=0 n=0 o
  while [ "$i" -lt 5 ]; do
    o=$(mkstdin "$2" "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$codesandbox" bash "$HOOK" 2>/dev/null)
    case "$o" in *'"permissionDecision":"deny"'*) n=$((n+1)) ;; esac
    i=$((i+1))
  done
  if [ "$n" -eq 5 ]; then echo "PASS $1 → deny 5/5"; pass=$((pass+1)); else echo "FAIL $1 — deny $n/5 (전부 막혀야 한다)"; fail=$((fail+1)); fi
}
#   크기는 약 103KB 로 둔다: 파이프 버퍼(64KB)보다 커야 재현되고, Linux 가 exec 인자 1개에 두는 한도(131072바이트)보다는
#   작아야 한다 — 이 문자열이 jq --arg 의 인자로 넘어간다(넘으면 입력이 만들어지지 않아 CI 의 ubuntu 에서만 거짓 결과가 난다).
_tp_big=$(_tp_i=0; while [ "$_tp_i" -lt 2000 ]; do echo "echo line-$_tp_i-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; _tp_i=$((_tp_i+1)); done)
_form_deny5 "T-pipe.a ★ 인용 메시지 + 줄 연속 커밋" 'git commit -m "x" \
  --no-verify'
_form_deny5 "T-pipe.b ★ gh pr create + 인용 + 줄 연속" 'gh pr create --title "x" \
  --body "y"'
_form_deny5 "T-pipe.c ★ 커밋 뒤에 큰 여러 줄(${#_tp_big}바이트 · heredoc 아님)" "git commit -m x
$_tp_big"
# 대조 — 같은 형태라도 검증 증거가 갖춰진 상태에서는 통과한다(새로 막히는 것은 검증 없이 나가던 커밋뿐이다)
_tp_ok=$(mktemp -d) || exit 1
( cd "$_tp_ok" && git init -q && echo "echo x" > a.sh && git add a.sh \
  && mkdir -p .specops/20260101-tpipe \
  && printf '# Session Progress\n\n## 20260101-tpipe\n\n- 2026-01-01 10:00 /verify PASS\n' > .specops/session-progress.md ) >/dev/null 2>&1
_tp_tr=$(_tr_for "$_tp_ok" "$FIX/pretool-with-verify-exec.jsonl")
out=$(mkstdin 'git commit -m "x" \
  --no-verify' "$_tp_tr" | CLAUDE_PROJECT_DIR="$_tp_ok" bash "$HOOK" 2>/dev/null)
check "T-pipe.d 대조 — 검증을 거친 상태의 인용 + 줄 연속 커밋 → allow" '"continue":true' "$out"
out=$(mkstdin "git commit -m x
$_tp_big" "$_tp_tr" | CLAUDE_PROJECT_DIR="$_tp_ok" bash "$HOOK" 2>/dev/null)
check "T-pipe.d2 대조 — 검증을 거친 상태의 큰 여러 줄 커밋 → allow" '"continue":true' "$out"
rm -rf "$_tp_ok"
# 꺼진 훅의 기록 — 훅 종단에서도 인용 + 줄 연속 커밋이 기록된다(lib 의 T-pipe.a 가 함수 단위로 잰 것의 종단 확인)
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  _tp_off=$(mktemp -d) || exit 1
  ( cd "$_tp_off" && git init -q && echo "echo x" > a.sh && git add a.sh && mkdir .specops \
    && printf 'hooks:\n  pretool-governance:\n    enabled: false\n' > .specops/config.yaml ) >/dev/null 2>&1
  ( cd "$_tp_off" && mkstdin 'git commit -m "x" \
  --no-verify' "$FIX/pretool-no-verify.jsonl" | CLAUDE_PROJECT_DIR="$_tp_off" bash "$HOOK" >/dev/null 2>&1 )
  grep -qs '"rule_id":"GOVERNANCE-DISABLED"' "$_tp_off/.specops/friction-log.jsonl" \
    && { echo "PASS T-pipe.e 꺼진 채 인용 + 줄 연속 커밋 → GOVERNANCE-DISABLED 기록"; pass=$((pass+1)); } \
    || { echo "FAIL T-pipe.e 꺼진 채 인용 + 줄 연속 커밋이 기록되지 않음"; fail=$((fail+1)); }
  rm -rf "$_tp_off"
else
  echo "SKIP T-pipe.e (python3+pyyaml 부재)"
fi

echo "==== Results: PASS=$pass FAIL=$fail ===="
[ "$fail" -eq 0 ]
