#!/usr/bin/env bash
set -u  # set -e 의도적 미사용 — rc 수동 체크 패턴 (테스트별 개별 판정)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
RELEASE="$PLUGIN/scripts/release.sh"


# AC-7 격리: tmpdir + git init (실제 repo 오염 차단)
_make_git_fixture() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.email "t@t.com"
  git -C "$dir" config user.name "T"
  mkdir -p "$dir/commands"
  mkdir -p "$dir/.claude-plugin"
  cat > "$dir/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "specops-ko",
  "version": "1.9.0",
  "description": "test"
}
JSON
  cat > "$dir/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "specops-ko",
  "metadata": {
    "description": "specops-ko 로컬 마켓플레이스 (v1.9.0 — test)"
  },
  "version": "1.9.0"
}
JSON
  cat > "$dir/CHANGELOG.md" <<'CHANGELOG'
# Changelog

## [Unreleased]

### Added
- test entry

[Unreleased]: https://github.com/andyko18/specops-ko/compare/v1.9.0...HEAD
[1.9.0]: https://github.com/andyko18/specops-ko/compare/v1.8.0...v1.9.0
CHANGELOG
  cat > "$dir/README.md" <<'README'
# specops-ko (v1.9.0)

Test.

*초기화: 2026-01-01 · **최신: v1.9.0 (2026-01-01)** · test*
README
  cat > "$dir/commands/cmd.md" <<'CMD'
---
name: cmd
specops_version: 1.9.0
---

Content

*specops-ko v1.8.0 · 2026-01-01 · test*
CMD
  git -C "$dir" add -A
  git -C "$dir" commit -m "init" -q
}

# T1: AC-1 semver 검증
out=$(bash "$RELEASE" abc 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T1.a semver 'abc' → exit 1" || fail "T1.a (rc=$rc)"
out=$(bash "$RELEASE" 1.2 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T1.b semver '1.2' → exit 1" || fail "T1.b (rc=$rc)"
out=$(bash "$RELEASE" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "T1.c semver 인자 없음 → exit 1" || fail "T1.c (rc=$rc)"

# T2: AC-2 git 클린 워킹트리
TD=$(mktemp -d); _make_git_fixture "$TD"
echo "dirty" >> "$TD/README.md"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 2>&1); rc=$?
rm -rf "$TD"
[ "$rc" -eq 1 ] && echo "$out" | grep -q "클린하지 않" \
  && ok "T2.a git unclean → exit 1 + 메시지" || fail "T2.a (rc=$rc out='$out')"

# T2.b/c/d (FID 20261003-ops-debt): 클린 검사는 추적 변경(수정·스테이징·삭제)만 차단하고 untracked 는 경고
TD=$(mktemp -d); _make_git_fixture "$TD"
echo "x" > "$TD/scratch-note.txt"; mkdir -p "$TD/tmp-ui"; echo "y" > "$TD/tmp-ui/a.html"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
rm -rf "$TD"
{ [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q "클린하지 않" && printf '%s' "$out" | grep -qE "Warning: untracked 2개 — .*scratch-note.txt" && printf '%s' "$out" | grep -qF "tmp-ui/"; } \
  && ok "T2.b untracked 만 있음 → 클린 검사 통과(rc 0) + untracked 경고(개수·이름)" || fail "T2.b (rc=$rc out='$out')"
TD=$(mktemp -d); _make_git_fixture "$TD"
for i in 1 2 3 4 5 6 7; do echo "$i" > "$TD/u$i.txt"; done
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
rm -rf "$TD"
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "Warning: untracked 7개" && printf '%s' "$out" | grep -qF "외 2개"; } \
  && ok "T2.c untracked 7개 → 앞 5개 이름 + 외 2개" || fail "T2.c (rc=$rc out='$out')"
TD=$(mktemp -d); _make_git_fixture "$TD"
echo "staged" >> "$TD/README.md"; git -C "$TD" add README.md
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc1=$?
git -C "$TD" reset -q HEAD README.md; git -C "$TD" checkout -q -- README.md
rm "$TD/commands/cmd.md"
out2=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc2=$?
rm -rf "$TD"
{ [ "$rc1" -eq 1 ] && printf '%s' "$out" | grep -q "클린하지 않" && [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q "클린하지 않"; } \
  && ok "T2.d 스테이징 변경·추적 파일 삭제는 계속 차단(rc 1)" || fail "T2.d (rc1=$rc1 rc2=$rc2)"

# T2.e/f (Phase C 보정): untracked commands/*.md 는 stamp 수정·릴리즈 커밋·롤백 어디에도 끼지 않는다
TD=$(mktemp -d); _make_git_fixture "$TD"
printf -- '---\nname: draft\nspecops_version: 1.9.0\n---\n\n*specops-ko v1.0.0 · t*\n' > "$TD/commands/draft.md"
cp "$TD/commands/draft.md" "$TD/draft.before"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 2>&1); rc=$?
tr_=$(git -C "$TD" ls-files commands/draft.md); stat_=$(git -C "$TD" show --stat --format= HEAD)
{ [ "$rc" -eq 0 ] && [ -z "$tr_" ] && cmp -s "$TD/commands/draft.md" "$TD/draft.before" && ! printf '%s' "$stat_" | grep -q "draft.md"; } \
  && ok "T2.e untracked commands/draft.md → 릴리즈 커밋에 안 실리고 내용도 불변(rc 0)" || fail "T2.e (rc=$rc tracked='$tr_' stat='$stat_')"
rm -rf "$TD"
TD=$(mktemp -d); _make_git_fixture "$TD"
printf -- '---\nname: draft\nspecops_version: 1.9.0\n---\n\n*specops-ko v1.0.0 · t*\n' > "$TD/commands/draft.md"
cp "$TD/commands/draft.md" "$TD/draft.before"
# post-flight 만 실패하게 한다(버전 bump 후 README 에 v1.11.0 이 생기면 실패) — 파일이 이미 수정된 뒤의 롤백 경로를 탄다
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD="! grep -q v1.11.0 $TD/README.md" bash "$RELEASE" 1.11.0 2>&1); rc=$?
dirty=$(git -C "$TD" status --porcelain --untracked-files=no)
{ [ "$rc" -eq 1 ] && [ -z "$dirty" ] && cmp -s "$TD/commands/draft.md" "$TD/draft.before"; } \
  && ok "T2.f untracked 가 있어도 중간 실패 롤백이 추적 파일을 전부 복원(pathspec 오류 없음)" || fail "T2.f (rc=$rc dirty='$dirty')"
rm -rf "$TD"

# T3: AC-2 already tagged
TD=$(mktemp -d); _make_git_fixture "$TD"
git -C "$TD" tag v1.11.0
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 2>&1); rc=$?
rm -rf "$TD"
[ "$rc" -eq 1 ] && echo "$out" | grep -q "already tagged" \
  && ok "T3.a already tagged → exit 1 + 메시지" || fail "T3.a (rc=$rc out='$out')"

