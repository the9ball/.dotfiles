import { describe, expect, test } from 'claude-code/testing'
import { formatLine, formatRemaining } from './register'

const now = Date.parse('2026-10-15T00:00:00Z')

describe('formatRemaining', () => {
  /** Checks that a due or past reset reads as zero minutes. */
  test('shows 0m when the reset is due', () => {
    expect(formatRemaining(0)).toBe('0m')
    expect(formatRemaining(-1)).toBe('0m')
  })

  /** Checks that partial minutes round up instead of down. */
  test('rounds up to whole minutes', () => {
    expect(formatRemaining(1)).toBe('1m')
    expect(formatRemaining(59 * 60_000 + 1)).toBe('1h0m')
  })

  /** Checks that only the two largest units are shown. */
  test('shows the two largest units', () => {
    expect(formatRemaining((2 * 60 + 5) * 60_000)).toBe('2h5m')
    expect(formatRemaining(((3 * 24 + 4) * 60 + 30) * 60_000)).toBe('3d4h')
  })
})

describe('formatLine', () => {
  /** Checks the full line when every figure is reported. */
  test('joins context, five-hour, and weekly figures', () => {
    const line = formatLine(
      {
        context: { window: 200_000, tokens: 50_000, percent: 25 },
        rateLimits: [
          { kind: 'five_hour', percentUsed: 12.4, resetsAt: new Date(now + 90 * 60_000).toISOString() },
          { kind: 'seven_day', percentUsed: 40.5, resetsAt: new Date(now + 2 * 86_400_000).toISOString() },
        ],
      },
      now,
    )
    expect(line).toBe('25%｜5時間 12% 1h30m｜週 41% 2d0h')
  })

  /** Checks the placeholders when no figures are known yet. */
  test('shows placeholders for missing figures', () => {
    const line = formatLine({ context: { window: 200_000 }, rateLimits: [] }, now)
    expect(line).toBe('--｜5時間 --｜週 --')
  })

  /** Checks that a window without a reset time omits the countdown. */
  test('omits the countdown when no reset time is reported', () => {
    const line = formatLine(
      { context: { window: 200_000, percent: 0 }, rateLimits: [{ kind: 'five_hour', percentUsed: 3 }] },
      now,
    )
    expect(line).toBe('0%｜5時間 3%｜週 --')
  })
})
