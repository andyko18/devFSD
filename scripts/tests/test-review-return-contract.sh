#!/usr/bin/env bash
# test-review-return-contract — 리뷰 반환 요약화 문서 계약 (AC-7) · FID 20260914-review-return-summary
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

# ── T1 리뷰어 문서 ──
for a in spec-reviewer-ko code-reviewer-ko; do
  f="$PLUGIN/agents/$a.md"
  if grep -qF '<<<REVIEW fid=' "$f" && grep -qF '<<<END>>>' "$f"; then ok "T1.a $a 마커 형식"
  else nope "T1.a $a 마커 형식"; fi
  if grep -qF 'stop-hook 지시' "$f"; then ok "T1.b $a stop-hook 지시 준수 문구"
  else nope "T1.b $a stop-hook 지시"; fi
  if ! grep -qE '요약 형식|300토큰|Critical: <' "$f"; then ok "T1.c $a 요약 형식 미기재 (선취 방지)"
  else nope "T1.c $a 요약 형식이 에이전트 정의에 있음"; fi
  if ! grep -m1 '^tools:' "$f" | grep -qE 'Write|Edit'; then ok "T1.d $a Write/Edit 박탈 유지"
  else nope "T1.d $a tools"; fi
done
if grep -qF 'verdict=<PASS|NEEDS_FIX>' "$PLUGIN/agents/spec-reviewer-ko.md"; then ok "T1.e Phase B 판정 어휘"
else nope "T1.e Phase B 판정 어휘"; fi
if grep -qF 'verdict=<READY_TO_MERGE|NEEDS_FIX|NEEDS_DISCUSSION>' "$PLUGIN/agents/code-reviewer-ko.md"; then ok "T1.f Phase C 판정 어휘"
else nope "T1.f Phase C 판정 어휘"; fi
if grep -qF '## 🔴 Critical' "$PLUGIN/agents/code-reviewer-ko.md"; then ok "T1.g 보고서 템플릿 🔴 헤딩 유지 (release-ready)"
else nope "T1.g 🔴 헤딩"; fi
# 채운 예시 — 자리표시자 `>` 와 마커 `>>>` 가 겹쳐 꺾쇠 개수가 모호해지는 것을 막는다 (Phase C T3 🟡)
if grep -qF '<<<REVIEW fid=20260914-example tid=T1 phase=B verdict=PASS>>>' "$PLUGIN/agents/spec-reviewer-ko.md"; then ok "T1.h Phase B 채운 예시 줄"
else nope "T1.h Phase B 채운 예시 줄 부재"; fi
if grep -qF '<<<REVIEW fid=20260914-example tid=T1 phase=C verdict=READY_TO_MERGE>>>' "$PLUGIN/agents/code-reviewer-ko.md"; then ok "T1.i Phase C 채운 예시 줄"
else nope "T1.i Phase C 채운 예시 줄 부재"; fi
# 채운 예시는 인용 — 줄 맨 앞이면 리뷰어가 옮겨 쓸 때 중첩·짝 없는 헤더로 저장 전체 무동작 (Phase C 라운드 2 T3 🟡)
for a in spec-reviewer-ko code-reviewer-ko; do
  if ! grep -qE '^<<<REVIEW fid=20260914-example' "$PLUGIN/agents/$a.md"; then ok "T1.j $a 채운 예시 줄 들여씀"
  else nope "T1.j $a 채운 예시 줄이 줄 맨 앞"; fi
done

# ── T2 부모 문서 공통 리터럴 (implementing-ko) ──
for d in skills/implementing-ko/SKILL.md; do
  for lit in '판정 SoT = reviews 파일' 'report 부재 시 부모 fallback 저장' 'dispatch-log 행은 부모가 기록'; do
    if grep -qF "$lit" "$PLUGIN/$d"; then ok "T2.a $d · $lit"
    else nope "T2.a $d" "'$lit' 부재"; fi
  done
done
if grep -qF 'hooks/save-review-report.sh' "$PLUGIN/skills/implementing-ko/SKILL.md"; then ok "T2.b implementing-ko 훅 경로 명시"
else nope "T2.b implementing-ko 훅 경로"; fi
# fallback 확장 — 형식 오류·이동 실패로 옛 report 가 남아 옛 판정을 읽는 경로 차단 (Phase C T4 🟡)
if grep -qF '반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장' "$PLUGIN/skills/implementing-ko/SKILL.md"; then ok "T2.c implementing-ko fallback 덮어쓰기 조건"
else nope "T2.c implementing-ko fallback 덮어쓰기 조건 부재"; fi
# ── T3 propagation edge ──
if grep -qF '"id": "review-return-summary"' "$PLUGIN/scripts/_internal/propagation-matrix.jsonl"; then ok "T3.a propagation edge 존재"
else nope "T3.a propagation edge"; fi
if bash "$PLUGIN/scripts/_internal/check-propagation.sh" >/dev/null 2>&1; then ok "T3.b check-propagation 전 edge PASS"
else nope "T3.b check-propagation"; fi

