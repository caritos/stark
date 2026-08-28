import * as FileSystem from 'expo-file-system';
import { NativeModules } from 'react-native';
import { parseLine, serializeTasks } from '@shared/parser';
import type { Task } from '@shared/parser';

type ExpoIcloudFileModule = {
  pickFolder(): Promise<{ folderBookmark: string; name: string }>;
  checkExistingFile(folderBookmark: string): Promise<{ exists: boolean; content: string | null }>;
  finalizeFile(folderBookmark: string, content: string, overwrite: boolean): Promise<{ bookmark: string }>;
  readFile(bookmark: string): Promise<string>;
  writeFile(bookmark: string, content: string): Promise<void>;
};

const ExpoIcloudFile = NativeModules.ExpoIcloudFile as ExpoIcloudFileModule;

const CONFIG_FILE = FileSystem.documentDirectory + 'todo-config.json';
const ICLOUD_PREFIX = 'icloud:';

// Always-writable default inside the app sandbox
export const LOCAL_PATH = FileSystem.documentDirectory
  ? FileSystem.documentDirectory + 'todo.txt'
  : null;

type Config = {
  weekStart?: 0 | 1;
  icloudBookmark?: string;
  icloudFolderName?: string;
};

export type StorageInfo = { mode: 'local' | 'icloud'; label: string };

async function readConfig(): Promise<Config> {
  try {
    const json = await FileSystem.readAsStringAsync(CONFIG_FILE!, { encoding: 'utf8' });
    return JSON.parse(json) as Config;
  } catch {
    return {};
  }
}

async function writeConfig(config: Config): Promise<void> {
  await FileSystem.writeAsStringAsync(CONFIG_FILE!, JSON.stringify(config), { encoding: 'utf8' });
}

// LOCAL_PATH is always computed fresh rather than trusted from persisted
// config — a persisted absolute path (embedding the sandbox container UUID)
// can go stale across a reinstall/rebuild and silently fail to read, wiping
// the task list. A security-scoped bookmark (icloudBookmark) is different:
// it's Apple's own mechanism specifically designed to survive across
// reinstalls/rebuilds by re-resolving to the current location, so persisting
// it does not reintroduce that failure mode.
export async function resolveFile(): Promise<string> {
  const config = await readConfig();
  if (config.icloudBookmark) return ICLOUD_PREFIX + config.icloudBookmark;
  return LOCAL_PATH!;
}

export async function resolveStorageInfo(): Promise<StorageInfo> {
  const config = await readConfig();
  if (config.icloudBookmark) {
    return { mode: 'icloud', label: `ICLOUD DRIVE — ${config.icloudFolderName ?? 'Unknown'}` };
  }
  return { mode: 'local', label: LOCAL_PATH ?? '' };
}

export async function resolveWeekStart(): Promise<0 | 1> {
  const config = await readConfig();
  return config.weekStart ?? 0;
}

export async function setWeekStart(weekStart: 0 | 1): Promise<void> {
  const config = await readConfig();
  await writeConfig({ ...config, weekStart });
}

function parseTaskLines(content: string): Task[] {
  return content
    .split('\n')
    .filter(line => line.trim().length > 0)
    .map((line, i) => parseLine(line, i + 1));
}

export async function readTasks(filePath: string): Promise<Task[]> {
  if (filePath.startsWith(ICLOUD_PREFIX)) {
    const bookmark = filePath.slice(ICLOUD_PREFIX.length);
    try {
      const content = await ExpoIcloudFile.readFile(bookmark);
      return parseTaskLines(content);
    } catch (e) {
      const detail = e instanceof Error ? e.message : String(e);
      throw new Error(`Could not access iCloud Drive folder. Open Settings to reconnect or switch to local storage. (${detail})`);
    }
  }

  try {
    const content = await FileSystem.readAsStringAsync(filePath, { encoding: 'utf8' });
    return parseTaskLines(content);
  } catch {
    return [];
  }
}

async function writeLocal(filePath: string, tasks: Task[]): Promise<void> {
  if (!filePath) throw new Error('File path not configured. Open Settings to set a location.');

  const dir = filePath.slice(0, filePath.lastIndexOf('/'));
  if (dir) {
    try {
      await FileSystem.makeDirectoryAsync(dir, { intermediates: true });
    } catch (mkdirErr) {
      let dirExists = false;
      try {
        const info = await FileSystem.getInfoAsync(dir);
        dirExists = info.exists;
      } catch {
        dirExists = true;
      }
      if (!dirExists) {
        const detail = mkdirErr instanceof Error ? mkdirErr.message : String(mkdirErr);
        throw new Error(`Could not create directory for todo.txt. Check the file path in Settings. (${detail})`);
      }
    }
  }
  try {
    await FileSystem.writeAsStringAsync(filePath, serializeTasks(tasks), { encoding: 'utf8' });
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    throw new Error(`Could not write to ${filePath.replace(/^file:\/\//, '')}. Check the file path in Settings. (${detail})`);
  }
}

export async function writeTasks(filePath: string, tasks: Task[]): Promise<void> {
  if (filePath.startsWith(ICLOUD_PREFIX)) {
    const bookmark = filePath.slice(ICLOUD_PREFIX.length);
    try {
      await ExpoIcloudFile.writeFile(bookmark, serializeTasks(tasks));
    } catch (e) {
      const detail = e instanceof Error ? e.message : String(e);
      throw new Error(`Could not access iCloud Drive folder. Open Settings to reconnect or switch to local storage. (${detail})`);
    }
    return;
  }

  await writeLocal(filePath, tasks);
}

// Picks a folder without writing anything to it yet, so the caller can
// detect a pre-existing todo.txt and ask the user how to resolve it before
// any content is written. See finalizeICloudStorage for the write step.
export async function pickICloudFolder(): Promise<{ folderBookmark: string; name: string; existingTasks: Task[] | null }> {
  const { folderBookmark, name } = await ExpoIcloudFile.pickFolder();
  const { exists, content } = await ExpoIcloudFile.checkExistingFile(folderBookmark);
  return { folderBookmark, name, existingTasks: exists ? parseTaskLines(content!) : null };
}

export async function finalizeICloudStorage(
  folderBookmark: string,
  name: string,
  tasks: Task[],
  overwrite: boolean
): Promise<{ name: string }> {
  const { bookmark } = await ExpoIcloudFile.finalizeFile(folderBookmark, serializeTasks(tasks), overwrite);

  const config = await readConfig();
  await writeConfig({ ...config, icloudBookmark: bookmark, icloudFolderName: name });
  return { name };
}

export async function clearICloudBookmark(): Promise<void> {
  const config = await readConfig();
  delete config.icloudBookmark;
  delete config.icloudFolderName;
  await writeConfig(config);
}

export async function disableICloudStorage(tasks: Task[]): Promise<void> {
  await writeLocal(LOCAL_PATH!, tasks);
  await clearICloudBookmark();
}
