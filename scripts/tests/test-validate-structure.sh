#!/usr/bin/env bash
# specops-ko v0.0 PoC · scripts/_internal/validate-structure.sh 검증
# baseline: P1 flat — commands=1, skills/<name>/SKILL.md=16, templates=6 (sandbox 격리)
# U4 후: sandbox 가 .structure-baseline 자체 생성. agents/ 빈 디렉토리 OK.
# (meta skill 필수: skills/using-specops-ko/SKILL.md + hooks/session-start.sh exec-bit)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/_internal/validate-structure.sh"

source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
command -v iso::make_tree >/dev/null 2>&1 && command -v iso::fingerprint >/dev/null 2>&1 \
  || { echo "FATAL: isolated-tree 미로드(또는 반쯤 로드)" >&2; exit 1; }
# ISO pathspec = T-hg.b 가 (격리 전) 변이하던 유일한 실 파일
_iso_paths='skills/specifying-ko/SKILL.md'
_iso_before=$(iso::fingerprint $_iso_paths)

# T1 현재 플러그인 실행 — 모든 항목 OK 또는 INFO/SKIP, FAILS=0
out=$(bash "$SCRIPT" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '✅ directories: OK' && echo "$out" | grep -q '✅ file_counts: OK'; then
  PASS=$((PASS+1)); echo "PASS T1 current plugin passes"
else
  FAIL=$((FAIL+1)); echo "FAIL T1 current plugin (rc=$rc)"
  echo "$out" | sed 's/^/    /'
fi

# T2 --json 출력 파싱 가능
out=$(bash "$SCRIPT" --json 2>&1); rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | python3 -c "import sys,json; j=json.load(sys.stdin); assert 'fails' in j and 'checks' in j" 2>/dev/null; then
  PASS=$((PASS+1)); echo "PASS T2 --json parseable"
else
  FAIL=$((FAIL+1)); echo "FAIL T2 --json (rc=$rc)"
fi

source "$PLUGIN/scripts/tests/lib/vs-sandbox.sh"  # SKILL_NAMES · make_sandbox · add_docs (chain 스위트와 공유)


# T3a 정상 baseline sandbox — OK
sb=$(mktemp -d); make_sandbox "$sb"
out=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '✅ file_counts: OK' && echo "$out" | grep -q '✅ meta_injection: OK'; then
  PASS=$((PASS+1)); echo "PASS T3a baseline sandbox passes"
else
  FAIL=$((FAIL+1)); echo "FAIL T3a baseline sandbox (rc=$rc)"
  echo "$out" | sed 's/^/    /'
fi
rm -rf "$sb"

# T3b skills 15개(baseline 16에서 -1) — FAIL
sb=$(mktemp -d); make_sandbox "$sb"; rm -rf "$sb/skills/context-resets-ko"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'file_counts: FAIL'; then
  PASS=$((PASS+1)); echo "PASS T3b skills 15개 FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T3b (rc=$rc)"
fi
rm -rf "$sb"

# T3c 메타 skill 누락 — FAIL (P1 핵심 가설 위반)
sb=$(mktemp -d); make_sandbox "$sb"; rm -rf "$sb/skills/using-specops-ko"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'meta_injection: FAIL'; then
  PASS=$((PASS+1)); echo "PASS T3c 메타 skill 누락 FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T3c (rc=$rc)"
fi
rm -rf "$sb"

# T3d session-start.sh exec-bit 없음 — FAIL
sb=$(mktemp -d); make_sandbox "$sb"; chmod -x "$sb/hooks/session-start.sh"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'meta_injection: FAIL'; then
  PASS=$((PASS+1)); echo "PASS T3d session-start exec-bit 없음 FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T3d (rc=$rc)"
fi
rm -rf "$sb"

# T4 commands/start.md 에 superpowers 런타임 참조 삽입 — FAIL
sb=$(mktemp -d); make_sandbox "$sb"
printf -- '---\nname: bad\n---\nsuperpowers: call-this-at-runtime\n' > "$sb/commands/start.md"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'no_superpowers: FAIL'; then
  PASS=$((PASS+1)); echo "PASS T4 superpowers runtime ref FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T4 (rc=$rc, out=$(echo "$err" | head -10))"
fi
rm -rf "$sb"

# T5 manifest version 불일치 — FAIL
sb=$(mktemp -d); make_sandbox "$sb"
echo '{"version":"0.2.0"}' > "$sb/.claude-plugin/plugin.json"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'manifest: FAIL'; then
  PASS=$((PASS+1)); echo "PASS T5 version mismatch FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T5 (rc=$rc)"
fi
rm -rf "$sb"

# T6 frontmatter 손상 — FAIL (python3+pyyaml 가정)
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
  sb=$(mktemp -d); make_sandbox "$sb"
  printf -- '---\nname: { unclosed\n  - bad\n---\n' > "$sb/commands/start.md"
  err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
  if [ $rc -eq 1 ] && echo "$err" | grep -q 'frontmatter: FAIL'; then
    PASS=$((PASS+1)); echo "PASS T6 broken frontmatter FAIL"
  else
    FAIL=$((FAIL+1)); echo "FAIL T6 (rc=$rc)"
  fi
  rm -rf "$sb"
else
  PASS=$((PASS+1)); echo "PASS T6 skipped (pyyaml 미설치)"
fi

# T7 실행권한
if [ -x "$SCRIPT" ]; then
  PASS=$((PASS+1)); echo "PASS T7 exec-bit"
else
  FAIL=$((FAIL+1)); echo "FAIL T7 exec-bit"
fi

# ── U4 회귀: .structure-baseline 동적화 ─────────

# T8.a baseline 부재 → file_counts FAIL + 명시 메시지
sb=$(mktemp -d); make_sandbox "$sb"
rm -f "$sb/scripts/_internal/.structure-baseline"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q '.structure-baseline 부재'; then
  PASS=$((PASS+1)); echo "PASS T8.a (U4) baseline 부재 → FAIL + 명시 메시지"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.a (rc=$rc, out=$(echo "$err" | head -3 | tr '\n' ';'))"
fi
rm -rf "$sb"

# T8.b baseline 카운트가 실측과 다름 → FAIL + "got X, expect Y"
sb=$(mktemp -d); make_sandbox "$sb"
# templates 카운트를 6 → 99 로 의도적으로 mismatch
sed -i.bak 's/"glob":"templates\/\*.md","count":6/"glob":"templates\/*.md","count":99/' "$sb/scripts/_internal/.structure-baseline"
rm -f "$sb/scripts/_internal/.structure-baseline.bak"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'templates: got 6, expect 99'; then
  PASS=$((PASS+1)); echo "PASS T8.b (U4) 카운트 mismatch → FAIL + got/expect 메시지"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.b (rc=$rc, out=$(echo "$err" | grep file_counts))"
fi
rm -rf "$sb"

# T8.c --update-baseline → 갱신 후 재검증 PASS
sb=$(mktemp -d); make_sandbox "$sb"
# templates 카운트를 6 → 99 mismatch
sed -i.bak 's/"glob":"templates\/\*.md","count":6/"glob":"templates\/*.md","count":99/' "$sb/scripts/_internal/.structure-baseline"
rm -f "$sb/scripts/_internal/.structure-baseline.bak"
# --update-baseline 호출 → 실측 6 으로 갱신
update_out=$(bash "$sb/scripts/_internal/validate-structure.sh" --update-baseline 2>&1)
update_rc=$?
# 재검증 → PASS 기대
revalidate_out=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1)
revalidate_rc=$?
if [ $update_rc -eq 0 ] && [ $revalidate_rc -eq 0 ] \
   && echo "$update_out" | grep -q '갱신 완료' \
   && echo "$revalidate_out" | grep -q '✅ file_counts: OK' \
   && grep -q '"count":6' "$sb/scripts/_internal/.structure-baseline"; then
  PASS=$((PASS+1)); echo "PASS T8.c (U4) --update-baseline → 갱신 후 재검증 PASS"
