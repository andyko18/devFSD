#!/usr/bin/env bash
# /basic 경로의 기계 절차 (20261112 speed) — spec 1장 → 주 세션 직접 구현 → 리뷰 1회 → 검증 1회 → PR.
#
# Usage:
#   basic-path.sh route <start|maintain> "<인자 원문>"   /start·/maintain·자연어 진입의 갈래 고르기(쓰지 않는다) — `ROUTE: basic|full — <이유>` + NOTICE·KIND·PROCEDURE(기본 경로 절차 파일)·ENTRY(진입 명령 파일)·OPTIONS·REQUEST 줄
#   basic-path.sh lane "<요청 한 줄>" [<FID>]   갈래 판정만 한다(쓰지 않는다) — `LANE: basic|full <신호>` 1줄
#   basic-path.sh start <FID> "<요청 한 줄>" [maintain]   갈래 판정 → FID 폴더·진행 기록·spec 골격(기본 브랜치 위면 브랜치도) · maintain = 유지보수 골격(현재 동작 절 · AC-R-1)
#   basic-path.sh approve <FID>                 사용자 승인 뒤: spec 절 확인 → 갈래 재판정 → acceptance-criteria.md 도출 · `SIGNALS:`·`EXPERTS:` 줄(켤 단계)
#   basic-path.sh plan <FID> <태스크 수>        승인 뒤·구현 전: 켤 단계 판정 — `PLAN: yes <경로>|skip` · `EXPERTS: <에이전트…>|none` · 태스크 수가 상한 이상이면 rc 3(풀 경로로)
#   basic-path.sh review <FID>                  구현 뒤·리뷰 dispatch 직전: 진행 기록만 남긴다(구현 완료 · 리뷰 진행 — 관제판 단계 표시)
#   basic-path.sh related                       검증에 쓸 test_command 제안 — `RELATED: <명령>` 또는 `RELATED: none — <사유>`(쓰지 않는다)
#   basic-path.sh seal <FID> "<test_command>"   리뷰 뒤: 변경 파일로 갈래 재판정 → 1-태스크 문서 · 리뷰 감사 행
#   basic-path.sh design-scope <화면 수> [new|flow]   화면 설계 확인 범위 — `DESIGN: none|update|approve` + `UI:` 줄(이식·브라우저 점검 안내 — 항상 1줄)
#   basic-path.sh promote <FID> "<사유>"        풀 경로로 올린다 — 기본 경로 산출물을 basic-draft/ 로 보존 · 진행 기록 · 이어 갈 skill 과 args 줄 안내
#   basic-path.sh done <FID> "<한 줄 요약>"     종결 기록
# Exit: 0 = 성공 · 3 = 풀 경로 대상(위험 신호) · 4 = 리뷰 보고서 없음 · 1 = 그 밖(입력 오류 · 절 누락 · 관할 아님)
#
# 통합 절차 (20261114): 위험 신호는 갈래가 아니라 **켤 단계**를 정한다 — 신호가 걸리면 이 경로 안에서 분석 문서(유지보수)·계획·
#   그 신호의 전문가 1종을 켠다. 풀 경로(종전 skill chain)로 넘기는 것은 무거운 신호(데이터 삭제·이관 · 되돌릴 수 없는 외부 작업 ·
#   결제·개인정보) · 태스크 수 상한 이상 · --full · --step 뿐이다. 끄는 스위치: SPECOPS_UNIFIED_PATH=0 또는 .specops/config.yaml 의
#   `unified_path: false` — 끄면 아래 종전 규칙(신호가 하나라도 있으면 풀)이다.
# 갈래(종전 규칙): 풀 = 인증·권한 변경 · DB 스키마 변경 · 데이터 삭제·이관 · 기존 API 응답 형태 변경 · 되돌릴 수 없는 외부 작업.
#   기존 판정기(risk-profile.sh 의 rp::detect_strict_signals — 영문 낱말·경로)를 그대로 쓰고, 그것이 못 잡는 한글 낱말만 여기서 더한다.
#   **애매하면 무거운 쪽이다** — 신호가 하나라도 보이면 풀이다. spec 은 무엇을 바꾸는지 적는 절(목표·범위)만 본다 — "범위 밖"·"현재 동작" 절과
#   수용 기준·비기능 요구의 낱말은 판정에서 뺀다(_spec_corpus). 적지 않은 변경은 seal 이 바뀐 파일 경로로 잡는다(경로 이름에 한함).
# 강제는 여기가 아니라 기존 훅이 한다: 이 경로의 FID 는 spec.md + tasks.md 를 가진 **정식 FID** 다 — 커밋(R-1)·PR(R-2)은
#   run-verification.sh 의 `VERIFY: PASS` 실행 출력과 진행 기록이 있어야 열린다. 훅·검증 러너는 고치지 않았다.
set -u

BASIC_FULL_TASK_MIN=4         # 태스크가 이 수 이상이면 풀 경로로 넘긴다(계획 리뷰·태스크별 구현자가 거기 있다 — 근거 얇은 초기값 · 여기 한 곳)
# 통합 절차에서도 항상 풀 경로인 신호 — 되돌리기 어려운 것. destructive_fs(rm -rf · irreversible: true)·infra(deploy · 워크플로)도 여기다
#   (한글 "운영 배포" 가 irreversible_ext 로 풀인데 영문 deploy 만 가벼우면 어긋난다 — 코드 리뷰 실측).
BASIC_HARD_SIGNALS="data_move irreversible_ext payment_pii destructive_fs infra"
BASIC_SCREEN_APPROVAL_MIN=3   # 이 수 이상의 화면을 고치면 화면 스펙·목업을 먼저 만들고 승인받는다(근거 얇은 기본값 — 여기 한 곳에서 고친다)

ACTION="${1:-}"
SPECOPS="${SPECOPS_ROOT:-.specops}"
# risk-profile.sh 는 source 되면 PLUGIN·SPECOPS 를 자기 기준($0 의 두 단계 위)으로 다시 잡는다 — 이 스크립트는 한 단계 위가 루트라 이름을 달리 쓴다.
BP_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BP_SPECOPS="$SPECOPS"
APPEND="$BP_ROOT/scripts/session-progress-append.sh"

_die() { echo "basic-path: $1" >&2; exit "${2:-1}"; }
_fid_ok() { printf '%s' "$1" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || _die "FID 형식이 아니다 (YYYYMMDD-kebab-slug): $1"; }

# 한글 위험 낱말 — rp::detect_strict_signals 가 보지 않는 것만.
_ko_signals() {  # <말뭉치>
  local c="$1" s="" t
  # `토큰` 은 인증 말고도 쓴다 — 판정 줄(VERIFY 토큰)·LLM 사용량(토큰 비용·출력 토큰·12M 토큰). 그 쓰임만 지우고 본다
  #   (20261112 실측: spec 의 "VERIFY 토큰" 으로 승인 단계에서 풀 판정이 났다). 지우고도 남는 `토큰` 은 종전대로 auth 다 —
  #   맨 `토큰`·"세션 토큰" 은 풀이다(애매하면 무거운 쪽). 괄호식에 한글을 넣지 않는다(C 로케일에서 바이트로 쪼개진다).
  t=$(printf '%s\n' "$c" | sed -E \
    -e 's/VERIFY[^[:space:]]{0,3} ?토큰//g' \
    -e 's/(실행-근거|출력|입력|캐시|판정|PASS|FAIL|LLM|모델|프롬프트|컨텍스트) ?토큰//g' \
    -e 's/토큰 ?(비용|사용량|소비|소진|절감|경제|예산|한도)//g' \
    -e 's/[0-9][0-9.,]*([KMkm]|만|천)? ?토큰//g')
  { printf '%s\n' "$c" | grep -qE '인증|인가|권한|로그인|비밀번호' || printf '%s\n' "$t" | grep -q '토큰'; } && s="$s auth"
  printf '%s\n' "$c" | grep -qE '스키마|마이그레이션|컬럼|테이블 ?(추가|변경|삭제|생성)|인덱스 ?(추가|삭제)' && s="$s db_schema"
  printf '%s\n' "$c" | grep -qiE '데이터 ?(삭제|이관|이전|정리)|일괄 ?삭제|백필|backfill|truncate|purge' && s="$s data_move"
  printf '%s\n' "$c" | grep -qiE '응답 ?(형태|형식|구조|필드|스키마)|하위 ?호환|breaking|API ?(변경|수정|삭제)' && s="$s api_shape"
  printf '%s\n' "$c" | grep -qE '운영 ?(배포|반영)|결제|과금|환불|(메일|문자|푸시|알림) ?발송|되돌릴 수 없' && s="$s irreversible_ext"
  printf '%s' "$s"
}

