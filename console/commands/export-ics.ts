import { existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from 'fs';
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
  const dirExists = existsSync(dir);
  if (dirExists && !statSync(dir).isDirectory()) {
    console.error(`todo: ${dir} exists and is not a directory`);
    process.exit(1);
  }
  const hasContents = dirExists && readdirSync(dir).length > 0;
  if (hasContents && !force) {
    console.error(`todo: ${dir} is not empty (use --force to overwrite a previous export)`);
    process.exit(1);
  }

  // Build everything in memory first so a failure here leaves the directory untouched.
  const result = applyExportIcs(readTasks(filePath));
  const report = formatReport(result.report);

  if (hasContents) {
    for (const name of readdirSync(dir)) {
      if (EXPORT_FILE_RE.test(name)) rmSync(join(dir, name));
    }
  }

  try {
    mkdirSync(dir, { recursive: true });
  } catch (err) {
    console.error(`todo: cannot create ${dir}: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
  for (const [name, content] of Object.entries(result.files)) {
    writeFileSync(join(dir, name), content, 'utf8');
  }
  writeFileSync(join(dir, 'export-report.txt'), report, 'utf8');

  console.log(report);
  console.log(`Wrote ${Object.keys(result.files).length} files and export-report.txt to ${dir}`);
}
