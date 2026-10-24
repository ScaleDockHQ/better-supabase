-- ==== alone: schema supabase/schemas/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block search@2 managed
-- @bsb-hash sha256:aa4a66c85fca2ff9cba92cbe2b18e76b64720f44bd6072484f2e07f6b635b359
-- A search_documents index kept up by triggers from each config.records search entry, with search(q) as the caller (websearch, trigram prefixes, can_subject, hybrid with embeddings), and recents and favorites from the share-links user state.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."search_documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create table if not exists "better_supabase"."search_documents" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "title" text,
  "title_search" text not null default '',
  "body" text,
  "url" text,
  "tsv" tsvector not null,
  "content_hash" text not null,
  "updated_at" timestamptz not null default now(),
  primary key ("subject_type", "subject_id")
);
alter table "better_supabase"."search_documents" enable row level security;
revoke all on "better_supabase"."search_documents" from anon, authenticated;
grant select on "better_supabase"."search_documents" to authenticated;
grant all on "better_supabase"."search_documents" to service_role;
create index if not exists search_documents_tsv_idx on "better_supabase"."search_documents" using gin ("tsv");
create index if not exists search_documents_title_trgm_idx on "better_supabase"."search_documents" using gin ("title_search" extensions.gin_trgm_ops);
create index if not exists search_documents_tenant_idx on "better_supabase"."search_documents" ("tenant_id", "subject_type");

drop policy if exists "search_documents_read" on "better_supabase"."search_documents";
create policy "search_documents_read" on "better_supabase"."search_documents" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')));

-- Lowercase and without accents. unaccent is stable because its dictionary
-- can change; pinning the dictionary makes this safe to index.
create or replace function "better_supabase"."search_normalize"(value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, '')))
$$;
revoke execute on function "better_supabase"."search_normalize"(text) from public, anon;
grant execute on function "better_supabase"."search_normalize"(text) to authenticated, service_role;

-- Reads one registered subject row (config.subjects.<type>.search) into the
-- index, or drops it when the row is gone or soft-deleted (deletedAt).
create or replace function "better_supabase"."search_refresh"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when '' then null;
    else
      raise exception 'this subject type has no search entry in config.records' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now();
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_refresh"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_refresh"(text, text) to service_role;

