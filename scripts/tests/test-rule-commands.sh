#!/usr/bin/env bash
# 헌법 판정 명령 실행 — check-rule-commands.sh + run-verification 경고 배선 (20261015-verify-rule-commands)
#
# 판정 `명령` 규칙을 테스트 명령과 같은 허용 형식 안에서만 실행하고(셸 해석 없이), 결과를 규칙마다 내며,
# 검증 단계에는 경고로만 붙는다(VERIFY 판정·종료 코드 불변). "없음"과 "판정 불가"를 섞지 않는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CRC="$PLUGIN/scripts/_internal/check-rule-commands.sh"
RV="$PLUGIN/scripts/_internal/run-verification.sh"
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

_repo() {  # $1=dir — 규칙이 부를 스크립트들
  mkdir -p "$1/.specops/memory" "$1/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/scripts/ok.sh"
  printf '#!/usr/bin/env bash\npwd\nfor i in $(seq 1 12); do echo "line$i"; done\nexit 3\n' > "$1/scripts/bad.sh"
  printf '#!/usr/bin/env bash\nsleep 5\n' > "$1/scripts/slow.sh"
  printf '#!/usr/bin/env bash\ntouch MARK\n' > "$1/scripts/mark.sh"
  printf '#!/usr/bin/env bash\ncat >/dev/null\n' > "$1/scripts/eat.sh"
}
_rules() {  # $1=dir · stdin = 규칙 행들
  { printf '# 헌법\n\n## 구조 규칙\n\n<!-- structure-rules:start -->\n| ID | 규칙 | 적용 경로 | 판정 | 판정 명령 |\n|---|---|---|---|---|\n'
    cat
    printf '<!-- structure-rules:end -->\n'
  } > "$1/.specops/memory/constitution.md"
}

# C1 (AC-2): 허용 형식 판정 명령이 실행되고 규칙마다 결과 · 리뷰 규칙은 줄 없음 · rc 1
D="$ROOT/c1"; _repo "$D"
_rules "$D" <<'EOF'
| S-1 | 통과 | `scripts/` | 명령 | `bash scripts/ok.sh` |
| S-2 | 위반 | `scripts/` | 명령 | `bash scripts/bad.sh` |
| S-3 | 리뷰만 | `scripts/` | 리뷰 | - |
EOF
out=$(cd "$D" && bash "$CRC" 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qx 'RULE S-1: PASS' && printf '%s\n' "$out" | grep -qx 'RULE S-2: FAIL (rc=3)' \
  && ! printf '%s\n' "$out" | grep -q '^RULE S-3' && printf '%s\n' "$out" | grep -qx 'RULE-COMMANDS: PASS 1 · FAIL 1 · TIMEOUT 0 · SKIP 0'; } \
  && ok "C1 규칙마다 PASS/FAIL · 리뷰 규칙 제외 · 요약 · rc 1" || nope "C1" "rc=$rc out=$out"

# C1b (AC-2): 명령이 표준 입력을 읽어도 뒤 규칙이 사라지지 않는다 — 규칙마다 결과가 나온다
D="$ROOT/c1b"; _repo "$D"
_rules "$D" <<'EOF'
| S-1 | 입력 먹기 | `scripts/` | 명령 | `bash scripts/eat.sh` |
| S-2 | 통과 | `scripts/` | 명령 | `bash scripts/ok.sh` |
| S-3 | 위반 | `scripts/` | 명령 | `bash scripts/bad.sh` |
EOF
out1b=$(cd "$D" && bash "$CRC" 2>&1); rc=$?
{ [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out1b" | grep -c '^RULE S-[1-3]: ')" -eq 3 ] \
  && printf '%s\n' "$out1b" | grep -qx 'RULE-COMMANDS: PASS 2 · FAIL 1 · TIMEOUT 0 · SKIP 0'; } \
  && ok "C1b 표준 입력을 읽는 명령 뒤 규칙도 실행·집계" || nope "C1b" "rc=$rc out=$out1b"

