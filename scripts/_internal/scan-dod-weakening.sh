#!/usr/bin/env bash
# scan-dod-weakening.sh — 변경(diff)에서 품질 기준을 낮추는 후보를 결정론으로 뽑는다 (20261113-dod-weakening-scan)
# Usage: scan-dod-weakening.sh [--base <ref>]      (기본 origin/main · 어느 폴더에서 불러도 저장소 전체를 본다 · read-only)
#
# 대상: merge-base(<ref>, HEAD) 부터 지금 작업 트리까지의 변경 + 추적하지 않는 새 파일.
# 출력: 후보 1건에 1줄 `<클래스>\t<파일>:<줄>\t<패턴>`, 마지막 줄은 항상 요약
#   `DOD-WEAKENING: candidates=N suppress=a skip=b assert=c threshold=d disable=e stub=f base=<sha7> files=<n>`
#   - files 는 본 변경 파일 수다. candidates=0 이어도 files=0 이면 "약화 없음"이 아니라 "본 것이 없음"이다.
#   - 줄 원문은 출력하지 않는다(패턴 이름·숫자만) — 후보 줄에 비밀값이 있어도 새지 않게.
# 종료 코드: 0 = 후보 없음 · 1 = 후보 있음 · 2 = 실행 불가(git 저장소 아님 · base 없음 · 사용 오류). **2 를 0 으로 읽지 않는다.**
#
# 클래스 (기준이 내려가는 방향만 — 억제 제거·skip 해제·임계 상향은 조용하다):
#   suppress   추가 줄의 검사 억제 주석(eslint-disable · @ts-ignore · # noqa · nosemgrep …)
#   skip       추가 줄의 테스트 skip 표식 · 테스트 파일 삭제(`<파일>:-  deleted-test-file`)
#   assert     테스트 파일에서 단언 줄이 추가보다 삭제가 많다(`<파일>:-  assertions -R +A`)
#   threshold  같은 줄의 숫자만 바뀌었고 임계가 내려갔거나 타임아웃이 올라갔다(`OLD -> NEW`) — 상한(max…)은 보지 않는다
#   disable    검증 명령 뒤 `|| true` 류 · continue-on-error: true · set +e · --no-verify
#   stub       테스트가 아닌 파일의 미구현 표식 · 빈 catch
# 이 출력은 **후보**이지 판정이 아니다 — 사유·등급은 리뷰어(agents/code-reviewer-ko.md 「기준 약화 탐지」)가 정한다.
# 한계: 줄 단위 패턴이다. 프로젝트 고유 단언 관용구 · 기대 건수 하향 · 여러 줄에 걸친 skip · 파일 이동을 동반한 약화는 못 본다.
#   `*.md` · `.specops/` · node_modules · dist · build · vendor 는 보지 않는다(규칙을 설명하는 산문이 후보를 오염시킨다).
#   스캐너 자신과 그 테스트(정확한 두 경로)도 보지 않는다 — 패턴 글자를 그대로 담고 있다.
# 출처: addyosmani/agent-skills@301b02b skills/constraint-driven-development/references/floor-guard.md (MIT) 의 계약을 bash 로 옮김.
set -u
export LC_ALL=C

BASE="origin/main"
err() { echo "DOD-WEAKENING: ERROR $1" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] && [ -n "$2" ] || err "--base 값 필요"; BASE="$2"; shift 2 ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "알 수 없는 인자: $1" ;;
  esac
done

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || err "git 저장소가 아니다"
[ -n "$TOP" ] && cd "$TOP" || err "git 저장소가 아니다"
MB=$(git merge-base "$BASE" HEAD 2>/dev/null) || err "merge-base 를 구할 수 없다 — base=$BASE"
[ -n "$MB" ] || err "merge-base 를 구할 수 없다 — base=$BASE"

