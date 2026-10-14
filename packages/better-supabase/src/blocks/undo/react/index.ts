"use client";

import { useCallback, useRef, useState } from "react";

import type { UndoToken } from "../undo.ts";

export interface UndoEntry {
  readonly id: number;
  /** What the toast or menu shows, e.g. "Moved 3 tasks". */
  readonly label: string;
  readonly token: UndoToken;
}

export interface UseUndoStackOptions {
  /** Applies a token, e.g. a server action that calls `createUndo().apply(token)`. */
  readonly apply: (token: UndoToken) => Promise<unknown>;
  /** How many entries to keep; older ones drop off. Default 20. */
  readonly limit?: number;
}

export interface UndoStack {
  /** Newest last. */
  readonly entries: readonly UndoEntry[];
  readonly canUndo: boolean;
  /** Whether an undo is running. */
  readonly pending: boolean;
  /** What the last failed undo threw; cleared by the next push or undo. */
  readonly error: unknown;
  /** Adds a token; a `null` token (a change with no inverse) is ignored. */
  readonly push: (token: UndoToken | null | undefined, label?: string) => void;
  /**
   * Applies the newest entry and removes it. A failed undo removes it too,
   * since its rows changed since, and sets `error`. Resolves whether it worked.
   */
  readonly undo: () => Promise<boolean>;
  readonly clear: () => void;
}

/**
 * A stack of undo tokens in the browser, for a toast's Undo button or a
 * Cmd+Z handler:
 *
 * ```tsx
 * const stack = useUndoStack({ apply: undoAction });
 * const moved = await moveTasks(ids);
 * stack.push(moved.undo, `Moved ${ids.length} tasks`);
 * ```
 */
export function useUndoStack(options: UseUndoStackOptions): UndoStack {
  const [entries, setEntries] = useState<readonly UndoEntry[]>([]);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<unknown>(undefined);
  const latest = useRef(options);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = options;
  const stack = useRef<readonly UndoEntry[]>([]);
  const nextId = useRef(0);
  const running = useRef(false);

  const set = useCallback((next: readonly UndoEntry[]) => {
    stack.current = next;
    setEntries(next);
  }, []);

  const push = useCallback(
    (token: UndoToken | null | undefined, label = "") => {
      if (!token) return;
      nextId.current += 1;
      const limit = Math.max(1, latest.current.limit ?? 20);
      set(
        [...stack.current, { id: nextId.current, label, token }].slice(-limit),
      );
      setError(undefined);
    },
    [set],
  );

  const undo = useCallback(async () => {
    const top = stack.current.at(-1);
    if (!top || running.current) return false;
    running.current = true;
    setPending(true);
    setError(undefined);
    set(stack.current.slice(0, -1));
    let worked = true;
    try {
      await latest.current.apply(top.token);
    } catch (cause) {
      setError(cause);
      worked = false;
    }
    running.current = false;
    setPending(false);
    return worked;
  }, [set]);

  const clear = useCallback(() => {
    set([]);
    setError(undefined);
  }, [set]);

  return {
    entries,
    canUndo: entries.length > 0 && !pending,
    pending,
    error,
    push,
    undo,
    clear,
  };
}
