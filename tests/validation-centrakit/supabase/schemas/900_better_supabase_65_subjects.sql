-- better-supabase module: subjects
-- @bsb-block subjects@1 managed
-- The app-wide subject registry from config.records: subject_title, subject_url, subject_titles, can_subject, can_subject_for and record_summary for every registered type, my_work across the installed blocks, and Realtime presence on presence:<type>:<id> for readers of the subject.
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
-- The app's subject registry (config.subjects, ADR 0020). Each function runs
-- as the caller, so the subject table's own policies decide what is visible.
create or replace function "better_supabase"."subject_types"()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select '{message,conversation,task,project,customer}'::text[]
$$;
revoke execute on function "better_supabase"."subject_types"() from public, anon;
grant execute on function "better_supabase"."subject_types"() to authenticated, service_role;

create or replace function "better_supabase"."subject_title"(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_title.subject_type
    when 'message' then
      return (select s."body"::text from "better_supabase"."messages" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'conversation' then
      return (select s."title"::text from "better_supabase"."conversations" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    else
      return null;
  end case;
  return null;
end;
$$;
revoke execute on function "better_supabase"."subject_title"(text, text) from public, anon;
grant execute on function "better_supabase"."subject_title"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."subject_url"(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_url.subject_type
    when '' then null;
    else
      return null;
  end case;
  return null;
end;
$$;
revoke execute on function "better_supabase"."subject_url"(text, text) from public, anon;
grant execute on function "better_supabase"."subject_url"(text, text) to authenticated, service_role;

-- Titles and paths for many subjects in one call: refs is a JSON array of
-- { "type", "id" }, the result one of { type, id, title, url }. A row the
-- caller can't see, an unknown type or a soft-deleted row returns nothing.
create or replace function "better_supabase"."subject_titles"(refs jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > 500 then
    raise exception 'subject_titles takes at most 500 refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'message', 'id', s."id"::text,
      'title', s."body"::text, 'url', null::text))
    from "better_supabase"."messages" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'message')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'conversation', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."conversations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'conversation')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'task', 'id', s."id"::text,
      'title', null::text, 'url', null::text))
    from "centrakit"."tasks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'project', 'id', s."id"::text,
      'title', null::text, 'url', null::text))
    from "centrakit"."projects" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'project')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'customer', 'id', s."id"::text,
      'title', null::text, 'url', null::text))
    from "centrakit"."customers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'customer')::bigint[])), '[]'::jsonb);
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$$;
revoke execute on function "better_supabase"."subject_titles"(jsonb) from public, anon;
grant execute on function "better_supabase"."subject_titles"(jsonb) to authenticated, service_role;

