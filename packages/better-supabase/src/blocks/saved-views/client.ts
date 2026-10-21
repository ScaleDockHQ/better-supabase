import type { ListQueryInput } from "../../list/list-query.ts";
import type { Controller } from "../controller.ts";
import type { ListUrlState } from "./query-state.ts";
import type {
  DefaultViewCandidate,
  SavedViewDisplayState,
  SavedViewPreferenceInput,
  SavedViewScope,
  SavedViewState,
} from "./saved-views.ts";

import { defineController } from "../controller.ts";
import {
  displayStateOf,
  queryFromUrlState,
  sameDisplayState,
  sameQuery,
  urlStateFromQuery,
} from "./query-state.ts";
import { defaultView } from "./saved-views.ts";

/** The fields of a saved view the controller reads; `SavedView` fits. */
export interface SavedViewLike extends DefaultViewCandidate {
  readonly id: string;
  readonly name: string;
  readonly state: SavedViewState;
}

export interface SavedViewsSyncOptions<V extends SavedViewLike> {
  /**
   * Loads the list's views, e.g. a server action that calls
   * `savedViews.list()`.
   */
  readonly load: () => Promise<readonly V[]>;
  /**
   * The state the UI shows outside the URL: columns, grouping, density and
   * layout. `saveCurrent` stores it with the query, and `active` and `isDirty`
   * compare it. Without it only the query counts.
   */
  readonly getState?: () => SavedViewDisplayState;
  /**
   * Shows a view's state outside the URL; `apply` calls it with everything but
   * `query`.
   */
  readonly onApplyState?: (state: SavedViewDisplayState, view: V) => void;
  /**
   * Saves the current state, e.g. a server action that calls
   * `savedViews.save()`.
   */
  readonly save?: (input: {
    readonly name: string;
    readonly query: ListQueryInput<string, string>;
    /** The query and `getState()` together, as `savedViews.save()` takes it. */
    readonly state: SavedViewState;
    readonly id?: string;
  }) => Promise<unknown>;
  readonly remove?: (id: string) => Promise<unknown>;
  /** Copies a view, e.g. a server action that calls `savedViews.duplicate()`. */
  readonly duplicate?: (input: {
    readonly id: string;
    readonly name: string;
    readonly scope?: SavedViewScope;
  }) => Promise<unknown>;
  /**
   * Sets the caller's flags, e.g. a server action that calls
   * `savedViews.setPreference()`.
   */
  readonly setPreference?: (
    id: string,
    preference: SavedViewPreferenceInput,
  ) => Promise<unknown>;
  /**
   * Applies the default view after the first load when the URL holds no query.
   * Default `true`.
   */
  readonly openDefault?: boolean;
}

export interface SavedViewsControllerOptions<
  V extends SavedViewLike,
> extends SavedViewsSyncOptions<V> {
  /**
   * The list's URL state now, e.g. from nuqs
   * `useQueryStates(list.nuqs(createParser))`.
   */
  readonly urlState: () => ListUrlState;
  /** Its setter, which `apply` calls with every key so stale ones clear. */
  readonly setUrlState: (next: Record<string, unknown>) => unknown;
}

export interface SavedViewsSnapshot<V extends SavedViewLike> {
  /** `undefined` until the first load. */
  readonly views: readonly V[] | undefined;
  /** The view `apply` opened last. */
  readonly opened: V | undefined;
  readonly error: unknown;
}

export interface SavedViewsActions<V extends SavedViewLike> {
  /** Puts a view's query in the URL and passes the rest to `onApplyState`. */
  readonly apply: (view: V) => void;
  /** Saves the current state as a new view, or over `id`, then loads again. */
  readonly saveCurrent: (name: string, id?: string) => Promise<void>;
  readonly remove: (id: string) => Promise<void>;
  /** Copies a view under `name`, then loads again. */
  readonly duplicate: (
    id: string,
    name: string,
    scope?: SavedViewScope,
  ) => Promise<void>;
  /** Sets the caller's own default, hidden or pinned flag, then loads again. */
  readonly setPreference: (
    id: string,
    preference: SavedViewPreferenceInput,
  ) => Promise<void>;
  readonly refresh: () => Promise<void>;
}

