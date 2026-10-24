#!/usr/bin/env bash
# Wave C — 계약 경계 전파 매트릭스 스캔
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }

MATRIX="$PLUGIN/scripts/_internal/propagation-matrix.jsonl"
CHK="$PLUGIN/scripts/_internal/check-propagation.sh"

[ -f "$MATRIX" ] || { nope "P0" "matrix 부재"; finish; }
[ -f "$CHK" ] || { nope "P0" "checker 부재"; finish; }

# P1: 매트릭스 스키마 — edge id + edges[].path/must_match
ids=$(jq -rs '[.[].id] | sort | join(",")' "$MATRIX")
expected="ac-format-switch,active-fid-producer,assumption-digest-deterministic,attempt-fingerprint,batch-gate-propagation,batch-id-active-resume,batch-queue-init,batch-review-skip,batch-tail-contract,bounded-run-watchdog,decisions-ledger-resolved,declared-testcmd-anchor,design-critical-cap,design-overview-view,dev-no-ask,doc-number-lock,doctor-readonly-always-zero,end-loaded-skip,fid-size-gate,file-class-sot,fingerprint-unhashable-consumers,foundation-before-batch,foundation-entry-if-scope,foundation-fr-boundary,foundation-if-baseline,foundation-manifest-gate,foundation-merged-before-batch,foundation-shell-baseline,friction-aggregate-default,friction-scope-class,full-suite-fresh-consumption,gbrain-confidence-example,implementer-needs-approval-receiver,intent-per-fid-gate,leaf-run-mode-contract,lite-bc-mandatory,lite-clarify-plan-skip,lite-screen-if-keep,lite-strict-guard,matrix-pattern-lint,overengineering-review,p2t-generator-wiring,p2t-must-ac-gate,plugin-root-paths,predispatch-check-wiring,process-design-rename,propagation-env-pin,queue-fid-cell,r1-docs-only-scope,receipt-mandatory,reconcile-review-skip,redact-capture-wiring,regression-ac-gate,release-push-recursion-guard,release-ready-hard,review-audit-structured,review-presence-warn,review-reentry-fresh,review-return-summary,review-skip-pass-fastpath,review-verdict-contract,runner-anchor-exec-evidence,runner-whitelist-prefix,screen-quality-consumption,screens-overview-consumption,skip-citation-sot,start-entry-design-first,task-id-gate,tdd-red-observation,template-example-detectable,token-metering,trigger-prefix-value-space,yaml-cwd-shadow"
if [ "$ids" = "$expected" ]; then
  ok "P1 matrix id 정렬 일치"
else
  nope "P1" "ids=$ids expect=$expected"
fi

if jq -e 'all(.[]; (.id|type=="string") and (.edges|type=="array" and length>=1)
  and all(.edges[]; (.path|type=="string" and length>0) and (.must_match|type=="string" and length>0)))' \
  < <(jq -s '.' "$MATRIX") >/dev/null; then
  ok "P2 matrix 스키마"
else
  nope "P2" "invalid schema"
fi

