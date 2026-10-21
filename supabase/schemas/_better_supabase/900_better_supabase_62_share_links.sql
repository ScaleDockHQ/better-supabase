-- better-supabase module: share-links
-- @bs-module share-links@1 managed
-- Hashed share links, view counts and per-user state. The token is returned once. Resolving a link hashes the token the caller presents, so a stored plaintext token keeps working after it is hashed.
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
create table if not exists "better_supabase"."share_links" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "token_hash" text not null unique,
  "role" text not null default 'view',
  "version" integer not null default 1,
  "expires_at" timestamptz,
  "revoked_at" timestamptz,
  "max_uses" integer,
  "created_by" uuid,
  "leaf_id" text
);
alter table "better_supabase"."share_links" add column if not exists "version_id" uuid;
alter table "better_supabase"."share_links" add column if not exists "use_count" integer not null default 0;
alter table "better_supabase"."share_links" enable row level security;
revoke all on "better_supabase"."share_links" from anon, authenticated;
grant select on "better_supabase"."share_links" to authenticated;
grant all on "better_supabase"."share_links" to service_role;
create index if not exists "share_links_subject_idx" on "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id");
create table if not exists "better_supabase"."subject_views" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "viewer_kind" text not null,
  "viewer" text,
  "first_viewed_at" timestamptz not null default now(),
  "last_viewed_at" timestamptz not null default now(),
  "view_count" integer not null default 1,
  unique ("tenant_id", "subject_type", "subject_id", "viewer_kind", "viewer")
);
alter table "better_supabase"."subject_views" enable row level security;
revoke all on "better_supabase"."subject_views" from anon, authenticated;
grant select on "better_supabase"."subject_views" to authenticated;
grant all on "better_supabase"."subject_views" to service_role;

create table if not exists "better_supabase"."subject_user_state" (
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid not null,
  "starred_at" timestamptz,
  "last_opened_at" timestamptz,
  primary key ("subject_type", "subject_id", "user_id")
);
alter table "better_supabase"."subject_user_state" enable row level security;
revoke all on "better_supabase"."subject_user_state" from anon, authenticated;
grant select on "better_supabase"."subject_user_state" to authenticated;
grant all on "better_supabase"."subject_user_state" to service_role;


drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, jsonb);
-- fields: the extra columns (blocks.share-links.options.extraColumns) to set.
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, jsonb);
create or replace function "better_supabase"."create_share_link"(tenant uuid, subject_type text, subject_id text, role text, version_id uuid default null, expires_at timestamptz default null, max_uses integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_subject_ok boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_share_link.tenant, 'share_links.create'), false)) then
    raise exception 'not allowed to share' using errcode = '42501', hint = 'SHARE_FORBIDDEN';
  end if;
  if create_share_link.expires_at is not null and create_share_link.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'SHARE_EXPIRY_INVALID';
  end if;
  if create_share_link.max_uses is not null and create_share_link.max_uses < 1 then
    raise exception 'max_uses must be at least 1' using errcode = '22023', hint = 'SHARE_MAX_USES_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    v_subject_ok := case create_share_link.subject_type
    when 'ai-chat' then exists (select 1 from "better_supabase".ai_chats s where s.id::text = create_share_link.subject_id and s.organization_id::text = create_share_link.tenant::text and s.owner_id = auth.uid())
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'calendar' then exists (select 1 from "better_supabase"."calendars" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'booking_service' then exists (select 1 from "better_supabase"."booking_services" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    else case create_share_link.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'comments.read'), false)
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'customers.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    else null
  end
  end;
    if v_subject_ok is null then
      raise exception 'this subject type can''t be shared' using errcode = '22023', hint = 'SHARE_SUBJECT_UNKNOWN';
    end if;
    if not v_subject_ok then
      raise exception 'the subject does not exist in this organization' using errcode = 'P0002', hint = 'SHARE_SUBJECT_NOT_FOUND';
    end if;
  end if;
  if create_share_link.version_id is not null then
    declare
      v_version jsonb := "better_supabase"."get_version"(create_share_link.version_id);
    begin
      if v_version ->> 'subjectType' is distinct from create_share_link.subject_type
        or v_version ->> 'subjectId' is distinct from create_share_link.subject_id then
        raise exception 'the version belongs to another subject' using errcode = '22023', hint = 'SHARE_VERSION_INVALID';
      end if;
    end;
  end if;
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "expires_at", "max_uses", "created_by", "version_id")
  values (create_share_link.tenant, create_share_link.subject_type, create_share_link.subject_id, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), coalesce(create_share_link.role, 'view'), create_share_link.expires_at, create_share_link.max_uses, auth.uid(), create_share_link.version_id)
  returning "id" into v_id;
  perform "better_supabase".emit_event('share_link.created', jsonb_build_object('organizationId', create_share_link.tenant, 'id', v_id, 'subjectType', create_share_link.subject_type, 'subjectId', create_share_link.subject_id), 'share-links/' || v_id::text, (create_share_link.tenant)::text, null, 'better-supabase/share-links');
  return jsonb_build_object('id', v_id, 'token', v_token);
