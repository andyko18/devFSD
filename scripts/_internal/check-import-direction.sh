#!/usr/bin/env bash
# check-import-direction.sh — plan.md 「경계 약속」의 허용 의존(화살표 형식)을 실제 import 와 대조하고 순환을 찾는다 (읽기 전용 · 경고 전용)
#   FID 20261021-import-direction
#
# Usage: check-import-direction.sh <FID>                                  # .specops/<FID>/plan.md · 이 FID 가 바꾼 파일(분기점…작업 트리 + 추적 안 한 새 파일)
#        check-import-direction.sh --plan <경로> --files <목록 파일> [--root <디렉터리>]   # 목록 파일 = 한 줄에 경로 하나(root 기준)
#
# 허용 의존 형식(templates/plan.md 경계 약속):  - **허용 의존**: `src/domain/` → 없음 · `src/app/` → `src/domain/` · `src/adapters/` → `src/app/`, `src/domain/`
#   화살표 왼쪽 경로 안의 파일은 오른쪽에 적은 경로만 불러 쓸 수 있다(같은 왼쪽 경로 안은 자유). `->` 도 받는다.
#   판정은 **선언한 경로끼리만** 한다 — 어느 왼쪽 경로에도 속하지 않는 내부 파일·외부 패키지를 부르는 것은 보지 않는다(오탐을 만들지 않는다).
#   화살표 형식이 하나도 없으면(자유 문장·자리표시자) 방향은 SKIP 이고 순환만 본다.
#
# 출력 첫 줄: IMPORT-DIRECTION: OK | WARN | SKIP | 판정 불가 — 그 아래 줄은 두 칸 들여쓰기
#   [역방향] <파일>:<줄> → <대상> (<왼쪽 경로> 허용: …)   선언한 다른 경로를 허용 없이 부른다
#   [순환] a → b → a                                         모듈 최상위 import 의 순환(바꾼 파일이 낀 것만)
#   [미해석] N건 — <파일>:<줄> '<명시>' …                   풀지 못한 import(별칭·동적 import) — 판정하지 않았다("지킴"으로 치지 않는다)
#   [범위 상한] …                                            순환 탐색이 노드 상한에서 멈췄다
# Exit: 0 = 판정함(위반이 있어도 0)·SKIP · 1 = 사용 오류 · 2 = 판정 불가(python3 없음 · git 분기점 없음 · plan·목록을 읽지 못함)
#
# 막지 않는다: run-verification.sh 가 evidence.md `### import-direction` 에 남기고 경고만 낸다(VERIFY 판정·종료 코드 불변).
# 언어: Python(import · from … import · 상대 import) · JS/TS(import … from · export … from · import '…' · require('…') · import('…'),
#   상대 경로와 루트 tsconfig.json/jsconfig.json 의 compilerOptions.paths·baseUrl).
# 한계: 정규식 추출이다 — 문자열 속 import 꼴을 import 로 읽을 수 있다(주석·파이썬 삼중따옴표 안은 뺀다).
#   파이썬 패키지 루트는 저장소 루트 · src/ · 선언 경로에서 모듈 첫 마디가 나오는 위치 앞으로만 찾는다(그 밖의 루트는 외부 패키지로 읽힌다 — 누락이지 오탐은 아니다).
#   순환은 최상위 import 만 본다 — 들여쓴 import(함수 안·if TYPE_CHECKING·try)와 TS `import type`·동적 import 는 순환 간선에서 뺀다(방향 판정에는 넣는다).
set -u

SPECOPS="${SPECOPS_ROOT:-.specops}"
PLAN=""; FILES=""; ROOT=""; FID=""
usage() { echo "usage: check-import-direction.sh <FID> | --plan <경로> --files <목록 파일> [--root <디렉터리>]" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --plan)  [ $# -ge 2 ] && [ -z "$PLAN" ] || usage; PLAN="$2"; shift 2 ;;
    --files) [ $# -ge 2 ] && [ -z "$FILES" ] || usage; FILES="$2"; shift 2 ;;
    --root)  [ $# -ge 2 ] && [ -z "$ROOT" ] || usage; ROOT="$2"; shift 2 ;;
    -*|"")   usage ;;
    *)       [ -z "$FID" ] && [ -z "$PLAN" ] || usage; FID="$1"; shift ;;
  esac
