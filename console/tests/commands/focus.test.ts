import { test, expect, describe, beforeEach, afterEach } from 'bun:test';
import { spawnSync } from 'child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

const CLI = './console/index.ts';

function run(args: string[]): { stdout: string; stderr: string; code: number } {
  const result = spawnSync('bun', [CLI, ...args], { encoding: 'utf8', env: { ...process.env, TZ: 'UTC' } });
  return { stdout: result.stdout ?? '', stderr: result.stderr ?? '', code: result.status ?? 0 };
}

function todayStr(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function addDays(dateStr: string, n: number): string {
  const d = new Date(dateStr + 'T12:00:00');
  d.setDate(d.getDate() + n);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

describe('focus command', () => {
  let dir: string;
  let todoFile: string;
  let today: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'todo-test-'));
    todoFile = join(dir, 'todo.txt');
    today = todayStr();
  });

  afterEach(() => {
    rmSync(dir, { recursive: true });
  });

  test('exits with error if file not found', () => {
    const { stderr, code } = run(['--file', '/nonexistent/todo.txt', 'focus']);
    expect(code).toBe(1);
    expect(stderr).toContain('No todo.txt found');
  });

  test('shows nothing message when no items in window', () => {
    writeFileSync(todoFile, '', 'utf8');
    const { stdout, code } = run(['--file', todoFile, 'focus']);
    expect(code).toBe(0);
    expect(stdout).toContain('Nothing');
  });

  // Non-recurring events
  test('shows non-recurring event with start: in window', () => {
    const start = addDays(today, 5);
    writeFileSync(todoFile, `2026-05-06 Dentist start:${start}T09:00 end:${start}T10:00 type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Dentist');
  });

  test('shows end time range when end-time: is set alongside a start: time', () => {
    const start = addDays(today, 5);
    writeFileSync(todoFile, `2026-05-06 Standup start:${start}T09:00 end-time:09:30 type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('09:00-09:30');
  });

  test('shows only start time when end-time: is not set', () => {
    const start = addDays(today, 5);
    writeFileSync(todoFile, `2026-05-06 Dentist start:${start}T09:00 type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('09:00');
    expect(stdout).not.toContain('09:00-');
  });

  test('shows end time range when end: carries a same-day datetime (no end-time: extension)', () => {
    const start = addDays(today, 5);
    writeFileSync(todoFile, `2026-05-06 Standup start:${start}T08:30 end:${start}T10:30 type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('08:30-10:30');
  });

  test('does not render "undefined"/"NaN" when start: is a bare time with no date', () => {
    // A malformed start: (e.g. accidentally typed as just a time, missing the date
    // prefix) must never produce garbage output like "undefined undefined NaN" -
    // see issue where `new Date("17:30T12:00:00")` is an Invalid Date.
    writeFileSync(todoFile, `${today} pick up the girls from tennis practice start:17:30\n`, 'utf8');
    const { stdout, code } = run(['--file', todoFile, 'focus']);
    expect(code).toBe(0);
    expect(stdout).toContain('tennis practice');
    expect(stdout).not.toContain('undefined');
    expect(stdout).not.toContain('NaN');
  });

  test('does not crash when end-time: is set but start: has no time component', () => {
    const start = addDays(today, 5);
    writeFileSync(todoFile, `2026-05-06 All-day thing start:${start} end-time:09:30 type:event\n`, 'utf8');
    const { stdout, code } = run(['--file', todoFile, 'focus']);
    expect(code).toBe(0);
    expect(stdout).toContain('All-day thing');
    expect(stdout).not.toContain('09:30');
  });

  test('hides non-recurring event with start: after window', () => {
    const start = addDays(today, 20);
    writeFileSync(todoFile, `2026-05-06 Future Event start:${start} type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('Future Event');
  });

  test('hides non-recurring event with start: before today', () => {
    const start = addDays(today, -3);
    writeFileSync(todoFile, `2026-05-06 Past Event start:${start} type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('Past Event');
  });

  test('shows non-recurring event starting today', () => {
    writeFileSync(todoFile, `2026-05-06 Today Event start:${today}T10:00 type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Today Event');
  });

  // Yearly recurring (birthday/anniversary)
  test('shows yearly birthday whose next occurrence is in window', () => {
    const nextOccurrence = addDays(today, 7);
    const mmdd = nextOccurrence.slice(5);
    writeFileSync(todoFile, `2026-05-06 John Birthday start:1990-${mmdd} frequency:yearly type:birthday\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('John Birthday');
  });

  test('hides yearly birthday whose next occurrence is after window', () => {
    const afterWindow = addDays(today, 30);
    const mmdd = afterWindow.slice(5);
    writeFileSync(todoFile, `2026-05-06 John Birthday start:1990-${mmdd} frequency:yearly type:birthday\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('John Birthday');
  });

  // Other recurring events (weekly/monthly)
  test('shows active weekly recurring event regardless of original start:', () => {
    const pastStart = addDays(today, -60);
    writeFileSync(todoFile, `2026-05-06 Weekly Standup start:${pastStart}T09:00 frequency:weekly type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Weekly Standup');
  });

  test('hides weekly recurring event whose recur-until: has passed', () => {
    const pastStart = addDays(today, -60);
    const pastUntil = addDays(today, -10);
    writeFileSync(todoFile, `2026-05-06 Ended Standup start:${pastStart}T09:00 frequency:weekly recur-until:${pastUntil} type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('Ended Standup');
  });

  test('still shows a recurring event whose start: is older than 2 years with no recur-until:', () => {
    // Recurring means recurring — an old start: date must never suppress an otherwise-active
    // recurring task/event. A prior guard mistakenly hid these; reversed per explicit product decision.
    const staleStart = addDays(today, -800);
    writeFileSync(todoFile, `2026-05-06 Old Workshop start:${staleStart}T10:00 frequency:daily type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Old Workshop');
  });

  test('shows daily recurring task whose start: is in the future (within window)', () => {
    const futureStart = addDays(today, 3);
    writeFileSync(todoFile, `2026-05-06 Water plants start:${futureStart}T09:00 frequency:daily\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Water plants');
    expect(stdout).not.toContain('today');
  });

  test('hides daily recurring task whose start: is beyond the focus window', () => {
    const farFuture = addDays(today, 20);
    writeFileSync(todoFile, `2026-05-06 Far future daily start:${farFuture}T09:00 frequency:daily\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('Far future daily');
  });

  test('shows recurring event whose start: is within 2 years with no recur-until:', () => {
    const recentStart = addDays(today, -60);
    writeFileSync(todoFile, `2026-05-06 Weekly Standup start:${recentStart}T09:00 frequency:weekly type:event\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Weekly Standup');
  });

  // Regular tasks
  test('shows regular task with due: in window', () => {
    const due = addDays(today, 5);
    writeFileSync(todoFile, `2026-05-06 Buy groceries due:${due}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Buy groceries');
  });

  test('hides regular task with due: after window', () => {
    const due = addDays(today, 20);
    writeFileSync(todoFile, `2026-05-06 Future task due:${due}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('Future task');
  });

  test('hides regular task with no due:', () => {
    writeFileSync(todoFile, `2026-05-06 No due task\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('No due task');
  });

  test('shows regular task with start: today (no type, no frequency)', () => {
    writeFileSync(todoFile, `2026-05-06 Basketball wechat start:${today}T09:00\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Basketball wechat');
  });

  test('shows regular task with start: in window (no type, no frequency)', () => {
    const start = addDays(today, 5);
    writeFileSync(todoFile, `2026-05-06 Scheduled task start:${start}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Scheduled task');
  });

  test('hides regular task with start: after window (no type, no frequency)', () => {
    const start = addDays(today, 20);
    writeFileSync(todoFile, `2026-05-06 Future scheduled task start:${start}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('Future scheduled task');
  });

  test('shows regular task with start: in the past (no type, no frequency) — overdue', () => {
    const start = addDays(today, -3);
    writeFileSync(todoFile, `2026-05-06 Past scheduled task start:${start}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('Past scheduled task');
  });

  test('sorts regular task with start: by start date', () => {
    const near = addDays(today, 2);
    const far = addDays(today, 8);
    writeFileSync(todoFile, [
      `2026-05-06 Far start task start:${far}`,
      `2026-05-06 Near start task start:${near}`,
    ].join('\n') + '\n', 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout.indexOf('Near start task')).toBeLessThan(stdout.indexOf('Far start task'));
  });

  test('sorts weekly recurring event by next occurrence of its weekday, not today', () => {
    // Find the next Saturday from today
    const todayDate = new Date(today + 'T12:00:00');
    const daysUntilSat = (6 - todayDate.getDay() + 7) % 7;
    const nextSat = addDays(today, daysUntilSat === 0 ? 0 : daysUntilSat);
    // A task due the day after next Saturday should sort after the weekly Saturday event
    const afterSat = addDays(nextSat, 1);
    // A task due the day before next Saturday should sort before it
    const beforeSat = daysUntilSat > 0 ? addDays(today, 1) : addDays(nextSat, -1);
    // The recurring event's start must be a Saturday, computed relative to `today` (not a
    // fixed calendar date) so this test can't itself go stale as real time passes.
    const startSat = addDays(nextSat, -7);
    writeFileSync(todoFile, [
      `2026-05-06 Weekly Saturday event start:${startSat}T10:00 frequency:weekly type:event`,
      `2026-05-06 Task due after Saturday due:${afterSat}`,
      ...(beforeSat >= today ? [`2026-05-06 Task due before Saturday due:${beforeSat}`] : []),
    ].join('\n') + '\n', 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    if (daysUntilSat > 0) {
      expect(stdout.indexOf('Task due before Saturday')).toBeLessThan(stdout.indexOf('Weekly Saturday event'));
    }
    expect(stdout.indexOf('Weekly Saturday event')).toBeLessThan(stdout.indexOf('Task due after Saturday'));
  });

  test('sorts by nearest due date first', () => {
    const near = addDays(today, 2);
    const far = addDays(today, 10);
    writeFileSync(todoFile, `2026-05-06 Far task due:${far}\n2026-05-06 Near task due:${near}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout.indexOf('Near task')).toBeLessThan(stdout.indexOf('Far task'));
  });

  test('hides done tasks', () => {
    const due = addDays(today, 5);
    writeFileSync(todoFile, `x 2026-05-06 2026-05-01 Done task due:${due}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('Done task');
  });

  test('weekly task with frequency-day shows for next matching day-of-week, not 7-day interval from start', () => {
    // Start on last Sunday (Sunday is NOT in frequency-day:W,F).
    // Without frequency-day support, nextWeeklyDate returns next Sunday (wrong).
    // With fix, it returns the nearest Wednesday or Friday from today.
    const todayDate = new Date(today + 'T12:00:00');
    // Last Sunday: go back by today's DOW days (Sun=0 → go back 7 to avoid start=today)
    const daysBack = todayDate.getDay() || 7;
    const lastSunday = addDays(today, -daysBack);

    // Find next W (3) or F (5) from today (0 = today itself if today is Wed or Fri)
    let daysToNextWF = 7;
    for (let i = 0; i <= 7; i++) {
      const dow = (todayDate.getDay() + i) % 7;
      if (dow === 3 || dow === 5) { daysToNextWF = i; break; }
    }
    const nextOccurrence = addDays(today, daysToNextWF);

    writeFileSync(todoFile,
      `2026-01-01 chorus practice frequency:weekly frequency-day:W,F start:${lastSunday}T08:15\n`,
      'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);

    expect(stdout).toContain('chorus practice');

    const d = new Date(nextOccurrence + 'T12:00:00');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (daysToNextWF === 0) {
      expect(stdout).toContain('today');
      expect(stdout).toContain('08:15');
    } else {
      expect(stdout).toContain(`${months[d.getMonth()]} ${d.getDate()} 08:15`);
    }
  });
});

describe('focus - recurring task completion tracking', () => {
  function todayStr(): string {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }
  function daysAgo(n: number): string {
    const d = new Date();
    d.setDate(d.getDate() - n);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  let dir: string;
  let todoFile: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'todo-test-'));
    todoFile = join(dir, 'todo.txt');
  });

  afterEach(() => {
    rmSync(dir, { recursive: true });
  });

  test('shows daily recurring task for next day when last-done equals today', () => {
    const today = todayStr();
    const tomorrow = addDays(today, 1);
    writeFileSync(todoFile, `stoicism start:${daysAgo(1)}T06:00 frequency:daily last-done:${today}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    // Completed today — shows as tomorrow's occurrence
    expect(stdout).toContain('stoicism');
    expect(stdout).not.toContain('today');
  });

  test('shows recurring task when last-done is yesterday', () => {
    const yesterday = daysAgo(1);
    writeFileSync(todoFile, `stoicism start:${daysAgo(2)}T06:00 frequency:daily last-done:${yesterday}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('stoicism');
  });

  test('shows streak count ×N for recurring task with 2+ consecutive completions', () => {
    const lines = [
      `stoicism start:${daysAgo(5)}T06:00 frequency:daily`,
      `x ${daysAgo(1)} stoicism`,
      `x ${daysAgo(2)} stoicism`,
      `x ${daysAgo(3)} stoicism`,
    ].join('\n') + '\n';
    writeFileSync(todoFile, lines, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('stoicism');
    expect(stdout).toContain('×3');
  });

  test('does not show streak for task with only 1 completion', () => {
    writeFileSync(todoFile, [
      `stoicism start:${daysAgo(5)}T06:00 frequency:daily`,
      `x ${daysAgo(1)} stoicism`,
    ].join('\n') + '\n', 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).not.toContain('×');
  });

  test('shows streak of 2 for task completed yesterday and day before', () => {
    const yesterday = daysAgo(1);
    writeFileSync(todoFile, [
      `stoicism start:${daysAgo(5)}T06:00 frequency:daily last-done:${yesterday}`,
      `x ${yesterday} stoicism`,
      `x ${daysAgo(2)} stoicism`,
    ].join('\n') + '\n', 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('stoicism');
    expect(stdout).toContain('×2');
  });
});

describe('focus - overdue recurring tasks', () => {
  function todayStr(): string {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }
  function daysAgo(n: number): string {
    const d = new Date();
    d.setDate(d.getDate() - n);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  let dir: string;
  let todoFile: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'todo-test-'));
    todoFile = join(dir, 'todo.txt');
  });

  afterEach(() => {
    rmSync(dir, { recursive: true });
  });

  test('weekly task with start yesterday and no last-done shows as overdue today', () => {
    const yesterday = daysAgo(1);
    writeFileSync(todoFile, `weekly review start:${yesterday} frequency:weekly\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('weekly review');
    expect(stdout).toContain('today');
  });

  test('weekly task with start yesterday and last-done matching yesterday shows as next occurrence (not overdue)', () => {
    const yesterday = daysAgo(1);
    writeFileSync(todoFile, `weekly review start:${yesterday} frequency:weekly last-done:${yesterday}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('weekly review');
    // Next occurrence is 6 days from now, not today
    expect(stdout).not.toContain('today');
  });

  test('monthly task with occurrence yesterday (>14 days gap) still shows in focus as overdue', () => {
    // Start exactly one month before yesterday so monthly occurrence lands on yesterday
    const yesterday = daysAgo(1);
    const d = new Date(yesterday + 'T12:00:00');
    d.setMonth(d.getMonth() - 1);
    const startDate = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    writeFileSync(todoFile, `monthly task start:${startDate} frequency:monthly\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('monthly task');
    expect(stdout).toContain('today');
  });

  test('weekly task with start tomorrow and last-done today shows next occurrence (not overdue)', () => {
    const today = todayStr();
    const tomorrow = addDays(today, 1);
    writeFileSync(todoFile, `mow lawn start:${tomorrow}T09:00 frequency:weekly last-done:${today}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('mow lawn');
    // Next occurrence is 8 days out (tomorrow + 7), not today
    expect(stdout).not.toContain('today');
  });

  test('weekly task done yesterday shows next occurrence, not today', () => {
    const today = todayStr();
    const yesterday = addDays(today, -1);
    // start = today, done yesterday (one day early) — should not show as "today"
    writeFileSync(todoFile, `mow lawn start:${today}T09:00 frequency:weekly last-done:${yesterday}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    expect(stdout).toContain('mow lawn');
    expect(stdout).not.toContain('today');
  });

  test('monthly task with last-done matching most recent occurrence is not shown as overdue', () => {
    // Same setup: start one month before yesterday so occurrence was yesterday
    const yesterday = daysAgo(1);
    const d = new Date(yesterday + 'T12:00:00');
    d.setMonth(d.getMonth() - 1);
    const startDate = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    writeFileSync(todoFile, `monthly task start:${startDate} frequency:monthly last-done:${yesterday}\n`, 'utf8');
    const { stdout } = run(['--file', todoFile, 'focus']);
    // Next occurrence is ~30 days away, outside the 14-day window — should not show
    expect(stdout).not.toContain('monthly task');
  });
});
