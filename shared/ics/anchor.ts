import type { Task } from '../parser';
import { addDays } from '../utils';
import { nextMonthlyDate, nextWeeklyDate, nextYearlyDate } from '../commands/focus';

export interface Anchor {
  /** 'YYYY-MM-DD' or 'YYYY-MM-DDTHH:MM' (the start's time-of-day is kept). */
  start: string;
  /**
   * True only when `recur-until` rules out every occurrence after what is already done, or the
   * next occurrence lies beyond the representable calendar (year 9999); `start` is then the
   * original, unchanged. An open series is never finished, however many occurrences are exdated.
   */
  finished: boolean;
  /**
   * The ORIGINAL start's day-of-month, set only when a plain monthly/yearly series (no
   * `frequency-month-day`) was re-based onto a clamped date (e.g. Jan 31 -> Feb 28, Feb 29 ->
   * Feb 28), so the caller can keep the series on that day (BYMONTHDAY). Otherwise null.
   */
  pinnedDay: number | null;
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
 * done (`last-done:` and, for a done line, the `x` completion date), skipping `exdate:` dates.
 * Precondition: the task has `start:` and `frequency:` extensions.
 *
 * Each frequency is resolved with ONE call to the matching single-step helper in
 * shared/commands/focus.ts (the same arguments generateTaskOccurrences passes), never by
 * enumerating a window, so the cost does not depend on `every`.
 */
export function rebaseAnchor(task: Task): Anchor {
  const start = task.extensions['start']!;
  const startDate = start.slice(0, 10);
  const time = start.slice(10);
  const unchanged = (finished: boolean): Anchor => ({ start, finished, pinnedDay: null });
  if (!isRealDate(startDate)) return unchanged(false);

  const candidates = [task.extensions['last-done'], task.done ? task.completionDate : undefined]
    .filter(isRealDate)
    .sort();
  const resolvedThrough = candidates[candidates.length - 1];
  if (!resolvedThrough || resolvedThrough < startDate) return unchanged(false);

  const from = addDays(resolvedThrough, 1);
  const frequency = task.extensions['frequency'];
  // every:0, negative or non-numeric all mean 1.
  const every = Math.max(parseInt(task.extensions['every'] ?? '1', 10) || 1, 1);
  const until = task.extensions['recur-until'];
  const untilDate = isRealDate(until) ? until : undefined;

  // Nothing after `from` can be in the series.
  if (untilDate && from > untilDate) return unchanged(true);

  const exdates = new Set((task.extensions['exdate'] ?? '').split(',').filter(Boolean));
  const lastDone = task.extensions['last-done'];
  if (lastDone) exdates.add(lastDone);
  const freqDay = task.extensions['frequency-day'];
  const freqMonthDay = task.extensions['frequency-month-day'];

  let next: string;
  if (frequency === 'daily') {
    const diff = dayNumber(from) - dayNumber(startDate);
    next = addDays(startDate, (diff <= 0 ? 0 : Math.ceil(diff / every)) * every);
    // Terminates: every pass consumes one distinct exdate (or leaves the calendar range).
    while (exdates.has(next)) next = addDays(next, every);
  } else if (frequency === 'weekly') {
    next = nextWeeklyDate(start, from, every, exdates, freqDay);
  } else if (frequency === 'monthly') {
    next = nextMonthlyDate(start, from, exdates, freqMonthDay, every);
  } else if (frequency === 'yearly') {
    next = nextYearlyDate(startDate, from, exdates, freqMonthDay, every);
  } else {
    return unchanged(false); // not a series we can advance
  }

  // A huge `every` pushes the date out of Date's range (or past year 9999): no usable occurrence.
  if (!isRealDate(next)) return unchanged(true);
  // The helper found nothing at or after `from` (e.g. an empty weekday set, or every candidate
  // in its search span exdated): the series cannot be advanced, keep it as written.
  if (next < from) return unchanged(false);
  if (untilDate && next > untilDate) return unchanged(true);

  const startDay = Number(startDate.slice(8, 10));
  const pinnedDay =
    (frequency === 'monthly' || frequency === 'yearly') &&
    !freqMonthDay &&
    Number(next.slice(8, 10)) !== startDay
      ? startDay
      : null;
  return { start: next + time, finished: false, pinnedDay };
}
