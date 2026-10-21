#!/usr/bin/env bash
# API 계약 빈칸·형식 경고 — check-api-contract.sh + run-verification 경고 배선 (20261021-api-contract-check)
#
# IF 설계서(api-spec.md)의 엔드포인트 표(경로 동사·중첩 · Status 열)와 계약 칸(오류 형식·오류 코드·목록 정책·멱등 정책·
# rate limit·버전 전략)을 본다. 경고 전용이다: 위반이 있어도 rc 0 · VERIFY 판정·종료 코드 불변. 칸이 없는 옛 문서는 건너뛴다.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CAC="$PLUGIN/scripts/_internal/check-api-contract.sh"
RV="$PLUGIN/scripts/_internal/run-verification.sh"
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

# 칸을 모두 채운 문서 — $1 에 엔드포인트 표 행을 덧붙인다
_spec() {  # $1=파일 $2=표 행(여러 줄)
  cat > "$1" <<EOF
# IF 설계서

## §1. Markdown 엔드포인트 표

| Method | Path | Auth | Request | Response | Status | 비고 |
|---|---|---|---|---|---|---|
$2

- **오류 형식**: RFC 9457 Problem Details

### 오류 코드 카탈로그

| 코드 | HTTP | 언제 |
|---|---|---|
| ORDER_NOT_FOUND | 404 | 주문이 없다 |

### 목록 정책

- **방식**: cursor
- **기본 크기**: 20
- **최대 크기**: 100

### 멱등 정책

- POST /v1/orders 는 Idempotency-Key 를 받는다 · 나머지 쓰기는 재시도 불안전

## §5. 인증·인가 정책

- **rate limit**: 사용자당 100 req/min

## §6. 버저닝

- **버전 전략**: URL prefix /v1/
EOF
}
_ok_rows='| GET | `/v1/orders` | Bearer | — | `Page<Order>` | 200 · 401 | 목록 |
| GET | `/v1/orders/:id` | Bearer | — | `Order` | 200 · 404 | 단건 |
| POST | `/v1/orders` | Bearer | `CreateOrder` | `Order` | 201 · 409 · 422 | 생성 |
| DELETE | `/v1/orders/:id` | Bearer | — | — | 204 · 404 | 삭제 |'
_run() { bash "$CAC" --spec "$1"; }

# A1: 칸을 모두 채운 깨끗한 문서 → OK · rc 0
_spec "$ROOT/a1.md" "$_ok_rows"
out=$(_run "$ROOT/a1.md"); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "API-CONTRACT: OK (위반 0 · 엔드포인트 4/4 · 건너뜀 0)" ]; } \
  && ok "A1 깨끗한 문서 → OK · 위반 0 · 건너뜀 0" || nope "A1" "rc=$rc out=$out"

