#!/usr/bin/env bash
# 진행 패널 mod 배선·동작 (FID 20261030-progress-pane-mod)
#   --part=self   : 이 스위트의 SKIP 경로 (claude CLI 없으면 PP-7 을 SKIP 하고 PASS 로 끝나는지)
#   --part=mod    : STAGE_NAMES 의 skill 실재(+변이) · mod 소스 단독 엔진 검사(임시 조립본)
#   --part=wiring : hooks.json modules·plugin.json types 배선 · classic 6종·명령 경로 보존 · 변이 4건 · .claude-plugin/types/ 무시 · 엔진 검사(실 배선 사본)
#   --part=docs   : README 안내 · CHANGELOG ### Added (버전 절 무관 — 릴리즈가 [Unreleased] 를 [X.Y.Z] 로 바꿔도 통과)
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
  local pp=$1 label=$2 mods out n_pass n_fail expected ev
  if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1 || ! "$CLAUDE_BIN" plugin test --help >/dev/null 2>&1; then
    echo "SKIP PP-7 ($label) claude CLI 없음·plugin test 미지원 — validate·test 생략"
    return 0
  fi
  if out=$("$CLAUDE_BIN" plugin validate "$pp" 2>&1); then
    local miss=""
    mods=register.tsx   # progress-pane.tsx 는 이제 register.tsx 가 부르는 하위 모듈 — modules[0] 은 register.tsx
    echo "$out" | grep -q "$mods" || miss="$miss $mods"
    for ev in $EVENTS; do echo "$out" | grep -q "$ev" || miss="$miss $ev"; done
    if [ "$label" = wiring ]; then   # 실 배선: 진행 패널·관제판 둘 다의 등록 이벤트가 validate 출력에 있다
      for ev in 'requestId=devfsd-progress' 'requestId=devfsd-console' 'command.run{command=devfsd-progress}' 'command.run{command=devfsd}'; do
        echo "$out" | grep -qF "$ev" || miss="$miss $ev"
      done
    fi
    [ -z "$miss" ] && ok "PP-7a ($label) validate · 모듈·이벤트 5종" || ng "PP-7a ($label) validate 출력 누락:$miss"
  else
    echo "$out" | tail -10; ng "PP-7a ($label) validate 실패"
  fi
  out=$("$CLAUDE_BIN" plugin test "$pp" 2>&1); local rc=$?
  n_pass=$(echo "$out" | sed -nE 's/^ *([0-9]+) pass$/\1/p' | tail -1)
  n_fail=$(echo "$out" | sed -nE 's/^ *([0-9]+) fail$/\1/p' | tail -1)
  expected=$(echo "$out" | sed -nE 's/^Ran ([0-9]+) tests.*/\1/p' | tail -1)   # 도우미가 test() 를 감싸 grep -c 와 어긋난다 — 엔진이 보고한 실행 수
  if [ "$rc" -eq 0 ] && [ "${n_fail:-x}" = 0 ] && [ "${n_pass:-0}" -eq "${expected:--1}" ]; then
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
  echo '{ "modules": ["./register.tsx"] }' > "$pp/hooks/hooks.json"
  if [ "$PART" = engine ] && ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    engine_check "$pp" mod
  elif cp "$PLUGIN"/hooks/{register.tsx,console.tsx,core.ts,ci-watch.ts,rail.tsx,elapsed.tsx,console.test.ts,progress-pane.tsx,progress-pane.test.tsx} "$pp/hooks/" 2>/dev/null && cp "$PLUGIN/types/index.d.ts" "$pp/types/" 2>/dev/null; then
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
  cp "$PLUGIN/hooks/register.tsx" "$m/hooks/" 2>/dev/null; cp "$PLUGIN/types/index.d.ts" "$m/types/" 2>/dev/null
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
  # ── 보존 잠금 (FID 20261105-console-baseline T4) ──
  # PP-L1: 셸 훅 등록 전체 등가 — modules 를 뺀 나머지가 이식 전 hooks.json 의 리터럴과 같다(키·matcher·command·async 값까지)
  EXPECTED_SHELL_HOOKS=$(cat <<'LITERAL'
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "async": true,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/notify.sh\"",
            "type": "command"
          }
        ],
        "matcher": "idle_prompt"
      },
      {
        "hooks": [
          {
            "async": true,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/notify.sh\"",
            "type": "command"
          }
        ],
        "matcher": "permission_prompt"
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "async": false,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/posttool-governance.sh\"",
            "type": "command"
          }
        ],
        "matcher": "Bash|Skill"
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "async": false,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pretool-governance.sh\"",
            "type": "command"
          }
        ],
        "matcher": "Bash"
      },
      {
        "hooks": [
          {
            "async": false,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/save-review-report.sh\"",
            "type": "command"
          }
        ],
        "matcher": "SubagentHandback"
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "async": false,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"",
            "type": "command"
          }
        ],
        "matcher": "startup|clear|compact"
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "async": false,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/ensure-session-progress.sh\"",
            "type": "command"
          }
        ],
        "matcher": "*"
      },
      {
        "hooks": [
          {
            "async": false,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stop-governance.sh\"",
            "type": "command"
          }
        ],
        "matcher": "*"
      },
      {
        "hooks": [
          {
            "async": false,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/freecomment-capture.sh\"",
            "type": "command"
          }
        ],
        "matcher": "*"
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "async": false,
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/save-review-report.sh\"",
            "type": "command"
          }
        ],
        "matcher": "devfsd:spec-reviewer-ko|devfsd:code-reviewer-ko|specops-ko:spec-reviewer-ko|specops-ko:code-reviewer-ko"
      }
    ]
  }
}
LITERAL
)
  [ "$(jq -S 'del(.modules)' "$HJ" 2>/dev/null)" = "$EXPECTED_SHELL_HOOKS" ] && ok "PP-L1 셸 훅 등록 전체 등가(값까지)" || ng "PP-L1 셸 훅 등록이 보존 리터럴과 다르다"
  [ "$(jq -c '.modules' "$HJ" 2>/dev/null)" = '["./register.tsx"]' ] && ok "PP-L2 modules == [./register.tsx]" || ng "PP-L2 modules 가 [./register.tsx] 가 아니다"
  # PP-L3: 출처 고지
  { [ -s "$PLUGIN/NOTICE" ] && grep -qF 'Stephen Casella' "$PLUGIN/NOTICE" && grep -qF 'MIT' "$PLUGIN/NOTICE"; } && ok "PP-L3 NOTICE 존재·Stephen Casella·MIT" || ng "PP-L3 NOTICE 없음 또는 Stephen Casella/MIT 누락"
  { [ -s "$PLUGIN/LICENSE-flightdeck" ] && grep -qF 'Stephen Casella' "$PLUGIN/LICENSE-flightdeck" && grep -qF 'MIT' "$PLUGIN/LICENSE-flightdeck"; } && ok "PP-L4 LICENSE-flightdeck 존재·Stephen Casella·MIT" || ng "PP-L4 LICENSE-flightdeck 없음/빈 파일 또는 Stephen Casella/MIT 누락"
  # PP-L5: 이식 파일 5개 첫 3줄 머리말 (register.tsx 는 devFSD 작성이라 제외)
  for f in console.tsx core.ts rail.tsx elapsed.tsx console.test.ts; do
    head -3 "$PLUGIN/hooks/$f" 2>/dev/null | grep -qF 'Ported from Claude Flightdeck' && ok "PP-L5 $f 머리말" || ng "PP-L5 $f 머리말(Ported from Claude Flightdeck) 없음"
  done
  # PP-L6: 격리 5곳 — validate 의 'without .catch' 이름 집합이 정확히 범위 밖 둘 (CLI 없으면 SKIP)
  if command -v "$CLAUDE_BIN" >/dev/null 2>&1 && "$CLAUDE_BIN" plugin test --help >/dev/null 2>&1; then
    names=$("$CLAUDE_BIN" plugin validate "$pp" 2>&1 | sed -n 's/.*gating hook without \.catch: //p' | sort | tr '\n' ' ')
    [ "$names" = "agent.offer session.compact " ] && ok "PP-L6 without .catch 이름 집합 == {agent.offer, session.compact}" || ng "PP-L6 without .catch 이름 집합이 다르다: ${names:-없음}"
  else
    echo "SKIP PP-L6 claude CLI 없음·plugin test 미지원 — validate 이름 집합 생략"
  fi
