"use client";

import type { UndoActions, UndoSnapshot, UndoStackOptions } from "../client.ts";

import { useController, useLatest } from "../../react-controller.ts";
import { createUndoController } from "../client.ts";

export type { UndoEntry } from "../client.ts";

export type UseUndoStackOptions = UndoStackOptions;

export interface UndoStack extends UndoSnapshot, UndoActions {}

/**
 * A stack of undo tokens on the client, for a toast's Undo button or a
 * Cmd+Z handler:
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
