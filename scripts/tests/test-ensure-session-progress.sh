#!/usr/bin/env bash
# specops-ko · hooks/ensure-session-progress.sh 회귀 테스트
# 검증 분기: 멱등성·is-hook-enabled disabled·template 부재·project 치환·mkdir -p
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
HOOK="$PLUGIN/hooks/ensure-session-progress.sh"


# setup_temp_plugin: $tmp_plugin 디렉토리에 ensure 실행에 필요한 최소 PLUGIN_ROOT 구성
# 인자 1: with-template (true|false) — templates/session-progress.md 포함 여부
setup_temp_plugin() {
  local tmp_plugin="$1"
  local with_template="$2"
  mkdir -p "$tmp_plugin/hooks" "$tmp_plugin/scripts/_internal"
  cp "$PLUGIN/hooks/ensure-session-progress.sh" "$tmp_plugin/hooks/"
  cp "$PLUGIN/scripts/_internal/is-hook-enabled.sh" "$tmp_plugin/scripts/_internal/"
  if [ "$with_template" = "true" ]; then
    mkdir -p "$tmp_plugin/templates"
    cp "$PLUGIN/templates/session-progress.md" "$tmp_plugin/templates/"
  fi
}

# ── T1.a 멱등성 ──────────────────────────────────────────────────────────
tmp=$(mktemp -d); mkdir -p "$tmp/.specops"
(cd "$tmp" && bash "$HOOK" >/dev/null 2>&1)   # 첫 호출 — 생성
T1a_out=$(cd "$tmp" && bash "$HOOK" 2>&1)
T1a_rc=$?
[ "$T1a_rc" -eq 0 ] && [ -z "$T1a_out" ] \
  && ok "T1.a 멱등 — target 존재 시 noop (stdout 빈, rc=0)" \
  || fail "T1.a 멱등 — target 존재 시 noop (rc=$T1a_rc, out='$T1a_out')"
rm -rf "$tmp"

# ── T1.b is-hook-enabled disabled (SPECOPS_CONFIG mock) ─────────────────
# prereq: python3 + pyyaml. is-hook-enabled.sh 가 graceful degradation
# (pyyaml 부재 시 default enabled, exit 0) 하므로 미설치 환경에서는
# disable 시뮬레이션 자체가 불가. project 패턴 일관 — validate-structure.sh:98
# 도 동일 graceful SKIP 사용.
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" 2>/dev/null; then
  skip "T1.b (python3+pyyaml 부재 — is-hook-enabled disable 시뮬레이션 불가)"
else
  tmp=$(mktemp -d)
  cat > "$tmp/config.yaml" <<'YAML'
profile: test-disabled
profiles:
  test-disabled:
    enforce_all_disabled: true
YAML
  T1b_out=$(cd "$tmp" && SPECOPS_CONFIG="$tmp/config.yaml" bash "$HOOK" 2>&1)
  T1b_rc=$?
  [ "$T1b_rc" -eq 0 ] && [ ! -f "$tmp/.specops/session-progress.md" ] \
    && ok "T1.b is-hook-enabled disabled → exit 0 + 파일 생성 안 함" \
    || fail "T1.b is-hook-enabled disabled (rc=$T1b_rc, file 존재=$([ -f \"$tmp/.specops/session-progress.md\" ] && echo yes || echo no))"
  rm -rf "$tmp"
fi

# ── T1.c template 부재 → exit 1 + stderr 에러 ─────────────────────────
tmp=$(mktemp -d)
tmp_plugin="$tmp/plugin"
setup_temp_plugin "$tmp_plugin" "false"   # templates/ 미생성
tmp_work="$tmp/work"
mkdir -p "$tmp_work/.specops"   # 도입 저장소 — 부재면 템플릿을 보기 전에 noop 이다(T1.e)
T1c_out=$(cd "$tmp_work" && bash "$tmp_plugin/hooks/ensure-session-progress.sh" 2>&1)
T1c_rc=$?
[ "$T1c_rc" -eq 1 ] && echo "$T1c_out" | grep -q "template not found" \
  && [ ! -f "$tmp_work/.specops/session-progress.md" ] \
  && ok "T1.c template 부재 → exit 1 + stderr 'template not found'" \
  || fail "T1.c template 부재 (rc=$T1c_rc, out='$T1c_out')"