# P3: checker green on repo
# ★ env 를 **의도적으로 비운다** — P4·P5·P9 가 픽스처를 물리려고 열어둔 문이라, 셸에
#   SPECOPS_PROPAGATION_MATRIX 가 잔류하면 이 양성 케이스가 1-edge 픽스처로 PASS 해
#   **run-all 이 오염 하에서 vacuous** 해진다 (.githooks/pre-commit 과 동일 클래스).
out=$(SPECOPS_PROPAGATION_MATRIX= bash "$CHK" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'PROPAGATION: PASS'; then
  ok "P3 check-propagation PASS"
else
  nope "P3" "rc=$rc out=$out"
fi

# ── P4 (AC-2): 파일 부재 edge → 체커가 실제로 FAIL 한다 ──
# 종전엔 검출 로직을 여기서 재구현해 자기 자신을 검사했다(체커를 지워도 green).
# 이제 픽스처를 물려 **실제 체커**를 부른다.
FX="$PLUGIN/scripts/tests/fixtures/propagation"
p4_out=$(SPECOPS_PROPAGATION_MATRIX="$FX/missing-path.jsonl" bash "$CHK" 2>&1); p4_rc=$?
if [ "$p4_rc" -eq 1 ] && printf '%s' "$p4_out" | grep -q 'missing file'; then
  ok "P4 파일 부재 edge → 체커 rc=1 + missing file (AC-2)"
else
  nope "P4" "rc=$p4_rc out=$p4_out"
fi

# ── P5 (AC-2): 패턴 불일치 edge → 체커가 실제로 FAIL 한다 ──
p5_out=$(SPECOPS_PROPAGATION_MATRIX="$FX/mismatch-pattern.jsonl" bash "$CHK" 2>&1); p5_rc=$?
# 'missing /<pat>/' 는 런타임 조립이라 통짜 리터럴로 잠그지 않는다 — 두 정적 조각으로 나눈다
#   ('missing /' 는 체커 소스에, 패턴 문자열은 픽스처 파일에 각각 실재).
if [ "$p5_rc" -eq 1 ] && printf '%s' "$p5_out" | grep -q 'missing /' \
   && printf '%s' "$p5_out" | grep -q 'never-match-zzz-wave-c'; then
  ok "P5 패턴 불일치 edge → 체커 rc=1 + missing pattern (AC-2)"
else
  nope "P5" "rc=$p5_rc out=$p5_out"
fi

# P6: README 에 매트릭스 유지 안내
if grep -q 'propagation-matrix' "$PLUGIN/scripts/README.md"; then
  ok "P6 README propagation-matrix 안내"
else
  nope "P6" "README 안내 부재"
fi

# P7: 실제 드리프트 회귀 락 — batch-review-skip 이 소비 경로 문자열까지 요구하는가
#     계기 44cd095: revert 가 start-all.md 에서 risk-profile.json 경로만 떨어뜨렸는데
#     구 edge(batch-review-skip 토큰만)는 통과했고 T1.e 가 하루 red 로 방치됐다.
if jq -es 'map(select(.id=="batch-review-skip").edges[]
             | select(.path=="commands/start-all.md" and (.must_match|test("risk-profile"))))
           | length > 0' "$MATRIX" >/dev/null; then
  ok "P7 batch-review-skip 이 start-all 소비 경로까지 락"
else
  nope "P7" "start-all.md ~ risk-profile 경로 edge 부재 (44cd095 재발 가능)"
fi

# P8: end-loaded 리뷰 계약 4자 전파 (implementing 산출 → requesting 사유 → start-all 조건 → batch-state 재검)
el_paths=$(jq -rs 'map(select(.id=="end-loaded-skip").edges[].path) | sort | join(",")' "$MATRIX")
for want in skills/implementing-ko/SKILL.md skills/requesting-code-review-ko/SKILL.md \
            commands/start-all.md scripts/batch-state.sh; do
  case ",$el_paths," in *",$want,"*) ;; *) nope "P8" "end-loaded-skip 에 $want 누락"; el_missing=1 ;; esac
done
[ -z "${el_missing:-}" ] && ok "P8 end-loaded 계약 4자 전파" || true

# ── P9 (AC-1): MATRIX env override — 기본값 불변 + 픽스처 지정 동작 ──
# 왜: 체커의 MATRIX 가 하드코딩이라 테스트가 픽스처를 물릴 수 없었고, 그래서 P4/P5 가
#   검출 로직을 테스트 안에 재구현해 자기 자신을 검사했다(체커를 지워도 green).
p9_tmp=$(mktemp -d) || exit 1
printf '%s\n' '{"id":"p9-probe","edges":[{"path":"scripts/_internal/check-propagation.sh","must_match":"PROPAGATION"}]}' \
  > "$p9_tmp/one-edge.jsonl"
p9_out=$(SPECOPS_PROPAGATION_MATRIX="$p9_tmp/one-edge.jsonl" bash "$CHK" 2>&1); p9_rc=$?
# 어서션은 **정적 존재 문자열**로 구성한다 — 'PASS (1 edges)' 는 런타임 조립이라
#   사전검사(check-plan-predispatch)가 dangling-lock 으로 잡는다. OK 줄 수로 edge 수를 센다.
p9_ok=$(printf '%s' "$p9_out" | grep -c 'PROPAGATION: OK')
if [ "$p9_rc" -eq 0 ] && [ "${p9_ok:-0}" -eq 1 ]; then
  ok "P9.a MATRIX override 적용 — 픽스처 1 edge 로 판정 (AC-1 b)"
else
  nope "P9.a" "rc=$p9_rc ok줄=${p9_ok:-0} out=$p9_out"
fi
rm -rf "$p9_tmp"

