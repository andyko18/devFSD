#!/usr/bin/env bash
# 구현자 태스크 절 분리 (20261115-token-task-slice) — emit-context.sh 가 tasks.md 의 태스크 절을 잘라
#   dispatch/<task-id>-task.md 로 쓰고, 문맥 파일에 그 경로를 싣는지.
#
# 왜 필요한가: 구현자는 자기 태스크 하나를 찾으려고 tasks.md 전체(이 저장소 최근 12건 5~65KB)를 읽었다.
#   자른 절에 앞뒤 태스크가 섞이거나(경계 오판) 코드 펜스 안의 `## ` 줄을 제목으로 읽으면 구현자가 남의 태스크를
#   구현하거나 자기 테스트 코드를 잃는다. 절을 못 찾는 옛 형식 문서에서 emit 이 실패하면 구현 진입이 막힌다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
FIX="$PLUGIN/scripts/tests/dag/fixtures/emit-context/ok-fid"
EMIT="$PLUGIN/scripts/dag/emit-context.sh"
VAL="$PLUGIN/scripts/dag/validate-context.sh"
F=slice-fid
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

_pf() { if [ "$2" = ok ]; then PASS=$((PASS+1)); echo "PASS $1"; else FAIL=$((FAIL+1)); echo "FAIL $1${3:+ — $3}"; fi; }

# YAML DAG — 인자로 받은 id 마다 태스크 1개(AC-1·AC-2 공유 — must 커버리지 게이트)
_yaml() {
  printf '## 의존 그래프\n\n```yaml\ntasks:\n'
  local id
  for id in "$@"; do
    printf '  - id: %s\n    depends_on: []\n    inputs: [src/%s.sh]\n    outputs: [src/%s.sh]\n    ac: [AC-1, AC-2]\n    test_command: "bash scripts/tests/test-%s.sh"\n' "$id" "$id" "$id" "$id"
  done
  printf '```\n'
}
# 새 작업 폴더 — spec·AC 는 ok-fid 것, tasks.md 는 stdin
_mk() {
  local d; d=$(mktemp -d "$TMP/w.XXXXXX")
  mkdir -p "$d/.specops/$F"
  cp "$FIX/spec.md" "$FIX/acceptance-criteria.md" "$d/.specops/$F/"
  cat > "$d/.specops/$F/tasks.md"
  printf '%s' "$d"
}
# implementing-ko 가 dispatch 직전에 하는 것처럼 §5 작업 디렉터리 자리표시를 채운 사본으로 검사한다(emit 원본은 `<repo-root>` 라 늘 5번 누락이다)
_val() { sed 's|<repo-root>|/repo|' "$1" > "$1.v" && bash "$VAL" "$1.v" 2>/dev/null; }
_emit() { ( cd "$1" && bash "$EMIT" "$F" 2>"$1/emit.err" >"$1/emit.out" ); }

# ── 기본 문서: 2단계 `## Task N` · 하위 `### Task N —` · 펜스 안 `## ` · 태스크 아닌 `## ` 절 ──
W=$( { cat <<'EOF'
# 태스크 목록 — slice-fid

## Task 1: parser

본문-T1-ALPHA

```bash
## Task 2: 펜스 안의 가짜 제목 — 제목이 아니다
echo FENCED-T1
```

### Task 1 — 둘째 사이클

본문-T1-BETA

## Task 2: writer

본문-T2-GAMMA

````markdown
```python
## 펜스 안 펜스
```
## Task 1: 네 칸 펜스 안 — 제목이 아니다
````

~~~
## Task 1: 물결 펜스 안
~~~

### 스텝 3

본문-T2-DELTA

## 파괴적 작업

본문-NOT-TASK

EOF
_yaml T1 T2; } | _mk)
_emit "$W"; rc=$?
D="$W/.specops/$F/dispatch"
t1=$(cat "$D/T1-task.md" 2>/dev/null); t2=$(cat "$D/T2-task.md" 2>/dev/null)

