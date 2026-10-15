"use client";

import type {
  SavedViewLike,
  SavedViewsActions,
  SavedViewsMatch,
  SavedViewsSyncOptions,
} from "../client.ts";
import type { ListUrlState } from "../query-state.ts";

import { useController, useLatest } from "../../react-controller.ts";
import { createSavedViewsController, matchSavedViews } from "../client.ts";

export type { SavedViewLike } from "../client.ts";

export interface UseSavedViewsOptions<
  V extends SavedViewLike,
> extends SavedViewsSyncOptions<V> {
  /** The list's URL state: the values of nuqs `useQueryStates(list.nuqs(createParser))`. */
  readonly urlState: ListUrlState;
  /** Its setter, which `apply` calls with every key so stale ones clear. */
  readonly setUrlState: (next: Record<string, unknown>) => unknown;
}

export interface SavedViewsState<V extends SavedViewLike>
  extends SavedViewsMatch<V>, SavedViewsActions<V> {
  /** `undefined` until the first load. */
  readonly views: readonly V[] | undefined;
  readonly error: unknown;
}

/**
 * Saved views of one list, synced with its URL state and, through
 * `getState` and `onApplyState`, with the table's columns, grouping, density
 * and layout. Pair it with nuqs and a view menu (ReUI's Filters toolbar, a
 * Select or a Tabs list):
 *
 * ```tsx
 * const [urlState, setUrlState] = useQueryStates(tasksList.nuqs(createParser));
 * const views = useSavedViews({
 *   load: () => listViews(organizationId, "tasks"),
 *   save: ({ name, state, id }) => saveView({ organizationId, list: "tasks", name, state, id }),
 *   urlState,
 *   setUrlState,
 *   getState: () => ({ columns, density }),
 *   onApplyState: (state) => showState(state),
 * });
 * ```
 */
export function useSavedViews<V extends SavedViewLike>(
  options: UseSavedViewsOptions<V>,
): SavedViewsState<V> {
  const latest = useLatest(options);
  const { view } = useController(
    () =>
      createSavedViewsController<V>({
        load: () => latest.current.load(),
        urlState: () => latest.current.urlState,
        setUrlState: (next) => latest.current.setUrlState(next),
        getState: () => latest.current.getState?.() ?? {},
        onApplyState: (state, applied) => {
          latest.current.onApplyState?.(state, applied);
        },
        save: (input) => needs(latest.current.save, "save")(input),
        remove: (id) => needs(latest.current.remove, "remove")(id),
        duplicate: (input) =>
          needs(latest.current.duplicate, "duplicate")(input),
        setPreference: (id, preference) =>
          needs(latest.current.setPreference, "setPreference")(id, preference),
        openDefault: options.openDefault !== false,
      }),
    [latest],
  );
  const match = matchSavedViews(view, options.urlState, options.getState?.());
  return {
    views: view.views,
    error: view.error,
    ...match,
    apply: view.apply,
    saveCurrent: view.saveCurrent,
    remove: view.remove,
    duplicate: view.duplicate,
    setPreference: view.setPreference,
    refresh: view.refresh,
  };
}

function needs<T>(value: T | undefined, name: string): T {
  if (value === undefined) throw new Error(`useSavedViews: pass \`${name}\``);
  return value;
}
