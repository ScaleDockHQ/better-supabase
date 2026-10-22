import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { ChannelsSql } from "./channels-names.ts";

import { sqlString } from "../../core/template.ts";
import {
  SERVICE_CALLER,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { CHANNELS_NAMES, channelsSql } from "./channels-names.ts";

const NAME = "'^[a-z0-9][a-z0-9_-]{0,79}$'";

/**
 * `jsonb` for channel row `ch` with its conversation `c` and the caller's
 * membership.
 */
function channelJson(q: ChannelsSql, ch: string, c: string): string {
  const { cv, mb, members } = q;

  return `to_jsonb(${ch}) || jsonb_build_object(
      'archivedAt', ${c}.${cv("archivedAt")},
      'lastMessageAt', ${c}.${cv("lastMessageAt")},
      'role', (select k.${mb("role")} from ${members} k where k.${mb("conversation")} = ${c}.${cv("id")} and k.${mb("user")} = auth.uid()),
      'memberCount', (select count(*) from ${members} k where k.${mb("conversation")} = ${c}.${cv("id")})
    )`;
}

/** `ctx.record` of a channel event over the channel row variable `row`. */
function channelRecord(q: ChannelsSql, type: string, row: string): string {
  const { ch } = q;

  return q.ctx.record({
    type,
    payload: `jsonb_build_object('organizationId', ${row}.${ch("tenant")}::text, 'channelId', ${row}.${ch("id")}, 'name', ${row}.${ch("name")}, 'visibility', ${row}.${ch("visibility")}, 'recordType', ${row}.${ch("subjectType")}, 'recordId', ${row}.${ch("subjectId")}, 'subjectType', ${sqlString(q.e("channel"))}, 'subjectId', ${row}.${ch("id")}::text)`,
    subject: `'channels/' || ${row}.${ch("id")}::text`,
    tenant: `${row}.${ch("tenant")}::text`,
    audit: {
      category: "configuration",
      targetType: q.e("channel"),
      recordId: `${row}.${ch("id")}::text`,
      targetLabel: `${row}.${ch("name")}`,
    },
  });
}

function channelsTable(q: ChannelsSql): string {
  const { ctx, t, ch, cv, conversations } = q;
  const idx = (name: string): string => ctx.naming.rename(name);
  const policy = `${ctx.tableName("channels").name}_read`;

  if (!ctx.manages) {
    return "";
  }

  return `
create table if not exists ${t("channels")} (
  ${ch("id")} uuid primary key references ${conversations} (${cv("id")}) on delete cascade,
  ${ch("tenant")} ${ctx.idType} not null,
  ${ch("name")} text not null check (${ch("name")} ~ ${NAME}),
  ${ch("visibility")} text not null default 'public' check (${ch("visibility")} in ('public', 'private')),
  ${ch("topic")} text check (${ch("topic")} is null or length(${ch("topic")}) <= 250),
  ${ch("purpose")} text check (${ch("purpose")} is null or length(${ch("purpose")}) <= 250),
  ${ch("subjectType")} text,
  ${ch("subjectId")} text,
  ${ch("createdBy")} uuid,
  ${ch("createdAt")} timestamptz not null default now(),
  ${ch("updatedAt")} timestamptz not null default now(),
  check ((${ch("subjectType")} is null) = (${ch("subjectId")} is null))
);
create unique index if not exists ${idx("channels_name_idx")} on ${t("channels")} (${ch("tenant")}, ${ch("name")});
create index if not exists ${idx("channels_subject_idx")} on ${t("channels")} (${ch("tenant")}, ${ch("subjectType")}, ${ch("subjectId")}) where ${ch("subjectType")} is not null;
${lockTable(t("channels"), { read: true })}

-- A channel is visible when its conversation is: a public one to the tenant,
-- a private one to its members.
drop policy if exists ${policy} on ${t("channels")};
create policy ${policy} on ${t("channels")} for select to authenticated
using (exists (select 1 from ${conversations} c where c.${cv("id")} = ${t("channels")}.${ch("id")}));
`;
}

/** The channel functions: create, update, join, leave, list and look up. */
function channelsFunctions(q: ChannelsSql): string {
  const { ctx, t, fn, ch, cv, mb, mfn, conversations, members } = q;
  const id = ctx.idType;
  const subjects = ctx.of("subjects");

  const manage = (row: string): string =>
    `(${q.ctx.scope.can(`${row}.${ch("tenant")}`, q.key("manage"))}
    or exists (select 1 from ${members} k where k.${mb("conversation")} = ${row}.${ch("id")} and k.${mb("user")} = auth.uid() and k.${mb("role")} = 'owner'))`;

  return `
-- Creates a channel: a conversation of kind channel with a unique lowercase
-- name in the tenant. attrs: visibility ('public', read by the tenant, or
-- 'private', read by its members), topic, purpose, and subjectType and
-- subjectId to link it to a record. members joins others with the caller.
create or replace function ${fn("create_channel")}(tenant ${id}, name text, attrs jsonb default '{}', members uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := lower(trim(create_channel.name));
  v_visibility text := coalesce(create_channel.attrs ->> 'visibility', 'public');
  v_conv jsonb;
  v_ch ${t("channels")};
  v_c ${conversations};
begin
  if not (${SERVICE_CALLER} or ${q.can("create_channel.tenant", "create")}) then
    ${fail("CHANNELS_FORBIDDEN", "not allowed to create channels here")}
  end if;
  if v_name is null or v_name !~ ${NAME} then
    ${fail("CHANNELS_NAME_INVALID", "a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit", "22023")}
  end if;
  if v_visibility not in ('public', 'private') then
    ${fail("CHANNELS_VISIBILITY_INVALID", "a channel is public or private", "22023")}
  end if;
  if (nullif(create_channel.attrs ->> 'subjectType', '') is null) <> (nullif(create_channel.attrs ->> 'subjectId', '') is null) then
    ${fail("CHANNELS_SUBJECT_INVALID", "a linked record needs subjectType and subjectId", "22023")}
  end if;
  if nullif(create_channel.attrs ->> 'subjectType', '') is not null
    and not (${SERVICE_CALLER} or coalesce(${subjects.fn("can_subject")}(create_channel.attrs ->> 'subjectType', create_channel.attrs ->> 'subjectId', 'read'), false)) then
    ${fail("CHANNELS_NOT_FOUND", "no such record you can read", "P0002")}
  end if;
  if coalesce(${subjectTenant(ctx, "(create_channel.attrs ->> 'subjectType')", "(create_channel.attrs ->> 'subjectId')")} <> create_channel.tenant::text, false) then
    ${fail("CHANNELS_NOT_FOUND", "no such record in this organization", "P0002")}
  end if;
  if exists (select 1 from ${t("channels")} x where x.${ch("tenant")} = create_channel.tenant and x.${ch("name")} = v_name) then
    ${fail("CHANNELS_NAME_TAKEN", "a channel with this name exists", "23505")}
  end if;
  v_conv := ${mfn("open_conversation")}(
    create_channel.tenant,
    'channel',
    jsonb_build_object('title', v_name, 'access', case v_visibility when 'public' then 'tenant' else 'members' end),
    create_channel.members
  );
  begin
    insert into ${t("channels")} (${ch("id")}, ${ch("tenant")}, ${ch("name")}, ${ch("visibility")}, ${ch("topic")}, ${ch("purpose")}, ${ch("subjectType")}, ${ch("subjectId")}, ${ch("createdBy")})
    values ((v_conv ->> 'id')::uuid, create_channel.tenant, v_name, v_visibility,
      nullif(trim(create_channel.attrs ->> 'topic'), ''), nullif(trim(create_channel.attrs ->> 'purpose'), ''),
      nullif(create_channel.attrs ->> 'subjectType', ''), nullif(create_channel.attrs ->> 'subjectId', ''), auth.uid())
    returning * into v_ch;
  exception
    when unique_violation then
      ${fail("CHANNELS_NAME_TAKEN", "a channel with this name exists", "23505")}
    when check_violation then
      ${fail("CHANNELS_INVALID", "a channel field has an invalid value", "22023")}
  end;
  ${channelRecord(q, "channel.created", "v_ch")}
  select * into v_c from ${conversations} c where c.${cv("id")} = v_ch.${ch("id")};
  return ${channelJson(q, "v_ch", "v_c")};
end;
$$;
${userGrant(`${fn("create_channel")}(${id}, text, jsonb, uuid[])`)}

-- Renames a channel or changes its topic, purpose or visibility: whoever
-- holds the manage key, or the channel's owner. A key left out of attrs keeps
-- its value; null clears topic and purpose.
create or replace function ${fn("update_channel")}(channel uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ch ${t("channels")};
  v_c ${conversations};
  v_name text;
  v_visibility text;
begin
  select * into v_ch from ${t("channels")} x where x.${ch("id")} = update_channel.channel;
  if not found or not ${mfn("can_conversation")}(v_ch.${ch("id")}, 'read') then
    ${fail("CHANNELS_NOT_FOUND", "no such channel you can read", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${manage("v_ch")}) then
    ${fail("CHANNELS_FORBIDDEN", "not allowed to change this channel")}
  end if;
  v_name := coalesce(lower(trim(update_channel.attrs ->> 'name')), v_ch.${ch("name")});
  if v_name !~ ${NAME} then
    ${fail("CHANNELS_NAME_INVALID", "a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit", "22023")}
  end if;
  v_visibility := coalesce(update_channel.attrs ->> 'visibility', v_ch.${ch("visibility")});
  if v_visibility not in ('public', 'private') then
    ${fail("CHANNELS_VISIBILITY_INVALID", "a channel is public or private", "22023")}
  end if;
  begin
    update ${t("channels")} x set
      ${ch("name")} = v_name,
      ${ch("visibility")} = v_visibility,
      ${ch("topic")} = case when update_channel.attrs ? 'topic' then nullif(trim(update_channel.attrs ->> 'topic'), '') else x.${ch("topic")} end,
      ${ch("purpose")} = case when update_channel.attrs ? 'purpose' then nullif(trim(update_channel.attrs ->> 'purpose'), '') else x.${ch("purpose")} end,
      ${ch("updatedAt")} = now()
    where x.${ch("id")} = v_ch.${ch("id")}
    returning * into v_ch;
  exception
    when unique_violation then
      ${fail("CHANNELS_NAME_TAKEN", "a channel with this name exists", "23505")}
    when check_violation then
      ${fail("CHANNELS_INVALID", "a channel field has an invalid value", "22023")}
  end;
  update ${conversations} c set
    ${cv("title")} = v_name,
    ${cv("access")} = case v_visibility when 'public' then 'tenant' else 'members' end,
    ${cv("updatedAt")} = now()
  where c.${cv("id")} = v_ch.${ch("id")}
  returning * into v_c;
  ${channelRecord(q, "channel.updated", "v_ch")}
  return ${channelJson(q, "v_ch", "v_c")};
end;
$$;
${userGrant(`${fn("update_channel")}(uuid, jsonb)`)}

-- The caller joins a public channel; true when they are a member after it.
create or replace function ${fn("join_channel")}(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from ${t("channels")} x where x.${ch("id")} = join_channel.channel) then
    ${fail("CHANNELS_NOT_FOUND", "no such channel you can read", "P0002")}
  end if;
  perform ${mfn("add_conversation_members")}(join_channel.channel, array[auth.uid()]);
  return true;
end;
$$;
${userGrant(`${fn("join_channel")}(uuid)`)}

-- The caller leaves a channel; false when they weren't a member.
create or replace function ${fn("leave_channel")}(channel uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (select 1 from ${t("channels")} x where x.${ch("id")} = leave_channel.channel) then
    ${fail("CHANNELS_NOT_FOUND", "no such channel you can read", "P0002")}
  end if;
  return ${mfn("remove_conversation_member")}(leave_channel.channel, auth.uid());
end;
$$;
${userGrant(`${fn("leave_channel")}(uuid)`)}

-- Adds members to a channel; returns how many joined. The messaging rules
-- apply: members add others to a private channel, a moderator adds anyone.
create or replace function ${fn("invite_to_channel")}(channel uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from ${t("channels")} x where x.${ch("id")} = invite_to_channel.channel) then
    ${fail("CHANNELS_NOT_FOUND", "no such channel you can read", "P0002")}
  end if;
  return ${mfn("add_conversation_members")}(invite_to_channel.channel, invite_to_channel.users);
end;
$$;
${userGrant(`${fn("invite_to_channel")}(uuid, uuid[])`)}

-- Archives a channel (read-only from then on) or restores it: its owner or a
-- moderator, as messaging decides.
create or replace function ${fn("archive_channel")}(channel uuid, archived boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from ${t("channels")} x where x.${ch("id")} = archive_channel.channel) then
    ${fail("CHANNELS_NOT_FOUND", "no such channel you can read", "P0002")}
  end if;
  return ${mfn("archive_conversation")}(archive_channel.channel, archive_channel.archived);
end;
$$;
${userGrant(`${fn("archive_channel")}(uuid, boolean)`)}

-- The tenant's channels by name: the caller's, or with browse every channel
-- they can see (public ones and the private ones they are in). Archived
-- channels only with include_archived.
create or replace function ${fn("list_channels")}(tenant ${id}, browse boolean default false, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${channelJson(q, "x", "c")} order by x.${ch("name")}), '[]'::jsonb)
  from ${t("channels")} x
  join ${conversations} c on c.${cv("id")} = x.${ch("id")}
  where ${ctx.scope.eq(`x.${ch("tenant")}`, "list_channels.tenant")}
    and (list_channels.include_archived or c.${cv("archivedAt")} is null)
    and (list_channels.browse or exists (
      select 1 from ${members} k where k.${mb("conversation")} = x.${ch("id")} and k.${mb("user")} = auth.uid()
    ))
$$;
${userGrant(`${fn("list_channels")}(${id}, boolean, boolean)`)}

-- One channel by id, or null when the caller can't see it.
create or replace function ${fn("get_channel")}(channel uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${channelJson(q, "x", "c")}
  from ${t("channels")} x
  join ${conversations} c on c.${cv("id")} = x.${ch("id")}
  where x.${ch("id")} = get_channel.channel
$$;
${userGrant(`${fn("get_channel")}(uuid)`)}

-- One channel by its name in the tenant, or null.
create or replace function ${fn("find_channel")}(tenant ${id}, name text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${channelJson(q, "x", "c")}
  from ${t("channels")} x
  join ${conversations} c on c.${cv("id")} = x.${ch("id")}
  where ${ctx.scope.eq(`x.${ch("tenant")}`, "find_channel.tenant")} and x.${ch("name")} = lower(trim(find_channel.name))
$$;
${userGrant(`${fn("find_channel")}(${id}, text)`)}

-- The channels linked to a record that the caller can see, by name.
create or replace function ${fn("channels_for_record")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${channelJson(q, "x", "c")} order by x.${ch("name")}), '[]'::jsonb)
  from ${t("channels")} x
  join ${conversations} c on c.${cv("id")} = x.${ch("id")}
  where x.${ch("subjectType")} = channels_for_record.subject_type and x.${ch("subjectId")} = channels_for_record.subject_id
$$;
${userGrant(`${fn("channels_for_record")}(text, text)`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const q = channelsSql(ctx);

  return `${schemaPreamble(ctx)}
-- Channels: named conversations in a tenant, public (read by the tenant) or
-- private (read by their members), with a topic, a purpose and an optional
-- linked record. Messages, threads, typing and read markers come from the
-- messaging module; a channel's id is its conversation's id.
${channelsTable(q)}
${channelsFunctions(q)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_channel",
      args: ["{id}", "text", "jsonb", "uuid[]"],
      returns: "jsonb",
    },
    { name: "update_channel", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "join_channel", args: ["uuid"], returns: "boolean" },
    { name: "leave_channel", args: ["uuid"], returns: "boolean" },
    { name: "invite_to_channel", args: ["uuid", "uuid[]"], returns: "integer" },
    { name: "archive_channel", args: ["uuid", "boolean"], returns: "boolean" },
    {
      name: "list_channels",
      args: ["{id}", "boolean", "boolean"],
      returns: "jsonb",
    },
    { name: "get_channel", args: ["uuid"], returns: "jsonb" },
    { name: "find_channel", args: ["{id}", "text"], returns: "jsonb" },
    { name: "channels_for_record", args: ["text", "text"], returns: "jsonb" },
  ];
}

export const CHANNELS: BlockSqlDefinition = {
  name: "channels",
  scopes: ["tenant"],
  title: "Channels",
  description:
    "Named conversations on the messaging core: public channels anyone in the tenant reads and joins, private ones for their members, each with a topic, a purpose and an optional linked record. Create, rename, join, leave and browse; messages, threads, typing and read markers come from messaging.",
  requires: ["memberships", "permissions", "subjects", "messaging"],
  integrates: ["outbox", "audit", "data-lifecycle"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: CHANNELS_NAMES,
  contract,
  build,
};
