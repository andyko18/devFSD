// Ported from Claude Flightdeck (https://github.com/scasella/claude-flightdeck, v0.6.0)
// Copyright (c) 2026 Stephen Casella — MIT License. See NOTICE. Modified for devFSD.
// A connector drawn on the surface's own frame clock: packets travel along it while `active`,
// and it rests as a plain dim line otherwise. Only this region redraws; the pane does not.
import type { ClientModule, RenderChildren } from 'claude-code'

type Props = {
  active: boolean
  width: number
  color: string
  dim: string
  /** Cells where a branch drops (┬); the rest of the line is ─. */
  marks: number[]
  /** Draw ┴ instead of ┬ at the marks: a merge into what is below. */
  isMerge: boolean
  /** devFSD: 'aurora' 는 오로라 띠(분홍→주황→노랑). 기본은 connector. */
  variant?: 'connector' | 'aurora'
  /** devFSD: aurora 의 흐름 속도 — working 빠름, waiting 느림, idle 정지. */
  mode?: 'working' | 'waiting' | 'idle'
}

type Ref = { phase: number; active: boolean }
type State = { ref: Ref }

const STEP_MS = 110
/** Dashes drawn past the line's end and clipped by its box, so the right end is the box's edge. */
const SPARE = 4

/** devFSD: 오로라 그라데이션 — 분홍 → 주황 → 노랑. 장식이라 테마 키가 아닌 고정 hex. */
const AURORA = ['#D4537E', '#D85A30', '#EF9F27'] as const
type AuroraMode = 'working' | 'waiting' | 'idle'
type Cell = { ch: string; isLit: boolean; color?: string; isBold?: boolean }

/** 한 프레임의 칸들. working 은 1칸/프레임, waiting 은 1칸/3프레임, idle 은 정지. 길이는 항상 width. */
export const auroraCells = (phase: number, width: number, mode: AuroraMode): Cell[] => {
  const len = mode === 'working' ? 12 : 8
  const span = width + len
  const step = mode === 'working' ? phase : Math.floor(phase / 3)
  const head = mode === 'idle' ? -span : (step % span) - len // 띠의 왼쪽 끝
  return Array.from({ length: width }, (_, i) => {
    const d = i - head
    if (mode === 'idle' || d < 0 || d >= len) return { ch: '─', isLit: false }
    const color = AURORA[Math.min(AURORA.length - 1, Math.floor((d / len) * AURORA.length))]
    return { ch: '━', isLit: true, color, isBold: d >= len - 3 }
  })
}

const Rail: ClientModule<Props, State> = (props, surface) => {
  const { Box, Text } = surface.elements
  const ref = surface.state?.ref ?? { phase: 0, active: props.active }
  const aurora = props.variant === 'aurora'
  const mode: AuroraMode = props.mode ?? 'idle'
  ref.active = aurora ? mode !== 'idle' : props.active
  if (surface.state === undefined) {
    surface.setState({ ref })
    surface.every(STEP_MS, () => {
      if (ref.active) {
        ref.phase += 1
        surface.setState({ ref })
      }
    })
  }

  const width = Math.max(1, surface.columns || props.width)
  const cells = Array.from({ length: width + SPARE }, () => '─')
  for (const m of props.marks) if (m >= 0 && m < width) cells[m] = props.isMerge ? '┴' : '┬'

  // A graphical surface draws text in a proportional face, where ─ ● • and bold differ in width, so as
  // the packets moved the line's length changed and its right end jittered. Drawn in the surface's
  // monospaced face (whose advance is what a cell is there) each glyph is one cell, and the line sits in
  // a box of its width that clips the spare dashes: its right end is that edge, every frame.
  const line = (children: RenderChildren) => (
    <Box width={width} overflow="hidden">
      <Box flexShrink={0}>{children}</Box>
    </Box>
  )

  if (aurora) {
    // 연속 같은 색끼리 한 Text 로 묶는다(점등 여부·색이 같은 칸의 run).
    const runs: { text: string; color: string; isBold: boolean }[] = []
    for (const c of auroraCells(ref.phase, width, mode)) {
      const color = c.isLit && c.color ? c.color : props.dim
      const isBold = c.isBold === true
      const last = runs[runs.length - 1]
      if (last && last.color === color && last.isBold === isBold) last.text += c.ch
      else runs.push({ text: c.ch, color, isBold })
    }
    runs.push({ text: '─'.repeat(SPARE), color: props.dim, isBold: false })
    return line(
      runs.map(r => (
        <Text color={r.color} bold={r.isBold} mono>
          {r.text}
        </Text>
      )),
    )
  }

  if (!props.active) {
    return line(
      <Text color={props.dim} mono>
        {cells.join('')}
      </Text>,
    )
  }

  // Two packets per 24 cells, a bright head and a trailing dot, moving left to right.
  const lit = new Map<number, string>()
  for (let base = 0; base < width + 24; base += 24) {
    const head = (base + ref.phase) % (width + 24)
    if (head < width) lit.set(head, '●')
    if (head - 1 >= 0 && head - 1 < width) lit.set(head - 1, '•')
  }
  // Runs, not cells: consecutive cells of one kind share a Text, a handful of nodes per frame.
  const runs: { text: string; isLit: boolean }[] = []
  cells.forEach((ch, i) => {
    const isLit = lit.has(i)
    const last = runs[runs.length - 1]
    const glyph = lit.get(i) ?? ch
    if (last && last.isLit === isLit) last.text += glyph
    else runs.push({ text: glyph, isLit })
  })
  return line(
    runs.map(r => (
      <Text color={r.isLit ? props.color : props.dim} bold={r.isLit} mono>
        {r.text}
      </Text>
    )),
  )
}

export default Rail