else
  FAIL=$((FAIL+1)); echo "FAIL T8.c (update_rc=$update_rc revalidate_rc=$revalidate_rc)"
fi
rm -rf "$sb"

# ── drift guard (v1.12): version_sync · readme_counts · changelog_body · xref_resolve ─────────


# T9.a docs 정합 → 신규 체크 4종 전부 OK + rc=0
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
out=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '✅ version_sync: OK' \
   && echo "$out" | grep -q '✅ readme_counts: OK' \
   && echo "$out" | grep -q '✅ changelog_body: OK' \
   && echo "$out" | grep -q '✅ xref_resolve: OK'; then
  PASS=$((PASS+1)); echo "PASS T9.a drift 4종 정합 → OK"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.a (rc=$rc)"; echo "$out" | sed 's/^/    /'
fi
rm -rf "$sb"

# T9.b README footer 버전 불일치 → version_sync FAIL
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
sed -i.bak 's/최신: v0.1.0/최신: v0.0.9/' "$sb/README.md"; rm -f "$sb/README.md.bak"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'version_sync: FAIL' && echo "$err" | grep -q 'README.footer=v0.0.9'; then
  PASS=$((PASS+1)); echo "PASS T9.b footer drift → version_sync FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.b (rc=$rc, out=$(echo "$err" | grep version_sync))"
