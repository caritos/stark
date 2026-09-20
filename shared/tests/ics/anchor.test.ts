import { test, expect } from 'bun:test';
import { parseLine } from '../../parser';
import { addDays } from '../../utils';
import { rebaseAnchor } from '../../ics/anchor';

const anchor = (line: string) => rebaseAnchor(parseLine(line, 1));

test('no last-done keeps the start', () => {
  expect(anchor('Pay rent start:2026-10-01 frequency:monthly')).toEqual({ start: '2026-10-01', finished: false, pinnedDay: null });
});

test('last-done before start keeps the start', () => {
  expect(anchor('Water start:2026-09-27T07:00 frequency:weekly last-done:2026-09-20')).toEqual({ start: '2026-09-27T07:00', finished: false, pinnedDay: null });
});

test('weekly every 2: the first occurrence after last-done, time-of-day kept', () => {
  expect(anchor('Water plants start:2026-09-13T07:00 frequency:weekly every:2 last-done:2026-09-20'))
    .toEqual({ start: '2026-09-27T07:00', finished: false, pinnedDay: null });
});

test('weekly with a weekday set', () => {
  // Mon 9/7 start, done Wed 9/9 -> next M/W/F occurrence is Fri 9/11
  expect(anchor('Gym start:2026-09-07 frequency:weekly frequency-day:M,W,F last-done:2026-09-09'))
    .toEqual({ start: '2026-09-11', finished: false, pinnedDay: null });
});

test('monthly', () => {
  expect(anchor('Rent start:2026-08-15 frequency:monthly last-done:2026-09-20')).toEqual({ start: '2026-10-15', finished: false, pinnedDay: null });
});

test('yearly keeps its month and day', () => {
  expect(anchor('Renew start:2020-06-10 frequency:yearly last-done:2026-06-10')).toEqual({ start: '2027-06-10', finished: false, pinnedDay: null });
});

test('daily every 3 (computed here, generateTaskOccurrences ignores daily)', () => {
  // 9/1, 9/4, 9/7, 9/10 (done), next is 9/13
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:3 last-done:2026-09-10')).toEqual({ start: '2026-09-13', finished: false, pinnedDay: null });
});

test('a done line resolves through its completion date', () => {
  expect(anchor('x 2026-09-20 2026-09-01 Water start:2026-09-13 frequency:weekly')).toEqual({ start: '2026-09-27', finished: false, pinnedDay: null });
});

test('a series whose recur-until has passed is finished and keeps its start', () => {
  expect(anchor('Old start:2026-01-05 frequency:weekly recur-until:2026-02-01 last-done:2026-03-01'))
    .toEqual({ start: '2026-01-05', finished: true, pinnedDay: null });
});

// Hostile / edge cases

test('a malformed last-done is treated as no resolved date and does not throw', () => {
  expect(anchor('Water start:2026-09-13T07:00 frequency:weekly last-done:soon'))
    .toEqual({ start: '2026-09-13T07:00', finished: false, pinnedDay: null });
});

test('an impossible-but-well-shaped last-done does not throw', () => {
  expect(() => anchor('Water start:2026-09-13 frequency:weekly last-done:2026-13-45')).not.toThrow();
});

test('a last-done after everything (past recur-until) finishes the series', () => {
  expect(anchor('Old start:2026-01-05 frequency:daily recur-until:2026-01-31 last-done:2030-01-01'))
    .toEqual({ start: '2026-01-05', finished: true, pinnedDay: null });
});

test('a last-done far in the future of an open series still resolves', () => {
  expect(anchor('Water start:2026-09-13 frequency:weekly last-done:2030-01-01')).toEqual({ start: '2030-01-06', finished: false, pinnedDay: null });
});

