#!/usr/bin/env bash
# specops-ko governance — PreToolUse entrypoint (강제 차단)
# stdin: Claude Code PreToolUse JSON
# stdout: allow={"continue":true} · deny=hookSpecificOutput permissionDecision:deny
# 실패 내성: fail-open — 내부 오류 시 allow. 차단은 verify 누락 판정 시에만.
set -uo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin_root=$(dirname "$script_dir")

bash "$plugin_root/scripts/_internal/is-hook-enabled.sh" pretool-governance >/dev/null 2>&1 \
  || { _off_in=$(cat 2>/dev/null || true); case "$_off_in" in *commit*|*create*) printf '%s' "$_off_in" | ( . "$script_dir/governance-lib.sh" && _note_governance_disabled "$plugin_root" ) >/dev/null 2>&1 || true ;; esac; echo '{"continue":true}'; exit 0; }

allow() { echo '{"continue":true}'; exit 0; }
# degraded 기록은 lib 로드 후에만 동작한다 — 로드 전 호출(declare -F 실패·.specops 부재) 시 무음 스킵.
# stdout JSON·stderr 문안은 불변(기존 테스트·판정기 계약 유지), allow 흐름도 불변(fail-open 계약).
safe_exit() { echo "[governance] pretool: $1" >&2; _log_degraded "GOVERNANCE-DEGRADED" "pretool fail-open: $1" 2>/dev/null || true; echo '{"continue":true}'; exit 0; }

# shellcheck disable=SC1091
source "$script_dir/governance-lib.sh" 2>/dev/null || safe_exit "lib source 실패"

if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR:-}" ]; then
  cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
fi

input=$(cat 2>/dev/null || echo "")
# jq 는 거버넌스 판정의 필수 의존이다. 부재 시 종전엔 아래 jq 실패가
# "stdin JSON parse 실패" 로 **오진**되어, 원인을 모른 채 전면 fail-open 했다.
# 동작(통과)은 그대로 두고 원인만 정확히 말한다 — fail-closed 로 바꾸면
# jq 없는 사용자의 모든 커밋이 막히고, 그건 BYPASS 관성을 만든다(실측 24건/30일).
command -v jq >/dev/null 2>&1 || safe_exit "jq 미설치 — 거버넌스 비활성 (설치: brew install jq)"
echo "$input" | jq -e . >/dev/null 2>&1 || safe_exit "stdin JSON parse 실패"

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
tool_cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

[ "$tool_name" = "Bash" ] || allow
# 의도적 범위 경계(F-3, WON'T-FIX): 선행자는 쉘 메타문자([;&|({`])·줄시작 뒤의 env 접두·래퍼·제어 키워드, 그리고 경로로 부른 git·gh 까지 인식(20261009 확대 — 정직한 사용에서 나오는 형태).
#   wrapper-class(sh -c·bash -c·eval·perl -e·python -c·xargs·find -exec…)는 미차단 — 정규식으로 무한확장 닫기 불가(두더지잡기).
#   본 게이트는 적대적 경계가 아닌 Claude 자기정직 스캐폴드(공식 우회 SPECOPS_GOVERNANCE_BYPASS=1 제공). honest Claude 가
#   자기 commit 을 wrapper 난독화할 동기 0 = honest-mistake 경로 부재. 보안 1차방어는 is_docs_only_change(git-authoritative, wrapper-agnostic).
# heredoc 본문 제거 후 검사 (20260713-heredoc-false-block): grep -E 는 줄 단위라, 멀티라인 command 의
#   heredoc **본문**에 쓴 git 예시(문서·테스트 작성)가 실제 명령으로 오인돼 정직한 작업을 차단했다.
#   정규식은 그대로 두고 **입력만** 전처리한다 — 정규식을 손대면 evasion 방어(PR #84·#112)가 흔들린다.
#   `bash <<EOF`(셸 실행자) 본문은 제외하지 않는다(실제 실행됨 → F-3 표면 불변). 실패 시 원본 = 차단 우세.
#   $tool_cmd 원본은 아래 apply_lookback_rule·deny 메시지에서 그대로 쓴다 — 덮어쓰기 금지.
tool_cmd_scan=$(_strip_heredoc_bodies "$tool_cmd")
tool_cmd_scan=$(_strip_quoted_strings "$(_join_line_continuations "$tool_cmd_scan")")
# prefilter 정규식은 rules.jsonl R-1/R-2 trigger_pattern 동적 로드 (T-H1 single-source — 구버전은 literal
#   복제 + 정합 테스트였으나, VAR=val 인용값 클래스 도입(20260716-batch-dogfood widening: `FOO='a b' git commit`
#   이 prefix 체인을 끊어 트리거를 통째로 비껴감 — 인식 확대 = deny-superset = 차단 우세라 evasion 방어
#   PR #84·#112 불변식 유지)으로 literal 에 quote-splice 가 생겨 복제 유지비 > 동적 로드 비용이 됐다.
#   R-3 의 posttool trigger_skill_pattern 동적 참조(T-R8)와 동형. 로드 실패 = 판정 불가 → fail-open.
rules_path="$plugin_root/hooks/rules.jsonl"
[ -f "$rules_path" ] || safe_exit "rules.jsonl 부재 — trigger 로드 불가"
trigger_re=$(jq -rs '[.[]|select(.id=="R-1" or .id=="R-2")|.trigger_pattern|select(.!=null)]|join("|")' "$rules_path" 2>/dev/null)
[ -n "$trigger_re" ] || safe_exit "trigger_pattern 로드 실패"
# 트리거 판정은 잇기 전 원문도 함께 본다(_trigger_scan_text) — 아래 범위 판정들은 이은 문자열(tool_cmd_scan)을 쓴다.
grep -Eq "$trigger_re" <<< "$(_trigger_scan_text "$(_strip_heredoc_bodies "$tool_cmd")")" || allow
_GOV_INPUT_CWD=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)   # 셸 위치 — 판정 대상(아래)과 이동 위치 해석(_gov_cmd_moves_elsewhere)이 쓴다 (20261016)
_gov_cmd_moves_git "$tool_cmd_scan" || _gov_apply_git_target "$_GOV_INPUT_CWD"   # 셸이 같은 저장소의 다른 worktree 면 git 조회를 그쪽으로 — 명령이 스스로 옮기면 종전 (20261016-hook-worktree-target)

# 세션-env 우회 = 사용자 주권(막지 않음). 단 무기록 우회는 감사 공백(상한 3호) → 기록 후 allow.
#   .specops 有일 때만 기록 — 부재(비-specops repo)면 log_friction 이 .specops 를 생성해 월권(M2 관할 가드 철학).
#   principle=1(숫자, 5원칙 1 투명성)·offset=0(숫자) 은 log_friction 이 --argjson 으로 소비 → 유효 JSON 필수.
if [ "${SPECOPS_GOVERNANCE_BYPASS:-}" = "1" ]; then
  if [ -d ".specops" ]; then
    _bypass_fid=$(detect_fid 2>/dev/null || echo "")
    log_friction "$_bypass_fid" "BYPASS-ENV" 1 "cat=unclassified | session-env SPECOPS_GOVERNANCE_BYPASS: ${tool_cmd:0:120}" 0 \
      "$(_commit_scope_class)" 2>/dev/null || true
    _record_bypass_metric "$_bypass_fid"
  fi
  allow
