#!/usr/bin/env bun
import { resolveFile } from './store';
import { helpCommand } from './commands/help';
import { addCommand } from './commands/add';
import { listCommand } from './commands/list';
import { listallCommand } from './commands/listall';
import { doneCommand } from './commands/done';
import { rmCommand } from './commands/rm';
import { priCommand, depriCommand } from './commands/pri';
import { searchCommand } from './commands/search';
import { reportCommand } from './commands/report';
import { eventCommand } from './commands/event';
import { focusCommand } from './commands/focus';
import { editCommand } from './commands/edit';
import { importCommand } from './commands/import';
import { remindersCommand } from './commands/reminders';
import { skipCommand } from './commands/skip';
import { exportIcsCommand } from './commands/export-ics';

const args = process.argv.slice(2);

// Extract --file flag if present
let fileFlag: string | undefined;
const filteredArgs: string[] = [];

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--file' && i + 1 < args.length) {
    fileFlag = args[i + 1];
    i++; // Skip the next arg (the file path)
  } else {
    filteredArgs.push(args[i]!);
  }
}

// Resolve the file path
const filePath = resolveFile(fileFlag);

// Get the command
const cmd = filteredArgs[0];

// Route to commands
if (!cmd) {
  process.stdout.write('\x1Bc');
  focusCommand(filePath);
  process.exit(0);
}

if (cmd === 'help' || cmd === '--help' || cmd === '-h') {
  helpCommand();
  process.exit(0);
}

switch (cmd) {
  case 'add': {
    addCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'list': {
    listCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'listall': {
    listallCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'done': {
    doneCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'rm': {
    rmCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'pri': {
    priCommand(filePath, filteredArgs[1], filteredArgs[2]);
    break;
  }

  case 'depri': {
    depriCommand(filePath, filteredArgs[1]);
    break;
  }

  case 'search': {
    searchCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'event': {
    eventCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'focus': {
    process.stdout.write('\x1Bc');
    focusCommand(filePath);
    break;
  }

  case 'edit': {
    editCommand(filePath, filteredArgs[1], filteredArgs.slice(2));
    break;
  }

  case 'report': {
    reportCommand(filePath);
    break;
  }

  case 'import': {
    importCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'reminders': {
    remindersCommand(filePath, filteredArgs.slice(1));
    break;
  }

  case 'skip': {
    skipCommand(filePath, filteredArgs[1]);
    break;
  }

  case 'export-ics': {
    exportIcsCommand(filePath, filteredArgs.slice(1));
    break;
  }

  default:
    console.error(`todo: unknown command '${cmd}'`);
    process.exit(1);
}
