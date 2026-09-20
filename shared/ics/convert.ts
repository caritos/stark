import type { Task } from '../parser';
import type { IcsEvent, IcsReminder, Wall } from './types';
import { buildRRule } from './rrule';
import { cleanTitle, decodeNote, isBareTime, joinNotes, parseWall, priorityToNumber, resolveEventEnd } from './fields';
import { rebaseAnchor } from './anchor';

export type ReportKind =
  | 'unsupported-recurrence' | 'ignored-extension' | 'end-before-start'
  | 'undated' | 'untitled' | 'event-without-start' | 'finished-series';
export interface ReportEntry { line: number; kind: ReportKind; detail: string }
export type SourceBucket =
  | 'open-event' | 'open-birthday' | 'open-anniversary' | 'open-task'
  | 'done-plain' | 'done-with-start' | 'done-event' | 'done-recurring';
export type Converted =
  | { kind: 'event'; event: IcsEvent; source: SourceBucket; entries: ReportEntry[] }
  | { kind: 'reminder'; reminder: IcsReminder; source: SourceBucket; entries: ReportEntry[] };

const TYPED = new Set(['event', 'birthday', 'anniversary']);

function titleOf(task: Task, entries: ReportEntry[]): string {
  const title = cleanTitle(task.text);
  if (title === '') {
    entries.push({ line: task.line, kind: 'untitled', detail: task.raw });
    return '(untitled)';
  }
  return title;
}

/**
 * The `exdate:` list at the anchor's time-of-day. A value that is not a real calendar date is
 * skipped and reported: the Swift parser silently drops an impossible EXDATE, which would
 * resurrect the occurrence the user excluded.
 */
function exdatesOf(task: Task, time: string | null, entries: ReportEntry[]): Wall[] {
  const result: Wall[] = [];
  for (const value of (task.extensions['exdate'] ?? '').split(',')) {
    if (value === '') continue;
    const wall = parseWall(value);
    if (wall === null || wall.time !== null) {
      entries.push({ line: task.line, kind: 'ignored-extension', detail: `exdate:${value}` });
      continue;
    }
    result.push({ date: wall.date, time });
  }
  return result;
}

function recurrenceOf(task: Task, entries: ReportEntry[]): string | null {
  const result = buildRRule(task.extensions);
  for (const detail of result.ignored) entries.push({ line: task.line, kind: 'ignored-extension', detail });
  if (result.unsupported) entries.push({ line: task.line, kind: 'unsupported-recurrence', detail: result.unsupported });
  return result.rrule;
}

function buildEvent(task: Task, uid: string, entries: ReportEntry[]): IcsEvent | null {
  const ext = task.extensions;
  const start = parseWall(ext['start']);
  if (!start) return null;
  // A present but unusable end / end-time is reported. A VALID bare end: or end-time: on an
  // all-day event is ignored by design (spec) and is not an error.
  const rawEnd = ext['end'];
  if (rawEnd !== undefined && !isBareTime(rawEnd) && parseWall(rawEnd) === null) {
    entries.push({ line: task.line, kind: 'ignored-extension', detail: `end:${rawEnd}` });
  }
  const endTime = ext['end-time'];
  if (endTime !== undefined && !isBareTime(endTime)) {
    entries.push({ line: task.line, kind: 'ignored-extension', detail: `end-time:${endTime}` });
  }
  const { end, endBeforeStart } = resolveEventEnd(start, ext);
  if (endBeforeStart) entries.push({ line: task.line, kind: 'end-before-start', detail: `end:${ext['end'] ?? ''}` });
  const rrule = recurrenceOf(task, entries);
  return {
    uid,
    title: titleOf(task, entries),
    start,
    end,
    allDay: start.time === null,
    notes: joinNotes([ext['description'] ? decodeNote(ext['description']) : null, ext['note'] ? decodeNote(ext['note']) : null]),
    location: ext['location'] ? decodeNote(ext['location']) : null,
    rrule,
    exdates: rrule ? exdatesOf(task, start.time, entries) : [],
  };
}

/**
 * `reportStart` is false for a typed line that fell back from an event: its unusable start was
 * already reported as `event-without-start`, so it must not be reported a second time.
 */