test('every:0 is treated as 1 for every frequency and does not hang', () => {
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:0 last-done:2026-09-10')).toEqual({ start: '2026-09-11', finished: false, pinnedDay: null });
  expect(anchor('Water start:2026-09-13 frequency:weekly every:0 last-done:2026-09-20')).toEqual({ start: '2026-09-27', finished: false, pinnedDay: null });
  expect(anchor('Rent start:2026-08-15 frequency:monthly every:0 last-done:2026-09-20')).toEqual({ start: '2026-10-15', finished: false, pinnedDay: null });
  expect(anchor('Renew start:2020-06-10 frequency:yearly every:0 last-done:2026-06-10')).toEqual({ start: '2027-06-10', finished: false, pinnedDay: null });
});

test('a non-numeric every is treated as 1', () => {
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:abc last-done:2026-09-10')).toEqual({ start: '2026-09-11', finished: false, pinnedDay: null });
  expect(anchor('Water start:2026-09-13 frequency:weekly every:abc last-done:2026-09-20')).toEqual({ start: '2026-09-27', finished: false, pinnedDay: null });
});

test('a negative every is treated as 1', () => {
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:-2 last-done:2026-09-10')).toEqual({ start: '2026-09-11', finished: false, pinnedDay: null });
});

test('an absurdly large every never yields an invalid date', () => {
  // No occurrence within the representable calendar (past year 9999) -> finished, start unchanged.
  for (const line of [
    'V start:2026-09-01 frequency:daily every:99999999999 last-done:2026-09-10',
    'M start:2026-08-15 frequency:monthly every:99999 last-done:2026-09-20',
    'Y start:2020-06-10 frequency:yearly every:100000 last-done:2026-06-10',
  ]) {
    const a = anchor(line);
    expect(a.start).not.toContain('NaN');
    expect(a).toEqual({ start: line.match(/start:(\S+)/)![1]!, finished: true, pinnedDay: null });
  }
  // Weekly every:99999 has a real (if distant) next occurrence, 99999 weeks after the start.
  expect(anchor('W start:2026-09-13 frequency:weekly every:99999 last-done:2026-09-20'))
    .toEqual({ start: addDays('2026-09-13', 99999 * 7), finished: false, pinnedDay: null });
});

test('a done line with no completion date keeps the start', () => {
  expect(anchor('x Water start:2026-09-13T07:00 frequency:weekly')).toEqual({ start: '2026-09-13T07:00', finished: false, pinnedDay: null });
});

test('a recur-until equal to the next occurrence still allows it', () => {
  expect(anchor('Water start:2026-09-13 frequency:weekly recur-until:2026-09-27 last-done:2026-09-20'))
    .toEqual({ start: '2026-09-27', finished: false, pinnedDay: null });
});

test('a recur-until one day before the next occurrence finishes the series', () => {
  expect(anchor('Water start:2026-09-13 frequency:weekly recur-until:2026-09-26 last-done:2026-09-20'))
    .toEqual({ start: '2026-09-13', finished: true, pinnedDay: null });
});

test('when a done line and last-done disagree, the later date wins', () => {
  expect(anchor('x 2026-09-20 2026-09-01 Water start:2026-09-06 frequency:weekly last-done:2026-09-08'))
    .toEqual({ start: '2026-09-27', finished: false, pinnedDay: null });
});

// Fix round 1: exdates skipped for every frequency, no window enumeration, pinned day-of-month

test('an exdated next yearly occurrence is skipped, and the series is not finished', () => {
  expect(anchor('Y start:2020-06-10 frequency:yearly last-done:2026-06-10 exdate:2027-06-10'))
    .toEqual({ start: '2028-06-10', finished: false, pinnedDay: null });
  expect(anchor('Y start:2020-06-10 frequency:yearly every:2 last-done:2026-06-10 exdate:2028-06-10'))
    .toEqual({ start: '2030-06-10', finished: false, pinnedDay: null });
});

