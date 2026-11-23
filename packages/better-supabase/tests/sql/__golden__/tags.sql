-- ==== alone: schema supabase/schemas/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block tags@2 managed
-- @bsb-hash sha256:a935396feb65025704865c52617aa3a87ceecfed858acaf083a9eaa508360932
-- Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."tags" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "name" text not null constraint bsb_tags_name_check check (length("name") >= 1 and length("name") <= 80),
  "slug" text not null,
  "color" text,
  "description" text,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "kind", "slug")
);
alter table "better_supabase"."tags" enable row level security;
revoke all on "better_supabase"."tags" from public, anon, authenticated;
grant select on "better_supabase"."tags" to authenticated;
grant all on "better_supabase"."tags" to service_role;
create table "better_supabase"."taggings" (
  "tenant_id" uuid not null,
  "tag_id" uuid not null references "better_supabase"."tags" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("tag_id", "subject_type", "subject_id")
);
create index "taggings_subject_idx" on "better_supabase"."taggings" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."taggings" enable row level security;
revoke all on "better_supabase"."taggings" from public, anon, authenticated;
grant select on "better_supabase"."taggings" to authenticated;
grant all on "better_supabase"."taggings" to service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  select max(t."rank" collate "C") into v_last from "better_supabase"."tags" t
    where t."tenant_id" = create_tag.tenant and t."kind" = create_tag.kind;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."tags" ("tenant_id", "kind", "name", "slug", "color", "description", "rank", "created_at")
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when '' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."tag"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."update_tag"(tag_id uuid, name text)
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
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = update_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" t set "name" = coalesce(update_tag.name, t."name"), "updated_at" = now() where t."id" = update_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."update_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."update_tag"(uuid, text) to authenticated, service_role;

-- Sets a tag's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_tag"(tag_id uuid, rank text)
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
  if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'TAG_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = rank_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" set "rank" = rank_tag.rank, "updated_at" = now() where "id" = rank_tag.tag_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_tag"(tag_id uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  delete from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."untag"(uuid, text, text, uuid) to authenticated, service_role;

-- The tenant's tags of one kind (every kind when it is null), in rank order.
create or replace function "better_supabase"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = list_tags.tenant
      and (list_tags.kind is null or t."kind" = list_tags.kind)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tags"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_tags"(uuid, text) to authenticated, service_role;

