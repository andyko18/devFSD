#!/usr/bin/env bash
# test-hardgate-ratchet.sh — hardgate_classified 래칫 계약 (20260830-metalayer-teeth)
# 왜: 메타 규칙이 꺾쇠 마커 보유 파일만 검사해 산문 HARD GATE 선언이 규칙 밖이었다.
#   회피법이 "마커를 안 쓰는 것" 이라 §auto 자기발급 면제표와 같은 형태였다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0
BL="$PLUGIN/scripts/_internal/.hardgate-baseline"
VS="$PLUGIN/scripts/_internal/validate-structure.sh"

source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
command -v iso::make_tree >/dev/null 2>&1 && command -v iso::make_git_tree >/dev/null 2>&1 \
  && command -v iso::fingerprint >/dev/null 2>&1 \
  || { echo "FATAL: isolated-tree 미로드(또는 반쯤 로드)" >&2; exit 1; }

# ★ 자가점검 (AC-10): 이 스위트가 실 트리를 변이하지 않음을 스스로 단언한다.
#   trap 은 **중단** 안전을 담당하고, 이 어서션은 **정상 실행 중** 무변이를 담당한다 —
#   역할이 겹치지 않는다.
# ★ porcelain 만으로는 **이미 M 인 tracked 파일의 내용 변화**를 못 본다(실측: ' M x' 상태에서
#   v1→v2 로 바꿔도 sha 동일 7e3de7179805). T2 구현 중엔 두 스위트가 정확히 M 상태다.
#   git diff HEAD 를 병기해 내용까지 지문에 넣는다.
_iso_paths='scripts/_internal/.hardgate-baseline skills/specifying-ko/SKILL.md commands/start-all.md skills scripts/tests'
_iso_before=$(iso::fingerprint $_iso_paths)

# ── H1 (AC-4 a): baseline 실재 + 현재 트리에서 OK ──
if [ -f "$BL" ]; then
  ok "H1.a .hardgate-baseline 실재"
else
  nope "H1.a" "baseline 부재 — 실 repo 에서 사라지면 래칫이 무음이 된다"
fi
out=$(cd "$PLUGIN" && bash "$VS" 2>&1)
if printf '%s' "$out" | grep -q '✅ hardgate_classified'; then
  ok "H1.b 현재 트리에서 hardgate_classified OK (AC-4 a)"
else
  nope "H1.b" "$(printf '%s' "$out" | grep hardgate)"
fi

# ── H2 (AC-5): baseline 부재 → SKIP (FAIL 아님) — revert 안전 ──
# ★ 격리 사본에서 지운다. 실 트리의 baseline 을 mv 하면 그 창에 다른 프로세스의
#   validate-structure 가 무음 SKIP 이 되어 래칫이 사라진 것처럼 보인다(20260906 실측).
T=$(iso::make_tree) || { nope "H2.a" "격리 사본 생성 실패"; T=""; }
if [ -n "$T" ]; then
  trap 'rm -rf "$T"' EXIT   # 중단 시 tmpdir 누출 방지 (AC-9)
  rm -f "$T/scripts/_internal/.hardgate-baseline"
  out2=$(cd "$T" && bash scripts/_internal/validate-structure.sh 2>&1)
  rm -rf "$T"; trap - EXIT
  if printf '%s' "$out2" | grep -qE 'hardgate_classified.*(SKIP|baseline 부재)'; then
    ok "H2.a baseline 부재 → SKIP (AC-5)"
  else
    nope "H2.a" "$(printf '%s' "$out2" | grep hardgate)"
  fi
fi

# ── H3 (AC-6 b): 비율 노출 ──
if printf '%s' "$out" | grep -qE 'hardgate_classified.*마커 [0-9]+/[0-9]+'; then
  ok "H3.a 마커 보유 비율 노출 (AC-6 b)"
else
  nope "H3.a" "비율 미노출 — 감소 판단을 데이터로 못 한다"
