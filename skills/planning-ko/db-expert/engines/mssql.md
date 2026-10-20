<!-- reference_upstream: claude-dev-suite/claude-dev-suite skills/databases/sqlserver/SKILL.md · claude-dev-suite/claude-dev-suite skills/databases/sqlserver/quick-ref/datatypes.md · claude-dev-suite/claude-dev-suite skills/databases/sqlserver/quick-ref/indexes.md (MIT) · 공식 문서 https://learn.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server · https://learn.microsoft.com/en-us/sql/t-sql/queries/table-value-constructor-transact-sql · https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql — specops-ko 한국어 재작성 (20261020-db-designer-agent) -->
# SQL Server 설계 규칙 — db-designer-ko 보조 파일

`data-model.md` §1 유형이 이 엔진일 때 db-designer-ko 가 읽는다. 공통 규칙은 에이전트 본문에 있다 — 여기에는 이 엔진에만 해당하는 것만 둔다.
약칭: K=claude-dev-suite databases/sqlserver (MIT).

## 규칙
- 한 요청의 파라미터는 최대 2100 개다 — 행 수 × 컬럼 수로 청크한다. `INSERT … VALUES` 다중 행 생성자는 최대 1000 행이고 초과하면 오류 10738 이 난다. 우회는 여러 INSERT·파생 테이블·bcp/BULK INSERT 다 — 출처: https://learn.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server · https://learn.microsoft.com/en-us/sql/t-sql/queries/table-value-constructor-transact-sql
- 시각은 `DATETIME2` 를 쓴다(DATETIME 은 3.33ms 정밀도·1753 이후). 금액은 `DECIMAL`(MONEY 지양), 한글 등 유니코드는 `NVARCHAR`, `TEXT`/`NTEXT` 는 금지하고 `(N)VARCHAR(MAX)` 를 쓴다 — 출처: K:sqlserver/quick-ref/datatypes.md · K:sqlserver/SKILL.md
- 인덱스 키 크기는 클러스터드 900바이트·비클러스터드 1700바이트 이하여야 한다. 모든 테이블에 클러스터드 인덱스를 두어 힙 스캔을 막고, 키 룩업은 `INCLUDE` 로, 일부 행만 대상이면 필터 인덱스를 쓴다 — 출처: https://learn.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server · K:sqlserver/SKILL.md · K:sqlserver/quick-ref/indexes.md
- 신규 ID 는 `@@IDENTITY` 가 아니라 `SCOPE_IDENTITY()`(또는 `OUTPUT`)로 받는다 — `@@IDENTITY` 는 트리거가 만든 다른 ID 를 받는다. `SET NOCOUNT ON` 을 쓰고 커서 대신 집합 연산을 쓴다 — 출처: K:sqlserver/SKILL.md
- `MERGE` upsert 에서 유니크 키를 삽입·갱신하면 `HOLDLOCK` 이 유니크 키 위반을 막는다. 다만 HOLDLOCK 은 SERIALIZABLE 과 동의어라 동시성이 낮아지고, 문서는 동시성이 높으면 MERGE 보다 개별 INSERT/UPDATE 가 나을 수 있다고 적는다 — 출처: https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql
- 교착은 접근 순서 통일·트랜잭션 단축으로 줄이고 trace flag 1222 또는 Extended Events 로 진단한다. 블로킹은 `sp_who2` 로 본다 — 출처: K:sqlserver/SKILL.md
