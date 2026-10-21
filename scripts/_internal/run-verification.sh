#!/usr/bin/env bash
# 추출된 검증 명령을 순차 실행 + evidence.md append + exit code 집계
# Usage: run-verification.sh <FID>
#
# 동작:
#   1. extract-test-commands.sh <FID 의 tasks.md> 로 명령 목록 추출
#   2. 각 명령 순차 실행 + stdout/stderr 전문을 evidence.md 에 append
#   3. 모두 PASS → stdout "VERIFY: PASS" + exit 0
#   4. 1건 FAIL → stderr "VERIFY: FAIL <cmd> (exit=N)" + exit 1
#
# U3 (wobbly §U3): verifying-evidence-ko 의 수동 명령 실행 → 자동화.
# "요약 금지" 5원칙 1 투명성을 스크립트가 강제 (출력 전문 기록).
set -u

FID="${1:?usage: $0 <FID>}"
# worktree 에서 불려도 메인 worktree 의 .specops 를 쓴다 — 테스트·구조 규칙 명령은 원래 폴더로 (20261016-hook-worktree-target)
#   자기 경로는 이동 전에 절대경로로 잡는다 — 아래 PLUGIN 이 이것을 쓴다.
_RV_SELF=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
. "$_RV_SELF/specops-root.sh" 2>/dev/null || true
command -v _sr_leave >/dev/null 2>&1 || _sr_leave() { :; }
specops_root_enter "$FID" 2>/dev/null || true
TASKS=".specops/$FID/tasks.md"
EVIDENCE=".specops/$FID/evidence.md"
START_SECONDS=$(date +%s)

if [ ! -f "$TASKS" ]; then
  echo "tasks.md not found: $TASKS" >&2
  exit 1
fi

PLUGIN=$(cd "$_RV_SELF/../.." && pwd)
EXTRACT="$PLUGIN/scripts/_internal/extract-test-commands.sh"
AUDIT_SH="$PLUGIN/scripts/_internal/check-review-audit.sh"
FND_SH="$PLUGIN/scripts/_internal/check-foundation-manifest.sh"
LABEL_SH="$PLUGIN/scripts/_internal/check-spec-label-compat.sh"
PRESENCE_SH="$PLUGIN/scripts/_internal/check-review-presence.sh"
ACFMT_SH="$PLUGIN/scripts/_internal/check-ac-format.sh"
STATE_SH="$PLUGIN/scripts/_internal/verification-state.sh"
METRIC_SH="$PLUGIN/scripts/_internal/record-metric.sh"
METER_SH="$PLUGIN/scripts/_internal/meter-tokens.sh"
ATTEMPT_SH="$PLUGIN/scripts/_internal/attempt-fp.sh"
[ -f "$PLUGIN/scripts/_internal/run-bounded.sh" ] && source "$PLUGIN/scripts/_internal/run-bounded.sh"

