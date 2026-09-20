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
