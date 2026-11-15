#!/usr/bin/env bash
# specops-ko — DAG 파서 (Sourced library)
#
# 7 함수 namespace:
#   dag::extract_yaml      <tasks.md>                        — DAG YAML fenced block stdout (2단 탐색: 헤더 → tasks: 키)
#   dag::list_leaves       <yaml-string>                     — depends_on=[] 인 task id (newline 구분)
#   dag::outputs_disjoint  <yaml-string> <id1> <id2>         — id1·id2 outputs 교집합 0이면 exit 0
#   dag::find_independent_batch <yaml-string>                — 절대 leaf 2개+ + outputs disjoint 인 batch (newline)
#   dag::get_task_test_command  <yaml-string> <task-id>      — task 의 test_command 필드 (없으면 빈 + exit 0)  [Wave 2 U2]
#   dag::get_task_outputs       <yaml-string> <task-id>      — task 의 outputs 필드 (newline 구분, 없으면 빈 + exit 0)
#   dag::find_ready        <yaml-string> [done-id...]        — done 집합 기반 ready frontier (다단계 wave 지원)
#
# 의존성: python3 + pyyaml (기존 is-hook-enabled.sh, is-rule-enabled.sh와 동일 인프라)
# 제약: extract_yaml 의 코드펜스 매칭은 행두 고정 (^```yaml / ^```) — 리스트 내 들여쓴 fence 미인식.
#       미인식 시 빈 출력 → 호출측 sequential fallback (안전 degrade). tasks.md 작성 시 fence 를 행두에 둘 것.
# 참조: 마스터 plan §6 v0.4a W1 + advisor 협의 2026-04-26 13:00 (정정 채택)
#       dynamic-workflow 이식 플랜 2026-06-08 (dag::find_ready 신설)
#
# Sourced library — caller가 set -u/-e 제어. strict mode 위임.

# 탐침은 import 전에 cwd 를 경로에서 뺀다(20261115) — `-c` 는 cwd 가 import 경로 맨 앞이라 저장소의 yaml.py 가 실행됐다.
# Python 의존 가드 — 부재 시 stderr 1회 경고 + 함수는 빈 문자열·exit 1 반환 (안전 fallback)
__dag_check_python() {
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.path[:] = [p for p in sys.path if p not in ("", ".")]; import yaml' 2>/dev/null; then
    if [ -z "${SPECOPS_DAG_WARNED:-}" ]; then
      echo "⚠️  dag::*: python3+pyyaml 미설치 — 모든 DAG 함수 빈 결과 (순차 fallback)" >&2
      export SPECOPS_DAG_WARNED=1
    fi
    return 1
  fi
  return 0
}

