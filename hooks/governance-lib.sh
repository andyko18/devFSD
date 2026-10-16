#!/usr/bin/env bash
# specops-ko governance-capture 공용 함수 라이브러리
# source 로 로드하여 사용. 실행 파일 아님.
#
# Sourced library — strict mode 는 caller 에 위임 (set -u/-e 생략).
# Requires: jq 1.6+, bash 3.2+, coreutils (date, grep, sed, cut, mkdir).
_GOV_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_VERIFICATION_STATE_SH="$_GOV_LIB_DIR/../scripts/_internal/verification-state.sh"
_RECORD_METRIC_SH="$_GOV_LIB_DIR/../scripts/_internal/record-metric.sh"
_CHECK_TASK_RECEIPT_SH="$_GOV_LIB_DIR/../scripts/_internal/check-task-receipt.sh"
_QUICK_SCOPE_SH="$_GOV_LIB_DIR/../scripts/_internal/quick-scope.sh"
# 파일 분류 단일 SoT (20260912-verify-stale-docs-scope) — 면제 판정과 무효화 판정이 같은 기준을 쓴다.
#   부재 시 fail-safe: 전건 비문서(코드) 취급 = 면제 축소·지문 확대. 무음으로 두지 않고 stderr 로 알린다
#   (v1.88.0 이 고친 "강제층이 조용히 사라지는 경로" 계열).
_FILE_CLASS_SH="$_GOV_LIB_DIR/../scripts/_internal/file-class.sh"
if [ -f "$_FILE_CLASS_SH" ]; then
  # shellcheck source=/dev/null
  . "$_FILE_CLASS_SH"
else
  echo "governance-lib: file-class.sh 로드 실패 — 전건 비문서(코드)로 판정한다" >&2
  fc::is_doc() { return 1; }
  fc::is_plugin_repo() { return 1; }
  FC_DOC_RE='$^'; FC_RUNTIME_RE='$^'
fi

# 논리 경로 기준 저장소 루트 (심링크 **미해석**) — transcript 의 file_path 는 셸의 논리 cwd 로
#   만들어지는데 `git rev-parse --show-toplevel` 은 물리 경로를 준다(macOS: /var → /private/var).
#   물리만 쓰면 저장소 **안** 편집이 "밖" 으로 오판돼 코드 편집을 세지 않는 fail-open 이 된다.
# ★ prefix 끝 슬래시를 먼저 떼야 한다 — `${PWD%/scripts/}` 는 매치하지 않아 PWD 가 그대로 남고,
#   서브디렉터리에서 훅이 돌 때 루트가 아니라 cwd 가 root 로 잡힌다(실측).
_fc_root_log() {
  local p
  p=$(git rev-parse --show-prefix 2>/dev/null) || return 0
  printf '%s' "${PWD%/${p%/}}"
}

