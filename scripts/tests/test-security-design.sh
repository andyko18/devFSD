#!/usr/bin/env bash
# 보안 설계 칸 + 판정기 — check-security-design.sh · 템플릿 보안 칸 · 검증 러너 경고 배선 (20261021-security-design-checker)
#
# IF 설계서(api-spec.md)·테이블 설계서(data-model.md)의 보안 결정 칸과, 문서만 보고 알 수 있는 보안 설계 결함(Auth 빈칸·URL 민감정보·
# 응답 민감 필드·CORS `*`+credentials·위험 기능 결정 누락)을 본다. 경고 전용이다: 위반이 있어도 rc 0 · VERIFY 판정·종료 코드 불변.
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES   # 훅 환경 격리 — 직접 실행돼도 픽스처가 실저장소를 건드리지 않게 (test-git-hooks GH-env.4 가 잠근다)
PASS=0; FAIL=0
PLUGIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source "$PLUGIN/scripts/tests/harness.sh"
command -v finish >/dev/null 2>&1 || { echo "FATAL: harness 미로드" >&2; exit 1; }
CSD="$PLUGIN/scripts/_internal/check-security-design.sh"
RV="$PLUGIN/scripts/_internal/run-verification.sh"
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

# 보안 칸을 모두 채운 IF 설계서 — $2 에 엔드포인트 표 행을 덧붙인다
_api() {  # $1=파일 $2=표 행(여러 줄)
  cat > "$1" <<EOF
# IF 설계서

## §1. Markdown 엔드포인트 표

| Method | Path | Auth | Request | Response | Status | 비고 |
|---|---|---|---|---|---|---|
$2

## §5. 인증·인가 정책

- **인증 방식**: Bearer 헤더 · access 15분 · refresh 는 httpOnly 쿠키 · 로그아웃 시 refresh 폐기
- **권한 모델**: RBAC admin·user · 주문은 소유자만(서비스 계층에서 확인)
- **CORS**: https://app.example.com 만 · credentials 사용
- **CSRF**: 해당 없음(헤더 토큰 인증)
- **rate limit**: 사용자당 100 req/min

### 위험 기능 결정

- **업로드**: 해당 없음
- **웹훅 수신**: 해당 없음
- **외부 URL 가져오기**: 해당 없음
- **LLM 호출**: 해당 없음

## §6. 버저닝

- **버전 전략**: URL prefix /v1/
EOF
}
_dm() {  # $1=파일
  cat > "$1" <<'EOF'
# 테이블 설계서

## §8. 데이터 보호

- **개인정보 분류**: users.email = PII · orders = 비개인
- **보존·삭제**: 탈퇴 후 30일 hard delete · 백업은 35일 순환
EOF
}
_ok_rows='| GET | `/v1/orders` | Bearer | `?cursor=&limit=` | `Page<Order>` | 200 · 401 | 목록 |
| GET | `/v1/orders/:id` | Bearer · owner | — | `Order` | 200 · 404 | 단건 |
| POST | `/v1/auth/token` | 없음(공개) | `LoginDto` | `{ accessToken, expiresIn }` | 200 · 401 | 로그인 |
| GET | `/v1/files?pageToken=` | Bearer | — | `Page<File>` | 200 | 페이지 커서 |'
_run() { bash "$CSD" --spec "$@" --all-rows; }
_has() { printf '%s\n' "$1" | grep -qF -- "$2"; }

