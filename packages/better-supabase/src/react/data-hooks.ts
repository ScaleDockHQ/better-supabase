import { useContext, useEffect } from "react";

import type {
  DataId,
  DataListOptions,
  DataRow,
  DataRows,
  DataSource,
  DataState,
  DataWrites,
} from "../bindings/data-hooks.ts";

import {
  createDataList,
  createDataOne,
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
