#!/usr/bin/env bash
# specops-ko v0.2 묶음 3 · scripts/_internal/is-hook-enabled.sh 검증
# T1 config 없음 / T2 enabled:true / T3 enabled:false / T4 strict.enforce_all_hooks override / T5 pyyaml 없음
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(pwd)
SCRIPT="$PLUGIN/scripts/_internal/is-hook-enabled.sh"

# T1 config 파일 없음 → exit 0 (default enabled)
tmp=$(mktemp -d)
SPECOPS_CONFIG="$tmp/missing.yaml" bash "$SCRIPT" any-hook >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T1 config 부재 → exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T1 (rc=$rc, expect 0)"
fi
rm -rf "$tmp"

# T2 lite profile + hooks.foo.enabled:true → exit 0
tmp=$(mktemp -d)
cat > "$tmp/c.yaml" <<EOF
profile: lite
hooks:
  foo:
    enabled: true
profiles:
  lite:
    enforce_all_hooks: false
EOF
SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T2 enabled:true → exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T2 (rc=$rc, expect 0)"
fi
rm -rf "$tmp"

# T3 lite profile + hooks.foo.enabled:false → exit 1
tmp=$(mktemp -d)
cat > "$tmp/c.yaml" <<EOF
profile: lite
hooks:
  foo:
    enabled: false
profiles:
  lite:
    enforce_all_hooks: false
EOF
SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T3 enabled:false → exit 1"
else
  FAIL=$((FAIL+1)); echo "FAIL T3 (rc=$rc, expect 1)"
fi
rm -rf "$tmp"

# T4 strict.enforce_all_hooks=true → 개별 hooks.foo.enabled:false 무시 → exit 0
tmp=$(mktemp -d)
cat > "$tmp/c.yaml" <<EOF
profile: strict
hooks:
  foo:
    enabled: false
profiles:
  strict:
    enforce_all_hooks: true
EOF
SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then
  PASS=$((PASS+1)); echo "PASS T4 strict override → exit 0"
else
  FAIL=$((FAIL+1)); echo "FAIL T4 (rc=$rc, expect 0)"
fi
rm -rf "$tmp"

# T5 pyyaml 부재 시뮬레이션 → exit 0 + stderr 경고
# fake python3: yaml import 시 항상 exit 1, 다른 호출은 시스템 python3 위임
tmp=$(mktemp -d)
cat > "$tmp/c.yaml" <<EOF
profile: lite
hooks:
  foo:
    enabled: false
profiles:
  lite:
    enforce_all_hooks: false
EOF
mkdir "$tmp/bin"
SYS_PY=$(command -v python3)
cat > "$tmp/bin/python3" <<PYWRAP
#!/bin/sh
# 인자에 'import yaml'이 있으면 무조건 실패 (pyyaml 부재 시뮬)
case "\$*" in
  *"import yaml"*) exit 1 ;;
esac
exec "$SYS_PY" "\$@"
PYWRAP
chmod +x "$tmp/bin/python3"
err=$(SPECOPS_YAML_WARNED= SPECOPS_CONFIG="$tmp/c.yaml" PATH="$tmp/bin:$PATH" bash "$SCRIPT" foo 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 0 ] && echo "$err" | grep -q 'pyyaml'; then
  PASS=$((PASS+1)); echo "PASS T5 pyyaml 부재 → exit 0 + 경고"
else
  FAIL=$((FAIL+1)); echo "FAIL T5 (rc=$rc, err=$err)"
fi
rm -rf "$tmp"

# T6 none.enforce_all_disabled=true → hooks.foo.enabled:true 무시 → exit 1
tmp=$(mktemp -d)
cat > "$tmp/c.yaml" <<EOF
profile: none
hooks:
  foo:
    enabled: true
profiles:
  none:
    enforce_all_disabled: true
EOF
SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T6 none.enforce_all_disabled override → exit 1"
else
  FAIL=$((FAIL+1)); echo "FAIL T6 (rc=$rc, expect 1)"
fi
rm -rf "$tmp"

# T7 (보너스) 실행권한
if [ -x "$SCRIPT" ]; then
  PASS=$((PASS+1)); echo "PASS T7 exec-bit"
else
  FAIL=$((FAIL+1)); echo "FAIL T7 exec-bit"
fi

