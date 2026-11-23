// devFSD 모드 진입점 — 관제판·계기판의 훅과 자료 수집(진행 기록)을 함께 등록한다.
// 관제판은 관찰만 한다(차단·수정 없음). 커밋·PR 게이트는 셸 훅(hooks/*.sh)이 맡는다.
import type { Register } from 'claude-code'

import { registerConsole } from './console'
import { registerGauge } from './gauge'
import { registerProgress } from './progress-pane'

export const register: Register = (on, options) => {
  registerProgress(on)
  registerConsole(on, options)
  registerGauge(on)
}