# A2: 경로 — 첫 리소스 마디가 동사 · 리소스 중첩 3단계 · 경고여도 rc 0
_spec "$ROOT/a2.md" "$_ok_rows
| POST | \`/v1/createOrder\` | Bearer | — | — | 201 | 동사 |
| GET | \`/v1/users/:id/orders/:oid/items\` | Bearer | — | — | 200 | 중첩 |"
out=$(_run "$ROOT/a2.md"); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^API-CONTRACT: WARN (위반 ' \
  && printf '%s\n' "$out" | grep -qF '[경로] POST /v1/createOrder — 리소스 마디가 동사(createOrder)' \
  && printf '%s\n' "$out" | grep -qF '[경로] GET /v1/users/:id/orders/:oid/items — 리소스 중첩 3단계' \
  && ! printf '%s\n' "$out" | grep -qF '[경로] GET /v1/orders'; } \
  && ok "A2 경로 동사·중첩 3단계 적발 · 정상 경로는 조용 · rc 0" || nope "A2" "rc=$rc out=$out"

# A3: 명명 — 경로 마디에 snake_case 와 camelCase 가 섞임
_spec "$ROOT/a3.md" "$_ok_rows
| GET | \`/v1/order_items\` | Bearer | — | — | 200 | snake |
| GET | \`/v1/shippingLabels\` | Bearer | — | — | 200 | camel |"
out=$(_run "$ROOT/a3.md")
printf '%s\n' "$out" | grep -qF '[명명] 경로 마디에 snake_case 와 camelCase 가 섞였다 — 예: order_items · shippingLabels' \
  && ok "A3 명명 섞임 적발(예시 두 개)" || nope "A3" "$out"
out=$(_run "$ROOT/a1.md")
! printf '%s\n' "$out" | grep -q '\[명명\]' && ok "A3b 한 규약만 쓰면 명명 경고 없음" || nope "A3b" "$out"

# A4: 상태코드 — 빈칸 · POST 에 성공 코드 없음 · DELETE 에 성공 코드 없음
_spec "$ROOT/a4.md" "| GET | \`/v1/carts/:id\` | Bearer | — | — |  | 빈칸 |
| POST | \`/v1/carts\` | Bearer | — | — | 409 · 422 | 성공 없음 |
| DELETE | \`/v1/carts/:id\` | Bearer | — | — | 404 | 성공 없음 |"
out=$(_run "$ROOT/a4.md")
{ printf '%s\n' "$out" | grep -qF '[상태코드] GET /v1/carts/:id — 상태코드 칸이 비었다' \
  && printf '%s\n' "$out" | grep -qF '[상태코드] POST /v1/carts — 성공 코드(201·202·200) 없음' \
  && printf '%s\n' "$out" | grep -qF '[상태코드] DELETE /v1/carts/:id — 성공 코드(204·202·200) 없음'; } \
  && ok "A4 상태코드 빈칸·POST·DELETE 성공 코드 누락 적발" || nope "A4" "$out"

# A5: 옛 문서 — Status 열·정책 칸이 없으면 그 규칙은 건너뛴다(경고로 덮지 않는다)
cat > "$ROOT/a5.md" <<'EOF'
## §1. Markdown 엔드포인트 표

| Method | Path | Auth | Request | Response | 비고 |
|---|---|---|---|---|---|
| GET | `/v1/users` | Bearer | — | `User[]` | 목록 |
| POST | `/v1/users` | Bearer | `CreateUser` | `User` | 생성 |
EOF
out=$(_run "$ROOT/a5.md"); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "API-CONTRACT: OK (위반 0 · 엔드포인트 2/2 · 건너뜀 7)" ] \
  && printf '%s\n' "$out" | grep -qF '[건너뜀] 상태코드(엔드포인트 표에 상태코드 열 없음)' \
  && printf '%s\n' "$out" | grep -qF '[건너뜀] 페이지(「목록 정책」 절 없음)' \
  && printf '%s\n' "$out" | grep -qF '[건너뜀] 멱등(「멱등 정책」 절 없음)' \
  && ! printf '%s\n' "$out" | grep -qE '\[(상태코드|페이지|멱등|미정)\]'; } \
  && ok "A5 옛 문서 — 칸 없는 규칙은 [건너뜀] · 위반 0" || nope "A5" "rc=$rc out=$out"

# A6: 목록 정책 — 목록 엔드포인트가 있는데 최대 크기가 자리표시자 · 단건 GET 만 있으면 묻지 않는다
_spec "$ROOT/a6.md" "$_ok_rows"; sed -i.bak 's/- \*\*최대 크기\*\*: 100/- **최대 크기**: <100>/' "$ROOT/a6.md"
out=$(_run "$ROOT/a6.md")
_spec "$ROOT/a6b.md" '| GET | `/v1/orders/:id` | Bearer | — | `Order` | 200 · 404 | 단건 |'; sed -i.bak 's/- \*\*최대 크기\*\*: 100/- **최대 크기**: <100>/' "$ROOT/a6b.md"
out2=$(_run "$ROOT/a6b.md")
{ printf '%s\n' "$out" | grep -qF '[페이지] 목록 엔드포인트 1개(GET /v1/orders …) — 「목록 정책」의 최대 페이지 크기가 없다' \
  && ! printf '%s\n' "$out2" | grep -q '\[페이지\]'; } \
  && ok "A6 목록 최대 크기 자리표시자 적발 · 단건만이면 묻지 않음" || nope "A6" "out=$out out2=$out2"

# A7: 멱등 정책 — 쓰기 엔드포인트가 있는데 정책이 자리표시자
_spec "$ROOT/a7.md" "$_ok_rows"
python3 - "$ROOT/a7.md" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"(### 멱등 정책\n\n)- .*\n", r"\1- <상태를 바꾸는 엔드포인트마다 둘 중 하나>\n", s); open(p,"w").write(s)
PY
out=$(_run "$ROOT/a7.md")
printf '%s\n' "$out" | grep -qF '[멱등] 상태를 바꾸는 엔드포인트 2개 — 「멱등 정책」이 비었다' \
  && ok "A7 멱등 정책 자리표시자 적발(쓰기 2개)" || nope "A7" "$out"

# A8: 미정 — 오류 형식·버전 전략 자리표시자 · 오류 코드 카탈로그에 코드 행 없음
_spec "$ROOT/a8.md" "$_ok_rows"
sed -i.bak -e 's/- \*\*오류 형식\*\*: RFC 9457 Problem Details/- **오류 형식**: <RFC 9457 \/ 자체 envelope>/' \
  -e 's/- \*\*버전 전략\*\*: URL prefix \/v1\//- **버전 전략**: <URL \/ 헤더>/' -e 's/^| ORDER_NOT_FOUND | 404 | 주문이 없다 |$/| <ERROR_CODE> | <4xx> | <언제> |/' "$ROOT/a8.md"
out=$(_run "$ROOT/a8.md")
{ printf '%s\n' "$out" | grep -qF '[미정] 오류 형식 — 칸이 비었거나 자리표시자(<RFC 9457 / 자체 envelope>)' \
  && printf '%s\n' "$out" | grep -qF '[미정] 버전 전략 — 칸이 비었거나 자리표시자(<URL / 헤더>)' \
  && printf '%s\n' "$out" | grep -qF '[미정] 오류 코드 — 「오류 코드 카탈로그」 표에 코드 행이 없다' \
  && ! printf '%s\n' "$out" | grep -qF '[미정] rate limit'; } \
  && ok "A8 오류 형식·버전 전략 자리표시자 · 오류 코드 행 없음 적발 · 채운 칸은 조용" || nope "A8" "$out"

# A9: 예시 블록(specops:example) 안의 행은 보지 않는다 · 템플릿 그대로면 칸 자리표시자만 경고
out=$(_run "$PLUGIN/templates/api-spec.md"); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^API-CONTRACT: WARN (위반 4 · 엔드포인트 0/0 · ' \
  && printf '%s\n' "$out" | grep -qF '[미정] 오류 형식' && printf '%s\n' "$out" | grep -qF '[미정] 버전 전략' && printf '%s\n' "$out" | grep -qF '[미정] rate limit' \
  && ! printf '%s\n' "$out" | grep -qE '\[(경로|상태코드)\]'; } \
  && ok "A9 템플릿 — 예시 행 무시 · 칸 자리표시자 4건만 경고(rate limit 포함)" || nope "A9" "rc=$rc out=$out"

# A10: api-spec 부재 → SKIP rc 0 · 판정할 칸이 없는 문서 → SKIP · 사용 오류 rc 1
out=$(bash "$CAC" --spec "$ROOT/none.md"); rc=$?
printf '# 메모\n\n그냥 글\n' > "$ROOT/a10.md"; out2=$(_run "$ROOT/a10.md"); rc2=$?
bash "$CAC" >/dev/null 2>&1; rc3=$?; bash "$CAC" 'bad fid' >/dev/null 2>&1; rc4=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^API-CONTRACT: SKIP (api-spec.md 부재' \
  && [ "$rc2" -eq 0 ] && printf '%s\n' "$out2" | grep -q '^API-CONTRACT: SKIP (판정할 칸이 없다' && [ "$rc3" -eq 1 ] && [ "$rc4" -eq 1 ]; } \
  && ok "A10 부재·칸 없음 SKIP rc 0 · 사용 오류 rc 1" || nope "A10" "rc=$rc out=$out rc2=$rc2 out2=$out2 rc3=$rc3 rc4=$rc4"

# A11: FID 모드 — api-spec 이 git 추적 중이면 분기점 이후 바뀐 행만 본다 · 추적 밖이면 전체 행 + [범위]
D="$ROOT/a11"; mkdir -p "$D/.specops/memory" "$D/.specops/20261021-f"
_spec "$D/.specops/memory/api-spec.md" "$_ok_rows
| POST | \`/v1/createLegacy\` | Bearer | — | — | 201 | 옛 위반 |"
( cd "$D" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && git checkout -qb feat )
printf '| POST | `/v1/createNew` | Bearer | — | — | 201 | 새 위반 |\n' > "$ROOT/newrow"
python3 - "$D/.specops/memory/api-spec.md" "$ROOT/newrow" <<'PY'
import sys
p,n=sys.argv[1],sys.argv[2]; s=open(p).read(); r=open(n).read()
s=s.replace("| 옛 위반 |\n","| 옛 위반 |\n"+r,1); open(p,"w").write(s)
PY
out=$(cd "$D" && bash "$CAC" 20261021-f); rc=$?
D2="$ROOT/a11b"; mkdir -p "$D2/.specops/memory"; cp "$D/.specops/memory/api-spec.md" "$D2/.specops/memory/"
out2=$(cd "$D2" && bash "$CAC" 20261021-f); rc2=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qF '[경로] POST /v1/createNew' && ! printf '%s\n' "$out" | grep -qF 'createLegacy' \
  && ! printf '%s\n' "$out" | grep -q '\[범위\]' \
  && [ "$rc2" -eq 0 ] && printf '%s\n' "$out2" | grep -qF 'createLegacy' && printf '%s\n' "$out2" | grep -qF '[범위] 전체 행'; } \
  && ok "A11 FID 모드 — 추적 중이면 바뀐 행만 · 추적 밖이면 전체 행 + [범위]" || nope "A11" "rc=$rc out=$out rc2=$rc2 out2=$out2"

# A12 (배선): 검증 러너가 evidence.md 에 절을 남기고 경고를 내지만 VERIFY PASS·rc 0 은 그대로다
D="$ROOT/a12"; VF=20261021-f; mkdir -p "$D/.specops/memory" "$D/.specops/$VF" "$D/scripts/tests"
_spec "$D/.specops/memory/api-spec.md" "$_ok_rows"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D/scripts/tests/dummy.sh"; chmod +x "$D/scripts/tests/dummy.sh"
printf -- '- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy.sh`\n' > "$D/.specops/$VF/tasks.md"
( cd "$D" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && git checkout -qb feat )
# 이 FID 가 위반 행을 더한다(분기점 이후 바뀐 행만 본다)
python3 - "$D/.specops/memory/api-spec.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("| 204 · 404 | 삭제 |\n","| 204 · 404 | 삭제 |\n| POST | `/v1/createThing` | Bearer | — | — | 201 | 동사 |\n",1); open(p,"w").write(s)
PY
out=$(cd "$D" && bash "$RV" "$VF" 2>"$ROOT/a12.err"); rc=$?; err=$(cat "$ROOT/a12.err")
ev="$D/.specops/$VF/evidence.md"
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && grep -qx '### api-contract' "$ev" \
  && grep -qF '[경로] POST /v1/createThing' "$ev" \
  && printf '%s\n' "$err" | grep -qF 'WARN: API 계약 빈칸·형식 — 경고만(차단 아님)'; } \
  && ok "A12 run-verification — evidence 절 · 경고 · VERIFY PASS·rc 0 불변" || nope "A12" "rc=$rc out=$out err=$err"