-- The tenant's tags as a keyset page, in rank order (ADR 1077). filters is
-- { kind (a value or a list), search (name, slug, description), sort (rank,
-- name, kind, createdAt), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "better_supabase"."page_tags"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_tags.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'TAG_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'kind', 'createdAt') then
    raise exception 'sort is one of rank, name, kind, createdAt' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text, lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."kind"::text asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text <= (v_after ->> 0)::text and ((x."kind"::text < (v_after ->> 0)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."kind"::text desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_tags"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_tags"(uuid, jsonb) to authenticated, service_role;

-- One tag, or null, for a caller who can read its tenant's tags.
create or replace function "better_supabase"."get_tag"(tag_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select t."tenant_id" into v_tenant from "better_supabase"."tags" t where t."id" = get_tag.tag_id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return (select jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") from "better_supabase"."tags" t where t."id" = get_tag.tag_id);
end;
$$;
revoke execute on function "better_supabase"."get_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."get_tag"(uuid) to authenticated, service_role;

-- The tags on one subject, for a caller who can read the tenant's tags and the subject.
create or replace function "better_supabase"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_tags"(uuid, text, text) to authenticated, service_role;

-- The tags on several subjects of one type, keyed by subject id, in one call.
-- Each subject goes through the same checks as subject_tags.
create or replace function "better_supabase"."subjects_tags"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "better_supabase"."subject_tags"(subjects_tags.tenant, subjects_tags.subject_type, s.id)), '{}'::jsonb)
  from (select distinct u as id from unnest(subjects_tags.subject_ids) u limit 200) s
$$;
revoke execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."tags" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."tags" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."tags" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."tags" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."taggings" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."taggings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."taggings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."taggings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:baa1d5b6721528e763808c231522383a33db513a6254d0a316c15c1087308cb6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block tags@2 managed
-- @bsb-hash sha256:0aaa2cea1263c8e45ddb03cafbb179199d471032c83d7a9bda32ef3dee9e74da
-- Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."tags" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "name" text not null constraint bsb_tags_name_check check (length("name") >= 1 and length("name") <= 80),
  "slug" text not null,
  "color" text,
  "description" text,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "kind", "slug")
);
alter table "better_supabase"."tags" enable row level security;
revoke all on "better_supabase"."tags" from public, anon, authenticated;
grant select on "better_supabase"."tags" to authenticated;
grant all on "better_supabase"."tags" to service_role;
create table "better_supabase"."taggings" (
  "tenant_id" uuid not null,
  "tag_id" uuid not null references "better_supabase"."tags" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("tag_id", "subject_type", "subject_id")
);
create index "taggings_subject_idx" on "better_supabase"."taggings" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."taggings" enable row level security;
revoke all on "better_supabase"."taggings" from public, anon, authenticated;
grant select on "better_supabase"."taggings" to authenticated;
grant all on "better_supabase"."taggings" to service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  select max(t."rank" collate "C") into v_last from "better_supabase"."tags" t
    where t."tenant_id" = create_tag.tenant and t."kind" = create_tag.kind;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."tags" ("tenant_id", "kind", "name", "slug", "color", "description", "rank", "created_at")
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())
  returning "id" into v_id;
  perform "better_supabase".emit_event('tag.created', jsonb_build_object('organizationId', create_tag.tenant, 'id', v_id, 'kind', create_tag.kind, 'name', create_tag.name), 'tags/' || v_id::text, (create_tag.tenant)::text, null, 'better-supabase/tags');
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not ((case when tag.subject_type = 'drive_node' then coalesce(case when tag.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((tag.subject_id)::uuid, 'editor') end, false) else true end)) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when '' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  perform "better_supabase".emit_event('subject.tagged', jsonb_build_object('organizationId', tag.tenant, 'subjectType', tag.subject_type, 'subjectId', tag.subject_id, 'id', tag.tag_id), 'subjects/' || tag.subject_type || '/' || tag.subject_id, (tag.tenant)::text, null, 'better-supabase/tags');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."tag"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."update_tag"(tag_id uuid, name text)
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
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = update_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" t set "name" = coalesce(update_tag.name, t."name"), "updated_at" = now() where t."id" = update_tag.tag_id;
  perform "better_supabase".emit_event('tag.updated', jsonb_build_object('organizationId', v_tenant, 'id', update_tag.tag_id, 'name', update_tag.name), 'tags/' || update_tag.tag_id::text, (v_tenant)::text, null, 'better-supabase/tags');
  return true;
end;
$$;
revoke execute on function "better_supabase"."update_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."update_tag"(uuid, text) to authenticated, service_role;

-- Sets a tag's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_tag"(tag_id uuid, rank text)
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
  if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'TAG_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = rank_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" set "rank" = rank_tag.rank, "updated_at" = now() where "id" = rank_tag.tag_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_tag"(tag_id uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  delete from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  perform "better_supabase".emit_event('tag.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_tag.tag_id), 'tags/' || delete_tag.tag_id::text, (v_tenant)::text, null, 'better-supabase/tags');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not ((case when untag.subject_type = 'drive_node' then coalesce(case when untag.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((untag.subject_id)::uuid, 'editor') end, false) else true end)) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  perform "better_supabase".emit_event('subject.untagged', jsonb_build_object('organizationId', untag.tenant, 'subjectType', untag.subject_type, 'subjectId', untag.subject_id, 'id', untag.tag_id), 'subjects/' || untag.subject_type || '/' || untag.subject_id, (untag.tenant)::text, null, 'better-supabase/tags');
  return true;
