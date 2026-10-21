<!-- reference_upstream: wshobson/agents@0874a27 plugins/backend-development/skills/api-design-principles/references/graphql-schema-design.md · plugins/backend-development/skills/api-design-principles/assets/api-design-checklist.md · davila7/claude-code-templates@e7d17f9 cli-tool/components/agents/api-graphql/api-architect.md · cli-tool/components/agents/api-graphql/api-designer.md (MIT) — specops-ko 한국어 재작성 (20261021-api-designer-agent) -->
# GraphQL 규칙 — api-designer-ko 보조 파일

api-spec §0 정의 방식이 GraphQL 이거나 plan 이 `.graphql`·스키마·리졸버 파일을 만들거나 고칠 때 api-designer-ko 가 읽는다. 공통 원칙(호환성·멱등·오류 형식 하나)은 에이전트 본문에 있다 — 여기에는 GraphQL 에만 해당하는 것만 둔다.

- 스키마 작성 방식(SDL 먼저 · 코드 먼저) 중 하나를 plan 에 적는다. 섞지 않는다.
- nullability: 필드는 nullable 로 시작하고 항상 값이 보장될 때만 non-null(`!`)로 바꾼다. 이미 공개된 필드를 nullable → non-null 로 바꾸는 것은 입력 쪽에서, non-null → nullable 은 출력 쪽에서 깨는 변경이다(specops-ko 추가 — 원문에 없음).
- mutation 은 인자 하나짜리 `input` 타입을 받고 전용 payload 타입을 돌려준다(`createPost(input: CreatePostInput!): CreatePostPayload!`).
- 오류 전략은 하나만 쓴다 — payload 안의 `errors` 필드, union 오류 타입, 최상위 `errors` 중 프로젝트가 정한 것. mutation 마다 다르면 지적한다.
- 목록 필드는 Relay connection(`edges`·`node`·`cursor`·`pageInfo`) 또는 api-spec 에 정한 방식으로 페이지네이션한다. 상한 없는 목록 필드를 두지 않는다.
- 쿼리 깊이·복잡도 상한을 실행 전에 검사한다(원문 권고: 깊이 10 이하). 상한이 plan 에 없으면 지적한다.
- 관계 필드 리졸버는 DataLoader(또는 같은 일괄 로더)로 묶어 N+1 을 막는다.
- 도메인 값(이메일·일시·금액)은 custom scalar 로 정의하고 검증 위치를 적는다.
- 모든 타입·필드에 description 을 단다. 제거할 필드는 `@deprecated(reason:)` 로 먼저 표시한다.
- 구독은 `graphql-ws` 프로토콜을 쓴다 — 폐기된 `subscriptions-transport-ws` 를 새로 쓰지 않는다.