# A13 (배선): specifying Step 5.6 이 판정기를 부르고 막지 않는다 · 템플릿이 칸 계약을 안내한다
SP="$PLUGIN/skills/specifying-ko/SKILL.md"
{ grep -qF 'scripts/_internal/check-api-contract.sh <FID>' "$SP" && grep -qF '막지 않는다 — 종료 코드와 무관하게 Step 6 진행' "$SP" \
  && grep -qF '| Method | Path | Auth | Request | Response | Status | 비고 |' "$PLUGIN/templates/api-spec.md" \
  && grep -q '^### 목록 정책' "$PLUGIN/templates/api-spec.md" && grep -q '^### 멱등 정책' "$PLUGIN/templates/api-spec.md" \
  && grep -q '^### 오류 코드 카탈로그' "$PLUGIN/templates/api-spec.md" && grep -qF -- '- **버전 전략**:' "$PLUGIN/templates/api-spec.md"; } \
  && ok "A13 Step 5.6 판정기 호출(비차단) · 템플릿 칸 계약(Status 열·오류 코드·목록·멱등·버전 전략)" || nope "A13" "specifying 또는 템플릿 문구 누락"

# ── Phase B·C 리뷰 반영 (20261021) ──
# A14: 동사는 모든 리소스 마디에서 · /api 접두는 리소스로 세지 않는다(중첩 오탐·동사 미탐 둘 다 막는다)
_spec "$ROOT/a14.md" "$_ok_rows
| GET | \`/v1/users/:id/getOrders\` | Bearer | — | — | 200 | 둘째 마디 동사 |
| GET | \`/api/v1/users/:id/orders\` | Bearer | — | — | 200 | api 접두 정상 |
| POST | \`/api/createUser\` | Bearer | — | — | 201 | api 뒤 동사 |
| POST | \`/auth/login\` | — | — | — | 200 | 정상 |
| GET | \`/me\` | Bearer | — | — | 200 | 정상 |"
out=$(_run "$ROOT/a14.md")
{ printf '%s\n' "$out" | grep -qF '[경로] GET /v1/users/:id/getOrders — 리소스 마디가 동사(getOrders)' \
  && printf '%s\n' "$out" | grep -qF '[경로] POST /api/createUser — 리소스 마디가 동사(createUser)' \
  && ! printf '%s\n' "$out" | grep -qF '/api/v1/users/:id/orders' && ! printf '%s\n' "$out" | grep -qE '\[경로\] (POST /auth/login|GET /me)'; } \
  && ok "A14 둘째 마디 동사 · /api 뒤 동사 적발 · /api 접두·/auth/login·/me 는 조용" || nope "A14" "$out"

# A15: 꾸민 칸(백틱·굵게 메서드 · 백틱 오류 코드) · 셀 안의 이스케이프 파이프
_spec "$ROOT/a15.md" "$_ok_rows
| \`POST\` | \`/v1/createThing\` | Bearer | — | — | 201 | 백틱 메서드 |
| **DELETE** | \`/v1/things/:id\` | Bearer | — | — | 404 | 굵게 메서드 |
| PATCH | \`/v1/things/:id\` | Bearer | \`{a: \"x\\|y\"}\` | \`Thing \\| null\` | 200 · 422 | 이스케이프 파이프 |"
sed -i.bak 's/^| ORDER_NOT_FOUND | 404 | 주문이 없다 |$/| `ORDER_NOT_FOUND` | 404 | 주문이 없다 |/' "$ROOT/a15.md"
out=$(_run "$ROOT/a15.md")
{ printf '%s\n' "$out" | grep -qF '[경로] POST /v1/createThing' && printf '%s\n' "$out" | grep -qF '[상태코드] DELETE /v1/things/:id — 성공 코드' \
  && ! printf '%s\n' "$out" | grep -qF '[상태코드] PATCH' && ! printf '%s\n' "$out" | grep -qF '[미정] 오류 코드'; } \
  && ok "A15 백틱·굵게 메서드 칸 읽음 · 백틱 오류 코드 인정 · 이스케이프 파이프는 칸을 밀지 않음" || nope "A15" "$out"

# A16: 멱등은 엔드포인트별 — 경로로 언급되지 않은 쓰기를 짚고, 전체 적용 문장(모든·나머지)은 통과
_spec "$ROOT/a16.md" "$_ok_rows"
sed -i.bak 's/^- POST \/v1\/orders 는 Idempotency-Key 를 받는다 · 나머지 쓰기는 재시도 불안전$/- POST \/v1\/orders 는 Idempotency-Key 를 받는다/' "$ROOT/a16.md"
out=$(_run "$ROOT/a16.md"); out2=$(_run "$ROOT/a1.md")
{ printf '%s\n' "$out" | grep -qF '[멱등] 상태를 바꾸는 엔드포인트 1개가 「멱등 정책」에 없다' && printf '%s\n' "$out" | grep -qF 'DELETE /v1/orders/:id' \
  && ! printf '%s\n' "$out2" | grep -q '\[멱등\]'; } \
  && ok "A16 멱등 엔드포인트별 — 언급 없는 DELETE 적발 · '나머지' 전체 적용 문장은 통과" || nope "A16" "out=$out out2=$out2"

# A17: 판정 불가(rc 2) — 읽을 수 없는 문서(디렉터리) · 닫히지 않은 코드 펜스 · 펜스 안의 표는 보지 않는다
mkdir -p "$ROOT/a17dir"; out=$(bash "$CAC" --spec "$ROOT/a17dir"); rc=$?
ln -s "$ROOT/does-not-exist.md" "$ROOT/a17link.md"; outL=$(bash "$CAC" --spec "$ROOT/a17link.md"); rcL=$?   # 셸 쪽 판정 불가(따라갈 수 없는 링크)
_spec "$ROOT/a17.md" "$_ok_rows"; printf '\n```\n| GET | `/v1/createX` | — | — | — | 200 | 펜스 안 |\n' >> "$ROOT/a17.md"; out2=$(_run "$ROOT/a17.md"); rc2=$?
_spec "$ROOT/a17b.md" "$_ok_rows"; printf '\n````\n```\n| Method | Path | Status |\n|---|---|---|\n| POST | `/v1/createY` | 201 |\n```\n````\n' >> "$ROOT/a17b.md"; out3=$(_run "$ROOT/a17b.md"); rc3=$?
{ [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q '^API-CONTRACT: 판정 불가' \
  && [ "$rcL" -eq 2 ] && printf '%s\n' "$outL" | grep -q '^API-CONTRACT: 판정 불가 (api-spec 을 따라갈 수 없는 심볼릭 링크' \
  && [ "$rc2" -eq 2 ] && printf '%s\n' "$out2" | grep -q '^API-CONTRACT: 판정 불가 (닫히지 않은 코드 펜스' \
  && [ "$rc3" -eq 0 ] && ! printf '%s\n' "$out3" | grep -qF 'createY' && printf '%s\n' "$out3" | head -1 | grep -q '^API-CONTRACT: OK'; } \
  && ok "A17 판정 불가 rc 2(읽기 불가·깨진 링크·닫히지 않은 펜스) · 4백틱 펜스 안 3백틱·표는 무시" || nope "A17" "rc=$rc out=$out rc2=$rc2 out2=$out2 rc3=$rc3 out3=$out3"

# A18: batch 경로 — api-spec 을 커밋한 뒤 review-base.sha 가 기록돼도 이 FID 가 더한 행을 본다(merge-base 기준)
D="$ROOT/a18"; mkdir -p "$D/.specops/memory" "$D/.specops/20261021-f"
_spec "$D/.specops/memory/api-spec.md" "$_ok_rows"
( cd "$D" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && git checkout -qb feat )
python3 - "$D/.specops/memory/api-spec.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("| 204 · 404 | 삭제 |\n","| 204 · 404 | 삭제 |\n| POST | `/v1/createBatch` | Bearer | — | — | 201 | batch 새 행 |\n",1); open(p,"w").write(s)
PY
( cd "$D" && git add -A && git -c user.email=t@t -c user.name=t commit -qm spec && git rev-parse HEAD > .specops/20261021-f/review-base.sha )
out=$(cd "$D" && bash "$CAC" 20261021-f)
printf '%s\n' "$out" | grep -qF '[경로] POST /v1/createBatch' \
  && ok "A18 batch — review-base.sha 가 api-spec 커밋 뒤여도 새 행을 본다" || nope "A18" "$out"

# A19: 표기 변형 — 굵게 없는 '최대 크기' · 대소문자 다른 'Rate Limit' · 표 없는 문서는 경로·상태코드 [건너뜀]
_spec "$ROOT/a19.md" "$_ok_rows"; sed -i.bak -e 's/^- \*\*최대 크기\*\*: 100$/- 최대 크기: 100/' -e 's/- \*\*rate limit\*\*/- **Rate Limit**/' "$ROOT/a19.md"
out=$(_run "$ROOT/a19.md")
printf -- '- **오류 형식**: RFC 9457\n- **버전 전략**: URL\n' > "$ROOT/a19b.md"; out2=$(_run "$ROOT/a19b.md")
{ ! printf '%s\n' "$out" | grep -qE '\[(페이지|건너뜀)\]' && printf '%s\n' "$out2" | grep -qF '[건너뜀] 경로·상태코드(§1 Markdown 엔드포인트 표 없음'; } \
  && ok "A19 굵게 없는 최대 크기·대소문자 다른 Rate Limit 인정 · 표 없는 문서는 경로·상태코드 [건너뜀]" || nope "A19" "out=$out out2=$out2"

finish
