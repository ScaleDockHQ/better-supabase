import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import {
  canIn,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

/** The layouts a saved view can open in. */
export const SAVED_VIEW_KINDS = [
  "table",
  "board",
  "calendar",
  "timeline",
  "gantt",
] as const;

/** Who sees a saved view: its owner, a team, or the whole tenant. */
export const SAVED_VIEW_SCOPES = ["user", "team", "tenant"] as const;

const MAX_STATE_BYTES = 65_536;

const EVENTS: ModuleEvents = {
  "saved_view.saved": {
    subject: "saved-views",
    payload: ["organizationId", "id", "kind", "name"],
  },
  "saved_view.deleted": {
    subject: "saved-views",
    payload: ["organizationId", "id"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_view_save", "after_view_save"],
  tables: {
    views: {
      name: "saved_views",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        list: "list",
        scope: "scope",
        owner: "owner_id",
        team: "team_id",
        name: "name",
        kind: "kind",
        state: "state",
        rank: "rank",
        isDefault: "is_default",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

const textList = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const views = ctx.table("views");
  const c = (column: string): string => ctx.col("views", column);
  const [id, tenant, list, scope, owner, team, name, kind, state, rank] = [
    c("id"),
    c("tenant"),
    c("list"),
    c("scope"),
    c("owner"),
    c("team"),
    c("name"),
    c("kind"),
    c("state"),
    c("rank"),
  ];
  const isDefault = c("isDefault");
  const createdAt = c("createdAt");
  const updatedAt = c("updatedAt");
  const read = ctx.permission("read", MODULE_PERMISSIONS["saved-views"].read);
  const share = ctx.permission(
    "share",
    MODULE_PERMISSIONS["saved-views"].share,
  );
  const teams = ctx.installed("teams")
    ? `select t::text from ${ctx.of("teams").fn("team_ids_of")}(auth.uid()) t`
    : "";
  const inTeam = (value: string): string =>
    teams === "" ? "false" : `${value} in (${teams})`;
  const slot = `coalesce(case ${scope} when 'user' then ${owner}::text when 'team' then ${team} end, '')`;
  const tables = ctx.manages
    ? `create table if not exists ${views} (
  ${id} uuid primary key default gen_random_uuid(),
  ${tenant} ${ctx.idType} not null,
  ${list} text not null check (length(${list}) between 1 and 80),
  ${scope} text not null default 'user' check (${scope} in (${textList(SAVED_VIEW_SCOPES)})),
  ${owner} uuid references auth.users (id) on delete cascade,
  ${team} text,
  ${name} text not null check (length(${name}) between 1 and 120),
  ${kind} text not null default 'table' check (${kind} in (${textList(SAVED_VIEW_KINDS)})),
  ${state} jsonb not null default '{}'::jsonb check (jsonb_typeof(${state}) = 'object' and pg_column_size(${state}) <= ${String(MAX_STATE_BYTES)}),
  ${rank} text collate "C" not null default 'V',
  ${isDefault} boolean not null default false,
  ${createdAt} timestamptz not null default now(),
  ${updatedAt} timestamptz not null default now(),
  check (${scope} <> 'user' or ${owner} is not null),
  check (${scope} <> 'team' or ${team} is not null)
);
create index if not exists saved_views_list_idx on ${views} (${tenant}, ${list});
create unique index if not exists saved_views_default_idx on ${views} (${tenant}, ${list}, ${scope}, (${slot})) where ${isDefault};
${lockTable(views, { read: true })}
`
    : "";
  const fn = (value: string): string => ctx.fn(value);
  // A user sees their own views, their teams' views and the tenant's views.
  const visible = `${tenant} in (select better_supabase.tenant_ids_with(${read}))
  and (
    (${scope} = 'user' and ${owner} = (select auth.uid()))
    or (${scope} = 'team' and ${inTeam(team)})
    or ${scope} = 'tenant'
  )`;
  const mayEdit = (alias: string): string =>
    `(auth.role() = 'service_role'
    or (${alias}.${scope} = 'user' and ${alias}.${owner} = auth.uid())
    or (${alias}.${scope} <> 'user' and ${canIn(`${alias}.${tenant}`, share)}))`;
  return `${schemaPreamble(ctx)}
${tables}
drop policy if exists saved_views_read on ${views};
create policy saved_views_read on ${views} for select to authenticated
using (${visible});

create or replace function ${fn("save_view")}(tenant ${ctx.idType}, list text, name text, kind text, scope text, team text, state jsonb, view_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_view.view_id;
  v_row ${views};
  v_last text;
  v_rank text;
  v_service boolean := auth.role() = 'service_role';
begin
  if save_view.scope is null or save_view.scope not in (${textList(SAVED_VIEW_SCOPES)}) then
    ${fail("SAVED_VIEW_INVALID", "scope must be user, team or tenant", "22023")}
  end if;
  if save_view.kind is null or save_view.kind not in (${textList(SAVED_VIEW_KINDS)}) then
    ${fail("SAVED_VIEW_INVALID", "unknown view kind", "22023")}
  end if;
  if save_view.state is null or jsonb_typeof(save_view.state) <> 'object' then
    ${fail("SAVED_VIEW_INVALID", "state must be an object", "22023")}
  end if;
  if not (v_service or ${canIn("save_view.tenant", read)}) then
    ${fail("SAVED_VIEW_FORBIDDEN", "not allowed to save views")}
  end if;
  if save_view.scope = 'user' and auth.uid() is null then
    ${fail("SAVED_VIEW_INVALID", "a personal view needs a signed-in user", "22023")}
  end if;
  if save_view.scope <> 'user' and not (v_service or ${canIn("save_view.tenant", share)}) then
    ${fail("SAVED_VIEW_FORBIDDEN", "not allowed to share views")}
  end if;
  if save_view.scope = 'team' then
    if save_view.team is null then
      ${fail("SAVED_VIEW_INVALID", "a team view needs a team", "22023")}
    end if;
    if not (v_service or ${inTeam("save_view.team")}) then
      ${fail("SAVED_VIEW_FORBIDDEN", "not a member of this team")}
    end if;
  end if;
  if v_id is not null then
    select * into v_row from ${views} where ${id} = v_id and ${tenant} = save_view.tenant for update;
    if not found then
      ${fail("SAVED_VIEW_NOT_FOUND", "saved view not found", "P0002")}
    end if;
    if not ${mayEdit("v_row")} then
      ${fail("SAVED_VIEW_FORBIDDEN", "not allowed to change this view")}
    end if;
  end if;
  ${ctx.hook("before_view_save", [
    [ctx.idType, "save_view.tenant"],
    ["text", "save_view.list"],
    ["text", "save_view.scope"],
    ["jsonb", "save_view.state"],
  ])}
  if v_id is null then
    select max(v.${rank} collate "C") into v_last from ${views} v
      where v.${tenant} = save_view.tenant and v.${list} = save_view.list;
    v_rank := ${rankAfter("v_last")};
    insert into ${views} (${tenant}, ${list}, ${scope}, ${owner}, ${team}, ${name}, ${kind}, ${state}, ${rank})
    values (save_view.tenant, save_view.list, save_view.scope, auth.uid(),
      case when save_view.scope = 'team' then save_view.team end,
      save_view.name, save_view.kind, save_view.state, v_rank)
    returning ${id} into v_id;
  else
    update ${views} set
      ${list} = save_view.list,
      ${scope} = save_view.scope,
      ${team} = case when save_view.scope = 'team' then save_view.team end,
      ${owner} = coalesce(${owner}, auth.uid()),
      ${name} = save_view.name,
      ${kind} = save_view.kind,
      ${state} = save_view.state,
      ${isDefault} = case when ${scope} = save_view.scope then ${isDefault} else false end,
      ${updatedAt} = now()
    where ${id} = v_id
    returning ${rank} into v_rank;
  end if;
  ${ctx.record({
    type: "saved_view.saved",
    payload: `jsonb_build_object('organizationId', save_view.tenant, 'id', v_id, 'kind', save_view.kind, 'name', save_view.name)`,
    subject: `'saved-views/' || v_id::text`,
    tenant: "save_view.tenant",
    audit: false,
  })}
  ${ctx.hook("after_view_save", [["uuid", "v_id"]])}
  return jsonb_build_object('id', v_id, 'rank', v_rank);
end;
$$;
${userGrant(`${fn("save_view")}(${ctx.idType}, text, text, text, text, text, jsonb, uuid)`)}

create or replace function ${fn("list_views")}(tenant ${ctx.idType}, list text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', v.${id},
    'list', v.${list},
    'scope', v.${scope},
    'ownerId', v.${owner},
    'teamId', v.${team},
    'name', v.${name},
    'kind', v.${kind},
    'state', v.${state},
    'rank', v.${rank},
    'isDefault', v.${isDefault},
    'updatedAt', v.${updatedAt}
  ) order by v.${rank} collate "C", v.${id}), '[]'::jsonb)
  from ${views} v
  where v.${tenant} = list_views.tenant and v.${list} = list_views.list
$$;
${userGrant(`${fn("list_views")}(${ctx.idType}, text)`)}

create or replace function ${fn("rank_view")}(view_id uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${views};
begin
  if rank_view.rank is null or rank_view.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("SAVED_VIEW_RANK_INVALID", "not a rank key", "22023")}
  end if;
  select * into v_row from ${views} where ${id} = rank_view.view_id;
  if not found then
    ${fail("SAVED_VIEW_NOT_FOUND", "saved view not found", "P0002")}
  end if;
  if not ${mayEdit("v_row")} then
    ${fail("SAVED_VIEW_FORBIDDEN", "not allowed to change this view")}
  end if;
  update ${views} set ${rank} = rank_view.rank, ${updatedAt} = now() where ${id} = rank_view.view_id;
  return true;
end;
$$;
${userGrant(`${fn("rank_view")}(uuid, text)`)}

-- One default per list and slot: a user's own, a team's, or the tenant's.
create or replace function ${fn("set_default_view")}(view_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${views};
begin
  select * into v_row from ${views} where ${id} = set_default_view.view_id for update;
  if not found then
    ${fail("SAVED_VIEW_NOT_FOUND", "saved view not found", "P0002")}
  end if;
  if not ${mayEdit("v_row")} then
    ${fail("SAVED_VIEW_FORBIDDEN", "not allowed to change this view")}
  end if;
  if set_default_view.on_default then
    update ${views} v set ${isDefault} = false
    where v.${tenant} = v_row.${tenant} and v.${list} = v_row.${list}
      and v.${scope} = v_row.${scope} and v.${isDefault} and v.${id} <> v_row.${id}
      and coalesce(case v.${scope} when 'user' then v.${owner}::text when 'team' then v.${team} end, '')
        = coalesce(case v_row.${scope} when 'user' then v_row.${owner}::text when 'team' then v_row.${team} end, '');
  end if;
  update ${views} set ${isDefault} = coalesce(set_default_view.on_default, false), ${updatedAt} = now()
  where ${id} = set_default_view.view_id;
  return true;
end;
$$;
${userGrant(`${fn("set_default_view")}(uuid, boolean)`)}

create or replace function ${fn("delete_view")}(view_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${views};
begin
  select * into v_row from ${views} where ${id} = delete_view.view_id;
  if not found then
    ${fail("SAVED_VIEW_NOT_FOUND", "saved view not found", "P0002")}
  end if;
  if not ${mayEdit("v_row")} then
    ${fail("SAVED_VIEW_FORBIDDEN", "not allowed to change this view")}
  end if;
  delete from ${views} where ${id} = delete_view.view_id;
  ${ctx.record({
    type: "saved_view.deleted",
    payload: `jsonb_build_object('organizationId', v_row.${tenant}, 'id', delete_view.view_id)`,
    subject: `'saved-views/' || delete_view.view_id::text`,
    tenant: `v_row.${tenant}`,
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("delete_view")}(uuid)`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "save_view",
      args: ["{id}", "text", "text", "text", "text", "text", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "list_views", args: ["{id}", "text"], returns: "jsonb" },
    { name: "rank_view", args: ["uuid", "text"], returns: "boolean" },
    { name: "set_default_view", args: ["uuid", "boolean"], returns: "boolean" },
    { name: "delete_view", args: ["uuid"], returns: "boolean" },
  ];
}

export const SAVED_VIEWS: ModuleDefinition = {
  name: "saved-views",
  title: "Saved views",
  description:
    "Named, ranked list states (filters, sort, columns, grouping, density) for one user, a team or the whole tenant.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "teams"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
