#!/usr/bin/env bash
# test-gate-presence.sh — skill-body HARD GATE 존재 회귀 (②)
#
# 목적: skill body 의 핵심 게이트 문구가 실수로 삭제·drift 되는 것을 **결정적 grep** 으로 방어한다.
#   - LLM 이 게이트를 "지키는지"(행동) 는 llm-eval(주간 smoke) 관할.
#   - 본 테스트는 게이트가 "존재하는지"(구조) 만 — 무료·결정적·CI 상시.
#   - recurring 결함 클래스(feedback_skill_body_infra_propagation: teeth in body, 인프라 소실)의
#     "게이트 자체 소실" 절반을 봉쇄. cross-skill signal 정합은 validate-structure contract_consistency(①) 담당.
# (templates·scripts 파일의 문구·배선 존재도 has 로 확인한다 — task id 규약 등)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 1
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
cd "$PLUGIN" || exit 1

# has <file> <regex...> — 모든 패턴이 파일에 존재하면 0
has() {
  local f="$1"; shift
  local p
  for p in "$@"; do grep -qE "$p" "$f" || return 1; done
  return 0
}

# ── foundation 재사용 메커니즘 3-지점 계약 (PR #165) ─────────────
V=skills/verifying-evidence-ko/SKILL.md
if has "$V" '§유형.*foundation' 'foundation-manifest' 'VERIFY: FAIL foundation-manifest'; then
  ok "foundation manifest 생산 게이트 존재 (verify: §유형=foundation → 실제 파일 검사)"
else
  nope "foundation manifest 생산 게이트 소실" "verifying-evidence-ko — 소비 게이트가 침묵 no-op 될 수 있음"
fi

D=skills/decomposing-ko/SKILL.md
if has "$D" 'foundation 재사용 게이트' '재사용 foundation' '미재사용 근거'; then
  ok "foundation 재사용 소비 게이트 존재 (decomposing)"
else
  nope "foundation 재사용 소비 게이트 소실" "decomposing-ko"
fi

P=skills/planning-ko/SKILL.md
if has "$P" 'foundation-manifest' 'verifying-evidence-ko'; then
  ok "foundation 생산 지시 + verify 강제 cross-ref 존재 (planning)"
else
  nope "foundation 생산 지시/강제 cross-ref 소실" "planning-ko"
fi

# 경로 정합 — 생산 게이트·소비 게이트가 동일 정규 경로를 가리키는가
if has "$V" '\.specops/memory/foundation-manifest\.md' && has "$D" 'foundation-manifest\.md'; then
  ok "foundation-manifest 경로 정합 (.specops/memory/)"
else
  nope "foundation-manifest 경로 drift" "verify↔decomposing 경로 불일치"
fi

# ── 입력 프로브 (fixture-외) 의무 — code-reviewer-ko 4단계 + 보고서 섹션 ────
# 한계 (5원칙 5): 본 검사는 **문구 존재**만 본다 — 리뷰어가 실제로 프로브했는지는 검증하지 않는다.
#   프로브는 행동이라 파일 대조로 검증 가능한 객관 신호가 없다(F1 의 누락 검사와 다른 지점).
#   guidance-level 이라는 뜻이며, 그 천장을 알고 넣는다 (#226 P4 넛지와 같은 등급).
CR=agents/code-reviewer-ko.md
#   패턴 3종은 각각 다른 소실을 잡는다: ① 프로세스 단계(번호 앵커) ② fixture 수정 금지 계약
#   ③ 보고서 섹션. ①·③ 중 하나만 검사하면 나머지 삭제가 mutation 생존한다 (실측).
if has "$CR" '^4\. \*\*입력 프로브' 'fixture.*수정하지 않는다' '^## 입력 프로브'; then
  ok "입력 프로브(fixture-외) 의무 + 보고서 섹션 존재 (code-reviewer-ko)"
else
  nope "입력 프로브 의무 소실" "code-reviewer-ko — 작성자 fixture 안에서만 판정하게 됨"
fi

# ── BATCH halt signal — 방출 skill 에 signal + halt 동시 존재 ────
# (cross-skill 방출↔감시 정합은 ① contract_consistency; 여기선 방출측 halt 구조만)
declare -a SIG=(
  "BATCH-PHASE1-DONE:decomposing-ko"
  "BATCH-REVIEW-DONE:receiving-code-review-ko"
  "BATCH-SECURITY-DONE:security-review-ko"
  "BATCH-INTEGRATION-DONE:integration-test-ko"
  "BATCH-PERF-DONE:performance-test-ko"
)
for pair in "${SIG[@]}"; do
  token="${pair%%:*}"; skill="${pair##*:}"
  f="skills/${skill}/SKILL.md"
  if has "$f" "$token" 'halt|PR 게이트'; then
    ok "batch halt signal 존재: ${token} (${skill})"
  else
    nope "batch halt signal 소실: ${token}" "${skill} — signal 또는 halt 문구 부재"
  fi
done

# ── 가정 다이제스트 "자동 결정 인터페이스" 수집 3-소비처 (P1-3 audit 20260710) ──
# specifying §auto Step 5.6 이 spec.md 에 기록하는 라벨을 다이제스트 소비처가 실제 수집하는지.
for f in skills/performance-test-ko/SKILL.md commands/start-auto.md commands/start-all-auto.md; do
  if grep -q '자동 결정 인터페이스' "$f"; then
    ok "다이제스트 인터페이스 수집 존재 ($f)"
  else
    nope "다이제스트 인터페이스 수집 ($f)" "'자동 결정 인터페이스' 미수집 — 무인 API 가정이 PR 게이트에 안 보임"
  fi
done

# ── FID 크기 규약 (완성율 레버, 20260718-fid-size) ──
# decomposing-ko body 에 per-FID 태스크 수 소프트 신호가 존재하는지 (silent drift 방어).
# dogfood: test2 3-태스크 FID 6/6 완주 vs test1 10-태스크 FID 정체 → 큰 FID = 완성율 리스크.
if has skills/decomposing-ko/SKILL.md 'FID 크기' 'FID-SIZE' '재개는? ?/status|/status.*재개|reconcile'; then
  ok "decomposing-ko FID 크기 규약 존재 (완성율 소프트 신호 + 재개 연결)"
else
  nope "decomposing-ko FID 크기 규약 소실" "per-FID 태스크수 신호 부재 — 큰 FID 정체 리스크 무경고"
fi

# ── E2 최종 리뷰 right-size + end-loaded (경제성) ──
# end-loaded C 또는 단일 태스크 per-task C 와의 중복 최종 리뷰 skip + B/C 생략 금지(시점 통합만 허용).
if has skills/implementing-ko/SKILL.md '최종 리뷰 right-size|최종 리뷰 SKIP' 'end-loaded|태스크 수 == 1' 'Phase B/C \*\*생략\*\*|시점 통합|생략 금지'; then
  ok "implementing-ko E2/end-loaded 최종 리뷰 right-size 존재 (중복 skip + B/C 생략 금지)"
else
  nope "implementing-ko E2/end-loaded 최종 리뷰 right-size 소실" "중복 제거 게이트 또는 품질 가드 부재"
fi

# ── P1 Evaluator 모델 불가 fallback (20260718 test2 회고) ──
# 지정 모델 한도 소진·접근 불가 시 부모 self-review 붕괴 금지 + 독립 리뷰어 fallback 존재.
if has skills/implementing-ko/SKILL.md 'Evaluator 모델 불가' '부모 self-review 로 후퇴 금지|부모 self-review.*금지' '독립 서브에이전트'; then
  ok "implementing-ko Evaluator fallback 존재 (독립 리뷰어 + 부모 self-review 금지)"
else
  nope "implementing-ko Evaluator fallback 소실" "지정 모델 불가 시 Generator↔Evaluator 붕괴 무방어"
fi
if grep -q '부모 self-review 로 후퇴 금지' skills/planning-ko/SKILL.md && grep -q 'plan-reviewer-ko .*독립 서브에이전트\|독립 서브에이전트로 가용 모델' skills/planning-ko/SKILL.md; then
  ok "planning-ko plan-reviewer fallback 참조 존재"
else
  nope "planning-ko plan-reviewer fallback 소실" "plan-reviewer 도 동일 붕괴 표면"
fi

# ── P5 detection-proof (테스트 전용 태스크 RED 대체, 20260718 test2 회고) ──
if has skills/tdd-ko/SKILL.md 'detection-proof' '규칙 뒤집기|rule inversion' '유령 주입|ghost' '변이해도 통과.*tautology|tautology'; then
  ok "tdd-ko detection-proof 존재 (RED 대체: 변이로 탐지력 증명)"
else
  nope "tdd-ko detection-proof 소실" "테스트 전용 태스크가 자연 RED 없어 가짜 RED/공회전"
fi

# ── P2 공유유틸 창발중복 경고 + P4 implement 선언 넛지 (20260718 test2 회고) ──
if has skills/planning-ko/SKILL.md '공유 유틸 창발 중복' '공통 lib|공통lib' '창발 중복 리스크'; then
  ok "planning-ko P2 창발중복 경고 존재"
else
  nope "planning-ko P2 창발중복 경고 소실" "형제-FID 유틸 복제 무경고 → 승격 backlog 반복"
fi

# ── batch plan-reviewer DEFER ──
if has skills/planning-ko/SKILL.md 'plan-reviewer DEFER|DEFERRED → Phase 2 batch' '§batch' 'dispatch 하지 않음'; then
  ok "planning-ko batch plan-reviewer DEFER 존재"
else
  nope "planning-ko batch DEFER 소실" "Phase 1 FR마다 reviewer 회귀 위험"
fi
if grep -q 'Batch plan-review' commands/start-all.md && grep -q 'batch-plan-digest.sh' commands/start-all.md; then
  ok "start-all Phase 2 batch plan-review + digest 배선"
else
  nope "start-all Phase 2 plan-review 배선 소실" "DEFER 해소 경로 부재"
fi
if grep -q '호출 직전 한 줄 선언' skills/decomposing-ko/SKILL.md && grep -q 'implementing-ko 를 호출합니다' skills/decomposing-ko/SKILL.md; then
  ok "decomposing-ko P4 implement 선언 넛지 존재 (R-3 투명성)"
else
  nope "decomposing-ko P4 선언 넛지 소실" "implementing-ko 자동호출 R-3 warn 재발"
fi

# ── /security-scan 소유확인 게이트 (M3, 20260806) ────────────────
# DAST 는 타인 서버에 쏘면 불법이다. 소유 확인 프롬프트는 **법적 안전장치**인데
# 커맨드 문서에 문구만 있고 이를 잠그는 테스트가 0 이었다 — 리팩터링에서 조용히 사라질 수 있다.
S=commands/security-scan.md
# ★ 프롬프트 **한 줄** 안에 소유확인 + [y/N] 이 함께 있어야 한다.
#   느슨하게 '본인 소유' 만 보면 §안티패턴의 서술문("본인 소유가 아닌 서버를 스캔하면 불법")에
#   걸려 프롬프트를 지워도 통과한다 — mutation 으로 실제 확인된 false-pass.
if grep -qE '본인 소유.*\[y/N\]' "$S"; then
  ok "security-scan DAST 소유확인 프롬프트 존재 (법적 안전장치)"
else
  nope "security-scan 소유확인 프롬프트 소실" "'본인 소유…[y/N]' 단일 줄 부재"
fi
if grep -qE '무단.*불법|불법.*무단|무단 스캔' "$S"; then
  ok "security-scan 무단 스캔 위법 고지 존재"
else
  nope "security-scan 위법 고지 소실" "무단 스캔 경고 문구 부재"
fi
# 승인 없이 dast-scan.sh 를 먼저 실행하는 순서 역전 방지 — 경고(Process 1)가 DAST(Process 3)보다 앞
_l_warn=$(grep -n '능동 스캔 경고' "$S" | head -1 | cut -d: -f1)
_l_dast=$(grep -n 'dast-scan.sh' "$S" | head -1 | cut -d: -f1)
if [ -n "$_l_warn" ] && [ -n "$_l_dast" ] && [ "$_l_warn" -lt "$_l_dast" ]; then
  ok "security-scan 승인→DAST 순서 보존"
else
  nope "security-scan 순서 역전" "warn=$_l_warn dast=$_l_dast"
fi

# ── self-config 적대감사 토큰 경고 (M3 동반) ─────────────────────
if has "$S" 'self-config' '토큰 비용' '\[y/N\]'; then
  ok "security-scan --self-config 토큰 경고 게이트 존재"
else
  nope "security-scan self-config 토큰 경고 소실" "3 서브에이전트 dispatch 무경고"
fi

# ── task id 규격 게이트 배선 (20261001-task-id-guard) ──
if has scripts/dag/emit-context.sh 'check-task-ids\.sh' 'task id 규격 위반'; then
  ok "task-ids: emit-context 가 check-task-ids 를 구현 전에 호출"
else
  nope "task-ids: emit-context 배선 부재"
fi

