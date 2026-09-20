import { test, expect, describe } from 'bun:test';
import { parseLine } from '../../parser';
import { convertTask } from '../../ics/convert';

const conv = (line: string, n = 1) => convertTask(parseLine(line, n), 'U');
const ev = (line: string) => { const c = conv(line); if (c.kind !== 'event') throw new Error('expected event'); return c; };
const rem = (line: string) => { const c = conv(line); if (c.kind !== 'reminder') throw new Error('expected reminder'); return c; };

describe('events', () => {
  test('timed event with end, location and description', () => {
    const c = ev('2026-09-01 Dentist start:2026-09-22T14:30 end:2026-09-22T15:30 type:event location:123_Main_St description:Bring_forms,_insurance_card');
    expect(c.source).toBe('open-event');
    expect(c.event).toEqual({
      uid: 'U', title: 'Dentist', start: { date: '2026-09-22', time: '14:30' }, end: { date: '2026-09-22', time: '15:30' },
      allDay: false, notes: 'Bring forms, insurance card', location: '123 Main St', rrule: null, exdates: [],
    });
    expect(c.entries).toEqual([]);
  });
  test('date-only start is an all-day event with no end', () => {
    const c = ev('Company holiday start:2026-10-12 type:event');
    expect(c.event.allDay).toBe(true);
    expect(c.event.end).toBeNull();
  });
  test('multi-day all-day event keeps the end date verbatim', () => {
    expect(ev('Conference start:2026-10-05 end:2026-10-08 type:event').event.end).toEqual({ date: '2026-10-08', time: null });
  });
  test('birthday and anniversary buckets; yearly rule; original year kept', () => {
    const b = ev("Mom's birthday %birthday start:1975-05-15 type:birthday frequency:yearly");
    expect(b.source).toBe('open-birthday');
    expect(b.event.title).toBe("Mom's birthday %birthday");
    expect(b.event.start.date).toBe('1975-05-15');
    expect(b.event.rrule).toBe('FREQ=YEARLY');
    expect(ev('Anniv start:2004-05-01 type:anniversary frequency:yearly').source).toBe('open-anniversary');
  });
  test('a %birthday tag without type: is still a birthday event (parser alias)', () => {
    const c = ev('Sam %birthday start:2000-01-02 frequency:yearly');
    expect(c.source).toBe('open-birthday');
  });
  test('recurring event: BYDAY, UNTIL and EXDATEs at the start time-of-day, event anchor NOT re-based', () => {
    const c = ev('Standup start:2026-09-21T09:00 end:2026-09-21T09:15 type:event frequency:weekly frequency-day:M,W,F exdate:2026-09-23,2026-09-25 recur-until:2026-12-18 last-done:2026-09-30');
    expect(c.event.rrule).toBe('FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261218');
    expect(c.event.exdates).toEqual([{ date: '2026-09-23', time: '09:00' }, { date: '2026-09-25', time: '09:00' }]);
    expect(c.event.start).toEqual({ date: '2026-09-21', time: '09:00' });
  });
  test('unsupported recurrence imports a one-off at its start and reports it', () => {
    const c = ev('Fifth Friday start:2026-10-30T18:00 type:event frequency:monthly frequency-month-day:fifth-friday exdate:2026-11-27');
    expect(c.event.rrule).toBeNull();
    expect(c.event.exdates).toEqual([]);
    expect(c.entries).toEqual([{ line: 1, kind: 'unsupported-recurrence', detail: 'frequency-month-day:fifth-friday' }]);
  });
  test('an ignored extension is reported but the rule is kept', () => {
    const c = ev('Odd start:2026-09-01T10:00 type:event frequency:monthly frequency-day:M');
    expect(c.event.rrule).toBe('FREQ=MONTHLY');
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'frequency-day:M' }]);
  });
  test('an end before the start is dropped and reported', () => {
    const c = ev('Bad start:2026-09-22T14:30 end:2026-09-22T13:00 type:event');
    expect(c.event.end).toBeNull();
    expect(c.entries[0]).toEqual({ line: 1, kind: 'end-before-start', detail: 'end:2026-09-22T13:00' });
  });
  test('a typed line without a usable start becomes an undated reminder, reported', () => {
    const c = rem('Lost type:event start:17:30');
    expect(c.reminder.due).toBeNull();
    expect(c.source).toBe('open-event');
    expect(c.entries.map(e => e.kind)).toContain('event-without-start');
    expect(c.entries.map(e => e.kind)).toContain('undated');
  });
  test('an empty title becomes (untitled) and is reported', () => {
    const c = ev('start:2026-09-22T10:00 type:event');
    expect(c.event.title).toBe('(untitled)');
    expect(c.entries.map(e => e.kind)).toContain('untitled');
  });
});

