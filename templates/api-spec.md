<!-- OWNER_COMMAND: /init-project -->
<!-- layer: Project-Memory -->

# <PROJECT_NAME> IF 설계서 (API Specification)

> 한국 SI 표준 "IF 설계서". `/init-project` Phase 8f 가 1회 생성 (BE/풀스택 종류만).
> 4 가지 정의 방식 중 사용자가 선택한 §섹션만 활성. 나머지는 placeholder 로 남김.

> ⚠️ **활성 §섹션의 `/v1/users` 등 엔드포인트·스키마는 작성 방법을 보여주는 예시이며 본 프로젝트와 무관하다. 실제 API 로 전부 교체하라.**

## §0. 정의 방식 선택

`/init-project` Phase 8f 가 사용자에게 선택받음. 활성 §섹션 표시:

- [ ] §1 Markdown 엔드포인트 표 (가벼움, 빠른 시작)
- [ ] §2 OpenAPI 3.1 YAML 골격 (정식, swagger 통합)
- [ ] §3 GraphQL SDL 골격
- [ ] §4 RPC / TS 시그니처

**채택한 방식**: <`/init-project` 입력값>

## §1. Markdown 엔드포인트 표

> ⚠️ **아래는 전자상거래 예시다 — 실제 엔드포인트로 교체하고 `specops:example` 마커 블록째 삭제하라.**
> 본 문서는 구현의 **설계 계약**이라 예시가 남으면 `design-reviewer-ko` 정합 검사·`verifying-evidence-ko`
> memory 동기화 점검이 **유령 엔드포인트를 실 계약으로 읽는다**. 잔존 시 `scan-enrich-placeholders.sh` 가 미채움 판정.

<!-- specops:example:start -->
| Method | Path | Auth | Request | Response | Status | 비고 |
|---|---|---|---|---|---|---|
| GET | `/v1/users` | Bearer (admin) | `?cursor=&limit=` | `Page<User>` | 200 · 401 · 403 | 사용자 목록 (목록 정책 적용) |
| GET | `/v1/users/:id` | Bearer | — | `User` | 200 · 401 · 404 | 단일 사용자 조회 |
| POST | `/v1/users` | Bearer (admin) | `CreateUserDto` | `User` | 201 · 401 · 403 · 409 · 422 | 사용자 생성 (`Location` 헤더) |
| PATCH | `/v1/users/:id` | Bearer (self/admin) | `UpdateUserDto` | `User` | 200 · 401 · 403 · 404 · 422 | 사용자 수정 |
| DELETE | `/v1/users/:id` | Bearer (admin) | — | `204 No Content` | 204 · 401 · 403 · 404 | 사용자 삭제 |
<!-- specops:example:end -->

> **칸 계약** (`check-api-contract.sh` 가 읽는다 — 경고 전용): 엔드포인트 표의 **Status** 열 · 아래 **오류 형식**·**오류 코드 카탈로그**·**목록 정책**·**멱등 정책** · §5 **rate limit** · §6 **버전 전략**. 비었거나 `<…>` 그대로면 검증 때 경고한다.
> **Auth 열** (`check-security-design.sh` 가 읽는다 — 경고 전용): 공개면 `없음(공개)`, 아니면 인증 방식과 필요한 역할·scope(예: `Bearer · admin`). 빈칸·`—` 는 검증 때 경고한다. 토큰·비밀번호·API 키를 경로·쿼리 파라미터로 받지 않는다.

- **오류 형식**: <RFC 9457 Problem Details / 자체 envelope — 모든 엔드포인트가 이 하나만 쓴다>

**공통 에러 포맷** (RFC 9457 Problem Details — 2023년에 RFC 7807 을 대체 · `Content-Type: application/problem+json`):
```json
{
  "type": "https://example.com/errors/validation",
  "title": "Validation Error",
  "status": 400,
  "detail": "email field is required",
  "instance": "/v1/users"
}
```

### 오류 코드 카탈로그

기계가 읽는 오류 코드 — 클라이언트는 문구가 아니라 이 코드로 분기한다. 검증 오류는 `errors[]` 에 `field`·`message` 를 담는다(입력값을 되돌려 주지 않는다).

| 코드 | HTTP | 언제 |
|---|---|---|
| <ERROR_CODE> | <4xx·5xx> | <언제 나는가> |

### 목록 정책

- **방식**: <cursor / offset — 큰 목록·무한 스크롤은 cursor>
- **기본 크기**: <20>
- **최대 크기**: <100>
- **정렬 키**: <예: created_at, id — 커서에는 정렬 컬럼 전부와 유일한 tiebreaker 를 담는다>

### 멱등 정책

- <상태를 바꾸는 엔드포인트마다 둘 중 하나: `Idempotency-Key` 헤더를 받는다(키는 클라이언트가 의도마다 한 번 만든다 · 같은 키·다른 본문은 422 · 완료된 중복은 원래 응답 재생 · 보존기간) / 재시도 불안전 — 클라이언트가 재시도하지 않는다>

## §2. OpenAPI 3.1 YAML

