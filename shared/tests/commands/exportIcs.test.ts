import { test, expect, describe } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { parseLine } from '../../parser';
import type { Task } from '../../parser';
import { applyExportIcs, assertReconciled, formatReport } from '../../commands/exportIcs';

const FIXTURES = join(import.meta.dir, '../fixtures/ics');
const parse = (text: string): Task[] =>
  text.split('\n').filter(l => l.trim() !== '').map((l, i) => parseLine(l, i + 1));
const sequentialUid = (t: Task) => 'L' + String(t.line).padStart(2, '0');
const sample = () => parse(readFileSync(join(FIXTURES, 'sample.todo.txt'), 'utf8'));

describe('golden fixtures (byte for byte, the same files the Swift ICSParser test reads)', () => {
  const result = applyExportIcs(sample(), { uid: sequentialUid });

  test('the set of files', () => {
    expect(Object.keys(result.files)).toEqual(['recurring.ics', '2026-08.ics', '2026-09.ics', '2026-10.ics']);
  });
  for (const name of ['recurring.ics', '2026-08.ics', '2026-09.ics', '2026-10.ics']) {
    test(`${name} matches the fixture exactly`, () => {
      expect(result.files[name]).toBe(readFileSync(join(FIXTURES, 'expected', name), 'utf8'));
    });
  }
  test('the report reconciles with the 17 sample lines', () => {
    expect(result.report.lines).toBe(17);
    expect(result.report.events).toBe(10);
    expect(result.report.reminders).toBe(7);
    expect(result.report.bySource).toEqual({
      'open-event': 8, 'open-birthday': 1, 'open-task': 5, 'done-plain': 1, 'done-with-start': 1, 'done-event': 1,
    });
    expect(result.report.entries).toEqual([
      { line: 14, kind: 'unsupported-recurrence', detail: 'frequency-month-day:fifth-friday' },
      { line: 15, kind: 'undated', detail: 'Buy milk' },
    ]);
  });
});

describe('ids', () => {
  test('default ids are UUID-shaped and stable across runs', () => {
    const a = applyExportIcs(parse('2026-09-01 A start:2026-09-22\n2026-09-01 B start:2026-09-23\n'));
    const b = applyExportIcs(parse('2026-09-01 A start:2026-09-22\n2026-09-01 B start:2026-09-23\n'));
    expect(a.files).toEqual(b.files);
    expect(a.files['2026-09.ics']).toMatch(/UID:[0-9A-F]{8}-[0-9A-F]{4}-5[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}/);
  });
  test('two identical lines get different ids', () => {
    const r = applyExportIcs(parse('Same start:2026-09-22\nSame start:2026-09-22\n'));
    const uids = [...(r.files['2026-09.ics'] ?? '').matchAll(/UID:(\S+)/g)].map(m => m[1]);
    expect(uids.length).toBe(2);
    expect(uids[0]).not.toBe(uids[1]);
  });
});

describe('undated reminders', () => {
  test('go to the creation-date month', () => {
    const r = applyExportIcs(parse('2026-05-03 Buy milk\n2026-09-01 X start:2026-09-22\n'));
    expect(Object.keys(r.files)).toEqual(['2026-05.ics', '2026-09.ics']);
  });
  test('without a creation date, go to the earliest dated month', () => {
    const r = applyExportIcs(parse('Buy milk\n2026-09-01 X start:2026-09-22\n2026-07-01 Y start:2026-07-04\n'));
    expect(r.files['2026-07.ics']).toContain('SUMMARY:Buy milk');
  });
  test('an impossible creation date never names a file the app cannot load', () => {
    const r = applyExportIcs(parse('2026-13-45 Buy milk\n2026-09-01 X start:2026-09-22\n'));
    expect(Object.keys(r.files)).toEqual(['2026-09.ics']);
    expect(r.files['2026-09.ics']).toContain('SUMMARY:Buy milk');
  });
  test('with nothing else dated, fall back to 1970-01', () => {
    expect(Object.keys(applyExportIcs(parse('Buy milk\n')).files)).toEqual(['1970-01.ics']);
  });
  test('an impossible creation date with nothing else dated falls back to 1970-01', () => {
    expect(Object.keys(applyExportIcs(parse('2026-13-45 Buy milk\n')).files)).toEqual(['1970-01.ics']);
  });
  test('a creation month later than every dated month gets its own, later file', () => {
    const r = applyExportIcs(parse('2026-12-05 Buy milk\n2026-09-01 X start:2026-09-22\n'));
    expect(Object.keys(r.files)).toEqual(['2026-09.ics', '2026-12.ics']);
    expect(r.files['2026-12.ics']).toContain('SUMMARY:Buy milk');
    expect(r.files['2026-09.ics']).not.toContain('SUMMARY:Buy milk');
  });
});

describe('assertReconciled', () => {
  test('returns normally when the counts agree', () => {
    expect(() => assertReconciled(3, 3)).not.toThrow();
  });
  test('throws when a line was lost', () => {
    expect(() => assertReconciled(3, 2)).toThrow('export lost lines: 3 in, 2 out');
  });
  test('throws when a line was invented', () => {
    expect(() => assertReconciled(2, 3)).toThrow('export lost lines: 2 in, 3 out');
  });
});

describe('edges', () => {
  test('empty input gives no files and a zero report', () => {
    const r = applyExportIcs([]);
    expect(r.files).toEqual({});
    expect(r.report).toEqual({ lines: 0, events: 0, reminders: 0, bySource: {}, entries: [] });
  });
  test('report entries are ordered by line', () => {
    const r = applyExportIcs(parse('Buy milk\nOdd start:2026-09-01T10:00 type:event frequency:monthly frequency-day:M\n'));
    expect(r.report.entries.map(e => e.line)).toEqual([1, 2]);
  });
  test('report entries are sorted even when the tasks arrive out of line order', () => {
    const tasks = [parseLine('Nine', 9), parseLine('Two', 2), parseLine('Five', 5)];
    const r = applyExportIcs(tasks);
    expect(r.report.entries.map(e => e.line)).toEqual([2, 5, 9]);
  });
});

describe('formatReport', () => {
  test('summarises counts, sources and every entry', () => {
    const text = formatReport(applyExportIcs(sample(), { uid: sequentialUid }).report);
    expect(text).toContain('17 lines -> 10 events + 7 reminders');
    expect(text).toContain('open-event: 8');
    expect(text).toContain('line 14: unsupported-recurrence - frequency-month-day:fifth-friday');
    expect(text).toContain('line 15: undated - Buy milk');
  });
  test('says so when there is nothing to report', () => {
    expect(formatReport(applyExportIcs(parse('A start:2026-09-22\n')).report)).toContain('No report entries.');
  });
});
