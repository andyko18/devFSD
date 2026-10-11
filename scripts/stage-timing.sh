#!/usr/bin/env bash
# stage-timing.sh — session-progress 원장을 FID 간 단계별 소요로 집계한다 (읽기 전용 관측)
# Usage: bash scripts/stage-timing.sh [--since YYYYMMDD] [--gap-cap-min N] [--min-n N] [--split | --by-agent] [--transcript-dir DIR]
# rc: 0 = 집계 성공(구간 0건이어도 그 사실을 표시) · 2 = 원장 부재·읽기 불가·잘못된 인자
#
# 원장 규약: "## FID" 섹션 아래 "- YYYY-MM-DD HH:MM /cmd 상태 (...)" 행 (시각 = 로컬 · 분 해상도 — session-progress-append.sh).
# FID 단위 단계 소요는 show-fid-status.sh(/status)가 이미 낸다 — 이 스크립트는 FID 간 분포만 더한다.
# 행 단위 루프에서 외부 프로세스를 띄우지 않는다 — sort 1회 + awk 2회(일수 산술)로 끝낸다.
#
# --split: Claude Code transcript 의 구조 필드(turn_duration·origin.kind)로 각 구간을 작업·사람·백그라운드·기타로 쪼갠다.
#   transcript 본문은 읽지 않는다 — 읽는 일은 scripts/_internal/transcript-turns.sh(프라이버시 경계) 한 곳이 맡는다.
# --by-agent: --split 을 내포하고, 서브에이전트 transcript(세션폴더/subagents/agent-ID.jsonl + .meta.json)의 구조 필드로
#   서브에이전트 역할별 소요 표를 --split 표 뒤에 더한다. 읽는 일은 scripts/_internal/agent-spans.sh(프라이버시 경계) 한 곳이 맡는다.
set -u
# 프로토타입은 한글이 섞인 단계 키를 sort 하다 로케일(en_US.UTF-8)에 따라 그룹이 갈라져 표가 뒤섞였다(실측).
# 이 스크립트의 sort 키는 ASCII FID·숫자뿐이지만, awk 의 단계 이름 비교(동률 정렬)는 로케일을 따라 달라진다 —
# 비교 규칙을 바이트 순으로 고정한다(T1.g 가 잠근다).
export LC_ALL=C

SPECOPS="${SPECOPS_ROOT:-.specops}"
LEDGER="$SPECOPS/session-progress.md"
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SINCE=0; CAP=720; MINN=1; SPLIT=0; BYAGENT=0; TDIR=""; TDIRS=(); TDIR_MISS=0

die() { echo "stage-timing: $1" >&2; exit 2; }
need_val() { [ "$#" -ge 2 ] && [ -n "${2:-}" ] || die "$1 값 필요"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --since)
      need_val "$@"
      grep -qE '^[0-9]{8}$' <<< "$2" || die "--since 는 YYYYMMDD 여야 합니다: $2"
      SINCE="$2"; shift 2 ;;
    --gap-cap-min)
      need_val "$@"
      grep -qE '^[1-9][0-9]*$' <<< "$2" || die "--gap-cap-min 은 1 이상의 정수여야 합니다: $2"
      CAP="$2"; shift 2 ;;
    --min-n)
      need_val "$@"
      grep -qE '^[1-9][0-9]*$' <<< "$2" || die "--min-n 은 1 이상의 정수여야 합니다: $2"
      MINN="$2"; shift 2 ;;
    --split) SPLIT=1; shift ;;
    --by-agent) BYAGENT=1; SPLIT=1; shift ;;
    --transcript-dir) need_val "$@"; TDIRS+=("$2"); shift 2 ;;
    *) die "알 수 없는 옵션: $1" ;;
  esac
done

{ [ -f "$LEDGER" ] && [ -r "$LEDGER" ]; } || die "원장 없음 또는 읽기 불가: $LEDGER"
if [ "${#TDIRS[@]}" -gt 0 ]; then
  [ "$SPLIT" = 1 ] || die "--transcript-dir 는 --split 과 함께만 쓸 수 있습니다"
  for TDIR in "${TDIRS[@]}"; do [ -d "$TDIR" ] || die "--transcript-dir 가 디렉토리가 아닙니다: $TDIR"; done
  TDIR="${TDIRS[0]}"
fi

