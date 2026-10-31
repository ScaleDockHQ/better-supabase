import type { BlockSqlContext } from "../context.ts";
import type { DamSql } from "./dam-sql.ts";

import { pageSize, serviceGrant, userGrant } from "../shared.ts";
import { damSql } from "./dam-sql.ts";
import { DAM_RENDITION_STATUSES } from "./dam-values.ts";

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function renditionFunctions(ctx: BlockSqlContext, q: DamSql): string {
  const { fn, n, renditions } = q;
  const idType = ctx.idType;

  return `
-- Records one rendition of a file, replacing the one of the same kind. input
-- is { status: 'pending' | 'ready' | 'failed', format, width, height,
-- sizeBytes, path, error }. A renderer job calls it as the service role, a
-- member needs dam.write.
create or replace function ${fn("record_rendition")}(tenant ${idType}, node_id uuid, kind text, input jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${renditions};
  v_input jsonb := coalesce(record_rendition.input, '{}'::jsonb);
  v_status text := coalesce(nullif(v_input ->> 'status', ''), 'ready');
begin
  if not ${q.allowed("record_rendition.tenant", q.write)} then
    ${q.forbidden("not allowed to record renditions")}
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  if record_rendition.kind is null or record_rendition.kind !~ '^[a-z][a-z0-9_]{0,40}$' then
    ${q.invalid("a rendition kind is lowercase letters, digits and underscores, up to 41 characters")}
  end if;
  if v_status not in (${list(DAM_RENDITION_STATUSES)}) then
    ${q.invalid("the status is pending, ready or failed")}
  end if;
  begin
    insert into ${renditions} (${n("tenant")}, ${n("node")}, ${n("kind")}, ${n("status")}, ${n("format")}, ${n("width")}, ${n("height")}, ${n("sizeBytes")}, ${n("path")}, ${n("error")})
    values (record_rendition.tenant, record_rendition.node_id, record_rendition.kind, v_status,
      nullif(v_input ->> 'format', ''), (v_input ->> 'width')::integer, (v_input ->> 'height')::integer,
      (v_input ->> 'sizeBytes')::bigint, nullif(v_input ->> 'path', ''), nullif(v_input ->> 'error', ''))
    on conflict (${n("tenant")}, ${n("node")}, ${n("kind")}) do update set
      ${n("status")} = excluded.${n("status")}, ${n("format")} = excluded.${n("format")}, ${n("width")} = excluded.${n("width")},
      ${n("height")} = excluded.${n("height")}, ${n("sizeBytes")} = excluded.${n("sizeBytes")}, ${n("path")} = excluded.${n("path")},
      ${n("error")} = excluded.${n("error")}, ${n("updatedAt")} = now()
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    ${q.invalid("a rendition has a format of up to 20 characters, a width and height above 0, a size of 0 or more and a path of up to 1000 characters")}
  end;
  ${ctx.record({
    type: "dam_rendition.recorded",
    payload: `jsonb_build_object('organizationId', v_row.${n("tenant")}, 'id', v_row.${n("id")}, 'nodeId', v_row.${n("node")}, 'kind', v_row.${n("kind")}, 'status', v_row.${n("status")})`,
    subject: `'dam-renditions/' || v_row.${n("id")}::text`,
    tenant: `v_row.${n("tenant")}`,
    audit: false,
  })}
  return ${q.renditionJson("v_row")};
end;
$$;
${userGrant(`${fn("record_rendition")}(${idType}, uuid, text, jsonb)`)}

-- The renditions of a file, by kind.
create or replace function ${fn("list_renditions")}(tenant ${idType}, node_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("list_renditions.tenant", q.read)} then
    ${q.forbidden("not allowed to read renditions")}
  end if;
  return coalesce((
    select jsonb_agg(${q.renditionJson("x")} order by x.${n("kind")})
    from ${renditions} x
    where x.${n("tenant")} = list_renditions.tenant and x.${n("node")} = list_renditions.node_id
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_renditions")}(${idType}, uuid)`)}
`;
}

function rightFunctions(ctx: BlockSqlContext, q: DamSql): string {
  const { fn, u, rights } = q;
  const idType = ctx.idType;

  return `
