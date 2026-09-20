import { test, expect, describe, beforeEach, afterEach } from 'bun:test';
import { spawnSync } from 'child_process';
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync, readdirSync, mkdirSync, symlinkSync, lstatSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

const CLI = './console/index.ts';
function run(...args: string[]) {
  const r = spawnSync('bun', [CLI, ...args], { encoding: 'utf8' });
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', code: r.status ?? 0 };
}

const TODO_TEXT = [
  '2026-09-01 Dentist start:2026-09-22T14:30 end:2026-09-22T15:30 type:event',
  'x 2026-09-18 2026-09-01 Take out trash',
  '2026-09-01 Standup start:2026-09-21T09:00 type:event frequency:weekly frequency-day:M,W,F',
  '',
].join('\n');

describe('export-ics command', () => {
  let dir: string;
  let todoFile: string;
  let out: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'todo-export-'));
    todoFile = join(dir, 'todo.txt');
    out = join(dir, 'out');
    writeFileSync(todoFile, TODO_TEXT, 'utf8');
  });
  afterEach(() => rmSync(dir, { recursive: true }));

  test('writes the month files, recurring.ics and the report, and prints a summary', () => {
    const { stdout, code } = run('--file', todoFile, 'export-ics', '--out', out);
    expect(code).toBe(0);
    expect(readdirSync(out).sort()).toEqual(['2026-09.ics', 'export-report.txt', 'recurring.ics']);
    expect(stdout).toContain('3 lines -> 2 events + 1 reminders');
    expect(stdout).toContain(out);
    expect(readFileSync(join(out, '2026-09.ics'), 'utf8')).toContain('SUMMARY:Dentist');
    expect(readFileSync(join(out, 'recurring.ics'), 'utf8')).toContain('RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR');
  });

  test('files use CRLF line endings on disk', () => {
    run('--file', todoFile, 'export-ics', '--out', out);
    expect(readFileSync(join(out, '2026-09.ics'), 'utf8')).toContain('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n');
  });

  test('is deterministic: two exports are byte-identical', () => {
    const out2 = join(dir, 'out2');
    run('--file', todoFile, 'export-ics', '--out', out);
    run('--file', todoFile, 'export-ics', '--out', out2);
    for (const name of readdirSync(out)) {
      expect(readFileSync(join(out2, name), 'utf8')).toBe(readFileSync(join(out, name), 'utf8'));
    }
  });

  test('refuses a non-empty output directory without --force', () => {
    mkdirSync(out);
    writeFileSync(join(out, 'keep.txt'), 'x');
    const { stderr, code } = run('--file', todoFile, 'export-ics', '--out', out);
    expect(code).toBe(1);
    expect(stderr).toContain('not empty');
    expect(readdirSync(out)).toEqual(['keep.txt']);
  });

  test('--force replaces old export files but leaves other files alone', () => {
    mkdirSync(out);
    writeFileSync(join(out, '2020-01.ics'), 'stale');
    writeFileSync(join(out, 'recurring.ics'), 'stale');
    writeFileSync(join(out, 'notes.txt'), 'mine');
    const { code } = run('--file', todoFile, 'export-ics', '--out', out, '--force');
    expect(code).toBe(0);
    expect(existsSync(join(out, '2020-01.ics'))).toBe(false);
    expect(readFileSync(join(out, 'notes.txt'), 'utf8')).toBe('mine');
    expect(readFileSync(join(out, 'recurring.ics'), 'utf8')).toContain('BEGIN:VCALENDAR');
  });

  test('a missing todo file is an error', () => {
    const { stderr, code } = run('--file', join(dir, 'nope.txt'), 'export-ics', '--out', out);
    expect(code).toBe(1);
    expect(stderr).toContain('no todo file');
  });

  test('an unknown option is an error', () => {
    const { stderr, code } = run('--file', todoFile, 'export-ics', '--bogus');
    expect(code).toBe(1);
    expect(stderr).toContain("unknown option '--bogus'");
  });

  test('help documents the command', () => {
    expect(run('help').stdout).toContain('export-ics');
  });

  test('--out naming an existing regular file is a clear error and leaves the file untouched', () => {
    const notADir = join(dir, 'a-file');
    writeFileSync(notADir, 'precious', 'utf8');
    for (const extra of [[], ['--force']]) {
      const { stderr, code } = run('--file', todoFile, 'export-ics', '--out', notADir, ...extra);
      expect(code).toBe(1);
      expect(stderr).toContain(`todo: ${notADir} exists and is not a directory`);
      expect(stderr).not.toContain('ENOTDIR');
      expect(readFileSync(notADir, 'utf8')).toBe('precious');
    }
  });
});

