import { test, expect } from 'bun:test';
import { parseLine } from '../../parser';
import { rebaseAnchor } from '../../ics/anchor';

const anchor = (line: string) => rebaseAnchor(parseLine(line, 1));

test('no last-done keeps the start', () => {
  expect(anchor('Pay rent start:2026-10-01 frequency:monthly')).toEqual({ start: '2026-10-01', finished: false });
});

test('last-done before start keeps the start', () => {
  expect(anchor('Water start:2026-09-27T07:00 frequency:weekly last-done:2026-09-20')).toEqual({ start: '2026-09-27T07:00', finished: false });
});

test('weekly every 2: the first occurrence after last-done, time-of-day kept', () => {
  expect(anchor('Water plants start:2026-09-13T07:00 frequency:weekly every:2 last-done:2026-09-20'))
    .toEqual({ start: '2026-09-27T07:00', finished: false });
});

test('weekly with a weekday set', () => {
  // Mon 9/7 start, done Wed 9/9 -> next M/W/F occurrence is Fri 9/11
  expect(anchor('Gym start:2026-09-07 frequency:weekly frequency-day:M,W,F last-done:2026-09-09'))
    .toEqual({ start: '2026-09-11', finished: false });
});

test('monthly', () => {
  expect(anchor('Rent start:2026-08-15 frequency:monthly last-done:2026-09-20')).toEqual({ start: '2026-10-15', finished: false });
});

test('yearly keeps its month and day', () => {
  expect(anchor('Renew start:2020-06-10 frequency:yearly last-done:2026-06-10')).toEqual({ start: '2027-06-10', finished: false });
});

test('daily every 3 (computed here, generateTaskOccurrences ignores daily)', () => {
  // 9/1, 9/4, 9/7, 9/10 (done), next is 9/13
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:3 last-done:2026-09-10')).toEqual({ start: '2026-09-13', finished: false });
});

test('a done line resolves through its completion date', () => {
  expect(anchor('x 2026-09-20 2026-09-01 Water start:2026-09-13 frequency:weekly')).toEqual({ start: '2026-09-27', finished: false });
});

test('a series whose recur-until has passed is finished and keeps its start', () => {
  expect(anchor('Old start:2026-01-05 frequency:weekly recur-until:2026-02-01 last-done:2026-03-01'))
    .toEqual({ start: '2026-01-05', finished: true });
});

// Hostile / edge cases

test('a malformed last-done is treated as no resolved date and does not throw', () => {
  expect(anchor('Water start:2026-09-13T07:00 frequency:weekly last-done:soon'))
    .toEqual({ start: '2026-09-13T07:00', finished: false });
});

test('an impossible-but-well-shaped last-done does not throw', () => {
  expect(() => anchor('Water start:2026-09-13 frequency:weekly last-done:2026-13-45')).not.toThrow();
});

test('a last-done after everything (past recur-until) finishes the series', () => {
  expect(anchor('Old start:2026-01-05 frequency:daily recur-until:2026-01-31 last-done:2030-01-01'))
    .toEqual({ start: '2026-01-05', finished: true });
});

test('a last-done far in the future of an open series still resolves', () => {
  expect(anchor('Water start:2026-09-13 frequency:weekly last-done:2030-01-01')).toEqual({ start: '2030-01-06', finished: false });
});

test('every:0 is treated as 1 for every frequency and does not hang', () => {
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:0 last-done:2026-09-10')).toEqual({ start: '2026-09-11', finished: false });
  expect(anchor('Water start:2026-09-13 frequency:weekly every:0 last-done:2026-09-20')).toEqual({ start: '2026-09-27', finished: false });
  expect(anchor('Rent start:2026-08-15 frequency:monthly every:0 last-done:2026-09-20')).toEqual({ start: '2026-10-15', finished: false });
  expect(anchor('Renew start:2020-06-10 frequency:yearly every:0 last-done:2026-06-10')).toEqual({ start: '2027-06-10', finished: false });
});

test('a non-numeric every is treated as 1', () => {
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:abc last-done:2026-09-10')).toEqual({ start: '2026-09-11', finished: false });
  expect(anchor('Water start:2026-09-13 frequency:weekly every:abc last-done:2026-09-20')).toEqual({ start: '2026-09-27', finished: false });
});

test('a negative every is treated as 1', () => {
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:-2 last-done:2026-09-10')).toEqual({ start: '2026-09-11', finished: false });
});

test('an absurdly large every never yields an invalid date', () => {
  for (const line of [
    'V start:2026-09-01 frequency:daily every:99999999999 last-done:2026-09-10',
    'W start:2026-09-13 frequency:weekly every:99999 last-done:2026-09-20',
    'M start:2026-08-15 frequency:monthly every:99999 last-done:2026-09-20',
    'Y start:2020-06-10 frequency:yearly every:100000 last-done:2026-06-10',
  ]) {
    const a = anchor(line);
    expect(a.start).not.toContain('NaN');
    expect(a).toEqual({ start: line.match(/start:(\S+)/)![1]!, finished: true });
  }
});

test('a done line with no completion date keeps the start', () => {
  expect(anchor('x Water start:2026-09-13T07:00 frequency:weekly')).toEqual({ start: '2026-09-13T07:00', finished: false });
});

test('a recur-until equal to the next occurrence still allows it', () => {
  expect(anchor('Water start:2026-09-13 frequency:weekly recur-until:2026-09-27 last-done:2026-09-20'))
    .toEqual({ start: '2026-09-27', finished: false });
});

test('a recur-until one day before the next occurrence finishes the series', () => {
  expect(anchor('Water start:2026-09-13 frequency:weekly recur-until:2026-09-26 last-done:2026-09-20'))
    .toEqual({ start: '2026-09-13', finished: true });
});

test('when a done line and last-done disagree, the later date wins', () => {
  expect(anchor('x 2026-09-20 2026-09-01 Water start:2026-09-06 frequency:weekly last-done:2026-09-08'))
    .toEqual({ start: '2026-09-27', finished: false });
});
