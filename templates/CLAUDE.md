# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

<PRD §1 한 줄 설명 자동 인용 — `/init-project` Phase 5 가 채움>

## devFSD 사용

본 프로젝트는 devFSD 한국어 자율 Lifecycle 플러그인을 사용합니다.

- **신규 기능**: `/start` 뒤에 기능 설명 — 위험 신호가 없으면 기본 경로(spec 1장 → 구현 → 리뷰 → 검증 → PR), 있으면 풀 경로를 스크립트가 고른다(`--full` 은 무조건 풀)
- **유지보수**: `/maintain` 뒤에 대상
- **몇 줄 수정**: `/quick-fix` 뒤에 고칠 것 (문서 없이 테스트 + 코드 리뷰 1회)
- **공통부 → 일괄 개발**: `/start-foundation` 다음에 `/start-all`
- **프로젝트 부트스트랩**: `/init-project` (이미 실행됨 · 보강은 `--enrich`)
- **산출물**: `.specops/<FID>/` (기능별 lifecycle 산출물)

## 테스트 명령

<!-- 프로젝트의 테스트 명령 한 줄 — 검증 단계가 이 명령을 쓴다. 예: npm test · pytest · bash scripts/tests/run-all.sh -->

```bash
<TEST_COMMAND>
```

## 코딩 컨벤션

<constitution.md §원칙 5개 자동 요약 인용 — `/init-project` Phase 5 가 채움>

- 원칙 1: <원칙 1 이름 — 1줄 요약>
- 원칙 2: <원칙 2 이름 — 1줄 요약>
- 원칙 3: <원칙 3 이름 — 1줄 요약>
- 원칙 4: <원칙 4 이름 — 1줄 요약>
- 원칙 5: <원칙 5 이름 — 1줄 요약>

상세: `.specops/memory/constitution.md`

## 아키텍처

`.specops/memory/*` 산출물 인덱스 — `/init-project` 가 이 프로젝트에 만든 산출물만 남긴다:

- 헌법: `.specops/memory/constitution.md`
- 요구사항 마스터: `.specops/memory/requirements.md`
- 전체 아키텍처: `.specops/memory/architecture.md`
- 프론트 아키텍처: `.specops/memory/frontend-architecture.md` (UI/풀스택/모바일)
- 백엔드 아키텍처: `.specops/memory/backend-architecture.md` (BE/풀스택만)
- IF 설계서: `.specops/memory/api-spec.md` (API 가 있을 때)
- 소비 IF: `.specops/memory/api-spec-consumer.md` (UI·모바일: Phase 8g에서 y 선택 시)
- 테이블 설계서: `.specops/memory/data-model.md` (DB 사용 시)
- 화면 목록: `.specops/memory/screens-overview.md` (UI/풀스택/모바일)
- 테스트 전략: `.specops/memory/test-strategy.md`
- 프로세스 설계서: `.specops/memory/process-design.md`
- 프로젝트 컨텍스트: `.specops/memory/project-context.md`
- 결정 원장: `.specops/memory/decisions.md`

UI 프로젝트인 경우:
- 디자인 시스템: `DESIGN.md`
- 화면 목록: `.specops/memory/screens-overview.md` (상세 `screens/` 는 `/start-all` Phase 2.5 또는 `/design-screen`)

## 작업 흐름

1. **새 기능**: `/start` — 기본 경로는 spec 1장 승인 뒤 PR 까지, 풀 경로는 spec → clarify → plan → 분해 → 구현 → 검증 → 리뷰·게이트 → PR
2. **버그/리팩터**: `/maintain` — 기본 경로는 같고, 풀 경로는 분석(현재 동작·영향)이 앞에 붙는다
3. **검증**: 위 「테스트 명령」

---

*생성: /init-project (Phase 5) · `.specops/memory/*` 인덱스 자동 갱신*
