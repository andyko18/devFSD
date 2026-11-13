#!/usr/bin/env bash
# 검증 판정 단일 SoT.
# Usage:
#   verification-state.sh current <FID>
#   verification-state.sh stale-scope <FID>     (STALE 의 범위 — untracked-only | changed)
#   verification-state.sh record <FID> <NOT_RUN|PASS|PARTIAL|FAIL|WAIVED> [options]
# 신규 FID는 verification-state.json을 우선하며, 기존 evidence stamp는 읽기 호환만 제공한다.
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"

# 파일 분류 단일 SoT (20260912-verify-stale-docs-scope).
#   ★ ${BASH_SOURCE[0]%/*} 로 해석한다 — .githooks/pre-push 가 이 파일을 **상대경로**로 source 하므로
#     $0 기반 해석은 깨진다. 슬래시 없는 source 면 이 확장이 파일명을 그대로 돌려주어 source 가
#     실패하는데, 아래 가드가 fail-safe(전건 비문서=지문 확대)로 받는다.
_VS_DIR="${BASH_SOURCE[0]%/*}"
if [ -f "$_VS_DIR/file-class.sh" ]; then
  # shellcheck source=/dev/null
  . "$_VS_DIR/file-class.sh"
else
  echo "verification-state: file-class.sh 로드 실패 — 전건 비문서로 판정한다" >&2
  fc::is_doc() { return 1; }
  fc::is_plugin_repo() { return 1; }
fi

vs::valid_fid() {
  printf '%s' "$1" | grep -qE '^[0-9]{8}-[a-z0-9-]+$'
}

vs::valid_verdict() {
  case "$1" in
    NOT_RUN|PASS|PARTIAL|FAIL|WAIVED) return 0 ;;
    *) return 1 ;;
  esac
}

# 워크스페이스 내용 지문 — HEAD 문자열이 아니라 임시 인덱스의 write-tree 해시.
# 동일 내용을 커밋해도 지문이 바뀌지 않아 verify→commit 정상 흐름이 STALE로 뒤집히지 않는다.
# .specops 는 검증 기록 자기오염을 막기 위해 제외한다.
vs::workspace_fingerprint() {
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf 'NO_GIT'
    return 0
  fi
  local idx tree add_rc unborn=""
  idx=$(mktemp "${TMPDIR:-/tmp}/vs-idx.XXXXXX") || { printf 'NO_GIT'; return 0; }
  # 저장소 인덱스 비오염: GIT_INDEX_FILE 격리. unborn HEAD 도 add→write-tree 로 식별.
  GIT_INDEX_FILE="$idx" git read-tree HEAD >/dev/null 2>&1 || true
  # unborn HEAD(첫 커밋 전)는 mktemp 가 만든 0바이트 인덱스를 git 이 손상으로 보아 add 가 rc 128 이 된다 — 읽을 수 없는 파일 때문이
  #   아니므로 UNHASHABLE 로 분류하지 않는다(종전 퇴행 지문 유지 — 새 repo 의 첫 커밋을 R-1 이 STALE 로 막으면 안 된다).
  git rev-parse --verify -q HEAD >/dev/null 2>&1 || unborn=1
  add_rc=0
  # add.ignoreErrors=true 면 읽을 수 없는 파일이 rc 128 대신 rc 1 로 조용히 건너뛰어진다 — 끈다.
  GIT_INDEX_FILE="$idx" git -c add.ignoreErrors=false add -A -- . ':(exclude).specops' >/dev/null 2>&1 || add_rc=$?
  # rc 1 = ".gitignore 가 무시하는 경로" 안내다 — 인덱스는 정상 갱신되고, .specops 가 ignore 인 repo(이 repo)에선 항상 1 이다.
  # rc 2 이상은 fatal(읽을 수 없는 파일 등) — 인덱스가 HEAD 로 퇴행해 비문서 변경이 지문에 안 보인다.
  #   NO_GIT 과 구분되는 전용 값을 낸다: NO_GIT 은 "비교 근거 없음 → STALE 안 만듦" 이라 실패를 그 값으로 내면
  #   실패 상태에서 기록된 PASS·receipt 가 영영 STALE 이 되지 않는다. 소비자는 UNHASHABLE 을 일치로 보지 않는다.
  [ "$add_rc" -le 1 ] || [ -n "$unborn" ] || { rm -f "$idx"; printf 'UNHASHABLE'; return 0; }
  tree=$(GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null) || tree=""
  rm -f "$idx"
  if [ -n "$tree" ]; then
    printf '%s' "$tree"
  else
    printf 'NO_GIT'
  fi
}

