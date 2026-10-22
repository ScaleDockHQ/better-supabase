-- ==== alone: schema supabase/schemas/900_better_supabase_130_channels.sql
-- better-supabase module: channels
-- @bs-module channels@1 managed
-- Named conversations on the messaging core: public channels anyone in the tenant reads and joins, private ones for their members, each with a topic, a purpose and an optional linked record. Create, rename, join, leave and browse; messages, threads, typing and read markers come from messaging.
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
-- Channels: named conversations in a tenant, public (read by the tenant) or
-- private (read by their members), with a topic, a purpose and an optional
-- linked record. Messages, threads, typing and read markers come from the
-- messaging module; a channel's id is its conversation's id.

create table if not exists "better_supabase"."channels" (
  "id" uuid primary key references "better_supabase"."conversations" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "name" text not null check ("name" ~ '^[a-z0-9][a-z0-9_-]{0,79}$'),
  "visibility" text not null default 'public' check ("visibility" in ('public', 'private')),
  "topic" text check ("topic" is null or length("topic") <= 250),
  "purpose" text check ("purpose" is null or length("purpose") <= 250),
  "subject_type" text,
  "subject_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null))
);
create unique index if not exists channels_name_idx on "better_supabase"."channels" ("tenant_id", "name");
create index if not exists channels_subject_idx on "better_supabase"."channels" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."channels" enable row level security;
revoke all on "better_supabase"."channels" from anon, authenticated;
grant select on "better_supabase"."channels" to authenticated;
grant all on "better_supabase"."channels" to service_role;

-- A channel is visible when its conversation is: a public one to the tenant,
-- a private one to its members.
drop policy if exists channels_read on "better_supabase"."channels";
create policy channels_read on "better_supabase"."channels" for select to authenticated
using (exists (select 1 from "better_supabase"."conversations" c where c."id" = "better_supabase"."channels"."id"));


-- Creates a channel: a conversation of kind channel with a unique lowercase
-- name in the tenant. attrs: visibility ('public', read by the tenant, or
-- 'private', read by its members), topic, purpose, and subjectType and
-- subjectId to link it to a record. members joins others with the caller.
create or replace function "better_supabase"."create_channel"(tenant uuid, name text, attrs jsonb default '{}', members uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := lower(trim(create_channel.name));
  v_visibility text := coalesce(create_channel.attrs ->> 'visibility', 'public');
  v_conv jsonb;
  v_ch "better_supabase"."channels";
  v_c "better_supabase"."conversations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_channel.tenant, 'channels.create'), false)) then
    raise exception 'not allowed to create channels here' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  if v_name is null or v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  if (nullif(create_channel.attrs ->> 'subjectType', '') is null) <> (nullif(create_channel.attrs ->> 'subjectId', '') is null) then
    raise exception 'a linked record needs subjectType and subjectId' using errcode = '22023', hint = 'CHANNELS_SUBJECT_INVALID';
  end if;
  if nullif(create_channel.attrs ->> 'subjectType', '') is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(create_channel.attrs ->> 'subjectType', create_channel.attrs ->> 'subjectId', 'read'), false)) then
    raise exception 'no such record you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if coalesce(null::text <> create_channel.tenant::text, false) then
    raise exception 'no such record in this organization' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."channels" x where x."tenant_id" = create_channel.tenant and x."name" = v_name) then
    raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
  end if;
  v_conv := "better_supabase"."open_conversation"(
    create_channel.tenant,
    'channel',
    jsonb_build_object('title', v_name, 'access', case v_visibility when 'public' then 'tenant' else 'members' end),
    create_channel.members
  );
  begin
    insert into "better_supabase"."channels" ("id", "tenant_id", "name", "visibility", "topic", "purpose", "subject_type", "subject_id", "created_by")
    values ((v_conv ->> 'id')::uuid, create_channel.tenant, v_name, v_visibility,
      nullif(trim(create_channel.attrs ->> 'topic'), ''), nullif(trim(create_channel.attrs ->> 'purpose'), ''),
      nullif(create_channel.attrs ->> 'subjectType', ''), nullif(create_channel.attrs ->> 'subjectId', ''), auth.uid())
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  null;
  select * into v_c from "better_supabase"."conversations" c where c."id" = v_ch."id";
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$$;
revoke execute on function "better_supabase"."create_channel"(uuid, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_channel"(uuid, text, jsonb, uuid[]) to authenticated, service_role;

-- Renames a channel or changes its topic, purpose or visibility: whoever
-- holds the manage key, or the channel's owner. A key left out of attrs keeps
-- its value; null clears topic and purpose.
create or replace function "better_supabase"."update_channel"(channel uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ch "better_supabase"."channels";
  v_c "better_supabase"."conversations";
  v_name text;
  v_visibility text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ch from "better_supabase"."channels" x where x."id" = update_channel.channel;
  if not found or not "better_supabase"."can_conversation"(v_ch."id", 'read') then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_ch."tenant_id", 'channels.manage'), false)
    or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_ch."id" and k."user_id" = auth.uid() and k."role" = 'owner'))) then
    raise exception 'not allowed to change this channel' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  v_name := coalesce(lower(trim(update_channel.attrs ->> 'name')), v_ch."name");
  if v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  v_visibility := coalesce(update_channel.attrs ->> 'visibility', v_ch."visibility");
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  begin
    update "better_supabase"."channels" x set
      "name" = v_name,
      "visibility" = v_visibility,
      "topic" = case when update_channel.attrs ? 'topic' then nullif(trim(update_channel.attrs ->> 'topic'), '') else x."topic" end,
      "purpose" = case when update_channel.attrs ? 'purpose' then nullif(trim(update_channel.attrs ->> 'purpose'), '') else x."purpose" end,
      "updated_at" = now()
    where x."id" = v_ch."id"
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  update "better_supabase"."conversations" c set
    "title" = v_name,
    "access" = case v_visibility when 'public' then 'tenant' else 'members' end,
    "updated_at" = now()
  where c."id" = v_ch."id"
  returning * into v_c;
  null;
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$$;
revoke execute on function "better_supabase"."update_channel"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_channel"(uuid, jsonb) to authenticated, service_role;

