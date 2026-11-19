---
name: feedback
disable-model-invocation: true
description: "[운영] 쓰다 겪은 불편을 플러그인 저장소에 알린다 — 초안(본문 + 버전·단계·차단 규칙 번호)을 보여 주고 확인받은 뒤 GitHub 이슈로 올린다. `--summary` 는 사용 요약(숫자만)을 붙인다"
triggers:
  - "/feedback"
mode: ask
specops_version: 5.7.10
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /feedback [--summary] <겪은 일>

## 목적

devFSD 를 쓰다 겪은 불편·막힘·느림을 만든 사람에게 전한다. 기록(`.specops/`)은 각자 컴퓨터에만 남으므로, 말해 주지 않으면 알 수 없다.

- `/feedback <겪은 일>` — 겪은 일 + 지금 상태(플러그인 버전 · 최근 작업의 갈래·마지막 단계 · 최근 차단 규칙 번호)
- `/feedback --summary <겪은 일>` — 위에 **사용 요약**을 더한다(갈래별 작업 수·끝낸 수·소요 중앙값 · 끝내지 못한 작업의 마지막 단계 · 규칙별 차단·경고 횟수 · 검증·리뷰 횟수)
- `/feedback --summary` — 겪은 일 없이 사용 요약만 보인다(올리지 않는다 — 직접 전할 때 쓴다)

**올라가는 곳은 공개 저장소다.** 자동으로 붙는 것은 숫자·규칙 번호·명령 이름·버전뿐이다 — 작업 이름 · 요청 문장 · 파일 경로 · 프로젝트 이름 · 코드 · 차단된 명령 원문은 붙지 않는다. 사용자가 쓴 본문은 그대로 올라간다.

## Process

1. **겪은 일이 없고 `--summary` 만 있으면** 요약만 보이고 끝낸다:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/feedback.sh summary
   ```
   겪은 일도 `--summary` 도 없으면 "무엇이 불편했는지 한두 문장으로 적어 주세요" 1줄을 묻는다.
2. **초안을 만든다** — 겪은 일은 사용자가 쓴 글 그대로 표준 입력으로 넘긴다(고쳐 쓰거나 덧붙이지 않는다 · `--summary` 가 있었으면 붙인다):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/feedback.sh draft --stdin [--summary] <<'SPECOPS_FEEDBACK_EOF'
   <겪은 일>
   SPECOPS_FEEDBACK_EOF
   ```
   따옴표 붙은 heredoc 을 **명령 치환 없이** 쓴다 — 본문 속 백틱·`$( )`·작은따옴표가 명령으로 읽히지 않는다.
3. **초안을 보인다** — `DRAFT:` 줄의 파일을 Read 해 **전문을 그대로** 보이고, 이어서:
   - `REPO:` 줄의 저장소 이름과 **"공개 저장소에 올라갑니다 — 누구나 볼 수 있습니다"** 1줄
   - `WARN:` 줄이 있으면 전부 그대로(경로·주소·메일·비밀 값처럼 보이는 글자) — 사용자가 본문을 고치겠다고 하면 2번부터 다시 한다
   - 초안 파일 경로(`DRAFT:` 줄)
   - "이대로 올릴까요? [y/수정/파일만]"
4. **답에 따라**:
   - `y` → `bash "${CLAUDE_PLUGIN_ROOT}"/scripts/feedback.sh submit <DRAFT 파일>` — `SUBMITTED:` 줄의 이슈 주소를 보인다. 이때 `WARN:` 줄이 나오면 함께 보인다(올리기 직전에 본문을 한 번 더 본 결과다). 올린 초안 파일은 지워진다. 종료 코드 4(`gh` 없음·로그인 안 됨·실패)면 `MANUAL:` 주소와 `MANUAL-FILE:` 경로를 보이고 "주소를 열어 초안 내용을 붙여 넣으면 됩니다" 로 끝낸다.
   - `파일만` → 올리지 않고 초안 파일 경로만 알린다(사내 프로젝트라 공개 이슈를 쓸 수 없을 때 — 파일을 다른 경로로 전한다).
   - `수정` → 고칠 내용을 받아 2번부터 다시 한다.

## 안티패턴

- **확인 없이 올리기** — 초안 전문을 보이고 `y` 를 받기 전에는 `submit` 을 부르지 않는다. 앞선 대화의 승인은 이 초안의 승인이 아니다.
- **본문을 대신 쓰거나 보태기** — 대화에서 본 파일 경로·요청 문장·코드·오류 원문을 본문이나 초안 파일에 넣지 않는다. 본문은 사용자가 쓴 글뿐이다.
- **초안 파일을 손으로 고치기** — 자동으로 붙는 절은 스크립트가 낸 그대로 둔다. 고칠 것은 본문이고, 본문은 2번을 다시 실행해 바꾼다.
- **초안을 커밋하기** — 초안은 `.specops/feedback/` 에 있고 그 폴더는 스스로를 git 에서 뺀다(`.gitignore`). `git add -f` 로 싣지 않는다.
- **`gh issue create` 를 직접 부르기** — 올리는 일은 `feedback.sh submit` 한 곳이 맡는다.

## 참조

- `scripts/feedback.sh` — 요약·상태·초안·제출 (싣지 않는 항목은 그 파일 머리가 유일한 정의다)
- `.github/ISSUE_TEMPLATE/feedback.md` — 이슈 양식

---

*specops-ko v5.7.10 · 2026-11-17 · /feedback command (공개 저장소 — 숫자·규칙 번호·버전만 자동 첨부)*
