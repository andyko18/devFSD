#!/usr/bin/env bash
# doctor.sh — specops 설치·환경 건강 진단 (20260807, FID 20260807-specops-doctor)
# Usage: bash scripts/doctor.sh [--json]
# Exit: 0 항상 (조회 도구 — 어떤 흐름도 막지 않는다)
# 환경: SPECOPS_ROOT(기본 .specops)
#
# 왜 필요한가: validate-structure.sh 는 **플러그인 개발자용**이라 사용자 프로젝트의
#   .specops/ 상태를 보는 층이 0곳이었다. 가장 위험한 공백은 git hook 미설치 —
#   install-git-hooks.sh 는 clone 마다 수동 1회이고, 미실행 시 2단 게이트가
#   **조용히 없다**(Claude Code PreToolUse 훅은 Cursor 등 타 도구 커밋에 발화하지 않음).
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
PLUGIN=$(cd "$(dirname "$0")/.." && pwd)
ROWS=""   # 누적 형식: id|status|detail|fix (bash 3.2 — 연상배열 미사용)

# 구분자 인젝션 차단 — 필드값(FID 디렉토리명 등)에 `|` 나 개행이 있으면 표 셀이 밀리고
#   `--json`(schema_version 있는 기계 계약) 의 fix 필드가 오염돼 **조치 문구가 유실**된다.
#   개행이면 행 자체가 위조된다. 근원이 한 곳이므로 여기서만 봉합한다.
#   순수 bash 치환만 사용 — bash 3.2 호환, 프로세스 스폰 0.
_add() {
  local a out=""
  for a in "$1" "$2" "$3" "$4"; do
    a="${a//|//}"                     # 구분자 → 슬래시 (삭제하면 이름이 조용히 합쳐진다). 치환부는 `/` 그대로 — `\/` 로 쓰면 bash 3.2 가 백슬래시를 남긴다
    a="${a//$'\n'/ }"; a="${a//$'\r'/ }"
    out="${out}${out:+|}${a}"
  done
  ROWS="${ROWS}${out}"$'\n'
}

_chk_hooks() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    _add git_hooks unknown "git repo 아님 — 판정 불가" ""; return
  fi
  # 관할 판정 — 처방(install-git-hooks.sh)이 **이 repo 에서 실행 가능한가**.
  #   installer 는 `.githooks/` 없는 repo 를 거부한다(2df6de6). 둘 중 하나라도 없으면
  #   플러그인 2단 게이트는 이 repo 의 것이 아니고, 처방해도 죽는다(실측: 하류에서
  #   `No such file or directory`). 게다가 절대경로로 설치에 성공하더라도 두 훅 본문이
  #   하류에서 자기면제(`pre-commit` 의 `[ -f "$VS" ] && [ -f "$CP" ] || exit 0` · `pre-push` 의
  #   `[ -f "$RUN_ALL" ] || exit 0` — 라인번호 대신 문구로 적는다, 훅 편집 시 드리프트하므로)라
  #   **no-op 훅**이 걸리고, 종전 판정은
  #   그것을 `✅` 로 보고했다 — 처방이 거짓 ✅ 를 직접 만드는 경로였다.
  #   조치는 **비운다**: 하류용 도구 무관 게이트 본문은 아직 제공하지 않는다(별건).
  if [ ! -f "scripts/_internal/install-git-hooks.sh" ] || [ ! -d ".githooks" ]; then
    _add git_hooks warn "specops 2단 게이트 미설치 — 이 repo 는 플러그인 관할 밖 (Claude Code 밖의 도구로 한 커밋은 검증 게이트를 거치지 않는다 — 알려진 한계, 조치 없음)" ""
    return
  fi
  local hp missing=""
  hp=$(git config core.hooksPath 2>/dev/null || true)
  [ "$hp" = ".githooks" ] || missing="core.hooksPath"
  for h in pre-commit pre-push; do
    [ -x ".githooks/$h" ] || missing="${missing}${missing:+ · }$h"
  done
  if [ -z "$missing" ]; then
    _add git_hooks ok "2단 게이트 설치됨 (pre-commit · pre-push)" ""
  else
    _add git_hooks warn "누락: $missing" "bash scripts/_internal/install-git-hooks.sh"
  fi
}

