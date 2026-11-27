// devFSD 계기판 — 내연기관 모드의 계기반(클러스터). 칸 전체 장면 한 장(SVG)이다. 순수 함수뿐이다(상태·엔진 호출 없음).
//   회전계 = 단계(바늘이 지금 단계 · 지나온 호가 찬다 · 사람이 서는 승인·머지는 레드존)
//   연료계 둘 = Claude 5h · 7d 의 남은 한도(E–F) · 경고등 = 승인(빨강 깜빡임) · 재검증(호박) · 실패(빨강).
//   왼쪽은 비워 둔다 — 상태·단계 이름·안내 글자와 버튼을 그 위에 겹쳐 올린다. 그림 안에는 시각을 넣지 않는다.
import type { DialLimit, DialTick } from './gauge-dial'
import { dialHue, dialNow } from './gauge-dial'
import { SCENE_BG } from './gauge-road'

const BOX_W = 360 // 계기반 한 덩이의 설계 폭 — 칸 높이에 맞춰 늘리고 오른쪽에 붙인다
const BOX_H = 150
const CX = 90 // 회전계 가운데
const CY = 82
const R = 46
const FACE_R = 56
const A0 = 150 // 호가 시작하는 각도(왼쪽 아래) — 아래쪽 120도가 열린다
const SWEEP = 240
const FUEL = [252, 320] as const // 연료계 가운데 x
const FUEL_Y = 92
const FUEL_R = 22
const RED = '#C8372A'
const ALERT = '#FF3B30'
const INK = '#EEF2F6'
const MUTED = '#8B96A5'
const TRACK = '#2A333F'
const NEEDLE = '#FF7A45'
const FONT = "-apple-system, 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif"

export type ClusterModel = {
  ticks: readonly DialTick[]
  isAlert: boolean
  isMoving: boolean
  limits: readonly DialLimit[]
}

const rad = (deg: number) => (deg * Math.PI) / 180
const n1 = (v: number) => v.toFixed(1)
const pt = (cx: number, cy: number, r: number, deg: number) => ({ x: cx + r * Math.cos(rad(deg)), y: cy + r * Math.sin(rad(deg)) })
const esc = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

/** `from`° 에서 `to`° 까지 시계 방향 호. */
const arc = (cx: number, cy: number, r: number, from: number, to: number) => {
  const a = pt(cx, cy, r, from)
  const b = pt(cx, cy, r, to)

  return `M${n1(a.x)} ${n1(a.y)} A${r} ${r} 0 ${to - from > 180 ? 1 : 0} 1 ${n1(b.x)} ${n1(b.y)}`
}

const STYLE =
  '<style>' +
  '@keyframes s{0%,100%{transform:rotate(-1.2deg)}50%{transform:rotate(1.2deg)}}.nd{transform-origin:0 0;animation:s 1.4s ease-in-out infinite}' +
  '@keyframes k{0%,100%{opacity:1}50%{opacity:.3}}.blink{animation:k 1.2s ease-in-out infinite}' +
  '@media (prefers-reduced-motion:reduce){.nd,.blink{animation:none}}' +
  '</style>'

/** 회전계의 눈금 — 단계들 + 끝의 머지(사람이 서는 마지막 자리). */
function dialStops(ticks: readonly DialTick[]): DialTick[] {
  return [...ticks, { key: 'merge', label: '머지', state: 'todo' }]
}

type Lamps = { approve: boolean; redo: boolean; fail: boolean }

export function lampsOf(m: ClusterModel): Lamps {
  const now = dialNow(m.ticks)
  const cur = m.ticks[now]

  return {
    approve: m.isAlert && cur?.key === 'approve',
    redo: m.ticks.some(t => t.state === 'warn'),
    fail: m.ticks.some(t => t.state === 'fail'),
  }
}

