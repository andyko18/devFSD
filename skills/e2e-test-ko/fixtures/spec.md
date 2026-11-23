<!-- FID: <FID> -->
<!-- OWNER_COMMAND: /specify -->
<!-- reference_upstream: specops-ko 독자 추가 -->
<!-- layer: Lifecycle-Artifact -->

# greet-cli 명세 — <FID>

## 1. 개요

**목적**: 이름을 CLI 인자로 받아 한국어 인사말을 출력하는 bash 함수를 제공한다.

**배경**: E2E 테스트용 내장 fixture. specops-ko lifecycle chain의 전체 동작을 검증하기 위한 최소 기능.

**성공 판정**: greet-cli.sh가 이름을 인자로 받아 "안녕하세요, <name>!"을 출력하면 완성.

**§유형**: 신규

## 2. 범위

### 포함
- greet-cli.sh: 이름 인사 bash 함수 (독립 — 병렬 구현 가능)
- test-greet-cli.sh: 단위 테스트 스크립트 (독립 — 병렬 구현 가능)

### 제외 (YAGNI)
- 다국어 지원
- 설정 파일
- 환경변수 오버라이드

## 3. 사용자 시나리오

### 주요 시나리오
**사용자**: 개발자
**상황**: 터미널에서 이름을 인자로 스크립트 실행
**행동**: `bash .specops/<FID>/greet-cli.sh 철수`
**기대 결과**: `안녕하세요, 철수!` 출력

### 보조 시나리오
**상황**: 인자 없이 실행
**행동**: `bash .specops/<FID>/greet-cli.sh`
**기대 결과**: 오류 메시지 + exit 1

## 4. 기능 요구사항 (FR)

| ID | 요구사항 | 우선순위 |
|---|---|---|
| FR-1 | greet-cli.sh <name> → "안녕하세요, <name>!" 출력 | must |
| FR-2 | 인자 없을 시 → 오류 메시지 + exit 1 | must |
| FR-3 | 빈 문자열 인자 → 오류 처리 + exit 1 | should |

## 5. 비기능 요구사항 (NFR)

| ID | 항목 | 기준 |
|---|---|---|
| NFR-1 | 호환성 | bash 3.2+ (macOS 실측 · Linux 미검증) |
| NFR-2 | 응답시간 | 즉시 (< 100ms) |

## 6. 제약사항

- 기술 스택: bash (외부 의존성 없음)
- 생성 위치: `.specops/<FID>/` 하위

## 7. 가정

- bash 3.2 이상 설치됨 (macOS 기본)
- .specops/<FID>/ 디렉토리가 미리 생성됨

## 8. 열린 질문

(S2 CLARIFY 단계에서 해소됨)

## 9. Advisor 협의 기록

해당 없음 — E2E fixture이므로 설계 불확실 지점 없음.

## 10. 참조

- DESIGN.md 디자인 시스템 준수 (비UI 기능이므로 시각 규칙 해당 없음)

---

*작성: e2e-test-ko · <날짜> · FID: <FID> · 생성 커맨드: /e2e-test*
