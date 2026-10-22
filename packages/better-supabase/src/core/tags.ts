import type { CacheAdapter, CacheTarget } from "./cache.ts";

export interface TagOptions {
  /** The tenant the read is scoped to; `"*"` is every tenant's reads. */
  readonly tenant?: string;
}

/**
 * `bsb:<table>`, `bsb:<table>:<id>`, or `bsb:<table>@<tenant>` for a read
 * scoped to one tenant. Mutations invalidate the table tag, the tag of their
 * tenant (`bsb:<table>@*` without one) and the tags of the changed rows.
 */
export function tagFor(
  table: string,
  id?: string | number,
  options: TagOptions = {},
): string {
  if (id !== undefined) {
    return `bsb:${table}:${String(id)}`;
  }

  return options.tenant === undefined
    ? `bsb:${table}`
    : `bsb:${table}@${options.tenant}`;
}

/**
 * The tags a mutation invalidates: `bsb:<table>` for every table in the target,
 * the tenant's `bsb:<table>@<tenant>` (every tenant's `bsb:<table>@*` when the
 * mutation has no tenant) and `bsb:<table>:<id>` per changed row.
 */
export function cacheTagsOf(target: CacheTarget): string[] {
  const tenant = { tenant: target.tenant ?? "*" };
  const tags: string[] = [];

  for (const table of target.tables) {
    tags.push(tagFor(table), tagFor(table, undefined, tenant));
  }

  for (const id of target.ids) {
    tags.push(tagFor(target.table, id));
  }

  return tags;
}

/**
 * A `CacheAdapter` for any tag-based cache: it hands `invalidate` the tags from
 * `cacheTagsOf`, e.g. a CDN purge by tag, SvelteKit's `invalidate`, or a Redis
 * set of keys per tag. Tag your reads with `tagFor`.
 *
 * ```ts
 * betterSupabase.cache(tagCache((tags) => purgeCdn(tags), "cdn"));
 * ```
 */
export function tagCache(
  invalidate: (tags: readonly string[]) => void | Promise<void>,
  name = "tags",
): CacheAdapter {
  return { name, invalidate: (target) => invalidate(cacheTagsOf(target)) };
}
