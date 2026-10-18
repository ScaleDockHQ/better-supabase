-- better-supabase module: reactions (0.8.0)
-- @bs-module reactions@1 managed
-- Emoji reactions on any subject, comments and inbox messages, with per-tenant custom emoji, counts per subject under the subject's own read rules and a realtime topic per tenant.
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
create table if not exists "better_supabase"."reactions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "actor" text not null,
  "user_id" uuid,
  "emoji" text not null check (length("emoji") between 1 and 64 and "emoji" !~ '\s'),
  "created_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "actor", "emoji")
);
create index if not exists "reactions_tenant_idx" on "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id");
create index if not exists "reactions_user_idx" on "better_supabase"."reactions" ("user_id");
alter table "better_supabase"."reactions" enable row level security;
revoke all on "better_supabase"."reactions" from anon;
grant select, insert, delete on "better_supabase"."reactions" to authenticated;
grant all on "better_supabase"."reactions" to service_role;

create table if not exists "better_supabase"."custom_emoji" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shortcode" text not null check ("shortcode" ~ '^[a-z0-9_+-]{1,32}$'),
  "attachment_id" uuid,
  "url" text check ("url" ~ '^https://'),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "shortcode"),
  check ("attachment_id" is not null or "url" is not null)
);
alter table "better_supabase"."custom_emoji" enable row level security;
revoke all on "better_supabase"."custom_emoji" from anon, authenticated;
grant select on "better_supabase"."custom_emoji" to authenticated;
grant all on "better_supabase"."custom_emoji" to service_role;
drop policy if exists "custom_emoji_read" on "better_supabase"."custom_emoji";
create policy "custom_emoji_read" on "better_supabase"."custom_emoji" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('reactions.read')));

-- Whether the caller sees the subject. It runs as the caller, so the subject
-- tables' policies apply.
create or replace function "better_supabase"."reaction_subject_visible"(subject_type text, subject_id text, tenant uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case reaction_subject_visible.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" c where c."id"::text = reaction_subject_visible.subject_id and c."organization_id" = reaction_subject_visible.tenant and c."deleted_at" is null)
    when 'inbox_message' then exists (select 1 from "better_supabase"."inbox_messages" m where m."id"::text = reaction_subject_visible.subject_id and m."tenant_id" = reaction_subject_visible.tenant)
    else case reaction_subject_visible.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    else false
  end
  end
$$;
revoke execute on function "better_supabase"."reaction_subject_visible"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."reaction_subject_visible"(text, text, uuid) to authenticated, service_role;

drop policy if exists "reactions_read" on "better_supabase"."reactions";
create policy "reactions_read" on "better_supabase"."reactions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('reactions.read')) and "better_supabase"."reaction_subject_visible"("subject_type", "subject_id", "tenant_id"));
drop policy if exists "reactions_insert" on "better_supabase"."reactions";
create policy "reactions_insert" on "better_supabase"."reactions" for insert to authenticated
  with check ((
    "user_id" = (select auth.uid())
    and "actor" = (select auth.uid())::text
    and "tenant_id" in (select better_supabase.tenant_ids_with('reactions.create')) and "subject_type" <> 'inbox_message'
    and "better_supabase"."reaction_subject_visible"("subject_type", "subject_id", "tenant_id")
  ) and (select better_supabase.actor_may_write()));
drop policy if exists "reactions_delete" on "better_supabase"."reactions";
create policy "reactions_delete" on "better_supabase"."reactions" for delete to authenticated
  using (("user_id" = (select auth.uid()) and "subject_type" <> 'inbox_message') and (select better_supabase.actor_may_write()));

drop trigger if exists "bs_reactions_check" on "better_supabase"."reactions";
drop trigger if exists "bs_reactions_changed" on "better_supabase"."reactions";

-- A custom emoji's :shortcode: must exist in the reaction's tenant.
create or replace function "better_supabase"."reactions_check"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."emoji" ~ '^:[a-z0-9_+-]{1,32}:$' and not exists (
    select 1 from "better_supabase"."custom_emoji" x
    where x."tenant_id" = new."tenant_id" and x."shortcode" = trim(both ':' from new."emoji")
  ) then
    raise exception 'unknown custom emoji' using errcode = '22023', hint = 'REACTION_INVALID';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."reactions_check"() from public, anon, authenticated;
create trigger "bs_reactions_check"
  before insert on "better_supabase"."reactions"
  for each row execute function "better_supabase"."reactions_check"();

-- Records reaction.added and reaction.removed, then tells the tenant's topic
-- which subject changed. The payload carries ids only.
create or replace function "better_supabase"."reactions_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reactions"%rowtype;
begin
  if current_setting('better_supabase.reactions_backfill', true) = 'on' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    v_row := new;
    
  else
    v_row := old;
    
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'reactions:' || v_row."tenant_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reactions_changed"() from public, anon, authenticated;
create trigger "bs_reactions_changed"
  after insert or delete on "better_supabase"."reactions"
  for each row execute function "better_supabase"."reactions_changed"();

-- One subject's reactions under the read policy: emoji, count, whether the
-- caller reacted and the first ten actors, most used first.
create or replace function "better_supabase"."reaction_list"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('emoji', g.emoji, 'count', g.n, 'reacted', g.mine, 'actors', g.actors) order by g.n desc, g.first, g.emoji), '[]'::jsonb)
  from (
    select r."emoji" as emoji, count(*)::integer as n, min(r."created_at") as first,
      coalesce(bool_or(r."user_id" = (select auth.uid())), false) as mine,
      (array_agg(r."actor" order by r."created_at"))[1:10] as actors
    from "better_supabase"."reactions" r
    where r."tenant_id" = reaction_list.tenant
      and r."subject_type" = reaction_list.subject_type
      and r."subject_id" = reaction_list.subject_id
    group by r."emoji"
  ) g