TMP=$(mktemp) || err "임시 파일을 만들 수 없다"
trap 'rm -f "$TMP"' EXIT
# 접두사를 고정한다 — 사용자 설정(diff.noprefix · diff.mnemonicPrefix)이 경로 모양을 바꾸면 파서가 틀린 경로를 낸다
git -c core.quotepath=off -c diff.noprefix=false -c diff.mnemonicPrefix=false diff --no-color --no-ext-diff -M --unified=0 \
    --src-prefix=a/ --dst-prefix=b/ "$MB" -- > "$TMP" 2>/dev/null \
  || err "diff 를 만들 수 없다 — base=$BASE"

# 추적하지 않는 새 파일을 "전부 추가된 diff" 로 이어 붙인다(git diff 는 새 파일을 보지 못한다)
UNTRACKED=$(git -c core.quotepath=off ls-files --others --exclude-standard 2>/dev/null) || err "추적하지 않는 파일 목록을 읽을 수 없다"
MAX_BYTES=1048576   # 이보다 큰 새 파일은 줄 단위 검사 대상이 아니다(생성물·데이터)
while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  printf 'diff --git a/%s b/%s\n+++ b/%s\n' "$f" "$f" "$f" >> "$TMP"
  if [ "$(wc -c < "$f" | tr -d ' ')" -le "$MAX_BYTES" ] && grep -Iq . "$f" 2>/dev/null; then
    printf '@@ -0,0 +1 @@\n' >> "$TMP"
    sed 's/^/+/' "$f" >> "$TMP"
    printf '\n' >> "$TMP"
  fi
done <<< "$UNTRACKED"