# spec 에서 **무엇을 바꾸는지 적는 절(목표·범위)** 만 꺼낸다 — 갈래는 낱말이 나왔는가가 아니라 그 일을 하는가로 정한다.
#   수용 기준의 전제("로그인한 사용자가…")·현재 동작 설명·비기능 요구에 나온 낱말은 바꾸는 일이 아니다
#   (20261114 실측: 하류 앱 spec 144건을 전문으로 보면 기본 15% · 목표·범위 절만 보면 43%).
#   그 안에서도 "범위 밖"·"제외"·"현재 동작" 절은 뺀다(하지 않는 일 · 지금 코드의 설명). 가림은 그 절에서 끝난다.
#   목표·범위 절이 하나도 없는 문서(골격이 다른 spec)는 종전대로 전문을 본다 — 모르면 무거운 쪽이다.
#   안전망: seal 이 **바뀐 파일 경로**로 한 번 더 판정한다(_path_signals — 경로 이름에 한한다. 파일 내용은 보지 않으므로
#   평범한 이름의 파일 안에서 한 위험 변경은 여기서 걸리지 않는다 — 그것은 범위 절에 적는 규칙과 리뷰·보안 스캔이 받는다).
_spec_corpus() {  # <spec.md>
  [ -f "$1" ] || return 0
  awk '
    function lvl(s,  n) { n = 0; while (substr(s, n + 1, 1) == "#") n++; return n }
    # 제목으로 치는 것은 코드 펜스 밖의 2단계 이상뿐이다 — 1단계 제목(문서 제목)과 펜스 안 `# 주석` 이 가림을 열면 문서 끝까지 닫히지 않는다.
    function head(s) { return (!fence && s ~ /^##+ /) }
    { all[++na] = $0 }
    /^(```|~~~)/ { fence = !fence }
    head($0) { d = lvl($0)
               if (skip && d <= depth) skip = 0
               # 2단계: 목표·범위 절만 남긴다. 제목에 "제외" 같은 말이 붙어도 그 절은 본다("## 2. 범위 (인증 제외)") — "범위 밖" 절만 뺀다.
               if (d == 2) { keep = ($0 ~ /(목표|범위)/ && $0 !~ /범위 밖/); if (keep) found = 1 }
               else if (!skip && $0 ~ /(범위 밖|제외|하지 않는|현재 동작)/) { skip = 1; depth = d; next } }
    keep && !skip { out[++no] = $0 }
    END {
      if (found) { for (i = 1; i <= no; i++) print out[i]; exit }
      skip = 0; fence = 0
      for (i = 1; i <= na; i++) {
        l = all[i]
        if (l ~ /^(```|~~~)/) fence = !fence
        if (head(l)) { if (skip && lvl(l) <= depth) skip = 0
                       if (!skip && l ~ /(범위 밖|제외|하지 않는)/) { skip = 1; depth = lvl(l); continue } }
        if (!skip) print l
      }
    }
  ' "$1"
}

# 바뀐 파일 경로의 위험 신호 — rp::detect_strict_signals 의 경로 패턴이 못 잡는 것만(봉인 단계의 안전망).
#   경로만 본다(파일 내용은 보지 않는다): 스키마 정의·ORM 모델 파일 → DB 스키마, 인증·세션 이름이 든 경로 → 인증.
#   새 화면·새 라우트 파일은 신호가 아니다(풀 신호는 "기존 API 응답 형태 변경"이고 경로로는 알 수 없다 — 그것은 범위 절과 리뷰가 받는다).
_path_signals() {  # <변경 파일 목록(줄 단위)>
  local f="$1" s=""
  [ -n "$f" ] || return 0
  printf '%s\n' "$f" | grep -qiE '(^|/)schema\.[a-z]+$|\.sql$|(^|/)(models|entities|entity)(/|\.py$)|\.entity\.[a-z]+$|(^|/)models\.py$' && s="$s db_schema"
  # `author`(글쓴이)·`session-progress` 같은 이름은 인증이 아니다 — auth 뒤에 o 가 오면 빼고, session 은 그 이름의 파일·폴더만 친다.
  printf '%s\n' "$f" | grep -qiE 'auth([^o]|$)|login|(^|/)sessions?(\.|/|$)|permission|password|passwd|guard|rbac' && s="$s auth"
  printf '%s' "$s"
}

