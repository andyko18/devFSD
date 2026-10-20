<!-- reference_upstream: claude-dev-suite/claude-dev-suite skills/databases/oracle/SKILL.md · claude-dev-suite/claude-dev-suite skills/databases/oracle/quick-ref/datatypes.md · claude-dev-suite/claude-dev-suite skills/databases/oracle/quick-ref/sequences.md (MIT) · 공식 문서 https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ (Nulls · Expression-Lists · MERGE · CREATE-SEQUENCE · ROWNUM-Pseudocolumn · Types-of-SQL-Statements) · https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/ · https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/partition-concepts.html — specops-ko 한국어 재작성 (20261020-db-designer-agent) -->
# Oracle 설계 규칙 — db-designer-ko 보조 파일

`data-model.md` §1 유형이 이 엔진일 때 db-designer-ko 가 읽는다. 공통 규칙은 에이전트 본문에 있다 — 여기에는 이 엔진에만 해당하는 것만 둔다.
공식 문서 기반 규칙은 Oracle 19c 문서를 대조했다. ORA 에러 코드는 문서 페이지에 적혀 있지 않아 관용 표기다. 약칭: K=claude-dev-suite databases/oracle (MIT).

## 규칙
- 길이 0 문자열은 NULL 이다 — NOT NULL 문자 컬럼에 빈 문자열을 넣을 수 없고 `col = ''` 는 항상 거짓이다(`IS NULL` 을 쓴다). 다른 DB 에서 이식할 때 빈 문자열/NULL 구분이 사라진다 — 출처: https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Nulls.html
- `DATE` 는 시각(초)을 포함한다 — 일 단위 비교는 `TRUNC(date)` 또는 범위(`>= d AND < d+1`)로 한다. 문자 길이는 `VARCHAR2(n CHAR)` 와 BYTE 의미를 구분하고(다국어는 CHAR), 금액은 `NUMBER(p,s)` 를 쓴다 — 출처: K:oracle/SKILL.md · K:oracle/quick-ref/datatypes.md
- 바인드 변수를 쓰고(하드 파싱 방지) 암묵적 형변환을 하지 않는다(`TO_CHAR`/`TO_NUMBER` 를 명시 — 인덱스가 무력화된다). IN 목록은 표현식 1000 개를 넘을 수 없다(ORA-01795 — 에러 코드는 관용 표기). 튜플 형태의 리스트는 집합당 1000 개 이하면 된다 — 출처: K:oracle/SKILL.md · https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Expression-Lists.html
- upsert 는 `MERGE` 로 하고 `WHEN MATCHED THEN UPDATE SET` 에는 갱신할 컬럼만 둔다. ON 절에 쓴 컬럼(조인 키)은 갱신할 수 없다(ORA-38104 — 에러 코드는 관용 표기) — 출처: K:oracle/SKILL.md · https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/MERGE.html
- 12c+ 는 `GENERATED … AS IDENTITY` 를 쓴다. 시퀀스는 롤백·동시 사용·장애로 번호가 건너뛰므로(CACHE 기본 20) 연속성을 가정하지 않는다 — 출처: K:oracle/quick-ref/sequences.md · https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-SEQUENCE.html
- 함수 기반 인덱스(`UPPER(col)`)는 질의에 같은 함수/표현식이 들어갈 때만 쓰인다. 대형 테이블은 파티션 키를 WHERE 에 넣어 pruning 하고, 로컬 인덱스는 파티션 키가 인덱스 키의 부분집합일 때 권고된다(로컬 UNIQUE 는 파티션 키를 인덱스 키에 포함해야 한다) — 출처: K:oracle/SKILL.md · https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html · https://docs.oracle.com/en/database/oracle/oracle-database/19/vldbg/partition-concepts.html
- `ROWNUM` 은 ORDER BY 보다 먼저 부여되므로 정렬 후 N 건은 ORDER BY 를 서브쿼리로 감싸거나 `FETCH FIRST n ROWS ONLY` 를 쓴다. 문서는 row_limiting_clause 가 ROWNUM 보다 낫다고 설명하며, 도입 버전(12c)은 확인하지 않았다(미확인) — 출처: https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ROWNUM-Pseudocolumn.html
- DDL 은 문장 전후로 현재 트랜잭션을 암묵 커밋하므로 롤백되지 않는다 — 되돌림은 백업 또는 보정 마이그레이션으로 계획한다(Flashback 활용은 이 파일에서 대조하지 않았다) — 출처: https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Types-of-SQL-Statements.html
