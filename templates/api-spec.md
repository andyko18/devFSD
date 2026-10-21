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

## 공통 계약 — 오류·목록·멱등

> 정의 방식(§1~§4)과 무관하게 모든 엔드포인트가 따르는 계약이다. `/init-project` 가 고르지 않은 방식 절을 지워도 이 절은 남는다 —
> 방식 절 아래로 옮기지 마라(그 방식을 고르지 않은 프로젝트에서 칸이 함께 지워진다).

> **칸 계약** (`check-api-contract.sh` 가 읽는다 — 경고 전용): §1 을 골랐으면 엔드포인트 표의 **Status** 열 · 이 절의 **오류 형식**·**오류 코드 카탈로그**·**목록 정책**·**멱등 정책** · §5 **rate limit** · §6 **버전 전략**. 비었거나 `<…>` 그대로면 검증 때 경고한다.

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

- **인증**: Bearer JWT (Access 15m + Refresh 7d)
- **권한 모델**: RBAC — admin, user, guest
- **rate limit**: <예: 사용자당 100 req/min · 익명 20 req/min — 429 응답에 `Retry-After`>

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