fi

# ── batch PR 뭉개짐 게이트 (20260721-batch-pr-teeth) ─────────────────────────
# dogfood test1: 무인 batch 가 7개 per-FR FID 를 BATCH_ID 하나로 뭉갠 채 PR 을 냈다.
#   teeth(scripts/batch-state.sh)는 commands/start-all.md:114 **산문**에만 있어 아무도 호출하지 않았고,
#   R-2 훅은 verify 만 보므로 통과했다. 산문 teeth 를 훅으로 옮긴다.
#
# 배치 순서가 의미를 갖는다 — 세션 env BYPASS(위 줄) **뒤**, 인라인 BYPASS(아래) **앞**:
#   · 세션 env = 사용자가 켠 것 = 주권(5원칙 4) → 인정
#   · 인라인 = 모델 자기발급 → **불인정**. batch PR 은 비가역이고, 뭉개진 채 나가면 되돌리기 비싸다.
#     security Critical/High 를 "§auto여도 자동통과 금지"로 둔 선례와 동급(start-all-auto.md:56).
#     이 순서가 아니면 test1 이 한 그대로(#421) 사유 한 줄로 우회된다.
#
# 대상은 PR 뿐이다. **중간 커밋은 검사하지 않는다** — chain 상 verify 보다 앞서는 것이 정상이고
#   (아래 L97-101 참조) 여기서 막으면 정직한 태스크별 커밋이 전부 걸린다.
_batch_pr_gate() {
  grep -Eq "$_PR_CREATE_RE" <<< "$tool_cmd_scan" || return 0
  # ★ 진행 중(ACTIVE 마커) batch 만 판정한다. glob-latest 는 쓰지 않는다.
  #   `.specops/*` 는 gitignore 라 뭉개진 batch 디렉토리가 디스크에 무기한 남는다. 아무 batch 나
  #   집으면 그것과 **무관한** 단일 FID 작업의 PR 이 과거 라벨 오염으로 차단된다 (실측 재현:
  #   specops-test1 의 무관한 PR 이 batch-20260721b 의 `DONE` 때문에 deny 됐다). 이 게이트는
  #   인라인 BYPASS 앞이라, 그런 false-block 의 탈출구는 "세션 전체 거버넌스 해제"뿐이 된다 —
  #   보호를 끄는 것이 유일한 출구인 형태는 게이트를 의례로 만든다.
  #   마커는 start-all Phase 0 이 queue.md 와 함께 만들고, batch PR 성공 후 지운다.
  #
  #   한계(5원칙 5): 마커는 오케스트레이터가 쓰는 것이라, 마커를 안 만들면 게이트도 안 열린다
  #   (자기보고 의존). 그럼에도 이 설계를 택한 이유는 **놓치는 비용 < 오차단 비용** 이기 때문이다 —
  #   false-block 은 사용자를 도구 밖으로 밀어내는 완주율 킬러이고, 미발화는 기존 상태로의 복귀일 뿐이다.
  #
  #   ★ 마커만으로는 부족하다. 마커는 "batch 가 진행 중인가"에 답할 뿐, 게이트가 필요한 답은
  #   "**이 PR 이 그 batch 의 PR 인가**"다. 특히 중단된 batch 가 치명적이다 — 마커는 PR 성공
  #   (Step D)에서만 지워지는데, 이 게이트의 목적이 뭉개진 batch 를 막는 것이라 막힌 batch 는
  #   Step D 에 도달하지 못한다. 마커가 영구히 남아 이후 모든 무관한 PR 을 차단한다.
  #   게이트가 잘 막을수록 오염 마커가 쌓이는 역설이다.
  #   판별자는 브랜치다 — batch PR 은 feat/<BATCH_ID> 에서 난다(start-all.md Phase 0).
  #   불일치·판정 불가(git 부재·detached)는 skip — false-block 회피가 옳은 오류 방향이다.
  local queue m d branch
  # symbolic-ref: 커밋 0건(unborn HEAD)에서도 브랜치명을 준다. rev-parse 는 unborn 에서 실패해
  #   갓 만든 batch(첫 커밋 전) 가 통째로 skip 된다 — 게이트가 가장 필요한 시점에 침묵한다.
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return 0
  [ -n "$branch" ] || return 0
  queue=""
  for m in .specops/batch-*/ACTIVE; do
    [ -f "$m" ] || continue
    d=$(dirname "$m")
    [ "$branch" = "feat/$(basename "$d")" ] || continue
    [ -f "$d/queue.md" ] && queue="$d/queue.md" && break
  done
  [ -n "$queue" ] || return 0
  is_docs_only_change "$tool_cmd_scan" && return 0   # PR 범위(base...HEAD) 기준 — 무인자는 작업트리라 dirty docs 하나로 새던 구멍
  local gout grc
  gout=$(bash "$plugin_root/scripts/batch-state.sh" --gate "$(dirname "$queue")" 2>&1); grc=$?
  # 0=뭉개짐 없음 · 2=판정 불가(queue/requirements 파싱 실패) → fail-open. 1 만 차단.
  # 판정 불가도 기록은 남긴다(allow 불변) — 무음 fail-open 이 "보호 중" 착각을 만들지 않게 한다.
  [ "$grc" -eq 2 ] && _log_degraded "GOVERNANCE-DEGRADED" "batch-state 판정 불가 fail-open (queue: $(dirname "$queue"))" 2>/dev/null || true
  [ "$grc" -eq 1 ] || return 0
  local reason
  reason="batch PR 차단 — per-FR 산출물·진행기록이 뭉개졌습니다 (BATCH-GATE).

$gout

batch 는 FR 마다 개별 FID 로 verify·review 를 남겨야 합니다 (commands/start-all.md:93).
FR 하나를 BATCH_ID 디렉토리에 통합해 돌리면 per-FR 근거가 사라지고, 그 상태의 PR 은 되돌리기 비쌉니다.
해법: 누락된 FID 의 verify·review 를 개별 실행한 뒤 queue.md Status 를 IMPL_DONE 으로 갱신하고 재시도하세요.
이 차단은 인라인 SPECOPS_GOVERNANCE_BYPASS 로 열리지 않습니다 (비가역 불변식 — security Critical/High 와 동급).
사용자가 의도적으로 넘기려면 세션 환경변수로 지정하세요: export SPECOPS_GOVERNANCE_BYPASS=1"
  jq -nc --arg r "$reason$(_gov_target_note "$plugin_root" "${fid:-}")" \
    '{ hookSpecificOutput: { hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r }, decision:"block", reason:$r }'
  exit 0
}
_batch_pr_gate

