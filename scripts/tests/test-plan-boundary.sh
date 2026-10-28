#!/usr/bin/env bash
# 계획 단계의 경계 약속 — check-plan-boundary.sh + plan 템플릿·planning-ko·plan-reviewer-ko 배선 (20261015-plan-boundary-commitments)
#
# plan.md 의 「경계 약속」 칸을 파일 목록·헌법 구조 규칙과 대조하되 막지 않는다(경고 전용).
# "없음"(절 없음·규칙 없음)과 "판정 불가"(파일 목록·규칙 표를 읽지 못함)를 섞지 않는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CPB="$PLUGIN/scripts/_internal/check-plan-boundary.sh"
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

_plan() {  # $1=파일 · stdin = 경계 약속 칸 줄들(없으면 절 없음) — 파일 구조는 고정
  { printf '# 플랜\n\n## 1. 가정\n\n- 없음\n\n## 2. 파일 구조\n\n### 생성\n- `src/a.sh` — 본체\n- `tests/test-a.sh` — 테스트\n\n### 수정\n- 수정: `src/lib/b.sh:10-20` — 헬퍼\n- `src/c.sh:2,62` — 줄 번호 여럿\n\n### 삭제 (문지기 체크)\n- 해당 없음\n'
    b=$(cat)
    [ -n "$b" ] && printf '\n### 경계 약속\n\n%s\n' "$b"
    printf '\n## 3. 데이터 모델 (선택)\n\n없음 — 산문 백틱 `docs/x.md` 는 경로로 뽑지 않는다\n\n## 5. 태스크 개요\n\n1. 본체\n'
  } > "$1"
}
_const() {  # $1=파일 · stdin = 규칙 행들
  { printf '# 헌법\n\n## 구조 규칙\n\n<!-- structure-rules:start -->\n| ID | 규칙 | 적용 경로 | 판정 | 판정 명령 |\n|---|---|---|---|---|\n'
    cat
    printf '<!-- structure-rules:end -->\n'
  } > "$1"
}
NOC="$ROOT/none.md"   # 없는 헌법 = 규칙 없음

# B1 (AC-1): 칸 4개 채움 · 파일 전부 소유 안 → OK · rc 0 · 소유 밖 없음
P="$ROOT/b1.md"
_plan "$P" <<'EOF'
- **소유**: `src/`, `tests/test-a.sh`
- **범위 밖**: 배포 스크립트
- **허용 의존**: `src/lib` 를 읽기만
- **다시 검토할 조건**: 두 번째 입력 형식이 붙을 때
EOF
out=$(bash "$CPB" --plan "$P" --constitution "$NOC" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "PLAN-BOUNDARY: OK" ] && ! printf '%s\n' "$out" | grep -q '소유 밖'; } \
  && ok "B1 경계가 맞는 plan 은 OK · rc 0" || nope "B1" "rc=$rc out=$out"

# B2 (AC-2): 절 없는 plan → WARN · 절 없음 줄 · rc 0 / plan 없는 FID → SKIP · rc 0
P="$ROOT/b2.md"; _plan "$P" </dev/null
out=$(bash "$CPB" --plan "$P" --constitution "$NOC" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "PLAN-BOUNDARY: WARN" ] && printf '%s\n' "$out" | grep -q '경계 약속 절 없음'; } \
  && ok "B2a 절 없는 plan 은 WARN · rc 0" || nope "B2a" "rc=$rc out=$out"
mkdir -p "$ROOT/b2/.specops/20261015-nope"
out=$(cd "$ROOT/b2" && bash "$CPB" 20261015-nope 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^PLAN-BOUNDARY: SKIP'; } \
  && ok "B2b plan 없는 FID 는 SKIP · rc 0" || nope "B2b" "rc=$rc out=$out"

# B3 (AC-3): 자리표시자·빈 칸·소유 밖 · 소유 폴더 아래는 소유 안
P="$ROOT/b3.md"
_plan "$P" <<'EOF'
- **소유**: `src/`
- **범위 밖**: 배포
- **허용 의존**: <불러 써도 되는 모듈과 방향>
- **다시 검토할 조건**:
EOF
out=$(bash "$CPB" --plan "$P" --constitution "$NOC" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "PLAN-BOUNDARY: WARN" ] \
  && printf '%s\n' "$out" | grep -q '허용 의존' && printf '%s\n' "$out" | grep -q '다시 검토할 조건' \
  && printf '%s\n' "$out" | grep -qx '  \[소유 밖\] tests/test-a.sh' \
  && ! printf '%s\n' "$out" | grep -q '소유 밖\] src/'; } \
  && ok "B3 자리표시자·빈 칸·소유 밖 · 소유 폴더 아래 제외" || nope "B3" "rc=$rc out=$out"