describe('export-ics command: collisions, pruning, option validation (fix round 1)', () => {
  const CLI_ABS = join(import.meta.dir, '../../index.ts');
  function runIn(cwd: string, ...args: string[]) {
    const r = spawnSync('bun', [CLI_ABS, ...args], { encoding: 'utf8', cwd });
    return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', code: r.status ?? 0 };
  }

  let dir: string;
  let todoFile: string;
  let out: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'todo-export-fix1-'));
    todoFile = join(dir, 'todo.txt');
    out = join(dir, 'out');
    writeFileSync(todoFile, TODO_TEXT, 'utf8');
  });
  afterEach(() => rmSync(dir, { recursive: true }));

  function seedCollidingDir() {
    mkdirSync(out);
    mkdirSync(join(out, '2026-09.ics'));
    writeFileSync(join(out, '2026-09.ics', 'inner.txt'), 'inner');
    writeFileSync(join(out, 'recurring.ics'), 'old-recurring');
    writeFileSync(join(out, 'export-report.txt'), 'old-report');
    writeFileSync(join(out, 'notes.txt'), 'mine');
  }
  function expectCollidingDirUntouched() {
    expect(readdirSync(out).sort()).toEqual(['2026-09.ics', 'export-report.txt', 'notes.txt', 'recurring.ics']);
    expect(readFileSync(join(out, '2026-09.ics', 'inner.txt'), 'utf8')).toBe('inner');
    expect(readFileSync(join(out, 'recurring.ics'), 'utf8')).toBe('old-recurring');
    expect(readFileSync(join(out, 'export-report.txt'), 'utf8')).toBe('old-report');
    expect(readFileSync(join(out, 'notes.txt'), 'utf8')).toBe('mine');
  }

  test('--force with a directory named like an export file refuses and changes nothing', () => {
    seedCollidingDir();
    const { stderr, code } = run('--file', todoFile, 'export-ics', '--out', out, '--force');
    expect(code).toBe(1);
    expect(stderr).toContain(`todo: ${join(out, '2026-09.ics')} is a directory; remove it or choose another --out`);
    expect(stderr).not.toContain('EFAULT');
    expect(stderr).not.toContain('    at ');
    expectCollidingDirUntouched();
  });

  test('the same directory without --force is still refused as not empty', () => {
    seedCollidingDir();
    const { stderr, code } = run('--file', todoFile, 'export-ics', '--out', out);
    expect(code).toBe(1);
    expect(stderr).toContain('not empty');
    expectCollidingDirUntouched();
  });

  test('--force prunes stale export files and symlinks, never follows them, and leaves everything else', () => {
    mkdirSync(out);
    writeFileSync(join(out, '2020-01.ics'), 'stale');
    writeFileSync(join(out, 'notes.txt'), 'mine');
    symlinkSync(join(out, 'notes.txt'), join(out, '2027-01.ics'));
    writeFileSync(join(out, 'recurring.ics.bak'), 'bak');
    writeFileSync(join(out, '2026-9.ics'), 'not-an-export-name');
    const { code } = run('--file', todoFile, 'export-ics', '--out', out, '--force');
    expect(code).toBe(0);
    expect(readFileSync(join(out, '2026-09.ics'), 'utf8')).toContain('SUMMARY:Dentist');
    expect(readFileSync(join(out, 'recurring.ics'), 'utf8')).toContain('BEGIN:VCALENDAR');
    expect(existsSync(join(out, 'export-report.txt'))).toBe(true);
    expect(existsSync(join(out, '2020-01.ics'))).toBe(false);
    expect(() => lstatSync(join(out, '2027-01.ics'))).toThrow();
    expect(readFileSync(join(out, 'notes.txt'), 'utf8')).toBe('mine');
    expect(readFileSync(join(out, 'recurring.ics.bak'), 'utf8')).toBe('bak');
    expect(readFileSync(join(out, '2026-9.ics'), 'utf8')).toBe('not-an-export-name');
  });

  test('--force replaces a symlink named like a file being written without writing through it', () => {
    mkdirSync(out);
    const target = join(dir, 'outside-target.txt');
    writeFileSync(target, 'precious');
    symlinkSync(target, join(out, 'recurring.ics'));
    const { code } = run('--file', todoFile, 'export-ics', '--out', out, '--force');
    expect(code).toBe(0);
    expect(readFileSync(target, 'utf8')).toBe('precious');
    expect(lstatSync(join(out, 'recurring.ics')).isFile()).toBe(true);
    expect(readFileSync(join(out, 'recurring.ics'), 'utf8')).toContain('BEGIN:VCALENDAR');
  });

  test('--force never writes through a case-variant symlink (case-insensitive filesystems resolve it)', () => {
    mkdirSync(out);
    const victim = join(dir, 'victim.txt');
    writeFileSync(victim, 'precious');
    symlinkSync(victim, join(out, 'Recurring.ics'));
    const { code } = run('--file', todoFile, 'export-ics', '--out', out, '--force');
    expect(code).toBe(0);
    // Invariants that hold on both case-insensitive (link replaced) and case-sensitive (link survives) filesystems.
    expect(readFileSync(victim, 'utf8')).toBe('precious');
    expect(lstatSync(join(out, 'recurring.ics')).isFile()).toBe(true);
    expect(readFileSync(join(out, 'recurring.ics'), 'utf8')).toContain('BEGIN:VCALENDAR');
  });

  test.each([
    ['--out as the last argument', ['--out']],
    ['--out followed by --force', ['--out', '--force']],
    ['--out with an empty value', ['--out', '']],
  ])('%s is an error and creates nothing', (_label, extra) => {
    const { stderr, code } = runIn(dir, '--file', todoFile, 'export-ics', ...extra);
    expect(code).toBe(1);
    expect(stderr).toContain('todo: --out requires a directory');
    expect(existsSync(join(dir, '--force'))).toBe(false);
    expect(existsSync(join(dir, 'stark-export'))).toBe(false);
    expect(readdirSync(dir)).toEqual(['todo.txt']);
  });

  test('--out under a path whose parent is a regular file reports cannot create', () => {
    const blocker = join(dir, 'blocker');
    writeFileSync(blocker, 'x');
    const { stderr, code } = run('--file', todoFile, 'export-ics', '--out', join(blocker, 'sub', 'dir'));
    expect(code).toBe(1);
    expect(stderr).toContain('todo: cannot create');
    expect(stderr).not.toContain('    at ');
    expect(readFileSync(blocker, 'utf8')).toBe('x');
  });

  test('an empty todo file exports only the report', () => {
    writeFileSync(todoFile, '', 'utf8');
    const { stdout, code } = run('--file', todoFile, 'export-ics', '--out', out);
    expect(code).toBe(0);
    expect(readdirSync(out)).toEqual(['export-report.txt']);
    expect(stdout).toContain('0 lines -> 0 events + 0 reminders');
    expect(readFileSync(join(out, 'export-report.txt'), 'utf8')).toContain('0 lines -> 0 events + 0 reminders');
  });

  test('the summary line directly follows the report with no extra blank line', () => {
    const { stdout } = run('--file', todoFile, 'export-ics', '--out', out);
    expect(stdout).toMatch(/\nWrote 2 files and export-report\.txt to /);
    expect(stdout).not.toContain('\n\nWrote');
  });
});

