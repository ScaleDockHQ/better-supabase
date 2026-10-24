-- ==== schema supabase/schemas/900_better_supabase_67_saved_views.sql
-- better-supabase module: saved-views
-- @bsb-block saved-views@2 managed
-- Named, ranked list states (filters, sort, columns, grouping, density) for one user, a team or the whole tenant.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."saved_views" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "list" text not null check (length("list") between 1 and 80),
  "scope" text not null default 'user' check ("scope" in ('user', 'team', 'tenant')),
  "owner_id" uuid references auth.users (id) on delete cascade,
  "team_id" text,
  "name" text not null check (length("name") between 1 and 120),
  "kind" text not null default 'table' check ("kind" in ('table', 'board', 'calendar', 'timeline', 'gantt')),
  "state" jsonb not null default '{}'::jsonb check (jsonb_typeof("state") = 'object' and pg_column_size("state") <= 65536),
  "rank" text collate "C" not null default 'V',
  "is_default" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("scope" <> 'user' or "owner_id" is not null),
  check ("scope" <> 'team' or "team_id" is not null)
);
create index if not exists "saved_views_list_idx" on "better_supabase"."saved_views" ("tenant_id", "list");
create index if not exists "saved_views_owner_idx" on "better_supabase"."saved_views" ("owner_id") where "owner_id" is not null;
create unique index if not exists "saved_views_default_idx" on "better_supabase"."saved_views" ("tenant_id", "list", "scope", (coalesce(case "scope" when 'user' then "owner_id"::text when 'team' then "team_id" end, ''))) where "is_default";
alter table "better_supabase"."saved_views" enable row level security;
revoke all on "better_supabase"."saved_views" from anon, authenticated;
grant select on "better_supabase"."saved_views" to authenticated;
grant all on "better_supabase"."saved_views" to service_role;

drop policy if exists saved_views_read on "better_supabase"."saved_views";
create policy saved_views_read on "better_supabase"."saved_views" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('views.read'))
  and (
    ("scope" = 'user' and "owner_id" = (select auth.uid()))
    or ("scope" = 'team' and false)
    or "scope" = 'tenant'
  ));
create table if not exists "better_supabase"."saved_view_preferences" (
  "view_id" uuid not null references "better_supabase"."saved_views" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "is_default" boolean not null default false,
  "hidden" boolean not null default false,
  "pinned" boolean not null default false,
  "updated_at" timestamptz not null default now(),
  primary key ("view_id", "user_id")
);
create index if not exists "saved_view_preferences_user_idx" on "better_supabase"."saved_view_preferences" ("user_id", "tenant_id");
alter table "better_supabase"."saved_view_preferences" enable row level security;
revoke all on "better_supabase"."saved_view_preferences" from anon, authenticated;
grant select on "better_supabase"."saved_view_preferences" to authenticated;
grant all on "better_supabase"."saved_view_preferences" to service_role;
drop policy if exists saved_view_preferences_read on "better_supabase"."saved_view_preferences";
create policy saved_view_preferences_read on "better_supabase"."saved_view_preferences" for select to authenticated
using ("user_id" = (select auth.uid()));


