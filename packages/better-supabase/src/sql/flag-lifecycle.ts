import type { ModuleLayout } from "./module-types.ts";

import { moduleContext } from "./module-context.ts";

/**
 * The flags past their `expires_at`, as doctor reads them: `expires_at` and
 * `owner` are optional `extraColumns` of the flags table, and an archived
 * flag is left out. Undefined when the flags module isn't installed or has
 * no `expires_at` column.
 */
export function expiredFlagsQuery(
  layout: ModuleLayout,
  installed: readonly string[],
): string | undefined {
  if (!installed.includes("flags")) {
    return undefined;
  }

  const ctx = moduleContext("flags", layout, installed);
  const extras = ctx.extraColumns("flags");
  const expires = extras.find((column) => column.name === "expires_at");

  if (!expires) {
    return undefined;
  }

  const owner = extras.find((column) => column.name === "owner");

  return `select f.${ctx.col("flags", "key")} as key,
  f.${expires.ident}::text as expires_at,
  ${owner ? `f.${owner.ident}::text` : "null::text"} as owner
from ${ctx.table("flags")} f
where f.${expires.ident} < now() and not f.${ctx.col("flags", "archived")}
order by 1`;
}