describe('open reminders', () => {
  test('priority, tags and unknown tokens; start becomes DUE', () => {
    const c = rem('(A) Call insurance start:2026-09-25T10:00 ~sam %phone bus:16:00');
    expect(c.source).toBe('open-task');
    expect(c.reminder.title).toBe('Call insurance ~sam %phone bus:16:00');
    expect(c.reminder.due).toEqual({ date: '2026-09-25', time: '10:00' });
    expect(c.reminder.priority).toBe(1);
    expect(c.reminder.completed).toBe(false);
  });
  test('due: is used when there is no start:', () => {
    expect(rem('Pay bill due:2026-10-01').reminder.due).toEqual({ date: '2026-10-01', time: null });
  });
  test('start wins; a different due: date is preserved in the notes', () => {
    const c = rem('Report start:2026-09-20 due:2026-10-01');
    expect(c.reminder.due).toEqual({ date: '2026-09-20', time: null });
    expect(c.reminder.notes).toBe('Due: 2026-10-01');
  });
  test('an undated reminder is kept and reported', () => {
    const c = rem('2026-09-03 Buy milk');
    expect(c.reminder.due).toBeNull();
    expect(c.entries).toEqual([{ line: 1, kind: 'undated', detail: 'Buy milk' }]);
  });
  test('a reminder location becomes a Location: note line, before the description', () => {
    expect(rem('Fix bike start:2026-09-20 location:@home description:Check_tires').reminder.notes).toBe('Location: @home\nCheck tires');
  });
  test('a recurring reminder is re-based past last-done and keeps its rule', () => {
    const c = rem('2026-09-02 Water plants start:2026-09-13T07:00 frequency:weekly every:2 last-done:2026-09-20');
    expect(c.reminder.due).toEqual({ date: '2026-09-27', time: '07:00' });
    expect(c.reminder.rrule).toBe('FREQ=WEEKLY;INTERVAL=2');
    expect(c.entries).toEqual([]);
  });
  test('a finished series keeps its start and is reported', () => {
    const c = rem('Old start:2026-01-05 frequency:weekly recur-until:2026-02-01 last-done:2026-03-01');
    expect(c.reminder.due).toEqual({ date: '2026-01-05', time: null });
    expect(c.entries).toEqual([{ line: 1, kind: 'finished-series', detail: 'recur-until:2026-02-01' }]);
  });
  test('a recurring reminder carries EXDATEs at its own time-of-day', () => {
    const c = rem('Trash start:2026-09-21T06:00 frequency:weekly exdate:2026-09-28');
    expect(c.reminder.exdates).toEqual([{ date: '2026-09-28', time: '06:00' }]);
  });
  test('frequency without start: is reported and imported as a one-off', () => {
    const c = rem('Vague due:2026-10-01 frequency:weekly');
    expect(c.reminder.rrule).toBeNull();
    expect(c.entries[0]!.kind).toBe('unsupported-recurrence');
  });
});

describe('completed lines', () => {
  test('plain completion copy: due and completed on the x date', () => {
    const c = rem('x 2026-09-18 2026-09-01 Take out trash');
    expect(c.source).toBe('done-plain');
    expect(c.reminder).toMatchObject({ title: 'Take out trash', completed: true, priority: null,
      due: { date: '2026-09-18', time: null }, completedDate: { date: '2026-09-18', time: null } });
  });
  test('completed with a start: due is the start', () => {
    const c = rem('x 2026-08-30 Renew passport start:2026-08-25');
    expect(c.source).toBe('done-with-start');
    expect(c.reminder.due).toEqual({ date: '2026-08-25', time: null });
    expect(c.reminder.completedDate).toEqual({ date: '2026-08-30', time: null });
  });
  test('completed typed one-off is a past event', () => {
    const c = ev('x 2026-09-10 Old dentist start:2026-09-09T10:00 end:2026-09-09T11:00 type:event');
    expect(c.source).toBe('done-event');
    expect(c.event.title).toBe('Old dentist');
    expect(c.event.rrule).toBeNull();
  });
  test('completed typed recurring line is a live/finished recurring event', () => {
    const c = ev('x 2026-01-01 Anniv start:2004-05-01 type:anniversary frequency:yearly recur-until:2025-12-31');
    expect(c.source).toBe('done-recurring');
    expect(c.event.rrule).toBe('FREQ=YEARLY;UNTIL=20251231');
  });
  test('completed untyped recurring line is a NOT-completed recurring reminder re-based past the x date', () => {
    const c = rem('x 2026-09-20 2026-09-01 Water start:2026-09-13 frequency:weekly');
    expect(c.source).toBe('done-recurring');
    expect(c.reminder.completed).toBe(false);
    expect(c.reminder.due).toEqual({ date: '2026-09-27', time: null });
  });
});