fi
if printf '%s' "$out" | grep -qE 'hardgate_classified.*규칙밖 [0-9]+'; then
  ok "H3.b 규칙 밖 수 노출 (AC-6 b)"
else
  nope "H3.b" "규칙 밖 수 미노출"
fi

# ── H4 (AC-4 b): baseline 밖 신규 산문 HARD GATE → FAIL ──
# ★ probe 를 실 트리에 만들면 그 창의 모든 validate-structure 가 4건 FAIL 한다
#   (file_counts·skill_conventions·readme_counts·skill_size). 사본에만 만든다.
T=$(iso::make_tree) || { nope "H4.a" "격리 사본 생성 실패"; T=""; }
if [ -n "$T" ]; then
  trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/skills/__ratchet_probe__"
  printf -- '---\nname: __ratchet_probe__\n---\n\n산문에서 HARD GATE 를 선언한다.\n' \
    > "$T/skills/__ratchet_probe__/SKILL.md"
  out4=$(cd "$T" && bash scripts/_internal/validate-structure.sh 2>&1)
  rm -rf "$T"; trap - EXIT
  if printf '%s' "$out4" | grep -qE 'hardgate_classified.*__ratchet_probe__'; then
    ok "H4.a baseline 밖 신규 산문 HARD GATE → FAIL + 이름 표시 (AC-4 b)"
  else
    nope "H4.a" "$(printf '%s' "$out4" | grep hardgate)"
  fi
fi

# ── H5 (AC-6 a): 기존 마커 검사 무손상 ──
# ★ 한 문구만 지우는 변이는 vacuous 다 — hardgate_classified 는 파일 **전체**에서
#   분류 토큰을 찾으므로(validate-structure.sh:422) 세 토큰을 **모두** 치환한다.
# ★ 사본에서 변이하므로 실 SKILL.md 는 손대지 않는다 — 종전엔 이 블록이 실 파일을
#   변이해 20260809 에 중단 시 손상이 남았고(주석 기록), 정상 실행 중에도 다른
#   프로세스에 `M` 으로 보였다(20260906 실측).
T=$(iso::make_tree) || { nope "H5.a" "격리 사본 생성 실패"; T=""; }
if [ -n "$T" ]; then
  trap 'rm -rf "$T"' EXIT
  python3 - "$T/skills/specifying-ko/SKILL.md" <<'PYEOF2'
import sys
p=sys.argv[1]; s=open(p,encoding="utf-8").read(); o=s
for tok in ("판정 SoT", "기계화 불가", "대화 게이트"):
    s = s.replace(tok, "설명")
assert s != o, "EDIT-FAILED: 치환 대상 토큰이 없다"
open(p,"w",encoding="utf-8").write(s)
PYEOF2
  _py_rc=$?
  if [ "$_py_rc" -ne 0 ]; then
    nope "H5.a" "EDIT-FAILED — 치환 대상 토큰 부재 (python rc=$_py_rc · 변이 미적용)"
    rm -rf "$T"; trap - EXIT; T=""
  else
    out5=$(cd "$T" && bash scripts/_internal/validate-structure.sh 2>&1)
    rm -rf "$T"; trap - EXIT
    if printf '%s' "$out5" | grep -qE 'hardgate_classified.*specifying-ko\(미분류\)'; then
      ok "H5.a 마커 3토큰 치환 → 미분류 검출 (AC-6 a)"
    else
      nope "H5.a" "$(printf '%s' "$out5" | grep hardgate)"
    fi
  fi
fi

