#!/usr/bin/env bash
# 진행 패널 mod 배선·동작 (FID 20261030-progress-pane-mod)
#   --part=self   : 이 스위트의 SKIP 경로 (claude CLI 없으면 PP-7 을 SKIP 하고 PASS 로 끝나는지)
#   --part=mod    : STAGE_NAMES 의 skill 실재(+변이) · mod 소스 단독 엔진 검사(임시 조립본)
#   --part=wiring : hooks.json modules·plugin.json types 배선 · classic 6종·명령 경로 보존 · 변이 4건 · .claude-plugin/types/ 무시 · 엔진 검사(실 배선 사본)
#   --part=docs   : README 안내 · CHANGELOG [Unreleased] ### Added
#   인자 없음(all) : self + mod(엔진 제외) + wiring + docs — run-all 이 이것을 돈다.
#   엔진 검사(PP-7)는 claude CLI 가 있고 `plugin test` 를 알 때만 임시 사본에서 돈다(실 트리에 쓰지 않는다). 없으면 SKIP.
#   끄려면 PROGRESS_PANE_CLAUDE_BIN=/nonexistent. 실패는 FAIL — mod 표면 변경을 알아채기 위함.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SELF="$PLUGIN/scripts/tests/test-progress-pane.sh"
PART=all
for a in "$@"; do case "$a" in --part=*) PART=${a#--part=} ;; esac; done
CLAUDE_BIN=${PROGRESS_PANE_CLAUDE_BIN:-claude}
CLASSIC="Notification,PostToolUse,PreToolUse,SessionStart,Stop,SubagentStop"
EVENTS="session.start command.run tool.call session.append ui.render"
ok() { echo "PASS $1"; PASS=$((PASS+1)); }
ng() { echo "FAIL $1"; FAIL=$((FAIL+1)); }
want() { [ "$PART" = all ] || [ "$PART" = "$1" ]; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# 배선 판정 — 인자: 플러그인 루트. 0 = modules 첫 항목 파일과 plugin.json types 파일이 루트 기준으로 있다
wiring_ok() {
  local root=$1 mod types
  mod=$(jq -r '.modules[0] // empty' "$root/hooks/hooks.json" 2>/dev/null)
  [ -n "$mod" ] && [ -f "$root/hooks/${mod#./}" ] || return 1
  types=$(jq -r '.types // empty' "$root/.claude-plugin/plugin.json" 2>/dev/null)
  [ -n "$types" ] && [ -f "$root/${types#./}" ] || return 1   # 루트 기준만 — 엔진 사본(.claude-plugin/types/)은 인정하지 않는다
}

# STAGE_NAMES 키 목록 — 인자: tsx 파일
stage_keys() {
  sed -n '/^const STAGE_NAMES/,/^}/p' "$1" | grep -oE "^  '?[a-z-]+'?:" | tr -d "': "
}

# 엔진 검사 — 인자: 조립된 플러그인 폴더, 라벨. CLI 없으면 SKIP
engine_check() {
  local pp=$1 label=$2 out n_pass n_fail expected ev
  if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1 || ! "$CLAUDE_BIN" plugin test --help >/dev/null 2>&1; then
    echo "SKIP PP-7 ($label) claude CLI 없음·plugin test 미지원 — validate·test 생략"
    return 0
  fi
  if out=$("$CLAUDE_BIN" plugin validate "$pp" 2>&1); then
    local miss=""
    echo "$out" | grep -q 'progress-pane.tsx' || miss="$miss progress-pane.tsx"
    for ev in $EVENTS; do echo "$out" | grep -q "$ev" || miss="$miss $ev"; done
    [ -z "$miss" ] && ok "PP-7a ($label) validate · 모듈·이벤트 5종" || ng "PP-7a ($label) validate 출력 누락:$miss"
  else
    echo "$out" | tail -10; ng "PP-7a ($label) validate 실패"
  fi
  out=$("$CLAUDE_BIN" plugin test "$pp" 2>&1); local rc=$?
  n_pass=$(echo "$out" | sed -nE 's/^ *([0-9]+) pass$/\1/p' | tail -1)
  n_fail=$(echo "$out" | sed -nE 's/^ *([0-9]+) fail$/\1/p' | tail -1)
  expected=$(grep -c '^test(' "$pp/hooks/progress-pane.test.tsx")
  if [ "$rc" -eq 0 ] && [ "${n_fail:-x}" = 0 ] && [ "${n_pass:-0}" -eq "$expected" ]; then
    ok "PP-7b ($label) test ${n_pass}/${expected} pass"
  else
    echo "$out" | tail -15; ng "PP-7b ($label) test rc=$rc pass=${n_pass:-?}/${expected} fail=${n_fail:-?}"
  fi
}

# ── self: SKIP 경로 자기 검사 ─────────────────────────────────────────
if want self && [ -z "${PP_INNER:-}" ]; then
  out=$(PP_INNER=1 PROGRESS_PANE_CLAUDE_BIN=/nonexistent/claude bash "$SELF" --part=engine 2>&1); rc=$?
  [ "$rc" -eq 0 ] && echo "$out" | grep -q '^SKIP PP-7' && ok "PP-9 CLI 없으면 SKIP·PASS" || { echo "$out" | tail -5; ng "PP-9 CLI 없으면 SKIP·PASS (rc=$rc)"; }
fi

# ── engine: mod 소스 단독 조립본 엔진 검사 (self 가 CLI 없이 부른다) ──────
if [ "$PART" = engine ] || [ "$PART" = mod ]; then
  pp="$WORK/mod"; mkdir -p "$pp/.claude-plugin" "$pp/hooks" "$pp/types"
  jq '. + {types: "./types/index.d.ts"}' "$PLUGIN/.claude-plugin/plugin.json" > "$pp/.claude-plugin/plugin.json"
  echo '{ "modules": ["./progress-pane.tsx"] }' > "$pp/hooks/hooks.json"
  if [ "$PART" = engine ] && ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    engine_check "$pp" mod
  elif cp "$PLUGIN/hooks/progress-pane.tsx" "$PLUGIN/hooks/progress-pane.test.tsx" "$pp/hooks/" 2>/dev/null && cp "$PLUGIN/types/index.d.ts" "$pp/types/" 2>/dev/null; then
    engine_check "$pp" mod
  else
    ng "PP-7 (mod) 소스 파일 없음 — hooks/progress-pane*.tsx · types/index.d.ts"
  fi
fi

# ── mod: STAGE_NAMES ↔ skills ────────────────────────────────────────
if want mod; then
  src="$PLUGIN/hooks/progress-pane.tsx"
  if [ -f "$src" ]; then
    keys=$(stage_keys "$src"); n=$(printf '%s\n' $keys | grep -c .)
    miss=""; for k in $keys; do [ -d "$PLUGIN/skills/$k-ko" ] || miss="$miss $k"; done
    [ "$n" -ge 15 ] && [ -z "$miss" ] && ok "PP-8 STAGE_NAMES ${n}건 skill 실재" || ng "PP-8 STAGE_NAMES ${n}건 부재:$miss"
    sed 's/^const STAGE_NAMES/const STAGE_NAMEZ/' "$src" > "$WORK/mut.tsx"
    n2=$(printf '%s\n' $(stage_keys "$WORK/mut.tsx") | grep -c .)
    [ "$n2" -lt 15 ] && ok "PP-8m 이름 변이 → 파싱 ${n2}건으로 검출" || ng "PP-8m 이름 변이 미검출"
  else
    ng "PP-8 hooks/progress-pane.tsx 없음"
  fi
fi

# ── wiring ───────────────────────────────────────────────────────────
if want wiring; then
  HJ="$PLUGIN/hooks/hooks.json"; PJ="$PLUGIN/.claude-plugin/plugin.json"
  wiring_ok "$PLUGIN" && ok "PP-1 modules·types 파일 존재" || ng "PP-1 modules·types 파일 존재"
  ev=$(jq -r '.hooks | keys | join(",")' "$HJ" 2>/dev/null)
  [ "$ev" = "$CLASSIC" ] && ok "PP-2 classic 6종 보존" || ng "PP-2 classic 6종 보존 ($ev)"
  miss=""
  for f in $(jq -r '.hooks[][].hooks[].command' "$HJ" | grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+' | sed 's#^${CLAUDE_PLUGIN_ROOT}/##' | sort -u); do
    [ -f "$PLUGIN/$f" ] || miss="$miss $f"
  done
  [ -z "$miss" ] && ok "PP-2c classic 명령 경로 실재" || ng "PP-2c classic 명령 경로 부재:$miss"
  # 변이 4건 — 사본에서 하나씩 깨고 wiring_ok 가 떨어지는지
  m="$WORK/mut"; mkdir -p "$m/hooks" "$m/.claude-plugin" "$m/types"
  cp "$PLUGIN/hooks/progress-pane.tsx" "$m/hooks/" 2>/dev/null; cp "$PLUGIN/types/index.d.ts" "$m/types/" 2>/dev/null
  mutate() {   # 인자: 라벨, hooks.json jq, plugin.json jq
    jq "$2" "$HJ" > "$m/hooks/hooks.json"; jq "$3" "$PJ" > "$m/.claude-plugin/plugin.json"
    wiring_ok "$m" && ng "PP-3 $1 미검출" || ok "PP-3 $1 검출"
  }
  mutate "modules 오타" '.modules = ["./no-such.tsx"]' '.'
  mutate "modules 빈 배열" '.modules = []' '.'
  mutate "types 파일 없음" '.' '.types = "./types/none.d.ts"'
  mutate "types 키 삭제" '.' 'del(.types)'
  (cd "$PLUGIN" && git check-ignore -q .claude-plugin/types/x) && ok "PP-4 .claude-plugin/types/ 무시" || ng "PP-4 .claude-plugin/types/ 무시"
  pp="$WORK/wired"; mkdir -p "$pp/.claude-plugin"
  cp "$PJ" "$pp/.claude-plugin/"; cp -R "$PLUGIN/hooks" "$pp/"; cp -R "$PLUGIN/types" "$pp/" 2>/dev/null
  engine_check "$pp" wiring
fi

# ── docs ─────────────────────────────────────────────────────────────
if want docs; then
  R="$PLUGIN/README.md"; miss=""
  for s in '/devfsd-progress' '2.1.309' 'CLAUDE_CODE_PLUGIN_DIRS' 'devFSD 진행'; do grep -qF "$s" "$R" || miss="$miss [$s]"; done
  [ -z "$miss" ] && ok "PP-5 README 안내" || ng "PP-5 README 안내 누락:$miss"
  awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f && /^### /{s=$0} f && s=="### Added"' "$PLUGIN/CHANGELOG.md" | grep -q '진행 패널' \
    && ok "PP-6 CHANGELOG Unreleased Added" || ng "PP-6 CHANGELOG Unreleased Added"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