-- Grants a usage right on a file. input is { nodeId, licensee, territory,
-- channel, startsOn, expiresOn, note }. A right without territory or channel
-- covers every territory or channel; without expiresOn it never expires.
-- Needs dam.write.
create or replace function ${fn("grant_usage_right")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rights};
begin
  if not ${q.allowed("grant_usage_right.tenant", q.write)} then
    ${q.forbidden("not allowed to grant usage rights")}
  end if;
  if jsonb_typeof(grant_usage_right.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  ${ctx.hook("before_dam_usage_right_create", [
    [idType, "grant_usage_right.tenant"],
    ["jsonb", "grant_usage_right.input"],
  ])}
  begin
    insert into ${rights} (${u("tenant")}, ${u("node")}, ${u("licensee")}, ${u("territory")}, ${u("channel")}, ${u("startsOn")}, ${u("expiresOn")}, ${u("note")}, ${u("createdBy")})
    values (grant_usage_right.tenant, (grant_usage_right.input ->> 'nodeId')::uuid, trim(grant_usage_right.input ->> 'licensee'),
      nullif(trim(grant_usage_right.input ->> 'territory'), ''), nullif(trim(grant_usage_right.input ->> 'channel'), ''),
      coalesce((grant_usage_right.input ->> 'startsOn')::date, current_date), (grant_usage_right.input ->> 'expiresOn')::date,
      nullif(trim(grant_usage_right.input ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${q.invalid("a usage right needs a nodeId, a licensee of 1 to 200 characters and an expiresOn on or after startsOn")}
  end;
  ${q.recordRight("dam_usage_right.granted", "v_row", "usage right granted")}
  ${ctx.hook("after_dam_usage_right_create", [["uuid", `v_row.${u("id")}`]])}
  return ${q.rightJson("v_row")};
end;
$$;
${userGrant(`${fn("grant_usage_right")}(${idType}, jsonb)`)}

-- Revokes a usage right. It stays in the history as revoked. Needs dam.write.
create or replace function ${fn("revoke_usage_right")}(right_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rights};
begin
  select * into v_row from ${rights} x where x.${u("id")} = revoke_usage_right.right_id for update;
  if not found or not ${q.allowed(`v_row.${u("tenant")}`, q.read)} then
    ${q.rightMissing}
  end if;
  if not ${q.allowed(`v_row.${u("tenant")}`, q.write)} then
    ${q.forbidden("not allowed to revoke usage rights")}
  end if;
  if v_row.${u("revokedAt")} is null then
    update ${rights} x set ${u("revokedAt")} = now() where x.${u("id")} = v_row.${u("id")} returning * into v_row;
    ${q.recordRight("dam_usage_right.revoked", "v_row", "usage right revoked")}
  end if;
  return ${q.rightJson("v_row")};
end;
$$;
${userGrant(`${fn("revoke_usage_right")}(uuid)`)}

-- Usage rights, soonest expiry first. filters is { nodeId, status: 'upcoming'
-- | 'active' | 'expired' | 'revoked', expiringWithinDays, limit, offset }.
create or replace function ${fn("list_usage_rights")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_usage_rights.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
begin
  if not ${q.allowed("list_usage_rights.tenant", q.read)} then
    ${q.forbidden("not allowed to read usage rights")}
  end if;
  return coalesce((
    select jsonb_agg(${q.rightJson("y")} order by y.${u("expiresOn")} nulls last, y.${u("id")})
    from (
      select * from ${rights} x
      where x.${u("tenant")} = list_usage_rights.tenant
        and (not v_filters ? 'nodeId' or x.${u("node")} = (v_filters ->> 'nodeId')::uuid)
        and (not v_filters ? 'status' or ${q.rightStatus("x", "current_date")} = v_filters ->> 'status')
        and (not v_filters ? 'expiringWithinDays' or (
          x.${u("revokedAt")} is null and x.${u("expiresOn")} is not null
          and x.${u("expiresOn")} between current_date and current_date + (v_filters ->> 'expiringWithinDays')::integer
        ))
      order by x.${u("expiresOn")} nulls last, x.${u("id")}
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_usage_rights")}(${idType}, jsonb)`)}

-- Whether a file may be used. filters is { on, territory, channel }: a right
-- that is active that day and names that territory and channel, or names none,
-- allows it. Returns { allowed, rightId, expiresOn }. A file without any
-- right is not allowed.
create or replace function ${fn("check_usage")}(tenant ${idType}, node_id uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(check_usage.filters, '{}'::jsonb);
  v_day date := coalesce((v_filters ->> 'on')::date, current_date);
  v_row ${rights};
begin
  if not ${q.allowed("check_usage.tenant", q.read)} then
    ${q.forbidden("not allowed to read usage rights")}
  end if;
  select * into v_row from ${rights} x
  where x.${u("tenant")} = check_usage.tenant and x.${u("node")} = check_usage.node_id
    and ${q.rightStatus("x", "v_day")} = 'active'
    and (x.${u("territory")} is null or x.${u("territory")} = v_filters ->> 'territory')
    and (x.${u("channel")} is null or x.${u("channel")} = v_filters ->> 'channel')
  order by x.${u("expiresOn")} desc nulls first, x.${u("id")}
  limit 1;
  if not found then
    return jsonb_build_object('allowed', false, 'rightId', null, 'expiresOn', null);
  end if;
  return jsonb_build_object('allowed', true, 'rightId', v_row.${u("id")}, 'expiresOn', v_row.${u("expiresOn")});
end;
$$;
${userGrant(`${fn("check_usage")}(${idType}, uuid, jsonb)`)}
`;
}

function reminder(ctx: BlockSqlContext, q: DamSql): string {
  const { fn, u, rights } = q;

  if (!ctx.installed("notifications")) {
    return `
-- Without the notifications block there is nobody to tell; the function stays so
-- the client and its schedule work the same everywhere.
create or replace function ${fn("notify_expiring_usage_rights")}(days integer default 30)
returns integer
language sql
security definer
set search_path = ''
as $$ select 0 $$;
${serviceGrant(`${fn("notify_expiring_usage_rights")}(integer)`)}
`;
  }

  return `
-- Tells the member who granted a right that it ends within days days, once per
-- expiry date (changing the date allows a new notice). Run it daily from a job.
-- Returns how many rights it reported.
create or replace function ${fn("notify_expiring_usage_rights")}(days integer default 30)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${rights};
  v_claims text;
  v_count integer := 0;
begin
  for v_row in
    select * from ${rights} x
    where x.${u("revokedAt")} is null and x.${u("expiresOn")} is not null
      and x.${u("expiresOn")} between current_date and current_date + greatest(notify_expiring_usage_rights.days, 0)
      and x.${u("remindedFor")} is distinct from x.${u("expiresOn")}
    for update skip locked
  loop
    if v_row.${u("createdBy")} is not null then
      ${ctx.notify(
        `jsonb_build_object(
        'type', 'dam_usage_right.expiry_notified',
        'tenant', v_row.${u("tenant")},
        'actor', null,
        'subject_type', ${q.subject},
        'subject_id', v_row.${u("id")}::text,
        'summary', v_row.${u("licensee")},
        'recipients', to_jsonb(array[v_row.${u("createdBy")}]),
        'key', 'dam_usage_right.expiry_notified:' || v_row.${u("id")}::text || ':' || v_row.${u("expiresOn")}::text,
        'data', jsonb_build_object('usageRightId', v_row.${u("id")}, 'nodeId', v_row.${u("node")}, 'expiresOn', v_row.${u("expiresOn")})
      )`,
        { indent: "      " },
      )}
    end if;
    update ${rights} x set ${u("remindedFor")} = v_row.${u("expiresOn")} where x.${u("id")} = v_row.${u("id")};
    ${q.recordRight("dam_usage_right.expiry_notified", "v_row", "usage right expires soon")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_expiring_usage_rights")}(integer)`)}
`;
}

export function damFunctions(ctx: BlockSqlContext): string {
  const q = damSql(ctx);

  return `${renditionFunctions(ctx, q)}${rightFunctions(ctx, q)}${reminder(ctx, q)}`;
}