# 비문서 지문 — 문서 전용 변경에는 불변이다 (20260912-verify-stale-docs-scope).
#   왜 별도 함수인가: vs::workspace_fingerprint 는 pre-push 마커·receipt 가 "이 트리가 통과했다" 는
#   진술로 쓰던 값이다. 의미를 바꾸지 않고 **비문서 한정 지문을 추가**해, 소비자가 어느 의미를
#   원하는지 호출부에서 드러나게 한다.
#   왜 과거 트리를 조회하지 않는가: write-tree 산출 트리는 어떤 ref 에서도 도달 불가라 git gc 대상이다
#   (실측: 이 저장소 기록 55건 중 3건이 이미 소실). 기록 시점에 지문을 남겨야 대조가 성립한다.
#   $1 = tracked 면 **추적 중이거나 인덱스에 오른 경로만** 본다(vs::stale_scope 전용 — 아래 주석). 무인자는 종전 그대로다.
vs::nondoc_fingerprint() {
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf 'NO_GIT'
    return 0
  fi
  local idx plugin_rc=1 line f out="" top add_rc unborn="" mode="${1:-all}" ridx
  idx=$(mktemp "${TMPDIR:-/tmp}/vs-nidx.XXXXXX") || { printf 'NO_GIT'; return 0; }
  # ★ 저장소 루트에 앵커한다 — pathspec `.` 과 `:(exclude).specops` 는 **cwd 상대**라
  #   서브디렉터리에서 부르면 그 아래만 열거된다. workspace_fingerprint 는 같은 트리면 cwd 와
  #   무관하게 같은 값을 주는데 nondoc 만 갈리면, 기록 cwd ≠ 조회 cwd 일 때 가짜 STALE·
  #   `tree stale` 오거부가 나고 반대로 같은 서브디렉터리끼리면 바깥 코드 변경을 못 본다
  #   (실측: 루트 c372baae vs sub fd7dce69 — 같은 트리인데 다름). Phase C I-3.
  # ★ exclude 는 **long-form magic 안에 `top` 을 넣어야** 루트 기준이 된다.
  #   종전 `':(exclude,glob):/.specops/**'` 는 무효였다 — long-form `(exclude,glob)` **뒤의 `:/` 는
  #   short-magic 으로 재해석되지 않고** 나머지가 리터럴 패턴 `:/.specops/**` 가 되어 아무것도 안 걸린다.
  #   실측(git 2.50.1): 그 형태로는 미추적 `.specops/x/new.json` 과 수정된 `.specops/state.json` 이
  #   임시 인덱스에 **그대로 들어왔다**(루트·서브 양쪽). chain 코드리뷰 I-1.
  #   ※ `top` 을 써도 **추적된** `.specops/*` 는 남는다 — `read-tree HEAD` 로 이미 들어온 분이라
  #     add 의 pathspec 이 손대지 않기 때문이다(workspace_fingerprint 와 같은 성질).
  #     exclude 가 실제로 막는 것은 **미추적 신규 파일**이다.
  #   ※ 그래서 이 pathspec 은 지문의 정확성을 혼자 책임지지 않는다 — 아래 루프의 `fc::is_doc` 이
  #     `^\.specops/` 를 문서로 걸러 최종 방어를 한다(실측: 두 경우 모두 지문 불변).
  #     둘 중 하나만 믿지 말 것. 분류 패턴이 바뀌면 이 pathspec 이 유일한 방어가 된다.
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { rm -f "$idx"; printf 'NO_GIT'; return 0; }
  GIT_INDEX_FILE="$idx" git -C "$top" read-tree HEAD >/dev/null 2>&1 || true
  git -C "$top" rev-parse --verify -q HEAD >/dev/null 2>&1 || unborn=1   # unborn HEAD 취급은 vs::workspace_fingerprint 의 주석 참조
  add_rc=0
  if [ "$mode" = "tracked" ]; then
    # **실 인덱스를 복사**해 그 경로들만 작업트리 내용으로 갱신한다(add -u). 임시 인덱스의 경로 집합이 실 인덱스와 같아야 한다:
    #   staged 신규·intent-to-add 는 들어가고, 인덱스에서 뺀 파일(`git rm`·`git rm --cached` — 커밋이 그 파일을 지운다)은 빠지고,
    #   아무 데도 오르지 않은 untracked 파일은 처음부터 없다. HEAD 에서 시작하면 인덱스에서 뺀 파일이 임시 인덱스에 남아
    #   "달라지지 않았다" 고 답한다. 복사·갱신이 조금이라도 실패하면 add_rc 가 2 로 남아 아래에서 UNHASHABLE 이 된다.
    add_rc=2; unborn=""   # 이 모드에는 unborn 예외가 없다 — 실 인덱스는 첫 커밋 전에도 유효하고, 실패는 언제나 UNHASHABLE 이다
    ridx=$(git -C "$top" rev-parse --git-path index 2>/dev/null) || ridx=""
    case "$ridx" in ""|/*) ;; *) ridx="$top/$ridx" ;; esac
    # 사본의 mtime 을 원본에 맞춘다 — git 은 "항목 mtime ≥ 인덱스 파일 mtime" 이면 내용을 다시 비교하는데(racy-clean),
    #   방금 만든 사본은 mtime 이 지금이라 그 보호가 꺼진다: 인덱스에 오른 것과 같은 초에 같은 크기로 고친 파일을 놓친다.
    if [ -n "$ridx" ] && [ -f "$ridx" ] && cp "$ridx" "$idx" 2>/dev/null && touch -r "$ridx" "$idx" 2>/dev/null; then
      GIT_INDEX_FILE="$idx" git -C "$top" -c add.ignoreErrors=false add -u -- ':/' >/dev/null 2>&1 && add_rc=0
    fi
  fi
  [ "$mode" = "tracked" ] || GIT_INDEX_FILE="$idx" git -C "$top" -c add.ignoreErrors=false add -A -- ':/' ':(exclude,glob,top).specops/**' >/dev/null 2>&1 || add_rc=$?
  # add rc 해석(0·1 정상 / 2 이상 UNHASHABLE)은 vs::workspace_fingerprint 의 주석 참조
  [ "$add_rc" -le 1 ] || [ -n "$unborn" ] || { rm -f "$idx"; printf 'UNHASHABLE'; return 0; }
  fc::is_plugin_repo && plugin_rc=0   # 루프 **밖에서 1회만** — 파일마다 부르면 프로세스를 스폰한다
  # ※ `--full-name` 은 `-C "$top"` 아래에서는 **중복**이다(실측: 서브디렉터리에서 유무 출력 동일).
  #   `-C` 가 없던 시절엔 필수였고 지금은 방어적 잉여다 — 남겨 두되 "필수" 라고 쓰지 않는다.
  #   (종전 주석이 "필수" 라고 단언했으나 근거가 없었다 — chain 코드리뷰 M-1.)
  # ★★ `-C "$top"` 도 필수다 — `ls-files` 는 **cwd 하위만 열거**한다. read-tree·add 만 앵커하고
  #   이 줄을 빠뜨리면 인덱스에는 전체가 들어와도 **목록이 cwd 아래로 잘려** 지문이 갈린다.
  #   실측(수정 전 HEAD): 같은 깨끗한 트리에서 루트 c5e6e0a9 vs sub fd7dce69, 그리고 루트 code.sh 를
  #   고쳐도 sub 에서는 값이 안 변했다(바깥 변경이 안 보임). Phase C 재판정이 이걸 잡았다 —
  #   78·79 만 고치고 "cwd 의존 제거" 라 적었던 것은 **거짓 주장**이었고, probe 재실행을 했으면 잡혔다.
  # ★ core.quotePath=false — 비ASCII 경로를 `"\355\225\234..."` 로 인용하지 않고 원문으로 낸다.
  #   인용되면 fc::is_doc 이 받는 이름이 실제 경로와 달라져 분류 근거가 흔들린다(M-2).
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    f=${line#*$'\t'}
    fc::is_doc "$f" "$plugin_rc" && continue
    out="${out}${line}"$'\n'
  done <<EOF
$(GIT_INDEX_FILE="$idx" git -C "$top" -c core.quotePath=false ls-files -s --full-name 2>/dev/null)
EOF
  rm -f "$idx"
  [ -z "$out" ] && { printf 'EMPTY'; return 0; }
  printf '%s' "$out" | shasum -a 256 | awk '{print $1}' | tr -d '\n'
}

# 통과 마커의 지문 신선도 — 마커 첫 줄(기록 시점 비문서 지문)이 지금 트리의 비문서 지문과 같은가 (20261113-commit-gate-related-evidence).
#   $1 = 마커 경로. rc 0 = 일치(stdout 에 지금 지문) · rc 1 = 불일치·판정 불가(stdout 에 사유 1줄). 판정이 애매하면 rc 1 이다.
#   소비자: full-suite-fresh.sh(.full-suite-pass) · related-suite-fresh.sh(.related-suite-pass) — 둘이 같은 판정을 두 벌로 갖고 있었다.
#   마커 부재·빈 첫 줄은 소비자가 자기 어휘("마커 부재"·"통과 기록 부재")로 먼저 막는다 — 여기 사유는 그 뒤의 공통 구간이다.
vs::marker_fresh() {
  local marker="$1" rec top unreadable now
  rec=$(head -1 "$marker" 2>/dev/null || printf '')
  [ -n "$rec" ] || { printf '마커가 비었거나 읽을 수 없음'; return 1; }
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { printf '현재 지문 산출 불가'; return 1; }
  # 지문 계산(git add -A)은 읽을 수 없는 untracked 파일이 있으면 통째로 실패하고 HEAD 지문으로 퇴행한다 — 비교 전에 막는다
  unreadable=$( git -C "$top" ls-files -o --exclude-standard -z 2>/dev/null \
    | while IFS= read -r -d '' _f; do [ -r "$top/$_f" ] || { printf x; break; }; done )
  [ -z "$unreadable" ] || { printf '읽을 수 없는 untracked 파일 — 지문 신뢰 불가'; return 1; }
  now=$( cd "$top" && vs::nondoc_fingerprint 2>/dev/null ) || now=""
  [ -n "$now" ] && [ "$now" != "NO_GIT" ] && [ "$now" != "UNHASHABLE" ] || { printf '현재 지문 산출 불가'; return 1; }
  [ "$rec" = "$now" ] || { printf '트리 변경 — 지문 불일치'; return 1; }
  printf '%s' "$now"
  return 0
}

vs::legacy_verdict() {
  local evidence="$1" verdict
  [ -f "$evidence" ] || { printf 'NOT_RUN'; return 0; }
  verdict=$(grep '^RUN-VERIFICATION-RESULT: ' "$evidence" 2>/dev/null | tail -1 | sed 's/^RUN-VERIFICATION-RESULT: //')
  vs::valid_verdict "$verdict" && printf '%s' "$verdict" || printf 'NOT_RUN'
}

vs::current() {
  local fid="$1"
  local state="$SPECOPS/$fid/verification-state.json"
  if [ ! -f "$state" ]; then
    vs::legacy_verdict "$SPECOPS/$fid/evidence.md"
    return 0
  fi

  local verdict recorded_hash current_hash expires now
  verdict=$(jq -r '.verdict // "NOT_RUN"' "$state" 2>/dev/null) || { printf 'NOT_RUN'; return 0; }
  vs::valid_verdict "$verdict" || { printf 'NOT_RUN'; return 0; }

  # WAIVED는 저장값이 아니라 조회 시점에 만료를 계산한다. 만료·메타 부재는 면제 종료.
  if [ "$verdict" = "WAIVED" ]; then
    expires=$(jq -r '.waiver.expires_at // empty' "$state" 2>/dev/null)
    if [ -z "$expires" ]; then
      printf 'NOT_RUN'
      return 0
    fi
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [[ "$now" > "$expires" ]]; then
      printf 'NOT_RUN'
      return 0
    fi
  fi

  # PASS 이후 변경 판정 — 문서 전용 변경은 무효화하지 않는다 (20260912-verify-stale-docs-scope).
  #   nondoc_hash 가 있으면 그것으로 비교하고, 없으면(구버전 기록) 종전 전체 지문 비교로 떨어진다.
  #   부재 시 방향은 **더 엄격한 쪽**이라 fail-safe 다 — 기존 기록이 갑자기 느슨해지지 않는다.
  #   둘 다 없으면(20261010-hashless-pass-stale) 일치를 확인할 수단이 없으므로 STALE 이다 — 아래 비교가 빈 값을 "다르다" 로 본다.
  if [ "$verdict" = "PASS" ]; then
    recorded_hash=$(jq -r '.nondoc_hash // ""' "$state" 2>/dev/null)
    if [ -n "$recorded_hash" ] && [ "$recorded_hash" != "NO_GIT" ]; then
      current_hash=$(vs::nondoc_fingerprint)
    else
      recorded_hash=$(jq -r '.tree_hash // ""' "$state" 2>/dev/null)
      current_hash=$(vs::workspace_fingerprint)
    fi
    # 읽을 수 없는 파일로 지문을 믿을 수 없는 상태 — 두 값이 같아도(UNHASHABLE == UNHASHABLE) 일치가 아니다.
    if [ "$recorded_hash" = "UNHASHABLE" ] || [ "$current_hash" = "UNHASHABLE" ]; then
      printf 'STALE'
      return 0
    fi
    # 기록에 비교할 지문이 없다 — 지금 트리와 같은지 확인할 수 없는 PASS 는 유효 PASS 가 아니다.
    #   record 는 지문을 항상 쓰므로 이 상태는 손으로 쓴(또는 깨진) 기록에서만 나온다. 종전에는 빈 값이 "비교 생략" 으로 흘러
    #   그런 기록이 영영 STALE 이 되지 않았고, 같은 기록을 stale-scope 는 `changed`(막는 쪽)로 읽어 두 조회의 방향이 갈렸다.
    #   NO_GIT 은 다르다: git 이 없는 프로젝트는 비교할 수단 자체가 없어 종전대로 STALE 을 만들지 않는다.
    #   그래서 이 비교에는 "기록이 비어 있지 않을 때만" 이라는 조건을 두지 않는다 — 빈 값은 어떤 지문과도 다르다.
    if [ "$recorded_hash" != "NO_GIT" ] && [ "$recorded_hash" != "$current_hash" ]; then
      printf 'STALE'
      return 0
    fi
  fi
  printf '%s' "$verdict"
}

# STALE 의 범위 (20261009) — `untracked-only` | `changed`.
#   untracked-only: 기록된 PASS 와 지금의 차이가 **추적하지 않는 파일**(로그·캐시·.DS_Store — 생겼거나 바뀌었거나)뿐이다.
#   판정: 지금의 추적 파일 지문이 기록된 추적 파일 지문(`tracked_nondoc_hash`)과 같다. 그 필드가 없는 기록(구버전)과
#   비교 근거가 없는 값(NO_GIT·UNHASHABLE)은 `changed` 다(막는 쪽). EMPTY 는 "추적 중인 비문서 파일이 없다" 는 실제 값이다.
#   소비자: R-1 훅(_vs_stale_blocks). `current` 의 답(STALE)은 바꾸지 않는다 — 작업트리 전체를 보는 다른 소비자가 있다.
vs::stale_scope() {
  local state="$SPECOPS/$1/verification-state.json" rec="" now=""
  [ -f "$state" ] && [ "$(jq -r '.verdict // ""' "$state" 2>/dev/null)" = "PASS" ] && rec=$(jq -r '.tracked_nondoc_hash // ""' "$state" 2>/dev/null)
  case "$rec" in NO_GIT|UNHASHABLE) ;; *) now=$(vs::nondoc_fingerprint tracked) ;; esac   # 빈 값(필드 없는 기록)은 아래 비교에서 어긋난다
  if [ -n "$now" ] && [ "$now" = "$rec" ]; then printf 'untracked-only'; else printf 'changed'; fi
}

vs::record() {
  local fid="$1" verdict="$2"; shift 2
  vs::valid_fid "$fid" || { echo "verification-state: invalid FID" >&2; return 1; }
  vs::valid_verdict "$verdict" || { echo "verification-state: invalid verdict: $verdict" >&2; return 1; }
  [ ! -L "$SPECOPS" ] || { echo "verification-state: $SPECOPS symlink 거부" >&2; return 1; }
  [ ! -L "$SPECOPS/$fid" ] || { echo "verification-state: FID symlink 거부" >&2; return 1; }

  local executed=0 skipped=0 failed=0 duration_ms=0
  local waiver_reason="" waiver_approved_by="" waiver_expires_at=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --executed) executed="${2:-}"; shift 2 ;;
      --skipped) skipped="${2:-}"; shift 2 ;;
      --failed) failed="${2:-}"; shift 2 ;;
      --duration-ms) duration_ms="${2:-}"; shift 2 ;;
      --waiver-reason) waiver_reason="${2:-}"; shift 2 ;;
      --waiver-approved-by) waiver_approved_by="${2:-}"; shift 2 ;;
      --waiver-expires-at) waiver_expires_at="${2:-}"; shift 2 ;;
      *) echo "verification-state: unknown option: $1" >&2; return 1 ;;
    esac
  done
  local n
  for n in "$executed" "$skipped" "$failed" "$duration_ms"; do
    printf '%s' "$n" | grep -qE '^[0-9]+$' || { echo "verification-state: numeric value required" >&2; return 1; }
  done
  if [ "$verdict" = "WAIVED" ]; then
    [ -n "$waiver_reason" ] && [ -n "$waiver_approved_by" ] && [ -n "$waiver_expires_at" ] \
      || { echo "verification-state: WAIVED requires reason, approved-by, expires-at" >&2; return 1; }
    [ ${#waiver_reason} -le 200 ] && [ ${#waiver_approved_by} -le 120 ] \
      || { echo "verification-state: waiver field too long" >&2; return 1; }
    printf '%s' "$waiver_expires_at" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
      || { echo "verification-state: invalid waiver expiry" >&2; return 1; }
  elif [ -n "$waiver_reason$waiver_approved_by$waiver_expires_at" ]; then
    echo "verification-state: waiver options require WAIVED verdict" >&2
    return 1
  fi

  mkdir -p "$SPECOPS/$fid" || return 1
  local target="$SPECOPS/$fid/verification-state.json"
  local tmp="$SPECOPS/$fid/.verification-state.$$.tmp"
  [ ! -L "$target" ] || { echo "verification-state: state file symlink 거부" >&2; return 1; }
  local ts head_sha tree
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  head_sha=$(git rev-parse HEAD 2>/dev/null || printf 'UNBORN')
  tree=$(vs::workspace_fingerprint)
  # 비문서 지문을 함께 남긴다 — 조회 시점에 과거 트리를 못 찾는 문제(gc)를 구조적으로 피한다.
  #   schema_version 은 올리지 않는다: 필드 부재가 곧 구버전이고 소비측이 종전 경로로 떨어진다.
  local nondoc tracked
  nondoc=$(vs::nondoc_fingerprint)
  # 추적 파일만의 지문 — stale-scope 가 "달라진 것이 추적하지 않는 파일뿐인가" 를 답하는 근거다(20261009).
  #   nondoc_hash 와 따로 남긴다: 검증 때 이미 untracked 파일(로그·.DS_Store)이 있던 트리에서는 둘이 다르다.
  tracked=$(vs::nondoc_fingerprint tracked)
  if [ "$tree" = "UNHASHABLE" ] || [ "$nondoc" = "UNHASHABLE" ]; then
    echo "verification-state: 지문 산출 불가(UNHASHABLE) — 읽을 수 없는 파일 등으로 git add 가 실패해 이 기록은 조회 시 STALE 로 읽힌다. git add -A -n 으로 원인(permission 오류 등)을 찾아 고치세요" >&2
  fi
  jq -n \
    --argjson schema_version 1 --arg fid "$fid" --arg verdict "$verdict" \
    --arg recorded_at "$ts" --arg head_sha "$head_sha" --arg tree_hash "$tree" \
    --arg nondoc_hash "$nondoc" --arg tracked_nondoc_hash "$tracked" \
    --argjson executed "$executed" --argjson skipped "$skipped" \
    --argjson failed "$failed" --argjson duration_ms "$duration_ms" \
    --arg waiver_reason "$waiver_reason" --arg waiver_approved_by "$waiver_approved_by" \
    --arg waiver_expires_at "$waiver_expires_at" \
    '{schema_version:$schema_version,fid:$fid,verdict:$verdict,recorded_at:$recorded_at,
      head_sha:$head_sha,tree_hash:$tree_hash,nondoc_hash:$nondoc_hash,tracked_nondoc_hash:$tracked_nondoc_hash,
      executed:$executed,skipped:$skipped,
      failed:$failed,duration_ms:$duration_ms,
      waiver:(if $verdict=="WAIVED" then
        {reason:$waiver_reason,approved_by:$waiver_approved_by,expires_at:$waiver_expires_at}
        else null end)}' > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$target"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  action="${1:-}"; fid="${2:-}"
  case "$action" in
    current)
      vs::valid_fid "$fid" || { echo "verification-state: invalid FID" >&2; exit 1; }
      vs::current "$fid"; printf '\n'
      ;;
    record)
      [ "$#" -ge 3 ] || { echo "usage: $0 record <FID> <verdict> [options]" >&2; exit 1; }
      shift 2
      vs::record "$fid" "$@"
      ;;
    stale-scope)
      vs::valid_fid "$fid" || { echo "verification-state: invalid FID" >&2; exit 1; }
      vs::stale_scope "$fid"; printf '\n'
      ;;
    *)
      echo "usage: $0 {current <FID>|stale-scope <FID>|record <FID> <verdict> [options]}" >&2
      exit 1
      ;;
  esac
fi
