import type { BlockSqlContext } from "./context.ts";

import { fillTemplate } from "../core/access-sql.ts";
import { sqlString } from "../core/template.ts";

const RESOURCE = /^[a-z_][a-z0-9_]{0,62}$/;

export type RowCheck = (id: string, user: string) => string;

export const isResourceName = (rows: unknown): rows is string =>
  typeof rows === "string" && RESOURCE.test(rows);

export function providerRowCheck(
  ctx: BlockSqlContext,
  where: string,
  rows: string,
  key: string,
): RowCheck {
  const rowsWith = ctx.providerRowsWith;

  if (rowsWith === undefined) {
    throw new TypeError(
      `${where}.rows needs blocks.permissions.model "provider" and an authorization provider with functions.rowsWith`,
    );
  }

  const forUser = ctx.providerRowsWithFor;
  const permission = sqlString(key);

  return (id, user) => {
    const ids = `array[${id}::text]`;

    const member = (set: string) =>
      `${id}::text in (select r.id::text from ${set} as r(id))`;

    const own = member(
      fillTemplate("authorization.functions.rowsWith", rowsWith, {
        resource: rows,
        permission,
        ids,
      }),
    );

    if (forUser === undefined) {
      return `(${user} = auth.uid() and ${own})`;
    }

    const other = member(
      fillTemplate("authorization.functions.rowsWithFor", forUser, {
        user,
        resource: rows,
        permission,
        ids,
      }),
    );

    return `(case when ${user} = auth.uid() then ${own} when ${user} is not null then ${other} else false end)`;
  };
}
