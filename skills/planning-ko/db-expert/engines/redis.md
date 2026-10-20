<!-- reference_upstream: claude-dev-suite/claude-dev-suite skills/databases/redis/SKILL.md · claude-dev-suite/claude-dev-suite skills/databases/redis/quick-ref/patterns.md · davila7/claude-code-templates cli-tool/components/agents/database/nosql-specialist.md · addyosmani/agent-skills skills/performance-optimization/SKILL.md · addyosmani/agent-skills skills/performance-optimization/references/optimization-patterns.md (MIT) · 공식 문서 https://redis.io/docs/latest/commands/keys/ · https://redis.io/docs/latest/commands/incr/ · https://redis.io/docs/latest/develop/reference/eviction/ · https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/ · https://redis.io/docs/latest/develop/using-commands/transactions/ · https://redis.io/docs/latest/develop/using-commands/pipelining/ — specops-ko 한국어 재작성 (20261020-db-designer-agent) -->
# Redis 설계 규칙 — db-designer-ko 보조 파일

`data-model.md` §1 유형이 이 엔진일 때 db-designer-ko 가 읽는다. 공통 규칙은 에이전트 본문에 있다 — 여기에는 이 엔진에만 해당하는 것만 둔다.
약칭: K=claude-dev-suite databases/redis · D7=davila7 nosql-specialist · A1/A2=addyosmani performance-optimization SKILL.md/optimization-patterns.md (모두 MIT).

## 규칙
- 캐시·세션 키에는 항상 TTL(`SETEX`/`EXPIRE`)을 건다. `TTL key` 가 -1 인 키가 남지 않게 점검하고, 값은 작게(≈100KB 미만) 두며 큰 객체는 외부 저장소에 두고 참조만 저장한다 — 출처: K:redis/SKILL.md
- 애플리케이션 코드에서 `KEYS` 를 쓰지 않는다 — O(N) 으로 서버를 막는다. 반복은 `SCAN`, 그룹 무효화는 SET/태그 키로 한다. K:redis 의 `invalidatePattern` 예시 코드는 `KEYS` 를 써서 자기 안티패턴과 모순이니 따라 쓰지 않는다 — 출처: https://redis.io/docs/latest/commands/keys/ · K:redis/SKILL.md
- 분산 락은 `SET key token NX PX ttl` 로 획득하고, 해제는 토큰 비교 후 삭제를 Lua 로 원자 처리한다(토큰 없이 DEL 하면 남의 락을 지운다) — 출처: K:redis/quick-ref/patterns.md · K:redis/SKILL.md · D7
- `maxmemory` 와 `maxmemory-policy` 를 명시한다(`maxmemory` 기본값 0 은 64비트에서 무제한). 캐시는 allkeys-lru 가 일반적 기본 선택이고, noeviction 은 키를 지우지 않고 메모리 초과 시 쓰기 명령에 오류를 낸다. `volatile-*` 정책은 만료 설정된 키가 없으면 noeviction 처럼 동작한다. 복제·영속화를 쓰면 버퍼용 여유 RAM 을 남기고, 영속(RDB/AOF/없음/RDB+AOF)은 내구성 요구에 맞춰 선택해 문서화한다 — 출처: https://redis.io/docs/latest/develop/reference/eviction/ · https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/
- 다수 명령은 pipeline 으로 왕복을 줄이되 한 번에 약 1만 건 단위 배치로 나누고, 관련 필드는 키 여러 개 대신 해시로 둔다. `MULTI/EXEC` 는 롤백이 없다 — EXEC 이전 큐잉 오류는 트랜잭션 전체가 거부되지만 EXEC 이후 실행 오류는 나머지 명령이 계속 실행된다. 원자성이 필요하면 Lua 스크립트를 쓴다 — 출처: D7 · https://redis.io/docs/latest/develop/using-commands/transactions/ · https://redis.io/docs/latest/develop/using-commands/pipelining/
- 카운터+만료(`INCR` 후 `EXPIRE`)를 두 호출로 나누면 그 사이에서 죽을 때 TTL 없는 키가 남는다 — Lua(INCR 값이 1 이면 EXPIRE) 또는 MULTI/EXEC 로 원자화한다 — 출처: https://redis.io/docs/latest/commands/incr/
- 캐시 키에는 응답에 영향을 주는 모든 입력(tenant·locale·권한)을 포함한다 — 빠지면 다른 사용자의 데이터를 내준다. 무효화 전략 하나를 정하고 허용 stale 시간을 명시하며, 핫 키는 stampede 를 방어하고 신선해야 하는 값(잔액·권한)은 캐시하지 않는다 — 출처: A1 · A2
- 운영 접속은 AUTH+TLS 로 하고 연결 풀·재시도(backoff)를 설정하며, 단일 인스턴스 SPOF 는 Sentinel/Cluster 로 푼다 — 출처: K:redis/SKILL.md
