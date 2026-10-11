#!/usr/bin/env bash
# 위험 프로파일 분류기 (P1 → Wave B limited live).
# Usage:
#   risk-profile.sh compute <FID> [--floor standard|strict]
#   risk-profile.sh show <FID>
# lite/standard/strict 를 계산·기록한다. mode=live 이며, effective=lite 일 때만
# reductions_allowed=["batch-review-skip"] (requesting/receiving skip). Phase B·TDD·verify·receipt 축소 금지.
# 참고: review_mode:end-loaded 는 B/C 생략이 아니라 말미 1회 수행 — reductions_allowed 와 무관.
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
PLUGIN=$(cd "$(dirname "$0")/../.." && pwd)
METRIC_SH="$PLUGIN/scripts/_internal/record-metric.sh"
# shellcheck source=/dev/null
source "$PLUGIN/scripts/dag/parse-dag.sh" 2>/dev/null || true

rp::rank() {
  case "$1" in lite) echo 1 ;; standard) echo 2 ;; strict) echo 3 ;; *) echo 0 ;; esac
}

rp::max_profile() {
  local a="$1" b="$2" ra rb
  ra=$(rp::rank "$a"); rb=$(rp::rank "$b")
  [ "$ra" -ge "$rb" ] && printf '%s' "$a" || printf '%s' "$b"
}

# 기준 브랜치 — main·master·origin/main·origin/master 중 **HEAD 에 가장 가까운**(ref..HEAD 커밋 수 최소) ref.
#   로컬 main 만 보던 종전 판정은 로컬 main 이 원격보다 뒤처진 repo 에서, 그동안 원격에 쌓인 변경 전부를 이 FID 의
#   변경으로 읽었다(실측 20261008: 100커밋 뒤처진 main → 3줄 수정이 151파일·infra strict → lite 가 풀 경로로 승격).
#   동률이면 앞선 후보(로컬)를 쓴다. 후보가 하나도 없으면 빈 문자열(종전과 동일 — 파일 신호 없음).
rp::base_ref() {
  local ref n best="" best_n=""
  for ref in main master origin/main origin/master; do
    git rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1 || continue
    n=$(git rev-list --count "$ref..HEAD" 2>/dev/null) || continue
    case "$n" in ''|*[!0-9]*) continue ;; esac
    if [ -z "$best" ] || [ "$n" -lt "$best_n" ]; then best=$ref; best_n=$n; fi
  done
  printf '%s' "$best"
}

