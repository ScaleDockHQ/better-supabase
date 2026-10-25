import type { ExtraColumn } from "./context.ts";

import { isSqlType } from "../config/sql-type.ts";
import { sqlIdent } from "../core/template.ts";

const EXTRA_COLUMN = /^[a-z_][a-z0-9_]*$/;

export function checkedExtraColumns(
  at: string,
  value: object,
  taken: ReadonlySet<string>,
): readonly ExtraColumn[] {
  return Object.entries(value).map(([name, type]: [string, unknown]) => {
    if (!EXTRA_COLUMN.test(name) || name.length > 63) {
      throw new TypeError(`${at}: "${name}" is not a valid column name`);
    }

    if (taken.has(name)) {
      throw new TypeError(
        `${at}.${name} shadows a column the module already returns`,
      );
    }

    if (typeof type !== "string" || !isSqlType(type)) {
      throw new TypeError(
        `${at}.${name} must be a SQL type such as "text not null default 'en'"`,
      );
    }

    return { name, ident: sqlIdent(name), type };
  });
}