done
if [ -n "$FID" ]; then
  [ -z "$FILES" ] && [ -z "$ROOT" ] || usage
  printf '%s' "$FID" | grep -qE '^[0-9]{8}-[a-z0-9-]+$' || { echo "check-import-direction: FID 형식 오류: '$FID'" >&2; exit 1; }
  PLAN="$SPECOPS/$FID/plan.md"
else
  [ -n "$PLAN" ] && [ -n "$FILES" ] || usage
  [ -n "$ROOT" ] || ROOT="."
fi

cant() { echo "IMPORT-DIRECTION: 판정 불가 ($1)"; exit 2; }

if [ ! -e "$PLAN" ]; then
  [ -L "$PLAN" ] && cant "plan 을 따라갈 수 없는 심볼릭 링크: $PLAN"
  echo "IMPORT-DIRECTION: SKIP (plan.md 부재 — lite·trivial 정상 경로)"; exit 0
fi
[ -r "$PLAN" ] || cant "plan 을 읽을 수 없음: $PLAN"
command -v python3 >/dev/null 2>&1 || cant "python3 없음"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/specops-impdir.XXXXXX") || cant "임시 디렉터리 생성 실패"
_ID_TMP="$TMP"
trap 'rm -rf "$_ID_TMP"' EXIT
trap 'exit 143' TERM INT HUP