rm -rf "$tmp"

# ── T1.d project 인자 치환 ─────────────────────────────────────────────
# 주: tasks.md 원본의 `|| echo 0` 패턴은 BSD grep -c 와 비호환 (매칭 0 시
# stdout "0" + exit 1 → 두 번 echo). ${var:-0} 패턴으로 정정.
tmp=$(mktemp -d); mkdir -p "$tmp/.specops"
T1d_out=$(cd "$tmp" && bash "$HOOK" "my-proj" 2>&1)
T1d_rc=$?
match_count=$(grep -c "my-proj" "$tmp/.specops/session-progress.md" 2>/dev/null)
match_count=${match_count:-0}
placeholder_count=$(grep -c "<project-name>" "$tmp/.specops/session-progress.md" 2>/dev/null)
placeholder_count=${placeholder_count:-0}
[ "$T1d_rc" -eq 0 ] && [ "$match_count" -ge 1 ] && [ "$placeholder_count" -eq 0 ] \
  && ok "T1.d project 인자 치환 (my-proj=${match_count}건, placeholder=${placeholder_count}건)" \
  || fail "T1.d project 인자 치환 (rc=$T1d_rc, my-proj=$match_count, placeholder=$placeholder_count)"
rm -rf "$tmp"

# ── T1.e 관할 한정 — .specops 없는 저장소에는 아무것도 만들지 않는다 ─────
# 왜: Stop 훅은 모든 저장소에서 발화한다. 여기서 .specops/ 를 만들면 그 저장소가 관할로 편입돼
#   이후 커밋이 R-1 차단 대상이 된다(실측 20261009: 플러그인을 쓰지 않는 저장소 4곳에 흔적).
tmp=$(mktemp -d)
[ ! -d "$tmp/.specops" ] || { echo "FATAL: 사전 조건 위배 — .specops 이미 존재"; exit 99; }
T1e_out=$(cd "$tmp" && bash "$HOOK" 2>&1)
T1e_rc=$?
[ "$T1e_rc" -eq 0 ] && [ ! -e "$tmp/.specops" ] && [ -z "$T1e_out" ] \
  && ok "T1.e .specops 부재 → 아무것도 만들지 않음 (rc=0, 무출력)" \
  || fail "T1.e 비도입 저장소 침범 (rc=$T1e_rc, .specops 존재=$([ -e "$tmp/.specops" ] && echo yes || echo no), out='$T1e_out')"
rm -rf "$tmp"

# ── T1.e2 project 인자를 줘도 .specops 부재면 저장소에 파일을 하나도 만들지 않는다 ──
tmp=$(mktemp -d)
(cd "$tmp" && bash "$HOOK" "proj" >/dev/null 2>&1)
[ -z "$(ls -A "$tmp")" ] \
  && ok "T1.e2 .specops 부재 + project 인자 → 저장소에 파일 0개" \
  || fail "T1.e2 저장소에 흔적: $(ls -A "$tmp" | tr '\n' ' ')"
rm -rf "$tmp"

# ── T1.e3 .specops 가 있으면 종전대로 만든다 (가드가 도입 저장소를 막지 않는다) ──
tmp=$(mktemp -d); mkdir -p "$tmp/.specops"
(cd "$tmp" && bash "$HOOK" >/dev/null 2>&1)
T1e3_rc=$?
[ "$T1e3_rc" -eq 0 ] && [ -f "$tmp/.specops/session-progress.md" ] \
  && ok "T1.e3 .specops 존재 → session-progress.md 생성" \
  || fail "T1.e3 도입 저장소에서 미생성 (rc=$T1e3_rc)"
rm -rf "$tmp"

# ── T1.e4 하위 디렉토리에서 발화해도 그 자리에 .specops 를 만들지 않는다 (실측: .specops/.specops 흔적) ──
tmp=$(mktemp -d); mkdir -p "$tmp/.specops" "$tmp/src"
(cd "$tmp/.specops" && bash "$HOOK" >/dev/null 2>&1)
(cd "$tmp/src" && bash "$HOOK" >/dev/null 2>&1)
[ ! -e "$tmp/.specops/.specops" ] && [ ! -e "$tmp/src/.specops" ] \
  && ok "T1.e4 하위 디렉토리 cwd → 중첩 .specops 미생성" \
  || fail "T1.e4 중첩 생성: $(cd "$tmp" && find . -name .specops | tr '\n' ' ')"
