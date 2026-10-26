import type { AnnouncementsEvents } from "../../blocks/announcements/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  withExtraFields,
  schemaPreamble,
  SERVICE_CALLER,
  lockTable,
  fail,
  raise,
} from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<AnnouncementsEvents> = {
  "announcement.saved": {
    subject: "announcements",
    payload: ["announcementId"],
  },
  "announcement.deleted": {
    subject: "announcements",
    payload: ["announcementId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    announcement: {
      table: "announcements",
      singular: "announcement",
      primary: true,
    },
  },
  events: EVENTS,
  options: ["topic", "event", "extraColumns"],
  tables: {
    announcements: {
      name: "announcements",
      app: {},
      optional: ["body", "href", "createdBy", "createdAt", "updatedAt"],
      typed: ["severity", "audience"],
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
      app: {},
      lifecycle: { user: "user" },
      optional: ["dismissedAt"],
      columns: {
        announcement: "announcement_id",
        user: "user_id",
        dismissedAt: "dismissed_at",
      },
    },
  },
};

const TOPIC = /^[A-Za-z0-9_.:-]{1,100}$/;

/** The columns save_announcement writes on a new row. */
const COLUMNS = [
  "id",
  "title",
  "body",
  "severity",
  "href",
  "audience",
  "targets",
  "startsAt",
  "endsAt",
  "dismissible",
  "createdBy",
  "createdAt",
  "updatedAt",
] as const;

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

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const a = ctx.table("announcements");
  const d = ctx.table("dismissals");
  const ca = (c: string): string => ctx.col("announcements", c);
  const cd = (c: string): string => ctx.col("dismissals", c);
  const raw = (c: string): string => sqlString(ca(c).replaceAll('"', ""));
  const has = (c: string): boolean => ctx.has("announcements", c);
  const extras = ctx.extraColumns("announcements", ["fields"]);

  const editable = [
    ...EDITABLE.filter(has).map(ca),
    ...extras.map((extra) => extra.ident),
  ];

  const written = [
    ...COLUMNS.filter(has).map(ca),
    ...extras.map((extra) => extra.ident),
  ];

  // On the app's table, a new row names its columns so the app's other
  // columns keep their defaults.
  const insertRow = ctx.owns("announcements")
    ? `insert into ${a} select v_row.* returning * into v_row;`
    : `insert into ${a} (${written.join(", ")}) select ${written.map((c) => `v_row.${c}`).join(", ")} returning * into v_row;`;

  const column = (c: string, definition: (name: string) => string): string =>
    has(c) ? `\n  ${ca(c)} ${definition(ca(c))},` : "";

  const defaults = (
    [
      ["id", "gen_random_uuid()"],
      ["body", "''"],
      ["severity", "'info'"],
      ["audience", "'all'"],
      ["targets", "'{}'::text[]"],
      ["startsAt", "now()"],
      ["dismissible", "true"],
      ["createdBy", "auth.uid()"],
      ["createdAt", "now()"],
    ] as const
  )
    .filter(([c]) => has(c))
    .map(([c, value]) => `${raw(c)}, ${value}`)
    .join(",\n      ");

  const fixed = ["id", "createdBy", "createdAt"]
    .filter(has)
    .map((c) => ` - ${raw(c)}`)
    .join("");

  const touch = has("updatedAt")
    ? `\n    v_row.${ca("updatedAt")} := now();`
    : "";

  const manage = ctx.permission("manage", OPERATIONS["announcements.manage"]);
  const staff = ctx.staff(manage);

  const announcementEvent = (type: string, id: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('announcementId', ${id})`,
      subject: `'announcements/' || ${id}::text`,
      audit: {
        category: "configuration",
        targetType: "announcement",
        recordId: `${id}::text`,
      },
    });

  const plans = ctx.entitlements("v_tenant");
  const audiences = ["all", "tenant", "role", ...(plans ? ["plan"] : [])];
  const topic = ctx.text("topic", "announcements");

  if (!TOPIC.test(topic)) {
    throw new TypeError(
      "blocks.announcements.options.topic: use letters, digits, '_', '.', ':' or '-'",
    );
  }

  const event = ctx.text("event", "announcement_changed");
  const receive = ctx.trigger("announcements_receive");
  const trigger = ctx.trigger("announcements_broadcast");

  const planMatch = plans
    ? `when 'plan' then v_tenant is not null and x.${ca("targets")} && ${plans}`
    : "";

  return `${schemaPreamble(ctx)}
-- Announcements staff publish to everyone, to tenants, to members with a
-- role, or (with entitlements) to tenants on a plan, between starts_at and
-- ends_at. targets holds the tenant ids, roles or plan lookup keys.
create table if not exists ${a} (
  ${ca("id")} uuid primary key default gen_random_uuid(),
  ${ca("title")} text not null check (length(${ca("title")}) between 1 and 200),${column("body", (body) => `text not null default '' check (length(${body}) <= 10000)`)}
  ${ca("severity")} text not null default 'info' check (${ca("severity")} in ('info', 'success', 'warning', 'critical')),${column("href", (href) => `text check (${href} ~ '^(https://|/)')`)}
  ${ca("audience")} text not null default 'all',
  ${ca("targets")} text[] not null default '{}',
  ${ca("startsAt")} timestamptz not null default now(),
  ${ca("endsAt")} timestamptz,
  ${ca("dismissible")} boolean not null default true,${column("createdBy", () => "uuid references auth.users (id) on delete set null default auth.uid()")}${column("createdAt", () => "timestamptz not null default now()")}${column("updatedAt", () => "timestamptz not null default now()")}
  check (${ca("endsAt")} is null or ${ca("endsAt")} > ${ca("startsAt")}),
  check ((${ca("audience")} = 'all') = (cardinality(${ca("targets")}) = 0))
);
-- The plan audience depends on the entitlements module, so a re-run replaces
-- the check.
alter table ${a} drop constraint if exists bsb_announcements_audience;
alter table ${a} add constraint bsb_announcements_audience check (${ca("audience")} in (${audiences.map(sqlString).join(", ")}));
create index if not exists ${ctx.naming.rename("announcements_window_idx")} on ${a} (${ca("startsAt")}, ${ca("endsAt")});${has("createdBy") ? `\ncreate index if not exists ${ctx.naming.rename("announcements_created_by_idx")} on ${a} (${ca("createdBy")});` : ""}${addExtraColumns(a, extras)}
${lockTable(a)}

create table if not exists ${d} (
  ${cd("announcement")} uuid not null references ${a} (${ca("id")}) on delete cascade,
  ${cd("user")} uuid not null references auth.users (id) on delete cascade,${ctx.has("dismissals", "dismissedAt") ? `\n  ${cd("dismissedAt")} timestamptz not null default now(),` : ""}
  primary key (${cd("announcement")}, ${cd("user")})
);
create index if not exists ${ctx.naming.rename("announcement_dismissals_user_idx")} on ${d} (${cd("user")});${
    ctx.owns("dismissals")
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("dismissals").name}_key`)} on ${d} (${cd("announcement")}, ${cd("user")});`
  }