# ── P10: 소비측 env 핀 — pre-commit 게이트가 잔류 오염에 지배되지 않는다 ──
# 왜 이 케이스가 필요한가: P9 가 연 override 문은 **테스트용**인데, 셸에 export 가 잔류하면
#   .githooks/pre-commit 의 `cp_out=$(... )` 가 rc=0 경로에서 출력을 삼켜 **전량 edge 게이트가
#   무음으로 1 edge** 가 된다. 그 핀(`SPECOPS_PROPAGATION_MATRIX= bash "$CP"`)은 pre-commit 과
#   위 P3 **두 곳에** 사는 계약인데, 지워도 깨끗한 셸에서는 아무 스위트도 FAIL 하지 않았다 —
#   즉 픽스에 이빨이 없었다. 오염을 실제로 주입해 그 상태에서만 갈리게 한다.
# 픽스처는 T2 의 mismatch(1 edge · 반드시 FAIL)를 재사용한다 — 핀이 없으면 훅이 이걸 보고
#   rc=1 + `PROPAGATION: FAIL` 을 뱉고, 핀이 있으면 전량 매트릭스를 보아 rc=0 무출력이다.
P10_HOOK="$PLUGIN/.githooks/pre-commit"
if [ ! -f "$P10_HOOK" ]; then
  skip "P10 .githooks/pre-commit 부재 — 소비측 핀 검증 불가"
else
  p10_out=$(cd "$PLUGIN" && SPECOPS_PROPAGATION_MATRIX="$FX/mismatch-pattern.jsonl" \
    bash "$P10_HOOK" 2>&1); p10_rc=$?
  if [ "$p10_rc" -eq 0 ] && ! printf '%s' "$p10_out" | grep -q 'PROPAGATION: FAIL'; then
    ok "P10 pre-commit 이 잔류 SPECOPS_PROPAGATION_MATRIX 를 무시 — 무음 vacuous 차단"
  else
    nope "P10" "오염이 게이트를 지배한다(핀 소실 의심): rc=$p10_rc out=$p10_out"
  fi
fi

# P11: 산문 계약 앵커의 **술어 토큰** 락 — 앵커가 키워드로 되돌아가는 것을 막는다
#     계기 20260905-prose-contract-anchors: 산문 앵커 6건이 키워드 하나만 걸어
#     계약 문장을 지워도 통과했다(변이 실측). 이를 계약 문장 앵커로 조였는데,
#     ★ 그 형태를 잠그는 어서션이 어디에도 없었다 — P1 은 id 목록, P8 은 path,
#     test-exec-evidence 는 id 존재만 본다. 6 앵커를 옛 키워드로 되돌려도
#     전 스위트가 green 이었다(Phase C I-5 실측). P7 과 동형으로 잠근다.
#
#     각 record 의 must_match 가 **계약의 술어**를 담는지 본다. 주어(§lite·review_mode
#     같은 키워드)만으로는 통과 못 한다 — 그게 이 FID 가 고친 결함 자체다.
#     한계: 술어 토큰의 존재만 보므로 "앵커가 실제로 무엇을 잡는가"는 검사하지 않는다
#     (그건 변이 실행이 필요하고, 이 스위트는 매트릭스를 읽기만 한다).
_p11_fail=0
_p11_check(){  # $1=record id  $2=술어 토큰 정규식
  if jq -es --arg id "$1" --arg tok "$2" \
       'map(select(.id==$id).edges[] | select(.must_match|test($tok))) | length > 0' \
       "$MATRIX" >/dev/null 2>&1; then :; else
    _p11_fail=1; printf '  P11 미충족: %s 앵커에 술어 토큰 /%s/ 없음\n' "$1" "$2" >&2
  fi
}
_p11_check design-critical-cap     '정지|자동통과 금지'
_p11_check lite-clarify-plan-skip  '호출 금지|호출하지 않'
_p11_check lite-screen-if-keep     '제외 금지'
_p11_check lite-bc-mandatory       '유지'
_p11_check end-loaded-skip         '1회'
_p11_check declared-testcmd-anchor '필수|게이트'
if [ "$_p11_fail" -eq 0 ]; then
  ok "P11 산문 계약 앵커 6건이 술어 토큰 유지 (키워드 회귀 차단)"
else
  nope "P11" "앵커가 계약 술어를 잃었다 — 키워드로 되돌아갔는지 확인"
fi

finish
