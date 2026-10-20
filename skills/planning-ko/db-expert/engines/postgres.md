<!-- reference_upstream: supabase/agent-skills skills/supabase-postgres-best-practices/references/*.md · wshobson/agents plugins/database-design/skills/postgresql-table-design/SKILL.md · wshobson/agents plugins/database-design/skills/postgresql-table-design/references/details.md · davila7/claude-code-templates cli-tool/components/skills/database/postgres-schema-design/SKILL.md (MIT) · 공식 문서 https://www.postgresql.org/docs/current/protocol-message-formats.html — specops-ko 한국어 재작성 (20261020-db-designer-agent) -->
# PostgreSQL 설계 규칙 — db-designer-ko 보조 파일

`data-model.md` §1 유형이 이 엔진일 때 db-designer-ko 가 읽는다. 공통 규칙은 에이전트 본문에 있다 — 여기에는 이 엔진에만 해당하는 것만 둔다.
출처 약칭: S=supabase/agent-skills 의 references/<이름>.md · W1=wshobson SKILL.md · W2=wshobson references/details.md · D5=davila7 postgres-schema-design (모두 MIT).

## 규칙
- PK 는 `BIGINT GENERATED ALWAYS AS IDENTITY` 를 쓴다. `serial` 은 피하고, 랜덤 UUIDv4 를 대형 테이블 PK 로 쓰지 않는다(분산 생성이 필요하면 UUIDv7). 시퀀스 갭은 정상이므로 연속 ID 를 가정하지 않는다 — 출처: S:schema-primary-keys · W1 · D5
- 자료형: 시각은 `timestamptz`(timestamp 금지), 문자열은 `text`(길이 제한이 필요하면 `CHECK(length)`), 금액은 `numeric`(money 타입 금지), 불리언은 `boolean NOT NULL`. 변동하는 업무 값(상태)은 ENUM 타입이 아니라 TEXT+CHECK 또는 룩업 테이블로 둔다 — 출처: W1 · S:schema-data-types · W2
- `ON CONFLICT (cols)` 는 정확히 같은 컬럼의 UNIQUE 인덱스/제약이 있어야 동작한다. 갱신이 필요 없으면 `DO NOTHING`, 결과 행은 `RETURNING` 으로 받는다 — 출처: S:data-upsert · W2
- 한 문장의 바인드 파라미터는 65535 개(Bind 메시지의 Int16 필드) 이하여야 한다 — 행 수 × 컬럼 수로 청크한다. 대량 적재는 다중 행 INSERT(≈1000행 단위) 또는 COPY 를 쓴다 — 출처: S:data-batch-inserts · https://www.postgresql.org/docs/current/protocol-message-formats.html
- UNIQUE 는 NULL 을 여러 개 허용한다. NULL 이 낀 업무 키를 하나로 제한하려면 `UNIQUE NULLS NOT DISTINCT`(PG15+)를 쓰고, UNIQUE 만으로 유일성이 보장됐다고 가정하지 않는다 — 출처: W1 · D5
- CHECK 는 NULL 을 통과시키므로(3값 논리) NOT NULL 과 함께 쓴다. 기간 겹침 금지는 `EXCLUDE USING gist (room_id WITH =, period WITH &&)` 로 건다 — 출처: W1
- 식별자는 소문자 snake_case 로 쓴다. 따옴표 붙은 혼합 대문자 이름(`"userId"`)을 만들지 않고, ORM 이 quote 를 생성하면 설정으로 끈다 — 출처: S:schema-lowercase-identifiers · W1
- 인덱스 종류 선택: JSONB 포함 검색(`@>`)·배열·전문 검색은 GIN, 범위·기하·EXCLUDE 는 GiST, 큰 시계열은 BRIN, JSONB 의 특정 스칼라 등치/범위는 생성 컬럼+B-tree. 부분 인덱스(`WHERE deleted_at IS NULL`)와 `INCLUDE` 커버링 인덱스는 쿼리 조건이 정확히 맞을 때만 쓰인다 — 출처: S:query-index-types · S:query-partial-indexes · S:query-covering-indexes · S:advanced-jsonb-indexing · W2
- 전문 검색은 `to_tsvector('english', col)` 처럼 언어를 항상 지정하고(1인자 형태 금지) 인덱스 표현식과 쿼리가 같은 형태여야 한다 — 출처: W2
- 멱등 마이그레이션: `ADD CONSTRAINT IF NOT EXISTS` 문법은 없으므로 `pg_constraint` 조회 DO 블록으로 쓴다. 운영 인덱스는 `CREATE INDEX CONCURRENTLY`(트랜잭션 안에서 불가). `NOT NULL` 컬럼에 휘발성 기본값(`now()`·`gen_random_uuid()`)을 붙이면 테이블 전체가 재작성된다. 컬럼 삭제 전에 제약을 먼저 삭제한다 — 출처: S:schema-constraints · W2
- PG 의 DDL 은 대부분 트랜잭션 안에서 롤백되므로 마이그레이션 시험은 `BEGIN; ALTER …; ROLLBACK;` 로 한다. CONCURRENTLY 계열은 예외다 — 출처: W2
- 작업 큐 claim 은 `FOR UPDATE SKIP LOCKED` 한 문장(`UPDATE … WHERE id = (SELECT … LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING`)으로 한다. 앱 수준 상호배제는 advisory lock(`pg_advisory_xact_lock`)을 쓰고 더미 행 잠금을 쓰지 않는다 — 출처: S:lock-skip-locked · S:lock-advisory
- `idle_in_transaction_session_timeout`·`statement_timeout` 을 설정한다. 풀러 트랜잭션 모드에서는 이름 붙은 prepared statement 를 쓰지 않는다(세션 모드이거나 unnamed 만) — 출처: S:conn-idle-timeout · S:lock-short-transactions · S:conn-prepared-statements
- 앱 계정은 superuser 를 금지하고 최소 권한 GRANT 를 쓰며 `public` 스키마 기본 권한을 회수한다. 멀티테넌트는 RLS 활성+`FORCE ROW LEVEL SECURITY`, 정책 안의 함수 호출은 `(select auth.uid())` 로 감싸고 정책이 쓰는 컬럼에 인덱스를 둔다. `SECURITY DEFINER` 함수는 `set search_path = ''` 를 건다 — 출처: S:security-privileges · S:security-rls-basics · S:security-rls-performance
- 파티셔닝은 1억 행 이상이고 질의가 파티션 키로 일관되게 걸러질 때만 한다. 파티션 키를 PK/UNIQUE 에 포함해야 하고(글로벌 UNIQUE 불가) 상속 테이블 대신 선언적 파티션을 쓴다 — 출처: W1 · S:schema-partitioning
- 갱신이 잦은 테이블은 인덱스 컬럼 갱신을 피하고(HOT 갱신) `fillfactor=90` 을 두며 뜨거운 컬럼을 분리한다. 삽입 위주 테이블은 인덱스를 최소화하고 COPY 를 쓴다 — 출처: W2
