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