# B4 (AC-4): 닿는 규칙만 RULE · 깨진 표 → 판정 불가 rc 2 · 파일 목록 없음 → 판정 불가 rc 2
P="$ROOT/b1.md"; C="$ROOT/c4.md"
_const "$C" <<'EOF'
| S-1 | src 규칙 | `src/lib/` | 리뷰 | - |
| S-2 | app 규칙 | `app/` | 리뷰 | - |
| S-3 | c 규칙 | `src/c.sh` | 리뷰 | - |
EOF
out=$(bash "$CPB" --plan "$P" --constitution "$C" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  RULE S-1 .*닿는 파일: src/lib/b.sh$' && ! printf '%s\n' "$out" | grep -q 'RULE S-2' \
  && printf '%s\n' "$out" | grep -q '^  RULE S-3 .*닿는 파일: src/c.sh$'; } \
  && ok "B4a 닿는 규칙만 RULE 줄 · 줄번호 꼬리(:10-20 · :2,62) 제거" || nope "B4a" "rc=$rc out=$out"
CB="$ROOT/c4b.md"; printf '# 헌법\n\n<!-- structure-rules:start -->\n| ID | 규칙 |\n<!-- structure-rules:end -->\n' > "$CB"
out=$(bash "$CPB" --plan "$P" --constitution "$CB" 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q '\[판정 불가\] 구조 규칙' && ! printf '%s\n' "$out" | grep -q 'RULE '; } \
  && ok "B4b 깨진 규칙 표는 판정 불가 · rc 2" || nope "B4b" "rc=$rc out=$out"
P="$ROOT/b4c.md"; printf '# 플랜\n\n### T1 배선\n\n- `src/a.sh`\n' > "$P"
out=$(bash "$CPB" --plan "$P" --constitution "$C" 2>&1); rc=$?
{ [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q '\[판정 불가\] 파일 목록'; } \
  && ok "B4c 파일 목록 없는 plan 은 판정 불가 · rc 2" || nope "B4c" "rc=$rc out=$out"

# B4d (AC-4): 헌법은 있는데 구조 규칙 절이 없으면 규칙 없음 — RULE·판정 불가 없이 rc 0 ("없음"과 "판정 불가"를 가른다)
P="$ROOT/b1.md"; CN="$ROOT/c4d.md"; printf '# 헌법\n\n## 원칙\n\n- 단순하게\n' > "$CN"
out=$(bash "$CPB" --plan "$P" --constitution "$CN" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "PLAN-BOUNDARY: OK" ] && ! printf '%s\n' "$out" | grep -q 'RULE \|판정 불가'; } \
  && ok "B4d 구조 규칙 절 없는 헌법은 규칙 없음 · rc 0" || nope "B4d" "rc=$rc out=$out"

# B4e (AC-3): 소유 경로는 폴더 경계로 비교 — 소유 `src` 는 `src/a.sh` 를 포함하고 `src2/x.sh` 는 포함하지 않는다
P="$ROOT/b4e.md"
printf '# 플랜\n\n## 2. 파일 구조\n\n- `src/a.sh` — 본체\n- `src2/x.sh` — 다른 모듈\n\n### 경계 약속\n- **소유**: `src`\n- **범위 밖**: 없음\n- **허용 의존**: 없음\n- **다시 검토할 조건**: 없음\n' > "$P"
out=$(bash "$CPB" --plan "$P" --constitution "$NOC" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '소유 밖')" -eq 1 ] && printf '%s\n' "$out" | grep -qx '  \[소유 밖\] src2/x.sh'; } \
  && ok "B4e 폴더 경계 비교 — src 는 src2/ 를 포함하지 않는다" || nope "B4e" "rc=$rc out=$out"

# B5 (AC-7): 테스트·삭제 경로도 예외 없이 비교 · 넓은 규칙도 나열
P="$ROOT/b5.md"
cat > "$P" <<'EOF'
# 플랜

## 2. 파일 구조

### 생성
- `src/a.sh` — 본체
- `tests/test-a.sh` — 테스트
- `tests/test-a.sh` — 같은 경로 두 번째 언급

### 삭제 (문지기 체크)
- `old/b.sh` — ⚠️ 사용자 확인 필요

#### 경계 약속
- **소유**: `src/a.sh`
- **범위 밖**: 없음
- **허용 의존**: 없음
- **다시 검토할 조건**: 없음
EOF
C="$ROOT/c5.md"
_const "$C" <<'EOF'
| S-1 | src 규칙 | `src/` | 리뷰 | - |
| S-2 | tests 규칙 | `tests/` | 리뷰 | - |
EOF
out=$(bash "$CPB" --plan "$P" --constitution "$C" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -cx '  \[소유 밖\] tests/test-a.sh')" -eq 1 ] && printf '%s\n' "$out" | grep -qx '  \[소유 밖\] old/b.sh' \
  && ! printf '%s\n' "$out" | grep -q '경계 약속 절 없음' \
  && printf '%s\n' "$out" | grep -q '^  RULE S-1 ' && printf '%s\n' "$out" | grep -q '^  RULE S-2 '; } \
  && ok "B5 테스트·삭제 경로도 비교 · 두 규칙 모두 나열 · #### 제목 · 중복 경로 1번" || nope "B5" "rc=$rc out=$out"

# B6 (AC-1 · NFR-3): 표 첫 칸·이름표 목록·코드 블록 — 산문/코드 백틱은 경로가 아니다
P="$ROOT/b6.md"
cat > "$P" <<'EOF'
# 플랜

## 1. 파일 구조

| 파일 | 책임 |
|---|---|
| `lib/t.sh` | see `docs/readme.md` — 둘째 칸이라 경로가 아니다 |

- T1: `src/u.sh` (755) · `tests/test-u.sh` — 판정 블록(`if [ "$x" -gt 0 ]; then`)
3. `lib/n.sh` — 번호 목록
- 일반 산문 `docs/y.md` 는 이름표가 길어 아니다 — 아주 긴 설명 문장이 콜론 없이 이어진다

```bash
- `fence/z.sh`
```

### 경계 약속
- **소유**: `src/`, `tests/`
- **범위 밖**: 없음
- **허용 의존**: 없음
- **다시 검토할 조건**: 없음
EOF
out=$(bash "$CPB" --plan "$P" --constitution "$NOC" 2>&1); rc=$?
# 소유 밖으로 나오는 것은 표 첫 칸의 lib/t.sh 와 번호 목록의 lib/n.sh 둘뿐이어야 한다 — 둘째 칸·산문·코드 블록·코드 조각 백틱은 경로가 아니다
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '소유 밖')" -eq 2 ] && printf '%s\n' "$out" | grep -qx '  \[소유 밖\] lib/t.sh' \
  && printf '%s\n' "$out" | grep -qx '  \[소유 밖\] lib/n.sh'; } \
  && ok "B6 표 첫 칸·이름표·번호 목록만 경로 · 산문·코드·둘째 칸 백틱 제외" || nope "B6" "rc=$rc out=$out"