# 동일 실패 지문 재료 (FID 20261002-attempt-fingerprint) — 실패한 테스트 명령(CMD·EXIT·출력)과 사전 검사
#   실패 사유(REASON)를 임시 파일에 모아 판정 합류점(_record_result)에서 attempt-fp.sh record 에 넘긴다.
#   관측 전용·fail-open: mktemp·쓰기 실패는 재료 없이 진행하고 VERIFY 판정·출력·종료 코드에 영향 없다.
#   재료 원문은 임시 파일에만 있고(EXIT trap 으로 삭제) attempts.jsonl 에는 해시만 남는다.
MATERIAL=$(mktemp 2>/dev/null) || MATERIAL=""
[ -n "$MATERIAL" ] && trap 'rm -f "$MATERIAL"' EXIT
_mat_cmd() { # <cmd> <exit> <출력>
  [ -n "$MATERIAL" ] || return 0
  { printf 'CMD: %s\nEXIT: %s\n' "$1" "$2"; printf '%s\n' "$3"; } 2>/dev/null >> "$MATERIAL"
  return 0
}
_mat_reason() { # <tag> [<검사 출력>] — 출력 줄은 attempt-fp 의 실패 줄 필터를 거친다(위반 대상 구분용)
  [ -n "$MATERIAL" ] || return 0
  { printf 'REASON: %s\n' "$1"; [ $# -ge 2 ] && printf '%s\n' "$2"; } 2>/dev/null >> "$MATERIAL"
  return 0
}

all_pass=1
executed=0
skipped=0
failed=0

# 단일 판정 기록: evidence 호환 stamp + 구조화 상태 SoT + 비용/수율 계측.
# 구조화 기록 실패가 테스트 결과를 뒤집지는 않지만 stderr로 표면화한다.
_record_result() { # <verdict>
  local verdict="$1" now duration_ms
  now=$(date +%s)
  duration_ms=$(( (now - START_SECONDS) * 1000 ))
  mkdir -p "$(dirname "$EVIDENCE")"
  echo "RUN-VERIFICATION-RESULT: $verdict" >> "$EVIDENCE"
  if ! bash "$STATE_SH" record "$FID" "$verdict" \
      --executed "$executed" --skipped "$skipped" --failed "$failed" \
      --duration-ms "$duration_ms" 2>/dev/null; then
    echo "WARN: verification-state 기록 실패 (FID=$FID)" >&2
  fi
  # wall_ms 는 **이 스크립트 자체의 실행 구간**을 잰다 — `START_SECONDS`(:18, 스크립트 시작)
  #   부터 판정까지이므로 AC 계약·리뷰 감사·foundation·라벨·산출물 선행 검사도 포함된다.
  #   포함하지 않는 것은 **부모가 별도로 돌린 러너**다(예: run-all.sh 전체). 실측 사례:
  #   같은 verify 단계에서 wall_ms=35000 인데 부모의 run-all 은 ~570s 였다.
  #   이 값을 "verify 단계 총 소요"로 읽으면 틀린다.
  if ! bash "$METRIC_SH" --fid "$FID" --phase verify --wall-ms "$duration_ms" \
      --verdict "$verdict" 2>/dev/null; then
    echo "WARN: verify metric 기록 실패 (FID=$FID)" >&2
  fi
  # 동일 실패 지문 기록(관측 전용·fail-open) — FAIL·PASS 만. stdout 은 버리고 실패해도 판정·종료 코드는 불변.
  case "$verdict" in
    PASS|FAIL)
      if [ -f "$ATTEMPT_SH" ]; then
        bash "$ATTEMPT_SH" record "$FID" "$verdict" --material "${MATERIAL:-}" >/dev/null \
          || echo "WARN: attempt 지문 기록 실패 (FID=$FID)" >&2
      fi ;;
  esac
  # 토큰 관측(관측 전용·fail-open): fid-start 가 기록된 실 FID 에서만 호출 — fixture FID 는 호출 자체가 없다.
  # 출력 0, 실패·시간초과(124) 무시 — verdict·종료 코드·evidence stamp 에 영향 없음.
  if command -v bounded_run >/dev/null 2>&1 && [ -f "$METER_SH" ] \
     && grep -q '"phase":"fid-start"' ".specops/$FID/metrics.jsonl" 2>/dev/null; then
    bounded_run 5 bash "$METER_SH" "$FID" >/dev/null 2>&1 || true
  fi
}

# AC 계약 실재 검사 (20260828-ac-absence-detect).
#   결함: check-ac-format 은 emit-context.sh 에서만 불렸다 — **decompose 단계 전용**이다.
#   clarify·plan·decompose 를 건너뛰면 emit-context 가 돌 기회 자체가 없어 AC 파일 부재가
#   아무 데서도 안 걸린다. specifying-ko 는 "emit-context 가 acceptance-criteria.md 실재를
#   요구한다" 를 승인 우회 차단 근거로 선언하는데, 그 전제가 깨진다.
#   실측(argus batch-20260729): AC 가 아예 없는 FID 3건이 verify·리뷰를 통과했다.
#
#   AC 는 **스프린트 계약**이다 — 없으면 Phase B 가 대조할 기준이 없다. 그래서 차단이다.
#   단 freework mini-FID 는 면제한다: templates/freework.md 가 "spec.md 없는 경량 트랙" 이라고
#   직접 선언하므로, spec.md 부재 = lifecycle FID 가 아님 → 계약을 요구할 근거가 없다.
_ac_contract_check() {
  [ -f "$ACFMT_SH" ] || return 0
  [ -f ".specops/$FID/spec.md" ] || return 0   # freework mini-FID — 면제(spec.md 없는 경량 트랙)
  local out ec
  out=$(bash "$ACFMT_SH" "$FID" 2>&1); ec=$?
  [ "$ec" -eq 2 ] || return 0               # 2 = AC 파일 부재. 그 외(포맷 FAIL)는 emit-context 관할
  _mat_reason ac-format "$out"
  echo "VERIFY: FAIL ac-format" >&2
  echo "$out" >&2
  echo "  acceptance-criteria.md 가 없으면 Phase B 가 대조할 계약이 없다 — specifying-ko 가 spec.md 와 쌍으로 산출한다." >&2
  return 1
}

commands=$(bash "$EXTRACT" "$TASKS")
if [ -z "$commands" ]; then
  # 명령 0건이어도 리뷰 감사 추적은 검사한다 — 여기서 무조건 exit 0 하면 "테스트 명령을
  #   안 쓰는 FID" 가 review-audit 을 통째로 비껴가는 구멍이 된다.
  # AC 계약 — 명령 0건 경로도 검사한다(review-audit 과 동일한 "NO COMMANDS 우회" 구멍).
  _ac_contract_check || { failed=$((failed + 1)); _record_result FAIL; exit 1; }
  if [ -f "$AUDIT_SH" ]; then
    audit_out=$(bash "$AUDIT_SH" "$FID" 2>&1) || {
      failed=$((failed + 1))
      _mat_reason review-audit "$audit_out"
      _record_result FAIL
      echo "VERIFY: FAIL review-audit" >&2
      echo "$audit_out" >&2
      exit 1
    }
  fi
  # foundation manifest 도 동일 이유로 여기서 검사한다 — review-audit 이 봉합한 것과 같은
  #   "NO COMMANDS 우회" 구멍. 테스트 명령 0건인 foundation FID 가 게이트를 통째로 비껴간다.
  if [ -f "$FND_SH" ]; then
    fnd_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bash "$FND_SH" "$FID"; } 2>&1 ) || {
      failed=$((failed + 1))
      _mat_reason foundation-manifest "$fnd_out"
      _record_result FAIL
      echo "VERIFY: FAIL foundation-manifest 미산출" >&2
      echo "$fnd_out" >&2
      exit 1
    }
  fi
  _record_result NOT_RUN
  echo "VERIFY: NOT_RUN — 테스트 명령 0건" >&2
  exit 1
