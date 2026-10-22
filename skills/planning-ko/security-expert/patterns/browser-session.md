<!-- reference_upstream: addyosmani/agent-skills@aeac41d skills/security-and-hardening (SKILL.md · references/hardening-patterns.md) · references/security-checklist.md · wshobson/agents@0874a27 plugins/developer-essentials/skills/auth-implementation-patterns · plugins/backend-api-security/agents/backend-security-coder.md (모두 MIT) — specops-ko 한국어 재작성 -->
# 브라우저 세션 — 쿠키·CORS·CSRF

브라우저 클라이언트가 쿠키·세션으로 로그인하거나 다른 origin 에서 이 API 를 부를 때 읽는다.

- 인증 토큰·세션 ID 는 스크립트가 읽을 수 없는 httpOnly 쿠키에 둔다. localStorage·sessionStorage 에 둔 토큰은 XSS 한 번으로 빠져나간다.
- 세션 쿠키는 httpOnly·Secure(HTTPS 만)·SameSite·만료(maxAge)를 단다. 세션 비밀은 코드가 아니라 환경에서 읽는다.
- 인증이 쿠키로 실리면 CSRF 방어를 정한다 — SameSite(lax·strict)·anti-CSRF 토큰·Origin 헤더 검사 중 무엇을 쓰는지 plan 에 적는다. 상태를 바꾸는 요청을 GET 으로 받으면 SameSite=lax 로는 막히지 않는다(specops-ko 추가 — 원문에 없음).
- CORS 허용 origin 은 설정에서 읽는 명시적 목록이다. `*` 는 credentials 와 함께 쓸 수 없고, 요청의 Origin 을 그대로 되돌려 주는 설정은 `*` 와 같다(specops-ko 추가 — 원문에 없음).
- CORS 허용 origin 을 바꾸는 것은 사람 승인이 필요한 변경이다 — plan 에 바꾸는 이유와 새 목록을 적는다.