# ── 숫자 전용 task id 규약 문서화 (20261001-task-id-guard AC-7) ──
if has templates/tasks.md '숫자 전용' 'T1a'; then ok "task-ids: templates/tasks.md 숫자 전용 규약"; else nope "task-ids: templates/tasks.md 규약 문구 부재"; fi
if has skills/decomposing-ko/SKILL.md '숫자 전용' 'check-task-ids'; then ok "task-ids: decomposing-ko 숫자 전용 규약·판정기 언급"; else nope "task-ids: decomposing-ko 규약 문구 부재"; fi

# ── FID 스코프 게이트 배선 (20261007-fid-size-gate) ──
if has scripts/dag/emit-context.sh 'bash "\$_FS_SH"' 'FID 스코프 초과'; then
  ok "fid-size: emit-context 가 check-fid-size 를 구현 전에 호출"
else
  nope "fid-size: emit-context 배선 부재"
fi
if has templates/tasks.md '분할 계획' 'check-fid-size'; then ok "fid-size: templates/tasks.md 분할 계획행 규약·판정기 언급"; else nope "fid-size: templates/tasks.md 규약 문구 부재"; fi
if has skills/decomposing-ko/SKILL.md '분할 계획' 'check-fid-size'; then ok "fid-size: decomposing-ko 분할 계획행·판정기 언급"; else nope "fid-size: decomposing-ko 규약 문구 부재"; fi

# ── 무인 계약의 리프 전달 · 범위 위생 (20261007-fable-tips) ──
if has scripts/dag/emit-context.sh '## 7\. 실행 모드' 'run_mode' '사용자와 직접 대화할 수 없다'; then
  ok "fable-tips: emit-context 가 dispatch-context §7 실행 모드를 쓴다"
else
  nope "fable-tips: emit-context §7 배선 부재"
fi
if has agents/implementer-ko.md '## 실행 모드 계약' '시작 시 한 번에' '의존 없는 나머지는 끝까지' 'NEEDS_APPROVAL' '의견·설명만 요청'; then
  ok "fable-tips: implementer-ko 실행 모드 계약 5항목"
else
  nope "fable-tips: implementer-ko 실행 모드 계약 문구 부재"
fi
if has agents/implementer-ko.md '## 범위 위생' '무관 발견:' '`Edit` 로 필요한 부분만' '임시 확인 코드를 남기지 않는다' 'RED 테스트는 이 규칙의 예외가 아니라'; then
  ok "fable-tips: implementer-ko 범위 위생(무관 발견·부분 수정·임시 코드·TDD 예외 아님)"
else
  nope "fable-tips: implementer-ko 범위 위생 문구 부재"
fi
if has templates/dispatch-context.md '## 7\. 실행 모드'; then ok "fable-tips: dispatch-context 템플릿 §7"; else nope "fable-tips: 템플릿 §7 부재"; fi

# ── 사용자 전용 command 는 모델 자동 호출을 막는다 (20261007-doc-conformance) ──
#   공식 문서(skills): `disable-model-invocation: true` = "Description not in context, full skill loads when invoked".
#   release·promote·e2e-test 처럼 부작용이 있는 명령을 모델이 스스로 부르지 못하게 하고, 상시 목록에서 빠진다
#   (실측 `/context`: specops skill 행 54→32, ~870 tok 절감 — `claude plugin details` 투영값은 이 플래그를 반영하지 않는다).
#   모델이 부를 수 있어야 하는 init-project(메타 skill 이 y 응답 시 호출)·status(재개 조회)는 켜 두지 않는다.
_dmi_ok=ok; _dmi_n=0
for c in brainstorming design-interface design-interfaces design-screen design-screens doctor e2e-test gbrain improve-arch log maintain-lite maintain promote release security-scan start-all-auto start-all start-auto start-foundation start-lite start statusline-install; do
  _dmi_n=$((_dmi_n+1))
  awk 'NR==1&&$0=="---"{on=1;next} on&&$0=="---"{exit} on' "$PLUGIN/commands/$c.md" | grep -qx 'disable-model-invocation: true' || { _dmi_ok=no; echo "  (플래그 누락: commands/$c.md)"; }
done
for c in init-project status; do
  awk 'NR==1&&$0=="---"{on=1;next} on&&$0=="---"{exit} on' "$PLUGIN/commands/$c.md" | grep -q 'disable-model-invocation' && { _dmi_ok=no; echo "  (모델 호출 필요 command 에 플래그: $c)"; }
done
[ "$_dmi_ok" = ok ] && ok "dmi: 사용자 전용 command ${_dmi_n}종 disable-model-invocation · init-project·status 는 제외" || nope "dmi: command 플래그 계약 위반"
# 비활성 command 를 skill 호출 문법(specops-ko:<cmd>)으로 부르는 본문이 없다 — 있으면 모델이 못 불러 체인이 끊긴다
_dmi_ref=$(cd "$PLUGIN" && git grep -n -E 'specops-ko:(brainstorming|design-interfaces?|design-screens?|doctor|e2e-test|gbrain|improve-arch|log|maintain-lite|maintain|promote|release|security-scan|start-all-auto|start-all|start-auto|start-foundation|start-lite|start|statusline-install)([^-a-z]|$)' -- skills agents hooks 2>/dev/null | head -3)
[ -z "$_dmi_ref" ] && ok "dmi: 비활성 command 를 모델이 skill 로 호출하는 본문 0건" || nope "dmi: 비활성 command 호출 참조" "$_dmi_ref"

# ── implementer-ko 가 karpathy-ko 를 프리로드한다 (공식 sub-agents: `skills` frontmatter = 시작 시 전체 내용 주입) ──
#   실측: --plugin-dir 로 구현자를 띄워 첫 제목 `# Karpathy 행동 원칙` 이 컨텍스트에 있음을 확인(맨 이름 `karpathy-ko` 로 해석됨).
#   프리로드 대상은 disable-model-invocation 이 아닌 skill 이어야 한다(문서: 그런 skill 은 프리로드 불가).
if awk 'NR==1&&$0=="---"{on=1;next} on&&$0=="---"{exit} on' agents/implementer-ko.md 2>/dev/null | grep -q '^  - karpathy-ko$' \
   || awk 'NR==1&&$0=="---"{on=1;next} on&&$0=="---"{exit} on' "$PLUGIN/agents/implementer-ko.md" | grep -q '^  - karpathy-ko$'; then
  ok "preload: implementer-ko frontmatter skills 에 karpathy-ko"
else
  nope "preload: implementer-ko skills 프리로드 부재"
fi
if ! awk 'NR==1&&$0=="---"{on=1;next} on&&$0=="---"{exit} on' "$PLUGIN/skills/karpathy-ko/SKILL.md" | grep -q 'disable-model-invocation'; then
  ok "preload: karpathy-ko 는 프리로드 가능(disable-model-invocation 아님)"
else
  nope "preload: karpathy-ko 가 disable-model-invocation — 프리로드 불가"
fi

# ── 20261005 전체 스위트 병행 · 리뷰어 실행 예산 (implementing-ko) ──
# Phase A 직후 run-all 백그라운드 병행(리뷰 대기와 겹침) + 리뷰어 실행량 상한. 문구가 사라지면 병행·예산이 조용히 꺼진다.
if has skills/implementing-ko/SKILL.md '전체 스위트 병행' 'run-all\.sh --quiet' 'run-all\.log' '증거가 아니다' '라운드마다 다시 띄우지 않는다' 'FAILED. 줄을 사용자에게 알리되' '임시 복사본'; then
  ok "implementing-ko 전체 스위트 병행 계약 존재 (백그라운드·log·비증거·수정 라운드·FAIL 알림·실 트리 변조 금지)"
else
  nope "implementing-ko 전체 스위트 병행 계약 소실" "병행 실행 절차 또는 안전 규칙 부재"
fi
if has skills/implementing-ko/SKILL.md '리뷰어 실행 예산' '핵심 실행 2회' '되돌려-관찰 3회' '전체 소비자 스위트 재실행은 하지 않는다' 'strict. 는 종전 그대로' '대상 스위트가 느린 경우' '실행 상한을 숫자로' '계약 밖 점검' 'RED 1회·GREEN 1회·되돌려-관찰 1회' 'B·C 각 1회 필수'; then
  ok "implementing-ko 리뷰어 실행 예산 존재 (B 2회·C 3회·전체 재실행 금지·strict 불변·느린 대상 스위트 규칙·구현자 실행 상한)"
else
  nope "implementing-ko 리뷰어 실행 예산 소실" "리뷰어 재실행이 다시 무제한이 된다 (느린 대상 스위트 규칙·구현자 실행 상한 포함)"
fi
# 20261008 스위트 상한 — 부하(load 17)에서 test-validate-structure(단독 114s)가 300s 상한 TIMEOUT 으로 거짓 FAIL → 기본 600 doc-lock: historical (당시 실측)
if grep -qF 'SPECOPS_SUITE_TIMEOUT:-600' scripts/tests/run-all.sh && ! grep -qF 'SPECOPS_SUITE_TIMEOUT:-300' scripts/tests/run-all.sh \
   && grep -qF '스위트별 600s 상한' CLAUDE.md && ! grep -qF '스위트별 300s 상한' CLAUDE.md; then
  ok "run-all 스위트 상한 기본 600s (run-all.sh·CLAUDE.md 정합)"
else
  nope "run-all 스위트 상한 기본값 불일치" "run-all.sh 기본 600 또는 CLAUDE.md 서술 누락"
fi

# ── 20261005 전체 스위트 신선도 확인 (verifying-evidence-ko) ──
# FRESH 면 수동 전체 스위트 생략, 그 밖(STALE·부재·FAIL·판정 불가)은 포그라운드 재실행. 게이트 증거는 별개.
if has skills/verifying-evidence-ko/SKILL.md '전체 스위트 신선도 확인' 'full-suite-fresh\.sh' '재실행을 생략' '완료줄' '생략 판정이 애매하면 \*\*재실행\*\*' '게이트 증거는 여전히' 'PARTIAL·NOT_RUN 이면' '지문 한계'; then
  ok "verifying-evidence-ko 신선도 확인 절차 존재 (FRESH 생략·백그라운드 대기·애매하면 재실행·게이트 증거 별개)"
else
  nope "verifying-evidence-ko 신선도 확인 절차 소실" "생략 조건이 불명확해지거나 재실행 폴백이 사라진다"
fi
# ── 20261005 end-loaded 리뷰 완료 FID 의 기계적 단계 생략 (verifying-evidence-ko → review-skip-pass.sh) ──
# 조건 충족 시 requesting·receiving-code-review-ko 를 호출하지 않고 security-review-ko 로 간다. 문구가 사라지면 두 skill 이 다시 매번 주입된다.
if has skills/verifying-evidence-ko/SKILL.md 'review-skip-pass\.sh' 'rc 0 .*호출하지 않고.*Skill: specops-ko:security-review-ko' 'rc 1 이면.*아래 기본 경로다' '판정이 애매하면 기본 경로다'; then
  ok "verifying-evidence-ko review-skip-pass fast path 존재 (rc 0 → security-review · rc 1 → 종전 · 애매하면 기본)"
else
  nope "verifying-evidence-ko review-skip-pass fast path 소실" "end-loaded FID 의 기계적 리뷰 단계 생략 문구 부재"
fi



# ── 20261005 서브에이전트 모델·effort 프로파일 — 구현자 sonnet·medium + 재dispatch 상향 규칙 ──
# 구현자는 기본 Sonnet 이고 BLOCKED·Phase B/C FAIL 재dispatch 때만 부모가 opus 로 1회 상향한다. 문구가 사라지면 상향 근거가 없어진다.
# shellcheck disable=SC2016  # 패턴 안의 백틱은 리터럴이다
if grep -qx 'model: sonnet' agents/implementer-ko.md && grep -qx 'effort: medium' agents/implementer-ko.md \
   && has skills/implementing-ko/SKILL.md '재dispatch 시 \(상향 규칙\)' '인자로 `opus` 를 지정해 \*\*1회 상향\*\*'; then
  ok "implementer-ko sonnet·medium + implementing-ko 재dispatch opus 1회 상향 규칙 존재"
else
  nope "implementer 프로파일·상향 규칙 소실" "implementer-ko frontmatter 또는 implementing-ko 상향 규칙 문구 부재"
fi


# ── 20261005 README 모델·effort 운용 가이드 — 프로파일 표·effort 우선순위·덮어쓰기·문서 미확인 고지 ──
# 사용자가 환경변수 우선순위와 덮어쓰기를 알아야 프로파일이 의도대로 적용된다. 절이 사라지면 안내가 끊긴다.
if has README.md '^## 모델 · effort 운용' 'CLAUDE_CODE_EFFORT_LEVEL' 'CLAUDE_CODE_SUBAGENT_MODEL_FORCE' '문서 미확인'; then
  ok "README 모델·effort 운용 가이드 존재 (우선순위·덮어쓰기·문서 미확인 고지)"
else
  nope "README 모델·effort 운용 가이드 소실" "프로파일 표·환경변수 우선순위·덮어쓰기·한계 고지 중 일부 부재"
fi

