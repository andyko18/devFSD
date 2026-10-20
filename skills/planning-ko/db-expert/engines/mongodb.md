<!-- reference_upstream: davila7/claude-code-templates cli-tool/components/agents/programming-languages/mongodb-performance-advisor.md · davila7/claude-code-templates cli-tool/components/agents/database/nosql-specialist.md · claude-dev-suite/claude-dev-suite skills/databases/mongodb/SKILL.md · claude-dev-suite/claude-dev-suite skills/databases/mongodb/quick-ref/indexes.md (MIT) · 공식 문서 https://www.mongodb.com/docs/manual/reference/operator/update/setOnInsert/ — specops-ko 한국어 재작성 (20261020-db-designer-agent) -->
# MongoDB 설계 규칙 — db-designer-ko 보조 파일

`data-model.md` §1 유형이 이 엔진일 때 db-designer-ko 가 읽는다. 공통 규칙은 에이전트 본문에 있다 — 여기에는 이 엔진에만 해당하는 것만 둔다.
약칭: D6=davila7 mongodb-performance-advisor · D7=davila7 nosql-specialist · K=claude-dev-suite databases/mongodb (모두 MIT).

## 규칙
- 쿼리·집계는 `explain("executionStats")` 로 `IXSCAN` 인지 `COLLSCAN` 인지, `totalDocsExamined` 대 반환 수 비율을 본다. COLLSCAN 이면 인덱스가 필요하다 — 출처: D6 · K:mongodb/quick-ref/indexes.md
- 복합 인덱스는 ESR 순서(Equality → Sort → Range)로 만든다. 쓰이지 않거나 중복인 인덱스는 `$indexStats` 로 찾아 정리한다 — 출처: K:mongodb/quick-ref/indexes.md · D6 · D7
- 집계 파이프라인은 `$match` 를 최대한 앞에 두고 `$project` 로 일찍 줄인다. `$lookup` 남용을 피하고 임베딩/비정규화로 설계하며, 조회 시 projection 으로 필요한 필드만 가져온다 — 출처: D7 · K:mongodb/SKILL.md
- 배열이 무한히 커지게 두지 않는다(문서 16MB 한도) — 임베딩 배열은 `maxItems` 로 상한을 두고, 커지는 것은 별도 컬렉션으로 뺀다. 16MB 를 넘는 바이너리는 GridFS 를 쓴다 — 출처: K:mongodb/SKILL.md · D7
- `$jsonSchema` validator 로 required·bsonType·enum·maxLength 를 강제하고 금액은 `decimal` 로 둔다. 스키마 유연성이 곧 제약 부재가 되지 않게 한다 — 출처: D7
- upsert 의 최초 생성 필드(createdAt)는 `$set` 이 아니라 `$setOnInsert` 로 넣는다(`upsert: true` 로 삽입이 일어난 경우에만 적용된다). 다중 문서 정합이 필요하면 단일 문서 임베딩 또는 session 트랜잭션(commit/abort 처리)을 쓰고, 중요 데이터는 writeConcern `majority` 를 쓴다(트랜잭션·writeConcern 은 공식 문서 대조 범위 밖, 출처 스킬 기준) — 출처: https://www.mongodb.com/docs/manual/reference/operator/update/setOnInsert/ · D7 · K:mongodb/SKILL.md
- `count()` 대신 `countDocuments()`/`estimatedDocumentCount()` 를 쓴다. 만료 데이터는 TTL 인덱스(`expireAfterSeconds`), 일부 문서만 색인하려면 `partialFilterExpression` 을 쓰고 연결 풀(`maxPoolSize`)을 설정한다 — 출처: K:mongodb/SKILL.md · K:mongodb/quick-ref/indexes.md · D7
- 인덱스 효과는 실측 없이 수치로 단정하지 않고 트레이드오프(쓰기 비용)를 함께 적는다. 권장은 보수적으로 한다 — 출처: D6
