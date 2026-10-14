"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import type { ListQueryInput } from "../../../list/list-query.ts";
import type { ListUrlState } from "../query-state.ts";
import type { SavedViewScope } from "../saved-views.ts";

import {
  queryFromUrlState,
  sameQuery,
  urlStateFromQuery,
} from "../query-state.ts";
import { defaultView } from "../saved-views.ts";

/** The fields of a saved view the hook reads; `SavedView` fits. */
export interface SavedViewLike {
  readonly id: string;
  readonly name: string;
  readonly scope: SavedViewScope;
  readonly isDefault: boolean;
  readonly state: { readonly query?: ListQueryInput<string, string> };
}

export interface UseSavedViewsOptions<V extends SavedViewLike> {
  /** Loads the list's views, e.g. a server action that calls `savedViews.list()`. */
  readonly load: () => Promise<readonly V[]>;
  /** The list's URL state: the values of nuqs `useQueryStates(list.nuqs(createParser))`. */
  readonly urlState: ListUrlState;
  /** Its setter, which `apply` calls with every key so stale ones clear. */
  readonly setUrlState: (next: Record<string, unknown>) => unknown;
  /** Saves the current query, e.g. a server action that calls `savedViews.save()`. */
  readonly save?: (input: {
    readonly name: string;
    readonly query: ListQueryInput<string, string>;
    readonly id?: string;
  }) => Promise<unknown>;
  readonly remove?: (id: string) => Promise<unknown>;
  /** Applies the default view after the first load when the URL holds no query. Default `true`. */
  readonly openDefault?: boolean;
}

export interface SavedViewsState<V extends SavedViewLike> {
  /** `undefined` until the first load. */
  readonly views: readonly V[] | undefined;
  /** The view whose query the URL holds, if any. */
  readonly active: V | undefined;
  /** The URL's query, in the shape a view stores. */
  readonly query: ListQueryInput<string, string>;
  /** Whether the URL changed since `apply` opened the last view. */
  readonly isDirty: boolean;
  readonly error: unknown;
  /** Puts a view's query in the URL. */
  readonly apply: (view: V) => void;
  /** Saves the URL's query as a new view, or over `id`, then loads again. */
  readonly saveCurrent: (name: string, id?: string) => Promise<void>;
  readonly remove: (id: string) => Promise<void>;
  readonly refresh: () => Promise<void>;
}

/**
 * Saved views of one list, synced with its URL state. Pair it with nuqs
 * and a view menu (ReUI's Filters toolbar, a Select or a Tabs list):
 *
 * ```tsx
 * const [urlState, setUrlState] = useQueryStates(tasksList.nuqs(createParser));
 * const views = useSavedViews({
 *   load: () => listViews(organizationId, "tasks"),
 *   save: (input) => saveView({ organizationId, list: "tasks", ...input }),
 *   urlState,
 *   setUrlState,
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
  const query = queryFromUrlState(options.urlState);

  const apply = useCallback((view: V) => {
    const current = latest.current;
    setOpened(view);
    current.setUrlState(
      urlStateFromQuery(view.state.query, Object.keys(current.urlState)),
    );
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
          const first = defaultView(loaded.filter((view) => view.isDefault));
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
      await current.save({
        name,
        query: queryFromUrlState(current.urlState),
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

  const active = views?.find((view) => sameQuery(view.state.query, query));
  return {
    views,
    active,
    query,
    isDirty: opened !== undefined && !sameQuery(opened.state.query, query),
    error,
    apply,
    saveCurrent,
    remove,
    refresh,
  };
}
