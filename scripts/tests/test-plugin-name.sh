#!/usr/bin/env bash
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "PASS $1"; }; nope(){ FAIL=$((FAIL+1)); echo "FAIL $1 — $2"; }
# PN1 (AC-1) 매니페스트
v=$(jq -r '.name' "$ROOT/.claude-plugin/plugin.json")
m=$(jq -r '.name + "|" + .plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")
[ "$v|$m" = "devfsd|devfsd|devfsd" ] && ok "PN1 매니페스트 이름 devfsd" || nope PN1 "$v|$m"
# PN2 (AC-3) 허용 목록 밖 잔존 0 — 허용은 줄이 아니라 **경로**로 뺀다
#   허용 경로: 이력(CHANGELOG·docs/audit·docs/case-studies·docs/governance-history.md) +
#   3.x 호환 파일(Task 2 가 옛 접두사를 일부러 두는 훅 5개·그 테스트 2개·옛 접두사 픽스처 생성 줄이 있는 파일) + 이 스위트
ALLOW_PATHS=(CHANGELOG.md docs/audit docs/case-studies docs/governance-history.md
  hooks/rules.jsonl hooks/governance-lib.sh hooks/posttool-governance.sh hooks/hooks.json hooks/save-review-report.sh
  scripts/tests/governance/test-rules.sh scripts/tests/governance/test-pretool.sh scripts/tests/governance/test-hooks.sh scripts/tests/test-save-review-report.sh
  scripts/tests/test-plugin-name.sh)
OLD_RE='specops-ko[[:space:]]*:[a-z*]|specops-ko@|plugins/cache/specops-ko|SPECOPS-KO:'
scan_old_ns() {  # $1 = repo 루트 · stdout = 위반 줄 · rc 0=스캔 성공(위반 유무 무관) 2=스캔 실패
  local d="$1" ex=() p out rc
  for p in "${ALLOW_PATHS[@]}"; do ex+=(":!$p"); done
  out=$(cd "$d" && git grep -n -i -E "$OLD_RE" -- . "${ex[@]}" 2>&1); rc=$?
  [ "$rc" -le 1 ] || { echo "$out"; return 2; }
  printf '%s' "$out"
}
left=$(scan_old_ns "$ROOT"); src=$?
{ [ "$src" -eq 0 ] && [ -z "$left" ]; } && ok "PN2 옛 namespace 잔존 0 (허용 경로 밖)" || nope PN2 "rc=$src $(printf '%s\n' "$left" | head -5)"
# PN2.self 스캐너 자기 검증 — 임시 repo 에 위반 3변형(:·@·cache 경로)을 심으면 3줄을 잡는다
_t=$(mktemp -d); ( cd "$_t" && git init -q && printf 'Skill: specops-ko:planning-ko\nx specops-ko@specops-ko\n~/.claude/plugins/cache/specops-ko/\nok devfsd:planning-ko\n' > a.md && git add a.md ) >/dev/null 2>&1
n=$(scan_old_ns "$_t" | grep -c .); rm -rf "$_t"
[ "$n" = 3 ] && ok "PN2.self 스캐너가 위반 3변형을 잡음" || nope PN2.self "잡은 줄 $n (기대 3)"
# PN3 (AC-4) 표기 — README 제목·감독형 설명·설치 id
rd="$ROOT/README.md"
{ grep -q '^# devFSD' "$rd" && grep -q '개발 자율주행' "$rd" && grep -qE '감독형.*설계 승인.*PR 병합' "$rd" \
  && grep -q 'claude plugin install devfsd@devfsd' "$rd"; } && ok "PN3 README devFSD·감독형·설치 id" || nope PN3 "README 표기"
{ grep -q 'devFSD' "$ROOT/CONTRIBUTING.md" && grep -q 'devFSD' "$ROOT/CLAUDE.md" \
  && grep -q '^title="devFSD"' "$ROOT/hooks/notify.sh" && grep -q '^FALLBACK="◆ devFSD"' "$ROOT/scripts/statusline.sh"; } \
  && ok "PN3b CONTRIBUTING·CLAUDE.md·알림·statusline 표기" || nope PN3b "표기"
echo "==== Results: PASS=$PASS FAIL=$FAIL ===="; [ "$FAIL" -eq 0 ]
