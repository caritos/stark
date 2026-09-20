import { test, expect, describe } from 'bun:test';
import { escapeText, formatDate, formatDateTime, serializeEvent, serializeReminder, serializeCalendar } from '../../ics/text';
import type { IcsEvent, IcsReminder } from '../../ics/types';

const baseEvent: IcsEvent = {
  uid: 'L01', title: 'Dentist', start: { date: '2026-09-22', time: '14:30' },
  end: { date: '2026-09-22', time: '15:30' }, allDay: false,
  notes: 'Bring forms, insurance card', location: '123 Main St', rrule: null, exdates: [],
};

const baseReminder: IcsReminder = {
  uid: 'L11', title: 'Take out trash', due: { date: '2026-09-18', time: null }, notes: null, priority: null,
  completed: true, completedDate: { date: '2026-09-18', time: null }, rrule: null, exdates: [],
};

describe('escapeText', () => {
  test('escapes backslash, semicolon, comma and newline, backslash first', () => {
    expect(escapeText('a\\b;c,d\ne')).toBe('a\\\\b\\;c\\,d\\ne');
  });
  test('leaves emoji and apostrophes alone', () => {
    expect(escapeText("Mom's 🍜")).toBe("Mom's 🍜");
  });
});

describe('date formatting', () => {
  test('formatDate drops the dashes', () => {
    expect(formatDate('2026-09-22')).toBe('20260922');
  });
  test('formatDateTime writes floating local time', () => {
    expect(formatDateTime({ date: '2026-09-22', time: '14:30' })).toBe('20260922T143000');
  });
  test('formatDateTime treats a date-only value as midnight', () => {
    expect(formatDateTime({ date: '2026-09-18', time: null })).toBe('20260918T000000');
  });
});

describe('serializeEvent', () => {
  test('timed event with end, notes and location, in the Swift serializer property order', () => {
    expect(serializeEvent(baseEvent)).toBe([
      'BEGIN:VEVENT', 'UID:L01', 'SUMMARY:Dentist', 'DTSTART:20260922T143000', 'DTEND:20260922T153000',
      'DESCRIPTION:Bring forms\\, insurance card', 'LOCATION:123 Main St', 'END:VEVENT',
    ].join('\r\n'));
  });
  test('all-day event uses VALUE=DATE on DTSTART, DTEND and EXDATE', () => {
    const e: IcsEvent = {
      ...baseEvent, uid: 'L03', title: 'Conference', allDay: true, notes: null, location: null,
      start: { date: '2026-10-05', time: null }, end: { date: '2026-10-08', time: null },
      rrule: 'FREQ=YEARLY', exdates: [{ date: '2027-10-05', time: null }],
    };
    expect(serializeEvent(e)).toBe([
      'BEGIN:VEVENT', 'UID:L03', 'SUMMARY:Conference', 'DTSTART;VALUE=DATE:20261005',
      'DTEND;VALUE=DATE:20261008', 'RRULE:FREQ=YEARLY', 'EXDATE;VALUE=DATE:20271005', 'END:VEVENT',
    ].join('\r\n'));
  });
  test('one EXDATE line per exception, at the anchor time-of-day', () => {
    const e: IcsEvent = {
      ...baseEvent, end: null, notes: null, location: null, rrule: 'FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261218',
      exdates: [{ date: '2026-09-23', time: '14:30' }, { date: '2026-09-25', time: '14:30' }],
    };
    const lines = serializeEvent(e).split('\r\n');
    expect(lines).toContain('EXDATE:20260923T143000');
    expect(lines).toContain('EXDATE:20260925T143000');
  });
  test('escapes the title', () => {
    const e: IcsEvent = { ...baseEvent, title: 'Lunch; with, commas \\ backslash 🍜', end: null, notes: null, location: null };
    expect(serializeEvent(e)).toContain('SUMMARY:Lunch\\; with\\, commas \\\\ backslash 🍜');
  });
});

describe('serializeReminder', () => {
  test('completed reminder: STATUS then COMPLETED, no DESCRIPTION/PRIORITY', () => {
    expect(serializeReminder(baseReminder)).toBe([
      'BEGIN:VTODO', 'UID:L11', 'SUMMARY:Take out trash', 'DUE:20260918T000000',
      'STATUS:COMPLETED', 'COMPLETED:20260918T000000', 'END:VTODO',
    ].join('\r\n'));
  });
  test('open reminder with priority and RRULE, in property order', () => {
    const r: IcsReminder = { ...baseReminder, uid: 'L09', title: 'Call', completed: false, completedDate: null,
      priority: 1, notes: 'n', rrule: 'FREQ=MONTHLY', due: { date: '2026-09-25', time: '10:00' } };
    expect(serializeReminder(r)).toBe([
      'BEGIN:VTODO', 'UID:L09', 'SUMMARY:Call', 'DUE:20260925T100000', 'DESCRIPTION:n', 'PRIORITY:1',
      'STATUS:NEEDS-ACTION', 'RRULE:FREQ=MONTHLY', 'END:VTODO',
    ].join('\r\n'));
  });
  test('undated reminder has no DUE line', () => {
    const r: IcsReminder = { ...baseReminder, due: null, completed: false, completedDate: null };
    expect(serializeReminder(r)).not.toContain('DUE');
  });
  test('reminder EXDATE is always a date-time, never VALUE=DATE', () => {
    const r: IcsReminder = { ...baseReminder, completed: false, completedDate: null, rrule: 'FREQ=WEEKLY',
      exdates: [{ date: '2026-09-23', time: null }] };
    expect(serializeReminder(r)).toContain('EXDATE:20260923T000000');
  });
});

describe('serializeCalendar', () => {
  test('wraps events then reminders, CRLF endings and a trailing CRLF', () => {
    const text = serializeCalendar([baseEvent], [baseReminder]);
    expect(text.startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Stark//EN\r\nBEGIN:VEVENT')).toBe(true);
    expect(text.indexOf('BEGIN:VEVENT')).toBeLessThan(text.indexOf('BEGIN:VTODO'));
    expect(text.endsWith('END:VTODO\r\nEND:VCALENDAR\r\n')).toBe(true);
    expect(text.replace(/\r\n/g, '')).not.toContain('\n');
  });
});