# dag::extract_yaml <tasks.md>
# DAG YAML fenced block 본문만 stdout. 2단 탐색:
#   1단 — `## 의존 그래프` 섹션 안의 ```yaml ... ``` 펜스 (기존 경로 · 바이트 무변화)
#   2단 — 1단이 빈손일 때만: 문서 전체의 ```yaml 펜스 중 `tasks:` 키를 가진 첫 번째
#         (후보 2개 이상이면 첫 번째 채택 + stderr WARN 1줄 · stdout 은 오염하지 않는다)
# 둘 다 빈손이면 빈 출력 + exit 0 (WARN 없음 — 호출측 sequential fallback).
# 2단 한계 2가지 (문서-코드 격차 방지 — FID 20260902-dag-yaml-header-free):
#   - `tasks:` 판별은 `^tasks:[[:space:]]*$` 엄격 매칭 — `tasks: []`·`tasks:  # 주석` 은 후보 아님.
#   - 중첩 펜스 미인식 — ````markdown 외곽 펜스 안의 ```yaml 예시도 후보로 센다 (^``` 행두 매칭).
#   - 2단은 **닫힌 펜스만** 채택하고(닫는 ``` 이 없으면 후보 아님), 1단은 EOF 까지 출력한다.
#     비대칭이나 안전 방향 — 2단이 미닫힘 펜스로 문서 꼬리를 통째로 YAML 로 오인하지 않는다.
dag::extract_yaml() {
  local md="$1"
  if [ ! -f "$md" ]; then
    echo "dag::extract_yaml: 파일 없음 — $md" >&2
    return 1
  fi
  # 1단: ## 의존 그래프 헤더 발견 후 ```yaml ~ ``` 블록 추출 (기존 awk 무변화)
  #   trailing newline 보존을 위해 'X' sentinel — AC-2 바이트 동일 계약.
  local out
  out=$(awk '
    /^## 의존 그래프/ { in_section = 1; next }
    /^## / && in_section { in_section = 0 }
    in_section && /^```yaml/ { in_yaml = 1; next }
    in_yaml && /^```/ { in_yaml = 0; exit }
    in_yaml { print }
  ' "$md"; printf 'X')
  out=${out%X}
  if [ -n "$out" ]; then printf '%s' "$out"; return 0; fi

  # 2단: 헤더 부재 — 문서 전체의 ```yaml 펜스 중 `tasks:` 키를 가진 첫 번째
  #   (산문 헤더가 파서의 진입 조건이던 결함 — 20260902-dag-yaml-header-free)
  local cand
  cand=$(awk '
    /^```yaml/ { n++; inb = 1; buf = ""; has = 0; next }
    inb && /^```/ {
      inb = 0
      if (has) { print "@@BLOCK@@" n; printf "%s", buf }
      next
    }
    inb {
      buf = buf $0 "\n"
      if ($0 ~ /^tasks:[[:space:]]*$/) has = 1
    }
  ' "$md")
  [ -n "$cand" ] || return 0

  local count
  count=$(printf '%s\n' "$cand" | grep -c '^@@BLOCK@@')
  if [ "$count" -gt 1 ]; then
    echo "dag::extract_yaml: WARN — tasks: 후보 yaml 펜스 ${count}개, 첫 번째 채택 ($md)" >&2
  fi
  printf '%s\n' "$cand" | awk '
    /^@@BLOCK@@/ { seen++; next }
    seen == 1 { print }
  '
}

# dag::list_leaves <yaml-string>
# YAML 입력에서 depends_on=[] 인 task id 만 newline 구분 출력
# YAML 파싱 실패 시 stderr WARN + 빈 출력 (fallback)
dag::list_leaves() {
  local yaml="$1"
  __dag_check_python || return 1
  SPECOPS_DAG_YAML="$yaml" python3 -c '
import os, sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml
data = os.environ["SPECOPS_DAG_YAML"]
try:
    doc = yaml.safe_load(data) or {}
except Exception as e:
    sys.stderr.write(f"⚠️  dag::list_leaves: YAML 파싱 실패 ({e}) — fallback\n")
    sys.exit(0)
tasks = doc.get("tasks", []) or []
for t in tasks:
    if not isinstance(t, dict):
        continue
    deps = t.get("depends_on") or []
    if isinstance(deps, list) and len(deps) == 0:
        tid = t.get("id")
        if tid:
            print(tid)
'
}

# dag::outputs_disjoint <yaml-string> <id1> <id2>
# id1·id2 outputs 집합 교집합 0 + 같은 디렉터리 새 파일 추가도 disjoint=false (보수)
# disjoint이면 exit 0, overlap이면 exit 1
dag::outputs_disjoint() {
  local yaml="$1" id1="$2" id3="$3"
  __dag_check_python || return 1
  SPECOPS_DAG_YAML="$yaml" python3 -c '
import os, sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml
id1, id2 = sys.argv[1], sys.argv[2]
data = os.environ["SPECOPS_DAG_YAML"]
try:
    doc = yaml.safe_load(data) or {}
except Exception:
    sys.exit(2)
tasks = {t["id"]: t for t in (doc.get("tasks") or []) if isinstance(t, dict) and "id" in t}
if id1 not in tasks or id2 not in tasks:
    sys.exit(2)
out1 = set(tasks[id1].get("outputs") or [])
out2 = set(tasks[id2].get("outputs") or [])
if out1 & out2:
    sys.exit(1)
sys.exit(0)
' "$id1" "$id3"
}

# dag::find_independent_batch <yaml-string>
# 절대 leaf (depends_on=[]) 만 후보 + 두 개씩 disjoint 검사 + 2개+ pair 발견 시 batch 출력
# 출력: id 들 newline 구분. batch 형성 못하면 빈 출력.
dag::find_independent_batch() {
  local yaml="$1"
  __dag_check_python || return 1
  SPECOPS_DAG_YAML="$yaml" python3 -c '
import os, sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml
data = os.environ["SPECOPS_DAG_YAML"]
try:
    doc = yaml.safe_load(data) or {}
except Exception as e:
    sys.stderr.write(f"⚠️  dag::find_independent_batch: YAML 파싱 실패 ({e}) — fallback (빈 batch)\n")
    sys.exit(0)
tasks = {t["id"]: t for t in (doc.get("tasks") or []) if isinstance(t, dict) and "id" in t}
candidates = [tid for tid, t in tasks.items()
              if isinstance(t.get("depends_on"), list) and len(t.get("depends_on") or []) == 0]
if len(candidates) < 2:
    sys.exit(0)

def disjoint(a, b):
    out_a = set(tasks[a].get("outputs") or [])
    out_b = set(tasks[b].get("outputs") or [])
    if out_a & out_b:
        return False
    return True

batch = []
for cand in candidates:
    if all(disjoint(cand, b) for b in batch):
        batch.append(cand)
if len(batch) >= 2:
    for tid in batch:
        print(tid)
'
}

# dag::find_ready <yaml-string> [done-id1 done-id2 ...]
# done 집합에 포함되지 않은 task 중 depends_on ⊆ done 인 task id (newline 구분, 다단계 wave)
# done-ids: 위치 인자로 전달 (0개 = wave 0 = 절대 leaf; dag::list_leaves 동치).
# 용도: implementing-ko wave 루프에서 `dag::find_ready "$yaml" $done` 로 반복 호출.
dag::find_ready() {
  local yaml="$1"
  shift
  local done_raw="${*:-}"   # 나머지 인자 공백 구분 문자열 (없으면 빈)
  __dag_check_python || return 1
  SPECOPS_DAG_YAML="$yaml" SPECOPS_DAG_DONE="$done_raw" python3 -c '
import os, sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml
data = os.environ["SPECOPS_DAG_YAML"]
done_raw = os.environ.get("SPECOPS_DAG_DONE", "").strip()
done = set(done_raw.split()) if done_raw else set()
try:
    doc = yaml.safe_load(data) or {}
except Exception as e:
    sys.stderr.write(f"⚠️  dag::find_ready: YAML 파싱 실패 ({e}) — fallback\n")
    sys.exit(0)
tasks = doc.get("tasks", []) or []
for t in tasks:
    if not isinstance(t, dict):
        continue
    tid = t.get("id")
    if not tid or tid in done:
        continue
    deps = t.get("depends_on") or []
    if isinstance(deps, list) and set(deps) <= done:
        print(tid)
'
}

# dag::get_task_test_command <yaml-string> <task-id>
# task 의 test_command 필드 stdout (Wave 2 U2 — FID 20260514).
# 미기재·미존재·파싱실패 3 분기 모두 stderr 에 정확히 1줄 warn 출력 후 graceful exit 0 (AC-2 (b)).
dag::get_task_test_command() {
  local yaml="$1"
  local task_id="$2"
  __dag_check_python || return 1
  YAML_IN="$yaml" python3 - "$task_id" << 'PYEOF'
import os, sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml
task_id = sys.argv[1]
try:
    data = yaml.safe_load(os.environ.get("YAML_IN", ""))
    for task in (data.get("tasks", []) if data else []):
        if task.get("id") == task_id:
            tc = task.get("test_command", "")
            if tc:
                print(tc)
            else:
                print(f"warn: task {task_id} test_command 미기재 — fallback", file=sys.stderr)
            sys.exit(0)
    # 미존재 task → 1 회 warn
    print(f"warn: task {task_id} 미존재 — fallback", file=sys.stderr)
    sys.exit(0)
except Exception as e:
    print(f"warn: dag::get_task_test_command 파싱 실패 ({e}) — fallback", file=sys.stderr)
    sys.exit(0)
PYEOF
}

# dag::get_task_outputs <yaml-string> <task-id>
# task 의 outputs 목록을 newline 구분 stdout (P0-2 task receipt).
# 미기재·미존재·파싱실패는 stderr warn 1줄 + 빈 stdout + exit 0.
dag::get_task_outputs() {
  local yaml="$1"
  local task_id="$2"
  __dag_check_python || return 1
  YAML_IN="$yaml" python3 - "$task_id" << 'PYEOF'
import os, sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
import yaml
task_id = sys.argv[1]
try:
    data = yaml.safe_load(os.environ.get("YAML_IN", ""))
    for task in (data.get("tasks", []) if data else []):
        if task.get("id") == task_id:
            outs = task.get("outputs") or []
            if isinstance(outs, list) and outs:
                for p in outs:
                    if isinstance(p, str) and p:
                        print(p)
            else:
                print(f"warn: task {task_id} outputs 미기재 — fallback", file=sys.stderr)
            sys.exit(0)
    print(f"warn: task {task_id} 미존재 — fallback", file=sys.stderr)
    sys.exit(0)
except Exception as e:
    print(f"warn: dag::get_task_outputs 파싱 실패 ({e}) — fallback", file=sys.stderr)
    sys.exit(0)
PYEOF
}