_pf "S1 emit 성공 · 태스크마다 -task.md" "$([ "$rc" = 0 ] && [ -f "$D/T1-task.md" ] && [ -f "$D/T2-task.md" ] && echo ok)" "rc=$rc err=$(cat "$W/emit.err")"
_pf "S2 T1 절 — 자기 본문·하위 사이클·펜스 안 줄을 담고 다음 태스크는 담지 않는다" \
  "$(printf '%s' "$t1" | grep -q '^## Task 1: parser' && printf '%s' "$t1" | grep -q '본문-T1-ALPHA' && printf '%s' "$t1" | grep -q '본문-T1-BETA' \
     && printf '%s' "$t1" | grep -q 'FENCED-T1' && printf '%s' "$t1" | grep -q '^## Task 2: 펜스 안의 가짜 제목' \
     && ! printf '%s' "$t1" | grep -q '본문-T2' && echo ok)" "$t1"
_pf "S3 T2 절 — 펜스(네 칸·물결) 안 '## Task 1' 에서 끊기지 않고 '## 파괴적 작업' 앞에서 끝난다" \
  "$(printf '%s' "$t2" | grep -q '^## Task 2: writer' && printf '%s' "$t2" | grep -q '본문-T2-GAMMA' && printf '%s' "$t2" | grep -q '본문-T2-DELTA' \
     && ! printf '%s' "$t2" | grep -q '본문-T1' && ! printf '%s' "$t2" | grep -q 'NOT-TASK' && ! printf '%s' "$t2" | grep -q 'test_command' && echo ok)" "$t2"
ctx="$D/T1-context.md"
_pf "S4 문맥 파일에 태스크 절 경로 1줄 · validate-context 통과" \
  "$(grep -qF "\`.specops/$F/dispatch/T1-task.md\`" "$ctx" && [ "$(grep -c -- '-task.md' "$ctx")" = 1 ] && _val "$ctx" && echo ok)" "$(cat "$ctx" 2>/dev/null)"
_pf "S5 절을 다 찾으면 표준 오류에 절 알림이 없다" "$(! grep -q '태스크 절' "$W/emit.err" && echo ok)" "$(cat "$W/emit.err")"

# ── 재실행: 절이 바뀌면 덮어쓰고, 절이 사라지면 옛 파일을 지운다 ──
sed -i.bak 's/본문-T1-ALPHA/본문-T1-CHANGED/' "$W/.specops/$F/tasks.md"
_emit "$W"
_pf "S6 재실행 — 바뀐 절로 덮어쓴다" "$(grep -q '본문-T1-CHANGED' "$D/T1-task.md" && ! grep -q '본문-T1-ALPHA' "$D/T1-task.md" && echo ok)"
sed -i.bak 's/^## Task 2: writer/## 작업 둘: writer/' "$W/.specops/$F/tasks.md"
_emit "$W"; rc=$?
_pf "S7 재실행 — 절을 못 찾게 되면 옛 -task.md 를 남기지 않는다(낡은 절을 읽지 않게)" \
  "$([ "$rc" = 0 ] && [ ! -e "$D/T2-task.md" ] && [ -f "$D/T1-task.md" ] && echo ok)" "rc=$rc ls=$(ls "$D")"

# ── 절을 못 찾는 태스크: emit 은 성공 · 그 태스크만 파일 없음 · stderr 1줄 · 문맥 파일은 tasks.md 로 안내 ──
W=$( { printf '# t\n\n## Task 1: a\n\n본문-A\n\n## Task 2: b\n\n본문-B\n\n'; _yaml T1 T2 T3; } | _mk)
_emit "$W"; rc=$?; D="$W/.specops/$F/dispatch"
_pf "S8 절 없는 T3 — emit rc 0 · T3-task.md 없음 · T1·T2 는 있음" \
  "$([ "$rc" = 0 ] && [ ! -e "$D/T3-task.md" ] && [ -f "$D/T1-task.md" ] && [ -f "$D/T2-task.md" ] && [ -f "$D/T3-context.md" ] && echo ok)" "rc=$rc err=$(cat "$W/emit.err")"
_pf "S9 절 없는 태스크는 표준 오류 1줄로 알린다" "$([ "$(grep -c 'T3.*태스크 절' "$W/emit.err")" = 1 ] && ! grep -q 'T1.*태스크 절' "$W/emit.err" && echo ok)" "$(cat "$W/emit.err")"
_pf "S10 절 없는 태스크의 문맥 파일 — -task.md 경로 대신 tasks.md 에서 찾으라고 안내 · validate 통과" \
  "$(! grep -q 'T3-task.md' "$D/T3-context.md" && grep -q "tasks.md\` 에서" "$D/T3-context.md" && _val "$D/T3-context.md" && echo ok)" "$(cat "$D/T3-context.md")"

# ── 절 번호와 task id 가 어긋나면(T1·T2 인데 절은 2·3) 대응시키지 않는다 — 남의 절을 주지 않는다 ──
W=$( { printf '# t\n\n## Task 2: a\n\n본문-A\n\n## Task 3: b\n\n본문-B\n\n'; _yaml T1 T2; } | _mk)
_emit "$W"; rc=$?; D="$W/.specops/$F/dispatch"
_pf "S11 절 번호 어긋남 → -task.md 0개 · emit 성공 · 알림" \
  "$([ "$rc" = 0 ] && ! compgen -G "$D/*-task.md" >/dev/null && grep -q '태스크 절' "$W/emit.err" && echo ok)" "rc=$rc ls=$(ls "$D") err=$(cat "$W/emit.err")"

# ── 같은 번호의 절이 둘 → 그 태스크는 대응시키지 않는다 ──
W=$( { printf '# t\n\n## Task 1: a\n\n본문-A\n\n## Task 1: a2\n\n본문-A2\n\n## Task 2: b\n\n본문-B\n\n'; _yaml T1 T2; } | _mk)
_emit "$W"; rc=$?; D="$W/.specops/$F/dispatch"
_pf "S12 같은 번호 절 둘 → 그 태스크만 파일 없음" \
  "$([ "$rc" = 0 ] && [ ! -e "$D/T1-task.md" ] && grep -q '본문-B' "$D/T2-task.md" && echo ok)" "rc=$rc ls=$(ls "$D")"

# ── decomposing-ko 예시 형식: 3단계 `### Task N:` · `## 태스크 N:`(템플릿) ──
W=$( { printf '# t\n\n### Task 1: a\n\n본문-A\n\n### Task 2: b\n\n본문-B\n\n## 진행 상태\n\n- [ ] x\n\n'; _yaml T1 T2; } | _mk)
_emit "$W"; D="$W/.specops/$F/dispatch"
_pf "S13 3단계 '### Task N' — 다음 '### Task' 앞에서 끊고 '## 진행 상태' 를 담지 않는다" \
  "$(grep -q '본문-A' "$D/T1-task.md" && ! grep -q '본문-B' "$D/T1-task.md" && grep -q '본문-B' "$D/T2-task.md" && ! grep -q '진행 상태' "$D/T2-task.md" && echo ok)"
