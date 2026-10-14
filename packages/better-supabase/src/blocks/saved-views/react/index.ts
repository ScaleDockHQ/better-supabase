"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import type { ListQueryInput } from "../../../list/list-query.ts";
import type { ListUrlState } from "../query-state.ts";
import type {
  DefaultViewCandidate,
  SavedViewDisplayState,
  SavedViewPreferenceInput,
  SavedViewScope,
  SavedViewState,
} from "../saved-views.ts";

import {
  displayStateOf,
  queryFromUrlState,
  sameDisplayState,
  sameQuery,
  urlStateFromQuery,
} from "../query-state.ts";
import { defaultView } from "../saved-views.ts";

/** The fields of a saved view the hook reads; `SavedView` fits. */
export interface SavedViewLike extends DefaultViewCandidate {
  readonly id: string;
  readonly name: string;
  readonly state: SavedViewState;
}

export interface UseSavedViewsOptions<V extends SavedViewLike> {
  /** Loads the list's views, e.g. a server action that calls `savedViews.list()`. */
  readonly load: () => Promise<readonly V[]>;
  /** The list's URL state: the values of nuqs `useQueryStates(list.nuqs(createParser))`. */
  readonly urlState: ListUrlState;
  /** Its setter, which `apply` calls with every key so stale ones clear. */
  readonly setUrlState: (next: Record<string, unknown>) => unknown;
  /**
   * The state the UI shows outside the URL: columns, grouping, density and
   * layout. `saveCurrent` stores it with the query, and `active` and
   * `isDirty` compare it. Without it only the query counts.
   */
  readonly getState?: () => SavedViewDisplayState;
  /** Shows a view's state outside the URL; `apply` calls it with everything but `query`. */
  readonly onApplyState?: (state: SavedViewDisplayState, view: V) => void;
  /** Saves the current state, e.g. a server action that calls `savedViews.save()`. */
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
  /** Sets the caller's flags, e.g. a server action that calls `savedViews.setPreference()`. */
  readonly setPreference?: (
    id: string,
    preference: SavedViewPreferenceInput,
  ) => Promise<unknown>;
  /** Applies the default view after the first load when the URL holds no query. Default `true`. */
  readonly openDefault?: boolean;
}

export interface SavedViewsState<V extends SavedViewLike> {
  /** `undefined` until the first load. */
  readonly views: readonly V[] | undefined;
  /** The view whose state the URL and `getState()` hold, if any. */
  readonly active: V | undefined;
  /** The URL's query, in the shape a view stores. */
  readonly query: ListQueryInput<string, string>;
  /** The URL's query and `getState()`, in the shape a view stores. */
  readonly state: SavedViewState;
  /** Whether the state changed since `apply` opened the last view. */
  readonly isDirty: boolean;
  readonly error: unknown;
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
  const [views, setViews] = useState<readonly V[] | undefined>(undefined);
  const [error, setError] = useState<unknown>(undefined);
  const [opened, setOpened] = useState<V | undefined>(undefined);
  const latest = useRef(options);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = options;
  const { getState, urlState } = options;
  const query = queryFromUrlState(urlState);
  const display = getState?.();
  const state: SavedViewState = { ...display, query };
  const shows = (view: V): boolean =>
    sameQuery(view.state.query, query) &&
    (display === undefined || sameDisplayState(view.state, display));

  const apply = useCallback((view: V) => {
    const current = latest.current;
    setOpened(view);
    current.setUrlState(
      urlStateFromQuery(view.state.query, Object.keys(current.urlState)),
    );
    current.onApplyState?.(displayStateOf(view.state), view);
  }, []);

  const refresh = useCallback(async () => {
    try {
      setViews(await latest.current.load());
      setError(undefined);
    } catch (cause) {
      setError(cause);
    }
  }, []);

  useEffect(() => {
    const run = { live: true };
    void (async () => {
      try {
        const loaded = await latest.current.load();
        if (!run.live) return;
        setViews(loaded);
        const current = latest.current;
        if (
          current.openDefault !== false &&
          sameQuery(queryFromUrlState(current.urlState), undefined)
        ) {
          const first = defaultView(
            loaded.filter(
              (view) => view.isDefault || view.preference?.isDefault === true,
            ),
          );
          if (first) apply(first);
        }
      } catch (cause) {
        if (run.live) setError(cause);
      }
    })();
    return () => {
      run.live = false;
    };
  }, [apply]);

  const saveCurrent = useCallback(
    async (name: string, id?: string) => {
      const current = latest.current;
      if (!current.save) throw new Error("useSavedViews: pass `save`");
      const urlQuery = queryFromUrlState(current.urlState);
      await current.save({
        name,
        query: urlQuery,
        state: { ...current.getState?.(), query: urlQuery },
        ...(id !== undefined && { id }),
      });
      await refresh();
    },
    [refresh],
  );

  const remove = useCallback(
    async (id: string) => {
      const current = latest.current;
      if (!current.remove) throw new Error("useSavedViews: pass `remove`");
      await current.remove(id);
      setOpened((view) => (view?.id === id ? undefined : view));
      await refresh();
    },
    [refresh],
  );

  const duplicate = useCallback(
    async (id: string, name: string, scope?: SavedViewScope) => {
      const current = latest.current;
      if (!current.duplicate) {
        throw new Error("useSavedViews: pass `duplicate`");
      }
      await current.duplicate({
        id,
        name,
        ...(scope !== undefined && { scope }),
      });
      await refresh();
    },
    [refresh],
  );

  const setPreference = useCallback(
    async (id: string, preference: SavedViewPreferenceInput) => {
      const current = latest.current;
      if (!current.setPreference) {
        throw new Error("useSavedViews: pass `setPreference`");
      }
      await current.setPreference(id, preference);
      await refresh();
    },
    [refresh],
  );

  return {
    views,
    active: views?.find(shows),
    query,
    state,
    isDirty: opened !== undefined && !shows(opened),
    error,
    apply,
    saveCurrent,
    remove,
    duplicate,
    setPreference,
    refresh,
  };
}
