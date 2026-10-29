#!/usr/bin/env bash
# validate-structure 스위트 공용 sandbox 헬퍼 — test-validate-structure.sh · test-validate-structure-chain.sh 가 source 한다
# (20261008: 한 스위트가 부하 시 300s 상한을 넘겨 둘로 쪼개며 헬퍼를 공유)
# 호출 측이 SCRIPT(=scripts/_internal/validate-structure.sh 경로)를 먼저 정의해야 한다.

# 샌드박스 공통: P1 flat baseline 미니 플러그인 복제
# (commands=1, skills/<name>/SKILL.md=16, templates=6 + 메타 skill/hook 필수)
SKILL_NAMES=(
  using-specops-ko
  context-resets-ko file-based-communication-ko generator-evaluator-ko
  sprint-contracts-ko structured-artifacts-ko
  specifying-ko clarifying-ko planning-ko decomposing-ko implementing-ko
  tdd-ko verifying-evidence-ko requesting-code-review-ko receiving-code-review-ko
  systematic-debugging-ko
)
make_sandbox() {
  local sb=$1
  mkdir -p "$sb"/{commands,skills,templates,docs,hooks,scripts/_internal,agents,.claude-plugin}
  printf -- '---\nname: start\n---\n' > "$sb/commands/start.md"
  for name in "${SKILL_NAMES[@]}"; do
    mkdir -p "$sb/skills/$name"
    printf -- '---\nname: %s\n---\n' "$name" > "$sb/skills/$name/SKILL.md"
  done
  for i in 1 2 3 4 5 6; do printf -- '---\nname: t%s\n---\n' "$i" > "$sb/templates/t$i.md"; done
  # chain fixture (FID 20260702-chain-single-source): 기존 skill 2개 재사용 — 신규 skill 생성 금지
  # (신규 skill 은 xref_resolve 미존재 FAIL + baseline 카운트 + add_docs README 하드코딩 3중 회귀)
  # s1=specifying-ko → s2=clarifying-ko (T12.a 가 변조하는 tdd-ko 회피)
  printf -- '\n## 다음 skill\n\nSkill: devfsd:clarifying-ko\n' >> "$sb/skills/specifying-ko/SKILL.md"
  cat > "$sb/hooks/chain.yaml" <<'EOF'
edges:
  - {from: specifying-ko, to: clarifying-ko}
EOF
  # 메타 skill 주입 경로 (validator 의 meta_injection 체크 대상)
  printf '#!/usr/bin/env bash\necho "{}"\n' > "$sb/hooks/session-start.sh"
  chmod +x "$sb/hooks/session-start.sh"
  echo '{"version":"0.1.0"}' > "$sb/.claude-plugin/plugin.json"
  echo '{"plugins":[{"version":"0.1.0"}]}' > "$sb/.claude-plugin/marketplace.json"
  cp "$SCRIPT" "$sb/scripts/_internal/validate-structure.sh"
  chmod +x "$sb/scripts/_internal/validate-structure.sh"
  # plugin_root_paths 판정 SoT — validate-structure 가 형제 스크립트로 부른다(20261008)
  cp "$(dirname "$SCRIPT")/check-plugin-paths.sh" "$sb/scripts/_internal/check-plugin-paths.sh"
  # U4: sandbox 자체 .structure-baseline (agents 카테고리 생략 — sandbox 가 다루지 않음)
  cat > "$sb/scripts/_internal/.structure-baseline" <<'EOF'
{"category":"commands","glob":"commands/*.md","count":1}
{"category":"skills","glob":"skills/*/SKILL.md","count":16}
{"category":"templates","glob":"templates/*.md","count":6}
EOF
}

# sandbox 에 plugin 버전(0.1.0)과 정합하는 README/CHANGELOG 추가
add_docs() {
  local sb=$1
  cat > "$sb/README.md" <<'EOF'
# test-plugin (v0.1.0)

├── skills/    ← flat: skills/<name>/SKILL.md × 16

*초기화: 2026-01-01 · **최신: v0.1.0 (2026-01-01)** · test*
EOF
  cat > "$sb/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.1.0] — 2026-01-01

### Added
- 최초 릴리즈
EOF
}
