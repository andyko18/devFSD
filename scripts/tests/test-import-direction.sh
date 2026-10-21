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
  && ! printf '%s\n' "$out" | grep -q '\[순환\]' && printf '%s\n' "$out" | head -1 | grep -q 'WARN (역방향 1 · 순환 0 · '; } \
  && ok "D7 TS 별칭 해석 · 주석 무시 · import type 은 방향만" || nope "D7" "$out"

# D8: 풀지 못한 import(별칭 없이 @/ · 동적 require) 는 미해석으로 센다 — OK 여도 줄이 남는다
D="$ROOT/d8"; mkdir -p "$D/web/ui"; _plan "$D/plan.md" '`web/ui/` → 없음'
printf "import { x } from '@/missing'\nconst m = require(name)\nimport React from 'react'\n" > "$D/web/ui/p.ts"
out=$(_run "$D")
{ printf '%s\n' "$out" | head -1 | grep -q '^IMPORT-DIRECTION: OK ' && printf '%s\n' "$out" | grep -q '^  \[미해석\] 2건 — web/ui/p.ts:1 '"'"'@/missing'"'"; } \
  && ok "D8 미해석 2건(별칭 없음·동적) — 지킴으로 치지 않고 따로 적는다" || nope "D8" "$out"

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
out=$(cd "$D" && bash "$CID" 20261021-f); rc=$?
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

finish
