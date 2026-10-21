#!/usr/bin/env bash
# import 방향·순환 경고 — check-import-direction.sh + run-verification 경고 배선 (20261021-import-direction)
#
# plan 「경계 약속」의 허용 의존(화살표 형식)을 실제 import 와 대조하고 최상위 import 의 순환을 찾는다.
# 경고 전용이다: 위반이 있어도 rc 0 · VERIFY 판정·종료 코드 불변. 풀지 못한 import 는 "지킴"이 아니라 미해석으로 센다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CID="$PLUGIN/scripts/_internal/check-import-direction.sh"
RV="$PLUGIN/scripts/_internal/run-verification.sh"
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

_plan() {  # $1=파일 · $2=허용 의존 칸 내용
  printf '# plan\n\n## 2. 파일 구조\n\n### 경계 약속\n\n- **소유**: `src/`\n- **허용 의존**: %s\n- **다시 검토할 조건**: 없음\n\n## 3. 데이터 모델\n\n- **허용 의존**: `src/x/` → 없음\n' "$2" > "$1"
}
_layers='`src/domain/` → 없음 · `src/app/` → `src/domain/` · `src/adapters/` → `src/app/`, `src/domain/`'
_run() {  # $1=dir — plan.md · files.txt(그 폴더의 소스 전부) 로 실행
  ( cd "$1" && find . -type f \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' \) | sed 's#^\./##' | sort > files.txt \
    && bash "$CID" --plan plan.md --files files.txt --root . )
}
_py() { mkdir -p "$1/src/domain" "$1/src/app" "$1/src/adapters" "$1/src/utils"; }