fi

mkdir -p "$(dirname "$EVIDENCE")"
{
  echo ""
  echo "## run-verification.sh ($(date '+%Y-%m-%d %H:%M:%S'))"
  echo ""
} >> "$EVIDENCE"

# 러너별 선두 앵커 — 각 패턴이 ^ 로 고정되어 임의 명령 실행 차단 (AC-2).
# bash: 기존 동작 보존(scripts/*.sh 한정). 그 외 러너는 표준 호출형만 허용.
#
# 한계 고백 (5원칙 5) — 아래는 의도된 미지원이지 버그가 아니다:
#   1. `go test ./...` 는 실행되지 않는다. 아래 `*..*` path-traversal 가드가 `./...` 를 먼저 잡아 SKIP.
#      go 의 사실상 표준 호출형이지만 미지원 — 개별 패키지 경로(`go test ./pkg/foo`)를 쓸 것.
#   2. `npm run test:unit` 처럼 `:` 를 포함한 스크립트명도 인자 char-class 밖이라 SKIP.
#   3. 성격: 보안 경계가 아니라 anti-footgun 이다. 화이트리스트를 통과하면서 아무것도 검증하지 않는
#      exit-0 스푸핑(`pytest --collect-only` 류)은 차단하지 못한다 (spec §2 · F-3 클래스).
#   4. npx·(pnpm|yarn) exec 는 **임의 bin** 을 허용한다 — `npx cowsay` 류 비테스트 명령도 exit 0 이면
#      통과한다(exit-0 스푸핑 = 위 #3 `pytest --collect-only` 동류의 수용 한계, 위협모델=환각이지 침입 아님).
#      러너명 고정리스트(vitest·jest·ava·uvu·bun test…)로 제한하지 않는 이유: 러너명이 예측 불가라
#      고정하면 정직한 외부 테스트가 false-block 되는 재발(본 FID 의 존재 이유)을 부른다. bin 선두 char 를
#      [A-Za-z0-9_@] 로 조인 것(FIX-A)은 절대경로·옵션주입(파괴형)만 축소할 뿐 임의 bin 자체는 여전히 허용.
# bash 접두: (scripts|tests|test)/ — downstream 표준 테스트 배치 인정 (20260716 trivial dogfood
#   발견 #3: scripts/ 하드코딩 편향으로 외부 `bash tests/test-x.sh` 가 PARTIAL → 실행-근거 게이트
#   불인정 → 정직한 외부 완주가 커밋 deny. anti-footgun 성격(L50)이라 상대경로 테스트 디렉토리
#   확장은 안전 — 절대경로·lib/ 등은 여전히 차단 (T2.h 잠금).
# subdir/러너형: 선택적 `cd <상대subdir> && ` 접두 + `npx <bin>`·`pnpm|yarn exec <bin>` 러너형 인정
#   (false-block 9호 — monorepo `cd apps/web && npx vitest run`). subdir 첫 문자 '/' 불허(절대경로 차단)
#   + `*..*` 가드로 트래버설 차단. bare `pnpm|yarn <bin>`(예 `pnpm vitest`)는 미지원 (clarify Q1=(2)).
# 워크스페이스 플래그/의존성관리자 접두 (false-block 10호 — 하류 실제 test_command 22종이 차단됐다):
#   `(poetry|uv|pdm|rye) run ` 접두 + `(npm|pnpm|yarn) (--dir|--filter|-C|workspace) <값> … test[:name]`.
#   플래그 값 선두 클래스는 [A-Za-z0-9_.@] — '-'·'/' 를 배제해 옵션주입·절대경로를 막고 `..` 는 별도 가드.
#   `-w` 는 의도적 제외: npm 은 값을 받고 pnpm 은 boolean 이라 의미가 충돌한다(plan-review I-2).
#     지원한다고 광고하면 pnpm 사용자가 false-block 을 학습하므로 WARN 힌트에도 넣지 않는다.
#   알려진 한계(false-block 11호 후보): `test(:[…])?` 는 콜론 1회라 `npm run test:unit:watch` 는 여전히
#     BLOCK 이다. `--filter=web` 같은 '=' 결합형도 미지원(값이 별도 토큰이어야 한다).
#   매니저×플래그 교차곱은 제한하지 않는다 — whitelist 는 권한 경계지 문법 검사기가 아니다(clarify Q1).
_WHITELIST_PAT='^(cd[[:blank:]]+[A-Za-z0-9_.][A-Za-z0-9_/.-]*[[:blank:]]+&&[[:blank:]]+)?((poetry|uv|pdm|rye)[[:blank:]]+run[[:blank:]]+)?(bash[[:blank:]]+(scripts|tests?)/[A-Za-z0-9_/.-]+\.sh([[:blank:]][A-Za-z0-9_/.=-]*)*|(python[[:blank:]]+-m[[:blank:]]+)?pytest([[:blank:]][A-Za-z0-9_/.=-]*)*|(npm|pnpm|yarn)[[:blank:]]+((--dir|--filter|-C|workspace)[[:blank:]]+[A-Za-z0-9_.@][A-Za-z0-9_@/.-]*[[:blank:]]+)*(run[[:blank:]]+)?test(:[A-Za-z0-9._-]+)?([[:blank:]][A-Za-z0-9_/.=-]*)*|go[[:blank:]]+test([[:blank:]][A-Za-z0-9_/.=-]*)*|cargo[[:blank:]]+test([[:blank:]][A-Za-z0-9_/.=-]*)*|npx[[:blank:]]+[A-Za-z0-9_@][A-Za-z0-9_@/.-]*([[:blank:]][A-Za-z0-9_@/.=-]*)*|(pnpm|yarn)[[:blank:]]+exec[[:blank:]]+[A-Za-z0-9_@][A-Za-z0-9_@/.-]*([[:blank:]][A-Za-z0-9_@/.=-]*)*)$'

