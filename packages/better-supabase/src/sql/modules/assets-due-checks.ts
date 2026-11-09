import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, serviceGrant, triggerGrant } from "../shared.ts";

const plain = (qualified: string): string => qualified.replaceAll('"', "");

/**
 * A due check on an asset. The service-plan interval is a number of days, and
 * the next due date is the last completion plus that interval.
 */
export function dueChecksSql(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const assets = ctx.table("assets");
  const id = ctx.col("assets", "id");
  const tenant = ctx.col("assets", "tenant");
  const fn = (name: string): string => ctx.fn(name);
  const checks = `${ctx.schema}.asset_due_checks`;
  const read = ctx.permission("read", "assets.read");

  return `
create table if not exists ${checks} (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" ${ctx.idType} not null,
  "asset_id" uuid not null references ${assets} (${id}) on delete cascade,
  "check_type" text not null check ("check_type" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "interval_days" integer not null check ("interval_days" > 0),
  "last_done_at" timestamptz,
  "next_due_at" timestamptz,
  "result" text,
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "asset_id", "check_type")
);
create index if not exists asset_due_checks_due_idx
  on ${checks} ("tenant_id", "next_due_at") where "next_due_at" is not null;
${lockTable(checks, { read: true })}
${renderPolicy(
  makePolicy({
    table: checks,
    name: "bsb_asset_due_checks_read",
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check('"tenant_id"', read),
  }),
  { target: checks },
)}

-- Next due is the last completion plus the service-plan interval.
create or replace function ${fn("fill_asset_due_check")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new."last_done_at" is not null then
    new."next_due_at" := new."last_done_at" + make_interval(days => new."interval_days");
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
${triggerGrant(`${fn("fill_asset_due_check")}()`)}
drop trigger if exists ${ctx.trigger("asset_due_checks_fill")} on ${checks};
create trigger ${ctx.trigger("asset_due_checks_fill")}
  before insert or update of "last_done_at", "interval_days" on ${checks}
  for each row execute function ${fn("fill_asset_due_check")}();

create or replace function ${fn("import_due_check")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType} := (import_due_check.item ->> 'tenant')::${ctx.idType};
  v_data jsonb := import_due_check.item -> 'data';
  v_asset uuid;
  v_days integer;
  v_done timestamptz;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_asset := nullif(v_data ->> 'assetId', '')::uuid;
    v_days := (v_data ->> 'intervalDays')::integer;
    v_done := nullif(v_data ->> 'lastDoneAt', '')::timestamptz;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'assetId is a uuid, intervalDays is a whole number and lastDoneAt is a timestamp' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_asset is null or nullif(v_data ->> 'checkType', '') is null or v_days is null or v_days < 1 then
    raise exception 'a due check needs an assetId, a checkType and an intervalDays of 1 or more' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not exists (select 1 from ${assets} a where a.${id} = v_asset and a.${tenant} = v_tenant) then
    raise exception 'the asset is not in this organization' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into ${checks} ("tenant_id", "asset_id", "check_type", "interval_days", "last_done_at", "result")
  values (v_tenant, v_asset, v_data ->> 'checkType', v_days, v_done, nullif(v_data ->> 'result', ''))
  on conflict ("tenant_id", "asset_id", "check_type") do update set
    "interval_days" = excluded."interval_days",
    "last_done_at" = coalesce(excluded."last_done_at", ${checks}."last_done_at"),
    "result" = coalesce(excluded."result", ${checks}."result")
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$$;
${serviceGrant(`${fn("import_due_check")}(uuid, jsonb, text)`)}

create or replace function ${fn("due_check_updated_at")}(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from ${checks} x where x."id"::text = due_check_updated_at.subject_id
$$;
${serviceGrant(`${fn("due_check_updated_at")}(text)`)}
`;
}

/** The due-check import target. */
export function dueCheckImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  return own.mode === "custom"
    ? []
    : [
        {
          entity: "due_check",
          subjectType: "due_check",
          write: plain(own.fn("import_due_check")),
          updatedAt: plain(own.fn("due_check_updated_at")),
          refs: { asset: "asset" },
        },
      ];
}