# ── 개발 구간 무질문 정책 (20261008-dev-no-ask) ─────────────
#   실측: 하류 3개 프로젝트의 개발 중 질문 40건 중 33건은 플러그인 게이트가 아니라 세션이 스스로 물은 것이었다.
#   정책 문서·본문 포인터·끝 보고 배선이 하나라도 빠지면 "묻지도 않고 알리지도 않는" 상태가 된다.
I=skills/implementing-ko/SKILL.md
A=skills/implementing-ko/dev-autonomy.md
P=skills/performance-test-ko/SKILL.md
if has "$I" '^## 개발 구간 무질문' 'dev-autonomy\.md' 'dev-decision\.sh'; then
  ok "implementing-ko: 개발 구간 무질문 절 + 보조 문서 포인터"
else
  nope "implementing-ko 무질문 포인터 소실" "dev-autonomy.md 를 읽으라는 지시가 없으면 정책이 적용되지 않는다"
fi
if ! grep -qE '자동 수정 전 확인|자동 진행 금지 — 사용자 입력 대기|자동 진행 금지, 사용자 결정 대기' "$I"; then
  ok "implementing-ko: 무질문과 충돌하는 옛 문장(자동 수정 전 확인·자동 진행 금지) 없음"
else
  nope "implementing-ko 충돌 문장 재등장" "리뷰 이슈마다 묻게 만드는 문장이 돌아왔다"
fi
if has "$I" '\*\*cap 초과 처리\*\* \(모드 무관' 'systematic-debugging-ko → 전역 재시도'; then
  ok "implementing-ko: cap 초과 처리가 모드 무관(전역 재시도 1회 뒤에만 정지)"
else
  nope "implementing-ko cap 초과 처리 모드 한정" "단일 모드가 cap 초과마다 묻는 종전 동작으로 돌아갔다"
fi
if has "$A" '시작 전 — 알려진 외부 작업은 한 번에 승인' '이전부터 있던 결함' 'AC·spec 문언을 바꿔야' '묻지 않고 만들지 않는다' \
            '그래도 멈추는 것' 'NEEDS_APPROVAL' 'NEEDS_DISCUSSION' 'Critical 미해결' 'dev-decision\.sh show'; then
  ok "dev-autonomy.md: 사전 승인 · 계약 안/밖 기준 · 멈추는 예외 · 끝 보고"
else
  nope "dev-autonomy.md 핵심 규칙 소실" "$A"
fi
if has "$P" 'dev-decision\.sh show <FID>' '줄이지 않고 그대로' 'show <FID> --backlog' '### 개발 중 결정'; then
  ok "performance-test-ko: PR 게이트 끝 보고(단일·§auto 다이제스트) + PR 본문 backlog"
else
  nope "PR 게이트 끝 보고 소실" "묻지 않고 정한 것을 사용자가 볼 지점이 없다"
fi
if has scripts/_internal/collect-assumptions.sh 'dev-decisions\.md' '개발 중 결정 · '; then
  ok "collect-assumptions: batch 다이제스트가 개발 중 결정을 모은다"
else
  nope "batch 다이제스트의 개발 중 결정 집계 소실" "/start-all 은 FR 별 PR 게이트가 없어 이 집계가 유일한 보고 지점이다"
fi
#   구현자 쪽 짝 — 부모가 묻지 않아도 구현자가 되물으면 같은 병이다
if has agents/implementer-ko.md '재확인 금지' 'NEEDS_APPROVAL'; then
  ok "implementer-ko: 재확인 금지 + 비가역 NEEDS_APPROVAL 유지"
else
  nope "implementer-ko 재확인 금지·NEEDS_APPROVAL 소실" "agents/implementer-ko.md"
fi
#   ★ 안전망 — 사전 승인 훑기에서 빠진 외부 쓰기는 구현자가 실행 직전에 잡아야 한다(리뷰 C1).
#     "삭제"만 승인 대상이면 실 DB 적재·과금 API 호출이 묻지 않고 실행된다.
if has agents/implementer-ko.md 'repo 밖에 흔적을 남기는 실행' '실 DB 쓰기' 'approval\.md.*승인 범위 안' \
   && has "$A" '두 층 중 하나만 믿지 않는다' "grep -nE 'irreversible:" \
   && has skills/decomposing-ko/SKILL.md '^## repo 밖 흔적 표지' 'external: "'; then
  ok "외부 작업 승인 2층: 구현자 NEEDS_APPROVAL(repo 밖 흔적) + 사전 승인 표지(external:)"
else
  nope "외부 작업 승인 안전망 소실" "implementer-ko 의 repo 밖 흔적 트리거 또는 external: 표지 규칙"
fi
#   넘길 수 없는 것 — 출처가 기존 코드여도 backlog 로 흘리지 않는다(리뷰 I3)
if has "$A" '넘길 수 없는 것' 'Phase B FAIL' '보안 스캔의 Critical/High' 'verify FAIL' 'git diff <base>\.\.\.HEAD'; then
  ok "dev-autonomy.md: 넘길 수 없는 것(B FAIL·Critical·보안 Critical/High·verify FAIL) + 소유 판정 기준"
else
  nope "dev-autonomy.md 넘길 수 없는 것 소실" "보안·스펙 미충족이 backlog 로 흘러 PR 까지 갈 수 있다"
fi
#   환경이 없어 못 돌린 게이트는 조용히 SKIP 하지 않는다(리뷰 I2) · 사전 승인된 태스크는 Step 0 을 다시 묻지 않는다(I4)
if has "$A" '실행 환경이 없어' '조용히 SKIP 하면 검증되지 않은 채' 'Step 0\(승인 요청\)을 다시 묻지 않는다' '재리뷰를 거친다' \
   && ! grep -qE '환경 미비로 실행 불가' "$A"; then
  ok "dev-autonomy.md: 환경 미비는 묻는다 · 사전 승인 뒤 재질문 없음 · 수정 라운드는 재리뷰"
else
  nope "dev-autonomy.md 환경·재질문·재리뷰 규칙 소실" "$A"
fi
if has skills/receiving-code-review-ko/SKILL.md 'dev-autonomy\.md. 가 우선한다' 'dev-decision\.sh add'; then
  ok "receiving-code-review-ko: chain 안에서는 무질문 정책이 우선"
else
  nope "receiving-code-review-ko 포인터 소실" "이 skill 의 '명확화 요청' 이 개발 구간에서 그대로 질문이 된다"
fi
if ! grep -qE '사용자 확인 후\*\* 진행|cap 초과 — 사용자 개입 필요|task 내부 Step 0 \(기존 동작\)' "$I"; then
  ok "implementing-ko: 남은 충돌 문장(설계 계약 이탈 확인·cap 사용자 개입·Step 0 재질문) 없음"
else
  nope "implementing-ko 충돌 문장 재등장" "설계 계약 이탈·cap 초과·irreversible Step 0"
fi

# ── 20261009 — 문서끼리 어긋나 모델 재량으로 넘어가던 지점 ──
# FR 보류 신호: 내는 쪽(implementing-ko·needs-approval)과 받는 쪽(start-all Phase 3)이 같은 토큰을 쓴다.
#   종전엔 "FR halt" 라는 산문뿐이라 받는 절차가 없었다 — 보류된 FR 을 어떻게 할지가 모델 재량이었다.
if has skills/implementing-ko/SKILL.md 'NEEDS_DISCUSSION.*BATCH-FR-HELD: <FID>' 'NEEDS_APPROVAL.*BATCH-FR-HELD: <FID>|BATCH-FR-HELD: <FID>.*halt' \
   && has skills/implementing-ko/needs-approval.md 'BATCH-FR-HELD: <FID>' \
   && has commands/start-all.md '^1b\. \*\*FR 보류 신호\*\*.*BATCH-FR-HELD: <FID>' 'queue-set-status\.sh .* HELD <FID>' \
   && has commands/start-all-auto.md 'BATCH-FR-HELD: <FID>.*HELD' '대신 승인하지 않는다'; then
  ok "FR 보류 신호 — 방출(implementing·needs-approval) ↔ 수신(start-all 1b · start-all-auto)"
else
  nope "FR 보류 신호" "방출·수신 중 한쪽에 BATCH-FR-HELD 가 없다"
fi
# 보류에서 돌아온 FR 의 리뷰 기준점은 다시 쓰지 않는다 · 보류 FR 은 Phase 3 완료 게이트에서 세 번째 답으로 되살린다
if has commands/start-all.md '파일이 이미 있으면 다시 쓰지 않는다' '`HELD` FR 이 있으면 FR 별 사유·선택지.*세 번째 답' \
   && ! grep -q '보류된 FR 에 의존하는 FR 이 구현 중 막히면' commands/start-all.md \
   && grep -q '보류(HELD) ${held}건은 자동으로 다시 돌지 않는다' scripts/_internal/batch-resume-check.sh \
   && has skills/implementing-ko/dev-autonomy.md 'BATCH-FR-HELD: <FID>'; then
  ok "FR 보류의 재개 — 리뷰 기준점 보존 · 완료 게이트의 세 번째 답 · 재개 안내"
else
  nope "FR 보류의 재개" "start-all 1a·완료 게이트 · batch-resume-check · dev-autonomy 중 빠진 곳이 있다"
fi
# batch 게이트 FAIL 뒤의 복귀: 곧장 재실행이 아니라 verify → 리뷰 → 실패한 Step
if has commands/start-all.md '게이트 FAIL 뒤의 복귀 \(Step A·B·C 공통\)' 'BATCH-REVIEW-DONE: <FID>.*받고' 'Step A\(보안\)부터' \
   && ! grep -qE 'systematic-debugging-ko`? → 수정 후 재실행' commands/start-all.md; then
  ok "batch 게이트 FAIL 복귀 — verify·리뷰를 거쳐 Step A(보안)부터 (곧장 재실행 문구 없음)"
else
  nope "batch 게이트 FAIL 복귀" "복귀 절이 없거나 '수정 후 재실행' 문구가 남았다"
fi
# 무인 모드의 plan 리뷰 한도 초과: 진입 경로와 무관하게 Critical 이 남으면 정지
if has skills/planning-ko/SKILL.md 'Critical≥1 이면 무인이라도 `HARD-GATE: plan-reviewer Critical cap' 'Critical=0\(Important 만 남음\)' \
   && grep -qF "grep -qE '^Critical:[[:space:]]*0([^0-9]|\$)' .specops/<FID>/plan-review.md" skills/planning-ko/SKILL.md \
   && has commands/start-auto.md 'plan-reviewer cap 초과 \|.*Critical 이 남으면 정지' \
   && has commands/maintain-auto.md 'plan-reviewer cap 초과 \|.*Critical 이 남으면 정지' \
   && has commands/start-all.md 'Critical≥1.*§auto 모두' \
   && [ "$(grep -cE '\^Critical:\[\[:space:\]\]\*0`? 줄이 (\*\*)?있을 때만' commands/start-all.md)" -ge 2 ]; then
  ok "무인 plan 리뷰 한도 초과 — 단일(/start-auto·/maintain-auto)·batch 모두 Critical 이면 정지"
else
  nope "무인 plan 리뷰 한도 초과" "진입 경로마다 답이 다르다"
