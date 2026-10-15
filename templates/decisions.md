<!-- OWNER_COMMAND: /init-project -->
<!-- layer: Project-Memory -->

# <PROJECT_NAME> 결정 원장

> `/init-project` Phase 11.5 인터뷰·가정 승인과 clarifying RESOLVED 를 **기계적으로 소비**하기 위한 표.
> PRD `## §보강 가정 다이제스트` 와 동기 — 가정/결정은 여기에도 행으로 남긴다 (specifying이 PRD만 읽고 놓치는 단절 해소).

## 결정 표

| DECISION-ID | 주제 | 확정값 | 출처 | 갱신일 | 이유 | 검토한 대안 |
|---|---|---|---|---|---|---|
<!-- decisions-table:start -->
| D-001 | (예시) UI 유무 | 있음 | init Phase11.5 | YYYY-MM-DD | (예시) 사용자가 웹 화면으로 조회 | (예시) CLI 전용 — 비개발자가 못 써서 기각 |
<!-- decisions-table:end -->

> 예시 행은 첫 실결정 기록 시 삭제. ID는 `D-NNN` 단조 증가. 출처 예: `init Phase0` · `init Phase11.5` · `clarify FID` · `foundation`.
> `이유`·`검토한 대안` 은 기록용이다 — 판정(확정/미확정)에는 쓰지 않는다. 근거가 있으면 이유 한 줄과 버린 선택지(짧은 이유)를 적고, 모르면 비운다.

## 소비 규칙 (HARD)

1. clarifying-ko: 본 표에 **확정값이 있는 주제**는 BLOCKING·열린질문·`status: ASSUMED` 우회 재질문 **금지**. 스펙과 충돌할 때만 1회 재확인 후 표 갱신.
2. specifying-ko: 존재 시 §참조에 `"결정 원장 — \`.specops/memory/decisions.md\`"` 인용.
3. `/start-foundation`·`/start-all`: init이 채운 스택·인증·배포 결정을 FR/공통부 clarify에서 다시 묻지 않음.

## 갱신 규약

- init enrich 종료: 승인된 `가정:`·인터뷰 답을 행으로 **전건 동기**(기존 동일 주제 행은 replace).
- clarify RESOLVED: 해당 주제 행 upsert + 출처=`clarify FID`.
- 칸 계약: 판독기(`check-decisions-ledger.sh`·`foundation-kind.sh`)는 칸 **순서**로 읽는다 — 앞 5칸(DECISION-ID·주제·확정값·출처·갱신일)의 순서를 바꾸거나 그 사이에 칸을 끼우지 않는다. 새 칸은 **끝에만** 붙인다.
- 5칸 원장(이 두 칸이 생기기 전에 만든 원장)에 새 결정을 적을 때: 머리·구분선 끝에 `이유`·`검토한 대안` 두 칸을 붙이고 새 행만 7칸으로 쓴다. 기존 행은 그대로 둔다 — 판정 결과는 바뀌지 않는다.

---

*생성: /init-project · Phase 11*
