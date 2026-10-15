<!-- reference_upstream: github/spec-kit .specify/memory/constitution-template.md -->
<!-- OWNER_COMMAND: /init-project -->
<!-- layer: Project-Memory -->

# <PROJECT_NAME> 헌법

> AI 에이전트와 사람 모두 읽는 프로젝트의 **불변 원칙** 문서. spec-kit `.specify/memory/constitution-template.md` 패턴 차용.
> 본 파일은 `/init-project` 가 1회 생성. 이후 변경은 거버넌스 §개정 절차 준수.

**version**: 1.0.0
**ratification_date**: <YYYY-MM-DD>
**last_amended_date**: <YYYY-MM-DD>

## 원칙

### 원칙 1: <PRINCIPLE_1_NAME>

**규칙**: <한 문장 — MUST/SHOULD/MAY 명시>

**근거**: <왜 이 원칙이 필요한가 — 1~2 문장>

### 원칙 2: <PRINCIPLE_2_NAME>

**규칙**: <한 문장>

**근거**: <1~2 문장>

### 원칙 3: <PRINCIPLE_3_NAME>

**규칙**: <한 문장>

**근거**: <1~2 문장>

### 원칙 4: <PRINCIPLE_4_NAME>

**규칙**: <한 문장>

**근거**: <1~2 문장>

### 원칙 5: <PRINCIPLE_5_NAME>

**규칙**: <한 문장>

**근거**: <1~2 문장>

## 구조 규칙

> 코드의 **구조**에 대한 규칙을 정해진 형식의 표로 적는다 — 원칙(위)이 "왜"라면 이 표는 "어디에 무엇을 두는가"다.
> 판정할 수 있는 것만 적는다: 리뷰어가 diff 를 보고 예/아니오로 답할 수 있거나, 명령 하나로 검사할 수 있는 규칙.
> 예시 행(ID 칸이 `(예시)` 로 시작)은 규칙으로 세지 않는다 — 지우고 실제 규칙을 적는다. 정할 규칙이 아직 없으면 그대로 둔다.

| 칸 | 적는 것 |
|---|---|
| ID | `S-1`, `S-2` … (중복 없이) |
| 규칙 | 한 문장 |
| 적용 경로 | 이 규칙이 적용되는 폴더·파일 |
| 판정 | `리뷰`(리뷰어가 diff 로 판정) 또는 `명령`(명령으로 검사) |
| 판정 명령 | 판정이 `명령`일 때 실행할 명령. 없으면 `-` |

칸 안에는 세로줄 문자를 쓸 수 없다(명령에 파이프가 필요하면 스크립트 파일로 감싼다). 형식 확인: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/_internal/check-constitution-rules.sh`

판정 `명령` 은 검증(verify) 때 실행된다 — 결과는 경고로만 남는다(evidence.md `### structure-rule-commands`). 테스트 명령과 같은 허용 형식만 실행하고(예: `bash scripts/tests/test-structure.sh S-2` · `pytest …`), 그 밖(`! grep …` · `make …` 등)은 실행하지 않고 SKIP 으로 보고한다.

<!-- structure-rules:start -->
| ID | 규칙 | 적용 경로 | 판정 | 판정 명령 |
|---|---|---|---|---|
| (예시) S-1 | 외부 서비스 호출은 어댑터 모듈에만 둔다 | `src/adapters/` | 리뷰 | - |
| (예시) S-2 | 현재 시각은 시계 모듈로만 얻는다 | `src/` | 명령 | `bash scripts/tests/test-structure.sh S-2` |
<!-- structure-rules:end -->

## 거버넌스

### 개정 절차

1. 변경 제안: PR 또는 이슈로 변경 사유와 영향 범위 명시
2. 검토: 프로젝트 메인테이너 ≥ 1 인 승인
3. 버전 증가: semver 규칙 (MAJOR: 원칙 제거/재정의, MINOR: 원칙 추가, PATCH: 문구 정정)
4. `last_amended_date` 갱신
5. 의존 문서 (PRD.md / CLAUDE.md / requirements.md) 동기화 검토

### 컴플라이언스 점검

- spec/plan/code 작성 시 본 헌법의 원칙을 모두 만족하는지 자체 검토
- specops-ko Lifecycle 의 specifying-ko / planning-ko / receiving-code-review-ko 가 본 헌법을 자동 인용

## 참조

- 의존 문서: `PRD.md`, `CLAUDE.md`, `.specops/memory/requirements.md`, `.specops/memory/test-strategy.md`
- 거버넌스 원본: github/spec-kit `.specify/memory/constitution-template.md`

---

*작성: <작성자> · <YYYY-MM-DD> · 생성: /init-project (Phase 3)*
