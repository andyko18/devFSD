#!/usr/bin/env bash
# skill 크기 래칫 계약 (FID 20260828-skill-size-ratchet)
#
# 왜 래칫인가: 임계 경고는 무시된다 — 이 repo 는 이미 `skip-tracker` advisory 가 이빨 없이
#   SKIP 71% 를 방치한 전례가 있다. 대신 `.structure-baseline` 과 같은 패턴을 쓴다:
#   현재 크기를 기록하고 **초과하면 FAIL**, 늘리려면 `--update-baseline` 으로 명시 갱신한다.
#   임계값을 발명하지 않아도 되고, 49.5KB 짜리 SKILL.md 를 만든 드리프트가 다시 안 생긴다.
# 왜 bytes·lines 만인가: 토큰 수는 추정이다. 실측 문화의 repo 에서 게이트가 지어낸 수치를
#   출력하면 안 된다 — 토큰 환산은 리포트 산문의 몫이고, 게이트는 정확한 값만 다룬다.
# 한계 고백: 이 래칫은 **SKILL.md 본문**만 잰다(= 컨텍스트로 로드되는 것). 본문을 보조 파일로
#   옮기면 수치는 준다 — 그게 의도다(온디맨드 읽기). 다만 "보조 파일이 정말 온디맨드인가" 는
#   기계가 못 본다. 분할 리뷰에서 사람이 확인해야 한다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

BL="$PLUGIN/scripts/_internal/.skill-size-baseline"
VS="$PLUGIN/scripts/_internal/validate-structure.sh"

# ── T1: baseline 실재 + 스키마 ──
if [ -f "$BL" ]; then ok "T1.a baseline 존재"; else nope "T1.a baseline 부재" "$BL"; fi
if [ -f "$BL" ] && [ "$(jq -sr '[.[] | select(.skill) | select((.bytes|type)=="number" and (.lines|type)=="number")] | length' "$BL")" -eq "$(jq -sr '[.[] | select(.skill)] | length' "$BL")" ]; then
  ok "T1.b skill 레코드 스키마 (skill·bytes·lines)"
else
  nope "T1.b 스키마" "skill/bytes/lines 누락 레코드 있음"
fi
# 전 skill 이 baseline 에 있어야 한다 — 신규 skill 이 무기록으로 새면 래칫이 무의미하다
_n_skill=$(find "$PLUGIN/skills" -name SKILL.md | wc -l | tr -d ' ')
_n_base=$(jq -sr '[.[] | select(.skill)] | length' "$BL" 2>/dev/null || echo 0)
[ "$_n_skill" = "$_n_base" ] && ok "T1.c 전 skill 기록됨 ($_n_base)" \
  || nope "T1.c 커버리지" "skills=$_n_skill baseline=$_n_base (신규 skill 무기록 누수)"

# ── T2: chain 집계는 hooks/chain.yaml 에서 도출한다 (SoT 단일) ──
# 왜: 체인 스킬 목록을 lint 에 하드코딩하면 edge 변경 시 조용히 stale 이 된다 —
#   chain_consistency 가 이미 잡는 클래스의 드리프트를 새로 만드는 셈이다.
grep -q 'chain.yaml' "$VS" && ok "T2.a validate-structure 가 chain.yaml 을 읽는다" \
  || nope "T2.a SoT" "chain 집계가 chain.yaml 에서 도출되지 않음"
if grep -qE 'CHAIN_SKILLS=\(|chain_list=\(' "$VS"; then
  nope "T2.b SoT 단일" "체인 skill 목록 하드코딩 배열 발견"
else
  ok "T2.b 하드코딩 배열 없음"
fi

# ── T3: 현행 트리는 baseline 을 만족한다 (green 기준선) ──
out=$(bash "$VS" 2>&1)
printf '%s' "$out" | grep -qE '^(✅|ℹ️).*skill_size' && ok "T3.a 현행 트리 skill_size 통과" \
  || nope "T3.a" "$(printf '%s' "$out" | grep skill_size)"

# ── T4: ★ 되돌려-관찰 — 초과하면 실제로 FAIL 한다 ──
# 왜 필수인가: 래칫이 "있는데 안 무는" 상태가 가장 나쁘다(P1-4 로 지적한 advisory 무이빨과 동형).
#   skill 을 부풀려 FAIL 전환을 실측하고 원복한다.
#   ★ 격리 사본에서 부풀린다 (20260911-run-all-parallel): 실 skill 을 부풀리면 병렬로 도는
#     test-validate-structure 가 그 창에서 skill_size FAIL 을 봤고(스파이크 실측), trap 도 없어
#     중단되면 손상이 남았다. 사본 안의 validate-structure 는 사본 루트를 검사한다(isolated-tree.sh 규약).
source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
_victim=$(jq -sr '[.[] | select(.skill)] | sort_by(.bytes) | .[0].skill' "$BL" 2>/dev/null)
_T=""
command -v iso::make_tree >/dev/null 2>&1 && command -v iso::fingerprint >/dev/null 2>&1 && _T=$(iso::make_tree)
if [ -n "$_victim" ] && [ -n "$_T" ] && [ -f "$_T/skills/$_victim/SKILL.md" ]; then
  trap 'rm -rf "$_T"' EXIT
  _vf="$_T/skills/$_victim/SKILL.md"
  _vs="$_T/scripts/_internal/validate-structure.sh"
  _fp0=$(iso::fingerprint)
  cp "$_vf" "$_vf.ratchet-bak"
  # 주석 한 줄이 아니라 충분한 분량 — bytes·lines 양쪽 초과를 확실히 만든다
  for _i in $(seq 1 40); do echo "<!-- ratchet canary $_i -->" >> "$_vf"; done
  out2=$(bash "$_vs" 2>&1)
  mv "$_vf.ratchet-bak" "$_vf"
  printf '%s' "$out2" | grep -qE '^❌.*skill_size' \
    && ok "T4.a 초과 시 FAIL 전환 실측 ($_victim · 격리 사본)" \
    || nope "T4.a 래칫 무이빨" "부풀려도 FAIL 안 남: $(printf '%s' "$out2" | grep skill_size)"
  # 원복 확인 — 사본의 원복이 실제로 됐는지(다음 판정이 사본 잔존물을 보지 않게)
  out3=$(bash "$_vs" 2>&1)
  printf '%s' "$out3" | grep -qE '^❌.*skill_size' \
    && nope "T4.b 원복" "카나리 잔존 — 사본 오염" \
    || ok "T4.b 원복 확인 (사본 무오염)"
  # 실 트리는 처음부터 건드리지 않는다 — 지문이 같아야 한다
  [ "$(iso::fingerprint)" = "$_fp0" ] \
    && ok "T4.c 실 트리 지문 불변 (격리)" || nope "T4.c 실 트리 변이" "지문 $_fp0 → $(iso::fingerprint)"
else
  nope "T4 setup" "victim skill 결정 또는 격리 사본 실패 (victim=$_victim copy=${_T:-없음})"
fi

echo ""
finish