# ── 바꾼 파일 목록 (FID 모드) — 분기점은 reuse-metrics.sh 와 같다: review-base.sha → 기본 브랜치와의 merge-base ──
if [ -n "$FID" ]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || cant "git 저장소가 아님"
  _git() { git -C "$ROOT" -c core.quotePath=false "$@"; }
  base=""
  rb="$SPECOPS/$FID/review-base.sha"
  if [ -s "$rb" ]; then
    cand=$(tr -d ' \n\r' < "$rb")
    _git cat-file -e "${cand}^{commit}" 2>/dev/null && base="$cand"
  fi
  if [ -z "$base" ]; then
    b=$(_git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
    [ -n "$b" ] || { _git show-ref -q --verify refs/heads/main && b=main; }
    [ -n "$b" ] || { _git show-ref -q --verify refs/heads/master && b=master; }
    [ -n "$b" ] && base=$(_git merge-base HEAD "$b" 2>/dev/null || true)
  fi
  [ -n "$base" ] || cant "분기점을 구할 수 없음(review-base.sha·기본 브랜치 origin/HEAD·main·master 부재 또는 공통 조상 없음)"
  FILES="$TMP/files"
  # 파일로 받고 종료 코드를 따로 본다 — 파이프는 git 의 실패를 "바뀐 파일 없음"으로 읽게 만든다.
  _git diff --no-ext-diff --name-only --no-renames --diff-filter=AM "$base" > "$FILES" 2>/dev/null || cant "git diff 실패(분기점 $base)"
  _git ls-files --others --exclude-standard >> "$FILES" 2>/dev/null || cant "git ls-files 실패"
fi
[ -r "$FILES" ] || cant "파일 목록을 읽을 수 없음: $FILES"
[ -d "$ROOT" ] || cant "루트가 디렉터리가 아님: $ROOT"

python3 -E - "$PLAN" "$FILES" "$ROOT" <<'PY'
import json, os, re, sys

plan_path, files_path, root = sys.argv[1], sys.argv[2], sys.argv[3]
root = os.path.abspath(root)
MAX_NODES = 400
MAX_LIST = 20
PY_EXT = (".py",)
JS_EXT = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts", ".vue", ".svelte")
SRC_EXT = PY_EXT + JS_EXT
SKIP_DIRS = ("node_modules/", ".specops/", ".git/", "dist/", "build/", ".venv/", "venv/", "__pycache__/")

def out(first, lines):
    print(first)
    for l in lines:
        print("  " + l)
    sys.exit(0)

def norm(p):
    p = p.strip().replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return p

def under(path, d):
    d = d.rstrip("/")
    return d != "" and (path == d or path.startswith(d + "/"))

def isfile(rel):
    return os.path.isfile(os.path.join(root, rel))

def isdir(rel):
    return os.path.isdir(os.path.join(root, rel))

# ── 허용 의존 ──
try:
    plan = open(plan_path, encoding="utf-8", errors="replace").read().splitlines()
except OSError as e:
    print("IMPORT-DIRECTION: 판정 불가 (plan 을 읽을 수 없음: %s)" % e)
    sys.exit(2)

dep_text = None
in_sec = False
for line in plan:
    if re.match(r"^#{1,3}\s", line):
        in_sec = bool(re.match(r"^###\s+경계 약속", line))
        continue
    if in_sec:
        m = re.match(r"^\s*[-*]\s*\*\*허용 의존\*\*\s*[:：]\s*(.*)$", line)
        if m:
            dep_text = m.group(1)
            break

rules = []   # (왼쪽 경로, [허용 경로])
if dep_text and not re.match(r"^\s*<", dep_text):
    for ent in re.split(r"\s+·\s+|\s*;\s*", dep_text):
        m = re.match(r"^\s*`([^`]+)`\s*(?:→|->)\s*(.+?)\s*$", ent)
        if not m:
            continue
        left = norm(m.group(1)).rstrip("/")
        right = m.group(2).strip()
        if re.match(r"^(없음|none|-)\.?$", right, re.I):
            allowed = []
        else:
            allowed = [norm(x).rstrip("/") for x in re.findall(r"`([^`]+)`", right)]
            if not allowed:
                continue
        if left:
            rules.append((left, allowed))

lefts = [r[0] for r in rules]

def layer_of(path):
    best = None
    for l in lefts:
        if under(path, l) and (best is None or len(l) > len(best)):
            best = l
    return best

# ── 바꾼 소스 파일 ──
try:
    raw = open(files_path, encoding="utf-8", errors="replace").read().splitlines()
except OSError as e:
    print("IMPORT-DIRECTION: 판정 불가 (파일 목록을 읽을 수 없음: %s)" % e)
    sys.exit(2)
changed = []
seen = set()
for p in raw:
    p = norm(p)
    if not p or p in seen or not p.endswith(SRC_EXT):
        continue
    if any(p.startswith(s) or ("/" + s) in ("/" + p) for s in SKIP_DIRS):
        continue
    if not isfile(p):
        continue
    seen.add(p)
    changed.append(p)

if not changed:
    first = "IMPORT-DIRECTION: SKIP (바뀐 소스 파일 없음 — Python·JS/TS)"
    out(first, [])

# ── tsconfig 별칭 ──
alias = []   # (접두, [대체 접두])
base_url = None
def strip_json_comments(s):
    res, i, n, ins, q = [], 0, len(s), False, ""
    while i < n:
        c = s[i]
        if ins:
            res.append(c)
            if c == "\\" and i + 1 < n:
                res.append(s[i + 1]); i += 2; continue
            if c == q:
                ins = False
            i += 1; continue
        if c in "\"'":
            ins, q = True, c; res.append(c); i += 1; continue
        if s.startswith("//", i):
            j = s.find("\n", i); i = n if j < 0 else j; continue
        if s.startswith("/*", i):
            j = s.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        res.append(c); i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(res))
for cfg in ("tsconfig.json", "jsconfig.json"):
    fp = os.path.join(root, cfg)
    if not os.path.isfile(fp):
        continue
    try:
        co = json.loads(strip_json_comments(open(fp, encoding="utf-8", errors="replace").read())).get("compilerOptions", {}) or {}
    except Exception:
        continue
    base_url = norm(co.get("baseUrl", ".") or ".")
    if base_url in (".", ""):
        base_url = ""
    for k, v in (co.get("paths") or {}).items():
        if not isinstance(v, list):
            continue
        pre = k[:-1] if k.endswith("*") else k
        subs = [norm(os.path.join(base_url, (x[:-1] if x.endswith("*") else x))) for x in v if isinstance(x, str)]
        alias.append((pre, k.endswith("*"), subs))
    break