# C2 (AC-8): 검증을 부른 폴더에서 실행 · FAIL 아래 명령 출력은 10줄까지
first=$(printf '%s\n' "$out" | awk '/^RULE S-2:/{f=1;next} f&&/^  /{sub(/^  /,""); print; exit}')
n=$(printf '%s\n' "$out" | awk '/^RULE S-2:/{f=1;next} /^RULE/{f=0} f&&/^  /{c++} END{print c+0}')
{ [ "$first" = "$ROOT/c1" ] && [ "$n" -eq 10 ]; } && ok "C2 실행 위치 = 부른 폴더 · 출력 10줄 상한" || nope "C2" "first=$first n=$n"

# C3 (AC-3): 허용 목록 밖은 실행하지 않는다 — 표지 파일이 생기지 않는다
D="$ROOT/c3"; _repo "$D"
_rules "$D" <<'EOF'
| S-4 | 목록 밖 | `scripts/` | 명령 | `touch MARK` |
| S-5 | 상위 경로 | `scripts/` | 명령 | `bash scripts/../scripts/mark.sh` |
| S-6 | 부정 grep | `scripts/` | 명령 | `! grep -rq x scripts` |
| S-7 | poetry 린트 | `scripts/` | 명령 | `poetry run ruff check scripts` |
EOF
out=$(cd "$D" && bash "$CRC" 2>&1); rc=$?
s=$(printf '%s\n' "$out" | grep -c '^RULE S-[4-7]: SKIP — 허용 목록 밖')
{ [ "$rc" -eq 1 ] && [ "$s" -eq 4 ] && [ ! -e "$D/MARK" ] && printf '%s\n' "$out" | grep -q 'bash scripts/tests/test-structure.sh S-4' \
  && printf '%s\n' "$out" | grep -qx 'RULE-COMMANDS: PASS 0 · FAIL 0 · TIMEOUT 0 · SKIP 4'; } \
  && ok "C3 목록 밖 4건 SKIP · 실행 안 됨(MARK 없음) · 안내 · rc 1" || nope "C3" "rc=$rc skip=$s mark=$([ -e "$D/MARK" ] && echo y) out=$out"

