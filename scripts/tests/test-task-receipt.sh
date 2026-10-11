#!/usr/bin/env bash
# P0-2 태스크 receipt — 기록·게이트 판정
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
REC="$PLUGIN/scripts/_internal/record-task-receipt.sh"
CHK="$PLUGIN/scripts/_internal/check-task-receipt.sh"
source "$PLUGIN/hooks/governance-lib.sh"
rule_r1=$(jq -c 'select(.id == "R-1")' "$PLUGIN/hooks/rules.jsonl")
rule_r2=$(jq -c 'select(.id == "R-2")' "$PLUGIN/hooks/rules.jsonl")
FIX="$PLUGIN/scripts/tests/governance/fixtures/transcripts"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/tests/lib/exec-transcript.sh"   # _tr_for — 실행 증거 픽스처를 샌드박스 FID 에 맞춘다

_setup_fid() {  # $1=dir $2=fid
  local d="$1" fid="$2"
  mkdir -p "$d/.specops/$fid" "$d/scripts/tests" "$d/src"
  # 정식 lifecycle 의 FID 다 — 명세가 있다. 명세 없이 태스크 문서만 있으면 quick 경로로 판정돼 범위·리뷰까지 요구된다
  #   (20261010-quick-fix-path · 그쪽은 test-quick-fix.sh 가 잰다).
  printf '# spec\n' > "$d/.specops/$fid/spec.md"
  printf 'echo ok\n' > "$d/scripts/tests/test-foo.sh"
  chmod +x "$d/scripts/tests/test-foo.sh"
  printf 'x\n' > "$d/src/foo.sh"
  cat > "$d/.specops/$fid/tasks.md" <<'EOF'
# tasks

## 의존 그래프

```yaml
tasks:
  - id: T1
    test_command: "bash scripts/tests/test-foo.sh"
    depends_on: []
    inputs: []
    outputs: [src/foo.sh, scripts/tests/test-foo.sh]
    ac: [AC-1]
```
EOF
  printf '<!-- active-fid: %s -->\n## %s\n- 2026-08-03 10:00 /implement DONE (T1)\n' "$fid" "$fid" \
    > "$d/.specops/session-progress.md"
  (cd "$d" && git init -q && git add src scripts && git -c user.name=t -c user.email=t@e.com commit -qm init)
}

TD=$(mktemp -d) || exit 1
trap 'rm -rf "$TD"' EXIT
FID=20260803-receipt
_setup_fid "$TD" "$FID"

# 작업 트리에 커밋 가능한 변경을 만든 뒤 receipt를 찍는다 (clean tree면 staged 공집합).
printf 'updated\n' > "$TD/src/foo.sh"
printf 'echo ok\n' > "$TD/scripts/tests/test-foo.sh"

# TR-1: PASS 기록
(cd "$TD" && bash "$REC" "$FID" T1) >/dev/null
if [ -f "$TD/.specops/$FID/receipts/T1.json" ] \
   && jq -e '.verdict=="PASS" and .task=="T1" and (.outputs|length)==2' \
        "$TD/.specops/$FID/receipts/T1.json" >/dev/null; then
  ok "TR-1 PASS receipt 기록"
else
  nope "TR-1" "missing/invalid receipt"
fi

# TR-2: FAIL 테스트 → 기록 거부
printf 'exit 1\n' > "$TD/scripts/tests/test-foo.sh"
if (cd "$TD" && bash "$REC" "$FID" T1) >/dev/null 2>&1; then
  nope "TR-2" "FAIL 테스트가 receipt 기록됨"
else
  ok "TR-2 FAIL → 기록 거부"
fi
printf 'echo ok\n' > "$TD/scripts/tests/test-foo.sh"
(cd "$TD" && bash "$REC" "$FID" T1) >/dev/null

# TR-3: staged ⊆ outputs → check 0
(cd "$TD" && git add src/foo.sh scripts/tests/test-foo.sh)
if (cd "$TD" && bash "$CHK" "$FID" T1); then
  ok "TR-3 staged⊆outputs → 0"
else
  nope "TR-3" "rc=$?"
fi

# TR-4: staged 초과 → deny 1
printf 'extra\n' > "$TD/src/extra.sh"
(cd "$TD" && git add src/extra.sh)
if (cd "$TD" && bash "$CHK" "$FID" T1) >/dev/null 2>&1; then
  nope "TR-4" "초과 staged 허용"
else
  rc=$?; [ "$rc" -eq 1 ] && ok "TR-4 staged 초과 → 1" || nope "TR-4" "rc=$rc"
