<!-- OWNER_COMMAND: 모든 커맨드가 append -->
<!-- SCOPE: 프로젝트 전역 (.specops/ 루트) -->
<!-- reference_upstream: revfactory/harness session-progress -->
<!-- layer: Harness-Foundation-Artifact -->

# Session Progress — <project-name>

> 이 파일은 세션 재시작 후 맥락 복원의 **유일한 경로**입니다. 모든 Lifecycle 커맨드가 종료 시 한 줄 append 합니다. 대화가 끊겨도 이 파일만 읽으면 "어디까지 했는지"가 복원됩니다.

**포맷**: `<YYYY-MM-DD HH:MM> <command> <상태> (<산출·메모>)`

**유지 규칙**:
- FID별 섹션 구분
- 한 커맨드 실행 = 한 줄
- "무엇·결과·다음 단계"만 — 대화 전문 저장 금지
- 최신 블록이 위에

(아직 기록 없음 — 첫 lifecycle 커맨드 실행 시 FID 섹션이 아래 구분선 밑에 추가됨)

<!-- 작성 예시 (포맷 참고 — 각 줄 들여쓰기: rehydrate 의 ^## 매칭 차단):

  ## 20260420-rss-cache · RSS 캐시
  - 2026-04-20 12:00 /analyze BLOCK (analysis.md — AC-3 미매핑, /plan 재실행 필요)
  - 2026-04-20 11:10 /plan 완료 (plan.md)
  - 2026-04-20 10:30 /clarify 완료 (clarifications.md — 3 쟁점 해소)
  - 2026-04-20 10:00 /specify 완료 (spec.md, acceptance-criteria.md)

  안내문·본 예시는 첫 구분선(---) 위에 있어야 한다 — append.sh 가 첫 --- 직후에
  신규 FID 섹션을 꽂으므로, 아래 놓이면 섹션 본문으로 딸려 들어가 rehydrate 오염.
-->

---

## 활용 방법

### 새 세션 시작 시
1. 이 파일 최상단 5~10줄 읽기
2. 현재 FID 식별
3. 직전 커맨드와 상태 파악
4. 필요한 `.specops/<FID>/*.md` 파일 직접 읽기
5. 다음 커맨드 실행

### 커맨드 종료 시
1. Process 마지막 스텝에서 이 파일 상단에 한 줄 prepend
2. 형식: `<YYYY-MM-DD HH:MM> <command> <상태> (<산출·메모>)`

### BLOCK 판정 후
- 차단 커맨드와 사유를 기록
- 재호출할 Generator 이름 메모
- 예: `2026-04-20 12:00 /analyze BLOCK (analysis.md — AC-3 미매핑, /plan 재실행 필요)`

## 참조

- `docs/harness-principles.md` 「컨텍스트 리셋」 — 본 파일의 운용 규약
- `docs/harness-principles.md` 「아티팩트 구조 규약」 — FID 규약

---

*최초 생성: /implement 또는 첫 커맨드 · 갱신: 모든 Lifecycle 커맨드*