drop function if exists "better_supabase"."save_view"(uuid, text, text, text, text, text, jsonb, uuid, jsonb);
create or replace function "better_supabase"."save_view"(tenant uuid, list text, name text, kind text, scope text, team text, state jsonb, view_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := save_view.view_id;
  v_row "better_supabase"."saved_views";
  v_last text;
  v_rank text;
  v_service boolean := auth.role() = 'service_role';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_view.scope is null or save_view.scope not in ('user', 'team', 'tenant') then
    raise exception 'scope must be user, team or tenant' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.kind is null or save_view.kind not in ('table', 'board', 'calendar', 'timeline', 'gantt') then
    raise exception 'unknown view kind' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.state is null or jsonb_typeof(save_view.state) <> 'object' then
    raise exception 'state must be an object' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'views.read'), false)) then
    raise exception 'not allowed to save views' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  if save_view.scope = 'user' and auth.uid() is null then
    raise exception 'a personal view needs a signed-in user' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'views.share'), false)) then
    raise exception 'not allowed to share views' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  if save_view.scope = 'team' then
    if save_view.team is null then
      raise exception 'a team view needs a team' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
    end if;
    if not (v_service or false) then
      raise exception 'not a member of this team' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
    end if;
  end if;
  if v_id is not null then
    select * into v_row from "better_supabase"."saved_views" where "id" = v_id and "tenant_id" = save_view.tenant for update;
    if not found then
      raise exception 'saved view not found' using errcode = 'P0002', hint = 'SAVED_VIEW_NOT_FOUND';
    end if;
    if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'views.share'), false))) then
      raise exception 'not allowed to change this view' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_view_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_view.tenant, save_view.list, save_view.scope, save_view.state;
    end if;
  end;
  if v_id is null then
    select max(v."rank" collate "C") into v_last from "better_supabase"."saved_views" v
      where v."tenant_id" = save_view.tenant and v."list" = save_view.list;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."saved_views" ("tenant_id", "list", "scope", "owner_id", "team_id", "name", "kind", "state", "rank")
    values (save_view.tenant, save_view.list, save_view.scope, auth.uid(),
      case when save_view.scope = 'team' then save_view.team end,
      save_view.name, save_view.kind, save_view.state, v_rank)
    returning "id" into v_id;
  else
    update "better_supabase"."saved_views" set
      "list" = save_view.list,
      "scope" = save_view.scope,
      "team_id" = case when save_view.scope = 'team' then save_view.team end,
      "owner_id" = coalesce("owner_id", auth.uid()),
      "name" = save_view.name,
      "kind" = save_view.kind,
      "state" = save_view.state,
      -- The default is per list, scope and team; moving the view drops it.
      "is_default" = case
        when "scope" = save_view.scope and "list" = save_view.list
          and "team_id" is not distinct from case when save_view.scope = 'team' then save_view.team end
        then "is_default" else false end,
      "updated_at" = now()
    where "id" = v_id
    returning "rank" into v_rank;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_view_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."save_view"(uuid, text, text, text, text, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_view"(uuid, text, text, text, text, text, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_views"(tenant uuid, list text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', v."id",
    'list', v."list",
    'scope', v."scope",
    'ownerId', v."owner_id",
    'teamId', v."team_id",
    'name', v."name",
    'kind', v."kind",
    'state', v."state",
    'rank', v."rank",
    'isDefault', v."is_default",
    'updatedAt', v."updated_at",
    'preference', jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false))
  ) order by v."rank" collate "C", v."id"), '[]'::jsonb)
  from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())
  where v."tenant_id" = list_views.tenant and v."list" = list_views.list
$$;
revoke execute on function "better_supabase"."list_views"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_views"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."rank_view"(view_id uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."saved_views";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_view.rank is null or rank_view.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'SAVED_VIEW_RANK_INVALID';
  end if;
  select * into v_row from "better_supabase"."saved_views" where "id" = rank_view.view_id;
  if not found then
    raise exception 'saved view not found' using errcode = 'P0002', hint = 'SAVED_VIEW_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'views.share'), false))) then
    raise exception 'not allowed to change this view' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  update "better_supabase"."saved_views" set "rank" = rank_view.rank, "updated_at" = now() where "id" = rank_view.view_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_view"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_view"(uuid, text) to authenticated, service_role;

