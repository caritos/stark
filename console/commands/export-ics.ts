import { existsSync, lstatSync, mkdirSync, readdirSync, statSync, unlinkSync, writeFileSync } from 'fs';
import { join, resolve } from 'path';
import { readTasks } from '../store';
import { applyExportIcs, formatReport } from '../../shared/commands/exportIcs';

const EXPORT_FILE_RE = /^(recurring|\d{4}-\d{2})\.ics$|^export-report\.txt$/;

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

function reason(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

export function exportIcsCommand(filePath: string, args: string[]): void {
  let out = './stark-export';
  let force = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--out') {
      const value = args[i + 1];
      if (value === undefined || value === '' || value.startsWith('--')) {
        fail('todo: --out requires a directory');
      }
      out = value;
      i++;
    } else if (args[i] === '--force') {
      force = true;
    } else {
      fail(`todo: unknown option '${args[i]}' for export-ics`);
    }
  }

  if (!existsSync(filePath)) fail(`todo: no todo file at ${filePath}`);

  const dir = resolve(out);
  const dirExists = existsSync(dir);
  if (dirExists && !statSync(dir).isDirectory()) fail(`todo: ${dir} exists and is not a directory`);
  const existing = dirExists ? readdirSync(dir) : [];
  if (existing.length > 0 && !force) {
    fail(`todo: ${dir} is not empty (use --force to overwrite a previous export)`);
  }

  // Build everything in memory first so a failure here leaves the directory untouched.
  const result = applyExportIcs(readTasks(filePath));
  const report = formatReport(result.report);
  const written = new Set<string>([...Object.keys(result.files), 'export-report.txt']);

  // Pre-scan: an export-named (or about-to-be-written) entry that is not a regular file or a
  // symlink (e.g. a directory) blocks the whole run, before anything is created, written or deleted.
  for (const name of existing) {
    if (!EXPORT_FILE_RE.test(name) && !written.has(name)) continue;
    const stat = lstatSync(join(dir, name));
    if (stat.isFile() || stat.isSymbolicLink()) continue;
    const kind = stat.isDirectory() ? 'a directory' : 'not a regular file';
    fail(`todo: ${join(dir, name)} is ${kind}; remove it or choose another --out`);
  }

  try {
    mkdirSync(dir, { recursive: true });
  } catch (err) {
    fail(`todo: cannot create ${dir}: ${reason(err)}`);
  }

  // Write the new export first, then prune, so a failure can never leave less than we started with.
  const contents: Array<[string, string]> = [...Object.entries(result.files), ['export-report.txt', report]];
  for (const [name, content] of contents) {
    const target = join(dir, name);
    try {
      // Never write through a symlink: replace the link itself.
      if (existing.includes(name) && lstatSync(target).isSymbolicLink()) unlinkSync(target);
      writeFileSync(target, content, 'utf8');
    } catch (err) {
      fail(`todo: cannot write ${target}: ${reason(err)}`);
    }
  }

  if (force) {
    for (const name of existing) {
      if (!EXPORT_FILE_RE.test(name) || written.has(name)) continue;
      const target = join(dir, name);
      try {
        const stat = lstatSync(target);
        if (stat.isFile() || stat.isSymbolicLink()) unlinkSync(target);
      } catch (err) {
        fail(`todo: cannot write ${target}: ${reason(err)}`);
      }
    }
  }

  process.stdout.write(report);
  console.log(`Wrote ${Object.keys(result.files).length} files and export-report.txt to ${dir}`);
}