function lamp(x: number, w: number, label: string, on: boolean, fill: string, ink: string, blink: boolean): string {
  return on
    ? `<g${blink ? ' class="blink"' : ''}><rect x="${x}" y="4" width="${w}" height="13" rx="3" fill="${fill}"/><text x="${x + w / 2}" y="13.5" text-anchor="middle" font-size="8.5" font-weight="600" fill="${ink}">${esc(label)}</text></g>`
    : `<rect x="${x}" y="4" width="${w}" height="13" rx="3" fill="none" stroke="${TRACK}"/><text x="${x + w / 2}" y="13.5" text-anchor="middle" font-size="8.5" fill="#3A4452">${esc(label)}</text>`
}

function tach(m: ClusterModel): string {
  const all = dialStops(m.ticks)
  const last = all.length - 1
  const deg = (i: number) => A0 + (last > 0 ? (SWEEP * i) / last : 0)
  const now = dialNow(m.ticks)
  const hue = dialHue(m.ticks, now, m.isAlert)
  const red = (i: number) => {
    const d = deg(i)
    return `<path d="${arc(CX, CY, R, d - 5, d + 5)}" fill="none" stroke="${RED}" stroke-width="6"/>`
  }
  const zones = all.flatMap((t, i) => (t.key === 'approve' || t.key === 'merge' ? [red(i)] : [])).join('')
  const dots = all
    .map((_, i) => {
      const p = pt(CX, CY, R, deg(i))
      return `<circle cx="${n1(p.x)}" cy="${n1(p.y)}" r="1.6" fill="#5B6675"/>`
    })
    .join('')
  // 이름표는 처음 · 승인 · 머지만 — 다 적으면 겹친다(지금 단계 이름은 가운데 큰 글자).
  const labels = all
    .map((t, i) => {
      if (i !== 0 && t.key !== 'approve' && t.key !== 'merge') return ''
      const p = pt(CX, CY, R + 12, deg(i))
      const c = Math.cos(rad(deg(i)))
      const anchor = c < -0.3 ? 'end' : c > 0.3 ? 'start' : 'middle'
      const isRed = t.key === 'approve' || t.key === 'merge'
      return `<text x="${n1(p.x)}" y="${n1(p.y + 3)}" text-anchor="${anchor}" font-size="8.5" fill="${isRed ? '#E5534B' : MUTED}">${esc(t.label)}</text>`
    })
    .join('')
  const progress = now > 0 ? `<path d="${arc(CX, CY, R, A0, deg(now))}" fill="none" stroke="${hue}" stroke-width="6" stroke-linecap="round"/>` : ''
  const tip = pt(0, 0, R - 8, now >= 0 ? deg(now) : A0)
  const needleColor = m.isAlert ? ALERT : NEEDLE
  const cur = m.ticks[now]

  return (
    `<circle cx="${CX}" cy="${CY}" r="${FACE_R}" fill="#161C24" stroke="#232B35" stroke-width="1"/>` +
    `<path d="${arc(CX, CY, R, A0, A0 + SWEEP)}" fill="none" stroke="${TRACK}" stroke-width="6" stroke-linecap="round"/>` +
    zones +
    progress +
    dots +
    labels +
    `<g transform="translate(${CX},${CY})"><g${m.isMoving ? ' class="nd"' : ''}><path d="M0 0 L${n1(tip.x)} ${n1(tip.y)}" stroke="${needleColor}" stroke-width="2.5" stroke-linecap="round"/></g></g>` +
    `<circle cx="${CX}" cy="${CY}" r="6" fill="${INK}"/><circle cx="${CX}" cy="${CY}" r="2.5" fill="${needleColor}"/>` +
    (cur
      ? `<text x="${CX}" y="${CY + 24}" text-anchor="middle" font-size="14" font-weight="600" fill="${m.isAlert ? '#FF8A7E' : INK}">${esc(cur.label)}</text>` +
        `<text x="${CX}" y="${CY + 35}" text-anchor="middle" font-size="8.5" fill="${MUTED}">${now + 1} / ${m.ticks.length}</text>`
      : `<text x="${CX}" y="${CY + 26}" text-anchor="middle" font-size="12" fill="${MUTED}">대기</text>`)
  )
}

