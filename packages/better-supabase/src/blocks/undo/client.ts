import type { Controller } from "../controller.ts";
import type { UndoToken } from "./undo.ts";

import { defineController } from "../controller.ts";

export interface UndoEntry {
  readonly id: number;
  /** What the toast or menu shows, e.g. "Moved 3 tasks". */
  readonly label: string;
  readonly token: UndoToken;
}

export interface UndoStackOptions {
  /** Applies a token, e.g. a server action that calls `createUndo().apply(token)`. */
  readonly apply: (token: UndoToken) => Promise<unknown>;
  /** How many entries to keep; older ones drop off. Default 20. */
  readonly limit?: number | undefined;
}

export interface UndoSnapshot {
  /** Newest last. */
  readonly entries: readonly UndoEntry[];
  readonly canUndo: boolean;
  /** Whether an undo is running. */
  readonly pending: boolean;
  /** What the last failed undo threw; cleared by the next push or undo. */
  readonly error: unknown;
}

export interface UndoActions {
  /** Adds a token; a `null` token (a change with no inverse) is ignored. */
  readonly push: (token: UndoToken | null | undefined, label?: string) => void;
  /**
   * Applies the newest entry and removes it. A failed undo removes it too,
   * since its rows changed since, and sets `error`. Resolves whether it worked.
   */
  readonly undo: () => Promise<boolean>;
  readonly clear: () => void;
}

export type UndoController = Controller<UndoSnapshot, UndoActions>;

/** A stack of undo tokens on the client, for a toast's Undo button or a Cmd+Z handler. */
export function createUndoController(
  options: UndoStackOptions,
): UndoController {
  return defineController<UndoSnapshot, UndoActions>(
    { entries: [], canUndo: false, pending: false, error: undefined },
    (state) => {
      let nextId = 0;
      const show = (
        entries: readonly UndoEntry[],
        pending: boolean,
        error: unknown,
      ): void => {
        state.set({
          entries,
          pending,
          error,
          canUndo: entries.length > 0 && !pending,
        });
      };
      return {
        actions: {
          push: (token, label = "") => {
            if (!token) return;
            nextId += 1;
            const limit = Math.max(1, options.limit ?? 20);
            const { entries, pending } = state.get();
            show(
              [...entries, { id: nextId, label, token }].slice(-limit),
              pending,
              undefined,
            );
          },
          undo: async () => {
            const { entries, pending } = state.get();
            const top = entries.at(-1);
            if (!top || pending) return false;
            show(entries.slice(0, -1), true, undefined);
            let error: unknown;
            let worked = true;
            try {
              await options.apply(top.token);
            } catch (cause) {
              error = cause;
              worked = false;
            }
            show(state.get().entries, false, error);
            return worked;
          },
          clear: () => {
            show([], state.get().pending, undefined);
          },
        },
      };
    },
  );
}
