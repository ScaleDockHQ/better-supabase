import { useContext } from "react";

import type {
  DataId,
  DataListArgs,
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

/** What `useList` and `useOne` return: the read and the writes. */
export type DataView<S extends DataSource, T> = DataState<T> & DataWrites<S>;

/** The hooks `defineDataHooks` makes for one table or block instance. */
export interface DataHooks<S extends DataSource> {
  /** `source.list(args)`, kept fresh after every write. */
  readonly useList: (args?: DataListArgs<S>) => DataView<S, DataRows<S>>;
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
    useList: (args) => {
      const client = useClient();
      const target = dataTarget(client, name, select);

      return useController(
        () => createDataList(target, args),
        [
          client.db,
          target.engine,
          dataArgsKey(target.scope),
          dataArgsKey(args),
        ],
      ).view;
    },
    useOne: (id) => {
      const client = useClient();
      const target = dataTarget(client, name, select);

      return useController(
        () => createDataOne(target, id),
        [client.db, target.engine, dataArgsKey(target.scope), dataArgsKey(id)],
      ).view;
    },
  };
}
