#!/usr/bin/env bash
# check-plan-predispatch.sh — plan-reviewer dispatch 직전 사전검사 (read-only)
#   FID 20260809-predispatch-fail-check
#
# Usage: check-plan-predispatch.sh <FID>
#        check-plan-predispatch.sh --plan <경로>
# Exit:  0 통과 또는 SKIP · 1 발견 1건 이상
#
# 왜 필요한가: plan-reviewer 1회차 FAIL 이 **5/5** 이고 재dispatch 1회가 **+62~91k 토큰**이다.
#   그 FAIL 을 만든 결함 중 **기계 판별 가능한 3클래스**를 dispatch 전에 잡아 왕복을 없앤다.
#
# 왜 미탐을 택하는가: 오탐은 정상 plan 을 막아 게이트 신뢰를 깎는다(같은 세션에 게이트
#   오탐 3건 전례). 판별이 애매하면 **통과시킨다** — 놓친 건 plan-reviewer 가 여전히 잡는다.
#   이 검사는 리뷰어를 대체하지 않고 **왕복만 줄인다**.
#
# 검사하지 않는 것: AC 검증방법 ↔ 테스트 대조. 반증 실측으로 기각했다 — 실제 FAIL 시점의
#   테스트 파일에 AC 가 지목한 토큰이 이미 6회 있었다(토큰 검사는 통과시킨다). 결함은
#   "어느 픽스처에 대조가 없다"는 의미론이라 토큰 수준에서 판별되지 않는다.
set -u

PLAN=""
case "${1:-}" in
  --plan) PLAN="${2:-}" ;;
  "")     echo "check-plan-predispatch: FID 인자 필요" >&2; exit 1 ;;
  *)      PLAN=".specops/$1/plan.md" ;;
esac

# plan.md 부재는 정상이다 — §lite·trivial 은 plan ceremony 를 건너뛴다. chain 을 막지 않는다.
if [ ! -r "$PLAN" ]; then
  echo "PREDISPATCH: SKIP (plan.md 부재 — §lite·trivial 정상 경로)"
  exit 0
fi

PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
PLAN_ABS=$(cd "$(dirname "$PLAN")" && pwd)/$(basename "$PLAN")
FOUND=0
_report() { echo "  [$1] $2"; FOUND=$((FOUND + 1)); }

# ── 규칙 1: dangling-lock ────────────────────────────────────────────────
# 테스트가 잠그려는 문자열이 repo 에도 없고 **이 plan 이 만들지도 않으면** 그 어서션은
#   영구 FAIL 이다(실측: `BATCH-PHASE1-DONE:decomposing-ko` 가 repo 전체 0건).
# 판별 규칙: repo 부재 AND plan 본문(그 인용 줄 제외) 부재 → 보고.
#   plan 이 새로 만드는 문자열은 구현부 코드블록에 등장하므로 자동으로 면제된다.
_git_top=0; _top=$(git -C "$PLUGIN" rev-parse --show-toplevel 2>/dev/null) \
  && [ "$(cd "$_top" && pwd -P)" = "$(cd "$PLUGIN" && pwd -P)" ] && _git_top=1
_quotes=$(grep -oE "grep -(q|qF|c) '[^']+'" "$PLAN" 2>/dev/null \
          | sed -E "s/^grep -(q|qF|c) '//; s/'$//" | sort -u)

