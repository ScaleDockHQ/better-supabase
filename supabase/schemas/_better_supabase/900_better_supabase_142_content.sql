-- better-supabase module: content
-- @bsb-block content@1 managed
-- @bsb-hash sha256:c564fb257fc8387b128142055541d7fd733175c1b1bd9c1e1a94271fb2cb46e9
-- Typed, localized content entries per organization, such as pages and posts, with a slug unique per type and locale. Entries are drafted, scheduled and published, optionally through approvals, and anyone can read published entries.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."content_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Content entries per organization: typed, localized pages and posts with a
-- slug, drafted, scheduled and published, readable by anyone once published.
create table if not exists "better_supabase"."content_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- One of options.types and options.locales; the functions check both.
  "type" text not null,
  "locale" text not null,
  "slug" text not null check (length("slug") <= 200 and "slug" ~ '^[a-z0-9]+(?:[-/][a-z0-9]+)*$'),
  "title" text not null check (length("title") between 1 and 300),
  "summary" text check ("summary" is null or length("summary") <= 2000),
  "body" jsonb not null default '{}'::jsonb check (jsonb_typeof("body") in ('object', 'array')),
  "status" text not null default 'draft' check ("status" in ('draft', 'scheduled', 'published', 'archived')),
  "publish_at" timestamptz,
  "published_at" timestamptz,
  "author_id" uuid references auth.users (id) on delete set null,
  -- Entries in one group translate each other, one per locale.
  "translation_group_id" uuid not null default gen_random_uuid(),
  "cover_attachment_id" uuid references "better_supabase"."attachments" ("id") on delete set null,
  -- The latest publish request, when options.requireApproval is on.
  "approval_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "type", "locale", "slug"),
  unique ("tenant_id", "translation_group_id", "locale"),
  check ("status" <> 'scheduled' or "publish_at" is not null),
  check ("status" <> 'published' or "published_at" is not null)
);
create index if not exists "content_entries_published_idx" on "better_supabase"."content_entries" ("tenant_id", "type", "locale", "published_at" desc) where "status" = 'published';
create index if not exists "content_entries_due_idx" on "better_supabase"."content_entries" ("publish_at") where "status" = 'scheduled';
create index if not exists "content_entries_updated_idx" on "better_supabase"."content_entries" ("tenant_id", "updated_at" desc);
create index if not exists "content_entries_author_idx" on "better_supabase"."content_entries" ("author_id");
create index if not exists "content_entries_cover_idx" on "better_supabase"."content_entries" ("cover_attachment_id");

alter table "better_supabase"."content_entries" enable row level security;
revoke all on "better_supabase"."content_entries" from anon, authenticated;
grant select on "better_supabase"."content_entries" to authenticated;
grant all on "better_supabase"."content_entries" to service_role;
drop policy if exists "content_entries_read" on "better_supabase"."content_entries";
create policy "content_entries_read" on "better_supabase"."content_entries" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('content.read')));

