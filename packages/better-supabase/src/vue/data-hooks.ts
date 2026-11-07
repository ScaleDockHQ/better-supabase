import type {
  DataId,
  DataListOptions,
  DataRow,
  DataRows,
  DataSource,
  DataState,
  DataWrites,
} from "../bindings/data-hooks.ts";
import type { VueController } from "../blocks/vue-bind.ts";

import {
  createDataList,
  createDataOne,
  dataTarget,
} from "../bindings/data-hooks.ts";
import { bindVueController } from "../blocks/vue-bind.ts";
import { useContext } from "./context.ts";

/** What `useList` and `useOne` return: `state` and the writes. */
export type DataView<S extends DataSource, T> = VueController<
  DataState<T>,
  DataWrites<S>
>;

/** The composables `defineDataHooks` makes for one table or block instance. */
export interface DataHooks<S extends DataSource> {
  /** `source.list(args)`, kept fresh after every write. */
  readonly useList: (args?: DataListOptions<S>) => DataView<S, DataRows<S>>;
  /** `source.get(id)`, kept fresh after every write. */
  readonly useOne: (id: DataId<S>) => DataView<S, DataRow<S>>;
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
      bindVueController(
        createDataList(
          dataTarget(useContext().client, name, select, table),
          args,
        ),
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
      bindVueController(
        createDataOne(dataTarget(useContext().client, name, select, table), id),
      );

/**
 * The list and record composables for one table or block instance. The
 * generated `hooks.ts` calls it once per table; `select` picks the source from
 * the plugin's `db`.
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