# T4: AC-4 CHANGELOG 변환
TD=$(mktemp -d); _make_git_fixture "$TD"
DATE=$(date +%Y-%m-%d)
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0
grep -q "## \[1.11.0\]" "$TD/CHANGELOG.md" \
  && grep -q "^## \[Unreleased\]$" "$TD/CHANGELOG.md" \
  && grep -q "\[Unreleased\]: .*/compare/v1.11.0\.\.\.HEAD" "$TD/CHANGELOG.md" \
  && grep -q "\[1.11.0\]: .*/compare/v1.9.0\.\.\.v1.11.0" "$TD/CHANGELOG.md" \
  && ok "T4.a CHANGELOG 변환 (헤딩+링크)" || fail "T4.a CHANGELOG"
rm -rf "$TD"

# T5: AC-5 README 배지
TD=$(mktemp -d); _make_git_fixture "$TD"
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0
grep -q "(v1.11.0)" "$TD/README.md" && ! grep -q "(v1.9.0)" "$TD/README.md" \
  && ok "T5.a README 배지 갱신" || fail "T5.a README"
rm -rf "$TD"

# T6: AC-6 footer 스탬프 불일치 수정
TD=$(mktemp -d); _make_git_fixture "$TD"
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0
# frontmatter=1.9.0, footer는 1.8.0 → footer가 1.9.0으로 수정되어야 함
grep -q "specops-ko v1.9.0" "$TD/commands/cmd.md" \
  && ! grep -q "specops-ko v1.8.0" "$TD/commands/cmd.md" \
  && ok "T6.a footer 스탬프 불일치 수정" || fail "T6.a footer"
rm -rf "$TD"

# T7: AC-7 git commit + annotated tag
TD=$(mktemp -d); _make_git_fixture "$TD"
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0
commit_msg=$(git -C "$TD" log --oneline -1 2>/dev/null)
tag_exists=$(git -C "$TD" tag -l "v1.11.0" 2>/dev/null)
echo "$commit_msg" | grep -q "chore: release v1.11.0" && [ "$tag_exists" = "v1.11.0" ] \
  && ok "T7.a git commit + annotated tag 생성" || fail "T7.a (commit='$commit_msg' tag='$tag_exists')"
rm -rf "$TD"

# T8: AC-8 --dry-run 파일 미변경
TD=$(mktemp -d); _make_git_fixture "$TD"
BEFORE=$(cat "$TD/CHANGELOG.md")
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run; rc=$?
AFTER=$(cat "$TD/CHANGELOG.md")
tag_after=$(git -C "$TD" tag -l "v1.11.0" 2>/dev/null)
[ "$rc" -eq 0 ] && [ "$BEFORE" = "$AFTER" ] && [ -z "$tag_after" ] \
  && ok "T8.a --dry-run: 파일 미변경, exit 0" || fail "T8.a (rc=$rc)"
rm -rf "$TD"