while IFS= read -r cmd; do
  [ -z "$cmd" ] && continue
  if [[ ! "$cmd" =~ $_WHITELIST_PAT ]] || [[ "$cmd" == *..* ]]; then
    echo "WARN: SKIP '$cmd' — whitelist 미통과. 허용: bash (scripts|tests)/*.sh · pytest · npm/pnpm/yarn (run) test[:name] · go test · cargo test · npx <bin> · pnpm|yarn exec <bin>. 선택적 접두: 'cd <상대subdir> && ' · '(poetry|uv|pdm|rye) run '. 워크스페이스 플래그: '--dir|--filter|-C|workspace <값>' (값은 상대경로·패키지명만 — 선두 '-'·'/' 불가). 미지원: bare 'pnpm|yarn <러너>'(예 pnpm vitest)는 → 'pnpm exec <러너>' 를 쓸 것 · 다중 콜론 'test:a:b' · '=' 결합형 '--filter=web' · pnpm '-w'(boolean 이라 값 없음). '..' 포함 경로·절대경로는 차단(예 'go test ./...' 미지원 — 개별 패키지 경로를 쓸 것)" >&2
    {
      echo "### \`$cmd\`"
      echo '> WARN: SKIP — whitelist 미통과'
      echo ""
    } >> "$EVIDENCE"
    skipped=$((skipped + 1))
    continue
  fi
  {
    echo "### \`$cmd\`"
    echo '```'
  } >> "$EVIDENCE"
  executed=$((executed + 1))
  read -r -a _parts <<< "$cmd"
  # cd <subdir> && <rest> → 서브셸 직접-exec (no-shell 유지 · 부모 cwd 비오염 · false-block 9호)
  #   서브셸 `$(…)` 의 exit 가 곧 마지막 명령(runner) 종료코드. subdir 부재면 cd 실패 → 비0 → FAIL 정직포착.
  # bash 러너는 기존대로 bash 로 실행(scripts/*.sh 한정). 그 외 러너는 첫 토큰을 그대로 실행(PATH 조회).
  if [[ "$cmd" =~ ^cd[[:blank:]]+([^[:blank:]]+)[[:blank:]]+\&\&[[:blank:]]+(.*)$ ]]; then
    _sub_dir="${BASH_REMATCH[1]}"; read -r -a _sub_parts <<< "${BASH_REMATCH[2]}"
    # 그룹 `{ … }` 전체 stderr 캡처 — `2>&1` 를 러너에만 결속하면 cd 실패 진단이
    #   스크립트 stderr 로 유출되어 evidence 출력블록이 빈 채 exit 만 기록됨(L12 투명성 위반, Imp1).
    out=$( { _sr_leave && cd "$_sub_dir" && "${_sub_parts[@]}"; } 2>&1 )
  elif [ "${_parts[0]}" = "bash" ]; then
    out=$( { _sr_leave && bash "${_parts[@]:1}"; } 2>&1 )
  else
    out=$( { _sr_leave && "${_parts[@]}"; } 2>&1 )
  fi
  # ⚠️ 위 if/fi 블록과 이 줄 사이에 어떤 명령도 삽입 금지 (주석은 무해).
  #    명령을 넣으면 ec 가 그 명령의 status(0)를 캡처해 **실패한 테스트가 VERIFY: PASS 로 샌다**.
  #    실증된 함정(plan I-4) — test-verifying-automation.sh 의 T-multi.e/f 가 이 회귀를 고정한다.
  ec=$?
  {
    echo "$out"
    echo '```'
    echo "exit: $ec"
    echo ""
  } >> "$EVIDENCE"
  if [ "$ec" -ne 0 ]; then
    all_pass=0
    failed=$((failed + 1))
    echo "VERIFY: FAIL $cmd (exit=$ec)" >&2
    _mat_cmd "$cmd" "$ec" "$out"
  fi
