import { test, expect, describe } from 'bun:test';
import { parseLine } from '../../parser';
import { cleanTitle, decodeNote, isBareTime, parseWall, priorityToNumber, resolveEventEnd, joinNotes } from '../../ics/fields';

describe('cleanTitle', () => {
  test('removes only the known structural keys', () => {
    expect(cleanTitle('Standup start:2026-09-21T09:00 end:2026-09-21T09:15 type:event frequency:weekly frequency-day:M,W,F exdate:2026-09-23 recur-until:2026-12-18 every:2 last-done:2026-09-01 location:@home description:x note:y due:2026-10-01 end-time:10:00 reminders-id:abc'))
      .toBe('Standup');
  });
  test('keeps tags exactly as written', () => {
    expect(cleanTitle('~alex %errand %weekly start:2026-09-12T06:00')).toBe('~alex %errand %weekly');
    expect(cleanTitle('Trip +family @home %birthday')).toBe('Trip +family @home %birthday');
  });
  test('keeps unknown key:value tokens and times in prose', () => {
    expect(cleanTitle('Ward Melville @ Sachem bus:16:00 start:2026-09-24T17:00')).toBe('Ward Melville @ Sachem bus:16:00');
    expect(cleanTitle('Meet Sam at 9:00 start:2026-09-24T09:00')).toBe('Meet Sam at 9:00');
  });
  test('keeps URLs (a value starting with / is not an extension)', () => {
    expect(cleanTitle('Read https://example.com/x start:2026-09-24')).toBe('Read https://example.com/x');
  });
  test('collapses whitespace and returns an empty string when only extensions remain', () => {
    expect(cleanTitle('  a   b  type:event ')).toBe('a b');
    expect(cleanTitle('start:2026-09-24 type:event')).toBe('');
  });
  test('a tab-separated structural token is removed like a space-separated one', () => {
    const task = parseLine('Standup\tstart:2026-09-21T09:00\ttype:event\t~alex', 1);
    expect(cleanTitle(task.text)).toBe('Standup ~alex');
  });
  test('a CRLF-saved line: the trailing \\r never keeps the last structural token in the title', () => {
    const task = parseLine('Standup start:2026-09-21T09:00 type:event\r', 1);
    expect(task.text.endsWith('\r')).toBe(true);
    const title = cleanTitle(task.text);
    expect(title).toBe('Standup');
    expect(title).not.toContain('\r');
    expect(title).not.toContain('type:');
    expect(cleanTitle(parseLine('Buy milk\r', 1).text)).toBe('Buy milk');
  });
});

describe('decodeNote / joinNotes', () => {
  test('underscores become spaces, commas stay', () => {
    expect(decodeNote('Bring_forms,_insurance_card')).toBe('Bring forms, insurance card');
  });
  test('joinNotes skips empties and joins with a newline', () => {
    expect(joinNotes(['a', null, undefined, '', 'b'])).toBe('a\nb');
    expect(joinNotes([null, undefined])).toBeNull();
  });
  test('joinNotes drops parts that are blank after trimming, and is null when nothing real remains', () => {
    expect(joinNotes([' ', '\t'])).toBeNull();
    expect(joinNotes([' ', 'a', '  '])).toBe('a');
    expect(joinNotes([' padded '])).toBe(' padded ');
  });
});

describe('parseWall', () => {
  test('date-only and date-time', () => {
    expect(parseWall('2026-09-22')).toEqual({ date: '2026-09-22', time: null });
    expect(parseWall('2026-09-22T14:30')).toEqual({ date: '2026-09-22', time: '14:30' });
  });
  test('rejects anything else', () => {
    expect(parseWall(undefined)).toBeNull();
    expect(parseWall('17:30')).toBeNull();
    expect(parseWall('2026-9-2')).toBeNull();
  });
  // Controller ruling: validate calendar dates
  test('accepts valid leap year date (2028-02-29)', () => {
    expect(parseWall('2028-02-29')).toEqual({ date: '2028-02-29', time: null });
  });
  test('rejects invalid leap year date (2027-02-29)', () => {
    expect(parseWall('2027-02-29')).toBeNull();
  });
  test('rejects out-of-range month (2026-13-45)', () => {
    expect(parseWall('2026-13-45')).toBeNull();
  });
  test('rejects invalid day-of-month (2026-02-30)', () => {
    expect(parseWall('2026-02-30')).toBeNull();
  });
  test('rejects invalid day for April (2026-04-31)', () => {
    expect(parseWall('2026-04-31')).toBeNull();
  });
  test('rejects out-of-range time hour (2026-09-22T25:00)', () => {
    expect(parseWall('2026-09-22T25:00')).toBeNull();
  });
  test('rejects out-of-range time minute (2026-09-22T12:60)', () => {
    expect(parseWall('2026-09-22T12:60')).toBeNull();
  });
  test('accepts valid times', () => {
    expect(parseWall('2026-09-22T00:00')).toEqual({ date: '2026-09-22', time: '00:00' });
    expect(parseWall('2026-09-22T23:59')).toEqual({ date: '2026-09-22', time: '23:59' });
  });
});

