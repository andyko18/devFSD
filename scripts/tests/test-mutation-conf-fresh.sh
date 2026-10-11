#!/usr/bin/env bash
# mutation-equivalent.conf 신선도 계약 (FID 20260829-mutation-coverage)
#
# 왜 필요한가 (실측): conf 는 **절대 줄번호**로 equivalent mutant 를 지정한다. target 이
#   자라면 조용히 어긋나고, 어긋난 항목은 매칭 0건이 되어 **정상 변이가 equivalent 로 제외되지
#   못한 채** score 가 거짓 하락한다(conf 주석 실측: 64% → 50%). 반대로 stale 이 통과로
#   뭉개지면 거짓 상승한다.
#   판정기(`mutation-score.sh --check-conf`)는 **1초**면 끝나는데 `mutation-score.sh` 가
#   run-all 명명 규칙(test-*.sh) 밖이라 아무도 안 돌렸고, 이번 세션의 governance-lib 편집
#   3건으로 **16/18 이 stale** 이 됐다 — 그동안 아무 게이트도 울지 않았다.
#   무거운 mutation 실행은 그대로 수동으로 두고, **1초짜리 정합만** 상시 게이트에 넣는다.
# 20261010: conf 의 키가 줄번호에서 **함수 + 줄 원문**으로 바뀌었다(mutation-score.sh 머리말). 다른 곳에 줄을
#   넣고 빼는 편집으로는 더 이상 stale 이 되지 않는다 — T6 이 실제 conf 로 그것을 잠근다. 등재한 줄 자체를 고치거나
#   같은 원문의 줄을 함수 안에 늘리고 줄이면 stale 이고, 그때는 그 행의 근거를 다시 읽는다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
PASS=0; FAIL=0

MS="$PLUGIN/scripts/tests/mutation-score.sh"
TCONF="$PLUGIN/scripts/tests/mutation-targets.conf"
ECONF="$PLUGIN/scripts/tests/mutation-equivalent.conf"

[ -f "$MS" ] && ok "T1.a mutation-score.sh 존재" || nope "T1.a" "$MS 부재"
[ -f "$TCONF" ] && ok "T1.b targets conf 존재" || nope "T1.b" "$TCONF 부재"
[ -f "$ECONF" ] && ok "T1.c equivalent conf 존재" || nope "T1.c" "$ECONF 부재"