# D1: 역방향 — 도메인이 어댑터를 부른다 · 위반 줄 번호 · rc 0(경고 전용)
D="$ROOT/d1"; _py "$D"; _plan "$D/plan.md" "$_layers"
printf 'import os\nfrom src.adapters.db import Repo\n' > "$D/src/domain/user.py"
printf 'X = 1\n' > "$D/src/adapters/db.py"
out=$(_run "$D"); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: WARN (역방향 1 · 순환 0 · ' \
  && printf '%s\n' "$out" | grep -qF '[역방향] src/domain/user.py:2 → src/adapters/db.py (`src/domain/` 허용: 없음)'; } \
  && ok "D1 역방향(도메인 → 어댑터) 적발 · 줄 번호 · rc 0" || nope "D1" "rc=$rc out=$out"

# D2: 허용된 방향 · 같은 경로 안 · 외부 패키지 · 선언 밖 내부 경로는 위반이 아니다
D="$ROOT/d2"; _py "$D"; _plan "$D/plan.md" "$_layers"
printf 'from src.domain.user import U\nfrom . import helper\nimport requests\nfrom fastapi import APIRouter\nfrom src.utils.fmt import f\n' > "$D/src/app/svc.py"
printf 'Y = 1\n' > "$D/src/app/helper.py"; printf 'class U: pass\n' > "$D/src/domain/user.py"; printf 'def f(): pass\n' > "$D/src/utils/fmt.py"
out=$(_run "$D"); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK (역방향 0 · 순환 0 · ' && ! printf '%s\n' "$out" | grep -q '\[역방향\]'; } \
  && ok "D2 허용 방향·같은 경로·외부 패키지·선언 밖 경로 — OK" || nope "D2" "rc=$rc out=$out"

# D3: 함수 안 import 도 방향 판정에는 넣는다(지연 import 로 계층을 넘는 것도 의존이다)
D="$ROOT/d3"; _py "$D"; _plan "$D/plan.md" "$_layers"
printf 'def g():\n    from src.app.svc import run\n    return run\n' > "$D/src/domain/user.py"; printf 'def run(): pass\n' > "$D/src/app/svc.py"
out=$(_run "$D")
printf '%s\n' "$out" | grep -qF '[역방향] src/domain/user.py:2 → src/app/svc.py' && ok "D3 들여쓴 import 도 방향 판정" || nope "D3" "$out"

# D4: 순환 — 최상위 import 만 · 함수 안 import 는 순환을 만들지 않는다
D="$ROOT/d4"; mkdir -p "$D/src"; _plan "$D/plan.md" '<불러 써도 되는 모듈과 방향>'
printf 'from src.b import y\nx = 1\n' > "$D/src/a.py"; printf 'from src.a import x\ny = 2\n' > "$D/src/b.py"
printf 'from src.d import w\nz = 1\n' > "$D/src/c.py"; printf 'def h():\n    from src.c import z\nw = 3\n' > "$D/src/d.py"
out=$(_run "$D")
{ printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: WARN (역방향 0 · 순환 1 · ' && printf '%s\n' "$out" | grep -qF '[순환] src/a.py → src/b.py → src/a.py' \
  && ! printf '%s\n' "$out" | grep -q 'src/c.py →'; } \
  && ok "D4 최상위 순환 적발 · 함수 안 import 는 순환 아님 · 허용 의존 없어도 순환은 본다" || nope "D4" "$out"

# D5: 허용 의존이 자리표시자·자유 문장이면 방향은 SKIP(하위 호환) — 순환이 없으면 SKIP 줄
D="$ROOT/d5"; _py "$D"; _plan "$D/plan.md" '`src/core` 를 읽기만'
printf 'from src.adapters.db import Repo\n' > "$D/src/domain/user.py"; printf 'X = 1\n' > "$D/src/adapters/db.py"
out=$(_run "$D"); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: SKIP (허용 의존이 화살표 형식이 아님 — 순환만 검사: 역방향 0 · 순환 0 · '; } \
  && ok "D5 자유 문장 허용 의존 — 방향 SKIP · rc 0" || nope "D5" "rc=$rc out=$out"

# D6: 경계 약속 절 밖의 같은 이름 칸은 읽지 않는다 — 미끼 칸을 절 **앞**(§1)에 둔다(뒤에만 두면 첫 칸을 읽는 구현도 통과한다)
#   미끼를 읽으면 x → y 가 역방향(WARN)이 되고, 절의 칸을 읽으면 허용(OK)이다.
D="$ROOT/d6"; mkdir -p "$D/src/x" "$D/src/y"; _plan "$D/plan.md" '`src/x/` → `src/y/` · `src/y/` → 없음'
{ printf '## 1. 가정\n\n- **허용 의존**: `src/x/` → 없음 · `src/y/` → 없음\n\n'; cat "$D/plan.md"; } > "$D/plan.tmp" && mv "$D/plan.tmp" "$D/plan.md"
printf 'from src.y.m import a\n' > "$D/src/x/k.py"; printf 'a = 1\n' > "$D/src/y/m.py"
out=$(_run "$D")
printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK ' && ok "D6 경계 약속 절의 칸만 읽는다" || nope "D6" "$out"

# D7: JS/TS — 상대 경로 · tsconfig paths 별칭 · 주석 속 import 무시 · import type 은 방향엔 넣고 순환엔 빼기
D="$ROOT/d7"; mkdir -p "$D/web/ui" "$D/web/lib"
_plan "$D/plan.md" '`web/lib/` → 없음 · `web/ui/` → `web/lib/`'
printf '{\n  // 주석\n  "compilerOptions": { "baseUrl": ".", "paths": { "@/*": ["web/*"] }, },\n}\n' > "$D/tsconfig.json"
printf "import { a } from '@/lib/a'\nexport const c = 1\n" > "$D/web/ui/c.tsx"
printf "// import { c } from '../ui/c'\nimport type { C } from '../ui/c'\nexport const a = 1\n" > "$D/web/lib/a.ts"
out=$(_run "$D")
{ printf '%s\n' "$out" | grep -qF '[역방향] web/lib/a.ts:2 → web/ui/c.tsx' && ! printf '%s\n' "$out" | grep -q 'a.ts:1' \
  && ! printf '%s\n' "$out" | grep -q '\[순환\]' && printf '%s\n' "$out" | head -1 | grep -q 'WARN (역방향 1 · 순환 0 · ' \
  && ! printf '%s\n' "$out" | grep -q '\[미해석\]'; } \
  && ok "D7 TS 별칭 해석(미해석 0) · 주석 무시 · import type 은 방향만" || nope "D7" "$out"

# D7b: 별칭으로 금지 방향을 부르면 역방향이다 — 별칭을 풀지 못하면 이 줄이 사라진다
D="$ROOT/d7b"; mkdir -p "$D/web/ui" "$D/web/lib"
_plan "$D/plan.md" '`web/lib/` → 없음 · `web/ui/` → `web/lib/`'
printf '{ "compilerOptions": { "paths": { "@/*": ["./web/*"] } } }\n' > "$D/tsconfig.json"
printf "export const c = 1\n" > "$D/web/ui/c.tsx"
printf "import { c } from '@/ui/c'\nexport const a = c\n" > "$D/web/lib/a.ts"
out=$(_run "$D")
printf '%s\n' "$out" | grep -qF '[역방향] web/lib/a.ts:1 → web/ui/c.tsx' && ok "D7b 별칭 경유 금지 방향 적발" || nope "D7b" "$out"

# D7c: 추출 형식마다 위반 1건 — export … from · require('…') · 리터럴 import('…') · 파이썬 import a.b · 계층을 넘는 상대 import 2꼴
D="$ROOT/d7c"; _py "$D"; mkdir -p "$D/js/domain" "$D/js/adapters"
_plan "$D/plan.md" "$_layers"' · `js/domain/` → 없음 · `js/adapters/` → `js/domain/`'
printf 'X = 1\n' > "$D/src/adapters/db.py"; : > "$D/src/adapters/__init__.py"; : > "$D/src/domain/__init__.py"; : > "$D/src/__init__.py"
printf 'import src.adapters.db\n' > "$D/src/domain/p1.py"
printf 'from ..adapters import db\n' > "$D/src/domain/p2.py"
printf 'from ..adapters.db import X\n' > "$D/src/domain/p3.py"
printf "export const z = 1\n" > "$D/js/adapters/z.ts"
printf "export { z } from '../adapters/z'\n" > "$D/js/domain/e.ts"
printf "const z = require('../adapters/z')\n" > "$D/js/domain/r.js"
printf "export async function f() { return import('../adapters/z') }\n" > "$D/js/domain/d.ts"
out=$(_run "$D")
_miss=""
for w in 'src/domain/p1.py:1 → src/adapters/db.py' 'src/domain/p2.py:1 → src/adapters/db.py' 'src/domain/p3.py:1 → src/adapters/db.py' \
         'js/domain/e.ts:1 → js/adapters/z.ts' 'js/domain/r.js:1 → js/adapters/z.ts' 'js/domain/d.ts:1 → js/adapters/z.ts'; do
  printf '%s\n' "$out" | grep -qF "[역방향] $w" || _miss="$_miss [$w]"
done
[ -z "$_miss" ] && ok "D7c 추출 형식 6종(import a.b · 상대 2꼴 · export from · require · import()) 각각 적발" || nope "D7c" "누락:$_miss out=$out"

# D8: 풀지 못한 import(별칭 없이 @/ · 동적 require) 는 미해석으로 센다 — OK 여도 줄이 남는다
D="$ROOT/d8"; mkdir -p "$D/web/ui"; _plan "$D/plan.md" '`web/ui/` → 없음'
printf "import { x } from '@/missing'\nconst m = require(name)\nimport React from 'react'\n" > "$D/web/ui/p.ts"
out=$(_run "$D")
{ printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK ' && printf '%s\n' "$out" | grep -q '^  \[미해석\] 2건 — web/ui/p.ts:1 '"'"'@/missing'"'"; } \
  && ok "D8 미해석 2건(별칭 없음·동적) — 지킴으로 치지 않고 따로 적는다" || nope "D8" "$out"

# D8b: 풀리지 않는 파이썬 상대 import 도 미해석으로 센다(절대 import 는 외부 패키지로 읽어 세지 않는다)
D="$ROOT/d8b"; _py "$D"; _plan "$D/plan.md" "$_layers"
printf 'from .missing import x\nimport numpy\n' > "$D/src/domain/q.py"
out=$(_run "$D")
printf '%s\n' "$out" | grep -q "^  \[미해석\] 1건 — src/domain/q.py:1 '.missing'" && ok "D8b 풀리지 않는 상대 import 미해석 1건 · 외부 패키지는 세지 않음" || nope "D8b" "$out"

# D9: 파이썬 삼중따옴표 안의 import 꼴은 읽지 않는다
D="$ROOT/d9"; _py "$D"; _plan "$D/plan.md" "$_layers"
printf '"""설명\nfrom src.adapters.db import Repo\n"""\nX = 1\n' > "$D/src/domain/user.py"; printf 'X = 1\n' > "$D/src/adapters/db.py"
out=$(_run "$D")
printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK ' && ok "D9 docstring 속 import 꼴 무시" || nope "D9" "$out"

# D10: 선언 경로 앞의 패키지 루트를 찾는다(backend/app/… 를 app.… 로 부른다)
D="$ROOT/d10"; mkdir -p "$D/backend/app/domain" "$D/backend/app/infra"
_plan "$D/plan.md" '`backend/app/domain/` → 없음 · `backend/app/infra/` → `backend/app/domain/`'
printf 'from app.infra.db import S\n' > "$D/backend/app/domain/m.py"; printf 'S = 1\n' > "$D/backend/app/infra/db.py"
out=$(_run "$D")
printf '%s\n' "$out" | grep -qF '[역방향] backend/app/domain/m.py:1 → backend/app/infra/db.py' && ok "D10 선언 경로에서 패키지 루트 추론" || nope "D10" "$out"

# D11: plan 부재 SKIP · 바뀐 소스 없음 SKIP · 사용 오류 rc 1
D="$ROOT/d11"; mkdir -p "$D"; : > "$D/files.txt"
o1=$(cd "$D" && bash "$CID" --plan nope.md --files files.txt); r1=$?
_plan "$D/plan.md" "$_layers"; printf 'README.md\n' > "$D/files.txt"
o2=$(cd "$D" && bash "$CID" --plan plan.md --files files.txt); r2=$?
bash "$CID" >/dev/null 2>&1; r3=$?
bash "$CID" --plan x >/dev/null 2>&1; r4=$?
{ [ "$r1" -eq 0 ] && [ "$o1" = "IMPORT-DIRECTION: SKIP (plan.md 부재 — lite·trivial 정상 경로)" ] \
  && [ "$r2" -eq 0 ] && printf '%s\n' "$o2" | grep -q '^IMPORT-DIRECTION: SKIP (바뀐 소스 파일 없음' && [ "$r3" -eq 1 ] && [ "$r4" -eq 1 ]; } \
  && ok "D11 plan 부재·소스 없음 SKIP rc 0 · 사용 오류 rc 1" || nope "D11" "r1=$r1 r2=$r2 r3=$r3 r4=$r4 o1=$o1 o2=$o2"

# D12: FID 모드 — 분기점 이후 바꾼 파일만(분기점 전의 위반은 보지 않는다) · 추적 안 한 새 파일 포함 · 분기점 없으면 판정 불가 rc 2
_grepo() {  # $1=dir — main 에 이미 위반이 하나 있는 저장소, feature 브랜치
  _py "$1"; mkdir -p "$1/.specops/20261021-f"; _plan "$1/.specops/20261021-f/plan.md" "$_layers"
  printf 'X = 1\n' > "$1/src/adapters/db.py"; printf 'from src.adapters.db import X\n' > "$1/src/domain/old.py"
  ( cd "$1" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && git checkout -qb feat )
}
D="$ROOT/d12"; _grepo "$D"
printf 'from src.adapters.db import X\n' > "$D/src/domain/new.py"
printf 'from src.adapters.db import X\n' > "$D/src/domain/done.py"; ( cd "$D" && git add src/domain/done.py && git -c user.email=t@t -c user.name=t commit -qm feat )
printf 'from src.adapters.db import X\n' > "$D/src/domain/staged.py"; ( cd "$D" && git add src/domain/staged.py )
out=$(cd "$D" && bash "$CID" 20261021-f); rc=$?
{ printf '%s\n' "$out" | grep -qF '[역방향] src/domain/done.py:1 →' && printf '%s\n' "$out" | grep -qF '[역방향] src/domain/staged.py:1 →'; } \
  && ok "D12a FID 모드 — 분기점 이후 커밋한 파일 · 스테이징만 한 파일 포함" || nope "D12a" "$out"
D2="$ROOT/d12b"; mkdir -p "$D2/.specops/20261021-f"; _plan "$D2/.specops/20261021-f/plan.md" "$_layers"
( cd "$D2" && git init -q -b trunk && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m x )
o2=$(cd "$D2" && bash "$CID" 20261021-f); r2=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF '[역방향] src/domain/new.py:1 → src/adapters/db.py' && ! printf '%s\n' "$out" | grep -q 'old.py' \
  && [ "$r2" -eq 2 ] && printf '%s\n' "$o2" | grep -q '^IMPORT-DIRECTION: 판정 불가 (분기점을 구할 수 없음'; } \
  && ok "D12 FID 모드 — 분기점 이후 파일만 · 새 파일 포함 · 분기점 없음 판정 불가 rc 2" || nope "D12" "rc=$rc out=$out r2=$r2 o2=$o2"

# D13 (배선): 검증 러너가 evidence.md 에 절을 남기고 경고를 내지만 VERIFY PASS·rc 0 은 그대로다
D="$ROOT/d13"; _grepo "$D"; VF=20261021-f
mkdir -p "$D/scripts/tests"; printf '#!/usr/bin/env bash\nexit 0\n' > "$D/scripts/tests/dummy.sh"; chmod +x "$D/scripts/tests/dummy.sh"
printf -- '- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy.sh`\n' > "$D/.specops/$VF/tasks.md"
printf 'from src.adapters.db import X\n' > "$D/src/domain/new.py"
out=$(cd "$D" && bash "$RV" "$VF" 2>"$ROOT/d13.err"); rc=$?; err=$(cat "$ROOT/d13.err")
ev="$D/.specops/$VF/evidence.md"
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && grep -qx '### import-direction' "$ev" \
  && grep -qF '[역방향] src/domain/new.py:1 → src/adapters/db.py' "$ev" \
  && printf '%s\n' "$err" | grep -qF 'WARN: import 방향·순환 — 경고만(차단 아님)'; } \
  && ok "D13 run-verification — evidence 절 · 경고 · VERIFY PASS·rc 0 불변" || nope "D13" "rc=$rc out=$out err=$err"

# D14: 템플릿 — 허용 의존 칸이 화살표 형식을 안내하고 자리표시자로 남는다(경계 대조의 '칸 자리표시자' 판정 유지)
TPL="$PLUGIN/templates/plan.md"
{ grep -F -- '- **허용 의존**: <' "$TPL" | grep -qF '화살표로 적으면 검증 때 실제 import 와 대조한다(경고 전용)' \
  && grep -F -- '- **허용 의존**: <' "$TPL" | grep -qF '`src/domain/` → 없음'; } \
  && ok "D14 plan 템플릿 허용 의존 칸 — 화살표 안내 · 자리표시자 유지" || nope "D14" "templates/plan.md 허용 의존 칸"

# ── 오탐 회귀 (Phase C 리뷰 실측 7종) — 각 케이스는 고치기 전 판정기에서 WARN 이 났다 ──

# F1: 표준 라이브러리 이름은 같은 이름의 선언 폴더로 풀지 않는다(types · email) · __init__.py 없는 폴더는 모듈이 아니다
D="$ROOT/f1"; mkdir -p "$D/app/types" "$D/app/domain" "$D/src/adapters/email" "$D/src/app"
_plan "$D/plan.md" '`app/types/` → 없음 · `app/domain/` → 없음 · `src/adapters/` → 없음 · `src/adapters/stripe/` → 없음 · `src/app/` → 없음'
: > "$D/app/types/__init__.py"; printf 'from types import SimpleNamespace\n' > "$D/app/domain/m.py"
printf 'X = 1\n' > "$D/src/adapters/email/sender.py"; printf 'import email\n' > "$D/src/app/notify.py"
mkdir -p "$D/src/adapters/stripe"; printf 'X = 1\n' > "$D/src/adapters/stripe/client.py"; printf 'import stripe\n' > "$D/src/app/pay.py"   # 서드파티 이름 · __init__ 없는 폴더
out=$(_run "$D")
printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK (역방향 0 ' && ok "F1 표준 라이브러리(types·email)·서드파티(stripe) 이름 — 로컬 폴더로 풀지 않음" || nope "F1" "$out"

# F2: 여러 줄 괄호 import(black·isort 출력) — 한 줄로 쓴 것과 같은 판정(패키지 __init__ 으로 떨어져 순환을 만들지 않는다)
D="$ROOT/f2"; mkdir -p "$D/src/pkg"; _plan "$D/plan.md" '<불러 써도 되는 모듈과 방향>'
printf 'from . import a\n' > "$D/src/pkg/__init__.py"
printf 'from . import (\n    b,\n)\n' > "$D/src/pkg/a.py"; printf 'Y = 1\n' > "$D/src/pkg/b.py"
out=$(_run "$D")
{ ! printf '%s\n' "$out" | grep -q '\[순환\]' && printf '%s\n' "$out" | head -1 | grep -q '순환 0 '; } && ok "F2 여러 줄 괄호 import — 하위 모듈 이름 유지 · 순환 오탐 없음" || nope "F2" "$out"

# F3: export type … from 은 타입 간선이다 — 순환에 넣지 않는다
D="$ROOT/f3"; mkdir -p "$D/web"; _plan "$D/plan.md" '<불러 써도 되는 모듈과 방향>'
printf "import { b } from './b'\nexport type A = number\n" > "$D/web/a.ts"; printf "export type { A } from './a'\nexport const b = 1\n" > "$D/web/b.ts"
out=$(_run "$D")
! printf '%s\n' "$out" | grep -q '\[순환\]' && ok "F3 export type … from — 순환 간선 아님" || nope "F3" "$out"
D="$ROOT/f3b"; mkdir -p "$D/web/lib" "$D/web/ui"; _plan "$D/plan.md" '`web/lib/` → 없음 · `web/ui/` → `web/lib/`'
printf 'export type C = number\n' > "$D/web/ui/c.ts"; printf "export type { C } from '../ui/c'\n" > "$D/web/lib/t.ts"
out=$(_run "$D")
printf '%s\n' "$out" | grep -qF '[역방향] web/lib/t.ts:1 → web/ui/c.ts' && ok "F3b export type … from 도 방향 판정에는 넣는다" || nope "F3b" "$out"

# F4: tsconfig 에 baseUrl 이 없으면 bare 이름(config)을 저장소 루트 파일로 풀지 않는다
D="$ROOT/f4"; mkdir -p "$D/web/lib" "$D/config"; _plan "$D/plan.md" '`web/lib/` → 없음 · `config/` → 없음'
printf '{"compilerOptions":{"strict":true}}\n' > "$D/tsconfig.json"
printf "export default 1\n" > "$D/config/index.ts"; printf "import config from 'config'\nexport const a = config\n" > "$D/web/lib/a.ts"
out=$(_run "$D")
printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK (역방향 0 ' && ok "F4 baseUrl 없음 — bare 이름은 외부 패키지" || nope "F4" "$out"

# F5: 문자열·템플릿 리터럴 속 import 꼴은 import 가 아니다(코드 생성기·스냅숏 문자열)
D="$ROOT/f5"; mkdir -p "$D/web/lib" "$D/web/ui"; _plan "$D/plan.md" '`web/lib/` → 없음 · `web/ui/` → `web/lib/`'
printf 'export const b = 1\n' > "$D/web/ui/button.ts"
printf "export const tpl = \`\nimport { Button } from '../ui/button'\n\`\nexport const msg = \"run: import x from '../ui/button'\"\n" > "$D/web/lib/gen.ts"
out=$(_run "$D")
printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK (역방향 0 ' && ok "F5 문자열·템플릿 속 import 꼴 무시" || nope "F5" "$out"

# F6: 절 찾기는 경계 대조와 같다 — 펜스 안 예시 칸 무시 · 번호 붙은 제목 · #### 수준
D="$ROOT/f6"; mkdir -p "$D/src/x" "$D/src/y"
printf '# plan\n\n## 2. 파일 구조\n\n```md\n### 경계 약속\n- **허용 의존**: `src/x/` → 없음 · `src/y/` → 없음\n```\n\n#### 2.1 경계 약속\n\n- **허용 의존**: `src/x/` → `src/y/` · `src/y/` → 없음\n' > "$D/plan.md"
printf 'from src.y.m import a\n' > "$D/src/x/k.py"; printf 'a = 1\n' > "$D/src/y/m.py"
out=$(_run "$D")
printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK ' && ok "F6 펜스 안 예시 무시 · 번호 붙은 #### 경계 약속 절을 읽는다" || nope "F6" "$out"

# F7 (배선): 판정기가 판정 줄 없이 죽으면 evidence 에 판정 불가 줄을 앞에 붙인다 — VERIFY PASS·rc 0 은 그대로
D="$ROOT/f7"; _grepo "$D"; VF=20261021-f
mkdir -p "$D/scripts/tests" "$ROOT/f7shim"; printf '#!/usr/bin/env bash\nexit 0\n' > "$D/scripts/tests/dummy.sh"; chmod +x "$D/scripts/tests/dummy.sh"
printf -- '- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy.sh`\n' > "$D/.specops/$VF/tasks.md"
_realpy=$(command -v python3)
printf '#!/usr/bin/env bash\nif [ "${1:-}" = "-E" ] && [ "${2:-}" = "-" ]; then echo "Traceback (most recent call last): boom"; exit 1; fi\nexec %s "$@"\n' "$_realpy" > "$ROOT/f7shim/python3"; chmod +x "$ROOT/f7shim/python3"
out=$(cd "$D" && PATH="$ROOT/f7shim:$PATH" bash "$RV" "$VF" 2>/dev/null); rc=$?
ev="$D/.specops/$VF/evidence.md"
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] \
  && awk '/^### import-direction$/{f=1;next} f&&/^```$/{n++; next} f&&n==1{print; exit}' "$ev" | grep -qx 'IMPORT-DIRECTION: 판정 불가 (판정 줄 없음 · rc=1)' \
  && grep -qF 'Traceback (most recent call last): boom' "$ev"; } \
  && ok "F7 판정기 크래시 — evidence 첫 줄 판정 불가 · 원문 보존 · VERIFY PASS·rc 0" || nope "F7" "rc=$rc out=$out ev=$(sed -n '/### import-direction/,/^$/p' "$ev" 2>/dev/null)"

# ── 경계값·형식 ──

# E1: `->` 화살표 · `;` 구분자도 받는다
D="$ROOT/e1"; _py "$D"; _plan "$D/plan.md" '`src/domain/` -> 없음; `src/adapters/` -> `src/domain/`'
printf 'from src.adapters.db import Repo\n' > "$D/src/domain/user.py"; printf 'X = 1\n' > "$D/src/adapters/db.py"
out=$(_run "$D")
printf '%s\n' "$out" | grep -qF '[역방향] src/domain/user.py:1 → src/adapters/db.py' && ok "E1 -> 화살표 · ; 구분자" || nope "E1" "$out"

# E2: TS 의 .js 확장자 import 는 같은 이름의 .ts 로 푼다(ESM 관례)
D="$ROOT/e2"; mkdir -p "$D/web/lib" "$D/web/ui"; _plan "$D/plan.md" '`web/lib/` → 없음 · `web/ui/` → `web/lib/`'
printf 'export const c = 1\n' > "$D/web/ui/c.ts"; printf "import { c } from '../ui/c.js'\n" > "$D/web/lib/a.ts"
out=$(_run "$D")
printf '%s\n' "$out" | grep -qF '[역방향] web/lib/a.ts:1 → web/ui/c.ts' && ok "E2 .js 명시 → .ts 파일" || nope "E2" "$out"

# E3: node_modules 아래 파일은 바뀐 파일이어도 보지 않는다 · 자기 자신 import 는 순환이 아니다
D="$ROOT/e3"; mkdir -p "$D/node_modules/pkg/src/domain" "$D/src/domain" "$D/src/adapters"; _plan "$D/plan.md" "$_layers"
printf 'from src.adapters.db import X\n' > "$D/node_modules/pkg/src/domain/z.py"; printf 'X = 1\n' > "$D/src/adapters/db.py"
printf "import { s } from './self'\nexport const s = 1\n" > "$D/src/domain/self.ts"
mkdir -p "$D/src/domain/node_modules/p"; printf "const d = require('../../../adapters/db.py')\nimport x from '../../../adapters/q'\n" > "$D/src/domain/node_modules/p/i.js"; printf 'export const q = 1\n' > "$D/src/adapters/q.ts"
out=$(_run "$D")
{ ! printf '%s\n' "$out" | grep -q 'node_modules' && ! printf '%s\n' "$out" | grep -q '\[순환\]'; } && ok "E3 node_modules 제외 · 자기 import 는 순환 아님" || nope "E3" "$out"

finish
