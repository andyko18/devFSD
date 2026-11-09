#!/usr/bin/env bash
# test-demo-stage.sh — demo-ko 단계(20261105-demo-stage) 본문 계약 잠금
#   AC-1 demo-ko 본문(frontmatter·4단계·모드 분기·BATCH-DEMO-SKIP·evidence 양식) · AC-2 performance-test-ko 호출-복귀 ·
#   AC-3 확인 필수 규칙(fail-safe) · AC-4 기록·PR 본문 `## 데모`.  AC-5(구조·문서 수치)는 validate-structure·check-doc-numbers 가 잠근다.
#   잠금 방식: 절 범위(_sec)로 자르고 → 고정 문자열·줄 순서·개수·부재를 단언한다. 문구 하나만 사라져도 떨어지는지는
#   C 절(양성 대조)이 매번 증명한다 — 본문 사본에 변이를 넣고 같은 검사 함수를 돌려 기대한 ID 가 FAIL 하는지 본다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
export LC_ALL=C   # macOS grep -xF 가 UTF-8 로캘에서 한글 줄을 다르게 맞춘다(CI macOS 실측 C7.e) — 바이트 비교로 고정
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 1
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
DEMO="$PLUGIN/skills/demo-ko/SKILL.md"
PERF="$PLUGIN/skills/performance-test-ko/SKILL.md"
CHAIN="$PLUGIN/hooks/chain.yaml"
_T=$(mktemp -d) || exit 1
trap 'rm -rf "$_T"' EXIT

# ── 헬퍼 ───────────────────────────────────────────────────────────────
# $1=파일 $2=시작 줄 정규식(awk ERE) $3=끝 줄 정규식 — 시작 줄 다음부터 끝 줄 앞까지(끝이 없으면 파일 끝). 정규식은 ENVIRON 으로 넘긴다
_sec() { _S="$2" _E="$3" awk 'f&&$0~ENVIRON["_E"]{exit} f{print} $0~ENVIRON["_S"]{f=1}' "$1" 2>/dev/null; }
# frontmatter — 첫 줄 `---` 와 닫는 `---` 가 둘 다 있을 때만 그 사이를 낸다(닫힘 없으면 빈 출력 → 검사 FAIL)
_fm() { awk 'NR==1{if($0!="---")exit;f=1;next} f&&$0=="---"{c=1;exit} f{b=b $0 "\n"} END{if(c)printf "%s",b}' "$1" 2>/dev/null; }
_ln()  { printf '%s\n' "$1" | grep -nF  -- "$2" | head -1 | cut -d: -f1; }   # 고정 문자열이 든 첫 줄 번호
_lnx() { printf '%s\n' "$1" | grep -nxF -- "$2" | head -1 | cut -d: -f1; }   # 줄 전체가 같은 첫 줄 번호 (`### 데모` 가 `## 데모` 에 걸리는 부분 문자열 함정 방지)
_cnt() { printf '%s\n' "$1" | grep -cF  -- "$2"; }
_cntx() { printf '%s\n' "$1" | grep -cxF -- "$2"; }
# $1=본문 $2…=없는 고정 문자열 / 있는 고정 문자열을 [..] 로 이어서 출력
_miss()    { local b=$1 n m=""; shift; for n in "$@"; do printf '%s\n' "$b" | grep -qF -- "$n" || m="$m [$n]"; done; printf '%s' "$m"; }
_present() { local b=$1 n m=""; shift; for n in "$@"; do printf '%s\n' "$b" | grep -qF -- "$n" && m="$m [$n]"; done; printf '%s' "$m"; }
_missre()  { local b=$1 n m=""; shift; for n in "$@"; do printf '%s\n' "$b" | grep -qE -- "$n" || m="$m [$n]"; done; printf '%s' "$m"; }
# 모두 들어 있어야 한다 — 본문이 비어 있으면(대상 절을 못 찾음) 통과가 아니라 실패
_has() { local id=$1 b=$2 m; shift 2
  [ -n "$b" ] || { nope "$id" "대상 절이 비어 있다(검사 대상 0개)"; return 0; }
  m=$(_miss "$b" "$@"); [ -z "$m" ] && ok "$id" || nope "$id" "없음:$m"; }
_hasre() { local id=$1 b=$2 m; shift 2
  [ -n "$b" ] || { nope "$id" "대상 절이 비어 있다(검사 대상 0개)"; return 0; }
  m=$(_missre "$b" "$@"); [ -z "$m" ] && ok "$id" || nope "$id" "없음:$m"; }
# 하나도 들어 있으면 안 된다 — 빈 본문에서의 부재 단언은 늘 통과하므로 비어 있으면 실패
_lacks() { local id=$1 b=$2 p; shift 2
  [ -n "$b" ] || { nope "$id" "대상이 비어 있다(부재 단언이 공허)"; return 0; }
  p=$(_present "$b" "$@"); [ -z "$p" ] && ok "$id" || nope "$id" "있으면 안 됨:$p"; }
