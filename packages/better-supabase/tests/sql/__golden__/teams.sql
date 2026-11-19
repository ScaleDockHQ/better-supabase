-- ==== alone: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:da8761fb2d836c9da421117f220b699110d0cdb349ec053298e16a3f1bd9af48
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table "better_supabase"."teams" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200),
  "slug" text not null constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug")
);
create unique index "bsb_teams_tenant_id_key" on "better_supabase"."teams" ("tenant_id", "id");
alter table "better_supabase"."teams" enable row level security;
revoke all on "better_supabase"."teams" from public, anon, authenticated;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
create policy bsb_teams_read on "better_supabase"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table "better_supabase"."team_members" (
  "team_id" uuid not null references "better_supabase"."teams" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
create index team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index team_members_membership_idx on "better_supabase"."team_members" ("tenant_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
revoke all on "better_supabase"."team_members" from public, anon, authenticated;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
create policy bsb_team_members_read on "better_supabase"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "better_supabase"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("tenant_id", "user_id")
  references "better_supabase"."memberships" ("organization_id", "user_id")
  on delete cascade;
alter table "better_supabase"."team_members"
  add constraint team_members_team_tenant_fkey
  foreign key ("tenant_id", "team_id")
  references "better_supabase"."teams" ("tenant_id", "id")
  on delete cascade;
create index team_members_tenant_team_idx on "better_supabase"."team_members" ("tenant_id", "team_id");


-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function "better_supabase"."team_ids_of"(member uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "better_supabase"."team_ids_of"(uuid) from public, anon;
grant execute on function "better_supabase"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_team"(tenant uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$$;
revoke execute on function "better_supabase"."create_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text) to authenticated, service_role;
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$$;
revoke execute on function "better_supabase"."update_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_team"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_team"(uuid) to authenticated, service_role;
create or replace function "better_supabase"."purge_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = purge_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_team"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_team"(uuid) to authenticated, service_role;

-- purge_team for each of team_ids in one call, all or nothing; returns how many
-- it purged.
create or replace function "better_supabase"."purge_teams"(team_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid;
  v_count integer := 0;
begin
  if coalesce(cardinality(purge_teams.team_ids), 0) > 1000 then
    raise exception 'purge at most 1000 teams in one call' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  for v_team in select distinct x from unnest(purge_teams.team_ids) x where x is not null loop
    perform "better_supabase"."purge_team"(v_team);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_teams"(uuid[]) from public, anon;
grant execute on function "better_supabase"."purge_teams"(uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."add_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  null;
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_team_member"(uuid, uuid) to authenticated, service_role;
-- Teams as a keyset page, by name unless sort says otherwise (ADR 1077).
-- filters may hold status (a value or a list), search, sort (name,
-- createdAt), direction, facet, count, limit and after. Without paged it
-- returns the plain array, at most 200.
create or replace function "better_supabase"."list_teams"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_teams.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TEAM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
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
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_teams"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_teams"(uuid, jsonb) to authenticated, service_role;

-- One team the caller may read, or null.
create or replace function "better_supabase"."get_team"(team uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  )
    into v_tenant, v_row
    from "better_supabase"."teams" x
    where x."id" = get_team.team;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."get_team"(uuid) from public, anon;
grant execute on function "better_supabase"."get_team"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."team_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:2121d2aef54edc01010b5e875af5569da78cbeb0f7e0915301ff4837f3f76c29
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table "better_supabase"."teams" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200),
  "slug" text not null constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug")
);
create unique index "bsb_teams_tenant_id_key" on "better_supabase"."teams" ("tenant_id", "id");
alter table "better_supabase"."teams" enable row level security;
revoke all on "better_supabase"."teams" from public, anon, authenticated;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
create policy bsb_teams_read on "better_supabase"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table "better_supabase"."team_members" (
  "team_id" uuid not null references "better_supabase"."teams" ("id") on delete cascade,
  "user_id" uuid references auth.users (id) on delete cascade,
  "employee_id" uuid,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  constraint bsb_team_members_check check ("user_id" is not null or "employee_id" is not null)
);
create unique index "bsb_team_members_user_key" on "better_supabase"."team_members" ("team_id", "user_id") where "user_id" is not null;
create unique index "bsb_team_members_employee_key" on "better_supabase"."team_members" ("team_id", "employee_id") where "employee_id" is not null;
create index team_members_employee_idx on "better_supabase"."team_members" ("employee_id") where "employee_id" is not null;
create index team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index team_members_membership_idx on "better_supabase"."team_members" ("tenant_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
revoke all on "better_supabase"."team_members" from public, anon, authenticated;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
create policy bsb_team_members_read on "better_supabase"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "better_supabase"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("tenant_id", "user_id")
  references "better_supabase"."memberships" ("organization_id", "user_id")
  on delete cascade;
alter table "better_supabase"."team_members"
  add constraint team_members_team_tenant_fkey
  foreign key ("tenant_id", "team_id")
  references "better_supabase"."teams" ("tenant_id", "id")
  on delete cascade;
create index team_members_tenant_team_idx on "better_supabase"."team_members" ("tenant_id", "team_id");

alter table "better_supabase"."inbox_conversations"
  add constraint conversations_team_fkey
  foreign key ("team_id") references "better_supabase"."teams" ("id") on delete set null;
-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function "better_supabase"."team_ids_of"(member uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "better_supabase"."team_ids_of"(uuid) from public, anon;
grant execute on function "better_supabase"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_team"(tenant uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  perform "better_supabase".emit_event('team.created', jsonb_build_object('organizationId', create_team.tenant, 'id', v_id, 'name', create_team.name), 'teams/' || (v_id)::text, (create_team.tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.created',
    category => 'membership',
    target_type => 'team',
    record_id => (v_id)::text,
    tenant => (create_team.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', create_team.tenant, 'id', v_id, 'name', create_team.name)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$$;
revoke execute on function "better_supabase"."create_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text) to authenticated, service_role;
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  perform "better_supabase".emit_event('team.updated', jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name), 'teams/' || (update_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.updated',
    category => 'membership',
    target_type => 'team',
    record_id => (update_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name)
  );
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$$;
revoke execute on function "better_supabase"."update_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  perform "better_supabase".emit_event('team.archived', jsonb_build_object('organizationId', v_tenant, 'id', archive_team.team), 'teams/' || (archive_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.archived',
    category => 'membership',
    target_type => 'team',
    record_id => (archive_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', archive_team.team)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_team"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_team"(uuid) to authenticated, service_role;
create or replace function "better_supabase"."purge_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = purge_team.team;
  perform "better_supabase".emit_event('team.purged', jsonb_build_object('organizationId', v_tenant, 'id', purge_team.team), 'teams/' || (purge_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.purged',
    category => 'membership',
    target_type => 'team',
    record_id => (purge_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', purge_team.team)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_team"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_team"(uuid) to authenticated, service_role;

-- purge_team for each of team_ids in one call, all or nothing; returns how many
-- it purged.
create or replace function "better_supabase"."purge_teams"(team_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid;
  v_count integer := 0;
begin
  if coalesce(cardinality(purge_teams.team_ids), 0) > 1000 then
    raise exception 'purge at most 1000 teams in one call' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  for v_team in select distinct x from unnest(purge_teams.team_ids) x where x is not null loop
    perform "better_supabase"."purge_team"(v_team);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_teams"(uuid[]) from public, anon;
grant execute on function "better_supabase"."purge_teams"(uuid[]) to authenticated, service_role;

-- A row whose employee stays (the team and the employee exist) keeps the
-- employee when its user loses the account or the tenant membership.
create or replace function better_supabase.bsb_team_member_employee_keep()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old."employee_id" is null or old."user_id" is null
    or not exists (select 1 from "better_supabase"."teams" t where t."id" = old."team_id")
    or not exists (select 1 from "better_supabase"."employees" x where x."id" = old."employee_id")
    or (exists (select 1 from auth.users u where u.id = old."user_id")
      and exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = old."tenant_id"
      and m."user_id" = old."user_id"
  )) then
    return old;
  end if;
  update "better_supabase"."team_members" set "user_id" = null
  where "team_id" = old."team_id" and "employee_id" = old."employee_id";
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_team_member_employee_keep() from public, anon, authenticated;
create trigger bsb_team_member_employee_keep before delete on "better_supabase"."team_members"
for each row execute function better_supabase.bsb_team_member_employee_keep();
-- member: a user id; employee: an employee id. Pass one of them.
create or replace function "better_supabase"."add_team_member"(team uuid, member uuid default null, employee uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_user uuid := add_team_member.member;
  v_employee uuid := add_team_member.employee;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if (add_team_member.member is null) = (add_team_member.employee is null) then
    raise exception 'pass either a user or an employee' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  if v_employee is null then
    if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = v_user
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
    v_employee := (
      select x."id" from "better_supabase"."employees" x
      where x."tenant_id" = v_tenant and x."user_id" = v_user
    );
  else
    select x."user_id" into v_user from "better_supabase"."employees" x
    where x."id" = v_employee and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'employee is not in the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
    end if;
    if v_user is not null and not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = v_user
  ) then
      v_user := null;
    end if;
  end if;
  if v_employee is not null and v_user is not null then
    delete from "better_supabase"."team_members" x
    where x."team_id" = add_team_member.team and x."user_id" = v_user and x."employee_id" is null
      and exists (
        select 1 from "better_supabase"."team_members" y
        where y."team_id" = add_team_member.team and y."employee_id" = v_employee
      );
    update "better_supabase"."team_members" set "user_id" = v_user
    where "team_id" = add_team_member.team and "employee_id" = v_employee and "user_id" is null;
    update "better_supabase"."team_members" set "employee_id" = v_employee
    where "team_id" = add_team_member.team and "user_id" = v_user and "employee_id" is null;
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "employee_id", "tenant_id")
  values (add_team_member.team, v_user, v_employee, v_tenant)
  on conflict do nothing;
  perform "better_supabase".emit_event('team_member.added', jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', v_user, 'employeeId', v_employee), 'teams/' || (add_team_member.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team_member.added',
    category => 'membership',
    target_type => 'team',
    record_id => (add_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', v_user, 'employeeId', v_employee)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."add_team_member"(uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."add_team_member"(uuid, uuid, uuid) to authenticated, service_role;
-- member: a user id; employee: an employee id. Pass one of them. Removing a
-- user whose row has an employee removes the employee too.
create or replace function "better_supabase"."remove_team_member"(team uuid, member uuid default null, employee uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_user uuid;
  v_employee uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if (remove_team_member.member is null) = (remove_team_member.employee is null) then
    raise exception 'pass either a user or an employee' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  delete from "better_supabase"."team_members" x
  where x."team_id" = remove_team_member.team
    and (x."employee_id" = remove_team_member.employee or x."user_id" = remove_team_member.member)
  returning x."user_id", x."employee_id" into v_user, v_employee;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('team_member.deleted', jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', v_user, 'employeeId', v_employee), 'teams/' || (remove_team_member.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team_member.deleted',
    category => 'membership',
    target_type => 'team',
    record_id => (remove_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', v_user, 'employeeId', v_employee)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_team_member"(uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_team_member"(uuid, uuid, uuid) to authenticated, service_role;
-- Teams as a keyset page, by name unless sort says otherwise (ADR 1077).
-- filters may hold status (a value or a list), search, sort (name,
-- createdAt), direction, facet, count, limit and after. Without paged it
-- returns the plain array, at most 200.
create or replace function "better_supabase"."list_teams"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_teams.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TEAM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
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
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_teams"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_teams"(uuid, jsonb) to authenticated, service_role;

-- One team the caller may read, or null.
create or replace function "better_supabase"."get_team"(team uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  )
    into v_tenant, v_row
    from "better_supabase"."teams" x
    where x."id" = get_team.team;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."get_team"(uuid) from public, anon;
grant execute on function "better_supabase"."get_team"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."team_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.teams deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"team","event_prefix":"team"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:481baacff0f1311ce2d36402d32ec2aea3b163a9f2866c0912bdc0f6369702bf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Members with an employee record get its id.
update "better_supabase"."team_members" y set "employee_id" = x."id"
from "better_supabase"."employees" x
where y."employee_id" is null and x."tenant_id" = y."tenant_id" and x."user_id" = y."user_id"
  and not exists (
    select 1 from "better_supabase"."team_members" z
    where z."team_id" = y."team_id" and z."employee_id" = x."id"
  );
insert into "better_supabase"."team_members" ("team_id", "user_id", "employee_id", "tenant_id")
select t."id",
  case when exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = x."tenant_id"
      and m."user_id" = x."user_id"
  ) then x."user_id" end,
  x."id", x."tenant_id"
from "better_supabase"."employees" x
join "better_supabase"."teams" t on t."id" = x."team_id" and t."tenant_id" = x."tenant_id"
on conflict do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:2ba4c7ad8828d06650e469fb3f48431621deb14177e46dcb49e778d11f943527
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table "app_private"."teams" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200),
  "slug" text not null constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug")
);
create unique index "bsb_teams_tenant_id_key" on "app_private"."teams" ("tenant_id", "id");
alter table "app_private"."teams" enable row level security;
revoke all on "app_private"."teams" from public, anon, authenticated;
grant select on "app_private"."teams" to authenticated;
grant all on "app_private"."teams" to service_role;
create policy bsb_teams_read on "app_private"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table "app_private"."team_members" (
  "team_id" uuid not null references "app_private"."teams" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
create index team_members_user_idx on "app_private"."team_members" ("user_id");
create index team_members_membership_idx on "app_private"."team_members" ("tenant_id", "user_id");
alter table "app_private"."team_members" enable row level security;
revoke all on "app_private"."team_members" from public, anon, authenticated;
grant select on "app_private"."team_members" to authenticated;
grant all on "app_private"."team_members" to service_role;
create policy bsb_team_members_read on "app_private"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "app_private"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("tenant_id", "user_id")
  references "better_supabase"."memberships" ("organization_id", "user_id")
  on delete cascade;
alter table "app_private"."team_members"
  add constraint team_members_team_tenant_fkey
  foreign key ("tenant_id", "team_id")
  references "app_private"."teams" ("tenant_id", "id")
  on delete cascade;
create index team_members_tenant_team_idx on "app_private"."team_members" ("tenant_id", "team_id");


-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function "app_private"."team_ids_of"(member uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "app_private"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "app_private"."team_ids_of"(uuid) from public, anon;
grant execute on function "app_private"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "app_private"."create_team"(tenant uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "app_private"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$$;
revoke execute on function "app_private"."create_team"(uuid, text, text) from public, anon;
grant execute on function "app_private"."create_team"(uuid, text, text) to authenticated, service_role;
create or replace function "app_private"."update_team"(team uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "app_private"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "app_private"."teams" x where x."id" = update_team.team);
end;
$$;
revoke execute on function "app_private"."update_team"(uuid, text, text) from public, anon;
grant execute on function "app_private"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "app_private"."archive_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "app_private"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_team"(uuid) from public, anon;
grant execute on function "app_private"."archive_team"(uuid) to authenticated, service_role;
create or replace function "app_private"."purge_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "app_private"."teams" where "id" = purge_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."purge_team"(uuid) from public, anon;
grant execute on function "app_private"."purge_team"(uuid) to authenticated, service_role;

-- purge_team for each of team_ids in one call, all or nothing; returns how many
-- it purged.
create or replace function "app_private"."purge_teams"(team_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid;
  v_count integer := 0;
begin
  if coalesce(cardinality(purge_teams.team_ids), 0) > 1000 then
    raise exception 'purge at most 1000 teams in one call' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  for v_team in select distinct x from unnest(purge_teams.team_ids) x where x is not null loop
    perform "app_private"."purge_team"(v_team);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."purge_teams"(uuid[]) from public, anon;
grant execute on function "app_private"."purge_teams"(uuid[]) to authenticated, service_role;

create or replace function "app_private"."add_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "app_private"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "app_private"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "app_private"."remove_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "app_private"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "app_private"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  null;
  return found;
end;
$$;
revoke execute on function "app_private"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "app_private"."remove_team_member"(uuid, uuid) to authenticated, service_role;
-- Teams as a keyset page, by name unless sort says otherwise (ADR 1077).
-- filters may hold status (a value or a list), search, sort (name,
-- createdAt), direction, facet, count, limit and after. Without paged it
-- returns the plain array, at most 200.
create or replace function "app_private"."list_teams"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_teams.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TEAM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
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
      select 1 from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "app_private"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "app_private"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "app_private"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "app_private"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "app_private"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "app_private"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "app_private"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."list_teams"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_teams"(uuid, jsonb) to authenticated, service_role;

-- One team the caller may read, or null.
create or replace function "app_private"."get_team"(team uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "app_private"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  )
    into v_tenant, v_row
    from "app_private"."teams" x
    where x."id" = get_team.team;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return v_row;
end;
$$;
revoke execute on function "app_private"."get_team"(uuid) from public, anon;
grant execute on function "app_private"."get_team"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."team_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:11ec0ca46010c1e4d5120489f828aba8bab902213fecab8e4f6ba0e0259d6a7e
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table "better_supabase"."teams" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200),
  "slug" text not null constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug")
);
create unique index "bsb_teams_tenant_id_key" on "better_supabase"."teams" ("tenant_id", "id");
alter table "better_supabase"."teams" enable row level security;
revoke all on "better_supabase"."teams" from public, anon, authenticated;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
create policy bsb_teams_read on "better_supabase"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table "better_supabase"."team_members" (
  "team_id" uuid not null references "better_supabase"."teams" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
create index team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index team_members_membership_idx on "better_supabase"."team_members" ("tenant_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
revoke all on "better_supabase"."team_members" from public, anon, authenticated;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
create policy bsb_team_members_read on "better_supabase"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "better_supabase"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("tenant_id", "user_id")
  references "better_supabase"."memberships" ("organization_id", "user_id")
  on delete cascade;
alter table "better_supabase"."team_members"
  add constraint team_members_team_tenant_fkey
  foreign key ("tenant_id", "team_id")
  references "better_supabase"."teams" ("tenant_id", "id")
  on delete cascade;
create index team_members_tenant_team_idx on "better_supabase"."team_members" ("tenant_id", "team_id");


-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function "better_supabase"."team_ids_of"(member uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "better_supabase"."team_ids_of"(uuid) from public, anon;
grant execute on function "better_supabase"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_team"(tenant uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$$;
revoke execute on function "better_supabase"."create_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text) to authenticated, service_role;
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$$;
revoke execute on function "better_supabase"."update_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_team"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_team"(uuid) to authenticated, service_role;
create or replace function "better_supabase"."purge_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = purge_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_team"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_team"(uuid) to authenticated, service_role;

-- purge_team for each of team_ids in one call, all or nothing; returns how many
-- it purged.
create or replace function "better_supabase"."purge_teams"(team_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid;
  v_count integer := 0;
begin
  if coalesce(cardinality(purge_teams.team_ids), 0) > 1000 then
    raise exception 'purge at most 1000 teams in one call' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  for v_team in select distinct x from unnest(purge_teams.team_ids) x where x is not null loop
    perform "better_supabase"."purge_team"(v_team);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_teams"(uuid[]) from public, anon;
grant execute on function "better_supabase"."purge_teams"(uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."add_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  null;
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_team_member"(uuid, uuid) to authenticated, service_role;
-- Teams as a keyset page, by name unless sort says otherwise (ADR 1077).
-- filters may hold status (a value or a list), search, sort (name,
-- createdAt), direction, facet, count, limit and after. Without paged it
-- returns the plain array, at most 200.
create or replace function "better_supabase"."list_teams"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_teams.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TEAM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
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
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_teams"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_teams"(uuid, jsonb) to authenticated, service_role;

-- One team the caller may read, or null.
create or replace function "better_supabase"."get_team"(team uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  )
    into v_tenant, v_row
    from "better_supabase"."teams" x
    where x."id" = get_team.team;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."get_team"(uuid) from public, anon;
grant execute on function "better_supabase"."get_team"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."team_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.teams.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."team_ids_of"(member uuid)
returns setof uuid
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."team_ids_of"($1) $$;
revoke execute on function "api"."team_ids_of"(uuid) from public, anon;
grant execute on function "api"."team_ids_of"(uuid) to authenticated, service_role;

create or replace function "api"."create_team"(tenant uuid, name text, description text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_team"($1, $2, $3) $$;
revoke execute on function "api"."create_team"(uuid, text, text) from public, anon;
grant execute on function "api"."create_team"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."update_team"(team uuid, name text, description text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_team"($1, $2, $3) $$;
revoke execute on function "api"."update_team"(uuid, text, text) from public, anon;
grant execute on function "api"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."archive_team"(team uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_team"($1) $$;
revoke execute on function "api"."archive_team"(uuid) from public, anon;
grant execute on function "api"."archive_team"(uuid) to authenticated, service_role;

create or replace function "api"."purge_team"(team uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_team"($1) $$;
revoke execute on function "api"."purge_team"(uuid) from public, anon;
grant execute on function "api"."purge_team"(uuid) to authenticated, service_role;

create or replace function "api"."purge_teams"(team_ids uuid[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_teams"($1) $$;
revoke execute on function "api"."purge_teams"(uuid[]) from public, anon;
grant execute on function "api"."purge_teams"(uuid[]) to authenticated, service_role;

create or replace function "api"."add_team_member"(team uuid, member uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_team_member"($1, $2) $$;
revoke execute on function "api"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "api"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."remove_team_member"(team uuid, member uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_team_member"($1, $2) $$;
revoke execute on function "api"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "api"."remove_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."list_teams"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_teams"($1, $2) $$;
revoke execute on function "api"."list_teams"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_teams"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_team"(team uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_team"($1) $$;
revoke execute on function "api"."get_team"(uuid) from public, anon;
grant execute on function "api"."get_team"(uuid) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:dede773bb97f7a29e0ae0b45da6d5789b5f444fe20596f209d996a69b3bbeded
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
-- better_supabase.teams is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."teams" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."teams" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."teams" add column if not exists "name" text constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200);
alter table "better_supabase"."teams" add column if not exists "slug" text constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$');
alter table "better_supabase"."teams" add column if not exists "description" text;
alter table "better_supabase"."teams" add column if not exists "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived'));
alter table "better_supabase"."teams" add column if not exists "created_by" uuid;
alter table "better_supabase"."teams" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."teams" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."teams" enable row level security;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
create policy bsb_teams_select on "better_supabase"."teams"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));

-- better_supabase.team_members is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."team_members" add column if not exists "team_id" uuid references "better_supabase"."teams" ("id") on delete cascade;
alter table "better_supabase"."team_members" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."team_members" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."team_members" add column if not exists "created_at" timestamptz not null default now();
create index if not exists team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index if not exists team_members_membership_idx on "better_supabase"."team_members" ("tenant_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
create policy bsb_team_members_select on "better_supabase"."team_members"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')));
create index if not exists team_members_tenant_team_idx on "better_supabase"."team_members" ("tenant_id", "team_id");


-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function "better_supabase"."team_ids_of"(member uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "better_supabase"."team_ids_of"(uuid) from public, anon;
grant execute on function "better_supabase"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_team"(tenant uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$$;
revoke execute on function "better_supabase"."create_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text) to authenticated, service_role;
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$$;
revoke execute on function "better_supabase"."update_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_team"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_team"(uuid) to authenticated, service_role;
create or replace function "better_supabase"."purge_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = purge_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_team"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_team"(uuid) to authenticated, service_role;

-- purge_team for each of team_ids in one call, all or nothing; returns how many
-- it purged.
create or replace function "better_supabase"."purge_teams"(team_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid;
  v_count integer := 0;
begin
  if coalesce(cardinality(purge_teams.team_ids), 0) > 1000 then
    raise exception 'purge at most 1000 teams in one call' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  for v_team in select distinct x from unnest(purge_teams.team_ids) x where x is not null loop
    perform "better_supabase"."purge_team"(v_team);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_teams"(uuid[]) from public, anon;
grant execute on function "better_supabase"."purge_teams"(uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."add_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  null;
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_team_member"(uuid, uuid) to authenticated, service_role;
-- Teams as a keyset page, by name unless sort says otherwise (ADR 1077).
-- filters may hold status (a value or a list), search, sort (name,
-- createdAt), direction, facet, count, limit and after. Without paged it
-- returns the plain array, at most 200.
create or replace function "better_supabase"."list_teams"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_teams.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TEAM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
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
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_teams"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_teams"(uuid, jsonb) to authenticated, service_role;

-- One team the caller may read, or null.
create or replace function "better_supabase"."get_team"(team uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  )
    into v_tenant, v_row
    from "better_supabase"."teams" x
    where x."id" = get_team.team;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."get_team"(uuid) from public, anon;
grant execute on function "better_supabase"."get_team"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."teams" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."teams" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."teams" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."teams" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."team_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."team_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."team_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."team_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block teams@3 managed
-- @bsb-hash sha256:081a5316a3ea6bb0b95f6317ffc725aef9041fa3da4d93845a33f60c0686111c
-- Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
create table "better_supabase"."teams" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "name" text not null constraint bsb_teams_name_check check (length("name") >= 1 and length("name") <= 200),
  "slug" text not null constraint bsb_teams_slug_check check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "status" text not null default 'active' constraint bsb_teams_status_check check ("status" in ('active', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "slug")
);
create unique index "bsb_teams_tenant_id_key" on "better_supabase"."teams" ("org_id", "id");
alter table "better_supabase"."teams" enable row level security;
revoke all on "better_supabase"."teams" from public, anon, authenticated;
grant select on "better_supabase"."teams" to authenticated;
grant all on "better_supabase"."teams" to service_role;
create policy bsb_teams_read on "better_supabase"."teams"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('teams.read')));

create table "better_supabase"."team_members" (
  "team_id" uuid not null references "better_supabase"."teams" ("id") on delete cascade,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "org_id" uuid not null,
  "created_at" timestamptz not null default now(),
  primary key ("team_id", "user_id")
);
create index team_members_user_idx on "better_supabase"."team_members" ("user_id");
create index team_members_membership_idx on "better_supabase"."team_members" ("org_id", "user_id");
alter table "better_supabase"."team_members" enable row level security;
revoke all on "better_supabase"."team_members" from public, anon, authenticated;
grant select on "better_supabase"."team_members" to authenticated;
grant all on "better_supabase"."team_members" to service_role;
create policy bsb_team_members_read on "better_supabase"."team_members"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('teams.read')));
alter table "better_supabase"."team_members"
  add constraint team_members_membership_fkey
  foreign key ("org_id", "user_id")
  references "better_supabase"."memberships" ("org_id", "user_id")
  on delete cascade;
alter table "better_supabase"."team_members"
  add constraint team_members_team_tenant_fkey
  foreign key ("org_id", "team_id")
  references "better_supabase"."teams" ("org_id", "id")
  on delete cascade;
create index team_members_tenant_team_idx on "better_supabase"."team_members" ("org_id", "team_id");


-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function "better_supabase"."team_ids_of"(member uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    raise exception 'team_ids_of reads only the caller''s teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return query select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member;
end;
$$;
revoke execute on function "better_supabase"."team_ids_of"(uuid) from public, anon;
grant execute on function "better_supabase"."team_ids_of"(uuid) to authenticated, service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_team"(tenant uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "better_supabase"."teams" ("org_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$$;
revoke execute on function "better_supabase"."create_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_team"(uuid, text, text) to authenticated, service_role;
create or replace function "better_supabase"."update_team"(team uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  null;
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$$;
revoke execute on function "better_supabase"."update_team"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."update_team"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."archive_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_team"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_team"(uuid) to authenticated, service_role;
create or replace function "better_supabase"."purge_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = purge_team.team;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_team"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_team"(uuid) to authenticated, service_role;

-- purge_team for each of team_ids in one call, all or nothing; returns how many
-- it purged.
create or replace function "better_supabase"."purge_teams"(team_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team uuid;
  v_count integer := 0;
begin
  if coalesce(cardinality(purge_teams.team_ids), 0) > 1000 then
    raise exception 'purge at most 1000 teams in one call' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  for v_team in select distinct x from unnest(purge_teams.team_ids) x where x is not null loop
    perform "better_supabase"."purge_team"(v_team);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."purge_teams"(uuid[]) from public, anon;
grant execute on function "better_supabase"."purge_teams"(uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."add_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."memberships" m
    where m."org_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "org_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."add_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."add_team_member"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_team_member"(team uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "org_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  null;
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_team_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_team_member"(uuid, uuid) to authenticated, service_role;
-- Teams as a keyset page, by name unless sort says otherwise (ADR 1077).
-- filters may hold status (a value or a list), search, sort (name,
-- createdAt), direction, facet, count, limit and after. Without paged it
-- returns the plain array, at most 200.
create or replace function "better_supabase"."list_teams"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_teams.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TEAM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
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
      select 1 from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."teams" x
      where x."org_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_teams"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_teams"(uuid, jsonb) to authenticated, service_role;

-- One team the caller may read, or null.
create or replace function "better_supabase"."get_team"(team uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."org_id", jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at")
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  )
    into v_tenant, v_row
    from "better_supabase"."teams" x
    where x."id" = get_team.team;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."get_team"(uuid) from public, anon;
grant execute on function "better_supabase"."get_team"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."teams" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."teams" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."teams" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."teams" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."team_members" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('teams.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."team_members" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."team_members" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."team_members" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_058_teams.sql
-- better-supabase module: teams
-- @bsb-block-data teams
-- @bsb-hash sha256:343c6d189b386e49106859fc04e329bcaaa000b06471bf85ee6b94cd5f5c4867
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('teams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