# ── S1 템플릿 보안 칸 (AC-1) ──
TA="$PLUGIN/templates/api-spec.md"; TD="$PLUGIN/templates/data-model.md"
out=$(bash "$CSD" --spec "$TA" --data-model "$TD" --all-rows); rc=$?
{ [ "$rc" -eq 0 ] && grep -qE '^- \*\*인증 방식\*\*: <.+>$' "$TA" && grep -qE '^- \*\*권한 모델\*\*: <.+>$' "$TA" \
  && grep -qE '^- \*\*CORS\*\*: <.+>$' "$TA" && grep -qE '^- \*\*CSRF\*\*: <.+>$' "$TA" && grep -q '^### 위험 기능 결정$' "$TA" \
  && grep -qE '^- \*\*업로드\*\*: <' "$TA" && grep -qE '^- \*\*웹훅 수신\*\*: <' "$TA" && grep -qE '^- \*\*외부 URL 가져오기\*\*: <' "$TA" && grep -qE '^- \*\*LLM 호출\*\*: <' "$TA" \
  && grep -qE '^- \*\*개인정보 분류\*\*: <.+>$' "$TD" && grep -qE '^- \*\*보존·삭제\*\*: <.+>$' "$TD" \
  && [ "$(printf '%s\n' "$out" | grep -c '^  \[미정\] ')" -eq 6 ] \
  && _has "$out" '[미정] 인증 방식 —' && _has "$out" '[미정] 권한 모델 —' && _has "$out" '[미정] CORS —' && _has "$out" '[미정] CSRF —' \
  && _has "$out" '[미정] 개인정보 분류 —' && _has "$out" '[미정] 보존·삭제 —' \
  && ! printf '%s\n' "$out" | grep -qE '\[건너뜀\] (인증 방식|권한 모델|CORS|CSRF|개인정보 분류|보존·삭제|승인 대상)'; } \
  && ok "S1 템플릿 — 보안 칸 10개 · 판정기 [미정] 6건 · 칸 규칙 건너뜀 없음" || nope "S1" "rc=$rc out=$out"
grep -qF '**Auth 열** (`check-security-design.sh` 가 읽는다 — 경고 전용): 공개면 `없음(공개)`' "$TA" \
  && ok "S1b 템플릿 §1 — Auth 열 값 규칙 안내" || nope "S1b" "Auth 열 안내 문장 없음"

# ── S2 판정 규칙 (AC-2) ──
_api "$ROOT/ok.md" "$_ok_rows"; _dm "$ROOT/dm.md"
out=$(_run "$ROOT/ok.md" --data-model "$ROOT/dm.md"); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "SECURITY-DESIGN: OK (위반 0 · 엔드포인트 4/4 · 건너뜀 0)" ]; } \
  && ok "S2a 깨끗한 문서 → OK · 고정 경로 /auth/token·로그인 accessToken·pageToken 은 조용" || nope "S2a" "rc=$rc out=$out"

