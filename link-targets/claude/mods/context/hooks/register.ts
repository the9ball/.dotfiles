import type { Register, SessionContextUsage, SessionRateLimit, Timer } from 'claude-code'

type Usage = { context: SessionContextUsage; rateLimits: SessionRateLimit[] }

/**
 * Formats the time left until a reset as a compact duration such as `2d3h`, `4h5m`, or `7m`.
 *
 * @param ms Milliseconds until the reset; zero or less means the reset is already due.
 * @returns The duration rounded up to whole minutes, showing at most its two largest units.
 */
export const formatRemaining = (ms: number): string => {
  if (ms <= 0) return '0m'
  // Round up so a window that has not reset yet never reads as 0m.
  const totalMin = Math.ceil(ms / 60_000)
  const d = Math.floor(totalMin / 1440)
  const h = Math.floor((totalMin % 1440) / 60)
  const m = totalMin % 60
  if (d > 0) return `${d}d${h}h`
  if (h > 0) return `${h}h${m}m`
  return `${m}m`
}

/**
 * Formats one rate-limit window as its label, used percentage, and time until reset.
 *
 * @param label The window's display label.
 * @param limit The window's figures, or `undefined` when the session reports no such window.
 * @param now The current time in epoch milliseconds, used to compute the time until reset.
 * @returns `<label> <percent>% <remaining>`, without the remaining time when no reset is reported, or `<label> --` when the window is absent.
 */
const formatLimit = (label: string, limit: SessionRateLimit | undefined, now: number): string => {
  if (!limit) return `${label} --`
  const reset = limit.resetsAt ? ` ${formatRemaining(Date.parse(limit.resetsAt) - now)}` : ''
  return `${label} ${Math.round(limit.percentUsed)}%${reset}`
}

/**
 * Builds the status-line text from the context usage and the five-hour and weekly rate-limit windows.
 *
 * @param usage The latest context usage and rate-limit figures.
 * @param now The current time in epoch milliseconds.
 * @returns The three parts joined with full-width vertical bars, each part showing `--` when its figure is unknown.
 */
export const formatLine = (usage: Usage, now: number): string => {
  const ctx = usage.context.percent === undefined ? '--' : `${usage.context.percent}%`
  const session = formatLimit('5時間', usage.rateLimits.find(r => r.kind === 'five_hour'), now)
  const weekly = formatLimit('週', usage.rateLimits.find(r => r.kind === 'seven_day'), now)
  return `${ctx}｜${session}｜${weekly}`
}

// The figures last seen, kept so the per-minute timer can refresh the remaining times between measurements.
let last: Usage | undefined

// The per-minute refresh timer, kept so a later session.start replaces it instead of stacking another one.
let refreshTimer: Timer | undefined

/**
 * Registers the hooks that keep the status-line entry up to date.
 *
 * @param on The engine's hook registrar.
 */
export const register: Register = on => {
  // Shows the line as soon as the session starts and refreshes it every minute so the reset countdowns keep moving while no turn runs.
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    last = await $.session.usage()
    $.ui.status(formatLine(last, await $.clock.now()))
    refreshTimer?.cancel()
    refreshTimer = $.clock.every(60_000, async () => {
      if (last) $.ui.status(formatLine(last, await $.clock.now()))
    })
    return result
  })

  // Redraws the line with the figures the engine pushes after each turn or when a rate-limit window moves.
  on('session.measure', async ($, e, next) => {
    last = { context: e.context, rateLimits: e.rateLimits }
    $.ui.status(formatLine(last, await $.clock.now()))
    return next(e)
  })
}