describe('priorityToNumber', () => {
  test('A..I map to 1..9, J..Z to 9, none to null', () => {
    expect(priorityToNumber('A')).toBe(1);
    expect(priorityToNumber('E')).toBe(5);
    expect(priorityToNumber('I')).toBe(9);
    expect(priorityToNumber('Z')).toBe(9);
    expect(priorityToNumber(undefined)).toBeNull();
  });
});

describe('resolveEventEnd', () => {
  const timed = { date: '2026-09-22', time: '14:30' };
  const allDay = { date: '2026-10-05', time: null };
  test('no end', () => {
    expect(resolveEventEnd(timed, {})).toEqual({ end: null, endBeforeStart: false });
  });
  test('same-day date-time end is kept', () => {
    expect(resolveEventEnd(timed, { end: '2026-09-22T15:30' }).end).toEqual({ date: '2026-09-22', time: '15:30' });
  });
  test('a bare HH:MM end is a same-day end time', () => {
    expect(resolveEventEnd(timed, { end: '15:30' }).end).toEqual({ date: '2026-09-22', time: '15:30' });
  });
  test('end-time is used when end is absent, or has no time', () => {
    expect(resolveEventEnd(timed, { 'end-time': '16:00' }).end).toEqual({ date: '2026-09-22', time: '16:00' });
    expect(resolveEventEnd(timed, { end: '2026-09-23', 'end-time': '16:00' }).end).toEqual({ date: '2026-09-23', time: '16:00' });
  });
  test('a date-only end on a timed event uses the start time-of-day', () => {
    expect(resolveEventEnd(timed, { end: '2026-09-24' }).end).toEqual({ date: '2026-09-24', time: '14:30' });
  });
  test('all-day events keep the end date verbatim and drop any time', () => {
    expect(resolveEventEnd(allDay, { end: '2026-10-08' }).end).toEqual({ date: '2026-10-08', time: null });
    expect(resolveEventEnd(allDay, { end: '2026-10-08T10:00' }).end).toEqual({ date: '2026-10-08', time: null });
    expect(resolveEventEnd(allDay, { end: '2026-10-05' }).end).toEqual({ date: '2026-10-05', time: null });
  });
  test('an end before the start is dropped and flagged', () => {
    expect(resolveEventEnd(timed, { end: '2026-09-22T13:00' })).toEqual({ end: null, endBeforeStart: true });
    expect(resolveEventEnd(allDay, { end: '2026-10-01' })).toEqual({ end: null, endBeforeStart: true });
  });
  test('a bare end time on an all-day event is ignored', () => {
    expect(resolveEventEnd(allDay, { end: '10:00' })).toEqual({ end: null, endBeforeStart: false });
  });
  // Controller ruling: validate times in bare time checks
  test('bare time with out-of-range hour (99:99) is treated as absent', () => {
    expect(resolveEventEnd(timed, { end: '99:99' })).toEqual({ end: null, endBeforeStart: false });
  });
  test('bare time with out-of-range hour 24 is treated as absent', () => {
    expect(resolveEventEnd(timed, { end: '24:00' })).toEqual({ end: null, endBeforeStart: false });
  });
  test('end-time with out-of-range hour (24:00) is treated as absent', () => {
    expect(resolveEventEnd(timed, { 'end-time': '24:00' })).toEqual({ end: null, endBeforeStart: false });
  });
  test('end-time with out-of-range minute (12:60) is treated as absent', () => {
    expect(resolveEventEnd(timed, { 'end-time': '12:60' })).toEqual({ end: null, endBeforeStart: false });
  });
});

describe('isBareTime', () => {
  test('accepts a real HH:MM', () => {
    expect(isBareTime('00:00')).toBe(true);
    expect(isBareTime('09:30')).toBe(true);
    expect(isBareTime('23:59')).toBe(true);
  });
  test('rejects out-of-range and malformed values', () => {
    for (const v of ['24:00', '12:60', '25:99', '99:99', '9:30', '09:3', '09:30:00', 'garbage', '', '2026-09-22', '2026-09-22T09:30']) {
      expect(isBareTime(v)).toBe(false);
    }
  });
});
