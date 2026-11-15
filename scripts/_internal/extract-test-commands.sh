#!/usr/bin/env bash
# Wave 2 U2 (FID 20260514) — tasks.md 의 검증 명령 추출 (혼합 SSOT).
# Usage: extract-test-commands.sh <tasks.md>
#
# 우선순위:
#   1. YAML `test_command` 필드 (Wave 2 신규)
#   2. YAML 미기재 시: stderr WARN 1회 + Step 4 라인 grep fallback (구 FID 호환)
#   3. 둘 다 부재 시: exit 1
set -u

tasks="${1:?usage: $0 <tasks.md>}"
if [ ! -f "$tasks" ]; then
  echo "tasks.md not found: $tasks" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../dag/parse-dag.sh"

yaml=$(dag::extract_yaml "$tasks" 2>/dev/null)
yaml_cmds=""
if [ -n "$yaml" ]; then
  # YAML 의 모든 task id 추출
  ids=$(dag::list_leaves "$yaml" 2>/dev/null; echo "$yaml" | awk '/^[[:space:]]*-[[:space:]]*id:/ {gsub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, ""); print}')
  ids=$(echo "$ids" | sort -u | grep -v '^$' || true)
  for tid in $ids; do
    cmd=$(dag::get_task_test_command "$yaml" "$tid" 2>/dev/null)
    [ -n "$cmd" ] && yaml_cmds="${yaml_cmds}${cmd}\n"
  done
  yaml_cmds=$(printf "%b" "$yaml_cmds" | grep -v '^$' | sort -u || true)
fi

if [ -n "$yaml_cmds" ]; then
  echo "$yaml_cmds"
  exit 0
fi

# YAML 부재 또는 모든 task 가 test_command 미기재 — Step 4 라인 fallback
fid_hint=$(basename "$(dirname "$tasks")")
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.path[:] = [p for p in sys.path if p not in ("", ".")]; import yaml' 2>/dev/null; then
  # 사유를 사실대로 말한다(20261115) — 종전엔 pyyaml 이 없어도 "YAML missing test_command" 라고 해서 태스크 문서를 고치게 만들었다.
  echo "WARN: $fid_hint python3·pyyaml 이 없어 tasks.md 의 YAML 을 읽지 못했다(pip install pyyaml) — falling back to Step 4 line grep" >&2
else
  echo "WARN: $fid_hint tasks.md YAML missing test_command — falling back to Step 4 line grep" >&2
fi

# (scripts|tests|test)/ — downstream 표준 테스트 배치 인정 (20260716 trivial dogfood 발견 #3:
#   scripts/ 하드코딩은 플러그인 자기 repo 레이아웃 편향 — 외부 프로젝트 tests/ 가 추출 0건 → NO COMMANDS)
step4_cmds=$(grep -oE '`bash (scripts|tests?)/[^`]+`' "$tasks" \
  | sed -E 's/^`(.+)`$/\1/' \
  | grep -v '<' \
  | sort -u)

if [ -z "$step4_cmds" ]; then
  echo "extract-test-commands: 명령 0건 ($tasks)" >&2
  exit 1
fi
echo "$step4_cmds"
