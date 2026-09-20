import { readFileSync } from 'fs';
import { parseLine } from '../../shared/parser';
import type { Task } from '../../shared/parser';
import { addDays } from '../../shared/utils';
import { generateTaskOccurrences } from '../../shared/commands/focus';
import { cleanTitle, parseWall } from '../../shared/ics/fields';
import { buildRRule } from '../../shared/ics/rrule';

/**
 * `time` is 'HH:MM' for a timed row (a real 00:00 included for an event), 'allday' for an event
 * whose start is date-only, and null for an untimed reminder (date-only or 00:00).
 */
interface Row { kind: 'event' | 'reminder'; date: string; time: string | null; title: string }

function arg(name: string): string {
  const i = process.argv.indexOf(name);
  if (i < 0 || i + 1 >= process.argv.length) {
    console.error(`parity-expected: missing ${name}`);
    process.exit(1);
  }
  return process.argv[i + 1]!;
}

const WINDOW_DAYS = 14;
const LOOKBACK_DAYS = 90;
const TYPED = new Set(['event', 'birthday', 'anniversary']);
const file = arg('--file');
const today = arg('--today');
const windowEnd = addDays(today, WINDOW_DAYS);
const oldest = addDays(today, -LOOKBACK_DAYS);

const tasks: Task[] = readFileSync(file, 'utf8')
  .split('\n').filter(l => l.trim() !== '').map((l, i) => parseLine(l, i + 1));

function dailyDates(task: Task, startDate: string, from: string, to: string): string[] {
  const every = parseInt(task.extensions['every'] ?? '1', 10) || 1;
  const until = task.extensions['recur-until'];
  const excluded = new Set((task.extensions['exdate'] ?? '').split(',').filter(Boolean));
  const lastDone = task.extensions['last-done'];
  if (lastDone) excluded.add(lastDone);
  const dates: string[] = [];
  for (let d = startDate; d <= to; d = addDays(d, every)) {
    if (until && d > until) break;
    if (d >= from && !excluded.has(d)) dates.push(d);
  }
  return dates;
}

/**
 * Occurrence dates in [from, to] for a task whose start is the validated `startDate`. A one-off
 * counts on its START day only, because the native agenda expands an event onto its start day
 * (multi-day rows are a documented exemption). `recurring` is the converter's own decision (see
 * `isSeries`): a rule the converter cannot express became a one-off, so it is one here too.
 */
function occurrenceDates(task: Task, startDate: string, recurring: boolean, from: string, to: string): string[] {
  if (!recurring) return startDate >= from && startDate <= to ? [startDate] : [];
  if (task.extensions['frequency'] === 'daily') return dailyDates(task, startDate, from, to);
  return generateTaskOccurrences(task, from, to).map(o => o.date);
}

/**
 * Mirrors convert.ts: a line is a series only when it has a frequency, a usable (validated) start,
 * and buildRRule can express the rule. Anything else is imported as a one-off at its start/due.
 */
function isSeries(ext: Record<string, string>): boolean {
  return ext['frequency'] !== undefined
    && parseWall(ext['start']) !== null
    && buildRRule(ext).rrule !== null;
}

const reminderRow = (date: string, time: string | null, title: string): Row =>
  ({ kind: 'reminder', date, time: time === '00:00' ? null : time, title });
// An event's midnight is real (a timed 00:00 event); only a date-only start is all-day.
const eventRow = (date: string, time: string | null, title: string): Row =>
  ({ kind: 'event', date, time: time === null ? 'allday' : time, title });

/**
 * A COPY of the task without `last-done:`. convert.ts never exdates last-done for an event
 * (native events have no completion state), so an event's occurrences are expanded without it.
 * A reminder keeps it: the converter re-bases a reminder series past last-done.
 */
function withoutLastDone(task: Task): Task {
  const { ['last-done']: _dropped, ...extensions } = task.extensions;
  return { ...task, extensions };
}
const keyOf = (r: Row) => `${r.kind}|${r.date}|${r.time ?? '-'}|${r.title}`;

const window: Row[] = [];
const overdueOneOffs: Row[] = [];
let olderOverdue = 0;
let multiDayEvents = 0;

for (const task of tasks) {
  const ext = task.extensions;
  const startWall = parseWall(ext['start']);
  const typed = ext['type'] !== undefined && TYPED.has(ext['type']);
  const series = isSeries(ext);
  // The converter's title, including its fallback for a title that cleans down to nothing.
  const title = cleanTitle(task.text) || '(untitled)';

  // A typed line with a usable start is an Event whether or not it is done (the spec has no
  // completion for events). Every other line is a Reminder.
  if (typed && startWall !== null) {
    const end = parseWall(ext['end']);
    if (!series && end !== null && end.date > startWall.date) multiDayEvents++;
    for (const date of occurrenceDates(withoutLastDone(task), startWall.date, series, today, windowEnd)) {
      window.push(eventRow(date, startWall.time, title));
    }
    continue;
  }

  // Completed reminders are history; only a done line that continues as a series is still live.
  if (task.done && !series) continue;

  // Undated reminders are invisible in the native agenda and are not compared.
  const dueWall = startWall ?? parseWall(ext['due']);
  if (dueWall === null) continue;
  if (series) {
    for (const date of occurrenceDates(task, dueWall.date, true, today, windowEnd)) {
      window.push(reminderRow(date, dueWall.time, title));
    }
  } else if (dueWall.date >= today && dueWall.date <= windowEnd) {
    window.push(reminderRow(dueWall.date, dueWall.time, title));
  } else if (dueWall.date < today) {
    if (dueWall.date >= oldest) overdueOneOffs.push(reminderRow(dueWall.date, dueWall.time, title));
    else olderOverdue++;
  }
}

window.sort((a, b) => keyOf(a).localeCompare(keyOf(b)));
overdueOneOffs.sort((a, b) => keyOf(a).localeCompare(keyOf(b)));
console.log(JSON.stringify({ today, windowDays: WINDOW_DAYS, window, overdueOneOffs, exempt: { olderOverdue, multiDayEvents } }, null, 2));