fi
rm -rf "$sb"

# T9.c CHANGELOG 최신 헤딩 버전 불일치 → version_sync FAIL
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
sed -i.bak 's/## \[0.1.0\]/## [0.0.9]/' "$sb/CHANGELOG.md"; rm -f "$sb/CHANGELOG.md.bak"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'version_sync: FAIL' && echo "$err" | grep -q 'CHANGELOG.latest=0.0.9'; then
  PASS=$((PASS+1)); echo "PASS T9.c CHANGELOG drift → version_sync FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.c (rc=$rc, out=$(echo "$err" | grep version_sync))"
fi
rm -rf "$sb"

# T9.d marketplace description 버전 토큰 불일치 → version_sync FAIL
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
echo '{"metadata":{"description":"test (v0.0.9 — local)"},"plugins":[{"version":"0.1.0"}]}' > "$sb/.claude-plugin/marketplace.json"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'version_sync: FAIL' && echo "$err" | grep -q 'marketplace.description=v0.0.9'; then
  PASS=$((PASS+1)); echo "PASS T9.d marketplace description drift → version_sync FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.d (rc=$rc, out=$(echo "$err" | grep version_sync))"
fi
rm -rf "$sb"

# T9.e README/CHANGELOG 부재 (기존 sandbox) → version_sync SKIP (기존 테스트 비파괴)
sb=$(mktemp -d); make_sandbox "$sb"
out=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q 'version_sync: SKIP'; then
  PASS=$((PASS+1)); echo "PASS T9.e docs 부재 → SKIP (graceful)"
else
  FAIL=$((FAIL+1)); echo "FAIL T9.e (rc=$rc)"
fi
rm -rf "$sb"

# T10.a README skill 카운트 불일치 → readme_counts FAIL
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
sed -i.bak 's/× 16/× 99/' "$sb/README.md"; rm -f "$sb/README.md.bak"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'readme_counts: FAIL' && echo "$err" | grep -q 'README=99 actual=16'; then
  PASS=$((PASS+1)); echo "PASS T10.a skill 카운트 drift → readme_counts FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T10.a (rc=$rc, out=$(echo "$err" | grep readme_counts))"
fi
rm -rf "$sb"

# T10.b README 의 슬래시 명령 수 불일치 → readme_counts FAIL (종전엔 세지 않아 README 25 · 설계 문서 24 · 실제 28 로 갈라져 있었다)
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
printf '├── commands/           슬래시 진입로 99건\n' >> "$sb/README.md"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'readme_counts: FAIL' && echo "$err" | grep -q 'commands: README=99 actual='; then
  PASS=$((PASS+1)); echo "PASS T10.b 명령 수 drift(README) → readme_counts FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T10.b (rc=$rc, out=$(echo "$err" | grep readme_counts))"
fi
rm -rf "$sb"
# T10.d 실 README·설계 문서에 검사가 읽는 줄이 있다 — 문구 형태가 바뀌면 검사는 조용히 꺼진다(줄을 못 찾으면 건너뛴다)
if grep -qE 'commands/.*슬래시 진입로 [0-9]+건' "$PLUGIN/README.md" && grep -qE '^\| 슬래시 커맨드 \| [0-9]+건' "$PLUGIN/docs/architecture.md"; then
  PASS=$((PASS+1)); echo "PASS T10.d 실 README·설계 문서에 명령 수 줄이 검사가 읽는 형태로 있다"
