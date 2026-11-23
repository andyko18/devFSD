// devFSD 계기판의 도움말 본문 — 명령어 사용법. 명령마다 "입력 · 예 · 그러면" 세 줄로, 쉬운 말로 쓴다.
//   줄은 옆 패널 폭(약 60칸 — 한글은 2칸)에 맞춰 짧게 끊는다. 예시는 그대로 입력할 수 있는 꼴로 적는다.
export type HelpSection = { title: string; lines: readonly string[] }

export const HELP_SECTIONS: readonly HelpSection[] = [
  {
    title: '/start — 새 기능 만들기',
    lines: [
      '입력     /start "만들 것"',
      '예       /start "CSV 줄 수 세는 프로그램 만들어줘"',
      '그러면   질문 → 승인 → 만들기 → 확인까지 알아서 진행한다',
    ],
  },
  {
    title: '/maintain — 있는 코드 고치기',
    lines: [
      '입력     /maintain "고칠 것"',
      '예       /maintain "로그인이 안 되는 문제 고쳐줘"',
      '그러면   지금 동작을 먼저 확인한 뒤 고친다',
    ],
  },
  {
    title: '/quick-fix — 조금만 고치기',
    lines: [
      '입력     /quick-fix "고칠 것"',
      '예       /quick-fix "버튼 글자를 저장으로 바꿔줘"',
      '그러면   문서 없이 바로 고치고 테스트한다 (몇 줄짜리만)',
    ],
  },
  {
    title: '/status — 어디까지 했는지 보기',
    lines: ['입력     /status', '그러면   끝난 것 · 하는 중인 것 · 남은 것을 보여 준다'],
  },
  {
    title: '/init-project — 새 프로젝트 준비 (처음 한 번)',
    lines: ['입력     /init-project 프로젝트이름', '예       /init-project 재고관리', '그러면   프로젝트에 필요한 기본 문서를 만든다'],
  },
  {
    title: '/start-foundation — 공통 부분 먼저 만들기 (선택)',
    lines: ['입력     /start-foundation "공통으로 쓸 것"', '예       /start-foundation "로그인 · 화면 틀"', '그러면   여러 기능이 같이 쓰는 부분을 먼저 만든다'],
  },
  {
    title: '/start-all — 기능 여러 개 한꺼번에 만들기',
    lines: ['입력     /start-all', '그러면   요구사항 문서에 적힌 기능을 차례로 만든다'],
  },
  {
    title: '화면 명령',
    lines: ['/devfsd-gauge       계기판 켜기 · 끄기', '/devfsd             관제판 열기'],
  },
  {
    title: '자주 묻는 것',
    lines: [
      '커밋이 막혔다       고장이 아니다. "검증 돌려줘" 한 뒤 다시 한다',
      '뭔가 이상하다       "devfsd doctor 돌려줘" 라고 말한다',
      '끝나면 무엇을 하나  결과(PR)를 읽고 직접 병합한다',
    ],
  },
]
