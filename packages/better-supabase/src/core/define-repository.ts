import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";
import type { BetterSupabase } from "./define.ts";
import type { RepositoryOf } from "./repository-types.ts";

import {
  definePlugin,
  type Plugin,
  type RepositoryExtension,
} from "./plugin.ts";

/** Adds `Methods` to the repository of `Table` only. */
export interface TableRepositoryExtension<
  Table extends string,
  Methods,
> extends RepositoryExtension {
  readonly methods: this["T"] extends Table ? Methods : unknown;
}

/**
 * Domain methods for one table, installed with `use()`. `base` is the
 * repository at call time, with every other plugin's methods.
 *
 * ```ts
 * const customers = defineRepository(sb, 'customers', (base) => ({
 *   active: () => base.findMany({ where: { status: 'active' } }),
 * }));
 * export const app = sb.use(customers);
 * await app.connect(client).customers.active();
 * ```
 */
export function defineRepository<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  const Table extends TableKey<M>,
  Methods extends object,
>(
  sb: BetterSupabase<M, D, F, E>,
  table: Table,
  build: (base: RepositoryOf<M, Table, E>) => Methods,
): Plugin<`repository:${Table}`, TableRepositoryExtension<Table, Methods>> {
  if (!(table in sb.meta.tables)) {
    throw new TypeError(
      `better-supabase: defineRepository: unknown table "${table}"`,
    );
  }
  return definePlugin<
    `repository:${Table}`,
    TableRepositoryExtension<Table, Methods>
  >({
    name: `repository:${table}`,
    repository: ({ table: meta, base }) =>
      meta.key === table
        ? // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- `base` is the repository for `table`, checked by `meta.key` above.
          (build(base as unknown as RepositoryOf<M, Table, E>) as Readonly<
            Record<string, (...args: never[]) => unknown>
          >)
        : undefined,
  });
}
