import { useCallback, useContext, useEffect, useState } from "react";

import type {
  DataId,
  DataListOptions,
  DataPageOptions,
  DataRow,
  DataRows,
  DataSource,
  DataState,
  DataWrites,
} from "../bindings/data-hooks.ts";
import type { DbError } from "../core/errors.ts";

import {
  createDataList,
  createDataOne,
  createDataPage,
  dataArgsKey,
  dataTarget,
} from "../bindings/data-hooks.ts";
import { useController } from "../blocks/react-controller.ts";
import { ClientContext } from "./context.ts";
import { OfflineContext } from "./offline.ts";

/** What `useList` and `useOne` return: the read and the writes. */
export type DataView<S extends DataSource, T> = DataState<T> & DataWrites<S>;

/** The hooks `defineDataHooks` makes for one table or block instance. */
export interface DataHooks<S extends DataSource> {
  /** `source.list(args)`, kept fresh after every write. */
  readonly useList: (args?: DataListOptions<S>) => DataView<S, DataRows<S>>;
  /** `source.get(id)`, kept fresh after every write. */
  readonly useOne: (id: DataId<S>) => DataView<S, DataRow<S>>;
}

function useClient(): Parameters<typeof dataTarget>[0] {
  const context = useContext(ClientContext);

  if (!context) {
    throw new Error(
      "better-supabase: wrap your app in <BetterSupabaseProvider client={bsb}>",
    );
  }

  return context.client;
}

/**
 * The list hook for one table or block instance, for a module that wants to
 * tree-shake each hook on its own. `defineDataHooks` makes both. With a table
 * module from `tables/<table>.ts` as `table`, the hook reads through
 * `client.table(table)`, so a client of a `lazyTables` schema registers just
 * that table.
 */
export const defineListHook =
  /*#__NO_SIDE_EFFECTS__*/
  <D, S extends DataSource>(
    name: string,
    select: (db: D) => S,
    table?: object,
  ): DataHooks<S>["useList"] =>
    (args) => {
      const client = useClient();
      const target = dataTarget(client, name, select, table);
      const offline = useContext(OfflineContext);

      const { controller, view } = useController(
        () => createDataList(target, args, { offline }),
        [
          client.db,
          target.engine,
          dataArgsKey(target.scope),
          dataArgsKey(args),
        ],
      );

      useEffect(() => {
        controller.actions.setOffline(offline);
      }, [controller, offline]);

      return view;
    };

/** The record hook for one table or block instance (see `defineListHook`). */
export const defineOneHook =
  /*#__NO_SIDE_EFFECTS__*/
  <D, S extends DataSource>(
    name: string,
    select: (db: D) => S,
    table?: object,
  ): DataHooks<S>["useOne"] =>
    (id) => {
      const client = useClient();
      const target = dataTarget(client, name, select, table);
      const offline = useContext(OfflineContext);

      const { controller, view } = useController(
        () => createDataOne(target, id, { offline }),
        [client.db, target.engine, dataArgsKey(target.scope), dataArgsKey(id)],
      );

      useEffect(() => {
        controller.actions.setOffline(offline);
      }, [controller, offline]);

      return view;
    };

/**
 * The list and record hooks for one table or block instance. The generated
 * `hooks.ts` calls it once per table (`useTickets`, `useTicket`); `select`
 * picks the source from the provider's `db`.
 *
 * ```ts
 * export const { useList: useTickets, useOne: useTicket } =
 *   defineDataHooks("tickets", (db: AppDb) => db.tickets);
 * ```
 */
export function defineDataHooks<D, S extends DataSource>(
  name: string,
  select: (db: D) => S,
): DataHooks<S> {
  return {
    useList: defineListHook(name, select),
    useOne: defineOneHook(name, select),
  };
}

interface CursorPayload {
  readonly items: readonly unknown[];
  readonly nextCursor: string | null;
  readonly hasMore: boolean;
}

function isCursorPayload(value: unknown): value is CursorPayload {
  return (
    typeof value === "object" &&
    value !== null &&
    "items" in value &&
    Array.isArray(value.items) &&
    "hasMore" in value
  );
}

type PageFunction<S extends DataSource> = NonNullable<S["page"]>;

type PageArgs<S extends DataSource> =
  PageFunction<S> extends (first: infer A, ...rest: never[]) => unknown
    ? A
    : never;

type PageItem<S extends DataSource> =
  PageFunction<S> extends (
    ...args: never[]
  ) => PromiseLike<{ readonly ok: true; readonly data: infer D }>
    ? D extends { readonly items: readonly (infer T)[] }
      ? T
      : never
    : never;

/** One cursor page after another, on `source.page()`. */
export interface InfiniteList<T> {
  readonly items: readonly T[];
  readonly error: DbError | undefined;
  readonly isPending: boolean;
  readonly hasMore: boolean;
  readonly fetchNextPage: () => void;
}

/**
 * Pages a table with `page({ after, size })`. `fetchNextPage` asks for the next
 * cursor. A change to `args` starts again at the first page. Offline, the hook
 * pauses like `useList`.
 */
export const defineInfiniteListHook =
  /*#__NO_SIDE_EFFECTS__*/
  <D, S extends DataSource>(
    name: string,
    select: (db: D) => S,
    table?: object,
  ): ((args: Omit<PageArgs<S>, "after">) => InfiniteList<PageItem<S>>) =>
    (args) => {
      const client = useClient();
      const target = dataTarget(client, name, select, table);
      const offline = useContext(OfflineContext);
      const filters = dataArgsKey(args);
      const [seen, setSeen] = useState(filters);
      const [after, setAfter] = useState<string | null>(null);
      const [items, setItems] = useState<readonly PageItem<S>[]>([]);
      const [cursor, setCursor] = useState<string | null>(null);
      const [hasMore, setHasMore] = useState(false);

      if (seen !== filters) {
        setSeen(filters);
        setAfter(null);
        setItems([]);
        setCursor(null);
      }

      // SAFETY: `after` is the cursor argument the page function declares.
      // Omitting it from the hook's public args and adding it here rebuilds that argument.
      const pageArgs = { ...args, after } as DataPageOptions<S>;

      const { controller, view } = useController(
        () => createDataPage(target, pageArgs, { offline }),
        [
          client.db,
          target.engine,
          dataArgsKey(target.scope),
          dataArgsKey(pageArgs),
        ],
      );

      useEffect(() => {
        controller.actions.setOffline(offline);
      }, [controller, offline]);

      useEffect(() => {
        if (view.status !== "success" || !isCursorPayload(view.data)) {
          return;
        }

        const page = view.data;
        // SAFETY: isCursorPayload checked that items is an array. T is the row the caller named.
        const next = page.items as readonly PageItem<S>[];

        setItems((current) => (after === null ? next : [...current, ...next]));
        setCursor(page.nextCursor);
        setHasMore(page.hasMore);
      }, [view.data, view.status, after]);

      const fetchNextPage = useCallback(() => {
        if (hasMore && cursor !== null) {
          setAfter(cursor);
        }
      }, [hasMore, cursor]);

      return {
        items,
        error: view.error,
        isPending: view.isPending && items.length === 0,
        hasMore,
        fetchNextPage,
      };
    };