fi
if grep -qE 'plan-reviewer cap 초과 \| 자동 통과( \(plan은 verify/review가 검증\))? \| ❌' commands/*.md; then
  nope "무인 plan 리뷰 — 낡은 행" "무조건 자동 통과 행이 남았다"
else
  ok "무인 plan 리뷰 — 무조건 자동 통과 행 없음"
fi
# SKIP 근거 인용: 게이트 문서 3종이 판정기(release-ready)와 같은 기준 — §유형 과 무관
_sk=0
for s in security-review-ko integration-test-ko performance-test-ko; do
  has "skills/$s/SKILL.md" '\*\*SKIP 근거 의무\*\* \(V3\).*`§유형` 과 무관' || _sk=1
  grep -q '§유형≠trivial SKIP 근거 의무' "skills/$s/SKILL.md" && _sk=1
done
[ "$_sk" -eq 0 ] && ok "SKIP 근거 인용 — 게이트 문서 3종이 §유형 과 무관하게 요구" || nope "SKIP 근거 인용" "trivial 면제 문구가 남았다(판정기는 면제하지 않는다)"
# 보안 단계 문서가 스크립트와 같은 말을 한다 — 스캐너가 없어도 SKIP 이 아니라 self-check only 접미다
if has skills/security-review-ko/SKILL.md 'self-check only — semgrep·gitleaks 미설치' '접미까지 그대로' \
   && ! grep -qE 'SECURITY: SKIP.*스캐너 미설치|스캐너 미설치 또는 jq 부재' skills/security-review-ko/SKILL.md \
   && grep -q 'self-check only — semgrep·gitleaks 미설치' scripts/security-scan.sh; then
  ok "보안 단계 — 스캐너 부재는 SKIP 이 아니라 self-check only (스크립트 출력과 일치)"
else
  nope "보안 단계 스캐너 부재 서술" "문서가 스크립트가 내지 않는 SECURITY: SKIP 을 안내한다"
fi
# 낡은 문구: foundation 크기 예외 · 메타 스킬의 Phase A 잔재 · plan 리뷰어 관점 수
if ! grep -q '`§auto`·`§batch`·`foundation` 만 경고 후 진행' templates/tasks.md \
   && ! grep -q 'Phase A 단독' skills/using-specops-ko/SKILL.md \
   && ! grep -q '4관점 엔지니어링 검증' agents/plan-reviewer-ko.md; then
  ok "낡은 문구 3건 없음 (foundation 크기 예외 · Phase A 단독 · 4관점)"
else
  nope "낡은 문구" "templates/tasks.md · using-specops-ko · plan-reviewer-ko 중 남은 것이 있다"
fi

# ── 20261011-claude-md-diet: CLAUDE.md 크기 래칫 + 이력 문서 존재 ──
# CLAUDE.md 는 매 세션 로드된다 — 사건 이력·근거는 docs/governance-history.md 로 두고 규칙만 남긴다(실측 32,368B → 29,000B 이하).
_cm_bytes=$(wc -c < "$PLUGIN/CLAUDE.md" | tr -d ' ')
_gh_secs=$(grep -c -E '^## [1-7]\. ' "$PLUGIN/docs/governance-history.md" 2>/dev/null || echo 0)
if [ "$_cm_bytes" -le 29000 ] && [ "$_gh_secs" -eq 7 ]; then
  ok "T-diet CLAUDE.md ${_cm_bytes}B ≤ 29000 · docs/governance-history.md 절 7개"
else
  nope "T-diet" "CLAUDE.md ${_cm_bytes}B (상한 29000) · governance-history 절 ${_gh_secs}/7 — 이력·근거는 docs 로"
fi

# 단일 대화형 plan 리뷰 한도 초과: Critical 0 이고 Important 를 모두 반영하면 묻지 않고 진행 · 아니면 정지 (20261019-plan-review-cap-autopass)
SKP=skills/planning-ko/SKILL.md
if has "$SKP" 'cap 초과 — 단일 대화형' 'Important 를 \*\*모두\*\* plan\.md 에 반영' 'dev-decision\.sh add <FID> skip' \
     'FAIL→진행\(Critical 0' 'HARD-GATE: plan-reviewer cap 초과 — 사용자 결정 필요' 'spec·AC 변경이나 사용자가 골라야 하는 Important · 애매함' \
   && has "$SKP" '\[§auto 모드\] 와 같은 grep 으로 Critical=0' 'Critical=0 이고 남은 Important' 'Critical≥1 · `Critical:` 줄 없음' 'CLAUDE_PLUGIN_ROOT\}"/scripts/dev-decision\.sh add <FID> skip' \
   && ! grep -qE '\(재dispatch 후 재검토\) \| `HARD-GATE: plan-reviewer cap 초과' "$SKP"; then
  ok "단일 plan 리뷰 한도 초과 — Critical 0·Important 반영이면 진행 · 기계 판정 재사용 · 아니면 정지"
else
  nope "단일 plan 리뷰 한도 초과" "단일 대화형 절·기계 판정·기록·정지 조건 중 빠진 것이 있다"
fi

# DB 설계 전문가 에이전트 — opus·high · Generator(evaluator 아님) · 산출 계약(파일 하나) · 사고 11규칙(굵은 이름 앵커) · 엔진 선택 (20261020-db-designer-agent)
_DBA=agents/db-designer-ko.md
# 규칙 이름만이 아니라 같은 줄의 본문 핵심구까지 잠근다 — 이름만 남기고 본문을 비워도 통과하던 구멍 (20261021 후속)
_dba_body_ok() {
  local pair name body
  for pair in '바인드 파라미터 상한|청크' 'created_at 보존|갱신 대상에서' '키 불균일 금지|합집합' '롤백 파일 위치|밖에 둔다' '적용 태스크|실제 DB 에 적용' \
              'ORM 과 DDL 제약 일치|create_all' '커밋 경계|재개 지점' '인덱스 선두 컬럼|선두로 한 인덱스' '문서와 구현 타입 일치|대조해' 'fixture 대상 확인|테스트 전용 DB' '롤백·재전환 행 보존|행 수를 직접 대조'; do
    name=${pair%%|*}; body=${pair#*|}
    grep -F -- "- **$name**:" "$_DBA" | grep -qF -- "$body" || return 1
  done
}
if [ -f "$_DBA" ] && has "$_DBA" '^model: opus$' '^effort: high$' '쓰는 파일은 `\.specops/<FID>/experts/db\.md` 하나뿐이다' 'db-expert/engines/' '§1 유형' '^## 받는 컨텍스트' 'data-model\.md' \
     '\*\*바인드 파라미터 상한\*\*' '\*\*created_at 보존\*\*' '\*\*키 불균일 금지\*\*' '\*\*롤백 파일 위치\*\*' '\*\*적용 태스크\*\*' '\*\*ORM 과 DDL 제약 일치\*\*' \
     '\*\*커밋 경계\*\*' '\*\*인덱스 선두 컬럼\*\*' '\*\*문서와 구현 타입 일치\*\*' '\*\*fixture 대상 확인\*\*' '\*\*롤백·재전환 행 보존\*\*' \
     'plan\.md.*직접 수정하지 않는다' '^## 빈 출력 규칙' '\*\*Bash 행동계약\*\*' 'psql' '청크' 'migrations/' \
     '\*\*확인한 사실 위에서만 심각도를 매긴다\*\*' '^## 확인 필요' '확인 필요 1> — 확인 결과' \
   && ! grep -q '^role: evaluator' "$_DBA" && ! grep -q '미대조' "$_DBA" && grep -q 'agents/ .*← 15건' README.md && grep -q '^| db-designer-ko' README.md \
   && _dba_body_ok; then
  ok "DB 설계 전문가 에이전트 — opus·high · 산출 파일 하나 · 사고 11규칙 · 확인 필요 절(심각도 없음) · 엔진 선택 · README 15건·모델 표"
else
  nope "DB 설계 전문가 에이전트" "파일·frontmatter·산출 계약·사고 규칙·엔진 선택·README 중 빠진 것이 있다"
fi

# DB 전문가 엔진 지식 파일 6개 — 출처·라이선스 머리 주석 · 미대조 없음 · 규칙 5줄 이상 (20261020-db-designer-agent)
_dbe_bad=""
for _e in postgres mysql oracle mssql mongodb redis; do
  _f="skills/planning-ko/db-expert/engines/$_e.md"
  if [ ! -f "$_f" ]; then _dbe_bad="$_dbe_bad $_e(없음)"; continue; fi
  head -1 "$_f" | grep -q 'reference_upstream:' || _dbe_bad="$_dbe_bad $_e(출처 주석)"
  head -1 "$_f" | grep -qE 'MIT|Apache-2\.0|공식 문서' || _dbe_bad="$_dbe_bad $_e(라이선스)"
  grep -q '미대조' "$_f" && _dbe_bad="$_dbe_bad $_e(미대조 잔존)"
  [ "$(grep -cE '^- ' "$_f")" -ge 5 ] || _dbe_bad="$_dbe_bad $_e(규칙 5줄 미만)"
done
grep -q '32767' skills/planning-ko/db-expert/engines/postgres.md || _dbe_bad="$_dbe_bad postgres(드라이버 상한 32767 누락)"
grep -q 'btree_gist' skills/planning-ko/db-expert/engines/postgres.md || _dbe_bad="$_dbe_bad postgres(btree_gist 누락)"
grep -qE 'NOT NULL[^.]*휘발성|휘발성 기본값\(`now' skills/planning-ko/db-expert/engines/postgres.md && _dbe_bad="$_dbe_bad postgres(now 휘발성 오기)"
# now() 는 비휘발 — '휘발성 기본값(…)' 괄호 목록 안에 now 가 있으면 위치·표기와 무관하게 오기, 비휘발 쪽에는 now 가 있어야 한다
perl -ne 'print "$1\n" while /(?<!비)(휘발성 기본값\(.*?`\))/g' skills/planning-ko/db-expert/engines/postgres.md | grep -qi 'now' && _dbe_bad="$_dbe_bad postgres(휘발성 목록에 now)"
grep -qE '비휘발 기본값' skills/planning-ko/db-expert/engines/postgres.md && grep -E '비휘발 기본값' skills/planning-ko/db-expert/engines/postgres.md | grep -q 'now' || _dbe_bad="$_dbe_bad postgres(비휘발에 now 누락)"
# 대량 INSERT 행 수는 고정값이 아니라 '상한 ÷ 컬럼 수' — 컬럼 33개 초과면 asyncpg 32767 을 넘는다(실사고 형태)
grep -q '≈1000행' skills/planning-ko/db-expert/engines/postgres.md && _dbe_bad="$_dbe_bad postgres(고정 행 수 권고)"
grep -qF '상한 ÷ 컬럼 수' skills/planning-ko/db-expert/engines/postgres.md && grep -qF 'asyncpg/protocol/prepared_stmt.pyx' skills/planning-ko/db-expert/engines/postgres.md || _dbe_bad="$_dbe_bad postgres(행 수 산식·asyncpg 출처 누락)"
[ -z "$_dbe_bad" ] && ok "DB 전문가 엔진 파일 6개 — 출처·라이선스 · 미대조 없음 · 규칙 ≥5" || nope "DB 전문가 엔진 파일" "$_dbe_bad"

# planning-ko DB 전문가 패스 — 경계 대조 뒤·plan-reviewer 전 · 비batch · 발동 조건 · dispatch · 반영 · 재검사 · 기록(DONE 금지) (20261020-db-designer-agent)
_PL=skills/planning-ko/SKILL.md
_l_db=$(grep -n '^### DB 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_bd=$(grep -n '^### 경계 대조 입력' "$_PL" | head -1 | cut -d: -f1)
_l_pr=$(grep -n '^### 비-batch — plan-reviewer dispatch' "$_PL" | head -1 | cut -d: -f1)
_l_dbend=$(awk -v s="$_l_db" 'NR>s && /^### /{print NR; exit}' "$_PL")   # DB 절 다음 제목 — 뒤에 붙는 전문가 절이 DB 검사를 대신 통과시키지 않게
if [ -n "$_l_db" ] && [ -n "$_l_dbend" ] && [ -n "$_l_bd" ] && [ -n "$_l_pr" ] && [ "$_l_bd" -lt "$_l_db" ] && [ "$_l_db" -lt "$_l_pr" ] \
   && has "$_PL" 'subagent_type: "specops-ko:db-designer-ko"' 'experts/db\.md' '\| db-expert \| db-designer-ko \| 반영 \|' 'DB 산출물' 'upsert' '대량 적재' 'data-model\.md' '테스트 DB fixture' '언급되기만 하고' '## 반영' '두 스크립트를 다시 실행' '\| db-expert \| - \| SKIP \|' '가용 모델' '산출 없음' \
   && sed -n "${_l_db},${_l_dbend}p" "$_PL" | grep -q '§batch' && ! sed -n "${_l_db},${_l_pr}p" "$_PL" | grep -E '^\| [^|]*\| [^|]*\| db-expert \|' | grep -qE 'DONE|IMPL' \
   && ! sed -n "${_l_db},${_l_pr}p" "$_PL" | grep -oE '`\| [^|`]* \| [^|`]* \| db-expert \|[^`]*`' | grep -qE 'DONE|IMPL'; then
  ok "planning-ko DB 전문가 패스 — 경계 대조 뒤·plan-reviewer 전 · 발동 조건 · dispatch · 반영 · 재검사 · 기록 · batch 제외"
else
  nope "planning-ko DB 전문가 패스" "위치(db=$_l_db bd=$_l_bd pr=$_l_pr) 또는 필수 문구 누락"
fi

# API 계약 전문가 에이전트 — opus·high · Generator · 산출 파일 하나 · 판정기 선실행·중복 금지 · 공통 원칙 13(이름·본문 짝) · 범위 경계 (20261021-api-designer-agent)
# Then 절별 같은 줄 연접 잠금 — 파일 전체 grep 이 다른 줄의 같은 구절로 통과하던 구멍(리뷰 B 2회)
_APA=agents/api-designer-ko.md
_apa_body_ok() {
  local pair name body
  for pair in '추가형 변경만|새 major' '폐기 표기와 유예|@deprecated' '관찰 가능한 동작은 계약|DB 스키마' '메서드 의미|PATCH' '응답 형태 하나|입력 타입' \
              '벌크 부분 실패|항목마다' '오류 형식 하나|섞지 않는다' '기계가 읽는 오류 코드|카탈로그' '필드 단위 검증 오류|되돌려 주지 않는다' \
              '커서에 정렬 컬럼 전부|유일' '페이지 메타데이터|has_more' '멱등 키는 의도에서|randomUUID' '멱등 키 재사용·보존|422'; do
    name=${pair%%|*}; body=${pair#*|}
    grep -F -- "- **$name**:" "$_APA" | grep -qF -- "$body" || return 1
    grep -F -- "- **$name**:" "$_APA" | grep -qE '출처: .*\(MIT\)' || return 1
  done
}
if [ -f "$_APA" ] && has "$_APA" '^model: opus$' '^effort: high$' '쓰는 파일은 `\.specops/<FID>/experts/api\.md` 하나뿐이다' \
     'CLAUDE_PLUGIN_ROOT\}"/scripts/_internal/check-api-contract\.sh <FID>' \
     'check-api-contract\.sh <FID>` 를 먼저 실행해 첫 줄과 rc 를 산출의 `## 판정기` 에 옮긴다.*판정기가 낸 위반.*다시 지적하지 않는다' \
     'api-expert/patterns/graphql\.md` \| api-spec §0 정의 방식이 GraphQL 이거나 plan 이 `\.graphql`·스키마·리졸버 파일을 만들거나 고칠 때' \
     '^- \*\*api-spec\.md 가 없으면\*\* plan 의 엔드포인트·태스크만으로 검토한다 — 판정기는 SKIP 을 내고, .*모두 `## 확인 필요` 로 낸다\.' \
     '^## 받는 컨텍스트' '^## 핵심 규칙' '^## 공통 원칙' '^## 빈 출력 규칙' '^## 확인 필요' '^## 하지 말 것' \
     '\*\*엇갈리는 규약\*\*.*한쪽을 강요하지 않는다\. api-spec 에 정한 규약과 plan 이 어긋날 때만 지적하고, 정하지 않았으면 `## 확인 필요` 로 묻는다' \
     'RFC 9457' '\*\*확인한 사실 위에서만 심각도를 매긴다\*\*' '\*\*Bash 행동계약\*\*' 'plan\.md.*직접 수정하지 않는다' \
     '멱등 키 선점의 원자성\(유일 제약\)은 \*\*DB 전문가\*\* 몫이고, 인증·인가는 \*\*보안\*\* 분야, 타임아웃·재시도 정책\(횟수·백오프\)은 구조 분야다.*단 오류 응답의 입력값 반사는.*원칙 9' \
   && ! grep -q '^role: evaluator' "$_APA" && grep -q 'agents/ .*← 15건' README.md && grep -q '^| api-designer-ko' README.md \
   && _apa_body_ok; then
  ok "API 계약 전문가 에이전트 — opus·high · 산출 파일 하나 · 판정기 선실행 · 공통 원칙 13(이름·본문·출처) · 엇갈리는 규약 · README 15건·모델 표"
else
  nope "API 계약 전문가 에이전트" "파일·frontmatter·판정기 연계·원칙 13·범위 경계·README 중 빠진 것이 있다"
fi

# API 전문가 GraphQL 지식 파일 — 출처·라이선스 머리 주석 · 규칙 10줄 이상 · 핵심 규칙 앵커 (20261021-api-designer-agent)
_apg=skills/planning-ko/api-expert/patterns/graphql.md
_apg_bad=""
if [ ! -f "$_apg" ]; then _apg_bad=" 파일 없음"; else
  head -1 "$_apg" | grep -q 'reference_upstream:' || _apg_bad="$_apg_bad 출처 주석"
  head -1 "$_apg" | grep -q 'MIT' || _apg_bad="$_apg_bad 라이선스"
  [ "$(grep -cE '^- ' "$_apg")" -ge 10 ] || _apg_bad="$_apg_bad 규칙 10줄 미만"
  for _k in 'DataLoader' 'pageInfo' '@deprecated' 'graphql-ws' '인자 하나짜리 `input` 타입'; do grep -q -- "$_k" "$_apg" || _apg_bad="$_apg_bad $_k"; done
fi
[ -z "$_apg_bad" ] && ok "API 전문가 GraphQL 지식 파일 — 출처·라이선스 · 규칙 ≥10 · 핵심 앵커" || nope "API 전문가 GraphQL 지식 파일" "$_apg_bad"

# planning-ko API 전문가 패스 — DB 뒤·보안 앞(DB → API → 보안 → 테스트 → plan-reviewer) · 발동 조건 · dispatch · 반영 · 재검사 한 번 · 기록 3종(DONE 금지) · batch 제외 · 하위 제목 없음
#   문구는 API 절 범위(다음 `### ` 앞까지)에서만 찾는다 — 파일 전체 grep 은 다른 절의 같은 문구로 통과했다 (20261021-api-designer-agent · 범위 교정 20261022-api-expert-integrate)
_l_db3=$(grep -n '^### DB 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_api=$(grep -n '^### API 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_sec3=$(grep -n '^### 보안 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_tst3=$(grep -n '^### 테스트 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_pr3=$(grep -n '^### 비-batch — plan-reviewer dispatch' "$_PL" | head -1 | cut -d: -f1)
_l_apiend=""; _api_body=""
if [ -n "$_l_api" ]; then
  _l_apiend=$(awk -v s="$_l_api" 'NR>s && /^### /{print NR; exit}' "$_PL")
  [ -n "$_l_apiend" ] && _api_body=$(sed -n "${_l_api},$((_l_apiend-1))p" "$_PL")
fi
_api_has() { local p; for p in "$@"; do printf '%s\n' "$_api_body" | grep -qE -- "$p" || return 1; done; return 0; }
if [ -n "$_l_db3" ] && [ -n "$_l_apiend" ] && [ -n "$_l_sec3" ] && [ -n "$_l_tst3" ] && [ -n "$_l_pr3" ] \
   && [ "$_l_db3" -lt "$_l_api" ] && [ "$_l_api" -lt "$_l_sec3" ] && [ "$_l_sec3" -lt "$_l_tst3" ] && [ "$_l_tst3" -lt "$_l_pr3" ] \
   && _api_has 'subagent_type: "specops-ko:api-designer-ko"' 'experts/api\.md' '\| api-expert \| api-designer-ko \| 반영 \|' '\| api-expert \| - \| SKIP \|' '\| api-expert \| api-designer-ko \| 산출 없음 \|' \
        '엔드포인트를 추가·변경·삭제' '라우트·컨트롤러·GraphQL 스키마' 'api-expert/patterns/' '`§batch` 는 이 패스 미적용' '마지막 전문가 패스 뒤에 한 번만' \
   && [ "$(printf '%s\n' "$_api_body" | sed 1d | grep -c '^#')" -eq 0 ] \
   && ! printf '%s\n' "$_api_body" | grep -E '^\| [^|]*\| [^|]*\| api-expert \|' | grep -qE 'DONE|IMPL' \
   && ! printf '%s\n' "$_api_body" | grep -oE '`\| [^|`]* \| [^|`]* \| api-expert \|[^`]*`' | grep -qE 'DONE|IMPL' \
   && sed -n "${_l_sec3},$((_l_tst3-1))p" "$_PL" | grep -q 'API 전문가 패스 뒤' && ! sed -n "${_l_sec3},$((_l_tst3-1))p" "$_PL" | grep -q 'DB 전문가 패스 뒤' \
   && _l_dbend3=$(awk -v s="$_l_db3" 'NR>s && /^### /{print NR; exit}' "$_PL") && [ -n "$_l_dbend3" ] \
   && sed -n "${_l_db3},$((_l_dbend3-1))p" "$_PL" | grep -qF '뒤의 전문가 패스(구조·API·보안·테스트)' \
   && sed -n "$((_l_api+1)),$((_l_apiend-1))p" "$_PL" | grep -m1 -v '^$' | grep -q '^구조 전문가 패스 뒤, plan-reviewer 를 부르기'; then
  ok "planning-ko API 전문가 패스 — DB → API → 보안 → 테스트 순 · 절 범위 문구 · 재검사 한 번 · 기록 3종 · batch 제외 · 앞뒤 절 순서 문구"
else
  nope "planning-ko API 전문가 패스" "위치(db=$_l_db3 api=$_l_api end=$_l_apiend sec=$_l_sec3 tst=$_l_tst3 pr=$_l_pr3) · 절 범위 문구 · 순서 문구 · DONE 행 중 문제"
fi

# 보안 설계 전문가 에이전트 — opus·high · Generator · 산출 파일 하나 · 판정기 선실행·중복 금지 · 질문 틀 · 공통 원칙 16(이름·본문·출처 같은 줄) · 범위 경계 (20261021-security-designer-agent)
# Then 절별 같은 줄 연접 잠금 — 파일 전체 grep 이 다른 줄의 같은 구절로 통과하던 구멍(API 전문가 리뷰 B 2회)
_SDA=agents/security-designer-ko.md
_sda_body_ok() {
  local pair name body
  for pair in '남용 사례와 거부 AC|미인증 거부' '보호 엔드포인트마다 인증|컨텍스트 층' '인증 방식과 토큰 보관|httpOnly' '토큰 수명·폐기·검증|해시' \
              '인증 엔드포인트 시도 한도|공유 저장소' '재설정·복구|1회용' '기능 수준 인가|역할·scope' '객체 수준 인가|BOLA' \
              '바꿀 수 있는 필드 허용 목록|mass assignment' '경계에서 스키마 검증|파싱된 값' '데이터에서 온 경로의 파괴 작업|허용 루트' \
              '응답 민감 필드|응답 전용 타입' '개인정보 분류·최소화|목적' '보존기간과 실제 삭제 경로|백업' '쿠키 인증이면 CSRF|SameSite' '보안 이벤트 기록|로그에 남기지 않는다'; do
    name=${pair%%|*}; body=${pair#*|}
    grep -F -- "- **$name**:" "$_SDA" | grep -qF -- "$body" || return 1
    grep -F -- "- **$name**:" "$_SDA" | grep -qE '출처: .*\(MIT\)' || return 1
  done
}
# 산출 형식에서 신뢰 경계·자산 절이 지적 절보다 먼저 온다
_sda_order_ok() {
  local b j
  b=$(grep -n '^## 신뢰 경계·자산$' "$_SDA" | head -1 | cut -d: -f1); j=$(grep -n '^## 지적$' "$_SDA" | head -1 | cut -d: -f1)
  [ -n "$b" ] && [ -n "$j" ] && [ "$b" -lt "$j" ]
}
if [ -f "$_SDA" ] && has "$_SDA" '^model: opus$' '^effort: high$' '쓰는 파일은 `\.specops/<FID>/experts/security\.md` 하나뿐이다' \
     'CLAUDE_PLUGIN_ROOT\}"/scripts/_internal/check-security-design\.sh <FID>` 를 먼저 실행해 첫 줄과 rc 를 산출의 `## 판정기` 에 옮긴다.*판정기가 낸 위반.*다시 지적하지 않는다' \
     '^- \*\*STRIDE 는 이번 FID 의 경계만\*\*: 이번 FID 가 만들거나 바꾸는 경계마다 STRIDE 6범주\(위장·변조·부인·노출·서비스 거부·권한 상승\)를 묻고, 기존 경계는 다시 보지 않는다' \
     '^- \*\*신뢰 경계·자산 먼저\*\*:.*산출의 `## 신뢰 경계·자산` 에 먼저 적는다' \
     '^\*\*확인한 사실 위에서만 심각도를 매긴다\*\*:.*`## 확인 필요` 절에 질문 1줄로 적고 심각도를 매기지 않는다' \
     '^- \*\*api-spec\.md 가 없으면\*\* plan 의 파일·태스크만으로 검토한다 — 판정기 SKIP 을 산출에 적고, .*`## 확인 필요` 로 낸다\.' \
     '쿼리 쪽 권한\(RLS·GRANT·SECURITY DEFINER\)은 \*\*DB 전문가\*\*, 타임아웃·재시도는 \*\*구조\*\* 분야, 오류 형식·오류 응답의 입력값 반사·일반 rate limit 은 \*\*API 전문가\*\* 몫이고, 보안 전문가는 인증 엔드포인트 전용 한도만 본다' \
     '^- plan\.md·api-spec\.md·data-model\.md·spec\.md 는 직접 수정하지 않는다' \
     'security-expert/patterns/ssrf-upload-webhook\.md` \| plan 이 서버에서 사용자가 준 URL 을 가져오거나·파일 업로드·웹훅 수신' \
     'security-expert/patterns/llm\.md` \| plan 이 LLM 을 호출하거나' \
     'security-expert/patterns/browser-session\.md` \| 브라우저 클라이언트가 쿠키·세션·CORS' \
     'security-expert/patterns/oauth\.md` \| plan 이 OAuth·OIDC' \
     '^## 받는 컨텍스트' '^## 작업 순서' '^## 질문 틀' '^## 핵심 규칙' '^## 공통 원칙' '^## 범위 경계' '^## 빈 출력 규칙' '^## 산출' '^## 하지 말 것' \
     '\*\*Bash 행동계약\*\*' \
   && ! grep -q '^role: evaluator' "$_SDA" && grep -q 'agents/ .*← 15건' README.md && grep -q '^| security-designer-ko' README.md \
   && _sda_order_ok && _sda_body_ok; then
  ok "보안 설계 전문가 에이전트 — opus·high · 산출 파일 하나 · 판정기 선실행 · 질문 틀(경계 먼저·STRIDE 는 이번 FID) · 원칙 16(이름·본문·출처) · 범위 경계 · README 15건·모델 표"
else
  nope "보안 설계 전문가 에이전트" "파일·frontmatter·판정기 연계·질문 틀·원칙 16·범위 경계·패턴 표·README 중 빠진 것이 있다"
fi

# 보안 전문가 2층 패턴 파일 — 파일마다 출처·라이선스 머리 주석 · 규칙 4줄 이상 · 핵심 앵커 (20261021-security-designer-agent)
for _f in 'ssrf-upload-webhook|DNS 레코드를 \*\*전부\*\*|magic bytes|HMAC' 'llm|LLM05|LLM01|테넌트별' 'browser-session|httpOnly|SameSite|credentials' 'oauth|PKCE\(S256 만\)|Implicit|scope'; do
  _n=${_f%%|*}; _p=skills/planning-ko/security-expert/patterns/$_n.md; _sdp_bad=""
  if [ ! -f "$_p" ]; then _sdp_bad=" 파일 없음"; else
    head -1 "$_p" | grep -q 'reference_upstream:' || _sdp_bad="$_sdp_bad 출처 주석"
    head -1 "$_p" | grep -q 'MIT' || _sdp_bad="$_sdp_bad 라이선스"
    [ "$(grep -cE '^- ' "$_p")" -ge 4 ] || _sdp_bad="$_sdp_bad 규칙 4줄 미만"
    _rest=${_f#*|}
    while :; do _k=${_rest%%|*}; grep -qE -- "$_k" "$_p" || _sdp_bad="$_sdp_bad $_k"; [ "$_rest" = "$_k" ] && break; _rest=${_rest#*|}; done
  fi
  [ -z "$_sdp_bad" ] && ok "보안 전문가 패턴 파일 $_n — 출처·라이선스 · 규칙 ≥4 · 핵심 앵커" || nope "보안 전문가 패턴 파일 $_n" "$_sdp_bad"
done

# planning-ko 보안 전문가 패스 — API 패스 뒤·plan-reviewer 전 · 발동 조건 · 판정기 [승인 대상] · dispatch · 반영 · 재검사 한 번 · 기록 3종(DONE 금지) · batch 제외 · 하위 제목 없음 (20261021-security-designer-agent)
_l_db4=$(grep -n '^### DB 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_sec=$(grep -n '^### 보안 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_pr4=$(grep -n '^### 비-batch — plan-reviewer dispatch' "$_PL" | head -1 | cut -d: -f1)
_l_secend=$(awk -v s="$_l_sec" 'NR>s && /^### /{print NR; exit}' "$_PL")   # 보안 절 다음 제목 — 뒤에 붙는 전문가 절이 보안 검사를 대신 통과시키지 않게
if [ -n "$_l_secend" ] && [ -n "$_l_db4" ] && [ -n "$_l_sec" ] && [ -n "$_l_pr4" ] && [ "$_l_db4" -lt "$_l_sec" ] && [ "$_l_sec" -lt "$_l_pr4" ] \
   && has "$_PL" 'subagent_type: "specops-ko:security-designer-ko"' 'experts/security\.md' '\| security-expert \| security-designer-ko \| 반영 \|' '\| security-expert \| - \| SKIP \|' '\| security-expert \| security-designer-ko \| 산출 없음 \|' \
        '\*\*인증·인가·세션\*\*.*\*\*외부 입력 경계\*\*.*\*\*개인정보 필드\*\*.*만들거나 바꾸면 발동한다' '판단 전에 `bash "\$\{CLAUDE_PLUGIN_ROOT\}"/scripts/_internal/check-security-design\.sh <FID>` 를 한 번 실행해 `\[승인 대상\]` 줄이 있으면 발동한다' 'security-expert/patterns/' \
   && sed -n "${_l_sec},${_l_secend}p" "$_PL" | grep -q '`§batch` 는 이 패스 미적용' && sed -n "${_l_sec},${_l_secend}p" "$_PL" | grep -q '마지막 전문가 패스 뒤에 한 번만' \
   && [ "$(sed -n "$((_l_sec+1)),$((_l_secend-1))p" "$_PL" | grep -c '^#')" -eq 0 ] \
   && ! sed -n "${_l_sec},${_l_secend}p" "$_PL" | grep -E '^\| [^|]*\| [^|]*\| security-expert \|' | grep -qE 'DONE|IMPL' \
   && ! sed -n "${_l_sec},${_l_secend}p" "$_PL" | grep -oE '`\| [^|`]* \| [^|`]* \| security-expert \|[^`]*`' | grep -qE 'DONE|IMPL'; then
  ok "planning-ko 보안 전문가 패스 — API 패스 뒤·plan-reviewer 전 · 발동 조건 · 판정기 승인 대상 · dispatch · 반영 · 재검사 한 번 · 기록 3종 · batch 제외"
else
  nope "planning-ko 보안 전문가 패스" "위치(db=$_l_db4 sec=$_l_sec pr=$_l_pr4) · 필수 문구 · 하위 제목 · DONE 행 중 문제"
fi

# 요구사항 이해 전문가 에이전트 — opus·high · Generator · 산출 파일 하나 · 빈칸 증명(찾은 곳·빈칸) · 핵심 규칙 12(이름·근거 같은 줄) · 공통 원칙 5(출처 같은 줄) · README 15건·모델 표 (20261023-req-expert-integrate)
_RQA=agents/req-designer-ko.md
_rqa_rules_ok() {
  local name
  for name in '필드 상태마다 뜻' '결측이 섞인 계산' '유효 범위와 범위 밖 처리' '빈 결과의 원인별 결과' '실패 단위' '셈의 축' \
              '보장의 주체' '실제 진입점까지' '버리는 경로의 신호' '기록의 위치와 주체' '비교 기준의 출처' '마스터 문서와 다른 값'; do
    grep -F -- "- **$name**:" "$_RQA" | grep -qE '근거: Argus 2026[0-9]{4}-' || return 1
  done
  for name in '공유 경계는 한 곳에 정의' '흐린 말은 시나리오로' '검증 가능한 성공 기준' '엣지 케이스는 spec 에서' '결정은 사용자에게, 질문은 하나씩'; do
    grep -F -- "- **$name**:" "$_RQA" | grep -qE '출처: .*\(MIT\)' || return 1
  done
  [ "$(awk '/^## 핵심 규칙/{f=1;next} /^## /{f=0} f' "$_RQA" | grep -c '^- \*\*')" -eq 12 ] && [ "$(awk '/^## 공통 원칙/{f=1;next} /^## /{f=0} f' "$_RQA" | grep -c '^- \*\*')" -eq 5 ] || return 1
}
if [ -f "$_RQA" ] && has "$_RQA" '^name: req-designer-ko$' '^model: opus$' '^effort: high$' '쓰는 파일은 `\.specops/<FID>/experts/req\.md` 하나뿐이다' \
     '^## 받는 컨텍스트' '^## 작업 순서' '^## 핵심 규칙' '^## 공통 원칙' '^## 범위 경계' '^### Important 의 자격 — 빈칸 증명' '^## 빈 출력 규칙' '^## 산출' '^## 하지 말 것' \
     '`찾은 곳:`' '`빈칸:`' 'Important 는 많아야 5건' '\*\*`## 확인 필요` 질문으로만\*\*' '\*\*확인한 사실 위에서만 심각도를 매긴다\*\*' '\*\*Bash 행동계약\*\*' \
   && ! grep -q '^role: evaluator' "$_RQA" && grep -q 'agents/ .*← 15건 .*req-designer' README.md && grep -qE '^\| req-designer-ko .*\| opus · high \|' README.md \
   && _rqa_rules_ok; then
  ok "요구사항 이해 전문가 에이전트 — opus·high · 산출 파일 하나 · 빈칸 증명 · 핵심 규칙 12(근거) · 공통 원칙 5(출처) · README 15건·모델 표"
else
  nope "요구사항 이해 전문가 에이전트" "파일·frontmatter·빈칸 증명·핵심 규칙·공통 원칙·README 중 빠진 것이 있다"
fi

# 화면·UX 전문가 에이전트 — opus·high · Generator · 산출 파일 하나 · 빈칸 증명(찾은 곳·빈칸) · 핵심 규칙 8(이름·근거 같은 줄) · 공통 원칙 4(출처 같은 줄) · Critical 없음 · README 15건·모델 표 (20261023-ui-expert-integrate)
_UIA=agents/ui-designer-ko.md
_uia_rules_ok() {
  local name
  for name in '로딩·오류·0건 구분' '일부 실패' '공통 컴포넌트 계약 대조' '색만으로 전달 금지' '알림 수준' '같은 목적 입력의 동작 통일' '근거 없는 라벨 금지' '앞서 가는 화면 값'; do
    grep -F -- "- **$name**:" "$_UIA" | grep -qE '근거: Argus 2026[0-9]{4}-' || return 1
  done
  for name in '안내 문구의 실행 가능성' '디자인 토큰 밖 색' '포커스 이동' '부분 데이터가 없는 것보다 낫다'; do
    grep -F -- "- **$name**:" "$_UIA" | grep -qE '출처: .*\((MIT|Apache-2\.0)\)' || return 1
  done
  [ "$(awk '/^## 핵심 규칙/{f=1;next} /^## /{f=0} f' "$_UIA" | grep -c '^- \*\*')" -eq 8 ] && [ "$(awk '/^## 공통 원칙/{f=1;next} /^## /{f=0} f' "$_UIA" | grep -c '^- \*\*')" -eq 4 ] || return 1
}
if [ -f "$_UIA" ] && has "$_UIA" '^name: ui-designer-ko$' '^model: opus$' '^effort: high$' '쓰는 파일은 `\.specops/<FID>/experts/ui\.md` 하나뿐이다' \
     '^## 받는 컨텍스트' '^## 작업 순서' '^## 핵심 규칙' '^## 공통 원칙' '^## 범위 경계' '^### Important 의 자격 — 빈칸 증명' '^## 빈 출력 규칙' '^## 산출' '^## 하지 말 것' \
     '`찾은 곳:`' '`빈칸:`' 'Important 는 많아야 5건' '\*\*`## 확인 필요` 질문으로만\*\*' 'Critical 은 쓰지 않는다' '\*\*확인한 사실 위에서만 심각도를 매긴다\*\*' '\*\*Bash 행동계약\*\*' \
   && ! grep -q '^role: evaluator' "$_UIA" && grep -q 'agents/ .*← 15건 .*ui-designer' README.md && grep -qE '^\| ui-designer-ko .*\| opus · high \|' README.md \
   && _uia_rules_ok; then
  ok "화면·UX 전문가 에이전트 — opus·high · 산출 파일 하나 · 빈칸 증명 · 핵심 규칙 8(근거) · 공통 원칙 4(출처) · Critical 없음 · README 15건·모델 표"
else
  nope "화면·UX 전문가 에이전트" "파일·frontmatter·빈칸 증명·핵심 규칙·공통 원칙·README 중 빠진 것이 있다"
fi

# 구조 설계 전문가 에이전트 — opus·high · Generator · 산출 파일 하나 · 판정기 읽기 · 패턴 선택 5종 · 핵심 규칙 1(근거) · 공통 원칙 10(이름·본문·출처) · 근거 인용(찾은 곳·영향) · README 15건·모델 표 (20261023-arch-expert-integrate · #219 블록 확장)
_ARA=agents/arch-designer-ko.md
_ara_body_ok() {
  local pair name body
  for pair in '얕은 통과 모듈 금지|삭제 테스트' '인터페이스는 호출자가 알아야 할 전부|불변식' '이음새는 어댑터 둘일 때|둘 이상' '의존성 4분류|소유한 원격' '의존 방향은 안쪽으로|포트를 import' \
              '순환 금지|구체 어댑터' '컨텍스트 간 엔티티 직접 import 금지|번역 계층' '집합체는 일관성 경계|불변식 목록' '값 객체는 생성 시점에 검증|생성자' 'DDD 는 필요할 때만|둘 이상'; do
    name=${pair%%|*}; body=${pair#*|}
    grep -F -- "- **$name**:" "$_ARA" | grep -qF -- "$body" || return 1
    grep -F -- "- **$name**:" "$_ARA" | grep -qE '출처: .*\(MIT\)' || return 1
  done
  grep -F -- '- **프로세스 전역 설정을 바꾸는 호출**:' "$_ARA" | grep -qE '근거: Argus 2026[0-9]{4}-' || return 1
  [ "$(awk '/^## 핵심 규칙/{f=1;next} /^## /{f=0} f' "$_ARA" | grep -c '^- \*\*')" -eq 1 ] && [ "$(awk '/^## 공통 원칙/{f=1;next} /^## /{f=0} f' "$_ARA" | grep -c '^- \*\*')" -eq 10 ] || return 1
}
if [ -f "$_ARA" ] && has "$_ARA" '^name: arch-designer-ko$' '^model: opus$' '^effort: high$' 'bash "\$\{CLAUDE_PLUGIN_ROOT\}"/scripts/_internal/check-import-direction\.sh' '쓰는 파일은 `\.specops/<FID>/experts/arch\.md` 하나뿐이다' 'arch-expert/patterns/' \
     '^## 받는 컨텍스트' '^## 작업 순서' '^## 핵심 규칙' '^## 공통 원칙' '^## 빈 출력 규칙' '^## 산출' '^## 하지 말 것' \
     'backend-layered-clean\.md' 'backend-distributed\.md' 'backend-runtime\.md' 'frontend-react\.md' 'frontend-nextjs\.md' \
     'plan\.md.*직접 수정하지 않는다' '\*\*Bash 행동계약\*\*' '\*\*확인한 사실 위에서만 심각도를 매긴다\*\*' '문서화된 기본 동작' '^## 확인 필요' '확인 필요 1> — 확인 결과' \
     '^### Critical·Important 의 자격 — 근거 인용' '`찾은 곳:`' '`영향:`' '합쳐 많아야 5건' '\*\*`## 확인 필요` 질문으로만\*\*' \
   && ! grep -q '^role: evaluator' "$_ARA" && grep -q 'agents/ .*← 15건 .*arch-designer' README.md && grep -qE '^\| arch-designer-ko .*\| opus · high \|' README.md \
   && _ara_body_ok; then
  ok "구조 설계 전문가 에이전트 — opus·high · 산출 파일 하나 · 판정기 · 패턴 5종 · 핵심 규칙 1(근거) · 공통 원칙 10(출처) · 근거 인용 · README 15건·모델 표"
else
  nope "구조 설계 전문가 에이전트" "파일·frontmatter·산출 계약·규칙·근거 인용·README 중 빠진 것이 있다"
fi

# 구조 전문가 패턴 파일 5개 — 출처·라이선스 머리 주석 · 규칙 수 6·6·7·6·6 · 원문에 없는 규칙은 표시 (20261021-arch-designer-agent · 20261023-arch-expert-integrate 이식)
_arp_bad=""
for _en in backend-layered-clean:6 backend-distributed:6 backend-runtime:7 frontend-react:6 frontend-nextjs:6; do
  _e=${_en%%:*}; _n=${_en#*:}
  _f="skills/planning-ko/arch-expert/patterns/$_e.md"
  if [ ! -f "$_f" ]; then _arp_bad="$_arp_bad $_e(없음)"; continue; fi
  head -1 "$_f" | grep -q 'reference_upstream: wshobson/agents@0874a27' || _arp_bad="$_arp_bad $_e(출처 주석)"
  head -1 "$_f" | grep -q 'MIT' || _arp_bad="$_arp_bad $_e(라이선스)"
  [ "$(grep -cE '^- ' "$_f")" -eq "$_n" ] || _arp_bad="$_arp_bad $_e(규칙 수 $_n 아님)"
done
grep -q '멱등.*specops-ko 추가' skills/planning-ko/arch-expert/patterns/backend-distributed.md 2>/dev/null || _arp_bad="$_arp_bad distributed(추가 규칙 표시 누락)"
grep -q '직렬화할 수 있는 값' skills/planning-ko/arch-expert/patterns/frontend-nextjs.md 2>/dev/null || _arp_bad="$_arp_bad nextjs(직렬화 규칙 방향)"
grep -q '단순 CRUD 는 엔티티 단위 저장소' skills/planning-ko/arch-expert/patterns/backend-layered-clean.md 2>/dev/null || _arp_bad="$_arp_bad layered-clean(집합체 저장소는 DDD 조건부)"
[ -z "$_arp_bad" ] && ok "구조 전문가 패턴 파일 5개 — 출처·라이선스 · 규칙 수 6·6·7·6·6 · 추가 규칙 표시" || nope "구조 전문가 패턴 파일" "$_arp_bad"

# 테스트 설계 전문가 에이전트 — opus·high · Generator · 산출 파일 하나 · 핵심 규칙 4(이름·본문·근거 같은 줄) · 공통 원칙 11(이름·본문·출처 같은 줄) · 설계표 변이 열 · 범위 경계 (20261022-test-designer-agent)
_TDA=agents/test-designer-ko.md
_tda_rules_ok() {
  local pair name body
  for pair in '떨어뜨리는 잘못된 구현|이름 붙여' '값까지 묶는 단언|부분집합' '규칙을 태우는 픽스처|경계값' '가드 테스트 3요건|대상이 0개'; do
    name=${pair%%|*}; body=${pair#*|}
    grep -F -- "- **$name**:" "$_TDA" | grep -qF -- "$body" || return 1
    grep -F -- "- **$name**:" "$_TDA" | grep -qE '근거: Argus 2026[0-9]{4}-' || return 1
  done
  for pair in '기대값의 독립 출처|다시 계산' '실패 경로마다 테스트|CancelledError' '목은 기준 바깥 경계에|통째로' '대역은 계약을 지킨다|로그 레벨' \
              '외부 서비스는 기본 차단|fail-closed' '로그 기준은 내용을 단언|레벨' '부재 단언에 양성 대조|문구가 바뀌어도' '수·집합 단언 승계|grep' \
              '테스트 격리|순서에 의존' '공개 인터페이스로 검증|내부 협력자' '위험 영역에 집중|test-strategy'; do
    name=${pair%%|*}; body=${pair#*|}
    grep -F -- "- **$name**:" "$_TDA" | grep -qF -- "$body" || return 1
    grep -F -- "- **$name**:" "$_TDA" | grep -qF -- '출처: ' || return 1
  done
}
if [ -f "$_TDA" ] && has "$_TDA" '^model: opus$' '^effort: high$' '^reference_upstream: mattpocock/skills@5beb35b' '쓰는 파일은 `\.specops/<FID>/experts/test\.md` 하나뿐이다' \
     '^## 받는 컨텍스트' '^## 작업 순서' '^## 핵심 규칙' '^## 공통 원칙' '^## 범위 경계' '^## 빈 출력 규칙' '^## 산출' '^## 하지 말 것' \
     'acceptance-criteria\.md' 'test-strategy\.md' '^## 수용 기준별 테스트 설계$' '^## 지적$' '^## 확인 필요' '\| AC \| 테스트 \| 떨어뜨리는 잘못된 구현 \| 단언\(값까지\) \| 픽스처가 태우는 경계 \|' \
     '`must` AC 는 모두 한 행씩 쓴다' '^\*\*확인한 사실 위에서만 심각도를 매긴다\*\*:' '테스트 DB 환경.*\*\*DB 전문가\*\*' \
     '^- plan\.md·spec\.md·acceptance-criteria\.md 는 직접 수정하지 않는다' '\*\*Bash 행동계약\*\*' \
   && ! grep -q '^role: evaluator' "$_TDA" && grep -q 'agents/ .*← 15건 .*test-designer' README.md && grep -q '^| test-designer-ko' README.md \
   && _tda_rules_ok; then
  ok "테스트 설계 전문가 에이전트 — opus·high · 산출 파일 하나 · 핵심 규칙 4(근거) · 공통 원칙 11(출처) · 설계표 변이 열 · 범위 경계 · README 15건·모델 표"
else
  nope "테스트 설계 전문가 에이전트" "파일·frontmatter·산출 계약·핵심 규칙·공통 원칙·설계표·범위 경계·README 중 빠진 것이 있다"
fi

# planning-ko 테스트 전문가 패스 — 보안 패스 뒤·plan-reviewer 전 · 발동 조건(테스트 파일) · dispatch · 반영(변이 칸을 테스트 스텝으로) · 재검사 한 번 · 기록 3종(DONE 금지) · batch 제외 · 하위 제목 없음 (20261022-test-designer-agent)
_l_sec5=$(grep -n '^### 보안 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_tst=$(grep -n '^### 테스트 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_pr5=$(grep -n '^### 비-batch — plan-reviewer dispatch' "$_PL" | head -1 | cut -d: -f1)
_l_tstend=$(awk -v s="$_l_tst" 'NR>s && /^### /{print NR; exit}' "$_PL")   # 테스트 절 다음 제목 — 뒤에 절이 더 붙어도 이 검사가 그 절 문구로 통과하지 않게
if [ -n "$_l_sec5" ] && [ -n "$_l_tst" ] && [ -n "$_l_pr5" ] && [ -n "$_l_tstend" ] && [ "$_l_sec5" -lt "$_l_tst" ] && [ "$_l_tst" -lt "$_l_pr5" ] \
   && has "$_PL" 'subagent_type: "specops-ko:test-designer-ko"' 'experts/test\.md' '\| test-expert \| test-designer-ko \| 반영 \|' '\| test-expert \| - \| SKIP \|' '\| test-expert \| test-designer-ko \| 산출 없음 \|' \
        '\*\*테스트 파일\*\*.*`test_\*\.py`.*`scripts/tests/`.*만들거나 고치면 발동한다' '전문가 패스 가운데 마지막' '떨어뜨리는 잘못된 구현" 칸은 plan 의 해당 테스트 스텝에 옮긴다' \
   && sed -n "${_l_tst},${_l_tstend}p" "$_PL" | grep -q '`§batch` 는 이 패스 미적용' && sed -n "${_l_tst},${_l_tstend}p" "$_PL" | grep -q '마지막 전문가 패스 뒤에 한 번만' \
   && sed -n "${_l_tst},${_l_tstend}p" "$_PL" | grep -q 'acceptance-criteria\.md' \
   && [ "$(sed -n "$((_l_tst+1)),$((_l_tstend-1))p" "$_PL" | grep -c '^#')" -eq 0 ] \
   && ! sed -n "${_l_tst},${_l_tstend}p" "$_PL" | grep -E '^\| [^|]*\| [^|]*\| test-expert \|' | grep -qE 'DONE|IMPL' \
   && ! sed -n "${_l_tst},${_l_tstend}p" "$_PL" | grep -oE '`\| [^|`]* \| [^|`]* \| test-expert \|[^`]*`' | grep -qE 'DONE|IMPL'; then
  ok "planning-ko 테스트 전문가 패스 — 보안 패스 뒤·plan-reviewer 전 · 발동 조건 · dispatch · 반영 · 재검사 한 번 · 기록 3종 · batch 제외"
else
  nope "planning-ko 테스트 전문가 패스" "위치(sec=$_l_sec5 test=$_l_tst end=$_l_tstend pr=$_l_pr5) · 필수 문구 · 하위 제목 · DONE 행 중 문제"
fi

# specifying-ko Step 6.5 요구사항 전문가 — 6 < 6.5 < 7 · 절 범위(6.5 줄 ~ 7 줄 앞)에서만 문구 · 제외 5종 · §8 이관 · 기록 3종(DONE 금지) (20261023-req-expert-integrate)
_SPK=skills/specifying-ko/SKILL.md
_l_s6=$(grep -n '^6\. \*\*설계 문서 작성\*\*' "$_SPK" | head -1 | cut -d: -f1)
_l_s65=$(grep -n '^6\.5\. ' "$_SPK" | head -1 | cut -d: -f1)
_l_s7=$(grep -n '^7\. \*\*스펙 자체 검토\*\*' "$_SPK" | head -1 | cut -d: -f1)
_l_s65end=""; [ -n "$_l_s65" ] && _l_s65end=$(awk -v s="$_l_s65" 'NR>s && /^[0-9]+(\.[0-9]+)?\. /{print NR; exit}' "$_SPK")   # 6.5 다음 번호 항목(6.6 등) — 뒤 항목 문구로 통과하지 않게
_s65_body=""
[ -n "$_l_s65" ] && [ -n "$_l_s7" ] && [ "$_l_s65" -lt "$_l_s7" ] && [ -n "$_l_s65end" ] && _s65_body=$(sed -n "${_l_s65},$((_l_s65end-1))p" "$_SPK")
_s65_has() { local p; for p in "$@"; do printf '%s\n' "$_s65_body" | grep -qE -- "$p" || return 1; done; return 0; }
_s65_ex=$(printf '%s\n' "$_s65_body" | grep -E '^   - \*\*제외\*\*:')
if [ -n "$_l_s6" ] && [ -n "$_s65_body" ] && [ "$_l_s6" -lt "$_l_s65" ] \
   && _s65_has 'subagent_type: "specops-ko:req-designer-ko"' 'experts/req\.md' '저장·계산·판정' '판단이 서지 않으면 부른다' \
        'spec §8 열린 질문으로 옮긴다' '`§auto` 면 질문을 best-guess 로 정해 §8 에 `\(ASSUMED\)` 로 남긴다' \
        '`acceptance-criteria\.md` · `intent\.md`' '가용 모델 override 로 다시 dispatch' '부모가 대신 검토하지 않는다' \
        '\| req-expert \| req-designer-ko \| 반영 \|' '\| req-expert \| - \| SKIP \| 데이터 표면 없음 \|' '\| req-expert \| req-designer-ko \| 산출 없음 \|' \
   && printf '%s\n' "$_s65_ex" | grep -qE '^   - \*\*제외\*\*: `§batch` · `§lite`.* · `§유형: trivial` · promote\(`promote-fid`\) · foundation 은 부르지 않는다' \
   && printf '%s\n' "$_s65_ex" | grep -qF '유지보수 분기와 `§auto` 는 부른다' \
   && ! printf '%s\n' "$_s65_body" | grep -vE '^   - \*\*제외\*\*:' | grep -E '(§batch|§lite|trivial|promote|foundation)' | grep -q '부른다' \
   && [ "$(printf '%s\n' "$_s65_body" | grep -c '^ *#')" -eq 0 ] \
   && ! printf '%s\n' "$_s65_body" | grep -E '^ *\| [^|]*\| [^|]*\| req-expert \|' | grep -qE 'DONE|IMPL' \
   && ! printf '%s\n' "$_s65_body" | grep -oE '`\| [^|`]* \| [^|`]* \| req-expert \|[^`]*`' | grep -qE 'DONE|IMPL'; then
  ok "specifying-ko Step 6.5 요구사항 전문가 — 6 < 6.5 < 7 · 절 범위 문구 · 제외 5종 · §8 이관 · 기록 3종 · DONE 없음"
else
  nope "specifying-ko Step 6.5 요구사항 전문가" "위치(6=$_l_s6 6.5=$_l_s65 7=$_l_s7) · 절 범위 문구 · 하위 제목 · DONE 행 중 문제"
fi

# specifying-ko Step 6.6 화면 전문가 — 6.5 < 6.6 < 7 · 절 범위(6.6 줄 ~ 다음 번호 항목 앞) · 제외(무기록 4 · SKIP 1) · §8 이관 · 기록 3종(DONE 금지) (20261023-ui-expert-integrate)
_l_s66=$(grep -n '^6\.6\. ' "$_SPK" | head -1 | cut -d: -f1)
_l_s66end=""; [ -n "$_l_s66" ] && _l_s66end=$(awk -v s="$_l_s66" 'NR>s && /^[0-9]+(\.[0-9]+)?\. /{print NR; exit}' "$_SPK")
_s66_body=""; [ -n "$_l_s66end" ] && _s66_body=$(sed -n "${_l_s66},$((_l_s66end-1))p" "$_SPK")
_s66_has() { local p; for p in "$@"; do printf '%s\n' "$_s66_body" | grep -qE -- "$p" || return 1; done; return 0; }
_s66_ex=$(printf '%s\n' "$_s66_body" | grep -E '^   - \*\*제외\*\*:')
if [ -n "$_l_s65" ] && [ -n "$_l_s66" ] && [ -n "$_l_s7" ] && [ "$_l_s65" -lt "$_l_s66" ] && [ "$_l_s66" -lt "$_l_s7" ] && [ -n "$_s66_body" ] \
   && _s66_has 'subagent_type: "specops-ko:ui-designer-ko"' 'experts/ui\.md' '기능 화면 `screens/<name>\.md` 를 만들거나 고쳤으면 발동한다' \
        'spec §8 열린 질문으로 옮긴다' '`§auto` 면 질문을 best-guess 로 정해 §8 에 `\(ASSUMED\)` 로 남긴다' \
        '이번에 만든·고친 `screens/<name>\.md`·`\.html` · `\.specops/<FID>/spec\.md` · `acceptance-criteria\.md` · `DESIGN\.md`\(있으면\)' '가용 모델 override 로 다시 dispatch' '부모가 대신 검토하지 않는다' \
        '\| ui-expert \| ui-designer-ko \| 반영 \|' '\| ui-expert \| - \| SKIP \| 화면 변경 없음 \|' '\| ui-expert \| ui-designer-ko \| 산출 없음 \|' \
   && printf '%s\n' "$_s66_ex" | grep -qE '^   - \*\*제외\*\*: `§batch`.*Phase 2\.5 A2.* · `§lite`.* · `§유형: trivial` · foundation 셸 화면\(`<!-- foundation-shell -->`\)만 바꾼 경우는 부르지 않는다' \
   && printf '%s\n' "$_s66_ex" | grep -qF '화면 변경이 없으면 부르지 않고 SKIP 행을 남긴다' \
   && printf '%s\n' "$_s66_ex" | grep -qF '유지보수 분기와 `§auto` 는 부른다' \
   && ! printf '%s\n' "$_s66_body" | grep -vE '^   - \*\*제외\*\*:' | grep -E '(§batch|§lite|trivial|foundation)' | grep -q '부른다' \
   && [ "$(printf '%s\n' "$_s66_body" | grep -c '^ *#')" -eq 0 ] \
   && [ "$(awk '/^## 프로세스 흐름/{f=1;next} /^## /{f=0} f' "$_SPK" | grep -oE '(요구사항|화면) 전문가 패스 \(Step 6\.[56]\)|스펙 자체 검토' | tr '\n' ,)" = '요구사항 전문가 패스 (Step 6.5),화면 전문가 패스 (Step 6.6),스펙 자체 검토,' ] \
   && ! printf '%s\n' "$_s66_body" | grep -E '^ *\| [^|]*\| [^|]*\| ui-expert \|' | grep -qE 'DONE|IMPL' \
   && ! printf '%s\n' "$_s66_body" | grep -oE '`\| [^|`]* \| [^|`]* \| ui-expert \|[^`]*`' | grep -qE 'DONE|IMPL'; then
  ok "specifying-ko Step 6.6 화면 전문가 — 6.5 < 6.6 < 7 · 절 범위 문구 · 제외 · §8 이관 · 기록 3종 · DONE 없음"
else
  nope "specifying-ko Step 6.6 화면 전문가" "위치(6.5=$_l_s65 6.6=$_l_s66 end=$_l_s66end 7=$_l_s7) · 절 범위 문구 · 하위 제목 · DONE 행 중 문제"
fi

# /start-all Phase 2.5 A2 화면 전문가 — A < A2 < B · 절 범위(A2 ~ 다음 #### 앞) · batch 당 1회 · SKIP 기록 · 산출 경로 · E 게이트 이관 · 통상 순서 줄 (20261023-ui-expert-integrate)
_SAL=commands/start-all.md
_l_pa=$(grep -n '^#### A\. ' "$_SAL" | head -1 | cut -d: -f1)
_l_pa2=$(grep -n '^#### A2\. ' "$_SAL" | head -1 | cut -d: -f1)
_l_pb=$(grep -n '^#### B\. ' "$_SAL" | head -1 | cut -d: -f1)
_a2_end=""; [ -n "$_l_pa2" ] && _a2_end=$(awk -v s="$_l_pa2" 'NR>s && /^#### /{print NR; exit}' "$_SAL")
_a2_body=""; [ -n "$_a2_end" ] && _a2_body=$(sed -n "${_l_pa2},$((_a2_end-1))p" "$_SAL")
_a2_has() { local p; for p in "$@"; do printf '%s\n' "$_a2_body" | grep -qE -- "$p" || return 1; done; return 0; }
if [ -n "$_l_pa" ] && [ -n "$_l_pa2" ] && [ -n "$_l_pb" ] && [ "$_l_pa" -lt "$_l_pa2" ] && [ "$_l_pa2" -lt "$_l_pb" ] && [ "$_a2_end" = "$_l_pb" ] \
   && _a2_has '`UI-EXPERT: SKIP — 화면 산출 없음`' '`\.specops/<BATCH_ID>/experts/ui\.md`' 'E 설계 승인 게이트에서 함께 묻는다' \
        '`§auto` 면 best-guess 로 정해 `\(ASSUMED\)` 로 queue 다이제스트에 남긴다' '부모가 대신 검토하지 않는다' '`UI-EXPERT: 산출 없음`' \
        'D\(`design-reviewer-ko`\)의 독립 판정은 그대로다' '`BATCH_ID` 와 산출 경로 `\.specops/<BATCH_ID>/experts/ui\.md`\(산출 경로의 `<FID>` 자리에만 `<BATCH_ID>` 를 쓴다고 프롬프트에 적는다\)' \
   && printf '%s\n' "$_a2_body" | grep -F 'subagent_type: "specops-ko:ui-designer-ko"' | grep -qF 'batch 당 1회' \
   && printf '%s\n' "$_a2_body" | grep -F '`UI-EXPERT: SKIP — 화면 산출 없음`' | grep -F 'foundation 셸(`<!-- foundation-shell -->`)만 재사용했거나 A 가 SKIP 이면' | grep -qF '(`|` 로 시작 금지)' \
   && _l_pe=$(grep -n '^#### E\. ' "$_SAL" | head -1 | cut -d: -f1) && [ -n "$_l_pe" ] && _e_end=$(awk -v s="$_l_pe" 'NR>s && /^#### /{print NR; exit}' "$_SAL") && [ -n "$_e_end" ] \
   && sed -n "${_l_pe},$((_e_end-1))p" "$_SAL" | grep -qF 'A2 의 `experts/ui.md` `## 확인 필요` 질문' \
   && grep -qF '통상 순서: **A 화면 → A2 화면 전문가 → B 인터페이스 → C cross-FR → D 무거운 설계 리뷰 → E 승인 → F 커밋**' "$_SAL"; then
  ok "start-all Phase 2.5 A2 화면 전문가 — A < A2 < B · 절 범위 문구 · batch 당 1회 · SKIP·산출 없음 기록 · E 게이트 이관 · 통상 순서"
else
  nope "start-all Phase 2.5 A2 화면 전문가" "위치(A=$_l_pa A2=$_l_pa2 end=$_a2_end B=$_l_pb) · 절 범위 문구 · 통상 순서 줄 중 문제"
fi

# planning-ko 구조 전문가 패스 — DB < 구조 < API < 보안 < 테스트 < plan-reviewer · 절 범위(다음 ### 앞) · 발동 3종 · 극성(발동·미발동·판단 불가 시 부른다·§auto 부른다) · dispatch 입력 · 반영 줄 산출 경로 · dispatch · 재검사 한 번 · 기록 3종(DONE 금지) · batch 제외 · 하위 제목 없음 (20261023-arch-expert-integrate)
_l_db6=$(grep -n '^### DB 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_ar=$(grep -n '^### 구조 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_api6=$(grep -n '^### API 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_sec6=$(grep -n '^### 보안 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_tst6=$(grep -n '^### 테스트 전문가 패스' "$_PL" | head -1 | cut -d: -f1)
_l_pr6=$(grep -n '^### 비-batch — plan-reviewer dispatch' "$_PL" | head -1 | cut -d: -f1)
_l_arend=""; [ -n "$_l_ar" ] && _l_arend=$(awk -v s="$_l_ar" 'NR>s && /^### /{print NR; exit}' "$_PL")
_ar_body=""; [ -n "$_l_arend" ] && _ar_body=$(sed -n "${_l_ar},$((_l_arend-1))p" "$_PL")
_ar_has() { local p; for p in "$@"; do printf '%s\n' "$_ar_body" | grep -qE -- "$p" || return 1; done; return 0; }
if [ -n "$_l_db6" ] && [ -n "$_l_ar" ] && [ -n "$_l_api6" ] && [ -n "$_l_sec6" ] && [ -n "$_l_tst6" ] && [ -n "$_l_pr6" ] \
   && [ "$_l_db6" -lt "$_l_ar" ] && [ "$_l_ar" -lt "$_l_api6" ] && [ "$_l_api6" -lt "$_l_sec6" ] && [ "$_l_sec6" -lt "$_l_tst6" ] && [ "$_l_tst6" -lt "$_l_pr6" ] && [ "$_l_arend" = "$_l_api6" ] \
   && _ar_has '^- \*\*dispatch\*\*: `Agent` 도구, `subagent_type: "specops-ko:arch-designer-ko"` · 입력은 경로만 — `\.specops/<FID>/spec\.md` · `plan\.md` · `\.specops/memory/backend-architecture\.md`·`frontend-architecture\.md`\(있으면\) · `\$\{CLAUDE_PLUGIN_ROOT\}/skills/planning-ko/arch-expert/patterns/`\.$' \
        'plan §2 파일 구조가 \*\*새 폴더·새 모듈·새 계층\*\*을 만들거나, 경계 약속의 허용 의존에 \*\*새 의존 방향\*\*이 생기거나, spec 에 \*\*새 도메인 개념\*\*\(엔티티·상태\)이 생기면 발동한다\. 기존 파일 수정뿐이거나 문서·테스트만 바꾸면 발동하지 않는다\. 파일 구조·태스크로 판단이 서지 않으면 부른다\(' \
        '`§batch` 는 이 패스 미적용\(기록 행도 남기지 않는다\) · `§auto` 는 그대로 부른다\.' \
        '^- \*\*반영\*\*: `\.specops/<FID>/experts/arch\.md` 의 지적' '마지막 전문가 패스 뒤에 한 번만' \
        '부모가 대신 검토하지 않는다\)\. `experts/arch\.md` 가 만들어지지 않았으면 1회 다시 부르고, 그래도 없으면 dispatch-log 에 ' \
        '\| arch-expert \| arch-designer-ko \| 반영 \|' '\| arch-expert \| - \| SKIP \| 구조 표면 없음 \|' '\| arch-expert \| arch-designer-ko \| 산출 없음 \|' \
   && printf '%s\n' "$_ar_body" | sed -n 3p | grep -q '^DB 전문가 패스 뒤, plan-reviewer 를 부르기' \
   && [ "$(printf '%s\n' "$_ar_body" | sed 1d | grep -c '^ *#')" -eq 0 ] \
   && ! printf '%s\n' "$_ar_body" | grep -E '^ *\| [^|]*\| [^|]*\| arch-expert \|' | grep -qE 'DONE|IMPL' \
   && ! printf '%s\n' "$_ar_body" | grep -oE '`\| [^|`]* \| [^|`]* \| arch-expert \|[^`]*`' | grep -qE 'DONE|IMPL'; then
  ok "planning-ko 구조 전문가 패스 — DB < 구조 < API < 보안 < 테스트 · 절 범위 문구 · 발동 3종 · 재검사 한 번 · 기록 3종 · batch 제외"
else
  nope "planning-ko 구조 전문가 패스" "위치(db=$_l_db6 arch=$_l_ar end=$_l_arend api=$_l_api6 sec=$_l_sec6 tst=$_l_tst6 pr=$_l_pr6) · 절 범위 문구 · DONE 행 중 문제"
fi

finish