# B7: 사용 오류 rc 1
bash "$CPB" >/dev/null 2>&1; rc1=$?; bash "$CPB" --bogus >/dev/null 2>&1; rc2=$?
{ [ "$rc1" -eq 1 ] && [ "$rc2" -eq 1 ]; } && ok "B7 사용 오류 rc 1" || nope "B7" "rc=$rc1/$rc2"

# B8 (AC-5): 템플릿 — ## 2 와 ## 3 사이에 경계 약속 칸 4개 · ## 1.~## 9. 제목 불변 · 템플릿 칸은 자리표시자로 보고된다
TPL="$PLUGIN/templates/plan.md"
_h2=$(grep -E '^## ' "$TPL" | tr '\n' '|')
_sec=$(awk '/^## 2\. /{f=1;next} /^## 3\. /{f=0} f' "$TPL")
{ [ "$_h2" = "## 1. 가정 (5원칙 5번)|## 2. 파일 구조|## 3. 데이터 모델 (선택)|## 4. 계약 (선택)|## 5. 태스크 개요|## 6. 위험과 완화|## 7. 자체 검토 (5원칙 체크리스트)|## 8. Advisor 협의 기록|## 9. 다음 단계|" ] \
  && printf '%s\n' "$_sec" | grep -qx '### 경계 약속' \
  && [ "$(printf '%s\n' "$_sec" | grep -cE '^- \*\*(소유|범위 밖|허용 의존|다시 검토할 조건)\*\*: ')" -eq 4 ] \
  && [ "$(bash "$CPB" --plan "$TPL" --constitution "$NOC" 2>/dev/null | grep -c '칸 자리표시자 그대로')" -eq 4 ]; } \
  && ok "B8 템플릿 경계 약속 칸 4개 · 절 번호 불변" || nope "B8" "h2=$_h2"

