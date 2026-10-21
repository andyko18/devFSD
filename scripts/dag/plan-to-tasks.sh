#!/usr/bin/env bash
# plan-to-tasks.sh — plan.md 의 Task 블록을 tasks.md 골격으로 변환 (stdout 전용)
#   FID 20260809-plan-to-tasks-generator
#
# Usage: plan-to-tasks.sh <FID>
#        plan-to-tasks.sh --plan <경로>      # 테스트용 직접 지정
# Exit:  0 성공(stdout 골격) · 1 거부(stdout 빈손, 사유는 stderr)
#
# 왜 stdout 전용인가: 파일을 직접 쓰면 재실행이 decomposing-ko 의 기존 작업을 파괴한다.
# 왜 YAML 을 안 만드는가: depends_on 은 plan.md 에서 도출 불가하고, `[]` 로 채우면
#   dag::find_independent_batch 가 전 태스크를 절대 leaf 로 보아 **거짓 병렬**을 연다
#   (실측: 3-task all-leaf → `T1 T2 T3` 무경고 반환). 안 만드는 것이 안전하다.
#   반대로 per-task `ac` 는 비워도 emit-context 가 `must AC 미커버` 로 막으므로 관문이 강제한다.
set -u

FID=""; PLAN=""
case "${1:-}" in
  --plan) PLAN="${2:-}" ;;
  "")     echo "plan-to-tasks: FID 인자 필요" >&2; exit 1 ;;
  *)      FID="$1"; PLAN=".specops/$FID/plan.md" ;;
esac

if [ ! -r "$PLAN" ]; then
  echo "plan-to-tasks: plan.md 없음 — $PLAN" >&2
  exit 1
fi
[ -n "$FID" ] || FID=$(basename "$(dirname "$PLAN")")

# 단일 awk 패스 — 줄당 프로세스 스폰 0 (NFR-3).
# 검증 실패 시 아무것도 출력하지 않기 위해 전량 버퍼링 후 END 에서만 print 한다.
awk -v fid="$FID" '
function flush_task() {
  if (cur != "") {
    ntask++
    titles[ntask] = cur
    bodies[ntask] = body
    if (nstep == 0) { zero = cur }
  }
  cur = ""; body = ""; nstep = 0
}
BEGIN { fence = 0; ntask = 0; cur = ""; body = ""; nstep = 0; zero = "" }
{
  line = $0
  # ── 코드펜스 길이 추적 ──
  # 3-backtick 만 세면 4-backtick 블록 안의 3-backtick 을 종료로 오인한다(실측 1건).
  # 닫힘 조건은 `==` 가 아니라 **`>=`** 다 — CommonMark 는 "닫는 펜스는 여는 펜스
  #   **이상**" 이므로 3-open/4-close 가 유효하다. `==` 로 두면 그 문서에서 뒤 Task 가
  #   펜스 안으로 오인돼 **무음 병합**된다(Phase C 프로브 P5 실증).
  if (match(line, /^`+/) && RLENGTH >= 3) {
    if (fence == 0)            fence = RLENGTH
    else if (RLENGTH >= fence) fence = 0
  }
  if (fence == 0 && line ~ /^(##|###)[ \t]+(Task|태스크)[ \t]+[0-9]+/) {
    flush_task()
    t = line
    sub(/^#+[ \t]+(Task|태스크)[ \t]+/, "", t)   # "N: 제목" 만 남긴다
    cur = t
    next
  }
  if (cur != "" && fence == 0 && line ~ /^(#|##|###)[ \t]/) { flush_task(); next }
  if (cur != "") {
    # ★ fence == 0 가드 필수 — 코드펜스 **안**의 Step 은 문서가 스텝 문법을 예시한 것이지
    #   실제 스텝이 아니다. 가드가 없으면 "Step 이 예시로만 있는 Task" 가 zero-step 거부를
    #   우회한다(Phase C 프로브 P7 실증: rc=0). 이 repo 의 plan.md 자체가 그 입력 클래스다.
    if (fence == 0 && line ~ /^- \[ \] \*\*(Step|스텝)[ \t]+[0-9]+/) nstep++
    body = body line "\n"
  }
}
END {
  flush_task()
  if (ntask == 0) { print "plan-to-tasks: Task 블록 0건 — 산문형 plan" > "/dev/stderr"; exit 1 }
  if (zero != "") { print "plan-to-tasks: Step 0개 Task — " zero > "/dev/stderr"; exit 1 }

  printf "<!-- FID: %s -->\n<!-- OWNER_COMMAND: /tasks -->\n\n", fid
  printf "# %s 태스크 목록 (골격)\n\n", fid
  print  "> **골격 생성**: `scripts/dag/plan-to-tasks.sh` — plan.md 의 Task 블록만 옮긴 **미완성 골격**이다."
  print  "> **생성되지 않은 섹션**: `## 의존 그래프`(YAML) · `## AC → Task 매핑` · `## 파괴적 작업` · `## 진행 상태` — decomposing-ko 가 직접 작성한다."
  printf "\n**관련 플랜**: `.specops/%s/plan.md`\n\n---\n", fid
  for (i = 1; i <= ntask; i++) {
    printf "\n## Task %s\n%s\n---\n", titles[i], bodies[i]
  }
  exit 0
}
' "$PLAN"
