#!/usr/bin/env bash
# test-init-finalize.sh — 부트스트랩 종결 커밋 계약 (FID 20260810-init-commit-teeth)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

FIN="$PLUGIN/scripts/_internal/init-finalize.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 부트스트랩 산출물이 staged 인 repo 픽스처
_mkstaged() {
  local r="$1"; mkdir -p "$r/.specops/memory"; cd "$r" || return 1
  git init -q; git config user.email t@t; git config user.name t
  local f
  for f in PRD.md CLAUDE.md README.md DESIGN.md; do printf '# %s\n' "$f" > "$f"; done
  for f in constitution requirements test-strategy architecture frontend-architecture \
           backend-architecture api-spec data-model screens-overview; do
    printf '# %s\n' "$f" > ".specops/memory/$f.md"
  done
  git add -A
}

# F1 — 스테이징만 → 커밋 1건 · 파일수 일치
R="$TMP/f1"; _mkstaged "$R"
n_staged=$(git diff --cached --name-only | wc -l | tr -d ' ')
out=$(bash "$FIN" 2>&1); rc=$?
n_commits=$(git rev-list --count HEAD 2>/dev/null || echo 0)
n_files=$(git show --name-only --format= HEAD 2>/dev/null | grep -c . || echo 0)
sha=$(git rev-parse --short HEAD 2>/dev/null || echo "")
subj=$(git log -1 --format=%s 2>/dev/null)     # AC-9 2절 — 메시지 접두 (doctor 판정과 결합)
# 계약: staged 산출물 **전건** + 진행기록(session-progress.md) 이 한 커밋에 들어간다(spec §3 clean tree).
#   +1 은 **픽스처 한정** — 이 픽스처엔 session-progress.md 가 없어 finalize 가 새로 만든다.
#   실제 /init-project 는 phases-artifacts.sh:223 이 이미 staged 해 두므로 delta 는 0 이다.
has_sp=$(git show --name-only --format= HEAD 2>/dev/null | grep -c 'session-progress\.md' || true)
exp_files=$((n_staged + 1))
if [ "$rc" -eq 0 ] && [ "$n_commits" = "1" ] && [ "$n_files" = "$exp_files" ] \
   && [ "${has_sp:-0}" -ge 1 ] \
   && printf '%s' "$out" | grep -q "$sha" \
   && printf '%s' "$subj" | grep -q '^chore(init): '; then
  ok "F1 스테이징만 → 커밋 1건 · 파일수 $n_files(=staged $n_staged + 진행기록) · SHA 출력 · chore(init) 접두"
else
  nope "F1" "rc=$rc commits=$n_commits files=$n_files/exp$exp_files sp=$has_sp subj=$subj out=$out"
fi

# F2 — enrich 수정분이 커밋에 포함 (재-add 보증) ★핵심
R="$TMP/f2"; _mkstaged "$R"
printf '# PRD\n\nenriched-marker-XYZ\n' > PRD.md      # add 이후 수정 = AM 상태
bash "$FIN" >/dev/null 2>&1
if git show HEAD:PRD.md 2>/dev/null | grep -q 'enriched-marker-XYZ' \
   && [ -z "$(git status --short PRD.md)" ]; then
  ok "F2 enrich 수정분이 커밋에 포함 (재-add 보증)"
else
  nope "F2" "committed=$(git show HEAD:PRD.md 2>&1 | tr '\n' ' ') status=$(git status --short PRD.md)"
fi

# F11 (Phase C Critical) — repo **하위 디렉토리**에서 실행해도 재-add 가 보증된다
#   재-add 루프가 상대경로면 subdir 에서 전부 no-op 이 되어 기존 staged 만 커밋되고
#   rc=0 "커밋 완료" 를 출력한다 — AC-2 가 조용히 무력화되는 거짓 성공(부모 재현).
#   session-progress-append.sh 도 TARGET 이 상대경로라 sub/.specops/ 를 새로 판다 —
#   같은 근원이므로 한 어서션에 함께 잠근다.
R="$TMP/f11"; _mkstaged "$R"
printf '# PRD\n\nenriched-marker-SUBDIR\n' > PRD.md      # add 이후 수정 = AM 상태
mkdir -p sub; cd sub || exit 1
out=$(bash "$FIN" 2>&1); rc=$?
cd "$R" || exit 1
committed=$(git show HEAD:PRD.md 2>/dev/null | grep -c 'enriched-marker-SUBDIR' || true)
dirty=$(git status --short PRD.md 2>/dev/null | grep -c . || true)
stray=$([ -e sub/.specops ] && echo 1 || echo 0)
if [ "$rc" -eq 0 ] && [ "${committed:-0}" -ge 1 ] && [ "${dirty:-1}" -eq 0 ] && [ "$stray" -eq 0 ]; then
  ok "F11 subdir 실행에도 enrich 재-add 보증 · sub/.specops 미생성"
else
  nope "F11" "rc=$rc committed=$committed dirty=$dirty stray_sub_specops=$stray out=$out"
fi

# F3 — 커밋 대상 없음 → rc=0 · 커밋 0
R="$TMP/f3"; mkdir -p "$R"; cd "$R" || exit 1
git init -q; git config user.email t@t; git config user.name t
out=$(bash "$FIN" 2>&1); rc=$?
n_commits=$(git rev-list --count HEAD 2>/dev/null || echo 0)
[ "$rc" -eq 0 ] && [ "$n_commits" = "0" ] \
  && ok "F3 커밋 대상 없음 → rc=0 · 커밋 0" || nope "F3" "rc=$rc commits=$n_commits out=$out"

# F4 — SPECOPS_INIT_COMMIT_NOW 경로로 이미 커밋된 뒤 → no-op rc=0
R="$TMP/f4"; _mkstaged "$R"
git commit -q -m "chore(init): /init-project 부트스트랩 (사전 커밋)"
before=$(git rev-list --count HEAD)
out=$(bash "$FIN" 2>&1); rc=$?
after=$(git rev-list --count HEAD)
[ "$rc" -eq 0 ] && [ "$before" = "$after" ] \
  && ok "F4 이미 커밋됨 → no-op rc=0" || nope "F4" "rc=$rc $before→$after out=$out"

