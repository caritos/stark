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
