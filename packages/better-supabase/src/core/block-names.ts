import type { BlockTransportMiddleware } from "./block-hooks.ts";

import { defineTransportMiddleware } from "./block-hooks.ts";
import { tenantNames } from "./tenant-naming.ts";

// The block columns that carry the tenant concept in their default name.
// `sql.naming.tenant` refuses a name that would make one of them collide
// with a column a block already has, so the map back is unambiguous.
const TENANT_COLUMNS = ["organization_id", "active_organization_id"] as const;

/**
 * How the SQL names the block functions: `sql.naming.tenant` and the
 * `blocks.<name>.functions` maps, merged. `better-supabase gen` writes it to
 * each block's `naming` in `blocks.generated.ts`.
 */
export interface BlockNaming {
  /** `sql.naming.tenant`, such as `workspace`. */
  readonly tenant?: string;
  /** Function name to the name the SQL writes it under. */
  readonly functions?: Readonly<Record<string, string>>;
}

/**
 * Transport middleware that calls each block function by the name the SQL
 * wrote it under: `create_organization` becomes `create_workspace` with
 * `tenant: "workspace"`, then `functions` renames single functions. Wrap
 * a block's transport with it when the config sets `sql.naming` or
 * `blocks.<name>.functions`; `defineBlocks` does it from `blocks.generated.ts`.
 */
export function blockNames(naming: BlockNaming): BlockTransportMiddleware {
  const names = tenantNames(naming.tenant);
  const functions = naming.functions ?? {};

  const rename = (fn: string): string => {
    const renamed = names.rename(fn);

    return functions[fn] ?? functions[renamed] ?? renamed;
  };

  const columns = new Map(
    TENANT_COLUMNS.map((column) => [names.rename(column), column]),
  );

  // A row a function returns whole (`to_jsonb(row)`) carries the renamed
  // tenant columns; the clients read them by their default names.
  const restore = (value: unknown): unknown => {
    if (Array.isArray(value)) {
      return value.map(restore);
    }

    if (typeof value !== "object" || value === null) {
      return value;
    }

    return Object.fromEntries(
      Object.entries(value).map(([key, each]) => [
        columns.get(key) ?? key,
        restore(each),
      ]),
    );
  };

  return defineTransportMiddleware({
    name: "block-names",
    call: async (request, next) => {
      const result = await next({ ...request, fn: rename(request.fn) });

      return names.renamed ? restore(result) : result;
    },
  });
}
