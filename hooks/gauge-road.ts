// devFSD 계기판 — 전기차 모드의 도로 보기. 차 뒤 위에서 앞길을 내려다본 그림 한 장(SVG)이다. 순수 함수뿐이다(상태·엔진 호출 없음).
//   경로 띠 = devFSD 가 갈 길 · 띠 위의 점 = 남은 단계(가까울수록 크다) · 톨게이트 = 사람이 서는 곳(승인 · 머지).
//   그림 안에는 시각처럼 자주 바뀌는 값을 넣지 않는다 — 그림 문자열이 바뀌면 애니메이션이 처음부터 다시 돈다.
//   장면은 어두운 고정 색이다(앱 테마와 무관한 화면 한 장). 움직임은 달리는 중에만, 동작 줄이기 설정이면 멈춘다.
import type { DialTick } from './gauge-dial'
import { dialNow } from './gauge-dial'

export const ROAD_W = 300
export const ROAD_H = 96
export const ROAD_SCALE = 1.3
const VX = 150 // 소실점
const VY = 14
const AHEAD_MAX = 3 // 띠 위에 보이는 남은 단계 수
const AHEAD_Y = [54, 38, 26] as const // 가까운 것부터 — 멀수록 위(소실점 쪽)
const AHEAD_R = [3.6, 2.8, 2.2] as const

const BLUE = '#5EA2FF'
const RED = '#FF5A4E'
const INK = '#EEF2F6'

export type RoadModel = {
  ticks: readonly DialTick[]
  /** 사람 차례 · 실패 — 차가 서고 경로가 빨강. */
  isAlert: boolean
  /** 달리는 중 — 차선 흐름 · 차 흔들림 · 다가오는 점. 아니면 정지 화면. */
  isMoving: boolean
}

const esc = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

const STYLE =
  '<style>' +
  '@keyframes f{to{stroke-dashoffset:-18}}.ln{animation:f .7s linear infinite}' +
  '@keyframes b{0%,100%{transform:translateY(0)}50%{transform:translateY(-1px)}}.bob{animation:b 1.6s ease-in-out infinite}' +
  '@keyframes k{0%,100%{opacity:1}50%{opacity:.3}}.blink{animation:k 1.2s ease-in-out infinite}' +
  // 다가오는 점 — 시작부터 보인다(정지 화면·첫 장면에서도 점이 있어야 한다).
  '@keyframes c{0%,20%{transform:translate(0,0) scale(1);opacity:1}100%{transform:translate(8px,18px) scale(1.6);opacity:0}}' +
  '.near{transform-box:fill-box;transform-origin:center;animation:c 2.8s cubic-bezier(.5,0,.9,.5) infinite}' +
  '@media (prefers-reduced-motion:reduce){.ln,.bob,.blink,.near{animation:none}}' +
  '</style>'

/** 뒤에서 본 차 — (0,0) 이 차 가운데, 폭 약 44. `brake` 면 미등이 밝은 빨강. */
function car(brake: boolean, dim: boolean): string {
  return (
    `<g${dim ? ' opacity=".55"' : ''}>` +
    '<path d="M-22 17 Q-23 6 -16 3 L-11 -3 Q-9 -6 -5 -6 L5 -6 Q9 -6 11 -3 L16 3 Q23 6 22 17 Z" fill="#DCE3EA"/>' +
    '<path d="M-9 -1 L-6 -4 L6 -4 L9 -1 Z" fill="#2A323D"/>' +
    (dim ? '' : `<rect x="-20" y="6" width="40" height="2" rx="1" fill="${brake ? '#FF3B30' : '#E5534B'}"${brake ? '' : ' fill-opacity=".75"'}/>`) +
    '<rect x="-13" y="17" width="6" height="3.5" rx="1" fill="#1A1F26"/><rect x="7" y="17" width="6" height="3.5" rx="1" fill="#1A1F26"/>' +
    '</g>'
  )
}

