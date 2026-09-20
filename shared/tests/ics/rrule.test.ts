import { test, expect, describe } from 'bun:test';
import { buildRRule } from '../../ics/rrule';

const r = (ext: Record<string, string>) => buildRRule(ext);

describe('buildRRule: basics', () => {
  test('no frequency means no rule', () => {
    expect(r({})).toEqual({ rrule: null, unsupported: null, ignored: [] });
  });
  test('plain frequencies', () => {
    expect(r({ frequency: 'daily' }).rrule).toBe('FREQ=DAILY');
    expect(r({ frequency: 'yearly' }).rrule).toBe('FREQ=YEARLY');
  });
  test('every > 1 becomes INTERVAL, every 1 does not', () => {
    expect(r({ frequency: 'daily', every: '3' }).rrule).toBe('FREQ=DAILY;INTERVAL=3');
    expect(r({ frequency: 'daily', every: '1' }).rrule).toBe('FREQ=DAILY');
  });
  test('an invalid every is unsupported', () => {
    expect(r({ frequency: 'daily', every: '0' })).toEqual({ rrule: null, unsupported: 'every:0', ignored: [] });
  });
  test('an unknown frequency is unsupported', () => {
    expect(r({ frequency: 'hourly' }).unsupported).toBe('frequency:hourly');
  });
});

describe('buildRRule: weekly days', () => {
  test('frequency-day maps to BYDAY in the given order', () => {
    expect(r({ frequency: 'weekly', 'frequency-day': 'M,W,F' }).rrule).toBe('FREQ=WEEKLY;BYDAY=MO,WE,FR');
    expect(r({ frequency: 'weekly', 'frequency-day': 'Th,Sat,Sun' }).rrule).toBe('FREQ=WEEKLY;BYDAY=TH,SA,SU');
  });
  test('interval comes before BYDAY', () => {
    expect(r({ frequency: 'weekly', every: '2', 'frequency-day': 'T' }).rrule).toBe('FREQ=WEEKLY;INTERVAL=2;BYDAY=TU');
  });
  test('an unknown day code is unsupported', () => {
    expect(r({ frequency: 'weekly', 'frequency-day': 'M,Xx' })).toEqual({ rrule: null, unsupported: 'frequency-day:M,Xx', ignored: [] });
  });
  test('frequency-day on a monthly rule is ignored, the rule still produced', () => {
    expect(r({ frequency: 'monthly', 'frequency-day': 'M' })).toEqual({ rrule: 'FREQ=MONTHLY', unsupported: null, ignored: ['frequency-day:M'] });
  });
});