-- True when the caller can see the subject row and, for an action with a
-- key in config.records.<type>.permissions, holds that key in the
-- subject's tenant (or on the record, through the subject's scope).
create or replace function "better_supabase"."can_subject"(subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case can_subject.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'comments.create'), false)
          else true
        end)
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'comments.create'), false)
          else true
        end)
      );
    when 'task' then
      return exists (
        select 1 from "centrakit"."tasks" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    when 'project' then
      return exists (
        select 1 from "centrakit"."projects" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    when 'customer' then
      return exists (
        select 1 from "centrakit"."customers" s
        where s."id" = (can_subject.subject_id)::bigint
          and true
      );
    else
      return false;
  end case;
  return false;
end;
$$;
revoke execute on function "better_supabase"."can_subject"(text, text, text) from public, anon;
grant execute on function "better_supabase"."can_subject"(text, text, text) to authenticated, service_role;

-- A record page's header and tab badges in one call: the subject's title and
-- path, how many rows each named section has and whether any is newer than
-- seen_at. Runs as the caller, so each count is what the caller can read;
-- null when the caller can't read the subject. An unknown section is left out.
create or replace function "better_supabase"."record_summary"(subject_type text, subject_id text, sections text[], seen_at timestamptz default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_counts jsonb := '{}'::jsonb;
  v_unread jsonb := '{}'::jsonb;
  v_count bigint;
  v_latest timestamptz;
  v_seen timestamptz;
begin
  if coalesce(cardinality(record_summary.sections), 0) > 20 then
    raise exception 'record_summary takes at most 20 sections'
      using errcode = '22023', hint = 'RECORD_SECTIONS_TOO_MANY';
  end if;
  if not "better_supabase"."can_subject"(record_summary.subject_type, record_summary.subject_id, 'read') then
    return null;
  end if;
  if 'comments' = any (record_summary.sections) then
    select count(*), max(x."sent_at")
      into v_count, v_latest
      from "better_supabase"."messages" x
      join "better_supabase"."conversations" c on c."id" = x."conversation_id"
        and c."kind" = 'subject'
      where c."subject_type"::text = record_summary.subject_type
        and c."subject_id"::text = record_summary.subject_id
        and x."sent_at" is not null and x."deleted_at" is null;
    v_seen := coalesce((select "better_supabase"."conversation_read_at"(c."id") from "better_supabase"."conversations" c
        where c."kind" = 'subject'
          and c."subject_type" = record_summary.subject_type
          and c."subject_id" = record_summary.subject_id), record_summary.seen_at);
    v_counts := v_counts || jsonb_build_object('comments', v_count);
    v_unread := v_unread || jsonb_build_object('comments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  if 'attachments' = any (record_summary.sections) then
    select count(*), max(x."uploaded_at")
      into v_count, v_latest
      from "better_supabase"."attachments" x
      where x."subject_type"::text = record_summary.subject_type
        and x."subject_id"::text = record_summary.subject_id
        and x."uploaded_at" is not null and x."status" <> 'infected';
    v_seen := record_summary.seen_at;
    v_counts := v_counts || jsonb_build_object('attachments', v_count);
    v_unread := v_unread || jsonb_build_object('attachments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  return jsonb_build_object(
    'type', record_summary.subject_type,
    'id', record_summary.subject_id,
    'title', "better_supabase"."subject_title"(record_summary.subject_type, record_summary.subject_id),
    'url', "better_supabase"."subject_url"(record_summary.subject_type, record_summary.subject_id),
    'counts', v_counts,
    'unread', v_unread);
end;
$$;
revoke execute on function "better_supabase"."record_summary"(text, text, text[], timestamptz) from public, anon;
grant execute on function "better_supabase"."record_summary"(text, text, text[], timestamptz) to authenticated, service_role;

-- can_subject for another user, for server code that decides who receives
-- an event. It reads the row past its policies and asks can_user for the
-- action's key in config.records.<type>.permissions, so an action without
-- a key is false and a share-link grant never counts. A provider that
-- can't answer for others (no idsWithFor) gives false.
create or replace function "better_supabase"."can_subject_for"(member uuid, subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case can_subject_for.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'comments.create'), false)
          else false
        end
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'comments.create'), false)
          else false
        end
      );
    when 'task' then
      return exists (
        select 1 from "centrakit"."tasks" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    when 'project' then
      return exists (
        select 1 from "centrakit"."projects" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    when 'customer' then
      return exists (
        select 1 from "centrakit"."customers" s
        where s."id" = (can_subject_for.subject_id)::bigint
          and false
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$$;
revoke execute on function "better_supabase"."can_subject_for"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."can_subject_for"(uuid, text, text, text) to service_role;

-- The caller's own reminders sent in the last week, for my_work. Reminders
-- have no read policy, so this reads them past it, keeping only the caller's.
create or replace function "better_supabase"."my_reminders_due"(tenant uuid default null)
returns table (reminder uuid, subject_type text, subject_id text, at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id", r."subject_type"::text,
    r."subject_id"::text, max(d."occurrence_at")
  from "centrakit"."reminders" r
  join "centrakit"."reminder_deliveries" d on d."reminder_id" = r."id"
  where r."user_id" = (select auth.uid())
    and (my_reminders_due.tenant is null or r."tenant_id" = my_reminders_due.tenant)
    and d."sent_at" > now() - interval '7 days'
  group by 1, 2, 3
$$;
revoke execute on function "better_supabase"."my_reminders_due"(uuid) from public, anon;
grant execute on function "better_supabase"."my_reminders_due"(uuid) to authenticated, service_role;

-- What waits on the caller across the installed blocks, newest first. Runs as
-- the caller, so each row is one they can read.
create or replace function "better_supabase"."my_work"(tenant uuid default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind', w.kind,
      'subject', jsonb_build_object('type', w.subject_type, 'id', w.subject_id),
      'ref', w.ref,
      'title', coalesce(w.title, "better_supabase"."subject_title"(w.subject_type, w.subject_id)),
      'url', "better_supabase"."subject_url"(w.subject_type, w.subject_id),
      'at', w.at
    ) order by w.at desc nulls last, w.kind, w.ref), '[]'::jsonb)
    from (
      select * from (
    select 'mention'::text, c."subject_type"::text, c."subject_id"::text, m."id"::text, null::text,
      m."sent_at"
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id" and c."kind" = 'subject'
    where v_me = any (m."mentions")
      and m."deleted_at" is null
      and m."sent_at" > now() - interval '30 days'
      and (my_work.tenant is null or m."tenant_id" = my_work.tenant)
    union all
    select 'reminder'::text, d.subject_type, d.subject_id, d.reminder::text, null::text, d.at
    from "better_supabase"."my_reminders_due"(my_work.tenant) d
    where "better_supabase"."can_subject"(d.subject_type, d.subject_id, 'read')
      ) u (kind, subject_type, subject_id, ref, title, at)
      order by u.at desc nulls last, u.kind, u.ref
      limit least(greatest(coalesce(my_work.page_size, 50), 1), 200)
    ) w
  );
end;
$$;
revoke execute on function "better_supabase"."my_work"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."my_work"(uuid, integer) to authenticated, service_role;

-- Whether the caller may join presence topic `topic`
-- (presence:<type>:<id>): they can read that subject.
create or replace function "better_supabase"."subject_presence_allowed"(topic text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_parts text[] := regexp_match(subject_presence_allowed.topic, '^presence:([a-z][a-z0-9_]{0,62}):([^:]{1,200})$');
begin
  if v_parts is null then
    return false;
  end if;
  return coalesce("better_supabase"."can_subject"(v_parts[1], v_parts[2], 'read'), false);
exception
  when invalid_text_representation then
    return false;
end;
$$;
revoke execute on function "better_supabase"."subject_presence_allowed"(text) from public, anon;
grant execute on function "better_supabase"."subject_presence_allowed"(text) to authenticated, service_role;

do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bsb_subject_presence_receive" on realtime.messages;
    create policy "bsb_subject_presence_receive" on realtime.messages for select to authenticated
      using (
        realtime.messages.extension = 'presence'
        and (select realtime.topic()) like 'presence:' || '%'
        and "better_supabase"."subject_presence_allowed"((select realtime.topic()))
      );
    drop policy if exists "bsb_subject_presence_send" on realtime.messages;
    create policy "bsb_subject_presence_send" on realtime.messages for insert to authenticated
      with check ((
        realtime.messages.extension = 'presence'
        and (select realtime.topic()) like 'presence:' || '%'
        and "better_supabase"."subject_presence_allowed"((select realtime.topic()))
      ) and (select centrakit.authz_actor_may_write()));
  end if;
end;
$$;

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