-- An entry the caller writes: attrs is { type, locale, slug, title, summary,
-- body, coverAttachmentId, translationOf }. It starts as a draft. translationOf
-- names an entry of the same type whose translation group it joins.
create or replace function "better_supabase"."create_content_entry"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
  v_source "better_supabase"."content_entries";
  v_type text := create_content_entry.attrs ->> 'type';
  v_locale text := coalesce(nullif(create_content_entry.attrs ->> 'locale', ''), 'en');
  v_slug text := lower(trim(create_content_entry.attrs ->> 'slug'));
  v_title text := trim(create_content_entry.attrs ->> 'title');
  v_summary text := nullif(trim(create_content_entry.attrs ->> 'summary'), '');
  v_body jsonb := coalesce(create_content_entry.attrs -> 'body', '{}'::jsonb);
  v_cover uuid := nullif(create_content_entry.attrs ->> 'coverAttachmentId', '')::uuid;
  v_group uuid := gen_random_uuid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_content_entry.tenant is not null and coalesce(better_supabase.can('tenant', create_content_entry.tenant, 'content.write'), false))) then
    raise exception 'not allowed to write content' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  if jsonb_typeof(create_content_entry.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if v_type is null or not (v_type = any (array['page', 'post']::text[])) then
    raise exception 'the type is not one of options.types' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if not (v_locale = any (array['en']::text[])) then
    raise exception 'the locale is not one of options.locales' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an entry needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if v_slug is null or length(v_slug) > 200 or v_slug !~ '^[a-z0-9]+(?:[-/][a-z0-9]+)*$' then
    raise exception 'a slug is lowercase letters and digits joined by dashes, with / between segments, at most 200 characters' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if length(v_summary) > 2000 then
    raise exception 'a summary is at most 2000 characters' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if jsonb_typeof(v_body) not in ('object', 'array') then
    raise exception 'an entry''s body is a JSON object or array' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if octet_length(v_body::text) > 1000000 then
    raise exception 'an entry''s body is at most 1000000 bytes of JSON' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if v_cover is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = v_cover and a."organization_id" = create_content_entry.tenant
  ) then
    raise exception 'the cover image is not an attachment of this organization' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if nullif(create_content_entry.attrs ->> 'translationOf', '') is not null then
    select * into v_source from "better_supabase"."content_entries" x
    where x."id" = (create_content_entry.attrs ->> 'translationOf')::uuid
      and x."tenant_id" = create_content_entry.tenant;
    if not found then
      raise exception 'no such content entry' using errcode = 'P0002', hint = 'CONTENT_NOT_FOUND';
    end if;
    if v_source."type" <> v_type then
      raise exception 'a translation has the type of the entry it translates' using errcode = '22023', hint = 'CONTENT_INVALID';
    end if;
    v_group := v_source."translation_group_id";
    if exists (
      select 1 from "better_supabase"."content_entries" x
      where x."tenant_id" = create_content_entry.tenant and x."translation_group_id" = v_group and x."locale" = v_locale
    ) then
      raise exception 'the entry already has a translation in this locale' using errcode = '23505', hint = 'CONTENT_TRANSLATION_EXISTS';
    end if;
  end if;
  v_row."tenant_id" := create_content_entry.tenant;
  v_row."type" := v_type;
  v_row."locale" := v_locale;
  if exists (
    select 1 from "better_supabase"."content_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."type" = v_row."type"
      and x."locale" = v_row."locale" and x."slug" = v_slug
      and x."id" is distinct from null::uuid
  ) then
    raise exception 'another entry of this type and locale has this slug' using errcode = '23505', hint = 'CONTENT_SLUG_TAKEN';
  end if;
  insert into "better_supabase"."content_entries" ("tenant_id", "type", "locale", "slug", "title", "summary", "body", "cover_attachment_id", "translation_group_id", "author_id", "created_by")
  values (create_content_entry.tenant, v_type, v_locale, v_slug, v_title, v_summary, v_body, v_cover, v_group, auth.uid(), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('content_entry.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id"), 'content-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/content');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_content_entry"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_content_entry"(uuid, jsonb) to authenticated, service_role;

-- Changes an entry's slug, title, summary, body or cover. A change to a draft
-- withdraws its pending publish request, so the approver sees what goes live.
create or replace function "better_supabase"."update_content_entry"(entry_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
  v_slug text;
  v_title text;
  v_summary text;
  v_body jsonb;
  v_cover uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."content_entries" x where x."id" = update_content_entry.entry_id for update;
  if not found then
    raise exception 'no such content entry' using errcode = 'P0002', hint = 'CONTENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.write'), false))) then
    raise exception 'not allowed to write content' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  if jsonb_typeof(update_content_entry.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  v_slug := case when update_content_entry.attrs ? 'slug' then lower(trim(update_content_entry.attrs ->> 'slug')) else v_row."slug" end;
  v_title := case when update_content_entry.attrs ? 'title' then trim(update_content_entry.attrs ->> 'title') else v_row."title" end;
  v_summary := case when update_content_entry.attrs ? 'summary' then nullif(trim(update_content_entry.attrs ->> 'summary'), '') else v_row."summary" end;
  v_body := case when update_content_entry.attrs ? 'body' then coalesce(update_content_entry.attrs -> 'body', '{}'::jsonb) else v_row."body" end;
  v_cover := case when update_content_entry.attrs ? 'coverAttachmentId' then nullif(update_content_entry.attrs ->> 'coverAttachmentId', '')::uuid else v_row."cover_attachment_id" end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an entry needs a title of 1 to 300 characters' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if v_slug is null or length(v_slug) > 200 or v_slug !~ '^[a-z0-9]+(?:[-/][a-z0-9]+)*$' then
    raise exception 'a slug is lowercase letters and digits joined by dashes, with / between segments, at most 200 characters' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if length(v_summary) > 2000 then
    raise exception 'a summary is at most 2000 characters' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if jsonb_typeof(v_body) not in ('object', 'array') then
    raise exception 'an entry''s body is a JSON object or array' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if octet_length(v_body::text) > 1000000 then
    raise exception 'an entry''s body is at most 1000000 bytes of JSON' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if v_cover is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = v_cover and a."organization_id" = v_row."tenant_id"
  ) then
    raise exception 'the cover image is not an attachment of this organization' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."content_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."type" = v_row."type"
      and x."locale" = v_row."locale" and x."slug" = v_slug
      and x."id" is distinct from v_row."id"
  ) then
    raise exception 'another entry of this type and locale has this slug' using errcode = '23505', hint = 'CONTENT_SLUG_TAKEN';
  end if;
  if v_row."status" = 'draft' and v_row."approval_id" is not null then
    update "better_supabase"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_row."approval_id" and r."status" = 'pending';
  end if;
  update "better_supabase"."content_entries" x set
    "slug" = v_slug,
    "title" = v_title,
    "summary" = v_summary,
    "body" = v_body,
    "cover_attachment_id" = v_cover,
    "approval_id" = case when x."status" = 'draft' then null else x."approval_id" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase"."version_insert"(v_row."tenant_id", 'content_entry', v_row."id"::text,
    jsonb_build_object('title', v_row."title", 'slug', v_row."slug", 'summary', v_row."summary", 'body', v_row."body"),
    null, null, 'auto', false, auth.uid());
  perform "better_supabase".emit_event('content_entry.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id"), 'content-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/content');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_content_entry"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_content_entry"(uuid, jsonb) to authenticated, service_role;

-- Takes an entry down: archived entries leave the public reads. A draft needs
-- the write permission; a scheduled or published entry needs publish.
create or replace function "better_supabase"."archive_content_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."content_entries" x where x."id" = archive_content_entry.entry_id for update;
  if not found then
    raise exception 'no such content entry' using errcode = 'P0002', hint = 'CONTENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.write'), false)))
    or (v_row."status" in ('scheduled', 'published') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.publish'), false)))) then
    raise exception 'not allowed to archive this entry' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  if v_row."status" = 'archived' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if v_row."status" = 'draft' and v_row."approval_id" is not null then
    update "better_supabase"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_row."approval_id" and r."status" = 'pending';
  end if;
  update "better_supabase"."content_entries" x set
    "status" = 'archived',
    "publish_at" = null,
    "approval_id" = case when x."status" = 'draft' then null else x."approval_id" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('content_entry.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id"), 'content-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/content');
  perform better_supabase.audit_event(
    event_type => 'content_entry.archived',
    category => 'data',
    target_type => 'content_entry',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'archived a content entry',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_content_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_content_entry"(uuid) to authenticated, service_role;

-- One entry with its translations, or null when there is none the caller reads.
create or replace function "better_supabase"."get_content_entry"(entry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
begin
  select * into v_row from "better_supabase"."content_entries" x where x."id" = get_content_entry.entry_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.read'), false))) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('translations', (
    select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'locale', t."locale", 'slug', t."slug", 'status', t."status") order by t."locale"), '[]'::jsonb)
    from "better_supabase"."content_entries" t
    where t."tenant_id" = v_row."tenant_id" and t."translation_group_id" = v_row."translation_group_id" and t."id" <> v_row."id"
  ));