# 통합 절차 스위치 — 기본 켬. rc 0 = 켬.
_unified() {
  case "${SPECOPS_UNIFIED_PATH:-}" in 0|false|off) return 1 ;; 1|true|on) return 0 ;; esac
  # 따옴표·대소문자·no 도 끈 것으로 읽는다 — 끄려던 뜻이 조용히 무시되면 안 된다.
  [ -f "$BP_SPECOPS/config.yaml" ] && grep -qiE "^[[:space:]]*unified_path:[[:space:]]*[\"']?(false|off|no|0)[\"']?[[:space:]]*(#.*)?\$" "$BP_SPECOPS/config.yaml" && return 1
  return 0
}
# 신호 중 통합 절차에서도 풀 경로인 것만
_hard_of() {  # <신호…>
  local w out=""
  for w in $1; do case " $BASIC_HARD_SIGNALS " in *" $w "*) out="${out:+$out }$w" ;; esac; done
  printf '%s' "$out"
}
# 신호 → 켤 전문가 에이전트(중복 없이). 무거운 신호는 대상이 아니다(풀 경로가 받는다).
_experts_of() {  # <신호…>
  local w a out=""
  for w in $1; do
    case "$w" in
      db_schema|db_migration) a="devfsd:db-designer-ko" ;;
      api_shape|public_api) a="devfsd:api-designer-ko" ;;
      cross_service) a="devfsd:arch-designer-ko" ;;
      auth|destructive_fs|external_exec|infra) a="devfsd:security-designer-ko" ;;
      *) a="" ;;
    esac
    [ -n "$a" ] || continue
    case " $out " in *" $a "*) ;; *) out="${out:+$out }$a" ;; esac
  done
  printf '%s' "$out"
}
# 신호 수집 — stdout 신호 목록(공백 구분 · 없으면 빈 줄) · rc 1 = 판정기 로드 불가
_signals() {  # <요청 문장> [<FID>] [<변경 파일 목록>]
  local text="$1" fid="${2:-}" files="${3:-}" corpus sig
  # shellcheck source=/dev/null
  . "$BP_ROOT/scripts/_internal/risk-profile.sh" 2>/dev/null || return 1
  SPECOPS="$BP_SPECOPS"
  corpus="$text"
  [ -n "$fid" ] && corpus="$corpus
$(_spec_corpus "$SPECOPS/$fid/spec.md")"
  sig="$(rp::detect_strict_signals "$corpus" "$files") $(_ko_signals "$corpus") $(_path_signals "$files")"
  printf '%s' "$sig" | xargs -n1 2>/dev/null | sort -u | xargs
}
# 갈래 판정 — stdout `LANE: basic`(+ 통합 절차에서 가벼운 신호가 있으면 `SIGNALS: <신호…>` 1줄) 또는 `LANE: full <신호…>`
#   rc 0 = basic, 3 = full, 1 = 판정기 로드 불가(막는다). 통합 절차: 무거운 신호만 풀. 스위치를 끄면 신호가 하나라도 있으면 풀.
_lane() {  # <요청 문장> [<FID>] [<변경 파일 목록>]
  local sig hard
  sig=$(_signals "$@") || { echo "LANE: full 판정기(risk-profile.sh)를 읽을 수 없다"; return 1; }
  if [ -z "$sig" ]; then echo "LANE: basic"; return 0; fi
  if _unified; then
    hard=$(_hard_of "$sig")
    if [ -n "$hard" ]; then echo "LANE: full $sig"; return 3; fi
    echo "LANE: basic"; echo "SIGNALS: $sig"; return 0
  fi
  echo "LANE: full $sig"; return 3
}
_full_msg() {  # [<FID>] — FID 가 있으면(만든 것이 있다) promote 로 올린다. 없으면 아무것도 만들지 않았다.
  if [ -n "${1:-}" ]; then
    echo "basic-path: 위험 신호가 있어 풀 경로 대상이다 — basic-path.sh promote $1 \"<사유>\" 로 풀 경로에 올린다(spec·코드는 그대로 남는다 · commands/basic.md 「풀 경로로 올리기」)." >&2
  else
    echo "basic-path: 위험 신호가 있어 풀 경로 대상이다 — 풀 경로(신규 specifying-ko · 유지보수 analyzing-ko)로 진행한다. 만든 것은 없다." >&2
  fi
}
# 신호 이름 → 사용자에게 보일 말
_sig_ko() {  # <신호…>
  local w out=""
  for w in $1; do
    case "$w" in
      auth) w="인증·권한" ;; db_schema|db_migration) w="DB 스키마" ;; data_move) w="데이터 삭제·이관" ;;
      api_shape|public_api) w="API 계약" ;; irreversible_ext) w="되돌릴 수 없는 외부 작업" ;; destructive_fs) w="파일 삭제" ;;
      payment_pii) w="결제·개인정보" ;; infra) w="배포·인프라" ;; external_exec) w="외부 명령 실행" ;; cross_service) w="서비스 간 연동" ;;
    esac
    case ", $out, " in *", $w, "*) ;; *) out="${out:+$out, }$w" ;; esac
  done
  printf '%s' "$out"
}
# 검증 러너의 허용 형식 — 정의는 run-verification.sh 한 곳이다(check-rule-commands.sh 와 같은 읽기).
_runner_accepts() {  # <test_command> → rc 0 = 받는다 · 1 = 받지 않는다 · 2 = 허용 형식을 읽을 수 없다
  local pat
  pat=$(grep -m1 '^_WHITELIST_PAT=' "$BP_ROOT/scripts/_internal/run-verification.sh" 2>/dev/null | sed -E "s/^_WHITELIST_PAT='(.*)'\$/\1/")
  [ -n "$pat" ] || return 2
  [[ "$1" =~ $pat ]] && [[ "$1" != *..* ]]
}

_changed_files() {
  # shellcheck source=/dev/null
  . "$BP_ROOT/scripts/_internal/risk-profile.sh" 2>/dev/null || return 1
  SPECOPS="$BP_SPECOPS"
  { rp::collect_files; git ls-files -o --exclude-standard 2>/dev/null; } | sed '/^$/d' | grep -v '^\.specops/' | sort -u
}

# 관련 스위트 — 이 저장소가 스위트 매핑(scripts/tests/run-related.sh)을 가질 때만 변경 파일이 닿는 스위트를 고른다.
#   stdout: 스위트 경로(한 줄에 하나) · rc 0 = 골랐다 · 3 = 매핑이 없거나 고를 수 없다(사유 1줄을 stdout 에 — 호출자는 프로젝트의 테스트 명령 전체를 쓴다)
BP_RELATED="scripts/tests/run-related.sh"
_related_suites() {
  local files out
  [ -f "$BP_RELATED" ] && [ -f scripts/tests/run-all.sh ] || { echo "이 저장소에는 관련 스위트 매핑($BP_RELATED)이 없다"; return 3; }
  files=$(_changed_files) || { echo "변경 파일을 알 수 없다"; return 3; }
  [ -n "$files" ] || { echo "변경된 파일이 없다"; return 3; }
  out=$(printf '%s\n' "$files" | bash "$BP_RELATED" --list 2>&1) || { printf '%s\n' "$out" | tail -1; return 3; }
  [ -n "$out" ] || { echo "고른 스위트가 없다"; return 3; }
  printf '%s\n' "$out"
}