end;
$$;
revoke execute on function "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer) to authenticated, service_role;

-- The link's creator, or a caller who may create links in its tenant, may
-- revoke it. Anyone else gets SHARE_NOT_FOUND, so ids can't be probed.
create or replace function "better_supabase"."revoke_share_link"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_creator uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "created_by" into v_tenant, v_creator
  from "better_supabase"."share_links"
  where "id" = revoke_share_link.id and "revoked_at" is null
  for update;
  if not found or not (
    auth.role() = 'service_role'
    or (v_creator is not null and v_creator = auth.uid())
    or coalesce(better_supabase.can('tenant', v_tenant, 'share_links.create'), false)
  ) then
    raise exception 'share link not found' using errcode = 'P0002', hint = 'SHARE_NOT_FOUND';
  end if;
  update "better_supabase"."share_links" set "revoked_at" = now()
  where "id" = revoke_share_link.id;
  perform "better_supabase".emit_event('share_link.revoked', jsonb_build_object('organizationId', v_tenant, 'id', revoke_share_link.id), 'share-links/' || revoke_share_link.id::text, (v_tenant)::text, null, 'better-supabase/share-links');
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_share_link"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_share_link"(uuid) to authenticated, service_role;

-- Each resolve counts one use, so a link with max_uses stops resolving once
-- it is spent. The row lock keeps two concurrent resolves from both taking
-- the last use.
create or replace function "better_supabase"."resolve_share_link"(token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_link "better_supabase"."share_links"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_link
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(resolve_share_link.token, 'utf8'), 'sha256'), 'hex')
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
  for update;
  if not found then
    return null;
  end if;
  update "better_supabase"."share_links" set "use_count" = "use_count" + 1
  where "id" = v_link."id";
  return jsonb_build_object('id', v_link."id", 'organizationId', v_link."tenant_id", 'subjectType', v_link."subject_type", 'subjectId', v_link."subject_id", 'role', v_link."role", 'versionId', v_link."version_id", 'expiresAt', v_link."expires_at", 'maxUses', v_link."max_uses");
end;
$$;
revoke all on function "better_supabase"."resolve_share_link"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."resolve_share_link"(text) to anon, authenticated, service_role;

create or replace function "better_supabase"."record_view"(tenant uuid, subject_type text, subject_id text, viewer_kind text, viewer text)
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
  if not (auth.role() = 'service_role' or record_view.tenant in (select better_supabase.member_organization_ids())) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'SHARE_FORBIDDEN';
  end if;
  insert into "better_supabase"."subject_views" ("tenant_id", "subject_type", "subject_id", "viewer_kind", "viewer")
  values (record_view.tenant, record_view.subject_type, record_view.subject_id, record_view.viewer_kind, record_view.viewer)
  on conflict ("tenant_id", "subject_type", "subject_id", "viewer_kind", "viewer")
  do update set "last_viewed_at" = now(), "view_count" = "better_supabase"."subject_views"."view_count" + 1;
  perform "better_supabase".emit_event('subject.viewed', jsonb_build_object('organizationId', record_view.tenant, 'subjectType', record_view.subject_type, 'subjectId', record_view.subject_id), 'views/' || record_view.subject_type || '/' || record_view.subject_id, (record_view.tenant)::text, null, 'better-supabase/share-links');
  return true;
end;
$$;
revoke execute on function "better_supabase"."record_view"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_view"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_share_links"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'role', l."role", 'expiresAt', l."expires_at", 'revokedAt', l."revoked_at")), '[]'::jsonb)
  from "better_supabase"."share_links" l
  where l."subject_type" = list_share_links.subject_type
    and l."subject_id" = list_share_links.subject_id
    and (
      auth.role() = 'service_role'
      or l."created_by" = (select auth.uid())
      or l."tenant_id" in (select better_supabase.tenant_ids_with('share_links.read'))
    )
$$;
revoke execute on function "better_supabase"."list_share_links"(text, text) from public, anon;
grant execute on function "better_supabase"."list_share_links"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."set_user_state"(subject_type text, subject_id text, starred boolean)
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
  insert into "better_supabase"."subject_user_state" ("subject_type", "subject_id", "user_id", "starred_at", "last_opened_at")
  values (set_user_state.subject_type, set_user_state.subject_id, auth.uid(), case when set_user_state.starred then now() else null end, now())
  on conflict ("subject_type", "subject_id", "user_id")
  do update set "starred_at" = excluded."starred_at", "last_opened_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_user_state"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_user_state"(text, text, boolean) to authenticated, service_role;

