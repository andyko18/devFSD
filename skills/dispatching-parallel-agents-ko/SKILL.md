---
name: dispatching-parallel-agents-ko
description: 독립 태스크 2개 이상이 공유 상태·순차 의존 없이 진행 가능할 때 사용 — 병렬 서브에이전트 dispatch로 동시에 처리
layer: 2
reference_upstream: obra/superpowers@v5.0.7 skills/dispatching-parallel-agents/SKILL.md
specops_version: 2.9.0
used_by: implementing-ko (독립 leaf 태스크 2개+ 감지 시 자동 분기)
integrates_with: devfsd:file-based-communication-ko, devfsd:context-resets-ko
---

# Engine 스킬 — 병렬 서브에이전트 dispatch

## 개요

독립 도메인의 태스크를 **격리된 컨텍스트의 전문 에이전트들**에 동시에 위임한다. 지시·컨텍스트를 **정확히 조립**해 각 에이전트가 자기 영역에 집중하도록 보장. 서브에이전트는 당신 세션의 컨텍스트·히스토리를 **절대 상속하지 않는다** — 당신이 필요한 것만 구성해 넘긴다. 이로써 당신의 컨텍스트도 코디네이션용으로 보존된다.

**핵심 원칙**: 독립 문제 도메인 1개당 에이전트 1개. 동시에 작업하게 한다.

여러 무관한 실패(다른 테스트 파일·다른 서브시스템·다른 버그)를 **순차로 조사하면 시간 낭비**. 각 조사는 독립적이고 병렬 가능.

## 언제 사용하는가

```
독립 실패가 2개+ 인가?
    ↓ yes
각 실패가 다른 도메인(파일·서브시스템·버그 종류)인가?
    ↓ yes
공유 상태(같은 파일 수정·같은 리소스 사용)가 있는가?
    ↓ no                            ↓ yes
**병렬 dispatch (본 스킬)**       순차 dispatch (`implementing-ko` 기본 패턴)
```

**사용 조건**:
- 3+ 테스트 파일이 서로 다른 근본 원인으로 실패
- 다중 서브시스템이 독립적으로 깨짐
- 각 문제가 다른 문제의 컨텍스트 없이 이해 가능
- 조사 간 공유 상태 없음

**사용하지 않을 조건**:
- 실패들이 연관됨 (하나 고치면 다른 것도 고쳐질 수 있음)
- 전체 시스템 상태 이해 필요
- 에이전트들이 서로 간섭 (같은 파일 편집·같은 리소스)

## 패턴

### 1. 독립 도메인 식별

실패를 무엇이 깨졌는지로 그룹화:
- 파일 A 테스트: 도구 승인 흐름
- 파일 B 테스트: 배치 완료 동작
- 파일 C 테스트: 중단(abort) 기능

각 도메인은 독립 — 도구 승인 수정이 abort 테스트에 영향 없음.

### 2. 집중된 에이전트 태스크 작성

각 에이전트에 다음 4가지 제공:
- **구체 범위**: 테스트 파일 1개 또는 서브시스템 1개
- **명확한 목표**: 이 테스트들이 통과하게 만들기
- **제약**: 다른 코드 수정 금지
- **기대 출력**: 발견·수정 내역 요약

### 3. 병렬 dispatch (Claude Code Task 도구)

```
# 단일 메시지 안에 여러 Task 호출 → 동시 실행
Task("agent-tool-abort.test.ts 실패 수정")
Task("batch-completion-behavior.test.ts 실패 수정")
Task("tool-approval-race-conditions.test.ts 실패 수정")
```

**핵심**: 한 번의 응답 안에 여러 Task 도구 호출을 함께 전송하면 동시 실행. 별도 응답으로 분리하면 순차 실행이 됨.

### 4. 검토와 통합

에이전트들이 반환되면:
1. 각 요약 읽기
2. 수정이 충돌하지 않는지 확인 (`git diff`)
3. 전체 테스트 스위트 실행
4. 모든 변경 통합

## 에이전트 프롬프트 구조

좋은 에이전트 프롬프트는:
1. **집중** — 명확한 문제 도메인 1개
2. **자기완결** — 문제 이해에 필요한 모든 컨텍스트 포함
3. **출력 명세** — 에이전트가 무엇을 반환해야 하는지 명시

```
src/agents/agent-tool-abort.test.ts의 실패 테스트 3개 수정:

1. "should abort tool with partial output capture" — 메시지에 'interrupted at' 기대
2. "should handle mixed completed and aborted tools" — 빠른 도구가 완료 대신 abort됨
3. "should properly track pendingToolCount" — 결과 3개 기대하나 0개 받음

타이밍/race condition 이슈로 추정. 당신의 작업:

1. 테스트 파일 읽고 각 테스트가 검증하는 바 이해
2. 근본 원인 식별 — 타이밍 이슈인가 실제 버그인가?
3. 다음 중 적절한 방식으로 수정:
   - 임의 timeout을 이벤트 기반 대기로 교체
   - abort 구현의 버그 발견 시 수정
   - 변경된 동작 테스트 시 기대값 조정

**timeout만 늘리지 말 것** — 진짜 원인을 찾으라.

반환: 발견 사항과 수정 사항 요약.
```

## 5원칙 주입