# T9: AC-9 pre-flight FAIL → abort, 파일 미변경
TD=$(mktemp -d); _make_git_fixture "$TD"
BEFORE=$(cat "$TD/CHANGELOG.md")
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=false bash "$RELEASE" 1.11.0 2>&1); rc=$?
AFTER=$(cat "$TD/CHANGELOG.md")
[ "$rc" -eq 1 ] && echo "$out" | grep -q "pre-flight 검증 실패" && [ "$BEFORE" = "$AFTER" ] \
  && ok "T9.a pre-flight FAIL → exit 1 + 파일 미변경" || fail "T9.a (rc=$rc)"
rm -rf "$TD"

# T-manifest: AC-1/AC-2 plugin.json + marketplace.json 버전 bump
TD=$(mktemp -d); _make_git_fixture "$TD"
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 > /dev/null 2>&1
plugin_ver=$(grep '"version"' "$TD/.claude-plugin/plugin.json" | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"')
market_ver=$(grep '"version"' "$TD/.claude-plugin/marketplace.json" | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"')
[ "$plugin_ver" = "1.11.0" ] \
  && ok "T-manifest.a plugin.json 버전 1.11.0 갱신" || fail "T-manifest.a (got: $plugin_ver)"
[ "$market_ver" = "1.11.0" ] \
  && ok "T-manifest.b marketplace.json 버전 1.11.0 갱신" || fail "T-manifest.b (got: $market_ver)"
rm -rf "$TD"

# T10: pre-flight 실제 경로 검증 (Important fix — PREFLIGHT_CMD 우회 없이)
# T10.a: 스크립트 파일 존재 확인
[ -f "$PLUGIN/scripts/_internal/validate-structure.sh" ] \
  && [ -f "$PLUGIN/scripts/tests/run-all.sh" ] \
  && ok "T10.a pre-flight 스크립트 경로 실재" || fail "T10.a pre-flight 경로 미존재"

# T10.b: 실제 repo dry-run — RELEASE_PREFLIGHT_CMD 미설정, repo clean 시에만 실행
# run-all 내부에서 호출된 경우(SPECOPS_RUN_ALL=1)에도 재귀 가드 메시지로 통과해야 함
if [ -z "$(git -C "$PLUGIN" status --porcelain 2>/dev/null)" ] \
    && ! git -C "$PLUGIN" tag -l "v9.99.0" 2>/dev/null | grep -q "v9.99.0"; then
  out=$(bash "$RELEASE" 9.99.0 --dry-run 2>&1); rc=$?
  [ "$rc" -eq 0 ] && echo "$out" | grep -qE "pre-flight (PASS|skip)" \
    && ok "T10.b 실제 pre-flight 경로 dry-run PASS" || fail "T10.b (rc=$rc out='$out')"
else
  ok "T10.b (SKIP — repo unclean 또는 v9.99.0 태그 존재)"
fi

# T11: 재귀 가드 — SPECOPS_RUN_ALL=1 + PREFLIGHT_CMD 미설정 → pre-flight skip (run-all 무한 재귀 방지)
TD=$(mktemp -d); _make_git_fixture "$TD"
out=$(RELEASE_PLUGIN_ROOT="$TD" SPECOPS_RUN_ALL=1 bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
rm -rf "$TD"
[ "$rc" -eq 0 ] && echo "$out" | grep -q "재귀 방지" \
  && ok "T11.a SPECOPS_RUN_ALL=1 → pre-flight skip (재귀 가드)" || fail "T11.a (rc=$rc out='$out')"

# T12: FR-6b README footer 최신 스탬프 갱신
TD=$(mktemp -d); _make_git_fixture "$TD"
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 > /dev/null 2>&1
TODAY=$(date +%Y-%m-%d)
grep -q "최신: v1.11.0 (${TODAY})" "$TD/README.md" && ! grep -q "최신: v1.9.0" "$TD/README.md" \
  && ok "T12.a README footer 최신 스탬프 갱신" || fail "T12.a (footer=$(grep '최신' "$TD/README.md"))"
rm -rf "$TD"

# T13: FR-7c marketplace metadata.description 버전 토큰 갱신
TD=$(mktemp -d); _make_git_fixture "$TD"
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 > /dev/null 2>&1
grep -q "(v1.11.0 — test)" "$TD/.claude-plugin/marketplace.json" \
  && ! grep -q "(v1.9.0 — test)" "$TD/.claude-plugin/marketplace.json" \
  && ok "T13.a marketplace description 버전 갱신" || fail "T13.a (desc=$(grep description "$TD/.claude-plugin/marketplace.json"))"
rm -rf "$TD"

# T14: FR-12 origin 존재 시 push + gh release 발행 (bare origin + gh stub — 실제 GitHub 호출 없음)
TD=$(mktemp -d); _make_git_fixture "$TD"
BARE=$(mktemp -d); git init --bare -q "$BARE"
git -C "$TD" remote add origin "$BARE"
git -C "$TD" push -q -u origin HEAD          # upstream 설정 (release.sh 의 `git push` 대상)
FAKEBIN=$(mktemp -d); GH_LOG=$(mktemp)
cat > "$FAKEBIN/gh" <<GHSTUB
#!/usr/bin/env bash
echo "\$@" >> "$GH_LOG"
exit 0
GHSTUB
chmod +x "$FAKEBIN/gh"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true PATH="$FAKEBIN:$PATH" bash "$RELEASE" 1.11.0 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "릴리즈 발행 완료" \
  && ok "T14.a origin 존재 → push+release exit 0" || fail "T14.a (rc=$rc out='$out')"
git -C "$BARE" tag -l "v1.11.0" 2>/dev/null | grep -q "v1.11.0" \
  && ok "T14.b 태그 v1.11.0 origin(bare) push 확인" || fail "T14.b 태그 미push"
grep -q "release create" "$GH_LOG" && grep -q -- "--verify-tag" "$GH_LOG" && grep -q -- "--latest" "$GH_LOG" \
  && ok "T14.c gh release create --verify-tag --latest 호출" || fail "T14.c (gh_log='$(cat "$GH_LOG")')"
grep -q -- "--notes-file" "$GH_LOG" \
  && ok "T14.d CHANGELOG 노트 --notes-file 전달" || fail "T14.d (gh_log='$(cat "$GH_LOG")')"
rm -rf "$TD" "$BARE" "$FAKEBIN" "$GH_LOG"

# T14p: 부분 릴리즈 — main push 는 되고 태그 push 가 거부되면(20261021 클라우드 403 재현) 어디까지 됐는지·마무리 방법을 알리고 rc 1
TD=$(mktemp -d); _make_git_fixture "$TD"
BARE=$(mktemp -d); git init --bare -q "$BARE"
printf '#!/usr/bin/env bash\nwhile read -r _o _n ref; do case "$ref" in refs/tags/*) echo "tags denied" >&2; exit 1 ;; esac; done\nexit 0\n' > "$BARE/hooks/pre-receive"
chmod +x "$BARE/hooks/pre-receive"
git -C "$TD" remote add origin "$BARE"
git -C "$TD" push -q -u origin HEAD
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true PATH="$(mktemp -d):$PATH" bash "$RELEASE" 1.11.0 2>&1); rc=$?
_sha=$(git -C "$TD" rev-parse --short HEAD)
{ [ "$rc" -eq 1 ] && echo "$out" | grep -q "부분 릴리즈 — '태그 push'" && echo "$out" | grep -q "main 은 이미 push 됐다(${_sha})" \
  && echo "$out" | grep -q "git push origin v1.11.0" && echo "$out" | grep -q "target ${_sha}" \
  && [ "$(git -C "$BARE" rev-parse --short HEAD)" = "$_sha" ] && [ -z "$(git -C "$BARE" tag -l v1.11.0)" ]; } \
  && ok "T14p.a 태그 push 거부 → rc 1 · main push 됨·태그 없음 · 수동 마무리(git push · 웹 target sha) 안내" || fail "T14p.a (rc=$rc out='$out')"
! echo "$out" | grep -q "릴리즈 발행 완료" && ok "T14p.b 부분 릴리즈를 완료로 보고하지 않음" || fail "T14p.b"
rm -rf "$TD" "$BARE"

# T15: FR-12 origin 부재 시 push/release skip (commit/tag 는 로컬 수행, exit 0)
TD=$(mktemp -d); _make_git_fixture "$TD"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "원격 origin 없음" \
  && ok "T15.a origin 부재 → push/release skip exit 0" || fail "T15.a (rc=$rc out='$out')"
git -C "$TD" tag -l "v1.11.0" 2>/dev/null | grep -q "v1.11.0" \
  && ok "T15.b origin 부재여도 로컬 태그 v1.11.0 생성" || fail "T15.b 로컬 태그 미생성"
rm -rf "$TD"

# T16: 버전 단조성 게이트 — 현재(plugin.json=1.9.0) 이하 버전 발행 차단 (B#1)
TD=$(mktemp -d); _make_git_fixture "$TD"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.5.0 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q "회귀/중복" \
  && ok "T16.a 회귀버전(1.5.0<1.9.0) → exit 1" || fail "T16.a (rc=$rc out='$out')"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.9.0 2>&1); rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q "회귀/중복" \
  && ok "T16.b 동일버전(1.9.0) → exit 1" || fail "T16.b (rc=$rc out='$out')"
# 상위 버전 통과는 기존 T4~T15(1.11.0)가 커버 — 음성 회귀만 추가
rm -rf "$TD"

# T17: CHANGELOG 멱등 — [VERSION] 섹션 이미 존재 시 이중삽입 방지 (B#2)
TD=$(mktemp -d); _make_git_fixture "$TD"
# 부분 실패 재실행 시뮬: CHANGELOG 에 [1.11.0] 선삽입 (plugin.json 은 1.9.0 유지 → 단조성 통과)
awk '/^## \[Unreleased\]$/{print; print ""; print "## [1.11.0] — 2026-01-01"; next} {print}' \
  "$TD/CHANGELOG.md" > "$TD/CHANGELOG.md.t" && mv "$TD/CHANGELOG.md.t" "$TD/CHANGELOG.md"
git -C "$TD" add -A; git -C "$TD" commit -q -m "pre"
RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 > /dev/null 2>&1
cnt=$(grep -c "^## \[1.11.0\]" "$TD/CHANGELOG.md")
[ "$cnt" -eq 1 ] && ok "T17.a CHANGELOG [1.11.0] 이중삽입 방지(멱등)" || fail "T17.a (heading count=$cnt)"
rm -rf "$TD"

# T18: B층 llm-eval staleness soft 경고 (AC-5) — dry-run + PREFLIGHT_CMD=true 로 빠른 실행
# fixture 에 .specops-cache/ gitignore 선반영 (스탬프 생성이 FR-2 클린 트리 게이트를 오염하지 않도록 — 실 repo 와 동일 조건)
_seed_stamp_ignore() {  # $1=fixture dir
  printf '.specops-cache/\n' > "$1/.gitignore"
  git -C "$1" add .gitignore
  git -C "$1" commit -q -m "ignore cache"
}

# T18.a 스탬프 부재 → "실행 기록 없음" 경고 + release 계속 (exit 0, dry-run 완주)
TD=$(mktemp -d); _make_git_fixture "$TD"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "실행 기록 없음" && echo "$out" | grep -q "DRY-RUN 완료" \
  && ok "T18.a 스탬프 부재 → soft 경고 + release 계속" || fail "T18.a (rc=$rc out='$out')"
rm -rf "$TD"

# T18.b 8일 전 스탬프 → "N일 경과" 경고 + release 계속 (mtime 조작 — Darwin -v / GNU -d fallback)
TD=$(mktemp -d); _make_git_fixture "$TD"; _seed_stamp_ignore "$TD"
mkdir -p "$TD/.specops-cache"
date -u +%Y-%m-%dT%H:%M:%SZ > "$TD/.specops-cache/llm-eval-last-run"
touch -t "$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)" "$TD/.specops-cache/llm-eval-last-run"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "일 경과" && echo "$out" | grep -q "DRY-RUN 완료" \
  && ok "T18.b 8일 경과 스탬프 → staleness 경고 + release 계속" || fail "T18.b (rc=$rc out='$out')"
rm -rf "$TD"

# T18.c 방금 스탬프 → 무경고 (3문구 전부 부재) + release 계속
TD=$(mktemp -d); _make_git_fixture "$TD"; _seed_stamp_ignore "$TD"
mkdir -p "$TD/.specops-cache"
date -u +%Y-%m-%dT%H:%M:%SZ > "$TD/.specops-cache/llm-eval-last-run"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! echo "$out" | grep -q "실행 기록 없음" && ! echo "$out" | grep -q "일 경과" \
  && ! echo "$out" | grep -q "판독 불가" && echo "$out" | grep -q "DRY-RUN 완료" \
  && ok "T18.c 신선 스탬프 → 무경고 + release 계속" || fail "T18.c (rc=$rc out='$out')"
rm -rf "$TD"

# ── T19: specops_version 부패 soft 경고 (M1, 20260806) ──────────────────────
# 실측 부패: start.md 가 d1af18d(08-04)에서 end-loaded 절이 추가됐는데 frontmatter 는 1.0.0.
# release.sh FR-7 은 footer↔frontmatter **동기**만 하고, "본문이 바뀌었는데 버전이 그대로"는
# 아무도 안 본다. CLAUDE.md 규약("마지막 substantive 변경 버전")이 조용히 썩는다.
_stale_fixture() {  # $1=dir — 직전 태그 이후 본문 변경 + 버전 미bump
  _make_git_fixture "$1"
  git -C "$1" tag v1.9.0
  printf '\n추가된 본문 절 — substantive 변경.\n' >> "$1/commands/cmd.md"
  git -C "$1" add -A && git -C "$1" commit -qm "feat: cmd 본문 변경 (버전 미bump)"
}

TD=$(mktemp -d); _stale_fixture "$TD"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'specops_version 미갱신' && echo "$out" | grep -q 'commands/cmd.md' \
  && ok "T19.a 본문 변경 + 버전 미bump → soft 경고" || fail "T19.a (rc=$rc out='$out')"
rm -rf "$TD"

# T19.b: 버전을 올렸으면 무경고 (false-positive 없음)
TD=$(mktemp -d); _make_git_fixture "$TD"
git -C "$TD" tag v1.9.0
printf '\n본문 변경.\n' >> "$TD/commands/cmd.md"
sed -i.bak 's/^specops_version: 1.9.0/specops_version: 1.10.0/' "$TD/commands/cmd.md" && rm -f "$TD/commands/cmd.md.bak"
git -C "$TD" add -A && git -C "$TD" commit -qm "feat: 본문 변경 + 버전 bump"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'specops_version 미갱신' \
  && ok "T19.b 버전 bump 됨 → 무경고" || fail "T19.b (rc=$rc out='$out')"
rm -rf "$TD"

# T19.c: footer 스탬프만 바뀐 diff 는 substantive 아님 → 무경고 (release.sh FR-7 이 매 릴리즈 건드림)
TD=$(mktemp -d); _make_git_fixture "$TD"
git -C "$TD" tag v1.9.0
sed -i.bak 's/^\*specops-ko v1.8.0.*/*specops-ko v1.9.0 · 2026-01-02 · test*/' "$TD/commands/cmd.md" && rm -f "$TD/commands/cmd.md.bak"
git -C "$TD" add -A && git -C "$TD" commit -qm "chore: footer 스탬프만"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'specops_version 미갱신' \
  && ok "T19.c footer-only diff → 무경고" || fail "T19.c (rc=$rc out='$out')"
rm -rf "$TD"

# T19.f: ★ diff 집계가 stderr 오류를 내지 않는다 (20260806 회귀)
# 결함: `{ pipeline; } 2>/dev/null || echo 0` 은 wc 가 이미 "0" 을 낸 뒤 `echo 0` 이
#   **한 번 더** 붙어 "0\n0" 이 된다(set -euo pipefail 에서 grep 무매치 → 파이프라인 실패).
#   그러면 `[ "0\n0" -gt 0 ]` 가 `integer expression expected` 를 뱉고 rc=2 →
#   `|| continue` 로 흡수돼 **그 파일은 판정에서 조용히 누락**된다(false negative + 잡음).
#   dast-scan.sh 가 이미 문서화한 `grep -c` 0매치 패턴의 재발.
TD=$(mktemp -d); _make_git_fixture "$TD"
git -C "$TD" tag v1.9.0
sed -i.bak 's/^\*specops-ko v1.8.0.*/*specops-ko v1.9.0 · 2026-01-02 · test*/' "$TD/commands/cmd.md"
rm -f "$TD/commands/cmd.md.bak"
git -C "$TD" add -A && git -C "$TD" commit -qm "chore: footer 스탬프만"
err=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1 >/dev/null)
! printf '%s' "$err" | grep -q 'integer expression expected' \
  && ok "T19.f diff 집계 stderr 오류 0 (0매치 이중값 회귀)" || fail "T19.f (err='$err')"
