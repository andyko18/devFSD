# skills/ — SKILL.md 규약 · 서브에이전트 리뷰 패턴

> 루트 `CLAUDE.md` 에서 원문 그대로 분리했다(20261112). 하위 디렉터리의 CLAUDE.md 는 그 폴더의 파일을 읽거나 고칠 때만 로드된다 — 루트에는 요약과 포인터만 있다.

### SKILL.md frontmatter 필수 필드

```yaml
---
name: <스킬명>
description: <한 줄 설명>
layer: <1|2|3>
reference_upstream: <owner/repo@version path>  # 포맷 필수 (독자 추가 시 "specops-ko 독자 추가" 허용)
specops_version: <semver>  # 본 skill 본문이 마지막으로 substantive 변경된 플러그인 버전 (자동 갱신 아님)
used_by: <호출자 목록>  # 표기 규약 — command 는 /<name>, skill 은 short name (<skill>-ko)
---
```

선택 marker 필드: skills `discipline: true` (합리화 차단표 의무 — test-skill-conventions T9 스캔), agents `role: evaluator` (Write/Edit 박탈 하드강제 — validate-structure agent_tools 스캔). 신규 discipline/evaluator 항목은 marker 만 달면 자동 검사 편입.

### 서브에이전트 리뷰 패턴 (Generator ↔ Evaluator 분리)

Generator와 Evaluator를 엄격히 분리해 자기평가 편향을 차단한다. `agents/` 의 서브에이전트는 용도가 나뉜다:

- **구현 2단계** (`implementing-ko` 가 태스크별 fresh dispatch): **Phase B** `spec-reviewer-ko`(스펙 준수만) → PASS 후 **Phase C** `code-reviewer-ko`(코드 품질·보안·커버리지·DB 관점).
- **설계 리뷰** (`planning-ko` 가 dispatch): `plan-reviewer-ko` — TDD 커버리지·플레이스홀더·파일 경계·타입 일관성 + 실측 의무.
- **batch 화면·IF 리뷰** (`/start-all` Phase 2.5-D): `design-reviewer-ko` — Interactions↔api-spec·data-model 정합·껍데기·cross-FR + 실측 의무.
- **self-config 적대감사** (`/security-scan --self-config`): `red-team-ko`(공격 표면 탐색) → `blue-team-ko`(기존 방어 유효성 평가) → `auditor-ko`(종합 risk 등급 A~F 리포트). 플러그인 자기 hooks·rules·settings 번들을 read-only 감사.

Evaluator 에이전트는 frontmatter `role: evaluator` 로 Write/Edit 를 하드 박탈한다 (validate-structure `agent_tools` 스캔 강제).

서브에이전트의 **모델·effort 는 각 `agents/*.md` frontmatter 가 단일 소스**다(별칭 sonnet·opus 만, fable 금지 — 프로파일 표와 사용자 덮어쓰기는 README `## 모델 · effort 운용`). 값은 `test-review-evidence-rules`(Evaluator 4종)·`test-gate-presence`(구현자·상향 규칙·README 문구)가 잠근다.
