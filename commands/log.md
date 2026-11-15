---
name: log
disable-model-invocation: true
description: 자유작업 인사이트 즉석 수동 기록 — gbrain-append 재사용
triggers:
  - "/log"
mode: auto
specops_version: 2.6.0
specops_layer: Lifecycle-Tool
reference_upstream: specops-ko 독자 추가
---

# /log "<요약>"

사용자가 자연어로 처리한 작업을 즉시 learnings 에 기록한다.

실행:
```bash
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/gbrain-append.sh "$(cat <<'SPECOPS_LOG_EOF'
$ARGUMENTS
SPECOPS_LOG_EOF
)" --tags freelog,manual
```
메모는 따옴표 붙은 heredoc 으로 넘긴다 — 큰따옴표에 바로 넣으면 메모 속 백틱·`$( )` 가 명령으로 실행된다.
기록 후 "기록함: <요약>" 1줄 보고.

---

*specops-ko v2.6.0 · 2026-06-25 · /log command*
