-- ==== schema supabase/schemas/900_better_supabase_067_saved_views.sql
-- better-supabase module: saved-views
-- @bsb-block saved-views@2 managed
-- @bsb-hash sha256:89e7db4da106c9ebb2615ffd0a354cc13dacf3d3e8ae27b56495bc50c88dcf4a
-- Named, ranked list states (filters, sort, columns, grouping, density) for one user, a team or the whole tenant.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."saved_views" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "list" text not null constraint bsb_saved_views_list_check check (length("list") >= 1 and length("list") <= 80),
  "scope" text not null default 'user' constraint bsb_saved_views_scope_check check ("scope" in ('user', 'team', 'tenant')),
  "owner_id" uuid references auth.users (id) on delete cascade,
  "team_id" text,
  "name" text not null constraint bsb_saved_views_name_check check (length("name") >= 1 and length("name") <= 120),
  "kind" text not null default 'table' constraint bsb_saved_views_kind_check check ("kind" in ('table', 'board', 'calendar', 'timeline', 'gantt')),
  "state" jsonb not null default '{}'::jsonb constraint bsb_saved_views_state_check check (jsonb_typeof("state") = 'object' and pg_column_size("state") <= 65536),
  "rank" text collate "C" not null default 'V',
  "is_default" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_saved_views_check check ("scope" <> 'user' or "owner_id" is not null),
  constraint bsb_saved_views_check1 check ("scope" <> 'team' or "team_id" is not null)
);
create index "saved_views_list_idx" on "better_supabase"."saved_views" ("tenant_id", "list");
create index "saved_views_owner_idx" on "better_supabase"."saved_views" ("owner_id") where "owner_id" is not null;
create unique index "saved_views_default_idx" on "better_supabase"."saved_views" ("tenant_id", "list", "scope", (coalesce(case "scope" when 'user' then "owner_id"::text when 'team' then "team_id" end, ''))) where "is_default";
alter table "better_supabase"."saved_views" enable row level security;
revoke all on "better_supabase"."saved_views" from public, anon, authenticated;
grant select on "better_supabase"."saved_views" to authenticated;
grant all on "better_supabase"."saved_views" to service_role;

create policy bsb_saved_views_read on "better_supabase"."saved_views"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('saved_views.read'))
  and (
    ("scope" = 'user' and "owner_id" = (select auth.uid()))
    or ("scope" = 'team' and false)
    or "scope" = 'tenant'
  ));
create table "better_supabase"."saved_view_preferences" (
  "view_id" uuid not null references "better_supabase"."saved_views" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "is_default" boolean not null default false,
  "hidden" boolean not null default false,
  "pinned" boolean not null default false,
  "updated_at" timestamptz not null default now(),
  primary key ("view_id", "user_id")
);
create index "saved_view_preferences_user_idx" on "better_supabase"."saved_view_preferences" ("user_id", "tenant_id");
alter table "better_supabase"."saved_view_preferences" enable row level security;
revoke all on "better_supabase"."saved_view_preferences" from public, anon, authenticated;
grant select on "better_supabase"."saved_view_preferences" to authenticated;
grant all on "better_supabase"."saved_view_preferences" to service_role;
create policy bsb_saved_view_preferences_read on "better_supabase"."saved_view_preferences"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
create or replace function "better_supabase"."save_view"(tenant uuid, list text, name text, kind text, scope text, team text, state jsonb, view_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := save_view.view_id;
  v_inserted boolean := save_view.view_id is null;
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
  if not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'saved_views.read'), false)) then
    raise exception 'not allowed to save views' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  if save_view.scope = 'user' and auth.uid() is null then
    raise exception 'a personal view needs a signed-in user' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'saved_views.share'), false)) then
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
    or (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'saved_views.share'), false))) then
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
  if v_inserted then
    null;
  else
    null;
  end if;
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

-- The views the caller sees as a keyset page, in rank order (ADR 1077). It
-- runs as invoker, so the read policy decides which views are visible.
-- filters is { list, scope, kind (each a value or a list), search (name),
-- sort (rank, name, updatedAt), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "better_supabase"."page_saved_views"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_saved_views.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('scope', 'kind') then
      raise exception 'facet is one of scope, kind' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
    end if;
    with s as (
      select (case v_facet when 'scope' then (x."scope")::text when 'kind' then (x."kind")::text end) as v
      from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'updatedAt') then
    raise exception 'sort is one of rank, name, updatedAt' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."rank" collate "C", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."rank" collate "C" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."rank" collate "C" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."rank" collate "C", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."rank" collate "C" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."rank" collate "C")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."rank" collate "C" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  ) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
      where x."tenant_id" = page_saved_views.tenant
        and (not (v_filters -> 'list' is not null and jsonb_typeof(v_filters -> 'list') <> 'null' and not (jsonb_typeof(v_filters -> 'list') = 'array' and jsonb_array_length(v_filters -> 'list') = 0)) or x."list" = any((case when jsonb_typeof(v_filters -> 'list') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'list')) else array[v_filters ->> 'list'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_saved_views"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_saved_views"(uuid, jsonb) to authenticated, service_role;

-- One view the caller sees, or null. It runs as invoker.
create or replace function "better_supabase"."get_view"(view_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'list', x."list",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'kind', x."kind",
    'state', x."state",
    'rank', x."rank",
    'isDefault', x."is_default",
    'updatedAt', x."updated_at",
    'preference', x.bsb_preference
  )
  from (select v.*, jsonb_build_object('isDefault', coalesce(p."is_default", false), 'hidden', coalesce(p."hidden", false), 'pinned', coalesce(p."pinned", false)) as bsb_preference from "better_supabase"."saved_views" v
  left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())) x
  where x."id" = get_view.view_id
$$;
revoke execute on function "better_supabase"."get_view"(uuid) from public, anon;
grant execute on function "better_supabase"."get_view"(uuid) to authenticated, service_role;

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
    or (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'saved_views.share'), false))) then
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
    or (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'saved_views.share'), false))) then
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
    or (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'saved_views.share'), false))) then
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
    or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'saved_views.read'), false) and (
      (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false))
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
    or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'saved_views.read'), false) and (
      (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false))
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."saved_views" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('saved_views.read'))
  and (
    ("scope" = 'user' and "owner_id" = (select auth.uid()))
    or ("scope" = 'team' and false)
    or "scope" = 'tenant'
  ))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."saved_views" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."saved_views" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."saved_views" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."saved_view_preferences" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("user_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."saved_view_preferences" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."saved_view_preferences" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."saved_view_preferences" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_067_saved_views.sql
-- better-supabase module: saved-views
-- @bsb-block-data saved-views
-- @bsb-hash sha256:c7b5642e8303e22583d102851c071a83d2a86b6f5ab0aca5d15da41af490dba2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('saved-views', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