W=$( { printf '# t\n\n## 태스크 1: 가\n\n본문-가\n\n## 태스크 2: 나\n\n본문-나\n\n'; _yaml T1 T2; } | _mk)
_emit "$W"; D="$W/.specops/$F/dispatch"
_pf "S14 템플릿 형식 '## 태스크 N'" "$(grep -q '본문-가' "$D/T1-task.md" && ! grep -q '본문-나' "$D/T1-task.md" && grep -q '본문-나' "$D/T2-task.md" && echo ok)"

# ── 문서 배선 ──
IMP="$PLUGIN/agents/implementer-ko.md"
_pf "S15 구현자 정의 — 태스크 본문은 dispatch/<task-id>-task.md · tasks.md 전체는 읽지 않는다 · 없으면 tasks.md 에서 찾는다" \
  "$(grep -qF 'dispatch/<task-id>-task.md' "$IMP" && grep -q 'tasks.md` 전체는 읽지 않는다' "$IMP" && grep -q 'task.md` 가 없으면' "$IMP" && echo ok)"
_pf "S16 템플릿·implementing-ko 가 태스크 절 파일을 안다" \
  "$(grep -qF -- '-task.md' "$PLUGIN/templates/dispatch-context.md" && grep -qF -- '<task-id>-task.md' "$PLUGIN/skills/implementing-ko/SKILL.md" && echo ok)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