# 명령 위치(줄시작 또는 셸 메타문자 직후)의 env 접두 할당인가 — **앵커 단일 출처**.
#   $1 검사할 명령 · $2 리터럴 VAR=VAL · $3(선택) 그 앞에 올 수 있는 접두 그룹 정규식.
# 왜 함수인가: 이 앵커는 T37 사고("메시지 내 토큰 언급은 우회로 인정하지 않는다")의 산물인데,
#   소비자가 늘 때마다 정규식을 복제하면 한쪽만 고쳐지는 drift 가 곧 다음 결함이다 (실제로
#   20260910 SPECOPS_DRYRUN 초안이 무앵커 glob 으로 들어와 `echo SPECOPS_DRYRUN=1 && git commit`
#   을 조회로 오인했다 — false-deny 는 이 repo 가 두 번 겪은 BYPASS 관성 경로다).
#   선행자 클래스([;&|({`] + 줄시작)와 후행 공백 요구는 아래 인라인 BYPASS 주석의 근거를 승계한다.
# ★ 정의 위치가 파일 상단(allow/safe_exit 옆)이 아닌 이유: 정의 당시 scripts/tests/mutation-equivalent.conf 가
#   이 파일의 equivalent mutant 를 **절대 줄번호**로 고정했다 — 위쪽에 줄을 끼우면 그 고정이 통째로 stale 이 됐다
#   (test-mutation-conf-fresh.sh T2.a 실측). 20261010 부터 키가 함수+줄 원문이라 그 제약은 없다.
#   위치는 그대로 뒀다 — 첫 소비자 바로 앞이 co-location 측면에서도 낫다.
_is_cmd_pos_env() {
  grep -Eq "(^|[;&|({\`])[[:space:]]*${3:-}$2[[:space:]]" <<< "$1"
}

# 인라인 BYPASS 는 사유(SPECOPS_BYPASS_REASON) 병기 필수 (20260716-batch-dogfood: 첫 deny 후 모델이
#   무사유 BYPASS 를 커밋 3회+PR 생성에 관성 사용 — 사유 없는 friction-log 는 우회 횟수만 남는 무정보 감사
#   기록이 된다. 사유는 명령 원문째 friction-log evidence_snippet 에 남는다). 세션 env(위 줄)는 사용자 전용
#   탈출구라 사유 불요(주권). REASON 선행/후행 순서 모두 인정 — 형식 함정 false-deny 금지.
#   선행자는 트리거와 동일 클래스([;&|({`] + 줄시작) — dogfood 20260717 test2: `git add x && BYPASS=1
#   REASON='...' git commit`(compound)·`B() { BYPASS=1 ...; }`(wrapper) 가 ^줄시작 앵커에 걸려 사유까지
#   정직 병기한 우회가 false-deny 됐다. 단순 공백 선행(메시지 내 토큰 언급, T37)은 여전히 불인정.
_reason_val="('[^']*'|\"[^\"]*\"|[^[:space:]]+)"
if _is_cmd_pos_env "$tool_cmd" "SPECOPS_GOVERNANCE_BYPASS=1" \
     "(SPECOPS_BYPASS_REASON=${_reason_val}[[:space:]]+)?"; then
  # 메시지 오염 가드 (dogfood 20260717 test2 61f9e0d "BYPASS fix: ..."): 우회 표식이 git 히스토리에
  #   유입되면 conventional commit(릴리즈 노트·검색)이 훼손된다. 우회 기록은 REASON+friction-log 담당.
  if grep -Eq -- "-m[[:space:]]+[\"']?BYPASS" <<< "$tool_cmd"; then
    reason="커밋 메시지에 BYPASS 표식을 넣지 마세요 — 우회 기록은 SPECOPS_BYPASS_REASON 과 friction-log 가 담당합니다.
메시지는 conventional commit(fix:/feat:/test:/…)으로 정상 작성 후 재시도하세요."
    jq -nc --arg r "$reason$(_gov_target_note "$plugin_root" "${fid:-}")" \
      '{ hookSpecificOutput: { hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r }, decision:"block", reason:$r }'
    exit 0
  fi
  if grep -Eq "(^|[[:space:]])SPECOPS_BYPASS_REASON=[^[:space:]]" <<< "$tool_cmd"; then
    # 인라인 우회도 수율 계측에 남긴다(사유 원문은 friction-log / 명령 원문 쪽).
    if [ -d ".specops" ]; then
      _bypass_fid=$(detect_fid 2>/dev/null || echo "")
      # ⚠️ friction-log 기록이 **본체**다 — metrics 는 식별자만 담아 "우회 횟수만 아는
      #   무정보 감사"(위 :134 주석이 지적한 바로 그것)가 된다. 사유 원문은 여기 남는다.
      #   20260807 실사용 검증 3호: 이 호출이 **누락**돼 있었다. deny 메시지(아래 reason)와
      #   :135 주석이 "사유는 명령 원문째 friction-log evidence_snippet 에 남는다" 고
      #   약속하는데 실제로는 metrics 1건뿐이었다(실측: BYPASS-ENV 0 → 0).
      #   세션-env 경로(위 :59)는 부르는데 인라인만 빠져 **우회의 책임 추적이 통째로 공백**이었다.
      #   ⚠️ 앞부분 절단(${tool_cmd:0:N})은 쓰지 않는다 — 4호 실측: 앞에 cd·echo 전처리가
      #   붙으면 예산이 거기서 소진돼 **사유가 통째로 잘린다**. 사유는 위치 무관 **추출**하고,
      #   명령 원문은 그 뒤에 붙여 잘려도 사유는 항상 보존되게 한다.
      _bypass_reason=$(_extract_bypass_reason "$tool_cmd")
      _bypass_cat=$(_bypass_category "$_bypass_reason")
      log_friction "$_bypass_fid" "BYPASS-ENV" 1 \
        "cat=${_bypass_cat} | inline BYPASS reason=${_bypass_reason:-(추출실패)} | cmd: ${tool_cmd:0:200}" 0 \
        "$(_commit_scope_class)" 2>/dev/null || true
      _record_bypass_metric "$_bypass_fid"
    fi
    allow
  fi
  reason="SPECOPS_GOVERNANCE_BYPASS 인라인 우회에는 사유 병기가 필수입니다 (friction-log 감사 기록에 명령 원문째 남습니다).
형식: SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='<한 줄 사유>' <명령>
우회 전 정직한 해법 우선: bash '${plugin_root}'/scripts/_internal/run-verification.sh <FID> 를 이 세션에서 실행하면 우회 없이 열립니다."
  jq -nc --arg r "$reason$(_gov_target_note "$plugin_root" "${fid:-}")" \
    '{ hookSpecificOutput: { hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r }, decision:"block", reason:$r }'
  exit 0
