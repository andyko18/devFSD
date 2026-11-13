#!/usr/bin/env bash
# init-finalize.sh — /init-project Phase 11 종결 커밋 (FID 20260810-init-commit-teeth)
# Usage: bash scripts/_internal/init-finalize.sh
# Exit: 0 = 커밋 성공 또는 커밋 대상 없음(no-op) · 1 = 커밋 실패
#
# 왜 스크립트인가: 종전엔 commands/init-project.md 산문이 `git add <보강·골격 파일들>` 로
#   **목록을 모델에게 재구성시켰다**. bash 는 정본 배열을 이미 소유하므로 소유권을 되돌린다.
#   실측(attendance 20260810): 산문 스텝이 실행되지 않아 커밋 0건 · 18파일 staged 방치.
set -u

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 정본 배열 재사용 — 목록을 두 벌 만들지 않는다(drift 방지)
# shellcheck disable=SC1091
source "$_DIR/init-project.sh"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "init-finalize: git repo 아님" >&2; exit 1; }

# repo 루트로 이동 — 아래 경로가 **전부 상대경로**라 하위 디렉토리에서 실행하면
#   재-add 루프가 통째로 no-op 이 되고(파일이 안 보임) 기존 staged 만 커밋된 채
#   rc=0 "커밋 완료" 가 나온다 = AC-2 가 조용히 무력화되는 **거짓 성공**(Phase C 실측:
#   `cd sub && bash init-finalize.sh` → committed=0 dirty=1 rc=0).
#   session-progress-append.sh 도 TARGET=".specops/session-progress.md" 상대경로라
#   subdir 에서는 `sub/.specops/` 를 새로 파므로, cd 는 append 호출보다 **앞**에 있어야 한다.
# 왜 변수를 거치나: `cd ""` 는 bash 에서 rc=0 이라 조용히 subdir 에 머문다 — 빈 값을 먼저 막는다.
_root="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$_root" ] || { echo "init-finalize: repo 루트 확인 실패" >&2; exit 1; }
cd "$_root" || { echo "init-finalize: repo 루트 이동 실패 ($_root)" >&2; exit 1; }

# ── 설계 완료 표지 검증 (20261113) — stage 보다 앞: 내린 표지가 같은 커밋에 들어가야 한다 ──
# 왜: `init 설계 완료`(화면 목록의 목적 칸)와 `<!-- specops:init-designed: M1 -->`(api-spec·data-model 머리)는
#   /start-all Phase 2.5 가 그 화면·인터페이스의 설계·리뷰를 **건너뛰게** 하는 표지인데, 모델이 직접 쓴다.
#   리뷰 없이 달리면 설계 리뷰가 통째로 사라진다. 그래서 **이번 커밋이 새로 다는 표지**만 리뷰 보고서
#   (.specops/.init-design/design-review.md — 저장 훅이 리뷰어 출력에서 옮긴다)와 대조한다:
#   보고서 없음·판정 줄 없음·SKIP → 전부 내린다 · FAIL → Critical·Important 이슈 줄이 가리키는 것만 내린다 · PASS → 그대로.
#   HEAD 에 이미 있는 표지는 건드리지 않는다 — 앞선 부트스트랩이 승인받은 것이고, 리뷰 보고서는 커밋되지 않는 로컬 파일이다.
#   한계: 보고서 파일의 출처(훅이 썼는가)는 여기서 증명하지 못한다.
_ov=".specops/memory/screens-overview.md"
_rv=".specops/.init-design/design-review.md"
_designed_in() {   # stdin = screens-overview.md 내용 → 설계 완료 표지가 붙은 화면 이름(check-screens-overview.sh `designed` 와 같은 규칙)
  awk '
    /^<!-- screens-table:start -->/ { inside=1; next }
    /^<!-- screens-table:end -->/   { inside=0; next }
    inside && /^\|/ {
      split($0, f, "|")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[2]); gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[4])
      if (f[2] != "name" && f[2] != "" && index(f[4], "init 설계 완료") == 1) print f[2]
    }'
}
_new_marks=""; _new_if=""
if [ -f "$_ov" ]; then
  _old=$(git show "HEAD:$_ov" 2>/dev/null | _designed_in)
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    printf '%s\n' "$_old" | grep -qxF -- "$_s" || _new_marks="${_new_marks}${_s}
"
  done <<EOF