# jq 용 파일 분류 정의 — 세 판정 경로(_verify_exec_evidence · _verify_stale_cause · _bg_pending_path)가
#   이 **한 문자열을 연접**해 쓴다. jq 는 bash 함수를 못 부르므로 정의를 각 프로그램에 복제했었는데,
#   20260912 Phase C 에서 처음 발견된 결함(C-1)이 곧바로 **3중 동기 수정**을 요구한 것이 복제 비용의 실증이다.
# ★ "경로 미상" 과 "저장소 밖" 은 **반대 답**이 필요하다 — 종전엔 둘 다 `$rel == ""` 하나로 합쳐져
#   후자의 답(세지 않음)을 앞에도 줬다:
#   - 경로 미상(file_path 부재·빈 문자열·notebook_path 만 있는 NotebookEdit) → **코드로 센다**(fail-safe).
#     실측(Phase C C-1): BASE 는 rc=1(코드)였는데 HEAD 가 rc=0 이 되어 **R-1 면제가 조용히 넓어졌다**.
#     verify 실행 → 노트북 수정 → 커밋이 차단 없이 통과하는 경로였다.
#   - 저장소 밖 절대경로 → 세지 않는다(AC-4). 이 답은 그대로 유지해야 한다.
_FC_JQ_DEF='
    def fc_is_code(p):
      (p // "") as $raw
      | if $raw == "" then true          # 경로 미상 → 코드로 센다(fail-safe)
        else
          ($raw | sub("^\\./"; "")) as $p0
          | (if ($p0 | startswith("/")) then
               (if ($root_phys != "" and ($p0 | startswith($root_phys + "/")))
                then ($p0 | ltrimstr($root_phys + "/"))
                elif ($root_log != "" and ($p0 | startswith($root_log + "/")))
                then ($p0 | ltrimstr($root_log + "/"))
                elif ($root_phys == "" and $root_log == "")
                then $p0                 # root 판정 불가 → 코드로 센다(fail-safe)
                else "" end)             # 저장소 밖 → 세지 않는다(AC-4)
             else $p0 end) as $rel
          | if $rel == "" then false
            elif ($plugin_repo and ($rel | test($runtime_re))) then true
            elif ($rel | test($doc_re)) then false
            else true end
        end;
'

: "${_SPECOPS_SCOPE_FILES:=}"; _VS_VERDICT_CACHE=""; _VS_VERDICT_CACHE_FID=""   # 커밋 범위(계측) + verdict 캐시 **무조건** 초기화 — env 선주입 무음 우회 차단

# 커밋 메시지에서 태스크 ID 추론 — `T12` 또는 `Task: T12`. 없으면 빈 문자열.
_infer_commit_task() {
  local cmd="${1:-}" hit
  # ① 명시 선언 `Task: T#` 우선 — 산문보다 앞선다.
  #    구 구현은 `Task:...|T[0-9]+` 교대(alternation)를 한 번에 스캔해 **문서 순서상 먼저 나온
  #    쪽**을 집었다. 그래서 제목이 "출력층 (T1~T4 집약)" 이고 본문에 `Task: T4` 인 커밋이
  #    T1 으로 오인돼, 훅이 안내한 receipt 탈출구가 열리지 않았다
  #    (20260807 실사용 검증 — FID 20260807-specops-doctor 에서 실측).
  hit=$(printf '%s' "$cmd" | grep -oE 'Task:[[:space:]]*T[0-9]+' | head -1 | grep -oE 'T[0-9]+' | head -1)
  # ② 명시 선언이 없을 때만 산문 T# fallback (기존 동작 보존)
  [ -n "$hit" ] || hit=$(printf '%s' "$cmd" | grep -oE 'T[0-9]+' | head -1)
  printf '%s' "${hit:-}"
}

# 인라인 BYPASS 의 **사유 값**을 위치 무관하게 추출한다.
#   20260807 실사용 검증 4호: 3호 수정이 `${tool_cmd:0:200}` **앞부분 절단**이라,
#   앞에 `cd`·`echo` 같은 전처리가 붙으면 200자가 거기서 소진돼 **사유가 통째로 잘렸다**.
#   "사유는 명령 앞쪽에 온다"는 3호의 근거가 틀렸다 — compound·전처리가 붙으면 뒤로 밀린다.
#   따라서 자르지 말고 **추출**한다. 3형식(작은따옴표·큰따옴표·무따옴표) 전부 인정 —
#   형식 함정으로 정직하게 사유를 병기한 우회를 무기록 처리하면 안 된다(:136 false-deny 금지 정신).
#   개행은 공백으로 평탄화 — 사유는 계약상 한 줄이고, sed 가 줄 단위라 평탄화가 필요하다.
_extract_bypass_reason() {
  local c r
  c=$(printf '%s' "${1:-}" | tr '\n' ' ')
  r=$(printf '%s' "$c" | sed -n "s/.*SPECOPS_BYPASS_REASON='\([^']*\)'.*/\1/p" | head -1)
  [ -n "$r" ] || r=$(printf '%s' "$c" | sed -n 's/.*SPECOPS_BYPASS_REASON="\([^"]*\)".*/\1/p' | head -1)
  [ -n "$r" ] || r=$(printf '%s' "$c" | sed -n 's/.*SPECOPS_BYPASS_REASON=\([^[:space:]]*\).*/\1/p' | head -1)
  printf '%s' "$r"
}

# BYPASS 수율 계측 — 사유·명령 원문은 friction-log에 남기고, metrics에는 식별자만 기록한다.
# FID가 없거나 형식이 틀리면 no-op (비-specops·초기 세션에서 게이트를 막지 않음).
_record_bypass_metric() {
  local fid="${1:-}"
  [ -n "$fid" ] || return 0
  grep -qE '^[0-9]{8}-[a-z0-9-]+$' <<< "$fid" || return 0
  [ -f "$_RECORD_METRIC_SH" ] || return 0
  bash "$_RECORD_METRIC_SH" --fid "$fid" --phase governance-bypass --fallback true >/dev/null 2>&1 || true
}

detect_fid() {
  # U8: 다중 FID 환경에서 first-only 버그 회피
  #   1순위: <!-- active-fid: <FID> --> 마커 (사용자/도구가 명시적으로 active 표시)
  #   2순위: 첫 '## <FID>' 헤더 (기존 동작, 단일 FID 환경 fallback)
  local progress_file=".specops/session-progress.md"
  [ -f "$progress_file" ] || { echo ""; return 0; }
  # 1순위: active-fid 마커 (any line)
  local marker_fid
  marker_fid=$(grep -m1 -E '<!--[[:space:]]*active-fid:[[:space:]]*[0-9]{8}-[a-z0-9-]+[[:space:]]*-->' "$progress_file" \
    | sed -E 's/.*active-fid:[[:space:]]*([0-9]{8}-[a-z0-9-]+).*/\1/')
  if [ -n "$marker_fid" ]; then
    echo "$marker_fid"
    return 0
  fi
  # 2순위: 첫 ## 헤더 (single-FID fallback) — 단, **테스트 fixture FID 는 건너뛴다**.
  #
  # 왜 (20260829-fixture-fid-hijack): /e2e-test 는 session-progress 에 fixture 섹션을
  #   prepend 하므로, 한 번 돌리면 fixture 가 repo 의 활성 FID 가 되고 **이후 모든 커밋이
  #   fixture 의 verify 상태를 대신 answer** 하게 된다(R-1 ②앵커). 게다가 fixture 테스트는
  #   `.specops/<FID>/*.sh` 라 run-verification 실행 whitelist 밖이어서 구조적으로 PASS 를
  #   낼 수 없다 — 빠져나갈 정직 경로가 없어 BYPASS 밖에 안 남는다(실측 3회).
  #   테스트 픽스처가 repo 의 "현재 작업" 이 되는 것은 어느 각도로도 옳지 않다.
  #
  # 판별자가 마커 **파일**인 이유: 섹션 산문·헤더 포맷을 파싱하면 e2e 가 표기를 바꿀 때마다
  #   조용히 깨진다(이 repo 의 queue 라벨 드리프트와 동형). 파일 존재는 포맷 무관이고
  #   후보당 test 1회라 hot path 비용이 없다.
  #
  # ★ 1순위 active-fid 마커에는 적용하지 않는다: 사용자가 fixture 를 **명시적으로** 지목했다면
  #   그건 의도다(5원칙 4 주권). 제외는 "아무도 지목 안 했을 때의 추측"인 이 경로에만 건다.
  # ★ 전부 fixture 면 빈 값을 낸다 — 없는 FID 를 지어내지 않는다. 호출부는 이미 빈 fid 를
  #   "진행 기록 앵커 없음" 으로 안내한다(pretool _anchor_hint).
  local cand
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    [ -f ".specops/$cand/.fixture" ] && continue
    printf '%s' "$cand"
    return 0
  done <<EOF
$(grep -E '^## [0-9]{8}-[a-z0-9-]+' "$progress_file" | sed -E 's/^## ([0-9]{8}-[a-z0-9-]+).*/\1/')
EOF
  echo ""
}

# F-1(5c): session-progress 의 FID 섹션에서 /verify PASS 가 최신 코드변경보다 뒤(위)면 0(verify유효), 아니면 1.
# 코드변경 = /implement(항상) | /receive-review + (fix [1-9]|수용). /specify·/plan·/tasks·/clarify·/analyze 제외(.md).
#
# 한계(20260626 분석, WON'T-FIX): session-progress 는 self-reported — verify 후 lifecycle 밖
#   수동 변경(Edit·핫픽스·직접 git add, /implement 줄 미기록)은 감지 못 함(false-allow). self-report
#   에게 un-self-reported 변경 탐지는 범주 오류 = honesty-failure / out-of-band 2차 방어 클래스.
#   1차 방어는 pretool is_docs_only_change(git-authoritative, verify shortcut 前 실행)가 담당.
#   설계안 A(tree해시 자가오염)·B(수동변경 transcript 無로 우회)·C(detect_fid 무력화 회귀) 전수 기각.
_verify_passed_in_progress() {
  local fid="$1"
  local progress=".specops/session-progress.md"
  [ -f "$progress" ] || return 1
  local section
  section=$(awk -v f="## $fid" '
    $0 ~ "^"f"( |$)" {insec=1; next}
    insec && /^## / {exit}
    insec {print}
  ' "$progress")
  [ -n "$section" ] || return 1
  # I-2: 행 선두 앵커(`^- YYYY-MM-DD HH:MM /command`) — memo 자유텍스트 명령 언급 무매칭 → false-block 차단.
  # YYYY-MM-DD HH:MM 전체 비교: 사전순 = 연대순, 날짜경계(23:59→00:00) 자동 처리.
  # sort -r|head-1 로 max 추출: 줄 순서(prepend 불변식)가 아닌 타임스탬프 값 기준 → writer 순서 오류 무관.
  # 동률(same-minute) → 안전측 = return 2(stale/deny). evidence-stamp 구제 없음(T39b 불변식 보존).
  local vts cts
  vts=$(printf '%s\n' "$section" \
    | grep -E '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} /verify PASS' \
    | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' \
    | sed 's/^- //' | sort -r | head -1)
  cts=$(printf '%s\n' "$section" \
    | grep -E '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} (/implement|/receive-review.*(fix [1-9]|수용))' \
    | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' \
    | sed 's/^- //' | sort -r | head -1)
  [ -z "$vts" ] && return 1              # verify 없음
  [ -z "$cts" ] && return 0             # 코드변경 없음 → verify 유효
  [[ "$vts" > "$cts" ]] && return 0 || return 2   # 0=유효 / 2=affirmative-stale(implement최신 or 동률)
}

# evidence.md 의 run-verification PASS stamp (honest-scaffold — 실제 테스트 실행 증거).
# inconclusive(verify 줄 부재) 보조 면제용. affirmative-stale 에는 미적용(apply_lookback 분기).
_verify_evidence_stamp() {
  local fid="$1"
  local ev=".specops/$fid/evidence.md"
  local state=".specops/$fid/verification-state.json"
  if [ -f "$state" ] && [ -f "$_VERIFICATION_STATE_SH" ]; then
    local verdict                                    # FR-7 캐시 — 상세는 _vs_verdict_cached 참조
    _vs_verdict_cached "$fid" >/dev/null || return 1; verdict=${_VS_VERDICT_CACHE:-}
    [ "$verdict" = "PASS" ] && return 0 || return 1
  fi
  [ -f "$ev" ] || return 1
  grep -q '^RUN-VERIFICATION-RESULT: PASS' "$ev" && return 0 || return 1
}

# 실행 증거 판정 — transcript 의 tool_use(모델 작성 명령) ↔ tool_result(하네스 작성 출력)를
# tool_use_id 로 join 해, 검증 러너가 실제로 실행되어 PASS 를 냈는지 확인한다.
#
# 왜 둘 다 필요한가: command-only 검사는 `echo pytest` 로, result-only 검사는 `echo "VERIFY: PASS"` 로
#   뚫린다. 앵커된 러너 호출 + 그 호출의 하네스 출력을 함께 요구해야 위조 불가 바닥이 된다.
# 범위 경계(A-1, WON'T-FIX): `bash run-all.sh; echo "VERIFY: PASS"` 결합 날조는 미차단 —
#   F-3 wrapper-evasion 과 동일 클래스(의도적 날조). 본 게이트는 자기정직 스캐폴드이며
#   대상은 환각(검증했다 착각한 모델이 선의로 PASS 를 쓰는 것)이다.
# 반환: 0=실행증거 있음 / 1=없음 / 2=판정 불가(fail-open — 호출자가 기존 동작 유지)
#
# 판정 불가(2) 조건: transcript 부재 · jq 실패 · malformed JSONL(--slurpfile 전체 실패) ·
#   **tool_use 이벤트 0건**. 마지막 것이 핵심 — 이벤트가 0건이면 "검증을 안 했다"와 "transcript 를
#   제대로 못 읽었다"를 구별할 수 없다. fail-open 원칙상 판정 불가로 둔다 (C-3 설계 정정).
#
# ★ 신선도 게이트 (20260717-exec-evidence-staleness): 증거는 **마지막 실행증거 이후 코드 편집이
#   없을 때만** 유효하다. 종전엔 윈도우·스코프 없이 transcript 전체를 스캔해, 세션 초반 다른 FID 의
#   VERIFY: PASS 1회가 세션 끝까지 만능 면제표였다 (dogfood test1: FR-2 verify 가 FR-3 미검증
#   implement 커밋 8+개를 전부 열어 friction 무흔적 — 서브에이전트 훅도 main transcript 로 평가되므로
#   동일 적용). 코드 편집 = 비-.specops file_path 의 Edit/Write/NotebookEdit tool_use.
#   .specops/ 아티팩트 Write(evidence.md 마무리 등)는 정직한 verify 후 흐름이라 제외.
#   한계(F-1 동류 heuristic): Bash 경유 파일수정(sed -i·리다이렉트)은 미탐 — honest-mistake 의
#   지배 경로는 Edit/Write 이고, 의도적 우회는 F-3 wrapper 클래스로 수용.
# [실행 경로] 앵커와 러너 사이의 `KEY=VALUE ` 접두는 0개 이상 허용한다 (20260902-runner-anchor-env-prefix).
#   ※ 아래 `_extract_declared_cmds` 의 [선언 경로] 는 반대다 — 거기선 env 접두를 인식하지 않는다.
#   왜: `SPECOPS_SUITE_TIMEOUT=600 bash …` 는 이 repo 의 정상 관용구인데(136a763 이 도입),
#   앵커가 못 읽어 정직한 실행이 deny 됐다 — false-deny 는 BYPASS 관성을 만든다.
#   값은 `[^[:space:]]*` 라 리터럴 공백이 든 값(`FOO='a b'`)은 여전히 미인정이다(실측 0건).
#   반대로 값이 셸 메타문자(`;`·`|`·`$(..)`)를 삼키므로 `FOO=a;b <러너>` 도 인정된다 —
#   셸 의미로는 러너가 안 도는 형태지만, 안 돈 러너는 `VERIFY: PASS` 를 못 찍어 무해하다
#   (F-3 결합날조 클래스. Phase C 실측).
# ── 선언 test_command 추출 (FID 20260809-runner-anchor-downstream) ──
# 왜 필요한가: 실행-근거 앵커가 specops 자신의 러너 형태(run-verification·tests/run-all·
#   pytest·npm test·go/cargo test)를 전제해, downstream 이 테스트를 실제로 돌려도 게이트가
#   열리지 않는다. 실측: 외부 4개 프로젝트에서 BYPASS 77건, 실사용 러너 4종 전부 불인정
#   (bash scripts/tests/frontend.sh · npx vitest run · pnpm --filter … test · turbo run test).
# 왜 grep 인가: dag::get_task_test_command 는 python3+pyyaml 을 요구하는데 여기는 PreToolUse
#   훅 경로다(지연이 체감에 직결). test_command 는 중첩 없는 평면 스칼라라 grep 으로 족하다.
#   대가는 파서 두 벌 — propagation edge 로 잠근다.
# 왜 whitelist 인가: 선언값을 그대로 믿으면 임의 명령이 실행증거가 된다. record-task-receipt
#   가 쓰는 패턴을 **그대로** 재사용한다(두 벌 만들면 drift).
# 한계 (전부 **미탐 방향** — 막히면 사용자는 BYPASS 로 돌아갈 뿐이고 그건 현행이다):
#   - 쌍따옴표 값만 벗긴다. `test_command: 'x'` 는 따옴표가 남아 whitelist 를 못 통과한다.
#     templates/tasks.md 가 쌍따옴표를 쓰므로 실사용 영향 미관측.
#   - CRLF 개행 tasks.md 는 추출이 `[]` 가 된다(선언 경로 무음 비활성 — Phase C 프로브 P12).
#   - 매칭은 접두 비교라 `<러너> || true`·`<러너> 2>&1` 처럼 **임의 접미 wrapper** 를 허용한다.
#     F-3(의도 위조) 클래스로 수용 — 러너는 실제로 돌았고 결과 술어가 별도로 검사된다.
#   - `bash -c "<러너>"` 래핑은 인식하지 않는다(줄 첫 토큰이 다르다).
#   - `SPECOPS_X=1 <러너>` 같은 env 접두도 인식하지 않는다.
#   - 멀티라인 cmd 의 앞줄이 `cd <경로>`·`set -eu`·`export X=Y`·빈 줄이 아니면 인식하지
#     않는다. 따옴표 든 경로(`cd "/path with space"`)도 여기 걸린다 — 문자셋에 따옴표를
#     넣으면 `cd "` 한 줄이 "안전" 이 되어 게이트가 열리기 때문이다(T58 이 그 완화를 잠금).
_extract_declared_cmds() {
  local tasks="$1"
  [ -n "$tasks" ] && [ -r "$tasks" ] || { echo '[]'; return 0; }
  local pat='^(cd[[:blank:]]+[A-Za-z0-9_.][A-Za-z0-9_/.-]*[[:blank:]]+&&[[:blank:]]+)?((poetry|uv|pdm|rye)[[:blank:]]+run[[:blank:]]+)?(bash[[:blank:]]+(scripts|tests?)/[A-Za-z0-9_/.-]+\.sh([[:blank:]][A-Za-z0-9_/.=-]*)*|(python[[:blank:]]+-m[[:blank:]]+)?pytest([[:blank:]][A-Za-z0-9_/.=-]*)*|(npm|pnpm|yarn)[[:blank:]]+((--dir|--filter|-C|workspace)[[:blank:]]+[A-Za-z0-9_.@][A-Za-z0-9_@/.-]*[[:blank:]]+)*(run[[:blank:]]+)?test(:[A-Za-z0-9._-]+)?([[:blank:]][A-Za-z0-9_/.=-]*)*|go[[:blank:]]+test([[:blank:]][A-Za-z0-9_/.=-]*)*|cargo[[:blank:]]+test([[:blank:]][A-Za-z0-9_/.=-]*)*|npx[[:blank:]]+[A-Za-z0-9_@][A-Za-z0-9_@/.-]*([[:blank:]][A-Za-z0-9_@/.=-]*)*|(pnpm|yarn)[[:blank:]]+exec[[:blank:]]+[A-Za-z0-9_@][A-Za-z0-9_@/.-]*([[:blank:]][A-Za-z0-9_@/.=-]*)*)$'
  local cmd out=""
  # ★ sed 는 **파이프 1회**만 돈다 — 종전 per-line fork 는 태스크 수에 선형이었다
  #   (실측: 30태스크 97ms · 100태스크 268ms). PreToolUse hot path 라 fork 를 O(1) 로 낮춘다.
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    case "$cmd" in *..*) continue ;; esac
    [[ "$cmd" =~ $pat ]] || continue
    out="${out}${cmd}"$'\n'
  done <<EOF_TC
$(grep -E '^[[:blank:]]*test_command:' "$tasks" 2>/dev/null \
    | sed -E 's/^[[:blank:]]*test_command:[[:blank:]]*"?//; s/"[[:blank:]]*$//')
EOF_TC
  printf '%s' "$out" | jq -Rs 'split("\n") | map(select(length > 0)) | unique' 2>/dev/null || echo '[]'
}

# ── 러너 앵커 패턴 (단일 SoT — 20260907-false-deny-anchor-scope) ──────────────
# 왜 변수인가: 이 패턴은 _verify_exec_evidence(2곳 — $lasthit·$bghit) · _verify_stale_cause ·
#   _bg_pending_path **네 곳**에서 쓰인다. (줄번호로 적지 않는다 — 이 상수 블록을 넣는 것만으로
#   그 번호가 낡는다. 낡은 사본 참조가 바로 이 FID 가 고치는 결함이다.)
#   리터럴 4사본 시절 T25·T38 은 "넷이 서로 같음" 만 잠갔고 **넷이 함께 낡는 것**은 못 막았다 —
#   #22 가 앵커에 env 접두를, #26 이 whitelist 에 poetry/워크스페이스를 각각 넣고 서로 맞추지
#   않아 실제로 어긋났다. 변수화로 사본을 없애고, 계열 간 동치는 test-exec-evidence.sh T70 이 잠근다.
# 왜 --arg 인가: jq 프로그램 리터럴에 넣으면 jq 문자열 이스케이프가 한 겹 더 걸려
#   (`\\n`·`\\S`) 셸 변수와 형태가 달라진다. --arg 는 raw 전달이라 백슬래시 1개가 맞다.
#   ★ 이 한 겹 차이가 `test-run-all-verify-token.sh` T3 의 grep 패턴에도 걸린다 — 함께 갱신했다.
# 커버리지 계약: _extract_declared_cmds 의 whitelist(위 `local pat=`) 의 **비-bash 러너군**과
#   동치다 — "whitelist 허용 ∧ 앵커 불인정" 이 0건이어야 하고 T70 이 강제한다.
#   두 가지는 **동치가 아니며 의도적이다**:
#     · 역방향(앵커 인정 ∧ whitelist 차단)은 **FAIL 로 세지 않는다** — 넓어지는 쪽이라
#       "실행은 되는데 커밋이 막힌다" 를 만들지 않기 때문이다.
#       ★ 정정 2회(20260907): 이 자리에 **거짓 진술이 두 번 들어갔다**. 실측을 박아 둔다.
#         1차 오류 — `bash …/tests/run-all.sh` 를 역방향 사례로 적었다. whitelist 의
#           `bash (scripts|tests?)/….sh` 절이 그 명령을 허용하므로 실제는 `허용 ∧ 인정` 이다.
#         2차 오류 — 그것을 고치며 "역방향 사례는 하나도 없다" 고 적었다. 이것도 거짓이다.
#       **실측 역방향(Phase B 재현)**: `CI=true pytest -q` · `FOO=1 npx vitest run`
#         → `whitelist 차단 ∧ 앵커 인정`. whitelist 는 env 접두를 모르고(#26 은 poetry·
#         워크스페이스만 넓혔다), 앵커는 #22 로 env 접두를 인정한다. 두 계열이 **양방향으로**
#         어긋나 있으며, T70 이 한쪽만 검사하는 것은 그 방향만 사용자를 막기 때문이다.
#       교훈: 이 주석을 고치는 동안 같은 병을 두 번 저질렀다 — 커버리지 진술은 반드시
#         whitelist(`_extract_declared_cmds` 의 `local pat`) 와 `_RUNNER_ANCHOR_PAT` 양쪽에 넣어 보고 쓴다.
#     · bash 스크립트 일반(`bash tests/unit.sh` 류): whitelist 는 허용하나 앵커는 불인정.
#       T15 가 "tests/ 밖 run-all.sh 불인정"을 잠그고 있어 파일명 일반화는 위장 표면을 연다.
#       **미해결 결함으로 인지하고 별도 FID 로 미룬다** — T70 fixture 가 `#!skip` 으로 명시 제외한다.
# 한계: `npx <bin>`·`(pnpm|yarn) exec <bin>` 은 임의 바이너리를 받는다(`npx cowsay VERIFY` 도 인정).
#   whitelist 와 동치라는 요구의 귀결이며, 되돌리려면 whitelist 도 함께 좁혀야 한다.
_RUNNER_ANCHOR_PAT='(^|[;&|(\n])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((poetry|uv|pdm|rye)[[:space:]]+run[[:space:]]+)?(bash[[:space:]]+\S*(run-verification\.sh|tests/run-all\.sh)|(python[[:space:]]+-m[[:space:]]+)?pytest|(npm|pnpm|yarn)[[:space:]]+((--dir|--filter|-C|workspace)[[:space:]]+[A-Za-z0-9_.@][A-Za-z0-9_@/.-]*[[:space:]]+)*(run[[:space:]]+)?test(:[A-Za-z0-9._-]+)?|go[[:space:]]+test|cargo[[:space:]]+test|npx[[:space:]]+[A-Za-z0-9_@][A-Za-z0-9_@/.-]*|(pnpm|yarn)[[:space:]]+exec[[:space:]]+[A-Za-z0-9_@][A-Za-z0-9_@/.-]*)'

_verify_exec_evidence() {
  local transcript="$1" fiddir="${2:-}"
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 2
  # ★ 창 한정: tasks.md ∧ evidence.md 가 둘 다 있을 때만 선언 경로를 연다(post-verify 창).
  #   evidence.md 부재(implement 창)는 task receipt 소관이라 건드리지 않는다(Wave A).
  #   2번째 인자는 **선택적** — 기존 1-인자 호출자는 decl='[]' 라 판정이 완전히 불변이다.
  local decl='[]'
  if [ -n "$fiddir" ] && [ -f "$fiddir/tasks.md" ] && [ -f "$fiddir/evidence.md" ]; then
    decl=$(_extract_declared_cmds "$fiddir/tasks.md")
  fi
  local out uses hits
  out=$(jq -rn --slurpfile a "$transcript" --argjson decl "$decl" --arg anchor "$_RUNNER_ANCHOR_PAT" \
    --arg fid "${fiddir##*/}" \
    --arg doc_re "$FC_DOC_RE" --arg runtime_re "$FC_RUNTIME_RE" \
    --arg root_phys "$(git rev-parse --show-toplevel 2>/dev/null)" \
    --arg root_log "$(_fc_root_log)" \
    --argjson plugin_repo "$(fc::is_plugin_repo && echo true || echo false)" "$_FC_JQ_DEF"'
    # 이 러너 실행이 **이 FID** 의 것인가 (20261009). run-verification.sh 뒤에 FID 가 글자로 적혀 있는데 그 안에 이 FID 가
    #   없으면 다른 FID 를 검증한 것이다. 한 세션에서 FID 여럿을 다루면(batch) 앞 FID 의 PASS 가 뒤 FID 의 커밋을 열었다.
    #   FID 가 글자로 적히지 않은 명령(변수 `"$FID"` · run-all.sh)은 판단하지 않는다(거짓 차단 금지). 1-인자 호출($fid 빈 값)은 종전대로다.
    def fid_ok(c): ($fid == "")
      or ([ c | scan("run-verification\\.sh[\"\u0027]?[ \t]+[\"\u0027]?([0-9]{8}-[a-z0-9-]+)") | .[0] ] as $f
          | ($f | length) == 0 or ($f | index($fid)) != null);
    # 이 편집이 "코드 편집" 인가 — 판정·진단·안내 세 경로가 위 _FC_JQ_DEF 한 문자열을 공유한다(20260912).
    #   root 를 물리·논리 **양형**으로 받는다: macOS 는 /var → /private/var 심링크라
    #   show-toplevel(물리)과 셸 논리 경로가 갈리고, 물리만 쓰면 저장소 **안** 편집이
    #   "밖" 으로 오판돼 코드 편집을 세지 않는 fail-open 이 된다(실측).
    # ★ C-A: $all 은 **전체 tool_use** 를 센다 (name 무관). $uses(Bash 한정)로 세면
    #   Bash 가 없는 transcript(Edit-only·Skill-only = 위조 표현)가 0건이 되어 rc=2 fail-open 으로
    #   빠지고, 게이트가 지배 경로에서 no-op 이 된다. 이벤트 유무 판정과 러너 매칭은 다른 질문이다.
    ($a | map(select(.type=="assistant")
              | .message.content[]?
              | select(.type=="tool_use"))) as $tus
    | ($tus | length) as $all
    | ($a | map(select(.type=="user")
                | .message.content[]?
                | select(.type=="tool_result" and (.is_error != true))   # 에러 결과는 증거 불인정
                | {id: .tool_use_id,
                   out: (.content | if type=="string" then . else tostring end)})) as $res
    # 마지막 유효 실행증거의 전역 tool_use 인덱스 (없으면 -1)
    # 선행자 클래스의 \\n: Bash tool command 는 흔히 멀티라인이다(`cd <path>` 다음 줄에 러너).
    #   줄바꿈이 없으면 2번째 줄의 러너가 ^ 에도 [;&|(] 에도 안 걸려 **정직한 실행을 미인식→deny**
    #   하는 false-block 이 난다(실전 dogfooding 적발). 줄바꿈은 셸의 진짜 명령 구분자이므로
    #   `;`·`&`·`|` 와 동급으로 클래스에 든다 — 앵커 의미(줄 첫 토큰이 러너여야 함)는 그대로:
    #   `echo "ran pytest"`·`# bash run-verification.sh`(주석)는 여전히 불인정 (T12·T13 잠금).
    #   run-all.sh 인식 (20260716 false-block): self-maintenance 의 정식 러너는 전체 스위트
    #   run-all.sh 다 — 성공 시 스스로 `VERIFY: PASS` 토큰을 출력해 기존 토큰 계약으로 판정된다.
    #   앵커는 `tests/run-all\.sh` 로 좁힌다(downstream 의 무관한 ./run-all.sh 불인정 — T15 잠금).
    #   env 접두(`KEY=VAL `)는 0개 이상 허용 — 위조는 막힌다(`echo SPECOPS=1 bash …` 는
    #   `echo` 에 `=` 가 없어 반복군 0회 → 그 자리에서 bash 불일치. T62 가 잠근다).
    | ([ range(0; $all) as $i
         | $tus[$i]
         | select(.name=="Bash")
         | {id: .id, cmd: (.input.command // "")}
         | select(.cmd | test($anchor))
         | select(fid_ok(.cmd))
         | . as $u
         | ($res | map(select(.id == $u.id)) | .[0].out // "")
         | select(test("VERIFY: PASS") and (test("VERIFY: (PARTIAL|FAIL)") | not))
         | $i ] | max // -1) as $lasthit
    # ── 백그라운드 실행 증거 (20260807-bg-verify-evidence) — 기존 $lasthit 경로 무손상 ──
    # 백그라운드 Bash 는 tool_result 가 실행 출력이 아니라 스텁이다("Output is being written to: <경로>").
    # 실제 출력은 이후 별도 Read 의 결과에만 있으므로, **그 스텁이 발급한 경로와 정확히 일치하는**
    # Read 를 찾아 판정한다. 완화가 아니라 경로 추가다 — 백그라운드 Bash 도 러너 앵커를 먼저 통과해야 하고,
    # 경로 일치·출처 구속이 걸려 임의 파일 Read 로는 열리지 않는다.
    # ★ select 가드 필수: 없이 split 하면 미매칭 시 null|split 로 **jq 전체가 죽어** 셸의 `|| return 2`
    #   에 걸린다 → rc=2(fail-open) = 게이트 무음 해제. T21 이 이 회귀를 잠근다.
    # ★ Read 결과 술어는 Bash 결과와 **동일**해야 한다 — 기존 부정토큰 검사는 Bash 결과에만 걸려 있어
    #   자동 적용되지 않는다. 빼면 T10 이 잠근 위조 표면이 신규 경로에 무잠금 이식된다. T22 가 잠근다.
    | ([ range(0; $all) as $i
         | $tus[$i]
         | select(.name=="Bash")
         | {id: .id, cmd: (.input.command // "")}
         | select(.cmd | test($anchor))
         | select(fid_ok(.cmd))
         | . as $u
         | ($res | map(select(.id == $u.id)) | .[0].out // "")
         | select(test("Output is being written to: "))
         | (split("Output is being written to: ")[1] | split(" ")[0] | rtrimstr(".")) as $path
         | select($path | length > 0)
         | select([ range($i+1; $all) as $j
                    | $tus[$j]
                    | select(.name=="Read")
                    | select((.input.file_path // "") == $path)
                    | . as $r
                    | ($res | map(select(.id == $r.id)) | .[0].out // "")
                    | select(test("VERIFY: PASS") and (test("VERIFY: (PARTIAL|FAIL)") | not))
                    | 1 ] | length > 0)
         | $i ] | max // -1) as $bghit
    # ── 선언 test_command 실행 증거 (20260809-runner-anchor-downstream) ──
    # 왜 별도 블록인가: 기존 앵커 정규식은 3곳에 텍스트 복제돼 있고 T25 가 그 동일성을
    #   잠근다. 그 select 안에 OR 를 넣으면 고유 패턴이 2종이 되어 T25 가 깨진다.
    #   별도 블록은 리터럴을 늘리지 않고, 후속에 bg 확장이 필요해질 때 지점도 명확하다.
    # 왜 고정문자열인가: 선언 48건이 정규식 메타문자를 포함한다 — test() 에 넣으면 `.` 가
    #   임의 문자로 확장돼 과대 매치한다(게이트 무력화 방향).
    | ([ range(0; $all) as $i
         | $tus[$i]
         | select(.name=="Bash")
         | {id: .id, cmd: (.input.command // "")}
         # ★ heredoc 위장 차단: `cat <<DOC` 본문의 러너 줄이 줄시작 토큰으로 앵커를 통과한다.
         #   evidence.md 를 heredoc 으로 쓰는 것은 정직한 흐름이라, 막지 않으면 **문서 작성이
         #   게이트를 여는** false-open 이 된다. 기존 5종은 VERIFY: PASS 양성 요구라 무관했다.
         | select(.cmd | contains("<<") | not)
         | . as $u
         # ★ 매칭 줄이 **진짜 명령 시작**인지 본다 (Phase C Critical, 20260809).
         #   heredoc 가드만으로는 부족했다 — 따옴표 문자열 안의 실개행 줄이 선언 명령과
         #   같으면 실행 없이 열렸다(실측 재현):
         #     echo "노트\n<러너>\n끝" > notes.md      ← rc=0 이었음
         #     git commit -m "fix\n\n<러너> 로 검증함"  ← rc=0 이었음
         #     true \ + 개행 + <러너>                   ← rc=0 이었음 (인자 연속)
         #   ★ 이 판정은 인용 문법을 **흉내내지 않는다**. 두 번 시도했고 두 번 다 뚫렸다:
         #     1차 따옴표 개수 패리티 → `\"` 이스케이프가 짝수를 만들어 false-open
         #     2차 인용 상태기계     → ANSI-C `$\u0027..\u0027`·`$(..)` 중첩·백틱에서 false-open
         #   둘 다 주석에 "오산은 미탐 방향이라 안전" 이라 적었고 **둘 다 실측 반증됐다**.
         #   셸 인용은 정규 파싱이 불가하므로 아래처럼 **안전 접두 화이트리스트**로 뒤집는다.
         | ($u.cmd | split("\n")) as $lines
         | select([ range(0; ($lines | length)) as $k
             | ($lines[$k] | sub("^[ \t]+"; "")) as $L
             | select($decl | any(. as $d | $L == $d or ($L | startswith($d + " "))))
             # ★ 매칭 줄 **앞** 줄들을 안전 화이트리스트로 좁힌다 (Phase C 3회차 전환).
             #   종전엔 "문자열이 열렸나" 를 직접 판정했다 — 따옴표 패리티 → 인용 상태기계
             #   순으로 두 번 고쳤는데, 셸 인용은 정규 파싱이 불가해 라운드마다 새 우회가
             #   나왔다(이스케이프 \" → 혼합 인용 → ANSI-C → $(..) 중첩 → 백틱). 전부
             #   **false-open** 이었다. 쫓기를 그만두고 방향을 뒤집는다:
             #   앞 줄이 전부 `빈 줄`·`cd <경로>`·`set -eu`·`export X=Y` 일 때만 매칭 줄을
             #   명령 시작으로 인정한다. 그 밖(echo·git commit -m·치환·백틱·행연속·리다이렉션)은
             #   무엇이 들었든 skip 이라 **구성상 열 수 없다** — 인용 문법을 흉내내지 않는다.
             #   허용 문자셋에 따옴표·$·백틱·\ 를 넣지 않는 것이 이 가드의 본체다.
             #   대가는 미탐이다 — 앞줄에 echo 가 섞인 정직한 실행은 인식 못 한다. 그때
             #   사용자는 러너를 단독 실행하면 되고, 그건 현행 BYPASS 와 동등하다(T53).
             #   ★ 폐쇄의 범위는 **어휘적 열림**까지다. `export PATH=/tmp/evil` · `cd /가짜repo`
             #   처럼 **환경·경로를 바꿔 가짜 러너를 심는** 것은 화이트리스트를 통과한다 —
             #   F-3(의도 위조) 클래스로 설계상 수용된 범위이지 이 가드가 막는 대상이 아니다.
             #   (`_extract_declared_cmds` 헤더가 same-line env 접두를 "미인식" 이라 적은 것과 비대칭이다: 그건
             #   앵커가 줄 첫 토큰을 요구해서지 env 조작을 막아서가 아니다.)
             #   `set -euo pipefail`·`set -o pipefail` 은 `pipefail` 토큰 때문에 막힌다(미탐).
             #   후행 순수 옵션어 허용은 어휘 문자가 없어 안전하나, **인용값 허용**
             #   (`export FOO="bar baz"`)은 T58 이 잠근 `cd "` 구멍과 동형이라 금지다.
             | select($k == 0 or ([ $lines[0:$k][]
                 | select(test("^[ \t]*(cd[ \t]+[A-Za-z0-9_./~-]+|set[ \t]+-[a-zA-Z]+|export[ \t]+[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9_./:-]*)?[ \t]*$") | not)
               ] | length) == 0)
             | 1 ] | length > 0)
         # ★ 결과 존재 확인이 먼저다 — $res 는 is_error!=true 만 담으므로 에러 결과는
         #   조인에서 빠져 "" 가 되고, "" 엔 실패 토큰이 없어 성공으로 오판된다(T34 잠금).
         | ($res | map(select(.id == $u.id))) as $r
         | select($r | length > 0)
         | ($r[0].out // "")
         # ★ 백그라운드 스텁 차단 — bg Bash 의 결과는 실행 출력이 아니라 스텁이다.
         #   막지 않으면 러너를 띄우고 **결과를 보지도 않은 채** 커밋이 열린다(T41).
         #   문자열은 아래 $bghit(및 _bg_pending_path)이 쓰는 것과 동일하다.
         | select(test("Output is being written to: ") | not)
         # downstream 러너는 VERIFY: PASS 를 찍지 않는다(`PASS 12/12`) — 그 토큰을 요구하면
         #   이 경로가 영영 안 열린다. 주 판정은 위 `$r | length > 0`(= is_error false =
         #   종료코드 0) 이고, 아래 실패 토큰 스캔은 **보조층**이다.
         # ★ 꼬리 3줄만 본다 — 전체를 스캔하면 규약 성공 요약 `PASS=N FAIL=0` 과 테스트
         #   설명 줄(`PASS T16 run-all 실패(FAIL 토큰)`)이 걸려 정직한 성공이 막힌다.
         #   그건 이 FID 가 고치려는 병의 재생산이다(실측).
         | (split("\n") | map(select(test("^[ \t]*$") | not)) | .[-3:] | join("\n"))
         # 0-카운트 중화가 스캔보다 **먼저**여야 한다 — 안 그러면 FAIL=0 이 실패로 읽힌다.
         | gsub("(?i)(fail(ure)?(ed)?s?|error(s)?)[ \t]*[=:][ \t]*0(?![0-9])"; "ZERO")
         | gsub("(?i)\\b(0|no)[ \t]+(fail(ure|ed)?s?|errors?)"; "ZERO")
         # 한국어도 중화한다 — 없으면 `실패: 0`·`오류 0건` 이 차단된다. 한국어 플러그인이
         #   한국어 러너 출력을 막는 것은 대상 집단 직격 false-block 이다.
         | gsub("(실패|오류|에러)[ \t]*[:=]?[ \t]*0[ \t]*건?(?![0-9])"; "ZERO")
         | gsub("0[ \t]*건?[ \t]*(실패|오류|에러)"; "ZERO")
         | select(test("VERIFY: (PARTIAL|FAIL)") | not)
         | select(test("(?i)(^|[^a-z])(fail(ure|ed)?s?|error)") | not)
         | select(test("실패|오류|에러") | not)
         | $i ] | max // -1) as $declhit
    # 마지막 코드 편집(비-.specops Edit/Write/NotebookEdit/MultiEdit)의 전역 인덱스 (없으면 -1)
    | ([ range(0; $all) as $i
         | $tus[$i]
         | select(.name=="Edit" or .name=="Write" or .name=="NotebookEdit" or .name=="MultiEdit")
         | select(fc_is_code(.input.file_path // .input.notebook_path // ""))
         | $i ] | max // -1) as $lastedit
    # $bghit 은 **러너를 띄운 Bash 의 인덱스**다(Read 인덱스가 아님) — 실행 시작 시점이 더 보수적이라
    # "Bash 띄움 → 코드 수정 → Read" 를 stale 로 올바르게 판정한다(T20).
    | ([$lasthit, $bghit, $declhit] | max) as $besthit
    | (if $besthit >= 0 and $besthit > $lastedit then 1 else 0 end) as $h
    # 진단 전용 — 이 세션에 **다른 FID 를 글자로 적은** 러너 실행이 있었는가. 판정($h)에는 쓰지 않는다.
    | ([ $tus[] | select(.name=="Bash") | (.input.command // "") | select(test($anchor)) | select(fid_ok(.) | not) ] | length) as $other
    | "\($all) \($h) \(if $other > 0 then 1 else 0 end)"
  ' 2>/dev/null) || return 2
  [ -z "$out" ] && return 2
  uses=${out%% *}; hits=${out#* }; hits=${hits%% *}
  _EXEC_OTHER_FID=${out##* }   # apply_lookback_rule 이 같은 셸에서 읽는다(_exec_cause)
  [ "$uses" -eq 0 ] 2>/dev/null && return 2   # tool_use 이벤트 0건 → 판정 불가 (증거 없음이 아님)
  [ "$hits" -gt 0 ] 2>/dev/null && return 0
  return 1
}

# deny 사유 진단 (20260828-deny-cause-truth) — **판정에 관여하지 않는다**. deny 경로에서만 부른다.
#   stdout: `stale <마지막 편집 파일>`  (러너 PASS 증거는 있는데 그 뒤 코드를 고침)
#           빈 출력                      (그 외 — 증거 자체가 없음. 종전 문안 유지)
#
# 왜 필요한가 (실측): 러너를 정직하게 완주하고 그 뒤 파일을 고치면 stale 로 막힌다. 판정은 옳은데
#   문안이 "이 세션에 러너 실행 기록이 없습니다" 라고 **거짓 원인**을 말했다. 사용자는 방금 돌린
#   러너를 또 돌리거나(수분대 낭비) 게이트를 결함으로 의심한다 — 마찰로그 BYPASS 24건 중 15건이
#   "이 세션에서 verify PASS" 를 사유로 적었고, 4건은 "게이트 결함 의심" 이라고 명시했다.
#   틀린 deny 문안이 BYPASS 를 유도한 것은 두 번째다(v1.45.0 이 같은 이유로 문안을 교체했다).
#
# 왜 $lasthit 만 보는가: 전경 러너 경로가 지배적이고(이 함수가 다루는 실패 형태 자체가 그것),
#   $bghit·$declhit 블록까지 복제하면 리터럴이 늘어 T25(앵커 동일성 잠금)와 충돌한다.
#   그 경로는 진단이 빈 출력이 되어 **종전 문안으로 안전하게 떨어진다**(미탐 방향).
# ★ 별도 함수인 이유는 _bg_pending_path 와 같다 — _verify_exec_evidence 는 서브셸 안에서 돌아
#   변수 전파가 안 되고, 진단은 deny 경로에서만 필요해 jq 1회 추가 비용이 hot path 에 없다.
_verify_stale_cause() {  # $1=transcript → stdout "stale <파일>" 또는 빈 문자열
  [ -n "${1:-}" ] && [ -f "$1" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -rn --slurpfile a "$1" --arg anchor "$_RUNNER_ANCHOR_PAT" \
    --arg doc_re "$FC_DOC_RE" --arg runtime_re "$FC_RUNTIME_RE" \
    --arg root_phys "$(git rev-parse --show-toplevel 2>/dev/null)" \
    --arg root_log "$(_fc_root_log)" \
    --argjson plugin_repo "$(fc::is_plugin_repo && echo true || echo false)" "$_FC_JQ_DEF"'
    # 진단은 판정과 **같은 기준**을 써야 한다 — 어긋나면 deny 문안이 거짓 원인을 말한다
    #   (gbrain 20260910-commit-scope-prelude: 틀린 원인 표시가 사용자를 오진으로 몬다).
    #   그래서 위 _FC_JQ_DEF 를 판정 경로와 **같은 문자열로** 연접해 쓴다.
    ($a | map(select(.type=="assistant") | .message.content[]? | select(.type=="tool_use"))) as $tus
    | ($tus | length) as $all
    | ($a | map(select(.type=="user") | .message.content[]?
                | select(.type=="tool_result" and (.is_error != true))
                | {id: .tool_use_id, out: (.content | if type=="string" then . else tostring end)})) as $res
    | ([ range(0; $all) as $i
         | $tus[$i]
         | select(.name=="Bash")
         | {id: .id, cmd: (.input.command // "")}
         | select(.cmd | test($anchor))
         | . as $u
         | ($res | map(select(.id == $u.id)) | .[0].out // "")
         | select(test("VERIFY: PASS") and (test("VERIFY: (PARTIAL|FAIL)") | not))
         | $i ] | max // -1) as $lasthit
    | ([ range(0; $all) as $i
         | $tus[$i]
         | select(.name=="Edit" or .name=="Write" or .name=="NotebookEdit" or .name=="MultiEdit")
         | select(fc_is_code(.input.file_path // .input.notebook_path // ""))
         | {i: $i, f: (.input.file_path // .input.notebook_path // "?")} ]) as $edits
    | (($edits | map(.i) | max) // -1) as $lastedit
    | if $lasthit >= 0 and $lastedit >= $lasthit
      then "stale \(($edits | map(select(.i == $lastedit)) | .[0].f // "?"))"
      else "" end
  ' 2>/dev/null || true
}

# 백그라운드 러너 스텁은 있으나 출력 회수 Read 가 없는 경우의 경로를 반환 (없으면 빈 출력).
# deny 안내문이 "왜 막혔는지" 를 원인별로 구분하는 데 쓴다 — 구분이 없으면 사용자는 방금 러너를
# 돌리고도 "실행 기록이 없습니다" 를 보고 원인을 모른다(실측: 수분대 러너 재실행 낭비).
# ★ 별도 함수인 이유: _verify_exec_evidence 는 `res=$(apply_lookback_rule ...)` 서브셸 안에서
#   호출돼 그 안에서 설정한 변수가 부모로 전파되지 않는다(Phase B 적발). 안내문 생성은 deny
#   경로에서만 일어나므로 여기서 jq 를 1회 더 도는 비용은 hot path 에 영향이 없다.
_bg_pending_path() {  # $1=transcript → stdout 경로 (없으면 빈 문자열)
  [ -n "${1:-}" ] && [ -f "$1" ] || return 0
  jq -rn --slurpfile a "$1" --arg anchor "$_RUNNER_ANCHOR_PAT" \
    --arg doc_re "$FC_DOC_RE" --arg runtime_re "$FC_RUNTIME_RE" \
    --arg root_phys "$(git rev-parse --show-toplevel 2>/dev/null)" \
    --arg root_log "$(_fc_root_log)" \
    --argjson plugin_repo "$(fc::is_plugin_repo && echo true || echo false)" "$_FC_JQ_DEF"'
    # 안내도 판정과 같은 기준을 쓴다 — 어긋나면 "Read 하면 인정됩니다" 가 거짓이 되고
    #   안내 이행 후 동일 메시지 재차단 → BYPASS 스파이럴(dogfood #418→#421) 조건이 된다.
    #   그래서 위 _FC_JQ_DEF 를 판정 경로와 **같은 문자열로** 연접해 쓴다(사본 금지 — Phase C I-1).
    ($a | map(select(.type=="assistant") | .message.content[]? | select(.type=="tool_use"))) as $tus
    | ($tus | length) as $all
    | ($a | map(select(.type=="user") | .message.content[]?
                | select(.type=="tool_result" and (.is_error != true))
                | {id: .tool_use_id, out: (.content | if type=="string" then . else tostring end)})) as $res
    | ([ range(0; $all) as $i
         | $tus[$i]
         | select(.name=="Bash")
         | {id: .id, cmd: (.input.command // "")}
         | select(.cmd | test($anchor))
         | . as $u
         | ($res | map(select(.id == $u.id)) | .[0].out // "")
         | select(test("Output is being written to: "))
         | (split("Output is being written to: ")[1] | split(" ")[0] | rtrimstr(".")) as $path
         | select($path | length > 0)
         | select([ range($i+1; $all) as $j
                    | $tus[$j]
                    | select(.name=="Read")
                    | select((.input.file_path // "") == $path)
                    | 1 ] | length == 0)
         | {i: $i, p: $path} ] | last // null) as $pend
    # ★ staleness 정렬 (Phase C Important 1): 안내는 판정과 같은 기준을 써야 한다.
    #   bg 기동 이후 코드 편집이 있으면 안내대로 Read 해도 stale 로 재차단된다 —
    #   "Read 하면 인정됩니다" 가 거짓이 되고, 이 deny 메시지 자신이 경고하는
    #   "안내 이행 후 동일 메시지 재차단 → BYPASS 스파이럴"(dogfood #418→#421) 조건이 된다.
    | ([ range(0; $all) as $i
         | $tus[$i]
         | select(.name=="Edit" or .name=="Write" or .name=="NotebookEdit" or .name=="MultiEdit")
         | select(fc_is_code(.input.file_path // .input.notebook_path // ""))
         | $i ] | max // -1) as $lastedit
    | (if $pend != null and $pend.i > $lastedit then $pend.p else "" end)
  ' 2>/dev/null || true
}

# staged ∪ unstaged-tracked 합집합 변경이 전부 docs 확장자면 0(면제), 아니면 1(비면제).
# git diff HEAD = working tree vs HEAD = staged + unstaged tracked 전부 포함 (commit -a 우회 차단).
# base branch 자동감지 — main 우선, master 차선, 없으면 실패(안전측 차단).
_detect_base_branch() {
  # main·master·origin/main·origin/master 중 HEAD 에 가장 가까운(ref..HEAD 커밋 수 최소) ref — 동률이면 앞선 후보(로컬).
  #   로컬 main 만 보면, 로컬 main 이 원격보다 뒤처진 repo 에서 base...HEAD 가 원격에 쌓인 변경까지 PR 범위로 읽는다
  #   (문서뿐인 PR 이 코드 포함으로 판정돼 false-deny). risk-profile.sh rp::base_ref 와 같은 규칙이다.
  local b n best="" best_n=""
  for b in main master origin/main origin/master; do
    git rev-parse --verify --quiet "$b^{commit}" >/dev/null 2>&1 || continue
    n=$(git rev-list --count "$b..HEAD" 2>/dev/null) || continue
    case "$n" in ''|*[!0-9]*) continue ;; esac
    if [ -z "$best" ] || [ "$n" -lt "$best_n" ]; then best=$b; best_n=$n; fi
  done
  [ -n "$best" ] || return 1
  printf '%s' "$best"
}

# 명령이 `gh pr create` 이고 같은 명령에 커밋·add 가 없다 → 0 (PR 범위 판정). 그 밖엔 1 (종전 경로).
#   커밋을 함께 하는 compound(`git commit … && gh pr create`)는 PR 범위가 아직 확정 전이라 종전 경로를 유지한다.
#   $1 은 호출부가 heredoc·인용 본문을 벗긴 tool_cmd_scan 이다(batch 게이트도 같은 값을 넘긴다). 무인자 = 1.
_cmd_is_pr_create_only() {
  local c="${1:-}"
  [ -n "$c" ] || return 1
  grep -Eq "$_PR_CREATE_RE" <<< "$c" || return 1
  grep -Eq 'git[[:space:]]+([^;&|]*[[:space:]])?(commit|add|stage)([[:space:]]|$)' <<< "$c" && return 1
  return 0
}

# 명령이 index 에 파일을 더하는 `git add`/`git stage` 를 포함하는가 → 0 (untracked 가 커밋에 실릴 수 있음).
_cmd_stages_untracked() {
  local c="${1:-}"
  [ -n "$c" ] || return 1
  grep -Eq 'git[[:space:]]+([^;&|]*[[:space:]])?(add|stage)([[:space:]]|$)' <<< "$c"
}

# 신규 repo(HEAD 없음) → --cached fallback. working tree·staged 빈(=PR 맥락, 커밋 완료) → base...HEAD PR-범위 diff.
# 빈 목록·git 실패·base 결정 불가 → 1 (fail-safe — 판정 불가 시 차단 보존). fail-open(hook 에러 allow)과 구분.
is_docs_only_change() {
  # --no-renames: rename 을 delete(old)+add(new) 2줄로 분해 → 코드파일 .md rename 위장
  #   (tool.sh→tool.md)이 원본 .sh 를 숨겨 docs-only 오인면제되던 표면 차단. 출력포맷(--name-only) 무변경.
  # $1(선택): 실행될 커밋 명령. **인자가 없으면 아래 분기가 통째로 비활성**이라 종전과 동일하게 동작한다
  #   — batch 게이트(pretool:112)·기존 T-docs.a~q 가 무수정인 이유다.
  # ★ 계측 전역 리셋 (Phase C Important, 20260813-friction-staged-record): 아래 이른 반환 경로
  #   (`[ -z "$files" ] && return 1`, 2곳)는 대입 **전에** 빠져나간다. 같은 훅 프로세스에서
  #   batch 게이트(pretool:113, 무인자)가 먼저 working-tree 목록으로 전역을 채운 뒤 본판정이
  #   이른 반환하면, deny 경로(pretool:236)가 **직전 호출의 목록**을 분류한다(실측: staged 빈
  #   상태인데 `code` 로 기록). 나아가 working-tree 가 all-docs 면 block 레코드에 `docs-only` 가
  #   출현해 AC-3 이 세운 "구조적 불가" 이상신호 축을 자기오염시킨다. 판정·종료코드와는 무관한
  #   계측 전용 결함이지만, 계측이 사실을 말하지 않으면 존재 이유가 없다(5원칙 1).
  _SPECOPS_SCOPE_FILES=""
  local files
  # PR 생성은 **이미 커밋된 base...HEAD** 가 판정 대상이다 — 작업트리는 PR 에 실리지 않는다.
  #   종전엔 아래 작업트리 분기를 타서, 추적 중인 .specops/session-progress.md 하나만 dirty 여도 all-docs 로
  #   보여 커밋된 미검증 코드 PR 이 면제됐다(posttool is_docs_only_audit_scope R-2 와 같은 범위로 정렬).
  #   base 미검출·범위 빔·git 실패는 종전 fail-safe 와 동일하게 1(비면제 → 이후 verify/fail-open 경로).
  if _cmd_is_pr_create_only "${1:-}"; then
    local pr_base
    pr_base=$(_detect_base_branch) || return 1
    files=$(git diff "$pr_base"...HEAD --name-only --no-renames 2>/dev/null)
    [ -z "$files" ] && return 1
    _SPECOPS_SCOPE_FILES="$files"
    _files_all_docs "$files"
    return $?
  fi
  if _commit_scope_is_staged "${1:-}"; then
    # 안전 형태 → staged 가 곧 커밋 범위다. 빈 staged 는 fail-safe(비면제) 로 떨어진다.
    files=$(git diff --cached --name-only --no-renames 2>/dev/null)
    [ -z "$files" ] && return 1
    # 계측용 노출 (20260813-friction-staged-record) — 호출자가 같은 목록으로 분류할 수 있게 한다.
    #   deny 경로에서 git diff 를 재실행하지 않기 위함이며, 판정 자체에는 쓰이지 않는다.
    #   set -u 안전: 파일 상단에서 `: "${_SPECOPS_SCOPE_FILES:=}"` 로 초기화한다.
    _SPECOPS_SCOPE_FILES="$files"
    _files_all_docs "$files"
    return $?
  fi
  files=$(git diff HEAD --name-only --no-renames 2>/dev/null)
  [ -z "$files" ] && files=$(git diff --cached --name-only --no-renames 2>/dev/null)
  # `git add -A && git commit` 류 compound 는 untracked 신규 파일도 커밋에 싣는데 git diff HEAD 는 그걸 못 본다.
  #   add 가 든 명령에 한해 untracked(비-ignore)를 합쳐, 신규 코드가 문서 dirty 뒤에 숨어 면제되는 것을 막는다.
  #   `commit -am` 처럼 add 가 없으면 untracked 는 커밋에 실리지 않으므로 합치지 않는다(과잉 차단 방지).
  if _cmd_stages_untracked "${1:-}"; then
    local untracked
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null)
    [ -n "$untracked" ] && files="${files:+$files$'\n'}$untracked"
  fi
  if [ -z "$files" ]; then
    local base
    base=$(_detect_base_branch) || return 1
    files=$(git diff "$base"...HEAD --name-only --no-renames 2>/dev/null)
  fi
  [ -z "$files" ] && return 1
  # 계측용 노출 (20260813-friction-staged-record) — 위 staged 경로와 대칭.
  _SPECOPS_SCOPE_FILES="$files"
  _files_all_docs "$files"
}

# whitelist 매처 (is_docs_only_change ↔ is_docs_only_audit_scope 공유 — 면제 클래스 drift 방지)
# 빈 목록 = 1 (fail-safe — 판정 불가 시 비면제).

# 목록 **전체**가 문서인가 — 파일 1건 판정은 fc::is_doc 이 SoT 다(scripts/_internal/file-class.sh).
#   분류 규칙(플러그인 런타임 예외·screens/*.html·.specops/ 면제)과 그 근거는 전부 그 파일에 있다.
#   여기에 패턴을 **복제하지 않는다** — 두 벌이 되면 한쪽만 조여져 면제와 무효화가 어긋나고,
#   그게 20260912 에 문서 한 줄이 커밋을 막던 결함의 구조다(test-file-class.sh T1.d 가 복제를 잠근다).
_files_all_docs() {
  local files="$1" f plugin_rc=1
  [ -z "$files" ] && return 1
  fc::is_plugin_repo && plugin_rc=0   # 루프 **밖에서 1회만** — 훅은 hot path 다
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    fc::is_doc "$f" "$plugin_rc" || return 1
  done <<EOF
$files
EOF
  return 0
}

# 커밋 범위를 계측용으로 분류한다 (20260813-friction-staged-record).
#   stdout: docs-only | code | empty · 항상 rc=0 (판정 실패 개념이 없다 — 빈 목록도 유효한 답)
#
# 왜 필요한가: friction-log 가 "무엇을 커밋하려 했는가"를 남기지 않아, 마찰이 정탐인지
#   오탐인지 사후 산정이 불가능했다(선행 FID 20260813-r1-docs-only-scope 가 block 77건 중
#   결함 유래를 끝내 세지 못하고 "효과 미측정"으로 남긴 것이 실증).
#
# 왜 _files_all_docs 재사용인가: 분류가 **면제 클래스와 정의상 일치**해야 집계가 의미를 갖는다.
#   별도 규칙을 만들면 "면제됐는데 code 로 분류" 같은 모순이 생긴다. 매처 자체는 건드리지 않는다
#   (pretool↔posttool 공유 — #214→T8.e 회귀 위험).
_commit_scope_class() {
  local files rc1=0 rc2=0
  if [ "$#" -gt 0 ]; then
    files="$1"
  else
    files=$(git diff --cached --name-only --no-renames 2>/dev/null); rc1=$?
    if [ -z "$files" ]; then
      files=$(git diff HEAD --name-only --no-renames 2>/dev/null); rc2=$?
      # ★ 판정 불가(git 실패)와 빈 커밋범위를 구별한다 (AC-6·AC-4).
      #   둘 다 실패면 **아무것도 출력하지 않는다** → 호출부의 조건부 병합이 필드를 생략하고
      #   집계는 `판정불가` 로 센다. 여기서 'empty' 를 내면 AC-4 가 분리한 축이 다시 뭉개진다.
      [ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ] && return 0
    fi
  fi
  [ -z "$files" ] && { printf 'empty'; return 0; }
  if _files_all_docs "$files"; then printf 'docs-only'; else printf 'code'; fi
}

# 커밋 명령이 **staged 만** 커밋하는 안전 형태인지 판정한다 (20260813-r1-docs-only-scope).
#   0 = staged 로 스코프 축소 가능 / 1 = 보수(현행 working-tree) 스코프 유지.
#
# 왜 필요한가: is_docs_only_change 는 working tree 전체를 봐서, 문서만 staged 해 커밋해도
#   작업트리에 남은 코드 수정 때문에 차단됐다(실측 BYPASS 16건 중 13건이 "코드 변경 0").
#   종전 주석은 "pretool 은 액션 前이라 working-tree 가 곧 커밋 범위"라고 단정했으나 **틀렸다** —
#   staged 부분집합 커밋에서 working-tree ⊋ 커밋 범위다.
#
# 왜 화이트리스트인가: #255 가 "이름 나열"식 접근의 3회 반복 실패를 기록한다. 위험 형태를 나열하면
#   나열 밖이 뚫린다. 안전 형태만 통과시키면 나열 밖은 전부 **보수 쪽(false-block 방향)** 으로 넘어진다.
# C-1 (20260910): 커밋 명령 앞에 올 수 있는 **index 를 바꾸지 않는** 선행 줄인가.
#   0 = 안전(소비) · 1 = 아님(그 줄을 커밋 후보로 넘긴다 → 기존 C2 가 판정한다).
# 왜 "건너뛰기"가 아니라 "소비"인가: gbrain 20260813-r1-docs-only-scope 가 남긴 교훈 —
#   입력에서 정보를 버리면 검증도 함께 버려진다. 여기서는 **2형태만** 벗겨내고 나머지는
#   그대로 기존 파이프라인에 넘긴다. `cd` 뒤의 `git add -A` 가 커밋 후보가 되어 C2 에서
#   보수로 떨어지는 것이 이 구조의 요점이다(false-open 차단축).
# 순수 문자열 판정을 유지한다 — git·realpath 호출 0(사용자 결정 20260910: 심볼릭링크
#   구별 불가라는 비용을 감수하고 파일시스템 의존을 만들지 않는다).
_is_safe_prelude_line() {
  local l="$1" tok rest
  l=${l#"${l%%[![:space:]]*}"}; l=${l%"${l##*[![:space:]]}"}
  [ -n "$l" ] || return 1
  case "$l" in *'&&'*|*'||'*|*';'*|*'|'*|*'$('*|*'`'*) return 1 ;; esac
  tok=${l%%[[:space:]]*}; rest=${l#"$tok"}
  rest=${rest#"${rest%%[![:space:]]*}"}
  case "$tok" in
    cd)
      [ -n "$rest" ] || return 1                          # bare cd = HOME 이동
      # ★ 문자 화이트리스트 (plan-reviewer 1회차 Critical-1 실측): `_strip_quoted_strings` 는
      #   인용 **본문**만 지우고 껍데기(`""`·`''`)를 남긴다 — `cd "/tmp/other-repo"` 가
      #   `rest='""'` 가 되어 `/*` 매칭을 비껴가고 상대경로로 오인돼 **타 repo cd 가 열렸다**.
      #   `$HOME`·`$DIR`·`{a,b}`·`>x`·`cd a b`(공백) 도 같은 클래스다. 위험 문자를 나열하는
      #   대신 **허용 문자만** 통과시킨다(나열 밖은 전부 보수 — 이 파일의 화이트리스트 철학).
      #   ⚠️ 엄밀 ASCII 아님: bash 3.2 UTF-8 locale 에서 `[A-Za-z]` 가 `é` 류를 통과시킨다
      #   (실측). 셸 메타문자가 아니라 안전 영향은 없다.
      #   ★ `$PWD` 접두는 **벗겨낸 뒤** 나머지에만 적용한다 (2회차 Minor-1): repo 경로에
      #   한글·공백이 있으면 `cd "$PWD"` 자신이 막혀 그 사용자는 C-1 회수가 0 이 된다.
      case "$rest" in
        "$PWD")   return 0 ;;
        "$PWD"/*) rest=${rest#"$PWD"/} ;;
        /*)       return 1 ;;                              # 그 밖의 절대경로 = 타 repo
      esac
      case "$rest" in *[!A-Za-z0-9_./-]*) return 1 ;; esac
      case "$rest" in -*|*'..'*) return 1 ;; esac           # cd - · 옵션 · 상위 탈출
      return 0
      ;;
    *=*)
      [ -z "$rest" ] || return 1                           # 동일 줄 env 접두(T-docs.ae 불변)
      case "${tok%%=*}" in ''|*[!A-Za-z0-9_]*) return 1 ;; esac
      case "${tok%%=*}" in [0-9]*) return 1 ;; esac
      # ★ 이름 나열 예외 2건 (사용자 결정 20260910, Phase C Important-3). 이 파일은 위험 이름을
      #   나열하지 않는 화이트리스트 철학이지만, `PATH`·`CDPATH` 두 이름만은 거부한다 — 둘은
      #   이 함수의 전제("index 를 바꾸지 않는 줄") 자체를 거짓으로 만든다:
      #   `PATH=/tmp/evil` 은 뒤에 올 줄의 `git` 이 **어느 바이너리**인지를, `CDPATH=/tmp` 는
      #   `cd sub` 가 **어느 디렉터리**로 가는지를 바꾼다. 즉 prelude 가 약속한 불변식(어느 git·어디서)을
      #   직접 깨부수는 유이한 이름이라 예외로 둔다(실측: 둘 다 이 줄 이전에는 안전 prelude 로 통과했다).
      #   나열을 넓히지 않는다: `HOME`·`GIT_*`·`LD_*` 등은 본 FID 범위 밖이며 여전히 안전으로
      #   통과한다 — **알려진 한계**다(spec §7 에는 아직 기재되지 않았다).
      case "${tok%%=*}" in PATH|CDPATH) return 1 ;; esac
      # 리다이렉션·이스케이프(Minor-4). ★ `*\\*` 는 **역슬래시 1개**를 잡는다 — 앞선
      #   `*'\\'*` 는 single-quote 안이라 역슬래시 **2개**만 매칭해 `VAR=a\b` 가 새어
      #   안전(rc=0)으로 판정됐다(실측 rc=0→1). shellcheck SC1003 도 함께 해소된다.
      case "$tok" in *'>'*|*'<'*|*\\*) return 1 ;; esac
      return 0
      ;;
  esac
  return 1
}

_commit_scope_is_staged() {
  local s first resid tok extra rest skip=0 _NL=$'\n' _pre=0 _line
  [ -n "${1:-}" ] || return 1
  # 스트리퍼 재사용 — heredoc 본문·인용 내용이 판정을 오염시키지 않도록 (pretool 과 동일 전처리).
  s=$(_strip_heredoc_bodies "$1")
  s=$(_strip_quoted_strings "$s")
  # C-1: 안전 prelude 줄을 최대 8줄까지 벗긴다. 9줄째면 보수(입력 크기 방어 — AC-9).
  while :; do
    case "$s" in *"$_NL"*) _line=${s%%"$_NL"*} ;; *) break ;; esac
    _is_safe_prelude_line "$_line" || break
    [ "$_pre" -ge 8 ] && return 1
    _pre=$((_pre+1))
    s=${s#*"$_NL"}
  done
  # C1(개행): **개행은 `;` 와 동등한 명령 분리자다.** 첫 줄만 남기고 잔여를 무검증 폐기하면
  #   C1(연산자)·C2(단일 커밋) 가 둘째 줄부터 적용되지 않는다 — `git commit -m 'docs'` ⏎ `git add -A`
  #   ⏎ `git commit -am 'code'` 가 축소 승인으로 뚫렸다(Phase B false-allow 실측, 구코드는 deny).
  #   그렇다고 멀티라인을 전부 거부할 수는 없다 — `-F - <<'EOF'` heredoc 이 이 repo 주력 커밋 형태다(AC-7).
  #   그래서 잔여 줄이 **heredoc 종결자로만 설명되는지**를 검사한다: 첫 줄에 `<<` 가 있고 잔여 줄이
  #   공백 또는 bare word(`[A-Za-z0-9_]+`) 단독이면 통과, 그 외는 전부 보수.
  #   왜 실제 delimiter 와 대조하지 않는가: `<<EOF`·`<<'EOF'`·`<<-EOF` 파싱 표면만 늘고 보안 이득이 없다 —
  #   아래 C2 가 **첫 명령이 곧 커밋**임을 이미 보장하므로, 뒤따르는 bare word 명령은 그 커밋의
  #   staged 범위를 바꿀 수 없다(인자 없는 한 단어라 `git add ...` 형태가 불가능).
  #   ★ ANSI-C 인용 정정(Phase C 실측): `-m $'a\nb'` 는 _strip_quoted_strings 가 bail(원본 반환)하지만
  #     그것만으로 보수가 되지는 않는다 — **실개행을 포함한 형태**만 위 멀티라인 검사에서 보수로 떨어지고,
  #     리터럴 `\n` 한 토큰은 아래 C3 의 skip 이 소비해 통과한다(rc=0). 통과해도 무해하다 — 메시지 값이라
  #     staged 범위를 바꾸지 못한다. 이 주석을 정정하는 이유: 본 함수가 존재하는 원인 자체가
  #     "working-tree 가 곧 커밋 범위" 라는 **틀린 주석**이었다. 검증 없는 안전 주장은 다음 결함의 씨앗이다.
  first=${s%%$'\n'*}
  if [ "$first" != "$s" ]; then
    resid=${s#*$'\n'}
    while IFS=$' \t' read -r tok extra; do
      [ -z "$tok" ] && continue                            # 공백 전용 줄(후행 개행 등)
      case "$first" in *'<<'*) ;; *) return 1 ;; esac      # heredoc 아닌 멀티라인 = 명령 분리
      [ -n "$extra" ] && return 1                          # 종결자 줄에 토큰이 더 있으면 명령
      case "$tok" in *[!A-Za-z0-9_]*) return 1 ;; esac      # bare word 아님
    done <<EOF
$resid
EOF
  fi
  s=$first           # 첫 줄만 — heredoc 종결자 줄(EOF) 은 위에서 검증 완료
  s=${s%%<<*}        # heredoc 리다이렉션 토큰 절단 (`-F - <<'EOF'` 의 뒷부분)
  # C1: compound — 파싱 시점 staged ≠ 커밋 시점 staged (`git add -A && git commit`)
  case "$s" in *'&&'*|*'||'*|*';'*|*'|'*) return 1 ;; esac
  # 경로로 부른 git(`/usr/bin/git commit`)은 맨 `git commit` 과 같은 형태다 (20261009) — 트리거가 이 표기를 인식하게 된 뒤
  #   여기서만 못 읽으면 문서만 staged 한 커밋이 표기 때문에 보수 판정(작업트리 전체)으로 막힌다. 경로 문자는 화이트리스트.
  tok=${s%%[[:space:]]*}
  case "$tok" in */git) case "$tok" in *[!A-Za-z0-9_./~-]*) ;; *) s="git${s#"$tok"}" ;; esac ;; esac
  # C2+C5: 반드시 `git commit` 으로 시작. env 접두·`git -c ... commit`·다중 명령이 한 번에 배제된다.
  case "$s" in
    'git commit') rest="" ;;
    'git commit '*) rest=${s#git commit } ;;
    *) return 1 ;;
  esac
  # C3+C4+C6: 화이트리스트 플래그만 허용. 값을 받는 플래그는 다음 토큰을 소비한다.
  #   비플래그 토큰(경로 인자)·화이트리스트 밖 `-` 토큰은 전부 보수 판정.
  #   ★ 명령치환은 skip 소비보다 먼저 거부한다 (Phase C Important-2). _strip_quoted_strings 는
  #     `$(`·백틱 포함 인용을 "실제 실행된다 → 판정 보존" 목적으로 **일부러 남기는데**(:654),
  #     `skip=1` 이 그 보존 토큰을 무검사로 삼키면 스트리퍼의 의도가 무력화된다. 실측상 뚫리던 것은
  #     `-m "$(ga)"` 류 **무인자 단일 토큰**뿐이지만(다중 토큰·분리자 포함은 이미 보수),
  #     치환은 커밋 **전에** 실행되므로 그 한 형태로도 "파싱 시점 staged ≠ 커밋 시점 staged" 가 성립한다.
  #     false-block 비용은 `-m "$(cat f)"` 단일 토큰 클래스뿐이라 사실상 0.
  for tok in $rest; do
    case "$tok" in *'$('*|*'`'*) return 1 ;; esac
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$tok" in
      -m|--message|-F|--file) skip=1 ;;
      --message=*|--file=*|-q|--quiet) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# posttool 감사 스코프 (20260718-posttool-audit-silence): 감사는 **방금 일어난 액션의 범위**를 본다 —
#   R-1(commit) = HEAD~1..HEAD(방금 커밋), R-2(pr create) = base...HEAD(PR 범위).
# 왜: working-tree 기준 is_docs_only_change 를 posttool 에 쓰면, 커밋 직후 잔여 dirty 가 거의 항상
#   tracked `.specops/session-progress.md` 뿐이라 .specops/* 면제(#214)에 걸려 **감사가 통째로 침묵**한다
#   (#214 이후 R-1 posttool warn 전 repo 0건의 실물 원인 — pretool block 만 남는 절반 가시성).
#   pretool 을 분리해 두는 이 근거(#214 침묵)는 그대로 유효하다 — 감사는 **이미 일어난** 액션의 범위를 본다.
#   다만 종전 주석이 덧붙인 "pretool 은 액션 前이라 working-tree 가 곧 커밋 범위" 라는 전제는 **틀렸다**:
#   staged 부분집합 커밋에서 working-tree ⊋ 커밋 범위다. pretool 쪽은 is_docs_only_change 가 커밋 명령을
#   받아 _commit_scope_is_staged 로 스코프를 좁혀 해결했다 (20260813-r1-docs-only-scope, 위 :458 참조).
# fail-safe: range diff 실패(최초 커밋 HEAD~1 부재·base 미검출) = 비면제(감사 실행 — 차단 아닌 기록이라
#   과잉 방향이 안전).
is_docs_only_audit_scope() {
  local rule_id="$1" files
  case "$rule_id" in
    R-1) files=$(git diff HEAD~1..HEAD --name-only --no-renames 2>/dev/null) || files="" ;;
    R-2) local base
         base=$(_detect_base_branch) || return 1
         files=$(git diff "$base"...HEAD --name-only --no-renames 2>/dev/null) ;;
    *) return 1 ;;
  esac
  _files_all_docs "$files"
}

# 감사 스코프의 **커밋 범위 분류** (20260814-friction-scope-posttool).
#
# 왜 별도 함수인가: posttool 은 액션 **후** 발화하므로 `_commit_scope_class`(staged/HEAD 기준)를
#   쓰면 `git diff --cached` 가 비어 'empty' 로 오분류된다. 범위는 is_docs_only_audit_scope 와
#   **동일**해야 한다 — 분류가 면제 클래스와 정의상 일치해야 집계가 의미를 갖기 때문이다(:481 과 같은 이유).
#   is_docs_only_audit_scope 는 boolean 이라 파일 목록을 돌려주지 않아 여기서 다시 캡처한다.
#
# ★ 판정 불가(무출력) ↔ 'empty' 는 **다른 축**이다 (_commit_scope_class 와 동형):
#   전자는 git 판정 실패(HEAD~1 부재·base 미탐지·미지원 rule_id), 후자는 커밋 범위가 실제로 빔.
#   무출력이면 호출부의 조건부 병합이 scope_class 필드를 생략하고 집계가 `판정불가` 로 센다.
#
# ★ posttool 경로에서는 'docs-only' 가 **구조적으로 나오지 않는다** — posttool-governance.sh:78 이
#   is_docs_only_audit_scope 면제 시 기록 자체를 하지 않기 때문이다. 반환값에 'docs-only' 를 남겨 두는
#   것은 함수 계약의 대칭(직접 호출·향후 재사용)을 위해서이지 posttool 집계에 나타나기 때문이 아니다.
_audit_scope_class() {
  local rule_id="${1:-}" files
  case "$rule_id" in
    R-1) files=$(git diff HEAD~1..HEAD --name-only --no-renames 2>/dev/null) || return 0 ;;
    R-2) local base
         base=$(_detect_base_branch) || return 0
         files=$(git diff "$base"...HEAD --name-only --no-renames 2>/dev/null) || return 0 ;;
    *)   return 0 ;;
  esac
  [ -z "$files" ] && { printf 'empty'; return 0; }
  if _files_all_docs "$files"; then printf 'docs-only'; else printf 'code'; fi
}

# heredoc **본문**을 트리거 검사 입력에서 제거한다 (20260713-heredoc-false-block).
#
# 왜: Bash tool 의 command 는 흔히 멀티라인이고 `grep -E` 는 **줄 단위**로 검사한다 → 문서·테스트에 쓴
#   heredoc 본문의 git 예시가 **실제 명령으로 오인**되어 정직한 작업이 차단됐다(false-block, 실전 적발).
#   주석(`#`)·echo 는 선행자 클래스에 없어 안 걸리는데 heredoc 본문만 걸렸다. false-block 은 BYPASS 남발을
#   유발해 게이트 신호 자체를 희석한다.
# 범위: **입력만 전처리**한다. 트리거 정규식(rules.jsonl · pretool 인라인)은 무변경 — 정규식을 손대면
#   evasion 방어(PR #84·#112)가 흔들린다.
#
# ★ 실행자 판정 (F-3 표면 불변의 핵심): 시작 줄이 셸 실행자(bash·sh·zsh·ksh·dash·eval·exec·source)면
#   본문은 **실제로 셸에 실행되므로 제외하지 않는다**(passthrough). cat·tee·python3 등은 데이터로 보고 제외한다.
#   python3 본문은 셸 명령이 아니다 — 그 안의 subprocess git 호출은 **이미 F-3 wrapper-class**(WON'T-FIX)라
#   제외해도 표면이 넓어지지 않는다. 실측: 이 repo 는 `cat <<` 117건 · `python3 <<` 8건 · `bash <<` **0건**.
# ★ fail-safe (fail-open 아님): 미종료 heredoc · 한 줄 다중 heredoc · delimiter 파싱 불가 · awk 실패 →
#   **원본 반환** = 현재 동작(차단 우세)으로 후퇴. 제거 로직의 버그가 **차단을 뚫는 방향으로 작용하면 안 된다**.
#   애매하면 strip 하지 않는다 (정당한 차단이 뚫리는 것 > false-block).
# 지원 문법: `<<EOF` · `<<'EOF'` · `<<"EOF"` · `<<-EOF`(탭 들여쓰기 종료자). herestring(`<<<`)은 본문이 없어 무시.
# 이식성: POSIX awk 만 사용 (GNU 확장 match() 3인자 금지 — macOS bash 3.2/BSD awk).
_strip_heredoc_bodies() {
  local cmd="$1" out
  # 빠른 경로 — heredoc 연산자가 없으면 **바이트 동일** 반환 (기존 트리거 동작 완전 보존)
  case "$cmd" in
    *'<<'*) ;;
    *) printf '%s' "$cmd"; return 0 ;;
  esac
  out=$(printf '%s\n' "$cmd" | awk '
    BEGIN { inb=0; keep=0; dash=0; delim=""; bail=0; no=0; SQ=sprintf("%c",39); DQ=sprintf("%c",34) }
    { orig[NR]=$0
      if (bail) next
      if (inb) {                      # heredoc 본문 안
        t=$0
        if (dash) sub(/^\t+/,"",t)    # <<- 는 종료자의 선행 탭 허용
        if (t==delim) { inb=0; out[++no]=$0; next }   # 종료자 줄은 유지
        if (keep) out[++no]=$0        # 실행자 본문 = 실제 실행 → 유지
        next                          # 데이터 본문 → 제거
      }
      out[++no]=$0                    # 시작 줄은 항상 유지 (같은 줄의 `; git commit` 을 잡기 위해)
      probe=$0
      gsub(/<<</,"@@@",probe)         # herestring 마스킹 (길이 3 보존 → 위치 불변)
      cp=probe; nops=gsub(/<</,"x",cp)   # 치환결과 미사용 — gsub 반환값(연산자 개수)만 쓴다
      if (nops==0) next
      if (nops>1) { bail=1; next }    # 한 줄 다중 heredoc → 판정 포기(원본)
      if (!match(probe,/<<-?[ \t]*/)) { bail=1; next }
      dash=(substr(probe,RSTART+2,1)=="-")
      rest=substr(probe,RSTART+RLENGTH)
      q=substr(rest,1,1)
      if (q==SQ || q==DQ) {           # <<EOF 의 인용형: <<\047EOF\047 · <<"EOF"
        r2=substr(rest,2); p=index(r2,q)
        if (p<2) { bail=1; next }
        delim=substr(r2,1,p-1)
      } else if (match(rest,/^[A-Za-z_][A-Za-z0-9_]*/)) {
        delim=substr(rest,RSTART,RLENGTH)
      } else { bail=1; next }         # delimiter 파싱 불가 → 판정 포기(원본)
      # 실행자 판정은 **시작 줄 1줄**만 본다. 한계: 실행자가 줄-연속(백슬래시 개행)으로 시작 줄과 분리되면
      #   (bash 다음 줄에 <<EOF) 미탐지 → 본문 제외 → 통과. 실행자를 숨기려는 **의도적 난독화**이므로
      #   기존 F-3 wrapper-class(sh -c 등, 의도적 WONT-FIX)로 수용한다 — honest-mistake 경로가 없다.
      #   멀티라인 실행자 추적은 하지 않는다: 매 커밋에 도는 훅에 새 버그를 들이는 비용 > 그 표면의 값.
      keep=($0 ~ /(^|[ \t;&|(){}`])(bash|sh|zsh|ksh|dash|eval|exec|source)([ \t]|$)/) ? 1 : 0
      inb=1
    }
    END {
      if (bail || inb) { for(i=1;i<=NR;i++) print orig[i] }   # 미종료·판정 포기 → 원본 (fail-safe)
      else { for(i=1;i<=no;i++) print out[i] }
    }
  ' 2>/dev/null) || { printf '%s' "$cmd"; return 0; }   # awk 실패 → 원본 (fail-safe)
  [ -n "$out" ] || { printf '%s' "$cmd"; return 0; }    # 빈 출력(비정상) → 원본 (fail-safe)
  printf '%s' "$out"
}

# 인용 문자열 리터럴 본문을 트리거 검사 입력에서 제거한다 (20260717-quoted-falseblock).
#
# 왜: printf/echo 인자 등 **인용 문자열 안의 프로즈**("배포 후 (git commit 으로 기록)"·"build | git commit")에
#   든 셸 메타문자 선행자((·|)가 트리거와 오매칭 → 정직한 문서·코드 텍스트 작성이 차단됐다
#   (dogfood 20260717 test2 모델 backlog "R-1 블록주석 내부 오검출" — probe 로 실재 확정. heredoc 경로는
#   _strip_heredoc_bodies 가 이미 처리, 인라인 인용 인자가 잔여 표면이었다).
# 안전 불변식 (차단 우세 — heredoc strip 과 동일 철학):
#   - 싱글쿼트 본문: bash 가 절대 실행하지 않음 → 무조건 제거. eval/sh -c '...' wrapper 는 오늘도
#     트리거 미매칭(선행자 ' 는 클래스 밖 — F-3 WON'T-FIX 클래스)이라 제거해도 표면 불변.
#   - 더블쿼트 본문: $( ) 또는 백틱 포함 시 **실제 실행됨** → 그 문자열은 제거하지 않고 보존(deny 보존).
#   - 백슬래시: bash 인용 의미대로 처리(다음 1문자 verbatim — \" 가 인용 경계를 못 닫게). blanket-bail 로
#     하면 printf "%s\n" 류(실전 false-block 의 주 형태)가 전부 bail 돼 본 fix 가 무력화된다.
#   - bail(원본 반환): $'...' ANSI-C 인용 · 미종결 인용 · awk 실패 — 파싱 애매 시 현재
#     동작(차단 우세)으로 후퇴. 제거 로직 버그가 차단을 뚫는 방향으로 작용하면 안 된다.
# 이식성: POSIX awk (\x 이스케이프 금지 — SQ/DQ/BT 는 sprintf("%c",N), heredoc strip 선례).
_strip_quoted_strings() {
  local cmd="$1" out
  case "$cmd" in
    *"'"*|*'"'*) ;;
    *) printf '%s' "$cmd"; return 0 ;;   # 빠른 경로 — 인용 없음 = 바이트 동일
  esac
  out=$(printf '%s\n' "$cmd" | awk '
    BEGIN { SQ=sprintf("%c",39); DQ=sprintf("%c",34); BT=sprintf("%c",96); BS=sprintf("%c",92) }
    { lines[NR]=$0 }
    END {
      buf=""
      for(i=1;i<=NR;i++) buf = buf lines[i] (i<NR ? "\n" : "")
      if (index(buf, "$" SQ) > 0) { printf "%s", buf; exit }   # $\047...\047 ANSI-C → bail
      out=""; mode=0; dbuf=""; n=length(buf)
      for(i=1;i<=n;i++){
        ch=substr(buf,i,1)
        if(mode==0){
          if(ch==BS){ out=out ch; i++; if(i<=n) out=out substr(buf,i,1) }   # \x → 2문자 verbatim
          else if(ch==SQ){mode=1; out=out ch}
          else if(ch==DQ){mode=2; dbuf=""; out=out ch}
          else out=out ch
        } else if(mode==1){                       # 싱글쿼트 본문 — 제거 (bash: 내부 이스케이프 없음)
          if(ch==SQ){mode=0; out=out ch}
        } else {                                  # 더블쿼트 본문
          if(ch==BS){ dbuf=dbuf ch; i++; if(i<=n) dbuf=dbuf substr(buf,i,1) }   # \" 경계 오닫힘 방지
          else if(ch==DQ){
            mode=0
            if(index(dbuf,"$(")>0 || index(dbuf,BT)>0) out=out dbuf   # 실행 가능 → 보존
            out=out ch
          } else dbuf=dbuf ch
        }
      }
      if(mode!=0){ printf "%s", buf; exit }       # 미종결 인용 → 원본 (fail-safe)
      printf "%s", out
    }
  ' 2>/dev/null) || { printf '%s' "$cmd"; return 0; }
  [ -n "$out" ] || { printf '%s' "$cmd"; return 0; }
  printf '%s' "$out"
}

# transcript JSONL 에서 최근 N 개 tool_use 이벤트를 추출
# 출력: JSONL, 각 줄 { "index": <0-based>, "tool_name": "...", "input": {...} }
#   index = 필터된 tool_use 이벤트 배열의 0-based 위치 (raw JSONL line 아님)
# NOTE: --slurp 로 JSONL 전체 메모리 로드. v0.1 transcript 크기 (≤1MB 가정) 에서 허용.
# 대형 세션은 `jq -cs '.[-N:]'` → head-cut 선처리 고려 (후속 과제).
# usage: read_recent_tool_events <transcript_path> <max_count>
read_recent_tool_events() {
  local transcript="$1"
  local max="${2:-20}"
  [ -f "$transcript" ] || return 0
  jq -c --slurp --argjson max "$max" '
    [ .[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | { tool_name: .name, input: .input } ]
    | to_entries
    | map({ index: .key, tool_name: .value.tool_name, input: .value.input })
    | .[-$max:][]?
  ' "$transcript"
}

# .specops 가 symlink 면 비정상(악성 repo clone 시 외부 dir 로 write-through path-escape) — 쓰기 거부.
# fail-safe: symlink 면 1(거부), 정상 dir·부재(곧 mkdir)면 0.
_specops_dir_safe() { [ ! -L ".specops" ]; }

# per-FID 디렉토리 symlink 거부 (빈 fid → 무검사 통과). detect_fid 1차 차단 위 defense-in-depth.
_specops_fid_dir_safe() { [ -z "${1:-}" ] || [ ! -L ".specops/$1" ]; }

# friction-log append. FID 우선 fallback 전역.
# usage: log_friction <fid_or_empty> <rule_id> <principle> <evidence_snippet> <transcript_offset> [scope_class]
#   6번째 인자는 **선택**이다 (20260813-friction-staged-record) — 기존 5-인자 호출부는 무수정으로
#   종전과 byte-identical 한 레코드를 낸다(빈 값이면 필드 자체를 생략, AC-6·AC-7).
log_friction() {
  local fid="$1" rule_id="$2" principle="$3" snippet="$4" offset="$5" scope_class="${6:-}"
  _specops_dir_safe || { echo "log_friction: .specops 가 symlink — 쓰기 거부(path-escape 차단)" >&2; return 1; }
  if [ -n "$fid" ] && ! grep -Eq '^[0-9]{8}-[a-z0-9-]+$' <<< "$fid"; then
    echo "log_friction: invalid fid format" >&2
    return 1
  fi
  _specops_fid_dir_safe "$fid" || { echo "log_friction: .specops/$fid 가 symlink — 거부" >&2; return 1; }
  local target
  if [ -n "$fid" ]; then
    mkdir -p ".specops/$fid"
    target=".specops/$fid/friction-log.jsonl"
  else
    mkdir -p ".specops"
    target=".specops/friction-log.jsonl"
  fi
  # 파일 symlink 가드: 디렉토리(_specops_fid_dir_safe)는 통과해도 friction-log.jsonl
  # *파일* 자체가 symlink 면 >> 가 따라가 외부 path 누출 — append 전 차단.
  [ ! -L "$target" ] || { echo "log_friction: $target 가 symlink — 거부" >&2; return 1; }
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local fid_json
  if [ -n "$fid" ]; then
    fid_json="\"$fid\""
  else
    fid_json="null"
  fi
  local safe_snippet
  safe_snippet=$(printf '%s' "$snippet" | cut -c1-200)
  # dedup: 같은 rule_id + evidence_snippet 조합이 이미 존재하면 skip (stop hook 중복 실행 방지)
  if [ -f "$target" ] && jq -e --arg r "$rule_id" --arg s "$safe_snippet" \
       'select(.rule_id == $r and .evidence_snippet == $s)' "$target" >/dev/null 2>&1; then
    return 0
  fi
  jq -nc \
    --arg ts "$ts" \
    --argjson fid "$fid_json" \
    --arg rule_id "$rule_id" \
    --argjson principle "$principle" \
    --arg snippet "$safe_snippet" \
    --argjson offset "$offset" \
    --arg sc "$scope_class" \
    '{ ts: $ts, fid: $fid, rule_id: $rule_id, principle: $principle, severity: "warn", evidence_snippet: $snippet, transcript_offset: $offset }
     + (if $sc == "" then {} else {scope_class:$sc} end)' \
    >> "$target"
}

# log_friction 의 severity 파라미터화 변형 (기존 log_friction 무변경 — append).
# usage: log_friction_sev <fid> <rule_id> <principle> <snippet> <offset> <severity> [scope_class]
#   7번째 인자는 **선택** (20260813-friction-staged-record) — 빈 값이면 필드를 생략한다(AC-6).
log_friction_sev() {
  local fid="$1" rule_id="$2" principle="$3" snippet="$4" offset="$5" severity="${6:-warn}" scope_class="${7:-}"
  _specops_dir_safe || { echo "log_friction_sev: .specops 가 symlink — 쓰기 거부(path-escape 차단)" >&2; return 1; }
  [ -n "$fid" ] || return 0
  if ! grep -Eq '^[0-9]{8}-[a-z0-9-]+$' <<< "$fid"; then
    echo "log_friction_sev: invalid fid format" >&2; return 1
  fi
  _specops_fid_dir_safe "$fid" || { echo "log_friction_sev: .specops/$fid 가 symlink — 거부" >&2; return 1; }
  local target=".specops/$fid/friction-log.jsonl"
  mkdir -p ".specops/$fid" 2>/dev/null || return 0
  # 파일 symlink 가드 (log_friction 과 대칭) — friction-log.jsonl 파일 symlink 추종 차단.
  [ ! -L "$target" ] || { echo "log_friction_sev: $target 가 symlink — 거부" >&2; return 1; }
  local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local fid_json; fid_json=$(printf '%s' "$fid" | jq -R .)
  local safe_snippet; safe_snippet=$(printf '%s' "$snippet" | cut -c1-200)
  # dedup 비대칭(의도): block 항목끼리만 비교 — 기존 warn 줄(log_friction, severity 무시)과 공존 허용.
  # 정상 흐름(pretool deny → posttool 미실행 / bypass → block 미기록)에선 동일 snippet 에 둘이 안 생긴다.
  # 집계 로직이 severity 별 카운트 시 엣지에서 동일 snippet 이중계상 가능 — block 강제 기록 우선.
  if [ -f "$target" ] && jq -e --arg r "$rule_id" --arg s "$safe_snippet" \
       'select(.rule_id == $r and .evidence_snippet == $s and .severity == "block")' "$target" >/dev/null 2>&1; then
    return 0
  fi
  jq -nc --arg ts "$ts" --argjson fid "$fid_json" --arg rule_id "$rule_id" \
    --argjson principle "$principle" --arg snippet "$safe_snippet" \
    --argjson offset "$offset" --arg sev "$severity" --arg sc "$scope_class" \
    '{ ts:$ts, fid:$fid, rule_id:$rule_id, principle:$principle, severity:$sev,
       evidence_snippet:$snippet, transcript_offset:$offset }
     + (if $sc == "" then {} else {scope_class:$sc} end)' \
    >> "$target"
}

# rules.jsonl 에서 matcher + enabled:true 룰만 반환
# usage: load_rules <rules_path> <matcher>
load_rules() {
  local rules_path="$1" matcher="$2"
  [ -f "$rules_path" ] || return 0
  jq -c --arg m "$matcher" 'select(.enabled == true and .matcher == $m)' "$rules_path"
}

# lookback 룰 매처. trigger 일치 + negative_skill_pattern 이 직전 N 이벤트에 없으면 매칭.
# usage: apply_lookback_rule <rule_json> <transcript> <tool_name> <tool_command>
# 출력: 매칭 시 JSON { rule_id, evidence_snippet, offset }, 미매칭 시 빈 문자열
apply_lookback_rule() {
  local rule="$1" transcript="$2" tool_name="$3" tool_cmd="$4"
  local rule_id trigger_tool trigger_pattern lookback neg_pattern
  rule_id=$(echo "$rule" | jq -r '.id')
  trigger_tool=$(echo "$rule" | jq -r '.trigger_tool')
  [ "$tool_name" = "$trigger_tool" ] || return 0
  trigger_pattern=$(echo "$rule" | jq -r '.trigger_pattern')
  # heredoc 본문 제거 후 검사 (AC-7) — 정규식은 무변경, **입력만** 전처리한다.
  #   $tool_cmd 원본은 보존한다: 아래 evidence_snippet 은 모델이 실제로 낸 명령 전문을 남겨야 감사 가치가 있다.
  local _scan_cmd
  _scan_cmd=$(_trigger_scan_text "$(_strip_heredoc_bodies "$tool_cmd")")
  grep -Eq "$trigger_pattern" <<< "$_scan_cmd" || return 0
  lookback=$(echo "$rule" | jq -r '.negative_lookback // 20')
  neg_pattern=$(echo "$rule" | jq -r '.negative_skill_pattern')
  # ★ 실행-근거 gate (20260713-verify-exec-gate): transcript 를 읽을 수 있으면, 어느 자기보고 신호가
  #   발화하든 실제 실행 증거를 요구한다. 자기보고 3경로(session-progress /verify PASS · evidence stamp ·
  #   Skill 호출)는 전부 **모델이 쓰는 것**이라, 검증했다고 착각한 모델이 선의로 게이트를 연다.
  #   #138 staleness 와 직교: staleness 는 "verify 가 충분히 최신인가", 본 gate 는 "verify 가 실제로 돌았나".
  #   ★ emit 은 기존 경로로 흘려보낸다(early-return 금지) — offset 계산을 선점하면 T6.e/f 회귀.
  # ★ detect_fid 는 아래에서 최대 2회 더 쓰인다(R-1 receipt 창·자기보고 면제). 훅 경로라
  #   지연이 체감에 직결돼(NFR-3) **1회만 부르고 재사용**한다 — 20260809 리뷰 지적.
  local _exec_rc _efid
  _efid=$(detect_fid 2>/dev/null || echo "")
  _verify_exec_evidence "$transcript" "${_efid:+.specops/$_efid}"; _exec_rc=$?

  # ★ R-1 implement 창: task receipt 필수 (Wave A — downstream-dogfood 병렬 wave BYPASS 관성 제거)
  #   tasks.md 존재 ∧ verify 미완료(_receipt_window_open) = implement 창.
  #   창 조건은 20260910 에 `evidence.md 부재` 에서 바뀌었다 — 그 파일은 /verify 전용이 아니라
  #   구현 중 태스크도 쓰므로, 먼저 쓴 태스크가 남은 태스크의 탈출구를 스스로 닫았다.
  #   FID 전체 VERIFY: PASS·실행증거 fallthrough 폐지는 그대로다(bffe021 의도 보존).
  #   유효 receipt(staged⊆outputs·tree 신선·test_command hash)만 면제. T# 없음·부재·무효 → deny.
  #   verify 유효 PASS 이후(창 닫힘)는 아래 자기보고/Skill lookback. R-2 는 receipt 로 열지 않는다.
  if [ "$rule_id" = "R-1" ]; then
    local _rfid _rtask _rrc
    _rfid="$_efid"          # 위에서 1회 구한 값 재사용 (detect_fid 중복 호출 제거)
    # ★ quick 구조(명세 없음 — 20261010-quick-fix-path)는 verify 상태와 무관하게 이 가지를 탄다. 창 조건만 보면
    #   quick FID 도 러너가 PASS 를 내는 순간 창이 닫혀, 범위·리뷰 판정(check-task-receipt 의 quick 절)이 불리지 않은 채
    #   아래 자기보고 면제로 열렸다(코드 리뷰 실측). 정식 FID(명세 있음)의 창 조건은 그대로다.
    if [ -n "$_rfid" ] && [ -f ".specops/$_rfid/tasks.md" ] && { _quick_structure "$_rfid" || _receipt_window_open "$_rfid"; }; then
      _rtask=$(_infer_commit_task "$tool_cmd")
      _rrc=2
      if [ -n "$_rtask" ] && [ -f "$_CHECK_TASK_RECEIPT_SH" ]; then
        bash "$_CHECK_TASK_RECEIPT_SH" "$_rfid" "$_rtask" >/dev/null 2>&1
        _rrc=$?
      fi
      # quick 구조의 커밋은 스테이징된 것만 커밋하는 명령이어야 한다 — 판정기는 스테이징을 보는데 `-a`·경로 인자는
      #   그 밖의 변경을 함께 커밋한다(코드 리뷰 실측). 정식 FID 는 종전 그대로다(새 return 을 두지 않고 rc 로 흘린다).
      if [ "$_rrc" -eq 0 ] && _quick_structure "$_rfid"; then
        _commit_scope_is_staged "$tool_cmd" || _rrc=5
      fi
      if [ "$_rrc" -eq 0 ]; then
        return 0
      fi
      # 창은 열렸는데 receipt 가 없거나(T# 미기재·파일 부재) 무효다. rc 의미는 check-task-receipt.sh:
      #   2 = receipt 파일 부재(또는 인자 부적합) · 1 = 파일은 있으나 무효(verdict·staged·tree).
      #   초기값 _rrc=2 라 T# 미기재도 여기로 떨어진다 — 없는 receipt 를 "무효" 라 부르면
      #   pretool 이 "staged 를 확인하라" 고 오안내한다(축 B 가 다시 거짓말하는 경로).
      local _cr
      _cr=$(_receipt_cause "$_rrc" "$tool_cmd" "$_rtask" "$_rfid" 2>/dev/null) || _cr="open-missing"
      _emit_violation "$rule_id" "$tool_cmd" \
        "$(_violation_offset "$transcript" "$trigger_tool" "$trigger_pattern")" \
        "$(_exec_cause "$_exec_rc")" \
        "$(_cause_anchor "$_rfid")" "$_cr"
      return 0
    fi
  fi

  # ★ 검증 이후 코드 변경 (20261009): 판정 SoT(verification-state)가 STALE 이면 자기보고로 열지 않는다.
  #   무효화는 transcript 의 Edit/Write 이벤트로만 봤다($lastedit) — `sed -i`·`echo >`·포매터·코드 생성기·
  #   서브에이전트의 수정은 그 이벤트가 없어, SoT 가 STALE 이라 답하는데도 진행 기록 한 줄로 커밋이 열렸다.
  #   R-1 한정: R-2 는 커밋 범위를 보고, 그 커밋들은 이 줄을 지나야 만들어진다. 상태 기록이 없는 FID 는 종전대로다.
  if [ "$rule_id" = "R-1" ] && [ -n "$_efid" ]; then
    _vs_verdict_cached "$_efid" >/dev/null 2>&1 || true
    if [ "${_VS_VERDICT_CACHE_FID:-}" = "$_efid" ] && [ "${_VS_VERDICT_CACHE:-}" = "STALE" ] \
       && _vs_stale_blocks "$_efid" "$tool_cmd"; then
      _emit_violation "$rule_id" "$tool_cmd" \
        "$(_violation_offset "$transcript" "$trigger_tool" "$trigger_pattern")" \
        "vstale" "$(_cause_anchor "$_efid")" "closed-verified"
      return 0
    fi
  fi

  # rc=0(실행증거 있음)·rc=2(판정 불가 — fail-open) 일 때만 자기보고 면제를 인정한다.
  # F-1(5c): session-progress verify 우선 — transcript lookback false-block 회피
  if [ "$_exec_rc" -ne 1 ]; then
    local _fid
    _fid="$_efid"           # 위에서 1회 구한 값 재사용 (detect_fid 중복 호출 제거)
    if [ -n "$_fid" ]; then
      _verify_passed_in_progress "$_fid"; local _vp=$?
      if [ "$_vp" -eq 0 ]; then
        return 0   # 유효 → 면제
      fi
      if [ "$_vp" -eq 1 ] && _verify_evidence_stamp "$_fid"; then
        return 0   # inconclusive(verify 줄 부재) + evidence stamp → 면제
      fi
      # _vp=2 (affirmative-stale) → stamp 무시, 차단 진행 (T39/spec L21 보존)
    fi
  fi
  local found=""
  if [ "$_exec_rc" -ne 1 ]; then
    found=$(read_recent_tool_events "$transcript" "$lookback" \
      | jq -c --arg p "$neg_pattern" 'select(.tool_name == "Skill" and (.input.skill // "" | test($p)))' \
      | head -1)
  fi
  if [ -z "$found" ]; then
    # offset = triggering Bash tool_use 이벤트의 transcript 라인 번호 (0-based). _violation_offset 이
    #   두 emit 경로의 공통 구현이다 — PostToolUse 는 triggering 이벤트 직후 발화하므로 마지막 매칭.
    # receipt 축: R-2 는 그 경로 자체가 없다(n/a). R-1 도 **FID·tasks.md 가 없으면 n/a** 다 —
    #   창이 "닫힌" 게 아니라 애초에 receipt 경로가 성립하지 않는다. 여기서 closed-verified 를
    #   찍으면 "② 앵커가 없습니다" 와 "verify 가 이미 유효 PASS 이므로" 가 동시에 나온다(모순).
    #   closed-verified 는 창 판정이 실제로 닫힘을 돌려준 경우로 한정한다.
    local _cr2="n/a"
    if [ "$rule_id" = "R-1" ] && [ -n "$_efid" ] && [ -f ".specops/$_efid/tasks.md" ]; then
      _receipt_window_open "$_efid" || _cr2="closed-verified"
    fi
    _emit_violation "$rule_id" "$tool_cmd" \
      "$(_violation_offset "$transcript" "$trigger_tool" "$trigger_pattern")" \
      "$(_exec_cause "$_exec_rc")" \
      "$(_cause_anchor "$_efid")" "$_cr2"
  fi
}

# ── receipt 창 판정 (20260910-receipt-window-close) ──────────────────────────
# 창 = "verify 가 아직 유효 PASS 에 도달하지 않은 구간". 종전엔 `evidence.md 부재` 였는데,
#   그 파일은 /verify 전용이 아니다 — 구현 중 실험 태스크가 쓰면 남은 태스크의 receipt 경로가
#   스스로 닫혔다(20260910 실측: T4 가 14:39 작성 → T5·T6 커밋이 전 경로 폐쇄 → BYPASS 2건).
# STALE 을 창에서 **제외**한다: 17f8617(20260828)이 "verify PASS 후 코드 수정은 차단하고
#   그렇게 말한다" 를 계약으로 세웠고, 여기서 열면 receipt 가 그 계약의 우회로가 된다.
# 반환: 0=열림(NOT_RUN|PARTIAL|FAIL) · 1=닫힘(PASS|STALE|WAIVED·판정불가 — 보수)
# 부수효과: $_VS_VERDICT_CACHE(+_FID)를 채워 같은 호출의 _verify_evidence_stamp 가 재사용한다(FR-7).
#   NFR-6: verdict/tree_hash 판정을 여기 복제하지 않는다 — verification-state.sh 가 SoT.
# 배치 메모: 이 블록이 apply_lookback_rule **뒤**에 있는 것은 mutation-equivalent.conf 가 절대 줄번호 키였던 때의
#   제약이다. 20261010 부터 키가 함수+줄 원문이라 옮겨도 등가 제외가 어긋나지 않는다(위치는 그대로 뒀다).
_receipt_window_open() {
  local fid="$1" verdict
  [ -n "$fid" ] || return 1
  _vs_verdict_cached "$fid" >/dev/null || return 1; verdict=${_VS_VERDICT_CACHE:-}
  case "$verdict" in
    NOT_RUN|PARTIAL|FAIL) return 0 ;;
    *) return 1 ;;
  esac
}

# verify 판정 조회 1회 캐시 (FR-7). 훅 hot path 에서 vs::current 가 두 번 도는 것을 막는다 —
#   그 명령은 verdict=PASS 경로에서 write-tree 를 돌려 ~109 ms(실측), state 부재면 ~6.3 ms.
#   FID 를 함께 태그한다: 같은 프로세스에서 다른 FID 를 조회했을 때 잔여값이 새면 안 된다.
#   NFR-6: verdict/tree_hash/WAIVED 만료 규칙을 여기 복제하지 않는다 — verification-state.sh 가 SoT.
#   호출 실패·빈 출력은 rc=1 로 돌려보내 호출측이 보수(닫힘) 판정하게 한다.
_vs_verdict_cached() {
  local fid="$1" verdict
  [ -n "$fid" ] || return 1
  if [ -n "${_VS_VERDICT_CACHE:-}" ] && [ "${_VS_VERDICT_CACHE_FID:-}" = "$fid" ]; then
    printf '%s' "$_VS_VERDICT_CACHE"; return 0
  fi
  [ -f "$_VERIFICATION_STATE_SH" ] || return 1
  verdict=$(SPECOPS_ROOT=".specops" bash "$_VERIFICATION_STATE_SH" current "$fid" 2>/dev/null) || return 1
  [ -n "$verdict" ] || return 1
  _VS_VERDICT_CACHE="$verdict"; _VS_VERDICT_CACHE_FID="$fid"
  printf '%s' "$verdict"
}

# 위반 이벤트의 transcript 줄번호(0-based). 두 emit 경로가 같은 jq 를 복제하고 있었다 — 통일한다.
_violation_offset() {
  local transcript="$1" trigger_tool="$2" trigger_pattern="$3" offset
  offset=$(jq -n --arg t "$trigger_tool" --arg pat "$trigger_pattern" '
    [inputs] as $all
    | ([ $all | to_entries[]
         | select(.value.type == "assistant")
         | select([.value.message.content[]? | select(.type == "tool_use" and .name == $t and ((.input.command // "") | test($pat)))] | any)
         | .key ] | last) // ($all | length)
  ' "$transcript" 2>/dev/null)
  [ -z "$offset" ] && offset=0
  printf '%s' "$offset"
}

# ② 앵커 축 진단 — 판정과 같은 함수를 부른다(사본 0). 판정에 관여하지 않는다.
#   _verify_passed_in_progress: 0=유효 · 1=verify 줄 부재(inconclusive) · 2=affirmative-stale
_cause_anchor() {
  local fid="$1"
  [ -n "$fid" ] || { printf 'no-fid'; return 0; }
  _verify_passed_in_progress "$fid"
  case $? in
    0) printf 'ok' ;;
    2) printf 'stale' ;;
    *) if _verify_evidence_stamp "$fid"; then printf 'ok'; else printf 'missing'; fi ;;
  esac
}

# 위반 emit — 기존 3필드 + cause 진단 3축. cause 는 **진단 전용**이라 allow/deny 를 바꾸지 않는다.
#   exec 은 ok|missing 2값만 낸다: stale 승격은 pretool 이 이미 호출하는 _verify_stale_cause 로
#   병합한다(그 함수는 20,109줄 transcript 에서 391 ms — 여기서 또 부르면 전수 스캔이 2회다).
_emit_violation() {
  local rule_id="$1" snippet="$2" offset="$3" c_exec="$4" c_anchor="$5" c_receipt="$6"
  jq -nc --arg id "$rule_id" --arg snippet "$snippet" --argjson offset "$offset" \
    --arg ce "$c_exec" --arg ca "$c_anchor" --arg cr "$c_receipt" \
    '{ rule_id: $id, evidence_snippet: $snippet, offset: $offset,
       cause: { exec: $ce, anchor: $ca, receipt: $cr } }'
}

# R-3 매처 — Skill 호출 직전 N assistant 메시지에 선언 부재 확인 (AC-9, v0.4-pre W1 확장)
# usage: apply_skill_declaration_rule <transcript> <skill_full_name>
# 선언 = 영문 "[Using|Invoking|Calling|Switching to] <short|full>" 또는
#        한국어 "<short> (을|를|로|으로)? (사용|호출|진입|이동|넘어감|시작|진행|발동|들어감|넘어가|개시)"
# short = skill_full_name 에서 "specops-ko:" 접두 제거
# v0.4-pre W1 변경 (마스터 plan §6 v0.4-pre):
# 1. 동사군 확장 (한국어 6 → 12, 영문 1 → 4)
# 2. lookback N=1 → N=3 assistant 메시지
# 3. user turn 첫 진입 예외 (직전 user 메시지에 /start 또는 트리거 키워드 있으면 면제)
# v0.4b W1 변경: full name (specops-ko:<short>) 패턴 추가 (cvt+b64 7건 회귀 원인)
# v0.5 W1 변경: lifecycle chain auto-call exempt — 직전 tool_use가 Skill(specops-ko:*)이면 면제
apply_skill_declaration_rule() {
  local transcript="$1" skill_full="$2"
  [ -f "$transcript" ] || return 0
  local short="${skill_full#specops-ko:}"
  # full name = specops-ko:<short>, short name = <short> — 둘 다 허용
  local name_re="(specops-ko:)?${short}"
  local decl_re="([Uu]sing[[:space:]]+${name_re}|[Ii]nvoking[[:space:]]+${name_re}|[Cc]alling[[:space:]]+${name_re}|[Ss]witching[[:space:]]+to[[:space:]]+${name_re}|${short}[[:space:]]*(을|를|로|으로)?[[:space:]]*(사용|호출|진입|이동|넘어감|시작|진행|발동|들어감|넘어가|개시))"
  # user turn 첫 진입 예외 트리거 (사용자 입력에 이 패턴이 있으면 첫 Skill 호출은 면제)
  local trigger_re='(/start|/quick|/free|만들[고어]|구현|추가|수정|fix|feature)'
  # perf: 단일 jq reduce 패스 — 줄단위 echo|jq fork ×4 루프 제거.
  # 상태: p1~p3(assistant text ring buffer, p1=최신), lu(마지막 user text),
  #       plc(직전 lifecycle skill — v0.5 chain 면제), matched/done/offset.
  # combined 구분자는 원 구현의 bash 리터럴 "\n"(역슬래시+n) 을 jq "\\n" 으로 보존.
  local res
  res=$(jq -nc --arg s "$skill_full" --arg decl "$decl_re" --arg trig "$trigger_re" '
    def utext: [.message.content // "" | if type == "string" then . else (.[]? | select(.type == "text") | .text) end] | first // "";
    def atext: [.message.content[]? | select(.type == "text") | .text] | join("\n");
    def has_target($s): [.message.content[]? | select(.type == "tool_use" and .name == "Skill" and .input.skill == $s)] | length > 0;
    def lc_skill: [.message.content[]? | select(.type == "tool_use" and .name == "Skill") | (.input.skill // "") | select(startswith("specops-ko:"))] | first // "";
    [inputs] as $all
    | reduce range(0; $all | length) as $i (
        {p1: "", p2: "", p3: "", lu: "", plc: "", matched: false, done: false, offset: 0};
        if .done then .
        else $all[$i] as $e
        | if ($e.type // "") == "user" then
            .lu = ($e | utext)
          elif ($e.type // "") != "assistant" then
            .
          elif ($e | has_target($s)) then
            .offset = ($i + 1)
            | .done = true
            | .matched = (
                if .plc != "" then false
                elif ((.p1 + "\\n" + .p2 + "\\n" + .p3) | test($decl)) then false
                elif (.lu != "" and (.lu | test($trig))) then false
                else true
                end)
          else
            (($e | lc_skill) as $l | if $l != "" then .plc = $l else . end)
            | (($e | atext) as $t
               | if $t != "" then .p3 = .p2 | .p2 = .p1 | .p1 = $t else . end)
          end
        end)
    | { matched, offset }
  ' "$transcript" 2>/dev/null)
  local matched offset
  matched=$(printf '%s' "$res" | jq -r '.matched' 2>/dev/null)
  offset=$(printf '%s' "$res" | jq -r '.offset' 2>/dev/null)
  [ -z "$offset" ] && offset=0
  if [ "$matched" = "true" ]; then
    jq -nc --arg id "R-3" --arg snippet "Skill($skill_full) 호출 전 선언 부재" --argjson offset "$offset" \
      '{ rule_id: $id, evidence_snippet: $snippet, offset: $offset }'
  fi
}

# R-4 매처 — transcript 에 assertion_pattern 존재 + test_runner_pattern 부재 → 매칭
# usage: apply_assertion_without_test_rule <rule_json> <transcript>
# 출력: 매칭 시 JSON { rule_id, evidence_snippet, offset }, 미매칭 시 빈 문자열
apply_assertion_without_test_rule() {
  local rule="$1" transcript="$2"
  [ -f "$transcript" ] || return 0
  local assertion_re test_runner_re
  assertion_re=$(echo "$rule" | jq -r '.assertion_pattern')
  test_runner_re=$(echo "$rule" | jq -r '.test_runner_pattern')
  # assertion 있는가? (assistant text 전수 조사)
  local has_assertion
  has_assertion=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$transcript" 2>/dev/null \
    | grep -Eo "$assertion_re" | head -1)
  [ -n "$has_assertion" ] || return 0
  # test runner 실행 있는가? (Bash tool_use input.command 전수 조사)
  local has_runner
  has_runner=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Bash") | .input.command // empty' "$transcript" 2>/dev/null \
    | grep -Eo "$test_runner_re" | head -1)
  if [ -z "$has_runner" ]; then
    # assertion 매칭된 가장 마지막 assistant text 이벤트의 라인 번호 (0-based)
    # Stop hook 이므로 최근 주장이 증거로 더 적합
    # perf: 단일 jq 패스 — 줄단위 echo|jq fork 루프 제거 (Stop 훅 매 발화 경로)
    local offset
    offset=$(jq -n --arg re "$assertion_re" '
      [inputs] as $all
      | ([ $all | to_entries[]
           | select(.value.type == "assistant")
           | select([.value.message.content[]? | select(.type == "text") | .text | test($re)] | any)
           | .key ] | last) // ($all | length)
    ' "$transcript" 2>/dev/null)
    [ -z "$offset" ] && offset=0
    jq -nc --arg id "R-4" --arg snippet "성공 주장 '$has_assertion' + test runner 실행 부재" --argjson offset "$offset" \
      '{ rule_id: $id, evidence_snippet: $snippet, offset: $offset }'
  fi
}

# advisor 실호출 증거 판정 (20260806) — R-5 자기보고 면제표 봉합
#
# advisor 는 **서버사이드 도구**라 transcript 에 일반 tool_use/tool_result 로 남지 않는다.
# 실측 기록 형태: assistant 메시지의 `server_tool_use`(name="advisor", id=srvtoolu_*) ↔
#   `advisor_tool_result`(tool_use_id 동일). 일반 tool_use 만 보던 코드로는 영원히 0건이라
#   이 형태를 직접 join 한다.
# critic-ask.sh 도 인정한다 — advisor 미연결 시의 **공식 fallback**(advisor-ko §외부 모델 위탁)이라
#   이를 불인정하면 정직한 미연결 세션이 위반으로 찍힌다.
# 반환: 0=실호출 증거 있음 / 1=없음 / 2=판정 불가(fail-open)
_advisor_exec_evidence() {
  local transcript="$1"
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 2
  command -v jq >/dev/null 2>&1 || return 2
  local out
  out=$(jq -rn --slurpfile a "$transcript" '
    ([ $a[] | .message?.content? | select(type=="array") | .[] ]) as $blk
    # 이벤트 0건 = "호출 안 했다"와 "transcript 를 못 읽었다"를 구별 불가 → 판정 불가
    | ($blk | length) as $n
    | if $n == 0 then "UNKNOWN"
      else
        ([ $blk[] | select(.type=="server_tool_use" and .name=="advisor") | .id ]) as $calls
        | ([ $blk[] | select(.type=="advisor_tool_result" and (.is_error != true)) | .tool_use_id ]) as $oks
        | ([ $calls[] | select(. as $c | $oks | index($c)) ] | length) as $adv
        # critic-ask 공식 fallback
        | ([ $blk[] | select(.type=="tool_use" and .name=="Bash"
                             and ((.input.command // "") | test("critic-ask\\.sh"))) | .id ]) as $ccalls
        | ([ $blk[] | select(.type=="tool_result" and (.is_error != true)) | .tool_use_id ]) as $coks
        | ([ $ccalls[] | select(. as $c | $coks | index($c)) ] | length) as $crit
        | if ($adv + $crit) > 0 then "HIT" else "MISS" end
      end
  ' "$transcript" 2>/dev/null) || return 2
  case "$out" in
    HIT) return 0 ;;
    MISS) return 1 ;;
    *) return 2 ;;
  esac
}

# R-5 매처 — 세션 중 수정된 spec/plan/analysis md 의 Advisor 협의 기록 섹션 검사
# usage: apply_advisor_section_rule <rule_json> <transcript>
# PASS 조건: (a) 섹션 내 "해당 없음"(정직 선언 — 원칙 5) 또는
#            (b) data row 1+ **이면서** transcript 에 advisor/critic-ask 실호출 증거
# 매칭 조건: target_files 중 하나라도 위 PASS 조건 미충족
# 자기보고 봉합(20260806): 종전엔 data row 존재만으로 통과해 모델이 표를 쓰면 스스로 면제됐다.
#   R-1/R-2 실행-근거 게이트와 동형으로 "협의했다" 주장에는 실호출 증거를 요구한다.
#   판정 불가(rc=2)는 fail-open — 기존 관대 동작 유지.
apply_advisor_section_rule() {
  local rule="$1" transcript="$2"
  [ -f "$transcript" ] || return 0
  local target_files section_re
  target_files=$(echo "$rule" | jq -r '.target_files[]')
  section_re=$(echo "$rule" | jq -r '.advisor_section_pattern')
  # 세션 중 Edit/MultiEdit 된 파일 경로 추출 (Write는 신규 생성 — Advisor 섹션 불필요)
  local modified_files
  modified_files=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and (.name == "Edit" or .name == "MultiEdit")) | .input.file_path // empty' "$transcript" 2>/dev/null | sort -u)
  local match_result=""
  local fp bn is_target section_body data_rows has_hae
  # while-read — 공백 포함 경로 안전 (unquoted word-split 제거)
  while IFS= read -r fp; do
    [ -z "$fp" ] && continue
    bn=$(basename "$fp")
    is_target=0
    while IFS= read -r t; do
      [ "$bn" = "$t" ] && is_target=1
    done <<EOF_T
$target_files
EOF_T
    [ "$is_target" -eq 1 ] || continue
    [ -f "$fp" ] || continue
    # U1 R-5 trivial-skip: 동일 FID 의 spec.md §유형 라벨이 trivial 이면 본 파일 skip
    # specifying-ko 가 §1 개요에 자동 부여한 라벨 사용 (신규/유지보수/trivial).
    # spec.md 부재 시 보수적으로 기존 로직 진입 (false positive < silent pass).
    local _dir _spec _type_label
    _dir=$(dirname "$fp")
    _spec="$_dir/spec.md"
    if [ -f "$_spec" ]; then
      _type_label=$(grep -m1 '^\*\*§유형\*\*:' "$_spec" 2>/dev/null | sed 's/.*:[[:space:]]*//' | tr -d '[:space:]')
      if [ "$_type_label" = "trivial" ]; then
        continue
      fi
    fi
    # Advisor 섹션 본문 추출: section_re 이후 ~ 다음 ## 직전
    section_body=$(awk -v re="$section_re" '
      $0 ~ re { inside=1; next }
      inside && /^## / { exit }
      inside { print }
    ' "$fp")
    if [ -z "$section_body" ]; then
      match_result="섹션 부재: $fp"
      break
    fi
    # data row: | 로 시작, 헤더(`| 일시`)·구분선(`|---` 또는 `| --- |`) 제외
    data_rows=$(printf '%s\n' "$section_body" | grep -E '^\|' | grep -Ev '^\|[[:space:]]*-+' | grep -Ev '^\|[[:space:]]*일시[[:space:]]*\|' | wc -l | tr -d ' ')
    has_hae=$(printf '%s\n' "$section_body" | grep -c '해당 없음' | tr -d ' ')
    if [ "$data_rows" -eq 0 ] && [ "$has_hae" -eq 0 ]; then
      match_result="섹션 미충족: $fp"
      break
    fi
    # 협의를 **주장**하면(data row 1+, "해당 없음" 아님) 실호출 증거를 요구한다
    if [ "$data_rows" -gt 0 ] && [ "$has_hae" -eq 0 ]; then
      _advisor_exec_evidence "$transcript"
      case $? in
        1) match_result="협의 기록 있으나 advisor 실호출 증거 없음: $fp"; break ;;
        *) : ;;   # 0=증거 있음 · 2=판정 불가(fail-open)
      esac
    fi
  done <<EOF_M
$modified_files
EOF_M
  if [ -n "$match_result" ]; then
    # match_result 에 해당하는 파일 경로 추출 ("섹션 부재: <fp>" 또는 "섹션 미충족: <fp>")
    local matched_file=""
    if [[ "$match_result" == *": "* ]]; then
      matched_file="${match_result##*: }"
    fi
    # 첫 Edit/MultiEdit 이벤트 (target file 대상) 의 transcript 라인 번호 (0-based)
    # perf: 단일 jq 패스 — 줄단위 echo|jq fork 루프 제거.
    # 원 동작 보존: matched_file 비면 0, 매칭 파일은 있으나 이벤트 미발견이면 전체 라인 수.
    local offset=0
    if [ -n "$matched_file" ]; then
      offset=$(jq -n --arg p "$matched_file" '
        [inputs] as $all
        | ([ $all | to_entries[]
             | select(.value.type == "assistant")
             | select([.value.message.content[]? | select(.type == "tool_use" and (.name == "Edit" or .name == "MultiEdit") and .input.file_path == $p)] | any)
             | .key ] | first) // ($all | length)
      ' "$transcript" 2>/dev/null)
      [ -z "$offset" ] && offset=0
    fi
    jq -nc --arg id "R-5" --arg snippet "$match_result" --argjson offset "$offset" \
      '{ rule_id: $id, evidence_snippet: $snippet, offset: $offset }'
  fi
}

# R-6 매처 — transcript 에 verify skill + evidence.md Write 있고 gbrain-append 부재 시 매칭
# usage: apply_gbrain_absence_rule <rule_json> <transcript>
# 출력: 매칭 시 JSON { rule_id, evidence_snippet, offset, fid }, 미매칭 시 빈 문자열
# 매칭 알고리즘:
#   1. verify skill 호출 흔적 (전수 조사) 없으면 skip
#   2. 가장 최근 evidence.md Write 의 line 위치 추출 (last_evi_line). 없으면 skip
#   3. last_evi_line 이후 gbrain runner 호출 있는가? 있으면 PASS (skip)
#      — FR-6: multi-verify 환경에서도 가장 최근 evidence 이후만 본다
#   4. trivial-skip: evidence path 의 .specops/<FID>/spec.md 의 §유형 = trivial 이면 skip
#   5. FID 추출 + evidence_snippet 빌드 + JSON 반환
# 한계: trivial-skip(step 4) 의 spec.md lookup 은 transcript 에서 파생된 evidence path
#   (대개 상대경로 .specops/<FID>/evidence.md) 의 dirname 기준이라 **CWD 의존**이다.
#   훅이 plugin repo root 가 아닌 CWD 에서 실행되면 spec.md 를 못 찾아 trivial 판정이
#   누락(= 매칭 유지)될 수 있다. Stop 훅은 항상 repo root 에서 기동되므로 실사용엔 무해.
apply_gbrain_absence_rule() {
  local rule="$1" transcript="$2"
  [ -f "$transcript" ] || return 0
  local verify_skill_re evidence_path_re gbrain_runner_re
  verify_skill_re=$(echo "$rule" | jq -r '.verify_skill_pattern')
  evidence_path_re=$(echo "$rule" | jq -r '.evidence_path_pattern')
  gbrain_runner_re=$(echo "$rule" | jq -r '.gbrain_runner_pattern')

  # 1. verify skill 호출 흔적
  local has_verify
  has_verify=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Skill") | .input.skill // empty' "$transcript" 2>/dev/null \
    | grep -E "$verify_skill_re" | head -1)
  [ -n "$has_verify" ] || return 0

  # 2.+3. 가장 최근 evidence.md Write/Edit/Bash-invocation 위치 + 그 이후 gbrain runner 존재 여부
  # Edit 도 포함 — Claude 가 run-verification.sh append 후 헤더/AC 매핑 추가할 때 Edit 사용 (외부 review 후속 fix)
  # Bash 분기 — dogfood 경로 (bash scripts/_internal/run-verification.sh <FID>) invocation 도 evidence 의도 인정
  # perf: 단일 jq 패스 — transcript 2회 완주 + 줄단위 fork 루프 제거.
  # same-turn Write+Bash 의 Bash-우선 순서 (T-R6.17) 는 라인 내 bsynth 우선 평가로 보존.
  local res
  res=$(jq -nc --arg evire "$evidence_path_re" --arg grun "$gbrain_runner_re" '
    def wpath: [.message.content[]? | select(.type == "tool_use" and (.name == "Write" or .name == "Edit")) | (.input.file_path // "") | select(test($evire))] | first // "";
    def bsynth: [.message.content[]? | select(.type == "tool_use" and .name == "Bash") | (.input.command // "")
                 | (capture("bash[[:space:]]+(?:.*/)?run-verification\\.sh[[:space:]]+(?<fid>[^[:space:]]+)")? // empty)
                 | ".specops/" + .fid + "/evidence.md"
                 | select(test($evire))] | first // "";
    def grunner: [.message.content[]? | select(.type == "tool_use" and (.name == "Bash" or .name == "Skill")) | (.input.command // .input.skill // "") | select(test($grun))] | length > 0;
    [inputs] as $all
    | ($all | to_entries | map(select(.value.type == "assistant"))) as $ents
    | ([ $ents[] | { i: .key, p: ((.value | bsynth) as $b | if $b != "" then $b else (.value | wpath) end) } | select(.p != "") ] | last) as $evi
    | if $evi == null then { evi: -1, path: "", gb: false }
      else { evi: $evi.i, path: $evi.p, gb: ([ $ents[] | select(.key > $evi.i) | select(.value | grunner) ] | length > 0) }
      end
  ' "$transcript" 2>/dev/null)
  local last_evi_line last_evi_path has_gbrain_after
  last_evi_line=$(printf '%s' "$res" | jq -r '.evi' 2>/dev/null)
  last_evi_path=$(printf '%s' "$res" | jq -r '.path' 2>/dev/null)
  has_gbrain_after=$(printf '%s' "$res" | jq -r '.gb' 2>/dev/null)
  if [ -z "$last_evi_line" ] || [ "$last_evi_line" -lt 0 ]; then
    return 0
  fi
  [ "$has_gbrain_after" = "true" ] && return 0  # PASS — gbrain 호출 있음

  # 4. trivial-skip — evidence path 의 spec.md §유형 = trivial 이면 skip
  local fid_dir spec_path type_label
  fid_dir=$(dirname "$last_evi_path")
  spec_path="$fid_dir/spec.md"
  if [ -f "$spec_path" ]; then
    type_label=$(grep -m1 '^\*\*§유형\*\*:' "$spec_path" 2>/dev/null | sed 's/.*:[[:space:]]*//' | tr -d '[:space:]')
    [ "$type_label" = "trivial" ] && return 0
  fi

  # 5. FID 추출 (.specops/<FID>/evidence.md 패턴)
  local fid
  fid=$(echo "$last_evi_path" | sed -E 's|.*\.specops/([^/]+)/evidence\.md$|\1|')

  local snippet="lifecycle 완주 후 gbrain-append 호출 부재 — 1줄 인사이트 작성 권장: bash \"$_GOV_LIB_DIR/../scripts/gbrain-append.sh\" '<insight>' --fid $fid"
  jq -nc --arg id "R-6" --arg snippet "$snippet" --argjson offset "$last_evi_line" --arg fid "$fid" \
    '{ rule_id: $id, evidence_snippet: $snippet, offset: $offset, fid: $fid }'
}

# ── R-1 receipt 원인 진단 (20261001-task-id-guard) — 진단 전용, deny/허용 판정 불변 ──
# ★ 이 헬퍼들이 **파일 끝**에 있는 것은 mutation-equivalent.conf 가 이 파일을 절대 줄번호로 핀하던 때의 제약이다
#   (앞쪽에 줄을 넣으면 핀이 밀려 등가변이 제외가 무음으로 엉뚱한 가드에 붙었다). 20261010 부터 키가 함수+줄 원문이라
#   그 제약은 없다. 함수는 source 시 정의만 되고 런타임에 호출되므로 정의 위치는 동작과 무관하다.

# 커밋 명령에서 `Task:` 뒤 선언 토큰 전체 — `_infer_commit_task` 는 T숫자 로 자르므로(T1a→T1)
#   잘리기 전 원문을 본다. 마침표는 토큰에서 제외(`T12.`). 없으면 빈 문자열. 진단 전용.
#   한계: 첫 `Task:` 토큰만 집는다(두 번 선언하면 첫 값 기준 — 진단 전용이라 피해는 문안에 한정).
_declared_task_token() {
  printf '%s' "${1:-}" | grep -oE 'Task:[[:space:]]*[A-Za-z0-9_-]+' | head -1 | sed -E 's/^Task:[[:space:]]*//'
}
# tasks.md 에 해당 task id 줄이 있는가 — 0=있음 · 1=id 줄은 있으나 이 id 없음 · 2=판정불가(파일 부재/읽기 불가/id 줄 0건)
#   id 는 `_infer_commit_task` 반환값(T숫자)만 들어오므로 정규식에 안전하다. YAML 파서 대신 grep —
#   훅 hot path 라 python 기동을 피한다. 따옴표·인라인 주석 변형을 허용한다.
_tasks_has_id() {
  local f="${1:-}" id="${2:-}"
  [ -r "$f" ] && [ -n "$id" ] || return 2
  grep -qE '^[[:space:]]*-[[:space:]]+id:' "$f" 2>/dev/null || return 2
  grep -qE "^[[:space:]]*-[[:space:]]+id:[[:space:]]*[\"']?${id}[\"']?[[:space:]]*(#.*)?\$" "$f" 2>/dev/null && return 0
  return 1
}
# R-1 receipt 분기의 원인 코드 — $1=_rrc $2=tool_cmd $3=_rtask $4=_rfid.
#   stdout 으로 open-invalid | open-id-mismatch | open-missing 중 정확히 하나를 낸다.
#   receipt rc=1(무효)은 open-invalid 우선. 그 밖의 실패·판정불가는 전부 종전 open-missing.
_receipt_cause() {
  local rrc="${1:-2}" cmd="${2:-}" rtask="${3:-}" rfid="${4:-}" decl hid_rc=0
  # quick 경로(명세 없는 FID)의 영수증 검사 결과 — 영수증 자체는 유효한데 범위·리뷰가 걸렸다 (20261010-quick-fix-path).
  #   "무효" 로 뭉개면 "staged 를 확인하라" 는 거짓 안내가 나간다.
  case "$rrc" in
    3) printf 'quick-over'; return 0 ;;
    4) printf 'quick-noreview'; return 0 ;;
    5) printf 'quick-unstaged'; return 0 ;;
  esac
  if [ "$rrc" -eq 1 ] 2>/dev/null; then
    printf 'open-invalid'; return 0
  fi
  decl=$(_declared_task_token "$cmd" 2>/dev/null || true)
  if [ -n "$decl" ] && [ "$decl" != "$rtask" ]; then
    printf 'open-id-mismatch'; return 0
  fi
  if [ -n "$rtask" ]; then
    _tasks_has_id ".specops/$rfid/tasks.md" "$rtask" || hid_rc=$?
    if [ "$hid_rc" -eq 1 ]; then
      printf 'open-id-mismatch'; return 0
    fi
  fi
  printf 'open-missing'
}
# quick 구조 — 명세(spec.md)가 없는 FID. tasks.md 존재를 이미 확인한 자리(R-1 영수증 가지)에서만 부른다.
_quick_structure() { [ ! -f ".specops/${1:-}/spec.md" ]; }
# pretool deny 안내의 receipt 원인 문안 — $1=cause 코드 $2=tool_cmd. 알 수 없는 cause(n/a 등)는 빈 출력.
#   pretool 의 `*)` case 한 줄이 부른다 — 문안 본체를 여기(파일 끝)에 두어 pretool·lib 의 줄번호 핀을 보존한다.
#   ★ 실제로 일어난 일만 말한다(거짓 원인 → 재시도 낭비·BYPASS): 절단은 선언이 해석 id 로 **시작**할 때만이다.
#     `Task: fix …` + 산문 `(T1)` 처럼 해석 id 가 산문 fallback 에서 왔으면 절단이 아니다.
_receipt_hint_extra() {
  local cause="${1:-}" cmd="${2:-}" hfid="${3:-}" decl infer why
  # quick 경로 — 판정기에게 어느 기준에 걸렸는지 다시 묻는다(거부 경로에서만 1회 더 돈다). $3=FID.
  case "$cause" in
    quick-unstaged)
      printf '%s' "
▶ quick 커밋 범위 — 이 명령이 스테이징된 것만 커밋하는지 확인할 수 없습니다(\`-a\`·\`--all\`·경로 인자·다른 명령과 묶음·명령 치환).
   quick 경로의 범위·리뷰 판정은 스테이징된 변경을 봅니다. 커밋할 파일만 git add 한 뒤(별도 호출)
   \`git commit -m …\` 만 따로 실행하세요. 여러 줄 메시지는 \`git commit -F - <<'EOF'\` 형태로 씁니다
   (메시지를 명령 치환으로 넣는 \`-m \"\$(cat <<'EOF' …)\"\` 형태는 막힙니다)."
      return 0 ;;
    quick-over|quick-noreview)
      infer=$(_infer_commit_task "$cmd" 2>/dev/null || true)
      why=$(bash "$_QUICK_SCOPE_SH" "$hfid" "${infer:-T1}" --explain 2>/dev/null | head -1)
      case "$cause:$why" in
        quick-over:"판정 불가"*)
          # 판정기가 판정하지 못했다(막는 쪽) — 범위를 넘었다고 말하지 않고 /maintain-lite 로 보내지 않는다
          printf '%s' "
▶ quick 판정 불가 — ${why#판정 불가 — }.
   범위를 넘은 것이 아니라 판정 자체를 하지 못했습니다 — 판정할 수 없으면 막습니다.
   위 원인을 고친 뒤 영수증을 다시 남기고(quick-fix.sh seal) 커밋하세요." ;;
        quick-over:*)
          printf '%s' "
▶ quick 범위 초과 — ${why:-사유 조회 실패}.
   이 FID 는 명세 없이 태스크 문서만 있는 quick 경로입니다. quick 은 작고(구현 파일 수·변경 줄 수 상한 — 테스트·문서 제외)
   고위험 신호(인증·마이그레이션·스키마·공개 API·화면/인터페이스 문서)가 없는 수정만 받습니다.
   이 수정은 /maintain-lite <설명> 으로 진행하세요 — 고친 내용은 작업 트리에 그대로 남습니다." ;;
        *)
          printf '%s' "
▶ quick 리뷰 미충족 — ${why:-사유 조회 실패}.
   code-reviewer-ko 를 'quick 경로: yes' 로 1회 호출해 통과 판정을 받으세요(보고서: .specops/${hfid:-<FID>}/reviews/${infer:-T1}-C-report.md).
   리뷰 뒤에 코드를 다시 고쳤으면 리뷰도 다시 받아야 합니다. 그다음 영수증을 다시 남기고(quick-fix.sh seal) 커밋하세요." ;;
      esac
      return 0 ;;
  esac
  [ "$cause" = "open-id-mismatch" ] || return 0
  decl=$(_declared_task_token "$cmd" 2>/dev/null || true)
  infer=$(_infer_commit_task "$cmd" 2>/dev/null || true)
  if [ -n "$decl" ] && [ -z "$infer" ]; then
    # (a0) 선언은 있는데 T숫자 로 해석되지 않았다(예: task-3) — 절단이 아니라 미해석이다.
    printf '%s' "
▶ receipt 경로가 열리지 않는 원인: 커밋 메시지의 Task: ${decl} 가 task id 로 해석되지 않았습니다.
   task id 는 숫자 전용(T1~Tn)입니다 — tasks.md 의 id 를 확인하고 커밋 메시지를 그 숫자 id 로 맞추세요(예: Task: T1)."
  elif [ -n "$decl" ] && [ "$decl" != "$infer" ]; then
    case "$decl" in
      "$infer"*)
        # (a) 선언 토큰이 해석 과정에서 잘렸다(T1a → T1) — 절단을 원인으로 말한다.
        printf '%s' "
▶ receipt 경로가 열리지 않는 원인: 커밋 메시지의 task id 가 tasks.md 의 id 와 일치하지 않습니다.
   커밋 메시지 선언: Task: ${decl}  →  훅이 해석한 id: ${infer}
   task id 는 숫자 전용(T1~Tn)입니다 — T1a 같은 접미사는 T1 로 잘려 존재하지 않는 receipt 를 찾습니다.
   tasks.md 의 id 를 확인하고 커밋 메시지를 그 숫자 id 로 맞추세요(예: Task: T1).
   tasks.md 에 접미사 id 가 있으면 T숫자로 재명명한 뒤 emit-context 를 재실행하세요." ;;
      *)
        # (a1) 선언이 T숫자 형식이 아니고, 해석 id 는 본문 산문에서 왔다 — 절단은 일어나지 않았다.
        printf '%s' "
▶ receipt 경로가 열리지 않는 원인: 커밋 메시지의 Task: ${decl} 는 task id 형식(T숫자)이 아니며, 훅은 본문의 다른 id(${infer})로 해석했습니다.
   선언과 해석이 다르면 receipt 를 신뢰할 수 없습니다 — Task: 줄을 tasks.md 의 숫자 id 로 쓰세요(예: Task: T1, task id 는 숫자 전용 T1~Tn)." ;;
    esac
  elif [ -n "$decl" ]; then
    # (b) 선언=해석인데 tasks.md 에 그 id 가 없다 — 절단은 일어나지 않았다.
    printf '%s' "
▶ receipt 경로가 열리지 않는 원인: tasks.md 에 해당 task id(${infer})가 없습니다.
   커밋 메시지의 Task: 값이 tasks.md 의 id 와 정확히 일치해야 receipt 를 찾을 수 있습니다.
   tasks.md 의 id 목록을 확인하고 커밋 메시지를 그 id 로 맞추세요(task id 는 숫자 전용 T1~Tn)."
  else
    # (b') 선언 없음 — 훅이 본문 산문에서 id 를 집었다. 존재하지 않는 Task: 줄을 언급하지 않는다.
    printf '%s' "
▶ receipt 경로가 열리지 않는 원인: tasks.md 에 해당 task id(${infer:-(없음)})가 없습니다.
   커밋 메시지에 Task: 선언이 없어 훅은 본문의 산문 id(${infer:-(없음)})를 task id 로 집었습니다.
   tasks.md 의 숫자 id 를 확인하고 커밋 메시지에 그 id 를 Task: T숫자 형식으로 명시하세요(예: Task: T1)."
  fi
}

# ── BYPASS 사유 분류 (면제 남용 축소 1 — 기록만, 판정 불변) ──────────────────
# 왜: 자유서술 사유만 쌓이면 "우회 횟수"만 남는 무정보 감사가 된다(20260716 지적).
#   분류는 판정을 바꾸지 않는다 — deny/allow 조건은 그대로, friction-log snippet 선두에
#   cat=<분류> 를 붙여 gbrain-friction 집계 축을 만든다. 미분류는 unclassified 로 둔다
#   (형식 함정 false-deny 금지 — 분류 실패가 우회를 막지 않는다).
# 카테고리: [implement-commit] 태스크 중간 커밋 · [session-boundary] 세션 경계 재검증 ·
#   [stale-reverify] stale 후 재실행 회피 · [tool-limit] 도구·훅 한계 · [urgent] 긴급 hotfix ·
#   그 외 unclassified. 대괄호 없이 써도 키워드로 추정한다(추정 실패=unclassified).
_bypass_category() {  # <reason> → 분류 토큰
  local r="${1:-}" low
  low=$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')
  # 명시 태그([분류])는 키워드 추정보다 우선한다 — 추정 키워드(session·implement 등)가 태그를 가로채지 않게 선검사.
  case "$low" in
    *"[implement-commit]"*) echo "implement-commit"; return 0 ;;
    *"[session-boundary]"*) echo "session-boundary"; return 0 ;;
    *"[stale-reverify]"*) echo "stale-reverify"; return 0 ;;
    *"[tool-limit]"*) echo "tool-limit"; return 0 ;;
    *"[urgent]"*) echo "urgent"; return 0 ;;
  esac
  case "$low" in
    *"[implement-commit]"*|*"중간 커밋"*|*"태스크"*"커밋"*|*"implement"*|*"receipt"*) echo "implement-commit" ;;
    *"[session-boundary]"*|*"세션"*|*"session"*) echo "session-boundary" ;;
    *"[stale-reverify]"*|*"stale"*|*"스태일"*) echo "stale-reverify" ;;
    *"[tool-limit]"*|*"도구 한계"*|*"훅 한계"*|*"jq"*|*"판정 불가"*) echo "tool-limit" ;;
    *"[urgent]"*|*"긴급"*|*"hotfix"*|*"핫픽스"*) echo "urgent" ;;
    *) echo "unclassified" ;;
  esac
}

# ── fail-open degraded 기록 (면제 남용 축소 3 — 기록만, allow 불변) ───────────
# 왜: 판정 불가(jq·rules·trigger 로드 실패 등)가 무음으로 allow 되면 "보호 중" 착각을
#   만든다. allow 는 유지하고(차단은 verify 누락 판정 시에만 — fail-open 계약) repo 레벨
#   friction-log(.specops/friction-log.jsonl, fid 없음)에 degraded 1줄을 남긴다.
#   .specops 부재면 기록 자체가 월권이므로 스킵한다. 모든 실패는 || true 로 삼킨다.
_log_degraded() {  # <rule_id> <snippet> → 0 항상(기록 실패해도 호출자 흐름 불변)
  local rid="${1:-GOVERNANCE-DEGRADED}" snip="${2:-}"
  [ -d ".specops" ] || return 0
  declare -F log_friction >/dev/null 2>&1 || return 0
  log_friction "" "$rid" 1 "$snip" 0 2>/dev/null || true
  return 0
}

# ── "이 명령은 PR 생성인가" 의 단일 표기 (20261009) ───────────────────────────
# R-2 트리거가 `gh pr -R o/r create`·`gh -R o/r pr create` 를 인식하게 된 뒤에도, 그 뒤에 서는 세 판정
#   (PR 범위로 볼 것인가 `_cmd_is_pr_create_only` · batch 게이트 · release-ready 게이트)은 저마다 `gh pr create` 를
#   글자 그대로 찾았다 — 인식은 되는데 PR 범위가 아니라 작업트리로 판정돼, 문서 하나만 dirty 면 커밋된 미검증 코드의
#   PR 이 면제됐다. 세 곳이 이 한 정규식을 쓴다(명령 위치 앵커 없음 — 트리거가 이미 걸러 준 입력을 받는다).
_PR_CREATE_FLAG='((-R|--repo)[[:space:]]+[^[:space:]]+[[:space:]]+|--repo=[^[:space:]]+[[:space:]]+)*'
_PR_CREATE_RE="gh[[:space:]]+${_PR_CREATE_FLAG}pr[[:space:]]+${_PR_CREATE_FLAG}create"

# ── 줄 연속 잇기 (20261009) ───────────────────────────────────────────────────
# `git \` + 개행 + `commit` 은 한 명령인데 트리거 grep 은 줄 단위라 둘로 보고 놓쳤다. 역슬래시-개행을 공백으로 바꾼다.
#   인용 문자열 안의 역슬래시-개행도 함께 바뀌지만 그 본문은 뒤이은 _strip_quoted_strings 가 지운다.
#   빠른 경로 — 해당 표기가 없으면 바이트 동일 반환.
_join_line_continuations() {
  local nl=$'\n'
  case "$1" in *\\"$nl"*) printf '%s' "${1//\\$nl/ }" ;; *) printf '%s' "$1" ;; esac
}

# ── 꺼진 차단 훅의 흔적 (20261009) ────────────────────────────────────────────
# 인라인 우회는 사유를 요구하고 기록되는데, `.specops/config.yaml` 한 줄로 끄는 길은 아무 기록도 남기지 않았다.
#   그 파일은 모델도 쓸 수 있고 문서 면제 클래스다. 끄는 것은 막지 않는다(사용자 주권) — 꺼진 채 커밋·PR 이
#   나갔다는 사실만 repo 레벨 friction-log 에 남긴다. 커밋·PR 이 아닌 명령과 `.specops/` 없는 저장소에는 남기지 않는다.
#   stdin: PreToolUse JSON · $1 = 플러그인 루트. 모든 실패는 무음(호출자는 어차피 allow 한다).
_note_governance_disabled() {
  local root="${1:-}" input cmd re
  command -v jq >/dev/null 2>&1 || return 0
  input=$(cat 2>/dev/null) || return 0
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || return 0; fi
  [ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || return 0
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  re=$(jq -rs '[.[]|select(.id=="R-1" or .id=="R-2")|.trigger_pattern|select(.!=null)]|join("|")' "$root/hooks/rules.jsonl" 2>/dev/null)
  [ -n "$cmd" ] && [ -n "$re" ] || return 0
  grep -Eq "$re" <<< "$(_trigger_scan_text "$(_strip_heredoc_bodies "$cmd")")" || return 0
  # `.specops/` 없는 저장소에는 남기지 않는다 — 그 판정은 _log_degraded 가 한다(관할 한정).
  #   차단 훅은 설정 파일로만 꺼진다 — 프로파일 환경변수(strict·standard·minimal)는 셋 다 이 훅을 켠 채 둔다.
  _log_degraded "GOVERNANCE-DISABLED" "pretool-governance 가 꺼진 상태에서 실행(.specops/config.yaml 의 hooks 설정): ${cmd:0:100}"
}

# ── 트리거 판정용 문자열 (20261009) ───────────────────────────────────────────
# 줄 연속을 이은 문자열과 **잇지 않은 원문**을 둘 다 낸다 — grep 은 어느 쪽에 걸려도 트리거다.
#   이은 것만 보면 종전에 막히던 실커밋이 열린다: 주석 줄 끝의 `\` 와 `\\`(이스케이프된 역슬래시)는 줄을 잇지 않아
#   다음 줄의 `git commit` 이 실제로 실행되는데, 이으면 앞 줄 뒤에 붙어 명령 자리를 잃는다. 셸 문법(주석·이스케이프·인용)을
#   흉내내 구분하지 않고 양쪽을 본다 — 새 전처리는 인식을 넓히기만 한다(차단 우세).
#   $1 = heredoc 본문을 벗긴 명령. 줄 연속이 없으면 한 번만 낸다.
_trigger_scan_text() {
  local j; j=$(_join_line_continuations "$1")
  _strip_quoted_strings "$j"
  [ "$j" = "$1" ] || { printf '\n'; _strip_quoted_strings "$1"; }
}

# ── 실행 증거 축의 진단값 (20261009) ──────────────────────────────────────────
# ok | missing | otherfid — **진단 전용**이라 allow/deny 를 바꾸지 않는다. otherfid 는 "러너가 돌긴 했는데 다른 FID 를
#   검증했다" 다: 그때 "이 세션에 러너 실행 기록이 없습니다" 라고 말하면 거짓 원인이다(방금 돌린 러너를 또 돌리게 한다).
_exec_cause() {
  [ "${1:-1}" -eq 1 ] 2>/dev/null || { printf 'ok'; return 0; }
  [ "${_EXEC_OTHER_FID:-0}" = "1" ] && printf 'otherfid' || printf 'missing'
}

# ── STALE 인데도 R-1 을 막지 않는 두 경우 (20261009) ──────────────────────────
# rc 0 = 막는다 · rc 1 = 막지 않는다(종전 판정 경로로 흘려보낸다 — 실행 증거·앵커는 그대로 요구된다).
#   ① 전체 스위트가 **지금 이 트리**에서 통과했다. run-all.sh 는 `VERIFY: PASS` 를 내는 정식 러너인데 판정 상태를
#      갱신하지 않는다 — 통과 마커(.full-suite-pass)의 지문이 현재 비문서 트리와 같으면 그 변경은 검증된 것이다.
#      마커가 있을 때만 잰다: 지문 계산이 한 번 더 든다(추적 파일이 수천 개면 초 단위 — 마커 없는 하류 저장소에서 헛돈다).
#   ② 달라진 것이 **이 커밋에 실리지 않는 파일**뿐이다 — 추적하지 않는 파일(로그·캐시·.DS_Store)이 생기거나 바뀌었다.
#      **커밋만 실행하는 명령일 때만** 적용한다. 훅이 보는 것은 명령 실행 전의 인덱스라, 같은 명령이 커밋 전에 다른 일을
#      하면(`git add`·`xargs git add`·`find -exec`·`sh -c`·`git config core.hooksPath`·`git diff --output=` …) 그 사이
#      인덱스·작업트리가 바뀔 수 있다. 무엇이 안전한지 명령 글자로 가려내려 하지 않는다 — 두 번 시도했고 두 번 다
#      새는 표기가 나왔다(낱말 찾기 → 메시지의 `add` 에 걸림 · 하위명령 목록 → 감싼 git 과 쓰기 옵션을 놓침).
#      문서 전용 커밋의 범위 판정이 쓰는 `_commit_scope_is_staged`(안전 prelude 뒤의 `git commit [-m|-F|-q]` 한 줄 —
#      compound·경로 인자·명령 치환·모르는 옵션은 전부 거부)를 그대로 쓴다. `-a` 만 더 받는다: 추적 파일의 작업트리
#      내용은 추적 지문이 이미 본다.
#   어느 쪽도 확인되지 않으면 막는다.
_vs_stale_blocks() {
  local fid="$1" cmd="${2:-}" dir="${_VERIFICATION_STATE_SH%/*}" top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || top=""
  [ -n "$top" ] && [ -f "$top/.specops/.full-suite-pass" ] && bash "$dir/full-suite-fresh.sh" >/dev/null 2>&1 && return 1
  # `-a`·`--all`·`-am` 을 벗긴 뒤 묻는다(인용 안의 글자도 함께 바뀌지만 판정기는 인용 내용을 보지 않는다).
  cmd=$(printf '%s' "$cmd" | sed -E 's/(^|[[:space:]])(-a|--all)([[:space:]]|$)/\1\3/g; s/(^|[[:space:]])-am([[:space:]])/\1-m\2/g')
  _commit_scope_is_staged "$cmd" || return 0
  [ "$(SPECOPS_ROOT=".specops" bash "$_VERIFICATION_STATE_SH" stale-scope "$fid" 2>/dev/null)" = "untracked-only" ] && return 1
  return 0
}

# ── 판정 git 대상 (20261016-hook-worktree-target) ─────────────────────────────
# 훅은 프로젝트 폴더(CLAUDE_PROJECT_DIR)로 이동해 .specops·관할·FID 를 읽는다. 그런데 세션 셸이 같은 저장소의
#   다른 작업 트리(.worktrees/<FID>)에 있으면 커밋·PR 의 대상은 그 worktree 다 — 메인 트리의 staged·지문으로
#   판정하면 유효 receipt 가 "무효" 로 막힌다(Argus 실기록: 우회 51건).
# 왜 cd 가 아니라 env 인가: worktree 에는 .specops 가 없을 수 있다(gitignore). 판정 위치를 옮기면 관할 밖 allow 가
#   된다(실측). 그래서 .specops 는 프로젝트 폴더에 두고 git 조회만 GIT_DIR·GIT_WORK_TREE 로 돌린다 — export 는
#   훅 프로세스와 그 자식 판정 스크립트 안에서만 산다.
# stdout: 대상이 바뀔 때만 2줄(작업 트리 최상위 · 절대 git 디렉터리). 판정 불가는 무출력(종전 판정).
_gov_git_target() {
  local cwd="${1:-}" proj="${2:-$PWD}" ctop ptop ccd pcd gd
  [ -z "${GIT_DIR:-}${GIT_WORK_TREE:-}" ] || return 0
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  [ "$cwd" = "$proj" ] && return 0
  ctop=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 0
  ptop=$(git -C "$proj" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$ctop" ] && [ -n "$ptop" ] && [ "$ctop" != "$ptop" ] || return 0
  ccd=$(cd "$ctop" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 0
  pcd=$(cd "$ptop" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 0
  [ -n "$ccd" ] && [ "$ccd" = "$pcd" ] || return 0
  gd=$(git -C "$ctop" rev-parse --absolute-git-dir 2>/dev/null) || return 0
  [ -n "$gd" ] || return 0
  printf '%s\n%s\n' "$ctop" "$gd"
}

# 명령이 스스로 git 대상을 옮기면(cd·pushd·popd·-C·--git-dir·--work-tree·GIT_DIR=·GIT_WORK_TREE=) 셸 위치로
#   판정 대상을 바꾸지 않는다 — 셸이 worktree 인데 `cd <메인> && git commit` 이면 실제 커밋은 메인에서 일어난다.
#   worktree 기준으로 보면 검증 안 된 메인 커밋이 열린다(외부 critic 지적 — 이 변경이 새로 만들 구멍). 그 경우는
#   종전 판정(프로젝트 폴더)이다. `make -C` 같은 무관한 -C 도 걸리지만 종전 판정으로 떨어질 뿐이다(안전 쪽).
#   $1 = 인용·heredoc 을 벗긴 명령. rc 0 = 옮긴다.
_gov_cmd_moves_git() {
  grep -Eq '(^|[;&|({`[:space:]])(cd|pushd|popd)([[:space:]]|$)|(^|[[:space:]])(-C|--git-dir|--work-tree)([[:space:]=]|$)|(^|[;&|({`[:space:]])GIT_(DIR|WORK_TREE)=' <<< "${1:-}"
}

# 호출자 셸에서 직접 부른다(서브셸이면 export 가 사라진다). $1 = 훅 입력의 cwd.
_gov_apply_git_target() {
  local t
  t=$(_gov_git_target "${1:-}" "$PWD")
  [ -n "$t" ] || return 0
  _GOV_TARGET_WT=${t%%$'\n'*}
  GIT_WORK_TREE=$_GOV_TARGET_WT
  GIT_DIR=${t#*$'\n'}
  export GIT_DIR GIT_WORK_TREE
}

# deny 사유 끝에 붙인다 — 막혔을 때 어디를 봤는지 알아야 우회로 가지 않는다. 대상이 그대로면 빈 값.
#   $1 = 플러그인 루트 · $2 = FID(빈 값 가능).
_gov_target_note() {
  local root="${1:-}" fid="${2:-}"
  [ -n "${_GOV_TARGET_WT:-}" ] || return 0
  printf '\n\n판정 기준 worktree: %s (기록·관할은 %s/.specops)' "$_GOV_TARGET_WT" "$PWD"
  # 위 안내의 조회 명령(verification-state.sh current 등)을 worktree 셸에서 그대로 돌리면 이 판정과 다른 값을 본다
  #   (plan-reviewer 1회차 실측: worktree 에서 NOT_RUN · 메인에서 STALE · 훅은 PASS). 같은 값을 보는 형태를 적는다.
  printf '\n   이 판정과 같은 값으로 조회하려면: cd %q && GIT_DIR=%q GIT_WORK_TREE=%q bash %q current %s' \
    "$PWD" "${GIT_DIR:-}" "$_GOV_TARGET_WT" "$root/scripts/_internal/verification-state.sh" "${fid:-<FID>}"
  if [ -d "$_GOV_TARGET_WT/.specops" ] && ! [ "$_GOV_TARGET_WT/.specops" -ef "$PWD/.specops" ]; then
    printf '\n⚠️ worktree 에 .specops 사본이 있습니다 — 기록 스크립트가 사본에 쓰면 이 판정과 갈라집니다. 사본을 지우면 기록 스크립트도 메인 기록을 씁니다.'
  fi
}
