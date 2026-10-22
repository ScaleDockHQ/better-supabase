import type { BlockSqlLayout } from "./module-types.ts";

import { moduleContext } from "./module-context.ts";

export interface TenantQuery {
  readonly text: string;
  readonly values: readonly string[];
}

/**
 * The organizations `seed --tenant` fills: the one whose slug or id is
 * `tenant`, or every live one for `*`. Each row has `id`, `slug` and `name` as
 * text. Undefined when the organizations module isn't installed.
 */
export function tenantsQuery(
  layout: BlockSqlLayout,
  installed: readonly string[],
  tenant: string,
): TenantQuery | undefined {
  if (!installed.includes("organizations")) {
    return undefined;
  }

  const ctx = moduleContext("organizations", layout, installed);

  const col = (logical: string): string =>
    `o.${ctx.col("organizations", logical)}`;

  const slug = ctx.has("organizations", "slug") ? col("slug") : undefined;
  const filters: string[] = [];

  if (ctx.has("organizations", "deletedAt")) {
    filters.push(`${col("deletedAt")} is null`);
  }

  if (tenant !== "*") {
    filters.push(
      slug
        ? `(lower(${slug}::text) = lower($1) or ${col("id")}::text = $1)`
        : `${col("id")}::text = $1`,
    );
  }

  return {
    text: `select ${col("id")}::text as id, ${slug ? `${slug}::text` : "null::text"} as slug, ${col("name")}::text as name
from ${ctx.table("organizations")} o${filters.length > 0 ? `\nwhere ${filters.join(" and ")}` : ""}
order by 2, 1`,
    values: tenant === "*" ? [] : [tenant],
  };
}