```yaml
openapi: 3.1.0
info:
  title: <PROJECT_NAME> API
  version: 1.0.0
  description: <한 줄>
servers:
  - url: https://api.<domain>.com/v1
    description: Production
  - url: https://staging-api.<domain>.com/v1
    description: Staging

paths:
  /users/{id}:
    get:
      summary: 사용자 조회
      parameters:
        - in: path
          name: id
          required: true
          schema:
            type: string
            format: uuid
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'
        '404':
          $ref: '#/components/responses/NotFound'

components:
  schemas:
    User:
      type: object
      required: [id, email, createdAt]
      properties:
        id:
          type: string
          format: uuid
        email:
          type: string
          format: email
        createdAt:
          type: string
          format: date-time

  responses:
    NotFound:
      description: 리소스 없음
      content:
        application/problem+json:
          schema:
            $ref: '#/components/schemas/Problem'

  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

security:
  - bearerAuth: []
```

## §3. GraphQL SDL

```graphql
"GraphQL 스키마 — <PROJECT_NAME>"

type Query {
  user(id: ID!): User
  users(first: Int, after: String): UserConnection!
}

type Mutation {
  createUser(input: CreateUserInput!): UserPayload!
  updateUser(id: ID!, input: UpdateUserInput!): UserPayload!
  deleteUser(id: ID!): DeletePayload!
}

type User {
  id: ID!
  email: String!
  createdAt: DateTime!
}

type UserConnection {
  edges: [UserEdge!]!
  pageInfo: PageInfo!
}

type UserEdge {
  cursor: String!
  node: User!
}

input CreateUserInput {
  email: String!
  password: String!
}

input UpdateUserInput {
  email: String
}

type UserPayload {
  user: User
  errors: [UserError!]
}

type UserError {
  field: String!
  message: String!
}

type DeletePayload {
  success: Boolean!
}

type PageInfo {
  hasNextPage: Boolean!
  endCursor: String
}

scalar DateTime
```

## §4. RPC / TS 시그니처 (tRPC 등)

```typescript
// shared/api-contracts.ts
import { z } from 'zod';

export const userSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  createdAt: z.string().datetime(),
});

export type User = z.infer<typeof userSchema>;

export const createUserInput = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

export type CreateUserInput = z.infer<typeof createUserInput>;

// API 시그니처 (tRPC router 또는 직접 RPC)
export interface UserRouter {
  get(input: { id: string }): Promise<User>;
  create(input: CreateUserInput): Promise<User>;
  update(input: { id: string; email?: string }): Promise<User>;
  delete(input: { id: string }): Promise<{ success: boolean }>;
}
```

## §5. 인증·인가 정책

> **보안 칸** (`check-security-design.sh` 가 읽는다 — 경고 전용): 아래 **인증 방식**·**권한 모델**·**CORS**·**CSRF** 와 「위험 기능 결정」. 비었거나 `<…>` 그대로면 검증 때 경고한다. 해당하지 않으면 `해당 없음` 으로 적는다.

- **인증 방식**: <Bearer 헤더 / httpOnly 쿠키 세션 — 토큰 보관 위치·수명·폐기 방법>
- **권한 모델**: <역할·권한 목록(예: RBAC admin·user) — 객체 소유자 확인을 어디서 하는가>
- **CORS**: <허용 origin 목록 · credentials 사용 여부 — `*` 와 credentials 를 함께 쓰지 않는다>
- **CSRF**: <쿠키 인증이면 방어 방법(SameSite·CSRF 토큰) / 해당 없음(헤더 토큰 인증)>
- **rate limit**: <예: 사용자당 100 req/min · 익명 20 req/min — 429 응답에 `Retry-After`>

### 위험 기능 결정

이 기능이 있으면 결정을 적고, 없으면 `해당 없음` 으로 적는다. plan 의 파일 경로나 엔드포인트 경로에 이 기능의 신호가 있는데 칸이 비었으면 검증 때 경고한다.

- **업로드**: <해당 없음 / 허용 형식(MIME·magic bytes)·크기 상한·저장 위치(웹 루트 밖)>
- **웹훅 수신**: <해당 없음 / 서명 검증(HMAC·타임스탬프 허용 오차)·재전송 대비>
- **외부 URL 가져오기**: <해당 없음 / 허용 목록·사설 IP 차단(DNS 해석 결과 전부)·리다이렉트 금지>
- **LLM 호출**: <해당 없음 / 출력은 신뢰 불가 입력으로 검증·컨텍스트에 비밀·타 테넌트 데이터 금지>

## §6. 버저닝

- **버전 전략**: <URL prefix `/v1/` / 헤더 / 쿼리>
- URL prefix `/v1/`, 신규 메이저 시 `/v2/` 신설 + `/v1/` 6 개월 deprecate
- breaking change 정의: 응답 필드 제거, required 필드 추가, 의미 변경

## §7. 참조

- 상위: `.specops/memory/architecture.md` §2 통신
- 백엔드: `.specops/memory/backend-architecture.md` §7 API 설계
- 데이터: `.specops/memory/data-model.md`

---

*작성: <작성자> · <YYYY-MM-DD> · 생성: /init-project (Phase 8f)*