$$;
revoke execute on function "better_supabase"."reaction_list"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."reaction_list"(uuid, text, text) to authenticated, service_role;

-- Adds (present) or removes the caller's reaction, then returns the
-- subject's reactions. It runs as the caller: the insert and delete
-- policies check the permission and that the caller sees the subject.
-- The service role passes the actor (default 'service').
create or replace function "better_supabase"."react"(tenant uuid, subject_type text, subject_id text, emoji text, present boolean default true, actor text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_actor text;
  v_user uuid;
begin
  if react.subject_type = 'inbox_message' then
    perform "better_supabase"."react_to_message"(react.subject_id::uuid, react.emoji, coalesce(react.present, true), react.actor);
    return "better_supabase"."reaction_list"(react.tenant, react.subject_type, react.subject_id);
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_actor := coalesce(react.actor, 'service');
  elsif react.actor is not null then
    raise exception 'only the service role reacts for another actor' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  elsif not (coalesce(better_supabase.can('tenant', react.tenant, 'reactions.create'), false) and "better_supabase"."reaction_subject_visible"(react.subject_type, react.subject_id, react.tenant)) then
    raise exception 'not allowed to react to this record' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  else
    v_user := (select auth.uid());
    v_actor := v_user::text;
  end if;
  if react.emoji is null or length(react.emoji) not between 1 and 64 or react.emoji ~ '\s' then
    raise exception 'emoji must be 1 to 64 characters without spaces' using errcode = '22023', hint = 'REACTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_react"(uuid, text, text, text, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::boolean)', v_hook::oid::regproc)
        using react.tenant, react.subject_type, react.subject_id, react.emoji, coalesce(react.present, true);
    end if;
  end;
  if coalesce(react.present, true) then
    insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "emoji")
    values (react.tenant, react.subject_type, react.subject_id, v_actor, v_user, react.emoji)
    on conflict do nothing;
  else
    delete from "better_supabase"."reactions" r
    where r."subject_type" = react.subject_type
      and r."subject_id" = react.subject_id
      and r."tenant_id" = react.tenant
      and r."actor" = v_actor
      and r."emoji" = react.emoji;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_react"(uuid, text, text, text, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::boolean)', v_hook::oid::regproc)
        using react.tenant, react.subject_type, react.subject_id, react.emoji, coalesce(react.present, true);
    end if;
  end;
  return "better_supabase"."reaction_list"(react.tenant, react.subject_type, react.subject_id);
end;
$$;
revoke execute on function "better_supabase"."react"(uuid, text, text, text, boolean, text) from public, anon;
grant execute on function "better_supabase"."react"(uuid, text, text, text, boolean, text) to authenticated, service_role;

-- The reactions of many subjects of one type, as { subjectId: [...] }.
create or replace function "better_supabase"."reaction_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "better_supabase"."reaction_list"(reaction_summary.tenant, reaction_summary.subject_type, s.id)), '{}'::jsonb)
  from (select distinct unnest(reaction_summary.subject_ids[1:200]) as id) s
$$;
revoke execute on function "better_supabase"."reaction_summary"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."reaction_summary"(uuid, text, text[]) to authenticated, service_role;

