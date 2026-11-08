import { getContext } from "svelte";

import type { ClientLike } from "../bindings/client.ts";
import type {
  DataId,
  DataListOptions,
  DataRow,
  DataRows,
  DataSource,
  DataState,
  DataWrites,
} from "../bindings/data-hooks.ts";
import type { SvelteController } from "../blocks/svelte-bind.ts";

import {
  createDataList,
  createDataOne,
  dataTarget,
} from "../bindings/data-hooks.ts";
import { bindSvelteController } from "../blocks/svelte-bind.ts";
import { CLIENT } from "./context.ts";

/** What `useList` and `useOne` return: a store of the read, with the writes. */
export type DataView<S extends DataSource, T> = SvelteController<
  DataState<T>,
  DataWrites<S>
>;

/** The stores `defineDataHooks` makes for one table or block instance. */
export interface DataHooks<S extends DataSource> {
  /** `source.list(args)`, kept fresh after every write. */
  readonly useList: (args?: DataListOptions<S>) => DataView<S, DataRows<S>>;
  /** `source.get(id)`, kept fresh after every write. */
  readonly useOne: (id: DataId<S>) => DataView<S, DataRow<S>>;
}

function client(): ClientLike {
  const bound = getContext<{ readonly client: ClientLike } | undefined>(CLIENT);

  if (!bound) {
    throw new Error(
      "better-supabase: call setBetterSupabase(bsb) in a parent component",
    );
  }

  return bound.client;
}

/**
 * The list reader for one table or block instance, for a module that wants to
 * tree-shake each one on its own. `defineDataHooks` makes both. With a table
 * module from `tables/<table>.ts` as `table`, it reads through
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
    (args) =>
      bindSvelteController(
        createDataList(dataTarget(client(), name, select, table), args),
      );

/** The record reader for one table or block instance (see `defineListHook`). */
export const defineOneHook =
  /*#__NO_SIDE_EFFECTS__*/
  <D, S extends DataSource>(
    name: string,
    select: (db: D) => S,
    table?: object,
  ): DataHooks<S>["useOne"] =>
    (id) =>
      bindSvelteController(
        createDataOne(dataTarget(client(), name, select, table), id),
      );

/**
 * The list and record stores for one table or block instance. Call them during
 * component setup. The generated `hooks.ts` calls it once per table; `select`
 * picks the source from the bound client's `db`.
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