_chk_memory() {
  local dir="$SPECOPS/memory" scan="$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh"
  if [ ! -d "$dir" ]; then
    _add memory unknown "$dir 부재 — 부트스트랩 안 됨" "/init-project"; return
  fi
  local files
  files=$(ls "$dir"/*.md 2>/dev/null || true)
  if [ -z "$files" ]; then
    _add memory unknown "memory 문서 0건 — .specops 로컬전용 정책이면 정상 (무시 가능)" "/init-project"; return
  fi
  if [ ! -f "$scan" ]; then
    _add memory unknown "판정기 부재 — $scan" ""; return
  fi
  # 판정 SoT 재사용 — doctor.sh 안에 placeholder 규칙을 다시 구현하지 않는다(드리프트 방지)
  local bad=0 f
  while IFS= read -r f; do            # 공백 포함 파일명 대응 (word splitting 금지)
    [ -n "$f" ] || continue
    bash "$scan" "$f" >/dev/null 2>&1 || bad=$((bad + 1))
  done <<EOF_FILES
$files
EOF_FILES
  if [ "$bad" -eq 0 ]; then
    _add memory ok "placeholder 잔존 0건" ""
  else
    # 단위는 **문서 수**다 — init-finalize 가 말하는 "미채움 N건" 은 자리표시자 수라 숫자가 다르다.
    _add memory warn "미채움 문서 ${bad}개 (자리표시자가 남은 문서 수)" "해당 문서를 실제 값으로 채우세요 (보강: /init-project --enrich · 문서별 위치: bash '$PLUGIN/scripts/_internal/scan-enrich-placeholders.sh' <문서>)"
  fi
}

_chk_orphan() {
  local d fid names="" n=0
  for d in "$SPECOPS"/*/; do
    [ -d "$d" ] || continue
    fid=$(basename "$d")
    [ "$fid" = "memory" ] && continue
    [ -f "$d/spec.md" ] || continue
    # 경과일은 보지 않는다 — clarifications.md §Q1 확정(임계 없음, 경고만)
    if [ ! -f "$d/tasks.md" ] && [ ! -f "$d/evidence.md" ]; then
      n=$((n + 1)); names="${names}${names:+ }$fid"
    fi
  done
  if [ "$n" -eq 0 ]; then
    _add orphan_fid ok "고아 FID 없음" ""
  else
    _add orphan_fid warn "${n}건: $names" "진행하거나 정리하세요"
  fi
}

_chk_progress() {
  local sp="$SPECOPS/session-progress.md"
  if [ ! -f "$sp" ]; then
    _add progress unknown "session-progress.md 부재" ""; return
  fi
  # `/verify PASS` 를 기록한 FID 인데 evidence.md 가 없는 경우.
  #   포맷 정규식은 느슨하게 — gbrain 20260615-append-idempotency-fix:
  #   "session-progress 텍스트 소비는 출력 포맷 불변이 회귀 가드"
  # ⚠️ 줄당 프로세스 스폰 금지 — session-progress.md 는 append-only 라 선형 성장한다
  #   (실측 1,791줄). 리뷰 A/B 실측: 줄당 `printf | grep` 이 ~1.1s 를 차지해
  #   NFR-2(2초) 를 넘겼다. 순수 bash 문자열 연산만 쓴다.
  # 3분류: 아카이브(디렉터리째 정리됨) / 불일치(디렉터리 있는데 evidence 없음) / 정상.
  #   arch 는 bad 와 **대칭으로 dedup** 한다 — 같은 FID 헤더가 두 번 나오면 건수가 부푼다.
  #   (이 repo 실측: FID 섹션 125건 vs 디렉터리 32개 — 중복은 개연이지 가설이 아니다)
  local bad="" arch="" n=0 an=0 cur=""
  # an(아카이브 고유 건수)은 루프 종료 후 sort -u 로 1회 산출한다 — 아래 판정부 주석 참조.
  while IFS= read -r line; do
    case "$line" in
      "## "*) cur="${line#\#\# }"; cur="${cur%% *}"; cur="${cur%$'\r'}"
              # CRLF 방어 — `\r` 가 남으면 디렉터리명이 어긋나 `[ -d ]` 가 실패하고,
              #   그 결과 **존재하는 dir 이 아카이브로 오분류**된다. main 에서 ⚠️ 로 시끄럽던
              #   진짜 결함이 branch 에서 ✅ 로 조용해지는 **실패 방향 반전**이라 위험하다
              #   (Phase C 실측: main `⚠️ 1건 불일치` vs branch `✅ (아카이브 1건 제외)`).
              # 헤더는 신뢰 입력이 아니다 — 경로 구분자·상위 참조가 섞이면 .specops 밖을
              #   프로브하게 된다(read-only 라 무해하나 무검증). 실측: 실 repo 헤더 126건 중
              #   `/`·`..` 포함 0건 — 정상 FID 를 떨어뜨리지 않는다.
              case "$cur" in */*|*..*) cur="" ;; esac ;;
      # `*"/verify"*PASS*` 는 `- ... /verify FAIL — PASSWORD 마스킹 회귀` 를 오탐한다
      #   (PASSWORD 의 PASS). 실측: 실 repo 에서 loose 113줄 = `/verify PASS` 113줄 —
      #   loose-only 0줄이라 조여도 검출력 손실이 없다.
      *) if [ -n "$cur" ] && case "$line" in *"/verify PASS"*) true ;; *) false ;; esac; then
           if [ ! -d "$SPECOPS/$cur" ]; then
             # 디렉터리째 없음 = 아카이브. `.specops/*` 는 gitignore 라 로컬 전용이고
             #   session-progress.md 는 append-only 다 — 과거 FID 정리는 의도된 동작이지
             #   결함이 아니다. 조치 문구("evidence.md 확인")도 여기엔 수행 불가능하다.
             # dedup 은 **루프 밖에서 1회** 한다 — `case " $arch " in *" $cur "*` 인라인 dedup 은
             #   O(n²) 이고, arch 는 아카이브할수록 **단조 증가하는 축**이라 시간이 갈수록 나빠진다
             #   (Phase C 실측: 500건 0.17s / 2,000건 1.74s — NFR-2 예산 2s 근접 / 10,000건 40s).
             #   bad 는 인라인 dedup 을 유지한다 — 그쪽은 **순서 있는 표시 목록**이 필요하고
             #   실측 0건이라 성장 축이 아니다. 비대칭이지만 요구가 다르다(count vs ordered list).
             arch="${arch}${arch:+ }$cur"
           elif [ ! -f "$SPECOPS/$cur/evidence.md" ]; then
             # 디렉터리는 있는데 증거만 없다 = 진짜 결함(검증 주장 후 증거 유실).
             case " $bad " in *" $cur "*) ;; *) bad="${bad}${bad:+ }$cur"; n=$((n + 1)) ;; esac
           fi
           cur=""
         fi ;;
    esac
  done < "$sp"
  # 아카이브 고유 건수 — 스폰은 여기 4회로 **상수**다(줄당 0). `tr ' ' '\n'` 은 아래 head5 와
  #   같은 관용구로, 비인용 확장의 glob 전개(`## *` 류 헤더)를 피한다.
  [ -n "$arch" ] && an=$(printf '%s' "$arch" | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')
  if [ "$n" -eq 0 ]; then
    # 아카이브가 있으면 건수를 밝힌다 — 조용히 버리지 않는 것이 이 변경의 절반이다.
    #   0건이면 붙이지 않는다: 없는 정보로 잡음을 만들면 고치려던 문제를 재생산한다.
    local suffix=""
    [ "$an" -gt 0 ] && suffix=" (아카이브 ${an}건 제외)"
    _add progress ok "verify PASS 기록 ↔ evidence.md 정합${suffix}" ""
  else
    # 실 repo 실측(리뷰 3회차): 불일치가 많으면 표 한 셀이 수천 자가 된다.
    #   AC 는 "지목"만 요구하므로 앞 5건 + "외 N건" 으로 절단한다.
    local head5 rest suffix=""
    head5=$(printf '%s' "$bad" | tr ' ' '\n' | head -5 | tr '\n' ' ')
    rest=$((n - 5)); [ "$rest" -gt 0 ] && head5="${head5}외 ${rest}건"
    [ "$an" -gt 0 ] && suffix=" · 아카이브 ${an}건 제외"
    _add progress warn "${n}건 불일치: ${head5}${suffix}" "evidence.md 확인 또는 /verify 재실행"
  fi
}

_chk_bootstrap() {
  # 부트스트랩이 **커밋으로 종결**됐는가. staged 잔존 기준은 사용자가 나중에 문서를
  #   편집해 staged 로 두면 오탐하고, "커밋 0건" 기준은 기존 repo 에 init 한 흔한 경우를
  #   미탐한다. 그래서 init 커밋(chore(init) 접두 — init-finalize.sh 자신이 쓰는 문구)의
  #   부재를 본다.
  if [ ! -d "$SPECOPS/memory" ]; then
    # memory 도 FID 도 없으면 플러그인을 쓴 적이 없는 저장소일 수 있다 — v2.17.0 이하의 Stop 훅은 `.specops/` 가
    #   없는 저장소에도 session-progress.md 를 만들어 그 저장소를 관할로 편입시켰다. 빠져나가는 길을 같이 말한다.
    if ! ls -d "$SPECOPS"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-* >/dev/null 2>&1; then
      _add bootstrap unknown "$SPECOPS/memory 부재 — 부트스트랩 안 됨 · FID 도 없음(플러그인을 쓰지 않는 저장소라면 이전 버전 훅이 남긴 흔적일 수 있다 — $SPECOPS 를 지우면 관할에서 빠진다)" "/init-project"; return
    fi
    _add bootstrap unknown "$SPECOPS/memory 부재 — 부트스트랩 안 됨" "/init-project"; return
  fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    _add bootstrap unknown "git repo 아님 — 판정 불가" ""; return
  fi
  local n_init n_staged
  # subject(%s) 만 본다 — `--grep` 은 커밋 메시지를 **행 단위**로 매칭하므로 본문의 언급도
  #   잡는다. 무앵커(`chore(init)`)는 실 repo 에서 3건 전부 오탐이었고(190544d·a375648·23a4943),
  #   앵커(`^chore(init): `)조차 **본문 줄머리**를 매치한다(픽스처 실측 — test-doctor.sh T28).
  #   미종결이 조용히 ✅ 되는 실패 방향 반전이라, 판정 근거를 첫 줄로 한정한다.
  #   --grep 은 순수 prefilter 로 남긴다(대형 repo 스캔 절감) — 정확도는 뒤 grep 이 책임진다.
  n_init=$(git log --grep='chore(init)' --format=%s 2>/dev/null | grep -c '^chore(init): ' || true)
  [ -n "$n_init" ] || n_init=0
  if [ "$n_init" -gt 0 ]; then
    _add bootstrap ok "부트스트랩 커밋 확인 (${n_init}건)" ""; return
  fi
  n_staged=$(git diff --cached --name-only 2>/dev/null | grep -c . || true)
  [ -n "$n_staged" ] || n_staged=0
  _add bootstrap warn "부트스트랩 미종결 (staged ${n_staged}파일 · init 커밋 0 — 플러그인 저장소 자체면 정상, 무시 가능)" \
    "bash '$PLUGIN'/scripts/_internal/init-finalize.sh"
}

# ISO8601 → 경과일(정수). GNU/BSD date 차이를 피해 jq fromdateiso8601 로 통일한다.
#   파싱 실패·jq 부재 시 무출력 → 호출부가 "판정 불가"로 처리한다(0 을 반환하면 방금 일어난 일로 오독된다).
_days_since() { # $1=ISO8601
  command -v jq >/dev/null 2>&1 || return 0
  jq -rn --argjson n "$(date -u +%s)" --arg d "$1" \
    '($d | try fromdateiso8601 catch empty) as $t | if $t then (($n - $t) / 86400 | floor) else empty end' 2>/dev/null
}

# 무음 실패 감지 (FID 20260815-doctor-stale-detect) — "동작하는데 아무도 안 읽는" 상태를 표면화.
#   계기: SessionStart pending 안내가 페이로드 뒤쪽에 묻혀 약 1개월간 미수신됐고, 그 사이 어떤
#   게이트도 이를 잡지 못했다. doctor 는 설치·정합만 보고 "얼마나 방치됐나" 축이 없었다.
#   3지표 종합 1행. 임계는 상수(설정화는 오탐 관측 후) — 진단 전용이라 어떤 흐름도 막지 않는다.
#
# JSONL 손상 내성 — `jq -rs`(전체 슬럽)는 **마지막 1줄만 깨져도 전량이 사라진다**.
#   friction-log·pending-capture 는 훅이 append 하는 파일이라 중단된 append 로 부분 라인이
#   실제로 생긴다. 그 경우 슬럽 파싱이 실패 → 건수 0 → "적체 없음" 이라는 무음 낙관 보고가
#   나온다(Phase C probeA·B 실증). 라인 단위로 파싱하고, 버려진 줄 수를 세어 판정을 강등한다.
#
# 아래 두 지표는 **파일당 jq 1회**로 손상 줄 수와 본 지표를 함께 낸다. `-Rs` 로 통째 읽어
#   jq 안에서 줄을 쪼개므로, 라인 내성을 얻으면서도 스폰 수는 기존(파일당 1회)과 같다.
#   friction-log 는 FID 마다 1개라 glob 이 선형 성장한다(실측 45개) — 파일당 스폰 1회 차이가
#   NFR-2 2초 예산을 직접 갉는다. 실측(45파일): 파일당 1회 0.4s대 · 파이프 2회 0.67s ·
#   `$(...)` 캡처 후 재투입 0.73s(직렬화라 오히려 느리다).
#   `objects` 필터 — JSON 으로는 유효하나 레코드가 아닌 줄(`123`)이 뒤 `.rule_id` 접근에서
#   jq 전체를 죽이지 않도록 여기서 떨군다(그런 줄은 손상으로 집계된다).
_JQ_SPLIT='[ split("\n")[] | select(length > 0) ] as $L
  | [ $L[] | fromjson? | objects ] as $J
  | (($L | length) - ($J | length)) as $bad'

# 파일 최종 갱신으로부터 경과일(정수). 판정 불가면 **무출력** — 0 을 돌려주면 "방금 갱신됨"
#   으로 오독돼 정체를 놓친다(_days_since 와 동일 계약).
# GNU/BSD `stat` 인자가 갈리므로 두 형태를 순서대로 시도한다.
_file_age_days() {  # $1=파일
  local mt now
  [ -f "$1" ] || return 0
  mt=$(stat -f %m "$1" 2>/dev/null) || mt=$(stat -c %Y "$1" 2>/dev/null) || return 0
  case "$mt" in ''|*[!0-9]*) return 0 ;; esac
  now=$(date -u +%s)
  echo $(( (now - mt) / 86400 ))
}

_chk_stale() {
  local now cutoff msgs="" have=0 bad=0 f
  command -v jq >/dev/null 2>&1 || {
    _add stale unknown "적체 지표 판정 불가 (jq 미설치)" ""
    return 0
  }
  now=$(date -u +%s); cutoff=$(( now - 30 * 86400 ))

  # ① pending 적체 — 최고령 항목 경과일 > 7일
  if [ -s "$SPECOPS/pending-capture.jsonl" ]; then
    have=1
    # "손상줄 유효건수 최고령일" 3필드를 jq 1회로 받는다. 건수는 **유효 라인만** 센다 —
    #   손상 라인은 내용을 신뢰할 수 없다. 경과일 없음(=ts 전무)은 `-` 로 표기한다.
    local pend_n pend_age pend_out pend_bad
    pend_out=$(jq -Rsr --argjson n "$now" "$_JQ_SPLIT"'
      | ([ $J[] | .ts // empty | try fromdateiso8601 catch empty ] | sort) as $t
      | "\($bad) \($J|length) \(if ($t|length) > 0 then (($n - $t[0]) / 86400 | floor) else "-" end)"' \
      "$SPECOPS/pending-capture.jsonl" 2>/dev/null) || pend_out=""
    if [ -z "$pend_out" ]; then
      # jq 자체가 실패하면 파일 전체를 읽지 못한 것이다 — 낙관(0건)이 아니라 전부 손상 취급해
      #   판정을 unknown 으로 떨어뜨린다. `|| echo 0` 금지(grep -c 는 0건에 "0" 출력 + rc=1 이라
      #   재발동해 "0\n0" 이 된다 — 실측). 기존 관용구(`|| true` + `[ -n ] || =0`)와 동형.
      pend_bad=$(grep -c . "$SPECOPS/pending-capture.jsonl" 2>/dev/null || true)
      # ★ 0·빈값이면 1 로 올린다 — 여기 온 파일은 `-s`(비어있지 않음)를 통과했는데 jq 가
      #   못 읽은 것이다. grep 마저 못 세면(권한 000 등) 0 이 되어 **다시 "적체 없음" 낙관**으로
      #   떨어진다(실측: chmod 000 픽스처가 ✅ 로 보고됐다). 못 읽은 파일은 최소 1줄 미상이다.
      case "$pend_bad" in ''|0) pend_bad=1 ;; esac
      pend_n=0; pend_age="-"
    else
      pend_bad=${pend_out%% *}; pend_age=${pend_out##* }
      pend_n=${pend_out#* }; pend_n=${pend_n%% *}
      case "$pend_bad$pend_n" in ''|*[!0-9]*) pend_bad=0; pend_n=0 ;; esac
    fi
    bad=$(( bad + pend_bad ))
    [ "$pend_age" = "-" ] && pend_age=""
    [ -n "$pend_age" ] && [ "$pend_age" -gt 7 ] \
      && msgs="${msgs}${msgs:+ · }pending ${pend_n}건 적체(최고령 ${pend_age}일)"
  fi

  # ② freelog 정체 — 마지막 기록 후 14일 초과 AND 그 이후 커밋 1건 이상
  #    커밋 0이면 정체가 아니라 휴지다(오탐 방지 — AC-3).
  if [ -s "$SPECOPS/freelog.md" ]; then
    have=1
    local last_ymd fl_days fl_commits iso
    last_ymd=$(grep -oE '^## [0-9]{8}' "$SPECOPS/freelog.md" 2>/dev/null | tail -1 | tr -dc '0-9')
    if [ -n "$last_ymd" ]; then
      iso="${last_ymd:0:4}-${last_ymd:4:2}-${last_ymd:6:2}T00:00:00Z"
      fl_days=$(_days_since "$iso")
      # ★ 앵커는 `$iso`(UTC 자정) — `--since=YYYY-MM-DD` 의 approxidate 는 **실행 시각-of-day**
      #   를 앵커로 잡아 같은 데이터에 실행 시각마다 다른 답이 나온다(Phase C 실측: 01:29 커밋이
      #   14:39 실행에서 0건). 이미 계산해 둔 iso 를 쓰면 공짜로 결정적이다.
      fl_commits=$(git log --oneline --since="$iso" 2>/dev/null | grep -c . || true)
      [ -n "$fl_commits" ] || fl_commits=0
      [ -n "$fl_days" ] && [ "$fl_days" -gt 14 ] && [ "$fl_commits" -ge 1 ] \
        && msgs="${msgs}${msgs:+ · }freelog ${fl_days}일 정체(그 사이 커밋 ${fl_commits})"
    fi
  fi

  # ③ 우회 상시화 — 최근 30일 BYPASS-ENV 3건 이상
  #    ★ cutoff 를 필터에 실제로 적용한다 — clarify F-1 이 잡은 결함(argjson 만 넘기고
  #      select 에서 안 쓰면 전 기간을 세어 누적 21건인 repo 가 항상 warn 이 된다).
  local byp=0 n fout fbad
  for f in "$SPECOPS"/friction-log.jsonl "$SPECOPS"/*/friction-log.jsonl; do
    [ -s "$f" ] || continue
    have=1
    # "손상줄 우회건수" 2필드를 jq 1회로 받는다 (파일당 스폰 1회 유지).
    fout=$(jq -Rsr --argjson c "$cutoff" "$_JQ_SPLIT"'
      | ([ $J[] | select(.rule_id == "BYPASS-ENV")
                | select(((.ts // "") | try fromdateiso8601 catch 0) >= $c) ] | length) as $hit
      | "\($bad) \($hit)"' "$f" 2>/dev/null) || fout=""
    if [ -z "$fout" ]; then
      # 파일 전체 판독 실패 → 전부 손상 취급(무음 낙관 금지). pending 쪽과 동형 —
      #   grep 마저 못 세는 경우(권한 등)도 0 이 아니라 1(최소 1줄 미상)로 둔다.
      fbad=$(grep -c . "$f" 2>/dev/null || true); case "$fbad" in ''|0) fbad=1 ;; esac; n=0
    else
      fbad=${fout%% *}; n=${fout##* }
      case "$fbad$n" in ''|*[!0-9]*) fbad=0; n=0 ;; esac
    fi
    bad=$(( bad + fbad ))
    byp=$(( byp + n ))
  done
  [ "$byp" -ge 3 ] && msgs="${msgs}${msgs:+ · }최근 30일 우회 ${byp}건"

  # ④ batch 정체 — queue 미완 + N일 무갱신 (20260829-batch-stall-visibility)
  #
  # 왜 여기인가: argus 실측에서 FR 31건이 IMPL_DONE 에 멈춘 채 방치됐고, 그 사실을 **아무도
  #   묻지 않았다**. v1.81.0 의 batch-resume-check 가 SessionStart 에 표면화하지만 두 구멍이
  #   남는다 — ① 나이가 없어 매 세션 같은 줄이 나오고(2주면 벽지가 된다: skip-tracker advisory
  #   와 같은 형태) ② `ACTIVE` 마커에만 의존해 마커 없이 방치된 미완 queue 는 아예 안 보인다.
  #   stale 축은 이미 "적체·정체" 를 일수 임계로 모으는 자리라 여기 얹는다.
  # ★ 한계 고백: 문제 A 자체는 도구로 닫히지 않는다. "세션이 끝나면 이어받을 주체가 없다" 는
  #   모델이 들고 있는 오케스트레이션 루프의 성질이고, 도구가 살 수 있는 것은 **탐지와 재개성**뿐이다.
  # 판정: queue 표에서 SKIP 을 분모에서 뺀 뒤 완료(IMPL_DONE|MERGED) 미달이면 미완.
  #   전 FR 완료 + ACTIVE 잔존 = Phase 3 미실행(argus 상태) 도 미완으로 본다.
  #   전 FR 완료 + 마커 없음 = Step D 정상 종결 → 보고하지 않는다.
  # 라벨 정규화는 queue-lib 를 재사용한다 — 여기서 정규식을 새로 쓰면 20260828-queue-label-drift
  #   가 고친 드리프트를 소비자 하나에 그대로 되살린다.
  local _qlib="$PLUGIN/scripts/_internal/queue-lib.sh"
  if [ -f "$_qlib" ]; then
    # shellcheck source=/dev/null
    . "$_qlib"
    local bthr="${DOCTOR_BATCH_STALE_DAYS:-14}" q bdir bid bage bcnt bdone btot stalled=""
    for q in "$SPECOPS"/batch-*/queue.md; do
      [ -f "$q" ] || continue
      have=1
      bdir=$(dirname "$q"); bid=$(basename "$bdir")
      bcnt=$(awk -F'|' "$QUEUE_AWK_QNORM"'
        /^[[:space:]]*\|/ {
          id = qnorm($2)
          if (id == "FR-ID" || id !~ /^FR-/) next
          st = ""
          for (i = NF; i >= 1; i--) { if (qnorm($i) != "") { st = qnorm($i); break } }
          if (st == "SKIP") next
          total++
          if (st ~ /^(IMPL_DONE|MERGED)$/) done_n++
        }
        END { printf "%d %d", done_n + 0, total + 0 }
      ' "$q")
      bdone=${bcnt% *}; btot=${bcnt#* }
      [ "${btot:-0}" -gt 0 ] || continue
      # 종결 판정: 전 FR 완료 AND ACTIVE 부재 → 정상 종결, 보고 대상 아님
      if [ "$bdone" -eq "$btot" ] && [ ! -f "$bdir/ACTIVE" ]; then continue; fi
      # 나이 — queue.md 최종 갱신 기준(파일시스템만, 네트워크·per-FID spawn 없음)
      bage=$(_file_age_days "$q")
      [ -n "$bage" ] || continue                # 판정 불가는 조용히 건너뛴다
      [ "$bage" -ge "$bthr" ] || continue       # 진행 중인 최근 batch 를 정체로 부르지 않는다
      stalled="${stalled}${stalled:+, }${bid}(${bdone}/${btot}·${bage}일)"
    done
    [ -n "$stalled" ] && msgs="${msgs}${msgs:+ · }정체 batch ${stalled}"
  fi

  if [ "$have" -eq 0 ]; then
    _add stale unknown "적체 지표 판정 불가 (pending·freelog·friction-log 전부 부재)" ""
  elif [ -n "$msgs" ]; then
    [ "$bad" -gt 0 ] && msgs="${msgs} · 손상 라인 ${bad}줄 제외"
    _add stale warn "$msgs" "/log 로 기록하거나 pending 을 처리하세요"
  elif [ "$bad" -gt 0 ]; then
    # ★ 손상 라인이 있으면 "적체 없음" 이 아니라 판정 불가다 — 읽지 못한 줄에 적체가 있었을 수
    #   있으므로 무음 낙관 보고를 금지한다(Phase C Important 1·2).
    _add stale unknown "적체 지표 부분 판정 불가 (손상 라인 ${bad}줄)" "해당 JSONL 을 확인하세요"
  else
    _add stale ok "적체 없음 (pending·freelog·우회 전부 임계 미만)" ""
  fi
}

# 거버넌스 훅이 실제로 켜져 있는가 — 종전엔 어떤 항목도 이걸 보지 않아,
# .specops/config.yaml 4줄로 전 훅이 꺼져도 표가 전부 ✅/⚠️ 로 정상 보고했다.
_chk_governance() {
  # ★ SPECOPS_CONFIG 를 넘기지 않으면 is-hook-enabled 는 자기 기본값(cwd 의 .specops/config.yaml)을
  #   본다 — SPECOPS_ROOT 가 다른 곳을 가리키면 **한 리포트 안에 root 가 2개**가 되고, 실제로
  #   꺼진 프로젝트가 `✅ 훅 4종 활성` 로 보고된다(Phase C Important 1 실측: 표면화 장치의 거짓 ✅).
  #   사용자가 이미 export 한 SPECOPS_CONFIG 는 존중한다(`:-`). 기본 root 에선 값이 동일해 무변경.
  # ★ rc 를 뭉뚱그리면 판정기 부재(127)·사용법 오류(2)까지 "비활성" 으로 계상돼 **원인 귀속이 틀린다**
  #   — 사용자가 엉뚱하게 config.yaml 만 뒤진다(Phase C Minor 1). rc=1 만 진짜 비활성이고
  #   그 외 비-0 은 판정 불가(unknown)다.
  local h rc off="" n=0 bad="" nbad=0
  for h in pretool-governance posttool-governance stop-governance session-start; do
    if SPECOPS_CONFIG="${SPECOPS_CONFIG:-$SPECOPS/config.yaml}" \
       bash "$PLUGIN/scripts/_internal/is-hook-enabled.sh" "$h" >/dev/null 2>&1; then
      rc=0
    else
      rc=$?
    fi
    if [ "$rc" -eq 1 ]; then
      off="${off}${off:+,}${h}"; n=$((n+1))
    elif [ "$rc" -ne 0 ]; then
      bad="${bad}${bad:+,}${h}(rc=${rc})"; nbad=$((nbad+1))
    fi
  done
  if [ "$n" -eq 0 ] && [ "$nbad" -eq 0 ]; then
    # 켜져 있는 것과 동작하는 것은 다르다 — jq 가 없으면 훅은 전부 fail-open 한다.
    #   종전에는 한 표에 `governance ✅ 훅 4종 활성` 과 `deps ⚠️ … 거버넌스 비활성` 이 같이 나왔다.
    if command -v jq >/dev/null 2>&1; then
      _add governance ok "훅 4종 활성" ""
    else
      _add governance warn "훅 4종이 켜져 있으나 jq 미설치 — 전부 fail-open 이라 차단·감사가 동작하지 않는다" "brew install jq"
    fi
  elif [ "$nbad" -eq 0 ]; then
    _add governance warn "훅 ${n}/4 비활성: ${off}" ".specops/config.yaml 의 profile/hooks 설정을 확인하세요"
  elif [ "$n" -eq 0 ]; then
    _add governance unknown "훅 ${nbad}/4 판정 불가 (is-hook-enabled 실행 실패): ${bad}" \
      "scripts/_internal/is-hook-enabled.sh 가 실행 가능한지 확인하세요"
  else
    _add governance warn "훅 ${n}/4 비활성: ${off} · ${nbad}종 판정 불가: ${bad}" \
      ".specops/config.yaml 설정과 is-hook-enabled.sh 실행 가능 여부를 함께 확인하세요"
  fi
}

# 거버넌스가 의존하는 도구 — jq 부재는 훅 전체를 fail-open 시키고,
# python3/pyyaml 부재는 is-hook-enabled 를 default enabled 로 만들어
# 위 governance 항목이 config 킬스위치를 **탐지하지 못하게** 한다(표면화 장치의 무력화).
_chk_deps() {
  # ★ 두 부재의 귀결이 다르다 — 뭉뚱그리면 이 항목 자체가 부정확한 보고가 된다(plan-review 2회차).
  #   jq 부재      → 훅이 전면 fail-open (거버넌스 비활성)
  #   pyyaml 부재  → is-hook-enabled 가 default enabled 로 답해 governance 항목이 킬스위치를 못 봄
  #   pyyaml 만 없고 jq 는 있으면 훅은 **정상 동작**한다 — "거버넌스 비활성" 은 거짓이다.
  local miss="" note="" fixcmd=""
  if ! command -v jq >/dev/null 2>&1; then
    miss="jq"; note=" — 거버넌스 비활성"; fixcmd="brew install jq"
  fi
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import yaml" 2>/dev/null; then
    miss="${miss}${miss:+,}python3/pyyaml"
    note="${note} · governance 항목이 config 킬스위치를 탐지 못 함"
    # PEP 668(externally-managed) 환경에서는 맨 `pip3 install` 이 거부된다 — 그때의 길을 같이 적는다.
    fixcmd="${fixcmd}${fixcmd:+ · }pip3 install pyyaml (externally-managed 오류면: Debian·Ubuntu 는 apt install python3-yaml, 그 밖은 pip3 install --user --break-system-packages pyyaml)"
  fi
  if [ -z "$miss" ]; then
    _add deps ok "jq · python3/pyyaml 확인" ""
  else
    _add deps warn "미설치: ${miss}${note}" "$fixcmd"
  fi
}

# CLAUDE_CODE_EFFORT_LEVEL — env 가 설정되면 skill·agent frontmatter effort 가 전부 무력화된다
#   (env > frontmatter — 공식 문서. skill 은 20261007 실측으로도 전 구간 env 값 고정 확인, agent 는 문서 기준). 서브에이전트 effort 프로파일(PR #105)도 포함.
#   doctor 는 자기 프로세스 env 만 관측한다 — 미설정 보고가 무력화 없음의 증명은 아니다(상속 경로 한계).
#   빈 값은 미설정으로 본다. 표준 레벨 목록은 복제하지 않는다(모델별로 달라 drift) — env 존재 자체가 경고 사유.
_chk_effort_env() {
  local v="${CLAUDE_CODE_EFFORT_LEVEL:-}"
  if [ -z "$v" ]; then
    _add effort_env ok "CLAUDE_CODE_EFFORT_LEVEL 미설정 — skill·agent frontmatter effort 정상 적용 (doctor 는 자기 프로세스 env 만 관측)" ""
  else
    _add effort_env warn "CLAUDE_CODE_EFFORT_LEVEL=${v:0:24} 설정됨 — skill·agent frontmatter effort(서브에이전트 프로파일 포함)가 전부 무력화됨 · 의도한 설정이면 무시 가능" "셸/프로필의 CLAUDE_CODE_EFFORT_LEVEL 을 unset 하거나 settings 의 env 에서 제거"
  fi
}

# 관제판(mod) — Claude Code 2.1.287 이상에서만 로드된다. 조회만 한다.
_chk_console() {
  local v min=2.1.287
  if ! command -v claude >/dev/null 2>&1; then _add console unknown "claude CLI 없음 — 관제판(mod) 버전 판정 불가" ""; return; fi
  v=$(claude --version 2>/dev/null | sed -n 's/^\([0-9][0-9.]*\).*/\1/p')
  if [ -z "$v" ]; then _add console unknown "claude --version 출력을 판독하지 못함 — 관제판(mod) 버전 판정 불가" ""; return; fi
  if [ "$(printf '%s\n%s\n' "$min" "$v" | sort -V | head -1)" = "$min" ]; then _add console ok "Claude Code $v — 관제판 사용 가능(2.1.287 이상)" ""
  else _add console warn "Claude Code $v < $min — 관제판 비활성" "Claude Code 를 2.1.287 이상으로 올리세요"; fi
}

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

# 비-specops repo — 프로젝트 항목은 내지 않는다(플러그인은 자기 관할만 통제한다 — 5원칙 4 주권).
#   환경 항목(deps·effort_env)은 낸다: README 가 "설치 직후 /doctor 로 deps 확인" 을 안내하는데 설치 직후에는
#   `.specops/` 가 없다. 종전에는 그 시점에 아무 항목도 내지 않아, jq 부재(훅 전면 fail-open)를 도입 전에 알 길이 없었다.
SCOPE="project"
if [ ! -d "$SPECOPS" ]; then
  SCOPE="env-only"
  _chk_deps
  _chk_effort_env
else
  _chk_hooks
  _chk_memory
  _chk_orphan
  _chk_progress
  _chk_bootstrap
  _chk_stale
  _chk_governance
  _chk_deps
  _chk_console
  _chk_effort_env
fi

if [ "$JSON" -eq 1 ]; then
  # jq 가 없으면 표를 JSON 으로 만들 수 없다 — 빈 checks 로 "문제 없음" 을 흉내내지 않고 사유를 싣는다.
  if ! command -v jq >/dev/null 2>&1; then
    printf '{"schema_version":1,"scope":"%s","checks":[{"id":"deps","status":"warn","detail":"jq 미설치 — JSON 출력 불가(표 출력은 --json 없이)","fix":"brew install jq"}],"warn_count":1}\n' "$SCOPE"
    exit 0
  fi
  printf '%s' "$ROWS" | jq -Rs --arg scope "$SCOPE" '
    [ split("\n")[] | select(length > 0) | split("|")
      | {id: .[0], status: .[1], detail: .[2], fix: .[3]} ] as $c
    | {schema_version: 1, scope: $scope, checks: $c,
       warn_count: ([$c[] | select(.status != "ok")] | length)}'
  exit 0
fi

if [ "$SCOPE" = "env-only" ]; then
  printf 'specops 미사용 프로젝트입니다 (%s 부재) — 프로젝트 항목은 건너뛰고 환경 항목만 점검합니다. 도입은 `/init-project`.\n\n' "$SPECOPS"
fi
printf '### specops 건강 진단\n\n| 항목 | 상태 | 상세 | 조치 |\n|---|---|---|---|\n'
printf '%s' "$ROWS" | while IFS='|' read -r id st detail fix; do
  [ -n "$id" ] || continue
  case "$st" in ok) icon="✅" ;; *) icon="⚠️" ;; esac
  printf '| %s | %s | %s | %s |\n' "$id" "$icon" "$detail" "$fix"
done
exit 0