function buildReminder(task: Task, uid: string, entries: ReportEntry[], reportStart: boolean): IcsReminder {
  const ext = task.extensions;
  const title = titleOf(task, entries);
  const startWall = parseWall(ext['start']);
  const dueWall = parseWall(ext['due']);
  if (reportStart && ext['start'] !== undefined && startWall === null) {
    entries.push({ line: task.line, kind: 'ignored-extension', detail: `start:${ext['start']}` });
  }
  if (ext['due'] !== undefined && dueWall === null) {
    entries.push({ line: task.line, kind: 'ignored-extension', detail: `due:${ext['due']}` });
  }
  const completionWall = task.done ? parseWall(task.completionDate) : null;

  let due: Wall | null = null;
  let dueExtra: string | null = null;
  let rrule: string | null = null;

  const frequency = ext['frequency'];
  if (frequency !== undefined) {
    if (startWall === null) {
      // A series needs a usable anchor; without one the line is imported as a one-off.
      const detail = ext['start'] === undefined
        ? `frequency:${frequency} without start:`
        : `frequency:${frequency} with unusable start:${ext['start']}`;
      entries.push({ line: task.line, kind: 'unsupported-recurrence', detail });
    } else {
      rrule = recurrenceOf(task, entries);
    }
  }

  if (rrule !== null) {
    const lastDone = ext['last-done'];
    if (lastDone !== undefined) {
      const lastDoneWall = parseWall(lastDone);
      if (lastDoneWall === null || lastDoneWall.time !== null) {
        entries.push({ line: task.line, kind: 'ignored-extension', detail: `last-done:${lastDone}` });
      }
    }
    const anchor = rebaseAnchor(task);
    if (anchor.finished) entries.push({ line: task.line, kind: 'finished-series', detail: `recur-until:${ext['recur-until'] ?? ''}` });
    due = parseWall(anchor.start);
    if (anchor.pinnedDay !== null) {
      // A clamped re-base (Jan 31 -> Feb 28, Feb 29 -> Feb 28) must keep the series on its
      // original day: the native app clamps min(day, daysInMonth). Encode from a COPY of the
      // extensions (never mutate the task), straight through buildRRule so the report entries
      // recurrenceOf already produced are not duplicated.
      const pinned = buildRRule({ ...ext, 'frequency-month-day': String(anchor.pinnedDay) }).rrule;
      if (pinned !== null) rrule = pinned;
    }
  } else {
    // One-off. A done line without a usable start is due on its x date (spec rule 4), even when
    // it carries a due: (kept as a note below); an open line falls back to due:.
    due = task.done ? (startWall ?? completionWall ?? dueWall) : (startWall ?? dueWall);
    if (dueWall && due && dueWall.date !== due.date) dueExtra = `Due: ${ext['due']}`;
  }

  // A done line is a completed reminder unless a valid RRULE is emitted (the series continues).
  const completed = task.done && rrule === null;
  if (task.done && task.completionDate !== undefined && completionWall === null) {
    entries.push({ line: task.line, kind: 'ignored-extension', detail: `completion-date:${task.completionDate}` });
  }
  const completedDate: Wall | null = completed ? completionWall : null;
  if (due === null) entries.push({ line: task.line, kind: 'undated', detail: title });

  return {
    uid,
    title,
    due,
    notes: joinNotes([
      ext['location'] ? `Location: ${decodeNote(ext['location'])}` : null,
      ext['description'] ? decodeNote(ext['description']) : null,
      ext['note'] ? decodeNote(ext['note']) : null,
      dueExtra,
    ]),
    priority: task.done ? null : priorityToNumber(task.priority),
    completed,
    completedDate,
    rrule,
    exdates: rrule ? exdatesOf(task, due?.time ?? null, entries) : [],
  };
}

export function convertTask(task: Task, uid: string): Converted {
  const ext = task.extensions;
  const type = ext['type'];
  const typed = type !== undefined && TYPED.has(type);
  const hasStart = !!ext['start'];
  const hasFrequency = !!ext['frequency'];
  const entries: ReportEntry[] = [];

  const source: SourceBucket = task.done
    ? (hasFrequency && hasStart ? 'done-recurring' : typed ? 'done-event' : hasStart ? 'done-with-start' : 'done-plain')
    : type === 'birthday' ? 'open-birthday'
    : type === 'anniversary' ? 'open-anniversary'
    : typed ? 'open-event'
    : 'open-task';

  if (typed) {
    const event = buildEvent(task, uid, entries);
    if (event) return { kind: 'event', event, source, entries };
    entries.push({ line: task.line, kind: 'event-without-start', detail: `start:${ext['start'] ?? ''}` });
  }
  return { kind: 'reminder', reminder: buildReminder(task, uid, entries, !typed), source, entries };
}
