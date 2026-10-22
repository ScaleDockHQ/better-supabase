import type { TableGrant } from "./modules/data-api-grants.ts";

import { declaredTableColumns } from "./schema-scan.ts";

const keyOf = (name: string): string =>
  name.includes(".") ? name : `public.${name}`;

/** Whether a privilege is the `select(*, -col)` form `upgrade` resolves. */
export const hasColumnExclusions = (privilege: string): boolean =>
  /\(\s*\*/.test(privilege);

/**
 * The columns `privilege(*, -a, -b)` leaves out, unquoted. Empty for any other
 * privilege.
 */
export function excludedColumns(privilege: string): readonly string[] {
  if (!hasColumnExclusions(privilege)) {
    return [];
  }

  return privilege
    .slice(privilege.indexOf("(") + 1, privilege.lastIndexOf(")"))
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part.startsWith("-"))
    .map((part) => part.slice(1).trim());
}

/**
 * `grants` with every `privilege(*, -col)` turned into the explicit column list
 * the `create table` in `files` declares, in declaration order. Throws for a
 * table no file declares, or when the exclusions leave no column.
 */
export function resolveExposeColumns(
  grants: readonly TableGrant[],
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): readonly TableGrant[] {
  if (!grants.some((grant) => grant.privileges.some(hasColumnExclusions))) {
    return grants;
  }

  const declared = declaredTableColumns(files, schemas);

  return grants.map((grant) => {
    if (!grant.privileges.some(hasColumnExclusions)) {
      return grant;
    }

    const columns = declared.get(keyOf(grant.table));

    return {
      ...grant,
      privileges: grant.privileges.map((privilege) => {
        if (!hasColumnExclusions(privilege)) {
          return privilege;
        }

        if (columns === undefined || columns.size === 0) {
          throw new TypeError(
            `expose.${grant.table}: "${privilege}" needs the table's columns, and no \`create table\` in the schema files declares ${keyOf(grant.table)}. List the columns instead.`,
          );
        }

        const excluded = new Set(excludedColumns(privilege));
        const kept = [...columns].filter((column) => !excluded.has(column));

        if (kept.length === 0) {
          throw new TypeError(
            `expose.${grant.table}: "${privilege}" excludes every column of ${keyOf(grant.table)}. Drop the privilege instead.`,
          );
        }

        return `${privilege.slice(0, privilege.indexOf("(")).trim()}(${kept.join(", ")})`;
      }),
    };
  });
}