_eq() { [ "$2" = "$3" ] && ok "$1" || nope "$1" "got=[$2] want=[$3]"; }
# 줄 순서 — $3=f(포함)|x(줄 전체 일치). 모두 있고 번호가 strictly 증가해야 한다
_ord() { local id=$1 b=$2 mode=$3 prev=0 n l; shift 3
  [ -n "$b" ] || { nope "$id" "대상 절이 비어 있다(검사 대상 0개)"; return 0; }
  for n in "$@"; do
    if [ "$mode" = x ]; then l=$(_lnx "$b" "$n"); else l=$(_ln "$b" "$n"); fi
    [ -n "$l" ] || { nope "$id" "없음: [$n]"; return 0; }
    [ "$l" -gt "$prev" ] || { nope "$id" "순서 위반: [$n] L$l ≤ L$prev"; return 0; }
    prev=$l
  done; ok "$id"; }
# 변이 — $1=원본 $2=바꿀 고정 문자열(없으면 rc 3) $3=대체문 $4=L 이면 `$2` 와 줄 전체가 같은 첫 줄을 $3 로 교체. 첫 일치 1곳만 바꾼다
_mut() { _N="$2" _R="${3-}" _M="${4-}" awk 'BEGIN{n=ENVIRON["_N"];r=ENVIRON["_R"];m=ENVIRON["_M"];L=length(n)}
  { if(!d){ if(m=="L"){ if($0==n){$0=r;d=1} } else { i=index($0,n); if(i>0){ $0=substr($0,1,i-1) r substr($0,i+L); d=1 } } } print }
  END{ if(!d) exit 3 }' "$1"; }

# ── 모드 분기 픽스처 — 본문의 bash 조각(`<FID>` 자리만 실제 이름으로 바꾼다 — `<`·`>` 는 셸 리다이렉션이다)을 픽스처 디렉터리에서 실제로 실행한다 ──
_FX="$_T/fx"
_mkfx() { mkdir -p "$_FX/$1/.specops/20261105-fx" && printf '%s\n' "${@:2}" > "$_FX/$1/.specops/20261105-fx/spec.md"; }
_mkfx batch    '# 명세' '**§batch**: batch-1' '**§유형**: 신규'
_mkfx auto     '# 명세' '**§auto**: true' '**§유형**: 신규'
_mkfx both     '# 명세' '**§batch**: batch-1' '**§auto**: true'
_mkfx lite     '# 명세' '**§lite**: true' '**§일괄**: true'
_mkfx autofalse '# 명세' '**§auto**: false'
_mkfx prose    '# 명세' '- 라벨 예시: **§auto**: true 와 **§batch**: x 를 본문에서 설명만 한다'
_mkfx plain    '# 명세' '**§유형**: 신규'
_modes() { local id=$1 blk=$2 c exp out bad=""
  [ -n "$blk" ] || { nope "$id" "모드 분기 bash 조각이 없다(검사 대상 0개)"; return 0; }
  for c in batch:BATCH auto:AUTO both:BATCH lite:SINGLE autofalse:SINGLE prose:SINGLE plain:SINGLE; do
    exp=${c#*:}; out=$(cd "$_FX/${c%%:*}" && bash -c "${blk//<FID>/20261105-fx}" 2>/dev/null)
    [ "$out" = "$exp" ] || bad="$bad ${c%%:*}→[$out](기대 $exp)"
  done
  [ -z "$bad" ] && ok "$id" || nope "$id" "$bad"; }
_pats() { grep -oE "grep -qE '[^']+' \.specops/<FID>/spec\.md" | grep -E '§batch|§auto' | sort; }

# ═══ demo-ko 본문 (AC-1·3·4) ═══════════════════════════════════════════════
_demo_checks() { local f=$1 perf=$2 fm all m bb ba bs blk s k t line lb
  # D0 — 대상 0개는 통과가 아니라 실패
  if [ ! -s "$f" ]; then nope "D0.a skills/demo-ko/SKILL.md 실재·비어 있지 않음 — 검사 대상 0개는 통과가 아니다 (AC-1)" "$f"; return 0; fi
  ok "D0.a skills/demo-ko/SKILL.md 실재 (AC-1)"
  all=$(cat "$f")
  _eq "D0.b 본문 길이 ≤ 200줄 (NFR-2)" "$([ "$(wc -l < "$f" | tr -d ' ')" -le 200 ] && echo ok || echo over)" ok
  # D1 — frontmatter (AC-1)
  fm=$(_fm "$f")
  _hasre "D1.a frontmatter 필수 필드 6종 (AC-1)" "$fm" '^name: .+' '^description: .+' '^layer: .+' '^reference_upstream: .+' '^specops_version: .+' '^used_by: .+'
  _hasre "D1.b frontmatter 값 — name=demo-ko·layer 2·discipline·버전 형식·호출자 (AC-1)" "$fm" '^name: demo-ko$' '^layer: 2$' '^discipline: true$' '^specops_version: [0-9]+\.[0-9]+\.[0-9]+$' '^used_by: .*performance-test-ko'
  # D1 — 4단계 헤딩 (AC-1)
  _ord "D1.c 4단계 헤딩이 순서대로 (AC-1)" "$all" x '## 1단계: 종류 판정' '## 2단계: 실제로 실행해 보여 주기' '## 3단계: 확인 필요 판정' '## 4단계: 기록'
  _eq "D1.d '단계' 헤딩 정확히 4개 (AC-1)" "$(printf '%s\n' "$all" | grep -cE '^## [0-9]+단계')" 4
  _has "D1.l 호출-복귀 문단 — 호출자·복귀 지점·primary edge 아님 (AC-1·AC-2)" "$(_sec "$f" '^# Engine 스킬' '^## 모드 분기')" \
    '`## PR 생성 게이트` 가 이 skill 을 부르고' '그 게이트의 나머지' '로 돌아간다' 'chain primary edge 는 아니다'
  # D1 — 모드 분기 (AC-1)
  m=$(_sec "$f" '^## 모드 분기' '^## 1단계')
  bb=$(printf '%s\n' "$m" | grep -F -- '- **BATCH**'); ba=$(printf '%s\n' "$m" | grep -F -- '- **AUTO**'); bs=$(printf '%s\n' "$m" | grep -F -- '- **SINGLE**')
  _eq "D1.e 모드 갈래 bullet 이 BATCH·AUTO·SINGLE 각 1줄 (AC-1)" "$(printf '%s\n' "$bb" | grep -c .)$(printf '%s\n' "$ba" | grep -c .)$(printf '%s\n' "$bs" | grep -c .)" 111
  _has "D1.f BATCH — 마커 BATCH-DEMO-SKIP: <FID>·근거·즉시 복귀·evidence SKIP 기록 (AC-1)" "$bb" \
    'BATCH-DEMO-SKIP: <FID>' 'batch 오케스트레이터가 PR 을 소유' '즉시 복귀' '`## /demo` 절을 `결과: SKIP — batch`'
  _has "D1.g AUTO — 1~2단계 수행·확인 대기 안 함·가정 다이제스트로 이관 (AC-1)" "$ba" \
    '1~2단계는 수행' '확인 대기는 하지 않는다' 'PR 게이트의 가정 다이제스트' '`데모: 사용자 확인 대기`'
  _has "D1.h SINGLE — §lite 포함·생략 금지·1~4단계 전부 (AC-1)" "$bs" '`§lite` 포함' '생략하지 않는다' '1~4단계 전부'
  _lacks "D1.i 마커 BATCH-DEMO-SKIP 은 BATCH 갈래에만 (AC-1)" "$ba"$'\n'"$bs" 'BATCH-DEMO-SKIP'
  blk=$(printf '%s\n' "$m" | awk '/^```bash/{f=1;next} /^```/{if(f)exit} f')
  _modes "D1.j 모드 분기 조각을 픽스처 spec.md 7종에 실제 실행 — batch>auto 우선·라벨은 줄 머리만·false/lite/일괄은 SINGLE (AC-1)" "$blk"
  s=$(printf '%s\n' "$blk" | _pats)
  t=$(_sec "$perf" '^## PR 생성 게이트' '^## 5원칙' | _pats)
  { [ "$(printf '%s\n' "$s" | grep -c .)" = 2 ] && [ "$s" = "$t" ]; } && ok "D1.k 모드 판정 정규식이 performance-test-ko 3-way 분기와 글자 그대로 같다 (AC-1·AC-2)" || nope "D1.k" "demo=[$s] perf=[$t]"
  # D2 — 1단계 종류 판정 (AC-1)
  s=$(_sec "$f" '^## 1단계' '^## 2단계')
  _has "D2.a 1단계 — 기준 브랜치 대비 변경 파일 목록 (AC-1)" "$s" 'git diff "origin/$BASE"...HEAD --name-only' 'refs/remotes/origin/HEAD' 'BASE=${BASE:-main}'
  _has "D2.b 1단계 — 종류 5갈래 표와 신호 (AC-1)" "$s" '| 화면 |' '| iOS 앱 |' '| 진행 패널(mod) |' '| 명령·스크립트 출력 |' '| 내부 |' \
    '`screens/`' '`*.tsx`' '`*.swift`' '최상위 `scripts/*.sh`' '`commands/`' '`tests/`' '`scripts/_internal/`' '내부 라이브러리로 확인된 파일 **만**'
    _has "D2.c 1단계 — skills/ 문구 변경이 '내부' 가 아니라 명령·스크립트 출력 행으로 분류된다 (AC-3)" "$(printf '%s\n' "$s" | grep -F -- '| 명령·스크립트 출력 |')" '`skills/`'
  _has "D2.d 1단계 — '미분류' 행(소스 파일 예시)·3단계에서 확인 필수(fail-safe) (AC-3)" "$(printf '%s\n' "$s" | grep -F -- '| 미분류 |')" '`*.py`' '`*.go`' '`*.rs`' '`*.svelte`' '`*.scss`' 'API 서버 코드'
  _has "D2.d2 3단계 — 미분류 포함이 확인 필수 판정에 들어간다 (AC-3)" "$(_sec "$f" '^## 3단계' '^##+ 합리화')" '**미분류 포함**' '미분류는' '확인 필수로 다룬다(fail-safe)'
  _has "D2.e 1단계 — diff 실패(rc≠0)·빈 출력은 미분류·확인 필수, 내부로 읽지 않음 (AC-3)" "$s" 'rc≠0' '출력이 비어 있으면' '`미분류` 로 보고 확인 필수' '빈 출력을 `내부` 로 읽지 않는다' '사용자에게 변경 범위를 확인해 달라고 요청'
# D3 — 2단계 실행해 보여 주기 (AC-1)
  s=$(_sec "$f" '^## 2단계' '^## 3단계')
  _has "D3.a 2단계 — 테스트 요약은 데모가 아님·종류별 실행 수단·직접 확인 방법 (AC-1)" "$s" \
    '**테스트 통과 요약은 데모가 아니다.**' '`mcp__Claude_Browser__*`' '`mcp__Claude_Code_iOS_Simulator__control`' '대표 입력으로 **실제 실행한** 출력' \
    '**보여 줄 방법이 없을 때**' '**사용자가 직접 확인하는 방법**' '"확인함"이라 쓰지 않는다'
  _has "D3.b 2단계 — 내부 종류만 테스트 요약 허용 (AC-1)" "$(printf '%s\n' "$s" | grep -F -- '- **내부**')" '이 종류만 테스트 요약이 허용된다'
  _lacks "D3.c 2단계 — 화면·iOS·패널·명령 bullet 은 테스트 요약을 허용하지 않는다 (AC-1)" \
    "$(printf '%s\n' "$s" | grep -E '^- \*\*(화면|iOS 앱|진행 패널\(mod\)|명령·스크립트)\*\*')" '허용' '요약'
  # D4 — 3단계 확인 필요 판정 / fail-safe (AC-3)
  s=$(_sec "$f" '^## 3단계' '^##+ 합리화')
  line=$(printf '%s\n' "$s" | grep -F -- '화면·UI 소스' | head -1)
  _has "D4.a 확인 필수 조건 — 애매하면 필수(fail-safe)·가시 변경 6범주 (AC-3)" "$s" \
    '**판단이 애매하면** 확인이 **필수**다(fail-safe)' '화면·UI 소스' 'iOS 앱' '진행 패널' '최상위 `scripts/*.sh` 의 출력' '`commands/`·`skills/` 의 사용자 문구' '훅 메시지'
  _has "D4.b 3단계는 멈추지 않는다 — 확인은 PR 질문에서 함께 (20261109 사용자 결정)" "$s" '**멈추지 않는다**' 'PR 생성 질문에서 한 번에'
  _lacks "D4.c 확인 필수 열거에 테스트·문서·내부 라이브러리가 섞이지 않는다 (AC-3)" "$line" '테스트' '문서' '_internal' '내부'
  lb=$(printf '%s\n' "$s" | grep -F -- '다르다고 하면')
  _has "D4.d PR 질문에서 다르다면 → 수정 후 2단계부터 재시연 (AC-3)" "$lb" 'systematic-debugging-ko' '**2단계부터 다시**'
  _lacks "D4.e 3단계에 확인 대기 질문·기다림이 없다 (20261109)" "$s" '"위 결과가 의도한 모습입니까?' '응답을 기다린다' '때까지 넘어가지 않는다'
  _has "D4.f 확인 필수면 보여 준 것을 PR 게이트 요약 맨 앞에 다시 붙인다 (20261109)" "$s" 'PR 게이트 요약 맨 앞에' '보여 준 것(스크린샷·출력)을 다시 붙인다'
  _has "D4.g 보여 줄 방법이 없었던 경우 — 사실과 직접 확인 방법을 적고 확인한 척하지 않는다 (AC-3)" "$(printf '%s\n' "$s" | grep -F -- '보여 줄 방법이 없었던 경우')" '직접 확인하는 방법' '확인한 척하지 않는다'
  _has "D4.h 근거 — 도입 뒤 아니다 0건·대기는 사람 시간 (20261109)" "$s" '"아니다" 가 0건'
  _has "D5.a 합리화 차단표 — 행 5개의 핵심 (AC-3)" "$(_sec "$f" '^##+ 합리화 차단표' '^##+ 레드 플래그')" \
    '보여 주기는 항상 한다' '애매하면 yes' 'PR 게이트 요약에 적는다' '다시 보여 준 뒤에만 PR 로 간다' '확인 방법 1~2줄'
  _has "D5.b 레드 플래그 3종 (AC-3)" "$(_sec "$f" '^##+ 레드 플래그' '^## 4단계')" \
    '실행 없이 "데모 완료" 기록' '확인 필수인데 PR 게이트 요약에 보여 준 것(스크린샷·출력)을 붙이지 않음' '스크린샷·출력이 변경 전 상태'
  _has "D5.c 5원칙 문지기 — 보여 준 것을 PR 게이트 요약 맨 앞에 붙여 함께 확인 (20261109)" "$(_sec "$f" '^## 5원칙 주입' '^## 참조' | grep -F -- '2 문지기')" '보여 준 것을 PR 게이트 요약 맨 앞에 붙여'
  # D6 — 4단계 기록 (AC-4)
  s=$(_sec "$f" '^## 4단계' '^## 5원칙')
  blk=$(printf '%s\n' "$s" | awk '/^```markdown/{f=1;next} /^```/{if(f)exit} f')
  _ord "D6.a evidence.md ## /demo 양식 — 제목 + 필드 5개가 순서대로 (AC-4)" "$blk" f '## /demo — <ISO-8601>' '**종류**:' '**실행**:' '**보여 준 것**:' '**확인 필요**:' '**사용자 판정**:'
  _eq "D6.b 양식의 필드 줄이 정확히 5개 (AC-4)" "$(printf '%s\n' "$blk" | grep -cE '^\*\*[^*]+\*\*:')" 5
  _has "D6.c 필드 값 목록 — 종류 5갈래·확인 필요 yes|no·판정 3갈래 (AC-4)" "$blk" \
    '**종류**: 화면 | iOS 앱 | 진행 패널 | 명령·스크립트 | 내부' '**확인 필요**: yes | no' 'PR 게이트에서 확인 | 아니다→수정 후 재확인 | 해당 없음(내부)'
  _has "D6.d session-progress /demo 행 + PR 본문 ## 데모 요약 출처 (AC-4)" "$s" \
    'session-progress-append.sh <FID> /demo DONE|SKIP' '`## 데모` 절' 'evidence.md `## /demo`'
  # D7 — PR 본문 ## 데모 가 가리키는 필드가 양식에 실제로 있다 (AC-4)
  line=$(_sec "$perf" '^### 3\. PR 생성' '^### 4\. ' | awk 'p{print;exit} $0=="## 데모"{p=1}')
  lb=""
  for k in 종류 '보여 준 것' '사용자 판정'; do
    printf '%s\n' "$line" | grep -qF -- "$k" || lb="$lb [PR본문에 $k 없음]"
    printf '%s\n' "$blk"  | grep -qF -- "**$k**:" || lb="$lb [양식에 $k 필드 없음]"
  done
  { [ -n "$line" ] && [ -z "$lb" ]; } && ok "D7.a PR 본문 ## 데모 의 종류·보여 준 것·사용자 판정이 evidence 양식 필드와 짝이 맞는다 (AC-4)" || nope "D7.a" "line=[$line]$lb"
}

# ═══ performance-test-ko 연결 (AC-2·4) ═══════════════════════════════════
_perf_checks() { local f=$1 chain=$2 fm g bb ba bs lba lg lq lp lc s e1 e2 body
  if [ ! -s "$f" ]; then nope "P0.a performance-test-ko SKILL.md 실재·비어 있지 않음 — 검사 대상 0개는 통과가 아니다 (AC-2)" "$f"; return 0; fi
  ok "P0.a performance-test-ko SKILL.md 실재 (AC-2)"
  fm=$(_fm "$f")
  _hasre "P1.a frontmatter description·used_by 가 demo-ko 를 말한다 (AC-2)" "$fm" '^description: .*demo-ko' '^used_by: .*demo-ko'
  g=$(_sec "$f" '^## PR 생성 게이트' '^## 5원칙')
  bb=$(printf '%s\n' "$g" | grep -F -- '- **batch 모드**'); ba=$(printf '%s\n' "$g" | grep -F -- '- **auto 모드**'); bs=$(printf '%s\n' "$g" | grep -F -- '- **단일 모드**')
  _eq "P2.a PR 게이트 3-way bullet 이 batch·auto·단일 각 1줄 (AC-2)" "$(printf '%s\n' "$bb" | grep -c .)$(printf '%s\n' "$ba" | grep -c .)$(printf '%s\n' "$bs" | grep -c .)" 111
  _has "P2.b 단일 모드 — 먼저 Skill: devfsd:demo-ko 호출·멈추지 않고 복귀 (AC-2 · 20261109)" "$bs" 'Skill: devfsd:demo-ko' '멈추지 않고 demo-ko 가 복귀' '단일 모드 게이트 진행'
  _has "P2.c auto 모드 — 먼저 Skill: devfsd:demo-ko·확인 대기는 ### 데모 로 이관·이어서 다이제스트 (AC-2)" "$ba" 'Skill: devfsd:demo-ko' '### 데모' '이어서' '가정 다이제스트 제시'
  _lacks "P2.d batch 모드는 demo-ko 를 부르지 않는다 (AC-2)" "$bb" 'demo-ko' 'Skill:'
  _has "P2.e batch 모드 — 기존 BATCH-PERF-DONE·PR 게이트 전체 skip 보존 (AC-2)" "$bb" 'BATCH-PERF-DONE: <FID>' 'PR 게이트 전체 skip'
  _eq "P3.a Skill: devfsd:demo-ko 호출이 파일 전체에서 정확히 2곳(단일·auto) (AC-2)" "$(grep -cF 'Skill: devfsd:demo-ko' "$f")" 2
  lc=$(printf '%s\n' "$g" | grep -nF 'Skill: devfsd:demo-ko' | cut -d: -f1); lba=$(printf '%s\n' "$lc" | tail -1)
  lq=$(_ln "$g" 'PR을 생성하시겠습니까? [y/n]'); lg=$(_lnx "$g" '### 1. 커밋 전제 확인'); lp=$(_lnx "$g" 'gh pr create \')
  { [ "$(printf '%s\n' "$lc" | grep -c .)" = 2 ] && [ -n "$lq" ] && [ -n "$lg" ] && [ -n "$lp" ] \
    && [ "$lba" -lt "$lq" ] && [ "$lba" -lt "$lg" ] && [ "$lg" -lt "$lp" ]; } \
    && ok "P3.b 게이트 안 demo-ko 호출 2곳이 모두 첫 PR 생성 [y/n] 질문·커밋 전제 확인·gh pr create 앞이다 (AC-2)" || nope "P3.b" "호출 줄=[$(printf '%s' "$lc" | tr '\n' ' ')] y/n=L$lq 커밋전제=L$lg gh pr create=L$lp"
  # 다이제스트 ### 데모 (AC-4)
  _ord "P4.a §auto 다이제스트 — ### 데모 가 에스컬레이션 이력 뒤·개발 중 결정 앞 (AC-4)" "$g" x '### 에스컬레이션 이력' '### 데모' '### 개발 중 결정'
  _eq "P4.b ### 데모 절 제목이 정확히 1개 (AC-4)" "$(_cntx "$g" '### 데모')" 1
  _has "P4.c ### 데모 본문 — evidence ## /demo 요약·확인 필요는 사용자 확인 대기 (AC-4)" "$(printf '%s\n' "$g" | awk 'p{print;exit} $0=="### 데모"{p=1}')" 'evidence.md `## /demo`' '사용자 확인 대기'
  # PR 본문 ## 데모 (AC-4)
  body=$(_sec "$f" '^### 3\. PR 생성' '^### 4\. ')
  _ord "P5.a PR 본문 템플릿 — ## Test plan < ## 데모 < ## 이번에 고치지 않고 넘긴 것 < EOF (AC-4)" "$body" x '## Test plan' '## 데모' '## 이번에 고치지 않고 넘긴 것' 'EOF'
  _eq "P5.b PR 본문 ## 데모 절 제목이 파일 전체에서 정확히 1개 (AC-4)" "$(_cntx "$(cat "$f")" '## 데모')" 1
  _has "P5.c PR 본문 ## 데모 본문 — evidence ## /demo 의 종류·보여 준 것·사용자 판정 (AC-4)" "$(printf '%s\n' "$body" | awk 'p{print;exit} $0=="## 데모"{p=1}')" 'evidence.md `## /demo`' '종류' '보여 준 것' '사용자 판정'
  # 다음 skill (AC-2)
  s=$(_sec "$f" '^## 다음 skill' '^NEVER-MATCHES$')
  e1=$(printf '%s\n' "$s" | grep -F -- '- **단일 모드 PASS·SKIP**'); e2=$(printf '%s\n' "$s" | grep -F -- '- **batch 모드 PASS·SKIP**')
  _has "P6.a 다음 skill — 단일 모드는 demo-ko 호출-복귀 뒤 PR 생성 게이트 (AC-2)" "$e1" '`devfsd:demo-ko` 호출-복귀' 'PR 생성 게이트 진행' 'Lifecycle 종료'
  _lacks "P6.b 다음 skill — batch 모드 bullet 에 demo-ko 없음 (AC-2)" "$e2" 'demo-ko'
  _has "P6.c performance-test-ko 는 여전히 최종 단계·게이트 이후 자동 chain 없음 (AC-2)" "$s" '**최종 단계**' 'PR 게이트 이후 어떤 스킬도 자동 chain하지 않는다'
  # chain.yaml 불변 (AC-2) — git diff 가 아니라 내용으로 본다(커밋 뒤에도 유효)
  s=$(cat "$chain" 2>/dev/null)
  _eq "P7.a hooks/chain.yaml 을 읽을 수 있고 primary edge 가 11개 이상 — 빈 파일은 통과가 아니다 (AC-2)" "$([ "$(printf '%s\n' "$s" | grep -cE '^  - \{from: ')" -ge 11 ] && echo ok || echo few)" ok
  _lacks "P7.b hooks/chain.yaml 에 demo-ko 가 없다 (AC-2)" "$s" 'demo-ko'
  _has "P7.c chain 끝 edge 는 integration-test-ko → performance-test-ko (AC-2)" "$s" '{from: integration-test-ko, to: performance-test-ko}'
  _lacks "P7.d performance-test-ko 에서 나가는 primary edge 없음 (AC-2)" "$s" 'from: performance-test-ko'
}

# ═══ 실행 (실파일) ═══════════════════════════════════════════════════
_demo_checks "$DEMO" "$PERF"
_perf_checks "$PERF" "$CHAIN"

# ═══ BF — batch PR 직전 데모 (20261109-batch-demo-gate · 11회차 F-1) ═══════════════════════════
#   per-FR FID 의 데모 skip(BATCH-DEMO-SKIP)은 의도다(PR 이 없다). 그런데 batch PR 은 사용자가 결과를 처음 보는 지점인데
#   오케스트레이터(start-all Step D · start-all-auto PR 게이트)에 데모 호출이 0건이라 README 의 "PR 직전 데모 확인" 약속이
#   batch 에서 지켜지지 않았다. 오케스트레이터가 `batch-final` 인자로 demo-ko 를 PR 직전에 부른다.
SA="$PLUGIN/commands/start-all.md"; SAA="$PLUGIN/commands/start-all-auto.md"
_bf_checks() { local demo=$1 sa=$2 saa=$3 d dd da
  d=$(_sec "$demo" '^### batch 최종 호출' '^## 1단계')
  _has "BF.a demo-ko — batch-final 호출 절: 인자·diff 범위·무인 인자·기록 위치 (F-1)" "$d" \
    'batch-final <BATCH_ID>' 'origin/$BASE...HEAD' '<BATCH_ID> auto' '.specops/<BATCH_ID>/demo.md' 'session-progress'
  dd=$(_sec "$sa" '^\*\*Step D: batch PR 생성' '^## 안티패턴')
  _has "BF.b start-all Step D — demo-ko batch-final 호출 (F-1)" "$dd" 'Skill: devfsd:demo-ko' 'batch-final $BATCH_ID'
  _ord "BF.c start-all Step D — 데모 호출이 push·PR 생성보다 앞 (F-1)" "$dd" f 'Skill: devfsd:demo-ko' 'git push -u origin "feat/$BATCH_ID"' '  --base "$BASE"'
  _has "BF.d start-all PR 본문에 ## 데모 절 (F-1)" "$dd" '## 데모' '.specops/<BATCH_ID>/demo.md'
  da=$(_sec "$saa" '^6\. \*\*batch PR 게이트' '^## §auto 모드 동작')
  _has "BF.e start-all-auto PR 게이트 — demo-ko batch-final auto 호출 · 다이제스트로 이관 (F-1)" "$da" 'Skill: devfsd:demo-ko' 'batch-final <BATCH_ID> auto' '데모: 사용자 확인 대기'
}
_bf_checks "$DEMO" "$SA" "$SAA"
# 양성 대조 — start-all 사본에서 데모 호출이 사라지면 BF.b 가, 순서가 뒤집히면 BF.c 가 떨어진다
if _mut "$SA" 'Skill: devfsd:demo-ko' 'Skill: devfsd:XXXX' > "$_T/sa.mut" 2>/dev/null; then
  out=$(_bf_checks "$DEMO" "$_T/sa.mut" "$SAA"); printf '%s\n' "$out" | grep -qE '^FAIL BF\.b ' && ok "BF.x1 start-all 에서 데모 호출이 사라지면 BF.b FAIL" || nope "BF.x1" "변이가 살아남았다"
else nope "BF.x1" "변이 적용 실패"; fi
if _mut "$SAA" 'batch-final <BATCH_ID> auto' 'batch-final' > "$_T/saa.mut" 2>/dev/null; then
  out=$(_bf_checks "$DEMO" "$SA" "$_T/saa.mut"); printf '%s\n' "$out" | grep -qE '^FAIL BF\.e ' && ok "BF.x2 무인 인자가 사라지면 BF.e FAIL" || nope "BF.x2" "변이가 살아남았다"
else nope "BF.x2" "변이 적용 실패(본문에 문구가 없다)"; fi

# ═══ C — 양성 대조: 변이를 넣은 사본에서 같은 검사 함수가 기대한 ID 로 FAIL 하는지 (문구 하나가 사라지면 떨어진다) ═══
# $1=ID $2=demo|perf $3=바꿀 문자열 $4=대체문 $5=기대 FAIL ID(정규식) $6=L(줄 전체 일치, 선택)
_ctl() { local id=$1 kind=$2 src out
  case "$kind" in demo) src=$DEMO ;; perf) src=$PERF ;; esac
  if ! _mut "$src" "$3" "$4" "${6-}" > "$_T/mut" 2>/dev/null; then nope "$id" "변이 적용 실패 — 바꿀 문구가 본문에 없다: [$3]"; return 0; fi
  if [ "$3" != "$4" ] && cmp -s "$src" "$_T/mut"; then nope "$id" "변이가 파일을 바꾸지 못했다"; return 0; fi
  case "$kind" in
    demo)  out=$(_demo_checks "$_T/mut" "$PERF") ;;
    perf)  out=$(_perf_checks "$_T/mut" "$CHAIN") ;;
  esac
  if [ -z "$5" ]; then   # 동일 대체(항등) — FAIL 이 하나도 없어야 한다: 검사가 사본 경로 탓에 떨어지는 게 아님을 증명
    printf '%s\n' "$out" | grep -q '^FAIL ' && nope "$id" "항등 변이인데 FAIL: $(printf '%s\n' "$out" | grep '^FAIL ' | head -2 | tr '\n' ' ')" || ok "$id"
  else
    printf '%s\n' "$out" | grep -qE "^FAIL $5 " && ok "$id" || nope "$id" "변이가 살아남았다 — 기대 FAIL $5, 실제: $(printf '%s\n' "$out" | grep '^FAIL ' | cut -c1-40 | head -3 | tr '\n' '|')"
  fi; }
