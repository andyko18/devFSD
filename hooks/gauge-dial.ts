// devFSD 계기판의 둥근 계기 — 계기 셋(명령의 단계 · Claude 5h · Claude 7d)을 SVG 한 장으로 그린다. 순수 함수뿐이다(상태·엔진 호출 없음).
//   앱은 이 문자열을 그림으로 그린다(터미널에는 그림 요소가 없어 gauge.tsx 가 글자 계기판을 그린다).
//   색은 속성에 양쪽 테마에서 읽히는 중간 톤을 두고, 진한 글자만 <style> 로 테마를 따르게 한다 — 스타일이 걸러져도 읽힌다.

const A0 = 150 // 호가 시작하는 각도(왼쪽 아래)
const SWEEP = 240 // 호가 도는 각도 — 아래쪽 120도가 열린다
const STAGE_R = 40
const LIMIT_R = 30
const STROKE = 6
const STAGE_CX = 96
const STAGE_CY = 56
const LIMIT_CY = 44
const LIMIT_FIRST_CX = 208
const LIMIT_STEP = 84
const LABELS_ALL_MAX = 8 // 단계가 이보다 많으면 이름표는 지금 단계와 양 끝만 — 호 둘레에 다 못 적는다
const HOT_PCT = 80
export const DIAL_H = 96
export const DIAL_SCALE = 1.3

const MUTED = '#8A94A0' // 양쪽 테마에서 읽히는 중간 톤 — 스타일이 걸러졌을 때의 바닥값
const WARN = '#E0A030'
const ALERT = '#E5534B'
// 단계 묶음의 색 — 정하는 단계는 파랑, 만드는 단계는 청록, 확인하는 단계는 초록. 한 번에 한 색만 쓴다.
const PHASE_COLORS = ['#4F95F0', '#2FB7A3', '#4CC38A'] as const
const PHASE_OF: Record<string, number> = {
  analyze: 0,
  specify: 0,
  clarify: 0,
  approve: 0,
  plan: 0,
  tasks: 0,
  implement: 1,
  review: 1,
  verify: 2,
  gate: 2,
  pr: 2,
}

export type DialTickState = 'done' | 'now' | 'todo' | 'skip' | 'fail' | 'warn'
/** 눈금 하나 — `key` 는 단계 묶음을 아는 이름일 때만 준다(없으면 자리 비율로 색을 정한다). */
export type DialTick = { label: string; state: DialTickState; key?: string }
export type DialLimit = { name: string; pct: number; reset: string }
export type DialModel = {
  /** 계기 아래 이름 — 도는 명령(앞의 `/` 없이) 또는 `대기`. */
  command: string
  ticks: readonly DialTick[]
  /** 내 차례·실패 — 바늘과 지나온 호를 빨강으로. */
  isAlert: boolean
  limits: readonly DialLimit[]
}

const rad = (deg: number) => (deg * Math.PI) / 180
const at = (cx: number, cy: number, r: number, deg: number) => ({ x: cx + r * Math.cos(rad(deg)), y: cy + r * Math.sin(rad(deg)) })
const n1 = (v: number) => v.toFixed(1)
const esc = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

const arc = (cx: number, cy: number, r: number, frac: number) => {
  const a = at(cx, cy, r, A0)
  const b = at(cx, cy, r, A0 + SWEEP * frac)

  return `M${n1(a.x)} ${n1(a.y)} A${r} ${r} 0 ${SWEEP * frac > 180 ? 1 : 0} 1 ${n1(b.x)} ${n1(b.y)}`
}

const track = (cx: number, cy: number, r: number) =>
  `<path d="${arc(cx, cy, r, 1)}" fill="none" stroke="${MUTED}" stroke-opacity=".25" stroke-width="${STROKE}" stroke-linecap="round"/>`

/** 바늘이 가리킬 눈금 — 지금·실패 단계, 없으면 다 끝났을 때 마지막, 아니면 -1(바늘은 처음 자리). */
export function dialNow(ticks: readonly DialTick[]): number {
  const live = ticks.findIndex(t => t.state === 'now' || t.state === 'fail')
  if (live >= 0) return live

  return ticks.length > 0 && ticks.every(t => t.state === 'done' || t.state === 'skip' || t.state === 'warn') ? ticks.length - 1 : -1
}

/** 단계의 색 — 내 차례·실패는 빨강, 아니면 그 단계가 속한 묶음의 색(모르는 단계는 자리 비율로 셋에 나눈다). */
export function dialHue(ticks: readonly DialTick[], now: number, isAlert: boolean): string {
  const tick = ticks[now]
  if (!tick) return MUTED
  if (isAlert || tick.state === 'fail') return ALERT
  const known = tick.key === undefined ? undefined : PHASE_OF[tick.key]
  const phase = known ?? Math.min(PHASE_COLORS.length - 1, Math.floor((now * PHASE_COLORS.length) / Math.max(1, ticks.length)))

  return PHASE_COLORS[phase] ?? PHASE_COLORS[0]
}

