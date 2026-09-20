import { createHash } from 'node:crypto';

// Deterministic so re-running the export gives byte-identical files; UUID-shaped so the ids
// look like the ones the native app generates itself.
export function makeUid(raw: string, index: number): string {
  const hex = createHash('sha1').update(`${raw}#${index}`).digest('hex');
  const variant = ((parseInt(hex[16]!, 16) & 0x3) | 0x8).toString(16);
  const uuid = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-${variant}${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
  return uuid.toUpperCase();
}
