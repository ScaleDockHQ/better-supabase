import type {
  DataId,
  DataListArgs,
  DataRow,
  DataRows,
  DataSource,
  DataState,
  DataWrites,
} from "../bindings/data-hooks.ts";
import type { SolidController } from "../blocks/solid-bind.ts";

import {
  createDataList,
  createDataOne,
  dataTarget,
} from "../bindings/data-hooks.ts";
import { bindSolidController } from "../blocks/solid-bind.ts";
import { useContext } from "./context.ts";

/** What `useList` and `useOne` return: `state` and the writes. */
export type DataView<S extends DataSource, T> = SolidController<
  DataState<T>,
  DataWrites<S>
>;

/** The primitives `defineDataHooks` makes for one table or block instance. */
export interface DataHooks<S extends DataSource> {
  /** `source.list(args)`, kept fresh after every write. */
  readonly useList: (args?: DataListArgs<S>) => DataView<S, DataRows<S>>;
  /** `source.get(id)`, kept fresh after every write. */
  readonly useOne: (id: DataId<S>) => DataView<S, DataRow<S>>;
}

/**
 * The list and record primitives for one table or block instance. The generated
 * `hooks.ts` calls it once per table; `select` picks the source from the
 * provider's `db`.
 */
export function defineDataHooks<D, S extends DataSource>(
  name: string,
  select: (db: D) => S,
): DataHooks<S> {
  return {
    useList: (args) =>
      bindSolidController(
        createDataList(dataTarget(useContext().client, name, select), args),
      ),
    useOne: (id) =>
      bindSolidController(
        createDataOne(dataTarget(useContext().client, name, select), id),
      ),
  };
}
