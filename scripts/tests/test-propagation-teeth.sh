#!/usr/bin/env bash
# test-propagation-teeth.sh — propagation-env-pin edge 의 판별력 (20260831-propagation-contract-record)
#
# 왜 별도 파일인가: 이 스위트는 `test-propagation.sh` 와 `.githooks/pre-commit` 의 **배선을 변이**해
#   edge 가 실제로 격추되는지 본다. 그런데 잠금 패턴을 **잠금 대상 파일 안에** 쓰면 그 문자열
#   자체가 매치해, 실제 배선을 지워도 edge 가 green 이 된다(자기참조 false-match).
#   **잠금을 시험하는 코드는 잠금 대상 밖에 산다.** `test-hardgate-ratchet.sh` 와 동형.
#   이 파일을 `test-propagation.sh` 로 합치지 마라 — 합치는 순간 아래 전부가 공허해진다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
source "$PLUGIN/scripts/tests/lib/isolated-tree.sh" 2>/dev/null || true
command -v iso::make_tree >/dev/null 2>&1 && command -v iso::fingerprint >/dev/null 2>&1 \
  || { echo "FATAL: isolated-tree 미로드(또는 반쯤 로드)" >&2; exit 1; }
# ISO pathspec = _mutate_run 호출부 3곳이 넘기는 두 파일
_iso_paths='.githooks/pre-commit scripts/tests/test-propagation.sh'
_iso_before=$(iso::fingerprint $_iso_paths)

CHK="$PLUGIN/scripts/_internal/check-propagation.sh"
# 원장 경로는 **env 로 덮을 수 없다** — 하드코딩이 의도다.
#   소비측 변수(SPECOPS_PROPAGATION_MATRIX)를 재사용하면 run-all 이 env 를 핀하지 않으므로
#   (실측: run-all.sh 에 핀·unset 0건) 이 스위트가 **유일한 비핀 소비자**가 되어, 셸 잔류
#   override 가 T1.e 를 픽스처 위에서 green 으로 만든다 — 이 FID 가 잠그는 바로 그 누수다.
#   전용 변수(SPECOPS_TEETH_MATRIX)로 우회하는 안도 **기각**했다: 이름만 다를 뿐 run-all 이
#   돌리는 스위트에 비핀 override 문을 새로 뚫는 것이라 같은 클래스다(자기 자신은 핀할 수 없다).
#   T1.e 의 판별력(앵커 드리프트를 격추하는가)은 원장을 백업·변이해 확인한다 — evidence.md 기록.
MATRIX="$PLUGIN/scripts/_internal/propagation-matrix.jsonl"
TP="scripts/tests/test-propagation.sh"
HK=".githooks/pre-commit"
[ -f "$CHK" ] || { nope "T0" "checker 부재"; finish; }
[ -f "$MATRIX" ] || { nope "T0" "matrix 부재"; finish; }

# 변이 → 체커 실행 → 사본 폐기. $1=대상(PLUGIN 상대 경로) $2=python 치환 본문
# ★ 시그니처 불변(인자 2개) — 호출부 :63·:72·:84 무수정.
#   실 트리를 더 이상 건드리지 않는다: 사본을 만들고 그 안에서 변이한 뒤 **사본의 체커**를 돈다
#   (check-propagation.sh:7 이 BASH_SOURCE 로 루트를 잡으므로 사본이 사본을 검사한다).
#   rc=97 = 사본 생성 실패 = 변이 미실행 (종전 "백업 실패" 와 동일 의미 — 호출부 nope 문면 유지).
_mutate_run() {
  local T out rc
  T=$(iso::make_tree "$PLUGIN") || return 97
  # shellcheck disable=SC2064
  trap "rm -rf '$T'" EXIT
  python3 - "$T/$1" <<PYEOF
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
$2
open(p, 'w', encoding='utf-8').write(s)
PYEOF
  out=$(cd "$T" && SPECOPS_PROPAGATION_MATRIX= bash "$T/scripts/_internal/check-propagation.sh" 2>&1); rc=$?
  rm -rf "$T"
  trap - EXIT
  printf '%s' "$out"
  return "$rc"
}

# 체커 출력은 `echo "PROPAGATION: FAIL [$id] $path missing /$pat/"` 로 **런타임 조립**된다.
#   통짜 리터럴을 grep 하면 사전검사가 dangling-lock 으로 잡으므로 조각만 쓴다.
_faillines() { printf '%s\n' "$1" | grep 'PROPAGATION: FAIL' | grep 'missing'; }

# ── T1.a: pre-commit 핀 제거 → 그 edge 만 격추 ──
#   (rc=97 = _mutate_run 사본 생성 실패 = 변이 미실행. 아래 nope 의 rc 값이 원인을 가리킨다)
m=$(_mutate_run "$HK" 's = s.replace("cp_out=$(SPECOPS_PROPAGATION_MATRIX= bash", "cp_out=$(bash")'); rc=$?
fl=$(_faillines "$m"); n=$(printf '%s\n' "$fl" | grep -c .)
if [ "$rc" -ne 0 ] && [ "${n:-0}" -eq 1 ] && printf '%s' "$fl" | grep -q 'githooks/pre-commit'; then
  ok "T1.a pre-commit 핀 제거 → 해당 edge 만 격추 (AC-2 a)"
else
  nope "T1.a" "rc=$rc n=${n:-0} / $fl"
fi

