import React, { createContext, useContext, useState, useCallback, useEffect, useRef } from 'react';
import type { Task } from '@shared/parser';
import {
  readTasks,
  writeTasks,
  resolveFile,
  resolveWeekStart,
  resolveStorageInfo,
  setWeekStart as storeSetWeekStart,
  pickICloudFolder as storePickICloudFolder,
  finalizeICloudStorage,
  disableICloudStorage,
  clearICloudBookmark,
} from '../store';
import type { StorageInfo } from '../store';
import { today } from '../utils';

type TaskContextValue = {
  tasks: Task[];
  filePath: string;
  storageInfo: StorageInfo;
  pickICloudFolder: () => Promise<{ folderBookmark: string; name: string; existingTasks: Task[] | null }>;
  finalizeICloud: (folderBookmark: string, name: string, overwrite: boolean) => Promise<void>;
  disableICloud: () => Promise<void>;
  weekStart: 0 | 1;
  setWeekStart: (ws: 0 | 1) => Promise<void>;
  loading: boolean;
  error: string | null;
  reload: () => Promise<void>;
  save: (updated: Task[]) => Promise<void>;
  pendingDateJump: string | null;
  requestDateJump: (date: string) => void;
  clearDateJump: () => void;
};

const TaskContext = createContext<TaskContextValue | null>(null);

export function TaskProvider({ children }: { children: React.ReactNode }) {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [filePath, setFilePath] = useState('');
  const [storageInfo, setStorageInfo] = useState<StorageInfo>({ mode: 'local', label: '' });
  const [weekStart, setWeekStartState] = useState<0 | 1>(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pendingDateJump, setPendingDateJump] = useState<string | null>(null);

  // Keep a ref so save() always sees the latest filePath even if the
  // callback closure hasn't been recreated yet (avoids stale-closure
  // race on fast interactions shortly after launch).
  const filePathRef = useRef('');
  const tasksRef = useRef<Task[]>([]);
  // Tracks whether the most recent reload's readTasks call succeeded.
  // enableICloud/disableICloud must never write tasksRef.current when this
  // is false — after a failed read, tasksRef still holds a stale/empty
  // snapshot (see the "Switch to Local" data-loss bug this guards against),
  // and writing that snapshot over a real file would destroy the user's
  // actual data.
  const lastReadOkRef = useRef(true);

  const reload = useCallback(async () => {
    const [path, ws, info] = await Promise.all([resolveFile(), resolveWeekStart(), resolveStorageInfo()]);
    filePathRef.current = path;
    setFilePath(path);
    setWeekStartState(ws);
    setStorageInfo(info);
    try {
      const loaded = await readTasks(path);
      tasksRef.current = loaded;
      setTasks(loaded);
      setError(null);
      lastReadOkRef.current = true;
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      lastReadOkRef.current = false;
    }
  }, []);

  const setWeekStart = useCallback(async (ws: 0 | 1) => {
    await storeSetWeekStart(ws);
    setWeekStartState(ws);
  }, []);

  const save = useCallback(
    async (updated: Task[]) => {
      if (!lastReadOkRef.current) {
        throw new Error('Cannot save: the current task list could not be loaded from storage. Fix the storage issue shown above first, or restart the app.');
      }
      const path = filePathRef.current || filePath;
      if (!path) throw new Error('File path not configured. Open Settings to set a location.');
      await writeTasks(path, updated);
      tasksRef.current = updated;
      setTasks(updated);
    },
    [filePath]
  );

  const pickICloudFolder = useCallback(async () => {
    if (!lastReadOkRef.current) {
      throw new Error('Cannot enable iCloud Drive: the current task list could not be loaded. Fix the storage issue shown above first, or restart the app.');
    }
    return storePickICloudFolder();
  }, []);

  const finalizeICloud = useCallback(
    async (folderBookmark: string, name: string, overwrite: boolean) => {
      await finalizeICloudStorage(folderBookmark, name, tasksRef.current, overwrite);
      await reload();
    },
    [reload]
  );

  const disableICloud = useCallback(async () => {
    if (!lastReadOkRef.current) {
      // Don't overwrite the local file with a known-bad (empty/stale)
      // in-memory snapshot — just drop the iCloud bookmark and let the
      // next reload fall back to reading whatever is genuinely on local
      // disk, untouched.
      await clearICloudBookmark();
      await reload();
      return;
    }
    await disableICloudStorage(tasksRef.current);
    await reload();
  }, [reload]);

  const requestDateJump = useCallback((date: string) => setPendingDateJump(date), []);
  const clearDateJump = useCallback(() => setPendingDateJump(null), []);

  useEffect(() => {
    reload().finally(() => setLoading(false));
  }, []);

  return (
    <TaskContext.Provider
      value={{
        tasks,
        filePath,
        storageInfo,
        pickICloudFolder,
        finalizeICloud,
        disableICloud,
        weekStart,
        setWeekStart,
        loading,
        error,
        reload,
        save,
        pendingDateJump,
        requestDateJump,
        clearDateJump,
      }}
    >
      {children}
    </TaskContext.Provider>
  );
}

export function useTasks(): TaskContextValue {
  const ctx = useContext(TaskContext);
  if (!ctx) throw new Error('useTasks must be called inside <TaskProvider>');
  return ctx;
}
