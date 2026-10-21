<!-- reference_upstream: claude-dev-suite/claude-dev-suite skills/databases/mysql/SKILL.md · claude-dev-suite/claude-dev-suite skills/databases/mysql/quick-ref/indexes.md (MIT) · 공식 문서 https://dev.mysql.com/doc/refman/8.0/en/ (charset-unicode-utf8mb4 · innodb-index-types · insert-on-duplicate · implicit-commit · innodb-transaction-isolation-levels · innodb-deadlocks-handling · datetime) · https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_stmt_prepare.html — specops-ko 한국어 재작성 (20261020-db-designer-agent) -->
# MySQL 설계 규칙 — db-designer-ko 보조 파일

`data-model.md` §1 유형이 이 엔진일 때 db-designer-ko 가 읽는다. 공통 규칙은 에이전트 본문에 있다 — 여기에는 이 엔진에만 해당하는 것만 둔다.
공식 문서 기반 규칙은 MySQL 8.0 문서를 대조했다. MariaDB 에도 같은지는 대조하지 않았다 — MariaDB 를 쓰는 프로젝트는 해당 규칙을 KB 에서 따로 확인한다. 약칭: K=claude-dev-suite databases/mysql (MIT).

## 규칙
- 엔진은 InnoDB 만 쓴다(MyISAM 은 트랜잭션·행 잠금이 없다). 문자셋은 `utf8mb4` 를 쓴다 — `utf8` 은 utf8mb3(최대 3바이트)의 별칭이라 이모지 같은 4바이트 문자를 저장하지 못한다 — 출처: K:mysql/SKILL.md · https://dev.mysql.com/doc/refman/8.0/en/charset-unicode-utf8mb4.html
- InnoDB 는 PK 를 클러스터드 인덱스로 쓰고 보조 인덱스 레코드마다 PK 컬럼을 포함하므로 PK 는 짧을수록 유리하다 — 출처: https://dev.mysql.com/doc/refman/8.0/en/innodb-index-types.html
- upsert `ON DUPLICATE KEY UPDATE` 는 갱신할 컬럼만 열거한다. `VALUES(col)` 형태는 8.0.20 부터 deprecated 이므로 행 별칭(`AS new`, 8.0.19+)을 쓰고, 별칭은 테이블 이름과 같으면 안 된다 — 출처: https://dev.mysql.com/doc/refman/8.0/en/insert-on-duplicate.html
- prepared statement 의 placeholder 는 최대 65535 개다(프로토콜 num_params 가 2바이트 정수) — 행 수 × 컬럼 수로 청크한다. 이 숫자는 프로토콜 필드 크기에서 도출한 것이고 refman 에 상한 숫자는 없으며 MariaDB 동일성은 미확인이다 — 출처: https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_stmt_prepare.html
- 복합 인덱스는 선두 컬럼부터만 쓰인다(`(a,b,c)` 는 a, a+b, a+b+c 에만). `EXPLAIN` 에서 `type=ALL`(전체 스캔)이거나 `key` 가 비어 있는지 보고 `ANALYZE TABLE` 로 통계를 갱신한다. 긴 문자열은 prefix 인덱스로 걸되 선택도를 점검한다 — 출처: K:mysql/quick-ref/indexes.md · K:mysql/SKILL.md
- `UPDATE`/`DELETE` 에는 WHERE 가 필수다. `SELECT *` 와 LIMIT 없는 목록 조회는 금지하고, 변동하는 값 집합에 ENUM 을 쓰지 않고 룩업 테이블을 쓴다 — 출처: K:mysql/SKILL.md
- DDL 은 암묵적 커밋을 일으켜 트랜잭션으로 롤백되지 않는다 — 다단계 마이그레이션이 중간에 실패하면 부분 적용 상태로 남으므로 단계를 멱등하게 쓰고 적용 상태를 기록한다. TEMPORARY 테이블의 CREATE/DROP 은 암묵 커밋을 하지 않지만 롤백도 되지 않는다 — 출처: https://dev.mysql.com/doc/refman/8.0/en/implicit-commit.html
- 기본 격리 수준은 REPEATABLE READ 이고 갭 락이 생긴다(유니크 인덱스+유니크 검색 조건이면 갭 없이 해당 레코드만 잠근다). 교착은 같은 순서 접근·짧은 트랜잭션으로 줄이고 `SHOW ENGINE INNODB STATUS` 로 진단한다. 교착은 재시도 가능한 정상 상황이므로 트랜잭션 재실행 로직을 둔다 — 출처: K:mysql/SKILL.md · https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html · https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlocks-handling.html
- `TIMESTAMP` 는 2038-01-19 03:14:07 UTC 까지만 표현하므로 장기 보관 시각은 `DATETIME`(1000-01-01 ~ 9999-12-31)을 쓴다 — 출처: https://dev.mysql.com/doc/refman/8.0/en/datetime.html
