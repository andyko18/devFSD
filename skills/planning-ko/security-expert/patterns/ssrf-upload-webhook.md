<!-- reference_upstream: addyosmani/agent-skills@aeac41d skills/security-and-hardening (SKILL.md · references/hardening-patterns.md) · references/security-checklist.md · davila7/claude-code-templates@8b65a52 cli-tool/components/agents/api-graphql/api-designer.md (모두 MIT) — specops-ko 한국어 재작성 -->
# 위험 기능 — 서버가 가져오는 URL · 파일 업로드 · 웹훅 수신

plan 이 서버에서 사용자가 준 URL 을 가져오거나, 파일을 받거나, 외부가 보내는 웹훅·콜백을 받을 때 읽는다. 이 세 기능은 "사람 승인이 필요한 변경" 목록에 든다 — plan 에 아래 결정이 적혀 있는지 본다.

## 서버가 가져오는 URL (SSRF)

- 사용자가 영향을 주는 URL(웹훅 등록 URL·URL 에서 가져오기·이미지 프록시·링크 미리보기)을 서버가 가져오면 scheme 과 host 를 허용 목록으로 제한한다 — 아무 URL 이나 가져오는 plan 은 내부 서비스(클라우드 메타데이터 169.254.169.254·localhost·사설망)를 겨누게 해 준다.
- 호스트가 가리키는 DNS 레코드를 **전부** 풀어 하나라도 사설·예약 주소(loopback·link-local·private·unique-local, IPv4·IPv6)면 거부한다. 첫 레코드 하나만 보는 검사는 우회된다.
- 리다이렉트를 따라가지 않는다 — 허용 목록을 통과한 URL 이 내부 주소로 넘겨 보낼 수 있다.
- 검사와 연결 사이에 DNS 가 다시 풀리는 틈(DNS rebinding)이 남는다. 고위험 표면이면 한 번 푼 IP 에 고정해 연결하거나 걸러 주는 프록시를 앞에 둔다.

## 파일 업로드

- 받을 MIME 형식을 허용 목록으로 정하고 크기 상한을 둔다. 확장자는 형식의 증거가 아니다 — 중요한 경로면 파일 앞부분(magic bytes)으로 형식을 확인한다.
- 올라온 파일을 실행·해석될 수 있는 위치(웹 루트·정적 서빙 경로)에 두지 않고, 저장 이름은 서버가 만든다(specops-ko 추가 — 원문에 없음).

## 웹훅·콜백 수신

- 들어오는 웹훅·콜백은 서명(HMAC 등)으로 보낸 쪽과 본문 무결성을 검증한다 — 서명 검증이 없는 수신 엔드포인트는 누구나 결제 완료·상태 변경을 꾸며 보낼 수 있다.
- 서명 비교는 원본 바이트로, 상수 시간 비교로 하고, 타임스탬프 허용 오차를 둬 재전송을 막는다(specops-ko 추가 — 원문에 없음).
