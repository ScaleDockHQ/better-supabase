import type { BlockSqlContext } from "../context.ts";
import type { SequenceEntity } from "./numbering-entities.ts";

import { fail, serviceGrant } from "../shared.ts";

/**
 * `number_scope(tenant, legal_entity)`: the scope text of a legal entity. The
 * default entity, which a null column also means, is the empty scope, so both
 * spellings share one series.
 */
export function scopeFunction(ctx: BlockSqlContext): string {
  const fn = ctx.fn("number_scope");

  const entities = ctx.installed("legal-entities")
    ? ctx.of("legal-entities")
    : undefined;

  const standard =
    entities === undefined
      ? ""
      : `
  if exists (
    select 1 from ${entities.table("entities")} e
    where e.${entities.col("entities", "tenant")} = p_tenant
      and e.${entities.col("entities", "id")} = p_legal_entity
      and e.${entities.col("entities", "isDefault")}
  ) then
    return '';
  end if;`;

  return `
-- The series scope of a legal entity: the empty text for the default entity.
create or replace function ${fn}(p_tenant ${ctx.idType}, p_legal_entity uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_legal_entity is null then
    return '';
  end if;${standard}
  return p_legal_entity::text;
end;
$$;
${serviceGrant(`${fn}(${ctx.idType}, uuid)`)}`;
}

/**
 * `register_fixed_number` and `set_fixed_number`: a historical number taken as
 * is during an import. The counter rises to the number when it follows the
 * format; a number that doesn't is kept and listed by the sync's report.
 */
export function fixedNumberFunctions(
  ctx: BlockSqlContext,
  items: readonly SequenceEntity[],
  periodCase: string,
): string {
  const register = ctx.fn("register_fixed_number");
  const set = ctx.fn("set_fixed_number");
  const table = ctx.table("sequences");
  const tenant = ctx.col("sequences", "tenant");
  const entityCol = ctx.col("sequences", "entity");
  const scopeCol = ctx.col("sequences", "scope");
  const period = ctx.col("sequences", "period");
  const last = ctx.col("sequences", "lastNumber");
  const updatedAt = ctx.col("sequences", "updatedAt");

  const format =
    items.length === 0
      ? "null"
      : `${ctx.fn("number_format")}(p_tenant, p_entity)`;

  return `
-- Takes a historical number as is. Only an import (better_supabase.import_run()
-- is set) may do it; anything else gets NUMBER_FIXED_FORBIDDEN. Raises the
-- counter of the entity, scope and period to the number when it matches the
-- current format and returns the number's sequence part. A number in another
-- format is kept: it returns the digits it ends with and sync_number_sequences
-- lists it.
create or replace function ${register}(p_tenant ${ctx.idType}, p_entity text, p_number text, p_at timestamptz default now(), p_scope text default '')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_format text;
  v_period text;
  v_parts text[];
  v_n bigint;
begin
  if better_supabase.import_run() is null then
    ${fail("NUMBER_FIXED_FORBIDDEN", "a fixed number is only accepted during an import", "42501")}
  end if;
  if nullif(btrim(p_number), '') is null or length(p_number) > 200 then
    ${fail("NUMBER_FIXED_INVALID", "a fixed number is 1 to 200 characters", "22023")}
  end if;
  v_format := ${format};
  v_period := ${periodCase};
  if v_format is null or v_period is null then
    ${fail("NUMBER_ENTITY_UNKNOWN", "unknown number sequence", "22023")}
  end if;
  v_parts := regexp_match(p_number, better_supabase.number_format_pattern(v_format));
  if v_parts is null or v_parts[1] is null or length(v_parts[1]) > 18 then
    return case
      when p_number ~ '[0-9]{1,18}$' then substring(p_number from '([0-9]{1,18})$')::bigint
      else 0
    end;
  end if;
  v_n := v_parts[1]::bigint;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into ${table} (${tenant}, ${entityCol}, ${scopeCol}, ${period}, ${last})
  values (p_tenant, ${ctx.cast("sequences", "entity", "p_entity")}, coalesce(p_scope, ''), v_period, v_n)
  on conflict (${tenant}, ${entityCol}, ${scopeCol}, ${period})
  do update set ${last} = greatest(${table}.${last}, excluded.${last}), ${updatedAt} = now();
  return v_n;
end;
$$;
${serviceGrant(`${register}(${ctx.idType}, text, text, timestamptz, text)`)}

-- Names the number the next document of an entity takes, for the entities
-- that have no argument for it (quotes, orders, cases and the rest). Import
-- mode only; the creating function uses the number once and clears it.
create or replace function ${set}(p_entity text, p_number text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if better_supabase.import_run() is null then
    ${fail("NUMBER_FIXED_FORBIDDEN", "a fixed number is only accepted during an import", "42501")}
  end if;
  if nullif(btrim(p_entity), '') is null or nullif(btrim(p_number), '') is null then
    ${fail("NUMBER_FIXED_INVALID", "name the entity and its number", "22023")}
  end if;
  perform set_config('better_supabase.fixed_number', p_entity || chr(31) || p_number, true);
end;
$$;
${serviceGrant(`${set}(text, text)`)}`;
}
