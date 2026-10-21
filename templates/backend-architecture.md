<!-- OWNER_COMMAND: /init-project -->
<!-- layer: Project-Memory -->

# <PROJECT_NAME> 백엔드 아키텍처

> 한국 SI 표준 "백엔드 아키텍처". `/init-project` Phase 8d 가 1회 생성 (BE/풀스택 종류만).

## 1. 프레임워크

- **주 프레임워크**: <Express / Fastify / NestJS / Spring Boot / FastAPI / Gin / Rails>
- **언어**: <TypeScript / Java / Python / Go / Ruby>
- **런타임**: <Node 20 / JVM 21 / Python 3.12 / Go 1.22>
- **빌드/패키지**: <pnpm / Maven / poetry / go mod>

## 2. 레이어 구조

선택한 패턴: <Controller-Service-Repository / Hexagonal / Clean / Onion>

```
src/
├── controllers/  # HTTP 진입점 (Request → DTO 변환)
├── services/     # 비즈니스 로직 (도메인 규칙)
├── repositories/ # DB 접근 추상화
├── domain/       # 엔티티·값 객체·도메인 이벤트
├── infrastructure/ # DB·외부 서비스·캐시 구현체
├── middlewares/  # Cross-cutting (Auth·Logging·CORS·Rate-limit)
└── config/       # 환경 설정·의존성 주입
```

## 3. 미들웨어 / Cross-cutting

| 항목 | 라이브러리 / 패턴 | 비고 |
|---|---|---|
| 인증 | <Passport / Spring Security / JWT> | Access + Refresh 토큰 |
| 인가 | <RBAC / ABAC> | 역할/속성 기반 |
| 로깅 | <Pino / Winston / SLF4J / structlog> | JSON 구조화 |
| 모니터링 | <OpenTelemetry / Sentry> | 분산 추적 + 에러 |
| Rate Limit | <express-rate-limit / Bucket4j> | IP/User 단위 |
| CORS | <기본 미들웨어> | origin allowlist |
| 검증 | <zod / class-validator / Pydantic> | DTO 스키마 |

## 4. 비동기 처리

| 큐 | 도구 | 용도 |
|---|---|---|
| 일반 작업 | <BullMQ / Sidekiq / Celery> | 이메일·이미지 처리 |
| 메시지 | <RabbitMQ / SQS / Kafka> | 이벤트 발행 |
| 스케줄 | <node-cron / cron / Airflow> | 정기 배치 |

DLQ (Dead Letter Queue) 정책: 3 회 실패 → DLQ 이동 + 알림

## 5. 배포

- **컨테이너**: <Docker / Podman>
- **오케스트레이션**: <Kubernetes / Docker Swarm / Nomad>
- **서버리스 (선택)**: <Lambda / Cloud Functions / Cloud Run>
- **CI/CD**: <GitHub Actions / GitLab CI / ArgoCD>
- **롤링 배포**: <RollingUpdate / Blue-Green / Canary>

## 6. 데이터 접근

- **ORM/Query Builder**: <Prisma / TypeORM / SQLAlchemy / JPA / sqlx>
- **마이그레이션**: <Prisma Migrate / Alembic / Flyway / sqlx-cli>
- **트랜잭션 정책**: <Service 레이어에서 명시적 begin/commit>
- 상세: `.specops/memory/data-model.md`

## 7. API 설계

상세 IF: `.specops/memory/api-spec.md`

- 버저닝: <URL prefix `/v1/` / Header `Accept-Version`>
- 에러 포맷: <RFC 9457 Problem Details / 자체 envelope>
- 페이지네이션: <cursor / offset>

## 8. 테스트

- 단위: <Jest / pytest / JUnit>
- 통합: <Supertest + TestContainers / pytest + docker-compose>
- 부하: <k6 / Locust>
- 보안: <Snyk / OWASP ZAP>
- 상세: `.specops/memory/test-strategy.md`

## 9. 보안

- 비밀 관리: <Vault / AWS Secrets Manager / GCP Secret Manager>
- 입력 검증: 모든 외부 입력을 §3 검증 미들웨어로 통과
- SQL Injection: 파라미터화된 쿼리 + ORM
- XSS: 출력 escape (응답 자동)
- CSRF: <SameSite Cookie / 토큰>

## 10. 참조

- 상위: `.specops/memory/architecture.md`
- 데이터: `.specops/memory/data-model.md`
- IF: `.specops/memory/api-spec.md`
- 헌법: `.specops/memory/constitution.md`

---

*작성: <작성자> · <YYYY-MM-DD> · 생성: /init-project (Phase 8d)*