_api "$ROOT/s2b.md" "$_ok_rows
| DELETE | \`/v1/orders/:id\` |  | — | — | 204 | 빈칸 |
| PATCH | \`/v1/orders/:id\` | — | — | — | 200 | 대시 |
| GET | \`/v1/admin/stats\` | <역할> | — | — | 200 | 자리표시자 |"
printf '\n## §4. 내보내는 호출\n\n| Method | Path | 비고 |\n|---|---|---|\n| POST | `/hooks/out` | Auth 열 없는 표 |\n' >> "$ROOT/s2b.md"
out=$(_run "$ROOT/s2b.md"); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | head -1 | grep -q '^SECURITY-DESIGN: WARN (위반 3 ' \
  && _has "$out" '[인증] DELETE /v1/orders/:id — Auth 칸이 비었다' && _has "$out" '[인증] PATCH /v1/orders/:id — Auth 칸이 비었다' \
  && _has "$out" '[인증] GET /v1/admin/stats — Auth 칸이 비었다' && ! _has "$out" '[인증] POST /v1/auth/token' && ! _has "$out" '/hooks/out'; } \
  && ok "S2b [인증] 빈칸·대시·자리표시자 적발 · 없음(공개)·Auth 열 없는 표의 행은 조용 · rc 0" || nope "S2b" "rc=$rc out=$out"

_api "$ROOT/s2c.md" "$_ok_rows
| POST | \`/v1/password-reset/:token\` | 없음(공개) | — | — | 204 | 경로 토큰 |
| GET | \`/v1/export?apiKey=\` | Bearer | — | — | 200 | 쿼리 키 |
| GET | \`/v1/session\` | Bearer | \`?session_id=\` | — | 200 | 요청 칸 쿼리 |
| POST | \`/v1/login\` | 없음(공개) | \`?password=\` | — | 200 | 본문 메서드의 요청 칸 |"
out=$(_run "$ROOT/s2c.md")
{ _has "$out" '[URL 민감정보] POST /v1/password-reset/:token — token —' && _has "$out" '[URL 민감정보] GET /v1/export?apiKey= — apiKey —' \
  && _has "$out" '[URL 민감정보] GET /v1/session — session_id —' && [ "$(printf '%s\n' "$out" | grep -c '\[URL 민감정보\]')" -eq 3 ]; } \
  && ok "S2c [URL 민감정보] 경로·쿼리·GET 요청 칸 파라미터 적발 · 고정 마디·페이지 커서·POST 요청 칸은 조용" || nope "S2c" "$out"

_api "$ROOT/s2d.md" "$_ok_rows
| GET | \`/v1/users/:id\` | Bearer | — | \`{ id, email, passwordHash }\` | 200 | 해시 |
| POST | \`/v1/apps\` | Bearer · admin | — | \`{ id, client_secret }\` | 201 | 비밀 |
| GET | \`/v1/secrets/:id\` | Bearer · admin | — | \`Secret\` | 200 | 타입 이름 |
| GET | \`/v1/me\` | Bearer | — | \`{ id, hasPassword }\` | 200 | 불리언 |"
out=$(_run "$ROOT/s2d.md")
{ _has "$out" '[응답 민감 필드] GET /v1/users/:id — passwordHash —' && _has "$out" '[응답 민감 필드] POST /v1/apps — client_secret —' \
  && [ "$(printf '%s\n' "$out" | grep -c '\[응답 민감 필드\]')" -eq 2 ]; } \
  && ok "S2d [응답 민감 필드] passwordHash·client_secret 적발 · 타입 이름 Secret·accessToken·불리언 hasPassword 는 조용" || nope "S2d" "$out"

_api "$ROOT/s2e.md" "$_ok_rows"; sed -i.bak 's/^- \*\*CORS\*\*: .*/- **CORS**: `*` · credentials: true/' "$ROOT/s2e.md"
_api "$ROOT/s2e2.md" "$_ok_rows"; sed -i.bak 's/^- \*\*CORS\*\*: .*/- **CORS**: * (공개 읽기 API) · credentials 미사용/' "$ROOT/s2e2.md"
out=$(_run "$ROOT/s2e.md"); out2=$(_run "$ROOT/s2e2.md")
{ _has "$out" '[CORS] 허용 origin `*` 와 credentials 를 함께 쓴다' && ! _has "$out2" '[CORS]'; } \
  && ok "S2e [CORS] * + credentials 적발 · credentials 미사용이면 조용" || nope "S2e" "out=$out out2=$out2"

_api "$ROOT/s2f.md" "$_ok_rows"; sed -i.bak -e 's/^- \*\*권한 모델\*\*: .*/- **권한 모델**: <역할·권한 목록>/' -e 's/^- \*\*CSRF\*\*: .*/- **CSRF**:/' "$ROOT/s2f.md"
_dm "$ROOT/s2f-dm.md"; sed -i.bak 's/^- \*\*보존·삭제\*\*: .*/- **보존·삭제**: TBD/' "$ROOT/s2f-dm.md"
out=$(_run "$ROOT/s2f.md" --data-model "$ROOT/s2f-dm.md")
{ _has "$out" '[미정] 권한 모델 — 칸이 비었거나 자리표시자(<역할·권한 목록>)' && _has "$out" '[미정] CSRF — 칸이 비었거나 자리표시자(빈 값)' \
  && _has "$out" '[미정] 보존·삭제 — 칸이 비었거나 자리표시자(TBD)' && ! _has "$out" '[미정] 인증 방식' && ! _has "$out" '[미정] 개인정보 분류'; } \
  && ok "S2f [미정] 자리표시자·빈 값·TBD 적발(api-spec·data-model) · 채운 칸은 조용" || nope "S2f" "$out"

# ── S3 위험 기능 신호는 경로에서만 (AC-3 · AC-8) ──
_api "$ROOT/s3.md" "$_ok_rows
| POST | \`/v1/files/upload\` | Bearer | \`multipart\` | \`File\` | 201 | 업로드 |"
sed -i.bak -e 's/^- \*\*업로드\*\*: .*/- **업로드**: <해당 없음 \/ 허용 형식>/' -e 's/^- \*\*웹훅 수신\*\*: .*/- **웹훅 수신**: <해당 없음 \/ 서명 검증>/' \
  -e 's/^- \*\*외부 URL 가져오기\*\*: .*/- **외부 URL 가져오기**:/' -e 's/^- \*\*LLM 호출\*\*: .*/- **LLM 호출**: <해당 없음>/' "$ROOT/s3.md"
cat > "$ROOT/plan.md" <<'EOF'
# 플랜

## 1. 가정

- 웹훅·LLM·업로드·프록시 이야기는 산문일 뿐 신호가 아니다

## 2. 파일 구조

### 생성
- `src/webhooks/stripe.ts` — 결제 웹훅 수신
- `src/storage/s3.ts` — 저장소(storage 안의 rag 는 낱말이 아니다)

## 5. 태스크 개요

- `src/llm/client.ts` 는 §2 밖이라 신호가 아니다
EOF
printf '```yaml\ntasks:\n  - id: T1\n    outputs: [src/ai/openaiClient.ts, scripts/tests/test-ai.sh]\n```\n' > "$ROOT/tasks.md"
out=$(_run "$ROOT/s3.md" --plan "$ROOT/plan.md" --tasks "$ROOT/tasks.md")
{ _has "$out" '[승인 대상] 업로드 — api-spec `POST /v1/files/upload` — 「위험 기능 결정」의 업로드 칸이 비었다' \
  && _has "$out" '[승인 대상] 웹훅 수신 — plan §2 `src/webhooks/stripe.ts` —' \
  && _has "$out" '[승인 대상] LLM 호출 — tasks outputs `src/ai/openaiClient.ts` —' \
  && ! _has "$out" '[승인 대상] 외부 URL 가져오기' && [ "$(printf '%s\n' "$out" | grep -c '\[승인 대상\]')" -eq 3 ]; } \
  && ok "S3a [승인 대상] api-spec 경로·plan §2 경로·tasks outputs 신호 적발 · 신호 없는 빈 칸은 조용" || nope "S3a" "$out"

cat > "$ROOT/plan-prose.md" <<'EOF'
# 플랜

## 2. 파일 구조

- 업로드·웹훅·LLM·프록시·크롤러 기능은 이번 범위가 아니다(산문)
- `scripts/check-names.sh` — 이름 점검
EOF
_api "$ROOT/s3b.md" "$_ok_rows"; sed -i.bak -e 's/^- \*\*업로드\*\*: .*/- **업로드**: <해당 없음>/' -e 's/^- \*\*웹훅 수신\*\*: .*/- **웹훅 수신**: <해당 없음>/' \
  -e 's/^- \*\*외부 URL 가져오기\*\*: .*/- **외부 URL 가져오기**: <해당 없음>/' -e 's/^- \*\*LLM 호출\*\*: .*/- **LLM 호출**: <해당 없음>/' "$ROOT/s3b.md"
out=$(_run "$ROOT/s3b.md" --plan "$ROOT/plan-prose.md")
{ printf '%s\n' "$out" | head -1 | grep -q '^SECURITY-DESIGN: OK' && ! _has "$out" '[승인 대상]'; } && ok "S3b 산문 단어만 있는 plan → [승인 대상] 0건" || nope "S3b" "$out"

_api "$ROOT/s3c.md" "$_ok_rows"   # 위험 기능 칸이 모두 '해당 없음'
out=$(_run "$ROOT/s3c.md" --plan "$ROOT/plan.md")
_api "$ROOT/s3d.md" "$_ok_rows"; sed -i.bak 's/^- \*\*웹훅 수신\*\*: .*/- **웹훅 수신**: Stripe 서명(HMAC-SHA256) 검증 · 허용 오차 5분/' "$ROOT/s3d.md"
out2=$(_run "$ROOT/s3d.md" --plan "$ROOT/plan.md")
{ printf '%s\n' "$out" "$out2" | grep -c '^SECURITY-DESIGN: OK' | grep -qx 2 && ! _has "$out" '[승인 대상]' && ! _has "$out2" '[승인 대상]'; } \
  && ok "S3c '해당 없음'·결정을 채운 칸은 신호가 있어도 조용 (clarify Q1)" || nope "S3c" "out=$out out2=$out2"

printf '```yaml\ntasks:\n  - id: T1\n    outputs:\n      - src/upload/handler.ts\n      - scripts/tests/test-up.sh\n    depends_on: []\n```\n' > "$ROOT/tasks-block.md"
_api "$ROOT/s3e.md" "$_ok_rows"; sed -i.bak 's/^- \*\*업로드\*\*: .*/- **업로드**: <해당 없음>/' "$ROOT/s3e.md"
out=$(_run "$ROOT/s3e.md" --tasks "$ROOT/tasks-block.md")
_has "$out" '[승인 대상] 업로드 — tasks outputs `src/upload/handler.ts` —' && ok "S3d tasks 블록 목록 outputs 도 신호로 읽음" || nope "S3d" "$out"

# 펜스 안의 `## 2. 파일 구조`·경로는 신호가 아니다(태스크의 픽스처 코드 — plan-reviewer 2회차 실측 오탐)
printf '# 플랜\n\n## 2. 파일 구조\n\n- `scripts/check-names.sh` — 이름 점검\n\n## 5. 태스크\n\n```bash\ncat > plan.md <<EOF\n## 2. 파일 구조\n- `src/webhooks/stripe.ts`\nEOF\n```\n' > "$ROOT/plan-fence.md"
_api "$ROOT/s3f.md" "$_ok_rows"; sed -i.bak 's/^- \*\*웹훅 수신\*\*: .*/- **웹훅 수신**: <해당 없음>/' "$ROOT/s3f.md"
out=$(_run "$ROOT/s3f.md" --plan "$ROOT/plan-fence.md")
{ printf '%s\n' "$out" | head -1 | grep -q '^SECURITY-DESIGN: OK' && ! _has "$out" '[승인 대상]'; } \
  && ok "S3e plan 코드 펜스 안의 파일 구조·경로는 신호가 아님" || nope "S3e" "$out"

