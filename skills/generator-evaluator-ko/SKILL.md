---
name: generator-evaluator-ko
description: 생성 에이전트와 평가 에이전트를 엄격히 분리하여 자기평가 편향을 차단한다 (OMC 흡수)
layer: 3
reference_upstream: obra/omc@v1.0 skills/generator-evaluator/SKILL.md
specops_version: 1.72.0
used_by: implementing-ko (2단계 리뷰 패턴), requesting-code-review-ko, planning-ko, /start-all (Phase 2.5-D)
---

# Harness 기법 3 — Generator / Evaluator 분리

## 개념

같은 에이전트가 자기 산출물을 평가하면 **확증 편향**이 발생한다. 생성(Generator)과 평가(Evaluator)를 다른 에이전트·다른 세션·다른 역할로 분리해 교차 금지 원칙을 강제한다.

## 페어 매트릭스

분리가 **성립하는 곳은 서브에이전트 dispatch 지점뿐**이다. 명세·설계·분해·검증(`specifying-ko`·`planning-ko`·`decomposing-ko`·`verifying-evidence-ko`)은 서브에이전트가 아니라 **skill 이 메인 세션에서** 수행한다 — 그 단계에는 Gen/Eval 에이전트 페어가 존재하지 않는다. `/start-all` Phase 2.5 화면·IF 산출은 오케스트레이터가 만들고 `design-reviewer-ko`가 판정한다.

| 지점 | Generator | 산출 | Evaluator (서브에이전트) | 검증 산출 |
|---|---|---|---|---|
| 설계 리뷰 | `planning-ko` (메인 세션) | plan.md | `plan-reviewer-ko` | 판정 보고 (PASS/BLOCK) |
| batch 설계 리뷰 | `/start-all` Phase 2.5 (오케스트레이터) | screens + api-spec + data-model | `design-reviewer-ko` | design-review.md + `DESIGN-REVIEW-RESULT` |
| 구현 Phase B | `implementer-ko` | 코드 + 테스트 | `spec-reviewer-ko` | 스펙 준수 판정 |
| 구현 Phase C | `implementer-ko` | (동일 산출) | `code-reviewer-ko` | 코드 품질·보안·커버리지·DB 판정 |
| self-config 감사 | — | (플러그인 자기 번들) | `red-team-ko` → `blue-team-ko` → `auditor-ko` | risk 등급 리포트 |

**실재 에이전트는 `agents/` 14종뿐**: Generator 7 (`implementer-ko`·`req-designer-ko`·`ui-designer-ko`·`db-designer-ko`·`api-designer-ko`·`security-designer-ko`·`test-designer-ko`) / Evaluator 7 (`spec-reviewer-ko`·`code-reviewer-ko`·`plan-reviewer-ko`·`design-reviewer-ko`·`red-team-ko`·`blue-team-ko`·`auditor-ko`). 이 표에 없는 에이전트를 dispatch 하지 마라 — 존재하지 않는다.

## 엄격 규칙

1. **교차 금지**: Generator는 판정하지 않고, Evaluator는 새 산출물을 만들지 않는다.
2. **프롬프트 헤더 의무 선언**: 서브에이전트 dispatch 프롬프트 첫 줄에 다음 중 하나를 명시.
   - `You are a GENERATOR. You MUST produce <output artifact>. You MUST NOT judge prior outputs.`
   - `You are an EVALUATOR. You MUST produce ONLY a judgment artifact (PASS/BLOCK). You MUST NOT modify prior artifacts.`
3. **세션 분리**: Generator 세션과 Evaluator 세션은 별개 서브에이전트 호출로 분리. context-resets 스킬 준수.
4. **파일 통로만**: Evaluator는 Generator의 산출 파일만 읽는다. Generator의 사고 과정·중간 메모에 접근 금지.

## 체크리스트 (커맨드 구현 시)

- [ ] Evaluator 에이전트 frontmatter 에 `role: evaluator` marker 가 있는가? (validate-structure `agent_tools` 가 Write/Edit 박탈을 하드 검사)
- [ ] Generator 는 산출 **파일**을 만들고, Evaluator 는 **판정 보고**만 반환하는가? (판정 파일 저장은 부모 소관 — file-based-communication)
- [ ] 서브에이전트 호출 시 역할 선언 헤더를 포함하는가?
- [ ] Evaluator가 BLOCK 판정 시, 수정은 Generator 재호출로 이뤄지는가? (Evaluator가 직접 고치지 않음)

## 안티패턴

- 같은 에이전트가 "쓰고 검토하고 수정" 전부 수행 → 자기평가 편향
- Evaluator가 "빠르니까 내가 고칠게요" 라며 산출물 수정 → 재현 불가능한 수정 사슬 발생
- Generator가 "내가 봐도 문제없어 보여요" 라며 평가 생략 → Evaluator 우회
- Gen/Eval 페어 바깥의 에이전트가 산출물 수정 → 소유권 위반

## 예시

**GOOD**: `implementing-ko`가 태스크 구현을 `implementer-ko`에 dispatch → 완료 후 **fresh** `spec-reviewer-ko` dispatch → `spec-reviewer-ko`가 코드와 `acceptance-criteria.md`를 읽고 "BLOCK: AC-2 미충족" 판정만 반환 → `implementing-ko`가 BLOCK 사유를 담아 `implementer-ko`를 재dispatch 해 수정.

**BAD**: `spec-reviewer-ko`가 "빠르니까 내가 고칠게요" 라며 코드를 직접 수정. → 계약 위반. Generator 의 소유물을 건드림 (`role: evaluator` frontmatter 가 Write/Edit 를 박탈해 도구 수준에서 차단된다).
