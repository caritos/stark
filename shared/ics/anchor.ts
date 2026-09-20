import type { Task } from '../parser';
import { addDays } from '../utils';
import { generateTaskOccurrences } from '../commands/focus';

export interface Anchor {
  /** 'YYYY-MM-DD' or 'YYYY-MM-DDTHH:MM' (the start's time-of-day is kept). */
  start: string;
  /** True when no later occurrence exists (recur-until passed); start is then unchanged. */
  finished: boolean;
}

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** A well-formed AND real calendar date (rejects 2026-13-45, 2026-02-30). */
function isRealDate(value: string | undefined): value is string {
  if (!value) return false;
  const m = DATE_RE.exec(value);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const probe = new Date(y, mo - 1, d, 12, 0, 0);
  return probe.getFullYear() === y && probe.getMonth() === mo - 1 && probe.getDate() === d;
}

const dayNumber = (date: string): number => Math.round(new Date(date + 'T12:00:00').getTime() / 86400000);

/**
 * The first occurrence of a recurring reminder's series strictly after everything already
 * done (`last-done:` and, for a done line, the `x` completion date). Precondition: the task
 * has `start:` and `frequency:` extensions.
 */
export function rebaseAnchor(task: Task): Anchor {
  const start = task.extensions['start']!;
  const startDate = start.slice(0, 10);
  const time = start.slice(10);
  if (!isRealDate(startDate)) return { start, finished: false };

  const candidates = [task.extensions['last-done'], task.done ? task.completionDate : undefined]
    .filter(isRealDate)
    .sort();
  const resolvedThrough = candidates[candidates.length - 1];
  if (!resolvedThrough || resolvedThrough < startDate) return { start, finished: false };

  const from = addDays(resolvedThrough, 1);
  const frequency = task.extensions['frequency'];
  // every:0, negative or non-numeric all mean 1.
  const every = Math.max(parseInt(task.extensions['every'] ?? '1', 10) || 1, 1);
  const until = task.extensions['recur-until'];

  let next: string | null;
  if (frequency === 'daily') {
    const diff = dayNumber(from) - dayNumber(startDate);
    next = addDays(startDate, (diff <= 0 ? 0 : Math.ceil(diff / every)) * every);
  } else {
    // generateTaskOccurrences reads `every` straight from the task, so hand it the normalised value.
    const normalised: Task = { ...task, extensions: { ...task.extensions, every: String(every) } };
    const found = generateTaskOccurrences(normalised, from, addDays(from, 366 * every + 31));
    next = found.length > 0 ? found[0]!.date : null;
  }

  // A huge every: pushes the date out of Date's range (or past year 9999): no usable occurrence.
  if (next !== null && !isRealDate(next)) next = null;

  if (next === null || (isRealDate(until) && next > until)) return { start, finished: true };
  return { start: next + time, finished: false };
}