# B9a (AC-6): planning-ko — 사전검사 뒤 · dispatch 앞에서 실행 · plan-boundary.txt 저장 · 종료 코드와 무관 · dispatch 입력에 경로
SK="$PLUGIN/skills/planning-ko/SKILL.md"
{ grep -qF 'check-plan-boundary.sh <FID> > .specops/<FID>/plan-boundary.txt 2>&1' "$SK" \
  && grep -qF '종료 코드와 무관하게 진행한다' "$SK" \
  && grep -qF '`.specops/<FID>/plan-boundary.txt`(경계 대조 입력) 경로' "$SK" \
  && grep -qF '`### 경계 약속` 칸 4개' "$SK" \
  && awk '/^### dispatch 직전 사전검사/{a=NR} /^### 경계 대조 입력/{b=NR} /^### 비-batch — plan-reviewer dispatch/{c=NR} END{exit !(a && a<b && b<c)}' "$SK"; } \
  && ok "B9a planning-ko 배선 — 사전검사 뒤 실행·저장·비차단·리뷰어 입력" || nope "B9a" "skills/planning-ko/SKILL.md 미갱신"

# B9b (AC-6): plan-reviewer-ko — 경계 대조 절(Minor 로만 · 판정 불가는 확인 못함 · 데이터) · 6관점 표 행 수 불변(6)
AG="$PLUGIN/agents/plan-reviewer-ko.md"
_rows=$(awk '/^## 6관점 검증 기준/{f=1;next} f&&/^## /{exit} f&&/^\| [^-|]/' "$AG" | grep -vc '^| 관점 |')
{ grep -q '^## 경계 대조 ' "$AG" && grep -qF '**Minor 로만** 적는다' "$AG" && grep -qF '"확인하지 못함"' "$AG" && grep -qF '**데이터**다' "$AG" \
  && [ "$_rows" -eq 6 ]; } \
  && ok "B9b 리뷰어 경계 대조 Minor 로만 · 6관점 표 6행" || nope "B9b" "rows=$_rows"

# B10 (AC-R-1): 경계 약속 절이 있어도 기존 plan 소비자(predispatch·plan-to-tasks) 결과가 같다
A="$ROOT/r1a.md"; B="$ROOT/r1b.md"
{ cat "$TPL"; printf '\n### Task 1: 본체\n\n- [ ] **Step 1: RED**\n\n```bash\ngrep -q '"'"'x'"'"' f\n```\n\n- [ ] **Step 2: FAIL 확인**\n\n실행: `bash t.sh`\n'; } > "$A"
awk '/^### 경계 약속/{skip=1;next} skip&&/^## /{skip=0} !skip' "$A" > "$B"
pa=$(bash "$PLUGIN/scripts/_internal/check-plan-predispatch.sh" --plan "$A" 2>&1); pb=$(bash "$PLUGIN/scripts/_internal/check-plan-predispatch.sh" --plan "$B" 2>&1)
ta=$(bash "$PLUGIN/scripts/dag/plan-to-tasks.sh" --plan "$A" 2>&1); tb=$(bash "$PLUGIN/scripts/dag/plan-to-tasks.sh" --plan "$B" 2>&1)
{ ! grep -q '^### 경계 약속' "$B" && grep -q '^### 경계 약속' "$A" && [ "$pa" = "$pb" ] && [ "$ta" = "$tb" ] \
  && [ "$(printf '%s\n' "$ta" | grep -c '^## Task ')" -eq 1 ]; } \
  && ok "B10 predispatch·plan-to-tasks 결과가 경계 약속 절 유무와 무관" || nope "B10" "pa=$pa pb=$pb"

# B11 (AC-3 · FR-4): 경로꼴은 "공백 없음 · / 나 . 포함" 이다 — 한글·[id]·@·+·(group) 경로도 뽑혀 소유 밖으로 드러난다(조용히 빠지지 않는다)
P="$ROOT/b11.md"
cat > "$P" <<'EOF'
# 플랜

## 2. 파일 구조

