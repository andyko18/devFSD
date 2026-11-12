#!/usr/bin/env bash
# plan 의 구현 본문 축소 (20261112) — 테스트는 완성 코드, 구현 스텝은 시그니처·위험 로직·고정 값.
#
# 왜 필요한가: 규칙이 planning-ko 한 곳에만 있으면 나머지가 되돌린다 — decomposing 이 "코드 없는 스텝"을
#   플레이스홀더로 막고, plan 리뷰어가 본문 없음을 지적하고, 구현자가 옮겨 적을 본문을 찾다 멈춘다.
#   다섯 문서가 같은 계약을 말하는지와, 본문 없는 plan 을 태스크 골격 생성기·사전검사가 받는지를 잠근다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PL="$PLUGIN/skills/planning-ko/SKILL.md"
DE="$PLUGIN/skills/decomposing-ko/SKILL.md"
has() { grep -qF -- "$2" "$1"; }

# ── P: 다섯 문서가 같은 계약을 말한다 ────────────────────────────────────
has "$PL" '## 구현 스텝에는 본문을 쓰지 않는다' && has "$PL" '시그니처 + 핵심 로직은 플레이스홀더가 아니다' \
  && ok "P1 planning-ko — 규칙 절과 플레이스홀더 예외 문장" || nope "P1" "없음"
for w in '파일 경로' '시그니처' '위험 로직' '고정 값' '실행 가능한 완성 코드' '본문을 그대로 쓰는 예외'; do
  has "$PL" "$w" && ok "P2 planning-ko 에 '$w'" || nope "P2" "'$w' 없음"
done
! has "$PL" '모든 스텝에 완전한 코드' && ! has "$PL" '코드 스텝은 코드 블록 필수' \
  && ok "P3 ★ 완성 코드를 요구하던 옛 문구가 남아 있지 않다" || nope "P3" "옛 문구 잔존"
has "$DE" '시그니처·핵심 로직 없는 구현 스텝' && ! has "$DE" '코드 없는 스텝)' && ! has "$DE" '최소 구현 (실제 코드)' \
  && ok "P4 decomposing-ko — HARD GATE·Step 3 이 본문 없는 구현 스텝을 막지 않는다" || nope "P4" "문구 불일치"
has "$PLUGIN/agents/plan-reviewer-ko.md" '구현 본문이 없다고 지적하지 않는다' && has "$PLUGIN/agents/plan-reviewer-ko.md" '플레이스홀더가 아니다' \
  && ok "P5 plan-reviewer-ko — 본문 없음은 지적 대상이 아니다" || nope "P5" "없음"
has "$PLUGIN/agents/implementer-ko.md" '구현 명세' && has "$PLUGIN/agents/implementer-ko.md" '본문 코드가 없는 것이 정상' \
  && ! has "$PLUGIN/agents/implementer-ko.md" 'tasks.md의 최소 구현을 src 파일에 작성' \
  && ok "P6 implementer-ko — 명세로 본문을 직접 쓴다(옮겨 적기 전제 제거)" || nope "P6" "없음"
has "$PLUGIN/templates/tasks.md" '시그니처:' && has "$PLUGIN/templates/tasks.md" '구현 본문은 구현자가 쓴다' \
  && ok "P7 tasks 템플릿 Step 3 — 명세 형식" || nope "P7" "없음"
# 테스트 스텝은 줄지 않았다 — 예시의 Step 1 은 여전히 코드 블록이다
awk '/\*\*Step 1: 실패 테스트 작성\*\*/{f=1;next} f&&/^```python/{print "code";exit} f&&/\*\*Step 2/{exit}' "$PL" | grep -q code \
  && ok "P8 planning-ko 예시의 테스트 스텝은 완성 코드 블록 그대로" || nope "P8" "테스트 스텝 코드 블록 없음"

# ── G: 본문 없는 plan 을 도구가 받는다 ───────────────────────────────────
mkdir -p "$TMP/.specops/20261112-px"
cat > "$TMP/.specops/20261112-px/plan.md" <<'PLAN'
# 줄 수 세기 구현 플랜

### Task 1: 줄 수 세기

**파일**:
- 생성: `src/count.sh`
- 테스트: `tests/test-count.sh`

- [ ] **Step 1: 실패 테스트 작성**

```bash
out=$(bash src/count.sh /nonexistent 2>&1); echo "$out" | grep -q '@@TOK@@' || exit 1
```

- [ ] **Step 2: 실패 확인 실행**

실행: `bash tests/test-count.sh`
예상: FAIL — src/count.sh 없음

- [ ] **Step 3: 최소 구현 작성**

- 파일: `src/count.sh`
- 시그니처: `count.sh <파일>` — stdout 줄 수 · rc 0 / 파일 없으면 rc 2
- 핵심 로직: 마지막 줄에 개행이 없어도 1줄로 센다
- 고정 값: 오류 문구 `@@TOK@@`

- [ ] **Step 4: 통과 확인 실행**

실행: `bash tests/test-count.sh`
예상: PASS

- [ ] **Step 5: 커밋**

```bash
git add src/count.sh tests/test-count.sh
```
PLAN
# 잠글 문자열은 실행 때 조립한다 — 이 파일에 글자 그대로 있으면 사전검사가 "repo 에 실재"로 읽는다
TOK="count-$(printf 'no%s' file)-zq9"
sed -i.bak "s/@@TOK@@/$TOK/g" "$TMP/.specops/20261112-px/plan.md"
out=$(cd "$TMP" && bash "$PLUGIN/scripts/dag/plan-to-tasks.sh" 20261112-px 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '시그니처: `count.sh <파일>`' && printf '%s' "$out" | grep -q '고정 값: 오류 문구' \
  && ok "G1 태스크 골격 생성기 — 코드 블록 없는 구현 스텝을 명세째 옮긴다" || nope "G1" "rc=$rc $(printf '%s' "$out" | head -5)"
out=$(cd "$TMP" && bash "$PLUGIN/scripts/_internal/check-plan-predispatch.sh" 20261112-px 2>&1); rc=$?
[ "$rc" = 0 ] && ok "G2 사전검사 — 테스트가 잠그는 문자열이 '고정 값' 에 있으면 dangling 아님" || nope "G2" "rc=$rc $out"
sed -i.bak '/^- 고정 값:/d' "$TMP/.specops/20261112-px/plan.md"
out=$(cd "$TMP" && bash "$PLUGIN/scripts/_internal/check-plan-predispatch.sh" 20261112-px 2>&1); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'dangling-lock' \
  && ok "G3 ★ 고정 값을 빼면 사전검사가 잡는다(본문 축소가 이 검사를 무력화하지 않는다)" || nope "G3" "rc=$rc $out"

echo ""
finish