# F5 + F10(AC-10) — progress append · FID 형식 · 디렉토리 미생성
R="$TMP/f5"; _mkstaged "$R"
bash "$FIN" >/dev/null 2>&1
sp=".specops/session-progress.md"
fid=$(grep -oE '^## [0-9]{8}-init-project' "$sp" 2>/dev/null | head -1 | sed 's/^## //')
# spec §3 — 기록이 **그 단일 커밋 안에** 들어가야 커밋 직후 tree 가 clean 이다.
#   (기록이 커밋 뒤에 붙으면 downstream 에선 .specops/.gitignore 가 FID 디렉토리만
#    ignore 하므로(phases-artifacts.sh:190~194) session-progress.md 가 미커밋 수정분으로 남는다.)
sp_dirty=$(git status --short "$sp" 2>/dev/null | grep -c . || true)
sp_in_commit=$(git show --name-only --format= HEAD 2>/dev/null | grep -c 'session-progress\.md' || true)
# spec §3 기대결과는 파일 하나가 아니라 **워킹트리 전체** 가 clean 이다.
#   실측(Phase B): sp 만 보면 통과하지만 `?? .specops/session-progress.md.bak` 가 남았다
#   — session-progress-append.sh:108 이 prepend 직전 남긴 1세대 백업이고, downstream
#   .specops/.gitignore 는 FID 디렉토리 패턴만 커버해(phases-artifacts.sh:190~194) 걸러지지 않는다.
#   init 종결 경로에서 append 를 부르는 것은 본 FID 가 신규 도입했으므로 잔여물도 여기가 책임진다.
tree_dirty=$(git status --porcelain 2>/dev/null | grep -c . || true)
tree_out=$(git status --porcelain 2>/dev/null | tr '\n' '|')
if [ -n "$fid" ] && grep -q '/init-project' "$sp" && [ ! -d ".specops/$fid" ] \
   && [ "${sp_dirty:-1}" -eq 0 ] && [ "${sp_in_commit:-0}" -ge 1 ] \
   && [ "${tree_dirty:-1}" -eq 0 ]; then
  ok "F5 progress append (FID=$fid) · 커밋 포함 · 워킹트리 전체 clean · .specops/\$FID 디렉토리 미생성"
else
  nope "F5" "fid=$fid dir=$([ -d ".specops/$fid" ] && echo 있음 || echo 없음) dirty=$sp_dirty in_commit=$sp_in_commit tree_dirty=$tree_dirty tree=[$tree_out]"
fi

# F8 — 커밋 실패 → rc=1 · staged 보존 · 사유·재시도 안내
R="$TMP/f8"; _mkstaged "$R"
mkdir -p .git/hooks
printf '#!/bin/sh\necho "rejected by test hook" >&2\nexit 1\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
out=$(bash "$FIN" 2>&1); rc=$?
staged_after=$(git diff --cached --name-only | wc -l | tr -d ' ')
# AC-5/FR-5 는 기록을 **커밋 성공**에 조건부로 둔다(acceptance-criteria.md:71 Given,
#   spec.md:62 "finalize 성공 시") — 실패했는데 "완료" 가 남으면 검출형 근거가 거짓이 된다.
false_rec=$(grep -c '/init-project 완료' .specops/session-progress.md 2>/dev/null || true)
if [ "$rc" -eq 1 ] && [ "$staged_after" -gt 0 ] \
   && printf '%s' "$out" | grep -q '사유' && printf '%s' "$out" | grep -q '재시도' \
   && [ "${false_rec:-1}" -eq 0 ]; then
  ok "F8 커밋 실패 → rc=1 · staged $staged_after 보존 · 사유·재시도 안내 · 거짓 완료기록 0"
else
  nope "F8" "rc=$rc staged=$staged_after false_record=$false_rec out=$out"
fi

# F12/F13 공통 픽스처 — 이전 세션이 남긴 **출처 불명 .bak** + 커밋 실패
#   실패 경로의 복원(cp .bak → session-progress.md → git add)이 .bak 출처를 확인하지 않으면
#   남의 스냅샷으로 워킹트리와 **인덱스**를 덮는다(Phase C Important 2).
_mkstale() {          # $1=repo — stale .bak 를 444 로 만들어 append 의 cp(108) 를 실패시킨다
  _mkstaged "$1"
  printf '# Session Progress\n\n---\n\n## 20250101-old\n\n- 2025-01-01 09:00 /specify 완료\n' \
    > .specops/session-progress.md
  git add .specops/session-progress.md
  printf 'STALE-BAK-MARKER-이전세션\n' > .specops/session-progress.md.bak
  chmod 444 .specops/session-progress.md.bak
  mkdir -p .git/hooks
  printf '#!/bin/sh\necho "rejected by test hook" >&2\nexit 1\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
}
_stale_assert() {     # $1=태그 $2=rc $3=out — 워킹트리·인덱스 모두 stale 오염 0 · 원본 보존
  local tag="$1" rc="$2" out="$3" sp=".specops/session-progress.md"
  local stale idx orig staged false_rec
  stale=$(grep -c 'STALE-BAK-MARKER' "$sp" 2>/dev/null || true)
  idx=$(git show ":$sp" 2>/dev/null | grep -c 'STALE-BAK-MARKER' || true)
  orig=$(grep -c '/specify 완료' "$sp" 2>/dev/null || true)
  staged=$(git diff --cached --name-only | wc -l | tr -d ' ')
  # AC-5 는 그대로다 — 커밋 실패 시 "완료" 기록이 남으면 안 된다. F12 는 **정상 .bak 으로
  #   복원**해서, F13 은 애초에 append 가 실패해서 0 이 된다(복원 skip 이 기록을 남기지 않는다).
  false_rec=$(grep -c '/init-project 완료' "$sp" 2>/dev/null || true)
  if [ "$rc" -eq 1 ] && [ "${stale:-1}" -eq 0 ] && [ "${idx:-1}" -eq 0 ] \
     && [ "${orig:-0}" -ge 1 ] && [ "$staged" -gt 0 ] && [ "${false_rec:-1}" -eq 0 ]; then
    ok "$tag stale .bak 로 복원하지 않음 (워킹트리·인덱스 무오염 · 거짓 완료기록 0 · staged $staged 보존)"
  else
    nope "$tag" "rc=$rc stale=$stale index_stale=$idx orig_kept=$orig staged=$staged false_record=$false_rec out=$out"
  fi
}

# F12·F13 은 권한 거부(444 .bak · 555 .specops)로 실패를 만든다 — root 는 둘 다 무시해 실패 경로를 못 타고
#   단언이 공허하게 통과하므로 SKIP
if [ "$(id -u)" -eq 0 ]; then
  skip "F12 stale .bak 로 복원하지 않음(백업 cp 실패) — root 로 실행 중(권한 검사 무의미)"
  skip "F13 stale .bak 로 복원하지 않음(append 실패) — root 로 실행 중(권한 검사 무의미)"
else
# F12 (Phase C Important 2) — append 는 성공했으나 그 백업 cp 가 실패해 .bak 이 stale
R="$TMP/f12"; _mkstale "$R"
out=$(bash "$FIN" 2>&1); rc=$?
chmod 644 .specops/session-progress.md.bak 2>/dev/null || true
_stale_assert "F12" "$rc" "$out"

# F13 (Phase C Important 2 · 리뷰어 명시 시나리오) — append **자체**가 조용히 실패(`|| true`)
#   .specops 를 555 로 만들어 prepend(mv)를 막는다. append 는 마지막 echo 때문에 rc=0 으로
#   끝나므로(실측) 종료코드로는 실패를 못 본다 — 그래서 우리 기록의 **실재**를 확인해야 한다.
R="$TMP/f13"; _mkstale "$R"
chmod 555 .specops
out=$(bash "$FIN" 2>&1); rc=$?
chmod 755 .specops; chmod 644 .specops/session-progress.md.bak 2>/dev/null || true
_stale_assert "F13" "$rc" "$out"
fi