export type SavedViewsController<V extends SavedViewLike> = Controller<
  SavedViewsSnapshot<V>,
  SavedViewsActions<V>
>;

/** What the URL and the display state show, compared with the views. */
export interface SavedViewsMatch<V extends SavedViewLike> {
  /** The view whose state the URL and `getState()` hold, if any. */
  readonly active: V | undefined;
  /** The URL's query, in the shape a view stores. */
  readonly query: ListQueryInput<string, string>;
  /** The URL's query and `getState()`, in the shape a view stores. */
  readonly state: SavedViewState;
  /** Whether the state changed since `apply` opened the last view. */
  readonly isDirty: boolean;
}

/** Matches the URL state and the display state against the loaded views. */
export function matchSavedViews<V extends SavedViewLike>(
  snapshot: SavedViewsSnapshot<V>,
  urlState: ListUrlState,
  display: SavedViewDisplayState | undefined,
): SavedViewsMatch<V> {
  const query = queryFromUrlState(urlState);

  const shows = (view: V): boolean =>
    sameQuery(view.state.query, query) &&
    (display === undefined || sameDisplayState(view.state, display));

  return {
    active: snapshot.views?.find(shows),
    query,
    state: { ...display, query },
    isDirty: snapshot.opened !== undefined && !shows(snapshot.opened),
  };
}

function needs<T>(value: T | undefined, name: string): T {
  if (value === undefined) {
    throw new Error(`better-supabase: saved views need \`${name}\``);
  }

  return value;
}

/**
 * Saved views of one list, synced with its URL state and, through `getState`
 * and `onApplyState`, with the table's columns, grouping, density and layout.
 */
export function createSavedViewsController<V extends SavedViewLike>(
  options: SavedViewsControllerOptions<V>,
): SavedViewsController<V> {
  return defineController<SavedViewsSnapshot<V>, SavedViewsActions<V>>(
    { views: undefined, opened: undefined, error: undefined },
    (state) => {
      const apply = (view: V): void => {
        state.set({ opened: view });
        options.setUrlState(
          urlStateFromQuery(view.state.query, Object.keys(options.urlState())),
        );
        options.onApplyState?.(displayStateOf(view.state), view);
      };

      const refresh = async (): Promise<void> => {
        try {
          state.set({ views: await options.load(), error: undefined });
        } catch (cause) {
          state.set({ error: cause });
        }
      };

      return {
        actions: {
          apply,
          refresh,
          saveCurrent: async (name, id) => {
            const save = needs(options.save, "save");
            const query = queryFromUrlState(options.urlState());
            await save({
              name,
              query,
              state: { ...options.getState?.(), query },
              ...(id !== undefined && { id }),
            });
            await refresh();
          },
          remove: async (id) => {
            await needs(options.remove, "remove")(id);
            state.set((current) => ({
              opened: current.opened?.id === id ? undefined : current.opened,
            }));
            await refresh();
          },
          duplicate: async (id, name, scope) => {
            await needs(
              options.duplicate,
              "duplicate",
            )({ id, name, ...(scope !== undefined && { scope }) });
            await refresh();
          },
          setPreference: async (id, preference) => {
            await needs(options.setPreference, "setPreference")(id, preference);
            await refresh();
          },
        },
        start: () => {
          if (state.get().views !== undefined) {
            return;
          }

          const run = state.run();
          void (async () => {
            try {
              const loaded = await options.load();

              if (run !== state.run()) {
                return;
              }

              state.set({ views: loaded, error: undefined });

              if (
                options.openDefault !== false &&
                sameQuery(queryFromUrlState(options.urlState()), undefined)
              ) {
                const first = defaultView(
                  loaded.filter(
                    (view) =>
                      view.isDefault || view.preference?.isDefault === true,
                  ),
                );

                if (first) {
                  apply(first);
                }
              }
            } catch (cause) {
              if (run === state.run()) {
                state.set({ error: cause });
              }
            }
          })();

          return;
        },
      };
    },
  );
}
