#!/usr/bin/env bash
# specops-ko validate-structure.sh 검증(2/2) — chain_consistency · agent_tools · hardgate · 커맨드 chain (20261008 분할)
# baseline: P1 flat — commands=1, skills/<name>/SKILL.md=16, templates=6 (sandbox 격리)
# U4 후: sandbox 가 .structure-baseline 자체 생성. agents/ 빈 디렉토리 OK.
# (meta skill 필수: skills/using-specops-ko/SKILL.md + hooks/session-start.sh exec-bit)
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$PLUGIN/scripts/_internal/validate-structure.sh"

source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
command -v iso::make_tree >/dev/null 2>&1 && command -v iso::fingerprint >/dev/null 2>&1 \
  || { echo "FATAL: isolated-tree 미로드(또는 반쯤 로드)" >&2; exit 1; }
# ISO pathspec = T-hg.b 가 (격리 전) 변이하던 유일한 실 파일
_iso_paths='skills/specifying-ko/SKILL.md'
_iso_before=$(iso::fingerprint $_iso_paths)

source "$PLUGIN/scripts/tests/lib/vs-sandbox.sh"  # SKILL_NAMES · make_sandbox · add_docs (chain 스위트와 공유)

# 원 스위트(test-validate-structure.sh)의 T1~T13 은 그쪽에 남았다. 아래는 같은 단언을 그대로 옮긴 T14~T-cc4 와 ISO 자가점검.

# ── chain_consistency (FID 20260702-chain-single-source): hooks/chain.yaml 단일 source 대조 ─────────

# T14.a 실제 repo — chain_consistency OK (오탐 0 보증, AC-1)
out=$(bash "$SCRIPT" 2>&1); rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q 'chain_consistency: OK'; then
  PASS=$((PASS+1)); echo "PASS T14.a chain_consistency 실제 repo OK"
else
  FAIL=$((FAIL+1)); echo "FAIL T14.a chain_consistency 누락 또는 FAIL: $(printf '%s' "$out" | grep chain_consistency || echo '검사 부재')"
fi

# T14.b SKILL.md 측 drift — s1 의 Skill: 라인 대상을 제3 skill 로 변경 (chain.yaml 미갱신) → FAIL + edge 명시 (AC-2)
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); pre_rc=$?
sed -i.bak 's/^Skill: devfsd:clarifying-ko$/Skill: devfsd:planning-ko/' "$sb/skills/specifying-ko/SKILL.md"
rm -f "$sb/skills/specifying-ko/SKILL.md.bak"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $pre_rc -eq 0 ] && printf '%s' "$pre" | grep -q 'chain_consistency: OK' \
   && [ $rc -ne 0 ] && printf '%s' "$err" | grep -q 'chain_consistency: FAIL' \
   && printf '%s' "$err" | grep -q 'specifying-ko → planning-ko'; then
  PASS=$((PASS+1)); echo "PASS T14.b SKILL.md 측 drift → chain_consistency FAIL + edge 명시"
else
  FAIL=$((FAIL+1)); echo "FAIL T14.b (pre_rc=$pre_rc rc=$rc, out=$(printf '%s' "$err" | grep chain_consistency))"
fi
rm -rf "$sb"

# T14.c chain.yaml 측 drift — edge 1개 제거 (edges: [] 화, SKILL.md 미변경) → FAIL + edge 명시 (AC-3)
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); pre_rc=$?
printf 'edges: []\n' > "$sb/hooks/chain.yaml"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $pre_rc -eq 0 ] && printf '%s' "$pre" | grep -q 'chain_consistency: OK' \
   && [ $rc -ne 0 ] && printf '%s' "$err" | grep -q 'chain_consistency: FAIL' \
   && printf '%s' "$err" | grep -q 'SKILL.md에만: specifying-ko → clarifying-ko'; then
  PASS=$((PASS+1)); echo "PASS T14.c chain.yaml 측 drift → chain_consistency FAIL + edge 명시"
else
  FAIL=$((FAIL+1)); echo "FAIL T14.c (pre_rc=$pre_rc rc=$rc, out=$(printf '%s' "$err" | grep chain_consistency))"
fi
rm -rf "$sb"