$(_designed_in < "$_ov")
EOF
fi
for _f in .specops/memory/api-spec.md .specops/memory/data-model.md; do
  [ -f "$_f" ] && grep -q '^<!-- specops:init-designed: ' "$_f" || continue
  git show "HEAD:$_f" 2>/dev/null | grep -q '^<!-- specops:init-designed: ' && continue
  _new_if="${_new_if}${_f}
"
done
_demoted=""; _rv_state=""
if [ -n "$_new_marks$_new_if" ]; then
  _verdict=""
  [ -f "$_rv" ] && [ ! -L "$_rv" ] && _verdict=$(grep -m1 -E '^DESIGN-REVIEW-RESULT: (PASS|FAIL|SKIP)[[:space:]]*$' "$_rv" 2>/dev/null | awk '{ print $2 }')
  case "$_verdict" in
    PASS) _rv_state="PASS" ;;
    FAIL) _rv_state="리뷰 FAIL — 이슈가 걸린 것" ;;
    SKIP) _rv_state="리뷰 SKIP" ;;
    *)    _rv_state="리뷰 보고서 없음 — $_rv" ;;
  esac
  if [ "$_verdict" != "PASS" ]; then
    _issues=""
    [ "$_verdict" = "FAIL" ] && _issues=$(grep -E '^[[:space:]]*-[[:space:]]*\[(Critical|Important)\]' "$_rv" 2>/dev/null || true)
    while IFS= read -r _s; do
      [ -n "$_s" ] || continue
      # FAIL 이면 이슈 줄이 그 화면을 가리킬 때만 내린다(이름은 영숫자·-·_ 라 정규식 메타가 없다)
      if [ "$_verdict" = "FAIL" ] && ! printf '%s\n' "$_issues" | grep -qE "(^|[^A-Za-z0-9_-])${_s}([^A-Za-z0-9_-]|\$)"; then continue; fi
      N="$_s" awk '
        /^<!-- screens-table:start -->/ { inside=1 } /^<!-- screens-table:end -->/ { inside=0 }
        inside && /^\|/ {
          split($0, f, "|"); n = f[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", n)
          if (n == ENVIRON["N"]) sub(/init 설계 완료/, "init 보강")
        }
        { print }' "$_ov" > "$_ov.tmp" && mv "$_ov.tmp" "$_ov" && _demoted="${_demoted}${_demoted:+ }${_s}"
    done <<EOF
$_new_marks
EOF
    while IFS= read -r _f; do
      [ -n "$_f" ] || continue
      if [ "$_verdict" = "FAIL" ] && ! printf '%s\n' "$_issues" | grep -qE 'api-spec|data-model'; then continue; fi
      grep -v '^<!-- specops:init-designed: ' "$_f" > "$_f.tmp" && mv "$_f.tmp" "$_f" && _demoted="${_demoted}${_demoted:+ }${_f##*/}"
    done <<EOF
$_new_if
EOF
  fi
fi

# 재-add — Phase 10 과 같은 범위(lib.sh `_init_stage_own`): enrich 가 고친 산출물을 다시 stage 한다.
#   범위 밖(미리 stage 돼 있던 무관한 파일 · 화면 목록에 없는 screens/ 파일)과 보류 기록(.init-hold)의
#   파일은 건드리지 않는다 — 아래 커밋도 경로를 지정하므로 인덱스의 나머지는 그대로 남는다.
_init_stage_own

# 판정 실패(rc≠0)를 "대상 없음"으로 읽지 않는다 — git 오류가 no-op 성공으로 둔갑하면 산출물이 staged 로
#   남은 채 "종결됐다"고 보고하게 된다(독립 리뷰 재현).
if ! _own=$(_init_staged_own); then
  echo "init-finalize: staged 산출물을 판정하지 못했습니다 (git diff 실패) — 커밋하지 않았습니다" >&2
  exit 1
fi
if [ -z "$_own" ]; then
  # 쓴 파일의 기록은 여기서도 닫는다 — 커밋할 것이 없으면 이번 부트스트랩의 산출물은 이미 커밋돼 있다
  #   (손으로 커밋한 경우 포함). 남겨 두면 다음 실행이 그 경로의 사용자 수정분을 init 의 것으로 본다.
  #   보류 기록(.init-hold)은 남긴다 — 보류된 파일이 아직 미커밋이면 다음 호출이 쓸어 담지 않아야 한다.
  rm -f "$INIT_WRITTEN_FILE" 2>/dev/null
  echo "init-finalize: 커밋 대상 없음 — 이미 종결됐거나 변경이 없습니다 (no-op)"
  exit 0
fi

# ── 보강 누락 차단 (20261113) — 이번 부트스트랩이 쓴 문서에 한한다 ──
# 왜: 미채움은 제목과 출력으로 알리기만 했다. Phase 11(보강)을 통째로 건너뛰어도 골격·예시가 기준 문서로 커밋됐다.
#   막는 범위는 좁다 — **이번 부트스트랩이 쓴 파일**(.init-written · 아직 HEAD 에 없는 것)에서
#   ① 예시 블록(`specops:example`)이 남았거나 ② 깊게 보강하는 문서에 원시 자리표시자가 남았을 때만이다.
#   init 이 쓰지 않은 문서(기존 문서 · 소급 보강 --enrich · 손으로 커밋한 뒤)는 종전대로 알리기만 한다:
#   성숙한 문서의 `<cmd>` 같은 표기를 스캐너가 자리표시자로 세기 때문이다. 얕게 두는 문서(헌법·테스트 전략·
#   CLAUDE·README)의 자리표시자도 막지 않는다. 골격만 커밋하려면 SPECOPS_INIT_ALLOW_UNFILLED=1.
_is_deep() {
  case "$1" in
    PRD.md|DESIGN.md|.specops/memory/requirements.md|.specops/memory/api-spec.md|.specops/memory/data-model.md) return 0 ;;
    .specops/memory/frontend-architecture.md|.specops/memory/backend-architecture.md|.specops/memory/process-design.md) return 0 ;;
  esac
  return 1
}
if [ "${SPECOPS_INIT_ALLOW_UNFILLED:-0}" != "1" ] && [ -f "$_DIR/scan-enrich-placeholders.sh" ]; then
  _blk=""
  while IFS= read -r _p; do
    case "$_p" in *.md) ;; *) continue ;; esac
    [ -f "$_p" ] && _init_written_fresh "$_p" || continue
    _sc=$(bash "$_DIR/scan-enrich-placeholders.sh" "$_p" 2>/dev/null); _sc_rc=$?
    [ "$_sc_rc" = "1" ] || continue
    _e=$(printf '%s\n' "$_sc" | grep -c '\[example-block\]' || true)
    _h=0; _is_deep "$_p" && _h=$(printf '%s\n' "$_sc" | grep -v '\[example-block\]' | grep -c . || true)
    [ "${_e:-0}" -gt 0 ] || [ "${_h:-0}" -gt 0 ] || continue
    _blk="${_blk}  - ${_p}:"
    [ "${_h:-0}" -gt 0 ] && _blk="${_blk} 자리표시자 ${_h}건"
    [ "${_e:-0}" -gt 0 ] && _blk="${_blk} 예시 블록 ${_e}건"
    _blk="${_blk}
