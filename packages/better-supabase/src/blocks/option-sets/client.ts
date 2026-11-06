import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  OptionSet,
  OptionSetItemInput,
  OptionSets,
} from "./option-sets.ts";

import { defineController, whileSignedIn } from "../controller.ts";

export interface OptionSetsControllerOptions {
  readonly client: Pick<
    OptionSets,
    "archiveItem" | "ensure" | "list" | "reorderItem" | "saveItem"
  >;
  readonly auth: AuthPort;
  readonly organizationId: string;
  readonly subjectType: string;
  /** Sets this field's default set on load, so a new tenant gets its items. */
  readonly field?: string;
}

export interface OptionSetsSnapshot {
  /** `undefined` until the first load. */
  readonly sets: readonly OptionSet[] | undefined;
  readonly error: DbError | undefined;
}

export interface OptionSetsActions {
  readonly refresh: () => Promise<void>;
  readonly saveItem: (input: {
    optionSetId: string;
    input: OptionSetItemInput;
  }) => Promise<void>;
  /** Moves an item after `afterItemId`, or to the front without one. */
  readonly moveItem: (input: {
    optionSetId: string;
    itemId: string;
    afterItemId?: string;
  }) => Promise<void>;
  readonly archiveItem: (input: {
    itemId: string;
    replacementId?: string;
  }) => Promise<void>;
}

export type OptionSetsController = Controller<
  OptionSetsSnapshot,
  OptionSetsActions
>;

/** The organization's option sets of one subject type, with edit actions. */
export function createOptionSetsController(
  options: OptionSetsControllerOptions,
): OptionSetsController {
  const { client, organizationId, subjectType } = options;

  return defineController<OptionSetsSnapshot, OptionSetsActions>(
    { sets: undefined, error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        const run = state.run();

        if (options.field !== undefined) {
          const ensured = await client.ensure({
            organizationId,
            subjectType,
            field: options.field,
          });

          if (!ensured.ok) {
            if (run === state.run()) {
              state.set({ error: ensured.error });
            }

            return;
          }
        }

        const result = await client.list({ organizationId, subjectType });

        if (run !== state.run()) {
          return;
        }

        state.set(
          result.ok
            ? { sets: result.data, error: undefined }
            : { error: result.error },
        );
      };

      const after = async (result: Result<unknown>): Promise<void> => {
        if (!result.ok) {
          state.set({ error: result.error });

          return;
        }

        await refresh();
      };

      return {
        actions: {
          refresh,
          saveItem: async (input) => after(await client.saveItem(input)),
          moveItem: async ({ optionSetId, itemId, afterItemId }) => {
            const set = state
              .get()
              .sets?.find((candidate) => candidate.id === optionSetId);

            const items = (set?.items ?? []).filter(
              (item) => item.id !== itemId,
            );

            const index =
              afterItemId === undefined
                ? -1
                : items.findIndex((item) => item.id === afterItemId);

            const previous = items[index]?.rank;
            const next = items[index + 1]?.rank;

            await after(
              await client.reorderItem({
                itemId,
                neighbors: {
                  ...(previous === undefined ? {} : { previous }),
                  ...(next === undefined ? {} : { next }),
                },
              }),
            );
          },
          archiveItem: async (input) => after(await client.archiveItem(input)),
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();
          }),
      };
    },
  );
}
