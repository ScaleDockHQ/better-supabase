import type {
  DataId,
  DataListArgs,
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
  readonly useList: (args?: DataListArgs<S>) => DataView<S, DataRows<S>>;
  /** `source.get(id)`, kept fresh after every write. */
  readonly useOne: (id: DataId<S>) => DataView<S, DataRow<S>>;
}

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
    useList: (args) =>
      bindVueController(
        createDataList(dataTarget(useContext().client, name, select), args),
      ),
    useOne: (id) =>
      bindVueController(
        createDataOne(dataTarget(useContext().client, name, select), id),
      ),
  };
}