fi
# M2 관할 가드: .specops 부재 = specops 미사용 repo → verify-before-commit 강제 면제 (5원칙 4 주권 — 플러그인은
#   자기 관할 repo 만 통제, 무관 repo 월권 금지). lifecycle 진행 중(.specops 존재)이면 그대로 강제 — 보호 손실 0.
[ -d ".specops" ] || allow
# SPECOPS_DRYRUN — "이 커밋은 면제됩니까" 조회 (C-1, 20260910). **실행하지 않는다.**
#   ★ 두 가지 위치 계약:
#     ① BYPASS 분기 **뒤**다 — 앞에 두면 조회 플래그가 BYPASS 기록을 건너뛴다.
#     ② **deny 전용**이다 — allow 를 늘리지 않으므로 조회가 우회로 전용될 수 없다.
#        (초안은 allow 였고, 그건 커밋을 실행시키면서 friction-log 기록이 0인
#         무음 우회 클래스였다 — plan-reviewer Important, 사용자 결정으로 교체.)
#   실판정 경로를 그대로 태운다 — 별도 판정 로직을 만들면 훅과 조회의 답이 갈라진다(#40).
#   scripts/_internal/scope-explain.sh 를 **호출하지 않는다**: REASON 필드는
#   is_docs_only_change 가 in-process 로 세팅하는 $_SPECOPS_SCOPE_FILES 를 읽어 만드는데,
#   서브프로세스는 그 부수효과를 돌려줄 수 없다 → 파일목록 재유도(판정 사본, AC-5 금지) 또는
#   필드 누락 둘 중 하나가 된다. 같은 lib 함수를 직접 부르는 편이 단일 판정기에 더 가깝다.
_dryrun=0
_dry_cmd="$tool_cmd_scan"
[ "${SPECOPS_DRYRUN:-}" = "1" ] && _dryrun=1
# 인라인 형태는 형제 BYPASS 분기와 **같은 판정기**(_is_cmd_pos_env)로 인식한다 — 무앵커
#   `*SPECOPS_DRYRUN=1*` 은 `echo SPECOPS_DRYRUN=1 && git commit -m x` 같은 단순 언급을
#   조회로 오인해 커밋을 false-deny 한다. 사용자는 왜 막혔는지 모른 채 BYPASS 로 간다.
#   (경계는 BYPASS 와 동일하다 — `FOO=bar SPECOPS_DRYRUN=1 git commit` 처럼 다른 env 가
#    선행하면 인식되지 않는다. 그 경우 조회가 아니라 **평시 판정**으로 흐르므로 게이트
#    보호는 그대로다 = allow 확대 0. 형제와 같은 경계를 공유하는 편을 택했다.)
if _is_cmd_pos_env "$tool_cmd_scan" "SPECOPS_DRYRUN=1"; then
  _dryrun=1
  # 인라인 형태는 **접두를 벗긴 뒤** 판정한다 (2회차 Important 실측): 벗기지 않으면
  #   C2(`git commit` 으로 시작)에서 걸려 항상 `SCOPE=conservative` 가 나온다 —
  #   조회가 실제 커밋과 **다른 답**을 내면 조회로서 무가치하다(AC-6 "인라인도 동일 판정").
  # ★ 벗김 기준은 **줄 시작**이다 (3회차 Important-2 실측). 종전 `case SPECOPS_DRYRUN=1[[:space:]]*)`
  #   는 명령 **첫 줄**만 봤는데, 인식기 `_is_cmd_pos_env` 는 grep 이라 줄 단위다 — prelude 뒤
  #   둘째 줄의 인라인도 조회로 인식된다. 그 결과 접두가 남은 채 판정돼
  #   `cd sub` ⏎ `SPECOPS_DRYRUN=1 git commit -m x` 가 실제 커밋(SCOPE=staged)과 달리
  #   항상 conservative 를 답했다(실측). deny 전용 경로라 안전 영향은 0, **정확성** 결함이었다.
  #   범위 한계(추정이 아니라 인식기와 대조해 적는다): 인식기는 `[;&|({\`]` 뒤 인라인도 인정하지만
  #   이 sed 는 줄 시작만 벗긴다. 그 형태(`git add -A && SPECOPS_DRYRUN=1 git commit`)는 접두를
  #   벗기든 말든 compound 라 C1 에서 보수로 떨어지고, 접두를 뺀 실제 커밋도 같은 이유로 보수다
  #   → 두 답이 갈라지지 않는다. 또한 sed 쪽이 종전 case 보다 인식기에 **더 가깝다**: 인식기는
  #   앵커 뒤 선행 공백을 허용하는데 case 는 문자열 정확 시작만 매칭했다.
  _dry_cmd=$(printf '%s\n' "$tool_cmd_scan" | sed -E 's/^[[:space:]]*SPECOPS_DRYRUN=1[[:space:]]+//')
fi
if [ "$_dryrun" = "1" ]; then
  if _commit_scope_is_staged "$_dry_cmd"; then _dry_scope=staged; else _dry_scope=conservative; fi
  if is_docs_only_change "$_dry_cmd"; then _dry_ex=yes; else _dry_ex=no; fi
  _dry_files=${_SPECOPS_SCOPE_FILES:-}
  if [ -n "$_dry_files" ]; then
    _dry_n=$(printf '%s' "$_dry_files" | grep -c . 2>/dev/null || true)
    _dry_cls=$(_commit_scope_class "$_dry_files")
  else
    # ★ 빈 문자열을 **인자로** 넘기면 안 된다: _commit_scope_class 는 `$# -gt 0` 이면 그 인자를
    #   그대로 쓰므로(:622) 항상 `empty` 를 반환한다 — git 판정 실패(판정불가)와 "커밋 범위가
    #   실제로 비었음"이 같은 문자열로 나온다. AC-5 가 금지한 판정불가 위장과 같은 클래스다.
    #   인자 **없이** 부르면 git-authoritative 로 둘을 구분한다: 판정불가는 빈 출력(:631 의
    #   `return 0`), 진짜 빈 범위는 `empty`. 파일 수도 `?`(미상) 와 `0`(빈) 을 구별해 적는다.
    _dry_cls=$(_commit_scope_class)
    if [ -n "$_dry_cls" ]; then _dry_n=0; else _dry_cls="판정불가"; _dry_n="?"; fi
  fi
  printf 'SCOPE=%s EXEMPT=%s REASON=%s(%s files)\n' "$_dry_scope" "$_dry_ex" "$_dry_cls" "$_dry_n" >&2
  # deny 방출 — 훅에 `deny()` 헬퍼는 **없다**(정의된 것은 `allow()`·`safe_exit()` 뿐, :13-14).
  #   기존 5곳(:134·:154·:182·:328·:412)과 **동형**의 인라인 jq 를 쓴다.
  _dry_reason="SPECOPS_DRYRUN 조회 — 실행하지 않았습니다. SCOPE=$_dry_scope EXEMPT=$_dry_ex REASON=$_dry_cls($_dry_n files). 실제 커밋은 SPECOPS_DRYRUN 없이 재실행하세요."
  jq -nc --arg r "$_dry_reason$(_gov_target_note "$plugin_root" "${fid:-}")" \
    '{ hookSpecificOutput: { hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r }, decision:"block", reason:$r }'
  exit 0
