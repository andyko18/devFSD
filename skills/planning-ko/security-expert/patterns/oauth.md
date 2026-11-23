<!-- reference_upstream: specops-ko 독자 추가 -->
# OAuth·OIDC

plan 이 OAuth·OIDC 로그인·토큰 발급·콜백을 만들거나 고칠 때 읽는다. 기준은 OAuth 2.1 이다.

- 브라우저·모바일 같은 공개 클라이언트는 Authorization Code + PKCE(S256 만)를 쓴다. `plain` PKCE 는 쓰지 않는다.
- 서비스 간 호출은 Client Credentials 를 쓴다.
- Implicit 흐름과 Resource Owner Password Credentials(사용자 비밀번호를 클라이언트가 받는 흐름)는 쓰지 않는다 — OAuth 2.1 에서 빠졌다.
- 받은 토큰의 scope 를 검증하고, 엔드포인트마다 필요한 scope 를 적는다.
- 콜백에서 발급한 토큰을 리다이렉트 URL 의 쿼리에 실어 프론트로 넘기지 않는다 — 브라우저 기록·Referer·서버 로그에 남는다. 예시 코드가 이렇게 하더라도 그대로 따르지 않는다.
- 리다이렉트 URI 는 등록된 값과 정확히 일치할 때만 받고, state(또는 PKCE)로 콜백 위조를 막는다.
