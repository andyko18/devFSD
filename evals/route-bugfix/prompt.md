---
description: 유지보수 요청이 갈래 판정(basic-path.sh route maintain)을 거쳐 라이프사이클에 들어가는가
tags: [routing]
max_turns: 12
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

로그인 후 토큰 갱신이 실패하는 버그를 고쳐줘. src/auth.ts 의 refreshToken 이 401 을 받으면 재시도 없이 종료돼.