_ctl "C0.a 항등 변이(demo) — 사본 경로로도 검사가 전부 통과 (대조군)" demo '`§lite` 포함' '`§lite` 포함' ''
_ctl "C0.b 항등 변이(perf) — 사본 경로로도 검사가 전부 통과 (대조군)" perf 'BATCH-PERF-DONE: <FID>' 'BATCH-PERF-DONE: <FID>' ''
_ctl "C1.a layer 2→3 이면 D1.b FAIL" demo 'layer: 2' 'layer: 3' 'D1\.b' L
_ctl "C1.b BATCH 마커 이름이 바뀌면 D1.f FAIL" demo 'BATCH-DEMO-SKIP: <FID>' 'BATCH-SKIP: <FID>' 'D1\.f'
_ctl "C1.c SINGLE 의 §lite 포함 문구가 사라지면 D1.h FAIL" demo '`§lite` 포함' '' 'D1\.h'
_ctl "C1.d AUTO 가 확인 대기를 하도록 바뀌면 D1.g FAIL" demo '확인 대기는 하지 않는다' '확인 대기를 한다' 'D1\.g'
_ctl "C1.e 모드 판정 정규식에서 줄 머리 앵커가 빠지면(prose 라벨 오인) D1.j FAIL" demo "-qE '^\\*\\*§auto" "-qE '\\*\\*§auto" 'D1\.j'
_ctl "C1.f 4단계 헤딩이 하나 빠지면 D1.c FAIL" demo '## 4단계: 기록' '## 4단계 기록 생략' 'D1\.c' L
_ctl "C3.a 명령·스크립트 bullet 이 테스트 요약을 허용하면 D3.c FAIL" demo '입력과 명령을 함께 적는다.' '입력과 명령 없이 테스트 요약을 허용한다.' 'D3\.c'
_ctl "C4.a '판단이 애매하면' 이 사라지면 D4.a FAIL" demo '**판단이 애매하면** ' '' 'D4\.a'
_ctl "C4.b 확인이 필수 → 선택이면 D4.a FAIL" demo '확인이 **필수**다' '확인은 선택이다' 'D4\.a'
_ctl "C4.c 멈추지 않는다 가 사라지면 D4.b FAIL" demo '**멈추지 않는다**' '**멈춘다**' 'D4\.b'
_ctl "C4.d 확인 필수 열거에 테스트가 섞이면 D4.c FAIL" demo '화면·UI 소스 · iOS 앱' '테스트 · 화면·UI 소스 · iOS 앱' 'D4\.c'
_ctl "C4.e 아니다 가 2단계부터 다시 가 아니라 4단계로 가면 D4.d FAIL" demo '**2단계부터 다시**' '**4단계로**' 'D4\.d'
_ctl "C4.f 확인한 척하지 않는다 가 사라지면 D4.g FAIL" demo '확인한 척하지 않는다.' '.' 'D4\.g'
_ctl "C4.g 확인 대기 질문이 다시 들어오면 D4.e FAIL" demo '**멈추지 않는다**' '**멈추지 않는다** "위 결과가 의도한 모습입니까?' 'D4\.e'
_ctl "C6.a 사용자 판정 필드가 사라지면 D6.a FAIL" demo '**사용자 판정**: PR' '**판정**: PR' 'D6\.a'
_ctl "C6.b 양식에 필드가 하나 더 늘면 D6.b FAIL" demo '**확인 필요**: yes' '**추가**: x
**확인 필요**: yes' 'D6\.b'
_ctl "C6.c session-progress /demo 행이 사라지면 D6.d FAIL" demo '<FID> /demo DONE|SKIP' '<FID> /demo' 'D6\.d'
_ctl "C7.a 단일 모드에서 demo-ko 호출이 사라지면 P2.b FAIL" perf '**먼저 `Skill: devfsd:demo-ko`** 를 호출해' '를 호출해' 'P2\.b'
_ctl "C7.b auto 모드에서 demo-ko 호출이 사라지면 P2.c FAIL" perf '**먼저 `Skill: devfsd:demo-ko`**' '**먼저**' 'P2\.c'
_ctl "C7.c batch 모드가 demo-ko 를 부르면 P2.d FAIL" perf 'PR 게이트 전체 skip' '`Skill: devfsd:demo-ko` 후 PR 게이트 전체 skip' 'P2\.d'
_ctl "C7.d 가정 다이제스트 ### 데모 제목이 사라지면 P4.a FAIL" perf '### 데모' '### 시연' 'P4\.a' L
_ctl "C7.e PR 본문 ## 데모 절 제목만 사라지면(### 데모 는 남음) P5.a FAIL" perf '## 데모' '## 시연' 'P5\.a' L
_ctl "C7.f 다음 skill 의 호출-복귀 문구가 사라지면 P6.a FAIL" perf '`devfsd:demo-ko` 호출-복귀' '`devfsd:demo-ko` 호출' 'P6\.a'
_ctl "C7.g frontmatter used_by 의 demo-ko 가 사라지면 P1.a FAIL" perf ', demo-ko (PR 생성 게이트 직전 호출 → 복귀)' '' 'P1\.a'
cat "$CHAIN" > "$_T/chain.mut"; printf '%s\n' '  - {from: performance-test-ko, to: demo-ko}' >> "$_T/chain.mut"
printf '%s\n' "$(_perf_checks "$PERF" "$_T/chain.mut")" | grep -qE '^FAIL P7\.[ab] ' && ok "C7.h chain.yaml 에 performance-test-ko → demo-ko edge 가 생기면 P7 FAIL" || nope "C7.h" "chain edge 변이가 살아남았다"
# 대상 0개 — 빈 파일·없는 파일은 통과가 아니라 실패
: > "$_T/empty"
printf '%s\n' "$(_demo_checks "$_T/empty" "$PERF")" | grep -q '^FAIL D0\.a ' && ok "C9.a 빈 demo-ko 본문은 D0.a FAIL (대상 0개 ≠ 통과)" || nope "C9.a" "빈 파일이 통과했다"
printf '%s\n' "$(_perf_checks "$_T/none" "$CHAIN")" | grep -q '^FAIL P0\.a ' && ok "C9.b 없는 performance-test-ko 는 P0.a FAIL (대상 0개 ≠ 통과)" || nope "C9.b" "없는 파일이 통과했다"
printf '%s\n' "$(_perf_checks "$PERF" "$_T/none")" | grep -q '^FAIL P7\.a ' && ok "C9.c 읽을 수 없는 chain.yaml 은 P7.a FAIL (edge 0개 ≠ 통과)" || nope "C9.c" "없는 chain.yaml 이 통과했다"

finish
