"use client";

import type {
  UndoActions,
  UndoSnapshot,
  UndoStackOptions,
} from "better-supabase/blocks/undo";

import { createUndoController } from "better-supabase/blocks/undo";
import { useController, useLatest } from "better-supabase/react";

export type { UndoEntry } from "better-supabase/blocks/undo";

export type UseUndoStackOptions = UndoStackOptions;

export interface UndoStack extends UndoSnapshot, UndoActions {}

/**
 * A stack of undo tokens on the client, for a toast's Undo button or a Cmd+Z
 * handler:
 *
 * ```tsx
 * const stack = useUndoStack({ apply: undoAction });
 * const moved = await moveTasks(ids);
 * stack.push(moved.undo, `Moved ${ids.length} tasks`);
 * ```
 */
export function useUndoStack(options: UseUndoStackOptions): UndoStack {
  const latest = useLatest(options);
  const { limit } = options;

  return useController(
    () =>
      createUndoController({
        apply: (token) => latest.current.apply(token),
        limit,
      }),
    [latest, limit],
  ).view;
}