# ── H6 (T3 Phase C Minor): 접두 이름 계약 — checker grep 의 **닫는 따옴표** 잠금 ──
# 계약: `grep -qF "\"skill\":\"$sn\""` 의 닫는 따옴표가 baseline 이름과의 **접두 오매치**를
#   막는다. 방향이 하나뿐이라는 것이 실측의 핵심이다:
#     · H6.b `planning-k`(**신규 ⊂ baseline**) — 닫는 따옴표를 빼면 패턴 `"skill":"planning-k` 가
#       `{"skill":"planning-ko"}` 에 매치돼 신규 산문 HARD GATE 가 **조용히 등재된 척** 숨는다.
#       닫는 따옴표가 지키는 방향은 이쪽 **하나뿐**이다(실측: 따옴표 제거 → H6.b 만 FAIL).
#       리뷰 보고의 "닫는 따옴표가 양방향 차단(`planning-ko-v2` 격추 실측)" 은 원인 오귀속이다 —
#       격추는 사실이나 따옴표 덕이 아니다. 그 예시 1건만으로 만든 테스트는 vacuous 했을 것이다.
#     · H6.a `planning-ko-v2`(**baseline ⊂ 신규**) — 닫는 따옴표에는 둔감하지만 vacuous 하지 않다.
#       매칭을 baseline 쪽 접두 의미로 "단순화"하는 변이(예: `case "$sn" in "$bl"*)`)를 잡는
#       유일한 케이스다. 그 변이에서 H4(`__ratchet_probe__`)·H6.b 는 여전히 발화하고 H6.a 만 숨는다.
#       두 방향은 서로 다른 변이를 잠근다 — 어느 쪽도 지우지 마라.
# ★ probe 를 사본에만 만든다 — 실 트리에 잔류하면 이후 모든 validate-structure 가 FAIL 한다.
#   H6.a·H6.b 는 **같은 validate-structure 실행 출력**을 읽는 현행 구조를 유지한다(사본 1개).
#   Q-b 의 "축마다 새 사본" 은 **논리 축 단위**이지 어서션 단위가 아니다.
T=$(iso::make_tree) || { nope "H6.a" "격리 사본 생성 실패"; nope "H6.b" "격리 사본 생성 실패"; T=""; }
if [ -n "$T" ]; then
  trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/skills/planning-ko-v2" "$T/skills/planning-k"
  printf -- '---\nname: planning-ko-v2\n---\n\ntest-hardgate-ratchet H6 probe.\n산문에서 HARD GATE 를 선언한다.\n' \
    > "$T/skills/planning-ko-v2/SKILL.md"
  printf -- '---\nname: planning-k\n---\n\ntest-hardgate-ratchet H6 probe.\n산문에서 HARD GATE 를 선언한다.\n' \
    > "$T/skills/planning-k/SKILL.md"
  out6=$(cd "$T" && bash scripts/_internal/validate-structure.sh 2>&1)
  rm -rf "$T"; trap - EXIT
  hg6=$(printf '%s\n' "$out6" | grep hardgate_classified)
  printf '%s' "$hg6" | grep -qF 'planning-ko-v2(래칫' \
    && ok "H6.a baseline⊂신규(planning-ko-v2) → 래칫 FAIL — baseline 쪽 접두 매칭 변이 잠금" \
    || nope "H6.a" "$hg6"
  printf '%s' "$hg6" | grep -qF 'planning-k(래칫' \
    && ok "H6.b baseline 이름의 **접두**(planning-k) → 래칫 FAIL — 닫는 따옴표 계약" \
    || nope "H6.b" "접두 이름이 baseline 항목에 숨었다(닫는 따옴표 소실 의심): $hg6"
fi

# ★ 자가점검 (AC-10): 이 스위트가 실 트리를 변이하지 않았음을 스스로 단언한다.
_iso_after=$(iso::fingerprint $_iso_paths)
[ "$_iso_before" = "$_iso_after" ] \
  && ok "ISO 실 트리 무변이 (실행 전후 git status 불변)" \
  || nope "ISO" "실 트리가 변이됐다 (이 스위트 또는 동시 실행 중인 다른 프로세스) — before=$_iso_before after=$_iso_after"

finish