end;
$$;
revoke execute on function "better_supabase"."get_content_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."get_content_entry"(uuid) to authenticated, service_role;

-- The organization's entries, latest change first. filter is { type, locale,
-- status, translationGroupId, query, limit (1 to 200, default 50), offset }.
create or replace function "better_supabase"."list_content_entries"(tenant uuid, filter jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filter jsonb := coalesce(list_content_entries.filter, '{}'::jsonb);
  v_query text := nullif(trim(v_filter ->> 'query'), '');
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_content_entries.tenant is not null and coalesce(better_supabase.can('tenant', list_content_entries.tenant, 'content.read'), false))) then
    raise exception 'not allowed to read content' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.updated desc, q.id), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'body', x."body", 'status', x."status", 'publishAt', x."publish_at", 'publishedAt', x."published_at", 'authorId', x."author_id", 'translationGroupId', x."translation_group_id", 'coverAttachmentId', x."cover_attachment_id", 'approvalId', x."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = x."approval_id"), 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."updated_at" as updated, x."id" as id
    from "better_supabase"."content_entries" x
    where x."tenant_id" = list_content_entries.tenant
      and (v_filter ->> 'type' is null or x."type" = v_filter ->> 'type')
      and (v_filter ->> 'locale' is null or x."locale" = v_filter ->> 'locale')
      and (v_filter ->> 'status' is null or x."status" = v_filter ->> 'status')
      and (v_filter ->> 'translationGroupId' is null or x."translation_group_id" = (v_filter ->> 'translationGroupId')::uuid)
      and (v_query is null or x."title" ilike '%' || v_query || '%' or x."slug" ilike '%' || v_query || '%')
    order by x."updated_at" desc, x."id"
    limit least(greatest(coalesce((v_filter ->> 'limit')::integer, 50), 1), 200)
    offset greatest(coalesce((v_filter ->> 'offset')::integer, 0), 0)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_content_entries"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_content_entries"(uuid, jsonb) to authenticated, service_role;