/** 연료계 — 남은 한도(100 − 쓴 %). E 가 바닥, F 가 가득. 거의 바닥(20% 미만)이면 바늘·호가 빨강. */
function fuel(cx: number, l: DialLimit | undefined, name: string): string {
  const track = `<path d="${arc(cx, FUEL_Y, FUEL_R, 180, 360)}" fill="none" stroke="${TRACK}" stroke-width="5" stroke-linecap="round"/>`
  const ends = `<text x="${cx - FUEL_R - 2}" y="${FUEL_Y + 10}" text-anchor="middle" font-size="8.5" fill="${MUTED}">E</text><text x="${cx + FUEL_R + 2}" y="${FUEL_Y + 10}" text-anchor="middle" font-size="8.5" fill="${MUTED}">F</text>`
  if (!l) return track + ends + `<text x="${cx}" y="${FUEL_Y + 20}" text-anchor="middle" font-size="8.5" fill="${MUTED}">${name} —</text>`
  const left = Math.max(0, Math.min(100, 100 - Math.round(l.pct)))
  const isLow = left < 20
  const d = 180 + (180 * left) / 100
  const tip = pt(cx, FUEL_Y, FUEL_R - 4, d)
  const color = isLow ? ALERT : '#C7D0DA'

  return (
    track +
    (left > 0 ? `<path d="${arc(cx, FUEL_Y, FUEL_R, 180, d)}" fill="none" stroke="${color}" stroke-width="5" stroke-linecap="round"/>` : '') +
    `<path d="M${cx} ${FUEL_Y} L${n1(tip.x)} ${n1(tip.y)}" stroke="${isLow ? ALERT : NEEDLE}" stroke-width="2" stroke-linecap="round"/><circle cx="${cx}" cy="${FUEL_Y}" r="2.5" fill="${INK}"/>` +
    ends +
    `<text x="${cx}" y="${FUEL_Y + 20}" text-anchor="middle" font-size="8.5" fill="${isLow ? '#FF8A7E' : MUTED}">${name} 남음 ${left}%</text>`
  )
}

function clusterBody(m: ClusterModel): string {
  const lamps = lampsOf(m)
  const lx = CX - 45

  return (
    tach(m) +
    lamp(lx, 22, '승인', lamps.approve, '#E5534B', '#FFFFFF', true) +
    lamp(lx + 26, 30, '재검증', lamps.redo, '#E0A030', '#1A1206', false) +
    lamp(lx + 60, 22, '실패', lamps.fail, '#E5534B', '#FFFFFF', false) +
    fuel(FUEL[0], m.limits[0], '5h') +
    fuel(FUEL[1], m.limits[1], '7d')
  )
}

/** 칸 전체 장면 — 배경은 칸 끝까지, 계기반은 오른쪽에 붙인다. */
export function clusterBand(m: ClusterModel, w: number, h: number): string {
  const s = h / BOX_H
  const dx = Math.round(Math.max(w * 0.4, w - BOX_W * s - 8))

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" font-family="${FONT}">` +
    STYLE +
    `<rect width="${w}" height="${h}" fill="${SCENE_BG}"/>` +
    `<g transform="translate(${dx},0) scale(${s.toFixed(4)})">${clusterBody(m)}</g>` +
    '</svg>'
  )
}

/** 그림을 못 보는 독자를 위한 설명. */
export function clusterAlt(m: ClusterModel): string {
  const now = dialNow(m.ticks)
  const cur = m.ticks[now]
  const lamps = lampsOf(m)
  const on = [lamps.approve ? '승인' : '', lamps.redo ? '재검증' : '', lamps.fail ? '실패' : ''].filter(Boolean)
  const head = cur ? `계기반 — 회전계 ${m.ticks.length}단계 중 ${now + 1}번째 ${cur.label}` : '계기반 — 대기'
  const fuels = m.limits.slice(0, 2).map(l => `${l.name} 남은 한도 ${Math.max(0, 100 - Math.round(l.pct))}퍼센트`)

  return [head, ...(on.length > 0 ? [`경고등 ${on.join(' · ')}`] : []), ...fuels].join(', ')
}
