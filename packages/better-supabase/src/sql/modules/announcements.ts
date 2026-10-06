import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["topic", "event"],
  tables: {
    announcements: {
      name: "announcements",
      columns: {
        id: "id",
        title: "title",
        body: "body",
        severity: "severity",
        href: "href",
        audience: "audience",
        targets: "targets",
        startsAt: "starts_at",
        endsAt: "ends_at",
        dismissible: "dismissible",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    dismissals: {
      name: "announcement_dismissals",
      columns: {
        announcement: "announcement_id",
        user: "user_id",
        dismissedAt: "dismissed_at",
      },
    },
  },
};

const TOPIC = /^[A-Za-z0-9_.:-]{1,100}$/;

/** The columns save_announcement may change on an existing row. */
const EDITABLE = [
  "title",
  "body",
  "severity",
  "href",
  "audience",
  "targets",
  "startsAt",
  "endsAt",
  "dismissible",
  "updatedAt",
] as const;

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const a = ctx.table("announcements");
  const d = ctx.table("dismissals");
  const ca = (c: string): string => ctx.col("announcements", c);
  const cd = (c: string): string => ctx.col("dismissals", c);
  const raw = (c: string): string => sqlString(ca(c).replaceAll('"', ""));
  const manage = ctx.permission(
    "manage",
    MODULE_PERMISSIONS.announcements.manage,
  );
  const staff = `(${SERVICE_CALLER} or coalesce(better_supabase.is_platform(${manage}), false))`;
  const plans = ctx.installed("entitlements");
  const audiences = ["all", "tenant", "role", ...(plans ? ["plan"] : [])];
  const topic = ctx.text("topic", "announcements");
  if (!TOPIC.test(topic)) {
    throw new TypeError(
      "sql.modules.announcements.options.topic: use letters, digits, '_', '.', ':' or '-'",
    );
  }
  const event = ctx.text("event", "announcement_changed");
  const receive = ctx.trigger("announcements_receive");
  const trigger = ctx.trigger("announcements_broadcast");
  const planMatch = plans
    ? `when 'plan' then v_tenant is not null and x.${ca("targets")} && better_supabase.tenant_entitlements(v_tenant)`
    : "";

  return `${schemaPreamble(ctx)}
-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table if not exists ${a} (
  ${ca("id")} uuid primary key default gen_random_uuid(),
  ${ca("title")} text not null check (length(${ca("title")}) between 1 and 200),
  ${ca("body")} text not null default '' check (length(${ca("body")}) <= 10000),
  ${ca("severity")} text not null default 'info' check (${ca("severity")} in ('info', 'success', 'warning', 'critical')),
  ${ca("href")} text check (${ca("href")} ~ '^(https://|/)'),
  ${ca("audience")} text not null default 'all',
  ${ca("targets")} text[] not null default '{}',
  ${ca("startsAt")} timestamptz not null default now(),
  ${ca("endsAt")} timestamptz,
  ${ca("dismissible")} boolean not null default true,
  ${ca("createdBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${ca("createdAt")} timestamptz not null default now(),
  ${ca("updatedAt")} timestamptz not null default now(),
  check (${ca("endsAt")} is null or ${ca("endsAt")} > ${ca("startsAt")}),
  check ((${ca("audience")} = 'all') = (cardinality(${ca("targets")}) = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.
alter table ${a} drop constraint if exists bs_announcements_audience;
alter table ${a} add constraint bs_announcements_audience check (${ca("audience")} in (${audiences.map(sqlString).join(", ")}));
create index if not exists announcements_window_idx on ${a} (${ca("startsAt")}, ${ca("endsAt")});
create index if not exists announcements_created_by_idx on ${a} (${ca("createdBy")});
alter table ${a} enable row level security;
revoke all on ${a} from anon, authenticated;
grant all on ${a} to service_role;

create table if not exists ${d} (
  ${cd("announcement")} uuid not null references ${a} (${ca("id")}) on delete cascade,
  ${cd("user")} uuid not null references auth.users (id) on delete cascade,
  ${cd("dismissedAt")} timestamptz not null default now(),
  primary key (${cd("announcement")}, ${cd("user")})
);
create index if not exists announcement_dismissals_user_idx on ${d} (${cd("user")});
alter table ${d} enable row level security;
revoke all on ${d} from anon, authenticated;
grant all on ${d} to service_role;

-- The caller's live, undismissed announcements, newest first. Pass the
-- active tenant for tenant, role and plan audiences; a tenant the caller
-- isn't a member of counts as none.
create or replace function ${fn("active_announcements")}(tenant ${id} default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant ${id} := active_announcements.tenant;
  v_role text;
begin
  if v_tenant is not null then
    v_role := better_supabase.organization_member_role(v_tenant, v_user);
    if v_role is null and not ${SERVICE_CALLER} then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) - ${raw("targets")} order by x.${ca("startsAt")} desc), '[]'::jsonb)
    from ${a} x
    where x.${ca("startsAt")} <= now()
      and (x.${ca("endsAt")} is null or x.${ca("endsAt")} > now())
      and case x.${ca("audience")}
        when 'all' then true
        when 'tenant' then v_tenant is not null and v_tenant::text = any (x.${ca("targets")})
        when 'role' then v_role is not null and v_role = any (x.${ca("targets")})
        ${planMatch}
        else false
      end
      and not exists (
        select 1 from ${d} s
        where s.${cd("announcement")} = x.${ca("id")} and s.${cd("user")} = v_user
      )
  );
end;
$$;

-- Hides an announcement for the caller; false when it was hidden already.
create or replace function ${fn("dismiss_announcement")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x.${ca("dismissible")} into v_dismissible from ${a} x where x.${ca("id")} = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into ${d} (${cd("announcement")}, ${cd("user")}) values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Every announcement, for staff (announcements.manage on the platform).
create or replace function ${fn("list_announcements")}()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${staff} then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.${ca("startsAt")} desc), '[]'::jsonb)
    from ${a} x
  );
end;
$$;

-- Creates an announcement (id null) or changes one. fields holds the
-- columns to set; the others keep their value or default.
create or replace function ${fn("save_announcement")}(id uuid, fields jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${a};
begin
  if not ${staff} then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::${a}, jsonb_build_object(
      ${raw("id")}, gen_random_uuid(),
      ${raw("body")}, '',
      ${raw("severity")}, 'info',
      ${raw("audience")}, 'all',
      ${raw("targets")}, '{}'::text[],
      ${raw("startsAt")}, now(),
      ${raw("dismissible")}, true,
      ${raw("createdBy")}, auth.uid(),
      ${raw("createdAt")}, now()
    ) || save_announcement.fields);
    v_row.${ca("updatedAt")} := now();
    insert into ${a} select v_row.* returning * into v_row;
  else
    select * into v_row from ${a} x where x.${ca("id")} = save_announcement.id for update;
    if v_row.${ca("id")} is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - ${raw("id")} - ${raw("createdBy")} - ${raw("createdAt")});
    v_row.${ca("updatedAt")} := now();
    update ${a} x set (${EDITABLE.map(ca).join(", ")}) = (${EDITABLE.map((c) => `v_row.${ca(c)}`).join(", ")})
    where x.${ca("id")} = v_row.${ca("id")}
    returning * into v_row;
  end if;
  return to_jsonb(v_row);
end;
$$;

create or replace function ${fn("delete_announcement")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not ${staff} then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from ${a} x where x.${ca("id")} = delete_announcement.id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Tells signed-in clients on the ${topic} topic that announcements changed;
-- they load the list again through active_announcements().
create or replace function ${fn("broadcast_announcement")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('id', coalesce(new.${ca("id")}, old.${ca("id")}), 'operation', lower(tg_op)),
      ${sqlString(event)},
      ${sqlString(topic)},
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("broadcast_announcement")}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${a};
create trigger ${trigger} after insert or update or delete on ${a}
  for each row execute function ${fn("broadcast_announcement")}();
do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${receive} on realtime.messages;
    create policy ${receive} on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = ${sqlString(topic)});
  end if;
end;
$$;

revoke execute on function ${fn("active_announcements")}(${id}) from public, anon;
revoke execute on function ${fn("dismiss_announcement")}(uuid) from public, anon;
revoke execute on function ${fn("list_announcements")}() from public, anon;
revoke execute on function ${fn("save_announcement")}(uuid, jsonb) from public, anon;
revoke execute on function ${fn("delete_announcement")}(uuid) from public, anon;
grant execute on function ${fn("active_announcements")}(${id}) to authenticated, service_role;
grant execute on function ${fn("dismiss_announcement")}(uuid) to authenticated, service_role;
grant execute on function ${fn("list_announcements")}() to authenticated, service_role;
grant execute on function ${fn("save_announcement")}(uuid, jsonb) to authenticated, service_role;
grant execute on function ${fn("delete_announcement")}(uuid) to authenticated, service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "active_announcements", args: ["{id}"], returns: "jsonb" },
    { name: "dismiss_announcement", args: ["uuid"], returns: "boolean" },
    { name: "list_announcements", args: [], returns: "jsonb" },
    { name: "save_announcement", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "delete_announcement", args: ["uuid"], returns: "boolean" },
  ];
}

export const ANNOUNCEMENTS: ModuleDefinition = {
  name: "announcements",
  title: "Announcements",
  description:
    "In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