case "$ACTION" in
  related)
    # 검증 1회에 쓸 명령을 제안한다(쓰지 않는다). 전체 스위트는 push 전 게이트와 PR 의 CI 가 맡는다 — 여기서 고르는 것은 그 앞의 빠른 확인이다.
    if out=$(_related_suites); then
      echo "RELATED: bash $BP_RELATED $(printf '%s\n' "$out" | paste -sd' ' -)"
    else
      echo "RELATED: none — $out (프로젝트의 테스트 명령 전체를 test_command 로 쓴다)"
    fi
    ;;

  route)
    # /start·/maintain·자연어 진입이 갈래를 고르는 한 곳. 판정은 _lane 그대로다(둘로 만들지 않는다). 쓰지 않는다.
    #   풀: --full · --step(단계별 확인은 풀 경로의 기능) · 위험 신호 · 진입 약속어가 든 인자 · .specops 없음 · 판정 불가. 애매하면 풀.
    KIND="${2:-}"; RAW="${3:-}"
    case "$KIND" in start|maintain) ;; *) _die "usage: $0 route <start|maintain> \"<인자 원문>\"" ;; esac
    opts=""; req=""
    set -f   # 요청 문장의 * ? 가 파일 이름으로 풀리지 않게
    for w in $(printf '%s' "$RAW" | tr '\n' ' '); do
      case "$w" in
        --full|--step|--no-split) opts="$opts $w" ;;
        *) req="${req:+$req }$w" ;;
      esac
    done
    set +f
    [ -n "$req" ] || _die "요청이 비었다 — 무엇을 만들거나 고칠지 먼저 묻는다"
    why=""
    case " $opts " in *" --full "*) why="--full 지정" ;; esac
    [ -n "$why" ] || case " $opts " in *" --step "*) why="--step 지정(단계별 확인은 풀 경로)" ;; esac
    [ -n "$why" ] || case "$RAW" in *'<!--'*) why="진입 약속어가 든 인자(일괄·공통부 등은 종전 경로)" ;; esac
    [ -n "$why" ] || [ -d "$SPECOPS" ] || why="이 저장소에 $SPECOPS 가 없다(관할은 풀 경로가 연다)"
    if [ -z "$why" ]; then
      out=$(_lane "$req" "" ""); rc=$?
      case "$rc" in
        0) ;;
        3) why="위험 신호($(_sig_ko "$(printf '%s\n' "$out" | sed -n '1s/^LANE: full //p')"))" ;;
        *) why="위험 신호 판정 불가" ;;
      esac
    fi
    if [ -n "$why" ]; then
      echo "ROUTE: full — $why"
      echo "NOTICE: 풀 경로로 진행 — $why."
    else
      soft=$(printf '%s\n' "${out:-}" | sed -n 's/^SIGNALS: //p')
      if [ -n "$soft" ]; then
        echo "ROUTE: basic — 위험 신호($(_sig_ko "$soft")): 계획·전문가 검토를 켠다"
        echo "NOTICE: 기본 경로로 진행 — 위험 신호($(_sig_ko "$soft"))가 있어 계획과 전문가 검토를 켠다. 풀 경로는 \`--full\`."
      else
        echo "ROUTE: basic — 위험 신호 없음"
        echo "NOTICE: 기본 경로로 진행 — 위험 신호 없음. 풀 경로는 \`--full\`."
      fi
      echo "KIND: $KIND"
      echo "PROCEDURE: $BP_ROOT/commands/basic.md"
    fi
    echo "ENTRY: $BP_ROOT/commands/$KIND.md"
    echo "OPTIONS:${opts:- (없음)}"
    echo "REQUEST: $req"
    ;;

  lane)
    [ -n "${2:-}" ] || _die "usage: $0 lane \"<요청 한 줄>\" [<FID>]"
    [ -z "${3:-}" ] || _fid_ok "$3"
    _lane "$2" "${3:-}" ""; exit $?
    ;;

  design-scope)
    n="${2:-}"; kind="${3:-}"
    case "$n" in ''|*[!0-9]*) _die "usage: $0 design-scope <화면 수> [new|flow]" ;; esac
    case "$kind" in ""|new|flow) ;; *) _die "둘째 인자는 new(새 화면) 또는 flow(흐름 변경)" ;; esac
    if [ -n "$kind" ] || [ "$n" -ge "$BASIC_SCREEN_APPROVAL_MIN" ]; then
      echo "DESIGN: approve — 화면 스펙·목업을 먼저 만들고 승인받는다 (/design-screen · /design-screens)"
    elif [ "$n" -ge 1 ]; then
      echo "DESIGN: update — 기존 화면 스펙(screens/<name>.md)의 해당 부분을 구현과 함께 갱신한다"
    else
      echo "DESIGN: none — 문구·스타일만 바뀐다(화면 설계 확인 없음)"
    fi
    # 설계 확인 범위와 별개 — 화면을 건드리는 작업이면 구현 품질 두 가지를 항상 알린다(하류 실측: 목업 클래스 생존율 8%·33%)
    echo "UI: 목업 CSS 이식을 구현 첫 일로(목업이 있는 화면) · 봉인 전 브라우저 점검 1회(ui-probe.cjs — commands/basic.md 5번·7번)"
    ;;

  start)
    FID="${2:-}"; ARG="${3:-}"; MODE="${4:-}"
    [ -n "$FID" ] && [ -n "$ARG" ] || _die "usage: $0 start <FID> \"<요청 한 줄>\" [maintain]"
    case "$MODE" in ""|maintain) ;; *) _die "넷째 인자는 maintain(유지보수) 뿐이다" ;; esac
    _fid_ok "$FID"
    case "$ARG" in *$'\n'*) _die "요청은 한 줄이어야 한다" ;; esac
    # 관할은 여는 쪽(/init-project · /start)만 연다 — 여기서 .specops 를 만들면 specops 를 쓰지 않는 저장소가 편입된다.
    [ -d "$SPECOPS" ] || _die "이 저장소에는 $SPECOPS 가 없다 — specops 관할이 아니다(/init-project 또는 /start 로 시작한다)"
    [ ! -L "$SPECOPS" ] && [ ! -L "$SPECOPS/$FID" ] || _die "symlink 거부"
    [ ! -f "$SPECOPS/$FID/tasks.md" ] || _die "$FID 에는 이미 태스크 문서가 있다 — 다른 경로의 FID 는 다루지 않는다"
    lo=$(_lane "$ARG" "" ""); rc=$?
    printf '%s\n' "$lo"
    [ "$rc" = 0 ] || { _full_msg ""; exit 3; }
    soft=$(printf '%s\n' "$lo" | sed -n 's/^SIGNALS: //p')
    mkdir -p "$SPECOPS/$FID" || _die "FID 폴더를 만들 수 없다"
    cur=$(git symbolic-ref --short HEAD 2>/dev/null || true)
    case "$cur" in
      main|master) bash "$BP_ROOT/scripts/git-branch-create.sh" "$FID" || _die "브랜치를 만들 수 없다" ;;
    esac
    if [ ! -f "$SPECOPS/$FID/spec.md" ]; then
      sed "s|{{FID}}|$FID|g" "$BP_ROOT/templates/spec-basic.md" > "$SPECOPS/$FID/spec.md" || _die "spec 골격을 쓸 수 없다"
      if [ "$MODE" = maintain ]; then
        # 유지보수 — 분석 단계(analyzing-ko) 대신 spec 1장이 현재 동작과 "기존 동작 유지" 수용 기준(AC-R-1)을 받는다. approve 가 둘을 검사한다.
        awk '
          /^\*\*§기본\*\*/ { print; print "**§유형**: 유지보수"; next }
          /^### 범위 밖/ { print "### 현재 동작과 영향\n\n<!-- 고치는 파일·함수 · 그것을 부르는 곳 · 지금 통과하는 관련 테스트 · 깨질 수 있는 기존 동작. 코드를 읽고 3~6줄로 적는다. -->\n" }
          /^## 4\. / { print "### AC-R-1: {{유지할 기존 동작}}\n\n**우선순위**: must\n**Given** {{기존 전제}}\n**When** {{지금까지의 사용 방식}}\n**Then** {{지금과 같은 결과}}\n**검증 방법**: {{기존 테스트 명령}}\n" }
          { print }
        ' "$SPECOPS/$FID/spec.md" > "$SPECOPS/$FID/spec.md.tmp" && mv "$SPECOPS/$FID/spec.md.tmp" "$SPECOPS/$FID/spec.md" || _die "유지보수 골격을 쓸 수 없다"
      fi
    fi
    # 데이터 보존 수용 기준 — DB 스키마 신호가 걸리면 골격에 AC-R-2 를 넣는다(풀 경로가 스키마 변경에 요구하던 기준 — approve 가 검사한다).
    case " $soft " in *" db_schema "*|*" db_migration "*)
      if ! grep -q '^### AC-R-2' "$SPECOPS/$FID/spec.md"; then
        awk '/^## 4\. / { print "### AC-R-2: 데이터 보존 — {{지켜야 할 기존 데이터}}\n\n**우선순위**: must\n**Given** {{변경 전 데이터 상태(행 수·대표 값) — 기존 데이터가 없으면 그 근거}}\n**When** {{스키마 변경을 적용한다}}\n**Then** {{기존 데이터가 그대로 읽히고, 되돌리는 방법이 있다}}\n**검증 방법**: {{적용 전후 대조 명령 또는 테스트}}\n" } { print }' \
          "$SPECOPS/$FID/spec.md" > "$SPECOPS/$FID/spec.md.tmp" && mv "$SPECOPS/$FID/spec.md.tmp" "$SPECOPS/$FID/spec.md" || _die "AC-R-2 골격을 쓸 수 없다"
      fi ;;
    esac
    # 분석 문서 — 위험 신호가 걸린 유지보수만. spec 의 "현재 동작과 영향" 절(신호 없는 유지보수는 그 절로 충분하다)보다 먼저, 따로 쓴다.
    if [ "$MODE" = maintain ] && [ -n "$soft" ] && [ ! -f "$SPECOPS/$FID/analysis.md" ]; then
      {
        printf '# %s — 분석 (유지보수)\n\n' "$FID"
        printf '> 위험 신호(%s)가 걸린 유지보수라 spec 보다 먼저 쓴다. 코드를 읽고 사실만 적는다 — 추측은 "확인 못 함" 으로.\n\n' "$(_sig_ko "$soft")"
        printf '## 1. 현재 동작\n\n{{고치는 파일·함수가 지금 하는 일 — 파일:줄과 함께}}\n\n'
        printf '## 2. 영향 범위\n\n{{그것을 부르는 곳 · 같은 데이터·계약을 쓰는 곳 · 지금 통과하는 관련 테스트}}\n\n'
        printf '## 3. 깨질 수 있는 기존 동작\n\n{{이 변경으로 달라질 수 있는 기존 동작과, 그것을 지키는 방법(되돌리는 방법 포함)}}\n'
      } > "$SPECOPS/$FID/analysis.md" || _die "분석 문서 골격을 쓸 수 없다"
    fi
    bash "$APPEND" "$FID" /basic 시작 "$ARG" "$ARG" >/dev/null || _die "진행 기록을 남길 수 없다"
    if [ -f "$SPECOPS/$FID/analysis.md" ]; then
      echo "ANALYSIS: doc $SPECOPS/$FID/analysis.md — spec 보다 먼저 채운다(승인은 spec 과 함께 받는다)"
    elif [ "$MODE" = maintain ]; then echo "ANALYSIS: section — spec 의 '현재 동작과 영향' 절로 쓴다"
    else echo "ANALYSIS: none"; fi
    echo "BASIC: STARTED $FID — $SPECOPS/$FID/spec.md 를 채우고 승인받는다"
    ;;

  approve)
    FID="${2:-}"; [ -n "$FID" ] || _die "usage: $0 approve <FID>"; _fid_ok "$FID"
    SPEC="$SPECOPS/$FID/spec.md"
    [ -f "$SPEC" ] || _die "spec.md 가 없다 — 먼저 start 를 실행한다"
    for sec in '목표' '범위' '수용 기준'; do
      grep -qE "^## .*${sec}" "$SPEC" || _die "spec.md 에 '## … ${sec}' 절이 없다"
    done
    grep -q '{{' "$SPEC" && _die "spec.md 에 채우지 않은 자리표시({{…}})가 남아 있다"
    if grep -qE '^\*\*§유형\*\*:[[:space:]]*유지보수' "$SPEC"; then
      grep -qE '^### .*현재 동작' "$SPEC" || _die "유지보수 spec 에 '### 현재 동작과 영향' 절이 없다"
      grep -qE '^### AC-R-1' "$SPEC" || _die "유지보수 spec 에 기존 동작 유지 수용 기준(### AC-R-1)이 없다"
    fi
    if [ -f "$SPECOPS/$FID/analysis.md" ]; then
      grep -q '{{' "$SPECOPS/$FID/analysis.md" && _die "analysis.md 에 채우지 않은 자리표시({{…}})가 남아 있다 — 분석을 먼저 끝낸다"
      for sec in '현재 동작' '영향 범위' '깨질 수 있는'; do
        grep -qE "^## .*${sec}" "$SPECOPS/$FID/analysis.md" || _die "analysis.md 에 '## … ${sec}' 절이 없다"
      done
    fi
    lo=$(_lane "" "$FID" ""); rc=$?
    printf '%s\n' "$lo"
    [ "$rc" = 0 ] || { _full_msg "$FID"; exit 3; }
    soft=$(printf '%s\n' "$lo" | sed -n 's/^SIGNALS: //p')
    # DB 스키마를 바꾸는 작업은 데이터 보존 수용 기준(AC-R-2)이 있어야 한다 — 풀 경로의 check-regression-ac 가 스키마 변경에
    #   요구하던 것이다(통합 절차로 스키마 변경이 이 경로에 남으면서 빠졌다 — 20261114 점검).
    case " $soft " in *" db_schema "*|*" db_migration "*)
      grep -qE '^### AC-R-2' "$SPEC" || _die "DB 스키마 신호가 있는데 데이터 보존 수용 기준(### AC-R-2)이 없다 — spec 의 수용 기준 절에 '### AC-R-2: 데이터 보존 — <지켜야 할 기존 데이터>' 블록(우선순위 must · Given 변경 전 데이터 상태 · When 스키마 변경 적용 · Then 기존 데이터가 그대로 읽히고 되돌리는 방법이 있다 · 검증 방법)을 더한다(기존 데이터가 없으면 Given 에 그 근거를 적는다)" ;;
    esac
    # 수용 기준 절을 acceptance-criteria.md 로 옮긴다 — 검증 러너와 스펙 리뷰어가 읽는 계약 파일이다(사용자가 보는 것은 spec 1장).
    {
      printf '# 수용 기준 — %s\n\n> `/basic` 경로: spec.md 의 수용 기준 절에서 도출했다(basic-path.sh approve). 고칠 때는 spec.md 를 고치고 approve 를 다시 실행한다.\n\n' "$FID"
      awk '/^## .*수용 기준/ { f = 1; next } f && /^## / { exit } f { print }' "$SPEC"
    } > "$SPECOPS/$FID/acceptance-criteria.md" || _die "acceptance-criteria.md 를 쓸 수 없다"
    out=$(bash "$BP_ROOT/scripts/_internal/check-ac-format.sh" "$FID" 2>&1); rc=$?
    [ "$rc" = 0 ] || { printf '%s\n' "$out" >&2; rm -f "$SPECOPS/$FID/acceptance-criteria.md"; _die "수용 기준 형식이 맞지 않다 — spec.md 의 수용 기준 절을 고친 뒤 다시 실행한다"; }
    # 유지보수면 회귀 수용 기준(AC-R-1)이 채워져 있어야 한다 — 풀 경로와 같은 검사기다.
    out=$(SPECOPS_ROOT="$SPECOPS" bash "$BP_ROOT/scripts/_internal/check-regression-ac.sh" "$FID" 2>&1); rc=$?
    [ "$rc" = 0 ] || { printf '%s\n' "$out" >&2; rm -f "$SPECOPS/$FID/acceptance-criteria.md"; _die "기존 동작 유지 수용 기준(AC-R-1)이 채워지지 않았다 — spec.md 를 고친 뒤 다시 실행한다"; }
    [ ! -f "$SPECOPS/$FID/analysis.md" ] || bash "$APPEND" "$FID" /analyze 완료 "analysis.md (/basic)" >/dev/null || _die "진행 기록을 남길 수 없다"
    bash "$APPEND" "$FID" /approve 완료 "spec 1장 승인 (/basic)" >/dev/null || _die "진행 기록을 남길 수 없다"
    # 승인에 PR 생성까지가 들어 있다(commands/basic.md 4번 문구) — PR 단계의 판정기(scripts/pr-gate.sh)가 이 줄을 읽어 다시 묻지 않는다.
    #   다시 실행해도(spec 수정 뒤 재승인) 한 줄만 둔다.
    grep -qE '\[approval\] .*PR 생성 포함' "$SPECOPS/$FID/dev-decisions.md" 2>/dev/null \
      || SPECOPS_ROOT="$SPECOPS" bash "$BP_ROOT/scripts/dev-decision.sh" add "$FID" approval "spec 1장 승인 · PR 생성 포함" "/basic 승인 1회" >/dev/null \
      || _die "승인 기록을 남길 수 없다"
    ex=$(_experts_of "$soft")
    echo "EXPERTS: ${ex:-none}"
    echo "BASIC: APPROVED $FID — 다음: basic-path.sh plan $FID <태스크 수>"
    ;;

  plan)
    # 승인 뒤·구현 전 — 켤 단계를 판정한다. 태스크 수는 주 세션이 spec 과 코드를 보고 센다(함께 변하는 파일 묶음 = 1태스크).
    #   계획: 태스크 2개 이상이거나 위험 신호가 있을 때(전문가는 계획 문서를 읽는다). 태스크 1개·신호 없음이면 건너뛴다(spec 의 수용 기준이 곧 계획이다).
    #   태스크가 상한 이상이면 rc 3 — 계획 리뷰·태스크별 구현자가 있는 풀 경로로 올린다.
    FID="${2:-}"; N="${3:-}"
    [ -n "$FID" ] || _die "usage: $0 plan <FID> <태스크 수>"; _fid_ok "$FID"
    # 0 으로 시작하는 수·네 자리 이상은 받지 않는다 — 큰 수는 `[ -ge ]` 가 오류(rc 2)를 내 상한 검사를 그냥 지나간다(코드 리뷰 실측).
    case "$N" in ''|*[!0-9]*|0*|????*) _die "태스크 수는 1~999 의 정수다: '${N}'" ;; esac
    D="$SPECOPS/$FID"
    [ -f "$D/acceptance-criteria.md" ] || _die "acceptance-criteria.md 가 없다 — start → approve 를 먼저 실행한다"
    lo=$(_lane "" "$FID" ""); rc=$?
    [ "$rc" = 0 ] || { printf '%s\n' "$lo"; _full_msg "$FID"; exit 3; }
    soft=$(printf '%s\n' "$lo" | sed -n 's/^SIGNALS: //p')
    if _unified && [ "$N" -ge "$BASIC_FULL_TASK_MIN" ]; then
      echo "PLAN: full — 태스크 ${N}개(상한 ${BASIC_FULL_TASK_MIN}개 이상)"
      echo "basic-path: 태스크가 ${N}개다 — 계획 리뷰와 태스크별 구현자가 있는 풀 경로 대상이다. basic-path.sh promote $FID \"태스크 ${N}개\" 로 풀 경로에 올린다(commands/basic.md 「풀 경로로 올리기」)." >&2
      exit 3
    fi
    ex=$(_experts_of "$soft")
    # 판정 기록 — seal 이 이 줄들로 "계획 때 없던 신호"와 "전문가 보고서 유무"를 본다(모델의 기억이 아니라 파일).
    printf 'tasks=%s\nsignals=%s\nexperts=%s\n' "$N" "$soft" "$ex" > "$D/steps.txt" || _die "판정 기록을 쓸 수 없다"
    # 다시 실행했을 때 — 손대지 않은 골격(자리표시가 남은 plan.md)은 새 수로 다시 만들고, 이미 채운 계획은 건드리지 않고 칸 수만 알린다.
    #   지우지 않고 plan.md.prev 로 옮긴다 — 절반쯤 채운 계획이나 `${{ … }}` 를 적은 계획을 잃지 않게(코드 리뷰).
    if [ -f "$D/plan.md" ] && grep -q '{{' "$D/plan.md"; then
      mv -f "$D/plan.md" "$D/plan.md.prev" || _die "이전 계획을 옮길 수 없다"
      echo "PLAN-NOTE: 자리표시가 남은 이전 plan.md 를 plan.md.prev 로 옮겼다 — 적어 둔 내용이 있으면 거기서 가져온다"
    fi
    if [ -f "$D/plan.md" ]; then
      have=$(grep -cE '^### Task ' "$D/plan.md")
      [ "$have" = "$N" ] || echo "PLAN-NOTE: plan.md 의 태스크 칸은 ${have}개인데 ${N}개로 실행했다 — 계획을 직접 고쳐 맞춘다(채운 계획은 다시 만들지 않는다)"
    fi
    if [ "$N" -ge 2 ] || [ -n "$soft" ] || [ -f "$D/plan.md" ]; then
      if [ ! -f "$D/plan.md" ]; then
        {
          printf '# %s — plan (기본 경로)\n\n' "$FID"
          printf '> **결정만 적는다** — 파일·시그니처·테스트 단언. 함수 본문은 적지 않는다(시그니처와 테스트가 정하지 못하는 알고리즘만 예외). 기준은 spec.md 이고 이 문서는 그 구현 순서다. 이 문서가 구현할 코드보다 길면 코드를 대신 쓴 것이다.\n\n'
          printf '## 1. 파일 구조\n\n{{만들거나 고치는 파일과 각 파일의 책임 — 한 줄씩}}\n\n'
          printf '## 2. 태스크 (%s개)\n\n' "$N"
          i=1
          while [ "$i" -le "$N" ]; do
            printf '### Task %s: {{이름}}\n\n- 파일: {{경로}}\n- 인터페이스: {{시그니처 · 앞 태스크에서 받는 것 / 뒤 태스크에 주는 것}}\n- 테스트: {{테스트 이름과 단언(spec 의 값 그대로) · 실행 명령}}\n- 수용 기준: {{AC-n}}\n\n' "$i"
            i=$((i+1))
          done
          if [ -n "$soft" ]; then
            printf '## 3. 위험 신호 대응 (%s)\n\n{{걸린 신호마다 — 무엇을 바꾸는가 · 기존 데이터·호출자에 주는 영향 · 되돌리는 방법}}\n' "$(_sig_ko "$soft")"
          fi
        } > "$D/plan.md" || _die "계획 골격을 쓸 수 없다"
      fi
      bash "$APPEND" "$FID" /plan 진행 "계획 ${N}태스크 · 전문가 ${ex:-없음} (/basic)" >/dev/null || _die "진행 기록을 남길 수 없다"
      echo "PLAN: yes $D/plan.md"
    else
      echo "PLAN: skip — 태스크 1개 · 위험 신호 없음(spec 의 수용 기준으로 구현한다)"
    fi
    echo "EXPERTS: ${ex:-none}"
    ;;

  review)
    # 진행 기록만 남긴다 — 관제판(hooks/progress-pane.tsx 의 BASIC_STAGES)이 이 줄로 구현·리뷰 단계를 표시한다. 판정·산출물은 없다.
    #   `/implement` 줄은 훅이 코드 변경 시각으로 읽는다(governance-lib.sh _verify_passed_in_progress) — 검증보다 앞에 남으므로 뜻이 맞다.
    FID="${2:-}"; [ -n "$FID" ] || _die "usage: $0 review <FID>"; _fid_ok "$FID"
    [ -f "$SPECOPS/$FID/acceptance-criteria.md" ] || _die "acceptance-criteria.md 가 없다 — start → approve 를 먼저 실행한다"
    [ ! -f "$SPECOPS/$FID/plan.md" ] || ! grep -q '{{' "$SPECOPS/$FID/plan.md" || _die "plan.md 에 채우지 않은 자리표시({{…}})가 남아 있다 — 계획을 끝내고 구현한 뒤 다시 실행한다"
    # 계획이 있었으면 여기서 끝났다고 남긴다 — 관제판이 계획 단계를 ✓ 로 바꾼다(없으면 그 단계는 보이지 않는다).
    [ ! -f "$SPECOPS/$FID/plan.md" ] || bash "$APPEND" "$FID" /plan 완료 "계획·전문가 반영 (/basic)" >/dev/null || _die "진행 기록을 남길 수 없다"
    bash "$APPEND" "$FID" /implement 완료 "주 세션 직접 구현 (/basic)" >/dev/null || _die "진행 기록을 남길 수 없다"
    bash "$APPEND" "$FID" /review 진행 "스펙·코드 리뷰 + 보안 스캔 (/basic)" >/dev/null || _die "진행 기록을 남길 수 없다"
    echo "BASIC: REVIEWING $FID"
    ;;

  seal)
    FID="${2:-}"; ARG="${3:-}"
    [ -n "$FID" ] && [ -n "$ARG" ] || _die "usage: $0 seal <FID> \"<test_command>\""
    _fid_ok "$FID"
    D="$SPECOPS/$FID"
    [ -f "$D/spec.md" ] && [ -f "$D/acceptance-criteria.md" ] || _die "spec.md·acceptance-criteria.md 가 없다 — start → approve 를 먼저 실행한다"
    case "$ARG" in *'"'*|*'\'*|*$'\n'*) _die "test_command 에 따옴표·역슬래시·줄바꿈을 쓸 수 없다" ;; esac
    files=$(_changed_files) || _die "변경 파일을 알 수 없다"
    [ -n "$files" ] || _die "변경된 파일이 없다"
    case "$files" in *'"'*|*'\'*) _die "따옴표·역슬래시가 든 파일 이름은 다룰 수 없다" ;; esac
    lo=$(_lane "" "$FID" "$files"); rc=$?
    printf '%s\n' "$lo"
    [ "$rc" = 0 ] || { _full_msg "$FID"; exit 3; }
    if _unified; then
      # 통합 절차의 안전망 둘 — ① 계획 때 없던 위험 신호가 바뀐 파일에서 나왔으면 그 신호의 전문가 검토 없이 구현된 것이다 → 풀 경로로.
      #   ② 켜기로 한 전문가의 보고서가 없으면 그 단계를 건너뛴 것이다 → 받지 않는다.
      [ -f "$D/steps.txt" ] || _die "판정 기록(steps.txt)이 없다 — 승인 뒤 basic-path.sh plan $FID <태스크 수> 를 실행하지 않았다"
      seen=$(sed -n 's/^signals=//p' "$D/steps.txt" | head -1)
      new=""
      for w in $(printf '%s\n' "$lo" | sed -n 's/^SIGNALS: //p'); do
        case " $seen " in *" $w "*) ;; *) new="${new:+$new }$w" ;; esac
      done
      if [ -n "$new" ]; then
        echo "basic-path: 계획 때 없던 위험 신호가 바뀐 파일에서 나왔다($(_sig_ko "$new")) — 그 검토 없이 구현됐다. basic-path.sh promote $FID \"<사유>\" 로 풀 경로에 올린다." >&2
        exit 3
      fi
      # 켤 전문가는 기록(steps.txt)이 아니라 **지금 spec 의 신호에서 다시 구한다** — 기록을 고치거나 비워도 빠지지 않는다.
      for a in $(_experts_of "$(printf '%s\n' "$lo" | sed -n 's/^SIGNALS: //p')") $(sed -n 's/^experts=//p' "$D/steps.txt" | head -1); do
        case "$a" in
          devfsd:db-designer-ko) r=db ;; devfsd:api-designer-ko) r=api ;; devfsd:arch-designer-ko) r=arch ;; devfsd:security-designer-ko) r=security ;; *) r="" ;;
        esac
        [ -n "$r" ] || continue
        [ -s "$D/experts/$r.md" ] || _die "전문가 보고서가 없다: experts/$r.md — $a 를 호출해 계획을 검토받은 뒤 다시 실행한다(commands/basic.md 4-1번)"
        grep -qE '^## .*반영' "$D/experts/$r.md" || _die "experts/$r.md 에 '## 반영' 절이 없다 — 지적마다 반영·기각을 1줄씩 적은 뒤 다시 실행한다"
      done
      # 채우지 않은 계획으로는 봉인하지 않는다 — review 를 건너뛰면 그 검사를 지나칠 수 있었다(20261114 주행 실측).
      [ ! -f "$D/plan.md" ] || ! grep -q '{{' "$D/plan.md" || _die "plan.md 에 채우지 않은 자리표시({{…}})가 남아 있다 — 계획을 끝낸 뒤 다시 실행한다"
      # 계획의 태스크 칸 수가 상한 이상이면 풀 경로다 — plan 에 작은 수를 주고 계획에 태스크를 더 적는 길을 막는다.
      if [ -f "$D/plan.md" ]; then
        tn=$(grep -cE '^### Task ' "$D/plan.md")
        if [ "${tn:-0}" -ge "$BASIC_FULL_TASK_MIN" ]; then
          echo "basic-path: plan.md 의 태스크가 ${tn}개다(상한 ${BASIC_FULL_TASK_MIN}개 이상) — basic-path.sh promote $FID \"태스크 ${tn}개\" 로 풀 경로에 올린다." >&2
          exit 3
        fi
      fi
    fi
    # 관련 스위트 명령으로 봉인하면 **지금 변경 파일**이 닿는 스위트를 빠짐없이 담아야 한다 — related 뒤에 코드를 더 고쳤거나
    #   스위트를 손으로 뺀 명령은 받지 않는다(고를 수 없는 변경이면 전체 테스트 명령으로 봉인한다).
    case "$ARG" in
      "bash $BP_RELATED "*)
        need=$(_related_suites) || _die "관련 스위트를 고를 수 없는 변경이다($need) — 프로젝트의 테스트 명령 전체로 봉인한다"
        for s in $need; do
          case " ${ARG#"bash $BP_RELATED "} " in *" $s "*) ;; *) _die "test_command 에 관련 스위트가 빠졌다: $s — basic-path.sh related 를 다시 실행한다" ;; esac
        done ;;
      *run-related.sh*) _die "관련 스위트 명령은 'bash $BP_RELATED <스위트…>' 형태만 받는다(basic-path.sh related 의 답 그대로)" ;;
    esac
    # 검증 러너가 받지 않는 명령으로 봉인하면 검증에서야 `VERIFY: PARTIAL — whitelist 미통과` 로 걸린다(20261112 실측: related 의 `none — …` 안내문).
    _runner_accepts "$ARG"; rc=$?
    [ "$rc" != 2 ] || _die "검증 러너의 허용 형식을 읽을 수 없다(run-verification.sh)"
    [ "$rc" = 0 ] || _die "test_command 를 검증 러너가 받지 않는다: '$ARG' — 실행할 테스트 명령을 준다(bash scripts|tests/….sh · pytest · npm|pnpm|yarn test · go test · cargo test · npx <bin>). related 가 none 이면 프로젝트의 테스트 명령 전체를 쓴다."
    [ -f "$D/reviews/T1-B-report.md" ] && [ -f "$D/reviews/T1-C-report.md" ] \
      || { echo "basic-path: 리뷰 보고서가 없다 — spec-reviewer-ko·code-reviewer-ko 를 tid=T1 로 호출한 뒤 다시 실행한다" >&2; exit 4; }
    acs=$(grep -oE '^#{2,3} AC-[A-Za-z0-9-]+' "$D/acceptance-criteria.md" | sed -E 's/^#+ //' | sort -u | paste -sd, - | sed 's/,/, /g')
    {
      printf '# tasks — %s (/basic)\n\n' "$FID"
      printf '> `/basic` 경로가 만든 1-태스크 문서다. 주 세션이 직접 구현했다 — plan·분해·구현자 dispatch 가 없다.\n\n'
      printf '### Task 1: 구현 (주 세션)\n\n## 의존 그래프\n\n```yaml\nreview_mode: end-loaded\ntasks:\n  - id: T1\n    depends_on: []\n    inputs: []\n    outputs:\n'
      printf '%s\n' "$files" | while IFS= read -r f; do [ -n "$f" ] && printf '      - "%s"\n' "$f"; done
      printf '    ac: [%s]\n    test_command: "%s"\n```\n' "$acs" "$ARG"
    } > "$D/tasks.md" || _die "태스크 문서를 쓸 수 없다"
    # 리뷰 감사 행 — check-review-audit.sh 가 reviews 파일마다 dispatch-log 행을 요구한다(병렬 쌍의 사후 대조 포함).
    LOG="$D/dispatch-log.md"
    [ -f "$LOG" ] || printf '# dispatch-log — %s (/basic)\n\n| # | 시각 | Phase | agent | 결과 | 비고 |\n|---|---|---|---|---|---|\n' "$FID" > "$LOG"
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if ! grep -q 'BC-PAR-CHECK:T1' "$LOG"; then
      if [ -f "$D/reviews/T1-B-feedback.md" ]; then par="C 폐기(B FAIL) — 지적은 주 세션이 고쳤다"; else par="B PASS"; fi
      {
        printf '| - | %s | B:T1 | spec-reviewer-ko | 기록 | reviews/T1-B-report.md |\n' "$ts"
        printf '| - | %s | C:T1 | code-reviewer-ko | 기록 | reviews/T1-C-report.md |\n' "$ts"
        printf '| - | %s | BC-PAR-CHECK:T1 | - | %s | reviews/T1-B-report.md · reviews/T1-C-report.md |\n' "$ts" "$par"
        for fb in T1-B-feedback.md T1-C-feedback.md; do
          [ -f "$D/reviews/$fb" ] && printf '| - | %s | REVIEW-FIX:T1 | 주 세션 | FIXED | reviews/%s |\n' "$ts" "$fb"
        done
      } >> "$LOG"
    fi
    bash "$APPEND" "$FID" /review 완료 "리뷰 반영·봉인 (/basic)" >/dev/null || _die "진행 기록을 남길 수 없다"
    echo "BASIC: SEALED $FID — 이제 run-verification.sh $FID 를 실행한다(봉인 뒤 코드를 고치면 다시 seal)"
    ;;

  promote)
    # 기본 경로 → 풀 경로. 만든 것을 버리지 않는다: spec 1장·리뷰 보고서·1-태스크 문서를 basic-draft/ 로 보존하고(풀 경로의
    #   리뷰 감사·분해가 기본 경로 산출물을 자기 것으로 읽지 않게 자리에서 뺀다), 코드 변경은 작업 트리에 그대로 둔다.
    #   이어 가는 절차는 skills/specifying-ko/basic-promote.md — 여기서는 기계 절차와 안내만 한다.
    FID="${2:-}"; ARG="${3:-}"
    [ -n "$FID" ] && [ -n "$ARG" ] || _die "usage: $0 promote <FID> \"<사유>\""
    _fid_ok "$FID"
    case "$ARG" in *$'\n'*) _die "사유는 한 줄이어야 한다" ;; esac
    D="$SPECOPS/$FID"; DR="$D/basic-draft"
    [ ! -L "$SPECOPS" ] && [ ! -L "$D" ] && [ ! -L "$DR" ] || _die "symlink 거부"
    [ -f "$D/spec.md" ] || _die "spec.md 가 없다 — 올릴 것이 없다(풀 경로로 바로 진입한다)"
    if [ ! -f "$DR/promoted.md" ]; then
      grep -q '^\*\*§기본\*\*' "$D/spec.md" || _die "$FID 는 기본 경로의 FID 가 아니다"
      [ ! -f "$D/tasks.md" ] || grep -q '(/basic)' "$D/tasks.md" || _die "$FID 의 태스크 문서는 기본 경로 것이 아니다 — 다루지 않는다"
      files=$(_changed_files) || files=""
      stage=spec; [ -z "$files" ] || stage=code
      kind=new; ! grep -qE '^\*\*§유형\*\*:[[:space:]]*유지보수' "$D/spec.md" || kind=maintain
      sig=$(_lane "" "$FID" "$files" | head -1); sig="${sig#LANE: }"
      mkdir -p "$DR" || _die "보존 폴더를 만들 수 없다"
      cp "$D/spec.md" "$DR/spec.md" || _die "spec 을 보존할 수 없다"
      [ ! -f "$D/acceptance-criteria.md" ] || cp "$D/acceptance-criteria.md" "$DR/acceptance-criteria.md"
      for f in tasks.md dispatch-log.md reviews plan.md steps.txt experts analysis.md; do
        [ ! -e "$D/$f" ] || mv "$D/$f" "$DR/$f" || _die "$f 를 보존 폴더로 옮길 수 없다"
      done
      {
        printf '# 기본 경로 → 풀 경로 승격 — %s\n\n' "$FID"
        printf -- '- 사유: %s\n- 판정: %s\n- 단계: %s\n- 종류: %s\n- 시각: %s\n\n' "$ARG" "$sig" "$stage" "$kind" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '## 이미 쓴 코드 (작업 트리 — 커밋하지 않았다)\n\n'
        if [ -n "$files" ]; then printf '%s\n' "$files" | sed 's/^/- /'; else printf '없음\n'; fi
      } > "$DR/promoted.md" || _die "승격 기록을 쓸 수 없다"
      # 진행 기록의 `/full 승격` 줄 — 관제판이 이 FID 를 풀 경로 단계로 바꿔 표시한다(hooks/progress-pane.tsx).
      bash "$APPEND" "$FID" /full 승격 "$ARG — 기본 경로에서 올림" >/dev/null || _die "진행 기록을 남길 수 없다"
    fi
    stage=$(sed -n 's/^- 단계: //p' "$DR/promoted.md" | head -1); kind=$(sed -n 's/^- 종류: //p' "$DR/promoted.md" | head -1)
    echo "BASIC: PROMOTED $FID stage=$stage kind=$kind"
    echo "NOTICE: $(sed -n 's/^- 사유: //p' "$DR/promoted.md" | head -1) — 풀 경로로 올림."
    if [ "$kind" = maintain ]; then echo "NEXT: devfsd:analyzing-ko"; echo "ARGS: <!-- entry: maintain -->"; else echo "NEXT: devfsd:specifying-ko"; fi
    echo "ARGS: <!-- promoted-from-basic: $FID -->"
    [ "$stage" != code ] || echo "ARGS: <!-- split: false -->"
    echo "ARGS: <원래 요청 한 줄>"
    echo "PROCEDURE: $BP_ROOT/skills/specifying-ko/basic-promote.md"
    ;;

  done)
    FID="${2:-}"; ARG="${3:-}"
    [ -n "$FID" ] && [ -n "$ARG" ] || _die "usage: $0 done <FID> \"<한 줄 요약>\""
    _fid_ok "$FID"
    [ -d "$SPECOPS/$FID" ] || _die "$FID 폴더가 없다"
    bash "$APPEND" "$FID" /lifecycle DONE "/basic — $ARG" >/dev/null || _die "진행 기록을 남길 수 없다"
    echo "BASIC: DONE $FID"
    ;;

  *) _die "usage: $0 {route <start|maintain> \"<인자>\" | promote <FID> \"<사유>\" | related | lane \"<요청>\" [<FID>] | start <FID> \"<요청>\" | approve <FID> | plan <FID> <태스크 수> | review <FID> | seal <FID> \"<test_command>\" | design-scope <화면 수> [new|flow] | done <FID> \"<요약>\"}" ;;
esac
