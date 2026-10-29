#!/usr/bin/env bash
# show-fid-status.sh — FID Lifecycle 진행 단계 + 아티팩트 현황 표시
# Usage: bash scripts/show-fid-status.sh <FID>
# devfsd: FR-1~FR-5 (spec.md §4)
set -u

FID="${1:-}"

# 테스트 환경 오버라이드 (SPECOPS_ROOT 미설정 시 기본 .specops)
SPECOPS="${SPECOPS_ROOT:-.specops}"
PROGRESS="$SPECOPS/session-progress.md"

# 인자 없는 조회 — FID 를 스크립트가 정한다 (active-fid 표지 → 진행 기록의 헤더 순, **디렉토리가 있는 첫 FID**).
#   왜: 부트스트랩 직후 진행 기록의 최상단은 `<날짜>-init-project` 인데 그 디렉토리는 없다(init 은 FID 가 아니다).
#   종전에는 호출자가 "최상단 헤더" 를 뽑아 넘겼고, 처음 쓰는 사람이 /status 를 치면 Error·rc=1 부터 봤다.
#   인자를 준 경우의 계약(형식 오류·디렉토리 부재 → rc 1)은 그대로다.
if [ "$#" -eq 0 ]; then
  if [ ! -d "$SPECOPS" ]; then
    printf 'specops 미사용 프로젝트입니다 (%s 부재) — 조회할 FID 가 없습니다. 도입은 `/init-project`, 바로 시작은 `/start <기능 설명>`.\n' "$SPECOPS"
    exit 0
  fi
  _cands=""
  if [ -f "$PROGRESS" ]; then
    _cands=$( { grep -m1 -oE '<!--[[:space:]]*active-fid:[[:space:]]*[0-9]{8}-[a-z0-9-]+' "$PROGRESS" | grep -oE '[0-9]{8}-[a-z0-9-]+$'
                grep -oE '^## [0-9]{8}-[a-z0-9-]+' "$PROGRESS" | sed 's/^## //'; } 2>/dev/null )
  fi
  for _c in $_cands; do
    [ -d "$SPECOPS/$_c" ] && { FID="$_c"; break; }
  done
  # 진행 기록에 없지만 디렉토리는 있는 FID — 이름(날짜 접두)이 가장 늦은 것. 기록이 유실됐거나 아직 한 줄도 안 쓴 FID 다.
  if [ -z "$FID" ]; then
    FID=$(ls -d "$SPECOPS"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-* 2>/dev/null | LC_ALL=C sort | tail -1)
    FID=${FID##*/}
    printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || FID=""
  fi
  if [ -z "$FID" ]; then
    printf '진행 중인 FID 가 없습니다 — `/start <기능 설명>` 으로 시작하세요. (기존 코드 수정은 `/maintain <대상>`)\n'
    exit 0
  fi
fi

# FR-1: FID 형식 검증 (^\d{8}-[a-z0-9-]+$)
if ! printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$'; then
  printf 'Error: FID 형식 오류 — 올바른 형식: YYYYMMDD-kebab-slug (got: %s)\n' "${FID:-<비어있음>}" >&2
  exit 1
fi

# FR-3: FID 디렉토리 확인
FID_DIR="$SPECOPS/$FID"
if [ ! -d "$FID_DIR" ]; then
  printf 'Error: FID 디렉토리 없음 — %s\n' "$FID_DIR" >&2
  exit 1
fi

# 헤더 출력
printf '=== FID: %s ===\n\n' "$FID"

# FR-2 / FR-5: session-progress.md에서 FID 섹션 추출
# FID는 위에서 [0-9a-z-] 로 검증됨 — grep/awk regex 메타문자 없음
printf '## Lifecycle 진행 이력\n\n'
if [ ! -f "$PROGRESS" ]; then
  printf '(진행 이력 없음)\n'
elif grep -qE "^## $FID([[:space:]]|$)" "$PROGRESS"; then
  awk "/^## $FID([[:space:]]|\$)/{found=1; next} found && /^## /{exit} found && NF{print}" "$PROGRESS"
else
  printf '(진행 이력 없음)\n'
fi

printf '\n'

# 단계 소요 (20260911-stage-timing-derive) — 원장에서 **도출**한다(새 계측 없음).
#   원장은 prepend(최신 우선)라 정렬이 필수다 — 안 하면 인접 차이가 음수가 된다.
#   날짜→epoch 는 scripts/epoch.sh 재사용(macOS/GNU 분기 소유자). main guard 가 없어
#   source 불가라 인자 호출만 쓰고, **distinct 날짜당 1회**만 부른다(15회 162ms → 2회 ≈22ms 실측).
printf '## 단계 소요\n\n'
_ts_rows=""
if [ -f "$PROGRESS" ] && grep -qE "^## $FID([[:space:]]|$)" "$PROGRESS"; then
  _ts_rows=$(awk "/^## $FID([[:space:]]|\$)/{found=1; next} found && /^## /{exit} found" "$PROGRESS" \
    | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} /[a-z-]+' \
    | sed 's/^- //' | sort)
fi
_ts_n=$(printf '%s' "$_ts_rows" | grep -c . )
# fid-start 조회를 게이트 **위로** 올린다 — 아래 게이트가 이 값을 봐야 한다.
_ts_start=""
if [ -f "$FID_DIR/metrics.jsonl" ]; then
  _ts_start=$(grep '"phase":"fid-start"' "$FID_DIR/metrics.jsonl" 2>/dev/null \
    | head -1 | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p')
fi
# 구간 수 = 인접 쌍(n-1) + fid-start 구간(행이 1개 이상 **이면서** fid-start 기록이 있을 때 1).
#   종전 `-lt 2` 게이트는 fid-start 행을 통째로 삼켰다 — 원장 1행 + fid-start 인 FID 는
#   `fid-start → 행1` 이라는 **측정 가능한 구간**이 있는데도 '구간 없음' 이 나왔다(실측).
#   T3 이 진입 시점에 fid-start 를 기록하기 시작하면 신규 FID 의 첫 `/status` 마다 나온다.
#   계기판이 "없다"고 거짓말하는 것은 이 FID 가 없애려는 병 그 자체다.
#   n=0 + fid-start 는 **표를 열지 않는다** — 잴 대상(첫 행)이 없어서 빈 대상 행이 찍힌다.
_ts_seg=0
[ "${_ts_n:-0}" -gt 0 ] && _ts_seg=$(( _ts_n - 1 ))
if [ "${_ts_n:-0}" -ge 1 ] && [ -n "$_ts_start" ]; then _ts_seg=$(( _ts_seg + 1 )); fi
if [ "$_ts_seg" -lt 1 ]; then
  if [ "${_ts_n:-0}" -eq 1 ]; then
    printf '  (구간 없음 — 진행 기록 1행, fid-start 기록도 없음. 인접 2행 또는 fid-start 가 있어야 계산됩니다)\n\n'
  else
    printf '  (구간 없음 — 진행 기록 %s행. 소요는 인접 2행부터 계산됩니다)\n\n' "${_ts_n:-0}"
  fi
else
  printf '  측정: 완료시각 기준 **인접 행 차이** · **분 해상도** · **경과 시간**이지 작업량이 아닙니다\n'
  printf '        (대기·중단 시간이 포함됩니다 — 사람 응답 대기가 최대 구간인 경우가 실제로 있습니다)\n\n'
  # fid-start(metrics.jsonl)가 있으면 첫 구간을 계산하고, 없으면 **명시**한다.
  #   과거 FID 는 이 기록이 영구 부재다(소급 변환 금지 — 원장은 append-only 사실 기록).
  #
  # ★ TZ 불일치를 보정한다 — 이 FID 가 없애려는 '틀린 계기판' 그 자체다.
  #   record-metric.sh:58 은 `date -u`(UTC), session-progress-append.sh:120 은 **로컬**이다.
  #   행 간 인접 차이는 오프셋이 상쇄돼 무해하지만, UTC fid-start 와 로컬 첫 행을 그냥 빼면
  #   오프셋만큼 틀린다. 실측(plan-reviewer, +0900): 정답 5m 이 **9h5m** 으로 나왔다.
  #   `date +%z` 로 오프셋을 1회 읽어 UTC 기준값에 더해 로컬로 맞춘다.
  # 분 → 표기 1곳. 첫 구간(_ts_d0)과 본구간(_ts_dm)이 같은 규칙을 **한 정의**로 쓴다.
  #   결과를 `$( )` 로 받지 않고 **전역 `_ts_fmt_out` 에 쓴다** — 명령치환은 행마다
  #   서브셸을 fork 해서 15행 FID 에 +63ms 였다(실측: I-1 도입 전 396ms → 후 459ms).
  #   변수 대입 방식은 fork 0회다.
  _ts_fmt_min() { # <minutes> → _ts_fmt_out = "Nm" | "XhYm" | "(역순)"
    if [ "$1" -lt 0 ]; then _ts_fmt_out='(역순)'
    elif [ "$1" -ge 60 ]; then _ts_fmt_out="$(( $1 / 60 ))h$(( $1 % 60 ))m"
    else _ts_fmt_out="${1}m"; fi
  }
  _ts_z=$(date +%z)                                  # 예: +0900 / -0500
  _ts_zs=${_ts_z%"${_ts_z#?}"}                       # 부호 1글자
  _ts_zm=$(( 10#${_ts_z:1:2} * 60 + 10#${_ts_z:3:2} ))
  [ "$_ts_zs" = "-" ] && _ts_zm=$(( -_ts_zm ))
  # `_ts_start` 는 게이트 위에서 이미 조회했다(중복 호출 제거).
  if [ -n "$_ts_start" ]; then
    _ts_se=$(bash "$(dirname "${BASH_SOURCE[0]}")/epoch.sh" "$_ts_start" 2>/dev/null)
    _ts_first=$(printf '%s\n' "$_ts_rows" | head -1)
    _ts_fd=${_ts_first%% *}; _ts_frest=${_ts_first#* }
    _ts_fhm=${_ts_frest%% *}; _ts_fcmd=${_ts_frest#* }
    _ts_fb=$(bash "$(dirname "${BASH_SOURCE[0]}")/epoch.sh" "${_ts_fd}T00:00:00Z" 2>/dev/null)
    if [ -n "$_ts_se" ] && [ -n "$_ts_fb" ]; then
      # 첫 행은 로컬, fid-start 는 UTC → UTC 쪽에 오프셋을 더해 같은 기준으로 만든다.
      _ts_d0=$(( _ts_fb / 60 + 10#${_ts_fhm%%:*} * 60 + 10#${_ts_fhm##*:} - (_ts_se / 60 + _ts_zm) ))
      if [ "$_ts_d0" -lt 0 ]; then
        # fid-start 가 첫 행보다 **뒤**다(시계 오차·재실행·수동 편집). 음수 분을 그대로
        #   내면 `-3m` 같은 값이 표에 박혀 계기판이 또 거짓말한다 — 사유를 밝힌다.
        printf '  %-20s → %-20s %8s   (fid-start 가 첫 행보다 나중 — 시각 불일치)\n' \
          "fid-start" "$_ts_fcmd" "측정 불가"
      else
        _ts_fmt_min "$_ts_d0"
        printf '  %-20s → %-20s %8s\n' "fid-start" "$_ts_fcmd" "$_ts_fmt_out"
      fi
    else
      # 변환 실패를 조용히 삼키면 **행이 아예 사라져** "fid-start 기록이 없다"와
      #   구별되지 않는다. 기록은 있고 변환만 실패했음을 밝힌다(한계 고백).
      printf '  %-20s → %-20s %8s   (fid-start ts 파싱 실패: %s)\n' \
        "fid-start" "$_ts_fcmd" "측정 불가" "$_ts_start"
    fi
  else
    printf '  %-20s → %-20s %8s   (fid-start 미기록 FID)\n' "(FID 시작)" "$(printf '%s\n' "$_ts_rows" | head -1 | sed 's/.* //')" "측정 불가"
  fi
  _ts_prev_cmd=""; _ts_prev_min=""
  _ts_cache_date=""; _ts_cache_base=""
  printf '%s\n' "$_ts_rows" | while IFS= read -r _ts_line; do
    [ -n "$_ts_line" ] || continue
    _ts_d=${_ts_line%% *}                      # YYYY-MM-DD
    _ts_rest=${_ts_line#* }                    # HH:MM /command
    _ts_hm=${_ts_rest%% *}                     # HH:MM
    _ts_cmd=${_ts_rest#* }                     # /command
    if [ "$_ts_d" != "$_ts_cache_date" ]; then
      _ts_cache_base=$(bash "$(dirname "${BASH_SOURCE[0]}")/epoch.sh" "${_ts_d}T00:00:00Z" 2>/dev/null)
      _ts_cache_date="$_ts_d"
    fi
    if [ -z "$_ts_cache_base" ]; then
      # 변환 실패를 조용히 건너뛰면 다음 행이 **두 칸 건너뛴 구간**을 인접인 양 출력한다.
      printf '  %-20s → %-20s %8s\n' "$_ts_prev_cmd" "$_ts_cmd" "(변환 실패)"
      _ts_prev_cmd=""; _ts_prev_min=""; continue
    fi
    # 10# 강제 필수 — bash 는 `08`·`09` 를 8진수로 읽어 `value too great for base` 에러를 낸다.
    #   실측(plan-reviewer): 없이 돌리면 `21:09` 에서 죽고 4행 중 1행만 나온다.
    _ts_min=$(( _ts_cache_base / 60 + 10#${_ts_hm%%:*} * 60 + 10#${_ts_hm##*:} ))
    if [ -n "$_ts_prev_cmd" ]; then
      _ts_dm=$(( _ts_min - _ts_prev_min ))
      # `sort` 는 문자열 사전순이고 형식이 고정폭(YYYY-MM-DD HH:MM)이라 정상 데이터에서는
      #   시간순과 일치한다. 그래도 음수를 표에 내지는 않는다 — 손상된 원장 행이 섞이면
      #   `-13m` 이 출력돼 계기판이 거짓말한다(관측 아님, 방어).
      _ts_fmt_min "$_ts_dm"
      printf '  %-20s → %-20s %8s\n' "$_ts_prev_cmd" "$_ts_cmd" "$_ts_fmt_out"
    fi
    _ts_prev_cmd="$_ts_cmd"; _ts_prev_min="$_ts_min"
  done
  printf '\n'
fi

# FR-4: 아티팩트 현황
printf '## 아티팩트 현황\n\n'
for artifact in intent.md spec.md acceptance-criteria.md plan.md tasks.md evidence.md; do
  if [ -f "$FID_DIR/$artifact" ]; then
    printf '  \xe2\x9c\x85 %s\n' "$artifact"
  else
    printf '  \xe2\x9d\x8c %s\n' "$artifact"
  fi
done

# FR-6 (20260718-status-reconcile): 기록 frontier ↔ 실제 증거(산출물·dispatch·git) 대조.
#   정체 후 재개 시 session-progress 단독은 현실을 과소보고한다 — dogfood test1 FR-3: /tasks 기록
#   상태에서 12커밋+dispatch T7까지 존재했으나, 주 breadcrumb 만 읽으면 "구현 안 됨"으로 오판돼
#   24h+ 방치됐다(실제 잔여 작업은 5분). 진짜 frontier 를 계산해 desync 를 경고하고 재개점을 준다.
# 20260719: frontier 사다리·reconcile 로직은 scripts/_internal/reconcile-check.sh 로 추출(단일 SoT).
#   SessionStart 훅도 동일 스크립트(--hook 모드)로 재개 desync 를 자동표면화 — 사다리 변경 시 drift 방지.
_RC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_internal/reconcile-check.sh"
SPECOPS_ROOT="$SPECOPS" bash "$_RC" "$FID"