fi
(cd "$TD" && git reset -q HEAD -- src/extra.sh && rm -f src/extra.sh)
(cd "$TD" && bash "$REC" "$FID" T1) >/dev/null
(cd "$TD" && git add src/foo.sh scripts/tests/test-foo.sh)

# TR-5: tree stale → 1
printf 'dirty\n' >> "$TD/src/foo.sh"
if (cd "$TD" && bash "$CHK" "$FID" T1) >/dev/null 2>&1; then
  nope "TR-5" "stale tree 허용"
else
  rc=$?; [ "$rc" -eq 1 ] && ok "TR-5 tree stale → 1" || nope "TR-5" "rc=$rc"
fi
git -C "$TD" restore src/foo.sh
(cd "$TD" && bash "$REC" "$FID" T1) >/dev/null
(cd "$TD" && git add src/foo.sh scripts/tests/test-foo.sh)

# TR-6: test_command drift → 1
# tasks.md 의 test_command 변경
perl -pi -e 's/test-foo\.sh/test-foo.sh --x/' "$TD/.specops/$FID/tasks.md" 2>/dev/null \
  || sed -i '' 's/test-foo\.sh"/test-foo.sh --x"/' "$TD/.specops/$FID/tasks.md"
if (cd "$TD" && bash "$CHK" "$FID" T1) >/dev/null 2>&1; then
  nope "TR-6" "command drift 허용"
else
  rc=$?; [ "$rc" -eq 1 ] && ok "TR-6 command drift → 1" || nope "TR-6" "rc=$rc"
fi
# 복원
cat > "$TD/.specops/$FID/tasks.md" <<'EOF'
# tasks

## 의존 그래프

```yaml
tasks:
  - id: T1
    test_command: "bash scripts/tests/test-foo.sh"
    depends_on: []
    inputs: []
    outputs: [src/foo.sh, scripts/tests/test-foo.sh]
    ac: [AC-1]
```
EOF
(cd "$TD" && bash "$REC" "$FID" T1) >/dev/null
(cd "$TD" && git add src/foo.sh scripts/tests/test-foo.sh)

# TR-7: 부재 → 2
if (cd "$TD" && bash "$CHK" "$FID" T99) >/dev/null 2>&1; then
  nope "TR-7" "부재가 0"
else
  rc=$?; [ "$rc" -eq 2 ] && ok "TR-7 부재 → 2" || nope "TR-7" "rc=$rc"
fi

# TR-8: receipt 유효 → R-1 면제 (exec 증거 없어도)
out=$(cd "$TD" && apply_lookback_rule "$rule_r1" "$FIX/exec-evidence-absent.jsonl" \
  "Bash" 'git commit -m "feat(T1): foo"')
[ -z "$out" ] && ok "TR-8 receipt → R-1 면제(exec 불요)" || nope "TR-8" "out=$out"

# TR-9: Wave A — legacy 실행증거 implement 면제 폐지 (receipt 없으면 deny)
LGD=$(mktemp -d)
mkdir -p "$LGD/.specops/20260101-legacy"
printf '<!-- active-fid: 20260101-legacy -->\n## 20260101-legacy\n' > "$LGD/.specops/session-progress.md"
echo tasks > "$LGD/.specops/20260101-legacy/tasks.md"
out=$(cd "$LGD" && apply_lookback_rule "$rule_r1" "$(_tr_for "$LGD" "$FIX/exec-evidence-pass.jsonl")" \
  "Bash" 'git commit -m "feat: T1"')
if [ -n "$out" ] && echo "$out" | jq -e '.rule_id=="R-1"' >/dev/null; then
  ok "TR-9 legacy exec 면제 폐지 → deny"
else
  nope "TR-9" "out=$out"
fi
rm -rf "$LGD"

# TR-10: receipt 있어도 R-2는 열리지 않음
out=$(cd "$TD" && apply_lookback_rule "$rule_r2" "$FIX/exec-evidence-absent.jsonl" \
  "Bash" 'gh pr create --fill')
if [ -n "$out" ] && echo "$out" | jq -e '.rule_id=="R-2"' >/dev/null; then
  ok "TR-10 receipt로 R-2 미개방"
else
  nope "TR-10" "out=$out"
fi

# task 추론
hit=$(_infer_commit_task 'git commit -m "feat(T3): x"')
[ "$hit" = "T3" ] && ok "TR-11a infer T3" || nope "TR-11a" "hit=$hit"
hit=$(_infer_commit_task 'git commit -m "Task: T12 done"')
[ "$hit" = "T12" ] && ok "TR-11b infer Task: T12" || nope "TR-11b" "hit=$hit"