function stageDial(m: DialModel): string {
  const now = dialNow(m.ticks)
  const hue = dialHue(m.ticks, now, m.isAlert)
  const last = m.ticks.length - 1
  const frac = now > 0 && last > 0 ? now / last : 0
  const tip = at(STAGE_CX, STAGE_CY, STAGE_R - 12, A0 + SWEEP * frac)
  const isCrowded = m.ticks.length > LABELS_ALL_MAX
  const marks = m.ticks
    .map((t, i) => {
      const deg = A0 + (last > 0 ? (SWEEP * i) / last : 0)
      const p = at(STAGE_CX, STAGE_CY, STAGE_R, deg)
      const q = at(STAGE_CX, STAGE_CY, STAGE_R + 11, deg)
      const c = Math.cos(rad(deg))
      const anchor = c < -0.25 ? 'end' : c > 0.25 ? 'start' : 'middle'
      const isNow = i === now
      const isDone = now >= 0 && i < now
      const isWarn = !isNow && t.state === 'warn' // 다시 해야 하는 단계 — 지나온 자리에 있어도 호박색으로 남긴다
      const dot = isNow
        ? `<circle cx="${n1(p.x)}" cy="${n1(p.y)}" r="4.5" fill="${hue}"/>`
        : isWarn
          ? `<circle cx="${n1(p.x)}" cy="${n1(p.y)}" r="4" fill="${WARN}"/>`
          : `<circle${isDone ? '' : ' class="hole"'} cx="${n1(p.x)}" cy="${n1(p.y)}" r="2.6" fill="${isDone ? hue : MUTED}"/>`
      const hasLabel = !isCrowded || isNow || isWarn || i === 0 || i === last
      const label = hasLabel
        ? `<text x="${n1(q.x)}" y="${n1(q.y + 3.5)}" text-anchor="${anchor}" font-size="${isNow ? 11 : 10}" font-weight="${isNow ? 600 : 400}" fill="${isNow ? hue : isWarn ? WARN : MUTED}"${isNow || isDone || isWarn ? '' : ' fill-opacity=".8"'}>${esc(t.label)}</text>`
        : ''

      return dot + label
    })
    .join('')

  return (
    track(STAGE_CX, STAGE_CY, STAGE_R) +
    (frac > 0 ? `<path d="${arc(STAGE_CX, STAGE_CY, STAGE_R, frac)}" fill="none" stroke="${hue}" stroke-width="${STROKE}" stroke-linecap="round"/>` : '') +
    marks +
    `<line x1="${STAGE_CX}" y1="${STAGE_CY}" x2="${n1(tip.x)}" y2="${n1(tip.y)}" stroke="${hue}" stroke-width="2.5" stroke-linecap="round"/>` +
    `<circle cx="${STAGE_CX}" cy="${STAGE_CY}" r="4" fill="${hue}"/>` +
    `<text class="ink" x="${STAGE_CX}" y="${STAGE_CY + 28}" text-anchor="middle" font-size="12.5" font-weight="600" fill="${MUTED}">${esc(m.command)}</text>`
  )
}

function limitDial(cx: number, l: DialLimit): string {
  const pct = Math.max(0, Math.min(100, Math.round(l.pct)))
  const isHot = pct >= HOT_PCT
  const hue = isHot ? WARN : MUTED

  return (
    track(cx, LIMIT_CY, LIMIT_R) +
    (pct > 0 ? `<path d="${arc(cx, LIMIT_CY, LIMIT_R, pct / 100)}" fill="none" stroke="${hue}" stroke-width="${STROKE}" stroke-linecap="round"/>` : '') +
    `<text${isHot ? '' : ' class="ink"'} x="${cx}" y="${LIMIT_CY + 6}" text-anchor="middle" font-size="17" font-weight="600" fill="${hue}">${pct}<tspan font-size="10" font-weight="400">%</tspan></text>` +
    `<text class="ink" x="${cx}" y="${LIMIT_CY + 27}" text-anchor="middle" font-size="10.5" font-weight="600" fill="${MUTED}">${esc(l.name)}</text>` +
    (l.reset ? `<text x="${cx}" y="${LIMIT_CY + 46}" text-anchor="middle" font-size="10" fill="${MUTED}">${esc(l.reset)}</text>` : '')
  )
}

/** 그림의 가로 — 한도 계기 수(0~2)에 따라 줄어든다. */
export function dialWidth(limits: number): number {
  return limits > 0 ? LIMIT_FIRST_CX + LIMIT_STEP * (limits - 1) + 52 : STAGE_CX * 2
}

/** 계기 셋의 SVG — 왼쪽부터 명령의 단계 · 한도들. */
export function dialSvg(m: DialModel): string {
  const limits = m.limits.slice(0, 2)
  const w = dialWidth(limits.length)

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${DIAL_H}" viewBox="0 0 ${w} ${DIAL_H}" font-family="-apple-system, 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif">` +
    `<style>.ink{fill:#1F2933}.hole{fill-opacity:.45}@media (prefers-color-scheme: dark){.ink{fill:#E6ECF3}}</style>` +
    stageDial(m) +
    limits.map((l, i) => limitDial(LIMIT_FIRST_CX + LIMIT_STEP * i, l)).join('') +
    `</svg>`
  )
}

/** 그림을 못 보는 독자를 위한 설명. */
export function dialAlt(m: DialModel): string {
  const now = dialNow(m.ticks)
  const tick = m.ticks[now]
  const stage = tick ? `${m.command} 단계는 ${m.ticks.length}개 중 ${now + 1}번째 ${tick.label}${tick.state === 'fail' ? ' 실패' : ''}` : `${m.command} — 진행 중인 단계 없음`

  const redo = m.ticks.flatMap((t, i) => (i !== now && t.state === 'warn' ? [`${t.label} 다시 필요`] : []))

  return [stage, ...redo, ...m.limits.slice(0, 2).map(l => `${l.name} 한도 ${Math.round(l.pct)}퍼센트`)].join(', ')
}