def js_try(rel):
    rel = os.path.normpath(rel).replace("\\", "/")
    if rel.startswith("../") or rel == "..":
        return None
    cands = [rel] + [rel + e for e in JS_EXT] + [rel + "/index" + e for e in JS_EXT]
    if rel.endswith((".js", ".mjs", ".cjs", ".jsx")):   # TS 의 .js 확장자 import → .ts
        stem = rel.rsplit(".", 1)[0]
        cands += [stem + e for e in (".ts", ".tsx", ".mts", ".cts")]
    for c in cands:
        if isfile(c):
            return c
    return None

UNRES = object()
def resolve_js(f, spec):
    if spec.startswith("."):
        return js_try(os.path.join(os.path.dirname(f), spec)) or UNRES
    for pre, star, subs in alias:
        if (star and spec.startswith(pre)) or (not star and spec == pre):
            rest = spec[len(pre):] if star else ""
            for s in subs:
                t = js_try(s + rest if star else s)
                if t:
                    return t
            return UNRES
    if base_url is not None:
        t = js_try(os.path.join(base_url, spec)) if base_url else js_try(spec)
        if t:
            return t
    if spec.startswith(("@/", "~/", "#")):
        return UNRES
    return None   # 외부 패키지

# 파이썬 루트 후보: 저장소 루트 · src/ · 선언 경로에서 모듈 첫 마디가 나오는 위치 앞
decl_paths = set(lefts)
for _, al in rules:
    decl_paths.update(al)
def py_roots(first_seg):
    roots = ["", "src/"]
    for d in decl_paths:
        parts = d.split("/")
        for i, part in enumerate(parts):
            if part == first_seg:
                r = "/".join(parts[:i])
                r = (r + "/") if r else ""
                if r not in roots:
                    roots.append(r)
    return roots

def py_mod(rel_base):
    if isfile(rel_base + ".py"):
        return rel_base + ".py"
    if isfile(rel_base + "/__init__.py"):
        return rel_base + "/__init__.py"
    if isdir(rel_base) and rel_base:
        return rel_base   # 이름공간 패키지 — 폴더로 대조
    return None

def resolve_py(f, dots, mod, names):
    targets = []
    if dots:
        pkg = os.path.dirname(f)
        for _ in range(dots - 1):
            pkg = os.path.dirname(pkg)
        base = "/".join(x for x in [pkg, mod.replace(".", "/")] if x)
        bases = [base]
    else:
        if not mod:
            return []
        bases = [r + mod.replace(".", "/") for r in py_roots(mod.split(".")[0])]
    for b in bases:
        # `from 패키지 import 하위모듈` 은 하위 모듈 파일로, 그 밖의 이름(함수·클래스)은 모듈 자신으로 푼다
        for n in names:
            if n == "*":
                continue
            cand = (b + "/" + n) if b else n
            if isfile(cand + ".py"):
                targets.append(cand + ".py")
            elif isfile(cand + "/__init__.py"):
                targets.append(cand + "/__init__.py")
        if not targets and b:
            m = py_mod(b)
            if m:
                targets.append(m)
        if targets:
            return targets
    return [UNRES] if dots else []   # 상대 import 가 풀리지 않으면 미해석 · 절대 import 는 외부 패키지