# ── F14~F17 — 종결 커밋은 init 의 파일만 담는다 (20261009 init 점검) ──
#   종전엔 `git commit` 에 경로가 없어 인덱스 전체가 `chore(init)` 커밋에 들어갔다(설치본 재현):
#   미리 stage 해 둔 무관 파일(API 키가 든 notes.env) · 사용자가 고치던 README · 기존 앱의 screens/ 파일.

# F14 — 미리 stage 된 무관 파일은 커밋에 들어가지 않고 staged 로 남는다
R="$TMP/f14"; _mkstaged "$R"
printf 'API_KEY=sk-test-000\n' > notes.env; git add notes.env
out=$(bash "$FIN" 2>&1); rc=$?
in_commit=$(git show --name-only --format= HEAD 2>/dev/null | grep -c '^notes\.env$' || true)
still_staged=$(git diff --cached --name-only 2>/dev/null | grep -c '^notes\.env$' || true)
n_files=$(git show --name-only --format= HEAD 2>/dev/null | grep -c . || true)
subj_n=$(git log -1 --format=%s 2>/dev/null | sed -n 's/.*(\([0-9][0-9]*\)종).*/\1/p')
if [ "$rc" -eq 0 ] && [ "${in_commit:-1}" -eq 0 ] && [ "${still_staged:-0}" -eq 1 ] \
   && printf '%s' "$out" | grep -q 'notes\.env' && [ "$subj_n" = "$n_files" ]; then
  ok "F14 무관 staged 파일 → 커밋 제외 · staged 유지 · 출력에 고지 · 제목의 건수($subj_n)=커밋 파일 수"
else
  nope "F14" "rc=$rc in_commit=$in_commit still_staged=$still_staged subj_n=$subj_n files=$n_files out=$out"
fi

# F15 — init 이 보존한 파일의 미커밋 수정분(.init-hold)은 커밋에 넣지 않는다
#   기록은 bash 가 Phase 1 에서 남긴다(test-init-project T30.e). 여기서는 소비 쪽을 잠근다.
R="$TMP/f15"; mkdir -p "$R"; cd "$R" || exit 1
git init -q; git config user.email t@t; git config user.name t
printf '# 팀 README\n' > README.md; git add README.md; git commit -q -m base
printf '# 팀 README\n\n작성 중인 문단\n' > README.md          # 사용자의 미커밋 수정
mkdir -p .specops/memory; printf '# PRD\n' > PRD.md; printf '# req\n' > .specops/memory/requirements.md
printf 'README.md\n' > .specops/.init-hold
out=$(bash "$FIN" 2>&1); rc=$?
in_commit=$(git show --name-only --format= HEAD 2>/dev/null | grep -c '^README\.md$' || true)
kept=$(grep -c '작성 중인 문단' README.md 2>/dev/null || true)
prd_in=$(git show --name-only --format= HEAD 2>/dev/null | grep -c '^PRD\.md$' || true)
# 루트 파일 하나가 보류돼도 memory/ 는 그대로 커밋돼야 한다 — 보류 경로를 디렉토리 add 의 제외 인자로
#   섞으면 git 이 rc=0 으로 memory/ 전체를 건너뛴다(구현 중 실측).
mem_in=$(git show --name-only --format= HEAD 2>/dev/null | grep -c '^\.specops/memory/requirements\.md$' || true)
if [ "$rc" -eq 0 ] && [ "${in_commit:-1}" -eq 0 ] && [ "${kept:-0}" -eq 1 ] && [ "${prd_in:-0}" -eq 1 ] \
   && [ "${mem_in:-0}" -eq 1 ] \
   && [ -n "$(git status --short README.md)" ] && [ ! -e .specops/.init-hold ] \
   && printf '%s' "$out" | grep -q 'README\.md'; then
  ok "F15 보존 파일의 미커밋 수정분 → 커밋 제외 · 내용 유지 · 고지 · 종결 뒤 기록 파일 회수"
else
  nope "F15" "rc=$rc in_commit=$in_commit kept=$kept prd_in=$prd_in mem_in=$mem_in hold=$([ -e .specops/.init-hold ] && echo 남음 || echo 없음) out=$out"
fi

# F15b — memory/ 안의 보류 파일만 빠지고 같은 디렉토리의 나머지는 커밋된다
R="$TMP/f15b"; mkdir -p "$R/.specops/memory"; cd "$R" || exit 1
git init -q; git config user.email t@t; git config user.name t
printf '# api\n' > .specops/memory/api-spec.md; git add -A; git commit -q -m base
printf '# api\n\n진행 중인 설계\n' > .specops/memory/api-spec.md      # 진행 중 FID 의 미커밋 설계 수정
printf '# req\n' > .specops/memory/requirements.md
printf '.specops/memory/api-spec.md\n' > .specops/.init-hold
out=$(bash "$FIN" 2>&1); rc=$?
files=$(git show --name-only --format= HEAD 2>/dev/null)
if [ "$rc" -eq 0 ] && printf '%s\n' "$files" | grep -qx '.specops/memory/requirements.md' \
   && ! printf '%s\n' "$files" | grep -qx '.specops/memory/api-spec.md' \
   && [ "$(git status --short .specops/memory/api-spec.md | cut -c1-2)" = " M" ]; then
  ok "F15b memory/ 안 보류 파일 → 그 파일만 제외(미stage 유지) · 나머지 memory 는 커밋"
else
  nope "F15b" "rc=$rc files=$(printf '%s' "$files" | tr '\n' ' ') st=[$(git status --short | tr '\n' '|')] out=$out"
fi

# F16 — screens/ 는 화면 목록에 있는 화면 파일만 담는다 (기존 앱의 screens/ 폴더 보호)
R="$TMP/f16"; _mkstaged "$R"
cp "$PLUGIN/templates/screens-overview.md" .specops/memory/screens-overview.md
bash "$PLUGIN/scripts/_internal/design-screen.sh" home >/dev/null 2>&1      # 목록에 등록되는 화면
printf 'export default function Draft() {}\n' > screens/Draft.tsx            # 앱 소스(무관)
printf '# 목록에 없는 화면\n' > screens/orphan.md                            # 화면 형식이지만 목록 밖
out=$(bash "$FIN" 2>&1); rc=$?
files=$(git show --name-only --format= HEAD 2>/dev/null)
if [ "$rc" -eq 0 ] && printf '%s\n' "$files" | grep -qx 'screens/home.md' \
   && printf '%s\n' "$files" | grep -qx 'screens/home.html' \
   && ! printf '%s\n' "$files" | grep -qE 'Draft\.tsx|orphan\.md' \
   && git status --porcelain -uall 2>/dev/null | grep -q '^?? screens/Draft.tsx' \
   && printf '%s' "$out" | grep -q 'screens/orphan\.md' \
   && ! printf '%s' "$out" | grep -q 'Draft\.tsx'; then
  ok "F16 화면 목록의 화면만 커밋 · 앱 소스는 미추적 그대로(무고지) · 목록 밖 화면 파일은 고지"