describe('ruling: a re-based clamped series keeps its original day of month', () => {
  test('monthly Jan 31 re-based to Feb 28 is pinned to BYMONTHDAY=31', () => {
    const c = rem('Rent start:2026-01-31 frequency:monthly last-done:2026-02-15');
    expect(c.reminder.due).toEqual({ date: '2026-02-28', time: null });
    expect(c.reminder.rrule).toBe('FREQ=MONTHLY;BYMONTHDAY=31');
    expect(c.entries).toEqual([]);
  });
  test('yearly Feb 29 re-based to Feb 28 is pinned to BYMONTHDAY=29', () => {
    const c = rem('Leap start:2020-02-29 frequency:yearly last-done:2026-03-01');
    expect(c.reminder.due).toEqual({ date: '2027-02-28', time: null });
    expect(c.reminder.rrule).toBe('FREQ=YEARLY;BYMONTHDAY=29');
    expect(c.entries).toEqual([]);
  });
  test('a timed clamped series keeps its time-of-day and the pinned day', () => {
    const c = rem('Rent start:2026-01-31T09:30 frequency:monthly every:1 last-done:2026-02-15');
    expect(c.reminder.due).toEqual({ date: '2026-02-28', time: '09:30' });
    expect(c.reminder.rrule).toBe('FREQ=MONTHLY;BYMONTHDAY=31');
  });
  test('a non-clamped re-base is left unpinned', () => {
    const c = rem('Water start:2026-09-13 frequency:weekly last-done:2026-09-20');
    expect(c.reminder.rrule).toBe('FREQ=WEEKLY');
    const m = rem('Bills start:2026-01-15 frequency:monthly last-done:2026-02-20');
    expect(m.reminder.due).toEqual({ date: '2026-03-15', time: null });
    expect(m.reminder.rrule).toBe('FREQ=MONTHLY');
  });
  test('a task that already has frequency-month-day is untouched', () => {
    const c = rem('Pay start:2026-01-15 frequency:monthly frequency-month-day:15 last-done:2026-02-20');
    expect(c.reminder.rrule).toBe('FREQ=MONTHLY;BYMONTHDAY=15');
    const d = rem('Last start:2026-01-31 frequency:monthly frequency-month-day:last-day last-done:2026-02-15');
    expect(d.reminder.rrule).toBe('FREQ=MONTHLY;BYMONTHDAY=-1');
  });
  test('the pinned encoding never mutates the task and never duplicates report entries', () => {
    const task = parseLine('Rent start:2026-01-31 frequency:monthly frequency-day:M last-done:2026-02-15', 1);
    const before = { ...task.extensions };
    const c = convertTask(task, 'U');
    expect(task.extensions).toEqual(before);
    if (c.kind !== 'reminder') throw new Error('expected reminder');
    expect(c.reminder.rrule).toBe('FREQ=MONTHLY;BYMONTHDAY=31');
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'frequency-day:M' }]);
  });
});

describe('ruling: impossible exdates are skipped and reported', () => {
  test('recurring reminder: one valid exdate carried, one reported', () => {
    const c = rem('Trash start:2026-09-21T06:00 frequency:weekly exdate:2026-09-28,2026-13-45');
    expect(c.reminder.exdates).toEqual([{ date: '2026-09-28', time: '06:00' }]);
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'exdate:2026-13-45' }]);
  });
  test('recurring event: one valid exdate carried, one reported', () => {
    const c = ev('Standup start:2026-09-21T09:00 type:event frequency:weekly exdate:2026-09-28,2026-13-45');
    expect(c.event.exdates).toEqual([{ date: '2026-09-28', time: '09:00' }]);
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'exdate:2026-13-45' }]);
  });
  test('an impossible day (Feb 30) is also skipped and reported, with the task line number', () => {
    const c = convertTask(parseLine('Class start:2026-09-21 type:event frequency:daily exdate:2026-02-30', 7), 'U');
    if (c.kind !== 'event') throw new Error('expected event');
    expect(c.event.exdates).toEqual([]);
    expect(c.entries).toEqual([{ line: 7, kind: 'ignored-extension', detail: 'exdate:2026-02-30' }]);
  });
  test('a non-date exdate value is skipped and reported', () => {
    const c = rem('Trash start:2026-09-21 frequency:weekly exdate:soon');
    expect(c.reminder.exdates).toEqual([]);
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'exdate:soon' }]);
  });
});