# ── import 추출 ──
def py_imports(text):
    res = []   # (줄, 명시, 대상들, 최상위)
    in_str = None
    for no, line in enumerate(text.splitlines(), 1):
        s = line
        if in_str:
            if in_str in s:
                s = s.split(in_str, 1)[1]; in_str = None
            else:
                continue
        code = re.sub(r"#.*$", "", s)
        for q in ('"""', "'''"):
            if code.count(q) % 2 == 1:
                in_str = q
                code = code.split(q, 1)[0]
                break
        top = not code[:1].isspace()
        m = re.match(r"^\s*from\s+(\.*)([\w.]*)\s+import\s+(.+)$", code)
        if m:
            names = [x.strip().split(" as ")[0].strip() for x in m.group(3).strip("()\\ ").split(",")]
            names = [x for x in names if re.match(r"^[\w*]+$", x)]
            res.append((no, (m.group(1) + m.group(2)), ("py", len(m.group(1)), m.group(2), names), top))
            continue
        m = re.match(r"^\s*import\s+(.+)$", code)
        if m:
            for part in m.group(1).split(","):
                mod = part.strip().split(" as ")[0].strip()
                if re.match(r"^[\w.]+$", mod):
                    res.append((no, mod, ("py", 0, mod, []), top))
            continue
        if re.search(r"\b(importlib\.import_module|__import__)\s*\(", code):
            res.append((no, code.strip()[:60], ("dyn",), False))
    return res

def blank_js_comments(t):
    out_, i, n, ins, q = [], 0, len(t), False, ""
    while i < n:
        c = t[i]
        if ins:
            out_.append(c)
            if c == "\\" and i + 1 < n:
                out_.append(t[i + 1]); i += 2; continue
            if c == q or (c == "\n" and q != "`"):
                ins = False
            i += 1; continue
        if c in "\"'`":
            ins, q = True, c; out_.append(c); i += 1; continue
        if t.startswith("//", i):
            j = t.find("\n", i); j = n if j < 0 else j
            out_.append(" " * (j - i)); i = j; continue
        if t.startswith("/*", i):
            j = t.find("*/", i + 2); j = n if j < 0 else j + 2
            out_.append(re.sub(r"[^\n]", " ", t[i:j])); i = j; continue
        out_.append(c); i += 1
    return "".join(out_)

JS_PATS = [
    (re.compile(r"\bimport\s+type\s[^;]*?\bfrom\s*(['\"])([^'\"]+)\1", re.S), "type"),
    (re.compile(r"\bimport\s+(?!type\s)[^;'\"()]*?\bfrom\s*(['\"])([^'\"]+)\1", re.S), "static"),
    (re.compile(r"\bexport\s+(?:type\s+)?[^;'\"()]*?\bfrom\s*(['\"])([^'\"]+)\1", re.S), "static"),
    (re.compile(r"\bimport\s*(['\"])([^'\"]+)\1"), "static"),
    (re.compile(r"\brequire\(\s*(['\"])([^'\"]+)\1\s*\)"), "require"),
    (re.compile(r"\bimport\(\s*(['\"])([^'\"]+)\1\s*\)"), "dynamic"),
]
JS_DYN = re.compile(r"\b(?:require|import)\(\s*[^'\"\s)]")

def js_imports(text):
    t = blank_js_comments(text)
    res, taken = [], set()
    for pat, kind in JS_PATS:
        for m in pat.finditer(t):
            pos = m.start(2)
            if pos in taken:
                continue
            taken.add(pos)
            no = t.count("\n", 0, m.start()) + 1
            line_start = t.rfind("\n", 0, m.start()) + 1
            top = kind in ("static",) or (kind == "require" and not t[line_start:line_start + 1].isspace())
            res.append((no, m.group(2), ("js", m.group(2)), top))
    for m in JS_DYN.finditer(t):
        no = t.count("\n", 0, m.start()) + 1
        res.append((no, t[m.start():m.start() + 40].split("\n")[0], ("dyn",), False))
    return res

cache = {}
def imports_of(f):
    if f in cache:
        return cache[f]
    try:
        text = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
    except OSError:
        cache[f] = []
        return []
    items = []
    raw_ = py_imports(text) if f.endswith(PY_EXT) else js_imports(text)
    for no, spec, info, top in raw_:
        if info[0] == "dyn":
            items.append((no, spec, [UNRES], False))
            continue
        if info[0] == "py":
            ts = resolve_py(f, info[1], info[2], info[3])
        else:
            r = resolve_js(f, info[1])
            ts = [] if r is None else [r]
        items.append((no, spec, [x for x in ts if x is UNRES or x != f], top))
    cache[f] = items
    return items