fi
# tool_cmd_scan 을 넘긴다(원문 tool_cmd 아님) — :40-41 에서 heredoc 본문·인용 문자열이 이미 제거돼
#   판정 오염이 없다. :112 batch 게이트는 인자 없이 호출해 현행 동작을 유지한다(범위 밖).
#
# 스코프 축소가 실제로 열어준 경우만 정보성 1행을 남긴다 (20260813-r1-docs-only-scope AC-8).
#   목적은 효과 측정이다 — friction-log 에 staged 목록이 없어 기존 77 block 중 본 결함 유래를
#   사후 산정할 수 없었다. 앞으로는 gbrain-friction 이 이 행을 별도 rule_id 로 집계한다.
#   rule_id 를 R-1 과 분리하는 이유: gbrain-friction 은 rule_id 로 그룹핑하고 증류 후보를
#   blocks>=임계 로 거르므로(scripts/gbrain-friction.sh), 분리하면 R-1 통계가 불변이다.
#   기록은 **부수효과**다 — FID 미검출이든 로깅 실패든 allow 를 지연·차단하지 않는다.
if is_docs_only_change "$tool_cmd_scan"; then
  # 면제여도 기록은 남긴다 — staged 축소든 working-tree 범위든 R-1-SCOPE info 행으로 적재한다.
  # 기록 실패·FID 미검출은 allow 를 막지 않는다(부수효과).
  if [ -d ".specops" ]; then
    _scope_fid=$(detect_fid 2>/dev/null || echo "")
    if [ -n "$_scope_fid" ]; then
      if _commit_scope_is_staged "$tool_cmd_scan"; then
        _scope_note="staged-scope 축소로 docs-only 면제"
      else
        _scope_note="docs-only 면제(working-tree 범위)"
      fi
      log_friction_sev "$_scope_fid" "R-1-SCOPE" 1 \
        "${_scope_note}: ${tool_cmd:0:120}" 0 "info" 2>/dev/null || true
    fi
  fi
  allow
fi

# $fid 는 아래 log_friction_sev(위반 기록)·deny 메시지에서 재사용된다 — 삭제 금지.
#   set -uo pipefail 하에서 unbound "$fid" 는 스크립트를 즉사시켜 deny 경로가 JSON 을 못 뱉는다(무출력 = fail-open).
fid=$(detect_fid)

# §auto 무조건 면제는 여기 없다 — 의도적으로 제거했다 (20260713-verify-exec-gate).
#   구버전은 spec.md 의 `**§auto**: true` 라벨만 보고 실행-근거 검사에 **도달하기도 전에** allow 했다.
#   그 라벨은 모델이 spec.md 에 쓰는 것이라 사실상 자기발급 면제표였고, 무인 진입(/start-auto·/start-all-auto)이면
#   게이트가 통째로 무효화됐다. §auto 의 의미는 "가역 게이트 자동 통과"(사용자 확인 생략)이지 "검증 면제"가 아니다.
#   무인 모드도 chain 에 verifying-evidence-ko 가 있어 verify 를 실제 실행하므로, 정직한 무인 흐름은 실행 증거를
#   남기고 그대로 통과한다. 무인 중 정당한 우회는 명시적 SPECOPS_GOVERNANCE_BYPASS=1 + SPECOPS_BYPASS_REASON 을 쓴다
#   (감사 로그에 사유째 남으므로 암묵 면제보다 정직하다).
#
#   단 위 문장을 "무인이면 늘 통과한다" 로 읽지 말 것 — /implement 의 **태스크별 중간 커밋**은 chain 상
#   verify 보다 **앞서므로** 실행 증거가 아직 없다. 즉 정직한 흐름이어도 중간 커밋은 deny 되고
#   SPECOPS_GOVERNANCE_BYPASS=1 경로를 타며 friction-log 에 R-1 warn 이 남는다 (본 FID 의 T1~T4 커밋이 전부 그랬다).
#   이는 설계된 비용이다: "커밋 시점에 verify 실행 증거" 라는 불변식을 지키려면 verify 이전 커밋은 명시적
#   BYPASS 로만 통과해야 한다 (암묵 면제 = 게이트 무효화). 태스크별 커밋을 상시 면제하고 싶다면 그건 별도 설계 결정이다.

[ -n "$transcript" ] && [ -f "$transcript" ] || allow

rules_path="$plugin_root/hooks/rules.jsonl"
[ -f "$rules_path" ] || allow
violation=""; _cause_ok=0   # _cause_ok 선초기화 — parse 블록 이동 시 fail-open 대신 fallback deny
# rules 로드 실패는 R-1/R-2 판정 불가 → allow 로 흐른다. 기록은 남긴다(흐름 불변).
_rules_input=$(load_rules "$rules_path" "posttool" 2>/dev/null || true)
[ -n "$_rules_input" ] || _log_degraded "GOVERNANCE-DEGRADED" "rules 로드 실패 — R-1/R-2 판정 불가 fail-open" 2>/dev/null || true
while IFS= read -r rule; do
  [ -z "$rule" ] && continue
  rid=$(echo "$rule" | jq -r '.id')
  case "$rid" in
    R-1|R-2)
      res=$(apply_lookback_rule "$rule" "$transcript" "$tool_name" "$tool_cmd" 2>/dev/null || true)
      if [ -n "$res" ]; then
        violation="$rid"
        violation_res="$res"     # 축 B: deny 메시지 조립에서 cause 를 읽는다
        principle=$(echo "$rule" | jq -r '.principle')
        snippet=$(echo "$res" | jq -r '.evidence_snippet')
        offset=$(echo "$res" | jq -r '.offset')
        log_friction_sev "$fid" "$rid" "$principle" "$snippet" "$offset" block \
          "$(_commit_scope_class "${_SPECOPS_SCOPE_FILES:-}")" 2>/dev/null || true
        break
      fi
      ;;
  esac
done <<< "$_rules_input"