"
  done <<EOF
$_own
EOF
  if [ -n "$_blk" ]; then
    echo "init-finalize: 보강이 끝나지 않았습니다 — 커밋하지 않았습니다 (산출물은 staged 그대로)" >&2
    printf '%s' "$_blk" >&2
    echo "  줄 단위 목록: bash \"\${CLAUDE_PLUGIN_ROOT}\"/scripts/_internal/scan-enrich-placeholders.sh <파일>" >&2
    echo "  Phase 11 보강으로 실제 값·\`가정:\`·미확정 마커 중 하나로 채우고 예시 블록은 마커째 지운 뒤 다시 실행하세요." >&2
    echo "  골격 그대로 커밋하려면: SPECOPS_INIT_ALLOW_UNFILLED=1 bash \"\${CLAUDE_PLUGIN_ROOT}\"/scripts/_internal/init-finalize.sh" >&2
    exit 1
  fi
fi

# 진행 기록 — 미호출 검출의 근거(검출형). /init-project 는 FID 가 없으므로
#   규약 형식(YYYYMMDD-kebab-slug)을 만족하는 고정 slug 를 쓴다.
#   .specops/<FID>/ 디렉토리는 만들지 않는다 → /doctor orphan_fid 미발화.
# 왜 커밋 **앞**인가: 기록이 같은 커밋에 들어가야 종결 직후 tree 가 clean 하다
#   (spec §3). 커밋 뒤에 남기면 downstream 의 .specops/.gitignore 는 FID 디렉토리만
#   ignore 하므로(phases-artifacts.sh:190~194) session-progress.md 가 미커밋 수정분으로 남는다.
# 왜 가드 **뒤**인가: 커밋 대상이 없으면(no-op) 기록도 남기지 않는다 — 없는 종결을
#   기록하면 검출형 근거가 오염된다.
# 메모에 SHA·파일수를 넣지 않는 이유: 커밋 전이라 SHA 가 아직 없고, 파일수는 이 기록
#   파일 자신을 add 한 뒤에야 확정된다(아래 n) — 미리 센 값은 출력 (${n}파일) 과 어긋난다.
_fid="$(date +%Y%m%d)-init-project"
# 호출 **전** stale .bak 제거 — 실패 경로의 복원 소스 출처를 증명 가능하게 만든다.
#   append:108 의 cp 는 best-effort(`|| true`)라 **실패할 수 있고**, 그때 남아 있던 이전
#   세션의 .bak 은 우리 스냅샷이 아니다(F12). 미리 지워 두면 "복원 시점에 .bak 이 있다"
#   = "이번 실행의 cp 가 성공했다" 가 성립한다.
#   지워도 안전한 근거는 아래 성공 경로 주석과 같다 — 이 파일은 추적되지 않고, 내용은
#   커밋된 session-progress.md(=더 강한 복원원) 로 이미 대체 가능하다.
#   rm 자체가 실패할 수도 있으므로(예: .specops 가 읽기전용 — F13) 이것만으로는 부족하다.
rm -f .specops/session-progress.md.bak 2>/dev/null || true
bash "$_DIR/../session-progress-append.sh" "$_fid" /init-project 완료 \
  "부트스트랩 종결 커밋" "부트스트랩" >/dev/null 2>&1 || true
