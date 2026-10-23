import { getContext } from "svelte";

import type { ClientLike } from "../bindings/client.ts";
import type {
  DataId,
  DataListArgs,
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
  readonly useList: (args?: DataListArgs<S>) => DataView<S, DataRows<S>>;
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
 * The list and record stores for one table or block instance. Call them during
 * component setup. The generated `hooks.ts` calls it once per table; `select`
 * picks the source from the bound client's `db`.
 */
export function defineDataHooks<D, S extends DataSource>(
  name: string,
  select: (db: D) => S,
): DataHooks<S> {
  return {
    useList: (args) =>
      bindSvelteController(
        createDataList(dataTarget(client(), name, select), args),
      ),
    useOne: (id) =>
      bindSvelteController(
        createDataOne(dataTarget(client(), name, select), id),
      ),
  };
}
