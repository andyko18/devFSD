#!/usr/bin/env bash
# check-security-design.sh — IF·테이블 설계서의 보안 결정 칸과 문서로 보이는 보안 설계 결함을 판정한다 (읽기 전용 · 경고 전용)
#   FID 20261021-security-design-checker · 전문가 로드맵 4번 분야(보안 설계) FID-S1
#
# Usage: check-security-design.sh <FID>
#          api-spec=.specops/memory/api-spec.md · data-model=.specops/memory/data-model.md
#          plan=.specops/<FID>/plan.md · tasks=.specops/<FID>/tasks.md · api-spec 이 git 추적 중이면 분기점 이후 바뀐 표 행만
#        check-security-design.sh --spec <api-spec> [--data-model <경로>] [--plan <경로>] [--tasks <경로>] [--all-rows]
#
# 출력 첫 줄: SECURITY-DESIGN: OK | WARN | SKIP | 판정 불가 — 그 아래 줄은 두 칸 들여쓰기
#   [인증] <METHOD> <path> — 엔드포인트 표의 Auth 칸이 비었다(공개면 `없음(공개)` 으로 적는다)
#   [URL 민감정보] <METHOD> <path> — <이름> — 경로·쿼리 파라미터에 토큰·비밀번호·비밀·API 키가 실린다
#   [응답 민감 필드] <METHOD> <path> — <이름> — Response 칸에 비밀번호 해시·재설정 토큰·비밀·개인 키 필드
#   [CORS] 허용 origin `*` 와 credentials 를 함께 쓴다
#   [미정] <칸> — 인증 방식·권한 모델·CORS·CSRF·개인정보 분류·보존·삭제 칸이 비었거나 자리표시자(<…>)다
#   [승인 대상] <기능> — <출처> — 업로드·웹훅 수신·외부 URL 가져오기·LLM 호출 신호가 있는데 「위험 기능 결정」 칸이 비었다
#   [건너뜀] <규칙> — 그 규칙의 칸이 문서에 없다(옛 문서 — 경고하지 않는다)
#   [범위] 전체 행 — api-spec 이 git 추적 밖이라 바뀐 행을 가리지 못했다
# Exit: 0 = 판정함(위반이 있어도 0)·SKIP · 1 = 사용 오류 · 2 = 판정 불가(python3 없음 · 문서를 읽지 못함 · 닫히지 않은 코드 펜스 · git diff 실패)
#
# 막지 않는다: run-verification.sh 가 evidence.md `### security-design` 에 남기고 경고만 낸다(VERIFY 판정·종료 코드 불변).
#   specifying-ko Step 5.6 이 api-spec·data-model 을 고친 직후에도 불러 경고를 보여 준다. 차단 승격은 실사용 오탐 0 확인 뒤 별도 PR.
# 위험 기능 신호는 파일 경로와 엔드포인트 경로에서만 찾는다 — 산문 단어는 신호가 아니다(주제 단어를 변경으로 읽는 오판을 피한다).
#   경로는 마디(/ . _ - 와 camelCase 경계)로 잘라 낱말이 통째로 맞을 때만 신호다(`storage` 안의 rag 는 신호가 아니다).
#   칸을 `해당 없음` 으로 채우면 신호가 있어도 경고하지 않는다(사용자 결정 — 판단은 보안 설계 전문가 몫).
# 바뀐 행 한정은 [인증]·[URL 민감정보]·[응답 민감 필드]·api-spec 행 신호에만 적용된다. [CORS]·[미정] 은 문서 전체의 성질이다.
# 표 행 규칙은 Method·Path 열이 있는 Markdown 표만 본다 — [인증] 은 Auth 열이 있는 표의 행만. OpenAPI·GraphQL·RPC 본문은 해석하지 않는다(그건 보안 설계 전문가 몫).
# `<!-- specops:example:start -->` … `end` 안과 코드 펜스 안은 보지 않는다 — tasks.md 만 예외(outputs 가 YAML 펜스 안에 있다).
#   plan 의 펜스 안(태스크의 테스트 픽스처 코드 등)에 든 `## 2. 파일 구조`·경로는 신호가 아니다.
# 바뀐 행을 구하는 블록은 check-api-contract.sh 와 같다 — 한쪽을 고치면 다른 쪽도 고친다.
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
SPEC=""; FID=""; DM=""; PLAN=""; TASKS=""; ALL=0; EXTRA=0
usage() { echo "usage: check-security-design.sh <FID> | --spec <api-spec> [--data-model <경로>] [--plan <경로>] [--tasks <경로>] [--all-rows]" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)       [ $# -ge 2 ] && [ -z "$SPEC" ] && [ -z "$FID" ] || usage; SPEC="$2"; shift 2 ;;
    --data-model) [ $# -ge 2 ] && [ -z "$DM" ] || usage; DM="$2"; EXTRA=1; shift 2 ;;
    --plan)       [ $# -ge 2 ] && [ -z "$PLAN" ] || usage; PLAN="$2"; EXTRA=1; shift 2 ;;
    --tasks)      [ $# -ge 2 ] && [ -z "$TASKS" ] || usage; TASKS="$2"; EXTRA=1; shift 2 ;;
    --all-rows)   ALL=1; shift ;;
    -*|"")        usage ;;
    *)            [ -z "$FID" ] && [ -z "$SPEC" ] || usage; FID="$1"; shift ;;
  esac