-- One default per list and slot: a user's own, a team's, or the tenant's.
create or replace function "better_supabase"."set_default_view"(view_id uuid, on_default boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."saved_views";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."saved_views" where "id" = set_default_view.view_id for update;
  if not found then
    raise exception 'saved view not found' using errcode = 'P0002', hint = 'SAVED_VIEW_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'views.share'), false))) then
    raise exception 'not allowed to change this view' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  if set_default_view.on_default then
    update "better_supabase"."saved_views" v set "is_default" = false
    where v."tenant_id" = v_row."tenant_id" and v."list" = v_row."list"
      and v."scope" = v_row."scope" and v."is_default" and v."id" <> v_row."id"
      and coalesce(case v."scope" when 'user' then v."owner_id"::text when 'team' then v."team_id" end, '')
        = coalesce(case v_row."scope" when 'user' then v_row."owner_id"::text when 'team' then v_row."team_id" end, '');
  end if;
  update "better_supabase"."saved_views" set "is_default" = coalesce(set_default_view.on_default, false), "updated_at" = now()
  where "id" = set_default_view.view_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_default_view"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_default_view"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."delete_view"(view_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."saved_views";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."saved_views" where "id" = delete_view.view_id;
  if not found then
    raise exception 'saved view not found' using errcode = 'P0002', hint = 'SAVED_VIEW_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'views.share'), false))) then
    raise exception 'not allowed to change this view' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  delete from "better_supabase"."saved_views" where "id" = delete_view.view_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_view"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_view"(uuid) to authenticated, service_role;

-- A copy of a view the caller sees, saved through save_view, so the copy
-- needs the same rights as a new view of that scope.
create or replace function "better_supabase"."duplicate_view"(view_id uuid, scope text, name text, team text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."saved_views";
begin
  select * into v_row from "better_supabase"."saved_views" where "id" = duplicate_view.view_id;
  if not found or not (auth.role() = 'service_role'
    or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'views.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'saved view not found' using errcode = 'P0002', hint = 'SAVED_VIEW_NOT_FOUND';
  end if;
  return "better_supabase"."save_view"(v_row."tenant_id", v_row."list",
    coalesce(duplicate_view.name, v_row."name"), v_row."kind",
    coalesce(duplicate_view.scope, 'user'), duplicate_view.team, v_row."state", null);
end;
$$;
revoke execute on function "better_supabase"."duplicate_view"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."duplicate_view"(uuid, text, text, text) to authenticated, service_role;

-- The caller's own default, hidden and pinned flags for a view they see, so
-- a member can open a shared view by default without the right to change it.
-- A null argument keeps the current value; one default per user and list.
create or replace function "better_supabase"."set_view_preference"(view_id uuid, make_default boolean, hide boolean, pin boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_row "better_supabase"."saved_views";
  v_pref "better_supabase"."saved_view_preferences";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'a preference needs a signed-in user' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select * into v_row from "better_supabase"."saved_views" where "id" = set_view_preference.view_id;
  if not found or not (auth.role() = 'service_role'
    or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'views.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'saved view not found' using errcode = 'P0002', hint = 'SAVED_VIEW_NOT_FOUND';
  end if;
  if set_view_preference.make_default then
    update "better_supabase"."saved_view_preferences" p set "is_default" = false, "updated_at" = now()
    from "better_supabase"."saved_views" o
    where p."user_id" = v_user and p."is_default" and p."view_id" <> v_row."id"
      and o."id" = p."view_id"
      and o."tenant_id" = v_row."tenant_id" and o."list" = v_row."list";
  end if;
  insert into "better_supabase"."saved_view_preferences" as p ("view_id", "user_id", "tenant_id", "is_default", "hidden", "pinned")
  values (v_row."id", v_user, v_row."tenant_id",
    coalesce(set_view_preference.make_default, false),
    coalesce(set_view_preference.hide, false),
    coalesce(set_view_preference.pin, false))
  on conflict ("view_id", "user_id") do update set
    "is_default" = coalesce(set_view_preference.make_default, p."is_default"),
    "hidden" = coalesce(set_view_preference.hide, p."hidden"),
    "pinned" = coalesce(set_view_preference.pin, p."pinned"),
    "updated_at" = now()
  returning * into v_pref;
  return jsonb_build_object('viewId', v_pref."view_id") || jsonb_build_object('isDefault', coalesce(v_pref."is_default", false), 'hidden', coalesce(v_pref."hidden", false), 'pinned', coalesce(v_pref."pinned", false));
end;
$$;
revoke execute on function "better_supabase"."set_view_preference"(uuid, boolean, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."set_view_preference"(uuid, boolean, boolean, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."saved_views";
create policy bsb_tenant_scope on "better_supabase"."saved_views" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('views.read'))
  and (
    ("scope" = 'user' and "owner_id" = (select auth.uid()))
    or ("scope" = 'team' and false)
    or "scope" = 'tenant'
  ))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."saved_view_preferences";
create policy bsb_tenant_scope on "better_supabase"."saved_view_preferences" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("user_id" = (select auth.uid()))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_67_saved_views.sql
-- better-supabase module: saved-views
-- @bsb-block-data saved-views
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('saved-views', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