# 기록 실패가 커밋을 막지 않는다(|| true) — 커밋이 본질이고 기록은 보조다.
[ -f .specops/session-progress.md ] && git add .specops/session-progress.md

# 커밋 경로 = init 범위 안에서 staged 인 것(진행 기록 포함). 건수도 여기서 센다 — 인덱스 전체가 아니다.
cpaths=()
while IFS= read -r _p; do [ -n "$_p" ] && cpaths+=("$_p"); done <<EOF
$(_init_staged_own)
EOF
n=${#cpaths[@]}

# 남은 미채움을 센다 — 제목이 보강 여부를 지어내지 않게 한다.
#   종전엔 보강(Phase 11)을 건너뛰고 종결해도 제목이 "부트스트랩+enrich" 였다(20261009 재현: 미채움 152건 ·
#   예시 블록 2건이 그대로 커밋). 막지는 않는다: 얕게 두는 문서(헌법·테스트 전략 등)의 자리표시자는 계약상 남을 수
#   있고, 스캐너는 성숙한 문서의 `<cmd>` 같은 표기도 세므로 건수는 "0 이어야 한다"가 아니라 **보이게 하는 값**이다.
#   session-progress.md 는 세지 않는다 — 형식 안내 줄(`<YYYY-MM-DD HH:MM> <command> …`)이 자리표시자로 읽힌다.
_md=()
for _p in "${cpaths[@]}"; do
  case "$_p" in
    .specops/session-progress.md) ;;
    *.md) [ -f "$_p" ] && _md+=("$_p") ;;
  esac