-- The caller joins a public channel; true when they are a member after it.
create or replace function "better_supabase"."join_channel"(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from "better_supabase"."channels" x where x."id" = join_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  perform "better_supabase"."add_conversation_members"(join_channel.channel, array[auth.uid()]);
  return true;
end;
$$;
revoke execute on function "better_supabase"."join_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."join_channel"(uuid) to authenticated, service_role;

-- The caller leaves a channel; false when they weren't a member.
create or replace function "better_supabase"."leave_channel"(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from "better_supabase"."channels" x where x."id" = leave_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."remove_conversation_member"(leave_channel.channel, auth.uid());
end;
$$;
revoke execute on function "better_supabase"."leave_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."leave_channel"(uuid) to authenticated, service_role;

-- Adds members to a channel; returns how many joined. The messaging rules
-- apply: members add others to a private channel, a moderator adds anyone.
create or replace function "better_supabase"."invite_to_channel"(channel uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."channels" x where x."id" = invite_to_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."add_conversation_members"(invite_to_channel.channel, invite_to_channel.users);
end;
$$;
revoke execute on function "better_supabase"."invite_to_channel"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."invite_to_channel"(uuid, uuid[]) to authenticated, service_role;

-- Archives a channel (read-only from then on) or restores it: its owner or a
-- moderator, as messaging decides.
create or replace function "better_supabase"."archive_channel"(channel uuid, archived boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."channels" x where x."id" = archive_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."archive_conversation"(archive_channel.channel, archive_channel.archived);
end;
$$;
revoke execute on function "better_supabase"."archive_channel"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_channel"(uuid, boolean) to authenticated, service_role;

-- The tenant's channels by name: the caller's, or with browse every channel
-- they can see (public ones and the private ones they are in). Archived
-- channels only with include_archived.
create or replace function "better_supabase"."list_channels"(tenant uuid, browse boolean default false, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."tenant_id" = list_channels.tenant
    and (list_channels.include_archived or c."archived_at" is null)
    and (list_channels.browse or exists (
      select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()
    ))
$$;
revoke execute on function "better_supabase"."list_channels"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_channels"(uuid, boolean, boolean) to authenticated, service_role;

-- One channel by id, or null when the caller can't see it.
create or replace function "better_supabase"."get_channel"(channel uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    )
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."id" = get_channel.channel
$$;
revoke execute on function "better_supabase"."get_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."get_channel"(uuid) to authenticated, service_role;

-- One channel by its name in the tenant, or null.
create or replace function "better_supabase"."find_channel"(tenant uuid, name text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    )
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."tenant_id" = find_channel.tenant and x."name" = lower(trim(find_channel.name))
$$;
revoke execute on function "better_supabase"."find_channel"(uuid, text) from public, anon;
grant execute on function "better_supabase"."find_channel"(uuid, text) to authenticated, service_role;

-- The channels linked to a record that the caller can see, by name.
create or replace function "better_supabase"."channels_for_record"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."subject_type" = channels_for_record.subject_type and x."subject_id" = channels_for_record.subject_id
$$;
revoke execute on function "better_supabase"."channels_for_record"(text, text) from public, anon;
grant execute on function "better_supabase"."channels_for_record"(text, text) to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_130_channels.sql
-- better-supabase module: channels
-- @bs-module-data channels
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('channels', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_130_channels.sql
-- better-supabase module: channels
-- @bs-module channels@1 managed
-- Named conversations on the messaging core: public channels anyone in the tenant reads and joins, private ones for their members, each with a topic, a purpose and an optional linked record. Create, rename, join, leave and browse; messages, threads, typing and read markers come from messaging.
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
-- Channels: named conversations in a tenant, public (read by the tenant) or
-- private (read by their members), with a topic, a purpose and an optional
-- linked record. Messages, threads, typing and read markers come from the
-- messaging module; a channel's id is its conversation's id.

create table if not exists "better_supabase"."channels" (
  "id" uuid primary key references "better_supabase"."conversations" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "name" text not null check ("name" ~ '^[a-z0-9][a-z0-9_-]{0,79}$'),
  "visibility" text not null default 'public' check ("visibility" in ('public', 'private')),
  "topic" text check ("topic" is null or length("topic") <= 250),
  "purpose" text check ("purpose" is null or length("purpose") <= 250),
  "subject_type" text,
  "subject_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null))
);
create unique index if not exists channels_name_idx on "better_supabase"."channels" ("tenant_id", "name");
create index if not exists channels_subject_idx on "better_supabase"."channels" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."channels" enable row level security;
revoke all on "better_supabase"."channels" from anon, authenticated;
grant select on "better_supabase"."channels" to authenticated;
grant all on "better_supabase"."channels" to service_role;

-- A channel is visible when its conversation is: a public one to the tenant,
-- a private one to its members.
drop policy if exists channels_read on "better_supabase"."channels";
create policy channels_read on "better_supabase"."channels" for select to authenticated
using (exists (select 1 from "better_supabase"."conversations" c where c."id" = "better_supabase"."channels"."id"));


-- Creates a channel: a conversation of kind channel with a unique lowercase
-- name in the tenant. attrs: visibility ('public', read by the tenant, or
-- 'private', read by its members), topic, purpose, and subjectType and
-- subjectId to link it to a record. members joins others with the caller.
create or replace function "better_supabase"."create_channel"(tenant uuid, name text, attrs jsonb default '{}', members uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := lower(trim(create_channel.name));
  v_visibility text := coalesce(create_channel.attrs ->> 'visibility', 'public');
  v_conv jsonb;
  v_ch "better_supabase"."channels";
  v_c "better_supabase"."conversations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_channel.tenant, 'channels.create'), false)) then
    raise exception 'not allowed to create channels here' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  if v_name is null or v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  if (nullif(create_channel.attrs ->> 'subjectType', '') is null) <> (nullif(create_channel.attrs ->> 'subjectId', '') is null) then
    raise exception 'a linked record needs subjectType and subjectId' using errcode = '22023', hint = 'CHANNELS_SUBJECT_INVALID';
  end if;
  if nullif(create_channel.attrs ->> 'subjectType', '') is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(create_channel.attrs ->> 'subjectType', create_channel.attrs ->> 'subjectId', 'read'), false)) then
    raise exception 'no such record you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if coalesce(null::text <> create_channel.tenant::text, false) then
    raise exception 'no such record in this organization' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."channels" x where x."tenant_id" = create_channel.tenant and x."name" = v_name) then
    raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
  end if;
  v_conv := "better_supabase"."open_conversation"(
    create_channel.tenant,
    'channel',
    jsonb_build_object('title', v_name, 'access', case v_visibility when 'public' then 'tenant' else 'members' end),
    create_channel.members
  );
  begin
    insert into "better_supabase"."channels" ("id", "tenant_id", "name", "visibility", "topic", "purpose", "subject_type", "subject_id", "created_by")
    values ((v_conv ->> 'id')::uuid, create_channel.tenant, v_name, v_visibility,
      nullif(trim(create_channel.attrs ->> 'topic'), ''), nullif(trim(create_channel.attrs ->> 'purpose'), ''),
      nullif(create_channel.attrs ->> 'subjectType', ''), nullif(create_channel.attrs ->> 'subjectId', ''), auth.uid())
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  perform "better_supabase".emit_event('channel.created', jsonb_build_object('organizationId', v_ch."tenant_id"::text, 'channelId', v_ch."id", 'name', v_ch."name", 'visibility', v_ch."visibility", 'recordType', v_ch."subject_type", 'recordId', v_ch."subject_id", 'subjectType', 'channel', 'subjectId', v_ch."id"::text), 'channels/' || v_ch."id"::text, (v_ch."tenant_id"::text)::text, null, 'better-supabase/channels');
  perform better_supabase.audit_event(
    event_type => 'channel.created',
    category => 'configuration',
    target_type => 'channel',
    record_id => v_ch."id"::text,
    target_label => v_ch."name",
    tenant => (v_ch."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_ch."tenant_id"::text, 'channelId', v_ch."id", 'name', v_ch."name", 'visibility', v_ch."visibility", 'recordType', v_ch."subject_type", 'recordId', v_ch."subject_id", 'subjectType', 'channel', 'subjectId', v_ch."id"::text)
  );
  select * into v_c from "better_supabase"."conversations" c where c."id" = v_ch."id";
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$$;
revoke execute on function "better_supabase"."create_channel"(uuid, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_channel"(uuid, text, jsonb, uuid[]) to authenticated, service_role;

-- Renames a channel or changes its topic, purpose or visibility: whoever
-- holds the manage key, or the channel's owner. A key left out of attrs keeps
-- its value; null clears topic and purpose.
create or replace function "better_supabase"."update_channel"(channel uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ch "better_supabase"."channels";
  v_c "better_supabase"."conversations";
  v_name text;
  v_visibility text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ch from "better_supabase"."channels" x where x."id" = update_channel.channel;
  if not found or not "better_supabase"."can_conversation"(v_ch."id", 'read') then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_ch."tenant_id", 'channels.manage'), false)
    or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_ch."id" and k."user_id" = auth.uid() and k."role" = 'owner'))) then
    raise exception 'not allowed to change this channel' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  v_name := coalesce(lower(trim(update_channel.attrs ->> 'name')), v_ch."name");
  if v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  v_visibility := coalesce(update_channel.attrs ->> 'visibility', v_ch."visibility");
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  begin
    update "better_supabase"."channels" x set
      "name" = v_name,
      "visibility" = v_visibility,
      "topic" = case when update_channel.attrs ? 'topic' then nullif(trim(update_channel.attrs ->> 'topic'), '') else x."topic" end,
      "purpose" = case when update_channel.attrs ? 'purpose' then nullif(trim(update_channel.attrs ->> 'purpose'), '') else x."purpose" end,
      "updated_at" = now()
    where x."id" = v_ch."id"
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  update "better_supabase"."conversations" c set
    "title" = v_name,
    "access" = case v_visibility when 'public' then 'tenant' else 'members' end,
    "updated_at" = now()
  where c."id" = v_ch."id"
  returning * into v_c;
  perform "better_supabase".emit_event('channel.updated', jsonb_build_object('organizationId', v_ch."tenant_id"::text, 'channelId', v_ch."id", 'name', v_ch."name", 'visibility', v_ch."visibility", 'recordType', v_ch."subject_type", 'recordId', v_ch."subject_id", 'subjectType', 'channel', 'subjectId', v_ch."id"::text), 'channels/' || v_ch."id"::text, (v_ch."tenant_id"::text)::text, null, 'better-supabase/channels');
  perform better_supabase.audit_event(
    event_type => 'channel.updated',
    category => 'configuration',
    target_type => 'channel',
    record_id => v_ch."id"::text,
    target_label => v_ch."name",
    tenant => (v_ch."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_ch."tenant_id"::text, 'channelId', v_ch."id", 'name', v_ch."name", 'visibility', v_ch."visibility", 'recordType', v_ch."subject_type", 'recordId', v_ch."subject_id", 'subjectType', 'channel', 'subjectId', v_ch."id"::text)
  );
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$$;
revoke execute on function "better_supabase"."update_channel"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_channel"(uuid, jsonb) to authenticated, service_role;

-- The caller joins a public channel; true when they are a member after it.
create or replace function "better_supabase"."join_channel"(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from "better_supabase"."channels" x where x."id" = join_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  perform "better_supabase"."add_conversation_members"(join_channel.channel, array[auth.uid()]);
  return true;
end;
$$;
revoke execute on function "better_supabase"."join_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."join_channel"(uuid) to authenticated, service_role;

-- The caller leaves a channel; false when they weren't a member.
create or replace function "better_supabase"."leave_channel"(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from "better_supabase"."channels" x where x."id" = leave_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."remove_conversation_member"(leave_channel.channel, auth.uid());
end;
$$;
revoke execute on function "better_supabase"."leave_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."leave_channel"(uuid) to authenticated, service_role;

-- Adds members to a channel; returns how many joined. The messaging rules
-- apply: members add others to a private channel, a moderator adds anyone.
create or replace function "better_supabase"."invite_to_channel"(channel uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."channels" x where x."id" = invite_to_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."add_conversation_members"(invite_to_channel.channel, invite_to_channel.users);
end;
$$;
revoke execute on function "better_supabase"."invite_to_channel"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."invite_to_channel"(uuid, uuid[]) to authenticated, service_role;

-- Archives a channel (read-only from then on) or restores it: its owner or a
-- moderator, as messaging decides.
create or replace function "better_supabase"."archive_channel"(channel uuid, archived boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."channels" x where x."id" = archive_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."archive_conversation"(archive_channel.channel, archive_channel.archived);
end;
$$;
revoke execute on function "better_supabase"."archive_channel"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_channel"(uuid, boolean) to authenticated, service_role;

-- The tenant's channels by name: the caller's, or with browse every channel
-- they can see (public ones and the private ones they are in). Archived
-- channels only with include_archived.
create or replace function "better_supabase"."list_channels"(tenant uuid, browse boolean default false, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."tenant_id" = list_channels.tenant
    and (list_channels.include_archived or c."archived_at" is null)
    and (list_channels.browse or exists (
      select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()
    ))
$$;
revoke execute on function "better_supabase"."list_channels"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_channels"(uuid, boolean, boolean) to authenticated, service_role;

-- One channel by id, or null when the caller can't see it.
create or replace function "better_supabase"."get_channel"(channel uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    )
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."id" = get_channel.channel
$$;
revoke execute on function "better_supabase"."get_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."get_channel"(uuid) to authenticated, service_role;

-- One channel by its name in the tenant, or null.
create or replace function "better_supabase"."find_channel"(tenant uuid, name text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    )
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."tenant_id" = find_channel.tenant and x."name" = lower(trim(find_channel.name))
$$;
revoke execute on function "better_supabase"."find_channel"(uuid, text) from public, anon;
grant execute on function "better_supabase"."find_channel"(uuid, text) to authenticated, service_role;

-- The channels linked to a record that the caller can see, by name.
create or replace function "better_supabase"."channels_for_record"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."subject_type" = channels_for_record.subject_type and x."subject_id" = channels_for_record.subject_id
$$;
revoke execute on function "better_supabase"."channels_for_record"(text, text) from public, anon;
grant execute on function "better_supabase"."channels_for_record"(text, text) to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_130_channels.sql
-- better-supabase module: channels
-- @bs-module-data channels
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('channels', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_130_channels.sql
-- better-supabase module: channels
-- @bs-module channels@1 managed
-- Named conversations on the messaging core: public channels anyone in the tenant reads and joins, private ones for their members, each with a topic, a purpose and an optional linked record. Create, rename, join, leave and browse; messages, threads, typing and read markers come from messaging.
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Channels: named conversations in a tenant, public (read by the tenant) or
-- private (read by their members), with a topic, a purpose and an optional
-- linked record. Messages, threads, typing and read markers come from the
-- messaging module; a channel's id is its conversation's id.

create table if not exists "app_private"."channels" (
  "id" uuid primary key references "better_supabase"."conversations" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "name" text not null check ("name" ~ '^[a-z0-9][a-z0-9_-]{0,79}$'),
  "visibility" text not null default 'public' check ("visibility" in ('public', 'private')),
  "topic" text check ("topic" is null or length("topic") <= 250),
  "purpose" text check ("purpose" is null or length("purpose") <= 250),
  "subject_type" text,
  "subject_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null))
);
create unique index if not exists channels_name_idx on "app_private"."channels" ("tenant_id", "name");
create index if not exists channels_subject_idx on "app_private"."channels" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "app_private"."channels" enable row level security;
revoke all on "app_private"."channels" from anon, authenticated;
grant select on "app_private"."channels" to authenticated;
grant all on "app_private"."channels" to service_role;

-- A channel is visible when its conversation is: a public one to the tenant,
-- a private one to its members.
drop policy if exists channels_read on "app_private"."channels";
create policy channels_read on "app_private"."channels" for select to authenticated
using (exists (select 1 from "better_supabase"."conversations" c where c."id" = "app_private"."channels"."id"));


-- Creates a channel: a conversation of kind channel with a unique lowercase
-- name in the tenant. attrs: visibility ('public', read by the tenant, or
-- 'private', read by its members), topic, purpose, and subjectType and
-- subjectId to link it to a record. members joins others with the caller.
create or replace function "app_private"."create_channel"(tenant uuid, name text, attrs jsonb default '{}', members uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := lower(trim(create_channel.name));
  v_visibility text := coalesce(create_channel.attrs ->> 'visibility', 'public');
  v_conv jsonb;
  v_ch "app_private"."channels";
  v_c "better_supabase"."conversations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_channel.tenant, 'channels.create'), false)) then
    raise exception 'not allowed to create channels here' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  if v_name is null or v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  if (nullif(create_channel.attrs ->> 'subjectType', '') is null) <> (nullif(create_channel.attrs ->> 'subjectId', '') is null) then
    raise exception 'a linked record needs subjectType and subjectId' using errcode = '22023', hint = 'CHANNELS_SUBJECT_INVALID';
  end if;
  if nullif(create_channel.attrs ->> 'subjectType', '') is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(create_channel.attrs ->> 'subjectType', create_channel.attrs ->> 'subjectId', 'read'), false)) then
    raise exception 'no such record you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if coalesce(null::text <> create_channel.tenant::text, false) then
    raise exception 'no such record in this organization' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if exists (select 1 from "app_private"."channels" x where x."tenant_id" = create_channel.tenant and x."name" = v_name) then
    raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
  end if;
  v_conv := "better_supabase"."open_conversation"(
    create_channel.tenant,
    'channel',
    jsonb_build_object('title', v_name, 'access', case v_visibility when 'public' then 'tenant' else 'members' end),
    create_channel.members
  );
  begin
    insert into "app_private"."channels" ("id", "tenant_id", "name", "visibility", "topic", "purpose", "subject_type", "subject_id", "created_by")
    values ((v_conv ->> 'id')::uuid, create_channel.tenant, v_name, v_visibility,
      nullif(trim(create_channel.attrs ->> 'topic'), ''), nullif(trim(create_channel.attrs ->> 'purpose'), ''),
      nullif(create_channel.attrs ->> 'subjectType', ''), nullif(create_channel.attrs ->> 'subjectId', ''), auth.uid())
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  null;
  select * into v_c from "better_supabase"."conversations" c where c."id" = v_ch."id";
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$$;
revoke execute on function "app_private"."create_channel"(uuid, text, jsonb, uuid[]) from public, anon;
grant execute on function "app_private"."create_channel"(uuid, text, jsonb, uuid[]) to authenticated, service_role;

-- Renames a channel or changes its topic, purpose or visibility: whoever
-- holds the manage key, or the channel's owner. A key left out of attrs keeps
-- its value; null clears topic and purpose.
create or replace function "app_private"."update_channel"(channel uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ch "app_private"."channels";
  v_c "better_supabase"."conversations";
  v_name text;
  v_visibility text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ch from "app_private"."channels" x where x."id" = update_channel.channel;
  if not found or not "better_supabase"."can_conversation"(v_ch."id", 'read') then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_ch."tenant_id", 'channels.manage'), false)
    or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_ch."id" and k."user_id" = auth.uid() and k."role" = 'owner'))) then
    raise exception 'not allowed to change this channel' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  v_name := coalesce(lower(trim(update_channel.attrs ->> 'name')), v_ch."name");
  if v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  v_visibility := coalesce(update_channel.attrs ->> 'visibility', v_ch."visibility");
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  begin
    update "app_private"."channels" x set
      "name" = v_name,
      "visibility" = v_visibility,
      "topic" = case when update_channel.attrs ? 'topic' then nullif(trim(update_channel.attrs ->> 'topic'), '') else x."topic" end,
      "purpose" = case when update_channel.attrs ? 'purpose' then nullif(trim(update_channel.attrs ->> 'purpose'), '') else x."purpose" end,
      "updated_at" = now()
    where x."id" = v_ch."id"
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  update "better_supabase"."conversations" c set
    "title" = v_name,
    "access" = case v_visibility when 'public' then 'tenant' else 'members' end,
    "updated_at" = now()
  where c."id" = v_ch."id"
  returning * into v_c;
  null;
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$$;
revoke execute on function "app_private"."update_channel"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_channel"(uuid, jsonb) to authenticated, service_role;

-- The caller joins a public channel; true when they are a member after it.
create or replace function "app_private"."join_channel"(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from "app_private"."channels" x where x."id" = join_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  perform "better_supabase"."add_conversation_members"(join_channel.channel, array[auth.uid()]);
  return true;
end;
$$;
revoke execute on function "app_private"."join_channel"(uuid) from public, anon;
grant execute on function "app_private"."join_channel"(uuid) to authenticated, service_role;

-- The caller leaves a channel; false when they weren't a member.
create or replace function "app_private"."leave_channel"(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from "app_private"."channels" x where x."id" = leave_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."remove_conversation_member"(leave_channel.channel, auth.uid());
end;
$$;
revoke execute on function "app_private"."leave_channel"(uuid) from public, anon;
grant execute on function "app_private"."leave_channel"(uuid) to authenticated, service_role;

-- Adds members to a channel; returns how many joined. The messaging rules
-- apply: members add others to a private channel, a moderator adds anyone.
create or replace function "app_private"."invite_to_channel"(channel uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "app_private"."channels" x where x."id" = invite_to_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."add_conversation_members"(invite_to_channel.channel, invite_to_channel.users);
end;
$$;
revoke execute on function "app_private"."invite_to_channel"(uuid, uuid[]) from public, anon;
grant execute on function "app_private"."invite_to_channel"(uuid, uuid[]) to authenticated, service_role;

-- Archives a channel (read-only from then on) or restores it: its owner or a
-- moderator, as messaging decides.
create or replace function "app_private"."archive_channel"(channel uuid, archived boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "app_private"."channels" x where x."id" = archive_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."archive_conversation"(archive_channel.channel, archive_channel.archived);
end;
$$;
revoke execute on function "app_private"."archive_channel"(uuid, boolean) from public, anon;
grant execute on function "app_private"."archive_channel"(uuid, boolean) to authenticated, service_role;

-- The tenant's channels by name: the caller's, or with browse every channel
-- they can see (public ones and the private ones they are in). Archived
-- channels only with include_archived.
create or replace function "app_private"."list_channels"(tenant uuid, browse boolean default false, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) order by x."name"), '[]'::jsonb)
  from "app_private"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."tenant_id" = list_channels.tenant
    and (list_channels.include_archived or c."archived_at" is null)
    and (list_channels.browse or exists (
      select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()
    ))
$$;
revoke execute on function "app_private"."list_channels"(uuid, boolean, boolean) from public, anon;
grant execute on function "app_private"."list_channels"(uuid, boolean, boolean) to authenticated, service_role;

-- One channel by id, or null when the caller can't see it.
create or replace function "app_private"."get_channel"(channel uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    )
  from "app_private"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."id" = get_channel.channel
$$;
revoke execute on function "app_private"."get_channel"(uuid) from public, anon;
grant execute on function "app_private"."get_channel"(uuid) to authenticated, service_role;

-- One channel by its name in the tenant, or null.
create or replace function "app_private"."find_channel"(tenant uuid, name text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    )
  from "app_private"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."tenant_id" = find_channel.tenant and x."name" = lower(trim(find_channel.name))
$$;
revoke execute on function "app_private"."find_channel"(uuid, text) from public, anon;
grant execute on function "app_private"."find_channel"(uuid, text) to authenticated, service_role;

-- The channels linked to a record that the caller can see, by name.
create or replace function "app_private"."channels_for_record"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) order by x."name"), '[]'::jsonb)
  from "app_private"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."subject_type" = channels_for_record.subject_type and x."subject_id" = channels_for_record.subject_id
$$;
revoke execute on function "app_private"."channels_for_record"(text, text) from public, anon;
grant execute on function "app_private"."channels_for_record"(text, text) to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_130_channels.sql
-- better-supabase module: channels
-- @bs-module-data channels
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('channels', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_130_channels.sql
-- better-supabase module: channels
-- @bs-module channels@1 managed
-- Named conversations on the messaging core: public channels anyone in the tenant reads and joins, private ones for their members, each with a topic, a purpose and an optional linked record. Create, rename, join, leave and browse; messages, threads, typing and read markers come from messaging.
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
-- Channels: named conversations in a tenant, public (read by the tenant) or
-- private (read by their members), with a topic, a purpose and an optional
-- linked record. Messages, threads, typing and read markers come from the
-- messaging module; a channel's id is its conversation's id.

create table if not exists "better_supabase"."channels" (
  "id" uuid primary key references "better_supabase"."conversations" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "name" text not null check ("name" ~ '^[a-z0-9][a-z0-9_-]{0,79}$'),
  "visibility" text not null default 'public' check ("visibility" in ('public', 'private')),
  "topic" text check ("topic" is null or length("topic") <= 250),
  "purpose" text check ("purpose" is null or length("purpose") <= 250),
  "subject_type" text,
  "subject_id" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null))
);
create unique index if not exists channels_name_idx on "better_supabase"."channels" ("tenant_id", "name");
create index if not exists channels_subject_idx on "better_supabase"."channels" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."channels" enable row level security;
revoke all on "better_supabase"."channels" from anon, authenticated;
grant select on "better_supabase"."channels" to authenticated;
grant all on "better_supabase"."channels" to service_role;

-- A channel is visible when its conversation is: a public one to the tenant,
-- a private one to its members.
drop policy if exists channels_read on "better_supabase"."channels";
create policy channels_read on "better_supabase"."channels" for select to authenticated
using (exists (select 1 from "better_supabase"."conversations" c where c."id" = "better_supabase"."channels"."id"));


-- Creates a channel: a conversation of kind channel with a unique lowercase
-- name in the tenant. attrs: visibility ('public', read by the tenant, or
-- 'private', read by its members), topic, purpose, and subjectType and
-- subjectId to link it to a record. members joins others with the caller.
create or replace function "better_supabase"."create_channel"(tenant uuid, name text, attrs jsonb default '{}', members uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := lower(trim(create_channel.name));
  v_visibility text := coalesce(create_channel.attrs ->> 'visibility', 'public');
  v_conv jsonb;
  v_ch "better_supabase"."channels";
  v_c "better_supabase"."conversations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_channel.tenant, 'channels.create'), false)) then
    raise exception 'not allowed to create channels here' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  if v_name is null or v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  if (nullif(create_channel.attrs ->> 'subjectType', '') is null) <> (nullif(create_channel.attrs ->> 'subjectId', '') is null) then
    raise exception 'a linked record needs subjectType and subjectId' using errcode = '22023', hint = 'CHANNELS_SUBJECT_INVALID';
  end if;
  if nullif(create_channel.attrs ->> 'subjectType', '') is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(create_channel.attrs ->> 'subjectType', create_channel.attrs ->> 'subjectId', 'read'), false)) then
    raise exception 'no such record you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if coalesce(null::text <> create_channel.tenant::text, false) then
    raise exception 'no such record in this organization' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."channels" x where x."tenant_id" = create_channel.tenant and x."name" = v_name) then
    raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
  end if;
  v_conv := "better_supabase"."open_conversation"(
    create_channel.tenant,
    'channel',
    jsonb_build_object('title', v_name, 'access', case v_visibility when 'public' then 'tenant' else 'members' end),
    create_channel.members
  );
  begin
    insert into "better_supabase"."channels" ("id", "tenant_id", "name", "visibility", "topic", "purpose", "subject_type", "subject_id", "created_by")
    values ((v_conv ->> 'id')::uuid, create_channel.tenant, v_name, v_visibility,
      nullif(trim(create_channel.attrs ->> 'topic'), ''), nullif(trim(create_channel.attrs ->> 'purpose'), ''),
      nullif(create_channel.attrs ->> 'subjectType', ''), nullif(create_channel.attrs ->> 'subjectId', ''), auth.uid())
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  null;
  select * into v_c from "better_supabase"."conversations" c where c."id" = v_ch."id";
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$$;
revoke execute on function "better_supabase"."create_channel"(uuid, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_channel"(uuid, text, jsonb, uuid[]) to authenticated, service_role;

-- Renames a channel or changes its topic, purpose or visibility: whoever
-- holds the manage key, or the channel's owner. A key left out of attrs keeps
-- its value; null clears topic and purpose.
create or replace function "better_supabase"."update_channel"(channel uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ch "better_supabase"."channels";
  v_c "better_supabase"."conversations";
  v_name text;
  v_visibility text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ch from "better_supabase"."channels" x where x."id" = update_channel.channel;
  if not found or not "better_supabase"."can_conversation"(v_ch."id", 'read') then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_ch."tenant_id", 'channels.manage'), false)
    or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_ch."id" and k."user_id" = auth.uid() and k."role" = 'owner'))) then
    raise exception 'not allowed to change this channel' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  v_name := coalesce(lower(trim(update_channel.attrs ->> 'name')), v_ch."name");
  if v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  v_visibility := coalesce(update_channel.attrs ->> 'visibility', v_ch."visibility");
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  begin
    update "better_supabase"."channels" x set
      "name" = v_name,
      "visibility" = v_visibility,
      "topic" = case when update_channel.attrs ? 'topic' then nullif(trim(update_channel.attrs ->> 'topic'), '') else x."topic" end,
      "purpose" = case when update_channel.attrs ? 'purpose' then nullif(trim(update_channel.attrs ->> 'purpose'), '') else x."purpose" end,
      "updated_at" = now()
    where x."id" = v_ch."id"
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  update "better_supabase"."conversations" c set
    "title" = v_name,
    "access" = case v_visibility when 'public' then 'tenant' else 'members' end,
    "updated_at" = now()
  where c."id" = v_ch."id"
  returning * into v_c;
  null;
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$$;
revoke execute on function "better_supabase"."update_channel"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_channel"(uuid, jsonb) to authenticated, service_role;