if [ -n "$violation" ]; then
  case "$violation" in
    R-1) act="git commit" ;;
    R-2) act="gh pr create" ;;
    *)   act="이 작업" ;;
  esac
  # 세션 경계 한계 고백(5원칙 5): 실행 증거는 transcript(세션별 파일)에만 존재한다 → 이전 세션에서 정직하게 verify 를
  #   마쳤어도 새 세션에서는 증거가 보이지 않아 deny 된다. 이는 의도된 동작 — 세션 넘긴 verify 는 stale 위험(#120).
  #   따라서 메시지는 "verify 미실행"(단정·거짓 가능)이 아니라 "이 세션에 실행 증거 없음"으로 진술하고,
  #   실제로 게이트를 여는 유일한 행동(run-verification.sh 재실행)을 안내한다. Skill 호출 안내는 틀린 해법(T2b 가 차단).
  # $fid 는 L44 에서 bind 됨(빈 값 가능 — session-progress 부재 시) → ${fid:-<FID>} 로 dangling 방지.
  # ★ 면제 조건은 **두 겹**이다 (governance-lib.sh apply_lookback_rule L481-500):
  #     ① 실행 증거 — transcript 의 러너 tool_result 에 `VERIFY: PASS` (필요조건)
  #     ② FID-scoped 앵커 — session-progress `## <FID>` 섹션의 `/verify PASS` 줄, 또는 해당 FID 의
  #        evidence.md 스탬프, 또는 verify Skill 호출 이벤트 (①이 있어야 인정되는 보조 신호)
  #   구 문안은 ①만 안내해, 지시대로 러너를 재실행하고도 ②가 없어 또 막힌 모델을 BYPASS 로 몰았다
  #   (dogfood 20260721 test1 #418→#419→#420: 안내 이행 후 동일 메시지로 재차단 → #421 BYPASS).
  #   $fid 가 비어 있으면 그 자체가 진단이다 — session-progress 에 FID 섹션이 없다는 뜻.
  # 백그라운드 실행 원인 구분 (20260807-bg-verify-evidence) — 구분이 없으면 사용자는 방금 러너를
  # 돌리고도 "실행 기록이 없습니다" 를 보고 원인을 모른다(실측: 수분대 러너 재실행 낭비).
  # ★ 부모 스코프에서 계산한다 — _verify_exec_evidence 는 `res=$(apply_lookback_rule ...)`
  #   서브셸 안에서 돌아 그 안의 변수 설정이 여기로 전파되지 않는다(Phase B 적발).
  # ── 축 B: 원인 구분 (20260910-receipt-window-close) ─────────────────────────
  # 종전엔 ①·②·receipt 세 블록이 **무조건** 출력됐다. 구조적으로 닫힌 경로까지 성실히
  # 안내하므로, 안내를 그대로 이행할수록 BYPASS 로 몰린다(20260910 실측 — 커밋 2건).
  # cause 는 판정기가 이미 아는 사실만 실어 온다. 부재·파싱 실패면 종전 문안 그대로 —
  # 미탐 방향으로만 떨어진다(진단 실패가 차단을 무력화하지 않는다).
  # ★ 배치 주의: 이 블록은 _anchor_hint·_evidence_hint 산출보다 **앞**이어야 한다. 뒤로 옮기면
  #   cause 3축이 미산출 상태로 읽혀 진단이 통째로 종전 문안(FR-6 fallback)으로 퇴화한다 —
  #   차단 자체는 유지된다(L305 `_cause_ok=0` 선초기화가 unbound→fail-open allow 를 막는다).
  _c_exec=$(printf '%s' "${violation_res:-}" | jq -r '.cause.exec // empty' 2>/dev/null || true)
  _c_anchor=$(printf '%s' "${violation_res:-}" | jq -r '.cause.anchor // empty' 2>/dev/null || true)
  _c_receipt=$(printf '%s' "${violation_res:-}" | jq -r '.cause.receipt // empty' 2>/dev/null || true)
  _cause_ok=0
  [ -n "$_c_exec" ] && [ -n "$_c_anchor" ] && [ -n "$_c_receipt" ] && _cause_ok=1
  _EXEC_BG_PENDING_PATH=$(_bg_pending_path "$transcript" 2>/dev/null || true)
  _bg_hint=""   # 메인 흐름(함수 밖) — local 불가
  if [ -n "${_EXEC_BG_PENDING_PATH:-}" ]; then
    _bg_hint="   ※ 백그라운드 실행은 감지됐으나 출력을 Read 로 회수한 기록이 없습니다.
      ${_EXEC_BG_PENDING_PATH} 를 Read 하면 그 결과가 실행 증거로 인정됩니다."
  else
    _bg_hint="   ※ 긴 러너는 timeout 을 명시(최대 600s)해 **포그라운드**로 실행하세요 — 백그라운드로 돌리면
      출력 파일을 Read 로 회수해야만 증거가 성립합니다."
  fi

  _anchor_hint=""   # 메인 흐름(함수 밖) — local 불가
  if [ "$_cause_ok" -eq 1 ] && [ "$_c_anchor" = "ok" ]; then
    _anchor_hint="✔ ② 진행 기록 앵커: 확인됩니다."
  elif [ "$_cause_ok" -eq 1 ] && [ "$_c_anchor" = "stale" ]; then
    _anchor_hint="✘ ② 진행 기록 앵커: /verify PASS 줄보다 **더 최신인 코드 변경 기록**이 있습니다.
   검증 이후의 코드로 다시 verify 해야 앵커가 유효해집니다."
  elif [ -z "${fid:-}" ]; then
    _anchor_hint="✘ ② 진행 기록 앵커가 없습니다 — .specops/session-progress.md 에 \`## <FID>\` 섹션이 하나도 없습니다.
   FID 는 YYYYMMDD-kebab-slug 형식이어야 합니다(batch-<날짜> 같은 BATCH_ID 는 인식되지 않습니다).
   bash '${plugin_root}'/scripts/session-progress-append.sh <FID> /verify PASS 로 기록하세요."
  else
    _anchor_hint="✘ ② 진행 기록 앵커: .specops/session-progress.md 의 \`## ${fid}\` 섹션에 \`- <날짜> <시각> /verify PASS\` 줄,
   또는 .specops/${fid}/evidence.md 의 RUN-VERIFICATION-RESULT 스탬프가 필요합니다.
   이 세션에서 bash '${plugin_root}'/scripts/_internal/run-verification.sh ${fid} 가 \`VERIFY: PASS\` 로 끝난 것을 확인한 뒤 앵커를 남기세요:
   bash '${plugin_root}'/scripts/session-progress-append.sh ${fid} /verify PASS \"<요약>\""
  fi
  # Wave C: compound `git add … && git commit` deny 시 add도 취소됨 → 분리 안내 (트리거/부분실행은 불변)
  _compound_hint=""
  if [ "$violation" = "R-1" ] \
     && grep -Eq '(^|[[:space:];&|({`])git[[:space:]]+add([[:space:]]|$)' <<< "$tool_cmd_scan" ; then
    _compound_hint="

