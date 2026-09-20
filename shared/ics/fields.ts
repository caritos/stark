import type { Wall } from './types';

// The only keys the converter consumes. Everything else that looks like key:value (tags,
// custom keys like bus:16:00, times in prose like 9:00) stays in the title untouched.
export const STRUCTURAL_KEYS: ReadonlySet<string> = new Set([
  'type', 'start', 'end', 'end-time', 'frequency', 'frequency-day', 'frequency-month-day',
  'frequency-month', 'every', 'exdate', 'recur-until', 'last-done', 'due', 'location', 'note',
  'description', 'reminders-id',
]);

const TOKEN_RE = /^([\w-]+):([^/\s]\S*)$/;
const WALL_RE = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$/;
const BARE_TIME_RE = /^(\d{2}):(\d{2})$/;

/**
 * Validates that a date is valid using UTC round-trip.
 * Returns true if the date is valid in the calendar.
 */
function isValidDate(year: number, month: number, day: number): boolean {
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

/**
 * Validates that a time is within valid range: hour 0-23, minute 0-59.
 */
function isValidTime(hour: number, minute: number): boolean {
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

export function cleanTitle(text: string): string {
  return text
    .split(/\s+/) // any whitespace: tabs, and the \r a CRLF-saved line leaves on its last token
    .filter(token => {
      const m = TOKEN_RE.exec(token);
      return !(m && STRUCTURAL_KEYS.has(m[1]!));
    })
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function decodeNote(value: string): string {
  return value.replace(/_/g, ' ');
}

export function joinNotes(parts: Array<string | null | undefined>): string | null {
  // A part that is blank after trimming (e.g. `description:_` decodes to " ") is absent.
  const present = parts.filter((p): p is string => !!p && p.trim() !== '');
  return present.length > 0 ? present.join('\n') : null;
}

export function parseWall(value: string | undefined): Wall | null {
  if (value === undefined) return null;
  const m = WALL_RE.exec(value);
  if (!m) return null;

  const year = parseInt(m[1]!, 10);
  const month = parseInt(m[2]!, 10);
  const day = parseInt(m[3]!, 10);

  // Validate the date
  if (!isValidDate(year, month, day)) return null;

  const dateStr = `${m[1]!}-${m[2]!}-${m[3]!}`;

  // If there's a time component, validate it
  if (m[4] !== undefined && m[5] !== undefined) {
    const hour = parseInt(m[4]!, 10);
    const minute = parseInt(m[5]!, 10);
    if (!isValidTime(hour, minute)) return null;
    return { date: dateStr, time: `${m[4]}:${m[5]}` };
  }

  return { date: dateStr, time: null };
}

export function priorityToNumber(priority: string | undefined): number | null {
  if (!priority || !/^[A-Z]$/.test(priority)) return null;
  return Math.min(priority.charCodeAt(0) - 64, 9);
}

export interface EndResult {
  end: Wall | null;
  endBeforeStart: boolean;
}

/**
 * Validates a bare time string HH:MM
 */
function isValidBareTime(timeStr: string): boolean {
  const m = BARE_TIME_RE.exec(timeStr);
  if (!m) return false;
  const hour = parseInt(m[1]!, 10);
  const minute = parseInt(m[2]!, 10);
  return isValidTime(hour, minute);
}

/** True for a real bare time HH:MM (hour 0-23, minute 0-59). */
export function isBareTime(value: string): boolean {
  return isValidBareTime(value);
}

const sortKey = (w: Wall): string => `${w.date}T${w.time ?? '00:00'}`;

export function resolveEventEnd(start: Wall, ext: Record<string, string>): EndResult {
  const allDay = start.time === null;
  const rawEnd = ext['end'];
  const endTime = ext['end-time'];
  const endTimeOk = endTime !== undefined && isValidBareTime(endTime) && !allDay;
  let end: Wall | null = null;

  if (rawEnd !== undefined) {
    if (isValidBareTime(rawEnd)) {
      if (!allDay) end = { date: start.date, time: rawEnd };
    } else {
      const w = parseWall(rawEnd);
      if (w) {
        if (allDay) end = { date: w.date, time: null };
        else if (w.time !== null) end = w;
        else end = { date: w.date, time: endTimeOk ? endTime! : start.time };
      }
    }
  } else if (endTimeOk) {
    end = { date: start.date, time: endTime! };
  }

  if (!end) return { end: null, endBeforeStart: false };
  if (sortKey(end) < sortKey(start)) return { end: null, endBeforeStart: true };
  return { end, endBeforeStart: false };
}
