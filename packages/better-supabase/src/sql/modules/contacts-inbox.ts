import type { BlockSqlContext } from "../context.ts";
import type { PartyNames } from "./contacts-functions.ts";

import { sqlIdent } from "../../core/template.ts";

/**
 * A reference from another block's table to people. The inbox and identities
 * render before contacts, so their foreign keys to people live here.
 */
function personKey(
  other: BlockSqlContext,
  table: string,
  column: string,
  names: PartyNames,
): string {
  const target = other.table(table);

  const key = sqlIdent(
    `${other.tableName(table).name}_${other.colName(table, column)}_fkey`,
  );

  return `alter table ${target} drop constraint if exists ${key};
alter table ${target} add constraint ${key}
  foreign key (${other.col(table, column)}) references ${names.t("people")} (${names.c("people", "id")}) on delete cascade;`;
}

/** The tables whose `contact` column names a person: [their block, table]. */
function referrers(
  ctx: BlockSqlContext,
): readonly (readonly [BlockSqlContext, string])[] {
  return [
    ...(ctx.installed("inbox") && ctx.of("inbox").mode !== "custom"
      ? [[ctx.of("inbox"), "conversations"] as const]
      : []),
    ...(ctx.installed("identities") &&
    ctx.of("identities").has("links", "contact")
      ? [[ctx.of("identities"), "links"] as const]
      : []),
  ];
}

/**
 * The foreign keys of the inbox conversations' contact and of an identity
 * link's contact: both name a person.
 */
export function personReferences(
  ctx: BlockSqlContext,
  names: PartyNames,
): string {
  const keys = referrers(ctx)
    .filter(([other, table]) => other.owns(table))
    .map(([other, table]) => personKey(other, table, "contact", names));

  return keys.length === 0
    ? ""
    : `
-- A conversation's contact and an identity link's contact are people.
${keys.join("\n")}
`;
}

/**
 * SQL for a person merge: the inbox conversations and identity links of the
 * dropped person move to the kept one.
 */
export function personMergeMoves(
  ctx: BlockSqlContext,
  keep: string,
  drop: string,
): string {
  return referrers(ctx)
    .map(
      ([other, table]) =>
        `\n  update ${other.table(table)} x set ${other.col(table, "contact")} = ${keep} where x.${other.col(table, "contact")} = ${drop};`,
    )
    .join("");
}