/** 톨게이트 — 위 간판 · 양쪽 부스와 등 · 내려진 차단봉. `s` 는 크기(1 = 가까이). */
function tollgate(cx: number, top: number, s: number, label: string, blink: boolean): string {
  const half = 52 * s
  const h = 30 * s
  return (
    `<rect x="${cx - half}" y="${top}" width="${half * 2}" height="${7 * s}" rx="1" fill="#2E3743" stroke="#4A5566" stroke-width=".6"/>` +
    `<text x="${cx}" y="${top + 5.3 * s}" text-anchor="middle" font-size="${Math.max(5, 6 * s)}" font-weight="600" fill="#FF8A7E" letter-spacing=".08em">${esc(label)}</text>` +
    `<rect x="${cx - half + 5 * s}" y="${top + 7 * s}" width="${3 * s}" height="${h}" fill="#4A5566"/>` +
    `<rect x="${cx + half - 8 * s}" y="${top + 7 * s}" width="${3 * s}" height="${h}" fill="#4A5566"/>` +
    `<rect x="${cx - half + 9 * s}" y="${top + 19 * s}" width="${11 * s}" height="${18 * s}" rx="1" fill="#2E3743" stroke="#4A5566" stroke-width=".5"/>` +
    `<rect x="${cx + half - 20 * s}" y="${top + 19 * s}" width="${11 * s}" height="${18 * s}" rx="1" fill="#2E3743" stroke="#4A5566" stroke-width=".5"/>` +
    `<circle${blink ? ' class="blink"' : ''} cx="${cx - half + 14.5 * s}" cy="${top + 13 * s}" r="${2 * s}" fill="#FF3B30"/>` +
    `<circle${blink ? ' class="blink"' : ''} cx="${cx + half - 14.5 * s}" cy="${top + 13 * s}" r="${2 * s}" fill="#FF3B30"/>` +
    `<rect x="${cx - half + 20 * s}" y="${top + 34 * s}" width="${(half - 20 * s) * 2}" height="${3 * s}" rx="${1.5 * s}" fill="${INK}"/>` +
    [0.25, 0.5, 0.75]
      .map(f => `<rect x="${cx - half + 20 * s + (half - 20 * s) * 2 * f - 4 * s}" y="${top + 34 * s}" width="${8 * s}" height="${3 * s}" fill="#E5534B"/>`)
      .join('')
  )
}

/** 사람이 서는 단계 — 승인 · 머지. 그 단계에서 멈췄으면 톨게이트로 그린다. */
const isHumanGate = (t: DialTick | undefined) => t?.key === 'approve' || t?.key === 'merge'

function roadBody(m: RoadModel): string {
  const isIdle = m.ticks.length === 0
  const now = dialNow(m.ticks)
  const cur = m.ticks[now]
  const isGateStop = m.isAlert && isHumanGate(cur)
  const tone = m.isAlert ? RED : BLUE
  const head =
    `<path d="M24 ${ROAD_H} L${VX - 5} ${VY} L${VX + 5} ${VY} L${ROAD_W - 24} ${ROAD_H} Z" fill="${isIdle ? '#191F27' : '#1C232C'}"/>` +
    `<path d="M24 ${ROAD_H} L${VX - 5} ${VY} M${ROAD_W - 24} ${ROAD_H} L${VX + 5} ${VY}" stroke="${isIdle ? '#2C3440' : '#3A4452'}" stroke-width="1"/>` +
    `<path${m.isMoving ? ' class="ln"' : ''} d="M${VX} ${ROAD_H} L${VX} ${VY}" stroke="${isIdle ? '#3A4350' : '#5B6675'}" stroke-width="1.4" stroke-dasharray="6 12"/>`
  if (isIdle) return head + `<g transform="translate(${VX},${ROAD_H - 22})">${car(false, true)}</g>`

  // 경로 띠 — 사람 앞에서 멈췄으면 톨게이트 앞에서 끊긴다.
  const stopY = 52
  const ribbon = isGateStop
    ? `<path d="M${VX - 40} ${ROAD_H} L${VX - 26} ${stopY} L${VX + 26} ${stopY} L${VX + 40} ${ROAD_H} Z" fill="${RED}" fill-opacity=".16"/><path d="M${VX} ${ROAD_H} L${VX} ${stopY}" stroke="${RED}" stroke-width="1.8"/>`
    : `<path d="M${VX - 40} ${ROAD_H} L${VX - 2} ${VY + 2} L${VX + 2} ${VY + 2} L${VX + 40} ${ROAD_H} Z" fill="${tone}" fill-opacity=".2"/><path d="M${VX} ${ROAD_H} L${VX} ${VY + 4}" stroke="${tone}" stroke-width="1.8"/>`

  // 길 끝의 머지 톨게이트 — 마지막에 사람이 한 번 더 선다.
  //   눈앞에 톨게이트가 있으면 그 뒤에 가려 그리지 않는다.
  const far = isGateStop ? '' : `<g opacity=".75">${tollgate(VX, VY - 6, 0.22, '머지', false)}</g>`

  const scene = isGateStop
    ? tollgate(VX, 12, 0.82, cur?.label ?? '승인', true)
    : m.ticks
        .slice(now + 1)
        .filter(t => t.key !== 'merge')
        .slice(0, AHEAD_MAX)
        .map((t, i) => {
          const y = AHEAD_Y[i] ?? VY
          const r = AHEAD_R[i] ?? 2
          const pin =
            `<circle cx="${VX}" cy="${y}" r="${r}" fill="${i === 0 ? INK : tone}"${i === 0 ? '' : ` fill-opacity="${i === 1 ? 1 : 0.7}"`}/>` +
            `<text x="${VX + r + 4}" y="${y + 3}" font-size="${i === 0 ? 7.5 : 6.5}" fill="${i === 0 ? INK : '#C7D0DA'}"${i === 2 ? ' fill-opacity=".7"' : ''}>${esc(t.label)}</text>`
          return i === 0 && m.isMoving ? `<g class="near">${pin}</g>` : pin
        })
        .reverse()
        .join('')

  // 사람 차례(답변 대기)·실패는 지금 단계 이름을 차 앞에 빨간 글자로 — 톨게이트가 아닌 멈춤.
  const halt =
    m.isAlert && !isGateStop && cur
      ? `<path d="M${VX - 24} 60 L${VX + 24} 60" stroke="${RED}" stroke-width="2.4" stroke-linecap="round"/><text x="${VX}" y="55" text-anchor="middle" font-size="7.5" font-weight="600" fill="#FF8A7E">${esc(cur.label)}${cur.state === 'fail' ? ' 실패' : ''}</text>`
      : ''

  // 지나왔지만 다시 해야 하는 단계(검증 STALE 등) — 길가에 호박색 표지로 남긴다.
  const redo = m.ticks.filter((t, i) => i !== now && t.state === 'warn').map(t => t.label)
  const back = redo.length > 0 ? `<text x="14" y="${ROAD_H - 8}" font-size="7.5" font-weight="600" fill="#E0A030">↺ ${esc(redo.join(' · '))} 다시</text>` : ''

  const carY = ROAD_H - 24
  const theCar = m.isMoving
    ? `<g transform="translate(${VX},${carY})"><g class="bob">${car(false, false)}</g></g>`
    : `<g transform="translate(${VX},${carY})">${car(m.isAlert, false)}</g>`

  return head + far + ribbon + scene + halt + back + theCar
}