# --split 준비: 측정 불가 사유가 있으면 기존 표만 내고 끝에 사실 한 줄을 붙인다(오류 아님).
SPLIT_NA=""; SEG_FILES=()
if [ "$SPLIT" = 1 ]; then
  if ! command -v jq >/dev/null 2>&1; then
    SPLIT_NA="jq 없음"
  else
    if [ "${#TDIRS[@]}" -eq 0 ]; then
      # Claude Code 는 작업 디렉토리의 실경로에서 영숫자 아닌 글자를 '-' 로 바꾼 이름으로 세션을 모은다.
      #   ASCII 경로는 실제 이름과 대조했다. 비ASCII 는 바이트 단위(LC_ALL=C)와 문자 단위(UTF-8 로케일)가 갈려 둘 다 시도한다 — 규칙은 미검증.
      #   링크 worktree 의 세션은 worktree 경로로 인코딩된 다른 디렉토리에 있다 — 같은 저장소의 worktree 전부를
      #   합집합으로 읽는다(20261011: 이 저장소 10월 집계에서 기타 2325분 중 2323분이 "범위 밖"이었다 — 한 디렉토리만 읽어서).
      PROJ_ROOT="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/projects"
      ROOT_DIR=$(cd "$(dirname "$SPECOPS")" 2>/dev/null && pwd -P) || ROOT_DIR=""
      if [ -z "$ROOT_DIR" ]; then
        SPLIT_NA="원장 루트 경로를 해석할 수 없음 — --transcript-dir 로 지정하세요"
      else
        UTF8LOC=""
        for LOC in C.UTF-8 en_US.UTF-8; do
          if [ "$(LC_ALL=$LOC locale charmap 2>/dev/null)" = "UTF-8" ]; then UTF8LOC=$LOC; break; fi
        done
        # 후보 경로: 루트 + git worktree 목록(절대경로). git 부재·저장소 아님이면 루트 하나.
        CANDS=$(printf '%s\n' "$ROOT_DIR"; git -C "$ROOT_DIR" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
        ENC_B=$(printf '%s' "$ROOT_DIR" | sed 's/[^A-Za-z0-9]/-/g')
        OLD_IFS=$IFS; IFS='
'
        for CAND in $CANDS; do
          [ -n "$CAND" ] || continue
          CP=$(cd "$CAND" 2>/dev/null && pwd -P) || continue
          EB=$(printf '%s' "$CP" | sed 's/[^A-Za-z0-9]/-/g'); EC=""
          [ -n "$UTF8LOC" ] && EC=$(printf '%s' "$CP" | LC_ALL=$UTF8LOC sed 's/[^A-Za-z0-9]/-/g')
          if [ -d "$PROJ_ROOT/$EB" ]; then HIT="$PROJ_ROOT/$EB"
          elif [ -n "$EC" ] && [ -d "$PROJ_ROOT/$EC" ]; then HIT="$PROJ_ROOT/$EC"
          else TDIR_MISS=$((TDIR_MISS + 1)); continue; fi
          DUP=0; for X in "${TDIRS[@]:-}"; do [ "$X" = "$HIT" ] && DUP=1; done   # IFS 가 개행이라 ${TDIRS[*]} 문자열 대조는 쓸 수 없다
          [ "$DUP" = 1 ] || TDIRS+=("$HIT")
        done
        IFS=$OLD_IFS
        if [ "${#TDIRS[@]}" -gt 0 ]; then TDIR="${TDIRS[0]}"
        else TDIR="$PROJ_ROOT/$ENC_B"; SPLIT_NA="transcript 디렉토리 없음: $TDIR — --transcript-dir 로 지정하세요"; fi
      fi
      TDIR_NOTE="transcript 디렉토리 ${#TDIRS[@]}개 읽음: $(for d in "${TDIRS[@]:-}"; do [ -n "$d" ] && basename "$d"; done | paste -sd' ' -) · 대응 디렉토리 없는 worktree ${TDIR_MISS}개"
    else
      TDIR_NOTE="transcript 디렉토리 ${#TDIRS[@]}개 읽음"
    fi
    if [ -z "$SPLIT_NA" ]; then
      # 원장 최초 행 날짜 이후에 수정된 세션만 읽는다(그 전에 끝난 세션은 구간과 겹칠 수 없다).
      MINDATE=$(awk '/^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] \//{ if (min == "" || $2 < min) min = $2 } END { print min }' "$LEDGER")
      if [ -z "$MINDATE" ]; then
        SPLIT_NA="원장에 시각이 있는 행이 없음"
      else
        FILES_RAW=$(find "${TDIRS[@]}" -maxdepth 1 -type f -name '*.jsonl' -newermt "$MINDATE" 2>/dev/null | sort -u)
        if [ -n "$FILES_RAW" ]; then   # 줄 단위 분할로 배열을 채운다(경로의 공백 보존 · 글롭 해석 금지 · 행 단위 read 루프 없음)
          OLD_IFS=$IFS; IFS='
'
          set -f
          # shellcheck disable=SC2206
          SEG_FILES=($FILES_RAW)
          set +f; IFS=$OLD_IFS
        fi
        [ "${#SEG_FILES[@]}" -gt 0 ] || SPLIT_NA="원장 기간과 겹치는 세션 파일 0개: $TDIR"
      fi
    fi
  fi
fi

TAB=$(printf '\t')

# 세그먼트 생성(--split): 헬퍼의 사건 줄을 세션(파일)별로 짝지어 "시작·끝·범주" 줄(로컬 벽시계 초)로 낸다.
#   범주 M=작업(turn_duration 구간) · H=사람 · N=백그라운드 · U=미분류(턴 종료 뒤 다음 트리거 종류).
#   짝짓기는 같은 파일 안에서만 한다(파일 경계 F 에서 상태를 비운다) — 동시 세션의 사건이 엮이지 않게.
#   방치 상한을 넘는 유휴 구간은 세그먼트에서 빼고 건수·합계만 "#x" 줄로 남긴다. 직전 turn_duration 없는 트리거는 "#nod".
#   한 세션의 턴은 순차라 겹칠 수 없다 — 알림으로 재개된 턴의 durationMs 는 앞 턴 시작부터 누적될 수 있어(실측)
#   turn_duration 구간의 시작을 같은 파일의 직전 턴 끝 또는 직전 트리거(pend — 턴은 그 턴을 연 트리거보다 앞서 시작할 수 없다)로 잘라낸다.
seg_stream() (   # 서브셸 + pipefail — 헬퍼가 실패(읽을 수 없는 파일 등)하면 awk 의 rc 0 에 가려지지 않고 측정 불가로 보고한다
  set -o pipefail
  bash "$SELF_DIR/_internal/transcript-turns.sh" --local "${SEG_FILES[@]}" 2>/dev/null \
  | awk -F '\t' -v cap="$CAP" '
    BEGIN { capsec = cap * 60 }
    $2 == "F" { dend = ""; pend = ""; next }
    $2 == "D" { te = $1 + 0; tb = te - $3 / 1000; if (pend != "" && tb < pend) tb = pend; pend = te; if (tb < te) printf "%.3f\t%.3f\tM\n", tb, te; dend = te; next }
    {
      if ($2 == "U") nu++
      if (dend == "") { nod++; next }
      g = $1 - dend
      if (g > capsec) { xn[$2]++; xs[$2] += g } else if (g > 0) printf "%.3f\t%.3f\t%s\n", dend, $1, $2
      dend = ""; pend = $1 + 0
    }
    END {
      printf "#nod\t%d\n#u\t%d\n", nod + 0, nu + 0
      printf "#x\tH\t%d\t%d\n#x\tN\t%d\t%d\n#x\tU\t%d\t%d\n", xn["H"] + 0, xs["H"] + 0, xn["N"] + 0, xs["N"] + 0, xn["U"] + 0, xs["U"] + 0
    }'
)

SEG_OK=0; SEGTMP=""; AGTMP=""; BGTMP=""
trap 'rm -f "$SEGTMP" "$AGTMP" "$BGTMP"' EXIT

# 서브에이전트(--by-agent): 세션폴더/subagents/agent-*.jsonl 을 찾아 헬퍼로 에이전트당 1줄(시작·끝·wall·간격·역할)을 임시 파일에 낸다.
#   273MB 를 파싱해 약 4초가 걸려 세그먼트 생성과 병렬로 돌린다(wait 은 아래). --split 이 측정 불가면 그 사유를 그대로 따른다.
#   임시 파일에는 파생 숫자와 형식 검사를 통과한 역할 이름만 쓰인다.
AGENT_NA=""; AG_OK=0; AG_FILES=(); AG_CUT=""; AGENT_PID=""
if [ "$BYAGENT" = 1 ]; then
  if [ -n "$SPLIT_NA" ]; then
    AGENT_NA="$SPLIT_NA"
  else
    AG_NEWER=$MINDATE   # 파일 선별: --since 가 더 늦으면 그 날짜 이상으로(그 전에 끝난 파일에는 기준일 이후 시작한 에이전트가 있을 수 없다)
    if [ "$SINCE" != 0 ]; then AG_SD="${SINCE:0:4}-${SINCE:4:2}-${SINCE:6:2}"; if [[ "$AG_SD" > "$MINDATE" ]]; then AG_NEWER=$AG_SD; fi; fi
    AG_RAW=$(find "${TDIRS[@]}" -mindepth 3 -maxdepth 3 -type f -name 'agent-*.jsonl' -path '*/subagents/*' -newermt "$AG_NEWER" 2>/dev/null | sort -u)
    if [ -n "$AG_RAW" ]; then   # 줄 단위 분할(경로의 공백 보존 · 글롭 해석 금지)
      OLD_IFS=$IFS; IFS='
'
      set -f
      # shellcheck disable=SC2206
      AG_FILES=($AG_RAW)
      set +f; IFS=$OLD_IFS
    fi
    [ "${#AG_FILES[@]}" -gt 0 ] || AGENT_NA="서브에이전트 파일 0개: $TDIR"
  fi
  if [ -z "$AGENT_NA" ]; then
    AGTMP=$(mktemp "${TMPDIR:-/tmp}/stage-timing.XXXXXX" 2>/dev/null) || AGENT_NA="임시 파일을 만들 수 없음"
    [ -n "$AGENT_NA" ] || BGTMP=$(mktemp "${TMPDIR:-/tmp}/stage-timing.XXXXXX" 2>/dev/null) || AGENT_NA="임시 파일을 만들 수 없음"
  fi
  if [ -z "$AGENT_NA" ]; then
    AG_CUT=$SINCE; [ "$SINCE" != 0 ] || AG_CUT=${MINDATE//-/}
    ( bash "$SELF_DIR/_internal/agent-spans.sh" --local --gap-cap-min "$CAP" "${AG_FILES[@]}" > "$AGTMP" 2>/dev/null ) &
    AGENT_PID=$!
  fi
fi

if [ "$SPLIT" = 1 ] && [ -z "$SPLIT_NA" ]; then
  # 임시 파일에는 파생 숫자(시작·끝·범주)만 쓴다 — transcript 본문은 헬퍼 밖으로 나오지 않는다.
  SEGTMP=$(mktemp "${TMPDIR:-/tmp}/stage-timing.XXXXXX" 2>/dev/null) || SPLIT_NA="임시 파일을 만들 수 없음"
  if [ -z "$SPLIT_NA" ]; then
    seg_stream > "$SEGTMP" 2>/dev/null && SEG_OK=1 || SPLIT_NA="transcript 를 읽을 수 없음"
  fi
fi

if [ -n "$AGENT_PID" ]; then
  if wait "$AGENT_PID"; then AG_OK=1; else AGENT_NA="서브에이전트 transcript 를 읽을 수 없음"; fi
  if [ "$SEG_OK" != 1 ]; then AG_OK=0; AGENT_NA="$SPLIT_NA"; fi   # 본 표가 측정 불가가 되면(백그라운드 열 합을 비교할 수 없다) 사유를 따른다
fi

# 1단계: 원장 행 → "FID·분·줄번호·단계키·날짜"(탭 구분). 날짜는 일수 산술로 분으로 바꾼다.
#   (BSD awk 에는 mktime 이 없다.) 로컬 시각 그대로 쓴다 — 인접 차이는 오프셋이 상쇄된다.
#   유효 FID 섹션 안의 "- " 행이 형식에 안 맞거나 시각 범위 밖(월 1~12·일 1~31·HH<24·MM<60 위반)이면 건너뛰고 수만 센다
#   — 범위 밖 시각이 분으로 계산돼 방치 구간에 위장 흡수되지 않게 한다. 수는 FID 칸이 빈 행 1개로 다음 단계에 넘긴다.
# 2단계: FID·시각순 정렬. 동일 분은 줄번호 내림차순 — 섹션은 최신 우선이라 줄이 아래일수록 먼저 일어난 일이다.
#   같은 FID 가 여러 섹션에 흩어져도 한 시간선으로 합친다(FID 단위 소요 = /status 의미).
# 3단계: 인접 차이를 도착 행의 단계에 귀속해 집계한다.
awk '
function dn(y, m, d,   yy, mm) {
  yy = y - (m <= 2); mm = m + (m <= 2 ? 12 : 0)
  return 365 * yy + int(yy / 4) - int(yy / 100) + int(yy / 400) + int((153 * (mm - 3) + 2) / 5) + d
}
/^## / { fid = ($2 ~ /^[0-9]+-[a-z0-9-]+$/) ? $2 : ""; next }
/^- / {
  if (fid == "") next
  if ($0 !~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9] \/[a-z-]+/) { bad++; next }
  split($2, D, "-"); split($3, T, ":")
  if (D[2] + 0 < 1 || D[2] + 0 > 12 || D[3] + 0 < 1 || D[3] + 0 > 31 || T[1] + 0 > 23 || T[2] + 0 > 59) { bad++; next }
  printf "%s\t%d\t%d\t%s\t%s%s%s\n", fid, dn(D[1] + 0, D[2] + 0, D[3] + 0) * 1440 + (T[1] + 0) * 60 + (T[2] + 0), NR, $4 " " $5, D[1], D[2], D[3]
}
END { printf "\t%d\n", bad + 0 }' "$LEDGER" \
| sort -t "$TAB" -k1,1 -k2,2n -k3,3nr \
| STAGE_TIMING_LEDGER="$LEDGER" STAGE_TIMING_CAP="$CAP" STAGE_TIMING_TDIRNOTE="${TDIR_NOTE:-}" STAGE_TIMING_SEGFILE="$SEGTMP" STAGE_TIMING_BGFILE="$BGTMP" awk -v since="$SINCE" -v cap="$CAP" -v minn="$MINN" -v seg_ok="$SEG_OK" '
# 표시용 원장 경로·방치 상한은 ENVIRON 으로 받아 원문 그대로 쓴다 — awk -v 는 역슬래시 이스케이프를 해석하고,
# 거대 정수는 awk 구현마다 %d 표기가 갈린다. 비교용 숫자(cap·since·minn)는 -v 로 받는다.
function dn(y, m, d,   yy, mm) {
  yy = y - (m <= 2); mm = m + (m <= 2 ? 12 : 0)
  return 365 * yy + int(yy / 4) - int(yy / 100) + int(yy / 400) + int((153 * (mm - 3) + 2) / 5) + d
}
function isort(a, n,   gi, g, i, j, t) {   # Shell sort(Ciura 간격, n 이하만) — 삽입 정렬은 단계당 행 수에 이차(20,000행 15초 실측)
  for (gi = 1; gi <= ngap; gi++) {
    g = GAP[gi]; if (g > n) continue
    for (i = g + 1; i <= n; i++) { t = a[i]; for (j = i - g; j >= 1 && a[j] > t; j -= g) a[j + g] = a[j]; a[j + g] = t }
  }
}
function qn(a, n, p,   i) {   # nearest-rank: ceil(p% * n)
  i = int((p * n + 99) / 100); if (i < 1) i = 1; if (i > n) i = n
  return a[i]
}
function alloc(is, ie,   h, hb, he, nn, arr, i, idx, os, oe, c) {   # 구간 [is, ie) 와 겹친 세그먼트 초를 범주별로 aM·aH·aN·aU 에 모은다
  aM = 0; aH = 0; aN = 0; aU = 0
  hb = int(is / 3600); he = int((ie - 0.000001) / 3600)
  for (h = hb; h <= he; h++) {
    if (!(h in bkt)) continue
    nn = split(bkt[h], arr, " ")
    for (i = 1; i <= nn; i++) {
      idx = arr[i] + 0
      os = (sgs[idx] > is) ? sgs[idx] : is; oe = (sge[idx] < ie) ? sge[idx] : ie
      if (oe <= os) continue
      if (int(os / 3600) != h) continue   # 한 세그먼트가 여러 시간 버킷에 등록돼 있어도 겹침 시작이 속한 버킷에서 한 번만 센다
      c = sgc[idx]
      if (c == "M") aM += oe - os; else if (c == "H") aH += oe - os; else if (c == "N") aN += oe - os; else aU += oe - os
    }
  }
}
function fmt(sec,   dd, rs, z, era, doe, yoe, y, doy, mp, d, m) {   # 로컬 벽시계 초 → "YYYY-MM-DD HH:MM" (Hinnant civil_from_days)
  dd = int(sec / 86400); rs = sec - dd * 86400
  z = dd + 719468; era = int(z / 146097); doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100)); mp = int((5 * doy + 2) / 153)
  d = doy - int((153 * mp + 2) / 5) + 1; m = (mp < 10) ? mp + 3 : mp - 9; if (m <= 2) y++
  return sprintf("%04d-%02d-%02d %02d:%02d", y, m, d, int(rs / 3600), int((rs - int(rs / 3600) * 3600) / 60))
}
function lr4(v1, v2, v3, v4, wall,   vq, fl, fr, i, rem, b, bi, tot) {   # 큰 나머지법: 분 단위 정수 4개의 합이 wall 과 같게 반올림
  vq[1] = v1; vq[2] = v2; vq[3] = v3; vq[4] = v4; tot = 0
  for (i = 1; i <= 4; i++) { fl[i] = int(vq[i] + 0.000001); fr[i] = vq[i] - fl[i]; tot += fl[i] }
  rem = wall - tot
  while (rem > 0) {
    b = 0; bi = 0
    for (i = 1; i <= 4; i++) if (fr[i] > b + 0.0000001) { b = fr[i]; bi = i }
    if (bi == 0) { bi = 4 }   # 남은 몫이 없으면 기타에 얹는다
    fl[bi]++; fr[bi] = -1; rem--
  }
  o1 = fl[1]; o2 = fl[2]; o3 = fl[3]; o4 = fl[4]
}
BEGIN {
  FS = "\t"; ngap = split("701 301 132 57 23 10 4 1", GAP, " ")
  if (seg_ok == 1) {   # 세그먼트를 먼저 읽어 시간 버킷에 등록한다(표준입력은 원장 행 스트림이라 프로세스 치환 경로로 받는다)
    segf = ENVIRON["STAGE_TIMING_SEGFILE"]
    while ((getline line < segf) > 0) {
      nf = split(line, F, "\t")
      if (F[1] == "#nod") { nod = F[2] + 0 }
      else if (F[1] == "#u") { unn = F[2] + 0 }
      else if (F[1] == "#x") { xn[F[2]] = F[3] + 0; xs[F[2]] = F[4] + 0 }
      else { ns++; sgs[ns] = F[1] + 0; sge[ns] = F[2] + 0; sgc[ns] = F[3]; tot[F[3]] += F[2] - F[1]
             if (cmin == "" || sgs[ns] < cmin) cmin = sgs[ns]; if (cmax == "" || sge[ns] > cmax) cmax = sge[ns]
             for (h = int(sgs[ns] / 3600); h <= int((sge[ns] - 0.000001) / 3600); h++) bkt[h] = bkt[h] " " ns }
    }
    close(segf)
    U0 = dn(1970, 1, 1) * 1440
  }
}
$1 == "" { badn += $2; next }   # 1단계가 넘긴 무시 행 수
{
  rows[$1]++; last[$1] = $5
  if ($1 == pf) {
    d = $2 - pm
    if ($5 + 0 >= since + 0) {
      if (d > cap) { gapn++; gaps += d }
      else {
        n[$4]++; v[$4, n[$4]] = d; sum[$4] += d; total += d; cnt++
        if (seg_ok == 1) {
          is = (pm - U0) * 60; ie = ($2 - U0) * 60
          if (ns == 0 || ie <= cmin || is >= cmax) { outn++; outsum += d }   # transcript 시간 범위 밖 — 전부 기타
          alloc(is, ie)
          used = aM + aH + aN
          if (used > d * 60 + 60) { ovl[$4]++; ovn++ }                   # 원장 시각이 분 단위로 잘려 생기는 ±60초 오차는 겹침으로 세지 않는다
          else if (used > d * 60) { sc = d * 60 / used; aM *= sc; aH *= sc; aN *= sc }   # 허용오차 안의 초과는 비례 축소해 열 합 = wall 을 지킨다
          res = d * 60 - (aM + aH + aN)
          if (res < 0) res = 0
          tM[$4] += aM; tH[$4] += aH; tN[$4] += aN; aUall += (aU < res ? aU : res)   # 기타 중 미분류는 그 구간 기타를 넘지 않는다(동시 세션)
          tR[$4] += res
        }
      }
    }
  }
  pf = $1; pm = $2
}
END {
  for (f in rows) {   # since 이전에 끝난 FID(마지막 행 날짜 < since)는 대상에서 빼고 따로 센다
    if (since + 0 > 0 && last[f] + 0 < since + 0) { oldf++; continue }
    fidn++; if (rows[f] == 1) single++
  }
  printf "=== 단계별 소요 집계 (stage-timing) ===\n"
  printf "측정: 완료시각 인접 차이 · 분 해상도(0 = 1분 미만) · 사람 대기 포함 경과 시간(작업량 아님)\n"
  printf "      FID 경계 미교차 · 도착 행의 단계에 귀속 · DST·타임존 변경 경계 ±60분 오차 가능\n"
  if (seg_ok == 1) {
    printf "분리: 작업 = 에이전트 턴 진행 시간(모델 추론 + 도구 실행 포함) · 턴 안의 권한 승인·질문 응답 대기도 섞여 있을 수 있음 · 사람 = 턴 종료 뒤 사람 프롬프트까지 · 백그라운드 = 턴 종료 뒤 알림(서브에이전트 등)이 재개할 때까지\n"
    printf "      기타 = 나머지(미분류 포함) · 게이트(질문) 구분 없음 · 동시 세션 이중 계상 가능(같은 세션 누적 turn_duration 은 직전 턴 끝·직전 트리거로 잘라냄) · transcript 본문은 읽지 않음(구조 필드만) · 구간 경계 ±1분 · 행 끝 [겹침 N] = 겹친 구간이 있어 열 합이 합계와 다를 수 있음\n"
    if (ENVIRON["STAGE_TIMING_TDIRNOTE"] != "") printf "      %s\n", ENVIRON["STAGE_TIMING_TDIRNOTE"]
  }
  printf "원장: %s · FID %d개 · 구간 %d건(통계 %d · 방치 제외 %d) · 방치 상한 %s분 · since %s\n\n", ENVIRON["STAGE_TIMING_LEDGER"], fidn + 0, cnt + gapn, cnt + 0, gapn + 0, ENVIRON["STAGE_TIMING_CAP"], (since + 0 > 0 ? since : "없음")
  if (cnt == 0) {
    printf "집계할 구간 없음 — 통계에 들어갈 인접 행 쌍이 한 건도 없습니다(원장 부재가 아니라 구간 부재).\n"
  } else {
    nk = 0; for (k in n) keys[++nk] = k
    for (i = 1; i < nk; i++) {   # 합계 내림차순, 같으면 단계 이름 오름차순
      b = i
      for (j = i + 1; j <= nk; j++)
        if (sum[keys[j]] > sum[keys[b]] || (sum[keys[j]] == sum[keys[b]] && keys[j] < keys[b])) b = j
      t = keys[i]; keys[i] = keys[b]; keys[b] = t
    }
    # 머리행은 한글 표시 폭(글자당 2칸)을 손으로 맞춘 고정 문자열이다 — printf 폭은 바이트 기준이라 한글 열이 어긋난다.
    if (seg_ok == 1) printf "   합계    비중     n  중앙값    p90    max   작업   사람 백그라운드   기타  단계\n"
    else printf "   합계    비중     n  중앙값    p90    max  단계\n"
    for (r = 1; r <= nk; r++) {
      k = keys[r]; m = n[k]
      if (seg_ok == 1) gNa += tN[k]   # --by-agent 비교용 백그라운드 열 합은 --min-n 으로 가려진 단계도 포함한다
      if (m < minn) { hidden++; continue }
      for (i = 1; i <= m; i++) tmp[i] = v[k, i]
      isort(tmp, m)
      if (seg_ok == 1) {
        if (ovl[k] + 0 == 0) lr4(tM[k] / 60, tH[k] / 60, tN[k] / 60, tR[k] / 60, sum[k])
        else { o1 = int(tM[k] / 60 + 0.5); o2 = int(tH[k] / 60 + 0.5); o3 = int(tN[k] / 60 + 0.5); o4 = int(tR[k] / 60 + 0.5) }
        printf "%7d %6.1f%% %5d %7d %6d %6d %6d %6d %10d %6d  %s%s\n", sum[k], (total > 0 ? sum[k] * 100 / total : 0), m, qn(tmp, m, 50), qn(tmp, m, 90), tmp[m], o1, o2, o3, o4, k, (ovl[k] + 0 > 0 ? sprintf(" [겹침 %d]", ovl[k]) : "")
        gM += tM[k]; gH += tH[k]; gN += tN[k]; gR += tR[k]
      } else {
        printf "%7d %6.1f%% %5d %7d %6d %6d  %s\n", sum[k], (total > 0 ? sum[k] * 100 / total : 0), m, qn(tmp, m, 50), qn(tmp, m, 90), tmp[m], k
      }
    }
  }
  printf "\n방치 구간 제외 %d건 (합 %d분) — 위 통계에 불포함\n", gapn + 0, gaps + 0
  if (minn > 1) printf "표 가림(--min-n %d) %d단계\n", minn, hidden + 0
  printf "FID 첫 행 %d개는 기준 행이 없어 집계에 없음 (행 1개뿐인 FID %d개)%s\n", fidn + 0, single + 0, (since + 0 > 0 ? sprintf(" · since 이전에 끝난 FID %d개 제외", oldf + 0) : "")
  printf "형식 불일치·범위 밖 행 %d건은 무시됨 (집계 제외)\n", badn + 0
  if (seg_ok == 1) {
    printf "배분 합(분): 작업 %d · 사람 %d · 백그라운드 %d · 기타 %d (기타 중 미분류 %d분 · 미분류 트리거 %d건)\n", int(gM / 60 + 0.5), int(gH / 60 + 0.5), int(gN / 60 + 0.5), int(gR / 60 + 0.5), int(aUall / 60 + 0.5), unn + 0
    printf "transcript 조각 합(분): 작업 %d · 사람 %d · 백그라운드 %d · 미분류 %d — 배분 합과의 차이는 원장 구간 밖·방치/since 제외·겹침 때문\n", int(tot["M"] / 60 + 0.5), int(tot["H"] / 60 + 0.5), int(tot["N"] / 60 + 0.5), int(tot["U"] / 60 + 0.5)
    if (ns > 0) printf "transcript 시간 범위(로컬): %s ~ %s · 범위 밖 구간 %d건(합 %d분)은 전부 기타에 포함\n", fmt(cmin), fmt(cmax), outn + 0, outsum + 0
    else printf "transcript 조각 없음 — 모든 구간이 기타입니다\n"
    printf "방치 상한 초과 유휴(transcript, 통계 제외): 사람 %d건 %d분 · 백그라운드 %d건 %d분 · 미분류 %d건 %d분\n", xn["H"] + 0, int(xs["H"] / 60 + 0.5), xn["N"] + 0, int(xs["N"] / 60 + 0.5), xn["U"] + 0, int(xs["U"] / 60 + 0.5)
    printf "겹침 %d구간 (작업+사람+백그라운드가 구간 wall 을 넘음 — 같은 세션 누적 turn_duration 은 직전 턴 끝·직전 트리거로 잘라냄 · 남는 겹침 = 동시 세션 가능성, 해당 구간의 기타는 0)\n", ovn + 0
    printf "직전 turn_duration 없이 시작한 트리거 %d건 (세션 시작·턴 중 대기열·기록 누락 포함)\n", nod + 0
    if (ENVIRON["STAGE_TIMING_BGFILE"] != "") { bgf = ENVIRON["STAGE_TIMING_BGFILE"]; printf "%d\n", int(gNa / 60 + 0.5) > bgf; close(bgf) }   # --by-agent 푸터가 비교할 백그라운드 열 합
  }
}'
if [ "$BYAGENT" = 1 ] && [ "$AG_OK" = 1 ]; then
  BG_MIN=$(cat "$BGTMP" 2>/dev/null); BG_MIN=${BG_MIN:-0}
  # 역할별 표는 서브에이전트가 살아 있던 시간(첫~끝 timestamp − 방치 상한 초과 간격)을 초 단위로 모아 표시 시점에만 분으로 반올림한다.
  #   중앙값·p90 은 단계 표와 같은 nearest-rank. 합계 동률은 역할 이름 오름차순. --min-n 은 이 표에 적용하지 않는다(숨김 없음 원칙).
  awk -F '\t' -v cut="$AG_CUT" -v bg="$BG_MIN" '
  function dn(y, m, d,   yy, mm) {
    yy = y - (m <= 2); mm = m + (m <= 2 ? 12 : 0)
    return 365 * yy + int(yy / 4) - int(yy / 100) + int(yy / 400) + int((153 * (mm - 3) + 2) / 5) + d
  }
  function isort(a, n,   gi, g, i, j, t) {
    for (gi = 1; gi <= ngap; gi++) {
      g = GAP[gi]; if (g > n) continue
      for (i = g + 1; i <= n; i++) { t = a[i]; for (j = i - g; j >= 1 && a[j] > t; j -= g) a[j + g] = a[j]; a[j + g] = t }
    }
  }
  function qn(a, n, p,   i) { i = int((p * n + 99) / 100); if (i < 1) i = 1; if (i > n) i = n; return a[i] }
  function mn(x) { return int(x / 60 + 0.5) }
  BEGIN {
    ngap = split("701 301 132 57 23 10 4 1", GAP, " ")
    cs = sprintf("%s", cut); y = substr(cs, 1, 4) + 0; m = substr(cs, 5, 2) + 0; d = substr(cs, 7, 2) + 0
    cutsec = (dn(y, m, d) - dn(1970, 1, 1)) * 86400
  }
  {
    all++
    if ($1 + 0 < cutsec) { old++; next }
    w = $3 + 0; bn += $4; bs += $5; xn += $6; xs += $7
    if ($8 == "-") { un++; us += w; next }
    n[$8]++; v[$8, n[$8]] = w; sum[$8] += w; tot += w; cls++
  }
  END {
    printf "\n서브에이전트 역할별 소요(분) — 서브에이전트가 살아 있던 시간(부모가 기다린 시간이 아님) · %s 이후 시작\n", substr(cs, 1, 4) "-" substr(cs, 5, 2) "-" substr(cs, 7, 2)
    printf "서브에이전트 %d개 중 기준일 이전 시작 %d개 제외 (집계 %d개: 역할 판정 %d · 미분류 %d)\n", all + 0, old + 0, cls + un, cls + 0, un + 0
    if (cls == 0) {
      printf "역할을 판정할 수 있는 서브에이전트가 없음\n"
    } else {
      nk = 0; for (k in n) keys[++nk] = k
      for (i = 1; i < nk; i++) {
        b = i
        for (j = i + 1; j <= nk; j++)
          if (sum[keys[j]] > sum[keys[b]] || (sum[keys[j]] == sum[keys[b]] && keys[j] < keys[b])) b = j
        t = keys[i]; keys[i] = keys[b]; keys[b] = t
      }
      printf "   합계    비중     n  중앙값    p90    max  역할\n"
      for (r = 1; r <= nk; r++) {
        k = keys[r]; m = n[k]
        for (i = 1; i <= m; i++) tmp[i] = v[k, i]
        isort(tmp, m)
        printf "%7d %6.1f%% %5d %7d %6d %6d  %s\n", mn(sum[k]), (tot > 0 ? sum[k] * 100 / tot : 0), m, mn(qn(tmp, m, 50)), mn(qn(tmp, m, 90)), mn(tmp[m]), k
      }
    }
    printf "미분류(이름 지정) %d건 합계 %d분 — 역할 표에서 제외\n", un + 0, mn(us + 0)
    printf "역할 wall 합 %d분 · 같은 기간 백그라운드 열 합 %d분 — 병렬·작업 중 실행으로 같지 않음\n", mn(tot + 0), bg + 0
    printf "서브에이전트 내부 간격 10분 초과 %d건(합 %d분) — 권한 대기·유휴 포함, 제외하지 않음\n", bn + 0, mn(bs + 0)
    printf "방치 상한 초과 내부 간격 %d건(합 %d분) 제외\n", xn + 0, mn(xs + 0)
  }' "$AGTMP"
fi
if [ "$SPLIT" = 1 ] && [ -n "$SPLIT_NA" ]; then
  printf '측정 불가(--split): %s\n' "$SPLIT_NA"
fi
if [ "$BYAGENT" = 1 ] && [ -n "$AGENT_NA" ]; then
  printf '측정 불가(--by-agent): %s\n' "$AGENT_NA"
fi