create or replace function "better_supabase"."save_custom_emoji"(tenant uuid, shortcode text, attachment_id uuid default null, url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."custom_emoji"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_custom_emoji.tenant, 'reactions.manage'), false)) then
    raise exception 'not allowed to manage custom emoji' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."custom_emoji" ("tenant_id", "shortcode", "attachment_id", "url", "created_by")
  values (save_custom_emoji.tenant, lower(trim(both ':' from save_custom_emoji.shortcode)), save_custom_emoji.attachment_id, save_custom_emoji.url, auth.uid())
  on conflict ("tenant_id", "shortcode") do update
    set "attachment_id" = excluded."attachment_id", "url" = excluded."url"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'shortcode', v_row."shortcode", 'attachmentId', v_row."attachment_id", 'url', v_row."url", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."save_custom_emoji"(uuid, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."save_custom_emoji"(uuid, text, uuid, text) to authenticated, service_role;

-- Deletes a custom emoji and the reactions that used it.
create or replace function "better_supabase"."delete_custom_emoji"(emoji_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."custom_emoji"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."custom_emoji" x where x."id" = delete_custom_emoji.emoji_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reactions.manage'), false)) then
    raise exception 'not allowed to manage custom emoji' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  end if;
  delete from "better_supabase"."reactions" r
    where r."tenant_id" = v_row."tenant_id" and r."emoji" = ':' || v_row."shortcode" || ':';
  delete from "better_supabase"."custom_emoji" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_custom_emoji"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_custom_emoji"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_custom_emoji"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'shortcode', x."shortcode", 'attachmentId', x."attachment_id", 'url', x."url", 'createdAt', x."created_at") order by x."shortcode"), '[]'::jsonb)
  from "better_supabase"."custom_emoji" x
  where x."tenant_id" = list_custom_emoji.tenant
$$;
revoke execute on function "better_supabase"."list_custom_emoji"(uuid) from public, anon;
grant execute on function "better_supabase"."list_custom_emoji"(uuid) to authenticated, service_role;

-- Members join reactions:{tenant}; payloads name the subject that changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bs_reactions_receive" on realtime.messages;
    create policy "bs_reactions_receive" on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'reactions:%'
        and substr((select realtime.topic()), 11) in (select x::text from better_supabase.tenant_ids_with('reactions.read') x)
      );
  end if;
end;
$do$;

-- options.subjects with cascade: deleting a subject row deletes its reactions rows.
create or replace function "better_supabase"."reactions_subject_deleted"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reactions_subject_deleted"() from public, anon, authenticated;

drop trigger if exists "bs_reactions_product_cascade" on "better_supabase"."products";
create trigger "bs_reactions_product_cascade"
  after delete on "better_supabase"."products"
  for each row execute function "better_supabase"."reactions_subject_deleted"('product', 'id');

drop trigger if exists "bs_reactions_product_variant_cascade" on "better_supabase"."product_variants";
create trigger "bs_reactions_product_variant_cascade"
  after delete on "better_supabase"."product_variants"
  for each row execute function "better_supabase"."reactions_subject_deleted"('product_variant', 'id');

-- blocks.reactions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."reaction_subject_visible"(text, text, uuid);

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

create or replace function "api"."reaction_list"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reaction_list"($1, $2, $3) $$;
revoke execute on function "api"."reaction_list"(uuid, text, text) from public, anon;
grant execute on function "api"."reaction_list"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."react"(tenant uuid, subject_type text, subject_id text, emoji text, present boolean default true, actor text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."react"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."react"(uuid, text, text, text, boolean, text) from public, anon;
grant execute on function "api"."react"(uuid, text, text, text, boolean, text) to authenticated, service_role;

create or replace function "api"."reaction_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reaction_summary"($1, $2, $3) $$;
revoke execute on function "api"."reaction_summary"(uuid, text, text[]) from public, anon;
grant execute on function "api"."reaction_summary"(uuid, text, text[]) to authenticated, service_role;

create or replace function "api"."save_custom_emoji"(tenant uuid, shortcode text, attachment_id uuid default null, url text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_custom_emoji"($1, $2, $3, $4) $$;
revoke execute on function "api"."save_custom_emoji"(uuid, text, uuid, text) from public, anon;
grant execute on function "api"."save_custom_emoji"(uuid, text, uuid, text) to authenticated, service_role;

create or replace function "api"."delete_custom_emoji"(emoji_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_custom_emoji"($1) $$;
revoke execute on function "api"."delete_custom_emoji"(uuid) from public, anon;
grant execute on function "api"."delete_custom_emoji"(uuid) to authenticated, service_role;

create or replace function "api"."list_custom_emoji"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_custom_emoji"($1) $$;
revoke execute on function "api"."list_custom_emoji"(uuid) from public, anon;
grant execute on function "api"."list_custom_emoji"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