# === SPECOPS_GOVERNANCE_PROFILE ENV 프리셋 (AC-1~6) ===
chk_env() {
  SPECOPS_GOVERNANCE_PROFILE="$1" bash "$SCRIPT" "$2" >/dev/null 2>&1; local rc=$?
  if [ "$rc" -eq "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: $4 (rc=$rc, want $3)"; fi
}
# AC-1 strict: 6훅 전부 활성(rc=0)
for h in pretool-governance posttool-governance stop-governance session-start ensure-session-progress notify; do
  chk_env strict "$h" 0 "AC-1 strict $h"
done
# AC-2 standard: pretool/posttool/stop/session-start 활성, ensure/notify 비활성
for h in pretool-governance posttool-governance stop-governance session-start; do chk_env standard "$h" 0 "AC-2 standard $h 활성"; done
for h in ensure-session-progress notify; do chk_env standard "$h" 1 "AC-2 standard $h 비활성"; done
# AC-3 minimal: pretool/session-start 활성(hard-block 유지), 나머지 비활성
for h in pretool-governance session-start; do chk_env minimal "$h" 0 "AC-3 minimal $h 활성"; done
for h in posttool-governance stop-governance ensure-session-progress notify; do chk_env minimal "$h" 1 "AC-3 minimal $h 비활성"; done
# AC-5 미지원 프리셋 → default strict(rc=0) + 경고
out="$(SPECOPS_GOVERNANCE_PROFILE=bogus bash "$SCRIPT" pretool-governance 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: AC-5 bogus exit"; fi
if printf '%s' "$out" | grep -q "미지원"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL: AC-5 경고 미출력"; fi
# AC-4 우선순위·AC-6 pyyaml 독립: config.yaml 부재 환경에서 AC-1~3 통과로 입증
# AC-R-1 ENV 미설정 무변경
unset SPECOPS_GOVERNANCE_PROFILE
bash "$SCRIPT" pretool-governance >/dev/null 2>&1 && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: AC-R-1 미설정 default"; }

# T6 cwd 의 yaml.py 가짜 모듈이 킬스위치 판정을 속이지 못한다 (20261008-yaml-shadow-rest)
#   python3 stdin 실행은 sys.path[0]='' 라 cwd 의 yaml.py 가 진짜 pyyaml 을 가린다 — 가짜가 항상 {} 를 돌려주면
#   `enabled:false` 로 꺼 둔 훅이 켜진 것으로 판정된다.
tmp=$(mktemp -d)
printf 'hooks:\n  foo:\n    enabled: false\n' > "$tmp/c.yaml"
printf 'def safe_load(s):\n    return {}\n' > "$tmp/yaml.py"
( cd "$tmp" && SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T6 cwd yaml.py 가짜 주입에도 비활성 판정 유지 (rc=1)"
else
  FAIL=$((FAIL+1)); echo "FAIL T6 cwd yaml.py 에 속아 활성 판정 (rc=$rc, expect 1)"
fi
rm -rf "$tmp"

# T7 ★ 작업 폴더의 yaml.py 를 **실행하지 않는다** (20261114 재현 — pyyaml 유무 탐침 `python3 -c "import yaml"` 이 cwd 를
#   import 경로에 둬서, config 가 있는 저장소를 열기만 해도 그 저장소의 yaml.py 가 Bash 호출마다 돌았다. T6 은 파싱 단계만 봤다).
tmp=$(mktemp -d)
printf 'open("PWNED","w").write("x")\nraise ImportError("fake")\n' > "$tmp/yaml.py"
printf 'profile: strict\n' > "$tmp/c.yaml"
(cd "$tmp" && SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1)
if [ ! -e "$tmp/PWNED" ]; then
  PASS=$((PASS+1)); echo "PASS T7 cwd yaml.py 미실행"
else
  FAIL=$((FAIL+1)); echo "FAIL T7 cwd 의 yaml.py 가 실행됐다(PWNED 생성)"
fi
rm -rf "$tmp"

# T8 ★ config 구조가 예상과 달라도 훅이 꺼지지 않는다 (20261114 재현 — 최상위가 목록·문자열이거나 hooks·profiles 가
#   매핑이 아니면 파이썬이 예외로 rc 1 을 내고, 호출부는 rc 1 을 "비활성"으로 읽어 거버넌스 전체가 조용히 꺼졌다).
if python3 -c "import sys; sys.path[:] = [p for p in sys.path if p not in ('', '.')]; import yaml" 2>/dev/null; then
  _t8_bad=""
  for body in '- a
- b' 'just a string' 'hooks: [1, 2]' 'profile: strict
hooks: "off"' 'profiles: x' 'hooks:
  foo: nope' '42'; do
    tmp=$(mktemp -d); printf '%s\n' "$body" > "$tmp/c.yaml"
    SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 0 ] || _t8_bad="$_t8_bad [$(printf '%s' "$body" | tr '\n' ' ')→rc=$rc]"
    rm -rf "$tmp"
  done
  if [ -z "$_t8_bad" ]; then
    PASS=$((PASS+1)); echo "PASS T8 예상 밖 구조 7종 → 전부 exit 0(기본 활성)"
  else
    FAIL=$((FAIL+1)); echo "FAIL T8 구조 예외로 비활성 판정:$_t8_bad"
  fi
  # T8b 대조: 정상 구조의 명시적 끄기는 그대로 exit 1
  tmp=$(mktemp -d); printf 'profile: lite\nhooks:\n  foo:\n    enabled: false\n' > "$tmp/c.yaml"
  SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 1 ]; then PASS=$((PASS+1)); echo "PASS T8b 대조: 명시적 enabled:false → exit 1"
  else FAIL=$((FAIL+1)); echo "FAIL T8b (rc=$rc, expect 1)"; fi
  rm -rf "$tmp"
  # T8c 0 은 끄고, 빈 값은 끄지 않는다
  tmp=$(mktemp -d); printf 'hooks:\n  foo:\n    enabled: 0\n' > "$tmp/c.yaml"; SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1; r0=$?
  printf 'hooks:\n  foo:\n    enabled:\n' > "$tmp/c.yaml"; SPECOPS_CONFIG="$tmp/c.yaml" bash "$SCRIPT" foo >/dev/null 2>&1; rn=$?
  if [ "$r0" -eq 1 ] && [ "$rn" -eq 0 ]; then PASS=$((PASS+1)); echo "PASS T8c enabled: 0 → exit 1 · 빈 값 → exit 0"
  else FAIL=$((FAIL+1)); echo "FAIL T8c (0→$r0 expect 1 · 빈 값→$rn expect 0)"; fi
  rm -rf "$tmp"
else
  echo "SKIP T8 pyyaml 없음"
fi

echo "passed=$PASS failed=$FAIL"
exit $FAIL
