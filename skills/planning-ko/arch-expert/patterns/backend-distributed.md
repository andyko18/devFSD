<!-- reference_upstream: wshobson/agents@0874a27 plugins/backend-development/skills/microservices-patterns/SKILL.md · plugins/backend-development/skills/architecture-patterns/SKILL.md (MIT) — specops-ko 한국어 재작성 (20261021-arch-designer-agent) -->
# 백엔드 분산·여러 서비스 규칙 — arch-designer-ko 보조 파일

`backend-architecture.md` §4 "메시지" 행이 채워졌거나 서비스가 둘 이상일 때 arch-designer-ko 가 읽는다. 단일 프로세스 앱에는 적용하지 않는다.

- 서비스마다 자기 데이터 저장소를 가진다. 두 서비스가 같은 테이블을 직접 읽고 쓰는 plan 은 지적한다 — 소유 서비스의 API·이벤트로만 접근하게 고친다.
- 서비스 경계는 업무 기능(주문·결제·재고) 또는 바운디드 컨텍스트에 맞춘다. 기술 계층(공통 DB 서비스·유틸 서비스)으로 나누지 않는다.
- 여러 서비스에 걸친 쓰기는 분산 트랜잭션 대신 saga 로 하고, 단계마다 보상 동작(취소·환불)을 plan 에 적는다. 최종 일관성이 허용되는지 spec 에 적혀 있어야 한다.
- 서비스 간 동기 호출(REST·gRPC)에는 회로 차단기(연속 실패 시 빠른 실패)와 격벽(호출 대상별 자원 분리)을 둔다 — 한 서비스 장애가 연쇄되지 않게 한다.
- 이벤트·메시지를 받는 쪽은 같은 메시지를 두 번 받아도 결과가 같게(멱등) 처리하는 방법을 plan 에 적는다(specops-ko 추가 — 원문에 없음).
- 모놀리스에서 떼어 내는 plan 은 한 번에 옮기지 않고 프록시가 새·옛 경로를 나눠 보내는 점진 분리(strangler fig)로 단계를 나눈다.