rm -rf "$tmp"

# ── T1.e5 하위 디렉토리 cwd + 프로젝트 루트에 .specops → 루트에 만든다 (posttool·stop 과 같은 앵커) ──
tmp=$(mktemp -d); mkdir -p "$tmp/.specops" "$tmp/src/sub"
(cd "$tmp/src/sub" && CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" >/dev/null 2>&1)
[ -f "$tmp/.specops/session-progress.md" ] && [ ! -e "$tmp/src/sub/.specops" ] \
  && ok "T1.e5 하위 cwd → 프로젝트 루트의 .specops 에 생성" \
  || fail "T1.e5 (루트 파일=$([ -f "$tmp/.specops/session-progress.md" ] && echo yes || echo no), 중첩=$([ -e "$tmp/src/sub/.specops" ] && echo yes || echo no))"
rm -rf "$tmp"
# ── T1.e6 프로젝트 루트에도 .specops 가 없으면 앵커해도 만들지 않는다 ──
tmp=$(mktemp -d); mkdir -p "$tmp/src"
(cd "$tmp/src" && CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" >/dev/null 2>&1)
[ ! -e "$tmp/.specops" ] && [ ! -e "$tmp/src/.specops" ] \
  && ok "T1.e6 루트에도 부재 → 미생성" || fail "T1.e6 생성됨: $(cd "$tmp" && find . -name .specops | tr '\n' ' ')"
rm -rf "$tmp"

# ── T1.e7 cwd 에 .specops 가 있으면 cwd 가 우선이다 — session-progress-append 가 cwd 기준으로 이 스크립트를 부른다 ──
tmp=$(mktemp -d); mkdir -p "$tmp/proj/.specops" "$tmp/other/.specops"
(cd "$tmp/proj" && CLAUDE_PROJECT_DIR="$tmp/other" bash "$HOOK" >/dev/null 2>&1)
[ -f "$tmp/proj/.specops/session-progress.md" ] && [ ! -f "$tmp/other/.specops/session-progress.md" ] \
  && ok "T1.e7 cwd 의 .specops 우선 (CLAUDE_PROJECT_DIR 로 옮겨 가지 않는다)" \
  || fail "T1.e7 (cwd=$([ -f "$tmp/proj/.specops/session-progress.md" ] && echo yes || echo no), other=$([ -f "$tmp/other/.specops/session-progress.md" ] && echo yes || echo no))"
rm -rf "$tmp"

# ── T1.f .specops 디렉토리 symlink → 외부 write-through 차단 (#144 대칭) ──
tmp=$(mktemp -d)
outside=$(mktemp -d)
ln -s "$outside" "$tmp/.specops"
(cd "$tmp" && bash "$HOOK" >/dev/null 2>&1)
T1f_rc=$?
[ "$T1f_rc" -eq 0 ] && [ ! -f "$outside/session-progress.md" ] \
  && ok "T1.f .specops symlink → write 거부 (rc=0, 외부 미생성)" \
  || fail "T1.f .specops symlink write 거부 (rc=$T1f_rc, 외부생성=$([ -f "$outside/session-progress.md" ] && echo yes || echo no))"
rm -rf "$tmp" "$outside"

# ── T1.g session-progress.md dangling symlink → sed 관통 차단 (#144 대칭) ──
tmp=$(mktemp -d)
outside=$(mktemp -d)
mkdir -p "$tmp/.specops"
ln -s "$outside/leak.md" "$tmp/.specops/session-progress.md"   # dangling — L14 -f 통과
(cd "$tmp" && bash "$HOOK" >/dev/null 2>&1)
T1g_rc=$?
[ "$T1g_rc" -eq 0 ] && [ ! -f "$outside/leak.md" ] \
  && ok "T1.g target 파일 symlink → write 거부" \
  || fail "T1.g target 파일 symlink write 거부 (rc=$T1g_rc, 관통=$([ -f "$outside/leak.md" ] && echo yes || echo no))"
rm -rf "$tmp" "$outside"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