# ── S4 옛 문서·SKIP·판정 불가·사용 오류 (AC-4 · AC-9) ──
cat > "$ROOT/old.md" <<'EOF'
## §1. Markdown 엔드포인트 표

| Method | Path | Auth | Request | Response | Status | 비고 |
|---|---|---|---|---|---|---|
| GET | `/v1/users` | Bearer | — | `User[]` | 200 | 목록 |

## §5. 인증·인가 정책

- **인증**: Bearer JWT (Access 15m + Refresh 7d)
- **권한 모델**: RBAC — admin, user, guest
EOF
out=$(_run "$ROOT/old.md"); rc=$?
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | head -1)" = "SECURITY-DESIGN: OK (위반 0 · 엔드포인트 1/1 · 건너뜀 3)" ] \
  && _has "$out" '[건너뜀] CORS(칸 없음)' && _has "$out" '[건너뜀] CSRF(칸 없음)' && _has "$out" '[건너뜀] 승인 대상(「위험 기능 결정」 절 없음)' \
  && ! printf '%s\n' "$out" | grep -qE '\[(미정|건너뜀)\] 인증 방식'; } \
  && ok "S4a 옛 문서 — 없는 칸은 [건너뜀] · 옛 이름 **인증** 은 인증 방식으로 읽음(값 있음 → 조용)" || nope "S4a" "rc=$rc out=$out"
