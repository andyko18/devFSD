---
name: file-based-communication-ko
description: 서브에이전트 호출 시 프롬프트에 파일 경로만 전달하고 본문 페이로드는 금지한다
layer: 3
reference_upstream: revfactory/harness@v1.0 skills/file-based-communication/SKILL.md
specops_version: 1.44.0
used_by: implementing-ko (서브에이전트 dispatch 시 파일 경로 전달)
---

# Harness 기법 5 — File-Based Communication

## 개념

서브에이전트를 호출할 때 프롬프트에 **파일 경로만 전달**한다. 파일 본문을 프롬프트에 붙여넣지 않는다. 이것이 대규모 아티팩트에서 컨텍스트 낭비를 막고, 에이전트가 스스로 필요한 부분만 읽는 자기조절 능력을 부여한다.

## 규칙

1. 서브에이전트 호출 프롬프트는 **경로 + 지시사항**의 두 요소만 갖는다.
2. 경로는 **절대 경로** 또는 프로젝트 루트 기준 **상대 경로**. 모호성 금지.
3. 에이전트가 읽어야 할 파일이 여러 개면 **우선순위를 매겨 나열**. "AC 파일을 먼저, 그다음 plan.md."
4. 에이전트가 **쓸** 파일도 경로로 지시. "결과를 `.specops/<FID>/analysis.md`에 JSON 블록으로 저장."
5. 호출자는 서브에이전트 응답에서 **산출 파일 경로만 확인**하고 본문을 다시 읽는다. 응답에 본문이 와도 그걸 신뢰하지 말고 파일을 직접 읽는다.

## 프롬프트 템플릿

```
You are <agent-name>, a <Generator|Evaluator> in the specops-ko Lifecycle.

READ (in order):
1. /path/to/.specops/<FID>/acceptance-criteria.md (contract)
2. /path/to/.specops/<FID>/plan.md (artifact under review)
3. /path/to/knowledge/constitution/five-principles.md (Layer 5)

TASK:
<구체 작업 지시 — 한국어 존댓말로>

WRITE:
/path/to/.specops/<FID>/analysis.md (JSON block per sprint-contracts schema)

CONSTRAINTS:
- Do NOT modify the artifact files you read.
- Do NOT embed file contents in your response — write to the output path.
- Use 한국어 존댓말 in the output file.
```

## 체크리스트

- [ ] 프롬프트에 파일 본문이 들어가지 않았는가?
- [ ] READ·TASK·WRITE 3 섹션이 명확한가?
- [ ] 경로가 절대 경로 또는 루트 기준 상대 경로인가?
- [ ] 에이전트 응답 후 호출자가 WRITE 파일을 **직접 다시 읽는가**?
- [ ] 한국어 응답을 요구했는가? (CLAUDE.md §9)

## 안티패턴

- 프롬프트에 "여기 plan.md 내용입니다: ..." + 전체 붙여넣기 → 컨텍스트 낭비, 재사용성 0
- 경로 없이 "방금 그 plan 문서 기반으로 분석해줘" → 서브에이전트는 이전 대화를 모름
- 서브에이전트 응답에 담긴 파일 내용을 그대로 신뢰하여 다음 단계 진행 → 파일 실제 내용과 불일치 위험
- WRITE 경로를 지정하지 않고 "결과 알려줘" → 산출물이 대화 메시지에 휘발됨

## 예시

**GOOD**:
```
You are plan-reviewer-ko (Evaluator).
READ:
1. /Users/mac/Project/foo/.specops/20260420-rss-cache/acceptance-criteria.md
2. /Users/mac/Project/foo/.specops/20260420-rss-cache/plan.md
TASK: 각 AC가 plan의 태스크에 1:1로 매핑되는지 확인하고, 미매핑 AC를 BLOCK 사유로 분류하세요.
REPORT: 판정(PASS/BLOCK)과 근거만 반환하세요. 읽은 산출물을 수정하지 마세요 — 판정 파일 저장은 호출자 소관입니다.
```
> Evaluator 에이전트(`role: evaluator`)는 Write/Edit 가 **박탈**돼 있다. WRITE 경로 지시는 Generator(`implementer-ko`) dispatch 에만 쓴다.

**BAD**:
```
방금 만든 plan.md 내용:

# Plan
...전체 2000줄 붙여넣기...

이거 검토해줘.
```

### 예외 — Phase B/C 리뷰어 보고서 저장 (20260914)

`spec-reviewer-ko`·`code-reviewer-ko` 의 보고서는 호출자가 아니라 SubagentStop 훅(`hooks/save-review-report.sh`)이 저장한다. 리뷰어는 여전히 read-only 이고, 전문을 `<<<REVIEW …>>>` 블록으로 내면 훅이 `reviews/<tid>-<phase>-report.md` 로 옮긴 뒤 요약 재종료를 요구한다.

- 판정 SoT = reviews 파일 — 반환 요약은 경로 포인터일 뿐이다. 판정은 파일을 읽어 확정한다
- report 부재 시 부모 fallback 저장 — 훅이 돌지 않았거나 형식이 틀리면 전문이 그대로 반환되므로 부모가 태스크별로 저장한다. 반환에 훅 요약이 없으면 파일 존재와 무관하게 덮어쓰기 저장한다(이전 라운드 report 가 남아 옛 판정을 읽는 경로 차단) · 반환 뒤 `review-saved.sh check` 가 rc 0 이면(훅이 이번 dispatch 뒤 저장) 다시 쓰지 않는다 — 규약 원본은 implementing-ko 「end-loaded B/C 산출물 규약」
- dispatch-log 행은 부모가 기록 — 훅은 파일만 쓴다
- 한계: `SPECOPS_GOVERNANCE_PROFILE` 이 `standard`·`minimal` 이면 is-hook-enabled 가 이 훅을 끄므로 저장은 전부 부모 fallback 경로로 간다
