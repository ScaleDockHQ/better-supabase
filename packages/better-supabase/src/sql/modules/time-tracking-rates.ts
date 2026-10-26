import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { addCheck } from "../shared.ts";

/**
 * The rate's currency is an uppercase three-letter code (the client checks it
 * against ISO 4217) and is set exactly when the rate is. Added once, so new and
 * upgraded tables carry the same named checks.
 */
export function rateChecks(ctx: BlockSqlContext): string {
  const entries = ctx.table("entries");
  const name = ctx.tableName("entries").name;
  const rate = ctx.col("entries", "rate");
  const currency = ctx.col("entries", "rateCurrency");

  return `${addCheck({
    table: entries,
    name: `${name}_rate_currency_check`,
    expression: `${currency} is null or ${currency} ~ '^[A-Z]{3}$'`,
  })}
${addCheck({
  table: entries,
  name: `${name}_rate_pair_check`,
  expression: `(${rate} is null) = (${currency} is null)`,
})}`;
}

/** The functions' signatures before the rate became minor units and a currency. */
const NUMERIC_SIGNATURES = {
  start_timer: (id: string) => `${id}, text, text, boolean, numeric, text`,
  log_time: (id: string) =>
    `${id}, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid`,
};

export function dropNumericSignatures(ctx: BlockSqlContext): string {
  return Object.entries(NUMERIC_SIGNATURES)
    .flatMap(([name, types]) => [
      `drop function if exists ${ctx.fn(name)}(${types(ctx.idType)});`,
      `drop function if exists ${ctx.fn(name)}(${types(ctx.idType)}, jsonb);`,
    ])
    .join("\n");
}

/**
 * Version 1 stored the rate as `numeric(12, 2)` with no currency. Its two
 * decimals become minor units (times 100), and rates stay without a currency
 * until the app sets one; the pair check then warns.
 */
export function upgradeRateToMoney(ctx: BlockSqlContext): string {
  if (!ctx.owns("entries")) {
    return dropNumericSignatures(ctx);
  }

  const entries = ctx.table("entries");
  const { schema, name } = ctx.tableName("entries");
  const rate = ctx.col("entries", "rate");

  return `${dropNumericSignatures(ctx)}
alter table ${entries} add column if not exists ${ctx.col("entries", "rateCurrency")} text;
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = ${sqlString(schema)} and table_name = ${sqlString(name)}
      and column_name = ${sqlString(rate.replaceAll('"', ""))} and data_type = 'numeric'
  ) then
    alter table ${entries} alter column ${rate} type bigint using round(${rate} * 100)::bigint;
  end if;
end;
$$;
${rateChecks(ctx)}`;
}