# ── T1.b: test-propagation P3 핀 제거 → 그 edge 만 격추 ──
m=$(_mutate_run "$TP" 's = s.replace("out=$(SPECOPS_PROPAGATION_MATRIX= bash \"$CHK\"", "out=$(bash \"$CHK\"")'); rc=$?
fl=$(_faillines "$m"); n=$(printf '%s\n' "$fl" | grep -c .)
if [ "$rc" -ne 0 ] && [ "${n:-0}" -eq 1 ] \
   && printf '%s' "$fl" | grep -q 'test-propagation.sh' \
   && printf '%s' "$fl" | grep -q 'SPECOPS_PROPAGATION_MATRIX'; then
  ok "T1.b P3 핀 제거 → 해당 edge 만 격추 (AC-2 b)"
else
  nope "T1.b" "rc=$rc n=${n:-0} / $fl"
fi

# ── T1.c: P10(핀의 이빨) 제거 → 그 edge 격추 ──
#   핀 자체는 남아 있다. 즉 "핀만 잠갔다면 감시자 소실이 무음이었다"가 증명된다.
m=$(_mutate_run "$TP" 's = s.replace("P10_HOOK", "P10_RENAMED_PROBE")'); rc=$?
fl=$(_faillines "$m"); n=$(printf '%s\n' "$fl" | grep -c .)
if [ "$rc" -ne 0 ] && [ "${n:-0}" -eq 1 ] && printf '%s' "$fl" | grep -q 'P10_HOOK'; then
  ok "T1.c P10 이빨 제거 → 격추 (핀만 잠갔다면 무음이었다, AC-2 c)"
else
  nope "T1.c" "rc=$rc n=${n:-0} / $fl"
fi

# ── T1.d: AC-5 방향성 단언 — 절대 건수를 세지 않는다 ──
#   건수는 픽스처 호출이 늘면 stale 이 된다(이 FID 가 지우는 173 하드코딩과 같은 클래스).
#   핀을 지운 사본에서 **채택 패턴은 사라지고 기각 패턴은 살아남는지**만 본다.
mut=$(mktemp) || exit 1
sed 's/^out=\$(SPECOPS_PROPAGATION_MATRIX= bash "\$CHK"/out=$(bash "$CHK"/' "$PLUGIN/$TP" > "$mut"
adopted=$(grep -cE '^out=\$\(SPECOPS_PROPAGATION_MATRIX= bash' "$mut")
rej_plain=$(grep -cE 'SPECOPS_PROPAGATION_MATRIX= bash' "$mut")
rej_wide=$(grep -cE 'out=\$\(SPECOPS_PROPAGATION_MATRIX=' "$mut")
rm -f "$mut"
if [ "${adopted:-1}" -eq 0 ] && [ "${rej_plain:-0}" -ge 1 ] && [ "${rej_wide:-0}" -ge 1 ]; then
  ok "T1.d 핀 제거 시 채택=0 · 기각(평문·광의)≥1 — 기각 패턴이었다면 무음 (AC-5)"
else
  nope "T1.d" "adopted=$adopted rej_plain=$rej_plain rej_wide=$rej_wide"
fi

# ── T1.e: 원장의 핀 패턴이 행두 앵커인가 (FR-2) ──
#   비앵커로 "단순화"하면 cp_out= 이 out= 패턴을 뚫어 두 edge 가 서로를 만족시킨다.
#   ★ 앵커 "개수"(startswith("^") 합계)를 세면 안 된다 — 핀 edge 를 비앵커화하면서 다른 edge
#     (P10_HOOK)를 앵커화하면 합계 2 가 유지돼 어서션이 green 인 채 핀 보호만 사라진다(실측).
#     그래서 **두 핀 패턴 각각의 접두를 path 와 함께** 단언한다. `^out=` 는 `^cp_out=` 의 접두가
#     아니므로(^c vs ^o) 서로 오매치·중복 카운트 없다.
#     접두만 보면 패턴 몸통을 도려낸 `^cp_out=` 한 조각도 통과하므로(체커도 매치한다) env 토큰
#     보존까지 함께 단언한다 — 어서션은 자기가 지킨다는 속성보다 약해선 안 된다.
_pin_edges() {  # $1=path $2=must_match 접두
  jq -rs --arg p "$1" --arg pre "$2" \
    'map(select(.id=="propagation-env-pin").edges[]
       | select(.path==$p
                and (.must_match|startswith($pre))
                and (.must_match|contains("SPECOPS_PROPAGATION_MATRIX")))) | length' "$MATRIX"
}
cp_n=$(_pin_edges "$HK" "^cp_out=")
out_n=$(_pin_edges "$TP" "^out=")
if [ "${cp_n:-0}" -eq 1 ] && [ "${out_n:-0}" -eq 1 ]; then
  ok "T1.e 핀 edge 2종이 각각 행두 앵커 유지 (FR-2)"
else
  nope "T1.e" "^cp_out= 핀 ${cp_n:-0}건(기대 1) · ^out= 핀 ${out_n:-0}건(기대 1) — 앵커+env 토큰 중 하나라도 빠지면 자기참조 매치가 열린다"
fi

[ "$_iso_before" = "$(iso::fingerprint $_iso_paths)" ] \
  && ok "ISO 실 트리 전후 지문 불변" \
  || nope "ISO" "실 트리가 변이됐다 (이 스위트 또는 동시 실행 중인 다른 프로세스)"

finish