describe('buildRRule: month day', () => {
  test('a number becomes BYMONTHDAY', () => {
    expect(r({ frequency: 'monthly', 'frequency-month-day': '15' }).rrule).toBe('FREQ=MONTHLY;BYMONTHDAY=15');
  });
  test('an out-of-range number is unsupported', () => {
    expect(r({ frequency: 'monthly', 'frequency-month-day': '32' }).unsupported).toBe('frequency-month-day:32');
  });
  test.each([
    ['first-wednesday', 'BYDAY=1WE'],
    ['second-sunday', 'BYDAY=2SU'],
    ['third-monday', 'BYDAY=3MO'],
    ['fourth-friday', 'BYDAY=4FR'],
    ['last-friday', 'BYDAY=-1FR'],
    ['first-day', 'BYMONTHDAY=1'],
    ['fourth-day', 'BYMONTHDAY=4'],
    ['last-day', 'BYMONTHDAY=-1'],
    ['third-weekday', 'BYDAY=MO,TU,WE,TH,FR;BYSETPOS=3'],
    ['last-weekday', 'BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1'],
    ['first-weekend-day', 'BYDAY=SA,SU;BYSETPOS=1'],
    ['last-weekend-day', 'BYDAY=SA,SU;BYSETPOS=-1'],
  ])('positional %s', (value, expected) => {
    expect(r({ frequency: 'monthly', 'frequency-month-day': value }).rrule).toBe(`FREQ=MONTHLY;${expected}`);
  });
  test('fifth-* cannot be represented and is reported, not dropped', () => {
    expect(r({ frequency: 'monthly', 'frequency-month-day': 'fifth-friday' })).toEqual({
      rrule: null, unsupported: 'frequency-month-day:fifth-friday', ignored: [],
    });
  });
  test('a yearly rule may carry frequency-month-day and frequency-month', () => {
    expect(r({ frequency: 'yearly', 'frequency-month-day': 'first-monday', 'frequency-month': 'Nov' }).rrule)
      .toBe('FREQ=YEARLY;BYDAY=1MO;BYMONTH=11');
    expect(r({ frequency: 'yearly', 'frequency-month': 'Jan,Jul' }).rrule).toBe('FREQ=YEARLY;BYMONTH=1,7');
  });
  test('frequency-month-day on a weekly rule and frequency-month on a monthly rule are ignored', () => {
    expect(r({ frequency: 'weekly', 'frequency-month-day': '1' }).ignored).toEqual(['frequency-month-day:1']);
    expect(r({ frequency: 'monthly', 'frequency-month': 'Jan' }).ignored).toEqual(['frequency-month:Jan']);
  });
  test('a bad month name is unsupported', () => {
    expect(r({ frequency: 'yearly', 'frequency-month': 'Foo' }).unsupported).toBe('frequency-month:Foo');
  });
});

describe('buildRRule: UNTIL', () => {
  test('recur-until becomes a date-only UNTIL, last', () => {
    expect(r({ frequency: 'weekly', 'frequency-day': 'M,W,F', 'recur-until': '2026-12-18' }).rrule)
      .toBe('FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261218');
  });
  test('a malformed recur-until is ignored and reported', () => {
    expect(r({ frequency: 'weekly', 'recur-until': 'soon' })).toEqual({ rrule: 'FREQ=WEEKLY', unsupported: null, ignored: ['recur-until:soon'] });
  });
  test('an impossible calendar date in recur-until is ignored and reported', () => {
    expect(r({ frequency: 'weekly', 'recur-until': '2026-13-45' })).toEqual({ rrule: 'FREQ=WEEKLY', unsupported: null, ignored: ['recur-until:2026-13-45'] });
    expect(r({ frequency: 'weekly', 'recur-until': '2026-02-30' })).toEqual({ rrule: 'FREQ=WEEKLY', unsupported: null, ignored: ['recur-until:2026-02-30'] });
  });
  test('a valid leap day in recur-until produces UNTIL', () => {
    expect(r({ frequency: 'weekly', 'recur-until': '2028-02-29' }).rrule).toBe('FREQ=WEEKLY;UNTIL=20280229');
  });
});

describe('buildRRule: prototype-inherited keys', () => {
  test('prototype-inherited day-code keys are unsupported', () => {
    expect(r({ frequency: 'weekly', 'frequency-day': 'constructor' })).toEqual({
      rrule: null, unsupported: 'frequency-day:constructor', ignored: [],
    });
  });
  test('prototype-inherited position keys are unsupported', () => {
    expect(r({ frequency: 'monthly', 'frequency-month-day': 'first-constructor' })).toEqual({
      rrule: null, unsupported: 'frequency-month-day:first-constructor', ignored: [],
    });
    expect(r({ frequency: 'monthly', 'frequency-month-day': '__proto__-day' })).toEqual({
      rrule: null, unsupported: 'frequency-month-day:__proto__-day', ignored: [],
    });
  });
  test('prototype-inherited month names are unsupported', () => {
    expect(r({ frequency: 'yearly', 'frequency-month': 'toString' })).toEqual({
      rrule: null, unsupported: 'frequency-month:toString', ignored: [],
    });
  });
});