sed 's/^- \*\*인증\*\*: .*/- **인증**: <Bearer JWT>/' "$ROOT/old.md" > "$ROOT/old2.md"
out=$(_run "$ROOT/old2.md")
_has "$out" '[미정] 인증 방식 — 칸이 비었거나 자리표시자(<Bearer JWT>)' && ok "S4b 옛 이름 **인증** 이 자리표시자면 [미정] 인증 방식 (clarify Q2)" || nope "S4b" "$out"

out=$(bash "$CSD" --spec "$ROOT/none.md" --data-model "$ROOT/none2.md"); rc=$?
printf '# 메모\n\n그냥 글\n' > "$ROOT/memo.md"; out2=$(_run "$ROOT/memo.md"); rc2=$?
_api "$ROOT/fence.md" "$_ok_rows"; printf '\n```\n열린 펜스\n' >> "$ROOT/fence.md"; out3=$(_run "$ROOT/fence.md"); rc3=$?
mkdir -p "$ROOT/adir"; out4=$(bash "$CSD" --spec "$ROOT/adir"); rc4=$?
bash "$CSD" >/dev/null 2>&1; rc5=$?; bash "$CSD" 'bad fid' >/dev/null 2>&1; rc6=$?; bash "$CSD" 20261021-f --plan x >/dev/null 2>&1; rc7=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^SECURITY-DESIGN: SKIP (api-spec.md·data-model.md 부재' \
  && [ "$rc2" -eq 0 ] && printf '%s\n' "$out2" | grep -q '^SECURITY-DESIGN: SKIP (판정할 칸이 없다' \
  && [ "$rc3" -eq 2 ] && printf '%s\n' "$out3" | grep -q '^SECURITY-DESIGN: 판정 불가 (api-spec 의 닫히지 않은 코드 펜스' \
  && [ "$rc4" -eq 2 ] && printf '%s\n' "$out4" | grep -q '^SECURITY-DESIGN: 판정 불가 (api-spec 을 읽을 수 없음' \
  && [ "$rc5" -eq 1 ] && [ "$rc6" -eq 1 ] && [ "$rc7" -eq 1 ]; } \
  && ok "S4c 부재·칸 없음 SKIP rc 0 · 닫히지 않은 펜스·읽기 불가 판정 불가 rc 2 · 사용 오류 rc 1" \
  || nope "S4c" "rc=$rc out=$out rc2=$rc2 out2=$out2 rc3=$rc3 out3=$out3 rc4=$rc4 out4=$out4 rc5=$rc5 rc6=$rc6 rc7=$rc7"

# ── S5 바뀐 행 한정 (AC-5) ──
D="$ROOT/s5"; mkdir -p "$D/.specops/memory" "$D/.specops/20261021-f"
_api "$D/.specops/memory/api-spec.md" "$_ok_rows
| GET | \`/v1/legacy\` |  | — | — | 200 | 옛 빈칸 |"
( cd "$D" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && git checkout -qb feat )
python3 - "$D/.specops/memory/api-spec.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("| 옛 빈칸 |\n","| 옛 빈칸 |\n| GET | `/v1/fresh` |  | — | — | 200 | 새 빈칸 |\n",1); open(p,"w").write(s)
PY
out=$(cd "$D" && bash "$CSD" 20261021-f); rc=$?
D2="$ROOT/s5b"; mkdir -p "$D2/.specops/memory"; cp "$D/.specops/memory/api-spec.md" "$D2/.specops/memory/"
out2=$(cd "$D2" && bash "$CSD" 20261021-f); rc2=$?
{ [ "$rc" -eq 0 ] && _has "$out" '[인증] GET /v1/fresh' && ! _has "$out" '/v1/legacy' && ! _has "$out" '[범위]' \
  && [ "$rc2" -eq 0 ] && _has "$out2" '[인증] GET /v1/fresh' && _has "$out2" '[인증] GET /v1/legacy' && _has "$out2" '[범위] 전체 행'; } \
  && ok "S5 FID 모드 — 추적 중이면 바뀐 행만 · 추적 밖이면 전체 행 + [범위]" || nope "S5" "rc=$rc out=$out rc2=$rc2 out2=$out2"

# ── S6 배선 — 검증 러너·specifying·verifying (AC-6) ──
D="$ROOT/s6"; VF=20261021-f; mkdir -p "$D/.specops/memory" "$D/.specops/$VF" "$D/scripts/tests"
_api "$D/.specops/memory/api-spec.md" "$_ok_rows"
printf '#!/usr/bin/env bash\nexit 0\n' > "$D/scripts/tests/dummy.sh"; chmod +x "$D/scripts/tests/dummy.sh"
printf -- '- [ ] **스텝 4**: 실행: `bash scripts/tests/dummy.sh`\n' > "$D/.specops/$VF/tasks.md"
( cd "$D" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init && git checkout -qb feat )
python3 - "$D/.specops/memory/api-spec.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("| 페이지 커서 |\n","| 페이지 커서 |\n| GET | `/v1/fresh` |  | — | — | 200 | 새 빈칸 |\n",1); open(p,"w").write(s)
PY
out=$(cd "$D" && bash "$RV" "$VF" 2>"$ROOT/s6.err"); rc=$?; err=$(cat "$ROOT/s6.err")
ev="$D/.specops/$VF/evidence.md"
{ [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "VERIFY: PASS" ] && grep -qx '### security-design' "$ev" \
  && grep -q '^SECURITY-DESIGN: WARN ' "$ev" && grep -qF '[인증] GET /v1/fresh' "$ev" \
  && _has "$err" 'WARN: 보안 설계 칸·결함 — 경고만(차단 아님) · evidence.md ### security-design'; } \
  && ok "S6a run-verification — evidence ### security-design · 경고 · VERIFY PASS·rc 0 불변" || nope "S6a" "rc=$rc out=$out err=$err"

SP="$PLUGIN/skills/specifying-ko/SKILL.md"
grep -qE 'scripts/_internal/check-security-design\.sh <FID>` 를 한 번 실행한다.*막지 않는다' "$SP" \
  && ok "S6b specifying Step 5.6 — 보안 칸 판정기 호출(비차단)" || nope "S6b" "specifying 문구 누락"

VE="$PLUGIN/skills/verifying-evidence-ko/SKILL.md"
grep -qE '`### security-design` 에 남긴다\. `WARN` 은 결함 후보일 뿐 VERIFY 결과를 바꾸지 않는다' "$VE" \
  && ok "S6c verifying 체크 줄 — security-design 경고 전용" || nope "S6c" "verifying 문구 누락"

# ── S7 Phase C 리뷰 반영 (20261021) ──
# 옛 **인증** 과 새 **인증 방식** 이 함께 있으면 새 칸을 판정한다(clarify Q2 — 옛 이름은 새 칸이 없을 때만)
sed 's/^- \*\*인증\*\*: .*/- **인증**: Bearer JWT (Access 15m)\n- **인증 방식**: <Bearer 헤더 \/ 쿠키>/' "$ROOT/old.md" > "$ROOT/s7a.md"
out=$(_run "$ROOT/s7a.md")
_has "$out" '[미정] 인증 방식 — 칸이 비었거나 자리표시자(<Bearer 헤더 / 쿠키>)' && ok "S7a 옛 인증 + 새 인증 방식(자리표시자) 공존 → 새 칸 [미정]" || nope "S7a" "$out"
# CORS credentials 한국어 부정형은 경고하지 않는다 · origin=* 표기는 별표로 읽는다
n=0
for neg in 'credentials 사용하지 않음' 'credentials 허용하지 않음' 'credentials 사용 안 됨' 'credentials 비허용'; do
  _api "$ROOT/s7b.md" "$_ok_rows"; sed -i.bak "s/^- \*\*CORS\*\*: .*/- **CORS**: \`*\` · $neg/" "$ROOT/s7b.md"
  o=$(_run "$ROOT/s7b.md"); printf '%s\n' "$o" | head -1 | grep -q '^SECURITY-DESIGN: OK' && ! _has "$o" '[CORS]' && n=$((n+1))
done
_api "$ROOT/s7c.md" "$_ok_rows"; sed -i.bak 's/^- \*\*CORS\*\*: .*/- **CORS**: origin=* · credentials: true/' "$ROOT/s7c.md"
out=$(_run "$ROOT/s7c.md")
{ [ "$n" -eq 4 ] && _has "$out" '[CORS] 허용 origin `*` 와 credentials 를 함께 쓴다'; } \
  && ok "S7b CORS 한국어 부정형 4종 조용 · origin=* + credentials 적발" || nope "S7b" "neg_ok=$n/4 out=$out"
# plan §2 의 **범위 밖** 줄 경로는 신호가 아니다 · 약어 camelCase(LLMService) 는 낱말로 자른다
cat > "$ROOT/plan-s7.md" <<'EOF'
# 플랜

## 2. 파일 구조

- `src/LLMService.ts` — 요약 호출

### 경계 약속

- **범위 밖**: `src/webhooks/` — 건드리지 않는다
EOF
_api "$ROOT/s7d.md" "$_ok_rows"; sed -i.bak -e 's/^- \*\*웹훅 수신\*\*: .*/- **웹훅 수신**: <해당 없음>/' -e 's/^- \*\*LLM 호출\*\*: .*/- **LLM 호출**: <해당 없음>/' "$ROOT/s7d.md"
out=$(_run "$ROOT/s7d.md" --plan "$ROOT/plan-s7.md")
{ _has "$out" '[승인 대상] LLM 호출 — plan §2 `src/LLMService.ts` —' && ! _has "$out" '[승인 대상] 웹훅 수신'; } \
  && ok "S7c 약어 camelCase LLMService 신호 · 「범위 밖」 경로는 신호 아님" || nope "S7c" "$out"
_api "$ROOT/s7e.md" "$_ok_rows"; sed -i.bak 's/^- \*\*LLM 호출\*\*: .*/- **LLM 호출**: <해당 없음>/' "$ROOT/s7e.md"
printf '# 플랜\n\n## 2. 파일 구조\n\n- `src/LLMsClient.ts` — 여러 모델 호출\n' > "$ROOT/plan-s7e.md"
out=$(_run "$ROOT/s7e.md" --plan "$ROOT/plan-s7e.md")
_has "$out" '[승인 대상] LLM 호출 — plan §2 `src/LLMsClient.ts` —' && ok "S7d 약어 복수형 LLMsClient 도 신호(Phase C 재라운드)" || nope "S7d" "$out"

finish
