import type { BlockSqlContext } from "./context.ts";

import { isRecord } from "../core/guards.ts";
import { sqlString } from "../core/template.ts";
import { sequenceEntry } from "./modules/numbering-entities.ts";
import { fail } from "./shared.ts";

/**
 * The `numbering` format of `entity` in `tenant` as SQL, when the app
 * configured one or the block contributes a default.
 */
export function sequenceFormatOf(
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
 * The SQL expression that holds the fixed number an importer set for `entity`
 * with `set_fixed_number`, or null.
 */
function fixedSettingSql(entity: string, entitySql?: string): string {
  const setting =
    "coalesce(current_setting('better_supabase.fixed_number', true), '')";

  return `(case when split_part(${setting}, chr(31), 1) = ${entitySql ?? sqlString(entity)} then nullif(split_part(${setting}, chr(31), 2), '') end)`;
}

/**
 * Whether the legal entity column `key` of \`options.on\` exists on a table of
 * the calling module, so its rows have a number scope.
 */
export function hasLegalEntityColumn(
  ctx: BlockSqlContext,
  key: string,
): boolean {
  return (
    ctx.installed("legal-entities") &&
    ctx.of("legal-entities").list("on", []).includes(key)
  );
}

/**
 * The scope SQL of a row: its legal entity, normalized by `number_scope`, or
 * the empty scope when the table has no legal entity column.
 */
export function scopeSql(
  ctx: BlockSqlContext,
  key: string,
  tenant: string,
  row: string,
): string {
  return hasLegalEntityColumn(ctx, key) && ctx.installed("numbering")
    ? `${ctx.of("numbering").fn("number_scope")}(${tenant}, ${row}.legal_entity_id)`
    : "''";
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
  options: AssignOptions = {},
): string {
  const sequence = sequenceFormatOf(ctx, entity, tenant);
  const scope = options.scope ?? "''";
  // A legal entity scope: the fallback counts that entity's rows only.
  const scoped = scope !== "''";

  if (sequence !== undefined) {
    const next = ctx.of("numbering").fn("next_number");

    const issued = sequence.assigns
      ? `
  perform set_config('better_supabase.issued_number', ${sqlString(entity)} || chr(31) || ${target.seq}::text || chr(31) || ${target.identifier}, true);`
      : "";

    return withFixedNumber(
      ctx,
      entity,
      tenant,
      { seq: target.seq, text: target.identifier },
      `${target.seq} := ${next}(${tenant}, ${sqlString(entity)}, ${at}, ${scope});
  ${target.identifier} := better_supabase.format_assigned_number(${sequence.format}, ${target.seq}, ${at});${issued}`,
      {
        at,
        scope,
        registered: true,
        ...(options.fixed === undefined ? {} : { fixed: options.fixed }),
        after: issued,
      },
    );
  }

  return withFixedNumber(
    ctx,
    entity,
    tenant,
    { seq: target.seq, text: target.identifier },
    `perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(${tenant}::text || ${sqlString(`:${entity}`)}${scoped ? ` || ':' || ${scope}` : ""}, 0));
  select coalesce(max(x.${fallback.seq}), 0) + 1 into ${target.seq} from ${fallback.table} x where x.${fallback.tenant} = ${tenant}${scoped ? ` and ${ctx.of("numbering").fn("number_scope")}(x.${fallback.tenant}, x.legal_entity_id) = ${scope}` : ""};
  ${target.identifier} := ${sqlString(fallback.prefix)} || ${target.seq}::text;`,
    {
      at,
      scope,
      ...(options.fixed === undefined ? {} : { fixed: options.fixed }),
    },
  );
}

export interface AssignOptions {
  /** The number scope SQL, such as a legal entity; the empty scope by default. */
  readonly scope?: string;
  /** SQL text of a fixed number to take instead of the next one (import mode). */
  readonly fixed?: string;
}

/**
 * Wraps `normal`, the SQL that takes the next number, so an importer's fixed
 * number (the `fixed` expression, else the one `set_fixed_number` stored for
 * `entity`) is used instead. A fixed number needs import mode: with numbering
 * installed `register_fixed_number` refuses it outside, and the counter rises
 * to the number when it follows the format. The number text goes to
 * `target.text`, its sequence number to `target.seq`.
 */
export function withFixedNumber(
  ctx: BlockSqlContext,
  entity: string,
  tenant: string,
  target: { readonly seq: string; readonly text: string },
  normal: string,
  options: {
    readonly at: string;
    readonly scope: string;
    readonly fixed?: string;
    readonly after?: string;
    /** The entity has a numbering sequence, so its counter rises. */
    readonly registered?: boolean;
    /** SQL that holds the entity name when it is chosen at run time. */
    readonly entitySql?: string;
  },
): string {
  const named = options.entitySql ?? sqlString(entity);
  const setting = fixedSettingSql(entity, options.entitySql);

  const fixed =
    options.fixed === undefined
      ? setting
      : `coalesce(${options.fixed}, ${setting})`;

  const register =
    options.registered === true
      ? `${target.seq} := ${ctx.of("numbering").fn("register_fixed_number")}(${tenant}, ${named}, ${target.text}, ${options.at}, ${options.scope});`
      : `if better_supabase.import_run() is null then
      ${fail("NUMBER_FIXED_FORBIDDEN", "a fixed number is only accepted during an import", "42501")}
    end if;
    ${target.seq} := coalesce(substring(${target.text} from '([0-9]+)$')::bigint, 0);`;

  return `if ${fixed} is not null then
    ${target.text} := ${fixed};
    ${register}
    perform set_config('better_supabase.fixed_number', '', true);${options.after ?? ""}
  else
    ${normal}
  end if;`;
}