# T14.d 메타 fixture 미선언 edge — 화살표 라인 s2 → s1 추가 (chain.yaml 미변경) → FAIL (AC-4)
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); pre_rc=$?
printf -- '\nclarifying-ko → specifying-ko\n' >> "$sb/skills/using-specops-ko/SKILL.md"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $pre_rc -eq 0 ] && printf '%s' "$pre" | grep -q 'chain_consistency: OK' \
   && [ $rc -ne 0 ] && printf '%s' "$err" | grep -q 'chain_consistency: FAIL' \
   && printf '%s' "$err" | grep -q '메타목록 미선언 edge: clarifying-ko → specifying-ko'; then
  PASS=$((PASS+1)); echo "PASS T14.d 메타목록 미선언 edge → chain_consistency FAIL"
else
  FAIL=$((FAIL+1)); echo "FAIL T14.d (pre_rc=$pre_rc rc=$rc, out=$(printf '%s' "$err" | grep chain_consistency))"
fi
rm -rf "$sb"

# T14.e chain.yaml 절단 파손 → FAIL "파싱 실패" (silent pass 금지, AC-6)
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); pre_rc=$?
printf 'edges: [{from:\n' > "$sb/hooks/chain.yaml"
err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
if [ $pre_rc -eq 0 ] && printf '%s' "$pre" | grep -q 'chain_consistency: OK' \
   && [ $rc -ne 0 ] && printf '%s' "$err" | grep -q 'chain_consistency: FAIL' \
   && printf '%s' "$err" | grep -q '파싱 실패'; then
  PASS=$((PASS+1)); echo "PASS T14.e yaml 파손 → chain_consistency FAIL (파싱 실패)"
else
  FAIL=$((FAIL+1)); echo "FAIL T14.e (pre_rc=$pre_rc rc=$rc, out=$(printf '%s' "$err" | grep chain_consistency))"
fi
rm -rf "$sb"

# T14.f pyyaml 부재 graceful SKIP (AC-5)
# 한계 고백: 기존 T6 은 pyyaml "존재"를 전제(부재 시 케이스 자체 skip)하는 기법이라 SKIP 경로 런타임 모의 불가
# (python3 PATH 조작은 frontmatter 등 다른 검사까지 SKIP 시켜 sandbox 단언이 무의미해짐).
# → SKIP 분기 코드 존재를 정적 검증 (frontmatter SKIP 선례와 동일 분기 구조).
if grep -q 'emit chain_consistency SKIP' "$SCRIPT"; then
  PASS=$((PASS+1)); echo "PASS T14.f pyyaml 부재 SKIP 분기 존재 (정적 검증)"
else
  FAIL=$((FAIL+1)); echo "FAIL T14.f chain_consistency SKIP 분기 부재"
fi

# ── agent_tools marker 역방향 스캔 (FID 20260702-marker-reverse-scan) ─────────

