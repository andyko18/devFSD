---
name: advisor-ko
description: 기획·분석·설계·개발 중 스스로 확신이 없거나 모르는 지점이 생길 때, 또는 사용자가 결정을 맡기며 불확실함을 드러내거나 판단 근거의 검증을 요청할 때 호출 — advisor 도구로 외부 자문을 받아 단정·합리화·circular 검증을 차단
layer: 2
reference_upstream: specops-ko 독자 추가
specops_version: 2.18.0
used_by: using-specops-ko (cross-cutting 상시 — 기획·분석·설계·구현 중 애매성 발생 시 ambient 적용), planning-ko (advisor() 실호출)
user-invocable: false
---

# Advisor 활용 원칙

`advisor` 는 본 세션의 전체 conversation 을 자동 전송받는 외부 reviewer 모델. 단정·합리화·자기-편향 (self-confirmation bias) 을 차단해 specops-ko 의 5 원칙 (특히 원칙 1 투명성 · 원칙 5 한계 고백) 을 강화한다.

**트레이드오프:** advisor 호출은 latency + 토큰 비용을 발생시킨다. 자명한 작업 (typo fix, 단순 rename, 1 줄 변경 등) 은 호출하지 않는다. **애매성 / 미확신 / 결정 갈래** 가 있을 때만 호출.

---

## 원칙 1 — 호출 시점 (When)

**다음 중 하나 이상에 해당하면 호출 의무.** 합리화로 우회 금지.

- **substantive work 직전** — 첫 파일 편집·첫 commit·첫 결정 발화 직전
- **task 완료 직전** — 산출물 (spec/plan/evidence 등) durable 하게 저장한 후, 종결 발화 전
- **stuck 상태** — 같은 에러 2 회 이상 / 접근 불일치 / 결과가 가설과 안 맞음
- **접근 변경 고려 시** — 다른 방향 검토 의도 발생 시
- **circular 검증 위험** — 본 세션이 작성한 산출물을 본 세션이 검증하는 패턴 감지 시

**specops-ko 연결:** 원칙 5 한계 고백 + 단계별 HARD GATE 보강

---

## 원칙 2 — 단계별 호출 시점 (Where)

| 단계 | skill | advisor 호출 시점 | 산출물 반영 |
|---|---|---|---|
| **기획** | `specifying-ko` | spec.md §유형 분류 모호 / NFR 미확신 / YAGNI 경계 모호 | spec.md §N 메모 |
| **분석** | `analyzing-ko` | impact 5 항목 작성 중 외부 영향 범위 모호 / 회귀 위험 미확신 | impact-analysis.md §N 메모 |
| **설계** | `planning-ko` | (이미 강제) bite-sized task 분해 중 의존 관계 모호 | **plan.md §8 Advisor 협의 기록** (의무) |
| **개발** | `implementing-ko` | 서브에이전트 dispatch 전 task 의도 모호 / DAG 분기 결정 | dispatch-log.md 섹션 |
| **검증** | `verifying-evidence-ko` | structural-only 검증의 circular 위험 감지 시 | evidence.md §advisor 외부 검증 |
| **§auto 무인** | `clarifying-ko` · `planning-ko` · `verifying-evidence-ko` | best-guess 자동응답·cap 자동통과 시 고영향 가정 보조 자문 (결정 대행 아님 — 보조 입력) | 가정 근거·dispatch-log·escalations + **ASSUMED 유지(사용자 최종 확인)** |

**specops-ko 연결:** planning-ko §8 패턴을 다른 단계로 일반화

---

## 원칙 3 — 호출 형식 (How)

**파라미터 없음.** `advisor()` 호출 시 본 세션의 전체 conversation 이 자동 전송된다 — task 설명, 모든 tool call 과 result, 사고 과정 모두 포함.

```
advisor()
```

추가 prompt 작성 불필요. advisor 가 직접 보고 판단한다.

**호출 후 처리:**
- advisor 권고를 진지하게 수용. 단순 self-test 통과는 advisor 권고 반박 근거 아님
- empirical 증거 (파일 내용 / 테스트 결과 / 1 차 출처) 가 advisor 와 충돌하면 한 번 더 advisor 호출 (reconcile call) — 단순 swap 금지
- advisor 의 specific 주장을 검증할 때만 추가 도구 호출

