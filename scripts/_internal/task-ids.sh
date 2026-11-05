#!/usr/bin/env bash
# library-only
# tasks.md 의 task id 목록 — review-skip-pass.sh · batch-state.sh 가 같은 추출을 쓴다 (20261105-detector-false-positives).
# 인라인 주석(`id: T5   # 설명`)·따옴표·후행 공백을 걷어 첫 토큰만 낸다.
# 값이 있었는데 걷고 나니 빈 것(`""`·`# 주석뿐`)은 표식으로 낸다 — 빈 줄로 내면 호출부의 빈 줄 건너뛰기가 규격 위반을 통과시킨다.
# 값이 처음부터 없는 `- id:` 는 종전처럼 빈 줄이다.
tasks_md_ids() { # <tasks.md> → id 를 한 줄에 하나씩
  grep -E '^[[:space:]]*-[[:space:]]*id:[[:space:]]*' "$1" 2>/dev/null \
    | sed -E 's/^[[:space:]]*-[[:space:]]*id:[[:space:]]*//; /^$/!{ s/^["'"'"']//; s/[[:space:]#"'"'"'].*$//; s/^$/<빈-id>/; }'
}
