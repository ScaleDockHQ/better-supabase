-- ==== schema supabase/schemas/900_better_supabase_049_knowledge.sql
-- better-supabase module: knowledge
-- @bsb-block knowledge@7 managed
-- @bsb-hash sha256:302b7867245fb871988e87139513a0471834691831add18d3b552a02e4c26820
-- Documents and chunks for retrieval with an embedding and a tsvector each, scoped to an organization, agent, project, chat, user or record (subject) and grouped into collections with a visibility, a priority and grants, plus system documents shared with every tenant; hybrid search with reciprocal rank fusion, chunks that keep their embedding when unchanged, and an embed job per document when jobs is installed. With ai-files and jobs, queue_knowledge_file ingests a file through a job.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Collections group documents. automatic ones show up in every search of
-- their tenant, restricted ones only for their grants and admins, disabled
-- ones in no search. A collection without a tenant is a system collection.
create table "better_supabase"."knowledge_collections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "name" text not null constraint bsb_knowledge_collections_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text,
  "visibility" text not null default 'automatic' constraint bsb_knowledge_collections_visibility_check check ("visibility" in ('automatic', 'restricted', 'disabled')),
  "priority" integer not null default 0,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index knowledge_collections_name_key on "better_supabase"."knowledge_collections" ("tenant_id", "name") nulls not distinct;
create index knowledge_collections_created_by_idx on "better_supabase"."knowledge_collections" ("created_by");
alter table "better_supabase"."knowledge_collections" enable row level security;
revoke all on "better_supabase"."knowledge_collections" from public, anon, authenticated;
grant select on "better_supabase"."knowledge_collections" to authenticated;
grant all on "better_supabase"."knowledge_collections" to service_role;

create table "better_supabase"."knowledge_collection_grants" (
  "collection_id" uuid not null references "better_supabase"."knowledge_collections" ("id") on delete cascade,
  "tenant_id" uuid,
  "user_id" uuid references auth.users (id) on delete cascade,
  "team_id" text,
  "created_at" timestamptz not null default now(),
  constraint bsb_knowledge_collection_grants_check check (("user_id" is null) <> ("team_id" is null))
);
create unique index knowledge_collection_grants_key on "better_supabase"."knowledge_collection_grants" ("collection_id", "user_id", "team_id") nulls not distinct;
create index knowledge_collection_grants_user_idx on "better_supabase"."knowledge_collection_grants" ("user_id") where "user_id" is not null;
create index knowledge_collection_grants_tenant_idx on "better_supabase"."knowledge_collection_grants" ("tenant_id") where "tenant_id" is not null;
alter table "better_supabase"."knowledge_collection_grants" enable row level security;
revoke all on "better_supabase"."knowledge_collection_grants" from public, anon, authenticated;
grant all on "better_supabase"."knowledge_collection_grants" to service_role;

-- Security definer, so the documents policy can check grants the caller
-- can't select.
create or replace function "better_supabase"."knowledge_collection_readable"(collection_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."knowledge_collections" c
    where c."id" = knowledge_collection_readable.collection_id
      and (c."tenant_id" is null or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', c."tenant_id", 'knowledge.read'), false))
      and (c."visibility" = 'automatic'
        or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (c."tenant_id" is not null and coalesce(better_supabase.can('tenant', c."tenant_id", 'knowledge.manage'), false)))
        or exists (
          select 1 from "better_supabase"."knowledge_collection_grants" x
          where x."collection_id" = c."id" and (x."user_id" = auth.uid())
        ))
  )
$$;
revoke execute on function "better_supabase"."knowledge_collection_readable"(uuid) from public, anon;
grant execute on function "better_supabase"."knowledge_collection_readable"(uuid) to authenticated, service_role;
create policy bsb_knowledge_collections_read on "better_supabase"."knowledge_collections"
  for select to authenticated
  using ("better_supabase"."knowledge_collection_readable"("id"));