**specops-ko 연결:** 원칙 4 주권 (사용자 명시 지시 우선) — advisor 도 1 의견, 사용자 결정 최우선

---

## 원칙 4 — 회피 시점 (When NOT)

**호출하지 않을 때:**
- 단순 lookup (정확한 file path 알고 있음, 단순 grep 결과 확인)
- typo fix / 1 줄 rename / 기계적 변환
- 직전 tool result 가 명확히 다음 행동 지시
- 사용자가 explicit 결정 명시 ("X 로 진행해" 같은 직접 지시)
- 동일 task 에서 advisor 1 회 이상 호출 후 새 정보 없음

**호출 빈도:** 긴 작업에서 1 회 이상 (commit 전 + 종결 직전 권장). 짧은 reactive task 는 0~1 회.

**specops-ko 연결:** 원칙 2 문지기 (회색지대 만들지 말 것 — binary 결정)

---

## 기계 검증 — R-5 실호출 증거 게이트 (20260806)

`## N. Advisor 협의 기록` 에 **표를 쓰는 것만으로는 통과하지 않는다.** R-1/R-2 의 실행-근거 게이트와 동형으로, 협의를 **주장**하면 transcript 의 실호출 증거를 요구한다 (`governance-lib.sh:_advisor_exec_evidence`).

| 섹션 상태 | transcript 증거 | R-5 판정 |
|---|---|---|
| `해당 없음` (정직 선언) | 불요 | 통과 — 원칙 5 한계 고백 |
| data row 1+ | `server_tool_use`(name=advisor) ↔ `advisor_tool_result`(비-error) | 통과 |
| data row 1+ | `critic-ask.sh` Bash 실행 + 성공 결과 | 통과 — advisor 미연결 공식 fallback |
| data row 1+ | 없음 | **위반 기록** — 자기발급 면제표 |
| 섹션 부재·빈 섹션 | — | 위반 (기존) |

- advisor 는 서버사이드 도구라 일반 `tool_use`/`tool_result` 가 **아니다** — `server_tool_use`/`advisor_tool_result` 로 기록된다(실측 확인). 일반 tool_use 만 보는 검사로는 영원히 0건이다.
- **fail-open**: transcript 부재·jq 실패·content 블록 0건은 판정 불가로 두고 기존 관대 동작 유지.
- 강도는 `Stop` 훅 **warn**(friction-log 기록) — 커밋·PR 을 막지 않는다. advisor 는 비용·latency 트레이드오프가 있어 hard block 대상이 아니다.
- 함의: **advisor 를 못 부르는 세션이면 표를 쓰지 말고 `해당 없음` + 사유를 쓴다.** 아래 연결 진단 4원인 안내가 그 경로다.

## 5 원칙 매핑 요약

| advisor 원칙 | specops-ko 5 원칙 |
|---|---|
| 1 호출 시점 (When) | 원칙 5 한계 고백 (불확실 시 명시) |
| 2 단계별 시점 (Where) | 원칙 1 투명성 (단계마다 외부 검증 흔적) |
| 3 호출 형식 (How) | 원칙 4 주권 (advisor 도 1 의견) |
| 4 회피 시점 (When NOT) | 원칙 2 문지기 (binary 결정) |

---

## 5원칙 주입 (specops-ko 고유)

| 원칙 | 본 skill 적용 |
|---|---|
| 1 **투명성** | advisor 호출 결과를 plan.md §8 또는 spec.md §협의 기록에 명시 |
| 2 **문지기** | substantive work 전 advisor 미호출 = 원칙 2 위반 |
| 3 **깊이** | advisor 의견과 자체 근거 충돌 시 reconcile call 의무 |
| 4 **주권** | advisor 판단이 사용자 결정과 충돌 시 사용자 개입 요청 |
| 5 **한계 고백** | "advisor 미호출 = 자체검토만" 상태 명시 |

