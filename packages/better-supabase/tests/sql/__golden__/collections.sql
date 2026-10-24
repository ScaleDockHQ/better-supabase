-- ==== alone: schema supabase/schemas/900_better_supabase_103_collections.sql
-- better-supabase module: collections
-- @bsb-block collections@1 managed
-- @bsb-hash sha256:9f725d477a0e322555604e3ad81072194b81958ee88395746dfc1082357dd9d4
-- Favorites (a member's ranked stars on any registered record), lists (named, static collections of one subject type owned by a user, a team or the organization) and saved items (a member's records to come back to, with a note and a reminder), with entries hidden unless the caller can read their record.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collections";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collection_entries";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."favorites";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."saved_items";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Favorites (a member's starred records, ranked for a sidebar), lists (named,
-- static collections of one subject type) and saved items (a member's records
-- to come back to, with a reminder) on config.records records.

create table if not exists "better_supabase"."subject_collections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope" text not null default 'user' check ("scope" in ('user', 'team', 'tenant')),
  "owner_id" uuid references auth.users (id) on delete cascade,
  "team_id" text,
  "name" text not null check (length("name") between 1 and 120),
  "description" text check (length("description") <= 2000),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("scope" <> 'user' or "owner_id" is not null),
  check ("scope" <> 'team' or "team_id" is not null)
);
create index if not exists subject_collections_tenant_type_idx on "better_supabase"."subject_collections" ("tenant_id", "subject_type", lower("name"));
create index if not exists subject_collections_owner_idx on "better_supabase"."subject_collections" ("owner_id") where "owner_id" is not null;
alter table "better_supabase"."subject_collections" enable row level security;
revoke all on "better_supabase"."subject_collections" from anon, authenticated;
grant select on "better_supabase"."subject_collections" to authenticated;
grant all on "better_supabase"."subject_collections" to service_role;

create table if not exists "better_supabase"."subject_collection_entries" (
  "collection_id" uuid not null references "better_supabase"."subject_collections" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "rank" text collate "C" not null,
  "added_by" uuid,
  "added_at" timestamptz not null default now(),
  primary key ("collection_id", "subject_id")
);
create index if not exists subject_collection_entries_rank_idx on "better_supabase"."subject_collection_entries" ("collection_id", "rank", "subject_id");
create index if not exists subject_collection_entries_subject_idx on "better_supabase"."subject_collection_entries" ("subject_type", "subject_id");
alter table "better_supabase"."subject_collection_entries" enable row level security;
revoke all on "better_supabase"."subject_collection_entries" from anon, authenticated;
grant select on "better_supabase"."subject_collection_entries" to authenticated;
grant all on "better_supabase"."subject_collection_entries" to service_role;

create table if not exists "better_supabase"."favorites" (
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "rank" text collate "C" not null,
  "created_at" timestamptz not null default now(),
  primary key ("user_id", "subject_type", "subject_id")
);
create index if not exists favorites_user_rank_idx on "better_supabase"."favorites" ("user_id", "tenant_id", "rank");
create index if not exists favorites_subject_idx on "better_supabase"."favorites" ("subject_type", "subject_id");
alter table "better_supabase"."favorites" enable row level security;
revoke all on "better_supabase"."favorites" from anon, authenticated;
grant select on "better_supabase"."favorites" to authenticated;
grant all on "better_supabase"."favorites" to service_role;

create table if not exists "better_supabase"."saved_items" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "note" text check (length("note") <= 1000),
  "remind_at" timestamptz,
  "reminded_at" timestamptz,
  "completed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("user_id", "subject_type", "subject_id")
);
create index if not exists saved_items_user_idx on "better_supabase"."saved_items" ("user_id", "tenant_id", "created_at" desc, "id" desc);
create index if not exists saved_items_subject_idx on "better_supabase"."saved_items" ("subject_type", "subject_id");
create index if not exists saved_items_due_idx on "better_supabase"."saved_items" ("remind_at") where "reminded_at" is null and "completed_at" is null;
alter table "better_supabase"."saved_items" enable row level security;
revoke all on "better_supabase"."saved_items" from anon, authenticated;
grant select on "better_supabase"."saved_items" to authenticated;
grant all on "better_supabase"."saved_items" to service_role;