-- Creates a collection. A tenant's admins create its collections; only the
-- service role creates a system collection (tenant null).
create or replace function "better_supabase"."create_knowledge_collection"(
  tenant uuid,
  name text,
  description text default null,
  visibility text default 'automatic',
  priority integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."knowledge_collections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_knowledge_collection.tenant is not null and coalesce(better_supabase.can('tenant', create_knowledge_collection.tenant, 'knowledge.manage'), false))) then
    raise exception 'only admins add knowledge collections' using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_collection.visibility is null or create_knowledge_collection.visibility not in ('automatic', 'restricted', 'disabled') then
    raise exception 'visibility % is not automatic, restricted or disabled', create_knowledge_collection.visibility using errcode = '22023', hint = 'KNOWLEDGE_VISIBILITY';
  end if;
  insert into "better_supabase"."knowledge_collections" ("tenant_id", "name", "description", "visibility", "priority", "created_by")
  values (create_knowledge_collection.tenant, create_knowledge_collection.name, create_knowledge_collection.description, create_knowledge_collection.visibility, coalesce(create_knowledge_collection.priority, 0), auth.uid())
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'visibility', v_row."visibility", 'priority', v_row."priority", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_knowledge_collection"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."create_knowledge_collection"(uuid, text, text, text, integer) to authenticated, service_role;

-- Changes the name, description, visibility or priority a patch names.
create or replace function "better_supabase"."update_knowledge_collection"(collection_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."knowledge_collections"%rowtype;
  v_visibility text := coalesce(update_knowledge_collection.patch ->> 'visibility', 'automatic');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_collections" x where x."id" = update_knowledge_collection.collection_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'knowledge.manage'), false))) then
    raise exception 'collection % not found', update_knowledge_collection.collection_id using errcode = 'P0002', hint = 'KNOWLEDGE_COLLECTION_NOT_FOUND';
  end if;
  if update_knowledge_collection.patch ? 'visibility' then
  if v_visibility is null or v_visibility not in ('automatic', 'restricted', 'disabled') then
    raise exception 'visibility % is not automatic, restricted or disabled', v_visibility using errcode = '22023', hint = 'KNOWLEDGE_VISIBILITY';
  end if;
  end if;
  update "better_supabase"."knowledge_collections" x set
    "name" = coalesce(update_knowledge_collection.patch ->> 'name', x."name"),
    "description" = case when update_knowledge_collection.patch ? 'description' then update_knowledge_collection.patch ->> 'description' else x."description" end,
    "visibility" = case when update_knowledge_collection.patch ? 'visibility' then v_visibility else x."visibility" end,
    "priority" = coalesce((update_knowledge_collection.patch ->> 'priority')::integer, x."priority"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'visibility', v_row."visibility", 'priority', v_row."priority", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_knowledge_collection"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_knowledge_collection"(uuid, jsonb) to authenticated, service_role;

-- Deletes a collection; its documents stay, without a collection.
create or replace function "better_supabase"."delete_knowledge_collection"(collection_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."knowledge_collections"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_collections" x where x."id" = delete_knowledge_collection.collection_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'knowledge.manage'), false))) then
    raise exception 'collection % not found', delete_knowledge_collection.collection_id using errcode = 'P0002', hint = 'KNOWLEDGE_COLLECTION_NOT_FOUND';
  end if;
  delete from "better_supabase"."knowledge_collections" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_knowledge_collection"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_knowledge_collection"(uuid) to authenticated, service_role;

-- The collections the caller can read in a tenant, system ones included,
-- highest priority first.
create or replace function "better_supabase"."list_knowledge_collections"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."priority" desc, x."name"), '[]')
  from "better_supabase"."knowledge_collections" x
  where x."tenant_id" = list_knowledge_collections.tenant or x."tenant_id" is null
$$;
revoke execute on function "better_supabase"."list_knowledge_collections"(uuid) from public, anon;
grant execute on function "better_supabase"."list_knowledge_collections"(uuid) to authenticated, service_role;

-- The collections the caller can read in a tenant as a keyset page (ADR 1077),
-- system ones included, highest priority first. filters is { visibility (a
-- value or a list), search (name, description), sort (priority, name,
-- createdAt), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function "better_supabase"."page_knowledge_collections"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_knowledge_collections.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('priority', 'name', 'createdAt') then
    raise exception 'sort is one of priority, name, createdAt' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."priority")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."priority", lower(x."name"), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."priority" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."priority")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."priority" <= (v_after ->> 0)::integer and ((x."priority" < (v_after ->> 0)::integer) or (x."priority" = (v_after ->> 0)::integer and lower(x."name") > (v_after ->> 1)::text) or (x."priority" = (v_after ->> 0)::integer and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."priority" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'priority' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."priority")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."priority", lower(x."name"), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."priority" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'priority' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."priority")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."priority" <= (v_after ->> 0)::integer and ((x."priority" < (v_after ->> 0)::integer) or (x."priority" = (v_after ->> 0)::integer and lower(x."name") > (v_after ->> 1)::text) or (x."priority" = (v_after ->> 0)::integer and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."priority" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_knowledge_collections"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_knowledge_collections"(uuid, jsonb) to authenticated, service_role;

-- One collection the caller can read, or null.
create or replace function "better_supabase"."get_knowledge_collection"(collection_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."knowledge_collections" x where x."id" = get_knowledge_collection.collection_id
$$;
revoke execute on function "better_supabase"."get_knowledge_collection"(uuid) from public, anon;
grant execute on function "better_supabase"."get_knowledge_collection"(uuid) to authenticated, service_role;

-- Grants a user or a team a restricted collection, or revokes it. Returns
-- whether anything changed. The grant keeps the collection's tenant.
create or replace function "better_supabase"."set_knowledge_collection_grant"(collection_id uuid, user_id uuid default null, team_id text default null, granted boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."knowledge_collections"%rowtype;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_collections" x where x."id" = set_knowledge_collection_grant.collection_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'knowledge.manage'), false))) then
    raise exception 'collection % not found', set_knowledge_collection_grant.collection_id using errcode = 'P0002', hint = 'KNOWLEDGE_COLLECTION_NOT_FOUND';
  end if;
  if (set_knowledge_collection_grant.user_id is null) = (set_knowledge_collection_grant.team_id is null) then
    raise exception 'name a user or a team' using errcode = '22023', hint = 'KNOWLEDGE_GRANT';
  end if;
  if set_knowledge_collection_grant.granted then
    insert into "better_supabase"."knowledge_collection_grants" ("collection_id", "tenant_id", "user_id", "team_id")
    values (v_row."id", v_row."tenant_id", set_knowledge_collection_grant.user_id, set_knowledge_collection_grant.team_id)
    on conflict do nothing;
  else
    delete from "better_supabase"."knowledge_collection_grants" x
    where x."collection_id" = v_row."id"
      and x."user_id" is not distinct from set_knowledge_collection_grant.user_id
      and x."team_id" is not distinct from set_knowledge_collection_grant.team_id;
  end if;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;
revoke execute on function "better_supabase"."set_knowledge_collection_grant"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_knowledge_collection_grant"(uuid, uuid, text, boolean) to authenticated, service_role;

-- The grants of a collection, for its admins.
create or replace function "better_supabase"."list_knowledge_collection_grants"(collection_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."knowledge_collections"%rowtype;
begin
  select * into v_row from "better_supabase"."knowledge_collections" x where x."id" = list_knowledge_collection_grants.collection_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'knowledge.manage'), false))) then
    raise exception 'collection % not found', list_knowledge_collection_grants.collection_id using errcode = 'P0002', hint = 'KNOWLEDGE_COLLECTION_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('user_id', x."user_id", 'team_id', x."team_id", 'created_at', x."created_at") order by x."created_at"), '[]')
    from "better_supabase"."knowledge_collection_grants" x where x."collection_id" = v_row."id"
  );
end;
$$;
revoke execute on function "better_supabase"."list_knowledge_collection_grants"(uuid) from public, anon;
grant execute on function "better_supabase"."list_knowledge_collection_grants"(uuid) to authenticated, service_role;

-- Documents for retrieval: uploaded files, pasted text and synced rows, split
-- into chunks with an embedding and a tsvector each. The app chunks and
-- embeds; the database stores, scopes and searches.
create table "better_supabase"."knowledge_documents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid,
  "owner_id" uuid references auth.users (id) on delete cascade,
  "scope" text not null default 'user' constraint bsb_knowledge_documents_scope_check check ("scope" in ('organization', 'agent', 'project', 'chat', 'user', 'subject')),
  "scope_id" uuid,
  "file_id" uuid,
  "title" text not null constraint bsb_knowledge_documents_title_check check (length("title") >= 1 and length("title") <= 500),
  "source" text,
  "metadata" jsonb not null default '{}' constraint bsb_knowledge_documents_metadata_check check (jsonb_typeof("metadata") = 'object'),
  "status" text not null default 'pending' constraint bsb_knowledge_documents_status_check check ("status" in ('pending', 'ready', 'failed')),
  "error" text,
  "chunk_count" integer not null default 0,
  "embedding_model" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_knowledge_documents_check check (("scope" in ('organization', 'subject')) = ("scope_id" is null)),
  constraint bsb_knowledge_documents_system_check check ("tenant_id" is not null or ("scope" = 'organization' and "owner_id" is null))
);
alter table "better_supabase"."knowledge_documents" add column "collection_id" uuid references "better_supabase"."knowledge_collections" ("id") on delete set null;
alter table "better_supabase"."knowledge_documents" add column "subject_type" text constraint bsb_knowledge_documents_subject_type_check check (length("subject_type") >= 1 and length("subject_type") <= 100);
alter table "better_supabase"."knowledge_documents" add column "subject_id" text constraint bsb_knowledge_documents_subject_id_check check (length("subject_id") >= 1 and length("subject_id") <= 200);
alter table "better_supabase"."knowledge_documents" add constraint bsb_knowledge_documents_subject_check check (("scope" = 'subject') = ("subject_type" is not null and "subject_id" is not null));
create index knowledge_documents_subject_idx on "better_supabase"."knowledge_documents" ("subject_type", "subject_id") where "subject_type" is not null;
create index knowledge_documents_tenant_idx on "better_supabase"."knowledge_documents" ("tenant_id", "scope", "scope_id");
create index knowledge_documents_owner_idx on "better_supabase"."knowledge_documents" ("owner_id") where "owner_id" is not null;
create index knowledge_documents_collection_idx on "better_supabase"."knowledge_documents" ("collection_id") where "collection_id" is not null;
create index knowledge_documents_file_idx on "better_supabase"."knowledge_documents" ("file_id") where "file_id" is not null;
create index knowledge_documents_pending_idx on "better_supabase"."knowledge_documents" ("updated_at") where "status" = 'pending';
alter table "better_supabase"."knowledge_documents" enable row level security;
revoke all on "better_supabase"."knowledge_documents" from public, anon, authenticated;
grant select on "better_supabase"."knowledge_documents" to authenticated;
grant all on "better_supabase"."knowledge_documents" to service_role;
create policy bsb_knowledge_documents_read on "better_supabase"."knowledge_documents"
  for select to authenticated
  using (("tenant_id" is null or case when "scope" = 'subject' then false else ("owner_id" = (select auth.uid()) or ("scope" in ('organization', 'agent') and "tenant_id" in (select better_supabase.tenant_ids_with('knowledge.read'))) or "tenant_id" in (select better_supabase.tenant_ids_with('knowledge.manage')) or ("scope" = 'chat' and false)) end) and ("collection_id" is null or "better_supabase"."knowledge_collection_readable"("collection_id")));

