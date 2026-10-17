import type { ModuleContext } from "./context.ts";

import { sqlString } from "../core/template.ts";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The `number-sequences` format of `entity`, when the app configured one. */
function sequenceFormatOf(
  ctx: ModuleContext,
  entity: string,
): string | undefined {
  if (!ctx.installed("number-sequences")) {
    return undefined;
  }

  const entities = ctx.of("number-sequences").option("entities");

  if (!isRecord(entities)) {
    return undefined;
  }

  const entry = entities[entity];

  if (!isRecord(entry) || typeof entry["format"] !== "string") {
    return undefined;
  }

  return entry["format"];
}

/**
 * PL/pgSQL that assigns the next number of `entity` in `tenant` to
 * `target.seq` (bigint) and `target.identifier` (text): from
 * `number-sequences` when it configures the entity, otherwise one more than
 * the tenant's highest in `fallback.table` under a transaction lock, with
 * `prefix` in front (`DEAL-4821`).
 */
export function assignNumberSql(
  ctx: ModuleContext,
  entity: string,
  tenant: string,
  target: { readonly seq: string; readonly identifier: string },
  fallback: {
    readonly table: string;
    readonly seq: string;
    readonly tenant: string;
    readonly prefix: string;
  },
): string {
  const format = sequenceFormatOf(ctx, entity);

  if (format !== undefined) {
    const next = ctx.of("number-sequences").fn("next_number");

    return `${target.seq} := ${next}(${tenant}, ${sqlString(entity)}, now());
  ${target.identifier} := better_supabase.format_assigned_number(${sqlString(format)}, ${target.seq}, now());`;
  }

  return `perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(${tenant}::text || ${sqlString(`:${entity}`)}, 0));
  select coalesce(max(x.${fallback.seq}), 0) + 1 into ${target.seq} from ${fallback.table} x where x.${fallback.tenant} = ${tenant};
  ${target.identifier} := ${sqlString(fallback.prefix)} || ${target.seq}::text;`;
}