while IFS= read -r s; do
  [ -n "$s" ] || continue
  # 정규식 메타문자를 가진 인용은 고정문자열 대조가 불가하다 → 판정 제외(미탐 선택).
  case "$s" in *'*'*|*'\'*|*'['*|*'+'*|*'?'*|*'|'*) continue ;; esac
  # 앵커는 문자열의 일부가 아니다 — 벗겨내고 본문만 본다.
  probe="${s#^}"; probe="${probe%$}"
  [ ${#probe} -ge 4 ] || continue           # 너무 짧으면 우연 매치가 많다 → 제외
  # repo 실재? (.specops·.git 제외 — 전자는 gitignore 산출물이라 근거가 못 된다)
  # ★ 검사 대상 plan 자신은 제외한다 — 포함하면 그 어서션 줄이 스스로를 매치시켜
  #   dangling 을 영원히 통과시킨다(구현 중 실증: 양성 픽스처가 rc=0 이었다).
  # ★ git 저장소면 **이 저장소의 파일만** 본다(추적 + 무시되지 않은 미추적 · 중첩 git 저장소 안은 보지 않는다) —
  #   grep -r 은 작업 폴더 안의 링크 worktree·복사본의 같은 문자열을 실재로 읽어 dangling 을 놓쳤다(20261022 실측).
  #   PLUGIN 이 저장소 **최상위**일 때만 — 바깥 저장소 안의 하위 폴더(홈 dotfiles 저장소 안의 설치본 등)면
  #   그 저장소의 gitignore 가 PLUGIN 을 통째로 가려 실재 문자열을 dangling 으로 오보고한다 → 종전 grep -r.
  if [ "$_git_top" = 1 ]; then
    _hits=$(git -C "$PLUGIN" -c core.quotePath=false grep -lF --untracked -e "$probe" -- . ':!.specops' ':!.worktrees' 2>/dev/null \
            | awk -v p="$PLUGIN/" '{ print p $0 }')
  else
    _hits=$(grep -rlF --exclude-dir=.git --exclude-dir=.specops --exclude-dir=.worktrees -- "$probe" "$PLUGIN" 2>/dev/null)
  fi
  if printf '%s\n' "$_hits" | grep -v '^$' | grep -qvF -- "$PLAN_ABS"; then
    continue
  fi
  # plan 이 스스로 만드는가? **인용 패턴만** 지우고 나머지 본문에서 찾는다.
  #   ★ 줄을 통째로 지우면 `echo 'X' >> f && grep -q 'X' f` 처럼 생성과 어서션이
  #     같은 줄일 때 구현 증거까지 사라져 오탐이 난다(Phase C 프로브 I-1 실증).
  if sed -E "s/grep -(q|qF|c) '[^']*'//g" "$PLAN" 2>/dev/null | grep -qF -- "$probe"; then
    continue
  fi
  _report dangling-lock "잠글 문자열이 repo 에도 plan 구현부에도 없다 → 어서션이 영구 FAIL: '$s'"
done <<EOF_Q
$_quotes
EOF_Q

# ── 규칙 2: propagation-schema ───────────────────────────────────────────
# 실물 파서(check-propagation.sh)는 `.edges[].path` / `.must_match` 만 소비한다.
#   `{source,contract,consumers}` 로 쓰면 `.edges` 가 null 이라 **edge 0건 기여 + exit 0**,
#   즉 잠금이 설치 즉시 조용히 죽는다(실측 Critical).
# ★ `"id"` 만으로 고르면 **무관한 JSON** 이 걸린다 — doctor 의 `--json` checks 원소처럼
#   id 를 가진 객체는 흔하다(구현 중 실측: 오탐 2/28). propagation **어휘**
#   (edges·consumers·must_match·contract) 를 함께 요구해 대상을 좁힌다.
if command -v jq >/dev/null 2>&1; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # jq 로 파싱 안 되면 판정 불가 → 건너뜀(미탐)
    printf '%s' "$line" | jq -e . >/dev/null 2>&1 || continue
    printf '%s' "$line" | jq -e '.edges[0].path' >/dev/null 2>&1 && continue
    _report propagation-schema "레코드에 .edges[].path 가 없다 → 파서가 edge 0건으로 읽어 잠금이 무음 사망: ${line%%,*}…"
  done <<EOF_J
$(grep -oE '^[[:space:]]*\{"id".*\}[[:space:]]*$' "$PLAN" 2>/dev/null \
    | grep -E '"(edges|consumers|must_match|contract)"')
EOF_J
else
  # 무음 skip 은 "잠금의 무음 사망" 을 잡는 규칙이 스스로 같은 모드로 죽는 것이다(원칙 5).
  echo "  (info) jq 부재 — propagation-schema 규칙 미실행"
fi

# ── 규칙 3: red-evidence (선-green 단정 한정) ────────────────────────────
# **좁힌 이유(구현 중 실측)**: 처음엔 "Step 2 에 실행 출력 블록 또는 유보 문구가 없으면"
#   으로 잡았더니 실 코퍼스 **28건 중 21건**이 걸렸다. 원인은 `planning-ko` 자신의 템플릿이
#   `실행: <명령>` + `예상: FAIL — <이유>` **산문 형식**이기 때문이다. 정본 형식을 결함으로
#   보는 규칙은 오탐 생성기다(NFR-3 위반).
# 실제로 plan-reviewer 가 2라운드 연속 적발한 것은 형식이 아니라 **"이건 이미 통과한다"는
#   현재 상태 단정**이었다(예: "T14·T15 는 PASS 로 시작한다" → 실측하니 둘 다 RED).
#   그 단정은 **측정 가능한데 측정하지 않은 것**이라 좁혀 잡는다. `예상: FAIL` 은 TDD 의
#   정상 기대라 대상이 아니다. 좁힌 규칙의 실 코퍼스 발화: **0/28**.
_red=$(awk '
  # ★ 숫자 경계 필수 — 없으면 "Step 25" 도 Step 2 로 잡혀 오탐/미탐 양방향으로 샌다
  #   (Phase C 프로브 I-2). 경계를 넣으면 헤더 룰이 Step 26 을 삼키지 않아 종료 판정도 산다.
  /^- \[ \] \*\*(Step|스텝)[ \t]*2([^0-9]|$)/ { inb = 1; has = 0; claim = 0; next }
  inb && /^- \[ \] \*\*/ { if (claim && !has) bad++; inb = 0 }
  inb {
    if ($0 ~ /^```/)                                        has = 1
    if ($0 ~ /실행해 확인|실측 불가|변이로 대체|추론 금지/)   has = 1
    if ($0 ~ /PASS 로 시작|이미 (통과|green)|선-green|처음부터 (PASS|green)/) claim = 1
  }
  END { if (inb && claim && !has) bad++; print (bad + 0) }
' "$PLAN" 2>/dev/null)
if [ "${_red:-0}" -gt 0 ] 2>/dev/null; then
  _report red-evidence "Step 2 절 ${_red}건이 \"이미 통과한다\"고 단정하면서 실측 근거가 없다 → 측정 가능한데 측정하지 않았다"
fi

# ── 판정 ────────────────────────────────────────────────────────────────
if [ "$FOUND" -eq 0 ]; then
  echo "PREDISPATCH: OK"
  exit 0
fi
echo "PREDISPATCH: ${FOUND}건 발견 — plan.md 수정 후 재실행하세요 (plan-reviewer 왕복 1회 = 62~91k)"
exit 1