-- A chunk is visible when its document is, so search inherits the scopes.
create table "better_supabase"."knowledge_chunks" (
  "document_id" uuid not null references "better_supabase"."knowledge_documents" ("id") on delete cascade,
  "idx" integer not null constraint bsb_knowledge_chunks_idx_check check ("idx" >= 0),
  "content" text not null constraint bsb_knowledge_chunks_content_check check (length("content") > 0),
  "token_count" integer,
  "embedding" extensions.vector(1536),
  "embedding_hash" text,
  "metadata" jsonb not null default '{}',
  "tsv" tsvector generated always as (to_tsvector('simple'::regconfig, "content")) stored,
  primary key ("document_id", "idx")
);
create index knowledge_chunks_embedding_idx on "better_supabase"."knowledge_chunks" using hnsw ("embedding" extensions.vector_cosine_ops);
create index knowledge_chunks_tsv_idx on "better_supabase"."knowledge_chunks" using gin ("tsv");
create index knowledge_chunks_pending_idx on "better_supabase"."knowledge_chunks" ("document_id", "idx") where "embedding" is null;
alter table "better_supabase"."knowledge_chunks" enable row level security;
revoke all on "better_supabase"."knowledge_chunks" from public, anon, authenticated;
grant select on "better_supabase"."knowledge_chunks" to authenticated;
grant all on "better_supabase"."knowledge_chunks" to service_role;
create policy bsb_knowledge_chunks_read on "better_supabase"."knowledge_chunks"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."knowledge_documents" doc where doc."id" = "document_id"));