done <<< "$commands"

# 리뷰 감사 추적 대조 — Phase B/C 판정 리포트가 dispatch-log 에 기록됐는지 (F1 teeth).
#   테스트 명령 결과와 별개 축이지만 여기에 배선한 이유: 실행-근거 게이트(R-1/R-2)가
#   "VERIFY: PASS" 만 커밋 면제로 인정하므로, 이 축의 위반도 같은 관문을 통과해야 실효가 있다.
#   누락 전용 검사이며 산출물 부재는 fail-open(SKIP) 이라 무관 repo·초기 FID 에 월권하지 않는다.
_ac_contract_check || { failed=$((failed + 1)); _record_result FAIL; exit 1; }

if [ -f "$AUDIT_SH" ]; then
  audit_out=$(bash "$AUDIT_SH" "$FID" 2>&1)
  audit_ec=$?
  {
    echo "### review-audit"
    echo '```'
    echo "$audit_out"
    echo '```'
    echo ""
  } >> "$EVIDENCE"
  if [ "$audit_ec" -ne 0 ]; then
    all_pass=0
    failed=$((failed + 1))
    _mat_reason review-audit "$audit_out"
    echo "VERIFY: FAIL review-audit (exit=$audit_ec)" >&2
    echo "$audit_out" >&2
  fi
fi