# ── T4 부모 문서 공통 리터럴 (start-all · file-based-communication) ──
for d in commands/start-all.md skills/file-based-communication-ko/SKILL.md; do
  for lit in '판정 SoT = reviews 파일' 'report 부재 시 부모 fallback 저장' 'dispatch-log 행은 부모가 기록'; do
    if grep -qF "$lit" "$PLUGIN/$d"; then ok "T4.a $d · $lit"
    else nope "T4.a $d" "'$lit' 부재"; fi
  done
done
FBC="$PLUGIN/skills/file-based-communication-ko/SKILL.md"
if grep -qF '반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장' "$FBC"; then ok "T4.b file-based-communication-ko fallback 덮어쓰기 조건"
else nope "T4.b file-based-communication-ko fallback 덮어쓰기 조건 부재"; fi
# 프로필 한계 — standard·minimal 에서 is-hook-enabled 가 훅을 끈다 (사용자 결정: 현행 유지 + 한계 기록)
if grep -qF 'SPECOPS_GOVERNANCE_PROFILE' "$FBC"; then ok "T4.c file-based-communication-ko 프로필 한계 기록"
else nope "T4.c file-based-communication-ko 프로필 한계 부재"; fi
# start-all 도 같은 fallback 덮어쓰기 조건 (Phase C 라운드 2 T5 🟡)
if grep -qF '반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장' "$PLUGIN/commands/start-all.md"; then ok "T4.d start-all fallback 덮어쓰기 조건"
else nope "T4.d start-all fallback 덮어쓰기 조건 부재"; fi

# ── T5 부모 dispatch 규약 — implementing-ko 에 정확한 meta 형식이 있다 ──
IMP="$PLUGIN/skills/implementing-ko/SKILL.md"
if grep -qF 'fid=<FID> tid=<T#> phase=<B 또는 C> verdict=' "$IMP"; then ok "T5.a implementing-ko meta 형식 명시"
else nope "T5.a implementing-ko meta 형식 부재"; fi
if grep -qF 'PASS|READY_TO_MERGE|NEEDS_FIX|NEEDS_DISCUSSION' "$IMP"; then ok "T5.b implementing-ko verdict 어휘 4종"
else nope "T5.b implementing-ko verdict 어휘 부재"; fi
if grep -qF '속성을 생략하면 훅이 저장하지 않는다' "$IMP"; then ok "T5.c implementing-ko 축약 금지 경고"
else nope "T5.c implementing-ko 축약 금지 경고 부재"; fi

# ── T6 최초 B/C 병렬 dispatch 계약 (20261006-review-bc-parallel) ──
CR="$PLUGIN/agents/code-reviewer-ko.md"
if grep -qF '병렬 dispatch: yes (B 판정 대기)' "$CR"; then ok "T6.a code-reviewer 병렬 표시 리터럴"
else nope "T6.a 병렬 표시 리터럴 부재"; fi
if grep -qF 'PENDING(병렬 — 부모 사후 대조)' "$CR"; then ok "T6.b code-reviewer 병렬 헤더 리터럴"
else nope "T6.b PENDING(병렬 헤더 부재"; fi
if grep -qF '경로도 병렬 표시도 없으면 SKIP 반환' "$CR"; then ok "T6.c 자격 게이트 SKIP 유지 (경로·표시 둘 다 없으면)"
else nope "T6.c SKIP 분기 부재"; fi
if grep -qF 'AC 충족은 재평가하지 않는다' "$CR"; then ok "T6.d 병렬 모드에서도 AC 재평가 금지 유지"
else nope "T6.d AC 재평가 금지 문구 부재"; fi

if grep -qF '병렬 dispatch: yes (B 판정 대기)' "$IMP"; then ok "T6.e implementing-ko 병렬 표시 리터럴 — reviewer 와 동일"
else nope "T6.e implementing-ko 병렬 표시 리터럴 부재"; fi

if grep -qF '경로와 병렬 표시가 함께 오면 경로(B-report)를 우선' "$CR"; then ok "T6.f 경로·병렬 표시 동시 입력 시 경로 우선"
else nope "T6.f 경로 우선 문장 부재"; fi

finish