-- Creates a document for the caller (or for owner, as the service role).
-- Organization and agent knowledge needs the manage permission. Only the
-- service role creates a system document (tenant null, organization scope).
-- A document joins a collection of its tenant, or a system collection.
-- Subject knowledge names a record (subject_type, subject_id) of the tenant
-- that the caller can read, and is read only by those who can read it.

create or replace function "better_supabase"."create_knowledge_document"(
  tenant uuid,
  title text,
  scope text default 'user',
  scope_id uuid default null,
  file_id uuid default null,
  source text default null,
  metadata jsonb default '{}',
  owner uuid default null,
  collection_id uuid default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_knowledge_document.owner else auth.uid() end;
  v_scope_id uuid := create_knowledge_document.scope_id;
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or create_knowledge_document.tenant is null or not coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'knowledge.write'), false)) then
    raise exception 'you may not add knowledge here' using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.tenant is null then
    v_owner := null;
  end if;
  if create_knowledge_document.collection_id is not null and not exists (
    select 1 from "better_supabase"."knowledge_collections" kc
    where kc."id" = create_knowledge_document.collection_id
      and (kc."tenant_id" is null or kc."tenant_id" = create_knowledge_document.tenant)
      and "better_supabase"."knowledge_collection_readable"(kc."id")
  ) then
    raise exception 'collection % not found', create_knowledge_document.collection_id using errcode = 'P0002', hint = 'KNOWLEDGE_COLLECTION_NOT_FOUND';
  end if;
  if create_knowledge_document.scope in ('organization', 'agent') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'knowledge.manage'), false)) then
    raise exception 'only admins add % knowledge', create_knowledge_document.scope using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.scope = 'user' then
    v_scope_id := coalesce(v_scope_id, v_owner);
    if v_scope_id is null or v_scope_id is distinct from v_owner then
      raise exception 'user knowledge belongs to its owner' using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
    end if;
  end if;
  if create_knowledge_document.scope is null
    or create_knowledge_document.scope not in ('organization', 'agent', 'project', 'chat', 'user')
    or (create_knowledge_document.scope in ('organization', 'subject')) <> (v_scope_id is null) then
    raise exception '% knowledge needs %', create_knowledge_document.scope, case when create_knowledge_document.scope in ('organization', 'subject') then 'no scope_id' else 'a scope_id' end using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
  end if;
  if (create_knowledge_document.scope = 'subject') <> (create_knowledge_document.subject_type is not null and create_knowledge_document.subject_id is not null)
    or (create_knowledge_document.scope <> 'subject' and (create_knowledge_document.subject_type is not null or create_knowledge_document.subject_id is not null)) then
    raise exception 'subject knowledge needs subject_type and subject_id, and other scopes neither' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if create_knowledge_document.scope = 'chat' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or false) then
    raise exception 'chat % not found', v_scope_id using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."knowledge_documents" ("tenant_id", "owner_id", "scope", "scope_id", "file_id", "title", "collection_id", "source", "metadata", "subject_type", "subject_id")
  values (create_knowledge_document.tenant, v_owner, create_knowledge_document.scope, v_scope_id, create_knowledge_document.file_id, create_knowledge_document.title, create_knowledge_document.collection_id, create_knowledge_document.source, coalesce(create_knowledge_document.metadata, '{}'), create_knowledge_document.subject_type, create_knowledge_document.subject_id)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'collection_id', v_row."collection_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid, uuid, text, text) to authenticated, service_role;

