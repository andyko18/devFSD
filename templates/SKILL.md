---
name: "{{skill-name}}"
description: "{{one-line description — 어떤 상황에 사용, 핵심 기능}}"
layer: "{{1|2|3}}"
reference_upstream: "{{owner/repo@version path 또는 specops-ko 독자 추가}}"
specops_version: "{{semver — 예: 1.0.0}}"
used_by: "{{호출 스킬 목록 — 예: devfsd:implementing-ko}}"
---

# {{Skill Title}}

## 개요

{{이 skill이 무엇을 하는가. 1~2 문장.}}

## 사용 시점

{{언제 이 skill을 사용하는가. 조건·트리거 기술.}}

## 프로세스 / 체크리스트

{{구체적 단계. 체크리스트 형식 권장.}}

1. **Step 1: ...**
2. **Step 2: ...**

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 skill 적용 |
|---|---|
| 1 **투명성** | {{이 skill에서 투명성 원칙 적용 방법}} |
| 2 **문지기** | {{이 skill에서 파괴적 작업 방지 방법}} |
| 3 **깊이** | {{이 skill에서 깊이 원칙 적용 방법}} |
| 4 **주권 존중** | {{이 skill에서 사용자 주권 보장 방법}} |
| 5 **한계 고백** | {{이 skill의 알려진 한계}} |

## 참조

- `{{관련 skill 또는 파일 경로}}` — {{설명}}
- upstream 원본: `{{reference_upstream 값}}`

## 합리화 차단표 (Rationalization Table)

> 본 섹션은 **discipline-class skill** (거버넌스 강제·규율 위반 방지 목적)에만 포함.
> 일반 skill 은 생략. failure-first 관찰로 발견한 agent 합리화 패턴만 기재.
> discipline-class 는 frontmatter 에 `discipline: true` marker 필수 — test-skill-conventions T9 가 marker 스캔으로 본 섹션 존재를 강제한다 (marker 누락 시 검사 사각).

| AI 합리화 패턴 | 차단 규칙 |
|---|---|
| "{{핑계 1}}" | {{차단 방법}} |
| "{{핑계 2}}" | {{차단 방법}} |

## 다음 skill

{{이 skill 완료 후 호출할 skill. 또는 "chain 종료" 명시.}}

```
Skill: devfsd:{{next-skill-name}}
```