# === AC-2 / AC-R-1: evidence.md 를 쓴 태스크가 다른 태스크의 receipt 경로를 닫지 않는다 ===
# 사고 재현(20260910-commit-scope-prelude): T4 가 14:39 evidence.md 작성 → T5(15:46)·T6(16:45)
#   커밋이 /verify(16:56) 이전이라 자기보고 앵커도 없어 전 경로 폐쇄 → BYPASS 2건.
# ★ 픽스처는 반드시 _setup_fid(이 파일 L15-33)를 쓴다. 손으로 만들면 세 곳이 조용히 깨진다
#   (plan-reviewer 실측): ① session-progress 부재 → detect_fid 빈값 → R-1 창 분기 **미진입**
#   ② tasks.md 에 test_command 부재 → record-task-receipt.sh:34 exit 1 → receipt 미기록
#   ③ `git add -A` 가 .specops/* 를 staged → check-task-receipt.sh staged⊄outputs → rc=1
_RWC=$(mktemp -d) || exit 1
_rwc_fid=20260910-rwc
_setup_fid "$_RWC" "$_rwc_fid"
printf 'updated\n' > "$_RWC/src/foo.sh"          # 커밋 가능한 변경 (clean tree 면 staged 공집합)
# ★ 사고 조건: evidence.md 는 있고 verify 는 아직 안 돌았다
#   (verification-state.json 부재 + RUN-VERIFICATION-RESULT 스탬프 없음 → vs::current = NOT_RUN)
printf '# 실험 관찰 기록\n변이 M1 격추\n' > "$_RWC/.specops/$_rwc_fid/evidence.md"
(cd "$_RWC" && git add src && bash "$REC" "$_rwc_fid" T1) >/dev/null 2>&1
out=$(cd "$_RWC" && apply_lookback_rule "$rule_r1" "$(_tr_for "$_RWC" "$FIX/exec-evidence-pass.jsonl")" "Bash" 'git commit -m "fix: x (Task: T1)"')
if [ -z "$out" ]; then ok "T-rwc.a evidence.md 존재 + verify 미실행 → receipt 면제"
else nope "T-rwc.a" "창이 닫혔다: $out"; fi

