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