# ── T2: equivalent conf 전 항목이 현재 소스에 실재한다 (핵심) ──
out=$(cd "$PLUGIN" && bash "$MS" --check-conf 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  ok "T2.a equivalent conf 신선 ($(printf '%s' "$out" | grep -o '[0-9]*/[0-9]* 매칭' | head -1))"
else
  nope "T2.a conf stale" "$(printf '%s' "$out" | grep STALE | head -3 | tr '\n' ' ') — 그 줄이 바뀌었다. 행의 근거를 다시 보고 --anchor 로 키를 다시 만든다"
fi

# ── T3: targets conf 의 대상 스크립트·테스트 명령이 실재한다 ──
# 왜: 대상 경로가 오타·이동이면 mutation 이 **대상 0건으로 조용히 통과**한다(측정 없는 green).
miss=0; n=0
while IFS='|' read -r tgt cmd; do
  case "$tgt" in ''|\#*) continue ;; esac
  n=$((n+1))
  [ -f "$PLUGIN/$tgt" ] || { miss=$((miss+1)); echo "  대상 부재: $tgt"; }
  # 명령에 등장하는 test 스크립트 경로가 전부 실재하는가
  for p in $(printf '%s' "$cmd" | grep -oE '(scripts|hooks)/[A-Za-z0-9._/-]+\.sh'); do
    [ -f "$PLUGIN/$p" ] || { miss=$((miss+1)); echo "  테스트 부재: $p (target=$tgt)"; }
  done
done < "$TCONF"
[ "$miss" -eq 0 ] && ok "T3.a targets conf 경로 전건 실재 (대상 ${n}종)" \
  || nope "T3.a 경로" "부재 ${miss}건 — mutation 이 대상 0건으로 조용히 통과한다"

# ── T4: 게이트 핵심 스크립트가 측정 대상에 들어 있다 ──
# 왜: 측정 대상이 좁으면 "mutation 돌린다" 는 말만 남는다. 차단 판정을 실제로 내리는
#   두 파일(governance-lib·pretool-governance)과 신설 상한 헬퍼는 최소 커버 대상이다.
for must in hooks/governance-lib.sh hooks/pretool-governance.sh scripts/_internal/run-bounded.sh; do
  grep -q "^${must}|" "$TCONF" \
    && ok "T4 측정 대상 포함: $must" \
    || nope "T4 커버리지" "$must 가 mutation-targets.conf 에 없음"
done

# ── T5: 주간 CI matrix 가 targets conf 의 모든 대상을 덮는다 (20261008) ──
# 왜: llm-smoke.yml 의 mutation job 은 대상별 matrix 라, conf 에 대상을 추가하고 matrix 를 안 고치면
#   그 대상은 CI 에서 **측정되지 않는다**(6주 `cancelled` 침묵과 같은 "게이트가 조용히 꺼짐" 계열).
#   역방향(matrix 에만 있는 대상)은 mutation-score.sh --target 이 rc 2 로 막는다.
WF="$PLUGIN/.github/workflows/llm-smoke.yml"
if [ -f "$WF" ]; then
  wmiss=""; wn=0
  while IFS='|' read -r tgt cmd; do
    case "$tgt" in ''|\#*) continue ;; esac
    wn=$((wn+1))
    grep -qE "^[[:space:]]+target:[[:space:]]*${tgt}[[:space:]]*$" "$WF" || wmiss="$wmiss $tgt"
  done < "$TCONF"
  [ "$wn" -ge 1 ] && [ -z "$wmiss" ] && ok "T5.a CI matrix 가 conf 대상 ${wn}종 전부 포함" \
    || nope "T5.a" "llm-smoke.yml mutation matrix 누락:${wmiss:- (conf 대상 0건)}"
else
  nope "T5.a" "llm-smoke.yml 부재"
fi

# ── T6: 실제 conf 는 대상 파일의 줄이 밀려도 같은 사이트를 가리킨다 (20261010-mutation-equiv-anchors) ──
# 왜: 종전 키(절대 줄번호)는 대상에 줄 하나만 끼워도 뒤 항목이 전부 밀렸고, 밀린 자리에 같은 패턴의 다른 줄이
#   있으면 --check-conf 가 통과한 채 엉뚱한 가드가 등가로 빠졌다. 등재 대상 4종의 사본 머리에 7줄을 끼우고,
#   풀린 사이트가 **전부 정확히 +7** 인지 본다(개수만 보면 다른 줄로 옮겨 붙은 것을 못 잡는다).
# shellcheck disable=SC1090
source "$MS"
t6=$(mktemp -d); t6n=0; t6bad=""
for tgt in $(grep -v '^#' "$ECONF" | cut -f1 | grep . | sort -u); do
  [ -f "$PLUGIN/$tgt" ] || { t6bad="$t6bad $tgt(부재)"; continue; }
  { printf '# pad\n# pad\n# pad\n# pad\n# pad\n# pad\n# pad\n'; cat "$PLUGIN/$tgt"; } > "$t6/shifted.sh"
  a=$(cd "$PLUGIN" && mut::equiv_sites "$tgt" | awk -F'\t' '{ print $1 + 7 "\t" $2 }' | sort)
  b=$(cd "$PLUGIN" && mut::equiv_sites "$tgt" "$t6/shifted.sh" | sort)
  n=$(printf '%s\n' "$a" | grep -c .)
  t6n=$((t6n + n))
  [ "$n" -ge 1 ] && [ "$a" = "$b" ] || t6bad="$t6bad $tgt"
done
rm -rf "$t6"
[ "$t6n" -ge 1 ] && [ -z "$t6bad" ] && ok "T6.a 줄이 7줄 밀려도 등가 ${t6n}건이 같은 사이트를 가리킨다" \
  || nope "T6.a" "줄 이동 뒤 어긋난 대상:${t6bad:- (등재 0건)}"

echo ""
finish