⚠️ compound 안내: 이 명령에 \`git add\` 와 \`git commit\` 이 함께 있습니다.
   PreToolUse deny 시 add 도 함께 취소됩니다 — \`git add\` 와 \`git commit\` 을 **별도 Bash 호출**로 분리 실행하세요."
  fi
  # 원인 구분 (20260828-deny-cause-truth): 증거가 **있었는데** 그 뒤 코드를 고쳐 stale 인 경우,
  #   "실행 기록이 없습니다" 는 거짓이다. 거짓 원인은 러너 재실행 낭비 아니면 BYPASS 로 이어진다
  #   (마찰로그 BYPASS 24건 중 15건이 "이 세션에서 verify PASS" 를 사유로 적었다).
  #   진단이 빈 값이면 종전 문안 그대로 — 미탐 방향으로만 떨어진다.
  _stale_cause=$(_verify_stale_cause "$transcript" 2>/dev/null || true)
  if [ -n "${_stale_cause:-}" ]; then
    _evidence_hint="① 실행 증거가 **stale** 입니다 — 러너는 이 세션에서 PASS 했으나 그 뒤 코드가 수정됐습니다.
   마지막 수정: ${_stale_cause#stale }
   수정 이후의 코드로 다시 검증해야 합니다 — 러너를 **한 번 더** 실행하세요:
   bash '${plugin_root}'/scripts/_internal/run-verification.sh ${fid:-<FID>}
   (플러그인 자기 repo self-maintenance 는 bash scripts/tests/run-all.sh 전체 스위트 통과도 인정됩니다.)"
  elif [ "$_cause_ok" -eq 1 ] && [ "$_c_exec" = "vstale" ]; then
    # 검증 판정이 STALE — transcript 의 편집 이벤트로는 보이지 않는 변경이다(셸 명령·포매터·코드 생성·서브에이전트).
    _evidence_hint="✘ ① 검증 이후 코드가 바뀌었습니다 — 이 FID 의 검증 판정이 **STALE** 입니다.
   검증 PASS 를 기록한 뒤 문서가 아닌 파일이 달라졌습니다(편집 도구가 아닌 경로의 변경 포함 — 셸 명령·포매터·코드 생성·서브에이전트).
   검증 기록에 지문이 없어 지금 코드와 같은지 확인할 수 없는 경우도 STALE 입니다(러너가 아니라 손으로 쓴 기록 등).
   지금 코드로 다시 검증하세요: bash '${plugin_root}'/scripts/_internal/run-verification.sh ${fid:-<FID>}
   현재 verdict 확인: bash '${plugin_root}'/scripts/_internal/verification-state.sh current ${fid:-<FID>}
   (플러그인 자기 repo self-maintenance 는 bash scripts/tests/run-all.sh 전체 스위트를 **지금 이 트리에서** 통과시켜도 인정됩니다.
    달라진 것이 아직 추적하지 않는 파일뿐이면 막지 않습니다 — 단 커밋을 다른 명령과 한 번에 실행하면(\`&&\`·\`;\`·파이프·명령 치환·경로 인자)
    그 사이 인덱스가 바뀔 수 있어 막습니다. 그 경우 \`git commit -m …\` 만 따로 실행하세요.
    검증 때 추적하지 않던 파일을 그 뒤에 인덱스에 올린 것도 달라진 것으로 봅니다 — 다시 검증하면 풀립니다.)"
  elif [ "$_cause_ok" -eq 1 ] && [ "$_c_exec" = "otherfid" ]; then
    # 러너는 돌았는데 **다른 FID** 를 검증했다 — "실행 기록이 없다" 고 말하면 거짓 원인이다.
    _evidence_hint="✘ ① 실행 증거: 이 세션에서 돌린 러너는 **다른 FID** 를 검증했습니다 — ${fid:-<FID>} 의 통과한 실행 기록이 없습니다.
   run-verification.sh 뒤에 적힌 FID 가 이 FID 가 아닙니다(한 세션에서 FID 여럿을 다루면 앞 FID 의 PASS 는 뒤 FID 의 증거가 아닙니다).
   이 FID 로 실행하세요: bash '${plugin_root}'/scripts/_internal/run-verification.sh ${fid:-<FID>}
   (플러그인 자기 repo self-maintenance 는 bash scripts/tests/run-all.sh 전체 스위트 통과도 인정됩니다.)"
  elif [ "$_cause_ok" -eq 1 ] && [ "$_c_exec" = "ok" ]; then
    _evidence_hint="✔ ① 실행 증거: 이 축은 차단 사유가 아닙니다(이 세션 transcript 기준 실행 증거 있음, 또는 판정 불가로 fail-open). 차단 사유는 아래 ②·receipt 입니다."
  else
    # cause 부재(FR-6 fallback)와 exec=missing 이 같은 문안을 쓴다. `✘ ` 접두만 추가되므로
    # AC-6 의 "변경 전과 동일" 은 **본문 동일 + 상태 접두 추가**를 뜻한다(부분 문자열 단언으로 잠근다).
    _evidence_hint="✘ ① 실행 증거: 이 세션에 러너 실행 기록이 없습니다(이전 세션의 verify 는 transcript 가 세션별이라 인정되지 않고, stale 위험도 있습니다).
   bash '${plugin_root}'/scripts/_internal/run-verification.sh ${fid:-<FID>} 를 이 세션에서 실행하세요.
   러너를 이미 실행했는데 \`VERIFY: PARTIAL\` 로 끝났다면 tasks.md 의 test_command 가 whitelist 미통과라 건너뛰어진 것이며 실행 증거로 인정되지 않습니다 —
   test_command 를 허용 형태(bash scripts/tests/… · bash tests/… · pytest · npm test 등)로 고친 뒤 다시 실행하세요.
   (플러그인 자기 repo self-maintenance 는 bash scripts/tests/run-all.sh 전체 스위트 통과도 인정됩니다.)"
  fi
  # ① 이 충족이면 백그라운드 안내는 소음이다 — 그때만 끈다.
  [ "$_cause_ok" -eq 1 ] && [ "$_c_exec" = "ok" ] && _bg_hint=""
  # receipt 대안은 R-1 이고 창이 열려 있을 때만 실제로 열리는 경로다. 닫혔으면 권하지 않는다.
  if [ "$_cause_ok" -eq 1 ]; then
    case "$_c_receipt" in
      open-missing)
        _receipt_hint="
▶ 지금 열려 있는 경로 — receipt (R-1 implement 창):
   bash '${plugin_root}'/scripts/_internal/record-task-receipt.sh ${fid:-<FID>} <T#>
   그리고 커밋 메시지에 T#/Task: T# 를 넣으세요 (staged ⊆ task outputs, receipt 이후 코드 변경 없음)." ;;
      open-invalid)
        _receipt_hint="
▶ receipt 경로는 열려 있으나 **기록된 receipt 가 유효하지 않습니다**:
   staged 파일이 해당 task 의 outputs 안에 있는지, receipt 기록 이후 코드가 바뀌지 않았는지 확인하세요.
   bash '${plugin_root}'/scripts/_internal/record-task-receipt.sh ${fid:-<FID>} <T#> 로 다시 기록할 수 있습니다." ;;
      closed-verified)
        # ★ 어느 verdict 인지 **단정하지 않는다**. 창은 PASS·STALE·WAIVED(+판정불가) 전부에서 닫히는데
        #   (governance-lib.sh `_receipt_window_open` case), 초안 문안 "verify 가 이미 유효 PASS 이므로" 는
        #   그중 하나에서만 참이었다 — STALE 은 PASS 후 코드가 바뀐 상태고 WAIVED 는 verify 가 돌지도
        #   않았다. 세 상태 중 하나에서만 참인 문장을 셋 다에 출력하는 것이 바로 이 FID 가 없애려는
        #   병(거짓 deny 문안 → BYPASS)이다. 아래는 네 상태 전부에서 참인 진술 + 실제 verdict 조회 안내다.
        _receipt_hint="
※ receipt 경로는 이 FID 에서 **닫혀 있습니다** — receipt 는 verify 결과가 NOT_RUN·PARTIAL·FAIL 인
   implement 창에서만 열립니다(PASS·STALE·WAIVED 는 닫힘 — 특히 STALE 은 검증 이후 코드가 바뀐
   상태라 receipt 로 우회하지 않습니다). 지금은 ①·② 로 통과해야 합니다.
   현재 verdict 확인: bash '${plugin_root}'/scripts/_internal/verification-state.sh current ${fid:-<FID>}" ;;
      *) _receipt_hint=$(_receipt_hint_extra "$_c_receipt" "$tool_cmd" "${fid:-}" 2>/dev/null) || _receipt_hint="" ;;   # open-id-mismatch(문안은 governance-lib 끝 — 줄번호 핀 보존) · 그 밖(n/a R-2)은 빈 값
    esac
  else
    _receipt_hint="
implement 중간 커밋 대안(R-1): 태스크 테스트 PASS 후
   bash '${plugin_root}'/scripts/_internal/record-task-receipt.sh ${fid:-<FID>} <T#>
   로 receipt를 남기고, 커밋 메시지에 T#/Task: T# 를 넣으면 FID 전체 verify 없이 열릴 수 있습니다
   (staged ⊆ task outputs, receipt 이후 코드 변경 없음)."   # cause 부재 → 종전 문안
  fi
  reason="$act 차단 — verify 면제 조건 2가지 중 최소 하나가 미충족입니다.

$_evidence_hint
$_bg_hint
$_anchor_hint
$_receipt_hint

①은 필요조건입니다 — ② 만으로는 열리지 않습니다(모델 자기보고라 위조 가능). 둘 다 갖춰야 통과합니다.
우회(사유 병기 필수): SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='<한 줄 사유>' <명령>${_compound_hint}"
  # quick 사유(범위 초과 · 리뷰 미충족 · 커밋 범위)면 위 ①② 안내를 쓰지 않는다 — quick 구조의 FID 는 검증 러너를
  #   통과시켜도 열리지 않으므로, 그 안내는 닫힌 길을 가리킨다(거짓 안내 → BYPASS). 다른 사유의 문안은 그대로다.
  case "$_cause_ok:${_c_receipt:-}" in
    1:quick-*)
      reason="$act 차단 — quick 경로의 커밋 조건이 충족되지 않았습니다.
$_receipt_hint

이 FID 는 명세 없이 태스크 문서만 있는 quick 경로입니다 — 검증 러너(run-verification.sh) 통과로는 열리지 않습니다.
우회(사유 병기 필수): SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='<한 줄 사유>' <명령>${_compound_hint}" ;;
  esac
  jq -nc --arg r "$reason$(_gov_target_note "$plugin_root" "${fid:-}")$(_gov_moved_note "$tool_cmd_scan")" \
    '{ hookSpecificOutput: { hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r }, decision:"block", reason:$r }'
  exit 0
fi

# ── P0-3 RELEASE_READY (R-2 / gh pr create 전용) — Wave B limited hard ──────
# strict FID 또는 ACTIVE batch(브랜치 일치) PR: NOT_READY → hard deny.
# 그 외: warn-only. UNKNOWN(rc=2)은 fail-open. R-1·docs-only·BYPASS·batch-state·verify lookback 은 위에서 처리됨.
_release_ready_gate() {
  grep -Eq "$_PR_CREATE_RE" <<< "$tool_cmd_scan" || return 0
  [ -f "$plugin_root/scripts/_internal/release-ready.sh" ] || return 0

  local hard=0 hard_why="" fids="" f branch m d qdir qfile eff line
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)

  # batch 스코프 — ACTIVE + feat/<BATCH_ID> ( _batch_pr_gate 와 동일 판별 )
  if [ -n "$branch" ]; then
    for m in .specops/batch-*/ACTIVE; do
      [ -f "$m" ] || continue
      d=$(dirname "$m")
      [ "$branch" = "feat/$(basename "$d")" ] || continue
      qfile="$d/queue.md"
      [ -f "$qfile" ] || continue
      hard=1
      hard_why=batch
      qdir="$d"
      # IMPL_DONE FID 전부
      while IFS= read -r line; do
        f=$(printf '%s' "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')
        grep -qE '^[0-9]{8}-[a-z0-9-]+$' <<< "$f" || continue
        fids="${fids}${fids:+ }$f"
      done < <(grep -E '\|[[:space:]]*IMPL_DONE[[:space:]]*\|' "$qfile" 2>/dev/null || true)
      break
    done
  fi

  # detect_fid / active-fid fallback + strict 프로파일
  local _rr_fid="${fid:-}"
  [ -n "$_rr_fid" ] || _rr_fid=$(detect_fid 2>/dev/null || echo "")
  if [ -z "$fids" ] && [ -n "$_rr_fid" ]; then
    fids="$_rr_fid"
  fi
  if [ -n "$_rr_fid" ] && [ -f ".specops/$_rr_fid/risk-profile.json" ]; then
    eff=$(jq -r '.effective // empty' ".specops/$_rr_fid/risk-profile.json" 2>/dev/null || true)
    if [ "$eff" = "strict" ]; then
      hard=1
      [ "$hard_why" = "batch" ] || hard_why=strict
      case " $fids " in *" $_rr_fid "*) ;; *) fids="${fids}${fids:+ }$_rr_fid" ;; esac
    fi
  fi

  [ -n "$fids" ] || return 0

  local any_not_ready=0 agg="" rc out
  for f in $fids; do
    # || true 금지 — $? 가 항상 0 이 되어 NOT_READY 를 못 본다
    out=$(bash "$plugin_root/scripts/_internal/release-ready.sh" "$f" 2>&1)
    rc=$?
    if [ "$rc" -eq 1 ]; then
      any_not_ready=1
      if [ -n "$agg" ]; then
        agg="$agg

--- FID $f ---
$out"
      else
        agg="--- FID $f ---
$out"
      fi
    fi
    # rc=2 UNKNOWN → 해당 FID는 무시(fail-open)
  done

  [ "$any_not_ready" -eq 1 ] || return 0

  if [ "$hard" -eq 1 ]; then
    local reason
    reason="RELEASE_READY 차단 — PR 품질 축 미충족 (${hard_why}).

$agg

해법: 해당 FID에서 verify·review·security/integration/performance·reconcile 축을 충족한 뒤 재시도하세요.
우회(사유 병기 필수): SPECOPS_GOVERNANCE_BYPASS=1 SPECOPS_BYPASS_REASON='<한 줄 사유>' <명령>"
    log_friction_sev "${_rr_fid:-$f}" "RELEASE_READY" 1 "$(printf '%s' "$agg" | tr '\n' ' ' | cut -c1-200)" 0 block 2>/dev/null || true
    jq -nc --arg r "$reason$(_gov_target_note "$plugin_root" "${fid:-}")" \
      '{ hookSpecificOutput: { hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$r }, decision:"block", reason:$r }'
    exit 0
  fi

  echo "RELEASE_READY warn (PR 차단 아님): $agg" >&2
  log_friction "${_rr_fid:-unknown}" "RELEASE_READY" 1 "$(printf '%s' "$agg" | tr '\n' ' ' | cut -c1-200)" 0 2>/dev/null || true
}
_release_ready_gate

allow