const FONT = "-apple-system, 'Apple SD Gothic Neo', 'Malgun Gothic', sans-serif"
export const SCENE_BG = '#12171E'
const SKY = '#161C24'

/** 작은 그림 한 장(좁은 칸) — 300×96, 둥근 모서리. */
export function roadSvg(m: RoadModel): string {
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${ROAD_W}" height="${ROAD_H}" viewBox="0 0 ${ROAD_W} ${ROAD_H}" font-family="${FONT}">` +
    STYLE +
    `<rect width="${ROAD_W}" height="${ROAD_H}" rx="10" fill="${SCENE_BG}"/>` +
    `<path d="M0 10 Q0 0 10 0 L${ROAD_W - 10} 0 Q${ROAD_W} 0 ${ROAD_W} 10 L${ROAD_W} ${VY} L0 ${VY} Z" fill="${SKY}"/>` +
    roadBody(m) +
    '</svg>'
  )
}

/**
 * 칸 전체 장면(넓은 칸) — 배경과 하늘은 칸 끝까지, 길은 오른쪽(소실점이 폭의 약 2/3)에 둔다.
 * 왼쪽은 비워 둔다: 상태·단계 이름·안내 글자와 버튼을 그 위에 겹쳐 올린다.
 */
export function roadBand(m: RoadModel, w: number, h: number): string {
  const s = h / ROAD_H
  const vx = Math.max(w * 0.66, w - (ROAD_W - VX) * s)
  const dx = Math.round(vx - VX * s)
  const sky = Math.round(VY * s)

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" font-family="${FONT}">` +
    STYLE +
    `<rect width="${w}" height="${h}" fill="${SCENE_BG}"/><rect width="${w}" height="${sky}" fill="${SKY}"/>` +
    `<g transform="translate(${dx},0) scale(${s.toFixed(4)})">${roadBody(m)}</g>` +
    '</svg>'
  )
}

/** 그림을 못 보는 독자를 위한 설명. */
export function roadAlt(m: RoadModel): string {
  if (m.ticks.length === 0) return '도로 보기 — 대기, 출발 전'
  const now = dialNow(m.ticks)
  const cur = m.ticks[now]
  const ahead = m.ticks
    .slice(now + 1)
    .filter(t => t.key !== 'merge')
    .slice(0, AHEAD_MAX)
    .map(t => t.label)
  const where = cur ? `지금 ${cur.label}${cur.state === 'fail' ? ' 실패' : ''}` : '출발 전'
  const stop = m.isAlert ? (isHumanGate(cur) ? `, ${cur?.label ?? '승인'} 톨게이트 앞에서 정지` : ', 멈춤') : ''

  const redo = m.ticks.filter((t, i) => i !== now && t.state === 'warn').map(t => `${t.label} 다시 필요`)

  return [`도로 보기 — ${where}${stop}`, ...(ahead.length > 0 ? [`앞에 ${ahead.join(' · ')}`] : []), ...redo, '길 끝에 머지 톨게이트'].join(', ')
}