done
[ -n "$FID" ] || [ -n "$SPEC" ] || usage
if [ -n "$FID" ]; then
  [ "$EXTRA" -eq 0 ] || usage   # 문서 경로 지정은 --spec 모드에서만
  printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || { echo "check-security-design: FID 형식 오류: '$FID'" >&2; exit 1; }
  SPEC="$SPECOPS/memory/api-spec.md"; DM="$SPECOPS/memory/data-model.md"
  PLAN="$SPECOPS/$FID/plan.md"; TASKS="$SPECOPS/$FID/tasks.md"
fi

cant() { echo "SECURITY-DESIGN: 판정 불가 ($1)"; exit 2; }
# 있으면 경로를 $1 변수에, 없으면 빈 값을 넣는다 — 따라갈 수 없는 링크·읽을 수 없는 파일은 판정 불가(없는 것으로 위장하지 않는다)
present() {  # $1=변수 이름 $2=경로 $3=문서 이름
  printf -v "$1" '%s' ""
  [ -n "$2" ] || return 0
  if [ ! -e "$2" ]; then
    [ -L "$2" ] && cant "$3 을 따라갈 수 없는 심볼릭 링크: $2"
    return 0
  fi
  [ -r "$2" ] && [ -f "$2" ] || cant "$3 을 읽을 수 없음: $2"
  printf -v "$1" '%s' "$2"
}
present SPEC_P "$SPEC" api-spec; present DM_P "$DM" data-model; present PLAN_P "$PLAN" plan; present TASKS_P "$TASKS" tasks
if [ -z "$SPEC_P" ] && [ -z "$DM_P" ]; then
  echo "SECURITY-DESIGN: SKIP (api-spec.md·data-model.md 부재 — API·스키마가 없는 프로젝트의 정상 경로)"; exit 0
fi
command -v python3 >/dev/null 2>&1 || cant "python3 없음"

