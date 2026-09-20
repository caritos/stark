import type { Task } from '../parser';
import type { IcsEvent, IcsReminder, Wall } from './types';
import { buildRRule } from './rrule';
import { cleanTitle, decodeNote, joinNotes, parseWall, priorityToNumber, resolveEventEnd } from './fields';
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

function buildReminder(task: Task, uid: string, entries: ReportEntry[]): IcsReminder {
  const ext = task.extensions;
  const title = titleOf(task, entries);
  const startWall = parseWall(ext['start']);
  const dueWall = parseWall(ext['due']);
  const recurring = !!ext['frequency'] && !!ext['start'];
  if (ext['frequency'] && !ext['start']) {
    entries.push({ line: task.line, kind: 'unsupported-recurrence', detail: `frequency:${ext['frequency']} without start:` });
  }

  let due: Wall | null;
  let dueExtra: string | null = null;
  let rrule: string | null = null;

  if (recurring) {
    rrule = recurrenceOf(task, entries);
    if (rrule !== null) {
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
      due = startWall;
    }
  } else {
    due = startWall ?? dueWall;
    if (startWall && dueWall && dueWall.date !== startWall.date) dueExtra = `Due: ${ext['due']}`;
  }

  const completed = task.done && !recurring;
  const completionWall = task.done ? parseWall(task.completionDate) : null;
  if (task.done && task.completionDate !== undefined && completionWall === null) {
    entries.push({ line: task.line, kind: 'ignored-extension', detail: `completion-date:${task.completionDate}` });
  }
  const completedDate: Wall | null = completed ? completionWall : null;
  if (completed && due === null && completedDate) due = completedDate;
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
  return { kind: 'reminder', reminder: buildReminder(task, uid, entries), source, entries };
}
