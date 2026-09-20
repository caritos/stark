import type { Task } from '../parser';
import type { IcsEvent, IcsReminder } from '../ics/types';
import { convertTask } from '../ics/convert';
import type { ReportEntry, SourceBucket } from '../ics/convert';
import { parseWall } from '../ics/fields';
import { serializeCalendar } from '../ics/text';
import { makeUid } from '../ics/uid';

export interface ExportOptions {
  uid?: (task: Task, duplicateIndex: number) => string;
}

export interface ExportReport {
  lines: number;
  events: number;
  reminders: number;
  bySource: Partial<Record<SourceBucket, number>>;
  entries: ReportEntry[];
}

export interface ExportResult {
  files: Record<string, string>;
  report: ExportReport;
}

const RECURRING = 'recurring.ics';
const monthFile = (date: string): string => `${date.slice(0, 7)}.ics`;

export function applyExportIcs(tasks: Task[], options: ExportOptions = {}): ExportResult {
  const uidFor = options.uid ?? ((task: Task, index: number) => makeUid(task.raw, index));
  const seen = new Map<string, number>();

  // Items carry their source line so each file can be emitted in source order even when an
  // item (an undated reminder) is placed after the others.
  interface Placed<T> { line: number; value: T }
  const buckets = new Map<string, { events: Array<Placed<IcsEvent>>; reminders: Array<Placed<IcsReminder>> }>();
  const bucket = (name: string) => {
    let b = buckets.get(name);
    if (!b) { b = { events: [], reminders: [] }; buckets.set(name, b); }
    return b;
  };

  const report: ExportReport = { lines: tasks.length, events: 0, reminders: 0, bySource: {}, entries: [] };
  const undated: Array<{ task: Task; reminder: IcsReminder }> = [];

  for (const task of tasks) {
    const index = seen.get(task.raw) ?? 0;
    seen.set(task.raw, index + 1);
    const converted = convertTask(task, uidFor(task, index));
    report.bySource[converted.source] = (report.bySource[converted.source] ?? 0) + 1;
    report.entries.push(...converted.entries);

    if (converted.kind === 'event') {
      report.events++;
      const e = converted.event;
      bucket(e.rrule ? RECURRING : monthFile(e.start.date)).events.push({ line: task.line, value: e });
    } else {
      report.reminders++;
      const r = converted.reminder;
      if (r.rrule) bucket(RECURRING).reminders.push({ line: task.line, value: r });
      else if (r.due) bucket(monthFile(r.due.date)).reminders.push({ line: task.line, value: r });
      else undated.push({ task, reminder: r });
    }
  }

  if (report.events + report.reminders !== tasks.length) {
    throw new Error(`export lost lines: ${tasks.length} in, ${report.events + report.reminders} out`);
  }

  // An undated reminder goes in the month of its creation date, but only a REAL date: a
  // shape-only match (2026-13-45) would name a month file the app never loads.
  const earliest = [...buckets.keys()].filter(k => k !== RECURRING).sort()[0];
  for (const { task, reminder } of undated) {
    const creation = parseWall(task.creationDate)?.date;
    const created = creation !== undefined ? monthFile(creation) : undefined;
    bucket(created ?? earliest ?? '1970-01.ics').reminders.push({ line: task.line, value: reminder });
  }

  const names = [...buckets.keys()].sort((a, b) =>
    a === RECURRING ? -1 : b === RECURRING ? 1 : a.localeCompare(b));
  const files: Record<string, string> = {};
  for (const name of names) {
    const b = buckets.get(name)!;
    const bySourceLine = <T>(a: Placed<T>, c: Placed<T>) => a.line - c.line;
    files[name] = serializeCalendar(
      [...b.events].sort(bySourceLine).map(p => p.value),
      [...b.reminders].sort(bySourceLine).map(p => p.value),
    );
  }

  report.entries.sort((a, b) => a.line - b.line);
  return { files, report };
}

export function formatReport(report: ExportReport): string {
  const lines = [`${report.lines} lines -> ${report.events} events + ${report.reminders} reminders`, '', 'By source:'];
  for (const [source, count] of Object.entries(report.bySource).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`  ${source}: ${count}`);
  }
  lines.push('');
  if (report.entries.length === 0) {
    lines.push('No report entries.');
  } else {
    lines.push(`Report entries (${report.entries.length}):`);
    for (const e of report.entries) lines.push(`  line ${e.line}: ${e.kind} - ${e.detail}`);
  }
  return lines.join('\n') + '\n';
}