else
  FAIL=$((FAIL+1)); echo "FAIL T10.d 명령 수 줄을 찾지 못함 — readme_counts 의 명령 수 대조가 꺼져 있다"
fi
# T10.c 설계 문서의 슬래시 커맨드 행 불일치 → readme_counts FAIL · 맞으면 OK
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
_ncmd=$(ls "$sb"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
mkdir -p "$sb/docs"; printf '| 항목 | 값 |\n|---|---|\n| 슬래시 커맨드 | 99건 |\n' > "$sb/docs/architecture.md"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
printf '| 항목 | 값 |\n|---|---|\n| 슬래시 커맨드 | %s건 |\n' "$_ncmd" > "$sb/docs/architecture.md"
out=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1)
if [ $rc -eq 1 ] && echo "$err" | grep -q 'commands: docs/architecture.md=99 actual=' && echo "$out" | grep -q '✅ readme_counts: OK'; then
  PASS=$((PASS+1)); echo "PASS T10.c 명령 수 drift(설계 문서) → FAIL · 맞추면 OK"
else
  FAIL=$((FAIL+1)); echo "FAIL T10.c (rc=$rc, err=$(echo "$err" | grep readme_counts) out=$(echo "$out" | grep readme_counts))"
fi
rm -rf "$sb"

# T11.a CHANGELOG 최신 릴리즈 본문 공백 → changelog_body FAIL
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
cat > "$sb/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.1.0] — 2026-01-01

## [0.0.9] — 2025-12-01

### Added
- old
EOF
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'changelog_body: FAIL'; then
  PASS=$((PASS+1)); echo "PASS T11.a 최신 릴리즈 본문 공백 → changelog_body FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T11.a (rc=$rc, out=$(echo "$err" | grep changelog_body))"
fi
rm -rf "$sb"

# T12.a 미존재 skill 토큰 참조 → xref_resolve FAIL
sb=$(mktemp -d); make_sandbox "$sb"; add_docs "$sb"
printf -- '---\nname: tdd-ko\n---\n다음은 devfsd:nonexistent-zz 호출.\n' > "$sb/skills/tdd-ko/SKILL.md"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'xref_resolve: FAIL' && echo "$err" | grep -q 'nonexistent-zz'; then
  PASS=$((PASS+1)); echo "PASS T12.a 미존재 토큰 → xref_resolve FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.a (rc=$rc, out=$(echo "$err" | grep xref_resolve))"
fi
rm -rf "$sb"

# ── xref bare 토큰 (FID 20260713-ghost-agent-drift): prefix 없는 유령 에이전트 적발 ─────────
# 배경: 기존 xref_resolve 는 `devfsd:` prefix 토큰만 수집 → bare 로 서술된 유령
#       (analyzer-ko·planner-ko 등)이 검사망 밖이었다. 93 테스트 전부 통과하던 거짓.

# T12.b bare 유령 토큰 (prefix 없음) → xref_resolve FAIL (AC-4)
sb=$(mktemp -d) || exit 1; make_sandbox "$sb"; add_docs "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); pre_rc=$?
printf -- '---\nname: tdd-ko\n---\n판정은 analyzer-ko 가 수행한다.\n' > "$sb/skills/tdd-ko/SKILL.md"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $pre_rc -eq 0 ] && echo "$pre" | grep -q '✅ xref_resolve: OK' \
   && [ $rc -eq 1 ] && echo "$err" | grep -q 'xref_resolve: FAIL' && echo "$err" | grep -q 'analyzer-ko'; then
  PASS=$((PASS+1)); echo "PASS T12.b bare 유령 토큰 → xref_resolve FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.b (pre_rc=$pre_rc rc=$rc, out=$(echo "$err" | grep xref_resolve))"
fi
rm -rf "$sb"

