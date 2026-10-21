#!/usr/bin/env bash
# check-api-contract.sh — IF 설계서(api-spec.md)의 계약 빈칸·형식을 판정한다 (읽기 전용 · 경고 전용)
#   FID 20261021-api-contract-check · 전문가 로드맵 3번 분야(API 계약) FID-1
#
# Usage: check-api-contract.sh <FID>                      # .specops/memory/api-spec.md · git 추적 중이면 분기점 이후 바뀐 표 행만
#        check-api-contract.sh --spec <경로> [--all-rows]  # 지정 문서 · 표 행 전부
#
# 출력 첫 줄: API-CONTRACT: OK | WARN | SKIP | 판정 불가 — 그 아래 줄은 두 칸 들여쓰기
#   [경로] <METHOD> <path> — 리소스 마디가 동사(create·get·update·delete·remove·list·fetch)로 시작 / 리소스 중첩 3단계 이상
#          (`/api` 접두·`v1` 같은 버전 마디·`:id`·`{id}` 는 리소스로 세지 않는다)
#   [명명] 경로 마디에 snake_case 와 camelCase 가 섞였다(예시 두 개)
#   [상태코드] <METHOD> <path> — 상태코드 칸이 비었다 / POST 에 201·202·200 없음 / DELETE 에 204·202·200 없음
#   [페이지] 목록 엔드포인트(GET 컬렉션)가 있는데 「목록 정책」의 최대 크기가 없다
#   [멱등] 상태를 바꾸는 엔드포인트가 「멱등 정책」에 경로로도, 전체 적용 문장(모든·나머지·전체)으로도 언급되지 않았다
#   [미정] <칸> — 오류 형식·오류 코드·버전 전략·rate limit 칸이 비었거나 자리표시자(<…>)다
#   [건너뜀] <규칙> — 그 규칙의 칸이 문서에 없다(옛 문서 — 경고하지 않는다)
#   [범위] 전체 행 — api-spec 이 git 추적 밖이라 바뀐 행을 가리지 못했다
# Exit: 0 = 판정함(위반이 있어도 0)·SKIP · 1 = 사용 오류 · 2 = 판정 불가(python3 없음 · 문서를 읽지 못함)
#
# 막지 않는다: run-verification.sh 가 evidence.md `### api-contract` 에 남기고 경고만 낸다(VERIFY 판정·종료 코드 불변).
#   specifying-ko Step 5.6 이 api-spec 을 고친 직후에도 불러 경고를 보여 준다.
# 칸이 없으면 그 규칙은 건너뛴다 — 칸을 정한 템플릿(templates/api-spec.md)을 쓰기 전 문서를 경고로 덮지 않는다.
#   그래서 옛 문서의 첫 줄은 SKIP 이 아니라 `OK (… 건너뜀 N)` 이다. SKIP 은 판정할 칸이 하나도 없을 때만이다.
# 설계안과 다르게 정한 것(20261021 사용자 승인): ① "복수형이 아닌 컬렉션" 규칙은 넣지 않는다 — 영어 복수형 판정은
#   /me·/health·/search·/status·/data 같은 정상 경로를 오탐하고, 차단 승격 조건이 "실사용 오탐 0" 이다(판단은 API 전문가 몫).
#   ② 성공 코드는 POST 201 외에 202(비동기 접수)·200(생성이 아닌 동작)을, DELETE 204·200 외에 202 를 허용한다 — 모두 정상 설계다.
# 바뀐 행 한정은 [경로]·[상태코드] 에만 적용된다. [명명]·[페이지]·[멱등]·[미정] 은 문서 전체의 성질이라 늘 문서 전체를 본다.
# 표 행 규칙(경로·상태코드)은 §1 Markdown 엔드포인트 표만 본다. OpenAPI·GraphQL·RPC 본문은 해석하지 않는다(정책 칸 규칙만 돈다).
# `<!-- specops:example:start -->` … `end` 안의 예시 행은 보지 않는다.
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
SPEC=""; FID=""; ALL=0
usage() { echo "usage: check-api-contract.sh <FID> | --spec <경로> [--all-rows]" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)     [ $# -ge 2 ] && [ -z "$SPEC" ] && [ -z "$FID" ] || usage; SPEC="$2"; shift 2 ;;
    --all-rows) ALL=1; shift ;;
    -*|"")      usage ;;
    *)          [ -z "$FID" ] && [ -z "$SPEC" ] || usage; FID="$1"; shift ;;
  esac
done
[ -n "$FID" ] || [ -n "$SPEC" ] || usage
if [ -n "$FID" ]; then
  printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || { echo "check-api-contract: FID 형식 오류: '$FID'" >&2; exit 1; }
  SPEC="$SPECOPS/memory/api-spec.md"
