export function helpCommand(): void {
  const help = `Usage: todo <command> [options]

Commands:
  add <text>          Add a new task (creation date stamped automatically)
  event <text>        Add a new event (creation date stamped, tagged type:event)
  import <ics-file>   Import events from an iCalendar (.ics) file
  reminders [list]    Import tasks from Apple Reminders (macOS only)
  export-ics          Export to the native Stark app's .ics files (--out <dir>, --force)
  focus               Show tasks and events in the next 2 weeks
  list [filters]      List open tasks, sorted by priority. Filters: +project @context (A) keyword
  listall [filters]   List all tasks including completed
  edit <n> <text>     Replace task #n's text (creation date is preserved)
  done <n>            Mark task #n complete
  done <text>         Log ad-hoc task as already done (creates + completes in one step)
  skip <n>            Skip the upcoming occurrence of a recurring task
  rm <n>              Delete task #n permanently
  pri <n> <A-Z>       Set priority on task #n
  depri <n>           Remove priority from task #n
  search <term>       Full-text search across all tasks
  report              Stats: counts, by project/context, completed today/week

Options:
  --file <path>       Use a specific todo.txt file (overrides TODO_FILE env)

Scheduling extensions (for event and add):
  start:<date>        Start date: YYYY-MM-DD (all-day) or YYYY-MM-DDThh:mm (timed)
  end:<date>          End date: same format. Auto-set to start: if omitted on events.
  frequency:<freq>    Recurrence: daily | weekly | monthly | yearly
  every:<n>           Repeat every N units (default 1)
  frequency-day:<days>        Weekly days: M,T,W,Th,F,Sat,Sun (comma-separated)
  frequency-month-day:<val>   Monthly/yearly day: 1-31 or first-monday, last-weekend-day, etc.
  frequency-month:<months>    Yearly months: Jan,Feb,... (comma-separated)

Examples:
  todo add "Fix login bug +backend @work due:2026-05-10"
  todo add "(A) Urgent task"
  todo add "Pay bills frequency:monthly frequency-month-day:10"
  todo event "Team standup +work @office"
  todo event "Birthday party start:2026-05-10"
  todo event "Standup start:2026-05-10T09:00 end:2026-05-10T09:30 frequency:weekly frequency-day:M,W,F"
  todo event "Book club start:2026-05-06 frequency:monthly frequency-month-day:first-tuesday"
  todo edit 199 "Wedding Anniversary start:2004-05-01 frequency:yearly type:anniversary"
  todo focus
  todo list type:event
  todo list +backend
  todo list @work (B)
  todo done 3
  todo done "buy nina's yearbook"
  todo pri 5 A
  todo import family.ics
  todo --file work.txt import meetings.ics
  todo reminders
  todo reminders Work`;

  console.log(help);
}