# Phase B/C 수행 존재 관측 (warn-only — 20260806).
#   check-review-audit 는 정합 검사라 리뷰 0회면 검사 대상이 없어 통과한다.
#   "생략 금지" 선언에 대응하는 관측을 여기 둔다. **차단하지 않는다** —
#   즉시 하드화하면 기존 FID 35% 가 소급 FAIL(실측). 빈도 관측 후 전환 판단.
if [ -f "$PRESENCE_SH" ]; then
  presence_out=$(bash "$PRESENCE_SH" "$FID" 2>&1)
  presence_ec=$?
  {
    echo "### review-presence"
    echo '```'
    echo "$presence_out"
    echo '```'
    echo ""
  } >> "$EVIDENCE"
  if [ "$presence_ec" -ne 0 ]; then
    # §lite 만 rc=1 (하드) — 비-lite 는 rc=0 WARN 이라 여기 오지 않는다.
    all_pass=0
    failed=$((failed + 1))
    _mat_reason review-presence "$presence_out"
    echo "VERIFY: FAIL review-presence (§lite Phase B/C 생략)" >&2
    printf '%s\n' "$presence_out" >&2
  else
    printf '%s' "$presence_out" | grep -q 'WARN' && printf '%s\n' "$presence_out" >&2
  fi
fi

# hybrid 라벨 금지 — §유형=foundation ∧ §batch (emit-context 이중망).
if [ -f "$LABEL_SH" ]; then
  label_out=$(bash "$LABEL_SH" "$FID" 2>&1)
  label_ec=$?
  {
    echo "### spec-label-compat"
    echo '```'
    echo "$label_out"
    echo '```'
    echo ""
  } >> "$EVIDENCE"
  if [ "$label_ec" -ne 0 ]; then
    all_pass=0
    failed=$((failed + 1))
    _mat_reason spec-label "$label_out"
    echo "VERIFY: FAIL spec-label hybrid (exit=$label_ec)" >&2
    echo "$label_out" >&2
  fi
fi

# foundation manifest 산출 게이트 — §유형=foundation 인 FID 만 대상(그 외 SKIP).
#   review-audit 과 같은 이유로 여기 배선한다: 실행-근거 게이트(R-1/R-2)가 "VERIFY: PASS" 만
#   커밋·PR 면제로 인정하므로, 이 축의 위반도 같은 관문을 통과해야 실효가 있다.
#   종전엔 verifying-evidence-ko 산문뿐이라 모델이 건너뛰면 무발동이었다(20260806 실측).
if [ -f "$FND_SH" ]; then
  fnd_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bash "$FND_SH" "$FID"; } 2>&1 )
  fnd_ec=$?
  {
    echo "### foundation-manifest"
    echo '```'
    echo "$fnd_out"
    echo '```'
    echo ""
  } >> "$EVIDENCE"
  if [ "$fnd_ec" -ne 0 ]; then
    all_pass=0
    failed=$((failed + 1))
    _mat_reason foundation-manifest "$fnd_out"
    echo "VERIFY: FAIL foundation-manifest 미산출 (exit=$fnd_ec)" >&2
    echo "$fnd_out" >&2
  else
    # 통과해도 경고·안내(없는 경로 · 사라진 모듈 · 빈 공통 FR 칸)는 보이게 한다 — evidence.md 에만 남으면 지나친다.
    printf '%s\n' "$fnd_out" | grep -E '^FOUNDATION-MANIFEST: (WARN|NOTE)|^  ' >&2 || true
  fi
fi

# 헌법 구조 규칙의 판정 명령 (20261015-verify-rule-commands · 위반 차단 20261017-rule-commands-block).
#   위반(FAIL)만 판정에 넣는다 — 판정 불가·TIMEOUT·SKIP·검사기 판정 불가(rc 2)·요약 해석 실패는 경고로만 둔다(환경 문제로 정상 작업을 멈추지 않는다).
#   실행 범위는 위 테스트 명령과 같은 허용 형식뿐이다(검사 스크립트가 이 파일의 _WHITELIST_PAT 줄을 읽는다).
#   테스트 명령 0건(NOT_RUN)처럼 위에서 먼저 끝나는 경로에서는 이 블록에 닿지 않는다 — 판정과 무관한 관측이라 의도한 범위다.
RULECMD_SH="$PLUGIN/scripts/_internal/check-rule-commands.sh"
rulecmd_ec=0
rulecmd_fail=0
if [ -f "$RULECMD_SH" ]; then
  rulecmd_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bash "$RULECMD_SH"; } 2>&1 ); rulecmd_ec=$?
else
  rulecmd_out="검사 스크립트 없음 — check-rule-commands.sh"