describe('fix round 1: recurrence requires a parseable start', () => {
  test('an open line with an impossible start is a one-off and reports both problems', () => {
    const c = rem('Foo start:2026-13-45 frequency:weekly');
    expect(c.source).toBe('open-task');
    expect(c.reminder).toMatchObject({ due: null, rrule: null, exdates: [], completed: false });
    expect(c.entries).toEqual([
      { line: 1, kind: 'ignored-extension', detail: 'start:2026-13-45' },
      { line: 1, kind: 'unsupported-recurrence', detail: 'frequency:weekly with unusable start:2026-13-45' },
      { line: 1, kind: 'undated', detail: 'Foo' },
    ]);
  });
  test('a done line with an impossible start is a completed one-off due on the x date', () => {
    const c = rem('x 2026-01-01 Foo start:2026-13-45 frequency:weekly');
    expect(c.source).toBe('done-recurring');
    expect(c.reminder).toMatchObject({
      due: { date: '2026-01-01', time: null }, completed: true, completedDate: { date: '2026-01-01', time: null },
      rrule: null, exdates: [],
    });
    expect(c.entries).toEqual([
      { line: 1, kind: 'ignored-extension', detail: 'start:2026-13-45' },
      { line: 1, kind: 'unsupported-recurrence', detail: 'frequency:weekly with unusable start:2026-13-45' },
    ]);
  });
  test('a typed birthday with an impossible start is an undated one-off, reported once per problem', () => {
    const c = rem('Foo type:birthday start:1975-02-30 frequency:yearly');
    expect(c.source).toBe('open-birthday');
    expect(c.reminder).toMatchObject({ due: null, rrule: null, exdates: [], completed: false });
    expect(c.entries).toEqual([
      { line: 1, kind: 'event-without-start', detail: 'start:1975-02-30' },
      { line: 1, kind: 'unsupported-recurrence', detail: 'frequency:yearly with unusable start:1975-02-30' },
      { line: 1, kind: 'undated', detail: 'Foo' },
    ]);
  });
  test('frequency with no start at all keeps the "without start:" wording', () => {
    const c = rem('Vague due:2026-10-01 frequency:weekly');
    expect(c.reminder).toMatchObject({ due: { date: '2026-10-01', time: null }, rrule: null, completed: false });
    expect(c.entries).toEqual([{ line: 1, kind: 'unsupported-recurrence', detail: 'frequency:weekly without start:' }]);
  });
});

describe('fix round 1: a done line is completed unless a valid RRULE is emitted', () => {
  test('inexpressible recurrence on a done line is a completed reminder due at its start', () => {
    const c = rem('x 2026-01-01 T start:2026-01-05 frequency:monthly frequency-month-day:fifth-friday');
    expect(c.reminder).toMatchObject({
      due: { date: '2026-01-05', time: null }, completed: true, completedDate: { date: '2026-01-01', time: null }, rrule: null,
    });
    expect(c.entries).toEqual([{ line: 1, kind: 'unsupported-recurrence', detail: 'frequency-month-day:fifth-friday' }]);
  });
  test('a done line with a valid series stays an open recurring reminder', () => {
    const c = rem('x 2026-09-20 Water start:2026-09-13 frequency:weekly');
    expect(c.reminder).toMatchObject({ completed: false, completedDate: null, rrule: 'FREQ=WEEKLY' });
  });
});