# ── 방향 판정 ──
viol, unres = [], []
for f in changed:
    lf = layer_of(f)
    for no, spec, ts, top in imports_of(f):
        for t in ts:
            if t is UNRES:
                unres.append("%s:%d '%s'" % (f, no, spec))
                continue
            if lf is None:
                continue
            if under(t, lf):
                continue
            lt = layer_of(t)
            if lt is None:
                continue
            allowed = dict(rules)[lf]
            if any(under(t, a) for a in allowed):
                continue
            viol.append("[역방향] %s:%d → %s (`%s/` 허용: %s)" % (f, no, t, lf, ", ".join("`%s/`" % a for a in allowed) or "없음"))

# ── 순환 (최상위 import 만 · 바꾼 파일이 낀 것만) ──
graph, order, capped = {}, list(changed), False
i = 0
while i < len(order):
    f = order[i]; i += 1
    if not f.endswith(SRC_EXT) or not isfile(f):
        graph[f] = []
        continue
    nxt = []
    for no, spec, ts, top in imports_of(f):
        if not top:
            continue
        for t in ts:
            if t is UNRES or not t.endswith(SRC_EXT):
                continue
            nxt.append(t)
            if t not in graph and t not in order:
                if len(order) >= MAX_NODES:
                    capped = True
                    continue
                order.append(t)
    graph[f] = sorted(set(nxt))

idx, low, onst, st, sccs, counter = {}, {}, set(), [], [], [0]
sys.setrecursionlimit(10000)
def strong(v):
    idx[v] = low[v] = counter[0]; counter[0] += 1
    st.append(v); onst.add(v)
    for w in graph.get(v, []):
        if w not in graph:
            continue
        if w not in idx:
            strong(w); low[v] = min(low[v], low[w])
        elif w in onst:
            low[v] = min(low[v], idx[w])
    if low[v] == idx[v]:
        comp = []
        while True:
            w = st.pop(); onst.discard(w); comp.append(w)
            if w == v:
                break
        sccs.append(comp)
for v in list(graph):
    if v not in idx:
        strong(v)

cycles = []
chg = set(changed)
for comp in sccs:
    cs = set(comp)
    if len(comp) == 1 and comp[0] not in graph.get(comp[0], []):
        continue
    if not (cs & chg):
        continue
    start = sorted(cs & chg)[0]
    prev, q, found = {start: None}, [start], None
    while q and not found:
        v = q.pop(0)
        for w in graph.get(v, []):
            if w == start:
                found = v; break
            if w in cs and w not in prev:
                prev[w] = v; q.append(w)
    path, v = [], found
    while v is not None:
        path.append(v); v = prev[v]
    path.reverse()
    cycles.append("[순환] " + " → ".join(path + [start]))

lines = viol[:MAX_LIST]
if len(viol) > MAX_LIST:
    lines.append("… [역방향] 외 %d건" % (len(viol) - MAX_LIST))
lines += cycles[:MAX_LIST]
if unres:
    lines.append("[미해석] %d건 — %s%s (판정하지 않음)" % (len(unres), " · ".join(unres[:3]), " …" if len(unres) > 3 else ""))
if capped:
    lines.append("[범위 상한] 순환 탐색이 노드 %d개에서 멈췄다 — 그 밖의 순환은 보지 않았다" % MAX_NODES)

summary = "역방향 %d · 순환 %d · 소스 %d개" % (len(viol), len(cycles), len(changed))
if viol or cycles:
    out("IMPORT-DIRECTION: WARN (%s)" % summary, lines)
if not rules:
    out("IMPORT-DIRECTION: SKIP (허용 의존이 화살표 형식이 아님 — 순환만 검사: %s)" % summary, lines)
out("IMPORT-DIRECTION: OK (%s)" % summary, lines)
PY