| 원칙 | 본 스킬 연결 |
|---|---|
| 1 투명성 | 병렬 dispatch 시 `dispatch-log.md`에 모든 에이전트 프롬프트 + 반환 요약 기록 |
| 2 문지기 | "공유 상태 있는가?" 명시 확인. 회색지대 만들지 말 것 — 의심되면 순차 |
| 3 깊이 | "이 실패들이 정말 독립적인가?" 자문 — 추측 금지, 코드 확인 |
| 4 주권 | 사용자가 "병렬로 해도 되겠지?" 추측 금지. 에이전트 충돌 위험 시 사용자 확인 |
| 5 한계 고백 | 에이전트 자체검토 보고를 **독립 검증 없이** 수용 금지. `git diff` + 테스트 재실행 의무 |

## 흔한 실수

**❌ 너무 광범위**: "모든 테스트 수정" — 에이전트가 길을 잃음
**✅ 구체적**: "agent-tool-abort.test.ts 수정" — 집중된 범위

**❌ 컨텍스트 부재**: "race condition 수정" — 에이전트가 어디인지 모름
**✅ 컨텍스트 제공**: 에러 메시지·테스트 이름 붙여넣기

**❌ 제약 부재**: 에이전트가 모든 것을 리팩터링할 수 있음
**✅ 제약**: "프로덕션 코드 수정 금지" 또는 "테스트만 수정"

**❌ 모호한 출력**: "수정해줘" — 무엇이 변했는지 모름
**✅ 구체적**: "근본 원인과 변경 사항 요약 반환"

## 사용하지 않아야 할 때

- **연관된 실패**: 하나 수정이 다른 것도 수정할 수 있음 — 함께 조사 먼저
- **전체 컨텍스트 필요**: 이해에 시스템 전체가 필요
- **탐색 디버깅**: 무엇이 깨졌는지 아직 모름
- **공유 상태**: 에이전트들이 간섭 (같은 파일 편집·같은 리소스 사용)

## implementing-ko와의 통합

`devfsd:implementing-ko`는 기본적으로 **태스크별 fresh 서브에이전트 순차 dispatch**한다. 다음 조건 모두 충족 시 본 스킬로 분기:

1. **2개 이상 leaf 태스크가 독립** — `decomposing-ko`의 의존 그래프(DAG)에서 의존 edge 없는 태스크 2개+
2. **공유 파일 없음** — 각 태스크가 다른 파일 집합 수정
3. **AC injection contract 충족** — leaf 에이전트는 부모로부터 (a) 자기 담당 AC ID 목록, (b) 관련 spec.md 섹션, (c) test 명령을 명시 받음

**ESCAPE HATCH (F-12 재정의)**: 동일 파일 쌍을 순차 수정하는 TDD 체인이면 집약 가능 (병렬 안 함). 독립 leaf 2개+ 면 본 스킬로 병렬 권장.

## v0.4a — DAG-aware 자동 분기 모드

본 스킬은 두 모드로 동작한다:

### 모드 1: 단순 wrapper (사용자 직접 호출)
사용자가 task 목록을 손으로 넘기는 경우 (마스터 plan 외 ad-hoc 사용).

### 모드 2: DAG-aware 자동 (implementing-ko 호출, v0.4a 표준 경로)
`implementing-ko` 가 다음 절차로 본 스킬 호출:

1. **DAG 파싱**: `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/parse-dag.sh` 의 `dag::find_independent_batch` 호출 — `tasks.md` 의 `## 의존 그래프` YAML 분석
2. **batch 발견 시 (≥2 leaf)**: 각 leaf에 대해:
   - `.specops/<FID>/dispatch/<task-id>-context.md` 작성 (5 컨텍스트 — `templates/dispatch-context.md`)
   - `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/dag/validate-context.sh <path>` 실행 — exit 0 확인
   - `devfsd:using-git-worktrees-ko` skill 호출(Skill 도구) — leaf별 worktree 생성 (`.worktrees/<FID>-<task-id>/`)
3. **본 스킬 호출**: leaf id 배열 + context md path 배열 전달
4. **본 스킬 동작**:
   - 각 leaf 별로 `Task` 도구 병렬 호출 (단일 메시지 다중 tool_use)
   - leaf subagent는 worktree 안에서 작업 + context md 의 5 컨텍스트만 사용
   - leaf 가 NEEDS_CONTEXT 반환 시 부모(implementing-ko)가 보강 후 재dispatch
5. **결과 통합**: 모든 leaf 완료 후 `git diff` 로 충돌 확인 → 머지 순서 (output count 적은 leaf 먼저) → main worktree 로 fast-forward

### batch 미발견 시 (leaf 0~1)
implementing-ko 의 기본 순차 dispatch 경로 유지. 본 스킬 호출 안 함.

### 파싱 실패 시 (malformed YAML)
`dag::find_independent_batch` 가 빈 출력 + stderr WARN — implementing-ko 는 순차 dispatch 로 fallback (advisor 협의 13:00 fallback 시맨틱).

## 검증

에이전트들이 반환된 후:
1. **각 요약 검토** — 무엇이 변했는지 이해
2. **충돌 확인** — 에이전트들이 같은 코드 편집했는가? `git diff`로 확인
3. **전체 스위트 실행** — 모든 수정이 함께 작동하는지 검증
4. **spot check** — 에이전트는 체계적 오류를 만들 수 있음, 자체검토 보고 신뢰 금지

## 다음 skill

병렬 dispatch 완료 후 결과 통합 및 다음 단계:
- `devfsd:verifying-evidence-ko` — 통합 결과 증거 검증
- `devfsd:implementing-ko`로 복귀 — 다음 태스크 또는 마무리

## 참조

- 관련 스킬: `devfsd:implementing-ko` (caller), `devfsd:context-resets-ko` (fresh 세션 보장), `devfsd:file-based-communication-ko` (프롬프트는 파일 경로만)

---

*2026-04-25 · 한국어 이식 + 5원칙 주입 + AC injection contract 통합*