fi

cant() { echo "API-CONTRACT: 판정 불가 ($1)"; exit 2; }
if [ ! -e "$SPEC" ]; then
  [ -L "$SPEC" ] && cant "api-spec 을 따라갈 수 없는 심볼릭 링크: $SPEC"
  echo "API-CONTRACT: SKIP (api-spec.md 부재 — API 가 없는 프로젝트의 정상 경로)"; exit 0
fi
[ -r "$SPEC" ] || cant "api-spec 을 읽을 수 없음: $SPEC"
command -v python3 >/dev/null 2>&1 || cant "python3 없음"

# ── 바뀐 행 (FID 모드) — 분기점은 기본 브랜치와의 merge-base 다 ──
#   review-base.sha 는 쓰지 않는다: api-spec 은 구현 전(Step 5.6 · /start-all Phase 2.5-F)에 커밋되고 review-base 는 그 뒤에
#   기록되므로(start-all Phase 3), review-base 를 쓰면 이 FID 가 더한 엔드포인트가 하나도 안 보인다(Phase C 프로브 F4).
#   저장소는 api-spec 이 있는 곳에서 구한다 — 다른 worktree 에서 불러도 메인의 추적 여부로 판정한다.
#   api-spec 이 git 추적 밖이거나(.specops 를 ignore 하는 저장소) 분기점을 못 구하면 전체 행을 보고 [범위] 줄로 알린다.
CHANGED=""; SCOPE=all
if [ -n "$FID" ] && [ "$ALL" -eq 0 ]; then
  SCOPE=untracked   # 아래에서 바뀐 행을 구하면 changed 로 바뀐다
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/specops-apic.XXXXXX") || cant "임시 디렉터리 생성 실패"
  _AC_TMP="$TMP"; trap 'rm -rf "$_AC_TMP"' EXIT
  SPEC_ABS="$(cd "$(dirname "$SPEC")" && pwd)/$(basename "$SPEC")"
  top=$(git -C "$(dirname "$SPEC_ABS")" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$top" ] && git -C "$top" ls-files --error-unmatch -- "$SPEC_ABS" >/dev/null 2>&1; then
    base=""
    b=$(git -C "$top" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
    [ -n "$b" ] || { git -C "$top" show-ref -q --verify refs/heads/main && b=main; }
    [ -n "$b" ] || { git -C "$top" show-ref -q --verify refs/heads/master && b=master; }
    [ -n "$b" ] && base=$(git -C "$top" merge-base HEAD "$b" 2>/dev/null || true)
    if [ -n "$base" ]; then
      CHANGED="$TMP/changed"
      # 파일로 받고 종료 코드를 따로 본다 — 파이프는 git 의 실패를 "바뀐 행 없음"으로 읽게 만든다
      git -C "$top" diff --no-ext-diff -U0 "$base" -- "$SPEC_ABS" > "$TMP/diff" 2>/dev/null || cant "git diff 실패(분기점 $base)"
      sed -n 's/^+//p' "$TMP/diff" | grep -v '^++ ' > "$CHANGED" || true
      SCOPE=changed
    fi
  fi
fi

python3 - "$SPEC" "$SCOPE" "${CHANGED:-}" <<'PY'
import re, sys
spec, scope, changed_path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    text = open(spec, encoding="utf-8").read()
except Exception as e:
    print(f"API-CONTRACT: 판정 불가 (api-spec 을 읽지 못함: {e})"); sys.exit(2)
changed = None
if scope == "changed":
    changed = set(l.rstrip("\n").strip() for l in open(changed_path, encoding="utf-8", errors="replace"))

# 예시 블록·코드 펜스 밖의 줄만 본다 — 펜스는 CommonMark 처럼 연 문자와 같은 문자, 연 길이 이상으로만 닫힌다
#   (4백틱 펜스 안의 3백틱 줄은 닫는 줄이 아니다). 끝까지 닫히지 않으면 판정 불가 — 그 뒤를 "칸 없음"으로 위장하지 않는다.
lines, ex, fence, fence_at = [], False, None, 0
for no, raw in enumerate(text.splitlines(), 1):
    s = raw.strip()
    if s.startswith("<!-- specops:example:start"): ex = True; continue
    if s.startswith("<!-- specops:example:end"): ex = False; continue
    m = re.match(r"^(`{3,}|~{3,})", s)
    if m:
        tok = m.group(1)
        if fence is None: fence, fence_at = tok, no
        elif tok[0] == fence[0] and len(tok) >= len(fence) and s == tok: fence = None
        lines.append(("", True)); continue
    lines.append((raw, ex or fence is not None))
if fence is not None:
    print(f"API-CONTRACT: 판정 불가 (닫히지 않은 코드 펜스 — {fence_at}행부터 문서 끝까지)"); sys.exit(2)

PH = re.compile(r"<[^<>]{1,80}>")
def section(title_re):
    """제목이 title_re 와 맞는 절의 본문(다음 같은·상위 제목 전까지). 없으면 None."""
    out, cur = None, None
    for raw, hidden in lines:
        m = re.match(r"^(#{2,4})\s+(.*)$", raw)
        if m and not hidden:
            lvl = len(m.group(1))
            if cur is not None and lvl <= cur: break
            if re.search(title_re, m.group(2)): cur, out = lvl, []; continue
        if cur is not None and not hidden: out.append(raw)
    return None if out is None else "\n".join(out)
def field(label_re):
    """`- **라벨**: 값` 줄의 값. 없으면 None."""
    for raw, hidden in lines:
        if hidden: continue
        m = re.match(r"^\s*[-*]\s*\*\*(.+?)\*\*\s*[:：]\s*(.*)$", raw)
        if m and re.search(label_re, m.group(1), re.I): return m.group(2).strip()
    return None
def unset(v): return v is None or v == "" or PH.fullmatch(v.strip()) is not None or v.strip() in ("-", "—", "TBD", "TODO")

# ── §1 엔드포인트 표 ──
def cells_of(raw):
    """표 한 줄의 칸 — GFM 의 이스케이프 파이프(`\\|`, 예: TS 유니언 `User \\| null`)는 칸 구분자가 아니다."""
    body = raw.strip().strip("|").replace("\\|", "\0")
    return [c.replace("\0", "|").strip() for c in body.split("|")]
def bare(c): return re.sub(r"^[`*_ ]+|[`*_ ]+$", "", c)   # 백틱·굵게·기울임으로 꾸민 칸의 알맹이
rows, has_status, header, n_tables, n_unread = [], False, None, 0, 0
for raw, hidden in lines:
    if not raw.lstrip().startswith("|"): header = None; continue   # 표가 끝나면 머리글을 잊는다
    if hidden: continue                                            # 예시 블록·펜스 안의 표 행은 보지 않는다
    cells = cells_of(raw)
    if header is None:
        low = [bare(c).lower() for c in cells]
        if any(c in ("method", "메서드") for c in low) and any(c in ("path", "경로") for c in low):
            header = low; n_tables += 1; has_status = has_status or any(("status" in c) or ("상태" in c) for c in low)
        continue
    if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c): continue
    rec = dict(zip(header, cells))
    meth = bare(rec.get("method") or rec.get("메서드") or "").upper()
    path = bare(rec.get("path") or rec.get("경로") or "")
    if not re.fullmatch(r"GET|POST|PUT|PATCH|DELETE", meth) or not path.startswith("/"): n_unread += 1; continue
    st = next((rec[k] for k in rec if ("status" in k) or ("상태" in k)), None)
    rows.append((meth, path, st, raw.strip()))

def in_scope(r): return changed is None or r[3] in changed
VERB = re.compile(r"^(create|get|update|delete|remove|list|fetch)([A-Z_-]|$)")
def literals(path):
    segs = [s for s in path.split("?")[0].split("/") if s]
    if segs and segs[0].lower() == "api": segs = segs[1:]          # /api 접두는 리소스가 아니다
    return [s for s in segs if not (s.startswith(":") or s.startswith("{") or re.fullmatch(r"v\d+", s))]

out, skipped = [], []
for meth, path, st, raw in rows:
    if not in_scope((meth, path, st, raw)): continue
    lit = literals(path)
    verbs = [s for s in lit if VERB.match(s)]
    if verbs: out.append(f"[경로] {meth} {path} — 리소스 마디가 동사({verbs[0]}) — 동사는 메서드로 표현한다")
    if len(lit) >= 3: out.append(f"[경로] {meth} {path} — 리소스 중첩 {len(lit)}단계(2단계 이하 권장)")
# 명명은 문서 전체에서 본다 — 섞임은 행 하나가 아니라 문서의 성질이다
segs = sorted({s for _, p, _, _ in rows for s in literals(p)})
snake = [s for s in segs if "_" in s]; camel = [s for s in segs if re.search(r"[a-z][A-Z]", s)]
if snake and camel: out.append(f"[명명] 경로 마디에 snake_case 와 camelCase 가 섞였다 — 예: {snake[0]} · {camel[0]}")

if n_tables == 0: skipped.append("경로·상태코드(§1 Markdown 엔드포인트 표 없음 — OpenAPI·GraphQL·RPC 본문은 해석하지 않는다)")
elif not rows: skipped.append(f"경로·상태코드(엔드포인트 표에 읽을 수 있는 행이 없다 — 메서드·경로 칸을 못 읽은 행 {n_unread}개)")
elif not has_status: skipped.append("상태코드(엔드포인트 표에 상태코드 열 없음)")
for meth, path, st, raw in rows:
    if not has_status or not in_scope((meth, path, st, raw)): continue
    codes = set(re.findall(r"\b([1-5]\d\d)\b", st or ""))
    if not codes: out.append(f"[상태코드] {meth} {path} — 상태코드 칸이 비었다"); continue
    if meth == "POST" and not codes & {"200", "201", "202"}: out.append(f"[상태코드] {meth} {path} — 성공 코드(201·202·200) 없음")
    if meth == "DELETE" and not codes & {"200", "204", "202"}: out.append(f"[상태코드] {meth} {path} — 성공 코드(204·202·200) 없음")

lists = [(m, p) for m, p, _, _ in rows if m == "GET" and not re.search(r"/(:[^/]+|\{[^/]+\})$", p)]
listpol = section(r"목록 정책")
if listpol is None:
    if lists: skipped.append("페이지(「목록 정책」 절 없음)")
elif lists:
    mx = re.search(r"^\s*[-*]?\s*(?:\*\*)?최대[^:：*\n]*(?:\*\*)?\s*[:：]\s*(.+)$", listpol, re.M)
    if not mx or unset(mx.group(1)) or not re.search(r"\d", mx.group(1)):
        out.append(f"[페이지] 목록 엔드포인트 {len(lists)}개({lists[0][0]} {lists[0][1]} …) — 「목록 정책」의 최대 페이지 크기가 없다")

writes = [(m, p) for m, p, _, _ in rows if m in ("POST", "PUT", "PATCH", "DELETE")]
idem = section(r"멱등 정책")
if idem is None:
    if writes: skipped.append("멱등(「멱등 정책」 절 없음)")
elif writes:
    filled = [l for l in idem.splitlines() if l.strip() and not unset(l.strip(" -*"))]
    blanket = any(re.search(r"모든|나머지|전체|\ball\b", l, re.I) for l in filled)
    miss = [(m, p) for m, p in writes if not any(p in l for l in filled)] if not blanket else []
    if not filled:
        out.append(f"[멱등] 상태를 바꾸는 엔드포인트 {len(writes)}개 — 「멱등 정책」이 비었다(Idempotency-Key 를 받는지 · 재시도 불안전인지)")
    elif miss:
        ex_ = " · ".join(f"{m} {p}" for m, p in miss[:3]) + (" …" if len(miss) > 3 else "")
        out.append(f"[멱등] 상태를 바꾸는 엔드포인트 {len(miss)}개가 「멱등 정책」에 없다(경로로도, 모든·나머지 같은 전체 적용 문장으로도) — {ex_}")

for label, rx, sec in (("오류 형식", r"오류 형식|에러 형식", None), ("오류 코드", r"오류 코드|에러 코드", "오류 코드 카탈로그"),
                       ("버전 전략", r"버전 전략", None), ("rate limit", r"rate limit", None)):
    v = field(rx)
    body = section(sec) if sec else None
    if v is None and body is None: skipped.append(f"{label}(칸 없음)"); continue
    if v is not None and unset(v): out.append(f"[미정] {label} — 칸이 비었거나 자리표시자({v or '빈 값'})")
    if body is not None and not re.search(r"^\s*\|\s*[`*]*[A-Z][A-Z0-9_]{2,}[`*]*\s*\|", body, re.M):
        out.append(f"[미정] {label} — 「{sec}」 표에 코드 행이 없다")

if not out and not rows and all(field(r) is None for r in (r"오류 형식|에러 형식", r"버전 전략", r"rate limit")) and listpol is None and idem is None:
    print("API-CONTRACT: SKIP (판정할 칸이 없다 — 엔드포인트 표·정책 칸 모두 부재)"); sys.exit(0)
n_rows = sum(1 for r in rows if in_scope(r))
head = "WARN" if out else "OK"
print(f"API-CONTRACT: {head} (위반 {len(out)} · 엔드포인트 {n_rows}/{len(rows)} · 건너뜀 {len(skipped)})")
for l in out: print("  " + l)
for s in skipped: print("  [건너뜀] " + s)
if scope == "untracked": print("  [범위] 전체 행 — api-spec 이 git 추적 밖이거나 분기점을 구하지 못해 바뀐 행을 가리지 못했다")
sys.exit(0)
PY