fi
{
  echo "### structure-rule-commands"
  echo '```'
  echo "$rulecmd_out"
  echo '```'
  echo ""
} >> "$EVIDENCE"
if [ "$rulecmd_ec" -eq 1 ]; then
  # 요약 줄의 위반 수 — 못 읽으면 위반으로 몰지 않는다(빈 값 → 경고만)
  rulecmd_fail=$(printf '%s\n' "$rulecmd_out" | sed -n 's/^RULE-COMMANDS: PASS [0-9][0-9]* · FAIL \([0-9][0-9]*\) · .*/\1/p' | head -1)
  case "$rulecmd_fail" in ''|*[!0-9]*) rulecmd_fail=0 ;; esac
  if [ "$rulecmd_fail" -gt 0 ]; then
    all_pass=0
    failed=$((failed + 1))
    _mat_reason structure-rule-commands "$rulecmd_out"
    echo "VERIFY: FAIL structure-rule-commands (위반 ${rulecmd_fail}건 — 헌법 구조 규칙 · evidence.md ### structure-rule-commands)" >&2
  else
    echo "WARN: 구조 규칙 판정 명령 — 판정 불가·시간 초과·실행 안 함이 있다 (위반 0건 — 차단 아님 · evidence.md ### structure-rule-commands)" >&2
  fi
  # 규칙마다 결과 줄과 명령 출력 앞 3줄만 — 전체는 evidence.md 에 있다
  printf '%s\n' "$rulecmd_out" | awk '/^RULE-COMMANDS:/ { print; next } /^RULE / { show = ($0 !~ /: PASS$/); n = 0; if (show) print; next } /^  / { if (show && n < 3) print; n++ }' >&2
elif [ "$rulecmd_ec" -ne 0 ]; then
  printf '%s\n' "$rulecmd_out" | grep '^RULE-COMMANDS:' >&2
fi

# import 방향·순환 (20261021-import-direction) — 경고 전용: 판정·종료 코드에 넣지 않는다. 30초에서 끊는다(판정 줄이 없으면 — 시간 초과·크래시 — 판정 불가 줄을 앞에 붙인다).
#   plan 의 허용 의존(화살표 형식)을 이 FID 가 바꾼 파일의 import 와 대조한다 — 코드는 원래 폴더(worktree)에서, plan 은 메인 .specops 에서 읽는다.
IMPDIR_SH="$PLUGIN/scripts/_internal/check-import-direction.sh"
if [ -f "$IMPDIR_SH" ]; then
  if command -v bounded_run >/dev/null 2>&1; then
    impdir_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bounded_run 30 bash "$IMPDIR_SH" "$FID"; } 2>&1 ); impdir_ec=$?
  else
    impdir_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bash "$IMPDIR_SH" "$FID"; } 2>&1 ); impdir_ec=$?
  fi
  # 판정 줄로 시작하지 않으면(시간 초과의 Terminated · 크래시 원문 · 빈 출력) 판정 불가 줄을 앞에 붙인다 — 원문은 그 아래에 남긴다
  case "$impdir_out" in
    "IMPORT-DIRECTION: "*) ;;
    *) if [ "$impdir_ec" -eq 124 ]; then _impdir_why="30초 시간 초과"; else _impdir_why="판정 줄 없음 · rc=$impdir_ec"; fi
       impdir_out="IMPORT-DIRECTION: 판정 불가 (${_impdir_why})${impdir_out:+
$impdir_out}" ;;
  esac
  {
    echo "### import-direction"
    echo '```'
    echo "$impdir_out"
    echo '```'
    echo ""
  } >> "$EVIDENCE"
  case "$impdir_out" in
    "IMPORT-DIRECTION: WARN"*)
      echo "WARN: import 방향·순환 — 경고만(차단 아님) · evidence.md ### import-direction" >&2
      printf '%s\n' "$impdir_out" | head -6 >&2 ;;
  esac
fi