# === AC-R-2: STALE 대조군 — verify PASS 후 코드 수정이면 유효 receipt 가 있어도 차단 ===
# 17f8617(20260828) 계약 보존 실증. 이 케이스가 면제되면 축 A 가 계약을 약화시킨 것이다.
# ★ verification-state.json 을 손으로 쓰지 않는다 — SoT 스크립트로 기록해야 tree_hash 가 실물이다
#   (손으로 쓴 빈/가짜 해시는 vs::current 가 STALE 검사를 skip 해 픽스처가 항상 통과한다 — 리뷰어 실측).
(cd "$_RWC" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" \
   record "$_rwc_fid" PASS --executed 1 --failed 0) >/dev/null 2>&1
printf 'stale-inducing edit\n' >> "$_RWC/src/foo.sh"      # ← 기록 이후 코드 변경 → STALE
_rwc_v=$(cd "$_RWC" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" current "$_rwc_fid")
[ "$_rwc_v" = "STALE" ] || nope "T-rwc.b-pre" "픽스처가 STALE 이 아니다: $_rwc_v"
(cd "$_RWC" && git add src && bash "$REC" "$_rwc_fid" T1) >/dev/null 2>&1   # receipt 는 유효하게 갱신
out=$(cd "$_RWC" && apply_lookback_rule "$rule_r1" "$(_tr_for "$_RWC" "$FIX/exec-evidence-pass.jsonl")" "Bash" 'git commit -m "fix: x (Task: T1)"')
if [ -n "$out" ]; then ok "T-rwc.b STALE → 유효 receipt 여도 차단(17f8617 계약 보존)"
else nope "T-rwc.b" "STALE 인데 면제됨 — 계약 약화"; fi

# === PASS(신선) 대조군 — 창이 닫히고 자기보고 경로로 넘어간다 ===
# 위 STALE 편집 이후 다시 record 하면 현재 트리 지문이 기록돼 신선 PASS 가 된다.
(cd "$_RWC" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" \
   record "$_rwc_fid" PASS --executed 1 --failed 0) >/dev/null 2>&1
_rwc_v=$(cd "$_RWC" && SPECOPS_ROOT=.specops bash "$PLUGIN/scripts/_internal/verification-state.sh" current "$_rwc_fid")
[ "$_rwc_v" = "PASS" ] || nope "T-rwc.c-pre" "픽스처가 신선 PASS 가 아니다: $_rwc_v"
out=$(cd "$_RWC" && apply_lookback_rule "$rule_r1" "$(_tr_for "$_RWC" "$FIX/exec-evidence-pass.jsonl")" "Bash" 'git commit -m "fix: x (Task: T1)"')
if [ -z "$out" ]; then ok "T-rwc.c verify PASS 신선 → 자기보고 경로로 면제(창 닫힘)"
else nope "T-rwc.c" "PASS 신선인데 차단: $out"; fi
rm -rf "$_RWC"

# ── 파일 클래스 구분 (20260912-verify-stale-docs-scope) ──────────────────────
# receipt 는 verify 창이 닫혔을 때의 유일한 통로다 — 지문과 같은 맹점을 함께 푼다.
# ★ 양성 대조군 **쌍** 필수: 문서=유효 ∧ 코드=거부. 한쪽만 두면 분류기를 비워도 통과한다.
_RD=$(mktemp -d) || exit 1
_rd_fid=20260912-rcpt
_setup_fid "$_RD" "$_rd_fid"
mkdir -p "$_RD/.claude-plugin"
printf '{"name":"x"}\n' > "$_RD/.claude-plugin/plugin.json"
printf 'doc\n' > "$_RD/CHANGELOG.md"
(cd "$_RD" && git add -A && git -c user.name=t -c user.email=t@e.com commit -qm doc) >/dev/null 2>&1
printf 'updated\n' > "$_RD/src/foo.sh"
(cd "$_RD" && bash "$REC" "$_rd_fid" T1) >/dev/null 2>&1

# TR-D1 문서 전용 변경 후에도 receipt 유효 (AC-7)
printf 'doc changed\n' > "$_RD/CHANGELOG.md"
(cd "$_RD" && git add src scripts) >/dev/null 2>&1
if (cd "$_RD" && bash "$CHK" "$_rd_fid" T1) >/dev/null 2>&1; then
  ok "TR-D1 문서 변경 후 receipt 유효"
else
  nope "TR-D1 문서 변경 후 receipt 유효" "tree stale 로 거부됨"
fi

# TR-D2 코드 변경 후에는 거부 (양성 대조)
printf 'code changed\n' > "$_RD/src/foo.sh"
if (cd "$_RD" && bash "$CHK" "$_rd_fid" T1) >/dev/null 2>&1; then
  nope "TR-D2 코드 변경 후 receipt 거부" "통과해버림"
else
  ok "TR-D2 코드 변경 후 receipt 거부"
fi

# TR-D3 구버전 receipt(nondoc_hash 부재) → 종전 전체 지문 비교로 떨어진다 (AC-7 검증방법 3항)
# ★ 부재 시 방향이 **더 엄격한 쪽**이어야 한다 — 문서 변경만으로도 거부되는 것이 정상이다.
#   이 케이스가 없으면 "하위 호환" 주장이 무잠금이고, 필드를 안 읽는 구현으로 퇴행해도 통과한다.
jq 'del(.nondoc_hash)' "$_RD/.specops/$_rd_fid/receipts/T1.json" > "$_RD/rc.tmp" \
  && mv "$_RD/rc.tmp" "$_RD/.specops/$_rd_fid/receipts/T1.json"
printf 'code\n' > "$_RD/src/foo.sh"          # 코드 원복 — 문서 변경만 남긴다
printf 'doc changed twice\n' > "$_RD/CHANGELOG.md"
if (cd "$_RD" && bash "$CHK" "$_rd_fid" T1) >/dev/null 2>&1; then
  nope "TR-D3 구버전 receipt → 종전 동작(더 엄격)" "문서 변경인데 통과 — 하위 호환이 느슨한 쪽"
else
  ok "TR-D3 구버전 receipt → 종전 동작(더 엄격)"
fi
rm -rf "$_RD"

# ── TR-U 지문 계산 불가(UNHASHABLE) — 읽을 수 없는 파일 (20261005-fingerprint-add-failclosed) ──
# 이 repo 처럼 .specops 가 gitignore 인 조건(정상 add 가 rc 1)에서 정상 기록·검사가 되는 양성 대조군 +
# 읽을 수 없는 tracked 파일이 생기면 기록 거부·검사 거부(음성). root 는 chmod 000 이 읽히므로 skip.
_chmod_inert() { local f; f=$(mktemp) || return 0; chmod 000 "$f"; if [ -r "$f" ]; then rm -f "$f"; return 0; fi; rm -f "$f"; return 1; }   # root·ACL·비-POSIX FS 에서는 chmod 000 이 파일을 막지 못한다
if _chmod_inert; then
  skip "TR-U 읽을 수 없는 파일 — chmod 000 이 파일을 막지 못한다(root·ACL 등)"
else
_RU=$(mktemp -d) || exit 1
_ru_fid=20261005-unhash
_setup_fid "$_RU" "$_ru_fid"
printf '.specops/\n' > "$_RU/.gitignore"
printf 'locked\n' > "$_RU/locked.dat"
(cd "$_RU" && git add .gitignore locked.dat && git -c user.name=t -c user.email=t@e.com commit -qm lock) >/dev/null 2>&1
printf 'updated\n' > "$_RU/src/foo.sh"

# TR-U0 양성 대조 — .specops ignore(add rc 1) 에서도 기록·검사가 정상이다
(cd "$_RU" && bash "$REC" "$_ru_fid" T1) >/dev/null 2>&1
(cd "$_RU" && git add src scripts) >/dev/null 2>&1
if [ -f "$_RU/.specops/$_ru_fid/receipts/T1.json" ] && (cd "$_RU" && bash "$CHK" "$_ru_fid" T1) >/dev/null 2>&1; then
  ok "TR-U0 .specops ignore 에서 receipt 기록·검사 정상 (양성 대조)"
else
  nope "TR-U0 .specops ignore 에서 receipt 기록·검사 정상" "기록 또는 검사 실패"
fi

# TR-U1 읽을 수 없는 tracked 파일 → 유효하던 receipt 도 검사 거부 (사유에 UNHASHABLE)
chmod 000 "$_RU/locked.dat"
_ru_err=$(cd "$_RU" && bash "$CHK" "$_ru_fid" T1 2>&1 >/dev/null); _ru_rc=$?
if [ "$_ru_rc" != "0" ] && printf '%s' "$_ru_err" | grep -q 'UNHASHABLE'; then
  ok "TR-U1 읽을 수 없는 파일 → receipt 검사 거부 (사유 UNHASHABLE)"
else
  nope "TR-U1 읽을 수 없는 파일 → receipt 검사 거부" "rc=$_ru_rc err=$_ru_err"
fi

# TR-U2 읽을 수 없는 상태에서는 기록 자체를 거부한다 (receipt 파일을 만들지 않는다)
rm -f "$_RU/.specops/$_ru_fid/receipts/T1.json"
_ru_err=$(cd "$_RU" && bash "$REC" "$_ru_fid" T1 2>&1 >/dev/null); _ru_rc=$?
if [ "$_ru_rc" = "1" ] && [ ! -f "$_RU/.specops/$_ru_fid/receipts/T1.json" ] \
   && printf '%s' "$_ru_err" | grep -q 'UNHASHABLE'; then
  ok "TR-U2 읽을 수 없는 파일 → receipt 기록 거부 (exit 1 · 파일 없음 · 안내)"
else
  nope "TR-U2 읽을 수 없는 파일 → receipt 기록 거부" "rc=$_ru_rc err=$_ru_err"
fi
chmod 644 "$_RU/locked.dat"

# TR-U3 receipt 에 UNHASHABLE 이 기록돼 있으면(손으로 만든 경우 포함) 트리가 정상이어도 거부
(cd "$_RU" && bash "$REC" "$_ru_fid" T1) >/dev/null 2>&1
jq '.nondoc_hash="UNHASHABLE"' "$_RU/.specops/$_ru_fid/receipts/T1.json" > "$_RU/rc.tmp" \
  && mv "$_RU/rc.tmp" "$_RU/.specops/$_ru_fid/receipts/T1.json"
(cd "$_RU" && git add src scripts) >/dev/null 2>&1
if (cd "$_RU" && bash "$CHK" "$_ru_fid" T1) >/dev/null 2>&1; then
  nope "TR-U3 기록값 UNHASHABLE receipt 거부" "통과해버림"
else
  ok "TR-U3 기록값 UNHASHABLE receipt 거부"
fi

# TR-U4 기록값도 현재값도 UNHASHABLE(같은 값)이어도 일치로 보지 않는다 — 가드가 없으면 UNHASHABLE == UNHASHABLE 로 통과한다
chmod 000 "$_RU/locked.dat"
if (cd "$_RU" && bash "$CHK" "$_ru_fid" T1) >/dev/null 2>&1; then
  nope "TR-U4 기록·현재 모두 UNHASHABLE 이어도 거부" "UNHASHABLE == UNHASHABLE 로 통과해버림"
else
  ok "TR-U4 기록·현재 모두 UNHASHABLE 이어도 거부"
fi
chmod 644 "$_RU/locked.dat"

# TR-U5 구버전 receipt(nondoc_hash 부재 → tree_hash 비교 경로)도 UNHASHABLE 끼리 일치로 보지 않는다
jq 'del(.nondoc_hash) | .tree_hash="UNHASHABLE"' "$_RU/.specops/$_ru_fid/receipts/T1.json" > "$_RU/rc.tmp" \
  && mv "$_RU/rc.tmp" "$_RU/.specops/$_ru_fid/receipts/T1.json"
chmod 000 "$_RU/locked.dat"
if (cd "$_RU" && bash "$CHK" "$_ru_fid" T1) >/dev/null 2>&1; then
  nope "TR-U5 구버전 receipt 의 UNHASHABLE tree_hash 거부" "UNHASHABLE == UNHASHABLE 로 통과해버림"
else
  ok "TR-U5 구버전 receipt 의 UNHASHABLE tree_hash 거부"
fi
chmod 644 "$_RU/locked.dat"
rm -rf "$_RU"
fi

# ── TR-N 음성 경로 — check-task-receipt.sh 의 모든 거부 분기를 rc + 사유로 잠근다 (20261008-test-holes) ──
# 종전엔 TR-4~7 외 분기(verdict·fid/task 불일치·symlink·tasks.md 부재·test_command 부재·staged 공집합·
#   outputs 공집합·jq 파싱 실패·입력 형식 오류)가 무검증이라 `exit 1 → exit 0` 변이가 전부 생존했다.
# ★ 각 케이스는 rc 만이 아니라 **stderr 사유**도 단언한다 — 다른 분기가 우연히 같은 rc 를 내서 통과하는 것을 막는다.
# ★ 먼저 양성 대조(TR-N0: 무변형 receipt → rc 0)를 둔다. 이게 없으면 픽스처가 깨져도 음성이 전부 통과한다.
_RN=$(mktemp -d) || exit 1
_RA=$(mktemp -d) || exit 1   # 보조 파일(receipt 원본·shim)은 repo 밖에 둔다 — 안에 두면 untracked 파일이 지문을 바꿔 tree stale 이 된다
_rn_fid=20261008-neg
_setup_fid "$_RN" "$_rn_fid"
printf 'updated\n' > "$_RN/src/foo.sh"
(cd "$_RN" && bash "$REC" "$_rn_fid" T1) >/dev/null 2>&1
(cd "$_RN" && git add src scripts) >/dev/null 2>&1
_rn_rcpt="$_RN/.specops/$_rn_fid/receipts/T1.json"
_rn_tasks="$_RN/.specops/$_rn_fid/tasks.md"
cp "$_rn_rcpt" "$_RA/receipt.base"
cp "$_rn_tasks" "$_RA/tasks.base"

# _rn_expect <id> <기대 rc> <stderr 사유(부분문자열, 빈값=미검사)> -- <check 인자...>
_rn_expect() {
  local id="$1" want="$2" reason="$3"; shift 4
  local err rc
  err=$(cd "$_RN" && bash "$CHK" "$@" 2>&1 >/dev/null); rc=$?
  if [ "$rc" = "$want" ] && { [ -z "$reason" ] || printf '%s' "$err" | grep -qF -- "$reason"; }; then
    ok "$id → rc=$want${reason:+ ($reason)}"
  else
    nope "$id" "rc=$rc(기대 $want) err=$err"
  fi
}
_rn_restore() { rm -f "$_rn_rcpt" "$_RA/real.json"; cp "$_RA/receipt.base" "$_rn_rcpt"; cp "$_RA/tasks.base" "$_rn_tasks"; }

_rn_expect "TR-N0 양성 대조(무변형 receipt)" 0 "" -- "$_rn_fid" T1

# verdict != PASS
jq '.verdict="FAIL"' "$_RA/receipt.base" > "$_rn_rcpt"
_rn_expect "TR-N1 verdict!=PASS" 1 "verdict!=PASS" -- "$_rn_fid" T1
_rn_restore

# receipt 의 fid 불일치 / task 불일치 (각각 따로 — `&&` 한쪽만 끊는 변이도 잡는다)
jq '.fid="20260101-other"' "$_RA/receipt.base" > "$_rn_rcpt"
_rn_expect "TR-N2a receipt fid 불일치" 1 "fid/task mismatch" -- "$_rn_fid" T1
jq '.task="T2"' "$_RA/receipt.base" > "$_rn_rcpt"
_rn_expect "TR-N2b receipt task 불일치" 1 "fid/task mismatch" -- "$_rn_fid" T1
_rn_restore

# receipt 가 symlink — 유효한 receipt 를 가리켜도 거부 (-f 는 symlink 를 따라가므로 -L 분기가 유일한 방어)
mv "$_rn_rcpt" "$_RA/real.json"
ln -s "$_RA/real.json" "$_rn_rcpt"
_rn_expect "TR-N3 receipt symlink" 1 "symlink" -- "$_rn_fid" T1
_rn_restore

# tasks.md 부재
rm -f "$_rn_tasks"
_rn_expect "TR-N4 tasks.md 부재" 1 "tasks.md 부재" -- "$_rn_fid" T1
_rn_restore

# tasks.md 에 해당 태스크의 test_command 없음
grep -v 'test_command' "$_RA/tasks.base" > "$_rn_tasks"
_rn_expect "TR-N5 test_command 없음" 1 "test_command 없음" -- "$_rn_fid" T1
_rn_restore

# staged 공집합
(cd "$_RN" && git reset -q) >/dev/null 2>&1
_rn_expect "TR-N6 staged 공집합" 1 "staged empty" -- "$_rn_fid" T1
(cd "$_RN" && git add src scripts) >/dev/null 2>&1

# outputs 공집합 (staged 는 비어있지 않다)
jq '.outputs=[]' "$_RA/receipt.base" > "$_rn_rcpt"
_rn_expect "TR-N7 outputs 공집합" 1 "outputs empty" -- "$_rn_fid" T1
_rn_restore

# receipt jq 파싱 실패 — 깨진 JSON (verdict 줄에서 걸린다)
printf 'not json{' > "$_rn_rcpt"
_rn_expect "TR-N8a receipt 파싱 실패(깨진 JSON)" 1 "" -- "$_rn_fid" T1
_rn_restore

# jq 가 .fid / .task 필터에서만 실패하는 shim — 25·26행의 `|| exit 1` 을 각각 따로 잠근다
#   (깨진 JSON 은 24행에서 먼저 걸려 25·26행 변이가 생존한다)
_rn_shim="$_RA/shim"; mkdir -p "$_rn_shim"
cat > "$_rn_shim/jq" <<SHIM
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "\${JQ_FAIL_FILTER:-}" ] && exit 5; done
exec "$(command -v jq)" "\$@"
SHIM
chmod +x "$_rn_shim/jq"
_rn_err=$(cd "$_RN" && PATH="$_rn_shim:$PATH" JQ_FAIL_FILTER='.fid // empty' bash "$CHK" "$_rn_fid" T1 2>&1 >/dev/null); _rn_rc=$?
[ "$_rn_rc" = "1" ] && ok "TR-N8b jq(.fid) 실패 → rc=1" || nope "TR-N8b" "rc=$_rn_rc err=$_rn_err"
_rn_err=$(cd "$_RN" && PATH="$_rn_shim:$PATH" JQ_FAIL_FILTER='.task // empty' bash "$CHK" "$_rn_fid" T1 2>&1 >/dev/null); _rn_rc=$?
[ "$_rn_rc" = "1" ] && ok "TR-N8c jq(.task) 실패 → rc=1" || nope "TR-N8c" "rc=$_rn_rc err=$_rn_err"
# shim 대조 — 필터가 안 맞으면 shim 은 무해하고 rc=0 이어야 한다(shim 이 항상 실패시켜 가짜 통과하는 것을 방지)
_rn_err=$(cd "$_RN" && PATH="$_rn_shim:$PATH" JQ_FAIL_FILTER='.없는필터' bash "$CHK" "$_rn_fid" T1 2>&1 >/dev/null); _rn_rc=$?
[ "$_rn_rc" = "0" ] && ok "TR-N8d shim 대조(무관 필터) → rc=0" || nope "TR-N8d" "rc=$_rn_rc err=$_rn_err"

# 입력 형식 오류 / 인자 부재 → rc 2 (legacy fallthrough)
_rn_expect "TR-N9a FID 형식 오류" 2 "" -- "BAD_FID" T1
_rn_expect "TR-N9b TASK 형식 오류" 2 "" -- "$_rn_fid" "bad task!"
_rn_expect "TR-N9c 인자 전무" 2 "usage" --
_rn_expect "TR-N9d TASK 인자 부재" 2 "usage" -- "$_rn_fid"
_rn_expect "TR-N9e FID 빈 문자열" 2 "usage" -- "" T1
rm -rf "$_RN" "$_RA"

# ── TR-Q quick 경로 — 명세 없는 FID 는 영수증이 유효해도 범위·리뷰를 본다 (20261010-quick-fix-path) ──
# 왜: "태스크 문서는 있고 명세는 없는 FID" 는 영수증만 유효하면 rc 0 이었다 — 문서도 리뷰도 크기 상한도 없는 통로다.
#   그 구조가 곧 quick 경로다. 판정은 quick-scope.sh 가 하고(test-quick-fix.sh 가 잰다), 여기서는 검사기의 종료 코드 계약만 잠근다.
_RQ=$(mktemp -d) || exit 1
_rq_fid=20261010-quick
_setup_fid "$_RQ" "$_rq_fid"; rm -f "$_RQ/.specops/$_rq_fid/spec.md"      # 명세 없음 = quick 구조
_rq_rev() { mkdir -p "$_RQ/.specops/$_rq_fid/reviews"; printf '# 코드 품질 리뷰\n' > "$_RQ/.specops/$_rq_fid/reviews/T1-C-report.md"; }
printf 'updated\n' > "$_RQ/src/foo.sh"
(cd "$_RQ" && git add src && bash "$REC" "$_rq_fid" T1) >/dev/null 2>&1
(cd "$_RQ" && bash "$CHK" "$_rq_fid" T1) >/dev/null 2>&1; _rq_rc=$?
[ "$_rq_rc" = 4 ] && ok "TR-Q1 quick FID · 유효 영수증 · 리뷰 보고서 없음 → rc 4" || nope "TR-Q1" "rc=$_rq_rc (4 여야 한다)"
_rq_rev
(cd "$_RQ" && bash "$CHK" "$_rq_fid" T1) >/dev/null 2>&1; _rq_rc=$?
[ "$_rq_rc" = 0 ] && ok "TR-Q2 quick FID · 범위 안 + 통과 리뷰 → rc 0" || nope "TR-Q2" "rc=$_rq_rc"
# 판정기를 실행할 수 없으면 막는 쪽이다(NFR-3) — 판정기만 뺀 사본의 검사기로 방금 rc 0 이던 영수증을 다시 본다
_RQP=$(mktemp -d) || exit 1
mkdir -p "$_RQP/scripts" && cp -R "$PLUGIN/scripts/dag" "$PLUGIN/scripts/_internal" "$_RQP/scripts/" && rm -f "$_RQP/scripts/_internal/quick-scope.sh"
(cd "$_RQ" && bash "$_RQP/scripts/_internal/check-task-receipt.sh" "$_rq_fid" T1) >/dev/null 2>&1; _rq_rc=$?
[ "$_rq_rc" = 3 ] && ok "TR-Q5 판정기를 실행할 수 없으면 rc 3 (판정 불가는 통과가 아니다)" || nope "TR-Q5" "rc=$_rq_rc (3 이어야 한다)"
rm -rf "$_RQP"
{ _i=0; while [ "$_i" -lt 25 ]; do echo "line $_i"; _i=$((_i + 1)); done; } > "$_RQ/src/foo.sh"
(cd "$_RQ" && git add src && bash "$REC" "$_rq_fid" T1) >/dev/null 2>&1; _rq_rev
(cd "$_RQ" && bash "$CHK" "$_rq_fid" T1) >/dev/null 2>&1; _rq_rc=$?
[ "$_rq_rc" = 3 ] && ok "TR-Q3 quick FID · 유효 영수증 · 변경 26줄 → rc 3 (범위 초과)" || nope "TR-Q3" "rc=$_rq_rc (3 이어야 한다)"
printf '# spec\n' > "$_RQ/.specops/$_rq_fid/spec.md"                        # 명세가 생기면 정식 FID 다
(cd "$_RQ" && bash "$CHK" "$_rq_fid" T1) >/dev/null 2>&1; _rq_rc=$?
[ "$_rq_rc" = 0 ] && ok "TR-Q4 같은 영수증 · 명세 있음(정식 FID) → rc 0 (범위·리뷰를 보지 않는다)" || nope "TR-Q4" "rc=$_rq_rc"
rm -rf "$_RQ"

finish