-- Replaces a document's chunks. A chunk whose text is unchanged keeps its
-- embedding unless the model changed; the rest wait for the embed job.
-- chunks is a list of {content, tokens, metadata}, or {"items": list}.
create or replace function "better_supabase"."write_knowledge_chunks"(document_id uuid, chunks jsonb, model text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
  v_count integer;
  v_keep boolean;
  v_items jsonb := case when jsonb_typeof(write_knowledge_chunks.chunks) = 'object' then write_knowledge_chunks.chunks -> 'items' else write_knowledge_chunks.chunks end;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = write_knowledge_chunks.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'knowledge.manage'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'KNOWLEDGE_NOT_FOUND';
  end if;
  if coalesce(jsonb_typeof(v_items), '') <> 'array' or jsonb_array_length(v_items) > 10000 then
    raise exception 'chunks must be an array of at most 10000 chunks' using errcode = '22023', hint = 'KNOWLEDGE_CHUNKS';
  end if;
  v_count := jsonb_array_length(v_items);
  v_keep := write_knowledge_chunks.model is not distinct from v_row."embedding_model" or write_knowledge_chunks.model is null;
  insert into "better_supabase"."knowledge_chunks" as t ("document_id", "idx", "content", "token_count", "metadata")
  select v_row."id", (e.ord - 1)::integer, e.value ->> 'content', (e.value ->> 'tokens')::integer, coalesce(e.value -> 'metadata', '{}')
  from jsonb_array_elements(v_items) with ordinality e(value, ord)
  on conflict ("document_id", "idx") do update set
    "content" = excluded."content",
    "token_count" = excluded."token_count",
    "metadata" = excluded."metadata",
    "embedding" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding" end,
    "embedding_hash" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding_hash" end;
  delete from "better_supabase"."knowledge_chunks" x where x."document_id" = v_row."id" and x."idx" >= v_count;
  update "better_supabase"."knowledge_documents" x set
    "status" = case when exists (select 1 from "better_supabase"."knowledge_chunks" p where p."document_id" = x."id" and p."embedding" is null) then 'pending' else 'ready' end,
    "error" = null,
    "chunk_count" = v_count,
    "embedding_model" = coalesce(write_knowledge_chunks.model, x."embedding_model"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" = 'pending' then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'collection_id', v_row."collection_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."write_knowledge_chunks"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."write_knowledge_chunks"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."get_knowledge_document"(document_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."knowledge_documents" x where x."id" = get_knowledge_document.document_id
$$;
revoke execute on function "better_supabase"."get_knowledge_document"(uuid) from public, anon;
grant execute on function "better_supabase"."get_knowledge_document"(uuid) to authenticated, service_role;

-- The documents the caller can read in a tenant, newest first. With a
-- collection, its documents, system ones included. With a record, the
-- subject knowledge about it.

create or replace function "better_supabase"."list_knowledge_documents"(
  tenant uuid,
  scope text default null,
  scope_id uuid default null,
  max_rows integer default 100,
  collection_id uuid default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from (
    select * from "better_supabase"."knowledge_documents" y
    where (y."tenant_id" = list_knowledge_documents.tenant or (y."tenant_id" is null and list_knowledge_documents.collection_id is not null))
      and (list_knowledge_documents.collection_id is null or y."collection_id" = list_knowledge_documents.collection_id)
      and (list_knowledge_documents.scope is null or y."scope" = list_knowledge_documents.scope)
      and (list_knowledge_documents.scope_id is null or y."scope_id" = list_knowledge_documents.scope_id)
      and (list_knowledge_documents.subject_type is null or y."subject_type" = list_knowledge_documents.subject_type)
      and (list_knowledge_documents.subject_id is null or y."subject_id" = list_knowledge_documents.subject_id)
    order by y."created_at" desc
    limit least(greatest(list_knowledge_documents.max_rows, 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer, uuid, text, text) to authenticated, service_role;

-- The documents the caller can read in a tenant as a keyset page (ADR 1077).
-- filters is { collectionId (one uuid), scopeId (one uuid), subjectType, subjectId,
-- scope (a value or a list), status (a value or a list), search (title), sort
-- (createdAt, title), direction, facet, count, limit, after, offset, paged,
-- total, totalCap }. With a collection, its documents, system ones included.
create or replace function "better_supabase"."page_knowledge_documents"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_knowledge_documents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_collection text := nullif(coalesce(v_filters #>> '{collectionId,0}', v_filters ->> 'collectionId'), '');
  v_scope_id text := nullif(coalesce(v_filters #>> '{scopeId,0}', v_filters ->> 'scopeId'), '');
  v_subject_type text := nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '');
  v_subject_id text := nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '');
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'collectionId') = 'array' then v_filters -> 'collectionId' when jsonb_typeof(v_filters -> 'collectionId') in ('string', 'number') then jsonb_build_array(v_filters -> 'collectionId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then v_filters -> 'scopeId' when jsonb_typeof(v_filters -> 'scopeId') in ('string', 'number') then jsonb_build_array(v_filters -> 'scopeId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'collectionId and scopeId are uuids' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('scope', 'status') then
      raise exception 'facet is one of scope, status' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'scope' then (x."scope")::text when 'status' then (x."status")::text end) as v
      from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
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
      select 1 from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'title') then
    raise exception 'sort is one of createdAt, title' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_knowledge_documents"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_knowledge_documents"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_knowledge_document"(document_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = delete_knowledge_document.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'knowledge.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."knowledge_documents" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_knowledge_document"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_knowledge_document"(uuid) to authenticated, service_role;

-- Hybrid search over the chunks the caller can read: the vector and the
-- full-text rankings fused with reciprocal rank fusion (k = 60). Iterative
-- index scans keep looking until enough visible chunks turn up. scopes is a
-- list of {"scope", "id"} objects ({"scope": "subject", "type", "id"} for a
-- record), or {"items": list}; null searches every scope. collections limits it to those collections. System documents count
-- in every tenant, disabled collections in none, and a collection with a
-- higher priority ranks its chunks first, or ranks them by score alone when
-- priority_order is false. Returns a JSON array of {document_id, idx,
-- chunk_id, organization_id, content, metadata, title, score}; chunk_id is
-- the document id and idx joined by '#', and organization_id is null for a
-- system document. The custom plan setting lets the planner fold the null
-- collections parameter, so the collection filter can use its index.

create or replace function "better_supabase"."knowledge_search"(
  tenant uuid,
  query_embedding extensions.vector default null,
  query_text text default null,
  scopes jsonb default null,
  k integer default 8,
  filter jsonb default null,
  collections uuid[] default null,
  priority_order boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
set plan_cache_mode = force_custom_plan
as $$
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
  v_candidates integer := least(greatest(knowledge_search.k, 1) * 4, 400);
  v_scopes jsonb := case when jsonb_typeof(knowledge_search.scopes) = 'object' then knowledge_search.scopes -> 'items' else knowledge_search.scopes end;
  v_rows jsonb;
begin
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with docs as materialized (
    select x."id" as id, x."tenant_id" as doc_tenant, x."title" as title, coalesce((select kc."priority" from "better_supabase"."knowledge_collections" kc where kc."id" = x."collection_id"), 0) as priority from "better_supabase"."knowledge_documents" x
    where (x."tenant_id" = knowledge_search.tenant or x."tenant_id" is null)
      and (x."collection_id" is null or exists (select 1 from "better_supabase"."knowledge_collections" kc where kc."id" = x."collection_id" and kc."visibility" <> 'disabled'))
      and (knowledge_search.collections is null or x."collection_id" = any(knowledge_search.collections))
      and (v_scopes is null or exists (
        select 1 from jsonb_array_elements(v_scopes) s
        where s.value ->> 'scope' = x."scope"
          and (s.value ->> 'scope' = 'subject' or s.value ->> 'id' is null or (s.value ->> 'id')::uuid = x."scope_id")
          and (s.value ->> 'scope' <> 'subject' or ((s.value ->> 'type' is null or s.value ->> 'type' = x."subject_type") and (s.value ->> 'id' is null or s.value ->> 'id' = x."subject_id")))
      ))
      and (knowledge_search.filter is null or x."metadata" @> knowledge_search.filter)
  ),
  vector_hits as materialized (
    select t."document_id" as document_id, t."idx" as idx, t."embedding" operator(extensions.<=>) knowledge_search.query_embedding as distance
    from "better_supabase"."knowledge_chunks" t
    where knowledge_search.query_embedding is not null and t."embedding" is not null
      and t."document_id" in (select docs.id from docs)
    order by t."embedding" operator(extensions.<=>) knowledge_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.document_id, h.idx, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_hits as materialized (
    select t."document_id" as document_id, t."idx" as idx, ts_rank_cd(t."tsv", q) as text_score
    from "better_supabase"."knowledge_chunks" t, websearch_to_tsquery('simple'::regconfig, knowledge_search.query_text) q
    where knowledge_search.query_text is not null and t."tsv" @@ q
      and t."document_id" in (select docs.id from docs)
    order by text_score desc
    limit v_candidates
  ),
  text_ranked as (
    select x.document_id, x.idx, row_number() over (order by x.text_score desc) as rank from text_hits x
  ),
  fused as (
    select coalesce(v.document_id, x.document_id) as document_id, coalesce(v.idx, x.idx) as idx,
      coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.document_id = v.document_id and x.idx = v.idx
  )
  select coalesce(jsonb_agg(jsonb_build_object('document_id', r.document_id, 'idx', r.idx, 'chunk_id', r.document_id::text || '#' || r.idx::text, 'organization_id', r.doc_tenant, 'content', r.content, 'metadata', r.metadata, 'title', r.title, 'score', r.score) order by r.rank_priority desc, r.score desc, r.document_id, r.idx), '[]')
  into v_rows
  from (
    select f.document_id, f.idx, t."content" as content, t."metadata" as metadata, docs.title, docs.doc_tenant,
      case when knowledge_search.priority_order then docs.priority else 0 end as rank_priority, f.score
    from fused f
    join "better_supabase"."knowledge_chunks" t on t."document_id" = f.document_id and t."idx" = f.idx
    join docs on docs.id = f.document_id
    order by rank_priority desc, f.score desc, f.document_id, f.idx
    limit least(greatest(knowledge_search.k, 1), 100)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb, uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb, uuid[], boolean) to authenticated, service_role;

-- The chunks of a document still waiting for an embedding, for the worker,
-- with the md5 of each content it passes back to set_knowledge_embeddings.
create or replace function "better_supabase"."pending_knowledge_chunks"(document_id uuid, batch integer default 64)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('idx', x."idx", 'content', x."content", 'hash', md5(x."content")) order by x."idx"), '[]')
  from (
    select * from "better_supabase"."knowledge_chunks" y
    where y."document_id" = pending_knowledge_chunks.document_id and y."embedding" is null
    order by y."idx"
    limit least(greatest(pending_knowledge_chunks.batch, 1), 2048)
  ) x
$$;
revoke execute on function "better_supabase"."pending_knowledge_chunks"(uuid, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."pending_knowledge_chunks"(uuid, integer) to service_role;

-- Stores embeddings ([{"idx", "hash", "embedding"}], or {"items": list}) and marks the
-- document ready once no chunk is missing one. Returns how many chunks still wait.
-- hash is the md5 of the content that was embedded: a chunk rewritten since
-- then keeps waiting instead of taking a vector of its old text.
create or replace function "better_supabase"."set_knowledge_embeddings"(document_id uuid, embeddings jsonb, model text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_remaining integer;
  v_items jsonb := case when jsonb_typeof(set_knowledge_embeddings.embeddings) = 'object' then set_knowledge_embeddings.embeddings -> 'items' else set_knowledge_embeddings.embeddings end;
begin
  update "better_supabase"."knowledge_chunks" t set
    "embedding" = (e.value ->> 'embedding')::extensions.vector(1536),
    "embedding_hash" = e.value ->> 'hash'
  from jsonb_array_elements(coalesce(v_items, '[]')) e
  where t."document_id" = set_knowledge_embeddings.document_id and t."idx" = (e.value ->> 'idx')::integer
    and md5(t."content") = e.value ->> 'hash';
  select count(*)::integer into v_remaining from "better_supabase"."knowledge_chunks" t
  where t."document_id" = set_knowledge_embeddings.document_id and t."embedding" is null;
  update "better_supabase"."knowledge_documents" x set
    "status" = case when v_remaining = 0 then 'ready' else x."status" end,
    "embedding_model" = coalesce(set_knowledge_embeddings.model, x."embedding_model"),
    "updated_at" = now()
  where x."id" = set_knowledge_embeddings.document_id;
  return v_remaining;
end;
$$;
revoke execute on function "better_supabase"."set_knowledge_embeddings"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_knowledge_embeddings"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."fail_knowledge_document"(document_id uuid, error text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update "better_supabase"."knowledge_documents" x set "status" = 'failed', "error" = left(fail_knowledge_document.error, 2000), "updated_at" = now()
  where x."id" = fail_knowledge_document.document_id
  returning true
$$;
revoke execute on function "better_supabase"."fail_knowledge_document"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."fail_knowledge_document"(uuid, text) to service_role;

-- Documents waiting for embeddings, oldest first, for a drain without jobs.
create or replace function "better_supabase"."pending_knowledge_documents"(batch integer default 10)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x."id" order by x."updated_at"), '[]')
  from (
    select * from "better_supabase"."knowledge_documents" y where y."status" = 'pending'
    order by y."updated_at"
    limit least(greatest(pending_knowledge_documents.batch, 1), 1000)
  ) x
$$;
revoke execute on function "better_supabase"."pending_knowledge_documents"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."pending_knowledge_documents"(integer) to service_role;

-- Clears the embeddings of a tenant's documents (all tenants when null)
-- that another model embedded, so the worker embeds them again.
create or replace function "better_supabase"."reembed_knowledge"(tenant uuid default null, model text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  for v_id in
    update "better_supabase"."knowledge_documents" x set "status" = 'pending', "updated_at" = now()
    where (reembed_knowledge.tenant is null or x."tenant_id" = reembed_knowledge.tenant)
      and (reembed_knowledge.model is null or x."embedding_model" is distinct from reembed_knowledge.model)
      and x."chunk_count" > 0
    returning x."id"
  loop
    update "better_supabase"."knowledge_chunks" t set "embedding" = null, "embedding_hash" = null where t."document_id" = v_id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."reembed_knowledge"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."reembed_knowledge"(uuid, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."knowledge_documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or (("tenant_id" is null or case when "scope" = 'subject' then false else ("owner_id" = (select auth.uid()) or ("scope" in ('organization', 'agent') and "tenant_id" in (select better_supabase.tenant_ids_with('knowledge.read'))) or "tenant_id" in (select better_supabase.tenant_ids_with('knowledge.manage')) or ("scope" = 'chat' and false)) end) and ("collection_id" is null or "better_supabase"."knowledge_collection_readable"("collection_id")))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."knowledge_documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."knowledge_documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."knowledge_documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."knowledge_collections" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("better_supabase"."knowledge_collection_readable"("id"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."knowledge_collections" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."knowledge_collections" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."knowledge_collections" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_049_knowledge.sql
-- better-supabase module: knowledge
-- @bsb-block-data knowledge
-- @bsb-hash sha256:31229537e7fd8ac633d9c419d45cd77587d9d01d8e8ecb4cc956111f5a29f98c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('knowledge', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