test('an exdated next weekly, weekday-set, monthly and daily occurrence is skipped', () => {
  expect(anchor('Water start:2026-09-13 frequency:weekly last-done:2026-09-20 exdate:2026-09-27'))
    .toEqual({ start: '2026-10-04', finished: false, pinnedDay: null });
  expect(anchor('Gym start:2026-09-07 frequency:weekly frequency-day:M,W,F last-done:2026-09-09 exdate:2026-09-11'))
    .toEqual({ start: '2026-09-14', finished: false, pinnedDay: null });
  expect(anchor('Rent start:2026-08-15 frequency:monthly last-done:2026-09-20 exdate:2026-10-15'))
    .toEqual({ start: '2026-11-15', finished: false, pinnedDay: null });
  expect(anchor('Vitamins start:2026-09-01 frequency:daily every:3 last-done:2026-09-10 exdate:2026-09-13'))
    .toEqual({ start: '2026-09-16', finished: false, pinnedDay: null });
});

test('a series is finished when recur-until rules out everything after the exdated occurrence', () => {
  expect(anchor('Water start:2026-09-13 frequency:weekly recur-until:2026-10-01 last-done:2026-09-20 exdate:2026-09-27'))
    .toEqual({ start: '2026-09-13', finished: true, pinnedDay: null });
});

test('weekly + weekday set + every:2000 returns quickly with the right date', () => {
  const t = performance.now();
  const a = anchor('Gym start:2026-09-07 frequency:weekly frequency-day:M,W,F every:2000 last-done:2026-09-09');
  expect(performance.now() - t).toBeLessThan(500);
  expect(a).toEqual({ start: '2026-09-11', finished: false, pinnedDay: null });
});

test('every:99999999999 returns quickly for every frequency and never yields NaN', () => {
  for (const line of [
    'V start:2026-09-01 frequency:daily every:99999999999 last-done:2026-09-10',
    'W start:2026-09-13 frequency:weekly every:99999999999 last-done:2026-09-20',
    'G start:2026-09-07 frequency:weekly frequency-day:M,W,F every:99999999999 last-done:2026-09-09',
    'M start:2026-08-15 frequency:monthly every:99999999999 last-done:2026-09-20',
    'Y start:2020-06-10 frequency:yearly every:99999999999 last-done:2026-06-10',
  ]) {
    const t = performance.now();
    const a = anchor(line);
    expect(performance.now() - t).toBeLessThan(500);
    expect(a.start).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(a.pinnedDay).toBeNull();
  }
});

test('a clamped monthly anchor pins the original day-of-month', () => {
  expect(anchor('M start:2026-01-31 frequency:monthly last-done:2026-02-15'))
    .toEqual({ start: '2026-02-28', finished: false, pinnedDay: 31 });
  expect(anchor('M start:2026-01-31T07:00 frequency:monthly last-done:2026-02-15'))
    .toEqual({ start: '2026-02-28T07:00', finished: false, pinnedDay: 31 });
});

test('a clamped yearly anchor pins the original day-of-month', () => {
  expect(anchor('Leap start:2020-02-29 frequency:yearly last-done:2026-03-01'))
    .toEqual({ start: '2027-02-28', finished: false, pinnedDay: 29 });
});

test('an anchor that keeps the original day-of-month is not pinned', () => {
  expect(anchor('Rent start:2026-08-15 frequency:monthly last-done:2026-09-20'))
    .toEqual({ start: '2026-10-15', finished: false, pinnedDay: null });
  expect(anchor('M start:2026-01-31 frequency:monthly last-done:2026-03-01'))
    .toEqual({ start: '2026-03-31', finished: false, pinnedDay: null });
  expect(anchor('Leap start:2020-02-29 frequency:yearly last-done:2027-12-31'))
    .toEqual({ start: '2028-02-29', finished: false, pinnedDay: null });
});

test('frequency-month-day means the series is not pinned', () => {
  expect(anchor('Rent start:2026-08-31 frequency:monthly frequency-month-day:15 last-done:2026-09-20'))
    .toEqual({ start: '2026-10-15', finished: false, pinnedDay: null });
});

test('no re-base (or a finished series) is never pinned', () => {
  expect(anchor('M start:2026-01-31 frequency:monthly'))
    .toEqual({ start: '2026-01-31', finished: false, pinnedDay: null });
  expect(anchor('M start:2026-01-31 frequency:monthly recur-until:2026-02-10 last-done:2026-02-15'))
    .toEqual({ start: '2026-01-31', finished: true, pinnedDay: null });
});