# API 계약 빈칸·형식 (20261021-api-contract-check) — 경고 전용: 판정·종료 코드에 넣지 않는다. 30초에서 끊는다(판정 줄이 없으면 판정 불가 줄을 앞에 붙인다).
#   .specops/memory/api-spec.md 의 칸(Status 열·오류 형식·오류 코드·목록·멱등·rate limit·버전 전략)을 본다 — api-spec 이 없으면 SKIP.
APIC_SH="$PLUGIN/scripts/_internal/check-api-contract.sh"
if [ -f "$APIC_SH" ]; then
  if command -v bounded_run >/dev/null 2>&1; then
    apic_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bounded_run 30 bash "$APIC_SH" "$FID"; } 2>&1 ); apic_ec=$?
  else
    apic_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bash "$APIC_SH" "$FID"; } 2>&1 ); apic_ec=$?
  fi
  case "$apic_out" in
    "API-CONTRACT: "*) ;;
    *) if [ "$apic_ec" -eq 124 ]; then _apic_why="30초 시간 초과"; else _apic_why="판정 줄 없음 · rc=$apic_ec"; fi
       apic_out="API-CONTRACT: 판정 불가 (${_apic_why})${apic_out:+
$apic_out}" ;;
  esac
  {
    echo "### api-contract"
    echo '```'
    echo "$apic_out"
    echo '```'
    echo ""
  } >> "$EVIDENCE"
  case "$apic_out" in
    "API-CONTRACT: WARN"*)
      echo "WARN: API 계약 빈칸·형식 — 경고만(차단 아님) · evidence.md ### api-contract" >&2
      printf '%s\n' "$apic_out" | head -6 >&2 ;;
  esac
fi


# 보안 설계 칸·결함 (20261021-security-design-checker) — 경고 전용: 판정·종료 코드에 넣지 않는다. 30초에서 끊는다(판정 줄이 없으면 판정 불가 줄을 앞에 붙인다).
#   .specops/memory/api-spec.md·data-model.md 의 보안 칸, 이 FID 가 바꾼 엔드포인트 행, plan·tasks 경로의 위험 기능 신호를 본다 — 두 문서가 없으면 SKIP.
SECD_SH="$PLUGIN/scripts/_internal/check-security-design.sh"
if [ -f "$SECD_SH" ]; then
  if command -v bounded_run >/dev/null 2>&1; then
    secd_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bounded_run 30 bash "$SECD_SH" "$FID"; } 2>&1 ); secd_ec=$?
  else
    secd_out=$( { [ -z "${_SR_CWD:-}" ] || export SPECOPS_ROOT="$PWD/.specops"; _sr_leave && bash "$SECD_SH" "$FID"; } 2>&1 ); secd_ec=$?
  fi
  case "$secd_out" in
    "SECURITY-DESIGN: "*) ;;
    *) if [ "$secd_ec" -eq 124 ]; then _secd_why="30초 시간 초과"; else _secd_why="판정 줄 없음 · rc=$secd_ec"; fi
       secd_out="SECURITY-DESIGN: 판정 불가 (${_secd_why})${secd_out:+
$secd_out}" ;;
  esac
  {
    echo "### security-design"
    echo '```'
    echo "$secd_out"
    echo '```'
    echo ""
  } >> "$EVIDENCE"
  case "$secd_out" in
    "SECURITY-DESIGN: WARN"*)
      echo "WARN: 보안 설계 칸·결함 — 경고만(차단 아님) · evidence.md ### security-design" >&2
      printf '%s\n' "$secd_out" | head -6 >&2 ;;
  esac
fi

if [ "$skipped" -gt 0 ]; then
  _record_result PARTIAL
  echo "VERIFY: PARTIAL — ${skipped}개 명령 whitelist 미통과, 수동 검증 필요 (executed=${executed} skipped=${skipped})"
  exit 1
fi
if [ "$executed" -eq 0 ]; then
  _record_result NOT_RUN
  echo "VERIFY: NOT_RUN — 실행된 명령 0건" >&2
  exit 1
fi
if [ "$all_pass" = "1" ]; then
  _record_result PASS
  echo "VERIFY: PASS"
  # 재사용·복제 관측 (FID 20261013-reuse-dup-metrics) — 판정을 **낸 뒤** 1회. 관측 전용·fail-open:
  #   스크립트 부재·측정 실패·기록 실패·시간초과(30초에서 끊는다 — 기록 없음)는 위 판정 줄과 아래 종료 코드에 영향을 주지 않는다(출력도 버린다).
  if [ -f "$PLUGIN/scripts/reuse-metrics.sh" ]; then
    if command -v bounded_run >/dev/null 2>&1; then
      bounded_run 30 bash "$PLUGIN/scripts/reuse-metrics.sh" measure "$FID" >/dev/null 2>&1 || true
    else
      bash "$PLUGIN/scripts/reuse-metrics.sh" measure "$FID" >/dev/null 2>&1 || true
    fi
  fi
  exit 0
fi
_record_result FAIL
exit 1