done
# 스캔 결과는 셋 중 하나다: clean(0건) · found(건수 있음) · unknown(스캔하지 못함 — 문서 없음·스캐너 부재·오류).
#   unknown 을 0건으로 읽으면 고치려던 거짓 제목("+enrich")이 그대로 나온다(독립 리뷰 재현) — 주장하지 않는다.
_scan=""; _scan_state="unknown"
if [ ${#_md[@]} -gt 0 ] && [ -f "$_DIR/scan-enrich-placeholders.sh" ]; then
  _scan=$(bash "$_DIR/scan-enrich-placeholders.sh" "${_md[@]}" 2>/dev/null); _scan_rc=$?
  case "$_scan_rc" in
    0) _scan_state="clean" ;;
    1) _scan_state="found" ;;
  esac
fi
_n_ex=0; _n_ph=0
if [ "$_scan_state" = "found" ]; then
  _n_ex=$(printf '%s\n' "$_scan" | grep -c '\[example-block\]' || true)
  _n_ph=$(printf '%s\n' "$_scan" | grep -v '\[example-block\]' | grep -c . || true)
fi
case "$_scan_state" in
  clean) _title="chore(init): /init-project 부트스트랩+enrich (${n}종)" ;;
  found)
    _left=""
    [ "${_n_ph:-0}" -gt 0 ] && _left="미채움 ${_n_ph}건"
    [ "${_n_ex:-0}" -gt 0 ] && _left="${_left}${_left:+ · }예시 블록 ${_n_ex}건"
    _title="chore(init): /init-project 부트스트랩 (${n}종 · ${_left:-미채움 있음})" ;;
  *) _title="chore(init): /init-project 부트스트랩 (${n}종)" ;;
esac
if ! out=$(git commit -q -m "$_title" -- "${cpaths[@]}" 2>&1); then
  # 기록 되돌리기 — FR-5/AC-5 는 기록을 **커밋 성공**에 조건부로 둔다(spec.md:62 "성공 시",
  #   acceptance-criteria.md:71 Given). 실패했는데 "완료" 가 남으면 검출형 근거 자체가
  #   거짓이 되고, 재시도는 분(分)이 바뀌면 append 멱등키(%H:%M)를 벗어나 줄이 하나 더 는다.
  #   session-progress-append.sh:108 이 prepend 직전 남긴 .bak 이 정확히 append 이전 상태다.
  #   git reset 은 쓰지 않는다 — 다른 산출물의 staged 보존이 계약이므로, 복원본을 재-add 해
  #   인덱스에서도 거짓 줄을 지운다.
  #   ★ 출처 2중 확인 후에만 복원한다. append 는 총체적으로 실패해도 마지막 echo 때문에
  #     rc=0 으로 끝나므로(실측) 종료코드는 근거가 못 된다. 그래서 ①위에서 stale .bak 을
  #     미리 지웠고(존재 = 이번 실행의 cp 성공), ②우리 기록이 파일에 **실재**하는지 본다.
  #     둘 중 하나만으로는 못 막는다: ① 은 rm 이 실패하는 읽기전용 .specops 에서 뚫리고(F13),
  #     ② 는 백업 cp 만 실패한 경우에 뚫린다(F12 — 기록은 남았으니 grep 은 통과한다).
  #     검증 실패 시엔 복원하지 않는다 — 남의 스냅샷으로 워킹트리·인덱스를 덮는 것이
  #     거짓 기록 한 줄보다 크게 나쁘다(그 경우 append 가 실패했으니 거짓 줄도 없다).
  if [ -f .specops/session-progress.md.bak ] &&
     grep -q '/init-project 완료' .specops/session-progress.md 2>/dev/null; then
    cp .specops/session-progress.md.bak .specops/session-progress.md 2>/dev/null &&
      git add .specops/session-progress.md 2>/dev/null || true
  fi
  echo "init-finalize: git commit 실패" >&2
  [ -n "$out" ] && echo "  사유: $out" >&2
  echo "  산출물은 staged 로 보존됩니다 — 손실 없음" >&2
  echo "  재시도: bash \"\${CLAUDE_PLUGIN_ROOT}\"/scripts/_internal/init-finalize.sh" >&2
  exit 1