# T15.a 실제 repo — agent_tools 가 role: evaluator 역방향 스캔으로 7종 검사
#   (Phase 2.5 design-reviewer-ko 추가로 6→7)
ev_count=$(grep -l '^role: evaluator' "$PLUGIN"/agents/*.md 2>/dev/null | grep -c . || true)
if [ "$ev_count" -eq 7 ] && bash "$SCRIPT" 2>&1 | grep -q 'agent_tools: OK'; then
  PASS=$((PASS+1)); echo "PASS T15.a role: evaluator 마킹 7종 + 역방향 스캔 OK"
else
  FAIL=$((FAIL+1)); echo "FAIL T15.a evaluator 마킹 $ev_count/7 또는 agent_tools 비OK"
fi

# T15.b 가짜 evaluator (role: evaluator + Write) 자동 편입 적발 — 스크립트 무수정 (AC-2)
#       파일명 비reviewer(fake-audit-ko)로 2차 방어 분기와 판정 단일화
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1)
if ! echo "$pre" | grep -q 'agent_tools: SKIP'; then
  FAIL=$((FAIL+1)); echo "FAIL T15.b 변조 전 단언 (agents 빈 sandbox 가 SKIP 아님)"
else
  printf -- '---\nname: good-eval-ko\nrole: evaluator\ntools: Read\n---\n' > "$sb/agents/good-eval-ko.md"
  printf -- '---\nname: fake-audit-ko\nrole: evaluator\ntools: Read, Write\n---\n' > "$sb/agents/fake-audit-ko.md"
  err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
  if [ $rc -eq 1 ] && echo "$err" | grep -q 'agent_tools: FAIL' && echo "$err" | grep -q 'fake-audit-ko:Write/Edit포함'; then
    PASS=$((PASS+1)); echo "PASS T15.b 가짜 evaluator 자동 편입 적발"
  else
    FAIL=$((FAIL+1)); echo "FAIL T15.b (rc=$rc, out=$(echo "$err" | grep agent_tools))"
  fi
fi
rm -rf "$sb"

# T15.c 미마킹 reviewer (role 없음) 2차 방어 (AC-3)
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1)
if ! echo "$pre" | grep -q 'agent_tools: SKIP'; then
  FAIL=$((FAIL+1)); echo "FAIL T15.c 변조 전 단언 (agents 빈 sandbox 가 SKIP 아님)"
else
  printf -- '---\nname: good-eval-ko\nrole: evaluator\ntools: Read\n---\n' > "$sb/agents/good-eval-ko.md"
  printf -- '---\nname: fake-reviewer-ko\ntools: Read\n---\n' > "$sb/agents/fake-reviewer-ko.md"
  err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
  if [ $rc -eq 1 ] && echo "$err" | grep -q 'agent_tools: FAIL' && echo "$err" | grep -q 'fake-reviewer-ko:role마킹누락'; then
    PASS=$((PASS+1)); echo "PASS T15.c 미마킹 reviewer 2차 방어"
  else
    FAIL=$((FAIL+1)); echo "FAIL T15.c (rc=$rc, out=$(echo "$err" | grep agent_tools))"
  fi
fi
rm -rf "$sb"

# T15.d agents 파일 존재 + evaluator 마킹 0건 → 공회전 방지 (AC-4)
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1)
if ! echo "$pre" | grep -q 'agent_tools: SKIP'; then
  FAIL=$((FAIL+1)); echo "FAIL T15.d 변조 전 단언 (agents 빈 sandbox 가 SKIP 아님)"
else
  printf -- '---\nname: plain-agent-ko\ntools: Read\n---\n' > "$sb/agents/plain-agent-ko.md"
  err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
  if [ $rc -eq 1 ] && echo "$err" | grep -q 'agent_tools: FAIL' && echo "$err" | grep -q 'evaluator마킹0건'; then
    PASS=$((PASS+1)); echo "PASS T15.d 마킹 0건 공회전 방지"
  else
    FAIL=$((FAIL+1)); echo "FAIL T15.d (rc=$rc, out=$(echo "$err" | grep agent_tools))"
  fi
fi
rm -rf "$sb"

# T15.e MultiEdit 박탈 — -w Edit 만으로는 MultiEdit 를 못 잡던 구멍 (즉시 로드맵)
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1)
if ! echo "$pre" | grep -q 'agent_tools: SKIP'; then
  FAIL=$((FAIL+1)); echo "FAIL T15.e 변조 전 단언 (agents 빈 sandbox 가 SKIP 아님)"
else
  printf -- '---\nname: me-eval-ko\nrole: evaluator\ntools: Read, MultiEdit\n---\n' > "$sb/agents/me-eval-ko.md"
  err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
  if [ $rc -eq 1 ] && echo "$err" | grep -q 'agent_tools: FAIL' && echo "$err" | grep -q 'me-eval-ko:Write/Edit포함'; then
    PASS=$((PASS+1)); echo "PASS T15.e MultiEdit 자동 편입 적발"
  else
    FAIL=$((FAIL+1)); echo "FAIL T15.e (rc=$rc, out=$(echo "$err" | grep agent_tools))"
  fi
fi
rm -rf "$sb"

# T15.f NotebookEdit 박탈
sb=$(mktemp -d); make_sandbox "$sb"
pre=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1)
if ! echo "$pre" | grep -q 'agent_tools: SKIP'; then
  FAIL=$((FAIL+1)); echo "FAIL T15.f 변조 전 단언 (agents 빈 sandbox 가 SKIP 아님)"
else
  printf -- '---\nname: nb-eval-ko\nrole: evaluator\ntools: Read, NotebookEdit\n---\n' > "$sb/agents/nb-eval-ko.md"
  err=$(bash "$sb/scripts/_internal/validate-structure.sh" 2>&1); rc=$?
  if [ $rc -eq 1 ] && echo "$err" | grep -q 'agent_tools: FAIL' && echo "$err" | grep -q 'nb-eval-ko:Write/Edit포함'; then
    PASS=$((PASS+1)); echo "PASS T15.f NotebookEdit 자동 편입 적발"
  else
    FAIL=$((FAIL+1)); echo "FAIL T15.f (rc=$rc, out=$(echo "$err" | grep agent_tools))"
  fi
fi
rm -rf "$sb"

# ── hardgate_classified — 클래스 A 재발 방지 메타 규칙 (20260806) ─────────────
# 20260806 감사에서 동일 클래스 결함 9건: SKILL.md 가 HARD 를 선언하는데 검사 구현이 0곳
# (foundation manifest·재사용·회귀 AC·advisor·DAST 소유확인·브랜치 삭제·B/C 존재·
#  화면 8섹션·analyzing baseline). 개별 수정만으로는 다음에 또 나온다 —
# 선언 시점에 "기계 판정" 인지 "기계화 불가" 인지 **분류를 강제**한다.
out=$(bash "$SCRIPT" 2>&1)
if echo "$out" | grep -q 'hardgate_classified: OK'; then
  PASS=$((PASS+1)); echo "PASS T-hg.a 전 HARD-GATE 분류 완료"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hg.a 미분류 잔존"
fi

# T-hg.b: 분류 문구를 지우면 적발 (비-vacuous — 메타 규칙이 실제로 본다)
#   ★ 격리 (FID 20260906-test-isolation-completion): 실 SKILL.md 를 변이하지 않는다.
#     종전 주석의 2026-08-09 손상 사건(git push 180s 타임아웃이 pre-push 의 run-all 을
#     죽였고 SKILL.md 규약 문구가 깨졌다)은 **실 파일 변이**가 전제였고, 사본에선 성립하지
#     않는다. trap 이 못 막던 것도 그것이다 — 정상 실행 중 변이 창에 남이 트리를 읽는 것.
#   ★ 사본 **안의** validate-structure 를 돌린다. $SCRIPT 를 부르면 실 트리를 검사해
#     격리가 무의미해진다(변이는 사본에만 있으니 vacuous PASS 도 아니고 그냥 FAIL 이다).
#   ★ trap 은 이제 **사본 정리** 용이다(복원 대상 없음). tmpdir 누수가 새 위험이고
#     T-hg.e 가 그것을 잠근다. EXIT **단독** 요구는 그대로다(T-hg.d 대조 — 지연 핸들러).
#   ★ T="" 후에는 블록 전체를 건넌다. `cd ""` 는 no-op 이라 빈 경로로 진행하면
#     사본이 아니라 **실 트리**에 스크립트를 돌리게 된다(T3 의 ARM B2 실측).
T=$(iso::make_tree "$PLUGIN") || { FAIL=$((FAIL+1)); echo "FAIL T-hg.b 격리 사본 생성 실패"; T=""; }
if [ -n "$T" ]; then
  # shellcheck disable=SC2064   # $T 는 **지금** 확장돼야 한다 (해제 후 정리 대상이 사라짐)
  trap "rm -rf '$T'" EXIT
  ISO_VS="$T/scripts/_internal/validate-structure.sh"
  python3 - "$T/skills/specifying-ko/SKILL.md" <<'PYEOF'
import sys
# hardgate_classified 는 **파일 전체**에서 분류 토큰을 찾는다(블록 스코프 아님).
#   따라서 한 문구만 지우면 같은 파일의 다른 `판정 SoT` 언급이 규칙을 만족시켜
#   변이가 통과한다(20260807 실측 — specifying-ko Step 6 에 AC 게이트 SoT 를
#   추가하자 본 테스트가 vacuous 로 전환됐다). 세 토큰을 모두 제거해야
#   "메타 규칙이 실제로 본다" 를 검사할 수 있다.
p=sys.argv[1]; s=open(p,encoding="utf-8").read()
for tok in ("판정 SoT", "기계화 불가", "대화 게이트"):
    s = s.replace(tok, "설명")
open(p,"w",encoding="utf-8").write(s)
PYEOF
  out2=$(bash "$ISO_VS" 2>&1)
  rm -rf "$T"; trap - EXIT
  # ★ ok/nope 는 이 파일 아래쪽에서 정의된다 — 여기선 아직 없으니 직접 관용구를 쓴다.
  if echo "$out2" | grep -q 'hardgate_classified: FAIL'; then
    PASS=$((PASS+1)); echo "PASS T-hg.b 분류 제거 시 적발 (비-vacuous · 사본 격리)"
  else
    FAIL=$((FAIL+1)); echo "FAIL T-hg.b 메타 규칙 무반응"
  fi
fi

# T-hg.c: 판정 SoT 로 주장한 스크립트는 실재해야 한다 (dangling 인용 금지)
if grep -q 'SoT 부재' "$SCRIPT"; then
  PASS=$((PASS+1)); echo "PASS T-hg.c dangling SoT 인용 검사 존재"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hg.c 실재 검사 없음"
fi



# ── T-hg.d/e: 변이 테스트 중단 안전성 (FID 20260809-mutation-test-trap) ──
#   계기: 2026-08-09 git push 180초 타임아웃(SIGTERM)이 pre-push 훅의 run-all 을 죽였고,
#   그때 T-hg.b 가 변이 창 안이라 skills/specifying-ko/SKILL.md 손상이 워킹트리에 남았다.
#   다음 run-all 이 3 스위트 FAIL 을 내며 원인 불명으로 보였다.

# T-hg.d: 패턴 실증(trap EXIT 이 SIGTERM 에서 복원) — 시간 임계 단언이라 test-timing-serial.sh 로 이동했다(직렬). T-hg.e 는 정적 잠금이라 여기에 남는다.

# T-hg.e: T-hg.b **자신**이 그 패턴을 쓰는가 (사본 정리 trap 잠금)
#   T-hg.d 는 패턴 지식만 잠근다. 실제 블록이 안 고쳐지면 결함은 그대로다.
#   ★ 잠그는 대상이 바뀌었다 (FID 20260906-test-isolation-completion): T-hg.b 가 사본 격리로
#     넘어가면서 **복원** trap(실 파일 되돌리기)은 사라지고 **사본 정리** trap 이 그 자리를 받았다.
#     남은 위험은 손상 잔존이 아니라 tmpdir 누수다 — 사본 경로(`$T`)를 포함한 정리 줄을 특정한다.
#   ★ **설치** trap 만 본다. `^ *trap .+ EXIT *$` 로 느슨하게 잡으면 해제 줄(`trap - EXIT`)이
#     그 조건을 만족시켜, 설치 trap 을 통째로 지워도 통과한다(구현 중 변이 M1 이 실증).
#   ★ 패턴은 **단일 인용**이다. 이중 인용이면 bash 가 `\$` → `$` 로 풀어 ERE 끝 앵커가 되고
#     매치가 0건이 된다 — 무변이인데 T-hg.e 가 FAIL 한다(T6 구현 중 실측).
#   ★ 시그널 목록은 **등식**으로 본다. " EXIT 로 끝나는가" 로 보면 `trap "…" INT TERM EXIT` 가
#     통과한다 — EXIT 로 끝나면서 INT/TERM 을 잡는 형태이고, 이건 다중 시그널 trap 의 가장
#     관용적 표기다(Phase C 리뷰어 실측). 그러면 20260809 FID 가 고친 지연-핸들러 결함이
#     "견고화" 명목으로 조용히 부활한다. 마지막 따옴표 뒤 전체가 정확히 `EXIT` 여야 한다.
_thgb=$(awk '/^# T-hg\.b:/{f=1} f{print} f && /^fi$/{exit}' "$0" 2>/dev/null)
_thgb_trap=$(printf '%s\n' "$_thgb" | grep -E '^ *trap .*rm -rf .*\$T' | head -1)
_thgb_sig=$(printf '%s' "$_thgb_trap" | sed 's/.*"[[:space:]]*//')
#   ★ (Phase C Minor-1) trap 만 보면 **실 파일 변이+복원 형태로의 회귀**를 못 본다 —
#     복원되므로 ISO 축의 지문은 동일하고, 위 trap 검사는 정리 줄만 본다. 그래서 python
#     변이 **대상**이 사본 하위(`"$T/`)임을 함께 잠근다. `"$PLUGIN/skills/…` 로 되돌리는
#     변이는 여기서 FAIL 한다 (`\$` 는 단일 인용 ERE 안의 리터럴 `$` 다 — 끝 앵커가 아니다).
_thgb_py=$(printf '%s\n' "$_thgb" | grep -cE '^ *python3 - "\$T/' || true)
if [ -n "$_thgb_trap" ] && [ "$_thgb_sig" = EXIT ] && [ "$_thgb_py" -eq 1 ]; then
  PASS=$((PASS+1)); echo "PASS T-hg.e T-hg.b 가 사본 정리 trap 을 EXIT 단독으로 보유 + 변이 대상이 사본 하위 (tmpdir 누수·실파일 변이 방지)"
else
  FAIL=$((FAIL+1)); echo "FAIL T-hg.e 사본 정리 trap 부재/시그널 비-EXIT 또는 변이 대상이 사본 밖 — 시그널='${_thgb_sig:-없음}' 줄='${_thgb_trap:-없음}' 사본변이대상=$_thgb_py(기대1)"
fi

ok(){ PASS=$((PASS+1)); echo "PASS $1"; }
nope(){ FAIL=$((FAIL+1)); echo "FAIL $1 — ${2:-}"; }

# ── T-cc4.a~c: chain_consistency 가 **커맨드 문서**의 chain 서술도 본다 (FID 20260829-chain-4th-source) ──
# 왜: 세 출처(chain.yaml ↔ SKILL.md `## 다음 skill` ↔ 메타 skill 화살표)를 대조하면서
#   같은 주장을 하는 **네 번째 출처 commands/*.md 만 빠져 있었다**. 사용자가 흐름을 이해하려고
#   읽는 것이 바로 그 문서다 — 틀려도 아무도 울지 않았다(전수 대조 결과 현재 20/20 정상).
# ★ 비대칭은 메타 skill 목록과 동일 규칙: 요약이라 생략은 허용하고, chain.yaml 에 없는 edge 를
#   주장할 때만 FAIL 한다. /start-all 이 3 edge 만 적는 것은 batch 가 decompose 에서 멈춰서다.
_cc4=$(mktemp -d)
for d in hooks skills commands scripts agents templates docs; do cp -R "$PLUGIN/$d" "$_cc4/" 2>/dev/null; done
cp "$PLUGIN"/*.md "$_cc4"/ 2>/dev/null
mkdir -p "$_cc4/.claude-plugin"; cp "$PLUGIN"/.claude-plugin/*.json "$_cc4/.claude-plugin/" 2>/dev/null

_cc4_run() { ( cd "$_cc4" && bash scripts/_internal/validate-structure.sh 2>&1 | grep chain_consistency ); }

out=$(_cc4_run)
case "$out" in ✅*) ok "T-cc4.a 사본 기준선 chain_consistency OK" ;; *) nope "T-cc4.a 기준선" "$out" ;; esac

# 주입 형태는 실제 문서와 같아야 한다 — 각 `→` 세그먼트가 **skill 명으로 시작**해야 추출된다
#   (메타목록과 동일 규칙). 초안은 `흐름: ` 접두를 붙여 첫 토큰이 매칭에서 빠졌고, 그래서
#   구현이 정상인데도 RED 가 재현되지 않았다 — 픽스처가 계약을 안 지킨 경우다.
printf '\nspecifying-ko → performance-test-ko\n' >> "$_cc4/commands/start.md"
out=$(_cc4_run)
case "$out" in ❌*) ok "T-cc4.b ★ 커맨드 문서의 미선언 edge 주장 → FAIL" ;;
                *) nope "T-cc4.b 미탐" "없는 edge 를 주장해도 통과: $out" ;; esac

cp "$PLUGIN/commands/start.md" "$_cc4/commands/start.md"
python3 - "$_cc4/commands/start-all.md" <<'PYEOF'
import sys, re
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
open(p,'w',encoding='utf-8').write(re.sub(r'[a-z][a-z-]*-ko( *→ *[a-z][a-z-]*-ko)+', '(생략)', s))
PYEOF
out=$(_cc4_run)
case "$out" in ✅*) ok "T-cc4.c 커맨드 문서 chain 생략은 허용 (요약 문서 — 과잉 차단 방지)" ;;
                *) nope "T-cc4.c 오탐" "$out" ;; esac
rm -rf "$_cc4"

# ── ISO 자가점검 (AC-5): 이 스위트가 실 트리를 변이하지 않음을 스스로 단언한다 ──
#   trap 은 **중단** 안전을, 이 어서션은 **정상 실행 중** 무변이를 담당한다.
if [ "$_iso_before" = "$(iso::fingerprint $_iso_paths)" ]; then
  PASS=$((PASS+1)); echo "PASS ISO 실 트리 전후 지문 불변"
else
  FAIL=$((FAIL+1)); echo "FAIL ISO 실 트리가 변이됐다 (이 스위트 또는 동시 실행 중인 다른 프로세스)"
fi

echo "passed=$PASS failed=$FAIL"
exit $FAIL