rm -rf "$TD"

# T19.e: ★ 직전 태그 시점에 **없던 파일**이 있어도 죽지 않는다 (20260806 회귀)
# 결함: `git show <tag>:<newfile>` 은 exit 128 이고, release.sh 는 set -euo pipefail 이라
#   그 자리에서 스크립트가 통째로 중단됐다(rc=128). 신규 커맨드가 추가된 릴리즈는
#   **항상** 이 경로를 탄다 — 실측: v1.60.0 이후 추가된 commands/start-lite.md.
#   워킹트리가 dirty 하면 T10.b 가 skip 되어 세션 내내 가려져 있었다.
TD=$(mktemp -d); _make_git_fixture "$TD"
git -C "$TD" tag v1.9.0
cat > "$TD/commands/newcmd.md" <<'CMD'
---
name: newcmd
specops_version: 1.9.0
---
태그 이후 신설된 커맨드.
CMD
git -C "$TD" add -A && git -C "$TD" commit -qm "feat: 신규 커맨드 추가"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'DRY-RUN 완료' \
  && ok "T19.e 태그 시점 부재 파일 → 중단 없이 완주" || fail "T19.e (rc=$rc out='$out')"
rm -rf "$TD"

# T19.d: 태그 부재(최초 릴리즈) → 판정 불가 fail-open, 차단 없음
TD=$(mktemp -d); _make_git_fixture "$TD"
out=$(RELEASE_PLUGIN_ROOT="$TD" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.11.0 --dry-run 2>&1); rc=$?
[ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'specops_version 미갱신' \
  && ok "T19.d 태그 부재 → fail-open 무경고" || fail "T19.d (rc=$rc out='$out')"
rm -rf "$TD"

# T20: 릴리즈 push 재귀 가드 (20260820-release-push-guard)
# git push 는 원격이 필요해 실행 검증 불가(release.sh:248 origin 부재 skip) → 정적 검사로 계약을 잠근다.
PREPUSH="$PLUGIN/.githooks/pre-push"

# T20.a: push 2줄 모두 SPECOPS_RUN_ALL=1 prefix (AC-1)
push_lines=$(grep -cE '^[[:space:]]*SPECOPS_RUN_ALL=1[[:space:]]+git[[:space:]]+-C[[:space:]]+"\$PLUGIN_ROOT"[[:space:]]+push' "$RELEASE")
bare_push=$(grep -cE '^[[:space:]]*git[[:space:]]+-C[[:space:]]+"\$PLUGIN_ROOT"[[:space:]]+push' "$RELEASE")
[ "$push_lines" -eq 2 ] && [ "$bare_push" -eq 0 ] \
  && ok "T20.a push 2줄 SPECOPS_RUN_ALL=1 prefix (guarded=$push_lines bare=$bare_push)" \
  || fail "T20.a (guarded=$push_lines bare=$bare_push — 둘 다 prefix 필요)"

# T20.b: 전역 대입 금지 — standalone 대입/export 는 0건이어야 한다 (AC-2)
#         전역 설정 시 release.sh:65 가 pre-flight 자체를 skip 해 게이트가 전면 상실된다.
#   ★ 반드시 줄 끝 앵커(`$`)로 **standalone 대입만** 잡을 것. 앵커가 없으면 T20.a 가 요구하는
#     `SPECOPS_RUN_ALL=1 git ...` prefix 줄까지 매칭해 GREEN 을 자기격추한다 (실측: 앵커 없이 3, 있으면 1).
#     `(#.*)?` 는 trailing 주석 우회를 막는다 — `export SPECOPS_RUN_ALL=1  # 가드` 가
#     앵커만으로는 빠져나갔다 (Phase C 실측). prefix 줄은 뒤가 `git` 이라 여전히 미매칭.
global_set=$(grep -cE '^[[:space:]]*(export[[:space:]]+)?SPECOPS_RUN_ALL=[^[:space:]]*[[:space:]]*(#.*)?$' "$RELEASE")
[ "$global_set" -eq 0 ] \
  && ok "T20.b SPECOPS_RUN_ALL standalone 대입 없음" \
  || fail "T20.b standalone 대입 ${global_set}건 — pre-flight skip 회귀 (release.sh:65)"

# T20.c: CI-red 경고 보존 — push 줄보다 앞에 check-ci-status.sh 호출 (AC-3)
ci_ln=$(grep -nE 'check-ci-status\.sh' "$RELEASE" | tail -1 | cut -d: -f1)
push_ln=$(grep -nE 'SPECOPS_RUN_ALL=1[[:space:]]+git[[:space:]]+-C' "$RELEASE" | head -1 | cut -d: -f1)
# 비차단 계약: set -euo pipefail 하에서 CI 체크 실패가 릴리즈를 중단시키면 안 된다 (AC-3·AC-R-2)
nonblock=$(grep -cE 'CI_CHECK.*\|\|[[:space:]]*true' "$RELEASE")
# 서브셸 cd 계약: check-ci-status.sh 는 origin 을 cwd 기준으로 본다 → cd 누락 시 CI 경고 무음 소실
subcd=$(grep -cE '\(cd "\$PLUGIN_ROOT" && bash "\$CI_CHECK"\)' "$RELEASE")
if [ -n "$ci_ln" ] && [ -n "$push_ln" ] && [ "$ci_ln" -lt "$push_ln" ] && [ "$nonblock" -ge 1 ] && [ "$subcd" -ge 1 ]; then
  ok "T20.c check-ci-status 호출이 push 앞 + 비차단 + 서브셸 cd (ci=$ci_ln push=$push_ln nonblock=$nonblock subcd=$subcd)"
else
  fail "T20.c (ci=${ci_ln:-없음} push=${push_ln:-없음} nonblock=$nonblock subcd=$subcd — push 앞 비차단 호출 + 서브셸 cd 필요)"
fi

# T20.d: pre-flight 러너 == pre-push 러너 (AC-7)
#         두 경로가 갈라지면 "pre-flight 가 이미 검증했다"는 가드 전제가 깨진다.
rel_runner=$(grep -oE '_run_check "[^"]*run-all[^"]*"' "$RELEASE" | head -1 | sed 's/.*"\(.*\)"/\1/')
hook_runner=$(grep -oE 'RUN_ALL="[^"]*"' "$PREPUSH" | head -1 | sed 's/.*"\(.*\)"/\1/')
[ -n "$rel_runner" ] && [ "$rel_runner" = "$hook_runner" ] \
  && ok "T20.d pre-flight/pre-push 동일 러너 ($rel_runner)" \
  || fail "T20.d 러너 불일치 (release='$rel_runner' pre-push='$hook_runner')"

# T21: pre-flight 신선도 생략 (20261024-speed-release-fresh-task-record)
#   같은 비문서 트리의 통과 마커가 있으면 오버라이드(=false · 돌면 실패)조차 부르지 않고 지나간다. 마커가 없거나 FORCE_FULL 이면 종전대로 돈다.
TF21=$(mktemp -d) || exit 1
_make_git_fixture "$TF21"
printf '.specops/\n' >> "$TF21/.git/info/exclude"
mkdir -p "$TF21/.specops"
_fp21=$( cd "$TF21" && bash -c ". \"$PLUGIN/scripts/_internal/verification-state.sh\"; vs::nondoc_fingerprint" )
_r21() { ( cd "$TF21" && env -u SPECOPS_FORCE_FULL -u SPECOPS_RUN_ALL "$@" RELEASE_PLUGIN_ROOT="$TF21" RELEASE_PREFLIGHT_CMD=false bash "$RELEASE" 1.10.0 --dry-run 2>&1 ); }
out=$(_r21); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'pre-flight 검증 실패'; } && ok "T21.a 마커 없음 → 종전대로 실행(실패 전파)" || fail "T21.a (rc=$rc)"
printf '%s\n' "$_fp21" > "$TF21/.specops/.full-suite-pass"
out=$(_r21); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF -- '-> pre-flight skip (full-suite FRESH (fp=' && ! printf '%s' "$out" | grep -q 'pre-flight 검증 실패'; } \
  && ok "T21.b 마커 == 지문 → pre-flight skip · 오버라이드 미호출" || fail "T21.b (rc=$rc out=$(printf '%s' "$out" | head -3))"