## 연결 진단 — advisor 도구가 안 보일 때 (미연결 fallback 전 필수 1회)

advisor 는 **서버사이드 도구**다 (Anthropic 인프라 실행 — `/advisor <model>` 로 설정, 세션 도구 목록에 `advisor`/`Advising` 으로 노출). 호출 의무 시점인데 도구가 목록에 없으면, "자체검토만" fallback 으로 넘어가기 **전에** 아래 4원인을 진단하고 **사용자에게 재연결 방법을 1줄 안내**한다 (조용한 공회전 금지 — 협의 의무 체계가 도구 부재로 무음 무력화되는 것이 최악):

| # | 원인 | 판별 | 사용자 안내 |
|---|---|---|---|
| 1 | **pairing 무효** — advisor 는 main 과 **동급 이상** 모델이어야 함 (예: main=Fable 5 + advisor=Opus 4.8 → 무효. main 을 상향하면 기존 advisor 설정이 조용히 깨진다) | 세션의 main 모델 ≥ advisor 모델? | 유효 advisor 는 **opus·sonnet·off 뿐**(20260716 실측 — fable 은 advisor 미지원). ∴ **main=Fable 5 면 advisor 는 구조적으로 불가** — `/advisor off` + critic-ask fallback(공식 대체) 또는 main 하향(`/model opus`) 중 사용자 선택 안내 |
| 2 | main 모델 미지원 (Opus 4.6+·Sonnet 4.6+·Haiku 4.5·Fable 5 요건) | main 모델 확인 | main 모델 변경 또는 advisor 포기 |
| 3 | 비-Anthropic API (Bedrock·Vertex·게이트웨이 — server tool 미지원) | 실행 플랫폼 확인 | 플랫폼 제약 고지 (해법 없음) |
| 4 | `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` 환경변수 | env 확인 | 변수 해제 안내 |

- 진단 결과와 무관하게 해당 단계 진행은 fallback(아래 critic-ask 또는 자체검토 + 원칙 5 "자체검토만" 명시)으로 계속한다 — 진단은 **차단이 아니라 안내**다.
- 안내는 세션당 1회면 충분 (매 호출 시점마다 반복 금지 — 노이즈).

## 외부 모델 위탁 경로 (multimodel-critic)

advisor disabled 환경 또는 동종 모델 편향 차단이 필요할 때, **파일 기반 산출물 검증** 은 외부 모델로 위탁 가능:

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/critic-ask.sh "${CLAUDE_PLUGIN_ROOT}"/templates/critic-prompt-plan.md --files .specops/<FID>/plan.md
```

- 한계: 외부 CLI 는 본 세션의 conversation 에 접근 불가 — `advisor()` (세션 전체 자동 전송) 의 **대체가 아니라 산출물 검증 보강**. 세션 맥락 의존 자문은 critic-ask 부적합(파일 기반만).
- CLI (codex/gemini/ollama) 부재·실패 시 `CRITIC: SKIP/FAIL` — graceful (chain 비차단, 자기추론 fallback)
- **자동 fallback 트리거**: advisor() 호출이 미연결/실패(graceful)이고 검증 대상이 산출물(`.specops/<FID>/*.md`)이면, 해당 단계는 critic-ask.sh 를 보조 검증 경로로 **자동 시도**한다(수동 선택 불요). 의견은 advisory — Claude 가 비판적 평가, 판정 권한 없음.
- 연결 지점: planning-ko (plan.md) · clarifying-ko (clarifications.md) · verifying-evidence-ko (evidence.md) · analyzing-ko (impact-analysis.md) · requesting-code-review-ko (diff) — 모두 advisory (판정 권한 없음)

## 참조

- `skills/karpathy-ko/SKILL.md` — 동일한 cross-cutting skill 패턴
- `skills/planning-ko/SKILL.md` — `## 8. Advisor 협의 기록` 섹션 (이미 강제)
- `skills/using-specops-ko/SKILL.md` — 메타 skill cross-cutting 주입 위치

---

*v1.47.1 · 2026-07-16 · specops-ko 독자 추가 (advisor 활용 패턴 + critic-ask fallback + 연결 진단 4원인)*
