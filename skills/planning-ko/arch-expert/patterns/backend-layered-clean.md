<!-- reference_upstream: wshobson/agents@0874a27 plugins/backend-development/skills/architecture-patterns/SKILL.md (MIT) — specops-ko 한국어 재작성 (20261021-arch-designer-agent) -->
# 백엔드 계층형·Clean·Hexagonal 규칙 — arch-designer-ko 보조 파일

`backend-architecture.md` §2 "선택한 패턴"이 Controller-Service-Repository · Hexagonal · Clean · Onion 중 하나일 때 arch-designer-ko 가 읽는다. 공통 원칙(의존 방향·순환·이음새)은 에이전트 본문에 있다 — 여기에는 이 패턴들에만 해당하는 것만 둔다.

- 도메인 엔티티에 ORM·검증 라이브러리 표기(SQLAlchemy `Column()`·Pydantic `Field()`·JPA `@Entity` 등)를 붙이지 않는다. 저장용 ORM 모델은 어댑터(저장소 구현) 쪽에 따로 두고, 저장소가 도메인 엔티티와 서로 변환한다.
- 컨트롤러(핸들러)는 요청 파싱 · 유스케이스 호출 · 응답 변환 셋만 한다. plan 이 컨트롤러에 업무 규칙·DB 호출을 넣으면 유스케이스로 옮기는 문안을 준다.
- 유스케이스 테스트가 실 DB·Docker·네트워크를 요구하면 계층이 샌 것이다 — 저장소를 포트 뒤로 숨기고 테스트에는 메모리 어댑터를 주입하는 태스크가 plan 에 있어야 한다.
- 유스케이스(`use_cases/`·`application/`)는 포트만 import 하고 구체 어댑터(`adapters/`·`infrastructure/`)를 import 하지 않는다. 구체 어댑터는 조립 지점(진입점·DI 설정) 한 곳에서만 연결한다.
- DDD 를 적용한 plan(에이전트 공통 원칙 "DDD 는 필요할 때만"을 충족)에서는 저장소 인터페이스를 집합체 단위로 둔다(테이블 단위가 아니다) — 저장·복원 대상이 집합체 루트다. 단순 CRUD 는 엔티티 단위 저장소로 충분하다(원문에서 이 규칙은 DDD 전술 패턴 아래에 있다).
- 계층 폴더가 plan 에 새로 생기면 경계 약속의 허용 의존을 그 계층 순서대로 화살표 형식으로 적게 한다(바깥 → 안쪽만 허용 · specops-ko 추가 — FID-B import 방향 대조와 잇는다).