# T12.c allowlist (플러그인명·upstream 참조) → xref_resolve OK (AC-5 false-positive 차단)
sb=$(mktemp -d) || exit 1; make_sandbox "$sb"; add_docs "$sb"
printf -- '---\nname: tdd-ko\n---\nspecops-ko 는 specops-ko 의 writing-plans-ko · subagent-driven-development-ko 를 참조한다.\n' > "$sb/skills/tdd-ko/SKILL.md"
out=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '✅ xref_resolve: OK'; then
  PASS=$((PASS+1)); echo "PASS T12.c allowlist 토큰 → xref_resolve OK (오탐 0)"
else
  FAIL=$((FAIL+1)); echo "FAIL T12.c (rc=$rc, out=$(echo "$out" | grep xref_resolve))"
fi
rm -rf "$sb"

# T13 실제 repo — 신규 체크 4종 전부 ✅ (drift 0 상태 유지 보증)
out=$(bash "$SCRIPT" 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q '✅ version_sync: OK' \
   && echo "$out" | grep -q '✅ readme_counts: OK' \
   && echo "$out" | grep -q '✅ changelog_body: OK' \
   && echo "$out" | grep -q '✅ xref_resolve: OK'; then
  PASS=$((PASS+1)); echo "PASS T13 실제 repo drift 4종 ✅"
else
  FAIL=$((FAIL+1)); echo "FAIL T13 (rc=$rc)"; echo "$out" | grep -E 'version_sync|readme_counts|changelog_body|xref_resolve' | sed 's/^/    /'
fi

# T-ct contract_consistency — 보류 신호(BATCH-…-HELD)도 방출↔감시 대조 대상이다 (20261009)
#   종전 정규식은 `-DONE` 만 봐서, 받는 쪽 없는 보류 신호를 skill 이 내도 검사가 초록이었다.
sb=$(mktemp -d); make_sandbox "$sb"
printf '\n보류 시 `BATCH-FR-HELD: <FID>` 를 출력하고 halt 한다.\n' >> "$sb/skills/context-resets-ko/SKILL.md"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'contract_consistency: FAIL' && echo "$err" | grep -q 'BATCH-FR-HELD: skill 방출하나 오케스트레이터 감시 없음'; then
  PASS=$((PASS+1)); echo "PASS T-ct.a 받는 쪽 없는 보류 신호 → contract_consistency FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T-ct.a (rc=$rc, out=$(echo "$err" | grep contract_consistency))"
fi
_ctc=$(ls "$sb"/commands/*.md | head -1)
printf '\n`BATCH-FR-HELD: <BATCH_ID>` 를 받으면 HELD 로 적는다.\n' >> "$_ctc"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$err" | grep -q 'BATCH-FR-HELD: suffix 불일치'; then
  PASS=$((PASS+1)); echo "PASS T-ct.b 보류 신호의 인자 이름 불일치 → FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T-ct.b (rc=$rc, out=$(echo "$err" | grep contract_consistency))"
fi
printf '\n`BATCH-FR-HELD: <FID>` 를 받으면 HELD 로 적는다.\n' > "$_ctc.tail"
sed -i.bak '$d' "$_ctc"; cat "$_ctc.tail" >> "$_ctc"; rm -f "$_ctc.tail" "$_ctc.bak"
out=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1)
if echo "$out" | grep -q '✅ contract_consistency: OK'; then
  PASS=$((PASS+1)); echo "PASS T-ct.c 방출·감시가 맞물리면 OK"
else
  FAIL=$((FAIL+1)); echo "FAIL T-ct.c (out=$(echo "$out" | grep contract_consistency))"
fi
rm -rf "$sb"

# ── ISO 자가점검 (AC-5): 이 스위트가 실 트리를 변이하지 않음을 스스로 단언한다 ──
#   trap 은 **중단** 안전을, 이 어서션은 **정상 실행 중** 무변이를 담당한다.
if [ "$_iso_before" = "$(iso::fingerprint $_iso_paths)" ]; then
  PASS=$((PASS+1)); echo "PASS ISO 실 트리 전후 지문 불변"
else
  FAIL=$((FAIL+1)); echo "FAIL ISO 실 트리가 변이됐다 (이 스위트 또는 동시 실행 중인 다른 프로세스)"
fi

echo "passed=$PASS failed=$FAIL"
exit $FAIL
