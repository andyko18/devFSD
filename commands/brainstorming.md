---
name: brainstorming
disable-model-invocation: true
description: 구현 전 아이디어 탐색·수요 검증 슬래시 — devfsd:brainstorming-ko 호출. pre-init-project 선택 진입점.
triggers:
  - "/brainstorming"
mode: ask
specops_version: 2.6.0
specops_layer: Lifecycle-PreBootstrap
reference_upstream: specops-ko 독자 추가 (garrytan/gstack office-hours 한국어 재창작)
---

# /brainstorming [<주제>]

## 목적

`/init-project` 전에 "뭘 만들지 모르겠을 때" 또는 아이디어를 검증·구체화하고 싶을 때 사용하는 **선택적 진입점**.

Startup 모드(YC 6 forcing questions 기반 수요 검증)와 Builder 모드(창의 탐색) 중 하나를 선택해 진행한다.

## Process

1. **즉시 `devfsd:brainstorming-ko` 호출** — 전달된 `<주제>`를 초기 맥락으로 제공
2. 모드 선택 GATE (Startup / Builder)
3. 질문 기반 탐색 진행
4. 산출물 저장: `.specops/memory/brainstorming-<날짜>-<시간>-<슬러그>.md`
5. 탐색 완료 후 사용자 결정에 따라 `/init-project` 또는 `/start <기능>` 진행

## 권장 흐름

```
/brainstorming <아이디어>
    ↓
.specops/memory/brainstorming-<날짜>-<시간>-<슬러그>.md 저장
    ↓ (탐색 완료 후 선택)
/init-project          # 프로젝트 구조 부트스트랩 (메모→PRD 초안 합성 + Phase 11 보강)
    ↓
/start <첫 기능>         # Lifecycle 진입
```

## 사용 예

```
/brainstorming 사내 일정 관리 앱 아이디어

→ brainstorming-ko 호출
→ "Startup / Builder 모드 선택" GATE
→ Startup 선택 → YC 6 질문 진행
→ .specops/memory/brainstorming-20260515-143022-sanae-iljeong-gwanri-aep.md 저장
  (slug 은 scripts/slug.sh 가 국립국어원 로마자 표기법으로 한글 주제를 ASCII kebab 변환)
→ "/init-project 로 부트스트랩하시겠어요?" 안내
```

```
/brainstorming 해커톤 아이디어 탐색

→ Builder 모드 선택
→ 창의 탐색 질문 5개
→ 대안 3개 병렬 제시
→ 방향 결정 후 저장
```

## 선택적 진입점

본 슬래시는 Lifecycle **필수 단계가 아니다**. 이미 뭘 만들지 알면 바로 `/init-project` 또는 `/start <기능>`으로 진입해도 된다.

| 상황 | 권장 진입 |
|---|---|
| 아이디어가 있지만 방향 불확실 | `/brainstorming <아이디어>` → `/init-project` |
| 무엇을 만들지 이미 앎 | `/init-project` 직행 |
| 프로젝트 초기화됨, 기능 구현 시작 | `/start <기능>` 직행 |

## 안티패턴

- **구현 직진 요구** — 탐색이 목적. 코드 작성은 brainstorming-ko의 HARD GATE에 의해 거절됨
- **강제 chain** — 탐색 후 `/init-project` 자동 호출 없음. 사용자 결정

## 참조

- `skills/brainstorming-ko/SKILL.md` — 본 슬래시의 실행 skill
- `commands/init-project.md` — 다음 단계 (부트스트랩)
- `commands/start.md` — Lifecycle 진입점
- `skills/using-specops-ko/SKILL.md` — 메타 skill (선택 진입점 언급)

---

*specops-ko v2.6.0 · 2026-07-09 · garrytan/gstack office-hours/SKILL.md 참조*
