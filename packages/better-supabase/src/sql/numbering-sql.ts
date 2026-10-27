import type { BlockSqlContext } from "./context.ts";

import { isRecord } from "../core/guards.ts";
import { sqlString } from "../core/template.ts";
import { sequenceEntry } from "./modules/numbering-entities.ts";

/**
 * The `numbering` format of `entity` in `tenant` as SQL, when the app
 * configured one or the block contributes a default.
 */
function sequenceFormatOf(
  ctx: BlockSqlContext,
  entity: string,
  tenant: string,
): { readonly format: string; readonly assigns: boolean } | undefined {
  if (!ctx.installed("numbering")) {
    return undefined;
  }

  const entry = sequenceEntry(ctx.of("numbering"), entity);

  if (entry === undefined || typeof entry["format"] !== "string") {
    return undefined;
  }

  return {
    format: isRecord(entry["formatFrom"])
      ? `${ctx.of("numbering").fn("number_format")}(${tenant}, ${sqlString(entity)})`
      : sqlString(entry["format"]),
    assigns: typeof entry["table"] === "string",
  };
}

/**
 * PL/pgSQL that assigns the next number of `entity` in `tenant` to `target.seq`
 * (bigint) and `target.identifier` (text): from `numbering` when it numbers the
 * entity, otherwise one more than the tenant's highest in `fallback.table`
 * under a transaction lock, with `prefix` in front (`DEAL-4821`). When the
 * entity has a table, the number is marked as issued for the transaction, so
 * its assign trigger accepts it on the block's insert instead of refusing it.
 * `at` is the timestamptz SQL whose period the number belongs to, such as a
 * document's date; it defaults to `now()`.
 */
export function assignNumberSql(
  ctx: BlockSqlContext,
  entity: string,
  tenant: string,
  target: { readonly seq: string; readonly identifier: string },
  fallback: {
    readonly table: string;
    readonly seq: string;
    readonly tenant: string;
    readonly prefix: string;
  },
  at = "now()",
): string {
  const sequence = sequenceFormatOf(ctx, entity, tenant);

  if (sequence !== undefined) {
    const next = ctx.of("numbering").fn("next_number");

    return `${target.seq} := ${next}(${tenant}, ${sqlString(entity)}, ${at});
  ${target.identifier} := better_supabase.format_assigned_number(${sequence.format}, ${target.seq}, ${at});${
    sequence.assigns
      ? `
  perform set_config('better_supabase.issued_number', ${sqlString(entity)} || chr(31) || ${target.seq}::text || chr(31) || ${target.identifier}, true);`
      : ""
  }`;
  }

  return `perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(${tenant}::text || ${sqlString(`:${entity}`)}, 0));
  select coalesce(max(x.${fallback.seq}), 0) + 1 into ${target.seq} from ${fallback.table} x where x.${fallback.tenant} = ${tenant};
  ${target.identifier} := ${sqlString(fallback.prefix)} || ${target.seq}::text;`;
}