fi

# ── docs ─────────────────────────────────────────────────────────────
if want docs; then
  R="$PLUGIN/README.md"; miss=""
  for s in '/devfsd-progress' '2.1.309' 'CLAUDE_CODE_PLUGIN_DIRS' 'devFSD 진행'; do grep -qF "$s" "$R" || miss="$miss [$s]"; done
  [ -z "$miss" ] && ok "PP-5 README 안내" || ng "PP-5 README 안내 누락:$miss"
  # PP-6: 어느 버전 절이든 그 절의 ### Added 하위에 '- 진행 패널' 항목이 있다.
  added_has() { awk '/^## \[/{s="";next} /^### /{s=$0;next} s=="### Added"' "$1" | grep -q '^- 진행 패널'; }
  added_has "$PLUGIN/CHANGELOG.md" && ok "PP-6 CHANGELOG ### Added (버전 절 무관)" || ng "PP-6 CHANGELOG ### Added (버전 절 무관)"
  # PP-6m: Added 가 아닌 절에 있으면 떨어진다 — 사본의 ### Added 를 ### Changed 로
  sed 's/^### Added$/### Changed/' "$PLUGIN/CHANGELOG.md" > "$WORK/changelog-mut.md"
  added_has "$WORK/changelog-mut.md" && ng "PP-6m Added 밖 변이 미검출" || ok "PP-6m Added 밖 변이 검출"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