out=$(_r21 SPECOPS_FORCE_FULL=1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'pre-flight 검증 실패'; } && ok "T21.c FORCE_FULL → 마커가 있어도 실행" || fail "T21.c (rc=$rc)"
printf 'stale\n' > "$TF21/.specops/.full-suite-pass"
out=$(_r21); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'pre-flight 검증 실패'; } && ok "T21.d 지문 불일치 → 실행" || fail "T21.d (rc=$rc)"
# T21.f: cwd 가 FRESH 인 다른 트리여도 판정은 PLUGIN_ROOT 기준(cd "$PLUGIN_ROOT" 누락 금지) — T21.e 앞에 둔다
TF21o=$(mktemp -d) || exit 1
_make_git_fixture "$TF21o"
printf '.specops/\n' >> "$TF21o/.git/info/exclude"; mkdir -p "$TF21o/.specops"
printf '%s\n' "$_fp21" > "$TF21o/.specops/.full-suite-pass"
printf 'stale\n' > "$TF21/.specops/.full-suite-pass"
out=$( cd "$TF21o" && env -u SPECOPS_FORCE_FULL -u SPECOPS_RUN_ALL RELEASE_PLUGIN_ROOT="$TF21" RELEASE_PREFLIGHT_CMD=false bash "$RELEASE" 1.10.0 --dry-run 2>&1 ); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'pre-flight 검증 실패'; } && ok "T21.f cwd 가 FRESH 인 다른 트리여도 PLUGIN_ROOT 기준으로 판정" || fail "T21.f (rc=$rc)"
rm -rf "$TF21o"
# T21.e: 자기 마커 없음 + 다른 worktree 마커 == 지문 → skip (release 가 --any-worktree 로 부른다)
TW21=$(mktemp -d) || exit 1; rmdir "$TW21"
if git -C "$TF21" worktree add -q -b t21-wt "$TW21" 2>/dev/null; then
  mkdir -p "$TW21/.specops"
  rm -f "$TF21/.specops/.full-suite-pass"
  printf '%s\n' "$_fp21" > "$TW21/.specops/.full-suite-pass"
  out=$(_r21); rc=$?
  { [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF -- "-> pre-flight skip (full-suite FRESH (fp=${_fp21:0:12}, worktree=" \
      && printf '%s' "$out" | grep -qF "$(basename "$TW21")" && ! printf '%s' "$out" | grep -q 'pre-flight 검증 실패'; } \
    && ok "T21.e 자기 마커 없음 + 다른 worktree 마커 == 지문 → skip(--any-worktree)" || fail "T21.e (rc=$rc out=$(printf '%s' "$out" | head -3))"
  git -C "$TF21" worktree remove --force "$TW21" 2>/dev/null
else
  fail "T21.e worktree 픽스처 생성 실패"
fi
rm -rf "$TW21" "$TF21"
# T21.g: 생략해도 문서 수치·구조 검사는 돈다 — 문서만 바뀐 트리도 비문서 지문은 같다(release 는 main 에 직접 push)
TF21g=$(mktemp -d) || exit 1
_make_git_fixture "$TF21g"
printf '.specops/\n' >> "$TF21g/.git/info/exclude"; mkdir -p "$TF21g/.specops" "$TF21g/scripts/_internal"
printf 'exit 1\n' > "$TF21g/scripts/_internal/check-doc-numbers.sh"
git -C "$TF21g" add scripts && git -C "$TF21g" -c user.name=T -c user.email=t@t.com commit -qm stub
( cd "$TF21g" && bash -c ". \"$PLUGIN/scripts/_internal/verification-state.sh\"; vs::nondoc_fingerprint" ) > "$TF21g/.specops/.full-suite-pass"
out=$( cd "$TF21g" && env -u SPECOPS_FORCE_FULL -u SPECOPS_RUN_ALL RELEASE_PLUGIN_ROOT="$TF21g" RELEASE_PREFLIGHT_CMD=true bash "$RELEASE" 1.10.0 --dry-run 2>&1 ); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF -- '-> pre-flight skip (full-suite FRESH' && printf '%s' "$out" | grep -qF 'pre-flight 검증 실패 (scripts/_internal/check-doc-numbers.sh)'; } \
  && ok "T21.g 생략 뒤에도 문서 수치 검사를 돌려 실패를 전파" || fail "T21.g (rc=$rc)"
rm -rf "$TF21g"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
