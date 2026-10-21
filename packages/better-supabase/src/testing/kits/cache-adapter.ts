import type { CacheAdapter, CacheTarget } from "../../core/cache.ts";
import type { ConformanceReport } from "../conformance.ts";

import { conform, deepFreeze } from "../conformance.ts";
import { hasName } from "./executor.ts";

/**
 * Proves a `CacheAdapter` accepts table and row targets, repeated and
 * concurrent calls, and never mutates its input.
 */
export function testCacheAdapter(
  adapter: CacheAdapter,
  options: { readonly table?: string } = {},
): Promise<ConformanceReport> {
  const table = options.table ?? "customers";

  const invalidate = (target: CacheTarget): Promise<void> =>
    Promise.resolve(adapter.invalidate(deepFreeze(target)));

  return conform(`CacheAdapter "${adapter.name}"`, [
    hasName(adapter),
    [
      "invalidates a table",
      () => invalidate({ table, tables: [table], ids: [] }),
    ],
    [
      "invalidates rows of a tenant",
      () =>
        invalidate({
          table,
          tables: [table],
          ids: ["1", "a,b"],
          tenant: "organization_1",
        }),
    ],
    [
      "accepts repeated and concurrent calls",
      async () => {
        await invalidate({ table, tables: [table], ids: ["1"] });
        await Promise.all(
          Array.from({ length: 10 }, (_, index) =>
            invalidate({ table, tables: [table], ids: [String(index)] }),
          ),
        );
      },
    ],
    [
      "accepts tables it has never seen",
      () =>
        invalidate({
          table: "__better_supabase_unknown__",
          tables: ["__better_supabase_unknown__"],
          ids: [],
        }),
    ],
    [
      "invalidates tables reached through foreign keys",
      () =>
        invalidate({ table, tables: [table, `${table}_children`], ids: ["1"] }),
    ],
  ]);
}