awk -v base="$(printf '%s' "$MB" | cut -c1-7)" '
function excluded(p) {
  # 스캐너 자신과 그 테스트는 패턴 글자를 그대로 담고 있어 후보가 아니다(정확한 경로만 — 이름이 비슷한 파일은 본다)
  if (p == "scripts/_internal/scan-dod-weakening.sh" || p == "scripts/tests/test-scan-dod-weakening.sh") return 1
  return p ~ /(^|\/)(node_modules|dist|build|vendor|\.specops)\// || p ~ /\.md$/
}
function istest(p,   b) {
  if (p ~ /(^|\/)(tests?|__tests__|specs?|e2e)\//) return 1
  b = p; sub(/^.*\//, "", b)
  return b ~ /^test[-_]/ || b ~ /[._-](test|spec)\.[A-Za-z0-9]+$/ || b ~ /Tests?\.(java|kt|cs)$/
}
function isassert(s) {
  return s ~ /expect\(/ || s ~ /(^|[^A-Za-z_])assert/ || s ~ /\.should[.( ]/ || s ~ /(^|[ \t])ck "/ || s ~ /require\.(Equal|True|False|NoError|Nil)/
}
# 검증 명령인가 — 명령 자리의 낱말만 본다(templates/test-strategy.md 같은 경로 조각은 아니다)
function isverify(c) {
  return c ~ /(^|[ \t;&|(])(tests?|lint|build|check|verify|pytest|jest|vitest|mocha|tsc|eslint|ruff|mypy|flake8|shellcheck|semgrep|gitleaks|tox|rspec|phpunit)([ \t;&|):]|$)/ \
      || c ~ /run-all(\.sh)?([ \t;&|)]|$)/ || c ~ /(^|[ \t;&|(\/])(gradlew|mvnw)([ \t;&|)]|$)/
}
# diff 머리 줄의 경로 — git 은 공백 든 경로 뒤에 탭을 붙이고, 따옴표·역슬래시 든 경로를 "..." 로 감싼다
function hdrpath(s, pfx) {
  sub(/\t$/, "", s)
  if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2)
  if (index(s, pfx) == 1) s = substr(s, length(pfx) + 1)
  return s
}
function row(cls, loc, pat) { printf "%s\t%s:%s\t%s\n", cls, file, loc, pat; n[cls]++; total++ }
function skel(s) { gsub(/[0-9]+(\.[0-9]+)?/, "#", s); return s }
# 두 줄에서 처음 달라지는 숫자 쌍을 a·b 에, 그 숫자 앞의 글을 pre 에 담는다(없으면 0).
# 임계 낱말은 pre 에서 찾는다 — 같은 줄 뒤쪽의 낱말("bytes":9,"lines":3 의 lines)이 앞 숫자를 임계로 만들지 않게.
function firstdiff(o, w,   x, y) {
  pre = ""
  while (match(o, /[0-9]+(\.[0-9]+)?/)) {
    x = substr(o, RSTART, RLENGTH); o = substr(o, RSTART + RLENGTH)
    if (!match(w, /[0-9]+(\.[0-9]+)?/)) return 0
    y = substr(w, RSTART, RLENGTH); pre = pre substr(w, 1, RSTART - 1); w = substr(w, RSTART + RLENGTH)
    if (x != y) { a = x + 0; b = y + 0; as = x; bs = y; pre = tolower(pre); return 1 }
    pre = pre y
  }
  return 0
}
# 임계 낱말이 든 줄만 짝짓기 대상이다(큰 재작성 diff 에서 줄마다 짝을 찾지 않게)
function iskeyline(s) { s = tolower(s); return s ~ /timeout|cov|threshold|fail[-_]under|branches|lines|functions|statements/ }
# 같은 골격(숫자만 다른 줄)의 삭제 줄과 추가 줄을 나온 순서대로 짝짓는다 — 골격별 줄 세우기라 줄 수에 비례한다
function flush_hunk(   i, k) {
  for (i = 1; i <= na; i++) {
    k = skel(ad[i])
    if (qhead[k] >= qcnt[k]) continue
    qhead[k]++
    if (!firstdiff(rmq[k, qhead[k]], ad[i])) continue
    if (pre ~ /timeout/) { if (b > a) row("threshold", adl[i], as " -> " bs) }
    else if (pre !~ /max/ && pre ~ /cov|threshold|fail[-_]under|branches|lines|functions|statements/) {
      if (b < a) row("threshold", adl[i], as " -> " bs)
    }
  }
  split("", qcnt); split("", qhead); split("", rmq); split("", ad); split("", adl)
  na = 0
}
function flush_file() {
  flush_hunk()
  if (file != "" && !skipf && !deleted && tfile && arm > aad) row("assert", "-", "assertions -" arm " +" aad)
  arm = 0; aad = 0
}
function added(s, ln,   t) {
  # suppress
  if      (index(s, "eslint-disable"))     row("suppress", ln, "eslint-disable")
  else if (index(s, "@ts-ignore"))         row("suppress", ln, "@ts-ignore")
  else if (index(s, "@ts-expect-error"))   row("suppress", ln, "@ts-expect-error")
  else if (index(s, "@ts-nocheck"))        row("suppress", ln, "@ts-nocheck")
  else if (index(s, "# noqa"))             row("suppress", ln, "# noqa")
  else if (index(s, "# type: ignore"))     row("suppress", ln, "# type: ignore")
  else if (index(s, "pylint: disable"))    row("suppress", ln, "pylint: disable")
  else if (index(s, "# nosec"))            row("suppress", ln, "# nosec")
  else if (index(s, "//nolint"))           row("suppress", ln, "//nolint")
  else if (index(s, "#[allow("))           row("suppress", ln, "#[allow(")
  else if (index(s, "shellcheck disable=")) row("suppress", ln, "shellcheck disable=")
  else if (index(s, "istanbul ignore"))    row("suppress", ln, "istanbul ignore")
  else if (index(s, "c8 ignore"))          row("suppress", ln, "c8 ignore")
  else if (index(s, "nosemgrep"))          row("suppress", ln, "nosemgrep")
  else if (index(s, "gitleaks:allow"))     row("suppress", ln, "gitleaks:allow")
  else if (index(s, "Stryker disable"))    row("suppress", ln, "Stryker disable")
  else if (index(s, "@SuppressWarnings"))  row("suppress", ln, "@SuppressWarnings")
  else if (index(s, "rubocop:disable"))    row("suppress", ln, "rubocop:disable")
  # skip
  if      (index(s, ".skip("))             row("skip", ln, ".skip(")
  else if (index(s, ".todo("))             row("skip", ln, ".todo(")
  else if (s ~ /(^|[^A-Za-z0-9_])xit\(/)   row("skip", ln, "xit(")
  else if (index(s, "xdescribe("))         row("skip", ln, "xdescribe(")
  else if (index(s, "@pytest.mark.skip"))  row("skip", ln, "@pytest.mark.skip")
  else if (index(s, "@unittest.skip"))     row("skip", ln, "@unittest.skip")
  else if (index(s, "t.Skip("))            row("skip", ln, "t.Skip(")
  else if (index(s, "@Disabled"))          row("skip", ln, "@Disabled")
  else if (s ~ /@Ignore([^A-Za-z]|$)/)     row("skip", ln, "@Ignore")
  # disable
  if      (index(s, "continue-on-error: true")) row("disable", ln, "continue-on-error: true")
  else if (s ~ /(^|[; \t])set \+e([; \t]|$)/)   row("disable", ln, "set +e")
  else if (s ~ /git[^|;&]*[ \t](commit|push)[^|;&]*--no-verify/) row("disable", ln, "--no-verify")
  else if (match(s, /\|\|[ \t]*(true|:|exit 0)([^A-Za-z0-9_]|$)/) && isverify(substr(s, 1, RSTART - 1)))
                                                row("disable", ln, "|| true")
  # stub — 테스트 파일의 미구현 표식은 흔한 가짜 구현이라 보지 않는다
  if (!tfile) {
    t = tolower(s)
    if      (index(s, "NotImplementedError"))     row("stub", ln, "NotImplementedError")
    else if (index(s, "NotImplementedException")) row("stub", ln, "NotImplementedException")
    else if (index(t, "not implemented"))         row("stub", ln, "Not implemented")
    else if (index(s, "todo!("))                  row("stub", ln, "todo!(")
    else if (index(s, "unimplemented!("))         row("stub", ln, "unimplemented!(")
    else if (s ~ /catch[ \t]*(\([^)]*\))?[ \t]*\{[ \t]*\}/) row("stub", ln, "empty catch")
    else if (s ~ /except[^:]*:[ \t]*pass[ \t]*$/)  row("stub", ln, "except: pass")
  }
}
/^diff --git / { flush_file(); inhdr = 1; file = ""; oldpath = ""; deleted = 0; skipf = 1; tfile = 0; files++; next }
inhdr && /^--- / { oldpath = hdrpath(substr($0, 5), "a/"); next }
inhdr && /^\+\+\+ / {
  file = substr($0, 5)
  if (file == "/dev/null") { file = oldpath; deleted = 1 } else file = hdrpath(file, "b/")
  skipf = excluded(file); tfile = istest(file)
  if (deleted && !skipf && tfile) row("skip", "-", "deleted-test-file")
  next
}
/^@@ / {
  flush_hunk(); inhdr = 0
  h = $0; sub(/^@@ -[0-9,]+ \+/, "", h); sub(/[, ].*$/, "", h); newln = h + 0
  next
}
inhdr { next }
skipf || deleted { next }
/^\+/ {
  s = substr($0, 2)
  added(s, newln)
  if (tfile && isassert(s)) aad++
  if (iskeyline(s)) { na++; ad[na] = s; adl[na] = newln }
  newln++; next
}
/^-/ {
  s = substr($0, 2)
  if (tfile && isassert(s)) arm++
  if (iskeyline(s)) { k = skel(s); qcnt[k]++; rmq[k, qcnt[k]] = s }
  next
}
END {
  flush_file()
  printf "DOD-WEAKENING: candidates=%d suppress=%d skip=%d assert=%d threshold=%d disable=%d stub=%d base=%s files=%d\n", \
    total, n["suppress"], n["skip"], n["assert"], n["threshold"], n["disable"], n["stub"], base, files
  exit (total > 0 ? 1 : 0)
}
' "$TMP"