-- Publishes an entry now: sets it live, records a frozen "published" version
-- when versions is installed and writes content_entry.published. Publish,
-- the approval and the scheduler call it; it isn't granted to anyone.
create or replace function "better_supabase"."content_entry_go_live"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
begin
  select * into v_row from "better_supabase"."content_entries" x where x."id" = content_entry_go_live.entry_id for update;
  if not found then
    raise exception 'no such content entry' using errcode = 'P0002', hint = 'CONTENT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_content_entry_publish"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id";
    end if;
  end;
  update "better_supabase"."content_entries" x set
    "status" = 'published',
    "published_at" = now(),
    "publish_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase"."version_insert"(v_row."tenant_id", 'content_entry', v_row."id"::text,
    jsonb_build_object('title', v_row."title", 'slug', v_row."slug", 'summary', v_row."summary", 'body', v_row."body"),
    null, 'published', 'manual', true, auth.uid());
  perform "better_supabase".emit_event('content_entry.published', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id"), 'content-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/content');
  perform better_supabase.audit_event(
    event_type => 'content_entry.published',
    category => 'data',
    target_type => 'content_entry',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'published a content entry',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_content_entry_publish"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."content_entry_go_live"(uuid) from public, anon, authenticated;

-- Publishes an entry now. With options.requireApproval a writer's call opens
-- a publish request instead, and the entry goes live once it is approved.
create or replace function "better_supabase"."publish_content_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
  v_request jsonb;
begin
  select * into v_row from "better_supabase"."content_entries" x where x."id" = publish_content_entry.entry_id for update;
  if not found then
    raise exception 'no such content entry' using errcode = 'P0002', hint = 'CONTENT_NOT_FOUND';
  end if;
  if v_row."status" = 'published' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.read'), false))) then
      raise exception 'not allowed to read content' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
    end if;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.publish'), false))) then
    raise exception 'not allowed to publish content' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  return "better_supabase"."content_entry_go_live"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."publish_content_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_content_entry"(uuid) to authenticated, service_role;

-- Schedules an entry to go live at a future time; null unschedules it. With
-- options.requireApproval a writer's call opens a publish request, and the
-- entry is scheduled (or published, once the time has passed) when approved.
create or replace function "better_supabase"."schedule_content_entry"(entry_id uuid, at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."content_entries" x where x."id" = schedule_content_entry.entry_id for update;
  if not found then
    raise exception 'no such content entry' using errcode = 'P0002', hint = 'CONTENT_NOT_FOUND';
  end if;
  if schedule_content_entry.at is null then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.write'), false)))
      or (v_row."status" = 'scheduled' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.publish'), false)))) then
      raise exception 'not allowed to unschedule this entry' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
    end if;
    if v_row."status" not in ('draft', 'scheduled') or v_row."publish_at" is null then
      raise exception 'the entry is not scheduled' using errcode = '22023', hint = 'CONTENT_INVALID';
    end if;
  if v_row."status" = 'draft' and v_row."approval_id" is not null then
    update "better_supabase"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_row."approval_id" and r."status" = 'pending';
  end if;
    update "better_supabase"."content_entries" x set
      "status" = 'draft',
      "publish_at" = null,
      "approval_id" = case when x."status" = 'draft' then null else x."approval_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('content_entry.unscheduled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id"), 'content-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/content');
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if v_row."status" = 'published' then
    raise exception 'the entry is already published; archive it before scheduling it again' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  if schedule_content_entry.at <= now() then
    raise exception 'the publish time must be in the future' using errcode = '22023', hint = 'CONTENT_INVALID';
  end if;
  
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.publish'), false))) then
    raise exception 'not allowed to publish content' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  update "better_supabase"."content_entries" x set
    "status" = 'scheduled',
    "publish_at" = schedule_content_entry.at,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('content_entry.scheduled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id"), 'content-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/content');
  perform better_supabase.audit_event(
    event_type => 'content_entry.scheduled',
    category => 'data',
    target_type => 'content_entry',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'scheduled a content entry',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'body', v_row."body", 'status', v_row."status", 'publishAt', v_row."publish_at", 'publishedAt', v_row."published_at", 'authorId', v_row."author_id", 'translationGroupId', v_row."translation_group_id", 'coverAttachmentId', v_row."cover_attachment_id", 'approvalId', v_row."approval_id", 'approvalStatus', (select r."status" from "better_supabase"."approval_requests" r where r."id" = v_row."approval_id"), 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."schedule_content_entry"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."schedule_content_entry"(uuid, timestamptz) to authenticated, service_role;

-- Runs once a publish request is approved: schedules the entry when its time
-- is still ahead, and publishes it otherwise. Approvals calls it; it isn't
-- granted to anyone.
create or replace function "better_supabase"."content_entry_approved"(entry_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."content_entries";
begin
  select * into v_row from "better_supabase"."content_entries" x where x."id" = content_entry_approved.entry_id for update;
  if not found or v_row."status" <> 'draft' or v_row."approval_id" is null then
    return;
  end if;
  if v_row."publish_at" is not null and v_row."publish_at" > now() then
    update "better_supabase"."content_entries" x set "status" = 'scheduled', "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('content_entry.scheduled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id"), 'content-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/content');
  perform better_supabase.audit_event(
    event_type => 'content_entry.scheduled',
    category => 'data',
    target_type => 'content_entry',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'scheduled a content entry',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'status', v_row."status", 'translationGroupId', v_row."translation_group_id")
  );
  else
    perform "better_supabase"."content_entry_go_live"(v_row."id");
  end if;
end;
$$;
revoke execute on function "better_supabase"."content_entry_approved"(uuid) from public, anon, authenticated;

-- Publishes the scheduled entries whose time has come, at most 500 a call,
-- and returns how many. The content block's publish timer calls it.
create or replace function "better_supabase"."publish_due_content_entries"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role publishes due entries' using errcode = '42501', hint = 'CONTENT_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "better_supabase"."content_entries" x
    where x."status" = 'scheduled' and x."publish_at" <= now()
    order by x."publish_at"
    limit 500
    for update skip locked
  loop
    perform "better_supabase"."content_entry_go_live"(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."publish_due_content_entries"() from public, anon, authenticated;
grant execute on function "better_supabase"."publish_due_content_entries"() to service_role;

-- A published entry by type, slug and locale, or null. A slug the locale
-- lacks falls back to the default locale. Each entry lists its published
-- translations.
create or replace function "better_supabase"."public_content_entry"(tenant uuid, type text, slug text, locale text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_locale text := coalesce(nullif(public_content_entry.locale, ''), 'en');
  v_row "better_supabase"."content_entries";
begin
  select * into v_row from "better_supabase"."content_entries" x
  where x."tenant_id" = public_content_entry.tenant
    and x."type" = public_content_entry.type
    and x."slug" = public_content_entry.slug
    and x."locale" in (v_locale, 'en')
    and x."status" = 'published' and x."published_at" <= now()
  order by (x."locale" = v_locale) desc
  limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'type', v_row."type", 'locale', v_row."locale", 'slug', v_row."slug", 'title', v_row."title", 'summary', v_row."summary", 'coverAttachmentId', v_row."cover_attachment_id", 'translationGroupId', v_row."translation_group_id", 'publishedAt', v_row."published_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'body', v_row."body",
    'translations', (
      select coalesce(jsonb_agg(jsonb_build_object('locale', t."locale", 'slug', t."slug") order by t."locale"), '[]'::jsonb)
      from "better_supabase"."content_entries" t
      where t."tenant_id" = v_row."tenant_id" and t."translation_group_id" = v_row."translation_group_id"
        and t."id" <> v_row."id" and t."status" = 'published' and t."published_at" <= now()
    )
  );
end;
$$;
revoke all on function "better_supabase"."public_content_entry"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."public_content_entry"(uuid, text, text, text) to anon, authenticated, service_role;

-- Published entries of a type (all types when null) in a locale (the default
-- when null), newest first, without their bodies. page_size is 1 to 100
-- (default 20); before pages on publishedAt.
create or replace function "better_supabase"."public_content_entries"(tenant uuid, type text default null, locale text default null, page_size integer default 20, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'type', x."type", 'locale', x."locale", 'slug', x."slug", 'title', x."title", 'summary', x."summary", 'coverAttachmentId', x."cover_attachment_id", 'translationGroupId', x."translation_group_id", 'publishedAt', x."published_at", 'updatedAt', x."updated_at") as item, x."published_at" as published, x."id" as id
    from "better_supabase"."content_entries" x
    where x."tenant_id" = public_content_entries.tenant
      and (public_content_entries.type is null or x."type" = public_content_entries.type)
      and x."locale" = coalesce(nullif(public_content_entries.locale, ''), 'en')
      and x."status" = 'published' and x."published_at" <= now()
      and (public_content_entries.before is null or x."published_at" < public_content_entries.before)
    order by x."published_at" desc, x."id"
    limit least(greatest(coalesce(public_content_entries.page_size, 20), 1), 100)
  ) q
$$;
revoke all on function "better_supabase"."public_content_entries"(uuid, text, text, integer, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."public_content_entries"(uuid, text, text, integer, timestamptz) to anon, authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."content_entries";
create policy bsb_tenant_scope on "better_supabase"."content_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('content.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

drop trigger if exists "bsb_search_content_entry_index" on "better_supabase"."content_entries";
create trigger "bsb_search_content_entry_index"
  after insert or delete or update of "id", "tenant_id", "title", "summary" on "better_supabase"."content_entries"
  for each row execute function "better_supabase"."search_index_row"('content_entry', 'id');

-- blocks.content.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."create_content_entry"(tenant uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_content_entry"($1, $2) $$;
revoke execute on function "api"."create_content_entry"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_content_entry"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_content_entry"(entry_id uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_content_entry"($1, $2) $$;
revoke execute on function "api"."update_content_entry"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_content_entry"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."archive_content_entry"(entry_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_content_entry"($1) $$;
revoke execute on function "api"."archive_content_entry"(uuid) from public, anon;
grant execute on function "api"."archive_content_entry"(uuid) to authenticated, service_role;

create or replace function "api"."get_content_entry"(entry_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_content_entry"($1) $$;
revoke execute on function "api"."get_content_entry"(uuid) from public, anon;
grant execute on function "api"."get_content_entry"(uuid) to authenticated, service_role;

create or replace function "api"."list_content_entries"(tenant uuid, filter jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_content_entries"($1, $2) $$;
revoke execute on function "api"."list_content_entries"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_content_entries"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."publish_content_entry"(entry_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_content_entry"($1) $$;
revoke execute on function "api"."publish_content_entry"(uuid) from public, anon;
grant execute on function "api"."publish_content_entry"(uuid) to authenticated, service_role;

create or replace function "api"."schedule_content_entry"(entry_id uuid, at timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_content_entry"($1, $2) $$;
revoke execute on function "api"."schedule_content_entry"(uuid, timestamptz) from public, anon;
grant execute on function "api"."schedule_content_entry"(uuid, timestamptz) to authenticated, service_role;

create or replace function "api"."publish_due_content_entries"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_due_content_entries"() $$;
revoke execute on function "api"."publish_due_content_entries"() from public, anon, authenticated;
grant execute on function "api"."publish_due_content_entries"() to service_role;

create or replace function "api"."public_content_entry"(tenant uuid, type text, slug text, locale text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."public_content_entry"($1, $2, $3, $4) $$;
revoke execute on function "api"."public_content_entry"(uuid, text, text, text) from public;
grant execute on function "api"."public_content_entry"(uuid, text, text, text) to anon, authenticated, service_role;

create or replace function "api"."public_content_entries"(tenant uuid, type text default null, locale text default null, page_size integer default 20, before timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."public_content_entries"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."public_content_entries"(uuid, text, text, integer, timestamptz) from public;
grant execute on function "api"."public_content_entries"(uuid, text, text, integer, timestamptz) to anon, authenticated, service_role;

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