${lockTable(d)}

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
    v_role := ${ctx.of("memberships").fn("organization_member_role")}(v_tenant, v_user);
    if v_role is null and not ${SERVICE_CALLER} then
      v_tenant := null;
    end if;
  end if;
  return (
    select coalesce(jsonb_agg(${withExtraFields(`to_jsonb(x) - ${raw("targets")}`, "x", extras)} order by x.${ca("startsAt")} desc), '[]'::jsonb)
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
    ${fail("ANNOUNCEMENT_FORBIDDEN", "Sign in first")}
  end if;
  select x.${ca("dismissible")} into v_dismissible from ${a} x where x.${ca("id")} = dismiss_announcement.id;
  if v_dismissible is null then
    ${raise("No announcement %", "P0002", "ANNOUNCEMENT_NOT_FOUND", "dismiss_announcement.id")}
  end if;
  if not v_dismissible then
    ${fail("ANNOUNCEMENT_NOT_DISMISSIBLE", "This announcement can't be dismissed", "22023")}
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
    ${fail("ANNOUNCEMENT_FORBIDDEN", "You may not manage announcements")}
  end if;
  return (
    select coalesce(jsonb_agg(${withExtraFields("to_jsonb(x)", "x", extras)} order by x.${ca("startsAt")} desc), '[]'::jsonb)
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
    ${fail("ANNOUNCEMENT_FORBIDDEN", "You may not manage announcements")}
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::${a}, jsonb_build_object(
      ${defaults}
    ) || save_announcement.fields);${touch}
    ${insertRow}
  else
    select * into v_row from ${a} x where x.${ca("id")} = save_announcement.id for update;
    if v_row.${ca("id")} is null then
      ${raise("No announcement %", "P0002", "ANNOUNCEMENT_NOT_FOUND", "save_announcement.id")}
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields${fixed});${touch}
    update ${a} x set (${editable.join(", ")}) = (${editable.map((c) => `v_row.${c}`).join(", ")})
    where x.${ca("id")} = v_row.${ca("id")}
    returning * into v_row;
  end if;
  ${announcementEvent("announcement.saved", `v_row.${ca("id")}`)}
  return ${withExtraFields("to_jsonb(v_row)", "v_row", extras)};
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
    ${fail("ANNOUNCEMENT_FORBIDDEN", "You may not manage announcements")}
  end if;
  delete from ${a} x where x.${ca("id")} = delete_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    ${announcementEvent("announcement.deleted", "delete_announcement.id")}
  end if;
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
        ${renderPolicy(makePolicy({ table: "realtime.messages", name: receive, command: "select", roles: ["authenticated"], using: `realtime.messages.extension = 'broadcast' and (select realtime.topic()) = ${sqlString(topic)}` }), { drop: true, target: "realtime.messages" })}
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

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "active_announcements", args: ["{id}"], returns: "jsonb" },
    { name: "dismiss_announcement", args: ["uuid"], returns: "boolean" },
    { name: "list_announcements", args: [], returns: "jsonb" },
    { name: "save_announcement", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "delete_announcement", args: ["uuid"], returns: "boolean" },
  ];
}

export const ANNOUNCEMENTS: BlockSqlDefinition = {
  name: "announcements",
  scopes: ["tenant"],
  title: "Announcements",
  description:
    "In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.",
  requires: ["memberships", "permissions"],
  integrates: ["entitlements"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
  topics: (ctx) => [ctx.text("topic", "announcements")],
};
