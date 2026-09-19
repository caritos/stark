import type { Task } from '../shared/parser';
import { addDays } from '../shared/utils';
import { computeYearCount } from '../shared/commands/list';

const A = {
  reset:         '\x1b[0m',
  bold:          '\x1b[1m',
  dim:           '\x1b[2m',
  strikethrough: '\x1b[9m',
  red:           '\x1b[91m',
  green:         '\x1b[92m',
  blue:          '\x1b[94m',
  purple:        '\x1b[95m',
  orange:        '\x1b[38;5;208m',
  bgRed:         '\x1b[41m',
} as const;

function c(color: string, text: string): string {
  return `${color}${text}${A.reset}`;
}

export function today(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export { addDays } from '../shared/utils';

function colorPriority(p: string): string {
  if (p === 'A') return c(A.bold + A.red, `(${p})`);
  if (p === 'B') return c(A.bold + A.blue, `(${p})`);
  if (p === 'C') return c(A.bold + A.orange, `(${p})`);
  return c(A.bold, `(${p})`);
}

function colorText(text: string, todayStr: string): string {
  return text
    .replace(/(?:^|\s)(\+\S+)/g, (m, tag: string) => m.replace(tag, c(A.green, tag)))
    .replace(/(?:^|\s)(@\S+)/g, (m, tag: string) => m.replace(tag, c(A.purple, tag)))
    .replace(/(?:^|\s)(due:\d{4}-\d{2}-\d{2})/g, (m, due: string) => {
      const date = due.slice(4);
      if (date < todayStr) return m.replace(due, c(A.bgRed + A.red, `${due} OVERDUE`));
      if (date <= addDays(todayStr, 3)) return m.replace(due, c(A.orange, due));
      return m;
    });
}

export function formatTask(task: Task, todayStr: string): string {
  const num = c(A.dim, String(task.line).padStart(2));

  if (task.done) {
    const raw = ['x', task.completionDate, task.creationDate, task.text]
      .filter(Boolean)
      .join(' ');
    return `${num}  ${c(A.dim + A.strikethrough, raw)}`;
  }

  const parts: string[] = [];
  if (task.priority) parts.push(colorPriority(task.priority));
  if (task.creationDate) parts.push(c(A.dim, task.creationDate));
  const years = computeYearCount(task, todayStr);
  const yearCount = years !== undefined ? `(${years} years)` : undefined;
  const displayText = task.text.replace(/(?:^|\s)last-done:\S+/g, ' ').replace(/\s+/g, ' ').trim();
  const coloredText = colorText(displayText, todayStr);
  parts.push(yearCount ? `${coloredText} ${c(A.dim, yearCount)}` : coloredText);
  return `${num}  ${parts.join(' ')}`;
}

const DAY_ABBR = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MON_ABBR = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const FOCUS_STRIP_RE = /\s+(?:reminders-id|start|end|end-time|location|exdate|frequency(?:-(?:day|month(?:-day)?|month))?|recur-until|note|description|due|type|last-done|every):\S+/g;

export function formatFocusTask(task: Task, todayStr: string, effectiveDate: string, recLabel = '', streak = 0): string {
  const num = c(A.dim, String(task.line).padStart(4));

  const datePart = effectiveDate.slice(0, 10);
  const timePart = effectiveDate.length > 10 ? effectiveDate.slice(11, 16) : '';
  let when: string;
  if (datePart === todayStr) {
    when = timePart ? `today ${timePart}` : 'today';
  } else {
    const d = new Date(datePart + 'T12:00:00');
    if (isNaN(d.getTime())) {
      // A malformed date-like extension (e.g. start: written as a bare time with no
      // date, like "17:30") must never render as "undefined undefined NaN" - show
      // the raw value instead so it's at least legible and points at the bad data.
      when = datePart || '?';
    } else {
      const dm = `${MON_ABBR[d.getMonth()]} ${d.getDate()}`;
      when = timePart ? `${DAY_ABBR[d.getDay()]} ${dm} ${timePart}` : `${DAY_ABBR[d.getDay()]} ${dm}`;
    }
  }

  const rawStart = task.extensions['start'];
  const rawEnd = task.extensions['end'];
  const endTimeExt = task.extensions['end-time'] ??
    (rawEnd && rawStart && rawEnd.length > 10 && rawEnd.slice(0, 10) === rawStart.slice(0, 10)
      ? rawEnd.slice(11, 16)
      : undefined);
  if (endTimeExt && timePart) when += `-${endTimeExt}`;

  const cleanText = task.text.replace(FOCUS_STRIP_RE, '').trim();
  const years = computeYearCount(task, todayStr);
  const yearCount = years !== undefined ? `(${years} years)` : undefined;
  const colored = colorText(cleanText, todayStr);
  const title = yearCount ? `${colored} ${c(A.dim, yearCount)}` : colored;

  const overdue = datePart < todayStr && datePart !== '9999-12-31';
  const whenCol = overdue ? c(A.red, when.padEnd(18)) : c(A.dim, when.padEnd(18));
  const recPart = recLabel ? `  ${c(A.dim, recLabel)}` : '';
  const streakPart = streak >= 2 ? `  ${c(A.dim, `×${streak}`)}` : '';
  let thruPart = '';
  if (rawEnd && rawStart && rawEnd.slice(0, 10) !== rawStart.slice(0, 10)) {
    const endDate = rawEnd.slice(0, 10);
    const ed = new Date(endDate + 'T12:00:00');
    const yearSuffix = endDate.slice(0, 4) !== todayStr.slice(0, 4) ? ` ${ed.getFullYear()}` : '';
    thruPart = `  ${c(A.dim, `thru ${MON_ABBR[ed.getMonth()]} ${ed.getDate()}${yearSuffix}`)}`;
  }
  const taskType = task.extensions['type'];
  const TYPE_ICON: Record<string, string> = { event: '', birthday: '', anniversary: '' };
  const typeIcon = taskType ? (TYPE_ICON[taskType] ?? '') : '';
  const typePart = typeIcon ? `  ${c(A.dim, typeIcon)}` : '';
  if (task.priority) return `${num}  ${whenCol}  ${colorPriority(task.priority)} ${title}${thruPart}${recPart}${streakPart}${typePart}`;
  return `${num}  ${whenCol}  ${title}${thruPart}${recPart}${streakPart}${typePart}`;
}

export function formatSummary(open: number, done: number, overdue: number, dueSoon: number): string {
  const parts: string[] = [];
  if (done > 0) {
    parts.push(`${open + done} total · ${open} open · ${done} completed`);
  } else {
    parts.push(`${open} open task${open === 1 ? '' : 's'}`);
  }
  if (overdue > 0) parts.push(c(A.red, `${overdue} overdue`));
  else if (dueSoon > 0) parts.push(`${dueSoon} due within 3 days`);
  return c(A.dim, parts.join(' · '));
}