describe('fix round 1: unparseable structural values are reported', () => {
  test('done line with an impossible start time uses the x date and reports the start', () => {
    const c = rem('x 2026-01-01 T start:2026-01-05T25:00');
    expect(c.reminder).toMatchObject({ due: { date: '2026-01-01', time: null }, completed: true });
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'start:2026-01-05T25:00' }]);
  });
  test('an impossible start falls back to due: and is reported', () => {
    const c = rem('Foo start:2026-13-45 due:2026-10-01');
    expect(c.reminder.due).toEqual({ date: '2026-10-01', time: null });
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'start:2026-13-45' }]);
  });
  test('an impossible due: is dropped and reported', () => {
    const c = rem('T start:2026-01-05 due:2026-13-45');
    expect(c.reminder.due).toEqual({ date: '2026-01-05', time: null });
    expect(c.reminder.notes).toBeNull();
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'due:2026-13-45' }]);
  });
  test('an out-of-range end-time is dropped and reported', () => {
    const c = ev('E start:2026-09-22T10:00 type:event end-time:99:99');
    expect(c.event.end).toBeNull();
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'end-time:99:99' }]);
  });
  test('a non-time end-time is dropped and reported', () => {
    const c = ev('E start:2026-09-22T10:00 type:event end-time:garbage');
    expect(c.event.end).toBeNull();
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'end-time:garbage' }]);
  });
  test('an out-of-range bare end: is dropped and reported', () => {
    const c = ev('E start:2026-09-22T10:00 type:event end:25:99');
    expect(c.event.end).toBeNull();
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'end:25:99' }]);
  });
  test('an impossible end: date is dropped and reported', () => {
    const c = ev('E start:2026-10-05 type:event end:2026-10-32');
    expect(c.event.end).toBeNull();
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'end:2026-10-32' }]);
  });
  test('VALID bare end: / end-time: on an all-day event are ignored by design, without an entry', () => {
    const c = ev('E start:2026-10-12 type:event end:09:30 end-time:10:00');
    expect(c.event.end).toBeNull();
    expect(c.entries).toEqual([]);
  });
  test('an invalid end-time on an all-day event is still reported', () => {
    const c = ev('E start:2026-10-12 type:event end-time:99:99');
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'end-time:99:99' }]);
  });
  test('a bogus last-done is reported and the series is not re-based', () => {
    const c = rem('Water start:2026-09-13 frequency:weekly last-done:bogus');
    expect(c.reminder).toMatchObject({ due: { date: '2026-09-13', time: null }, rrule: 'FREQ=WEEKLY' });
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'last-done:bogus' }]);
  });
  test('a last-done with a time part is also invalid', () => {
    const c = rem('Water start:2026-09-13 frequency:weekly last-done:2026-09-20T10:00');
    expect(c.reminder.due).toEqual({ date: '2026-09-13', time: null });
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'last-done:2026-09-20T10:00' }]);
  });
  test('an impossible last-done is reported', () => {
    const c = rem('Water start:2026-09-13 frequency:weekly last-done:2026-02-30');
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'last-done:2026-02-30' }]);
  });
  test('valid values report nothing', () => {
    expect(rem('Water start:2026-09-13 frequency:weekly last-done:2026-09-20').entries).toEqual([]);
    expect(ev('E start:2026-09-22T10:00 type:event end:11:00').entries).toEqual([]);
    expect(ev('E start:2026-09-22T10:00 type:event end-time:11:00').entries).toEqual([]);
  });
});

describe('fix round 1: a done line without a usable start is due on the x date, keeping due: as a note', () => {
  test('due: is preserved as a Due: note line', () => {
    const c = rem('x 2026-01-01 T due:2026-02-01');
    expect(c.source).toBe('done-plain');
    expect(c.reminder).toMatchObject({
      due: { date: '2026-01-01', time: null }, completed: true, completedDate: { date: '2026-01-01', time: null },
      notes: 'Due: 2026-02-01',
    });
    expect(c.entries).toEqual([]);
  });
  test('a due: on the same date as the x date adds no note', () => {
    const c = rem('x 2026-01-01 T due:2026-01-01');
    expect(c.reminder.notes).toBeNull();
  });
  test('a done line with neither a start nor a usable x date falls back to due:', () => {
    const c = rem('x T due:2026-02-01');
    expect(c.reminder.due).toEqual({ date: '2026-02-01', time: null });
    expect(c.reminder.notes).toBeNull();
    expect(c.entries).toEqual([]);
  });
});

describe('ruling: an impossible completion date is reported, not un-completed', () => {
  test('x 2026-13-45 keeps completed true with no completedDate', () => {
    const c = rem('x 2026-13-45 Something');
    expect(c.source).toBe('done-plain');
    expect(c.reminder.completed).toBe(true);
    expect(c.reminder.completedDate).toBeNull();
    expect(c.entries).toEqual([
      { line: 1, kind: 'ignored-extension', detail: 'completion-date:2026-13-45' },
      { line: 1, kind: 'undated', detail: 'Something' },
    ]);
  });
  test('with a start:, due is the start and completedDate is still null', () => {
    const c = rem('x 2026-02-30 Renew start:2026-02-01');
    expect(c.reminder.completed).toBe(true);
    expect(c.reminder.due).toEqual({ date: '2026-02-01', time: null });
    expect(c.reminder.completedDate).toBeNull();
    expect(c.entries).toEqual([{ line: 1, kind: 'ignored-extension', detail: 'completion-date:2026-02-30' }]);
  });
  test('a done line with no completion date at all reports nothing extra', () => {
    const c = rem('x Something start:2026-02-01');
    expect(c.reminder.completed).toBe(true);
    expect(c.reminder.completedDate).toBeNull();
    expect(c.entries).toEqual([]);
  });
});
