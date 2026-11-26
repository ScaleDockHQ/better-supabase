import { tagFor } from "../core/tags.ts";

/**
 * One tag function per table: `tags.customers("org-1")` is
 * `bsb:customers@org-1`.
 */
export type TableTagFunctions<T extends string> = {
  readonly [K in T]: (tenant?: string) => string;
};

/**
 * A tag per table as a function of the tenant, declared once. A reader lists it
 * in `bsb.tenant(org, permission, { tags: [tags.customers(id)] })` and an
 * action in `tags: ({ tenant }) => [tags.customers(tenant)]`, so both sides
 * name the same entry. Without a tenant it is the table's own tag, which every
 * mutation expires (ADR 1256).
 *
 * ```ts
 * export const tags = defineTags(["customers", "invoices"]);
 * ```
 */
export function defineTags<const T extends readonly string[]>(
  tables: T,
): TableTagFunctions<T[number]> {
  // SAFETY: one function per listed table, which is the mapped type's shape.
  return Object.fromEntries(
    tables.map((table) => [
      table,
      (tenant?: string) =>
        tagFor(table, undefined, tenant === undefined ? {} : { tenant }),
    ]),
  ) as TableTagFunctions<T[number]>;
}