fi

# 자기 잔여물 회수 — 커밋 **성공** 이후에만. spec §3 기대결과는 "커밋 1건 + git status clean"
#   인데, 위 append 가 남긴 .bak(session-progress-append.sh:108, prepend 직전 1세대 백업)이
#   downstream 에 `?? .specops/session-progress.md.bak` 로 남아 그 절반을 깼다(Phase B 실측).
#   downstream .specops/.gitignore 는 FID 디렉토리 패턴만 만들므로(phases-artifacts.sh:190~194)
#   이 파일은 걸러지지 않는다. init 종결 경로에서 append 를 부르는 건 이 스크립트뿐이니
#   회수도 여기가 한다 — append 의 백업 계약(AC-1~3)은 건드리지 않는다.
# 왜 무조건인가(호출 전 존재 여부를 따지지 않는 이유): append:108 의 cp 는 **무조건 덮어쓰기**라
#   이 지점의 .bak 내용물은 언제나 우리가 만든 직전 스냅샷이다. 남의 데이터는 이미 append 가
#   지웠으므로 "호출 전에 있었으면 보존" 가드는 데이터가 아니라 **파일명만** 지키면서,
#   정작 F8 실패→재시도(위 안내문) 경로에서 .bak 이 살아남은 채 재시도가 성공하면
#   같은 위반을 그대로 재현한다.
# 안전 근거: 이 .bak 은 어디서도 추적되지 않고(git ls-files 0건) 커밋 성공 시점엔 그 내용이
#   이미 커밋에 들어가 있다 — ensure-session-progress 의 .bak 복원(AC-3)보다 git 이 강한 복원원이다.
# 실패 경로는 위 if 블록 안에서 .bak 을 복원 소스로 쓰고 끝나므로 이 줄에 닿지 않는다.
if [ -f .specops/session-progress.md.bak ]; then
  rm -f .specops/session-progress.md.bak
fi

sha=$(git rev-parse --short HEAD)
echo "init-finalize: 커밋 완료 ${sha} (${n}파일)"

# 내린 설계 완료 표지를 알린다 — 조용히 내리면 사용자는 /start-all 이 왜 다시 설계하는지 모른다.
[ -n "$_demoted" ] && echo "init-finalize: 설계 완료 표지를 내렸습니다(${_rv_state}) — ${_demoted}. 이 화면·인터페이스는 /start-all Phase 2.5 가 다시 설계·리뷰합니다."

# FR 이 마일스톤 시드 3행 그대로면 알린다 — 시드는 실제 문구라 미채움 스캔에 잡히지 않고, 그대로 두면 batch 에
#   마일스톤 3개가 FR 3개로 들어간다(M1 분해 누락). 막지 않는다: 마일스톤이 곧 FR 인 작은 프로젝트가 있다.
_rq=".specops/memory/requirements.md"
if printf '%s\n' "${cpaths[@]}" | grep -qxF -- "$_rq" && grep -q '^<!-- seed-fr: FR-1,FR-2,FR-3 -->' "$_rq" 2>/dev/null \
   && [ "$(grep -cE '^\| *FR-[0-9]+ *\|' "$_rq" 2>/dev/null || true)" = "3" ]; then
  echo "init-finalize: 요구사항이 마일스톤 시드 3행(FR-1~3) 그대로입니다 — 첫 마일스톤(M1)의 FR 분해가 빠졌을 수 있습니다 (보강: /init-project --enrich)"