-- The caller joins a public channel; true when they are a member after it.
create or replace function "better_supabase"."join_channel"(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from "better_supabase"."channels" x where x."id" = join_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  perform "better_supabase"."add_conversation_members"(join_channel.channel, array[auth.uid()]);
  return true;
end;
$$;
revoke execute on function "better_supabase"."join_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."join_channel"(uuid) to authenticated, service_role;

-- The caller leaves a channel; false when they weren't a member.
create or replace function "better_supabase"."leave_channel"(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from "better_supabase"."channels" x where x."id" = leave_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."remove_conversation_member"(leave_channel.channel, auth.uid());
end;
$$;
revoke execute on function "better_supabase"."leave_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."leave_channel"(uuid) to authenticated, service_role;

-- Adds members to a channel; returns how many joined. The messaging rules
-- apply: members add others to a private channel, a moderator adds anyone.
create or replace function "better_supabase"."invite_to_channel"(channel uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."channels" x where x."id" = invite_to_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."add_conversation_members"(invite_to_channel.channel, invite_to_channel.users);
end;
$$;
revoke execute on function "better_supabase"."invite_to_channel"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."invite_to_channel"(uuid, uuid[]) to authenticated, service_role;

-- Archives a channel (read-only from then on) or restores it: its owner or a
-- moderator, as messaging decides.
create or replace function "better_supabase"."archive_channel"(channel uuid, archived boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from "better_supabase"."channels" x where x."id" = archive_channel.channel) then
    raise exception 'no such channel you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  return "better_supabase"."archive_conversation"(archive_channel.channel, archive_channel.archived);
end;
$$;
revoke execute on function "better_supabase"."archive_channel"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_channel"(uuid, boolean) to authenticated, service_role;

-- The tenant's channels by name: the caller's, or with browse every channel
-- they can see (public ones and the private ones they are in). Archived
-- channels only with include_archived.
create or replace function "better_supabase"."list_channels"(tenant uuid, browse boolean default false, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."tenant_id" = list_channels.tenant
    and (list_channels.include_archived or c."archived_at" is null)
    and (list_channels.browse or exists (
      select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()
    ))
$$;
revoke execute on function "better_supabase"."list_channels"(uuid, boolean, boolean) from public, anon;
grant execute on function "better_supabase"."list_channels"(uuid, boolean, boolean) to authenticated, service_role;

-- One channel by id, or null when the caller can't see it.
create or replace function "better_supabase"."get_channel"(channel uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    )
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."id" = get_channel.channel
$$;
revoke execute on function "better_supabase"."get_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."get_channel"(uuid) to authenticated, service_role;

-- One channel by its name in the tenant, or null.
create or replace function "better_supabase"."find_channel"(tenant uuid, name text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    )
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."tenant_id" = find_channel.tenant and x."name" = lower(trim(find_channel.name))
$$;
revoke execute on function "better_supabase"."find_channel"(uuid, text) from public, anon;
grant execute on function "better_supabase"."find_channel"(uuid, text) to authenticated, service_role;

-- The channels linked to a record that the caller can see, by name.
create or replace function "better_supabase"."channels_for_record"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."channels" x
  join "better_supabase"."conversations" c on c."id" = x."id"
  where x."subject_type" = channels_for_record.subject_type and x."subject_id" = channels_for_record.subject_id
$$;
revoke execute on function "better_supabase"."channels_for_record"(text, text) from public, anon;
grant execute on function "better_supabase"."channels_for_record"(text, text) to authenticated, service_role;

-- blocks.channels.api: entry points for the Data API.
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

create or replace function "api"."create_channel"(tenant uuid, name text, attrs jsonb default '{}', members uuid[] default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_channel"($1, $2, $3, $4) $$;
revoke execute on function "api"."create_channel"(uuid, text, jsonb, uuid[]) from public, anon;
grant execute on function "api"."create_channel"(uuid, text, jsonb, uuid[]) to authenticated, service_role;

create or replace function "api"."update_channel"(channel uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_channel"($1, $2) $$;
revoke execute on function "api"."update_channel"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_channel"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."join_channel"(channel uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."join_channel"($1) $$;
revoke execute on function "api"."join_channel"(uuid) from public, anon;
grant execute on function "api"."join_channel"(uuid) to authenticated, service_role;

create or replace function "api"."leave_channel"(channel uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."leave_channel"($1) $$;
revoke execute on function "api"."leave_channel"(uuid) from public, anon;
grant execute on function "api"."leave_channel"(uuid) to authenticated, service_role;

create or replace function "api"."invite_to_channel"(channel uuid, users uuid[])
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."invite_to_channel"($1, $2) $$;
revoke execute on function "api"."invite_to_channel"(uuid, uuid[]) from public, anon;
grant execute on function "api"."invite_to_channel"(uuid, uuid[]) to authenticated, service_role;

create or replace function "api"."archive_channel"(channel uuid, archived boolean default true)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_channel"($1, $2) $$;
revoke execute on function "api"."archive_channel"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_channel"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."list_channels"(tenant uuid, browse boolean default false, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_channels"($1, $2, $3) $$;
revoke execute on function "api"."list_channels"(uuid, boolean, boolean) from public, anon;
grant execute on function "api"."list_channels"(uuid, boolean, boolean) to authenticated, service_role;

create or replace function "api"."get_channel"(channel uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_channel"($1) $$;
revoke execute on function "api"."get_channel"(uuid) from public, anon;
grant execute on function "api"."get_channel"(uuid) to authenticated, service_role;

create or replace function "api"."find_channel"(tenant uuid, name text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."find_channel"($1, $2) $$;
revoke execute on function "api"."find_channel"(uuid, text) from public, anon;
grant execute on function "api"."find_channel"(uuid, text) to authenticated, service_role;

create or replace function "api"."channels_for_record"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."channels_for_record"($1, $2) $$;
revoke execute on function "api"."channels_for_record"(text, text) from public, anon;
grant execute on function "api"."channels_for_record"(text, text) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_130_channels.sql
-- better-supabase module: channels
-- @bs-module-data channels
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('channels', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