- `src/a.sh` — 본체
- `app/[id]/page.tsx` — 동적 라우트
- `lib/@types/x.d.ts`
- `docs/설명서.md`
- `pkg/c++/x.cc`
- `app/(group)/page.tsx`

### 경계 약속
- **소유**: `src/`
- **범위 밖**: 없음
- **허용 의존**: 없음
- **다시 검토할 조건**: 없음
EOF
out=$(bash "$CPB" --plan "$P" --constitution "$NOC" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c '소유 밖')" -eq 5 ] \
  && printf '%s\n' "$out" | grep -qxF '  [소유 밖] app/[id]/page.tsx' && printf '%s\n' "$out" | grep -qxF '  [소유 밖] docs/설명서.md' \
  && printf '%s\n' "$out" | grep -qxF '  [소유 밖] app/(group)/page.tsx'; } \
  && ok "B11 한글·대괄호·@·+·괄호 경로도 소유 밖으로 드러난다" || nope "B11" "rc=$rc out=$out"

# B12 (AC-2 · FR-6): 확인할 수 없는 plan 은 "부재 SKIP" 이 아니라 판정 불가 rc 2 — 끊어진 링크 · 들어갈 수 없는 디렉터리
ln -s "$ROOT/no-such-dir/plan.md" "$ROOT/dangling.md"
out1=$(bash "$CPB" --plan "$ROOT/dangling.md" --constitution "$NOC" 2>&1); rc1=$?
if [ "$(id -u)" -eq 0 ]; then  # root 는 chmod 000 디렉터리에도 들어간다 — 그 절반은 판정하지 않고 SKIP 으로 드러낸다
  { [ "$rc1" -eq 2 ] && printf '%s\n' "$out1" | grep -q '\[판정 불가\] plan' && ! printf '%s\n' "$out1" | grep -q 'SKIP'; } \
    && ok "B12 끊어진 링크는 판정 불가 rc 2" || nope "B12" "rc=$rc1 out1=$out1"
  skip "B12 들어갈 수 없는 디렉터리 — root 로 실행 중(권한 검사 무의미)"
else
  mkdir -p "$ROOT/locked" && cp "$ROOT/b1.md" "$ROOT/locked/plan.md" && chmod 000 "$ROOT/locked"
  out2=$(bash "$CPB" --plan "$ROOT/locked/plan.md" --constitution "$NOC" 2>&1); rc2=$?
  chmod 755 "$ROOT/locked"
  { [ "$rc1" -eq 2 ] && printf '%s\n' "$out1" | grep -q '\[판정 불가\] plan' && ! printf '%s\n' "$out1" | grep -q 'SKIP' \
    && [ "$rc2" -eq 2 ] && printf '%s\n' "$out2" | grep -q '\[판정 불가\] plan'; } \
    && ok "B12 끊어진 링크·들어갈 수 없는 디렉터리는 판정 불가 rc 2" || nope "B12" "rc=$rc1/$rc2 out1=$out1 out2=$out2"
fi

# B13: `.specops/` 아래 FID 작업 파일(상대·절대)은 제품 코드가 아니라 소유 밖으로 대조하지 않는다 — 이름만 비슷한 `.specopsx/` 는 그대로 잡는다
#   (Argus 20261018-status-date-index: 측정 도구 `.specops/<FID>/tools/` 가 [소유 밖] 으로 WARN 된 오탐)
P="$ROOT/b13.md"
printf '# 플랜\n\n## 2. 파일 구조\n\n- `src/a.sh` — 본체\n- `.specops/20261018-x/tools/m.py` — 측정 도구\n- `/repo/.specops/20261018-x/tools/` — 같은 폴더(절대)\n- `.specopsx/y.sh` — 비슷한 이름\n\n### 경계 약속\n\n- **소유**: `src/`\n- **범위 밖**: 배포\n- **허용 의존**: 없음\n- **다시 검토할 조건**: 입력 형식이 늘 때\n' > "$P"
out=$(bash "$CPB" --plan "$P" --constitution "$NOC" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q '소유 밖\] .*\.specops/' \
  && [ "$(printf '%s\n' "$out" | grep -c '소유 밖')" -eq 1 ] && printf '%s\n' "$out" | grep -qx '  \[소유 밖\] .specopsx/y.sh'; } \
  && ok "B13 .specops/ 아래 작업 파일은 소유 밖 대조에서 뺀다 · .specopsx/ 는 잡는다" || nope "B13" "rc=$rc out=$out"

finish
