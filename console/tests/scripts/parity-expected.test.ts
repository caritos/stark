import { test, expect } from 'bun:test';
import { spawnSync } from 'child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

const SAMPLE = join(import.meta.dir, '../../../shared/tests/fixtures/ics/sample.todo.txt');

interface ParityRow { kind: string; date: string; time: string | null; title: string }

const SCRIPT = join(import.meta.dir, '../../scripts/parity-expected.ts');

const run = (file: string = SAMPLE, today = '2026-09-20') => {
  const r = spawnSync('bun', [SCRIPT, '--file', file, '--today', today], { encoding: 'utf8' });
  // Assert here so an outright spawn/script failure can never look like an empty (vacuous) result.
  expect(r.status).toBe(0);
  expect(r.stdout).not.toBe('');
  return { code: r.status ?? 0, json: JSON.parse(r.stdout), stderr: r.stderr ?? '' };
};

const keyOf = (r: ParityRow) => `${r.kind}|${r.date}|${r.time ?? '-'}|${r.title}`;

/** Runs the script over a temporary todo.txt made of `lines`. */
function runLines(lines: string[], today = '2026-09-20') {
  const dir = mkdtempSync(join(tmpdir(), 'parity-expected-'));
  try {
    const file = join(dir, 'todo.txt');
    writeFileSync(file, lines.join('\n') + '\n');
    const { code, json } = run(file, today);
    return {
      code,
      window: ((json.window ?? []) as ParityRow[]).map(keyOf),
      overdue: ((json.overdueOneOffs ?? []) as ParityRow[]).map(keyOf),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('emits the expected window rows for the sample fixture', () => {
  const { code, json } = run();
  expect(code).toBe(0);
  expect(json.today).toBe('2026-09-20');
  expect(json.windowDays).toBe(14);
  const keys = (json.window as ParityRow[]).map(keyOf);
  // Standup: Mon/Wed/Fri from 9/21, minus the exdates 9/23 and 9/25, through 10/4
  for (const d of ['2026-09-21', '2026-09-28', '2026-09-30', '2026-10-02']) expect(keys).toContain(`event|${d}|09:00|Standup`);
  expect(keys.some(k => k.includes('2026-09-23|09:00|Standup'))).toBe(false);
  expect(keys.some(k => k.includes('2026-09-25|09:00|Standup'))).toBe(false);
  expect(keys).toContain('event|2026-09-22|14:30|Dentist');
  expect(keys).toContain('event|2026-09-30|08:00|Payday');
  expect(keys).toContain('reminder|2026-09-25|10:00|Call insurance ~sam %phone bus:16:00');
  expect(keys).toContain('reminder|2026-09-27|07:00|Water plants');
  expect(keys).toContain('reminder|2026-10-01|-|Pay rent');
  // done lines and out-of-window items are not expected
  expect(keys.some(k => k.includes('Take out trash') || k.includes('Old dentist') || k.includes('Book club'))).toBe(false);
  expect(json.overdueOneOffs).toEqual([]);
});

// Ruling (a): a rule the converter cannot express is imported as a ONE-OFF at its start, so the
// expected agenda must show a single row on the start day and no occurrence series.
test('an inexpressible fifth-friday rule is expected as a one-off on its start date only', () => {
  const inWindow = runLines([
    '2026-09-01 Fifth Friday start:2026-10-30T18:00 type:event frequency:monthly frequency-month-day:fifth-friday',
  ], '2026-10-25');
  expect(inWindow.code).toBe(0);
  expect(inWindow.window).toEqual(['event|2026-10-30|18:00|Fifth Friday']);

  // Started in May (a real 5th Friday) and today is October: a series would put a row on 10-30,
  // the one-off has nothing in the window.
  const startedEarlier = runLines([
    '2026-05-01 Fifth Friday start:2026-05-29T18:00 type:event frequency:monthly frequency-month-day:fifth-friday',
  ], '2026-10-25');
  expect(startedEarlier.window).toEqual([]);
});

test('an unparseable start makes a frequency line a one-off at its due date, or nothing at all', () => {
  const none = runLines([
    '2026-09-01 Broken series start:2026-13-45 frequency:weekly',
    '2026-09-01 Broken event start:2026-13-45 type:event frequency:weekly',
  ]);
  expect(none.code).toBe(0);
  expect(none.window).toEqual([]);
  expect(none.overdue).toEqual([]);

  const withDue = runLines(['2026-09-01 Broken but due start:2026-13-45 due:2026-09-22 frequency:weekly']);
  expect(withDue.window).toEqual(['reminder|2026-09-22|-|Broken but due']);

  const noStart = runLines(['2026-09-01 No anchor frequency:weekly due:2026-09-23T08:15']);
  expect(noStart.window).toEqual(['reminder|2026-09-23|08:15|No anchor']);
});

// Ruling (b): titles equal the converter's, including its (untitled) fallback.
test('an empty cleaned title becomes (untitled), as the converter writes it', () => {
  const { window } = runLines(['2026-09-01 start:2026-09-22T10:00 type:event']);
  expect(window).toEqual(['event|2026-09-22|10:00|(untitled)']);
});

// The converter writes a done typed line with a usable start as an Event, so it is on the agenda.
test('a done typed event is expected as an event; a done plain reminder is not', () => {
  const { window } = runLines([
    'x 2026-09-10 2026-09-01 Team offsite start:2026-09-23T10:00 type:event',
    'x 2026-09-10 2026-09-01 Filed taxes start:2026-09-23T10:00',
  ]);
  expect(window).toEqual(['event|2026-09-23|10:00|Team offsite']);
});

// Fix round 1. convert.ts never exdates `last-done:` for an EVENT (native events have no completion
// state), so an event whose last-done falls in the window still has that occurrence on the agenda.
test('an event keeps the occurrence on its last-done date (daily, last-done today)', () => {
  const { window } = runLines([
    '2026-09-01 DailyLD start:2026-09-01T09:00 type:event frequency:daily last-done:2026-09-20',
  ]);
  expect(window).toContain('event|2026-09-20|09:00|DailyLD');
  expect(window).toContain('event|2026-09-21|09:00|DailyLD');
  expect(window.filter(k => k.includes('DailyLD'))).toHaveLength(15);
});

test('an event keeps the occurrence on its last-done date (weekly, last-done inside the window)', () => {
  const { window } = runLines([
    '2026-09-01 WeeklyLD start:2026-09-07T09:00 type:event frequency:weekly last-done:2026-09-21',
  ]);
  expect(window.filter(k => k.includes('WeeklyLD'))).toEqual([
    'event|2026-09-21|09:00|WeeklyLD',
    'event|2026-09-28|09:00|WeeklyLD',
  ]);
});

// The converter re-bases a REMINDER series past `last-done:`, so nothing on or before it survives.
test('a reminder series still drops occurrences up to its last-done date', () => {
  const daily = runLines([
    '2026-09-01 DailyRem start:2026-09-01T09:00 frequency:daily last-done:2026-09-20',
  ]);
  expect(daily.window).not.toContain('reminder|2026-09-20|09:00|DailyRem');
  expect(daily.window).toContain('reminder|2026-09-21|09:00|DailyRem');
  expect(daily.window.filter(k => k.includes('DailyRem'))).toHaveLength(14);

  const weekly = runLines([
    '2026-09-01 WeeklyRem start:2026-09-07T09:00 frequency:weekly last-done:2026-09-21',
  ]);
  expect(weekly.window.filter(k => k.includes('WeeklyRem'))).toEqual(['reminder|2026-09-28|09:00|WeeklyRem']);
});

// Fix round 1. An event is 'allday' when its start is date-only and keeps a real 00:00 when timed;
// a reminder's date-only or 00:00 time is still null.
test('an all-day event and a timed T00:00 event are different rows; a 00:00 reminder is untimed', () => {
  const { window } = runLines([
    '2026-09-01 AllDay start:2026-09-22 type:event',
    '2026-09-01 Midnight start:2026-09-22T00:00 type:event',
    '2026-09-01 Birthday start:1975-09-23 type:birthday frequency:yearly',
    '2026-09-01 Untimed start:2026-09-22',
    '2026-09-01 MidnightReminder start:2026-09-22T00:00',
  ]);
  expect(window).toContain('event|2026-09-22|allday|AllDay');
  expect(window).toContain('event|2026-09-22|00:00|Midnight');
  expect(window).toContain('event|2026-09-23|allday|Birthday');
  expect(window).toContain('reminder|2026-09-22|-|Untimed');
  expect(window).toContain('reminder|2026-09-22|-|MidnightReminder');
});

test('an open one-off reminder overdue by 1..90 days is listed; older ones are only counted', () => {
  const dir = mkdtempSync(join(tmpdir(), 'parity-expected-'));
  try {
    const file = join(dir, 'todo.txt');
    writeFileSync(file, [
      '2026-06-01 Recent start:2026-09-10',
      '2026-01-01 Ancient start:2026-01-10',
    ].join('\n') + '\n');
    const { json } = run(file);
    expect((json.overdueOneOffs as ParityRow[]).map(keyOf)).toEqual(['reminder|2026-09-10|-|Recent']);
    expect(json.exempt.olderOverdue).toBe(1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