else
  nope "F16" "rc=$rc files=$(printf '%s' "$files" | tr '\n' ' ') status=$(git status --porcelain | tr '\n' '|') out=$out"
fi

# F17 — 커밋 실패 시에도 무관 staged 파일이 그대로다 (경로 지정 커밋이 인덱스를 흩뜨리지 않는다)
#   방어 단언이다: 경로 없는 구판도 통과한다(독립 리뷰 확인). 경로 지정 커밋의 임시 인덱스가 실패 경로에서
#   원래 인덱스를 훼손하지 않는다는 것만 지킨다.
R="$TMP/f17"; _mkstaged "$R"
printf 'x\n' > other.txt; git add other.txt
mkdir -p .git/hooks
printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
out=$(bash "$FIN" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && git diff --cached --name-only | grep -qx 'other.txt' \
   && git diff --cached --name-only | grep -qx 'PRD.md'; then
  ok "F17 커밋 실패 → init 산출물·무관 파일 모두 staged 보존"
else
  nope "F17" "rc=$rc staged=$(git diff --cached --name-only | tr '\n' ' ') out=$out"
fi

# F18 — 화면 목록에 파일명이 될 수 없는 이름이 있어도 종결 커밋이 조용히 no-op 이 되지 않는다
#   독립 리뷰 재현: 손으로 고친 표의 `../x` 행 → git 경로 오류 → 삼켜져 "커밋 대상 없음" rc=0 · 산출물은 staged 방치.
R="$TMP/f18"; _mkstaged "$R"
cp "$PLUGIN/templates/screens-overview.md" .specops/memory/screens-overview.md
awk '/^<!-- screens-table:end -->/{print "| ../../../etc/x | t | t | l | l |"} {print}' \
  .specops/memory/screens-overview.md > ov.tmp && mv ov.tmp .specops/memory/screens-overview.md
out=$(bash "$FIN" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$(git rev-list --count HEAD 2>/dev/null)" = "1" ] \
   && git show --name-only --format= HEAD | grep -qx 'PRD.md' && [ -z "$(git status --porcelain)" ]; then
  ok "F18 화면 목록의 잘못된 이름 → 건너뛰고 산출물은 커밋 (no-op 둔갑 없음)"
else
  nope "F18" "rc=$rc commits=$(git rev-list --count HEAD 2>/dev/null) st=[$(git status --porcelain | tr '\n' '|')] out=$out"
fi

# F19 — 따옴표·공백·한글이 든 파일명도 커밋 경로로 넘어간다 (git 의 "…" 감싸기를 경로로 되먹이지 않는다)
R="$TMP/f19"; _mkstaged "$R"
printf '# m\n' > '.specops/memory/q"uote 한글.md'
out=$(bash "$FIN" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$(git status --porcelain)" ] \
   && [ "$(git ls-files .specops/memory | grep -c 'uote')" = "1" ]; then
  ok "F19 따옴표·공백·한글 파일명 → 커밋 성공 · 워킹트리 clean"
else
  nope "F19" "rc=$rc st=[$(git status --porcelain | tr '\n' '|')] out=$out"
fi

# F20 — git 이 staged 판정에 실패하면 "커밋 대상 없음" 이 아니라 실패로 끝난다
#   판정 호출(--no-renames 가 붙은 diff)만 실패시키는 git 대역을 PATH 앞에 둔다.
R="$TMP/f20"; _mkstaged "$R"
_real_git=$(command -v git)
mkdir -p "$TMP/shim"
printf '#!/bin/sh\ncase " $* " in *" --no-renames "*) exit 128 ;; esac\nexec "%s" "$@"\n' "$_real_git" > "$TMP/shim/git"
chmod +x "$TMP/shim/git"
out=$(PATH="$TMP/shim:$PATH" bash "$FIN" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '판정하지 못했습니다' \
   && ! printf '%s' "$out" | grep -q '커밋 대상 없음' \
   && [ "$(git rev-list --count HEAD 2>/dev/null || echo 0)" = "0" ] \
   && [ "$(git diff --cached --name-only | grep -c .)" -gt 0 ]; then
  ok "F20 staged 판정 실패 → rc=1 · no-op 으로 둔갑하지 않음 · 산출물 staged 보존"
else
  nope "F20" "rc=$rc out=$out"
fi

# ── F21~F22 — 종결 커밋은 보강 여부를 지어내지 않는다 (20261009 init 점검) ──
#   종전엔 보강(Phase 11)을 건너뛰고 종결해도 제목이 "부트스트랩+enrich" 였다(재현: 미채움 152건 · 예시 블록 2건이
#   그대로 커밋). 제목은 남은 미채움 건수를 적고, 출력으로 문서별 건수를 알린다. 막지는 않는다 — 얕게 두는
#   문서(헌법·테스트 전략 등)의 자리표시자는 계약상 남을 수 있다.
R="$TMP/f21"; _mkstaged "$R"
cp "$PLUGIN/templates/PRD.md" PRD.md                                   # 골격 그대로(자리표시자 다수)
cp "$PLUGIN/templates/api-spec.md" .specops/memory/api-spec.md         # 예시 블록 포함
out=$(bash "$FIN" 2>&1); rc=$?
subj=$(git log -1 --format=%s 2>/dev/null)
_m=$(printf '%s' "$subj" | sed -n 's/.*미채움 \([0-9][0-9]*\)건.*/\1/p')
if [ "$rc" -eq 0 ] && ! printf '%s' "$subj" | grep -q '+enrich' && [ "${_m:-0}" -gt 0 ] \
   && printf '%s' "$subj" | grep -q '^chore(init): ' \
   && printf '%s' "$out" | grep -q '미채움' && printf '%s' "$out" | grep -q 'PRD.md' \
   && printf '%s' "$out" | grep -q '예시 블록'; then
  ok "F21 보강 없이 종결 → 제목에 '+enrich' 없음 · 미채움 ${_m}건 표기 · 문서별 건수·예시 블록 고지"
else
  nope "F21" "rc=$rc subj=[$subj] out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-240)"
fi
R="$TMP/f22"; _mkstaged "$R"
out=$(bash "$FIN" 2>&1); rc=$?
subj=$(git log -1 --format=%s 2>/dev/null)
if [ "$rc" -eq 0 ] && printf '%s' "$subj" | grep -q '부트스트랩+enrich' && ! printf '%s' "$subj" | grep -q '미채움' \
   && ! printf '%s' "$out" | grep -q '미채움'; then
  ok "F22 미채움 0 → 제목 '부트스트랩+enrich' · 미채움 고지 없음"
else
  nope "F22" "rc=$rc subj=[$subj] out=$out"
fi

# F23 — 예시 블록만 남은 경우도 제목이 말한다 ("미채움 0건" 이라 쓰고 출력은 "예시 블록 1건" 이던 어긋남 — 독립 리뷰)
R="$TMP/f23"; _mkstaged "$R"
printf '# api\n\n<!-- specops:example:start -->\n| GET | /v1/users |\n<!-- specops:example:end -->\n' > .specops/memory/api-spec.md
out=$(bash "$FIN" 2>&1); rc=$?
subj=$(git log -1 --format=%s 2>/dev/null)
if [ "$rc" -eq 0 ] && printf '%s' "$subj" | grep -q '예시 블록 1건' && ! printf '%s' "$subj" | grep -q '+enrich\|미채움 0건'; then
  ok "F23 예시 블록만 잔존 → 제목 '예시 블록 1건' · '+enrich' 아님"
else
  nope "F23" "rc=$rc subj=[$subj]"
fi

# F24 — 스캔하지 못했으면 보강을 주장하지 않는다 (스캐너 부재를 0건으로 읽으면 같은 거짓 제목이 된다 — 독립 리뷰)
mkdir -p "$TMP/plug/scripts"
cp -R "$PLUGIN/scripts/_internal" "$TMP/plug/scripts/_internal"
cp "$PLUGIN/scripts/session-progress-append.sh" "$TMP/plug/scripts/" 2>/dev/null
cp -R "$PLUGIN/templates" "$TMP/plug/templates"
rm -f "$TMP/plug/scripts/_internal/scan-enrich-placeholders.sh"
R="$TMP/f24"; _mkstaged "$R"
cp "$PLUGIN/templates/PRD.md" PRD.md
out=$(bash "$TMP/plug/scripts/_internal/init-finalize.sh" 2>&1); rc=$?
subj=$(git log -1 --format=%s 2>/dev/null)
if [ "$rc" -eq 0 ] && printf '%s' "$subj" | grep -q '^chore(init): /init-project 부트스트랩 (' \
   && ! printf '%s' "$subj" | grep -q '+enrich' && printf '%s' "$out" | grep -q '스캔을 하지 못했습니다'; then
  ok "F24 스캐너 부재 → 제목에 '+enrich' 없음 · 스캔 불가 고지"
else
  nope "F24" "rc=$rc subj=[$subj] out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"
fi

# ── F25~F27 — 보강 누락 차단 (20261113): 이번 부트스트랩이 쓴 문서에만 ──
#   종전엔 미채움을 알리기만 해, 보강(Phase 11)을 건너뛴 골격·예시가 기준 문서로 커밋됐다. 막는 범위는
#   .init-written 에 적힌(=init 이 쓴) 아직 HEAD 에 없는 문서뿐이다 — 위 F21·F23 처럼 기록이 없는 문서는 종전대로다.
# F25 — init 이 쓴 깊게 대상 문서에 자리표시자 → rc 1 · 커밋 0 · staged 보존 · 파일·건수·우회 안내
R="$TMP/f25"; _mkstaged "$R"
cp "$PLUGIN/templates/PRD.md" PRD.md; git add PRD.md
printf 'PRD.md\n' > .specops/.init-written
n_staged=$(git diff --cached --name-only | wc -l | tr -d ' ')
out=$(bash "$FIN" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && [ "$(git rev-list --count HEAD 2>/dev/null || echo 0)" = "0" ] \
   && [ "$(git diff --cached --name-only | wc -l | tr -d ' ')" = "$n_staged" ] \
   && printf '%s' "$out" | grep -q '보강이 끝나지 않았습니다' && printf '%s' "$out" | grep -qE 'PRD\.md: 자리표시자 [1-9]' \
   && printf '%s' "$out" | grep -q 'SPECOPS_INIT_ALLOW_UNFILLED=1' && [ ! -e .specops/session-progress.md ]; then
  ok "F25 init 이 쓴 깊게 대상 문서에 자리표시자 → rc1 · 커밋 0 · staged 보존 · 진행 기록 없음 · 우회 안내"
else
  nope "F25" "rc=$rc commits=$(git rev-list --count HEAD 2>/dev/null) out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-240)"
fi
# F25b — 같은 상태에서 SPECOPS_INIT_ALLOW_UNFILLED=1 → 종전대로 커밋하고 제목이 건수를 말한다
out=$(SPECOPS_INIT_ALLOW_UNFILLED=1 bash "$FIN" 2>&1); rc=$?
subj=$(git log -1 --format=%s 2>/dev/null)
[ "$rc" -eq 0 ] && printf '%s' "$subj" | grep -q '미채움' && [ ! -e .specops/.init-written ] \
  && ok "F25b SPECOPS_INIT_ALLOW_UNFILLED=1 → 커밋 · 제목에 미채움 건수" || nope "F25b" "rc=$rc subj=[$subj]"
# F26 — 얕게 두는 문서의 자리표시자는 막지 않고, 예시 블록은 어느 문서든 막는다
R="$TMP/f26"; _mkstaged "$R"
printf -- '### 원칙 1: 단순함\n**규칙**: <한 문장>\n' > .specops/memory/constitution.md; git add -A   # 헌법은 사용자가 정하는 문서다 — 얕게 둔다
printf '.specops/memory/constitution.md\n' > .specops/.init-written
out=$(bash "$FIN" 2>&1); rc=$?
_a=$rc
R="$TMP/f26b"; _mkstaged "$R"
printf '# 구조\n\n<!-- specops:example:start -->\n| Cache | Redis |\n<!-- specops:example:end -->\n' > .specops/memory/architecture.md; git add -A
printf '.specops/memory/architecture.md\n' > .specops/.init-written
out=$(bash "$FIN" 2>&1); rc=$?
if [ "$_a" -eq 0 ] && [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'architecture\.md: 예시 블록 1건'; then
  ok "F26 얕게 두는 문서의 자리표시자 → 통과 · 예시 블록은 얕은 문서(architecture)에서도 rc1"
else
  nope "F26" "얕은 자리표시자 rc=$_a · 예시 블록 rc=$rc out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"
fi
# F27 — HEAD 에 이미 있는 문서(손으로 커밋한 뒤·소급 보강)는 기록이 있어도 막지 않는다
R="$TMP/f27"; _mkstaged "$R"
git commit -q -m base
cp "$PLUGIN/templates/PRD.md" PRD.md
printf 'PRD.md\n' > .specops/.init-written
out=$(bash "$FIN" 2>&1); rc=$?
[ "$rc" -eq 0 ] && git show --name-only --format= HEAD | grep -qx 'PRD.md' \
  && ok "F27 HEAD 에 있는 문서의 자리표시자 → 막지 않음(종전대로 알리기만)" || nope "F27" "rc=$rc out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"

# F33 (20261113) — 테스트 전략·전체 구조는 깊게 보강하는 문서다(하류가 읽는다 — planning·tdd·테스트 전문가·코드 리뷰어 · specifying)
#   실주행: 얕게 두던 test-strategy 에 자리표시자 21건이 그대로 커밋됐다. 모르는 값은 미확정 마커로 적으면 통과한다.
for _doc in test-strategy architecture; do
  R="$TMP/f33-$_doc"; _mkstaged "$R"
  printf -- '- 도구: <Jest / Vitest>\n' > ".specops/memory/$_doc.md"; git add -A
  printf '.specops/memory/%s.md\n' "$_doc" > .specops/.init-written
  out=$(bash "$FIN" 2>&1); rc=$?
  _a="$rc:$(printf '%s' "$out" | grep -c "$_doc.md: 자리표시자 1건")"
  printf -- '- 도구: <미확정 — 근거 필요>\n' > ".specops/memory/$_doc.md"; git add -A
  out=$(bash "$FIN" 2>&1); rc=$?
  [ "$_a" = "1:1" ] && [ "$rc" -eq 0 ] && ok "F33($_doc) 자리표시자 → rc1 · 미확정 마커로 적으면 통과" || nope "F33($_doc)" "raw=$_a marker_rc=$rc"
done

# ── F28 — 설계 완료 표지는 리뷰 보고서로 검증한다 (20261113) ──
#   표지(`init 설계 완료` · `<!-- specops:init-designed: M1 -->`)는 /start-all Phase 2.5 의 설계·리뷰를 건너뛰게 한다.
#   모델이 직접 쓰므로, 이번 커밋이 새로 다는 표지만 .specops/.init-design/design-review.md 의 판정과 대조한다.
_mkdesigned() {   # <repo> — 화면 home·booking 에 표지 · api-spec 머리 주석
  _mkstaged "$1"
  printf '# 화면\n\n<!-- screens-table:start -->\n| name | 제목 | 목적 | md | html |\n|---|---|---|---|---|\n| home | 홈 | init 설계 완료 (미확정 0) | a | b |\n| booking | 예약 | init 설계 완료 (미확정 1) | a | b |\n| stats | 통계 | init 보강 (미확정 3) | a | b |\n<!-- screens-table:end -->\n' > .specops/memory/screens-overview.md
  printf '# api\n<!-- specops:init-designed: M1 -->\n\n본문\n' > .specops/memory/api-spec.md
  git add -A
}
_marks() { grep -c 'init 설계 완료' .specops/memory/screens-overview.md | tr -d ' '; }
_ifmark() { grep -c '^<!-- specops:init-designed: ' .specops/memory/api-spec.md | tr -d ' '; }
# F28.a 리뷰 보고서 없음 → 전부 내린다 · 내린 내용이 같은 커밋에 들어간다 · 고지
R="$TMP/f28a"; _mkdesigned "$R"
out=$(bash "$FIN" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$(_marks)" = "0" ] && [ "$(_ifmark)" = "0" ] && [ -z "$(git status --porcelain)" ] \
   && git show HEAD:.specops/memory/screens-overview.md | grep -q '| booking | 예약 | init 보강 (미확정 1) |' \
   && printf '%s' "$out" | grep -q '설계 완료 표지를 내렸습니다' && printf '%s' "$out" | grep -q 'home booking api-spec.md'; then
  ok "F28.a 리뷰 보고서 없음 → 표지 전부 내림(미확정 수 보존) · 같은 커밋 · clean · 고지"
else
  nope "F28.a" "rc=$rc marks=$(_marks) if=$(_ifmark) st=[$(git status --porcelain | tr '\n' '|')] out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"
fi
# F28.b PASS → 그대로
R="$TMP/f28b"; _mkdesigned "$R"; mkdir -p .specops/.init-design
printf 'DESIGN-REVIEW-MODE: init\nDESIGN-REVIEW-RESULT: PASS\nCritical: 0건\n' > .specops/.init-design/design-review.md
printf '.init-*\n' > .specops/.gitignore; git add .specops/.gitignore
out=$(bash "$FIN" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(_marks)" = "2" ] && [ "$(_ifmark)" = "1" ] && ! printf '%s' "$out" | grep -q '표지를 내렸습니다' \
  && ok "F28.b 리뷰 PASS → 표지 유지 · 고지 없음" || nope "F28.b" "rc=$rc marks=$(_marks) if=$(_ifmark)"
# F28.c FAIL → 이슈 줄(Critical·Important)이 가리키는 화면만 내린다 · Minor 는 내리지 않는다 · 인터페이스는 이슈가 없으면 유지
R="$TMP/f28c"; _mkdesigned "$R"; mkdir -p .specops/.init-design
printf 'DESIGN-REVIEW-MODE: init\nDESIGN-REVIEW-RESULT: FAIL\nCritical: 0건\nImportant: 1건\n\n- [Important] screens/booking.md §States: empty 미정의\n- [Minor] screens/home.md: 순서\n' > .specops/.init-design/design-review.md
printf '.init-*\n' > .specops/.gitignore; git add .specops/.gitignore
out=$(bash "$FIN" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q '| home | 홈 | init 설계 완료' .specops/memory/screens-overview.md \
   && grep -q '| booking | 예약 | init 보강' .specops/memory/screens-overview.md && [ "$(_ifmark)" = "1" ] \
   && printf '%s' "$out" | grep -q '표지를 내렸습니다.*— booking\.'; then
  ok "F28.c 리뷰 FAIL → 이슈가 걸린 화면(booking)만 내림 · Minor 뿐인 화면·이슈 없는 인터페이스는 유지"
else
  nope "F28.c" "rc=$rc ov=$(grep -c 'init 설계 완료' .specops/memory/screens-overview.md) if=$(_ifmark) out=$(printf '%s' "$out" | grep 표지 | cut -c1-160)"
fi
# F28.d HEAD 에 이미 있는 표지는 보고서가 없어도 건드리지 않는다 (앞선 부트스트랩이 승인받은 것 — 보고서는 커밋되지 않는다)
R="$TMP/f28d"; _mkdesigned "$R"; git commit -q -m base
printf '\n추가 문단\n' >> PRD.md
out=$(bash "$FIN" 2>&1); rc=$?
[ "$rc" -eq 0 ] && [ "$(_marks)" = "2" ] && [ "$(_ifmark)" = "1" ] \
  && ok "F28.d HEAD 에 있던 표지 → 보고서 없어도 유지" || nope "F28.d" "rc=$rc marks=$(_marks) if=$(_ifmark)"

# F29 — FR 이 마일스톤 시드 3행 그대로면 알린다(막지 않는다) · 분해했으면 조용하다
R="$TMP/f29"; _mkstaged "$R"
printf '# 요구\n<!-- seed-fr: FR-1,FR-2,FR-3 -->\n| ID | 요구사항 |\n|---|---|\n| FR-1 | 가 |\n| FR-2 | 나 |\n| FR-3 | 다 |\n' > .specops/memory/requirements.md; git add -A
out=$(bash "$FIN" 2>&1); rc=$?
_a="$rc:$(printf '%s' "$out" | grep -c '마일스톤 시드 3행')"
R="$TMP/f29b"; _mkstaged "$R"
printf '# 요구\n<!-- seed-fr: FR-1,FR-2,FR-3 -->\n| ID | 요구사항 |\n|---|---|\n| FR-1 | 가 |\n| FR-2 | 나 |\n| FR-3 | 다 |\n| FR-4 | 라 |\n' > .specops/memory/requirements.md; git add -A
out=$(bash "$FIN" 2>&1); rc=$?
[ "$_a" = "0:1" ] && [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q '마일스톤 시드 3행' \
  && ok "F29 FR 시드 3행 그대로 → 경고 1줄(rc0) · FR 을 분해했으면 경고 없음" || nope "F29" "seed=$_a split_rc=$rc"

# F30 — 단계별 소요: 표시(--mark)가 있으면 종결이 구간별 소요를 출력하고 기록을 지운다 · 이름 형식이 아니면 rc 2
R="$TMP/f30"; _mkstaged "$R"
bash "$PLUGIN/scripts/_internal/init-project.sh" --mark phase0; _m1=$?
bash "$PLUGIN/scripts/_internal/init-project.sh" --mark enrich; _m2=$?
bash "$PLUGIN/scripts/_internal/init-project.sh" --mark 'Bad Name' >/dev/null 2>&1; _m3=$?
_lines=$(grep -c . .specops/.init-timing 2>/dev/null || true)
out=$(bash "$FIN" 2>&1); rc=$?
if [ "$_m1$_m2$_m3" = "002" ] && [ "$_lines" = "2" ] && [ "$rc" -eq 0 ] \
   && printf '%s' "$out" | grep -qE '단계별 소요 — enrich [0-9]+m[0-9]{2}s · finalize [0-9]+m[0-9]{2}s \(합계 ' && [ ! -e .specops/.init-timing ]; then
  ok "F30 --mark 2회 → 종결이 구간별 소요 출력 · 기록 회수 · 형식 밖 이름은 rc2"
else
  nope "F30" "mark=$_m1$_m2$_m3 lines=$_lines rc=$rc out=$(printf '%s' "$out" | grep 소요)"
fi
# F30b — .specops 가 없는 저장소에는 표시를 남기지 않는다(관할을 열지 않는다)
R="$TMP/f30b"; mkdir -p "$R"; cd "$R" || exit 1; git init -q
bash "$PLUGIN/scripts/_internal/init-project.sh" --mark phase0; rc=$?
[ "$rc" -eq 0 ] && [ ! -e .specops ] && ok "F30b .specops 없는 저장소 → 표시 안 남김 · .specops 미생성" || nope "F30b" "rc=$rc $(ls -A | tr '\n' ' ')"

# ── F31 — 미확정 마커 건수를 제목과 출력이 말한다 (20261113) ──
#   `<미확정 — 근거 필요>` 는 보강 계약상 허용이라 미채움 스캔·차단을 통과한다. 그래서 건수가 어디에도 보이지 않았다 —
#   실주행(20261113): 깊게 보강한 문서에 84건이 남았는데 제목은 "미채움 37건"(얕게 두는 문서의 자리표시자)만 말했다.
#   막지 않는다: 근거 없는 값을 지어내게 하는 것보다 모른다고 적는 쪽이 계약이다. 보이게만 한다.
R="$TMP/f31"; _mkstaged "$R"
printf '# 백엔드\n- 런타임: <미확정 — 근거 필요>\n- 로깅: <미확정 — 근거 필요> · 모니터링: <미확정 — 근거 필요>\n' > .specops/memory/backend-architecture.md
printf '# 요구\n- 기간: <미확정 — 근거 필요>\n' > .specops/memory/requirements.md; git add -A
out=$(bash "$FIN" 2>&1); rc=$?
subj=$(git log -1 --format=%s 2>/dev/null)
if [ "$rc" -eq 0 ] && printf '%s' "$subj" | grep -q '부트스트랩+enrich (.*미확정 4건)' && ! printf '%s' "$subj" | grep -q '미채움' \
   && printf '%s' "$out" | grep -q '미확정 마커 4건' && printf '%s' "$out" | grep -q 'backend-architecture.md 3 · .*requirements.md 1'; then
  ok "F31 미확정 마커 → 제목 '미확정 4건'(줄이 아니라 마커 수 · 미채움으로 세지 않음) · 문서별 건수 고지"
else
  nope "F31" "rc=$rc subj=[$subj] out=$(printf '%s' "$out" | grep 미확정 | cut -c1-200)"
fi
# F31b — 미확정 0건이면 제목·출력이 종전과 같다(위 F22 의 제목 계약 유지)
R="$TMP/f31b"; _mkstaged "$R"
out=$(bash "$FIN" 2>&1); rc=$?
subj=$(git log -1 --format=%s 2>/dev/null)
[ "$rc" -eq 0 ] && ! printf '%s%s' "$subj" "$out" | grep -q '미확정' && ok "F31b 미확정 0건 → 제목·출력에 언급 없음" || nope "F31b" "subj=[$subj]"

# ── F32 — 헌법 원칙이 비어 있으면 종결이 알린다 (20261113) ──
#   `principles=skip` 은 정당한 답이라 막지 않는다. 그런데 종전엔 승인 요약의 산문 한 줄에만 기대, 빈 헌법이 조용히
#   굳었다(실기록: 원칙이 자리표시자인 채 FID 60개 진행 — 구조 규칙 검사기·태스크 맥락이 이 문서를 읽는다).
R="$TMP/f32"; _mkstaged "$R"
printf '# 헌법\n\n### 원칙 1: <PRINCIPLE_1_NAME>\n\n### 원칙 2: 가독성\n' > .specops/memory/constitution.md; git add -A
out=$(bash "$FIN" 2>&1); rc=$?
_a="$rc:$(printf '%s' "$out" | grep -c '헌법 원칙이 정해지지 않았습니다')"
R="$TMP/f32b"; _mkstaged "$R"
printf '# 헌법\n\n### 원칙 1: 단순함\n\n### 원칙 2: 가독성\n' > .specops/memory/constitution.md; git add -A
out=$(bash "$FIN" 2>&1); rc=$?
[ "$_a" = "0:1" ] && [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q '헌법 원칙' \
  && ok "F32 헌법 원칙 자리표시자 → 경고 1줄(rc0 · 막지 않음) · 원칙이 채워졌으면 조용" || nope "F32" "skip=$_a filled_rc=$rc"

DOC="$PLUGIN/scripts/doctor.sh"

# F6 — 미커밋 부트스트랩 → bootstrap warn · exit 0 / 커밋 후 → ok
R="$TMP/f6"; _mkstaged "$R"
out=$(bash "$DOC" --json 2>&1); rc=$?
st=$(printf '%s' "$out" | jq -r '.checks[]|select(.id=="bootstrap")|.status' 2>/dev/null)
fix=$(printf '%s' "$out" | jq -r '.checks[]|select(.id=="bootstrap")|.fix' 2>/dev/null)
bash "$FIN" >/dev/null 2>&1
st2=$(bash "$DOC" --json 2>&1 | jq -r '.checks[]|select(.id=="bootstrap")|.status' 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$st" = "warn" ] && [ -n "$fix" ] && [ "$st2" = "ok" ]; then
  ok "F6 미커밋 → warn(+조치) · 커밋 후 → ok · exit 0"
else
  nope "F6" "rc=$rc st=$st fix=$fix st2=$st2"
fi

# F9 — memory 부재 repo → bootstrap unknown · 행 개수 동일
R="$TMP/f9"; mkdir -p "$R/.specops"; cd "$R" || exit 1
git init -q; git config user.email t@t; git config user.name t
j=$(bash "$DOC" --json 2>&1)
st=$(printf '%s' "$j" | jq -r '.checks[]|select(.id=="bootstrap")|.status' 2>/dev/null)
cnt=$(printf '%s' "$j" | jq -r '.checks|length' 2>/dev/null)
[ "$st" = "unknown" ] && [ "$cnt" = "10" ] \
  && ok "F9 memory 부재 → unknown · checks 10행 고정" || nope "F9" "st=$st cnt=$cnt"

# F7 — session-progress 제목이 그 프로젝트 이름 (하드코딩 인자 제거)
ENS="$PLUGIN/hooks/ensure-session-progress.sh"
R="$TMP/f7-외부"; mkdir -p "$R/.specops"; cd "$R" || exit 1
bash "$ENS" >/dev/null 2>&1
t1=$(awk 'FNR==6' .specops/session-progress.md 2>/dev/null)
R="$TMP/specops-ko"; mkdir -p "$R/.specops"; cd "$R" || exit 1
bash "$ENS" >/dev/null 2>&1
t2=$(awk 'FNR==6' .specops/session-progress.md 2>/dev/null)
# ★ 패턴 실측 필수: hooks.json 은 JSON 이스케이프라 리터럴이 `...progress.sh\" specops-ko` 다.
#   `\.sh" *specops-ko` 와 `[^"]*specops-ko` 는 **둘 다 0 match**(실측) — `\` 와 `"` 가 사이에 낀다.
#   아래 패턴만 현재 1 match 로 확인됐다.
hard=$(grep -c 'ensure-session-progress\.sh.*specops-ko' "$PLUGIN/hooks/hooks.json" || true)
if printf '%s' "$t1" | grep -q 'f7-외부' && ! printf '%s' "$t1" | grep -q 'specops-ko' \
   && printf '%s' "$t2" | grep -q 'specops-ko' && [ "${hard:-0}" -eq 0 ]; then
  ok "F7 제목=프로젝트명 · hooks.json 하드코딩 0"
else
  nope "F7" "t1=$t1 | t2=$t2 | hardcoded=$hard"
fi

# F-doc (AC-7) — 산문의 목록 소유권 이전
CMD="$PLUGIN/commands/init-project.md"
lit=$(grep -cE '^[[:space:]]*git (add|commit)' "$CMD" || true)
ph=$(grep -c '보강·골격 파일들' "$CMD" || true)
call=$(grep -c 'init-finalize\.sh' "$CMD" || true)
if [ "${lit:-0}" -eq 0 ] && [ "${ph:-0}" -eq 0 ] && [ "${call:-0}" -ge 1 ]; then
  ok "F-doc 산문 git add/commit 리터럴 0 · 플레이스홀더 0 · finalize 호출 ${call}건"
else
  nope "F-doc" "literal=$lit placeholder=$ph call=$call"
fi

# F-doc2 (SCOPE-MOVED) — /doctor 커맨드 문서가 doctor.sh 항목 목록과 동기.
#   T3 이 5번째 항목(bootstrap)을 scripts/doctor.sh 에 넣었는데 문서는 4항목인 채로 남았다.
#   문서/구현 drift 는 T5 가 존재하는 이유 그 자체라 같은 클래스를 여기서 잠근다.
#   20260830-silent-failure-surfacing T3 이 governance·deps 를 더해 8항목이 됐다 — id 순회·개수를 함께 올린다.
#   20261007-effort-env-doctor 가 effort_env 를 더해 9항목이 됐다 — 개수·id 순회를 함께 올린다.
#   20261105-console-baseline 이 console 을 더해 10항목이 됐다 — 같은 방식으로 올린다.
#   stale 라벨 판정은 리터럴 고정('4항목') 을 버리고 "현재 개수(9) 가 아닌 N항목 잔존 0" 으로 일반화한다:
#   고정 리터럴은 항목이 늘어나는 순간 절대 매치하지 않는 죽은 검사가 되어, 이 검사 자신이
#   무음 실패가 된다(= 이 FID 가 없애려는 클래스). 개수 증설 시엔 아래 -eq 9 가 강제로 실패해 갱신을 부른다.
DOCMD="$PLUGIN/commands/doctor.md"
d_boot=$(grep -c 'bootstrap' "$DOCMD" || true)
d_old=$(grep -oE '[0-9]+항목' "$DOCMD" | grep -vxc '10항목' || true)
d_ids=0
# id 존재 판정은 **점검 항목 표의 행**(`^| \`id\` |`) 을 요구한다 — 파일 어디든 백틱 언급이면 통과시키던
# 이전 판정은 이빨이 없었다(실측 20260830: `governance` 행을 통째로 지워도 `deps` 행 산문의
# "위 `governance` 항목이 …" 언급이 카운트를 8로 유지해 PASS 했다). 행 삭제가 안 잡히면 이 검사 자체가 무음이다.
for _id in git_hooks memory orphan_fid progress bootstrap stale governance deps console effort_env; do
  grep -qE "^\|[[:space:]]*\`$_id\`[[:space:]]*\|" "$DOCMD" && d_ids=$((d_ids + 1))
done
if [ "${d_boot:-0}" -ge 1 ] && [ "${d_old:-0}" -eq 0 ] && [ "$d_ids" -eq 10 ]; then
  ok "F-doc2 /doctor 문서 10항목 동기 (bootstrap 기재 · stale 'N항목' 라벨 잔존 0 · id ${d_ids}/10)"
else
  nope "F-doc2" "bootstrap=$d_boot stale_label=$d_old ids=$d_ids/10"
fi

# F-doc3 (20261007-effort-env-doctor AC-5): README 가 skill frontmatter effort 의 실측 사실을 담고 '확인 전' 문구가 사라졌다
RM="$PLUGIN/README.md"
_miss=""
for _kw in '활성화된 이후' '복원되지 않' '같은 턴' '다음 사용자 턴' 'CLAUDE_CODE_EFFORT_LEVEL' 'effort_env' '전부-또는-전무' '2.1.292'; do
  grep -qF -- "$_kw" "$RM" || _miss="$_miss $_kw"
done
if [ -z "$_miss" ] && ! grep -q '확인하기 전이라' "$RM"; then
  ok "F-doc3 README skill effort 실측 기술 (키워드 8종 존재 · '확인하기 전이라' 잔존 0)"
else
  nope "F-doc3" "누락:${_miss:- 없음} · '확인하기 전이라' 잔존=$(grep -c '확인하기 전이라' "$RM")"
fi

finish