# C4 (AC-4): 시간 상한을 넘으면 TIMEOUT — 수 초 안에 끝난다
D="$ROOT/c4"; _repo "$D"
_rules "$D" <<'EOF'
| S-8 | 느림 | `scripts/` | 명령 | `bash scripts/slow.sh` |
EOF
t0=$SECONDS; out=$(cd "$D" && SPECOPS_RULE_CMD_TIMEOUT=1 bash "$CRC" 2>&1); rc=$?; el=$((SECONDS - t0))
{ [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qx 'RULE S-8: TIMEOUT (1초)' && [ "$el" -lt 5 ]; } \
  && ok "C4 상한 초과 TIMEOUT · ${el}초" || nope "C4" "rc=$rc el=$el out=$out"

# C5 (AC-5): 해당 없음(헌법 없음 · 절 없음 · 리뷰만) rc 0 / 판정 불가(표 형식 위반) rc 2
D="$ROOT/c5a"; mkdir -p "$D"; out_a=$(cd "$D" && bash "$CRC" 2>&1); rc_a=$?
D="$ROOT/c5b"; mkdir -p "$D/.specops/memory"; echo '# 헌법' > "$D/.specops/memory/constitution.md"; out_b=$(cd "$D" && bash "$CRC" 2>&1); rc_b=$?
D="$ROOT/c5c"; _repo "$D"; printf '| S-1 | 리뷰 | `a/` | 리뷰 | - |\n' | _rules "$D"; out_c=$(cd "$D" && bash "$CRC" 2>&1); rc_c=$?
D="$ROOT/c5d"; mkdir -p "$D/.specops/memory"; printf '# h\n<!-- structure-rules:start -->\n| ID | 규칙 |\n<!-- structure-rules:end -->\n' > "$D/.specops/memory/constitution.md"
out_d=$(cd "$D" && bash "$CRC" 2>&1); rc_d=$?
{ [ "$rc_a" -eq 0 ] && [ "$rc_b" -eq 0 ] && [ "$rc_c" -eq 0 ] && [ "$rc_d" -eq 2 ] \
  && printf '%s' "$out_a" | grep -q '^RULE-COMMANDS: 해당 없음' && printf '%s' "$out_b" | grep -q '^RULE-COMMANDS: 해당 없음' \
  && printf '%s' "$out_c" | grep -q '^RULE-COMMANDS: 해당 없음' && printf '%s' "$out_d" | grep -q '^RULE-COMMANDS: 판정 불가'; } \
  && ok "C5 해당 없음 3종 rc 0 · 판정 불가 rc 2" || nope "C5" "rc=$rc_a/$rc_b/$rc_c/$rc_d d=$out_d"

# C6 (AC-1): 허용 패턴은 run-verification 의 한 줄에서 읽는다 — 복제 없음 · 못 읽으면 하나도 실행하지 않고 판정 불가
{ ! grep -q '^_WHITELIST_PAT=' "$CRC" && grep -qF "grep -m1 '^_WHITELIST_PAT='" "$CRC" && [ "$(grep -c '^_WHITELIST_PAT=' "$RV")" -eq 1 ]; } \
  && ok "C6.a 패턴 정의는 run-verification 한 줄뿐 · 검사기는 추출" || nope "C6.a" "정의 복제 또는 추출 줄 없음"
CP="$ROOT/cp/scripts/_internal"; mkdir -p "$CP"
cp "$CRC" "$PLUGIN/scripts/_internal/check-constitution-rules.sh" "$PLUGIN/scripts/_internal/run-bounded.sh" "$CP/"
D="$ROOT/c6"; _repo "$D"; printf '| S-1 | 표지 | `scripts/` | 명령 | `bash scripts/mark.sh` |\n' | _rules "$D"
out=$(cd "$D" && bash "$CP/check-rule-commands.sh" 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '^RULE-COMMANDS: 판정 불가 (허용 패턴' && [ ! -e "$D/MARK" ]; } \
  && ok "C6.b 패턴을 못 읽으면 실행 0건 · 판정 불가 rc 2" || nope "C6.b" "rc=$rc mark=$([ -e "$D/MARK" ] && echo y) out=$out"
# C6.d: 패턴 줄 형태가 바뀌어(큰따옴표) 추출이 따옴표를 남기면 — "목록 밖" 이 아니라 판정 불가 · 실행 0건
sed "s/^_WHITELIST_PAT='\\(.*\\)'\$/_WHITELIST_PAT=\"\\1\"/" "$RV" > "$CP/run-verification.sh"
out=$(cd "$D" && bash "$CP/check-rule-commands.sh" 2>&1); rc=$?
{ grep -q '^_WHITELIST_PAT="' "$CP/run-verification.sh" && [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '^RULE-COMMANDS: 판정 불가 (허용 패턴 형태' && [ ! -e "$D/MARK" ]; } \
  && ok "C6.d 패턴 형태 변경 → 판정 불가 rc 2 · 실행 0건" || nope "C6.d" "rc=$rc out=$out"
rm -f "$CP/run-verification.sh"
D="$ROOT/c6c"; _repo "$D"; printf '| S-1 | pytest | `t/` | 명령 | `pytest -q` |\n' | _rules "$D"
out=$(cd "$D" && bash "$CRC" 2>&1)
printf '%s\n' "$out" | grep -E '^RULE S-1: ' | grep -qv 'SKIP' && ok "C6.c 허용 형식(pytest)은 실행된다(SKIP 아님)" || nope "C6.c" "$out"

# C7 (변이): `..` 가드를 지운 사본은 상위 경로 명령을 실행한다 — 가드가 살아 있음을 확인
MP="$ROOT/mut/scripts/_internal"; mkdir -p "$MP"
cp "$PLUGIN/scripts/_internal/check-constitution-rules.sh" "$PLUGIN/scripts/_internal/run-bounded.sh" "$RV" "$MP/"
sed 's/ || \[\[ "\$cmd" == \*\.\.\* \]\]//' "$CRC" > "$MP/check-rule-commands.sh"
D="$ROOT/c7"; _repo "$D"; printf '| S-5 | 상위 경로 | `scripts/` | 명령 | `bash scripts/../scripts/mark.sh` |\n' | _rules "$D"
(cd "$D" && bash "$MP/check-rule-commands.sh" >/dev/null 2>&1)
{ ! cmp -s "$CRC" "$MP/check-rule-commands.sh" && [ -e "$D/MARK" ]; } && ok "C7 변이 적발 — 가드 없으면 실행됨" || nope "C7" "변이 sed 실패 또는 가드 무관"

# C8 (AC-6·AC-8): run-verification 에 경고로만 붙는다 — 판정 줄·rc 불변 · evidence 절 · 경고는 규칙당 3줄
_vrepo() {  # $1=dir $2=fid — 테스트 명령이 통과하는 FID 를 가진 git 저장소
  _repo "$1"; mkdir -p "$1/.specops/$2" "$1/scripts/tests"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/scripts/tests/dummy.sh"; chmod +x "$1/scripts/tests/dummy.sh"
  printf -- '- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy.sh`\n' > "$1/.specops/$2/tasks.md"
  ( cd "$1" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
}
VF=20261015-x
D="$ROOT/c8"; _vrepo "$D" "$VF"; printf '| S-1 | 위반 | `scripts/` | 명령 | `bash scripts/bad.sh` |\n' | _rules "$D"
out=$(cd "$D" && bash "$RV" "$VF" 2>"$ROOT/c8.err"); rc=$?; err=$(cat "$ROOT/c8.err")
ev="$D/.specops/$VF/evidence.md"
nerr=$(printf '%s\n' "$err" | awk '/^RULE S-1:/{f=1;next} /^RULE/{f=0} f&&/^  /{c++} END{print c+0}')
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] \
  && grep -qx '### structure-rule-commands' "$ev" && grep -qx 'RULE S-1: FAIL (rc=3)' "$ev" \
  && printf '%s\n' "$err" | grep -q '^WARN: 구조 규칙 판정 명령' && [ "$nerr" -eq 3 ]; } \
  && ok "C8 VERIFY: PASS·rc 0 그대로 · evidence 절 · 경고 + 출력 3줄" || nope "C8" "rc=$rc nerr=$nerr out=$out err=$err"

# C9 (AC-R-1): 헌법이 없으면 경고 없이 판정 그대로 — evidence 에 해당 없음 한 줄
D="$ROOT/c9"; _vrepo "$D" "$VF"; rm -f "$D/.specops/memory/constitution.md"
out=$(cd "$D" && bash "$RV" "$VF" 2>"$ROOT/c9.err"); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && ! grep -q '구조 규칙 판정 명령' "$ROOT/c9.err" \
  && grep -q '^RULE-COMMANDS: 해당 없음' "$D/.specops/$VF/evidence.md"; } \
  && ok "C9 규칙 없음 — 판정 그대로 · 경고 없음 · evidence 해당 없음" || nope "C9" "rc=$rc out=$out"

# C10 (AC-7): 헌법 템플릿 — 검증 때 실행 · 허용 형식 · 예시 명령이 허용 형식 · 템플릿이 형식 검사를 통과
TPL="$PLUGIN/templates/constitution.md"
{ grep -qF '판정 `명령` 은 검증(verify) 때 실행된다' "$TPL" && grep -qF '테스트 명령과 같은 허용 형식만 실행' "$TPL" \
  && grep -qF '| 명령 | `bash scripts/tests/test-structure.sh S-2` |' "$TPL" && ! grep -qF 'make check-clock' "$TPL" \
  && bash "$PLUGIN/scripts/_internal/check-constitution-rules.sh" "$TPL" >/dev/null 2>&1; } \
  && ok "C10 템플릿 실행 안내 · 예시 허용 형식 · 형식 통과" || nope "C10" "templates/constitution.md 미갱신"

# C11 (AC-7): 검증 스킬 체크리스트가 판정 명령 결과를 보고하게 한다
SK="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
{ grep -qF 'check-rule-commands.sh' "$SK" && grep -qF '### structure-rule-commands' "$SK"; } \
  && ok "C11 검증 스킬 체크리스트 항목" || nope "C11" "verifying-evidence-ko 미갱신"

finish