fi

# 단계별 소요 — 표시(`init-project.sh --mark`)가 있을 때만. 값은 앞 표시부터 그 표시까지 걸린 시간이다.
_tm=$(_init_timing_summary 2>/dev/null || true)
[ -n "$_tm" ] && echo "init-finalize: 단계별 소요 — $_tm"

# 남은 미채움을 문서별로 알린다(많은 순 5개). 보강을 건너뛴 종결이 조용히 지나가지 않게 한다.
if [ "${_n_ph:-0}" -gt 0 ]; then
  _by=$(printf '%s\n' "$_scan" | grep -v '\[example-block\]' | grep . | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 \
        | awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "%s%s %s", (NR > 1 ? " · " : ""), $0, n }')
  echo "init-finalize: 미채움 자리표시자 ${_n_ph}건이 남아 있습니다 — ${_by} (보강: /init-project --enrich)"
fi
if [ "${_n_ex:-0}" -gt 0 ]; then
  echo "init-finalize: 예시 블록 ${_n_ex}건이 남아 있습니다(api-spec·data-model·architecture 의 샘플) — Phase 11 보강이 수행되지 않았을 수 있습니다"
fi

if [ "$_scan_state" = "unknown" ] && [ ${#_md[@]} -gt 0 ]; then
  echo "init-finalize: 미채움 스캔을 하지 못했습니다(스캐너 부재·오류) — 보강 여부를 제목에 적지 않았습니다"
fi

# 커밋에 넣지 않은 것을 알린다 — 조용히 빼면 "왜 안 들어갔나"를 사용자가 뒤늦게 찾는다.
_brief() {   # 줄단위 목록 → 앞 5개 + "외 N개"
  local list="$1" total
  total=$(printf '%s\n' "$list" | grep -c . || true)
  printf '%s' "$(printf '%s\n' "$list" | head -5 | tr '\n' ' ')"
  [ "${total:-0}" -gt 5 ] && printf '외 %s개' "$((total - 5))"
  return 0
}
if [ -f "$INIT_HOLD_FILE" ]; then
  _held=$(grep . "$INIT_HOLD_FILE" 2>/dev/null || true)
  [ -n "$_held" ] && echo "init-finalize: init 이 쓰지 않은 기존 파일의 미커밋 내용은 커밋에 넣지 않았습니다(확인 후 직접 커밋): $(_brief "$_held")"
  rm -f "$INIT_HOLD_FILE"
fi
# 이번 부트스트랩이 쓴 파일의 기록도 닫는다 — 종결됐으니 다음 실행은 새 부트스트랩이다.
rm -f "$INIT_WRITTEN_FILE" "$INIT_TIMING_FILE" .specops/.init-answers 2>/dev/null
_rest=$(git diff -z --cached --name-only 2>/dev/null | tr '\0' '\n' || true)
[ -n "$_rest" ] && echo "init-finalize: init 과 무관한 staged 파일은 커밋하지 않고 그대로 두었습니다: $(_brief "$_rest")"
# 화면 파일 형식(.md·.html)만 알린다 — 기존 앱의 screens/ 소스(.tsx 등)는 애초에 init 의 대상이 아니다.
_scr=$(git -c core.quotePath=false status --porcelain -uall -- 'screens/*.md' 'screens/*.html' 2>/dev/null | sed 's/^...//' || true)
[ -n "$_scr" ] && echo "init-finalize: screens/ 의 다음 파일은 화면 목록(screens-overview.md)에 없거나 보류돼 커밋하지 않았습니다: $(_brief "$_scr")"
exit 0
