import type { Controller } from "../controller.ts";
import type { BulkOutcome, BulkProgress, BulkStarted } from "./bulk-actions.ts";

import { defineController } from "../controller.ts";

export interface BulkSelectionOptions {
  /**
   * Runs the action on the selected rows, e.g. a server action that calls
   * `bulkActions.apply({ organizationId, subjectType, rows, action, args })`.
   */
  readonly run: (input: {
    readonly rows: readonly string[];
    readonly action: string;
    readonly args?: Readonly<Record<string, unknown>> | undefined;
  }) => Promise<BulkOutcome>;
  /**
   * Follows a background run: calls `onProgress` for each update and returns
   * the cleanup. Without it a started run shows its `started` info only.
   */
  readonly watch?:
    | ((
        started: BulkStarted,
        onProgress: (progress: BulkProgress) => void,
      ) => () => void)
    | undefined;
}

export interface BulkSelectionSnapshot {
  /** The selected row ids, in the order they were selected. */
  readonly selected: readonly string[];
  /** Whether a run is waiting for its answer. */
  readonly pending: boolean;
  /** The outcome of the last run. */
  readonly outcome: BulkOutcome | undefined;
  /** The latest progress of a background run. */
  readonly progress: BulkProgress | undefined;
  /** What the last failed run threw; cleared by the next run. */
  readonly error: unknown;
}

export interface BulkSelectionActions {
  readonly select: (id: string) => void;
  readonly deselect: (id: string) => void;
  readonly toggle: (id: string) => void;
  /** Selects `ids` (a page of rows), keeping what is already selected. */
  readonly selectMany: (ids: readonly string[]) => void;
  readonly clear: () => void;
  /**
   * Runs `action` on the selection. Resolves the outcome, or `undefined` when
   * nothing is selected, a run is pending, or the call threw (see `error`). A
   * run that finished for every row clears the selection; one with failures
   * keeps only the failed rows selected, so a retry targets them.
   */
  readonly run: (input: {
    readonly action: string;
    readonly args?: Readonly<Record<string, unknown>>;
  }) => Promise<BulkOutcome | undefined>;
}

export type BulkSelectionController = Controller<
  BulkSelectionSnapshot,
  BulkSelectionActions
>;

/**
 * The selection and the run of a bulk action on the client, for a table's
 * checkbox column and its action bar.
 */
export function createBulkSelectionController(
  options: BulkSelectionOptions,
): BulkSelectionController {
  return defineController<BulkSelectionSnapshot, BulkSelectionActions>(
    {
      selected: [],
      pending: false,
      outcome: undefined,
      progress: undefined,
      error: undefined,
    },
    (state) => {
      let unwatch: (() => void) | undefined;

      const stopWatching = (): void => {
        unwatch?.();
        unwatch = undefined;
      };

      const add = (ids: readonly string[]): void => {
        state.set((current) => ({
          selected: [...new Set([...current.selected, ...ids])],
        }));
      };

      return {
        actions: {
          select: (id) => {
            add([id]);
          },
          selectMany: add,
          deselect: (id) => {
            state.set((current) => ({
              selected: current.selected.filter((row) => row !== id),
            }));
          },
          toggle: (id) => {
            state.set((current) => ({
              selected: current.selected.includes(id)
                ? current.selected.filter((row) => row !== id)
                : [...current.selected, id],
            }));
          },
          clear: () => {
            state.set({ selected: [] });
          },
          run: async ({ action, args }) => {
            const { selected, pending } = state.get();

            if (pending || selected.length === 0) {
              return;
            }

            const run = state.run();
            stopWatching();

            state.set({
              pending: true,
              error: undefined,
              outcome: undefined,
              progress: undefined,
            });

            try {
              const outcome = await options.run({
                rows: selected,
                action,
                args,
              });

              if (run !== state.run()) {
                return;
              }

              const failed =
                outcome.mode === "now"
                  ? outcome.results
                      .filter((row) => !row.ok)
                      .map((row) => row.id)
                  : [];

              state.set({ pending: false, outcome, selected: failed });

              if (outcome.mode === "background" && options.watch) {
                unwatch = options.watch(outcome, (progress) => {
                  if (run === state.run()) {
                    state.set({ progress });
                  }
                });
              }

              return outcome;
            } catch (error) {
              if (run === state.run()) {
                state.set({ pending: false, error });
              }

              return;
            }
          },
        },
        start: () => stopWatching,
      };
    },
  );
}