rp::collect_files() {
  local files base
  # 세 출처의 합집합이다 (20261008). 종전엔 앞 출처가 비었을 때만 다음을 봤다 — 트리에 미커밋 변경이 하나라도 있으면
  #   이 브랜치에 이미 커밋된 변경(예: Step 5.6 이 고쳐 커밋한 data-model.md)이 판정에서 빠졌다.
  base=$(rp::base_ref)
  files=$( { git diff HEAD --name-only --no-renames
             git diff --cached --name-only --no-renames
             [ -n "$base" ] && git diff "$base"...HEAD --name-only --no-renames; } 2>/dev/null || true)
  # tasks outputs 보강
  if [ -n "${_RP_YAML:-}" ] && command -v python3 >/dev/null 2>&1; then
    local extra
    extra=$(SPECOPS_DAG_YAML="$_RP_YAML" python3 -c '
import os, sys
sys.path[:] = [p for p in sys.path if p not in ("", ".")]
try:
  import yaml
except Exception:
  sys.exit(0)
doc = yaml.safe_load(os.environ.get("SPECOPS_DAG_YAML", "")) or {}
for t in doc.get("tasks") or []:
  if not isinstance(t, dict):
    continue
  for o in (t.get("outputs") or []):
    if isinstance(o, str) and o:
      print(o)
' 2>/dev/null || true)
    [ -n "$extra" ] && files=$(printf '%s\n%s\n' "$files" "$extra")
  fi
  printf '%s\n' "$files" | awk 'NF' | sort -u
}

rp::docs_only() {
  local f
  [ -z "$1" ] && return 1
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      *.md|*.txt|*.rst|screens/*.html|.specops/*) ;;
      *) return 1 ;;
    esac
  done <<< "$1"
  return 0
}

rp::impl_file_count() {
  local f n=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      *.md|*.txt|*.rst|screens/*.html|.specops/*) ;;
      *test*|*spec*|*/__tests__/*) ;;
      *) n=$((n + 1)) ;;
    esac
  done <<< "$1"
  printf '%d' "$n"
}

# 신호 판정 입력의 문맥 필터 (20260914-risk-profile-negation-blind).
# "무엇을 하는가" 가 아니라 "무엇을 언급하는가" 인 조각을 뺀다 — 부정문·괄호 나열·표 셀·격리 정리.
#   `.` 는 뒤가 공백·줄끝일 때만 경계다. `data-model.md`·`.env`·`path.join` 을 쪼개면 그 신호가 영영 안 걸린다.
#   영문 부정어는 소문자 단어만, SQL `not null`(대소문자 무관)은 부정어 검사에서 뺀다 — migration 을 놓치지 않게.
#   부정 수량은 `0건` 과, 뒤가 공백·구두점·조각 끝인 `0개` 다 — `v2.0개선` 은 부정이 아니다.
#   구조화 필드 `irreversible: true`(뒤가 공백·`#주석`·줄끝뿐)는 필터를 거치지 않는다 — 주석의 "되돌릴 수 없음" 은 위험 긍정이다.
#   `·` 나열 괄호구는 지운다. split 에 `()` 를 넣지 않는다 — `exec(`·`unlink(` 신호가 죽는다.
#   부정 표지를 담은 산문 괄호는 지우지 않고 `(` `)` 를 `|` 경계로 바꾼다 — 괄호 안이 독립 조각이 되어
#     부정은 괄호 안에 갇히고 괄호 안·밖 긍정 신호가 모두 산다(C-2·C-3 · `—` 로만 나뉜 괄호 M-3 포함).
#   탐지기가 괄호를 요구하는 토큰 `exec(`·`unlink(` 의 괄호만 \002 로 잠시 가려 치환 대상에서 뺀다 —
#     `middleware(`·`RBAC(`·`v2(` 같은 영숫자 직후 산문 괄호는 경계 치환된다(C-4). 앞 글자 클래스를 match 에
#     넣으면 BSD awk UTF-8 로케일이 한글 앞 괄호에서 `towc: multibyte conversion failure` 를 내므로 리터럴만 쓴다.
#     가림 토큰은 탐지기 `grep -i` 와 같게 대소문자 무시(`EXEC(`·`Unlink(` — 글자별 [Xx] 클래스, `&` 로 원문 보존).
#     표지는 \002 하나만 쓴다 — 별도 표지(\001)를 두면 입력에 이미 든 그 문자가 가림으로 오인된다(m-1).
#     표지 문자 \002 는 가림 전에 입력에서 지운다 — 제어문자는 어떤 탐지 신호에도 쓰이지 않고, 입력 `(\002` 가 표지로 오인되는 것을 막는다.
#     연동 규칙: rp::detect_strict_signals 에 `\(` 를 요구하는 토큰(현재 `unlink\(`·`exec\(`)을 추가하면 이 가림 목록도 같이 고친다.
#   격리 변수 면제는 `$TD`·`$TMP`·`$TMPDIR` 전체 이름만(뒤 `"`·공백·`/`·줄끝) — `$TD_ROOT` 류 접두 일치는 면제 아님.
#   BSD awk 는 괄호식 안 `/` 를 정규식 종료로 읽는다 — `\/` 는 괄호식 밖에 둔다.
# 필터 실패 시 원 코퍼스 + stderr 경고 — 오탐 쪽으로 기울고, 조용히 약해지지 않는다.
# `# rp-filter` 마커는 test-risk-profile.sh T31 의 fallback shim 이 이 호출만 골라 실패시키는 표지다.
rp::filter_corpus() {
  local out
  if out=$(printf '%s\n' "$1" | awk '
    # rp-filter
    {
      line = $0
      if (line ~ /irreversible:[[:space:]]*true[[:space:]]*(#.*)?$/) { print line; next }
      while (match(line, /\([^()]*·[^()]*\)/))
        line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
      gsub(/\002/, "", line)
      gsub(/[Ee][Xx][Ee][Cc]\(|[Uu][Nn][Ll][Ii][Nn][Kk]\(/, "&\002", line); gsub(/\(\002/, "\002", line)
      while (match(line, /\([^()]*(없다|없음|무관|해당 없음|미해당|제외|아님|금지)[^()]*\)/))
        line = substr(line, 1, RSTART - 1) "|" substr(line, RSTART + 1, RLENGTH - 2) "|" substr(line, RSTART + RLENGTH)
      gsub(/\002/, "(", line)
      n = split(line, parts, /\.[[:space:]]|\.$|[;,|]|—/)
      for (i = 1; i <= n; i++) {
        s = parts[i]
        if (s ~ /없다|없음|무관|해당 없음|미해당|제외|아님|금지|(^|[^0-9])(0건|0개([ \t.,;:)`"]|$))/) continue
        t = s; gsub(/[Nn][Oo][Tt][[:space:]]+[Nn][Uu][Ll][Ll]/, "", t)
        if (t ~ /(^|[^a-zA-Z])(none|not|no)([[:space:]]|$)/) continue
        if (s ~ /rm -rf/ && s ~ /mktemp|trap|[$][{]?(TD|TMP|TMPDIR)[}]?(["[:space:]]|\/|$)/) continue
        print s
      }
    }'); then
    printf '%s' "$out"
  else
    echo "RISK-PROFILE: corpus filter unavailable — raw corpus 로 판정" >&2
    printf '%s' "$1"
  fi
}

# 설계 문서 "인용" 과 "변경" 의 구분 (20261008-lite-strict-misjudge).
# specifying-ko 는 spec §참조에 `.specops/memory/api-spec.md`·`data-model.md` 경로를 자동 인용한다. 그 경로 문자열이
#   public_api·db_migration 신호로 읽혀 설계 문서가 있는 프로젝트의 FID 가 전부 strict 였다 — "(변경 없음)" 이라 적어도
#   괄호 밖 경로 조각은 긍정으로 남는다(실기록: 인용한 FID 67건 전부 strict · lite 는 매번 LITE-STRICT-GUARD).
# 가리는 것은 **§참조 절 글머리표의 경로 토큰뿐**이다 — 줄의 나머지 글(`/api/…`·DDL 등)은 그대로 판정한다.
#   §참조 절 = 제목이 `참조` 한 낱말(앞 번호·§ 허용: `## 10. 참조`)인 절. `### 3. 참조 무결성 변경` 같은 제목은 아니다 —
#   `참조` 가 들었다고 켜면 "data-model.md 의 FK 를 신설한다" 가 인용으로 가려진다(리뷰 I-1 · 실행으로 확인).
#   `(§)?` 는 묶어서 쓴다 — mawk 는 바이트 단위라 `§?` 가 마지막 바이트에만 걸려 `## 10. 참조` 를 놓친다(Linux CI 의 awk).
# 한계: 문서 변경이 기준 ref 자체에 커밋돼 있으면(브랜치 없이 main 에 직접) 변경 파일에 안 잡힌다 — 종전부터의 틈이다.
# 가리지 않는 것: ① git 이 추적하지 않는 문서(바꿨는지 알 길이 없다 — 종전대로 인용도 신호)
#   ② 갱신을 말하는 줄(갱신·반영·수정·신설·Step 5.6·Phase 2.5 — "수정 없음" 도 남는다: 미탐보다 오탐 쪽).
#      `변경`·`추가` 는 넣지 않는다 — 실기록의 인용 주석이 대부분 "(변경 없음)"·"엔드포인트 추가 없음" 이라 가림이 통째로 꺼진다.
#   ③ §참조 밖의 모든 줄(`**인터페이스 반영**:` 등) ④ tasks.md 전체(`Modify:` 줄·outputs).
# 추적 문서를 실제로 바꿨는지는 rp::collect_files(변경 파일 ∪ tasks outputs)가 말한다 — 탐지 정규식은 그대로다.
# 이 가림은 raw_corpus 를 잡기 **전에** 한다 — 뒤에 하면 "필터가 신호를 모두 제외함 — --floor strict" 경고가
#   인용뿐인 FID 마다 떠서 같은 오판을 사람 손으로 되살린다.
rp::mask_doc_citations() {
  local docs="" d
  for d in api-spec data-model; do
    git ls-files --error-unmatch -- "$SPECOPS/memory/$d.md" >/dev/null 2>&1 && docs="${docs}${docs:+|}$d"
  done
  [ -z "$docs" ] && { printf '%s' "$1"; return 0; }
  local out
  if out=$(printf '%s\n' "$1" | RP_DOCS="$docs" awk '
    # rp-mask
    BEGIN { n = split(ENVIRON["RP_DOCS"], doc, "|") }
    /^#+[[:space:]]/ { insec = ($0 ~ /^#+[[:space:]]+((§)?[0-9.]+[[:space:]]*)?참조[[:space:]]*$/) }
    insec && /^[[:space:]]*[-*+][[:space:]]/ && $0 !~ /갱신|반영|수정|신설|Step 5\.6|Phase 2\.5/ {
      for (i = 1; i <= n; i++) gsub(doc[i] "\\.md", doc[i] "-md")
    }
    { print }'); then
    printf '%s' "$out"
  else
    echo "RISK-PROFILE: citation mask unavailable — 인용도 신호로 판정" >&2
    printf '%s' "$1"
  fi
}

# 테스트 샌드박스 정리 가림 (20261008-lite-strict-misjudge).
# tasks.md 의 TDD 스텝에는 테스트 코드가 실린다. `T=$(mktemp -d)` … `rm -rf "$T"` 는 제품이 하는 일이 아니라
#   테스트가 자기 임시 디렉터리를 치우는 것인데 destructive_fs 로 잡혔다(실기록: §lite 가드 발동 9건 중 6건이 이 형태이고
#   8건이 override 로 통과 — 가드가 우회 습관을 만들고 있었다). filter_corpus 의 종전 면제는 변수 **이름**($TD·$TMP·$TMPDIR)만 본다.
# 여기서는 이름이 아니라 **출처**를 본다: 같은 구간(코드펜스 표지·제목 사이)에서 `이름=$(mktemp …)` 으로 대입된 변수여야 하고,
#   그 뒤 다른 값으로 재대입되지 않았어야 하며, `rm -rf` 의 **모든** 대상이 그런 변수(+ `..` 없는 하위 경로)여야 한다.
#   하나라도 어긋나면(리터럴 경로·출처 모르는 변수·다른 구간의 대입·섞인 대상) 손대지 않는다 — 종전대로 신호다.
#   출처로 인정하는 것은 `mktemp` 명령 그 자체다(`mktemp_backup_dir` 같은 접두 일치는 아니다 · 주석 줄의 대입도 아니다).
#   하위 경로에 또 다른 `$변수` 가 있으면(`"$T/$SUB"`) 가리지 않는다.
#   구간 경계는 코드펜스 표지 줄(``` · ~~~)과, **펜스 밖의** 마크다운 제목 줄이다. 펜스 안의 `# 주석` 은 제목이 아니다 —
#     그걸 경계로 읽으면 대입과 정리 사이에 주석 한 줄만 있어도 출처가 끊긴다. 펜스가 겹쳐 안팎이 뒤집히면
#     주석이 경계로 읽혀 가림이 줄어들 뿐이다(오탐 쪽).
# 가리는 것은 그 `rm -rf` 토큰 하나뿐이다. 같은 줄의 다른 명령·다른 신호(`DROP TABLE` 등)는 그대로 판정한다.
# 출처가 확인된 구조적 비신호라 raw_corpus 를 잡기 전에 한다(문맥 추정으로 빼는 filter_corpus 와 달리 경고 대상이 아니다).
#   BSD awk 는 괄호식 안 `/` 를 정규식 종료로 읽는다 — `\/` 는 괄호식 밖에 둔다. 작은따옴표는 \047 로 쓴다.
# 알려진 오발 — 고치지 않았다 (20261011-risk-sandbox-quote-rebind):
#   재대입 키워드(read·unset·for …)를 줄 전체에서 찾으므로 문자열·주석 속 낱말에도 반응한다. 픽스처를 쓰는 줄
#   `printf '%s\n' 'unset X' > "$T/a.sh"` 뒤의 `rm -rf "$T"` 가 신호로 남는다(PR #180 에서 경량 승격 가드가 틀리게 울렸다).
#   따옴표·주석을 읽어 빼는 수정을 네 번 설계했고, 독립 리뷰가 그때마다 종전에는 잡히던 재대입이 빠지는 입력을 찾았다:
#   `cmd='unset T'` 뒤의 `eval "$cmd"` · `$cmd` · 백틱 안의 ` #` · `echo() { $1; }` 로 다시 정의한 echo.
#   문자열이 실행되는 경로와 `#` 가 주석이 아닌 표기를 줄 단위로 다 가릴 수 없다 — 그 입력들은 test-risk-profile.sh T59 에 잠겨 있다.
#   남아 있는 FID 문서 147건에서 이 오발은 0건이었다(확인된 발생 1회). 이 오발로 가드가 울리면 승격하거나 사유를 적어 우회한다.
rp::mask_sandbox_cleanup() {
  local out
  if out=$(printf '%s\n' "$1" | awk '
    # rp-sandbox
    function all_sandbox(args,   n, i, t, name, cnt) {
      sub(/[[:space:]]#.*$/, "", args)
      gsub(/["\047]/, "", args)
      n = split(args, tk, /[[:space:]]+/); cnt = 0
      for (i = 1; i <= n; i++) {
        t = tk[i]
        if (t == "" || t ~ /^-/) continue
        if (t !~ /^[$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?(\/[^[:space:]]*)?$/ || t ~ /[.][.]/ || t ~ /.[$]/) return 0
        name = t; sub(/^[$][{]?/, "", name); sub(/[}].*$/, "", name); sub(/\/.*$/, "", name)
        if (!(name in sb)) return 0
        cnt++
      }
      return cnt > 0
    }
    {
      line = $0
      if (line ~ /^[[:space:]]*(```|~~~)/) { infence = !infence; split("", sb); print line; next }
      if (!infence && line ~ /^#+[[:space:]]/) { split("", sb); print line; next }
      # 대입이 아닌 방식으로 값이 바뀌는 변수는 출처를 잃는다 (for·read·unset·printf -v·`:=`·`+=`)
      #   for 는 루프 변수만 다시 묶는다 — 줄에 함께 나온 다른 변수(`touch "$T/$f"` 의 T)는 그대로다.
      rest = line
      while (match(rest, /(^|[^A-Za-z0-9_])for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
        name = substr(rest, RSTART, RLENGTH); sub(/^.*for[[:space:]]+/, "", name); delete sb[name]
        rest = substr(rest, RSTART + RLENGTH)
      }
      rebind = (line ~ /(^|[^A-Za-z0-9_])(read|unset|mapfile|readarray|getopts)[[:space:]]/ || line ~ /printf[[:space:]]+-v/)
      for (k in sb)
        if (index(line, k ":=") || index(line, k "+=") || (rebind && line ~ ("(^|[^A-Za-z0-9_])" k "([^A-Za-z0-9_]|$)"))) delete sb[k]
      rest = line
      comment = (line ~ /^[[:space:]]*#/)
      while (match(rest, /[A-Za-z_][A-Za-z0-9_]*=/)) {
        name = substr(rest, RSTART, RLENGTH - 1)
        rest = substr(rest, RSTART + RLENGTH)
        if (!comment && rest ~ /^"?[$]\(mktemp([[:space:]]|\))/) sb[name] = 1; else delete sb[name]
      }
      out = ""; rest = line
      while ((p = index(rest, "rm -rf")) > 0) {
        out = out substr(rest, 1, p - 1)
        rest = substr(rest, p + 6)
        args = rest
        if (match(args, /;|&&|\|/)) args = substr(args, 1, RSTART - 1)
        out = out (all_sandbox(args) ? "rm-rf" : "rm -rf")
      }
      print out rest
    }'); then
    printf '%s' "$out"
  else
    echo "RISK-PROFILE: sandbox mask unavailable — 정리 코드도 신호로 판정" >&2
    printf '%s' "$1"
  fi
}

rp::detect_strict_signals() {
  local corpus="$1" files="$2" signals="" 
  # keyword / path signals (라인수 무관)
  printf '%s\n%s\n' "$corpus" "$files" | grep -qiE \
    '(^|[^a-z])(auth|oauth|jwt|rbac|permission|credential|secret|\.env)([^a-z]|$)' \
    && signals="${signals} auth"
  printf '%s\n%s\n' "$corpus" "$files" | grep -qiE \
    '(migration|alembic|prisma/migrations|supabase/migrations|CREATE TABLE|ALTER TABLE|DROP TABLE|data-model\.md)' \
    && signals="${signals} db_migration"
  printf '%s\n%s\n' "$corpus" "$files" | grep -qiE \
    '(irreversible:\s*true|Delete:|unlink\(|rm -rf|path\.join|filesystem|fs\.(unlink|rm))' \
    && signals="${signals} destructive_fs"
  printf '%s\n%s\n' "$corpus" "$files" | grep -qiE \
    '(payment|billing|pii|개인정보|주민등록|credit.?card)' \
    && signals="${signals} payment_pii"
  printf '%s\n%s\n' "$corpus" "$files" | grep -qiE \
    '(api-spec\.md|/api/|openapi|public api|엔드포인트)' \
    && signals="${signals} public_api"
  printf '%s\n%s\n' "$corpus" "$files" | grep -qiE \
    '(\.github/workflows|Dockerfile|terraform|kubernetes|k8s|helm|deploy)' \
    && signals="${signals} infra"
  printf '%s\n%s\n' "$corpus" "$files" | grep -qiE \
    '(subprocess|child_process|os\.system|exec\(|bash -c|Runtime\.exec)' \
    && signals="${signals} external_exec"
  # cross-service heuristic
  printf '%s\n%s\n' "$corpus" "$files" | grep -qiE \
    '(cross-service|microservice|message.?queue|sqs|kafka|external api)' \
    && signals="${signals} cross_service"

  printf '%s' "$signals" | xargs -n1 2>/dev/null | sort -u | xargs
}

rp::compute() {
  local fid="$1" floor="${2:-}"
  printf '%s' "$fid" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || {
    echo "risk-profile: invalid FID" >&2; return 1
  }
  case "$floor" in
    ""|standard|strict) ;;
    lite) echo "risk-profile: floor 하향(lite) 거부 — 상향만 허용" >&2; return 1 ;;
    *) echo "risk-profile: invalid floor: $floor" >&2; return 1 ;;
  esac

  local fid_dir="$SPECOPS/$fid"
  [ -d "$fid_dir" ] || { echo "risk-profile: FID dir missing" >&2; return 1; }
  [ ! -L "$SPECOPS" ] && [ ! -L "$fid_dir" ] || {
    echo "risk-profile: symlink 거부" >&2; return 1
  }

  local spec="$fid_dir/spec.md" tasks="$fid_dir/tasks.md"
  local corpus="" files
  [ -f "$spec" ] && corpus=$(rp::mask_doc_citations "$(cat "$spec")")
  [ -f "$tasks" ] && corpus=$(printf '%s\n%s\n' "$corpus" "$(cat "$tasks")")

  _RP_YAML=""
  if [ -f "$tasks" ] && command -v dag::extract_yaml >/dev/null 2>&1; then
    _RP_YAML=$(dag::extract_yaml "$tasks" 2>/dev/null || true)
  fi

  corpus=$(rp::mask_sandbox_cleanup "$corpus")
  local raw_corpus="$corpus" raw_signals
  corpus=$(rp::filter_corpus "$corpus")
  files=$(rp::collect_files)
  local strict_signals docs_only=false impl_files parallel_batch=false irreversible=false
  strict_signals=$(rp::detect_strict_signals "$corpus" "$files")
  # 필터가 신호를 전부 지웠으면 stderr 1줄 — 미탐 방향이라 조용히 넘기지 않는다 (JSON 스키마는 불변)
  if [ -z "$strict_signals" ]; then
    raw_signals=$(rp::detect_strict_signals "$raw_corpus" "$files")
    [ -n "${raw_signals// /}" ] \
      && echo "RISK-PROFILE: 문맥 필터가 strict 신호를 모두 제외함 (원 코퍼스: ${raw_signals}) — 실제 위험이면 --floor strict" >&2
  fi
  # parallel_batch 는 기록만 한다 — 병렬 가능성은 위험이 아니다(strict 신호 아님)
  if [ -n "$_RP_YAML" ] && command -v dag::find_independent_batch >/dev/null 2>&1; then
    [ -n "$(dag::find_independent_batch "$_RP_YAML" 2>/dev/null || true)" ] && parallel_batch=true
  fi
  if printf '%s' "$corpus" | grep -qiE 'irreversible:[[:space:]]*true'; then
    irreversible=true
    printf '%s' "$strict_signals" | grep -qw destructive_fs \
      || strict_signals=$(printf '%s\ndestructive_fs\n' "$strict_signals" | awk 'NF' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  fi

  if rp::docs_only "$files"; then docs_only=true; else docs_only=false; fi
  impl_files=$(rp::impl_file_count "$files")

  local computed=standard
  if [ -n "$strict_signals" ]; then
    computed=strict
  elif [ "$docs_only" = true ] && [ "$impl_files" -le 1 ]; then
    computed=lite
  else
    computed=standard
  fi

  # §유형=trivial 단독으로는 lite 강제 금지 (이미 computed 유지)

  local effective="$computed"
  if [ -n "$floor" ]; then
    effective=$(rp::max_profile "$computed" "$floor")
  fi
  # ENV floor
  if [ -n "${SPECOPS_RISK_PROFILE_FLOOR:-}" ]; then
    case "$SPECOPS_RISK_PROFILE_FLOOR" in
      standard|strict)
        effective=$(rp::max_profile "$effective" "$SPECOPS_RISK_PROFILE_FLOOR")
        ;;
    esac
  fi

  local lite_eligible=false
  [ "$computed" = "lite" ] && lite_eligible=true

  local ts signals_json dj pj ij lj
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # 신호는 공백 구분 한 줄이다 — 필드를 전부 돈다(종전 `$1` 은 첫 신호만 남겨 진단이 가려졌다)
  signals_json=$(printf '%s' "$strict_signals" | awk '{for(i=1;i<=NF;i++) printf "%s\"%s\"", (n++?",":""), $i}')
  [ "$docs_only" = true ] && dj=true || dj=false
  [ "$parallel_batch" = true ] && pj=true || pj=false
  [ "$irreversible" = true ] && ij=true || ij=false
  [ "$lite_eligible" = true ] && lj=true || lj=false

  mkdir -p "$fid_dir" || return 1
  local target="$fid_dir/risk-profile.json" tmp="$fid_dir/.risk-profile.$$.tmp"
  local allowed_json='[]'
  [ "$effective" = "lite" ] && allowed_json='["batch-review-skip"]'
  jq -n \
    --argjson schema_version 1 --arg fid "$fid" \
    --arg computed "$computed" --arg effective "$effective" \
    --arg floor "${floor:-}" --arg mode live \
    --argjson docs_only "$dj" --argjson impl_files "$impl_files" \
    --argjson parallel_batch "$pj" --argjson irreversible "$ij" \
    --argjson lite_eligible "$lj" \
    --argjson strict_signals "[$signals_json]" \
    --argjson reductions_allowed "$allowed_json" \
    --arg recorded_at "$ts" --arg runner "risk-profile.sh" \
    '{schema_version:$schema_version,fid:$fid,computed:$computed,effective:$effective,
      user_floor:(if $floor=="" then null else $floor end),
      mode:$mode,
      signals:{strict:$strict_signals,lite_eligible:$lite_eligible,docs_only:$docs_only,
               impl_files:$impl_files,parallel_batch:$parallel_batch,irreversible:$irreversible},
      sources:{spec:(".specops/"+$fid+"/spec.md"),
               tasks:(".specops/"+$fid+"/tasks.md"),diff_ref:"HEAD"},
      reductions_allowed:$reductions_allowed,reductions_applied:[],
      recorded_at:$recorded_at,runner:$runner}' > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$target"

  if [ -f "$METRIC_SH" ]; then
    bash "$METRIC_SH" --fid "$fid" --phase risk-profile --verdict PASS --finding-severity none 2>/dev/null || true
  fi

  printf 'RISK_PROFILE: computed=%s effective=%s mode=live\n' "$computed" "$effective"
  printf '%s\n' "$effective"

  # ── §lite × strict 승격 가드 (H1, 20260806) ────────────────────────────────
  # specifying-ko:122·131 의 `★ strict 승격 가드` 는 산문(모델의 키워드 판단)뿐이었다.
  # lite 는 clarify·plan 을 **이미 건너뛴 뒤** decompose 에 도달하므로, strict 가 뒤늦게
  # 드러나도 되돌릴 게이트가 없었다 — 잃어버린 clarify·plan 은 스스로 돌아오지 않는다.
  #
  # self-detect 인 이유: `--lite-guard` 류 플래그 설계면 플래그를 안 넘기는 것으로 우회된다.
  #   spec.md 의 `**§lite**: true`(specifying-ko Step 6 이 강제 기재)를 직접 읽는다.
  # 범위 한정: §lite 만. `§유형: trivial` 단독은 제외 — public_api 가 "엔드포인트" 한 단어에
  #   걸리므로 최빈 경로인 trivial 까지 묶으면 false-block 생성기가 된다.
  # 자동 해제: plan.md 가 생기면(=승격 완료) 가드 무발화 — 영구 차단 방지.
  # 주권 탈출구: env + **사유 병기 필수**(SPECOPS_GOVERNANCE_BYPASS 규약 동형).
  #   마커 파일이 아닌 env 인 이유 — 파일은 모델이 쓸 수 있어 자기발급 면제표가 된다.
  # 강도: rc=3 은 **기계 탐지**이지 하드 차단이 아니다 (emit-context.sh fail-fast 와 동급 —
  #   체인 레벨 강제). 판정 불가(spec.md 부재 등)는 fail-open.
  local _spec="$fid_dir/spec.md"
  if [ "$effective" = "strict" ] && [ -f "$_spec" ] \
     && grep -qE '^\*\*§lite\*\*:[[:space:]]*true' "$_spec" 2>/dev/null \
     && [ ! -f "$fid_dir/plan.md" ]; then
    if [ "${SPECOPS_LITE_STRICT_OVERRIDE:-}" = "1" ] && [ -n "${SPECOPS_LITE_STRICT_REASON:-}" ]; then
      [ -f "$METRIC_SH" ] && bash "$METRIC_SH" --fid "$fid" --phase lite-strict-override \
        --verdict WAIVED --finding-severity high 2>/dev/null || true
      # 사유는 risk-profile.json 에 남긴다 — metrics.jsonl 은 원문을 받지 않는다(스키마 식별자만).
      #   종전엔 '사유 기록됨' 이라 출력만 하고 어디에도 저장하지 않아, 우회가 오탐 때문인지 사후에 알 수 없었다.
      if jq --arg r "$SPECOPS_LITE_STRICT_REASON" --arg at "$ts" --arg sig "${strict_signals:-}" \
           '.lite_strict_override={reason:($r|gsub("[\n\r\t]";" ")|.[0:200]),signals:$sig,recorded_at:$at}' \
           "$target" > "$tmp" 2>/dev/null && mv "$tmp" "$target"; then
        printf 'LITE-STRICT-GUARD: override (사유 기록됨) — lite 유지\n' >&2
      else
        rm -f "$tmp"
        printf 'LITE-STRICT-GUARD: override — lite 유지 (사유 기록 실패: risk-profile.json 갱신 불가)\n' >&2
      fi
      return 0
    fi
    # 유지보수 lite 는 제자리 승격을 해도 analyzing 이 mini 로 남는다 — 풀 분석이 필요하면 /maintain 재진입이다.
    local _maint_note=""
    grep -qE '^\*\*§유형\*\*:[[:space:]]*유지보수' "$_spec" 2>/dev/null && _maint_note='
              유지보수 FID: 제자리 승격은 분석이 mini(대상·직접 호출자)로 남습니다 — 풀 영향 분석이 필요하면 /maintain 으로 재진입하세요.'
    [ -f "$METRIC_SH" ] && bash "$METRIC_SH" --fid "$fid" --phase lite-strict-guard \
      --verdict FAIL --finding-severity high 2>/dev/null || true
    cat >&2 <<EOF
LITE-STRICT-GUARD: §lite FID 인데 위험 프로파일이 strict 입니다 (신호: ${strict_signals:-none}).
  lite 는 clarify·plan 을 이미 건너뛴 상태라 이대로 진행하면 고위험 변경이 설계 검토 없이 구현됩니다.

  승격(권장): specops-ko:clarifying-ko → specops-ko:planning-ko 수행 후 decomposing 재진입.
              plan.md 가 생기면 본 가드는 자동 해제됩니다.${_maint_note}
  사용자 주권 우회(사유 병기 필수):
              SPECOPS_LITE_STRICT_OVERRIDE=1 SPECOPS_LITE_STRICT_REASON='<한 줄 사유>' <명령>
EOF
    return 3
  fi
  return 0
}

rp::show() {
  local fid="$1" state="$SPECOPS/$fid/risk-profile.json"
  [ -f "$state" ] || { echo "risk-profile: not recorded" >&2; return 1; }
  jq -r '"\(.effective) (computed=\(.computed), mode=\(.mode))"' "$state"
}

# source 해서 함수만 쓰는 호출자(quick-scope.sh — rp::detect_strict_signals)는 여기서 돌아간다. 직접 실행이면 그대로 진행한다.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

action="${1:-}"; fid="${2:-}"
case "$action" in
  compute)
    [ -n "$fid" ] || { echo "usage: $0 compute <FID> [--floor standard|strict]" >&2; exit 1; }
    shift 2
    floor=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --floor) floor="${2:-}"; shift 2 ;;
        *) echo "risk-profile: unknown option: $1" >&2; exit 1 ;;
      esac
    done
    rp::compute "$fid" "$floor"
    ;;
  show)
    [ -n "$fid" ] || { echo "usage: $0 show <FID>" >&2; exit 1; }
    rp::show "$fid"
    ;;
  *)
    echo "usage: $0 {compute <FID> [--floor …]|show <FID>}" >&2
    exit 1
    ;;
esac
