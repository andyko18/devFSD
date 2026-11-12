# `/start` implementing — end-loaded 리뷰

기본 `review_mode: end-loaded` (tasks.md YAML; 필드 부재 시 동일).

## 현재(기본)

```mermaid
flowchart TD
  D[decomposing] --> W[wave: Phase A only]
  W --> A1[task N: implementer]
  A1 --> R[receipt + commit]
  R --> W
  W -->|all A done| B[spec-reviewer FID x1]
  B --> C[code-reviewer FID x1]
  C --> V[verifying-evidence]
  V --> S[requesting: review-skip if B+C reports]
  S --> Sec[security → integration → perf → PR]
```

- B/C는 **1회씩**이지만 감사 파일은 **tid마다** `reviews/<tid>-B-report.md` / `-C-report.md`.
- 최초 B·C 는 **동시 dispatch** — C 는 `PENDING(병렬` 로 쓰고 부모가 B 판정 뒤 dispatch-log 에 `BC-PAR-CHECK:<tid>` 행을 남긴다(없으면 `check-review-audit.sh` FAIL). 지적은 수정 라운드 1회로 고치고 재리뷰 없이 verify 로 간다 · per-task 는 직렬.
- requesting 추가 리뷰는 end-loaded C와 중복 → `review-skip.md` (`end-loaded: …`).
- **`/start-all` Phase 3**: FR마다 위 end-loaded implementing → verify → request/receive(또는 end-loaded skip). batch 단위 B/C 1회는 **쓰지 않음**.

## 레거시 (`review_mode: per-task`)

```mermaid
flowchart TD
  D[decomposing] --> W[wave]
  W --> A[implementer]
  A --> B[spec-reviewer per task]
  B --> C[code-reviewer per task]
  C --> R[receipt + commit]
  R --> W
  W -->|done| F[최종 C if N≥2]
  F --> V[verify → request → …]
```

## 비용

| 모드 | 리뷰 dispatch |
|---|---|
| end-loaded (`/start` · `/start-all` FR) | B×1 + C×1 (+ requesting skip) |
| per-task | (B+C)×N (+ 최종 C if N≥2) |

## `/start-all` Phase 1–2 plan-reviewer defer

Phase 1 FR마다 ★플랜 검사관을 돌리지 않는다:

```text
FR: 스펙 → 플랜 → (★ DEFER) → 쪼개기 → PLAN_DONE
…
Phase 2: ★ plan-reviewer ×1 → batch-plan-digest.sh → [y/n] → Phase 2.5
```

- planning-ko: `**§batch**`이면 `DEFERRED → Phase 2 batch`
- `/start`·foundation(비-batch): FID마다 plan-reviewer **유지**
