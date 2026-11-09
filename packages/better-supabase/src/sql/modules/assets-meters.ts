import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { lockTable, serviceGrant, triggerGrant } from "../shared.ts";

const plain = (qualified: string): string => qualified.replaceAll('"', "");

/**
 * Meter readings on an asset. A lower reading than the previous one of the same
 * asset and unit is stored with reason `import` and the warning
 * `IMPORT_SERIES_DECREASE`, instead of failing the batch.
 */
export function meterReadingsSql(ctx: BlockSqlContext): string {
  const assets = ctx.table("assets");
  const id = ctx.col("assets", "id");
  const tenant = ctx.col("assets", "tenant");
  const fn = (name: string): string => ctx.fn(name);
  const readings = `${ctx.schema}.${ctx.tableName("meterReadings").name}`;
  const r = (column: string): string => ctx.col("meterReadings", column);

  return `
create table if not exists ${readings} (
  "id" uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("asset")} uuid not null references ${assets} (${id}) on delete cascade,
  "unit" text not null check ("unit" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "value" numeric not null,
  "read_at" timestamptz not null,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("asset_meter_readings_asset_idx")} on ${readings} (${r("asset")});
create index if not exists ${ctx.naming.rename("asset_meter_readings_series_idx")}
  on ${readings} (${r("tenant")}, ${r("asset")}, ${r("unit")}, ${r("readAt")});
${lockTable(readings)}

create or replace function ${fn("guard_asset_meter_reading")}()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_previous numeric;
begin
  select r."value" into v_previous
  from ${readings} r
  where r.${r("tenant")} = new.${r("tenant")} and r.${r("asset")} = new.${r("asset")} and r.${r("unit")} = new.${r("unit")}
    and r."read_at" < new."read_at"
  order by r."read_at" desc
  limit 1;
  if v_previous is not null and new."value" < v_previous and new."reason" is null then
    raise exception 'a meter reading is below the previous one and has no reason' using errcode = '23514', hint = 'ASSET_METER_DECREASE_REASON';
  end if;
  return new;
end;
$$;
${triggerGrant(`${fn("guard_asset_meter_reading")}()`)}
drop trigger if exists ${ctx.trigger("asset_meter_readings_series")} on ${readings};
create trigger ${ctx.trigger("asset_meter_readings_series")}
  before insert on ${readings}
  for each row execute function ${fn("guard_asset_meter_reading")}();

create or replace function ${fn("import_meter_reading")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_meter_reading.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_meter_reading.item -> 'data';
  v_asset uuid;
  v_value numeric;
  v_at timestamptz;
  v_previous numeric;
  v_reason text;
  v_id uuid;
  v_warning boolean := false;
begin
  begin
    v_asset := nullif(v_data ->> 'assetId', '')::uuid;
    v_value := (v_data ->> 'value')::numeric;
    v_at := coalesce((v_data ->> 'readAt')::timestamptz, (v_data ->> 'orderBy')::timestamptz, now());
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'assetId is a uuid and value is a number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_asset is null or v_value is null or nullif(v_data ->> 'unit', '') is null then
    raise exception 'a meter reading needs an assetId, a unit and a value' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not exists (select 1 from ${assets} a where a.${id} = v_asset and a.${tenant} = v_tenant) then
    raise exception 'the asset is not in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."value" into v_previous from ${readings} r
  where r.${r("tenant")} = v_tenant and r.${r("asset")} = v_asset and r.${r("unit")} = v_data ->> 'unit' and r.${r("readAt")} < v_at
  order by r."read_at" desc limit 1;
  v_reason := nullif(v_data ->> 'reason', '');
  if v_previous is not null and v_value < v_previous then
    v_reason := coalesce(v_reason, 'import');
    v_warning := true;
  end if;
  if import_meter_reading.subject_id is null then
    insert into ${readings} (${r("tenant")}, ${r("asset")}, ${r("unit")}, ${r("value")}, ${r("readAt")}, ${r("reason")})
    values (v_tenant, v_asset, v_data ->> 'unit', v_value, v_at, v_reason)
    returning "id" into v_id;
  else
    update ${readings} r set "value" = v_value, "read_at" = v_at, "reason" = v_reason
    where r."id" = import_meter_reading.subject_id::uuid and r.${r("tenant")} = v_tenant
    returning r."id" into v_id;
    if v_id is null then
      raise exception 'the meter reading no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  return jsonb_build_object(
    'subjectId', v_id::text,
    'updatedAt', now(),
    'warnings', case when v_warning then jsonb_build_array(jsonb_build_object(
      'code', 'IMPORT_SERIES_DECREASE',
      'message', 'the reading is below the previous one and was stored with reason import'
    )) else '[]'::jsonb end
  );
end;
$$;
${serviceGrant(`${fn("import_meter_reading")}(uuid, jsonb, text)`)}
`;
}

/** The meter reading import target. */
export function meterImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return own.mode === "custom"
    ? []
    : [
        {
          entity: "meter_reading",
          subjectType: "meter_reading",
          write: plain(own.fn("import_meter_reading")),
        },
      ];
}
