# todo.txt → Native Stark Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `todo export-ics` command that converts a `todo.txt` into the native Stark app's `recurring.ics` + `YYYY-MM.ics` files, losing nothing, verified against both the Swift parser and the author's real file.

**Architecture:** A pure transform in `shared/` (`Task[]` → file contents + report) built from small single-purpose modules under `shared/ics/`, wrapped by a thin console command. The TypeScript writes the `.ics` text directly; fidelity to the Swift reader is enforced by hand-authored golden fixtures that a Swift test parses with the real `ICSParser`, plus a real-data parity run.

**Tech Stack:** TypeScript on Bun (`bun test`), Swift Testing in the `StarkKit` package (`swift test`).

**Spec:** `docs/superpowers/specs/2026-09-20-todo-txt-to-native-migration-design.md` (read it first; this plan implements it section by section).

## Global Constraints

- **Working directory:** `/Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps` (a git worktree). Use absolute paths in every command; never `cd` elsewhere. Run TS tests from that root (`bun test shared console`); run Swift tests from `ios/` (`swift test`).
- **Shell:** compound commands and heredocs may be rejected as "too complex to verify". Use plain single commands, the Write/Edit tools for files, `git -C <worktree>` and multiple `-m` flags for commits.
- **Commits:** stage specific paths only (never `git add -A`, `.` or `commit -a`). End every commit message with a separate `-m` paragraph: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Never push.
- **Output format is exactly what `ICSSerializer` writes:** `\r\n` line endings with a trailing `\r\n`; `BEGIN:VCALENDAR` / `VERSION:2.0` / `PRODID:-//Stark//EN`; events before reminders; floating local times `yyyyMMdd'T'HHmmss` (no `Z`, no `TZID`); all-day = `DTSTART;VALUE=DATE:yyyyMMdd`; `UNTIL` is date-only; one `EXDATE` line per exception; text escapes `\` → `\\`, `;` → `\;`, `,` → `\,`, newline → `\n`; no line folding.
- **Event property order:** `UID`, `SUMMARY`, `DTSTART`, `DTEND`, `DESCRIPTION`, `LOCATION`, `RRULE`, `EXDATE`… **Reminder (VTODO) order:** `UID`, `SUMMARY`, `DUE`, `DESCRIPTION`, `PRIORITY`, `STATUS`, `COMPLETED`, `RRULE`, `EXDATE`… **RRULE part order:** `FREQ`, `INTERVAL`, day spec (`BYDAY` / `BYMONTHDAY`, then `BYSETPOS`), `BYMONTH`, `COUNT`, `UNTIL`.
- **Layering:** `shared/` is pure (no I/O, no `console.*`, no `process.exit`, no clock — never read `Date.now()` or `new Date()` without an argument). `console/` does the I/O. `verbatimModuleSyntax` is on: use `import type` for type-only imports.
- **Never drop a line silently.** Every data problem becomes a report entry; on the author's real file the export must yield exactly **3,337 events + 4,965 reminders = 8,302 lines**.
- **Tags stay in titles exactly as written**; only known structural `key:value` tokens are removed from a title (spec, "Title, notes, location").
- **Native positions stop at `fourth` and `last`** (no `fifth`).
- The Swift `ICSParser` is the ground truth for what the app can read. If a fixture and the spec disagree, stop and report instead of editing either silently.

## File Structure

Create:
- `shared/ics/types.ts` — `Wall`, `IcsEvent`, `IcsReminder`.
- `shared/ics/text.ts` — escaping, date formatting, VEVENT/VTODO/VCALENDAR serialization.
- `shared/ics/rrule.ts` — todo.txt recurrence extensions → `RRULE` string.
- `shared/ics/fields.ts` — title cleaning, note decoding, date parsing, event end rules, priority.
- `shared/ics/uid.ts` — deterministic UUID-shaped ids.
- `shared/ics/anchor.ts` — re-basing a recurring reminder's anchor.
- `shared/ics/convert.ts` — one `Task` → one `IcsEvent` or `IcsReminder` + report entries.
- `shared/commands/exportIcs.ts` — `applyExportIcs(tasks, options)`: placement, ordering, report.
- `console/commands/export-ics.ts` — CLI wrapper.
- `console/scripts/parity-expected.ts` — expected-agenda JSON for the real-data parity run.
- `shared/tests/ics/*.test.ts`, `shared/tests/commands/exportIcs.test.ts`, `console/tests/commands/export-ics.test.ts`.
- `shared/tests/fixtures/ics/sample.todo.txt`, `shared/tests/fixtures/ics/expected/*.ics`, `shared/tests/fixtures/ics/.gitattributes`.
- `ios/Tests/StarkKitTests/ExportFixtureTests.swift`, `ios/Tests/StarkKitTests/ParityTests.swift`.

Modify: `console/index.ts` (route the command), `console/commands/help.ts` (document it), `CLAUDE.md` (document it).

---

### Task 1: Golden fixtures and the Swift test that pins the format

The expected `.ics` files are authored by hand from the Swift serializer's rules, *before* any TypeScript exists. A Swift test parses them with the real `ICSParser`, so if a fixture is unreadable or means something different from what the spec says, we find out now. Later tasks make the converter reproduce them byte for byte.

**Files:**
- Create: `shared/tests/fixtures/ics/sample.todo.txt`
- Create: `shared/tests/fixtures/ics/expected/recurring.ics`, `2026-08.ics`, `2026-09.ics`, `2026-10.ics`
- Create: `shared/tests/fixtures/ics/.gitattributes`
- Create: `ios/Tests/StarkKitTests/ExportFixtureTests.swift`

**Interfaces:**
- Produces: the input `sample.todo.txt` (17 lines, line N gets uid `LNN`, e.g. `L04`) and four expected files. Later tasks compare converter output to these exactly (after the CRLF conversion in Step 3).

- [ ] **Step 1: Write the sample input**

Create `shared/tests/fixtures/ics/sample.todo.txt` with exactly these 17 lines (no blank lines, LF endings, trailing newline):

```
2026-09-01 Dentist start:2026-09-22T14:30 end:2026-09-22T15:30 type:event location:123_Main_St description:Bring_forms,_insurance_card
2026-09-01 Company holiday start:2026-10-12 type:event
2026-09-01 Conference start:2026-10-05 end:2026-10-08 type:event
2026-09-01 Standup start:2026-09-21T09:00 end:2026-09-21T09:15 type:event frequency:weekly frequency-day:M,W,F exdate:2026-09-23,2026-09-25 recur-until:2026-12-18
2026-09-01 Book club start:2026-10-07T19:00 type:event frequency:monthly frequency-month-day:first-wednesday
2026-09-01 Payday start:2026-09-30T08:00 type:event frequency:monthly frequency-month-day:last-day
Mom's birthday %birthday start:1975-05-15 type:birthday frequency:yearly
2026-09-01 Pay rent start:2026-10-01 frequency:monthly
(A) Call insurance start:2026-09-25T10:00 ~sam %phone bus:16:00
2026-09-02 Water plants start:2026-09-13T07:00 frequency:weekly every:2 last-done:2026-09-20
x 2026-09-18 2026-09-01 Take out trash
x 2026-08-30 Renew passport start:2026-08-25
x 2026-09-10 Old dentist start:2026-09-09T10:00 end:2026-09-09T11:00 type:event
2026-09-01 Fifth Friday start:2026-10-30T18:00 type:event frequency:monthly frequency-month-day:fifth-friday
2026-09-03 Buy milk
2026-09-01 Meet Sam at 9:00 start:2026-09-24T09:00
2026-09-01 Lunch; with, commas \ backslash 🍜 start:2026-09-26T12:00 type:event
```

- [ ] **Step 2: Write the four expected files (LF for now)**

`shared/tests/fixtures/ics/expected/recurring.ics`:

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Stark//EN
BEGIN:VEVENT
UID:L04
SUMMARY:Standup
DTSTART:20260921T090000
DTEND:20260921T091500
RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261218
EXDATE:20260923T090000
EXDATE:20260925T090000
END:VEVENT
BEGIN:VEVENT
UID:L05
SUMMARY:Book club
DTSTART:20261007T190000
RRULE:FREQ=MONTHLY;BYDAY=1WE
END:VEVENT
BEGIN:VEVENT
UID:L06
SUMMARY:Payday
DTSTART:20260930T080000
RRULE:FREQ=MONTHLY;BYMONTHDAY=-1
END:VEVENT
BEGIN:VEVENT
UID:L07
SUMMARY:Mom's birthday %birthday
DTSTART;VALUE=DATE:19750515
RRULE:FREQ=YEARLY
END:VEVENT
BEGIN:VTODO
UID:L08
SUMMARY:Pay rent
DUE:20261001T000000
STATUS:NEEDS-ACTION
RRULE:FREQ=MONTHLY
END:VTODO
BEGIN:VTODO
UID:L10
SUMMARY:Water plants
DUE:20260927T070000
STATUS:NEEDS-ACTION
RRULE:FREQ=WEEKLY;INTERVAL=2
END:VTODO
END:VCALENDAR
```

`shared/tests/fixtures/ics/expected/2026-08.ics`:

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Stark//EN
BEGIN:VTODO
UID:L12
SUMMARY:Renew passport
DUE:20260825T000000
STATUS:COMPLETED
COMPLETED:20260830T000000
END:VTODO
END:VCALENDAR
```

`shared/tests/fixtures/ics/expected/2026-09.ics`:

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Stark//EN
BEGIN:VEVENT
UID:L01
SUMMARY:Dentist
DTSTART:20260922T143000
DTEND:20260922T153000
DESCRIPTION:Bring forms\, insurance card
LOCATION:123 Main St
END:VEVENT
BEGIN:VEVENT
UID:L13
SUMMARY:Old dentist
DTSTART:20260909T100000
DTEND:20260909T110000
END:VEVENT
BEGIN:VEVENT
UID:L17
SUMMARY:Lunch\; with\, commas \\ backslash 🍜
DTSTART:20260926T120000
END:VEVENT
BEGIN:VTODO
UID:L09
SUMMARY:Call insurance ~sam %phone bus:16:00
DUE:20260925T100000
PRIORITY:1
STATUS:NEEDS-ACTION
END:VTODO
BEGIN:VTODO
UID:L11
SUMMARY:Take out trash
DUE:20260918T000000
STATUS:COMPLETED
COMPLETED:20260918T000000
END:VTODO
BEGIN:VTODO
UID:L15
SUMMARY:Buy milk
STATUS:NEEDS-ACTION
END:VTODO
BEGIN:VTODO
UID:L16
SUMMARY:Meet Sam at 9:00
DUE:20260924T090000
STATUS:NEEDS-ACTION
END:VTODO
END:VCALENDAR
```

`shared/tests/fixtures/ics/expected/2026-10.ics`:

```
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Stark//EN
BEGIN:VEVENT
UID:L02
SUMMARY:Company holiday
DTSTART;VALUE=DATE:20261012
END:VEVENT
BEGIN:VEVENT
UID:L03
SUMMARY:Conference
DTSTART;VALUE=DATE:20261005
DTEND;VALUE=DATE:20261008
END:VEVENT
BEGIN:VEVENT
UID:L14
SUMMARY:Fifth Friday
DTSTART:20261030T180000
END:VEVENT
END:VCALENDAR
```

- [ ] **Step 3: Convert the expected files to CRLF and stop git rewriting them**

Create `shared/tests/fixtures/ics/.gitattributes` containing the single line `*.ics -text`.

Run (one command per file, absolute paths; the pattern is idempotent):

```bash
perl -pi -e 's/\r?\n/\r\n/' /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/shared/tests/fixtures/ics/expected/recurring.ics
perl -pi -e 's/\r?\n/\r\n/' /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/shared/tests/fixtures/ics/expected/2026-08.ics
perl -pi -e 's/\r?\n/\r\n/' /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/shared/tests/fixtures/ics/expected/2026-09.ics
perl -pi -e 's/\r?\n/\r\n/' /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/shared/tests/fixtures/ics/expected/2026-10.ics
```

Verify: `file /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/shared/tests/fixtures/ics/expected/2026-09.ics` → mentions `CRLF line terminators`.

- [ ] **Step 4: Write the Swift parse test**

Create `ios/Tests/StarkKitTests/ExportFixtureTests.swift`:

```swift
// ios/Tests/StarkKitTests/ExportFixtureTests.swift
//
// Parses the golden fixtures produced for the todo.txt migration with the REAL ICSParser.
// The TypeScript converter (shared/commands/exportIcs.ts) must reproduce these files byte for
// byte; this test proves the files mean what the migration spec says they mean to the app.
import Testing
import Foundation
@testable import StarkKit

private let expectedDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // StarkKitTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // ios
    .deletingLastPathComponent()   // repo root
    .appendingPathComponent("shared/tests/fixtures/ics/expected")

private func load(_ name: String) throws -> ICSParseResult {
    let text = try String(contentsOf: expectedDir.appendingPathComponent(name), encoding: .utf8)
    return ICSParser.parse(text)
}

private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func iso(_ date: Date) -> String { DateMath.isoDate(from: date) }

@Suite("Migration export fixtures")
struct ExportFixtureTests {
    @Test("fixtures are CRLF, as the Swift serializer writes them")
    func fixturesAreCRLF() throws {
        let text = try String(contentsOf: expectedDir.appendingPathComponent("2026-09.ics"), encoding: .utf8)
        #expect(text.contains("\r\n"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
    }

    @Test("recurring.ics: every recurrence form parses to the intended rule")
    func recurring() throws {
        let r = try load("recurring.ics")
        #expect(r.warnings.isEmpty)
        #expect(r.events.map(\.id) == ["L04", "L05", "L06", "L07"])
        #expect(r.reminders.map(\.id) == ["L08", "L10"])

        let standup = r.events[0]
        #expect(standup.title == "Standup")
        #expect(standup.start == local(2026, 9, 21, 9, 0))
        #expect(standup.end == local(2026, 9, 21, 9, 15))
        #expect(standup.recurrence?.frequency == .weekly)
        #expect(standup.recurrence?.byDay == [.monday, .wednesday, .friday])
        #expect(standup.recurrence?.until.map(iso) == "2026-12-18")
        #expect(standup.exceptionDates.map(iso) == ["2026-09-23", "2026-09-25"])

        #expect(r.events[1].recurrence?.byPositionalDay == [PositionalDay(position: .first, dayType: .weekday(.wednesday))])
        #expect(r.events[2].recurrence?.byPositionalDay == [PositionalDay(position: .last, dayType: .anyDay)])

        let birthday = r.events[3]
        #expect(birthday.title == "Mom's birthday %birthday")
        #expect(birthday.isAllDay)
        #expect(birthday.start == local(1975, 5, 15))
        #expect(birthday.recurrence?.frequency == .yearly)

        let rent = r.reminders[0]
        #expect(rent.dueDate == local(2026, 10, 1))
        #expect(rent.recurrence?.frequency == .monthly)
        #expect(!rent.isCompleted)

        let water = r.reminders[1]
        #expect(water.dueDate == local(2026, 9, 27, 7, 0))
        #expect(water.recurrence?.frequency == .weekly)
        #expect(water.recurrence?.interval == 2)
    }

    @Test("2026-08.ics: a completed reminder due on its own start date")
    func august() throws {
        let r = try load("2026-08.ics")
        #expect(r.warnings.isEmpty)
        #expect(r.events.isEmpty)
        #expect(r.reminders.count == 1)
        #expect(r.reminders[0].title == "Renew passport")
        #expect(r.reminders[0].isCompleted)
        #expect(r.reminders[0].dueDate == local(2026, 8, 25))
        #expect(r.reminders[0].completedDate == local(2026, 8, 30))
    }

    @Test("2026-09.ics: escaping, notes, location, priority, undated and completed reminders")
    func september() throws {
        let r = try load("2026-09.ics")
        #expect(r.warnings.isEmpty)
        #expect(r.events.map(\.id) == ["L01", "L13", "L17"])
        #expect(r.reminders.map(\.id) == ["L09", "L11", "L15", "L16"])

        let dentist = r.events[0]
        #expect(dentist.start == local(2026, 9, 22, 14, 30))
        #expect(dentist.end == local(2026, 9, 22, 15, 30))
        #expect(dentist.notes == "Bring forms, insurance card")
        #expect(dentist.location == "123 Main St")
        #expect(dentist.recurrence == nil)

        #expect(r.events[2].title == "Lunch; with, commas \\ backslash 🍜")

        let call = r.reminders[0]
        #expect(call.title == "Call insurance ~sam %phone bus:16:00")
        #expect(call.dueDate == local(2026, 9, 25, 10, 0))
        #expect(call.priority == 1)

        let trash = r.reminders[1]
        #expect(trash.isCompleted)
        #expect(trash.dueDate == local(2026, 9, 18))
        #expect(trash.completedDate == local(2026, 9, 18))

        #expect(r.reminders[2].title == "Buy milk")
        #expect(r.reminders[2].dueDate == nil)
        #expect(r.reminders[3].title == "Meet Sam at 9:00")
        #expect(r.reminders[3].dueDate == local(2026, 9, 24, 9, 0))
    }

    @Test("2026-10.ics: all-day, multi-day, and the unsupported fifth-Friday rule as a one-off")
    func october() throws {
        let r = try load("2026-10.ics")
        #expect(r.warnings.isEmpty)
        #expect(r.events.map(\.id) == ["L02", "L03", "L14"])
        #expect(r.events[0].isAllDay)
        #expect(r.events[0].start == local(2026, 10, 12))
        #expect(r.events[1].isAllDay)
        #expect(r.events[1].end == local(2026, 10, 8))
        #expect(r.events[2].recurrence == nil)
        #expect(r.events[2].start == local(2026, 10, 30, 18, 0))
    }
}
```

- [ ] **Step 5: Run the Swift test**

Run (from `/Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/ios`): `swift test --filter ExportFixtureTests`
Expected: PASS (5 tests). These validate the *fixtures* against the existing parser, so they pass immediately; if one fails, the fixture text is wrong — fix the fixture, re-run the CRLF step, and do not weaken the assertion.

- [ ] **Step 6: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add shared/tests/fixtures/ics ios/Tests/StarkKitTests/ExportFixtureTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "test: golden fixtures for the todo.txt migration, parsed by the real ICSParser" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Types and `.ics` text primitives

**Files:**
- Create: `shared/ics/types.ts`
- Create: `shared/ics/text.ts`
- Test: `shared/tests/ics/text.test.ts`

**Interfaces:**
- Produces (`types.ts`):
  ```ts
  export interface Wall { date: string; time: string | null }   // 'YYYY-MM-DD', 'HH:MM' or null (date-only)
  export interface IcsEvent {
    uid: string; title: string; start: Wall; end: Wall | null; allDay: boolean;
    notes: string | null; location: string | null; rrule: string | null; exdates: Wall[];
  }
  export interface IcsReminder {
    uid: string; title: string; due: Wall | null; notes: string | null; priority: number | null;
    completed: boolean; completedDate: Wall | null; rrule: string | null; exdates: Wall[];
  }
  ```
- Produces (`text.ts`): `escapeText(s: string): string`, `formatDate(date: string): string` (`'2026-09-22'` → `'20260922'`), `formatDateTime(w: Wall): string` (`time` null → `T000000`), `serializeEvent(e: IcsEvent): string`, `serializeReminder(r: IcsReminder): string` (both return lines joined by `\r\n`, no trailing newline), `serializeCalendar(events: IcsEvent[], reminders: IcsReminder[]): string`.

- [ ] **Step 1: Write the failing tests**

Create `shared/tests/ics/text.test.ts`:

```ts
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test shared/tests/ics/text.test.ts`
Expected: FAIL — cannot find module `../../ics/text`.

- [ ] **Step 3: Write `types.ts`**

Create `shared/ics/types.ts`:

```ts
// A wall-clock instant with no time zone, matching todo.txt's semantics.
// date is 'YYYY-MM-DD'; time is 'HH:MM', or null for a date-only value.
export interface Wall {
  date: string;
  time: string | null;
}

export interface IcsEvent {
  uid: string;
  title: string;
  start: Wall;
  end: Wall | null;
  allDay: boolean;
  notes: string | null;
  location: string | null;
  rrule: string | null;
  exdates: Wall[];
}

export interface IcsReminder {
  uid: string;
  title: string;
  due: Wall | null;
  notes: string | null;
  priority: number | null;
  completed: boolean;
  completedDate: Wall | null;
  rrule: string | null;
  exdates: Wall[];
}
```

- [ ] **Step 4: Write `text.ts`**

```ts
import type { IcsEvent, IcsReminder, Wall } from './types';

export function escapeText(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\n/g, '\\n');
}

export function formatDate(date: string): string {
  return date.replace(/-/g, '');
}

export function formatDateTime(w: Wall): string {
  const hhmm = (w.time ?? '00:00').replace(':', '');
  return `${formatDate(w.date)}T${hhmm}00`;
}

function dateParam(allDay: boolean): string {
  return allDay ? ';VALUE=DATE' : '';
}

function formatMaybeAllDay(w: Wall, allDay: boolean): string {
  return allDay ? formatDate(w.date) : formatDateTime(w);
}

export function serializeEvent(e: IcsEvent): string {
  const lines = ['BEGIN:VEVENT', `UID:${e.uid}`, `SUMMARY:${escapeText(e.title)}`];
  lines.push(`DTSTART${dateParam(e.allDay)}:${formatMaybeAllDay(e.start, e.allDay)}`);
  if (e.end) lines.push(`DTEND${dateParam(e.allDay)}:${formatMaybeAllDay(e.end, e.allDay)}`);
  if (e.notes !== null) lines.push(`DESCRIPTION:${escapeText(e.notes)}`);
  if (e.location !== null) lines.push(`LOCATION:${escapeText(e.location)}`);
  if (e.rrule) lines.push(`RRULE:${e.rrule}`);
  for (const ex of e.exdates) lines.push(`EXDATE${dateParam(e.allDay)}:${formatMaybeAllDay(ex, e.allDay)}`);
  lines.push('END:VEVENT');
  return lines.join('\r\n');
}

export function serializeReminder(r: IcsReminder): string {
  const lines = ['BEGIN:VTODO', `UID:${r.uid}`, `SUMMARY:${escapeText(r.title)}`];
  if (r.due) lines.push(`DUE:${formatDateTime(r.due)}`);
  if (r.notes !== null) lines.push(`DESCRIPTION:${escapeText(r.notes)}`);
  if (r.priority !== null) lines.push(`PRIORITY:${r.priority}`);
  lines.push(`STATUS:${r.completed ? 'COMPLETED' : 'NEEDS-ACTION'}`);
  if (r.completedDate) lines.push(`COMPLETED:${formatDateTime(r.completedDate)}`);
  if (r.rrule) lines.push(`RRULE:${r.rrule}`);
  for (const ex of r.exdates) lines.push(`EXDATE:${formatDateTime(ex)}`);
  lines.push('END:VTODO');
  return lines.join('\r\n');
}

export function serializeCalendar(events: IcsEvent[], reminders: IcsReminder[]): string {
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Stark//EN'];
  for (const e of events) lines.push(serializeEvent(e));
  for (const r of reminders) lines.push(serializeReminder(r));
  lines.push('END:VCALENDAR');
  return lines.join('\r\n') + '\r\n';
}
```

- [ ] **Step 5: Run to verify pass**

Run: `bun test shared/tests/ics/text.test.ts`
Expected: PASS (all tests).

- [ ] **Step 6: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add shared/ics/types.ts shared/ics/text.ts shared/tests/ics/text.test.ts
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "feat(shared): .ics text primitives matching the Swift serializer" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 3: Recurrence → `RRULE`

**Files:**
- Create: `shared/ics/rrule.ts`
- Test: `shared/tests/ics/rrule.test.ts`

**Interfaces:**
- Produces:
  ```ts
  export interface RRuleResult { rrule: string | null; unsupported: string | null; ignored: string[] }
  export function buildRRule(ext: Record<string, string>): RRuleResult
  ```
  `ext` is a `Task.extensions` map. `rrule` is null when there is no `frequency` or when the recurrence cannot be expressed (then `unsupported` holds the offending `key:value`). `ignored` lists extensions that were present but meaningless for this frequency (`frequency-day` off weekly, `frequency-month-day` off monthly/yearly, `frequency-month` off yearly, a malformed `recur-until`); the rule is still produced.

- [ ] **Step 1: Write the failing tests**

Create `shared/tests/ics/rrule.test.ts`:

```ts
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
});
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test shared/tests/ics/rrule.test.ts`
Expected: FAIL — cannot find module `../../ics/rrule`.

- [ ] **Step 3: Write `rrule.ts`**

```ts
export interface RRuleResult {
  rrule: string | null;
  unsupported: string | null;
  ignored: string[];
}

const FREQUENCIES = new Set(['daily', 'weekly', 'monthly', 'yearly']);
const DAY_CODES: Record<string, string> = { M: 'MO', T: 'TU', W: 'WE', Th: 'TH', F: 'FR', Sat: 'SA', Sun: 'SU' };
const WEEKDAY_NAMES: Record<string, string> = {
  monday: 'MO', tuesday: 'TU', wednesday: 'WE', thursday: 'TH', friday: 'FR', saturday: 'SA', sunday: 'SU',
};
// The native app's Position stops at fourth and last, so `fifth` is deliberately absent.
const POSITIONS: Record<string, number> = { first: 1, second: 2, third: 3, fourth: 4, last: -1 };
const MONTHS: Record<string, number> = {
  Jan: 1, Feb: 2, Mar: 3, Apr: 4, May: 5, Jun: 6, Jul: 7, Aug: 8, Sep: 9, Oct: 10, Nov: 11, Dec: 12,
};
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function encodeMonthDay(value: string): string[] | null {
  if (/^\d+$/.test(value)) {
    const n = Number(value);
    return n >= 1 && n <= 31 ? [`BYMONTHDAY=${n}`] : null;
  }
  const dash = value.indexOf('-');
  if (dash < 0) return null;
  const position = POSITIONS[value.slice(0, dash)];
  const dayType = value.slice(dash + 1);
  if (position === undefined) return null;
  const weekday = WEEKDAY_NAMES[dayType];
  if (weekday) return [`BYDAY=${position}${weekday}`];
  if (dayType === 'day') return [`BYMONTHDAY=${position}`];
  if (dayType === 'weekday') return ['BYDAY=MO,TU,WE,TH,FR', `BYSETPOS=${position}`];
  if (dayType === 'weekend-day') return ['BYDAY=SA,SU', `BYSETPOS=${position}`];
  return null;
}

export function buildRRule(ext: Record<string, string>): RRuleResult {
  const result: RRuleResult = { rrule: null, unsupported: null, ignored: [] };
  const freq = ext['frequency'];
  if (freq === undefined) return result;
  const unsupported = (detail: string): RRuleResult => ({ rrule: null, unsupported: detail, ignored: result.ignored });
  if (!FREQUENCIES.has(freq)) return unsupported(`frequency:${freq}`);

  const parts = [`FREQ=${freq.toUpperCase()}`];

  const every = ext['every'];
  if (every !== undefined) {
    const n = Number(every);
    if (!Number.isInteger(n) || n < 1) return unsupported(`every:${every}`);
    if (n > 1) parts.push(`INTERVAL=${n}`);
  }

  const days = ext['frequency-day'];
  if (days !== undefined) {
    if (freq !== 'weekly') {
      result.ignored.push(`frequency-day:${days}`);
    } else {
      const codes: string[] = [];
      for (const d of days.split(',')) {
        const code = DAY_CODES[d];
        if (!code) return unsupported(`frequency-day:${days}`);
        codes.push(code);
      }
      parts.push(`BYDAY=${codes.join(',')}`);
    }
  }

  const monthDay = ext['frequency-month-day'];
  if (monthDay !== undefined) {
    if (freq !== 'monthly' && freq !== 'yearly') {
      result.ignored.push(`frequency-month-day:${monthDay}`);
    } else {
      const encoded = encodeMonthDay(monthDay);
      if (!encoded) return unsupported(`frequency-month-day:${monthDay}`);
      parts.push(...encoded);
    }
  }

  const months = ext['frequency-month'];
  if (months !== undefined) {
    if (freq !== 'yearly') {
      result.ignored.push(`frequency-month:${months}`);
    } else {
      const numbers: number[] = [];
      for (const m of months.split(',')) {
        const n = MONTHS[m];
        if (n === undefined) return unsupported(`frequency-month:${months}`);
        numbers.push(n);
      }
      parts.push(`BYMONTH=${numbers.join(',')}`);
    }
  }

  const until = ext['recur-until'];
  if (until !== undefined) {
    if (DATE_RE.test(until)) parts.push(`UNTIL=${until.replace(/-/g, '')}`);
    else result.ignored.push(`recur-until:${until}`);
  }

  result.rrule = parts.join(';');
  return result;
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bun test shared/tests/ics/rrule.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add shared/ics/rrule.ts shared/tests/ics/rrule.test.ts
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "feat(shared): todo.txt recurrence to RRULE, matching RRuleCodec" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Field extraction (titles, notes, dates, end rules, priority)

**Files:**
- Create: `shared/ics/fields.ts`
- Test: `shared/tests/ics/fields.test.ts`

**Interfaces:**
- Consumes: `Wall` from `shared/ics/types.ts`.
- Produces:
  ```ts
  export const STRUCTURAL_KEYS: ReadonlySet<string>
  export function cleanTitle(text: string): string
  export function decodeNote(value: string): string
  export function parseWall(value: string | undefined): Wall | null
  export function priorityToNumber(priority: string | undefined): number | null
  export interface EndResult { end: Wall | null; endBeforeStart: boolean }
  export function resolveEventEnd(start: Wall, ext: Record<string, string>): EndResult
  export function joinNotes(parts: Array<string | null | undefined>): string | null
  ```

- [ ] **Step 1: Write the failing tests**

Create `shared/tests/ics/fields.test.ts`:

```ts
import { test, expect, describe } from 'bun:test';
import { cleanTitle, decodeNote, parseWall, priorityToNumber, resolveEventEnd, joinNotes } from '../../ics/fields';

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
});

describe('decodeNote / joinNotes', () => {
  test('underscores become spaces, commas stay', () => {
    expect(decodeNote('Bring_forms,_insurance_card')).toBe('Bring forms, insurance card');
  });
  test('joinNotes skips empties and joins with a newline', () => {
    expect(joinNotes(['a', null, undefined, '', 'b'])).toBe('a\nb');
    expect(joinNotes([null, undefined])).toBeNull();
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
});
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test shared/tests/ics/fields.test.ts`
Expected: FAIL — cannot find module `../../ics/fields`.

- [ ] **Step 3: Write `fields.ts`**

```ts
import type { Wall } from './types';

// The only keys the converter consumes. Everything else that looks like key:value (tags,
// custom keys like bus:16:00, times in prose like 9:00) stays in the title untouched.
export const STRUCTURAL_KEYS: ReadonlySet<string> = new Set([
  'type', 'start', 'end', 'end-time', 'frequency', 'frequency-day', 'frequency-month-day',
  'frequency-month', 'every', 'exdate', 'recur-until', 'last-done', 'due', 'location', 'note',
  'description', 'reminders-id',
]);

const TOKEN_RE = /^([\w-]+):([^/\s]\S*)$/;
const WALL_RE = /^(\d{4}-\d{2}-\d{2})(?:T(\d{2}:\d{2}))?$/;
const BARE_TIME_RE = /^\d{2}:\d{2}$/;

export function cleanTitle(text: string): string {
  return text
    .split(' ')
    .filter(token => {
      const m = TOKEN_RE.exec(token);
      return !(m && STRUCTURAL_KEYS.has(m[1]!));
    })
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function decodeNote(value: string): string {
  return value.replace(/_/g, ' ');
}

export function joinNotes(parts: Array<string | null | undefined>): string | null {
  const present = parts.filter((p): p is string => !!p);
  return present.length > 0 ? present.join('\n') : null;
}

export function parseWall(value: string | undefined): Wall | null {
  if (value === undefined) return null;
  const m = WALL_RE.exec(value);
  return m ? { date: m[1]!, time: m[2] ?? null } : null;
}

export function priorityToNumber(priority: string | undefined): number | null {
  if (!priority || !/^[A-Z]$/.test(priority)) return null;
  return Math.min(priority.charCodeAt(0) - 64, 9);
}

export interface EndResult {
  end: Wall | null;
  endBeforeStart: boolean;
}

const sortKey = (w: Wall): string => `${w.date}T${w.time ?? '00:00'}`;

export function resolveEventEnd(start: Wall, ext: Record<string, string>): EndResult {
  const allDay = start.time === null;
  const rawEnd = ext['end'];
  const endTime = ext['end-time'];
  const endTimeOk = endTime !== undefined && BARE_TIME_RE.test(endTime) && !allDay;
  let end: Wall | null = null;

  if (rawEnd !== undefined) {
    if (BARE_TIME_RE.test(rawEnd)) {
      if (!allDay) end = { date: start.date, time: rawEnd };
    } else {
      const w = parseWall(rawEnd);
      if (w) {
        if (allDay) end = { date: w.date, time: null };
        else if (w.time !== null) end = w;
        else end = { date: w.date, time: endTimeOk ? endTime! : start.time };
      }
    }
  } else if (endTimeOk) {
    end = { date: start.date, time: endTime! };
  }

  if (!end) return { end: null, endBeforeStart: false };
  if (sortKey(end) < sortKey(start)) return { end: null, endBeforeStart: true };
  return { end, endBeforeStart: false };
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bun test shared/tests/ics/fields.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add shared/ics/fields.ts shared/tests/ics/fields.test.ts
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "feat(shared): field extraction for the .ics export" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 5: Deterministic ids

**Files:**
- Create: `shared/ics/uid.ts`
- Test: `shared/tests/ics/uid.test.ts`

**Interfaces:**
- Produces: `export function makeUid(raw: string, index: number): string` — a UUID-shaped, upper-case, deterministic id from the source line and the occurrence index of identical lines (0 for the first).

- [ ] **Step 1: Write the failing test**

Create `shared/tests/ics/uid.test.ts`:

```ts
import { test, expect } from 'bun:test';
import { makeUid } from '../../ics/uid';

test('is UUID-shaped (version 5 nibble, RFC variant), upper-case', () => {
  expect(makeUid('a line', 0)).toMatch(/^[0-9A-F]{8}-[0-9A-F]{4}-5[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/);
});
test('is deterministic', () => {
  expect(makeUid('a line', 0)).toBe(makeUid('a line', 0));
});
test('differs by line text and by duplicate index', () => {
  expect(makeUid('a line', 0)).not.toBe(makeUid('another line', 0));
  expect(makeUid('a line', 0)).not.toBe(makeUid('a line', 1));
});
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test shared/tests/ics/uid.test.ts`
Expected: FAIL — cannot find module `../../ics/uid`.

- [ ] **Step 3: Write `uid.ts`**

```ts
import { createHash } from 'node:crypto';

// Deterministic so re-running the export gives byte-identical files; UUID-shaped so the ids
// look like the ones the native app generates itself.
export function makeUid(raw: string, index: number): string {
  const hex = createHash('sha1').update(`${raw}#${index}`).digest('hex');
  const variant = ((parseInt(hex[16]!, 16) & 0x3) | 0x8).toString(16);
  const uuid = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-${variant}${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
  return uuid.toUpperCase();
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bun test shared/tests/ics/uid.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add shared/ics/uid.ts shared/tests/ics/uid.test.ts
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "feat(shared): deterministic UUID-shaped ids for the .ics export" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Anchor re-basing for recurring reminders

The console advances `start:` when a weekly/monthly/daily task is completed, but yearly tasks only gain `last-done:`, and hand-edited lines can be anywhere. The native app has no `last-done`, so a recurring reminder's anchor must be the first occurrence *after* everything already done.

**Files:**
- Create: `shared/ics/anchor.ts`
- Test: `shared/tests/ics/anchor.test.ts`

**Interfaces:**
- Consumes: `generateTaskOccurrences(task, fromStr, cutoffStr): Array<{date: string; task: Task}>` from `shared/commands/focus.ts` (it ignores `daily`, so daily is computed here); `addDays` from `shared/utils.ts`.
- Produces:
  ```ts
  export interface Anchor { start: string; finished: boolean }   // start: 'YYYY-MM-DD' or 'YYYY-MM-DDTHH:MM'
  export function rebaseAnchor(task: Task): Anchor
  ```
  Precondition: the task has `start:` and `frequency:` extensions. `finished` is true when no later occurrence exists (`recur-until` passed); the original `start` is then returned unchanged.

- [ ] **Step 1: Write the failing tests**

Create `shared/tests/ics/anchor.test.ts`:

```ts
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test shared/tests/ics/anchor.test.ts`
Expected: FAIL — cannot find module `../../ics/anchor`.

- [ ] **Step 3: Write `anchor.ts`**

```ts
import type { Task } from '../parser';
import { addDays } from '../utils';
import { generateTaskOccurrences } from '../commands/focus';

export interface Anchor {
  start: string;
  finished: boolean;
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const dayNumber = (date: string): number => Math.round(new Date(date + 'T12:00:00').getTime() / 86400000);

export function rebaseAnchor(task: Task): Anchor {
  const start = task.extensions['start']!;
  const startDate = start.slice(0, 10);
  const time = start.slice(10);

  const candidates = [task.extensions['last-done'], task.done ? task.completionDate : undefined]
    .filter((d): d is string => !!d && DATE_RE.test(d))
    .sort();
  const resolvedThrough = candidates[candidates.length - 1];
  if (!resolvedThrough || resolvedThrough < startDate) return { start, finished: false };

  const from = addDays(resolvedThrough, 1);
  const frequency = task.extensions['frequency'];
  const every = Math.max(parseInt(task.extensions['every'] ?? '1', 10) || 1, 1);
  const until = task.extensions['recur-until'];

  let next: string | null;
  if (frequency === 'daily') {
    const diff = dayNumber(from) - dayNumber(startDate);
    next = addDays(startDate, (diff <= 0 ? 0 : Math.ceil(diff / every)) * every);
  } else {
    const found = generateTaskOccurrences(task, from, addDays(from, 366 * every + 31));
    next = found.length > 0 ? found[0]!.date : null;
  }

  if (next === null || (until && next > until)) return { start, finished: true };
  return { start: next + time, finished: false };
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bun test shared/tests/ics/anchor.test.ts`
Expected: PASS. If the weekly-weekday-set or monthly case fails, the shared helper's behaviour differs from the expectation in this plan; do not adjust the helper — re-derive the expected date by calling `generateTaskOccurrences` directly in a scratch test, and report the discrepancy.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add shared/ics/anchor.ts shared/tests/ics/anchor.test.ts
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "feat(shared): re-base a recurring reminder's anchor past its completed occurrences" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 7: Convert one task (classification, fields, report entries)

**Files:**
- Create: `shared/ics/convert.ts`
- Test: `shared/tests/ics/convert.test.ts`

**Interfaces:**
- Consumes: `buildRRule` (Task 3), `cleanTitle`/`decodeNote`/`joinNotes`/`parseWall`/`priorityToNumber`/`resolveEventEnd` (Task 4), `rebaseAnchor` (Task 6), `IcsEvent`/`IcsReminder`/`Wall` (Task 2), `Task` from `shared/parser.ts`.
- Produces:
  ```ts
  export type ReportKind = 'unsupported-recurrence' | 'ignored-extension' | 'end-before-start'
    | 'undated' | 'untitled' | 'event-without-start' | 'finished-series';
  export interface ReportEntry { line: number; kind: ReportKind; detail: string }
  export type SourceBucket = 'open-event' | 'open-birthday' | 'open-anniversary' | 'open-task'
    | 'done-plain' | 'done-with-start' | 'done-event' | 'done-recurring';
  export type Converted =
    | { kind: 'event'; event: IcsEvent; source: SourceBucket; entries: ReportEntry[] }
    | { kind: 'reminder'; reminder: IcsReminder; source: SourceBucket; entries: ReportEntry[] };
  export function convertTask(task: Task, uid: string): Converted
  ```
  `source` is the bucket in the spec's data table (used to reconcile counts); it is decided from the *source line*, even when a fallback changes the output type.

- [ ] **Step 1: Write the failing tests**

Create `shared/tests/ics/convert.test.ts`:

```ts
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test shared/tests/ics/convert.test.ts`
Expected: FAIL — cannot find module `../../ics/convert`.

- [ ] **Step 3: Write `convert.ts`**

```ts
import type { Task } from '../parser';
import type { IcsEvent, IcsReminder, Wall } from './types';
import { buildRRule } from './rrule';
import { cleanTitle, decodeNote, joinNotes, parseWall, priorityToNumber, resolveEventEnd } from './fields';
import { rebaseAnchor } from './anchor';

export type ReportKind =
  | 'unsupported-recurrence' | 'ignored-extension' | 'end-before-start'
  | 'undated' | 'untitled' | 'event-without-start' | 'finished-series';
export interface ReportEntry { line: number; kind: ReportKind; detail: string }
export type SourceBucket =
  | 'open-event' | 'open-birthday' | 'open-anniversary' | 'open-task'
  | 'done-plain' | 'done-with-start' | 'done-event' | 'done-recurring';
export type Converted =
  | { kind: 'event'; event: IcsEvent; source: SourceBucket; entries: ReportEntry[] }
  | { kind: 'reminder'; reminder: IcsReminder; source: SourceBucket; entries: ReportEntry[] };

const TYPED = new Set(['event', 'birthday', 'anniversary']);
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function titleOf(task: Task, entries: ReportEntry[]): string {
  const title = cleanTitle(task.text);
  if (title === '') {
    entries.push({ line: task.line, kind: 'untitled', detail: task.raw });
    return '(untitled)';
  }
  return title;
}

function exdatesOf(ext: Record<string, string>, time: string | null): Wall[] {
  return (ext['exdate'] ?? '').split(',').filter(d => DATE_RE.test(d)).map(date => ({ date, time }));
}

function recurrenceOf(task: Task, entries: ReportEntry[]): string | null {
  const result = buildRRule(task.extensions);
  for (const detail of result.ignored) entries.push({ line: task.line, kind: 'ignored-extension', detail });
  if (result.unsupported) entries.push({ line: task.line, kind: 'unsupported-recurrence', detail: result.unsupported });
  return result.rrule;
}

function buildEvent(task: Task, uid: string, entries: ReportEntry[]): IcsEvent | null {
  const ext = task.extensions;
  const start = parseWall(ext['start']);
  if (!start) return null;
  const { end, endBeforeStart } = resolveEventEnd(start, ext);
  if (endBeforeStart) entries.push({ line: task.line, kind: 'end-before-start', detail: `end:${ext['end'] ?? ''}` });
  const rrule = recurrenceOf(task, entries);
  return {
    uid,
    title: titleOf(task, entries),
    start,
    end,
    allDay: start.time === null,
    notes: joinNotes([ext['description'] ? decodeNote(ext['description']) : null, ext['note'] ? decodeNote(ext['note']) : null]),
    location: ext['location'] ? decodeNote(ext['location']) : null,
    rrule,
    exdates: rrule ? exdatesOf(ext, start.time) : [],
  };
}

function buildReminder(task: Task, uid: string, entries: ReportEntry[]): IcsReminder {
  const ext = task.extensions;
  const title = titleOf(task, entries);
  const startWall = parseWall(ext['start']);
  const dueWall = parseWall(ext['due']);
  const recurring = !!ext['frequency'] && !!ext['start'];
  if (ext['frequency'] && !ext['start']) {
    entries.push({ line: task.line, kind: 'unsupported-recurrence', detail: `frequency:${ext['frequency']} without start:` });
  }

  let due: Wall | null;
  let dueExtra: string | null = null;
  let rrule: string | null = null;

  if (recurring) {
    rrule = recurrenceOf(task, entries);
    if (rrule !== null) {
      const anchor = rebaseAnchor(task);
      if (anchor.finished) entries.push({ line: task.line, kind: 'finished-series', detail: `recur-until:${ext['recur-until'] ?? ''}` });
      due = parseWall(anchor.start);
    } else {
      due = startWall;
    }
  } else {
    due = startWall ?? dueWall;
    if (startWall && dueWall && dueWall.date !== startWall.date) dueExtra = `Due: ${ext['due']}`;
  }

  const completed = task.done && !recurring;
  const completedDate: Wall | null = completed && task.completionDate ? { date: task.completionDate, time: null } : null;
  if (completed && due === null && completedDate) due = completedDate;
  if (due === null) entries.push({ line: task.line, kind: 'undated', detail: title });

  return {
    uid,
    title,
    due,
    notes: joinNotes([
      ext['location'] ? `Location: ${decodeNote(ext['location'])}` : null,
      ext['description'] ? decodeNote(ext['description']) : null,
      ext['note'] ? decodeNote(ext['note']) : null,
      dueExtra,
    ]),
    priority: task.done ? null : priorityToNumber(task.priority),
    completed,
    completedDate,
    rrule,
    exdates: rrule ? exdatesOf(ext, due?.time ?? null) : [],
  };
}

export function convertTask(task: Task, uid: string): Converted {
  const ext = task.extensions;
  const type = ext['type'];
  const typed = type !== undefined && TYPED.has(type);
  const hasStart = !!ext['start'];
  const hasFrequency = !!ext['frequency'];
  const entries: ReportEntry[] = [];

  const source: SourceBucket = task.done
    ? (hasFrequency && hasStart ? 'done-recurring' : typed ? 'done-event' : hasStart ? 'done-with-start' : 'done-plain')
    : type === 'birthday' ? 'open-birthday'
    : type === 'anniversary' ? 'open-anniversary'
    : typed ? 'open-event'
    : 'open-task';

  if (typed) {
    const event = buildEvent(task, uid, entries);
    if (event) return { kind: 'event', event, source, entries };
    entries.push({ line: task.line, kind: 'event-without-start', detail: `start:${ext['start'] ?? ''}` });
  }
  return { kind: 'reminder', reminder: buildReminder(task, uid, entries), source, entries };
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bun test shared/tests/ics/convert.test.ts`
Expected: PASS. If the `%birthday`-alias test fails, check that `parseLine` sets `extensions['type'] = 'birthday'` for a bare `%birthday` tag (it does, in `shared/parser.ts`); if a rebase test fails, re-check Task 6 first.

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add shared/ics/convert.ts shared/tests/ics/convert.test.ts
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "feat(shared): convert one todo.txt task to an event or reminder with report entries" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 8: The export transform (placement, ordering, report) and the golden test

**Files:**
- Create: `shared/commands/exportIcs.ts`
- Test: `shared/tests/commands/exportIcs.test.ts`

**Interfaces:**
- Consumes: `convertTask`, `ReportEntry`, `SourceBucket`, `Converted` (Task 7); `serializeCalendar` (Task 2); `makeUid` (Task 5); `Task` from `shared/parser.ts`; the fixtures from Task 1.
- Produces:
  ```ts
  export interface ExportOptions { uid?: (task: Task, duplicateIndex: number) => string }
  export interface ExportReport {
    lines: number; events: number; reminders: number;
    bySource: Partial<Record<SourceBucket, number>>; entries: ReportEntry[];
  }
  export interface ExportResult { files: Record<string, string>; report: ExportReport }
  export function applyExportIcs(tasks: Task[], options?: ExportOptions): ExportResult
  export function formatReport(report: ExportReport): string
  ```
  `files` keys are `recurring.ics` (first) then `YYYY-MM.ics` ascending. Placement copies `PlannerStore`: any item with an `rrule` → `recurring.ics`; else the month of the event's start / the reminder's due. An undated reminder goes in the month of its creation date, else the earliest dated month present, else `1970-01.ics`. Within a file: events then reminders, each in source order. `applyExportIcs` throws if `events + reminders !== tasks.length` (a programmer error: a line was lost).

- [ ] **Step 1: Write the failing tests**

Create `shared/tests/commands/exportIcs.test.ts`:

```ts
import { test, expect, describe } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { parseLine } from '../../parser';
import type { Task } from '../../parser';
import { applyExportIcs, formatReport } from '../../commands/exportIcs';

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
  test('with nothing else dated, fall back to 1970-01', () => {
    expect(Object.keys(applyExportIcs(parse('Buy milk\n')).files)).toEqual(['1970-01.ics']);
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test shared/tests/commands/exportIcs.test.ts`
Expected: FAIL — cannot find module `../../commands/exportIcs`.

- [ ] **Step 3: Write `exportIcs.ts`**

```ts
import type { Task } from '../parser';
import type { IcsEvent, IcsReminder } from '../ics/types';
import { convertTask } from '../ics/convert';
import type { ReportEntry, SourceBucket } from '../ics/convert';
import { serializeCalendar } from '../ics/text';
import { makeUid } from '../ics/uid';

export interface ExportOptions {
  uid?: (task: Task, duplicateIndex: number) => string;
}

export interface ExportReport {
  lines: number;
  events: number;
  reminders: number;
  bySource: Partial<Record<SourceBucket, number>>;
  entries: ReportEntry[];
}

export interface ExportResult {
  files: Record<string, string>;
  report: ExportReport;
}

const RECURRING = 'recurring.ics';
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const monthFile = (date: string): string => `${date.slice(0, 7)}.ics`;

export function applyExportIcs(tasks: Task[], options: ExportOptions = {}): ExportResult {
  const uidFor = options.uid ?? ((task: Task, index: number) => makeUid(task.raw, index));
  const seen = new Map<string, number>();

  // Items carry their source line so each file can be emitted in source order even when an
  // item (an undated reminder) is placed after the others.
  interface Placed<T> { line: number; value: T }
  const buckets = new Map<string, { events: Array<Placed<IcsEvent>>; reminders: Array<Placed<IcsReminder>> }>();
  const bucket = (name: string) => {
    let b = buckets.get(name);
    if (!b) { b = { events: [], reminders: [] }; buckets.set(name, b); }
    return b;
  };

  const report: ExportReport = { lines: tasks.length, events: 0, reminders: 0, bySource: {}, entries: [] };
  const undated: Array<{ task: Task; reminder: IcsReminder }> = [];

  for (const task of tasks) {
    const index = seen.get(task.raw) ?? 0;
    seen.set(task.raw, index + 1);
    const converted = convertTask(task, uidFor(task, index));
    report.bySource[converted.source] = (report.bySource[converted.source] ?? 0) + 1;
    report.entries.push(...converted.entries);

    if (converted.kind === 'event') {
      report.events++;
      const e = converted.event;
      bucket(e.rrule ? RECURRING : monthFile(e.start.date)).events.push({ line: task.line, value: e });
    } else {
      report.reminders++;
      const r = converted.reminder;
      if (r.rrule) bucket(RECURRING).reminders.push({ line: task.line, value: r });
      else if (r.due) bucket(monthFile(r.due.date)).reminders.push({ line: task.line, value: r });
      else undated.push({ task, reminder: r });
    }
  }

  if (report.events + report.reminders !== tasks.length) {
    throw new Error(`export lost lines: ${tasks.length} in, ${report.events + report.reminders} out`);
  }

  const earliest = [...buckets.keys()].filter(k => k !== RECURRING).sort()[0];
  for (const { task, reminder } of undated) {
    const created = task.creationDate && DATE_RE.test(task.creationDate) ? monthFile(task.creationDate) : undefined;
    bucket(created ?? earliest ?? '1970-01.ics').reminders.push({ line: task.line, value: reminder });
  }

  const names = [...buckets.keys()].sort((a, b) =>
    a === RECURRING ? -1 : b === RECURRING ? 1 : a.localeCompare(b));
  const files: Record<string, string> = {};
  for (const name of names) {
    const b = buckets.get(name)!;
    const bySourceLine = <T>(a: Placed<T>, c: Placed<T>) => a.line - c.line;
    files[name] = serializeCalendar(
      [...b.events].sort(bySourceLine).map(p => p.value),
      [...b.reminders].sort(bySourceLine).map(p => p.value),
    );
  }

  report.entries.sort((a, b) => a.line - b.line);
  return { files, report };
}

export function formatReport(report: ExportReport): string {
  const lines = [`${report.lines} lines -> ${report.events} events + ${report.reminders} reminders`, '', 'By source:'];
  for (const [source, count] of Object.entries(report.bySource).sort(([a], [b]) => a.localeCompare(b))) {
    lines.push(`  ${source}: ${count}`);
  }
  lines.push('');
  if (report.entries.length === 0) {
    lines.push('No report entries.');
  } else {
    lines.push(`Report entries (${report.entries.length}):`);
    for (const e of report.entries) lines.push(`  line ${e.line}: ${e.kind} - ${e.detail}`);
  }
  return lines.join('\n') + '\n';
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bun test shared/tests/commands/exportIcs.test.ts`
Expected: PASS. **If a golden comparison fails**, the diff shows which side is wrong: compare the actual output to the fixture line by line. The fixture is authoritative (it was parsed successfully by the real `ICSParser` in Task 1); fix the converter, unless the mismatch reveals that the fixture contradicts the spec — in that case stop and report instead of editing the fixture.

- [ ] **Step 5: Run the whole shared suite**

Run: `bun test shared`
Expected: all pass (no regression in existing shared tests).

- [ ] **Step 6: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add shared/commands/exportIcs.ts shared/tests/commands/exportIcs.test.ts
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "feat(shared): applyExportIcs, reproducing the golden fixtures byte for byte" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 9: The `export-ics` console command

**Files:**
- Create: `console/commands/export-ics.ts`
- Modify: `console/index.ts` (import + a `case` before `default:`), `console/commands/help.ts` (one command line)
- Test: `console/tests/commands/export-ics.test.ts`

**Interfaces:**
- Consumes: `readTasks(filePath)` from `console/store.ts`; `applyExportIcs`, `formatReport` (Task 8).
- Produces: `export function exportIcsCommand(filePath: string, args: string[]): void`. Args: `--out <dir>` (default `./stark-export`), `--force`. Writes `recurring.ics`, `YYYY-MM.ics` files and `export-report.txt` into the directory; prints a summary. Exits 1 (message on stderr) for: unknown option, missing todo file, non-empty output directory without `--force`. With `--force` it first deletes only files named `recurring.ics`, `YYYY-MM.ics` or `export-report.txt` (so a stale month file from an earlier run cannot survive) and leaves everything else alone.

- [ ] **Step 1: Write the failing tests**

Create `console/tests/commands/export-ics.test.ts`:

```ts
import { test, expect, describe, beforeEach, afterEach } from 'bun:test';
import { spawnSync } from 'child_process';
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync, readdirSync, mkdirSync } from 'fs';
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
});
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test console/tests/commands/export-ics.test.ts`
Expected: FAIL (unknown command `export-ics`).

- [ ] **Step 3: Write the command**

Create `console/commands/export-ics.ts`:

```ts
import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from 'fs';
import { join, resolve } from 'path';
import { readTasks } from '../store';
import { applyExportIcs, formatReport } from '../../shared/commands/exportIcs';

const EXPORT_FILE_RE = /^(recurring|\d{4}-\d{2})\.ics$|^export-report\.txt$/;

export function exportIcsCommand(filePath: string, args: string[]): void {
  let out = './stark-export';
  let force = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--out' && i + 1 < args.length) {
      out = args[i + 1]!;
      i++;
    } else if (args[i] === '--force') {
      force = true;
    } else {
      console.error(`todo: unknown option '${args[i]}' for export-ics`);
      process.exit(1);
    }
  }

  if (!existsSync(filePath)) {
    console.error(`todo: no todo file at ${filePath}`);
    process.exit(1);
  }

  const dir = resolve(out);
  if (existsSync(dir) && readdirSync(dir).length > 0) {
    if (!force) {
      console.error(`todo: ${dir} is not empty (use --force to overwrite a previous export)`);
      process.exit(1);
    }
    for (const name of readdirSync(dir)) {
      if (EXPORT_FILE_RE.test(name)) rmSync(join(dir, name));
    }
  }

  const result = applyExportIcs(readTasks(filePath));
  mkdirSync(dir, { recursive: true });
  for (const [name, content] of Object.entries(result.files)) {
    writeFileSync(join(dir, name), content, 'utf8');
  }
  const report = formatReport(result.report);
  writeFileSync(join(dir, 'export-report.txt'), report, 'utf8');

  console.log(report);
  console.log(`Wrote ${Object.keys(result.files).length} files and export-report.txt to ${dir}`);
}
```

- [ ] **Step 4: Route it and document it**

In `console/index.ts` add `import { exportIcsCommand } from './commands/export-ics';` next to the other command imports, and add this case immediately before `default:`:

```ts
  case 'export-ics': {
    exportIcsCommand(filePath, filteredArgs.slice(1));
    break;
  }
```

In `console/commands/help.ts`, add this line to the `Commands:` list right after the `reminders [list]` line:

```
  export-ics          Export to the native Stark app's .ics files (--out <dir>, --force)
```

- [ ] **Step 5: Run to verify pass, then the full console suite**

Run: `bun test console/tests/commands/export-ics.test.ts` → PASS.
Run: `bun test shared console` → all pass. (A pre-existing "unexpected output from Reminders app / osascript failed" message on stderr is unrelated noise from the reminders test.)

- [ ] **Step 6: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add console/commands/export-ics.ts console/index.ts console/commands/help.ts console/tests/commands/export-ics.test.ts
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "feat(console): export-ics command" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 10: Run it on the real file and reconcile the counts; document the command

This is the spec's acceptance criterion 4. **No code changes unless a check fails.** Scratch output goes outside the repo: below, `OUT` means `/private/tmp/stark-export-real` (or `<scratchpad>/stark-export-real` if your session has a scratchpad directory). The author's file is at `$TODO_FILE`.

**Files:**
- Modify: `CLAUDE.md` (Console Layer section)

- [ ] **Step 1: Export the real file**

Run: `bun run /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/console/index.ts --file "$TODO_FILE" export-ics --out OUT --force`
Expected: exit 0; `OUT` contains `recurring.ics`, `export-report.txt` and one `YYYY-MM.ics` per month.

- [ ] **Step 2: Check the totals and every source bucket**

Read `OUT/export-report.txt`. The first line must be exactly:
`8302 lines -> 3337 events + 4965 reminders`
and the `By source:` block must be exactly:

```
  done-event: 155
  done-plain: 4665
  done-recurring: 5
  done-with-start: 165
  open-anniversary: 9
  open-birthday: 72
  open-event: 3096
  open-task: 135
```

If any number differs, **stop and report** the difference; do not adjust the expectation. (These come from the spec's data table, counted with the repo's own parser.)

- [ ] **Step 3: Classify every report entry**

Count entries by kind: `grep -c ": undated - " OUT/export-report.txt` (and likewise `ignored-extension`, `finished-series`, `end-before-start`, `unsupported-recurrence`, `event-without-start`, `untitled`). Expected on the author's real file (confirmed by the first real run): `undated` = 6; `ignored-extension` = 3 (one `frequency-day` on a monthly rule, and two completed lines with a malformed `start:`); `unsupported-recurrence` = 1 (a yearly task with `due:` and no `start:`, imported as a one-off like the console does); `end-before-start` = 3 (stale `end:` values); `event-without-start` and `untitled` = 0. `finished-series` and `end-before-start` are data-dependent: list each with its line number in your report, and confirm by looking at the source line that each is real.
If any entry kind or count differs from the list above (an extra `unsupported-recurrence`, any `event-without-start` or `untitled`, or a new kind), **stop and report the lines**.

- [ ] **Step 4: Document the command in CLAUDE.md**

In `CLAUDE.md`, at the end of the "Console Layer" section (just before the "Mobile Layer" heading), add:

```markdown
**`export-ics` converts a todo.txt into the native app's files** (`console/commands/export-ics.ts` → pure transform `shared/commands/exportIcs.ts`, built from `shared/ics/*`): `t export-ics [--out DIR] [--force]` writes `recurring.ics`, one `YYYY-MM.ics` per month and an `export-report.txt` (default `./stark-export`; refuses a non-empty directory without `--force`, which deletes only earlier export files). Design: `docs/superpowers/specs/2026-09-20-todo-txt-to-native-migration-design.md`. The output format is exactly what the Swift `ICSSerializer` writes (CRLF, floating local times, `;VALUE=DATE` for all-day, one `EXDATE` line each) and is pinned by golden fixtures in `shared/tests/fixtures/ics/expected/` that a Swift test (`ExportFixtureTests`) parses with the real `ICSParser`; if you change either side, both suites must still pass. Rules worth knowing: only the known structural keys are removed from a title (tags, `bus:16:00`, and times in prose like `9:00` stay); recurring *reminders* are re-based to the first occurrence after `last-done:`/the `x` date while recurring *events* keep their original start (a birthday keeps its birth year); a done line with `frequency:` + `start:` is a live series, not history; `frequency-month-day` is valid on monthly **and** yearly rules; native positions stop at `fourth`/`last`, so an unrepresentable rule (`fifth-*`) is imported as a one-off and reported, never dropped. Every line is accounted for: events + reminders always equals the input line count (`applyExportIcs` throws otherwise). Known gaps (multi-day events show only on their start day, undated tasks and overdue tasks older than 90 days are invisible in the native agenda) are listed in the spec.
```

- [ ] **Step 5: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add CLAUDE.md
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "docs: document export-ics in CLAUDE.md" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 11: The parity harness (expected agenda from TypeScript, actual agenda from Swift)

The spec's acceptance test: for a given day, the native `buildAgendaItems` over the exported files must show the same items as the console's own occurrence logic over the original `todo.txt`. Scope and exemptions are in the spec ("Testing and acceptance", item 3).

**Files:**
- Create: `console/scripts/parity-expected.ts`
- Test: `console/tests/scripts/parity-expected.test.ts`
- Create: `ios/Tests/StarkKitTests/ParityTests.swift`

**Interfaces:**
- Consumes: `generateTaskOccurrences` (`shared/commands/focus.ts`), `addDays` (`shared/utils.ts`), `cleanTitle`/`parseWall` (Task 4), `PlannerFile(directory:pendingDirectory:)`, `PlannerStore`, `AgendaWindow.loadRange(around:)`, `buildAgendaItems(events:reminders:in:today:)`, `AgendaItem` (StarkKit).
- Produces: `bun run console/scripts/parity-expected.ts --file <todo.txt> --today YYYY-MM-DD` prints JSON `{ today, windowDays, window: Row[], overdueOneOffs: Row[], exempt: { olderOverdue: number, multiDayEvents: number } }` where `Row = { kind: 'event'|'reminder', date, time: 'HH:MM'|null, title }` (a `00:00` time is `null`; rows sorted by key). And a Swift suite that reads two env vars, `STARK_PARITY_DIR` (an export directory) and `STARK_PARITY_EXPECTED` (that JSON file), and is **skipped when they are unset**.

- [ ] **Step 1: Write the failing script test**

Create `console/tests/scripts/parity-expected.test.ts`:

```ts
import { test, expect } from 'bun:test';
import { spawnSync } from 'child_process';
import { join } from 'path';

const SAMPLE = join(import.meta.dir, '../../../shared/tests/fixtures/ics/sample.todo.txt');
const run = () => {
  const r = spawnSync('bun', ['console/scripts/parity-expected.ts', '--file', SAMPLE, '--today', '2026-09-20'], { encoding: 'utf8' });
  return { code: r.status ?? 0, json: JSON.parse(r.stdout || '{}'), stderr: r.stderr ?? '' };
};

test('emits the expected window rows for the sample fixture', () => {
  const { code, json } = run();
  expect(code).toBe(0);
  expect(json.today).toBe('2026-09-20');
  expect(json.windowDays).toBe(14);
  const keys = (json.window as Array<{ kind: string; date: string; time: string | null; title: string }>)
    .map(r => `${r.kind}|${r.date}|${r.time ?? '-'}|${r.title}`);
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bun test console/tests/scripts/parity-expected.test.ts`
Expected: FAIL (the script does not exist).

- [ ] **Step 3: Write the script**

Create `console/scripts/parity-expected.ts`:

```ts
import { readFileSync } from 'fs';
import { parseLine } from '../../shared/parser';
import type { Task } from '../../shared/parser';
import { addDays } from '../../shared/utils';
import { generateTaskOccurrences } from '../../shared/commands/focus';
import { cleanTitle, parseWall } from '../../shared/ics/fields';

interface Row { kind: 'event' | 'reminder'; date: string; time: string | null; title: string }

function arg(name: string): string {
  const i = process.argv.indexOf(name);
  if (i < 0 || i + 1 >= process.argv.length) {
    console.error(`parity-expected: missing ${name}`);
    process.exit(1);
  }
  return process.argv[i + 1]!;
}

const WINDOW_DAYS = 14;
const LOOKBACK_DAYS = 90;
const TYPED = new Set(['event', 'birthday', 'anniversary']);
const file = arg('--file');
const today = arg('--today');
const windowEnd = addDays(today, WINDOW_DAYS);
const oldest = addDays(today, -LOOKBACK_DAYS);

const tasks: Task[] = readFileSync(file, 'utf8')
  .split('\n').filter(l => l.trim() !== '').map((l, i) => parseLine(l, i + 1));

function dailyDates(task: Task, from: string, to: string): string[] {
  const start = task.extensions['start']!.slice(0, 10);
  const every = parseInt(task.extensions['every'] ?? '1', 10) || 1;
  const until = task.extensions['recur-until'];
  const excluded = new Set((task.extensions['exdate'] ?? '').split(',').filter(Boolean));
  const dates: string[] = [];
  for (let d = start; d <= to; d = addDays(d, every)) {
    if (until && d > until) break;
    if (d >= from && !excluded.has(d)) dates.push(d);
  }
  return dates;
}

// Occurrence dates in [from, to]. A non-recurring item counts on its START day only, because the
// native agenda expands an event onto its start day (multi-day rows are a documented exemption).
function occurrenceDates(task: Task, from: string, to: string): string[] {
  const start = task.extensions['start'];
  if (!start) return [];
  const startDate = start.slice(0, 10);
  const frequency = task.extensions['frequency'];
  if (!frequency) return startDate >= from && startDate <= to ? [startDate] : [];
  if (frequency === 'daily') return dailyDates(task, from, to);
  return generateTaskOccurrences(task, from, to).map(o => o.date);
}

const rowOf = (kind: Row['kind'], date: string, time: string | null, title: string): Row =>
  ({ kind, date, time: time === '00:00' ? null : time, title });
const keyOf = (r: Row) => `${r.kind}|${r.date}|${r.time ?? '-'}|${r.title}`;

const window: Row[] = [];
const overdueOneOffs: Row[] = [];
let olderOverdue = 0;
let multiDayEvents = 0;

for (const task of tasks) {
  const ext = task.extensions;
  const typed = ext['type'] !== undefined && TYPED.has(ext['type']!);
  const recurring = !!ext['frequency'] && !!ext['start'];
  // Completed one-offs are history, not agenda rows. Completed recurring lines are live series.
  if (task.done && !recurring) continue;
  const title = cleanTitle(task.text);
  const time = parseWall(ext['start'])?.time ?? null;

  if (typed) {
    const end = ext['end']?.slice(0, 10);
    if (!recurring && end && ext['start'] && end > ext['start'].slice(0, 10)) multiDayEvents++;
    for (const date of occurrenceDates(task, today, windowEnd)) window.push(rowOf('event', date, time, title));
    continue;
  }

  // Untyped: a reminder. Undated items are invisible in the native agenda and are not compared.
  const dueWall = parseWall(ext['start']) ?? parseWall(ext['due']);
  if (!dueWall) continue;
  if (recurring) {
    for (const date of occurrenceDates(task, today, windowEnd)) window.push(rowOf('reminder', date, time, title));
  } else if (dueWall.date >= today && dueWall.date <= windowEnd) {
    window.push(rowOf('reminder', dueWall.date, dueWall.time, title));
  } else if (dueWall.date < today) {
    if (dueWall.date >= oldest) overdueOneOffs.push(rowOf('reminder', dueWall.date, dueWall.time, title));
    else olderOverdue++;
  }
}

window.sort((a, b) => keyOf(a).localeCompare(keyOf(b)));
overdueOneOffs.sort((a, b) => keyOf(a).localeCompare(keyOf(b)));
console.log(JSON.stringify({ today, windowDays: WINDOW_DAYS, window, overdueOneOffs, exempt: { olderOverdue, multiDayEvents } }, null, 2));
```

- [ ] **Step 4: Run to verify pass**

Run: `bun test console/tests/scripts/parity-expected.test.ts`
Expected: PASS.

- [ ] **Step 5: Write the Swift parity suite**

Create `ios/Tests/StarkKitTests/ParityTests.swift`:

```swift
// ios/Tests/StarkKitTests/ParityTests.swift
//
// Acceptance test for the todo.txt migration. Skipped unless both env vars are set:
//   STARK_PARITY_DIR       an export directory written by `t export-ics`
//   STARK_PARITY_EXPECTED  the JSON written by console/scripts/parity-expected.ts
// It loads the export into a real PlannerStore and compares the native agenda with the rows the
// console's own occurrence logic expects. Read-only: the export directory is never written to.
import Testing
import Foundation
@testable import StarkKit

private struct Row: Codable, Hashable {
    let kind: String
    let date: String
    let time: String?
    let title: String
}

private struct Expected: Codable {
    let today: String
    let windowDays: Int
    let window: [Row]
    let overdueOneOffs: [Row]
}

private let env = ProcessInfo.processInfo.environment
private let parityEnabled = env["STARK_PARITY_DIR"] != nil && env["STARK_PARITY_EXPECTED"] != nil
private let cal = Calendar(identifier: .gregorian)

private func key(_ r: Row) -> String { "\(r.kind)|\(r.date)|\(r.time ?? "-")|\(r.title)" }

private func multiset(_ keys: [String]) -> [String: Int] {
    Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +)
}

private func timeString(_ item: AgendaItem) -> String? {
    if case .event(let event) = item.kind, event.isAllDay { return nil }
    let c = cal.dateComponents([.hour, .minute], from: item.occurrence)
    if c.hour == 0 && c.minute == 0 { return nil }
    return String(format: "%02d:%02d", c.hour!, c.minute!)
}

private func nativeKey(_ item: AgendaItem) -> String {
    let kind: String
    switch item.kind {
    case .event: kind = "event"
    case .reminder: kind = "reminder"
    }
    return "\(kind)|\(DateMath.isoDate(from: item.occurrence))|\(timeString(item) ?? "-")|\(item.title)"
}

/// Missing = expected by the console but absent natively; extra = shown natively but not expected.
private func diff(expected: [String: Int], got: [String: Int]) -> (missing: [String], extra: [String]) {
    var missing: [String] = []
    var extra: [String] = []
    for (k, n) in expected where (got[k] ?? 0) < n { missing.append("\(k)  (expected \(n), got \(got[k] ?? 0))") }
    for (k, n) in got where (expected[k] ?? 0) < n { extra.append("\(k)  (expected \(expected[k] ?? 0), got \(n))") }
    return (missing.sorted(), extra.sorted())
}

private func describe(_ lines: [String]) -> String {
    (lines.prefix(40) + (lines.count > 40 ? ["… and \(lines.count - 40) more"] : [])).joined(separator: "\n")
}

@Suite("todo.txt migration parity", .enabled(if: parityEnabled))
struct ParityTests {
    private var dir: URL { URL(fileURLWithPath: env["STARK_PARITY_DIR"]!) }

    @Test("every exported file parses without warnings")
    func exportParsesCleanly() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".ics") }
        #expect(!names.isEmpty)
        var events = 0, reminders = 0
        for name in names {
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            let result = ICSParser.parse(text)
            #expect(result.warnings.isEmpty, "\(name): \(result.warnings)")
            events += result.events.count
            reminders += result.reminders.count
        }
        print("parity: parsed \(names.count) files, \(events) events, \(reminders) reminders")
    }

    @MainActor
    @Test("the native agenda matches the console's occurrences")
    func agendaMatchesTheConsole() throws {
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: URL(fileURLWithPath: env["STARK_PARITY_EXPECTED"]!)))
        let today = DateMath.date(from: expected.today)   // local noon of that day

        let pending = FileManager.default.temporaryDirectory.appendingPathComponent("parity-pending-\(UUID().uuidString)")
        let store = PlannerStore(file: PlannerFile(directory: dir, pendingDirectory: pending))
        let load = AgendaWindow.loadRange(around: today)
        store.start(windowStart: load.lowerBound, windowEnd: load.upperBound)
        #expect(store.error == nil, "\(store.error ?? "")")

        let start = cal.startOfDay(for: today)
        let after = cal.date(byAdding: .day, value: expected.windowDays + 1, to: start)!
        let items = buildAgendaItems(
            events: store.events, reminders: store.reminders,
            in: start...after.addingTimeInterval(-1), today: today)

        // (a) items dated today ... today + windowDays
        let window = diff(
            expected: multiset(expected.window.map(key)),
            got: multiset(items.filter { !$0.isCompleted && !$0.isOverdue }.map(nativeKey)))
        #expect(window.missing.isEmpty, "MISSING from the native agenda (\(window.missing.count)):\n\(describe(window.missing))")
        #expect(window.extra.isEmpty, "EXTRA in the native agenda (\(window.extra.count)):\n\(describe(window.extra))")

        // (b) one-off reminders overdue by 1...90 days
        let overdue = diff(
            expected: multiset(expected.overdueOneOffs.map(key)),
            got: multiset(items.filter { $0.isOverdue && !$0.isRecurring }.map(nativeKey)))
        #expect(overdue.missing.isEmpty, "MISSING overdue one-offs (\(overdue.missing.count)):\n\(describe(overdue.missing))")
        #expect(overdue.extra.isEmpty, "EXTRA overdue one-offs (\(overdue.extra.count)):\n\(describe(overdue.extra))")
    }
}
```

- [ ] **Step 6: Smoke-test the harness on the sample fixture**

This proves the harness itself before it is pointed at real data.

```bash
bun run /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/console/index.ts --file /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/shared/tests/fixtures/ics/sample.todo.txt export-ics --out SAMPLE_OUT --force
bun run /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/console/scripts/parity-expected.ts --file /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/shared/tests/fixtures/ics/sample.todo.txt --today 2026-09-20 > SAMPLE_EXPECTED.json
```

(`SAMPLE_OUT` and `SAMPLE_EXPECTED.json` are scratch paths outside the repo.) Then, from `/Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/ios`:

`STARK_PARITY_DIR=SAMPLE_OUT STARK_PARITY_EXPECTED=SAMPLE_EXPECTED.json swift test --filter ParityTests`
Expected: 2 tests PASS. Also run `swift test` with **no** env vars: the parity suite is reported skipped and everything else passes.
If the smoke test fails, the harness (or an assumption in it) is wrong: fix the harness, not the fixtures. Note that `--today 2026-09-20` is fixed so this smoke test does not depend on the real clock.

- [ ] **Step 7: Commit**

```bash
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps add console/scripts/parity-expected.ts console/tests/scripts/parity-expected.test.ts ios/Tests/StarkKitTests/ParityTests.swift
git -C /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps commit -m "test: parity harness comparing the native agenda with the console's occurrences" -m "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

### Task 12: Parity on the real file, then the device import

Task 10 already exported the real file to `OUT`. This task is investigative by nature, so it has an explicit triage policy instead of a fixed expected result. **Never touch the author's phone in steps 1–5; step 6 is for the controller and the author only.**

**Files:** none created unless a converter bug is found (then: a failing unit test in `shared/tests/ics/` plus the fix, one commit per bug).

- [ ] **Step 1: Generate the expected agenda for today**

Run: `bun run /Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/console/scripts/parity-expected.ts --file "$TODO_FILE" --today $(date +%F) > REAL_EXPECTED.json` (`REAL_EXPECTED.json` is a scratch path outside the repo). Read the `exempt` block: `olderOverdue` (open one-offs overdue by more than 90 days) and `multiDayEvents` are the spec's documented exemptions; note both numbers for the final report.

- [ ] **Step 2: Re-export if the file changed since Task 10**

If `$TODO_FILE` was modified since Task 10 step 1 (compare `ls -la` to the export time), re-run that export so both sides describe the same file.

- [ ] **Step 3: Run the parity suite**

From `/Users/eladio/src/todo-txt/.claude/worktrees/ios-mvp-gaps/ios`: `STARK_PARITY_DIR=OUT STARK_PARITY_EXPECTED=REAL_EXPECTED.json swift test --filter ParityTests`
Expected outcome A: 2 tests PASS (zero missing, zero extra). Go to step 5.
Otherwise the failure message lists `MISSING` (console expects, native lacks) and `EXTRA` (native shows, console does not) rows in the form `kind|date|time|title`.

- [ ] **Step 4: Triage every mismatch (do not guess)**

For each listed title, `grep -n` it in `$TODO_FILE` to find the source line, then classify:

1. **Converter bug** (wrong date, time, title, rule or anchor — e.g. an occurrence on the wrong weekday, a missing exception date, a re-base landing on the wrong day): write a failing unit test in `shared/tests/ics/` that reproduces the source line (copy the line with private text replaced by a placeholder title), see it fail, fix the module, re-run `bun test shared console`, re-export, re-run step 3. One commit per bug: `fix(shared): <what was wrong>`.
2. **The week-alignment risk** — a weekly series with `every:N` (N > 1) **and** `frequency-day:` (the spec expects 7 such tasks). If a mismatch involves only these: **stop and report to the author** with, for each, the source line, the console's dates and the native dates for the window. Do not change the converter's semantics without their decision.
3. **Anything else** (a divergence that is neither a converter bug nor already an exemption in the spec): **stop and report** with the row and the source line. Do not add a new exemption yourself.

Repeat steps 3–4 until there are no mismatches, or every remaining one has been reported to the author.

- [ ] **Step 5: Final verification**

Run from the worktree root: `bun test shared console` → all pass. Run from `ios/`: `swift test` (no env vars) → all pass, parity suite skipped. Report: the totals from Task 10, the parity result (pass, or the reported mismatches), and the `exempt` numbers.

- [ ] **Step 6: Import into the phone (controller and author only)**

The author has confirmed the export looks right in the report. Back up first (the app currently holds only test data, but the copy overwrites same-named month files):

```bash
xcrun devicectl device copy from --device <device-id> --domain-type appDataContainer --domain-identifier com.caritos.todo-txt --source /Documents --destination PHONE_BACKUP
xcrun devicectl device copy to --device <device-id> --domain-type appDataContainer --domain-identifier com.caritos.todo-txt --source OUT --destination /Documents
```

(`PHONE_BACKUP` is a scratch directory. The phone must be unlocked. Do not copy `export-report.txt` into the app if you prefer a clean folder: it is ignored by the app either way.) Then the author force-quits and reopens Stark and checks by eye: today's agenda against `t focus`; a busy month's density markers; a known weekly item (e.g. church); a birthday; a checkbox completion on an imported reminder; and that the known gaps behave as documented (multi-day events on their first day only; undated and >90-day-old overdue tasks absent).
If anything looks wrong, restore with `devicectl device copy to … --source PHONE_BACKUP --destination /Documents`.

---

## Self-Review

- **Spec coverage:** overview decisions → Tasks 8–9 (TS converter, direct `.ics`), fixtures/tests throughout; data table → Task 10 step 2; architecture and file format → Tasks 1, 2, 8, 9; classification → Task 7; dates/times/ends → Tasks 4, 7; title/notes/location/priority → Tasks 4, 7; RRULE table and edge rules → Task 3, 7; anchors → Tasks 6, 7; ids and placement → Tasks 5, 8; phone delivery → Task 12 step 6; testing items 1–4 → Tasks 2–8 (unit), 1 and 8 (golden, cross-language), 11–12 (parity), 10 (reconciliation); known gaps → the spec itself and CLAUDE.md (Task 10).
- **Placeholder scan:** the only substitutable names are scratch paths (`OUT`, `SAMPLE_OUT`, `SAMPLE_EXPECTED.json`, `REAL_EXPECTED.json`, `PHONE_BACKUP`), each defined where first used; every code step contains its code.
- **Type consistency:** `Wall`, `IcsEvent`, `IcsReminder` (Task 2) are used unchanged in Tasks 4, 7, 8; `RRuleResult`/`buildRRule` (Task 3) in Task 7; `Anchor`/`rebaseAnchor` (Task 6) in Task 7; `Converted`/`ReportEntry`/`SourceBucket`/`convertTask` (Task 7) in Task 8; `ExportResult`/`applyExportIcs`/`formatReport` (Task 8) in Task 9; `makeUid(raw, index)` (Task 5) matches `ExportOptions.uid(task, duplicateIndex)`'s default in Task 8.