end;
$$;
revoke execute on function "better_supabase"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."untag"(uuid, text, text, uuid) to authenticated, service_role;

-- The tenant's tags of one kind (every kind when it is null), in rank order.
create or replace function "better_supabase"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = list_tags.tenant
      and (list_tags.kind is null or t."kind" = list_tags.kind)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tags"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_tags"(uuid, text) to authenticated, service_role;

-- The tenant's tags as a keyset page, in rank order (ADR 1077). filters is
-- { kind (a value or a list), search (name, slug, description), sort (rank,
-- name, kind, createdAt), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "better_supabase"."page_tags"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_tags.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'TAG_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'kind', 'createdAt') then
    raise exception 'sort is one of rank, name, kind, createdAt' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text, lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."kind"::text asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text <= (v_after ->> 0)::text and ((x."kind"::text < (v_after ->> 0)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."kind"::text desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_tags"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_tags"(uuid, jsonb) to authenticated, service_role;

-- One tag, or null, for a caller who can read its tenant's tags.
create or replace function "better_supabase"."get_tag"(tag_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select t."tenant_id" into v_tenant from "better_supabase"."tags" t where t."id" = get_tag.tag_id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return (select jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") from "better_supabase"."tags" t where t."id" = get_tag.tag_id);
end;
$$;
revoke execute on function "better_supabase"."get_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."get_tag"(uuid) to authenticated, service_role;

-- The tags on one subject, for a caller who can read the tenant's tags and the subject.
create or replace function "better_supabase"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not ((case when subject_tags.subject_type = 'drive_node' then coalesce(case when subject_tags.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((subject_tags.subject_id)::uuid, 'viewer') end, false) else true end)) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_tags"(uuid, text, text) to authenticated, service_role;

-- The tags on several subjects of one type, keyed by subject id, in one call.
-- Each subject goes through the same checks as subject_tags.
create or replace function "better_supabase"."subjects_tags"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "better_supabase"."subject_tags"(subjects_tags.tenant, subjects_tags.subject_type, s.id)), '{}'::jsonb)
  from (select distinct u as id from unnest(subjects_tags.subject_ids) u limit 200) s
$$;
revoke execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."tags" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."tags" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."tags" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."tags" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."taggings" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."taggings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."taggings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."taggings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.tags deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"tag","event_prefix":"tag"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:baa1d5b6721528e763808c231522383a33db513a6254d0a316c15c1087308cb6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block tags@2 managed
-- @bsb-hash sha256:3f09bdb150b9fd4cd2b3cd8bdb662046752a39f894beb4fb34765c3696eaaa38
-- Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges for role postgres in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on functions from public, anon, authenticated;
create table "app_private"."tags" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "name" text not null constraint bsb_tags_name_check check (length("name") >= 1 and length("name") <= 80),
  "slug" text not null,
  "color" text,
  "description" text,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "kind", "slug")
);
alter table "app_private"."tags" enable row level security;
revoke all on "app_private"."tags" from public, anon, authenticated;
grant select on "app_private"."tags" to authenticated;
grant all on "app_private"."tags" to service_role;
create table "app_private"."taggings" (
  "tenant_id" uuid not null,
  "tag_id" uuid not null references "app_private"."tags" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("tag_id", "subject_type", "subject_id")
);
create index "taggings_subject_idx" on "app_private"."taggings" ("tenant_id", "subject_type", "subject_id");
alter table "app_private"."taggings" enable row level security;
revoke all on "app_private"."taggings" from public, anon, authenticated;
grant select on "app_private"."taggings" to authenticated;
grant all on "app_private"."taggings" to service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "app_private"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  select max(t."rank" collate "C") into v_last from "app_private"."tags" t
    where t."tenant_id" = create_tag.tenant and t."kind" = create_tag.kind;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "app_private"."tags" ("tenant_id", "kind", "name", "slug", "color", "description", "rank", "created_at")
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
revoke execute on function "app_private"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "app_private"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "app_private"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "app_private"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when '' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "app_private"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "app_private"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "app_private"."tag"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "app_private"."update_tag"(tag_id uuid, name text)
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
  select "tenant_id" into v_tenant from "app_private"."tags" where "id" = update_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "app_private"."tags" t set "name" = coalesce(update_tag.name, t."name"), "updated_at" = now() where t."id" = update_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."update_tag"(uuid, text) from public, anon;
grant execute on function "app_private"."update_tag"(uuid, text) to authenticated, service_role;

-- Sets a tag's rank key, from rankBetween over its neighbours' keys.
create or replace function "app_private"."rank_tag"(tag_id uuid, rank text)
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
  if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'TAG_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "app_private"."tags" where "id" = rank_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "app_private"."tags" set "rank" = rank_tag.rank, "updated_at" = now() where "id" = rank_tag.tag_id;
  return true;
end;
$$;
revoke execute on function "app_private"."rank_tag"(uuid, text) from public, anon;
grant execute on function "app_private"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."delete_tag"(tag_id uuid)
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
  select "tenant_id" into v_tenant from "app_private"."tags" where "id" = delete_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  delete from "app_private"."tags" where "id" = delete_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_tag"(uuid) from public, anon;
grant execute on function "app_private"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "app_private"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "app_private"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "app_private"."untag"(uuid, text, text, uuid) to authenticated, service_role;

-- The tenant's tags of one kind (every kind when it is null), in rank order.
create or replace function "app_private"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "app_private"."tags" t
    where t."tenant_id" = list_tags.tenant
      and (list_tags.kind is null or t."kind" = list_tags.kind)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_tags"(uuid, text) from public, anon;
grant execute on function "app_private"."list_tags"(uuid, text) to authenticated, service_role;

-- The tenant's tags as a keyset page, in rank order (ADR 1077). filters is
-- { kind (a value or a list), search (name, slug, description), sort (rank,
-- name, kind, createdAt), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "app_private"."page_tags"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_tags.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'TAG_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'kind', 'createdAt') then
    raise exception 'sort is one of rank, name, kind, createdAt' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text, lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."kind"::text asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text <= (v_after ->> 0)::text and ((x."kind"::text < (v_after ->> 0)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."kind"::text desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "app_private"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."page_tags"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."page_tags"(uuid, jsonb) to authenticated, service_role;

-- One tag, or null, for a caller who can read its tenant's tags.
create or replace function "app_private"."get_tag"(tag_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select t."tenant_id" into v_tenant from "app_private"."tags" t where t."id" = get_tag.tag_id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return (select jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") from "app_private"."tags" t where t."id" = get_tag.tag_id);
end;
$$;
revoke execute on function "app_private"."get_tag"(uuid) from public, anon;
grant execute on function "app_private"."get_tag"(uuid) to authenticated, service_role;

-- The tags on one subject, for a caller who can read the tenant's tags and the subject.
create or replace function "app_private"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "app_private"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "app_private"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "app_private"."subject_tags"(uuid, text, text) to authenticated, service_role;

-- The tags on several subjects of one type, keyed by subject id, in one call.
-- Each subject goes through the same checks as subject_tags.
create or replace function "app_private"."subjects_tags"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "app_private"."subject_tags"(subjects_tags.tenant, subjects_tags.subject_type, s.id)), '{}'::jsonb)
  from (select distinct u as id from unnest(subjects_tags.subject_ids) u limit 200) s
$$;
revoke execute on function "app_private"."subjects_tags"(uuid, text, text[]) from public, anon;
grant execute on function "app_private"."subjects_tags"(uuid, text, text[]) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."tags" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "app_private"."tags" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."tags" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."tags" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."taggings" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "app_private"."taggings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."taggings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."taggings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:baa1d5b6721528e763808c231522383a33db513a6254d0a316c15c1087308cb6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block tags@2 managed
-- @bsb-hash sha256:4b2fc0c4f707bbe4f965c89534e75f8db331c4c013d41bfa13a8f43d8bd7bf0a
-- Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."tags" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "name" text not null constraint bsb_tags_name_check check (length("name") >= 1 and length("name") <= 80),
  "slug" text not null,
  "color" text,
  "description" text,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "kind", "slug")
);
alter table "better_supabase"."tags" enable row level security;
revoke all on "better_supabase"."tags" from public, anon, authenticated;
grant select on "better_supabase"."tags" to authenticated;
grant all on "better_supabase"."tags" to service_role;
create table "better_supabase"."taggings" (
  "tenant_id" uuid not null,
  "tag_id" uuid not null references "better_supabase"."tags" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("tag_id", "subject_type", "subject_id")
);
create index "taggings_subject_idx" on "better_supabase"."taggings" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."taggings" enable row level security;
revoke all on "better_supabase"."taggings" from public, anon, authenticated;
grant select on "better_supabase"."taggings" to authenticated;
grant all on "better_supabase"."taggings" to service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  select max(t."rank" collate "C") into v_last from "better_supabase"."tags" t
    where t."tenant_id" = create_tag.tenant and t."kind" = create_tag.kind;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."tags" ("tenant_id", "kind", "name", "slug", "color", "description", "rank", "created_at")
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when '' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."tag"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."update_tag"(tag_id uuid, name text)
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
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = update_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" t set "name" = coalesce(update_tag.name, t."name"), "updated_at" = now() where t."id" = update_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."update_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."update_tag"(uuid, text) to authenticated, service_role;

-- Sets a tag's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_tag"(tag_id uuid, rank text)
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
  if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'TAG_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = rank_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" set "rank" = rank_tag.rank, "updated_at" = now() where "id" = rank_tag.tag_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_tag"(tag_id uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  delete from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."untag"(uuid, text, text, uuid) to authenticated, service_role;

-- The tenant's tags of one kind (every kind when it is null), in rank order.
create or replace function "better_supabase"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = list_tags.tenant
      and (list_tags.kind is null or t."kind" = list_tags.kind)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tags"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_tags"(uuid, text) to authenticated, service_role;

-- The tenant's tags as a keyset page, in rank order (ADR 1077). filters is
-- { kind (a value or a list), search (name, slug, description), sort (rank,
-- name, kind, createdAt), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "better_supabase"."page_tags"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_tags.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'TAG_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'kind', 'createdAt') then
    raise exception 'sort is one of rank, name, kind, createdAt' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text, lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."kind"::text asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text <= (v_after ->> 0)::text and ((x."kind"::text < (v_after ->> 0)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."kind"::text desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_tags"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_tags"(uuid, jsonb) to authenticated, service_role;

-- One tag, or null, for a caller who can read its tenant's tags.
create or replace function "better_supabase"."get_tag"(tag_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select t."tenant_id" into v_tenant from "better_supabase"."tags" t where t."id" = get_tag.tag_id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return (select jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") from "better_supabase"."tags" t where t."id" = get_tag.tag_id);
end;
$$;
revoke execute on function "better_supabase"."get_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."get_tag"(uuid) to authenticated, service_role;

-- The tags on one subject, for a caller who can read the tenant's tags and the subject.
create or replace function "better_supabase"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_tags"(uuid, text, text) to authenticated, service_role;

-- The tags on several subjects of one type, keyed by subject id, in one call.
-- Each subject goes through the same checks as subject_tags.
create or replace function "better_supabase"."subjects_tags"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "better_supabase"."subject_tags"(subjects_tags.tenant, subjects_tags.subject_type, s.id)), '{}'::jsonb)
  from (select distinct u as id from unnest(subjects_tags.subject_ids) u limit 200) s
$$;
revoke execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."tags" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."tags" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."tags" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."tags" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."taggings" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."taggings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."taggings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."taggings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.tags.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_tag"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "api"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "api"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tag"($1, $2, $3, $4) $$;
revoke execute on function "api"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."tag"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."update_tag"(tag_id uuid, name text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_tag"($1, $2) $$;
revoke execute on function "api"."update_tag"(uuid, text) from public, anon;
grant execute on function "api"."update_tag"(uuid, text) to authenticated, service_role;

create or replace function "api"."rank_tag"(tag_id uuid, rank text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_tag"($1, $2) $$;
revoke execute on function "api"."rank_tag"(uuid, text) from public, anon;
grant execute on function "api"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "api"."delete_tag"(tag_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_tag"($1) $$;
revoke execute on function "api"."delete_tag"(uuid) from public, anon;
grant execute on function "api"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "api"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."untag"($1, $2, $3, $4) $$;
revoke execute on function "api"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."untag"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_tags"($1, $2) $$;
revoke execute on function "api"."list_tags"(uuid, text) from public, anon;
grant execute on function "api"."list_tags"(uuid, text) to authenticated, service_role;

create or replace function "api"."page_tags"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_tags"($1, $2) $$;
revoke execute on function "api"."page_tags"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_tags"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_tag"(tag_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_tag"($1) $$;
revoke execute on function "api"."get_tag"(uuid) from public, anon;
grant execute on function "api"."get_tag"(uuid) to authenticated, service_role;

create or replace function "api"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_tags"($1, $2, $3) $$;
revoke execute on function "api"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "api"."subject_tags"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."subjects_tags"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."subjects_tags"($1, $2, $3) $$;
revoke execute on function "api"."subjects_tags"(uuid, text, text[]) from public, anon;
grant execute on function "api"."subjects_tags"(uuid, text, text[]) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:baa1d5b6721528e763808c231522383a33db513a6254d0a316c15c1087308cb6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block tags@2 managed
-- @bsb-hash sha256:15790c775ed6c56d53bb1cbb35e14b9b148d185102e10c5a974cedf24530686d
-- Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- better_supabase.tags is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."tags" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."tags" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."tags" add column if not exists "kind" text;
alter table "better_supabase"."tags" add column if not exists "name" text constraint bsb_tags_name_check check (length("name") >= 1 and length("name") <= 80);
alter table "better_supabase"."tags" add column if not exists "slug" text;
alter table "better_supabase"."tags" add column if not exists "color" text;
alter table "better_supabase"."tags" add column if not exists "description" text;
alter table "better_supabase"."tags" add column if not exists "rank" text collate "C" not null default 'V';
alter table "better_supabase"."tags" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."tags" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."tags" enable row level security;
grant select on "better_supabase"."tags" to authenticated;
grant all on "better_supabase"."tags" to service_role;
-- better_supabase.taggings is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."taggings" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."taggings" add column if not exists "tag_id" uuid references "better_supabase"."tags" ("id") on delete cascade;
alter table "better_supabase"."taggings" add column if not exists "subject_type" text;
alter table "better_supabase"."taggings" add column if not exists "subject_id" text;
alter table "better_supabase"."taggings" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "taggings_subject_idx" on "better_supabase"."taggings" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."taggings" enable row level security;
grant select on "better_supabase"."taggings" to authenticated;
grant all on "better_supabase"."taggings" to service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  select max(t."rank" collate "C") into v_last from "better_supabase"."tags" t
    where t."tenant_id" = create_tag.tenant and t."kind" = better_supabase.as_column_type(create_tag.kind, (null::"better_supabase"."tags")."kind");
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."tags" ("tenant_id", "kind", "name", "slug", "color", "description", "rank", "created_at")
  values (create_tag.tenant, better_supabase.as_column_type(create_tag.kind, (null::"better_supabase"."tags")."kind"), create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when '' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, better_supabase.as_column_type(tag.subject_type, (null::"better_supabase"."taggings")."subject_type"), tag.subject_id)
      on conflict do nothing;
  end case;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."tag"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."update_tag"(tag_id uuid, name text)
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
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = update_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" t set "name" = coalesce(update_tag.name, t."name"), "updated_at" = now() where t."id" = update_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."update_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."update_tag"(uuid, text) to authenticated, service_role;

-- Sets a tag's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_tag"(tag_id uuid, rank text)
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
  if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'TAG_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = rank_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" set "rank" = rank_tag.rank, "updated_at" = now() where "id" = rank_tag.tag_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_tag"(tag_id uuid)
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
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  delete from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = better_supabase.as_column_type(untag.subject_type, (null::"better_supabase"."taggings")."subject_type")
        and g."subject_id" = untag.subject_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."untag"(uuid, text, text, uuid) to authenticated, service_role;

-- The tenant's tags of one kind (every kind when it is null), in rank order.
create or replace function "better_supabase"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = list_tags.tenant
      and (list_tags.kind is null or t."kind" = better_supabase.as_column_type(list_tags.kind, (null::"better_supabase"."tags")."kind"))
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tags"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_tags"(uuid, text) to authenticated, service_role;

-- The tenant's tags as a keyset page, in rank order (ADR 1077). filters is
-- { kind (a value or a list), search (name, slug, description), sort (rank,
-- name, kind, createdAt), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "better_supabase"."page_tags"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_tags.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'TAG_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'kind', 'createdAt') then
    raise exception 'sort is one of rank, name, kind, createdAt' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text, lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."kind"::text asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text <= (v_after ->> 0)::text and ((x."kind"::text < (v_after ->> 0)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."kind"::text desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."tenant_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_tags"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_tags"(uuid, jsonb) to authenticated, service_role;

-- One tag, or null, for a caller who can read its tenant's tags.
create or replace function "better_supabase"."get_tag"(tag_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select t."tenant_id" into v_tenant from "better_supabase"."tags" t where t."id" = get_tag.tag_id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return (select jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") from "better_supabase"."tags" t where t."id" = get_tag.tag_id);
end;
$$;
revoke execute on function "better_supabase"."get_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."get_tag"(uuid) to authenticated, service_role;

-- The tags on one subject, for a caller who can read the tenant's tags and the subject.
create or replace function "better_supabase"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = better_supabase.as_column_type(subject_tags.subject_type, (null::"better_supabase"."taggings")."subject_type")
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_tags"(uuid, text, text) to authenticated, service_role;

-- The tags on several subjects of one type, keyed by subject id, in one call.
-- Each subject goes through the same checks as subject_tags.
create or replace function "better_supabase"."subjects_tags"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "better_supabase"."subject_tags"(subjects_tags.tenant, subjects_tags.subject_type, s.id)), '{}'::jsonb)
  from (select distinct u as id from unnest(subjects_tags.subject_ids) u limit 200) s
$$;
revoke execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."tags" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."tags" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."tags" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."tags" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."taggings" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."taggings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."taggings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."taggings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:baa1d5b6721528e763808c231522383a33db513a6254d0a316c15c1087308cb6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block tags@2 managed
-- @bsb-hash sha256:a20187605f9bec4ecba9313974635f11f1bfde05fd7dcbf2e2942f24e22e0b17
-- Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."tags" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "kind" text not null,
  "name" text not null constraint bsb_tags_name_check check (length("name") >= 1 and length("name") <= 80),
  "slug" text not null,
  "color" text,
  "description" text,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "kind", "slug")
);
alter table "better_supabase"."tags" enable row level security;
revoke all on "better_supabase"."tags" from public, anon, authenticated;
grant select on "better_supabase"."tags" to authenticated;
grant all on "better_supabase"."tags" to service_role;
create table "better_supabase"."taggings" (
  "org_id" uuid not null,
  "tag_id" uuid not null references "better_supabase"."tags" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("tag_id", "subject_type", "subject_id")
);
create index "taggings_subject_idx" on "better_supabase"."taggings" ("org_id", "subject_type", "subject_id");
alter table "better_supabase"."taggings" enable row level security;
revoke all on "better_supabase"."taggings" from public, anon, authenticated;
grant select on "better_supabase"."taggings" to authenticated;
grant all on "better_supabase"."taggings" to service_role;

-- fields: the extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  select max(t."rank" collate "C") into v_last from "better_supabase"."tags" t
    where t."org_id" = create_tag.tenant and t."kind" = create_tag.kind;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."tags" ("org_id", "kind", "name", "slug", "color", "description", "rank", "created_at")
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())
  returning "id" into v_id;
  null;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "org_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when '' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("org_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."tag"(uuid, text, text, uuid) to authenticated, service_role;
create or replace function "better_supabase"."update_tag"(tag_id uuid, name text)
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
  select "org_id" into v_tenant from "better_supabase"."tags" where "id" = update_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" t set "name" = coalesce(update_tag.name, t."name"), "updated_at" = now() where t."id" = update_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."update_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."update_tag"(uuid, text) to authenticated, service_role;

-- Sets a tag's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_tag"(tag_id uuid, rank text)
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
  if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'TAG_RANK_INVALID';
  end if;
  select "org_id" into v_tenant from "better_supabase"."tags" where "id" = rank_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" set "rank" = rank_tag.rank, "updated_at" = now() where "id" = rank_tag.tag_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_tag"(tag_id uuid)
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
  select "org_id" into v_tenant from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  delete from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."org_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."untag"(uuid, text, text, uuid) to authenticated, service_role;

-- The tenant's tags of one kind (every kind when it is null), in rank order.
create or replace function "better_supabase"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."org_id" = list_tags.tenant
      and (list_tags.kind is null or t."kind" = list_tags.kind)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tags"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_tags"(uuid, text) to authenticated, service_role;

-- The tenant's tags as a keyset page, in rank order (ADR 1077). filters is
-- { kind (a value or a list), search (name, slug, description), sort (rank,
-- name, kind, createdAt), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "better_supabase"."page_tags"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_tags.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', page_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'TAG_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('rank', 'name', 'kind', 'createdAt') then
    raise exception 'sort is one of rank, name, kind, createdAt' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."rank" collate "C" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."rank" collate "C")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."rank" collate "C" <= (v_after ->> 0)::text and ((x."rank" collate "C" < (v_after ->> 0)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."rank" collate "C" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."rank" collate "C" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text, lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."kind"::text asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'kind' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."kind"::text)::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."kind"::text <= (v_after ->> 0)::text and ((x."kind"::text < (v_after ->> 0)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."kind"::text = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."kind"::text desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'kind', x."kind", 'name', x."name", 'slug', x."slug", 'color', x."color", 'description', x."description", 'rank', x."rank") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
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
      select 1 from "better_supabase"."tags" x
      where x."org_id" = page_tags.tenant
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_tags"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_tags"(uuid, jsonb) to authenticated, service_role;

-- One tag, or null, for a caller who can read its tenant's tags.
create or replace function "better_supabase"."get_tag"(tag_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select t."org_id" into v_tenant from "better_supabase"."tags" t where t."id" = get_tag.tag_id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return (select jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") from "better_supabase"."tags" t where t."id" = get_tag.tag_id);
end;
$$;
revoke execute on function "better_supabase"."get_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."get_tag"(uuid) to authenticated, service_role;

-- The tags on one subject, for a caller who can read the tenant's tags and the subject.
create or replace function "better_supabase"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."org_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."org_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_tags"(uuid, text, text) to authenticated, service_role;

-- The tags on several subjects of one type, keyed by subject id, in one call.
-- Each subject goes through the same checks as subject_tags.
create or replace function "better_supabase"."subjects_tags"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "better_supabase"."subject_tags"(subjects_tags.tenant, subjects_tags.subject_type, s.id)), '{}'::jsonb)
  from (select distinct u as id from unnest(subjects_tags.subject_ids) u limit 200) s
$$;
revoke execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."subjects_tags"(uuid, text, text[]) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."tags" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."tags" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."tags" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."tags" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."taggings" as restrictive
  for select to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."taggings" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."taggings" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."taggings" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:baa1d5b6721528e763808c231522383a33db513a6254d0a316c15c1087308cb6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
