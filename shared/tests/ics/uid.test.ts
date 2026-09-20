import { test, expect } from 'bun:test';
import { makeUid } from '../../ics/uid';

test('is UUID-shaped (version 5 nibble, RFC variant), upper-case', () => {
  expect(makeUid('a line', 0)).toMatch(/^[0-9A-F]{8}-[0-9A-F]{4}-5[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/);
});
test('is deterministic', () => {
  expect(makeUid('a line', 0)).toBe(makeUid('a line', 0));
});
test('golden vector: exported ids can never drift silently', () => {
  expect(makeUid('a line', 0)).toBe('3C686D6A-70B5-5ECD-8B70-2702BA8B9FDF');
});
test('an empty raw line and a unicode raw line still produce stable, well-formed ids', () => {
  const shape = /^[0-9A-F]{8}-[0-9A-F]{4}-5[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/;
  for (const raw of ['', 'Café ☕ 日本語 🎂 start:2026-09-22']) {
    expect(makeUid(raw, 0)).toMatch(shape);
    expect(makeUid(raw, 0)).toBe(makeUid(raw, 0));
    expect(makeUid(raw, 0)).not.toBe(makeUid(raw, 1));
  }
  expect(makeUid('', 0)).not.toBe(makeUid('Café ☕ 日本語 🎂 start:2026-09-22', 0));
});
test('differs by line text and by duplicate index', () => {
  expect(makeUid('a line', 0)).not.toBe(makeUid('another line', 0));
  expect(makeUid('a line', 0)).not.toBe(makeUid('a line', 1));
});
