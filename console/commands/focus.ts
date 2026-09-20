import { existsSync } from 'fs';
import { readTasks } from '../store';
import { today, addDays, formatFocusTask } from '../output';
import { applyFocus } from '../../shared/commands/focus';
export { nextWeeklyDate, nextMonthlyDate, nextYearlyDate, focusSortKey } from '../../shared/commands/focus';

export function focusCommand(filePath: string): void {
  if (!existsSync(filePath)) {
    console.error("No todo.txt found in current directory. Run 'todo add' to create one.");
    process.exit(1);
  }
  const todayStr = today();
  const tasks = readTasks(filePath);
  const items = applyFocus(tasks, todayStr);

  if (items.length === 0) {
    console.log(`\x1b[2mNothing in focus for the next 2 weeks.\x1b[0m`);
    return;
  }

  const windowEnd = addDays(todayStr, 14);
  items.forEach(({ task, effectiveDate, recurrenceLabel, streak, overdueDate }) => {
    // effectiveDate collapses an overdue recurring task to today (for bucketing/sorting), which
    // would render a missed occurrence as "today". Show the missed date instead so it reads as
    // past due, keeping the start time-of-day. A cycle landing exactly on today stays "today".
    const shownDate = overdueDate && overdueDate < todayStr
      ? overdueDate + effectiveDate.slice(10)
      : effectiveDate;
    console.log(formatFocusTask(task, todayStr, shownDate, recurrenceLabel, streak));
  });
  console.log(`\x1b[2m${items.length} item${items.length === 1 ? '' : 's'} in focus (${todayStr} – ${windowEnd})\x1b[0m`);
}