-- Drops a subject from the index, for a soft delete the registry doesn't
-- describe (the trash block's subject.trashed, through searchSink).
create or replace function "better_supabase"."search_remove"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."search_documents"
  where "subject_type" = search_remove.subject_type and "subject_id" = search_remove.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."search_remove"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_remove"(text, text) to service_role;

-- Indexes every row of one registered type, or of all of them.
create or replace function "better_supabase"."search_reindex"(subject_type text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_id text;
begin
  null;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."search_reindex"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_reindex"(text) to service_role;

create or replace function "better_supabase"."search_index_row"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_new);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."search_index_row"() from public, anon, authenticated;



-- Full-text and trigram matches (plus nearest embeddings when the query
-- carries one, fused by reciprocal rank), as the caller: the policy keeps
-- the caller's tenants and can_subject drops what they can't read, trashed
-- rows included.
create or replace function "better_supabase"."search"(q text, types text[] default null, tenant uuid default null, max_results integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := "better_supabase"."search_normalize"(v_q);
  v_web := websearch_to_tsquery('simple', v_norm);
  select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d."subject_type" as subject_type, d."subject_id" as subject_id,
          2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
            + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
            + extensions.similarity(d."title_search", v_norm) as score
        from "better_supabase"."search_documents" d
        where (search.types is null or d."subject_type" = any (search.types))
          and (search.tenant is null or d."tenant_id" = search.tenant)
          and (d."tsv" @@ v_web
            or (v_prefix is not null and d."tsv" @@ v_prefix)
            or d."title_search" operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    ),
    visible as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
        d."title" as title, d."url" as url, d."body" as body, f.score
      from fused f
      join "better_supabase"."search_documents" d on d."subject_type" = f.subject_type and d."subject_id" = f.subject_id
      where "better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,
      'snippet', case when v.body is null then null
        else ts_headline('simple', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."search"(text, text[], uuid, integer) from public, anon;
grant execute on function "better_supabase"."search"(text, text[], uuid, integer) to authenticated, service_role;

-- The caller's own rows of the share-links per-user state. The lists below
-- run as the caller, so can_subject sees what they can read.
create or replace function "better_supabase"."search_user_state"()
returns table (subject_type text, subject_id text, starred_at timestamptz, opened_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select null::text, null::text, null::timestamptz, null::timestamptz where false
$$;
revoke execute on function "better_supabase"."search_user_state"() from public, anon;
grant execute on function "better_supabase"."search_user_state"() to authenticated, service_role;

create or replace function "better_supabase"."search_recents"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.opened_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.opened_at is not null
      and (search_recents.types is null or s.subject_type = any (search_recents.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.opened_at desc
    limit least(greatest(coalesce(search_recents.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_recents"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_recents"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_favorites"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.starred_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.starred_at is not null
      and (search_favorites.types is null or s.subject_type = any (search_favorites.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.starred_at desc
    limit least(greatest(coalesce(search_favorites.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_favorites"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_favorites"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_touch"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep recents' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$$;
revoke execute on function "better_supabase"."search_touch"(text, text) from public, anon;
grant execute on function "better_supabase"."search_touch"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."search_star"(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep favorites' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$$;
revoke execute on function "better_supabase"."search_star"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."search_star"(text, text, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."search_documents";
create policy bsb_tenant_scope on "better_supabase"."search_documents" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block-data search
-- @bsb-hash sha256:e45560981b9f8ba0017c9dd99e94102d44f5e85172772f3cc1bc772aa7b170f9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_trgm" with schema "extensions";
create extension if not exists "unaccent" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('search', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block search@2 managed
-- @bsb-hash sha256:cd45b193c629d6111b90b689b5342190dcad8f0760d4166fd7841730703f4779
-- A search_documents index kept up by triggers from each config.records search entry, with search(q) as the caller (websearch, trigram prefixes, can_subject, hybrid with embeddings), and recents and favorites from the share-links user state.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."search_documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create table if not exists "better_supabase"."search_documents" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "title" text,
  "title_search" text not null default '',
  "body" text,
  "url" text,
  "tsv" tsvector not null,
  "content_hash" text not null,
  "updated_at" timestamptz not null default now(),
  primary key ("subject_type", "subject_id")
);
alter table "better_supabase"."search_documents" enable row level security;
revoke all on "better_supabase"."search_documents" from anon, authenticated;
grant select on "better_supabase"."search_documents" to authenticated;
grant all on "better_supabase"."search_documents" to service_role;
create index if not exists search_documents_tsv_idx on "better_supabase"."search_documents" using gin ("tsv");
create index if not exists search_documents_title_trgm_idx on "better_supabase"."search_documents" using gin ("title_search" extensions.gin_trgm_ops);
create index if not exists search_documents_tenant_idx on "better_supabase"."search_documents" ("tenant_id", "subject_type");

drop policy if exists "search_documents_read" on "better_supabase"."search_documents";
create policy "search_documents_read" on "better_supabase"."search_documents" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')));

-- Lowercase and without accents. unaccent is stable because its dictionary
-- can change; pinning the dictionary makes this safe to index.
create or replace function "better_supabase"."search_normalize"(value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, '')))
$$;
revoke execute on function "better_supabase"."search_normalize"(text) from public, anon;
grant execute on function "better_supabase"."search_normalize"(text) to authenticated, service_role;

-- Reads one registered subject row (config.subjects.<type>.search) into the
-- index, or drops it when the row is gone or soft-deleted (deletedAt).
create or replace function "better_supabase"."search_refresh"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when '' then null;
    else
      raise exception 'this subject type has no search entry in config.records' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now();
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_refresh"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_refresh"(text, text) to service_role;

-- Drops a subject from the index, for a soft delete the registry doesn't
-- describe (the trash block's subject.trashed, through searchSink).
create or replace function "better_supabase"."search_remove"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."search_documents"
  where "subject_type" = search_remove.subject_type and "subject_id" = search_remove.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."search_remove"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_remove"(text, text) to service_role;

-- Indexes every row of one registered type, or of all of them.
create or replace function "better_supabase"."search_reindex"(subject_type text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_id text;
begin
  null;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."search_reindex"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_reindex"(text) to service_role;

create or replace function "better_supabase"."search_index_row"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_new);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."search_index_row"() from public, anon, authenticated;



-- Full-text and trigram matches (plus nearest embeddings when the query
-- carries one, fused by reciprocal rank), as the caller: the policy keeps
-- the caller's tenants and can_subject drops what they can't read, trashed
-- rows included.
create or replace function "better_supabase"."search"(q text, types text[] default null, tenant uuid default null, max_results integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := "better_supabase"."search_normalize"(v_q);
  v_web := websearch_to_tsquery('simple', v_norm);
  select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d."subject_type" as subject_type, d."subject_id" as subject_id,
          2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
            + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
            + extensions.similarity(d."title_search", v_norm) as score
        from "better_supabase"."search_documents" d
        where (search.types is null or d."subject_type" = any (search.types))
          and (search.tenant is null or d."tenant_id" = search.tenant)
          and (d."tsv" @@ v_web
            or (v_prefix is not null and d."tsv" @@ v_prefix)
            or d."title_search" operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    ),
    visible as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
        d."title" as title, d."url" as url, d."body" as body, f.score
      from fused f
      join "better_supabase"."search_documents" d on d."subject_type" = f.subject_type and d."subject_id" = f.subject_id
      where "better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,
      'snippet', case when v.body is null then null
        else ts_headline('simple', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."search"(text, text[], uuid, integer) from public, anon;
grant execute on function "better_supabase"."search"(text, text[], uuid, integer) to authenticated, service_role;

-- The caller's own rows of the share-links per-user state. The lists below
-- run as the caller, so can_subject sees what they can read.
create or replace function "better_supabase"."search_user_state"()
returns table (subject_type text, subject_id text, starred_at timestamptz, opened_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select s."subject_type", s."subject_id", s."starred_at", s."last_opened_at"
  from "better_supabase"."subject_user_state" s
  where s."user_id" = auth.uid()
$$;
revoke execute on function "better_supabase"."search_user_state"() from public, anon;
grant execute on function "better_supabase"."search_user_state"() to authenticated, service_role;

create or replace function "better_supabase"."search_recents"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.opened_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.opened_at is not null
      and (search_recents.types is null or s.subject_type = any (search_recents.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.opened_at desc
    limit least(greatest(coalesce(search_recents.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_recents"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_recents"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_favorites"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.starred_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.starred_at is not null
      and (search_favorites.types is null or s.subject_type = any (search_favorites.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.starred_at desc
    limit least(greatest(coalesce(search_favorites.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_favorites"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_favorites"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_touch"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to keep recents' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  insert into "better_supabase"."subject_user_state" as st ("subject_type", "subject_id", "user_id", "last_opened_at") values (search_touch.subject_type, search_touch.subject_id, auth.uid(), now())
  on conflict ("subject_type", "subject_id", "user_id") do update set "last_opened_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_touch"(text, text) from public, anon;
grant execute on function "better_supabase"."search_touch"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."search_star"(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to keep favorites' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  insert into "better_supabase"."subject_user_state" as st ("subject_type", "subject_id", "user_id", "starred_at") values (search_star.subject_type, search_star.subject_id, auth.uid(), case when search_star.starred then now() end)
  on conflict ("subject_type", "subject_id", "user_id") do update set "starred_at" = case when search_star.starred then coalesce(st."starred_at", now()) end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_star"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."search_star"(text, text, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."search_documents";
create policy bsb_tenant_scope on "better_supabase"."search_documents" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block-data search
-- @bsb-hash sha256:e45560981b9f8ba0017c9dd99e94102d44f5e85172772f3cc1bc772aa7b170f9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_trgm" with schema "extensions";
create extension if not exists "unaccent" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('search', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block search@2 managed
-- @bsb-hash sha256:8945b07fc3dbd5ac38cfc7fd35d6130a4658b95918b5eb26b42c5e05e75c26a6
-- A search_documents index kept up by triggers from each config.records search entry, with search(q) as the caller (websearch, trigram prefixes, can_subject, hybrid with embeddings), and recents and favorites from the share-links user state.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."search_documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create table if not exists "app_private"."search_documents" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "title" text,
  "title_search" text not null default '',
  "body" text,
  "url" text,
  "tsv" tsvector not null,
  "content_hash" text not null,
  "updated_at" timestamptz not null default now(),
  primary key ("subject_type", "subject_id")
);
alter table "app_private"."search_documents" enable row level security;
revoke all on "app_private"."search_documents" from anon, authenticated;
grant select on "app_private"."search_documents" to authenticated;
grant all on "app_private"."search_documents" to service_role;
create index if not exists search_documents_tsv_idx on "app_private"."search_documents" using gin ("tsv");
create index if not exists search_documents_title_trgm_idx on "app_private"."search_documents" using gin ("title_search" extensions.gin_trgm_ops);
create index if not exists search_documents_tenant_idx on "app_private"."search_documents" ("tenant_id", "subject_type");

drop policy if exists "search_documents_read" on "app_private"."search_documents";
create policy "search_documents_read" on "app_private"."search_documents" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')));

-- Lowercase and without accents. unaccent is stable because its dictionary
-- can change; pinning the dictionary makes this safe to index.
create or replace function "app_private"."search_normalize"(value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, '')))
$$;
revoke execute on function "app_private"."search_normalize"(text) from public, anon;
grant execute on function "app_private"."search_normalize"(text) to authenticated, service_role;

-- Reads one registered subject row (config.subjects.<type>.search) into the
-- index, or drops it when the row is gone or soft-deleted (deletedAt).
create or replace function "app_private"."search_refresh"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when '' then null;
    else
      raise exception 'this subject type has no search entry in config.records' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "app_private"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "app_private"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "app_private"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "app_private"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "app_private"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now();
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "app_private"."search_refresh"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."search_refresh"(text, text) to service_role;

-- Drops a subject from the index, for a soft delete the registry doesn't
-- describe (the trash block's subject.trashed, through searchSink).
create or replace function "app_private"."search_remove"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "app_private"."search_documents"
  where "subject_type" = search_remove.subject_type and "subject_id" = search_remove.subject_id;
  return found;
end;
$$;
revoke execute on function "app_private"."search_remove"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."search_remove"(text, text) to service_role;

-- Indexes every row of one registered type, or of all of them.
create or replace function "app_private"."search_reindex"(subject_type text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_id text;
begin
  null;
  return v_count;
end;
$$;
revoke execute on function "app_private"."search_reindex"(text) from public, anon, authenticated;
grant execute on function "app_private"."search_reindex"(text) to service_role;

create or replace function "app_private"."search_index_row"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform "app_private"."search_refresh"(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform "app_private"."search_refresh"(tg_argv[0], v_new);
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."search_index_row"() from public, anon, authenticated;



-- Full-text and trigram matches (plus nearest embeddings when the query
-- carries one, fused by reciprocal rank), as the caller: the policy keeps
-- the caller's tenants and can_subject drops what they can't read, trashed
-- rows included.
create or replace function "app_private"."search"(q text, types text[] default null, tenant uuid default null, max_results integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := "app_private"."search_normalize"(v_q);
  v_web := websearch_to_tsquery('simple', v_norm);
  select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d."subject_type" as subject_type, d."subject_id" as subject_id,
          2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
            + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
            + extensions.similarity(d."title_search", v_norm) as score
        from "app_private"."search_documents" d
        where (search.types is null or d."subject_type" = any (search.types))
          and (search.tenant is null or d."tenant_id" = search.tenant)
          and (d."tsv" @@ v_web
            or (v_prefix is not null and d."tsv" @@ v_prefix)
            or d."title_search" operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    ),
    visible as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
        d."title" as title, d."url" as url, d."body" as body, f.score
      from fused f
      join "app_private"."search_documents" d on d."subject_type" = f.subject_type and d."subject_id" = f.subject_id
      where "better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,
      'snippet', case when v.body is null then null
        else ts_headline('simple', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."search"(text, text[], uuid, integer) from public, anon;
grant execute on function "app_private"."search"(text, text[], uuid, integer) to authenticated, service_role;

-- The caller's own rows of the share-links per-user state. The lists below
-- run as the caller, so can_subject sees what they can read.
create or replace function "app_private"."search_user_state"()
returns table (subject_type text, subject_id text, starred_at timestamptz, opened_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select null::text, null::text, null::timestamptz, null::timestamptz where false
$$;
revoke execute on function "app_private"."search_user_state"() from public, anon;
grant execute on function "app_private"."search_user_state"() to authenticated, service_role;

create or replace function "app_private"."search_recents"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.opened_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "app_private"."search_user_state"() s
    where s.opened_at is not null
      and (search_recents.types is null or s.subject_type = any (search_recents.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.opened_at desc
    limit least(greatest(coalesce(search_recents.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "app_private"."search_recents"(integer, text[]) from public, anon;
grant execute on function "app_private"."search_recents"(integer, text[]) to authenticated, service_role;

create or replace function "app_private"."search_favorites"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.starred_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "app_private"."search_user_state"() s
    where s.starred_at is not null
      and (search_favorites.types is null or s.subject_type = any (search_favorites.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.starred_at desc
    limit least(greatest(coalesce(search_favorites.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "app_private"."search_favorites"(integer, text[]) from public, anon;
grant execute on function "app_private"."search_favorites"(integer, text[]) to authenticated, service_role;

create or replace function "app_private"."search_touch"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep recents' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$$;
revoke execute on function "app_private"."search_touch"(text, text) from public, anon;
grant execute on function "app_private"."search_touch"(text, text) to authenticated, service_role;

create or replace function "app_private"."search_star"(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep favorites' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$$;
revoke execute on function "app_private"."search_star"(text, text, boolean) from public, anon;
grant execute on function "app_private"."search_star"(text, text, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."search_documents";
create policy bsb_tenant_scope on "app_private"."search_documents" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block-data search
-- @bsb-hash sha256:e45560981b9f8ba0017c9dd99e94102d44f5e85172772f3cc1bc772aa7b170f9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_trgm" with schema "extensions";
create extension if not exists "unaccent" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('search', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block search@2 managed
-- @bsb-hash sha256:c2a8c48b647a6830f15282de3411339a7e163bac4c174f22c4dd3e261a16334a
-- A search_documents index kept up by triggers from each config.records search entry, with search(q) as the caller (websearch, trigram prefixes, can_subject, hybrid with embeddings), and recents and favorites from the share-links user state.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."search_documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create table if not exists "better_supabase"."search_documents" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "title" text,
  "title_search" text not null default '',
  "body" text,
  "url" text,
  "tsv" tsvector not null,
  "content_hash" text not null,
  "updated_at" timestamptz not null default now(),
  primary key ("subject_type", "subject_id")
);
alter table "better_supabase"."search_documents" enable row level security;
revoke all on "better_supabase"."search_documents" from anon, authenticated;
grant select on "better_supabase"."search_documents" to authenticated;
grant all on "better_supabase"."search_documents" to service_role;
create index if not exists search_documents_tsv_idx on "better_supabase"."search_documents" using gin ("tsv");
create index if not exists search_documents_title_trgm_idx on "better_supabase"."search_documents" using gin ("title_search" extensions.gin_trgm_ops);
create index if not exists search_documents_tenant_idx on "better_supabase"."search_documents" ("tenant_id", "subject_type");

drop policy if exists "search_documents_read" on "better_supabase"."search_documents";
create policy "search_documents_read" on "better_supabase"."search_documents" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')));

-- Lowercase and without accents. unaccent is stable because its dictionary
-- can change; pinning the dictionary makes this safe to index.
create or replace function "better_supabase"."search_normalize"(value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, '')))
$$;
revoke execute on function "better_supabase"."search_normalize"(text) from public, anon;
grant execute on function "better_supabase"."search_normalize"(text) to authenticated, service_role;

-- Reads one registered subject row (config.subjects.<type>.search) into the
-- index, or drops it when the row is gone or soft-deleted (deletedAt).
create or replace function "better_supabase"."search_refresh"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when '' then null;
    else
      raise exception 'this subject type has no search entry in config.records' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now();
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_refresh"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_refresh"(text, text) to service_role;

-- Drops a subject from the index, for a soft delete the registry doesn't
-- describe (the trash block's subject.trashed, through searchSink).
create or replace function "better_supabase"."search_remove"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."search_documents"
  where "subject_type" = search_remove.subject_type and "subject_id" = search_remove.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."search_remove"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_remove"(text, text) to service_role;

-- Indexes every row of one registered type, or of all of them.
create or replace function "better_supabase"."search_reindex"(subject_type text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_id text;
begin
  null;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."search_reindex"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_reindex"(text) to service_role;

create or replace function "better_supabase"."search_index_row"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_new);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."search_index_row"() from public, anon, authenticated;



-- Full-text and trigram matches (plus nearest embeddings when the query
-- carries one, fused by reciprocal rank), as the caller: the policy keeps
-- the caller's tenants and can_subject drops what they can't read, trashed
-- rows included.
create or replace function "better_supabase"."search"(q text, types text[] default null, tenant uuid default null, max_results integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := "better_supabase"."search_normalize"(v_q);
  v_web := websearch_to_tsquery('simple', v_norm);
  select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d."subject_type" as subject_type, d."subject_id" as subject_id,
          2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
            + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
            + extensions.similarity(d."title_search", v_norm) as score
        from "better_supabase"."search_documents" d
        where (search.types is null or d."subject_type" = any (search.types))
          and (search.tenant is null or d."tenant_id" = search.tenant)
          and (d."tsv" @@ v_web
            or (v_prefix is not null and d."tsv" @@ v_prefix)
            or d."title_search" operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    ),
    visible as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
        d."title" as title, d."url" as url, d."body" as body, f.score
      from fused f
      join "better_supabase"."search_documents" d on d."subject_type" = f.subject_type and d."subject_id" = f.subject_id
      where "better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,
      'snippet', case when v.body is null then null
        else ts_headline('simple', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."search"(text, text[], uuid, integer) from public, anon;
grant execute on function "better_supabase"."search"(text, text[], uuid, integer) to authenticated, service_role;

-- The caller's own rows of the share-links per-user state. The lists below
-- run as the caller, so can_subject sees what they can read.
create or replace function "better_supabase"."search_user_state"()
returns table (subject_type text, subject_id text, starred_at timestamptz, opened_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select null::text, null::text, null::timestamptz, null::timestamptz where false
$$;
revoke execute on function "better_supabase"."search_user_state"() from public, anon;
grant execute on function "better_supabase"."search_user_state"() to authenticated, service_role;

create or replace function "better_supabase"."search_recents"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.opened_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.opened_at is not null
      and (search_recents.types is null or s.subject_type = any (search_recents.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.opened_at desc
    limit least(greatest(coalesce(search_recents.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_recents"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_recents"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_favorites"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.starred_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.starred_at is not null
      and (search_favorites.types is null or s.subject_type = any (search_favorites.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.starred_at desc
    limit least(greatest(coalesce(search_favorites.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_favorites"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_favorites"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_touch"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep recents' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$$;
revoke execute on function "better_supabase"."search_touch"(text, text) from public, anon;
grant execute on function "better_supabase"."search_touch"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."search_star"(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep favorites' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$$;
revoke execute on function "better_supabase"."search_star"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."search_star"(text, text, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."search_documents";
create policy bsb_tenant_scope on "better_supabase"."search_documents" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.search.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."search_normalize"(text);
drop function if exists "api"."search_user_state"();

create or replace function "api"."search_refresh"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_refresh"($1, $2) $$;
revoke execute on function "api"."search_refresh"(text, text) from public, anon, authenticated;
grant execute on function "api"."search_refresh"(text, text) to service_role;

create or replace function "api"."search_remove"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_remove"($1, $2) $$;
revoke execute on function "api"."search_remove"(text, text) from public, anon, authenticated;
grant execute on function "api"."search_remove"(text, text) to service_role;

create or replace function "api"."search_reindex"(subject_type text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_reindex"($1) $$;
revoke execute on function "api"."search_reindex"(text) from public, anon, authenticated;
grant execute on function "api"."search_reindex"(text) to service_role;

create or replace function "api"."search"(q text, types text[] default null, tenant uuid default null, max_results integer default 20)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search"($1, $2, $3, $4) $$;
revoke execute on function "api"."search"(text, text[], uuid, integer) from public, anon;
grant execute on function "api"."search"(text, text[], uuid, integer) to authenticated, service_role;

create or replace function "api"."search_recents"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_recents"($1, $2) $$;
revoke execute on function "api"."search_recents"(integer, text[]) from public, anon;
grant execute on function "api"."search_recents"(integer, text[]) to authenticated, service_role;

create or replace function "api"."search_favorites"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_favorites"($1, $2) $$;
revoke execute on function "api"."search_favorites"(integer, text[]) from public, anon;
grant execute on function "api"."search_favorites"(integer, text[]) to authenticated, service_role;

create or replace function "api"."search_touch"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_touch"($1, $2) $$;
revoke execute on function "api"."search_touch"(text, text) from public, anon;
grant execute on function "api"."search_touch"(text, text) to authenticated, service_role;

create or replace function "api"."search_star"(subject_type text, subject_id text, starred boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_star"($1, $2, $3) $$;
revoke execute on function "api"."search_star"(text, text, boolean) from public, anon;
grant execute on function "api"."search_star"(text, text, boolean) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block-data search
-- @bsb-hash sha256:e45560981b9f8ba0017c9dd99e94102d44f5e85172772f3cc1bc772aa7b170f9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_trgm" with schema "extensions";
create extension if not exists "unaccent" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('search', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block search@2 managed
-- @bsb-hash sha256:08dedf1f5497ec6056d28fc22a215e66b1ef8dc5ed6daa1c1e3e844434221fca
-- A search_documents index kept up by triggers from each config.records search entry, with search(q) as the caller (websearch, trigram prefixes, can_subject, hybrid with embeddings), and recents and favorites from the share-links user state.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."search_documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
-- better_supabase.search_documents is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."search_documents" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."search_documents" add column if not exists "subject_type" text;
alter table "better_supabase"."search_documents" add column if not exists "subject_id" text;
alter table "better_supabase"."search_documents" add column if not exists "title" text;
alter table "better_supabase"."search_documents" add column if not exists "title_search" text not null default '';
alter table "better_supabase"."search_documents" add column if not exists "body" text;
alter table "better_supabase"."search_documents" add column if not exists "url" text;
alter table "better_supabase"."search_documents" add column if not exists "tsv" tsvector;
alter table "better_supabase"."search_documents" add column if not exists "content_hash" text;
alter table "better_supabase"."search_documents" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."search_documents" enable row level security;
grant select on "better_supabase"."search_documents" to authenticated;
grant all on "better_supabase"."search_documents" to service_role;
create index if not exists search_documents_tsv_idx on "better_supabase"."search_documents" using gin ("tsv");
create index if not exists search_documents_title_trgm_idx on "better_supabase"."search_documents" using gin ("title_search" extensions.gin_trgm_ops);
create index if not exists search_documents_tenant_idx on "better_supabase"."search_documents" ("tenant_id", "subject_type");

drop policy if exists bsb_search_documents_select on "better_supabase"."search_documents";
create policy bsb_search_documents_select on "better_supabase"."search_documents" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')));

-- Lowercase and without accents. unaccent is stable because its dictionary
-- can change; pinning the dictionary makes this safe to index.
create or replace function "better_supabase"."search_normalize"(value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, '')))
$$;
revoke execute on function "better_supabase"."search_normalize"(text) from public, anon;
grant execute on function "better_supabase"."search_normalize"(text) to authenticated, service_role;

-- Reads one registered subject row (config.subjects.<type>.search) into the
-- index, or drops it when the row is gone or soft-deleted (deletedAt).
create or replace function "better_supabase"."search_refresh"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when '' then null;
    else
      raise exception 'this subject type has no search entry in config.records' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now();
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_refresh"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_refresh"(text, text) to service_role;

-- Drops a subject from the index, for a soft delete the registry doesn't
-- describe (the trash block's subject.trashed, through searchSink).
create or replace function "better_supabase"."search_remove"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."search_documents"
  where "subject_type" = search_remove.subject_type and "subject_id" = search_remove.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."search_remove"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_remove"(text, text) to service_role;

-- Indexes every row of one registered type, or of all of them.
create or replace function "better_supabase"."search_reindex"(subject_type text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_id text;
begin
  null;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."search_reindex"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_reindex"(text) to service_role;

create or replace function "better_supabase"."search_index_row"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform "better_supabase"."search_refresh"(tg_argv[0], v_new);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."search_index_row"() from public, anon, authenticated;



-- Full-text and trigram matches (plus nearest embeddings when the query
-- carries one, fused by reciprocal rank), as the caller: the policy keeps
-- the caller's tenants and can_subject drops what they can't read, trashed
-- rows included.
create or replace function "better_supabase"."search"(q text, types text[] default null, tenant uuid default null, max_results integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := "better_supabase"."search_normalize"(v_q);
  v_web := websearch_to_tsquery('simple', v_norm);
  select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d."subject_type" as subject_type, d."subject_id" as subject_id,
          2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
            + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
            + extensions.similarity(d."title_search", v_norm) as score
        from "better_supabase"."search_documents" d
        where (search.types is null or d."subject_type" = any (search.types))
          and (search.tenant is null or d."tenant_id" = search.tenant)
          and (d."tsv" @@ v_web
            or (v_prefix is not null and d."tsv" @@ v_prefix)
            or d."title_search" operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    ),
    visible as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
        d."title" as title, d."url" as url, d."body" as body, f.score
      from fused f
      join "better_supabase"."search_documents" d on d."subject_type" = f.subject_type and d."subject_id" = f.subject_id
      where "better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,
      'snippet', case when v.body is null then null
        else ts_headline('simple', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."search"(text, text[], uuid, integer) from public, anon;
grant execute on function "better_supabase"."search"(text, text[], uuid, integer) to authenticated, service_role;

-- The caller's own rows of the share-links per-user state. The lists below
-- run as the caller, so can_subject sees what they can read.
create or replace function "better_supabase"."search_user_state"()
returns table (subject_type text, subject_id text, starred_at timestamptz, opened_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select null::text, null::text, null::timestamptz, null::timestamptz where false
$$;
revoke execute on function "better_supabase"."search_user_state"() from public, anon;
grant execute on function "better_supabase"."search_user_state"() to authenticated, service_role;

create or replace function "better_supabase"."search_recents"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.opened_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.opened_at is not null
      and (search_recents.types is null or s.subject_type = any (search_recents.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.opened_at desc
    limit least(greatest(coalesce(search_recents.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_recents"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_recents"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_favorites"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.starred_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.starred_at is not null
      and (search_favorites.types is null or s.subject_type = any (search_favorites.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.starred_at desc
    limit least(greatest(coalesce(search_favorites.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_favorites"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_favorites"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_touch"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep recents' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$$;
revoke execute on function "better_supabase"."search_touch"(text, text) from public, anon;
grant execute on function "better_supabase"."search_touch"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."search_star"(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'sign in to keep favorites' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  return false;
end;
$$;
revoke execute on function "better_supabase"."search_star"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."search_star"(text, text, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."search_documents";
create policy bsb_tenant_scope on "better_supabase"."search_documents" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_070_search.sql
-- better-supabase module: search
-- @bsb-block-data search
-- @bsb-hash sha256:e45560981b9f8ba0017c9dd99e94102d44f5e85172772f3cc1bc772aa7b170f9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pg_trgm" with schema "extensions";
create extension if not exists "unaccent" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('search', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