-- A collection is visible to its owner, its team's members or the whole
-- tenant. An entry is visible when its collection is and the caller can
-- read its record, so a shared list never shows a record to someone who
-- can't open it. Stars and saved items are the caller's own.
drop policy if exists subject_collections_read on "better_supabase"."subject_collections";
create policy subject_collections_read on "better_supabase"."subject_collections" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read')) and (
  ("scope" = 'user' and "owner_id" = (select auth.uid()))
  or ("scope" = 'team' and false)
  or "scope" = 'tenant'
));
drop policy if exists subject_collection_entries_read on "better_supabase"."subject_collection_entries";
create policy subject_collection_entries_read on "better_supabase"."subject_collection_entries" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and exists (select 1 from "better_supabase"."subject_collections" c where c."id" = "collection_id")
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists favorites_read on "better_supabase"."favorites";
create policy favorites_read on "better_supabase"."favorites" for select to authenticated
using ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists saved_items_read on "better_supabase"."saved_items";
create policy saved_items_read on "better_supabase"."saved_items" for select to authenticated
using ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- A list of one subject type, owned by the caller (scope user), a team
-- they belong to, or the whole tenant. Shared scopes need collections.share.
drop function if exists "better_supabase"."create_collection"(uuid, text, text, text, text, text, jsonb);
create or replace function "better_supabase"."create_collection"(tenant uuid, subject_type text, name text, scope text, team text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_scope text := coalesce(create_collection.scope, 'user');
  v_name text := nullif(trim(create_collection.name), '');
  v_service boolean := auth.role() = 'service_role';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_scope not in ('user', 'team', 'tenant') then
    raise exception 'scope must be user, team or tenant' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if create_collection.subject_type is null or not (create_collection.subject_type = any ('{}'::text[])) then
    raise exception 'not a subject type in config.records' using errcode = '22023', hint = 'COLLECTION_SUBJECT_TYPE_UNKNOWN';
  end if;
  if v_name is null then
    raise exception 'a name is required' using errcode = '23502', hint = 'COLLECTION_NAME_REQUIRED';
  end if;
  if not (v_service or coalesce(better_supabase.can('tenant', create_collection.tenant, 'collections.write'), false)) then
    raise exception 'not allowed to create collections' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_scope = 'user' and auth.uid() is null then
    raise exception 'a personal collection needs a signed-in user' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if v_scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', create_collection.tenant, 'collections.share'), false)) then
    raise exception 'not allowed to share collections' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_scope = 'team' then
    if create_collection.team is null then
      raise exception 'a team collection needs a team' using errcode = '22023', hint = 'COLLECTION_INVALID';
    end if;
    if not (v_service or false) then
      raise exception 'not a member of this team' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_collection_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using create_collection.tenant, create_collection.subject_type, v_scope;
    end if;
  end;
  insert into "better_supabase"."subject_collections" ("tenant_id", "subject_type", "scope", "owner_id", "team_id", "name", "description", "created_by")
  values (create_collection.tenant, create_collection.subject_type, v_scope,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'team' then create_collection.team end,
    v_name, nullif(trim(create_collection.description), ''), auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_collection_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") from "better_supabase"."subject_collections" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_collection"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_collection"(uuid, text, text, text, text, text) to authenticated, service_role;

-- A null name keeps it; an empty description clears it, a null one keeps it.
drop function if exists "better_supabase"."rename_collection"(uuid, text, text, jsonb);
create or replace function "better_supabase"."rename_collection"(collection uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = rename_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if rename_collection.name is not null and nullif(trim(rename_collection.name), '') is null then
    raise exception 'a name is required' using errcode = '23502', hint = 'COLLECTION_NAME_REQUIRED';
  end if;
  update "better_supabase"."subject_collections" x set
    "name" = coalesce(trim(rename_collection.name), x."name"),
    "description" = case when rename_collection.description is null then x."description"
      else nullif(trim(rename_collection.description), '') end,
    "updated_at" = now()
  where x."id" = v_row."id";
  return (select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") from "better_supabase"."subject_collections" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."rename_collection"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."rename_collection"(uuid, text, text) to authenticated, service_role;

-- Archives a collection (archived true) or restores it. An archived
-- collection keeps its entries but takes no changes to them.
create or replace function "better_supabase"."archive_collection"(collection uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = archive_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  update "better_supabase"."subject_collections" x set
    "archived_at" = case when coalesce(archive_collection.archived, true) then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id";
  if coalesce(archive_collection.archived, true) and v_row."archived_at" is null then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_collection"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_collection"(uuid, boolean) to authenticated, service_role;

-- The collections the caller sees in a tenant, by name: every subject type
-- when subject_type is null, archived ones only with include_archived.
create or replace function "better_supabase"."list_collections"(tenant uuid, subject_type text, include_archived boolean)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") order by lower(x."name"), x."id"), '[]'::jsonb)
  from "better_supabase"."subject_collections" x
  where x."tenant_id" = list_collections.tenant
    and (list_collections.subject_type is null or x."subject_type" = list_collections.subject_type)
    and (coalesce(list_collections.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_collections"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_collections"(uuid, text, boolean) to authenticated, service_role;

-- Adds records to the end of a collection, in the order given. Ids already
-- in it are skipped; one the caller can't read fails the whole call.
-- subject_type, when given, must be the collection's.
create or replace function "better_supabase"."add_collection_entries"(collection uuid, subject_ids text[], subject_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
  v_id text;
  v_last text;
  v_rank text;
  v_added text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  if cardinality(add_collection_entries.subject_ids) > 1000 then
    raise exception 'at most 1000 ids per call' using errcode = '22023', hint = 'COLLECTION_TOO_MANY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = add_collection_entries.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  if add_collection_entries.subject_type is not null and add_collection_entries.subject_type <> v_row."subject_type" then
    raise exception 'the collection holds another subject type' using errcode = '22023', hint = 'COLLECTION_SUBJECT_TYPE_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_collection_add"(uuid, text[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text[])', v_hook::oid::regproc)
        using v_row."id", add_collection_entries.subject_ids;
    end if;
  end;
  select max(e."rank") into v_last from "better_supabase"."subject_collection_entries" e where e."collection_id" = v_row."id";
  for v_id in
    select u.id from unnest(coalesce(add_collection_entries.subject_ids, '{}')) with ordinality u (id, n)
    where u.id is not null
    group by u.id order by min(u.n)
  loop
    if not false then
      raise exception 'a record is unknown or not readable in this organization' using errcode = '42501', hint = 'COLLECTION_SUBJECT_FORBIDDEN';
    end if;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."subject_collection_entries" ("collection_id", "tenant_id", "subject_type", "subject_id", "rank", "added_by")
    values (v_row."id", v_row."tenant_id", v_row."subject_type", v_id, v_rank, auth.uid())
    on conflict do nothing;
    if found then
      v_last := v_rank;
      v_added := v_added || v_id;
      null;
    end if;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_collection_add"(uuid, text[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text[])', v_hook::oid::regproc)
        using v_row."id", v_added;
    end if;
  end;
  return jsonb_build_object('added', to_jsonb(v_added));
end;
$$;
revoke execute on function "better_supabase"."add_collection_entries"(uuid, text[], text) from public, anon;
grant execute on function "better_supabase"."add_collection_entries"(uuid, text[], text) to authenticated, service_role;

-- Removes the records the caller can read from a collection; returns how many.
create or replace function "better_supabase"."remove_collection_entries"(collection uuid, subject_ids text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
  v_id text;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  if cardinality(remove_collection_entries.subject_ids) > 1000 then
    raise exception 'at most 1000 ids per call' using errcode = '22023', hint = 'COLLECTION_TOO_MANY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = remove_collection_entries.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  for v_id in
    delete from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = v_row."id"
      and e."subject_id" = any (coalesce(remove_collection_entries.subject_ids, '{}'))
      and (auth.role() = 'service_role' or "better_supabase"."can_subject"(e."subject_type", e."subject_id", 'read'))
    returning e."subject_id"
  loop
    v_count := v_count + 1;
    null;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."remove_collection_entries"(uuid, text[]) from public, anon;
grant execute on function "better_supabase"."remove_collection_entries"(uuid, text[]) to authenticated, service_role;

create or replace function "better_supabase"."rank_collection_entry"(collection uuid, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_collection_entry.rank is null or rank_collection_entry.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'COLLECTION_RANK_INVALID';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = rank_collection_entry.collection;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  update "better_supabase"."subject_collection_entries" e set "rank" = rank_collection_entry.rank
  where e."collection_id" = v_row."id" and e."subject_id" = rank_collection_entry.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."rank_collection_entry"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."rank_collection_entry"(uuid, text, text) to authenticated, service_role;

-- A page of a collection's entries in rank order, with each record's title
-- and URL. after_rank and after_id continue after the previous page's last
-- entry. Entries whose record the caller can't read are left out.
create or replace function "better_supabase"."collection_entries"(collection uuid, after_rank text, after_id text, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.rank, p.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'collectionId', e."collection_id",
      'subjectType', e."subject_type",
      'subjectId', e."subject_id",
      'rank', e."rank",
      'addedBy', e."added_by",
      'addedAt', e."added_at",
      'title', "better_supabase"."subject_title"(e."subject_type", e."subject_id"),
      'url', "better_supabase"."subject_url"(e."subject_type", e."subject_id")
    ) as value, e."rank" as rank, e."subject_id" collate "C" as id
    from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = collection_entries.collection
      and (collection_entries.after_rank is null
        or (e."rank", e."subject_id" collate "C") > (collection_entries.after_rank collate "C", coalesce(collection_entries.after_id, '') collate "C"))
    order by e."rank", e."subject_id" collate "C"
    limit least(greatest(coalesce(collection_entries.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."collection_entries"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."collection_entries"(uuid, text, text, integer) to authenticated, service_role;

-- The ids of a collection's records the caller can read, in rank order, at
-- most max_ids (default 500, up to 1000): a saved view's "in list" filter.
create or replace function "better_supabase"."collection_subject_ids"(collection uuid, max_ids integer)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(array_agg(p.id order by p.rank, p.id), '{}')
  from (
    select e."subject_id" collate "C" as id, e."rank" as rank
    from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = collection_subject_ids.collection
    order by e."rank", e."subject_id" collate "C"
    limit least(greatest(coalesce(collection_subject_ids.max_ids, 500), 1), 1000)
  ) p
$$;
revoke execute on function "better_supabase"."collection_subject_ids"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."collection_subject_ids"(uuid, integer) to authenticated, service_role;

-- The active collections the caller sees that hold a record, by name.
create or replace function "better_supabase"."collections_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") order by lower(x."name"), x."id"), '[]'::jsonb)
  from "better_supabase"."subject_collections" x
  join "better_supabase"."subject_collection_entries" e on e."collection_id" = x."id"
  where e."subject_type" = collections_of.subject_type
    and e."subject_id" = collections_of.subject_id
    and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."collections_of"(text, text) from public, anon;
grant execute on function "better_supabase"."collections_of"(text, text) to authenticated, service_role;

-- Stars a record the caller can read, at the end of their favorites. A
-- record already starred keeps its place.
create or replace function "better_supabase"."star_subject"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'a star needs a signed-in user' using errcode = '22023', hint = 'FAVORITE_INVALID';
  end if;
  if not coalesce(better_supabase.can('tenant', star_subject.tenant, 'collections.read'), false) then
    raise exception 'not allowed to star records' using errcode = '42501', hint = 'FAVORITE_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record is unknown or not readable in this organization' using errcode = '42501', hint = 'FAVORITE_SUBJECT_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."favorites" f
    where f."user_id" = v_user and f."subject_type" = star_subject.subject_type and f."subject_id" = star_subject.subject_id
  ) then
    select max(f."rank") into v_last from "better_supabase"."favorites" f
      where f."user_id" = v_user and f."tenant_id" = star_subject.tenant;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."favorites" ("user_id", "tenant_id", "subject_type", "subject_id", "rank")
    values (v_user, star_subject.tenant, star_subject.subject_type, star_subject.subject_id, v_rank)
    on conflict do nothing;
  end if;
  return (select jsonb_build_object(
      'subjectType', f."subject_type",
      'subjectId', f."subject_id",
      'organizationId', f."tenant_id",
      'rank', f."rank",
      'starredAt', f."created_at") from "better_supabase"."favorites" f
    where f."user_id" = v_user and f."subject_type" = star_subject.subject_type and f."subject_id" = star_subject.subject_id);
end;
$$;
revoke execute on function "better_supabase"."star_subject"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."star_subject"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."unstar_subject"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."favorites" f
  where f."user_id" = auth.uid() and f."subject_type" = unstar_subject.subject_type and f."subject_id" = unstar_subject.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."unstar_subject"(text, text) from public, anon;
grant execute on function "better_supabase"."unstar_subject"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."rank_star"(subject_type text, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_star.rank is null or rank_star.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FAVORITE_RANK_INVALID';
  end if;
  update "better_supabase"."favorites" f set "rank" = rank_star.rank
  where f."user_id" = auth.uid() and f."subject_type" = rank_star.subject_type and f."subject_id" = rank_star.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."rank_star"(text, text, text) from public, anon;
grant execute on function "better_supabase"."rank_star"(text, text, text) to authenticated, service_role;

-- The caller's stars in a tenant in sidebar order, with each record's title
-- and URL: every subject type when subject_type is null.
create or replace function "better_supabase"."starred_subjects"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'subjectType', f."subject_type",
      'subjectId', f."subject_id",
      'organizationId', f."tenant_id",
      'rank', f."rank",
      'starredAt', f."created_at") || jsonb_build_object(
      'title', "better_supabase"."subject_title"(f."subject_type", f."subject_id"),
      'url', "better_supabase"."subject_url"(f."subject_type", f."subject_id"))
    order by f."rank", f."subject_type", f."subject_id" collate "C"), '[]'::jsonb)
  from "better_supabase"."favorites" f
  where f."user_id" = (select auth.uid())
    and f."tenant_id" = starred_subjects.tenant
    and (starred_subjects.subject_type is null or f."subject_type" = starred_subjects.subject_type)
$$;
revoke execute on function "better_supabase"."starred_subjects"(uuid, text) from public, anon;
grant execute on function "better_supabase"."starred_subjects"(uuid, text) to authenticated, service_role;

-- Saves a record the caller can read for later. Saving it again replaces the
-- note and reminder and reopens a completed item.
create or replace function "better_supabase"."save_for_later"(tenant uuid, subject_type text, subject_id text, note text default null, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_note text := nullif(btrim(save_for_later.note), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'saving for later needs a signed-in user' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  if not coalesce(better_supabase.can('tenant', save_for_later.tenant, 'collections.read'), false) then
    raise exception 'not allowed to save records' using errcode = '42501', hint = 'SAVED_ITEM_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record is unknown or not readable in this organization' using errcode = '42501', hint = 'SAVED_ITEM_SUBJECT_FORBIDDEN';
  end if;
  if length(v_note) > 1000 then
    raise exception 'a note holds at most 1000 characters' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  if save_for_later.remind_at is not null and save_for_later.remind_at <= now() then
    raise exception 'the reminder time must be in the future' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  insert into "better_supabase"."saved_items" ("user_id", "tenant_id", "subject_type", "subject_id", "note", "remind_at")
  values (v_user, save_for_later.tenant, save_for_later.subject_type, save_for_later.subject_id, v_note, save_for_later.remind_at)
  on conflict ("user_id", "subject_type", "subject_id") do update
    set "note" = excluded."note",
      "remind_at" = excluded."remind_at",
      "reminded_at" = null,
      "completed_at" = null;
  return (select jsonb_build_object(
      'id', s."id",
      'organizationId', s."tenant_id",
      'userId', s."user_id",
      'subjectType', s."subject_type",
      'subjectId', s."subject_id",
      'note', s."note",
      'remindAt', s."remind_at",
      'remindedAt', s."reminded_at",
      'completedAt', s."completed_at",
      'createdAt', s."created_at") from "better_supabase"."saved_items" s
    where s."user_id" = v_user and s."subject_type" = save_for_later.subject_type and s."subject_id" = save_for_later.subject_id);
end;
$$;
revoke execute on function "better_supabase"."save_for_later"(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_for_later"(uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Marks one of the caller's saved items completed, or open again with
-- completed false.
create or replace function "better_supabase"."complete_saved_item"(item uuid, completed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."saved_items" s
    set "completed_at" = case when complete_saved_item.completed then coalesce(s."completed_at", now()) end
    where s."id" = complete_saved_item.item and s."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."complete_saved_item"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."complete_saved_item"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_saved_item"(item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."saved_items" s
    where s."id" = remove_saved_item.item and s."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_saved_item"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_saved_item"(uuid) to authenticated, service_role;

-- The caller's saved items in a tenant, the newest first, with each record's
-- title and URL: the open ones, or the completed ones with completed true.
create or replace function "better_supabase"."list_saved_items"(tenant uuid, completed boolean default false, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(item order by created_at desc, id desc), '[]'::jsonb)
  from (
    select s."created_at" as created_at, s."id" as id, jsonb_build_object(
      'id', s."id",
      'organizationId', s."tenant_id",
      'userId', s."user_id",
      'subjectType', s."subject_type",
      'subjectId', s."subject_id",
      'note', s."note",
      'remindAt', s."remind_at",
      'remindedAt', s."reminded_at",
      'completedAt', s."completed_at",
      'createdAt', s."created_at") || jsonb_build_object(
        'title', "better_supabase"."subject_title"(s."subject_type", s."subject_id"),
        'url', "better_supabase"."subject_url"(s."subject_type", s."subject_id")) as item
    from "better_supabase"."saved_items" s
    where s."user_id" = (select auth.uid())
      and s."tenant_id" = list_saved_items.tenant
      and (s."completed_at" is not null) = coalesce(list_saved_items.completed, false)
      and (list_saved_items.before is null
        or (s."created_at", s."id") < (list_saved_items.before, coalesce(list_saved_items.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by s."created_at" desc, s."id" desc
    limit least(greatest(coalesce(list_saved_items.max_rows, 50), 1), 200)
  ) page
$$;
revoke execute on function "better_supabase"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) to authenticated, service_role;

-- Service role. Claims the open saved items whose reminder time has passed,
-- records saved_item.reminded for each and returns them. A claimed item is not
-- returned again until it is saved with a new reminder.
create or replace function "better_supabase"."remind_due_saved_items"(max_rows integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."saved_items"%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not auth.role() = 'service_role' then
    raise exception 'only the service role sends saved item reminders' using errcode = '42501', hint = 'SAVED_ITEM_FORBIDDEN';
  end if;
  for v_row in
    update "better_supabase"."saved_items" s set "reminded_at" = now()
    where s."id" in (
      select d."id" from "better_supabase"."saved_items" d
      where d."remind_at" <= now() and d."reminded_at" is null and d."completed_at" is null
      order by d."remind_at", d."id"
      limit least(greatest(coalesce(remind_due_saved_items.max_rows, 100), 1), 500)
      for update skip locked
    )
    returning s.*
  loop
    null;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', v_row."id",
      'organizationId', v_row."tenant_id",
      'userId', v_row."user_id",
      'subjectType', v_row."subject_type",
      'subjectId', v_row."subject_id",
      'note', v_row."note",
      'remindAt', v_row."remind_at",
      'remindedAt', v_row."reminded_at",
      'completedAt', v_row."completed_at",
      'createdAt', v_row."created_at"));
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."remind_due_saved_items"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."remind_due_saved_items"(integer) to service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collections";
create policy bsb_tenant_scope on "better_supabase"."subject_collections" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read')) and (
  ("scope" = 'user' and "owner_id" = (select auth.uid()))
  or ("scope" = 'team' and false)
  or "scope" = 'tenant'
))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collection_entries";
create policy bsb_tenant_scope on "better_supabase"."subject_collection_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and exists (select 1 from "better_supabase"."subject_collections" c where c."id" = "collection_id")
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."favorites";
create policy bsb_tenant_scope on "better_supabase"."favorites" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."saved_items";
create policy bsb_tenant_scope on "better_supabase"."saved_items" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_103_collections.sql
-- better-supabase module: collections
-- @bsb-block-data collections
-- @bsb-hash sha256:77080beb5b84e4f94399188b93d547f7a72b4cd89f7a97593a08e54057c736a8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('collections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_103_collections.sql
-- better-supabase module: collections
-- @bsb-block collections@1 managed
-- @bsb-hash sha256:da94a6fd1c240a0c73f1e6a366f101356fc5855167897831560b711c837ba9e1
-- Favorites (a member's ranked stars on any registered record), lists (named, static collections of one subject type owned by a user, a team or the organization) and saved items (a member's records to come back to, with a note and a reminder), with entries hidden unless the caller can read their record.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collections";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collection_entries";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."favorites";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."saved_items";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Favorites (a member's starred records, ranked for a sidebar), lists (named,
-- static collections of one subject type) and saved items (a member's records
-- to come back to, with a reminder) on config.records records.

create table if not exists "better_supabase"."subject_collections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope" text not null default 'user' check ("scope" in ('user', 'team', 'tenant')),
  "owner_id" uuid references auth.users (id) on delete cascade,
  "team_id" text,
  "name" text not null check (length("name") between 1 and 120),
  "description" text check (length("description") <= 2000),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("scope" <> 'user' or "owner_id" is not null),
  check ("scope" <> 'team' or "team_id" is not null)
);
create index if not exists subject_collections_tenant_type_idx on "better_supabase"."subject_collections" ("tenant_id", "subject_type", lower("name"));
create index if not exists subject_collections_owner_idx on "better_supabase"."subject_collections" ("owner_id") where "owner_id" is not null;
alter table "better_supabase"."subject_collections" enable row level security;
revoke all on "better_supabase"."subject_collections" from anon, authenticated;
grant select on "better_supabase"."subject_collections" to authenticated;
grant all on "better_supabase"."subject_collections" to service_role;

create table if not exists "better_supabase"."subject_collection_entries" (
  "collection_id" uuid not null references "better_supabase"."subject_collections" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "rank" text collate "C" not null,
  "added_by" uuid,
  "added_at" timestamptz not null default now(),
  primary key ("collection_id", "subject_id")
);
create index if not exists subject_collection_entries_rank_idx on "better_supabase"."subject_collection_entries" ("collection_id", "rank", "subject_id");
create index if not exists subject_collection_entries_subject_idx on "better_supabase"."subject_collection_entries" ("subject_type", "subject_id");
alter table "better_supabase"."subject_collection_entries" enable row level security;
revoke all on "better_supabase"."subject_collection_entries" from anon, authenticated;
grant select on "better_supabase"."subject_collection_entries" to authenticated;
grant all on "better_supabase"."subject_collection_entries" to service_role;

create table if not exists "better_supabase"."favorites" (
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "rank" text collate "C" not null,
  "created_at" timestamptz not null default now(),
  primary key ("user_id", "subject_type", "subject_id")
);
create index if not exists favorites_user_rank_idx on "better_supabase"."favorites" ("user_id", "tenant_id", "rank");
create index if not exists favorites_subject_idx on "better_supabase"."favorites" ("subject_type", "subject_id");
alter table "better_supabase"."favorites" enable row level security;
revoke all on "better_supabase"."favorites" from anon, authenticated;
grant select on "better_supabase"."favorites" to authenticated;
grant all on "better_supabase"."favorites" to service_role;

create table if not exists "better_supabase"."saved_items" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "note" text check (length("note") <= 1000),
  "remind_at" timestamptz,
  "reminded_at" timestamptz,
  "completed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("user_id", "subject_type", "subject_id")
);
create index if not exists saved_items_user_idx on "better_supabase"."saved_items" ("user_id", "tenant_id", "created_at" desc, "id" desc);
create index if not exists saved_items_subject_idx on "better_supabase"."saved_items" ("subject_type", "subject_id");
create index if not exists saved_items_due_idx on "better_supabase"."saved_items" ("remind_at") where "reminded_at" is null and "completed_at" is null;
alter table "better_supabase"."saved_items" enable row level security;
revoke all on "better_supabase"."saved_items" from anon, authenticated;
grant select on "better_supabase"."saved_items" to authenticated;
grant all on "better_supabase"."saved_items" to service_role;

-- A collection is visible to its owner, its team's members or the whole
-- tenant. An entry is visible when its collection is and the caller can
-- read its record, so a shared list never shows a record to someone who
-- can't open it. Stars and saved items are the caller's own.
drop policy if exists subject_collections_read on "better_supabase"."subject_collections";
create policy subject_collections_read on "better_supabase"."subject_collections" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read')) and (
  ("scope" = 'user' and "owner_id" = (select auth.uid()))
  or ("scope" = 'team' and "team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
  or "scope" = 'tenant'
));
drop policy if exists subject_collection_entries_read on "better_supabase"."subject_collection_entries";
create policy subject_collection_entries_read on "better_supabase"."subject_collection_entries" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and exists (select 1 from "better_supabase"."subject_collections" c where c."id" = "collection_id")
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists favorites_read on "better_supabase"."favorites";
create policy favorites_read on "better_supabase"."favorites" for select to authenticated
using ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists saved_items_read on "better_supabase"."saved_items";
create policy saved_items_read on "better_supabase"."saved_items" for select to authenticated
using ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- A list of one subject type, owned by the caller (scope user), a team
-- they belong to, or the whole tenant. Shared scopes need collections.share.
drop function if exists "better_supabase"."create_collection"(uuid, text, text, text, text, text, jsonb);
create or replace function "better_supabase"."create_collection"(tenant uuid, subject_type text, name text, scope text, team text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_scope text := coalesce(create_collection.scope, 'user');
  v_name text := nullif(trim(create_collection.name), '');
  v_service boolean := auth.role() = 'service_role';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_scope not in ('user', 'team', 'tenant') then
    raise exception 'scope must be user, team or tenant' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if create_collection.subject_type is null or not (create_collection.subject_type = any ('{}'::text[])) then
    raise exception 'not a subject type in config.records' using errcode = '22023', hint = 'COLLECTION_SUBJECT_TYPE_UNKNOWN';
  end if;
  if v_name is null then
    raise exception 'a name is required' using errcode = '23502', hint = 'COLLECTION_NAME_REQUIRED';
  end if;
  if not (v_service or coalesce(better_supabase.can('tenant', create_collection.tenant, 'collections.write'), false)) then
    raise exception 'not allowed to create collections' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_scope = 'user' and auth.uid() is null then
    raise exception 'a personal collection needs a signed-in user' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if v_scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', create_collection.tenant, 'collections.share'), false)) then
    raise exception 'not allowed to share collections' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_scope = 'team' then
    if create_collection.team is null then
      raise exception 'a team collection needs a team' using errcode = '22023', hint = 'COLLECTION_INVALID';
    end if;
    if not (v_service or create_collection.team in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t)) then
      raise exception 'not a member of this team' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_collection_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using create_collection.tenant, create_collection.subject_type, v_scope;
    end if;
  end;
  insert into "better_supabase"."subject_collections" ("tenant_id", "subject_type", "scope", "owner_id", "team_id", "name", "description", "created_by")
  values (create_collection.tenant, create_collection.subject_type, v_scope,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'team' then create_collection.team end,
    v_name, nullif(trim(create_collection.description), ''), auth.uid())
  returning "id" into v_id;
  perform "better_supabase".emit_event('collection.created', jsonb_build_object('organizationId', create_collection.tenant, 'collectionId', v_id, 'subjectType', create_collection.subject_type, 'name', v_name, 'scope', v_scope), 'collections/' || v_id::text, (create_collection.tenant::text)::text, null, 'better-supabase/collections');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_collection_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") from "better_supabase"."subject_collections" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_collection"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_collection"(uuid, text, text, text, text, text) to authenticated, service_role;

-- A null name keeps it; an empty description clears it, a null one keeps it.
drop function if exists "better_supabase"."rename_collection"(uuid, text, text, jsonb);
create or replace function "better_supabase"."rename_collection"(collection uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = rename_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if rename_collection.name is not null and nullif(trim(rename_collection.name), '') is null then
    raise exception 'a name is required' using errcode = '23502', hint = 'COLLECTION_NAME_REQUIRED';
  end if;
  update "better_supabase"."subject_collections" x set
    "name" = coalesce(trim(rename_collection.name), x."name"),
    "description" = case when rename_collection.description is null then x."description"
      else nullif(trim(rename_collection.description), '') end,
    "updated_at" = now()
  where x."id" = v_row."id";
  return (select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") from "better_supabase"."subject_collections" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."rename_collection"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."rename_collection"(uuid, text, text) to authenticated, service_role;

-- Archives a collection (archived true) or restores it. An archived
-- collection keeps its entries but takes no changes to them.
create or replace function "better_supabase"."archive_collection"(collection uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = archive_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  update "better_supabase"."subject_collections" x set
    "archived_at" = case when coalesce(archive_collection.archived, true) then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id";
  if coalesce(archive_collection.archived, true) and v_row."archived_at" is null then
    perform "better_supabase".emit_event('collection.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'collectionId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'collections/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/collections');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_collection"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_collection"(uuid, boolean) to authenticated, service_role;

-- The collections the caller sees in a tenant, by name: every subject type
-- when subject_type is null, archived ones only with include_archived.
create or replace function "better_supabase"."list_collections"(tenant uuid, subject_type text, include_archived boolean)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") order by lower(x."name"), x."id"), '[]'::jsonb)
  from "better_supabase"."subject_collections" x
  where x."tenant_id" = list_collections.tenant
    and (list_collections.subject_type is null or x."subject_type" = list_collections.subject_type)
    and (coalesce(list_collections.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_collections"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_collections"(uuid, text, boolean) to authenticated, service_role;

-- Adds records to the end of a collection, in the order given. Ids already
-- in it are skipped; one the caller can't read fails the whole call.
-- subject_type, when given, must be the collection's.
create or replace function "better_supabase"."add_collection_entries"(collection uuid, subject_ids text[], subject_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
  v_id text;
  v_last text;
  v_rank text;
  v_added text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  if cardinality(add_collection_entries.subject_ids) > 1000 then
    raise exception 'at most 1000 ids per call' using errcode = '22023', hint = 'COLLECTION_TOO_MANY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = add_collection_entries.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  if add_collection_entries.subject_type is not null and add_collection_entries.subject_type <> v_row."subject_type" then
    raise exception 'the collection holds another subject type' using errcode = '22023', hint = 'COLLECTION_SUBJECT_TYPE_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_collection_add"(uuid, text[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text[])', v_hook::oid::regproc)
        using v_row."id", add_collection_entries.subject_ids;
    end if;
  end;
  select max(e."rank") into v_last from "better_supabase"."subject_collection_entries" e where e."collection_id" = v_row."id";
  for v_id in
    select u.id from unnest(coalesce(add_collection_entries.subject_ids, '{}')) with ordinality u (id, n)
    where u.id is not null
    group by u.id order by min(u.n)
  loop
    if not false then
      raise exception 'a record is unknown or not readable in this organization' using errcode = '42501', hint = 'COLLECTION_SUBJECT_FORBIDDEN';
    end if;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."subject_collection_entries" ("collection_id", "tenant_id", "subject_type", "subject_id", "rank", "added_by")
    values (v_row."id", v_row."tenant_id", v_row."subject_type", v_id, v_rank, auth.uid())
    on conflict do nothing;
    if found then
      v_last := v_rank;
      v_added := v_added || v_id;
      perform "better_supabase".emit_event('collection.entry_added', jsonb_build_object('organizationId', v_row."tenant_id", 'collectionId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'collections/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/collections');
    end if;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_collection_add"(uuid, text[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text[])', v_hook::oid::regproc)
        using v_row."id", v_added;
    end if;
  end;
  return jsonb_build_object('added', to_jsonb(v_added));
end;
$$;
revoke execute on function "better_supabase"."add_collection_entries"(uuid, text[], text) from public, anon;
grant execute on function "better_supabase"."add_collection_entries"(uuid, text[], text) to authenticated, service_role;

-- Removes the records the caller can read from a collection; returns how many.
create or replace function "better_supabase"."remove_collection_entries"(collection uuid, subject_ids text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
  v_id text;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  if cardinality(remove_collection_entries.subject_ids) > 1000 then
    raise exception 'at most 1000 ids per call' using errcode = '22023', hint = 'COLLECTION_TOO_MANY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = remove_collection_entries.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  for v_id in
    delete from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = v_row."id"
      and e."subject_id" = any (coalesce(remove_collection_entries.subject_ids, '{}'))
      and (auth.role() = 'service_role' or "better_supabase"."can_subject"(e."subject_type", e."subject_id", 'read'))
    returning e."subject_id"
  loop
    v_count := v_count + 1;
    perform "better_supabase".emit_event('collection.entry_removed', jsonb_build_object('organizationId', v_row."tenant_id", 'collectionId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'collections/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/collections');
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."remove_collection_entries"(uuid, text[]) from public, anon;
grant execute on function "better_supabase"."remove_collection_entries"(uuid, text[]) to authenticated, service_role;

create or replace function "better_supabase"."rank_collection_entry"(collection uuid, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_collection_entry.rank is null or rank_collection_entry.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'COLLECTION_RANK_INVALID';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = rank_collection_entry.collection;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  update "better_supabase"."subject_collection_entries" e set "rank" = rank_collection_entry.rank
  where e."collection_id" = v_row."id" and e."subject_id" = rank_collection_entry.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."rank_collection_entry"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."rank_collection_entry"(uuid, text, text) to authenticated, service_role;

-- A page of a collection's entries in rank order, with each record's title
-- and URL. after_rank and after_id continue after the previous page's last
-- entry. Entries whose record the caller can't read are left out.
create or replace function "better_supabase"."collection_entries"(collection uuid, after_rank text, after_id text, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.rank, p.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'collectionId', e."collection_id",
      'subjectType', e."subject_type",
      'subjectId', e."subject_id",
      'rank', e."rank",
      'addedBy', e."added_by",
      'addedAt', e."added_at",
      'title', "better_supabase"."subject_title"(e."subject_type", e."subject_id"),
      'url', "better_supabase"."subject_url"(e."subject_type", e."subject_id")
    ) as value, e."rank" as rank, e."subject_id" collate "C" as id
    from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = collection_entries.collection
      and (collection_entries.after_rank is null
        or (e."rank", e."subject_id" collate "C") > (collection_entries.after_rank collate "C", coalesce(collection_entries.after_id, '') collate "C"))
    order by e."rank", e."subject_id" collate "C"
    limit least(greatest(coalesce(collection_entries.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."collection_entries"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."collection_entries"(uuid, text, text, integer) to authenticated, service_role;

-- The ids of a collection's records the caller can read, in rank order, at
-- most max_ids (default 500, up to 1000): a saved view's "in list" filter.
create or replace function "better_supabase"."collection_subject_ids"(collection uuid, max_ids integer)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(array_agg(p.id order by p.rank, p.id), '{}')
  from (
    select e."subject_id" collate "C" as id, e."rank" as rank
    from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = collection_subject_ids.collection
    order by e."rank", e."subject_id" collate "C"
    limit least(greatest(coalesce(collection_subject_ids.max_ids, 500), 1), 1000)
  ) p
$$;
revoke execute on function "better_supabase"."collection_subject_ids"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."collection_subject_ids"(uuid, integer) to authenticated, service_role;

-- The active collections the caller sees that hold a record, by name.
create or replace function "better_supabase"."collections_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") order by lower(x."name"), x."id"), '[]'::jsonb)
  from "better_supabase"."subject_collections" x
  join "better_supabase"."subject_collection_entries" e on e."collection_id" = x."id"
  where e."subject_type" = collections_of.subject_type
    and e."subject_id" = collections_of.subject_id
    and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."collections_of"(text, text) from public, anon;
grant execute on function "better_supabase"."collections_of"(text, text) to authenticated, service_role;

-- Stars a record the caller can read, at the end of their favorites. A
-- record already starred keeps its place.
create or replace function "better_supabase"."star_subject"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'a star needs a signed-in user' using errcode = '22023', hint = 'FAVORITE_INVALID';
  end if;
  if not coalesce(better_supabase.can('tenant', star_subject.tenant, 'collections.read'), false) then
    raise exception 'not allowed to star records' using errcode = '42501', hint = 'FAVORITE_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record is unknown or not readable in this organization' using errcode = '42501', hint = 'FAVORITE_SUBJECT_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."favorites" f
    where f."user_id" = v_user and f."subject_type" = star_subject.subject_type and f."subject_id" = star_subject.subject_id
  ) then
    select max(f."rank") into v_last from "better_supabase"."favorites" f
      where f."user_id" = v_user and f."tenant_id" = star_subject.tenant;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."favorites" ("user_id", "tenant_id", "subject_type", "subject_id", "rank")
    values (v_user, star_subject.tenant, star_subject.subject_type, star_subject.subject_id, v_rank)
    on conflict do nothing;
  end if;
  return (select jsonb_build_object(
      'subjectType', f."subject_type",
      'subjectId', f."subject_id",
      'organizationId', f."tenant_id",
      'rank', f."rank",
      'starredAt', f."created_at") from "better_supabase"."favorites" f
    where f."user_id" = v_user and f."subject_type" = star_subject.subject_type and f."subject_id" = star_subject.subject_id);
end;
$$;
revoke execute on function "better_supabase"."star_subject"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."star_subject"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."unstar_subject"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."favorites" f
  where f."user_id" = auth.uid() and f."subject_type" = unstar_subject.subject_type and f."subject_id" = unstar_subject.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."unstar_subject"(text, text) from public, anon;
grant execute on function "better_supabase"."unstar_subject"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."rank_star"(subject_type text, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_star.rank is null or rank_star.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FAVORITE_RANK_INVALID';
  end if;
  update "better_supabase"."favorites" f set "rank" = rank_star.rank
  where f."user_id" = auth.uid() and f."subject_type" = rank_star.subject_type and f."subject_id" = rank_star.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."rank_star"(text, text, text) from public, anon;
grant execute on function "better_supabase"."rank_star"(text, text, text) to authenticated, service_role;

-- The caller's stars in a tenant in sidebar order, with each record's title
-- and URL: every subject type when subject_type is null.
create or replace function "better_supabase"."starred_subjects"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'subjectType', f."subject_type",
      'subjectId', f."subject_id",
      'organizationId', f."tenant_id",
      'rank', f."rank",
      'starredAt', f."created_at") || jsonb_build_object(
      'title', "better_supabase"."subject_title"(f."subject_type", f."subject_id"),
      'url', "better_supabase"."subject_url"(f."subject_type", f."subject_id"))
    order by f."rank", f."subject_type", f."subject_id" collate "C"), '[]'::jsonb)
  from "better_supabase"."favorites" f
  where f."user_id" = (select auth.uid())
    and f."tenant_id" = starred_subjects.tenant
    and (starred_subjects.subject_type is null or f."subject_type" = starred_subjects.subject_type)
$$;
revoke execute on function "better_supabase"."starred_subjects"(uuid, text) from public, anon;
grant execute on function "better_supabase"."starred_subjects"(uuid, text) to authenticated, service_role;

-- Saves a record the caller can read for later. Saving it again replaces the
-- note and reminder and reopens a completed item.
create or replace function "better_supabase"."save_for_later"(tenant uuid, subject_type text, subject_id text, note text default null, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_note text := nullif(btrim(save_for_later.note), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'saving for later needs a signed-in user' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  if not coalesce(better_supabase.can('tenant', save_for_later.tenant, 'collections.read'), false) then
    raise exception 'not allowed to save records' using errcode = '42501', hint = 'SAVED_ITEM_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record is unknown or not readable in this organization' using errcode = '42501', hint = 'SAVED_ITEM_SUBJECT_FORBIDDEN';
  end if;
  if length(v_note) > 1000 then
    raise exception 'a note holds at most 1000 characters' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  if save_for_later.remind_at is not null and save_for_later.remind_at <= now() then
    raise exception 'the reminder time must be in the future' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  insert into "better_supabase"."saved_items" ("user_id", "tenant_id", "subject_type", "subject_id", "note", "remind_at")
  values (v_user, save_for_later.tenant, save_for_later.subject_type, save_for_later.subject_id, v_note, save_for_later.remind_at)
  on conflict ("user_id", "subject_type", "subject_id") do update
    set "note" = excluded."note",
      "remind_at" = excluded."remind_at",
      "reminded_at" = null,
      "completed_at" = null;
  return (select jsonb_build_object(
      'id', s."id",
      'organizationId', s."tenant_id",
      'userId', s."user_id",
      'subjectType', s."subject_type",
      'subjectId', s."subject_id",
      'note', s."note",
      'remindAt', s."remind_at",
      'remindedAt', s."reminded_at",
      'completedAt', s."completed_at",
      'createdAt', s."created_at") from "better_supabase"."saved_items" s
    where s."user_id" = v_user and s."subject_type" = save_for_later.subject_type and s."subject_id" = save_for_later.subject_id);
end;
$$;
revoke execute on function "better_supabase"."save_for_later"(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_for_later"(uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Marks one of the caller's saved items completed, or open again with
-- completed false.
create or replace function "better_supabase"."complete_saved_item"(item uuid, completed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."saved_items" s
    set "completed_at" = case when complete_saved_item.completed then coalesce(s."completed_at", now()) end
    where s."id" = complete_saved_item.item and s."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."complete_saved_item"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."complete_saved_item"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_saved_item"(item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."saved_items" s
    where s."id" = remove_saved_item.item and s."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_saved_item"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_saved_item"(uuid) to authenticated, service_role;

-- The caller's saved items in a tenant, the newest first, with each record's
-- title and URL: the open ones, or the completed ones with completed true.
create or replace function "better_supabase"."list_saved_items"(tenant uuid, completed boolean default false, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(item order by created_at desc, id desc), '[]'::jsonb)
  from (
    select s."created_at" as created_at, s."id" as id, jsonb_build_object(
      'id', s."id",
      'organizationId', s."tenant_id",
      'userId', s."user_id",
      'subjectType', s."subject_type",
      'subjectId', s."subject_id",
      'note', s."note",
      'remindAt', s."remind_at",
      'remindedAt', s."reminded_at",
      'completedAt', s."completed_at",
      'createdAt', s."created_at") || jsonb_build_object(
        'title', "better_supabase"."subject_title"(s."subject_type", s."subject_id"),
        'url', "better_supabase"."subject_url"(s."subject_type", s."subject_id")) as item
    from "better_supabase"."saved_items" s
    where s."user_id" = (select auth.uid())
      and s."tenant_id" = list_saved_items.tenant
      and (s."completed_at" is not null) = coalesce(list_saved_items.completed, false)
      and (list_saved_items.before is null
        or (s."created_at", s."id") < (list_saved_items.before, coalesce(list_saved_items.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by s."created_at" desc, s."id" desc
    limit least(greatest(coalesce(list_saved_items.max_rows, 50), 1), 200)
  ) page
$$;
revoke execute on function "better_supabase"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) to authenticated, service_role;

-- Service role. Claims the open saved items whose reminder time has passed,
-- records saved_item.reminded for each and returns them. A claimed item is not
-- returned again until it is saved with a new reminder.
create or replace function "better_supabase"."remind_due_saved_items"(max_rows integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."saved_items"%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not auth.role() = 'service_role' then
    raise exception 'only the service role sends saved item reminders' using errcode = '42501', hint = 'SAVED_ITEM_FORBIDDEN';
  end if;
  for v_row in
    update "better_supabase"."saved_items" s set "reminded_at" = now()
    where s."id" in (
      select d."id" from "better_supabase"."saved_items" d
      where d."remind_at" <= now() and d."reminded_at" is null and d."completed_at" is null
      order by d."remind_at", d."id"
      limit least(greatest(coalesce(remind_due_saved_items.max_rows, 100), 1), 500)
      for update skip locked
    )
    returning s.*
  loop
    perform "better_supabase".emit_event('saved_item.reminded', jsonb_strip_nulls(jsonb_build_object('organizationId', v_row."tenant_id", 'savedItemId', v_row."id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'note', v_row."note", 'remindAt', v_row."remind_at")), 'saved-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/collections');
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', v_row."id",
      'organizationId', v_row."tenant_id",
      'userId', v_row."user_id",
      'subjectType', v_row."subject_type",
      'subjectId', v_row."subject_id",
      'note', v_row."note",
      'remindAt', v_row."remind_at",
      'remindedAt', v_row."reminded_at",
      'completedAt', v_row."completed_at",
      'createdAt', v_row."created_at"));
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."remind_due_saved_items"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."remind_due_saved_items"(integer) to service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collections";
create policy bsb_tenant_scope on "better_supabase"."subject_collections" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read')) and (
  ("scope" = 'user' and "owner_id" = (select auth.uid()))
  or ("scope" = 'team' and "team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
  or "scope" = 'tenant'
))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collection_entries";
create policy bsb_tenant_scope on "better_supabase"."subject_collection_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and exists (select 1 from "better_supabase"."subject_collections" c where c."id" = "collection_id")
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."favorites";
create policy bsb_tenant_scope on "better_supabase"."favorites" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."saved_items";
create policy bsb_tenant_scope on "better_supabase"."saved_items" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_103_collections.sql
-- better-supabase module: collections
-- @bsb-block-data collections
-- @bsb-hash sha256:77080beb5b84e4f94399188b93d547f7a72b4cd89f7a97593a08e54057c736a8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('collections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_103_collections.sql
-- better-supabase module: collections
-- @bsb-block collections@1 managed
-- @bsb-hash sha256:818338625c398394dbb85eddda12576d8f8c0125f4c8dca4325c6b299cb658fd
-- Favorites (a member's ranked stars on any registered record), lists (named, static collections of one subject type owned by a user, a team or the organization) and saved items (a member's records to come back to, with a note and a reminder), with entries hidden unless the caller can read their record.
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
    drop policy if exists bsb_tenant_scope on "app_private"."subject_collections";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."subject_collection_entries";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."favorites";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."saved_items";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Favorites (a member's starred records, ranked for a sidebar), lists (named,
-- static collections of one subject type) and saved items (a member's records
-- to come back to, with a reminder) on config.records records.

create table if not exists "app_private"."subject_collections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope" text not null default 'user' check ("scope" in ('user', 'team', 'tenant')),
  "owner_id" uuid references auth.users (id) on delete cascade,
  "team_id" text,
  "name" text not null check (length("name") between 1 and 120),
  "description" text check (length("description") <= 2000),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("scope" <> 'user' or "owner_id" is not null),
  check ("scope" <> 'team' or "team_id" is not null)
);
create index if not exists subject_collections_tenant_type_idx on "app_private"."subject_collections" ("tenant_id", "subject_type", lower("name"));
create index if not exists subject_collections_owner_idx on "app_private"."subject_collections" ("owner_id") where "owner_id" is not null;
alter table "app_private"."subject_collections" enable row level security;
revoke all on "app_private"."subject_collections" from anon, authenticated;
grant select on "app_private"."subject_collections" to authenticated;
grant all on "app_private"."subject_collections" to service_role;

create table if not exists "app_private"."subject_collection_entries" (
  "collection_id" uuid not null references "app_private"."subject_collections" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "rank" text collate "C" not null,
  "added_by" uuid,
  "added_at" timestamptz not null default now(),
  primary key ("collection_id", "subject_id")
);
create index if not exists subject_collection_entries_rank_idx on "app_private"."subject_collection_entries" ("collection_id", "rank", "subject_id");
create index if not exists subject_collection_entries_subject_idx on "app_private"."subject_collection_entries" ("subject_type", "subject_id");
alter table "app_private"."subject_collection_entries" enable row level security;
revoke all on "app_private"."subject_collection_entries" from anon, authenticated;
grant select on "app_private"."subject_collection_entries" to authenticated;
grant all on "app_private"."subject_collection_entries" to service_role;

create table if not exists "app_private"."favorites" (
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "rank" text collate "C" not null,
  "created_at" timestamptz not null default now(),
  primary key ("user_id", "subject_type", "subject_id")
);
create index if not exists favorites_user_rank_idx on "app_private"."favorites" ("user_id", "tenant_id", "rank");
create index if not exists favorites_subject_idx on "app_private"."favorites" ("subject_type", "subject_id");
alter table "app_private"."favorites" enable row level security;
revoke all on "app_private"."favorites" from anon, authenticated;
grant select on "app_private"."favorites" to authenticated;
grant all on "app_private"."favorites" to service_role;

create table if not exists "app_private"."saved_items" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "note" text check (length("note") <= 1000),
  "remind_at" timestamptz,
  "reminded_at" timestamptz,
  "completed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("user_id", "subject_type", "subject_id")
);
create index if not exists saved_items_user_idx on "app_private"."saved_items" ("user_id", "tenant_id", "created_at" desc, "id" desc);
create index if not exists saved_items_subject_idx on "app_private"."saved_items" ("subject_type", "subject_id");
create index if not exists saved_items_due_idx on "app_private"."saved_items" ("remind_at") where "reminded_at" is null and "completed_at" is null;
alter table "app_private"."saved_items" enable row level security;
revoke all on "app_private"."saved_items" from anon, authenticated;
grant select on "app_private"."saved_items" to authenticated;
grant all on "app_private"."saved_items" to service_role;

-- A collection is visible to its owner, its team's members or the whole
-- tenant. An entry is visible when its collection is and the caller can
-- read its record, so a shared list never shows a record to someone who
-- can't open it. Stars and saved items are the caller's own.
drop policy if exists subject_collections_read on "app_private"."subject_collections";
create policy subject_collections_read on "app_private"."subject_collections" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read')) and (
  ("scope" = 'user' and "owner_id" = (select auth.uid()))
  or ("scope" = 'team' and false)
  or "scope" = 'tenant'
));
drop policy if exists subject_collection_entries_read on "app_private"."subject_collection_entries";
create policy subject_collection_entries_read on "app_private"."subject_collection_entries" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and exists (select 1 from "app_private"."subject_collections" c where c."id" = "collection_id")
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists favorites_read on "app_private"."favorites";
create policy favorites_read on "app_private"."favorites" for select to authenticated
using ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists saved_items_read on "app_private"."saved_items";
create policy saved_items_read on "app_private"."saved_items" for select to authenticated
using ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- A list of one subject type, owned by the caller (scope user), a team
-- they belong to, or the whole tenant. Shared scopes need collections.share.
drop function if exists "app_private"."create_collection"(uuid, text, text, text, text, text, jsonb);
create or replace function "app_private"."create_collection"(tenant uuid, subject_type text, name text, scope text, team text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_scope text := coalesce(create_collection.scope, 'user');
  v_name text := nullif(trim(create_collection.name), '');
  v_service boolean := auth.role() = 'service_role';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_scope not in ('user', 'team', 'tenant') then
    raise exception 'scope must be user, team or tenant' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if create_collection.subject_type is null or not (create_collection.subject_type = any ('{}'::text[])) then
    raise exception 'not a subject type in config.records' using errcode = '22023', hint = 'COLLECTION_SUBJECT_TYPE_UNKNOWN';
  end if;
  if v_name is null then
    raise exception 'a name is required' using errcode = '23502', hint = 'COLLECTION_NAME_REQUIRED';
  end if;
  if not (v_service or coalesce(better_supabase.can('tenant', create_collection.tenant, 'collections.write'), false)) then
    raise exception 'not allowed to create collections' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_scope = 'user' and auth.uid() is null then
    raise exception 'a personal collection needs a signed-in user' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if v_scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', create_collection.tenant, 'collections.share'), false)) then
    raise exception 'not allowed to share collections' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_scope = 'team' then
    if create_collection.team is null then
      raise exception 'a team collection needs a team' using errcode = '22023', hint = 'COLLECTION_INVALID';
    end if;
    if not (v_service or false) then
      raise exception 'not a member of this team' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_collection_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using create_collection.tenant, create_collection.subject_type, v_scope;
    end if;
  end;
  insert into "app_private"."subject_collections" ("tenant_id", "subject_type", "scope", "owner_id", "team_id", "name", "description", "created_by")
  values (create_collection.tenant, create_collection.subject_type, v_scope,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'team' then create_collection.team end,
    v_name, nullif(trim(create_collection.description), ''), auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_collection_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") from "app_private"."subject_collections" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."create_collection"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "app_private"."create_collection"(uuid, text, text, text, text, text) to authenticated, service_role;

-- A null name keeps it; an empty description clears it, a null one keeps it.
drop function if exists "app_private"."rename_collection"(uuid, text, text, jsonb);
create or replace function "app_private"."rename_collection"(collection uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "app_private"."subject_collections" where "id" = rename_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if rename_collection.name is not null and nullif(trim(rename_collection.name), '') is null then
    raise exception 'a name is required' using errcode = '23502', hint = 'COLLECTION_NAME_REQUIRED';
  end if;
  update "app_private"."subject_collections" x set
    "name" = coalesce(trim(rename_collection.name), x."name"),
    "description" = case when rename_collection.description is null then x."description"
      else nullif(trim(rename_collection.description), '') end,
    "updated_at" = now()
  where x."id" = v_row."id";
  return (select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") from "app_private"."subject_collections" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "app_private"."rename_collection"(uuid, text, text) from public, anon;
grant execute on function "app_private"."rename_collection"(uuid, text, text) to authenticated, service_role;

-- Archives a collection (archived true) or restores it. An archived
-- collection keeps its entries but takes no changes to them.
create or replace function "app_private"."archive_collection"(collection uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "app_private"."subject_collections" where "id" = archive_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  update "app_private"."subject_collections" x set
    "archived_at" = case when coalesce(archive_collection.archived, true) then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id";
  if coalesce(archive_collection.archived, true) and v_row."archived_at" is null then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_collection"(uuid, boolean) from public, anon;
grant execute on function "app_private"."archive_collection"(uuid, boolean) to authenticated, service_role;

-- The collections the caller sees in a tenant, by name: every subject type
-- when subject_type is null, archived ones only with include_archived.
create or replace function "app_private"."list_collections"(tenant uuid, subject_type text, include_archived boolean)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") order by lower(x."name"), x."id"), '[]'::jsonb)
  from "app_private"."subject_collections" x
  where x."tenant_id" = list_collections.tenant
    and (list_collections.subject_type is null or x."subject_type" = list_collections.subject_type)
    and (coalesce(list_collections.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "app_private"."list_collections"(uuid, text, boolean) from public, anon;
grant execute on function "app_private"."list_collections"(uuid, text, boolean) to authenticated, service_role;

-- Adds records to the end of a collection, in the order given. Ids already
-- in it are skipped; one the caller can't read fails the whole call.
-- subject_type, when given, must be the collection's.
create or replace function "app_private"."add_collection_entries"(collection uuid, subject_ids text[], subject_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."subject_collections";
  v_id text;
  v_last text;
  v_rank text;
  v_added text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  if cardinality(add_collection_entries.subject_ids) > 1000 then
    raise exception 'at most 1000 ids per call' using errcode = '22023', hint = 'COLLECTION_TOO_MANY';
  end if;
  
  select * into v_row from "app_private"."subject_collections" where "id" = add_collection_entries.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  if add_collection_entries.subject_type is not null and add_collection_entries.subject_type <> v_row."subject_type" then
    raise exception 'the collection holds another subject type' using errcode = '22023', hint = 'COLLECTION_SUBJECT_TYPE_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_collection_add"(uuid, text[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text[])', v_hook::oid::regproc)
        using v_row."id", add_collection_entries.subject_ids;
    end if;
  end;
  select max(e."rank") into v_last from "app_private"."subject_collection_entries" e where e."collection_id" = v_row."id";
  for v_id in
    select u.id from unnest(coalesce(add_collection_entries.subject_ids, '{}')) with ordinality u (id, n)
    where u.id is not null
    group by u.id order by min(u.n)
  loop
    if not false then
      raise exception 'a record is unknown or not readable in this organization' using errcode = '42501', hint = 'COLLECTION_SUBJECT_FORBIDDEN';
    end if;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "app_private"."subject_collection_entries" ("collection_id", "tenant_id", "subject_type", "subject_id", "rank", "added_by")
    values (v_row."id", v_row."tenant_id", v_row."subject_type", v_id, v_rank, auth.uid())
    on conflict do nothing;
    if found then
      v_last := v_rank;
      v_added := v_added || v_id;
      null;
    end if;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_collection_add"(uuid, text[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text[])', v_hook::oid::regproc)
        using v_row."id", v_added;
    end if;
  end;
  return jsonb_build_object('added', to_jsonb(v_added));
end;
$$;
revoke execute on function "app_private"."add_collection_entries"(uuid, text[], text) from public, anon;
grant execute on function "app_private"."add_collection_entries"(uuid, text[], text) to authenticated, service_role;

-- Removes the records the caller can read from a collection; returns how many.
create or replace function "app_private"."remove_collection_entries"(collection uuid, subject_ids text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."subject_collections";
  v_id text;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  if cardinality(remove_collection_entries.subject_ids) > 1000 then
    raise exception 'at most 1000 ids per call' using errcode = '22023', hint = 'COLLECTION_TOO_MANY';
  end if;
  
  select * into v_row from "app_private"."subject_collections" where "id" = remove_collection_entries.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  for v_id in
    delete from "app_private"."subject_collection_entries" e
    where e."collection_id" = v_row."id"
      and e."subject_id" = any (coalesce(remove_collection_entries.subject_ids, '{}'))
      and (auth.role() = 'service_role' or "better_supabase"."can_subject"(e."subject_type", e."subject_id", 'read'))
    returning e."subject_id"
  loop
    v_count := v_count + 1;
    null;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."remove_collection_entries"(uuid, text[]) from public, anon;
grant execute on function "app_private"."remove_collection_entries"(uuid, text[]) to authenticated, service_role;

create or replace function "app_private"."rank_collection_entry"(collection uuid, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_collection_entry.rank is null or rank_collection_entry.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'COLLECTION_RANK_INVALID';
  end if;
  
  select * into v_row from "app_private"."subject_collections" where "id" = rank_collection_entry.collection;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  update "app_private"."subject_collection_entries" e set "rank" = rank_collection_entry.rank
  where e."collection_id" = v_row."id" and e."subject_id" = rank_collection_entry.subject_id;
  return found;
end;
$$;
revoke execute on function "app_private"."rank_collection_entry"(uuid, text, text) from public, anon;
grant execute on function "app_private"."rank_collection_entry"(uuid, text, text) to authenticated, service_role;

-- A page of a collection's entries in rank order, with each record's title
-- and URL. after_rank and after_id continue after the previous page's last
-- entry. Entries whose record the caller can't read are left out.
create or replace function "app_private"."collection_entries"(collection uuid, after_rank text, after_id text, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.rank, p.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'collectionId', e."collection_id",
      'subjectType', e."subject_type",
      'subjectId', e."subject_id",
      'rank', e."rank",
      'addedBy', e."added_by",
      'addedAt', e."added_at",
      'title', "better_supabase"."subject_title"(e."subject_type", e."subject_id"),
      'url', "better_supabase"."subject_url"(e."subject_type", e."subject_id")
    ) as value, e."rank" as rank, e."subject_id" collate "C" as id
    from "app_private"."subject_collection_entries" e
    where e."collection_id" = collection_entries.collection
      and (collection_entries.after_rank is null
        or (e."rank", e."subject_id" collate "C") > (collection_entries.after_rank collate "C", coalesce(collection_entries.after_id, '') collate "C"))
    order by e."rank", e."subject_id" collate "C"
    limit least(greatest(coalesce(collection_entries.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "app_private"."collection_entries"(uuid, text, text, integer) from public, anon;
grant execute on function "app_private"."collection_entries"(uuid, text, text, integer) to authenticated, service_role;

-- The ids of a collection's records the caller can read, in rank order, at
-- most max_ids (default 500, up to 1000): a saved view's "in list" filter.
create or replace function "app_private"."collection_subject_ids"(collection uuid, max_ids integer)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(array_agg(p.id order by p.rank, p.id), '{}')
  from (
    select e."subject_id" collate "C" as id, e."rank" as rank
    from "app_private"."subject_collection_entries" e
    where e."collection_id" = collection_subject_ids.collection
    order by e."rank", e."subject_id" collate "C"
    limit least(greatest(coalesce(collection_subject_ids.max_ids, 500), 1), 1000)
  ) p
$$;
revoke execute on function "app_private"."collection_subject_ids"(uuid, integer) from public, anon;
grant execute on function "app_private"."collection_subject_ids"(uuid, integer) to authenticated, service_role;

-- The active collections the caller sees that hold a record, by name.
create or replace function "app_private"."collections_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") order by lower(x."name"), x."id"), '[]'::jsonb)
  from "app_private"."subject_collections" x
  join "app_private"."subject_collection_entries" e on e."collection_id" = x."id"
  where e."subject_type" = collections_of.subject_type
    and e."subject_id" = collections_of.subject_id
    and x."archived_at" is null
$$;
revoke execute on function "app_private"."collections_of"(text, text) from public, anon;
grant execute on function "app_private"."collections_of"(text, text) to authenticated, service_role;

-- Stars a record the caller can read, at the end of their favorites. A
-- record already starred keeps its place.
create or replace function "app_private"."star_subject"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'a star needs a signed-in user' using errcode = '22023', hint = 'FAVORITE_INVALID';
  end if;
  if not coalesce(better_supabase.can('tenant', star_subject.tenant, 'collections.read'), false) then
    raise exception 'not allowed to star records' using errcode = '42501', hint = 'FAVORITE_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record is unknown or not readable in this organization' using errcode = '42501', hint = 'FAVORITE_SUBJECT_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "app_private"."favorites" f
    where f."user_id" = v_user and f."subject_type" = star_subject.subject_type and f."subject_id" = star_subject.subject_id
  ) then
    select max(f."rank") into v_last from "app_private"."favorites" f
      where f."user_id" = v_user and f."tenant_id" = star_subject.tenant;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "app_private"."favorites" ("user_id", "tenant_id", "subject_type", "subject_id", "rank")
    values (v_user, star_subject.tenant, star_subject.subject_type, star_subject.subject_id, v_rank)
    on conflict do nothing;
  end if;
  return (select jsonb_build_object(
      'subjectType', f."subject_type",
      'subjectId', f."subject_id",
      'organizationId', f."tenant_id",
      'rank', f."rank",
      'starredAt', f."created_at") from "app_private"."favorites" f
    where f."user_id" = v_user and f."subject_type" = star_subject.subject_type and f."subject_id" = star_subject.subject_id);
end;
$$;
revoke execute on function "app_private"."star_subject"(uuid, text, text) from public, anon;
grant execute on function "app_private"."star_subject"(uuid, text, text) to authenticated, service_role;

create or replace function "app_private"."unstar_subject"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "app_private"."favorites" f
  where f."user_id" = auth.uid() and f."subject_type" = unstar_subject.subject_type and f."subject_id" = unstar_subject.subject_id;
  return found;
end;
$$;
revoke execute on function "app_private"."unstar_subject"(text, text) from public, anon;
grant execute on function "app_private"."unstar_subject"(text, text) to authenticated, service_role;

create or replace function "app_private"."rank_star"(subject_type text, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_star.rank is null or rank_star.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FAVORITE_RANK_INVALID';
  end if;
  update "app_private"."favorites" f set "rank" = rank_star.rank
  where f."user_id" = auth.uid() and f."subject_type" = rank_star.subject_type and f."subject_id" = rank_star.subject_id;
  return found;
end;
$$;
revoke execute on function "app_private"."rank_star"(text, text, text) from public, anon;
grant execute on function "app_private"."rank_star"(text, text, text) to authenticated, service_role;

-- The caller's stars in a tenant in sidebar order, with each record's title
-- and URL: every subject type when subject_type is null.
create or replace function "app_private"."starred_subjects"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'subjectType', f."subject_type",
      'subjectId', f."subject_id",
      'organizationId', f."tenant_id",
      'rank', f."rank",
      'starredAt', f."created_at") || jsonb_build_object(
      'title', "better_supabase"."subject_title"(f."subject_type", f."subject_id"),
      'url', "better_supabase"."subject_url"(f."subject_type", f."subject_id"))
    order by f."rank", f."subject_type", f."subject_id" collate "C"), '[]'::jsonb)
  from "app_private"."favorites" f
  where f."user_id" = (select auth.uid())
    and f."tenant_id" = starred_subjects.tenant
    and (starred_subjects.subject_type is null or f."subject_type" = starred_subjects.subject_type)
$$;
revoke execute on function "app_private"."starred_subjects"(uuid, text) from public, anon;
grant execute on function "app_private"."starred_subjects"(uuid, text) to authenticated, service_role;

-- Saves a record the caller can read for later. Saving it again replaces the
-- note and reminder and reopens a completed item.
create or replace function "app_private"."save_for_later"(tenant uuid, subject_type text, subject_id text, note text default null, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_note text := nullif(btrim(save_for_later.note), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'saving for later needs a signed-in user' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  if not coalesce(better_supabase.can('tenant', save_for_later.tenant, 'collections.read'), false) then
    raise exception 'not allowed to save records' using errcode = '42501', hint = 'SAVED_ITEM_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record is unknown or not readable in this organization' using errcode = '42501', hint = 'SAVED_ITEM_SUBJECT_FORBIDDEN';
  end if;
  if length(v_note) > 1000 then
    raise exception 'a note holds at most 1000 characters' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  if save_for_later.remind_at is not null and save_for_later.remind_at <= now() then
    raise exception 'the reminder time must be in the future' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  insert into "app_private"."saved_items" ("user_id", "tenant_id", "subject_type", "subject_id", "note", "remind_at")
  values (v_user, save_for_later.tenant, save_for_later.subject_type, save_for_later.subject_id, v_note, save_for_later.remind_at)
  on conflict ("user_id", "subject_type", "subject_id") do update
    set "note" = excluded."note",
      "remind_at" = excluded."remind_at",
      "reminded_at" = null,
      "completed_at" = null;
  return (select jsonb_build_object(
      'id', s."id",
      'organizationId', s."tenant_id",
      'userId', s."user_id",
      'subjectType', s."subject_type",
      'subjectId', s."subject_id",
      'note', s."note",
      'remindAt', s."remind_at",
      'remindedAt', s."reminded_at",
      'completedAt', s."completed_at",
      'createdAt', s."created_at") from "app_private"."saved_items" s
    where s."user_id" = v_user and s."subject_type" = save_for_later.subject_type and s."subject_id" = save_for_later.subject_id);
end;
$$;
revoke execute on function "app_private"."save_for_later"(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "app_private"."save_for_later"(uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Marks one of the caller's saved items completed, or open again with
-- completed false.
create or replace function "app_private"."complete_saved_item"(item uuid, completed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "app_private"."saved_items" s
    set "completed_at" = case when complete_saved_item.completed then coalesce(s."completed_at", now()) end
    where s."id" = complete_saved_item.item and s."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "app_private"."complete_saved_item"(uuid, boolean) from public, anon;
grant execute on function "app_private"."complete_saved_item"(uuid, boolean) to authenticated, service_role;

create or replace function "app_private"."remove_saved_item"(item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "app_private"."saved_items" s
    where s."id" = remove_saved_item.item and s."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "app_private"."remove_saved_item"(uuid) from public, anon;
grant execute on function "app_private"."remove_saved_item"(uuid) to authenticated, service_role;

-- The caller's saved items in a tenant, the newest first, with each record's
-- title and URL: the open ones, or the completed ones with completed true.
create or replace function "app_private"."list_saved_items"(tenant uuid, completed boolean default false, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(item order by created_at desc, id desc), '[]'::jsonb)
  from (
    select s."created_at" as created_at, s."id" as id, jsonb_build_object(
      'id', s."id",
      'organizationId', s."tenant_id",
      'userId', s."user_id",
      'subjectType', s."subject_type",
      'subjectId', s."subject_id",
      'note', s."note",
      'remindAt', s."remind_at",
      'remindedAt', s."reminded_at",
      'completedAt', s."completed_at",
      'createdAt', s."created_at") || jsonb_build_object(
        'title', "better_supabase"."subject_title"(s."subject_type", s."subject_id"),
        'url', "better_supabase"."subject_url"(s."subject_type", s."subject_id")) as item
    from "app_private"."saved_items" s
    where s."user_id" = (select auth.uid())
      and s."tenant_id" = list_saved_items.tenant
      and (s."completed_at" is not null) = coalesce(list_saved_items.completed, false)
      and (list_saved_items.before is null
        or (s."created_at", s."id") < (list_saved_items.before, coalesce(list_saved_items.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by s."created_at" desc, s."id" desc
    limit least(greatest(coalesce(list_saved_items.max_rows, 50), 1), 200)
  ) page
$$;
revoke execute on function "app_private"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) from public, anon;
grant execute on function "app_private"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) to authenticated, service_role;

-- Service role. Claims the open saved items whose reminder time has passed,
-- records saved_item.reminded for each and returns them. A claimed item is not
-- returned again until it is saved with a new reminder.
create or replace function "app_private"."remind_due_saved_items"(max_rows integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."saved_items"%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not auth.role() = 'service_role' then
    raise exception 'only the service role sends saved item reminders' using errcode = '42501', hint = 'SAVED_ITEM_FORBIDDEN';
  end if;
  for v_row in
    update "app_private"."saved_items" s set "reminded_at" = now()
    where s."id" in (
      select d."id" from "app_private"."saved_items" d
      where d."remind_at" <= now() and d."reminded_at" is null and d."completed_at" is null
      order by d."remind_at", d."id"
      limit least(greatest(coalesce(remind_due_saved_items.max_rows, 100), 1), 500)
      for update skip locked
    )
    returning s.*
  loop
    null;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', v_row."id",
      'organizationId', v_row."tenant_id",
      'userId', v_row."user_id",
      'subjectType', v_row."subject_type",
      'subjectId', v_row."subject_id",
      'note', v_row."note",
      'remindAt', v_row."remind_at",
      'remindedAt', v_row."reminded_at",
      'completedAt', v_row."completed_at",
      'createdAt', v_row."created_at"));
  end loop;
  return v_out;
end;
$$;
revoke execute on function "app_private"."remind_due_saved_items"(integer) from public, anon, authenticated;
grant execute on function "app_private"."remind_due_saved_items"(integer) to service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "app_private"."subject_collections";
create policy bsb_tenant_scope on "app_private"."subject_collections" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read')) and (
  ("scope" = 'user' and "owner_id" = (select auth.uid()))
  or ("scope" = 'team' and false)
  or "scope" = 'tenant'
))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."subject_collection_entries";
create policy bsb_tenant_scope on "app_private"."subject_collection_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and exists (select 1 from "app_private"."subject_collections" c where c."id" = "collection_id")
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."favorites";
create policy bsb_tenant_scope on "app_private"."favorites" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."saved_items";
create policy bsb_tenant_scope on "app_private"."saved_items" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_103_collections.sql
-- better-supabase module: collections
-- @bsb-block-data collections
-- @bsb-hash sha256:77080beb5b84e4f94399188b93d547f7a72b4cd89f7a97593a08e54057c736a8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('collections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_103_collections.sql
-- better-supabase module: collections
-- @bsb-block collections@1 managed
-- @bsb-hash sha256:29125474d2c5b8e8edd4dafda710546b3b59a1bd2cbc0b86a61f7fce6086777f
-- Favorites (a member's ranked stars on any registered record), lists (named, static collections of one subject type owned by a user, a team or the organization) and saved items (a member's records to come back to, with a note and a reminder), with entries hidden unless the caller can read their record.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collections";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collection_entries";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."favorites";
  exception when undefined_table then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."saved_items";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Favorites (a member's starred records, ranked for a sidebar), lists (named,
-- static collections of one subject type) and saved items (a member's records
-- to come back to, with a reminder) on config.records records.

create table if not exists "better_supabase"."subject_collections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "scope" text not null default 'user' check ("scope" in ('user', 'team', 'tenant')),
  "owner_id" uuid references auth.users (id) on delete cascade,
  "team_id" text,
  "name" text not null check (length("name") between 1 and 120),
  "description" text check (length("description") <= 2000),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("scope" <> 'user' or "owner_id" is not null),
  check ("scope" <> 'team' or "team_id" is not null)
);
create index if not exists subject_collections_tenant_type_idx on "better_supabase"."subject_collections" ("tenant_id", "subject_type", lower("name"));
create index if not exists subject_collections_owner_idx on "better_supabase"."subject_collections" ("owner_id") where "owner_id" is not null;
alter table "better_supabase"."subject_collections" enable row level security;
revoke all on "better_supabase"."subject_collections" from anon, authenticated;
grant select on "better_supabase"."subject_collections" to authenticated;
grant all on "better_supabase"."subject_collections" to service_role;

create table if not exists "better_supabase"."subject_collection_entries" (
  "collection_id" uuid not null references "better_supabase"."subject_collections" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "rank" text collate "C" not null,
  "added_by" uuid,
  "added_at" timestamptz not null default now(),
  primary key ("collection_id", "subject_id")
);
create index if not exists subject_collection_entries_rank_idx on "better_supabase"."subject_collection_entries" ("collection_id", "rank", "subject_id");
create index if not exists subject_collection_entries_subject_idx on "better_supabase"."subject_collection_entries" ("subject_type", "subject_id");
alter table "better_supabase"."subject_collection_entries" enable row level security;
revoke all on "better_supabase"."subject_collection_entries" from anon, authenticated;
grant select on "better_supabase"."subject_collection_entries" to authenticated;
grant all on "better_supabase"."subject_collection_entries" to service_role;

create table if not exists "better_supabase"."favorites" (
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "rank" text collate "C" not null,
  "created_at" timestamptz not null default now(),
  primary key ("user_id", "subject_type", "subject_id")
);
create index if not exists favorites_user_rank_idx on "better_supabase"."favorites" ("user_id", "tenant_id", "rank");
create index if not exists favorites_subject_idx on "better_supabase"."favorites" ("subject_type", "subject_id");
alter table "better_supabase"."favorites" enable row level security;
revoke all on "better_supabase"."favorites" from anon, authenticated;
grant select on "better_supabase"."favorites" to authenticated;
grant all on "better_supabase"."favorites" to service_role;

create table if not exists "better_supabase"."saved_items" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "note" text check (length("note") <= 1000),
  "remind_at" timestamptz,
  "reminded_at" timestamptz,
  "completed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("user_id", "subject_type", "subject_id")
);
create index if not exists saved_items_user_idx on "better_supabase"."saved_items" ("user_id", "tenant_id", "created_at" desc, "id" desc);
create index if not exists saved_items_subject_idx on "better_supabase"."saved_items" ("subject_type", "subject_id");
create index if not exists saved_items_due_idx on "better_supabase"."saved_items" ("remind_at") where "reminded_at" is null and "completed_at" is null;
alter table "better_supabase"."saved_items" enable row level security;
revoke all on "better_supabase"."saved_items" from anon, authenticated;
grant select on "better_supabase"."saved_items" to authenticated;
grant all on "better_supabase"."saved_items" to service_role;

-- A collection is visible to its owner, its team's members or the whole
-- tenant. An entry is visible when its collection is and the caller can
-- read its record, so a shared list never shows a record to someone who
-- can't open it. Stars and saved items are the caller's own.
drop policy if exists subject_collections_read on "better_supabase"."subject_collections";
create policy subject_collections_read on "better_supabase"."subject_collections" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read')) and (
  ("scope" = 'user' and "owner_id" = (select auth.uid()))
  or ("scope" = 'team' and false)
  or "scope" = 'tenant'
));
drop policy if exists subject_collection_entries_read on "better_supabase"."subject_collection_entries";
create policy subject_collection_entries_read on "better_supabase"."subject_collection_entries" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and exists (select 1 from "better_supabase"."subject_collections" c where c."id" = "collection_id")
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists favorites_read on "better_supabase"."favorites";
create policy favorites_read on "better_supabase"."favorites" for select to authenticated
using ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists saved_items_read on "better_supabase"."saved_items";
create policy saved_items_read on "better_supabase"."saved_items" for select to authenticated
using ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- A list of one subject type, owned by the caller (scope user), a team
-- they belong to, or the whole tenant. Shared scopes need collections.share.
drop function if exists "better_supabase"."create_collection"(uuid, text, text, text, text, text, jsonb);
create or replace function "better_supabase"."create_collection"(tenant uuid, subject_type text, name text, scope text, team text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_scope text := coalesce(create_collection.scope, 'user');
  v_name text := nullif(trim(create_collection.name), '');
  v_service boolean := auth.role() = 'service_role';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_scope not in ('user', 'team', 'tenant') then
    raise exception 'scope must be user, team or tenant' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if create_collection.subject_type is null or not (create_collection.subject_type = any ('{}'::text[])) then
    raise exception 'not a subject type in config.records' using errcode = '22023', hint = 'COLLECTION_SUBJECT_TYPE_UNKNOWN';
  end if;
  if v_name is null then
    raise exception 'a name is required' using errcode = '23502', hint = 'COLLECTION_NAME_REQUIRED';
  end if;
  if not (v_service or coalesce(better_supabase.can('tenant', create_collection.tenant, 'collections.write'), false)) then
    raise exception 'not allowed to create collections' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_scope = 'user' and auth.uid() is null then
    raise exception 'a personal collection needs a signed-in user' using errcode = '22023', hint = 'COLLECTION_INVALID';
  end if;
  if v_scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', create_collection.tenant, 'collections.share'), false)) then
    raise exception 'not allowed to share collections' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_scope = 'team' then
    if create_collection.team is null then
      raise exception 'a team collection needs a team' using errcode = '22023', hint = 'COLLECTION_INVALID';
    end if;
    if not (v_service or false) then
      raise exception 'not a member of this team' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_collection_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using create_collection.tenant, create_collection.subject_type, v_scope;
    end if;
  end;
  insert into "better_supabase"."subject_collections" ("tenant_id", "subject_type", "scope", "owner_id", "team_id", "name", "description", "created_by")
  values (create_collection.tenant, create_collection.subject_type, v_scope,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'team' then create_collection.team end,
    v_name, nullif(trim(create_collection.description), ''), auth.uid())
  returning "id" into v_id;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_collection_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") from "better_supabase"."subject_collections" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_collection"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_collection"(uuid, text, text, text, text, text) to authenticated, service_role;

-- A null name keeps it; an empty description clears it, a null one keeps it.
drop function if exists "better_supabase"."rename_collection"(uuid, text, text, jsonb);
create or replace function "better_supabase"."rename_collection"(collection uuid, name text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = rename_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if rename_collection.name is not null and nullif(trim(rename_collection.name), '') is null then
    raise exception 'a name is required' using errcode = '23502', hint = 'COLLECTION_NAME_REQUIRED';
  end if;
  update "better_supabase"."subject_collections" x set
    "name" = coalesce(trim(rename_collection.name), x."name"),
    "description" = case when rename_collection.description is null then x."description"
      else nullif(trim(rename_collection.description), '') end,
    "updated_at" = now()
  where x."id" = v_row."id";
  return (select jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") from "better_supabase"."subject_collections" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."rename_collection"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."rename_collection"(uuid, text, text) to authenticated, service_role;

-- Archives a collection (archived true) or restores it. An archived
-- collection keeps its entries but takes no changes to them.
create or replace function "better_supabase"."archive_collection"(collection uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = archive_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  update "better_supabase"."subject_collections" x set
    "archived_at" = case when coalesce(archive_collection.archived, true) then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id";
  if coalesce(archive_collection.archived, true) and v_row."archived_at" is null then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_collection"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_collection"(uuid, boolean) to authenticated, service_role;

-- The collections the caller sees in a tenant, by name: every subject type
-- when subject_type is null, archived ones only with include_archived.
create or replace function "better_supabase"."list_collections"(tenant uuid, subject_type text, include_archived boolean)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") order by lower(x."name"), x."id"), '[]'::jsonb)
  from "better_supabase"."subject_collections" x
  where x."tenant_id" = list_collections.tenant
    and (list_collections.subject_type is null or x."subject_type" = list_collections.subject_type)
    and (coalesce(list_collections.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_collections"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_collections"(uuid, text, boolean) to authenticated, service_role;

-- Adds records to the end of a collection, in the order given. Ids already
-- in it are skipped; one the caller can't read fails the whole call.
-- subject_type, when given, must be the collection's.
create or replace function "better_supabase"."add_collection_entries"(collection uuid, subject_ids text[], subject_type text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
  v_id text;
  v_last text;
  v_rank text;
  v_added text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  if cardinality(add_collection_entries.subject_ids) > 1000 then
    raise exception 'at most 1000 ids per call' using errcode = '22023', hint = 'COLLECTION_TOO_MANY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = add_collection_entries.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  if add_collection_entries.subject_type is not null and add_collection_entries.subject_type <> v_row."subject_type" then
    raise exception 'the collection holds another subject type' using errcode = '22023', hint = 'COLLECTION_SUBJECT_TYPE_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_collection_add"(uuid, text[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text[])', v_hook::oid::regproc)
        using v_row."id", add_collection_entries.subject_ids;
    end if;
  end;
  select max(e."rank") into v_last from "better_supabase"."subject_collection_entries" e where e."collection_id" = v_row."id";
  for v_id in
    select u.id from unnest(coalesce(add_collection_entries.subject_ids, '{}')) with ordinality u (id, n)
    where u.id is not null
    group by u.id order by min(u.n)
  loop
    if not false then
      raise exception 'a record is unknown or not readable in this organization' using errcode = '42501', hint = 'COLLECTION_SUBJECT_FORBIDDEN';
    end if;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."subject_collection_entries" ("collection_id", "tenant_id", "subject_type", "subject_id", "rank", "added_by")
    values (v_row."id", v_row."tenant_id", v_row."subject_type", v_id, v_rank, auth.uid())
    on conflict do nothing;
    if found then
      v_last := v_rank;
      v_added := v_added || v_id;
      null;
    end if;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_collection_add"(uuid, text[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text[])', v_hook::oid::regproc)
        using v_row."id", v_added;
    end if;
  end;
  return jsonb_build_object('added', to_jsonb(v_added));
end;
$$;
revoke execute on function "better_supabase"."add_collection_entries"(uuid, text[], text) from public, anon;
grant execute on function "better_supabase"."add_collection_entries"(uuid, text[], text) to authenticated, service_role;

-- Removes the records the caller can read from a collection; returns how many.
create or replace function "better_supabase"."remove_collection_entries"(collection uuid, subject_ids text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
  v_id text;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  if cardinality(remove_collection_entries.subject_ids) > 1000 then
    raise exception 'at most 1000 ids per call' using errcode = '22023', hint = 'COLLECTION_TOO_MANY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = remove_collection_entries.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  for v_id in
    delete from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = v_row."id"
      and e."subject_id" = any (coalesce(remove_collection_entries.subject_ids, '{}'))
      and (auth.role() = 'service_role' or "better_supabase"."can_subject"(e."subject_type", e."subject_id", 'read'))
    returning e."subject_id"
  loop
    v_count := v_count + 1;
    null;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."remove_collection_entries"(uuid, text[]) from public, anon;
grant execute on function "better_supabase"."remove_collection_entries"(uuid, text[]) to authenticated, service_role;

create or replace function "better_supabase"."rank_collection_entry"(collection uuid, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_collection_entry.rank is null or rank_collection_entry.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'COLLECTION_RANK_INVALID';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = rank_collection_entry.collection;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  
  if not (auth.role() = 'service_role' or ((auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
      or (v_row."scope" = 'team' and false)
      or v_row."scope" = 'tenant'))) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))) then
    raise exception 'not allowed to change this collection''s entries' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the collection is archived' using errcode = '55000', hint = 'COLLECTION_ARCHIVED';
  end if;
  update "better_supabase"."subject_collection_entries" e set "rank" = rank_collection_entry.rank
  where e."collection_id" = v_row."id" and e."subject_id" = rank_collection_entry.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."rank_collection_entry"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."rank_collection_entry"(uuid, text, text) to authenticated, service_role;

-- A page of a collection's entries in rank order, with each record's title
-- and URL. after_rank and after_id continue after the previous page's last
-- entry. Entries whose record the caller can't read are left out.
create or replace function "better_supabase"."collection_entries"(collection uuid, after_rank text, after_id text, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.rank, p.id), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'collectionId', e."collection_id",
      'subjectType', e."subject_type",
      'subjectId', e."subject_id",
      'rank', e."rank",
      'addedBy', e."added_by",
      'addedAt', e."added_at",
      'title', "better_supabase"."subject_title"(e."subject_type", e."subject_id"),
      'url', "better_supabase"."subject_url"(e."subject_type", e."subject_id")
    ) as value, e."rank" as rank, e."subject_id" collate "C" as id
    from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = collection_entries.collection
      and (collection_entries.after_rank is null
        or (e."rank", e."subject_id" collate "C") > (collection_entries.after_rank collate "C", coalesce(collection_entries.after_id, '') collate "C"))
    order by e."rank", e."subject_id" collate "C"
    limit least(greatest(coalesce(collection_entries.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."collection_entries"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."collection_entries"(uuid, text, text, integer) to authenticated, service_role;

-- The ids of a collection's records the caller can read, in rank order, at
-- most max_ids (default 500, up to 1000): a saved view's "in list" filter.
create or replace function "better_supabase"."collection_subject_ids"(collection uuid, max_ids integer)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(array_agg(p.id order by p.rank, p.id), '{}')
  from (
    select e."subject_id" collate "C" as id, e."rank" as rank
    from "better_supabase"."subject_collection_entries" e
    where e."collection_id" = collection_subject_ids.collection
    order by e."rank", e."subject_id" collate "C"
    limit least(greatest(coalesce(collection_subject_ids.max_ids, 500), 1), 1000)
  ) p
$$;
revoke execute on function "better_supabase"."collection_subject_ids"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."collection_subject_ids"(uuid, integer) to authenticated, service_role;

-- The active collections the caller sees that hold a record, by name.
create or replace function "better_supabase"."collections_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'subjectType', x."subject_type",
    'scope', x."scope",
    'ownerId', x."owner_id",
    'teamId', x."team_id",
    'name', x."name",
    'description', x."description",
    'archivedAt', x."archived_at",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at") order by lower(x."name"), x."id"), '[]'::jsonb)
  from "better_supabase"."subject_collections" x
  join "better_supabase"."subject_collection_entries" e on e."collection_id" = x."id"
  where e."subject_type" = collections_of.subject_type
    and e."subject_id" = collections_of.subject_id
    and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."collections_of"(text, text) from public, anon;
grant execute on function "better_supabase"."collections_of"(text, text) to authenticated, service_role;

-- Stars a record the caller can read, at the end of their favorites. A
-- record already starred keeps its place.
create or replace function "better_supabase"."star_subject"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'a star needs a signed-in user' using errcode = '22023', hint = 'FAVORITE_INVALID';
  end if;
  if not coalesce(better_supabase.can('tenant', star_subject.tenant, 'collections.read'), false) then
    raise exception 'not allowed to star records' using errcode = '42501', hint = 'FAVORITE_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record is unknown or not readable in this organization' using errcode = '42501', hint = 'FAVORITE_SUBJECT_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "better_supabase"."favorites" f
    where f."user_id" = v_user and f."subject_type" = star_subject.subject_type and f."subject_id" = star_subject.subject_id
  ) then
    select max(f."rank") into v_last from "better_supabase"."favorites" f
      where f."user_id" = v_user and f."tenant_id" = star_subject.tenant;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."favorites" ("user_id", "tenant_id", "subject_type", "subject_id", "rank")
    values (v_user, star_subject.tenant, star_subject.subject_type, star_subject.subject_id, v_rank)
    on conflict do nothing;
  end if;
  return (select jsonb_build_object(
      'subjectType', f."subject_type",
      'subjectId', f."subject_id",
      'organizationId', f."tenant_id",
      'rank', f."rank",
      'starredAt', f."created_at") from "better_supabase"."favorites" f
    where f."user_id" = v_user and f."subject_type" = star_subject.subject_type and f."subject_id" = star_subject.subject_id);
end;
$$;
revoke execute on function "better_supabase"."star_subject"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."star_subject"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."unstar_subject"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."favorites" f
  where f."user_id" = auth.uid() and f."subject_type" = unstar_subject.subject_type and f."subject_id" = unstar_subject.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."unstar_subject"(text, text) from public, anon;
grant execute on function "better_supabase"."unstar_subject"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."rank_star"(subject_type text, subject_id text, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_star.rank is null or rank_star.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'FAVORITE_RANK_INVALID';
  end if;
  update "better_supabase"."favorites" f set "rank" = rank_star.rank
  where f."user_id" = auth.uid() and f."subject_type" = rank_star.subject_type and f."subject_id" = rank_star.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."rank_star"(text, text, text) from public, anon;
grant execute on function "better_supabase"."rank_star"(text, text, text) to authenticated, service_role;

-- The caller's stars in a tenant in sidebar order, with each record's title
-- and URL: every subject type when subject_type is null.
create or replace function "better_supabase"."starred_subjects"(tenant uuid, subject_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'subjectType', f."subject_type",
      'subjectId', f."subject_id",
      'organizationId', f."tenant_id",
      'rank', f."rank",
      'starredAt', f."created_at") || jsonb_build_object(
      'title', "better_supabase"."subject_title"(f."subject_type", f."subject_id"),
      'url', "better_supabase"."subject_url"(f."subject_type", f."subject_id"))
    order by f."rank", f."subject_type", f."subject_id" collate "C"), '[]'::jsonb)
  from "better_supabase"."favorites" f
  where f."user_id" = (select auth.uid())
    and f."tenant_id" = starred_subjects.tenant
    and (starred_subjects.subject_type is null or f."subject_type" = starred_subjects.subject_type)
$$;
revoke execute on function "better_supabase"."starred_subjects"(uuid, text) from public, anon;
grant execute on function "better_supabase"."starred_subjects"(uuid, text) to authenticated, service_role;

-- Saves a record the caller can read for later. Saving it again replaces the
-- note and reminder and reopens a completed item.
create or replace function "better_supabase"."save_for_later"(tenant uuid, subject_type text, subject_id text, note text default null, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_note text := nullif(btrim(save_for_later.note), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'saving for later needs a signed-in user' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  if not coalesce(better_supabase.can('tenant', save_for_later.tenant, 'collections.read'), false) then
    raise exception 'not allowed to save records' using errcode = '42501', hint = 'SAVED_ITEM_FORBIDDEN';
  end if;
  if not false then
    raise exception 'the record is unknown or not readable in this organization' using errcode = '42501', hint = 'SAVED_ITEM_SUBJECT_FORBIDDEN';
  end if;
  if length(v_note) > 1000 then
    raise exception 'a note holds at most 1000 characters' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  if save_for_later.remind_at is not null and save_for_later.remind_at <= now() then
    raise exception 'the reminder time must be in the future' using errcode = '22023', hint = 'SAVED_ITEM_INVALID';
  end if;
  insert into "better_supabase"."saved_items" ("user_id", "tenant_id", "subject_type", "subject_id", "note", "remind_at")
  values (v_user, save_for_later.tenant, save_for_later.subject_type, save_for_later.subject_id, v_note, save_for_later.remind_at)
  on conflict ("user_id", "subject_type", "subject_id") do update
    set "note" = excluded."note",
      "remind_at" = excluded."remind_at",
      "reminded_at" = null,
      "completed_at" = null;
  return (select jsonb_build_object(
      'id', s."id",
      'organizationId', s."tenant_id",
      'userId', s."user_id",
      'subjectType', s."subject_type",
      'subjectId', s."subject_id",
      'note', s."note",
      'remindAt', s."remind_at",
      'remindedAt', s."reminded_at",
      'completedAt', s."completed_at",
      'createdAt', s."created_at") from "better_supabase"."saved_items" s
    where s."user_id" = v_user and s."subject_type" = save_for_later.subject_type and s."subject_id" = save_for_later.subject_id);
end;
$$;
revoke execute on function "better_supabase"."save_for_later"(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_for_later"(uuid, text, text, text, timestamptz) to authenticated, service_role;

-- Marks one of the caller's saved items completed, or open again with
-- completed false.
create or replace function "better_supabase"."complete_saved_item"(item uuid, completed boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."saved_items" s
    set "completed_at" = case when complete_saved_item.completed then coalesce(s."completed_at", now()) end
    where s."id" = complete_saved_item.item and s."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."complete_saved_item"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."complete_saved_item"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_saved_item"(item uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."saved_items" s
    where s."id" = remove_saved_item.item and s."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_saved_item"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_saved_item"(uuid) to authenticated, service_role;

-- The caller's saved items in a tenant, the newest first, with each record's
-- title and URL: the open ones, or the completed ones with completed true.
create or replace function "better_supabase"."list_saved_items"(tenant uuid, completed boolean default false, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(item order by created_at desc, id desc), '[]'::jsonb)
  from (
    select s."created_at" as created_at, s."id" as id, jsonb_build_object(
      'id', s."id",
      'organizationId', s."tenant_id",
      'userId', s."user_id",
      'subjectType', s."subject_type",
      'subjectId', s."subject_id",
      'note', s."note",
      'remindAt', s."remind_at",
      'remindedAt', s."reminded_at",
      'completedAt', s."completed_at",
      'createdAt', s."created_at") || jsonb_build_object(
        'title', "better_supabase"."subject_title"(s."subject_type", s."subject_id"),
        'url', "better_supabase"."subject_url"(s."subject_type", s."subject_id")) as item
    from "better_supabase"."saved_items" s
    where s."user_id" = (select auth.uid())
      and s."tenant_id" = list_saved_items.tenant
      and (s."completed_at" is not null) = coalesce(list_saved_items.completed, false)
      and (list_saved_items.before is null
        or (s."created_at", s."id") < (list_saved_items.before, coalesce(list_saved_items.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by s."created_at" desc, s."id" desc
    limit least(greatest(coalesce(list_saved_items.max_rows, 50), 1), 200)
  ) page
$$;
revoke execute on function "better_supabase"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) to authenticated, service_role;

-- Service role. Claims the open saved items whose reminder time has passed,
-- records saved_item.reminded for each and returns them. A claimed item is not
-- returned again until it is saved with a new reminder.
create or replace function "better_supabase"."remind_due_saved_items"(max_rows integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."saved_items"%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not auth.role() = 'service_role' then
    raise exception 'only the service role sends saved item reminders' using errcode = '42501', hint = 'SAVED_ITEM_FORBIDDEN';
  end if;
  for v_row in
    update "better_supabase"."saved_items" s set "reminded_at" = now()
    where s."id" in (
      select d."id" from "better_supabase"."saved_items" d
      where d."remind_at" <= now() and d."reminded_at" is null and d."completed_at" is null
      order by d."remind_at", d."id"
      limit least(greatest(coalesce(remind_due_saved_items.max_rows, 100), 1), 500)
      for update skip locked
    )
    returning s.*
  loop
    null;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', v_row."id",
      'organizationId', v_row."tenant_id",
      'userId', v_row."user_id",
      'subjectType', v_row."subject_type",
      'subjectId', v_row."subject_id",
      'note', v_row."note",
      'remindAt', v_row."remind_at",
      'remindedAt', v_row."reminded_at",
      'completedAt', v_row."completed_at",
      'createdAt', v_row."created_at"));
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."remind_due_saved_items"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."remind_due_saved_items"(integer) to service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collections";
create policy bsb_tenant_scope on "better_supabase"."subject_collections" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read')) and (
  ("scope" = 'user' and "owner_id" = (select auth.uid()))
  or ("scope" = 'team' and false)
  or "scope" = 'tenant'
))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_collection_entries";
create policy bsb_tenant_scope on "better_supabase"."subject_collection_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and exists (select 1 from "better_supabase"."subject_collections" c where c."id" = "collection_id")
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."favorites";
create policy bsb_tenant_scope on "better_supabase"."favorites" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."saved_items";
create policy bsb_tenant_scope on "better_supabase"."saved_items" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  and "tenant_id" in (select better_supabase.tenant_ids_with('collections.read'))
  and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.collections.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_collection"(uuid, text, text, text, text, text, jsonb);
drop function if exists "api"."rename_collection"(uuid, text, text, jsonb);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."create_collection"(tenant uuid, subject_type text, name text, scope text, team text, description text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_collection"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."create_collection"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "api"."create_collection"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "api"."rename_collection"(collection uuid, name text, description text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rename_collection"($1, $2, $3) $$;
revoke execute on function "api"."rename_collection"(uuid, text, text) from public, anon;
grant execute on function "api"."rename_collection"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."archive_collection"(collection uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_collection"($1, $2) $$;
revoke execute on function "api"."archive_collection"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_collection"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."list_collections"(tenant uuid, subject_type text, include_archived boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_collections"($1, $2, $3) $$;
revoke execute on function "api"."list_collections"(uuid, text, boolean) from public, anon;
grant execute on function "api"."list_collections"(uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."add_collection_entries"(collection uuid, subject_ids text[], subject_type text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_collection_entries"($1, $2, $3) $$;
revoke execute on function "api"."add_collection_entries"(uuid, text[], text) from public, anon;
grant execute on function "api"."add_collection_entries"(uuid, text[], text) to authenticated, service_role;

create or replace function "api"."remove_collection_entries"(collection uuid, subject_ids text[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_collection_entries"($1, $2) $$;
revoke execute on function "api"."remove_collection_entries"(uuid, text[]) from public, anon;
grant execute on function "api"."remove_collection_entries"(uuid, text[]) to authenticated, service_role;

create or replace function "api"."rank_collection_entry"(collection uuid, subject_id text, rank text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_collection_entry"($1, $2, $3) $$;
revoke execute on function "api"."rank_collection_entry"(uuid, text, text) from public, anon;
grant execute on function "api"."rank_collection_entry"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."collection_entries"(collection uuid, after_rank text, after_id text, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."collection_entries"($1, $2, $3, $4) $$;
revoke execute on function "api"."collection_entries"(uuid, text, text, integer) from public, anon;
grant execute on function "api"."collection_entries"(uuid, text, text, integer) to authenticated, service_role;

create or replace function "api"."collection_subject_ids"(collection uuid, max_ids integer)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."collection_subject_ids"($1, $2) $$;
revoke execute on function "api"."collection_subject_ids"(uuid, integer) from public, anon;
grant execute on function "api"."collection_subject_ids"(uuid, integer) to authenticated, service_role;

create or replace function "api"."collections_of"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."collections_of"($1, $2) $$;
revoke execute on function "api"."collections_of"(text, text) from public, anon;
grant execute on function "api"."collections_of"(text, text) to authenticated, service_role;

create or replace function "api"."star_subject"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."star_subject"($1, $2, $3) $$;
revoke execute on function "api"."star_subject"(uuid, text, text) from public, anon;
grant execute on function "api"."star_subject"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."unstar_subject"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unstar_subject"($1, $2) $$;
revoke execute on function "api"."unstar_subject"(text, text) from public, anon;
grant execute on function "api"."unstar_subject"(text, text) to authenticated, service_role;

create or replace function "api"."rank_star"(subject_type text, subject_id text, rank text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_star"($1, $2, $3) $$;
revoke execute on function "api"."rank_star"(text, text, text) from public, anon;
grant execute on function "api"."rank_star"(text, text, text) to authenticated, service_role;

create or replace function "api"."starred_subjects"(tenant uuid, subject_type text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."starred_subjects"($1, $2) $$;
revoke execute on function "api"."starred_subjects"(uuid, text) from public, anon;
grant execute on function "api"."starred_subjects"(uuid, text) to authenticated, service_role;

create or replace function "api"."save_for_later"(tenant uuid, subject_type text, subject_id text, note text default null, remind_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_for_later"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."save_for_later"(uuid, text, text, text, timestamptz) from public, anon;
grant execute on function "api"."save_for_later"(uuid, text, text, text, timestamptz) to authenticated, service_role;

create or replace function "api"."complete_saved_item"(item uuid, completed boolean default true)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_saved_item"($1, $2) $$;
revoke execute on function "api"."complete_saved_item"(uuid, boolean) from public, anon;
grant execute on function "api"."complete_saved_item"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."remove_saved_item"(item uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_saved_item"($1) $$;
revoke execute on function "api"."remove_saved_item"(uuid) from public, anon;
grant execute on function "api"."remove_saved_item"(uuid) to authenticated, service_role;

create or replace function "api"."list_saved_items"(tenant uuid, completed boolean default false, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_saved_items"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) from public, anon;
grant execute on function "api"."list_saved_items"(uuid, boolean, timestamptz, uuid, integer) to authenticated, service_role;

create or replace function "api"."remind_due_saved_items"(max_rows integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remind_due_saved_items"($1) $$;
revoke execute on function "api"."remind_due_saved_items"(integer) from public, anon, authenticated;
grant execute on function "api"."remind_due_saved_items"(integer) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_103_collections.sql
-- better-supabase module: collections
-- @bsb-block-data collections
-- @bsb-hash sha256:77080beb5b84e4f94399188b93d547f7a72b4cd89f7a97593a08e54057c736a8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('collections', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