# ── 바뀐 행 (FID 모드) — check-api-contract.sh 와 같은 블록: 분기점은 기본 브랜치와의 merge-base 다 ──
CHANGED=""; SCOPE=all
if [ -n "$FID" ] && [ "$ALL" -eq 0 ] && [ -n "$SPEC_P" ]; then
  SCOPE=untracked   # 아래에서 바뀐 행을 구하면 changed 로 바뀐다
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/specops-secd.XXXXXX") || cant "임시 디렉터리 생성 실패"
  _SD_TMP="$TMP"; trap 'rm -rf "$_SD_TMP"' EXIT
  SPEC_ABS="$(cd "$(dirname "$SPEC_P")" && pwd)/$(basename "$SPEC_P")"
  top=$(git -C "$(dirname "$SPEC_ABS")" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$top" ] && git -C "$top" ls-files --error-unmatch -- "$SPEC_ABS" >/dev/null 2>&1; then
    base=""
    b=$(git -C "$top" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
    [ -n "$b" ] || { git -C "$top" show-ref -q --verify refs/heads/main && b=main; }
    [ -n "$b" ] || { git -C "$top" show-ref -q --verify refs/heads/master && b=master; }
    [ -n "$b" ] && base=$(git -C "$top" merge-base HEAD "$b" 2>/dev/null || true)
    if [ -n "$base" ]; then
      CHANGED="$TMP/changed"
      git -C "$top" diff --no-ext-diff -U0 "$base" -- "$SPEC_ABS" > "$TMP/diff" 2>/dev/null || cant "git diff 실패(분기점 $base)"
      sed -n 's/^+//p' "$TMP/diff" | grep -v '^++ ' > "$CHANGED" || true
      SCOPE=changed
    fi
  fi
fi

python3 - "$SPEC_P" "$DM_P" "$PLAN_P" "$TASKS_P" "$SCOPE" "${CHANGED:-}" <<'PY'
import re, sys
spec_p, dm_p, plan_p, tasks_p, scope, changed_path = sys.argv[1:7]

def cant(msg):
    print(f"SECURITY-DESIGN: 판정 불가 ({msg})"); sys.exit(2)
def read(p, what):
    if not p: return None
    try: return open(p, encoding="utf-8").read()
    except Exception as e: cant(f"{what} 을 읽지 못함: {e}")
def visible(text, what, strict=True):
    """(줄, 숨김) 목록 — 예시 블록·코드 펜스 안은 숨김. 펜스는 연 문자와 같은 문자, 연 길이 이상으로만 닫힌다.
    strict=False 면 닫히지 않은 펜스를 판정 불가로 보지 않는다(plan — 펜스 뒤를 숨긴 채 신호만 덜 읽는다)."""
    if text is None: return []
    out, ex, fence, at = [], False, None, 0
    for no, raw in enumerate(text.splitlines(), 1):
        s = raw.strip()
        if s.startswith("<!-- specops:example:start"): ex = True; continue
        if s.startswith("<!-- specops:example:end"): ex = False; continue
        m = re.match(r"^(`{3,}|~{3,})", s)
        if m:
            tok = m.group(1)
            if fence is None: fence, at = tok, no
            elif tok[0] == fence[0] and len(tok) >= len(fence) and s == tok: fence = None
            out.append(("", True)); continue
        out.append((raw, ex or fence is not None))
    if fence is not None and strict: cant(f"{what} 의 닫히지 않은 코드 펜스 — {at}행부터 문서 끝까지")
    return out

api = visible(read(spec_p, "api-spec"), "api-spec")
dm = visible(read(dm_p, "data-model"), "data-model")
plan = visible(read(plan_p, "plan"), "plan", strict=False) if plan_p else None
tasks = read(tasks_p, "tasks")
changed = None
if scope == "changed":
    changed = set(l.rstrip("\n").strip() for l in open(changed_path, encoding="utf-8", errors="replace"))

PH = re.compile(r"<[^<>]{1,200}>")
def unset(v): return v is None or v.strip() in ("", "-", "—", "–", "TBD", "TODO") or PH.fullmatch(v.strip()) is not None
def field(lines, label_re):
    """`- **라벨**: 값` 줄의 값(라벨 전체가 label_re 와 맞을 때). 없으면 None."""
    for raw, hidden in lines:
        if hidden: continue
        m = re.match(r"^\s*[-*]\s*\*\*(.+?)\*\*\s*[:：]\s*(.*)$", raw)
        if m and re.fullmatch(label_re, m.group(1).strip(), re.I): return m.group(2).strip()
    return None
def section(lines, title_re):
    """제목이 title_re 와 맞는 절의 줄 목록(다음 같은·상위 제목 전까지). 없으면 None."""
    out, cur = None, None
    for raw, hidden in lines:
        m = re.match(r"^(#{2,4})\s+(.*)$", raw)
        if m and not hidden:
            lvl = len(m.group(1))
            if cur is not None and lvl <= cur: break
            if re.search(title_re, m.group(2)): cur, out = lvl, []; continue
        if cur is not None: out.append((raw, hidden))
    return out
def words(s):
    """camelCase·snake·kebab·경로를 소문자 낱말로 자른다."""
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    s = re.sub(r"([A-Z]+)([A-Z](?!s(?![a-z]))[a-z])", r"\1_\2", s)   # 약어 복수형(LLMs)은 자르지 않는다
    return [w for w in re.split(r"[^a-z0-9]+", s.lower()) if w]

# ── §1 엔드포인트 표 ──
def cells_of(raw):
    body = raw.strip().strip("|").replace("\\|", "\0")
    return [c.replace("\0", "|").strip() for c in body.split("|")]
def bare(c): return re.sub(r"^[`*_ ]+|[`*_ ]+$", "", c)
def col(rec, *names):
    for k in rec:
        if any(n in k for n in names): return rec[k]
    return None
rows, header, n_tables, has_auth, t_auth = [], None, 0, False, False
for raw, hidden in api:
    if not raw.lstrip().startswith("|"): header = None; continue
    if hidden: continue
    cells = cells_of(raw)
    if header is None:
        low = [bare(c).lower() for c in cells]
        if any(c in ("method", "메서드") for c in low) and any(c in ("path", "경로") for c in low):
            header = low; n_tables += 1; t_auth = any(("auth" in c) or ("인증" in c) for c in low); has_auth = has_auth or t_auth
        continue
    if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c): continue
    rec = dict(zip(header, cells))
    meth = bare(rec.get("method") or rec.get("메서드") or "").upper()
    path = bare(rec.get("path") or rec.get("경로") or "")
    if not re.fullmatch(r"GET|POST|PUT|PATCH|DELETE", meth) or not path.startswith("/"): continue
    rows.append(dict(meth=meth, path=path, has_auth=t_auth, auth=col(rec, "auth", "인증"), req=col(rec, "request", "요청"),
                     resp=col(rec, "response", "응답"), raw=raw.strip()))
scoped = [r for r in rows if changed is None or r["raw"] in changed]

out, skipped = [], []
if n_tables == 0 and spec_p:
    skipped.append("엔드포인트 표 규칙(인증·URL 민감정보·응답 민감 필드 — §1 Markdown 엔드포인트 표 없음)")
# [인증] — 공개도 결정이다: `없음(공개)` 처럼 적으면 통과, 빈칸·대시·자리표시자만 경고
if n_tables and not has_auth: skipped.append("인증(엔드포인트 표에 Auth 열 없음)")
for r in scoped:
    if r["has_auth"] and unset(bare(r["auth"] or "")):
        out.append(f"[인증] {r['meth']} {r['path']} — Auth 칸이 비었다(공개면 `없음(공개)`, 아니면 인증 방식·역할)")
# [URL 민감정보] — 고정 경로 마디(/auth/token)는 보지 않고 파라미터 이름만 본다 · 페이지 커서(page_token 류)는 비밀이 아니다
#   Path 칸의 파라미터·쿼리는 모든 메서드에서, Request 칸의 `?이름=` 은 GET·DELETE 에서만 본다(본문이 없는 메서드의 요청 칸 = 쿼리)
SENS_PARAM = re.compile(r"(^|_)(token|secret|password|passwd|api_key|apikey|session_id|sessionid)$")
CURSOR = re.compile(r"(^|_)(page|next|prev|continuation|sync|cursor)_token$")
def params(r):
    p = r["path"]; names = re.findall(r":([A-Za-z_][A-Za-z0-9_]*)", p.split("?")[0]) + re.findall(r"\{([A-Za-z_][A-Za-z0-9_]*)\}", p)
    for cell in (p, (r["req"] or "") if r["meth"] in ("GET", "DELETE") else ""):
        names += re.findall(r"[?&]([A-Za-z_][A-Za-z0-9_]*)=", cell)
    return names
for r in scoped:
    hit = next((n for n in params(r) if SENS_PARAM.search("_".join(words(n))) and not CURSOR.search("_".join(words(n)))), None)
    if hit: out.append(f"[URL 민감정보] {r['meth']} {r['path']} — {hit} — 토큰·비밀번호·비밀·API 키는 URL 이 아니라 헤더·본문으로(로그·Referer 로 샌다)")
# [응답 민감 필드] — 소문자로 시작하는 필드 이름만 본다(User·Secret 같은 타입 이름은 필드가 아니다) · has_·is_ 로 시작하는 불리언(hasPassword)은 값이 아니다
SENS_RESP = re.compile(r"(^|_)(password|secret|password_hash|private_key|reset_token)$")
for r in scoped:
    ids = re.findall(r"(?<![A-Za-z0-9_])([a-z_][A-Za-z0-9_]*)", r["resp"] or "")
    hit = next((i for i in ids if SENS_RESP.search("_".join(words(i))) and not re.match(r"(has|is)_", "_".join(words(i)))), None)
    if hit: out.append(f"[응답 민감 필드] {r['meth']} {r['path']} — {hit} — 응답에서 빼고 응답 전용 타입으로 내보낸다")

# ── 칸 ──
AUTH_LBL, ROLE_LBL, CORS_LBL, CSRF_LBL = r"인증 방식", r"권한 모델", r"CORS", r"CSRF"
cells = [("인증 방식", api, AUTH_LBL, spec_p), ("권한 모델", api, ROLE_LBL, spec_p), ("CORS", api, CORS_LBL, spec_p),
         ("CSRF", api, CSRF_LBL, spec_p), ("개인정보 분류", dm, r"개인정보 분류", dm_p), ("보존·삭제", dm, r"보존\s*[·・/]?\s*삭제", dm_p)]
n_cells = 0
for label, lines, rx, present in cells:
    if not present: continue
    v = field(lines, rx)
    if v is None and label == "인증 방식": v = field(lines, r"인증")   # 옛 이름은 새 칸이 없을 때만 (clarify Q2)
    if v is None: skipped.append(f"{label}(칸 없음)"); continue
    n_cells += 1
    if unset(v): out.append(f"[미정] {label} — 칸이 비었거나 자리표시자({v or '빈 값'})")
cors = field(api, CORS_LBL)
if cors is not None and not unset(cors):
    star = re.search(r"(^|[\s,;:=(（'\"`])\*($|[\s,;)）'\"`])", cors)
    m = re.search(r"credentials?\s*[:=]?\s*([^·,;/|]*)", cors, re.I)
    cred = bool(m) and re.search(r"true|include|사용|허용", m.group(1), re.I) and not re.search(r"false|omit|\bno\b|미사용|불허|비허용|없음|금지|않|안\s*[함됨]", m.group(1), re.I)
    if star and cred: out.append("[CORS] 허용 origin `*` 와 credentials 를 함께 쓴다 — 브라우저가 거부하거나, origin 을 반사하면 아무 사이트나 인증 요청을 보낸다")

# ── [승인 대상] — 파일 경로·엔드포인트 경로에서만 신호를 찾는다 ──
FEATURES = [
    ("업로드", lambda w: bool({"upload", "uploads", "uploader", "multipart"} & w)),
    ("웹훅 수신", lambda w: bool({"webhook", "webhooks"} & w)),
    ("외부 URL 가져오기", lambda w: bool({"proxy", "scrape", "scraper", "scraping", "crawl", "crawler", "unfurl", "unfurler", "fetcher"} & w)
                         or ("url" in w and bool({"fetch", "import", "preview"} & w)) or {"link", "preview"} <= w),
    ("LLM 호출", lambda w: bool({"llm", "llms", "openai", "anthropic", "gpt", "chatgpt", "langchain", "embedding", "embeddings", "rag"} & w)),
]
sources = [(f"api-spec `{r['meth']} {r['path']}`", r["path"]) for r in scoped]
if plan is not None:
    psec, inside = [], False
    shown = [raw for raw, hidden in plan if not hidden]
    for raw in shown:
        if re.match(r"^##\s+", raw):
            inside = re.match(r"^##\s+2\.\s*파일 구조", raw) is not None; continue
        if inside: psec.append(raw)
    if not any(re.match(r"^##\s+2\.\s*파일 구조", l) for l in shown):
        skipped.append("승인 대상 plan 신호(plan 에 `## 2. 파일 구조` 절 없음)")
    for raw in psec:
        if re.match(r"^\s*[-*]\s*\*\*범위 밖\*\*", raw): continue   # 건드리지 않는다고 적은 경로는 신호가 아니다
        for tok in re.findall(r"`([^`\s]+)`", raw):
            if "/" in tok or "." in tok: sources.append((f"plan §2 `{tok}`", tok))
if tasks is not None:
    # outputs 는 한 줄 목록(`outputs: [a, b]`)과 블록 목록(`outputs:` 다음 줄부터 `- a`) 둘 다 읽는다
    outs, block = [], None
    for raw in tasks.splitlines():
        m = re.match(r"^(\s*)outputs:\s*(.*)$", raw)
        if m:
            block = None
            if m.group(2).startswith("["): outs += m.group(2).strip("[] ").split(",")
            elif not m.group(2).strip(): block = len(m.group(1))
            continue
        if block is not None:
            b = re.match(r"^(\s*)-\s+(.+)$", raw)
            if b and len(b.group(1)) >= block: outs.append(b.group(2)); continue
            if raw.strip(): block = None
    for tok in (t.strip().strip("'\"") for t in outs):
        if tok: sources.append((f"tasks outputs `{tok}`", tok))
risk = section(api, r"위험 기능 결정")
if spec_p and risk is None: skipped.append("승인 대상(「위험 기능 결정」 절 없음)")
for label, is_sig in FEATURES:
    src = next((s for s, p in sources if is_sig(set(words(p)))), None)
    if src is None: continue
    if not spec_p: skipped.append(f"승인 대상 {label}(api-spec 없음 — 신호: {src})"); continue
    if risk is None: continue
    v = field(risk, re.escape(label))
    if unset(v): out.append(f"[승인 대상] {label} — {src} — 「위험 기능 결정」의 {label} 칸이 비었다(결정 또는 `해당 없음`)")

if not out and not rows and n_cells == 0 and risk is None:
    print("SECURITY-DESIGN: SKIP (판정할 칸이 없다 — 엔드포인트 표·보안 칸 모두 부재)"); sys.exit(0)
head = "WARN" if out else "OK"
print(f"SECURITY-DESIGN: {head} (위반 {len(out)} · 엔드포인트 {len(scoped)}/{len(rows)} · 건너뜀 {len(skipped)})")
for l in out: print("  " + l)
for s in skipped: print("  [건너뜀] " + s)
if scope == "untracked": print("  [범위] 전체 행 — api-spec 이 git 추적 밖이거나 분기점을 구하지 못해 바뀐 행을 가리지 못했다")
sys.exit(0)
PY