-- ai-chat sharing is this block. The old functions stay callable and write
-- share_links instead of ai_chat_shares.
do $$
begin
  if to_regclass('"better_supabase".ai_chat_shares') is not null then
    insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "created_by", "leaf_id")
    select c.organization_id, 'ai-chat', s.chat_id::text, s.token_hash, s.created_by, s.leaf_id
    from "better_supabase".ai_chat_shares s
    join "better_supabase".ai_chats c on c.id = s.chat_id
    on conflict ("token_hash") do nothing;
  end if;
end;
$$;
create or replace function "better_supabase"."share_ai_chat"(chat uuid, leaf text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tenant uuid;
  v_owner uuid;
  v_leaf text;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select organization_id, owner_id, current_leaf_id into v_tenant, v_owner, v_leaf
  from "better_supabase".ai_chats where id = share_ai_chat.chat;
  if not found or v_owner is distinct from auth.uid() then
    raise exception 'no chat' using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_leaf);
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "created_by", "leaf_id")
  values (v_tenant, 'ai-chat', share_ai_chat.chat::text, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), 'view', auth.uid(), v_leaf)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf);
end;
$$;
revoke execute on function "better_supabase"."share_ai_chat"(uuid, text) from public, anon;
grant execute on function "better_supabase"."share_ai_chat"(uuid, text) to authenticated, service_role;
create or replace function "better_supabase"."revoke_ai_chat_share"(id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  return "better_supabase"."revoke_share_link"(revoke_ai_chat_share.id);
end;
$$;
create or replace function "better_supabase"."list_ai_chat_shares"(chat uuid)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select "better_supabase"."list_share_links"('ai-chat', list_ai_chat_shares.chat::text)
$$;
create or replace function "better_supabase"."get_shared_ai_chat"(token text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_subject text;
  v_tenant text;
  v_leaf text;
  v_chat_id uuid;
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select l."subject_id", l."tenant_id"::text, l."leaf_id"
    into v_subject, v_tenant, v_leaf
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(get_shared_ai_chat.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'ai-chat'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses");
  if not found or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_chat_id := v_subject::uuid;
  -- The chat must still live in the tenant the link was created in.
  if not exists (select 1 from "better_supabase".ai_chats where id = v_chat_id and organization_id::text = v_tenant) then
    return null;
  end if;
  return jsonb_build_object(
    'chat', (select jsonb_build_object('id', id, 'title', title, 'model', model, 'created_at', created_at) from "better_supabase".ai_chats where id = v_chat_id),
    'leaf_id', v_leaf,
    'messages', "better_supabase"."ai_message_path_of"(v_chat_id, v_leaf, false)
  );
end;
$$;

-- blocks.share-links.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_share_link"(uuid, text, text, text);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, jsonb);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, jsonb);

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

create or replace function "api"."create_share_link"(tenant uuid, subject_type text, subject_id text, role text, version_id uuid default null, expires_at timestamptz default null, max_uses integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_share_link"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."revoke_share_link"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_share_link"($1) $$;
revoke execute on function "api"."revoke_share_link"(uuid) from public, anon;
grant execute on function "api"."revoke_share_link"(uuid) to authenticated, service_role;

create or replace function "api"."resolve_share_link"(token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_share_link"($1) $$;
revoke execute on function "api"."resolve_share_link"(text) from public;
grant execute on function "api"."resolve_share_link"(text) to anon, authenticated, service_role;

create or replace function "api"."record_view"(tenant uuid, subject_type text, subject_id text, viewer_kind text, viewer text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_view"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."record_view"(uuid, text, text, text, text) from public, anon;
grant execute on function "api"."record_view"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "api"."list_share_links"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_share_links"($1, $2) $$;
revoke execute on function "api"."list_share_links"(text, text) from public, anon;
grant execute on function "api"."list_share_links"(text, text) to authenticated, service_role;

create or replace function "api"."set_user_state"(subject_type text, subject_id text, starred boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_user_state"($1, $2, $3) $$;
revoke execute on function "api"."set_user_state"(text, text, boolean) from public, anon;
grant execute on function "api"."set_user_state"(text, text, boolean) to authenticated, service_role;

create or replace function "api"."share_ai_chat"(chat uuid, leaf text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."share_ai_chat"($1, $2) $$;
revoke execute on function "api"."share_ai_chat"(uuid, text) from public, anon;
grant execute on function "api"."share_ai_chat"(uuid, text) to authenticated, service_role;

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
