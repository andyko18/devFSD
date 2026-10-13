<!-- specops-ko v0.4a W2 — AC injection contract 표준 포맷 -->
<!-- 위치: .specops/<FID>/dispatch/<task-id>-context.md -->
<!-- 작성: implementing-ko 컨트롤러가 leaf subagent dispatch 직전 -->
<!-- 검증: scripts/dag/validate-context.sh (5 컨텍스트 키 존재 + whitelist 형식) -->
<!-- 참조: 마스터 plan §6 v0.4a W2 + advisor 협의 2026-04-26 13:00 -->

# Dispatch Context: <task-id> (FID <FID>)

> leaf subagent 가 받는 5 컨텍스트의 표준 포맷. 부모(implementing-ko)가 dispatch 직전 작성.
> leaf 가 5개 중 누락 또는 모호하다고 판단하면 `NEEDS_CONTEXT: <누락 항목>` 반환 — 추측 금지.
> 본 파일은 file-based-communication-ko 원칙 따라 leaf 에 **경로만** 전달, 본문은 leaf 가 직접 읽음.

## 1. 담당 AC

> 본 task가 충족해야 할 AC ID 목록 + Given/When/Then 요약 (acceptance-criteria.md 인용).

- AC-N: <Given/When/Then 요약 한 줄>
- AC-N: <...>

## 2. 관련 spec.md 섹션

> spec.md 의 해당 task와 직결된 섹션 경로 + 라인 범위.

- `.specops/<FID>/spec.md` §<N> <섹션 제목> (line <start>-<end>)
- `.specops/<FID>/acceptance-criteria.md` AC-N, AC-N

## 3. 테스트 명령

> 본 task의 RED-GREEN-REFACTOR 검증 명령. exit 0이 PASS.

```bash
bash scripts/tests/test-<feature>.sh
```

기대 출력: `PASS=N FAIL=0`

## 4. 수정 허용 파일 (whitelist)

> leaf 가 Edit·Write 호출 가능한 파일 경로 목록. 이 외 파일 수정 시도 → leaf NEEDS_CONTEXT 반환.

- `src/<feature>.sh`
- `scripts/tests/test-<feature>.sh`

> ⚠️ **위 외 파일 수정 금지**. spec/AC/plan/tasks 같은 sprint contract은 read-only.

## 5. 작업 디렉터리

> leaf 가 작업할 worktree 경로. 부모가 `git worktree add` 로 생성.

- `<repo-root>/.worktrees/<FID>-<task-id>/`

> ⚠️ leaf는 **이 디렉터리 안에서만 작업**. 부모 main worktree 직접 수정 금지.

## 6. 설계 계약 (design-first — 선택, 존재 시만 emit)

> 인터페이스/스키마/화면을 건드리는 task 에만 emit-context.sh 가 자동 포함(`api-spec.md`·`data-model.md`·`screens/` 존재 시). 부재 시 본 섹션 생략(graceful). leaf 는 이 계약을 **준수**하고, 어긋나야 하면 사용자 확인.

- `.specops/memory/api-spec.md` (인터페이스 계약 — 있을 때)
- `.specops/memory/data-model.md` (스키마 계약 — 있을 때)
- `screens/` (화면 계약 — 있을 때)
- `.specops/memory/foundation-manifest.md` (공통부 모듈 — manifest 가 있고 §유형≠foundation 일 때. 이 task 의 `재사용 foundation`·`미재사용 근거` 선언이 함께 실린다)

## 7. 실행 모드 (emit-context.sh 자동 산출)

> `emit-context.sh` 가 spec.md 의 줄 선두 라벨로 판정해 쓴다: `**§batch**:` → batch · `**§auto**: true` → auto · 그 외 single.

- 모드: <single|auto|batch>

> leaf 는 사용자와 직접 대화할 수 없다(부모 중개). auto·batch 는 부모도 되묻지 못한다 — 질문은 **시작 시 NEEDS_CONTEXT 한 번에**, 일부가 막혀도 **의존 없는 나머지는 끝까지**, 비가역 삭제·범위 변경은 먼저 NEEDS_APPROVAL. 정본: `agents/implementer-ko.md` 「실행 모드 계약」.

## 8. 구조 규칙 (헌법 — 선택, 규칙이 있을 때만 emit)

> `emit-context.sh` 가 헌법(`.specops/memory/constitution.md`)의 「구조 규칙」 표를 `check-constitution-rules.sh --list` 로 읽어 싣는다. 규칙이 없으면(헌법 없음 · 절 없음 · 규칙 0건) 본 섹션 생략. leaf 는 이 규칙을 **따르고**, 지키면 태스크를 끝낼 수 없으면 어기지 말고 규칙 ID 와 사유를 보고한다. 코드 리뷰어는 판정이 `리뷰`인 규칙을 변경과 대조한다.

- **S-1** 규칙 문장 — 적용: 경로 · 판정: 리뷰
- **S-2** 규칙 문장 — 적용: 경로 · 판정: 명령 — 판정 명령

> 표가 형식 위반·판정 불가면 규칙 대신 "구조 규칙을 싣지 못했다"와 사유가 실린다(dispatch 는 막지 않는다) — 그때는 헌법의 표를 직접 읽는다.

---

## leaf 의무 (5원칙 주입)

| 원칙 | leaf 적용 |
|---|---|
| 1 투명성 | 5 컨텍스트 누락 시 즉시 NEEDS_CONTEXT 반환, 추측 금지 |
| 2 문지기 | whitelist 외 파일 수정 시도 시 즉시 중단 + NEEDS_CONTEXT |
| 3 깊이 | 테스트 명령 실제 실행 후에만 PASS 주장. RED 실측 출력(요약행+FAIL 라인 ≤10줄) 원문 캡처·보고 |
| 4 주권 | git commit 권한 박탈 — 부모만 commit (R8 보강) |
| 5 한계 고백 | 자체검토 보고를 최종 결과로 주장 금지, 부모 검증 의무 |

## NEEDS_CONTEXT 반환 트리거

leaf 가 다음 상황에 즉시 `NEEDS_CONTEXT` 반환:

1. 5 컨텍스트 중 1개 이상 누락 또는 빈 값
2. 담당 AC ID 가 acceptance-criteria.md 에서 발견 안 됨
3. spec.md 섹션 경로가 존재하지 않거나 빈 라인 범위
4. 테스트 명령 실행이 명령 자체 실패 (test 파일 없음 등)
5. whitelist 외 파일을 수정해야 본 task 완수 가능 — 부모에 컨텍스트 보강 요청
6. worktree 경로가 존재 안 함 또는 git worktree 가 아님

반환 형식 (assistant text):
```
NEEDS_CONTEXT: <누락 항목 1줄>
근거: <추가 설명>
요청: <부모가 보강해야 할 정확한 정보>
```

부모 처리 (implementing-ko:107 분기): 컨텍스트 보강 후 재dispatch. 추측으로 leaf가 진행 금지.
