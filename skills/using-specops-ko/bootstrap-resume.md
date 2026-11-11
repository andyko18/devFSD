# 프로젝트 최초 진입 감지 · 미완 lifecycle 재개 통보

> 메타 skill `using-specops-ko/SKILL.md` 에서 원문 그대로 분리한 보조 문서다(20261112). SessionStart 는 SKILL.md 만 주입한다 — 본문이 가리킬 때 `Read` 한다.

## 프로젝트 최초 진입 감지 (v2.0 신규)

신호 감지 후 maintenance 분류 **전에**, 프로젝트 부트스트랩 상태를 1 회 점검한다 (clarifications.md Q5 결정 — AND 조건 + 부분 부트 감지).

| `.specops/` | `CLAUDE.md` | 안내 | 메시지 |
|---|---|---|---|
| 부재 | 부재 | **전체 안내** | "프로젝트가 초기화되지 않았습니다. `/init-project` 권장 [y/N]" |
| 존재 | 부재 | 부분 안내 | "`CLAUDE.md` 가 없습니다. `/init-project --resume` 권장 [y/N]" |
| 부재 | 존재 | 부분 안내 | "`.specops/` 가 없습니다. `/init-project --resume` 권장 [y/N]" |
| 존재 | 존재 | 안내 X | (정상 specifying-ko 진입) |

**원칙**:
- **강제 X — 1 회 1 줄 안내**. 5원칙 4 (사용자 주권) 준수.
- `y` 응답 시: `/init-project` 호출 → 부트스트랩 완료 → 사용자에게 "이제 `/start \"<기능>\"` 재실행" 안내.
- `N` 또는 무응답 시: 그대로 specifying-ko 진입 (사용자가 부트스트랩 없이 진행 의지).
- `--resume` 은 기존 파일을 보존하고 누락분만 만든다 (`commands/init-project.md`).

## 미완 lifecycle 재개 통보 (v1.26.3 신규)

SessionStart 가 `<session-progress-rehydrate>` 블록을 주입했으면, **데이터만 있고 통보 규칙이 없던** 공백을 메운다 (재접속 사용자가 "어디까지 했나" 헤매는 것 방지). 사용자 입력 처리 전에 1 회 점검:

1. 최신 FID 섹션의 **최상단 활동 줄**(가장 최근 — session-progress 는 prepend 포맷)을 본다.
2. **종결 마커**(`/lifecycle DONE`·`/finishing 완료`·`PR #N 생성`·`DONE (PR`)면 → 완료된 작업. **통보 불필요** (노이즈 회피, 침묵).
3. **종결 마커 아니면**(미완) → 분기:
   - **사용자가 새 신호**(신규/유지보수)를 보냈으면 → **신호 처리 우선** (5원칙 4 주권 — 새 작업 의지 명확). 단 **1 줄 참고** 첨부: "(참고: 진행 중 `<FID>` 미완 — 직전 `<단계>`. 이어서 하려면 알려주세요)".
   - **신호 없는 일반 입력**이면 → **능동 재개 제안**: "진행 중 `<FID>` — 직전 `<단계>`, 다음 `<chain 다음 단계>`. 이어서 진행할까요? [y/n]".
4. **다음 단계 추론**: chain 순서(specify→clarify→plan→decompose→implement→verify→request-review→receive-review→security-review→integration-test→performance-test→PR)에서 최신 완료 단계의 **다음** 단계.

**원칙**:
- **강제 X — 미완일 때만 1 회**. 완료 FID 는 침묵 (5원칙 4 주권).
- **새 신호가 항상 우선** — 재개통보가 새 작업 진입을 막지 않는다 (재개는 신호 없을 때만 능동 제안).