describe('export-ics command: end to end on the golden sample', () => {
  const SAMPLE = join(import.meta.dir, '../../../shared/tests/fixtures/ics/sample.todo.txt');
  let dir: string;
  let out: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'todo-export-e2e-'));
    out = join(dir, 'out');
  });
  afterEach(() => rmSync(dir, { recursive: true }));

  test('exports sample.todo.txt: file set, component counts, byte-level CRLF, report entries', () => {
    const { stdout, code } = run('--file', SAMPLE, 'export-ics', '--out', out);
    expect(code).toBe(0);

    const ics = ['recurring.ics', '2026-08.ics', '2026-09.ics', '2026-10.ics'];
    expect(readdirSync(out).sort()).toEqual([...ics, 'export-report.txt'].sort());

    let events = 0;
    let todos = 0;
    for (const name of ics) {
      const buf = readFileSync(join(out, name));
      let cr = 0;
      let lf = 0;
      for (const b of buf) {
        if (b === 0x0d) cr++;
        else if (b === 0x0a) lf++;
      }
      expect(cr).toBe(lf);
      expect(cr).toBeGreaterThan(0);
      const text = buf.toString('utf8');
      expect(text.endsWith('END:VCALENDAR\r\n')).toBe(true);
      events += text.split('BEGIN:VEVENT').length - 1;
      todos += text.split('BEGIN:VTODO').length - 1;
    }
    expect(events).toBe(10);
    expect(todos).toBe(7);

    const reportFile = readFileSync(join(out, 'export-report.txt'), 'utf8');
    for (const text of [stdout, reportFile]) {
      expect(text).toContain('17 lines -> 10 events + 7 reminders');
      expect(text).toContain('line 14: unsupported-recurrence - frequency-month-day:fifth-friday');
      expect(text).toContain('line 15: undated - Buy milk');
    }
  });
});
