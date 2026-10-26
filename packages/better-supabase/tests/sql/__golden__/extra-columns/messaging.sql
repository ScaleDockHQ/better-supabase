-- ==== schema supabase/schemas/900_better_supabase_129_messaging.sql
-- better-supabase module: messaging
-- @bsb-block messaging@1 managed
-- @bsb-hash sha256:be50939695029f0dfb215f5f6eeccd78268116375ea7c1739fe67ad158eaf7f2
-- Conversations and messages shared by channels, record discussions and the inbox: channels, direct and group messages, one conversation per record, members with read markers and notification levels, threads, mentions, edits with history, pins, resolved threads, scheduled sends, files and reactions. Members, the tenant or the record's readers read a conversation; Realtime pings carry ids only.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."conversations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."conversations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."conversations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."conversations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."conversations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."conversation_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."conversation_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."conversation_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."conversation_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."conversation_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."messages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."messages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."messages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."messages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."messages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."message_edits";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."message_edits";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."message_edits";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."message_edits";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."message_edits";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."thread_reads";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."thread_reads";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."thread_reads";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."thread_reads";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."thread_reads";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."message_record_mentions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."message_record_mentions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."message_record_mentions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."message_record_mentions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."message_record_mentions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."thread_summaries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."thread_summaries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."thread_summaries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."thread_summaries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."thread_summaries";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Messaging: conversations (channels, direct and group messages, one per
-- record, the inbox's) with members, messages with threads, mentions, edits,
-- pins and resolution, scheduled sends and read markers. Writes go through
-- the functions; Realtime pings carry ids only.

create table if not exists "better_supabase"."conversations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" in ('channel', 'dm', 'group_dm', 'subject', 'inbox')),
  "access" text not null default 'members' check ("access" in ('members', 'tenant', 'subject')),
  "subject_type" text,
  "subject_id" text,
  "title" text check ("title" is null or length("title") between 1 and 200),
  "member_key" text,
  "created_by" uuid,
  "last_message_at" timestamptz,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null)),
  check ("access" <> 'subject' or "subject_type" is not null)
);
create unique index if not exists messaging_conversations_subject_idx on "better_supabase"."conversations" ("tenant_id", "subject_type", "subject_id") where "kind" = 'subject';
create unique index if not exists messaging_conversations_member_key_idx on "better_supabase"."conversations" ("tenant_id", "kind", "member_key") where "member_key" is not null;
create index if not exists messaging_conversations_list_idx on "better_supabase"."conversations" ("tenant_id", "last_message_at" desc nulls last, "id");
alter table "better_supabase"."conversations" enable row level security;
revoke all on "better_supabase"."conversations" from public, anon, authenticated;
grant select on "better_supabase"."conversations" to authenticated;
grant all on "better_supabase"."conversations" to service_role;

create table if not exists "better_supabase"."conversation_members" (
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null default 'member' check ("role" in ('owner', 'member')),
  "notify" text not null default 'all' check ("notify" in ('all', 'mentions', 'none')),
  "last_read_at" timestamptz,
  "joined_at" timestamptz not null default now(),
  primary key ("conversation_id", "user_id")
);
create index if not exists messaging_members_user_idx on "better_supabase"."conversation_members" ("user_id", "tenant_id");
alter table "better_supabase"."conversation_members" enable row level security;
revoke all on "better_supabase"."conversation_members" from public, anon, authenticated;
grant select on "better_supabase"."conversation_members" to authenticated;
grant all on "better_supabase"."conversation_members" to service_role;

-- Membership for the conversation policy. It runs as its owner, because the
-- members policy reads conversations and would call it again.
create or replace function "better_supabase"."is_conversation_member"(conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."conversation_members" m
    where m."conversation_id" = is_conversation_member.conversation and m."user_id" = auth.uid()
  )
$$;
revoke execute on function "better_supabase"."is_conversation_member"(uuid) from public, anon;
grant execute on function "better_supabase"."is_conversation_member"(uuid) to authenticated, service_role;

drop policy if exists conversations_read on "better_supabase"."conversations";
create policy conversations_read on "better_supabase"."conversations"
  for select to authenticated
  using (("better_supabase"."conversations"."tenant_id" in (select better_supabase.tenant_ids_with('messages.read'))
    and case "better_supabase"."conversations"."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"("better_supabase"."conversations"."id")
      when 'subject' then coalesce("better_supabase"."can_subject"("better_supabase"."conversations"."subject_type", "better_supabase"."conversations"."subject_id", 'read'), false)
      else false
    end));

drop policy if exists conversation_members_read on "better_supabase"."conversation_members";
create policy conversation_members_read on "better_supabase"."conversation_members"
  for select to authenticated
  using ("user_id" = (select auth.uid())
  or exists (select 1 from "better_supabase"."conversations" c where c."id" = "conversation_id"));

create table if not exists "better_supabase"."messages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "parent_id" uuid references "better_supabase"."messages" ("id") on delete set null,
  "thread_id" uuid references "better_supabase"."messages" ("id") on delete cascade,
  "author_id" uuid,
  "kind" text not null default 'message' check ("kind" in ('message', 'note')),
  "body" text not null default '' check (length("body") <= 40000),
  "document" jsonb,
  "anchor" jsonb,
  "mentions" uuid[] not null default '{}',
  "mention_scope" text check ("mention_scope" in ('channel', 'here')),
  "broadcast" boolean not null default false,
  "reply_count" integer not null default 0,
  "last_reply_at" timestamptz,
  "reply_user_ids" uuid[] not null default '{}',
  "pinned_at" timestamptz,
  "pinned_by" uuid,
  "resolved_at" timestamptz,
  "resolved_by" uuid,
  "scheduled_for" timestamptz,
  "sent_at" timestamptz,
  "edited_at" timestamptz,
  "deleted_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check (("thread_id" is null) = ("parent_id" is null))
);
create index if not exists messaging_messages_conversation_idx on "better_supabase"."messages" ("conversation_id", "sent_at", "id") where "thread_id" is null or "broadcast";
create index if not exists messaging_messages_thread_idx on "better_supabase"."messages" ("thread_id", "sent_at", "id") where "thread_id" is not null;
create index if not exists messaging_messages_parent_idx on "better_supabase"."messages" ("parent_id") where "parent_id" is not null;
create index if not exists messaging_messages_author_idx on "better_supabase"."messages" ("author_id");
create index if not exists messaging_messages_due_idx on "better_supabase"."messages" ("scheduled_for") where "sent_at" is null;
create index if not exists messaging_messages_file_anchor_idx on "better_supabase"."messages" (("anchor" ->> 'attachmentId')) where "anchor" ->> 'kind' = 'file';
create index if not exists messaging_messages_pinned_idx on "better_supabase"."messages" ("conversation_id", "pinned_at" desc) where "pinned_at" is not null;
alter table "better_supabase"."messages" add column if not exists "app_note" text;
alter table "better_supabase"."messages" enable row level security;
revoke all on "better_supabase"."messages" from public, anon, authenticated;
grant select on "better_supabase"."messages" to authenticated;
grant all on "better_supabase"."messages" to service_role;

-- A message shows to whoever reads its conversation once it is sent; a
-- scheduled one shows to its author only.
drop policy if exists messages_read on "better_supabase"."messages";
create policy messages_read on "better_supabase"."messages"
  for select to authenticated
  using (("sent_at" is not null or "author_id" = (select auth.uid()))
  and exists (select 1 from "better_supabase"."conversations" c where c."id" = "conversation_id"));

create table if not exists "better_supabase"."message_edits" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."messages" ("id") on delete cascade,
  "body" text not null,
  "document" jsonb,
  "edited_by" uuid,
  "edited_at" timestamptz not null default now()
);
create index if not exists messaging_edits_message_idx on "better_supabase"."message_edits" ("message_id", "edited_at");
alter table "better_supabase"."message_edits" enable row level security;
revoke all on "better_supabase"."message_edits" from public, anon, authenticated;
grant select on "better_supabase"."message_edits" to authenticated;
grant all on "better_supabase"."message_edits" to service_role;

drop policy if exists message_edits_read on "better_supabase"."message_edits";
create policy message_edits_read on "better_supabase"."message_edits"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."messages" m where m."id" = "message_id"));

-- Where a user has read to, per conversation (thread null) or per thread
-- root. Members keep the conversation marker on their member row too; a
-- record's thread has no members, so its readers keep it here.
create table if not exists "better_supabase"."thread_reads" (
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "thread_id" uuid references "better_supabase"."messages" ("id") on delete cascade,
  "last_read_at" timestamptz not null default now(),
  unique nulls not distinct ("user_id", "conversation_id", "thread_id")
);
create index if not exists messaging_reads_conversation_idx on "better_supabase"."thread_reads" ("conversation_id");
create index if not exists messaging_reads_thread_idx on "better_supabase"."thread_reads" ("thread_id");
alter table "better_supabase"."thread_reads" enable row level security;
revoke all on "better_supabase"."thread_reads" from public, anon, authenticated;
grant select on "better_supabase"."thread_reads" to authenticated;
grant all on "better_supabase"."thread_reads" to service_role;

drop policy if exists thread_reads_read on "better_supabase"."thread_reads";
create policy thread_reads_read on "better_supabase"."thread_reads"
  for select to authenticated
  using ("user_id" = (select auth.uid()));

-- The records a sent message mentions, for a record's backlinks. A row shows
-- with its message; list_record_mentions also asks can_subject on the record.
create table if not exists "better_supabase"."message_record_mentions" (
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."messages" ("id") on delete cascade,
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("message_id", "subject_type", "subject_id")
);
create index if not exists messaging_record_mentions_subject_idx on "better_supabase"."message_record_mentions" ("subject_type", "subject_id", "created_at" desc, "message_id");
create index if not exists messaging_record_mentions_conversation_idx on "better_supabase"."message_record_mentions" ("conversation_id");
alter table "better_supabase"."message_record_mentions" enable row level security;
revoke all on "better_supabase"."message_record_mentions" from public, anon, authenticated;
grant select on "better_supabase"."message_record_mentions" to authenticated;
grant all on "better_supabase"."message_record_mentions" to service_role;

drop policy if exists message_record_mentions_read on "better_supabase"."message_record_mentions";
create policy message_record_mentions_read on "better_supabase"."message_record_mentions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."messages" m where m."id" = "message_id"));

-- A thread's or a conversation's summary, which the service role writes
-- through save_thread_summary. It shows to whoever reads the conversation.
create table if not exists "better_supabase"."thread_summaries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."conversations" ("id") on delete cascade,
  "thread_id" uuid references "better_supabase"."messages" ("id") on delete cascade,
  "summary" text not null check (char_length("summary") between 1 and 20000),
  "model" text check (char_length("model") <= 200),
  "message_count" integer not null default 0 check ("message_count" >= 0),
  "through_at" timestamptz not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique nulls not distinct ("conversation_id", "thread_id")
);
create index if not exists messaging_thread_summaries_thread_idx on "better_supabase"."thread_summaries" ("thread_id");
alter table "better_supabase"."thread_summaries" enable row level security;
revoke all on "better_supabase"."thread_summaries" from public, anon, authenticated;
grant select on "better_supabase"."thread_summaries" to authenticated;
grant all on "better_supabase"."thread_summaries" to service_role;

drop policy if exists thread_summaries_read on "better_supabase"."thread_summaries";
create policy thread_summaries_read on "better_supabase"."thread_summaries"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."conversations" c where c."id" = "conversation_id"));

-- Keeps the thread root's reply count, last reply and first three repliers,
-- and the conversation's last message time, as a reply is sent or deleted.
create or replace function "better_supabase"."messaging_message_written"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."sent_at" is null then
    return null;
  end if;
  if tg_op = 'INSERT' or old."sent_at" is null then
    update "better_supabase"."conversations" c set "last_message_at" = greatest(coalesce(c."last_message_at", new."sent_at"), new."sent_at"), "updated_at" = now()
    where c."id" = new."conversation_id";
  end if;
  if new."thread_id" is not null and (tg_op = 'INSERT' or old."sent_at" is null or new."deleted_at" is distinct from old."deleted_at") then
    update "better_supabase"."messages" r set
      "reply_count" = (select count(*) from "better_supabase"."messages" x where x."thread_id" = r."id" and x."sent_at" is not null and x."deleted_at" is null),
      "last_reply_at" = (select max(x."sent_at") from "better_supabase"."messages" x where x."thread_id" = r."id" and x."deleted_at" is null),
      "reply_user_ids" = array(
        select y.u from (
          select x."author_id" as u, min(x."sent_at") as first
          from "better_supabase"."messages" x
          where x."thread_id" = r."id" and x."sent_at" is not null and x."deleted_at" is null and x."author_id" is not null
          group by x."author_id"
        ) y order by y.first limit 3
      )
    where r."id" = new."thread_id";
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."messaging_message_written"() from public, anon, authenticated;
drop trigger if exists "bsb_messaging_message_written" on "better_supabase"."messages";
create trigger "bsb_messaging_message_written" after insert or update of "sent_at", "deleted_at" on "better_supabase"."messages"
  for each row execute function "better_supabase"."messaging_message_written"();




-- The messages of ids the caller may read, oldest first, each with its
-- author, files and reactions when those modules are installed.
create or replace function "better_supabase"."messaging_messages_json"(ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with page_rows as (
    select m.* from "better_supabase"."messages" m where m."id" = any (messaging_messages_json.ids)
  )
  select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('fields', jsonb_build_object('app_note', x."app_note"))) order by coalesce(x."sent_at", x."scheduled_for", x."created_at"), x."id"), '[]'::jsonb)
  from page_rows x
$$;
revoke execute on function "better_supabase"."messaging_messages_json"(uuid[]) from public, anon;
grant execute on function "better_supabase"."messaging_messages_json"(uuid[]) to authenticated, service_role;

-- Runs once a message is sent (now or when its schedule comes due): the
-- event, the notifications and the after hook.
create or replace function "better_supabase"."messaging_message_sent"(message uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg "better_supabase"."messages";
  v_conv "better_supabase"."conversations";
begin
  select * into v_msg from "better_supabase"."messages" m where m."id" = messaging_message_sent.message;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id";
  perform "better_supabase"."index_record_mentions"(v_msg."id");
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
end;
$$;
revoke execute on function "better_supabase"."messaging_message_sent"(uuid) from public, anon, authenticated;

-- Whether the caller may act on a conversation: read it, send to it (the send
-- key, and membership unless anyone in the tenant may post), or moderate it.
create or replace function "better_supabase"."can_conversation"(conversation uuid, action text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations";
begin
  select * into v_conv from "better_supabase"."conversations" c
  where c."id" = can_conversation.conversation
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end));
  if not found then
    return false;
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return true;
  end if;
  case can_conversation.action
    when 'read' then
      return true;
    when 'send' then
      return v_conv."archived_at" is null
        and ((coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.send'), false)
        and (v_conv."access" <> 'members' or "better_supabase"."is_conversation_member"(v_conv."id"))));
    when 'moderate' then
      return coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.moderate'), false);
    else
      return false;
  end case;
end;
$$;
revoke execute on function "better_supabase"."can_conversation"(uuid, text) from public, anon;
grant execute on function "better_supabase"."can_conversation"(uuid, text) to authenticated, service_role;

-- Opens a conversation. kind channel: attrs.title, attrs.access ('members'
-- for a private one, 'tenant' for one anyone in the tenant reads). kind dm or
-- group_dm: the caller and members, one conversation per member set. kind
-- subject: attrs.subjectType and attrs.subjectId, one conversation per
-- record, read by whoever reads the record. Returns the conversation.
create or replace function "better_supabase"."open_conversation"(tenant uuid, kind text, attrs jsonb default '{}', members uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_users uuid[];
  v_key text;
  v_id uuid;
  v_access text;
  v_conv "better_supabase"."conversations";
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_conversation.tenant, 'messages.send'), false)) then
    raise exception 'not allowed to send messages here' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  v_users := array(
    select distinct x from unnest(coalesce(open_conversation.members, '{}') || case when auth.uid() is null then '{}'::uuid[] else array[auth.uid()] end) x
    where x is not null order by 1
  );
  if exists (
    select 1 from unnest(v_users) x
    where not coalesce(better_supabase.can_user(x, 'tenant', open_conversation.tenant, 'messages.read'), false)
  ) then
    raise exception 'every member must be able to read messages in the organization' using errcode = '22023', hint = 'MESSAGING_MEMBER_INVALID';
  end if;
  case open_conversation.kind
    when 'dm', 'group_dm' then
      if open_conversation.kind = 'dm' and cardinality(v_users) not in (1, 2) then
        raise exception 'a direct message has one or two people' using errcode = '22023', hint = 'MESSAGING_DM_MEMBERS';
      end if;
      if open_conversation.kind = 'group_dm' and cardinality(v_users) not between 3 and 9 then
        raise exception 'a group message has three to nine people' using errcode = '22023', hint = 'MESSAGING_GROUP_MEMBERS';
      end if;
      v_key := array_to_string(v_users, ',');
      select c."id" into v_id from "better_supabase"."conversations" c
      where c."tenant_id" = open_conversation.tenant and c."kind" = open_conversation.kind and c."member_key" = v_key;
      v_access := 'members';
    when 'subject' then
      if nullif(open_conversation.attrs ->> 'subjectType', '') is null or nullif(open_conversation.attrs ->> 'subjectId', '') is null then
        raise exception 'a record conversation needs attrs.subjectType and attrs.subjectId' using errcode = '22023', hint = 'MESSAGING_SUBJECT_REQUIRED';
      end if;
      if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(open_conversation.attrs ->> 'subjectType', open_conversation.attrs ->> 'subjectId', 'read'), false)) then
        raise exception 'no such record you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
      end if;
      -- A record with a tenant column takes conversations in its own tenant only.
      if coalesce(null::text <> open_conversation.tenant::text, false) then
        raise exception 'no such record in this organization' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
      end if;
      select c."id" into v_id from "better_supabase"."conversations" c
      where c."tenant_id" = open_conversation.tenant and c."kind" = 'subject'
        and c."subject_type" = open_conversation.attrs ->> 'subjectType' and c."subject_id" = open_conversation.attrs ->> 'subjectId';
      v_access := 'subject';
      v_users := '{}';
    when 'channel' then
      v_access := coalesce(open_conversation.attrs ->> 'access', 'members');
      if v_access not in ('members', 'tenant') then
        raise exception 'a channel''s access is members or tenant' using errcode = '22023', hint = 'MESSAGING_ACCESS_INVALID';
      end if;
    when 'inbox' then
      if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
        raise exception 'the inbox opens its own conversations' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
      end if;
      v_access := 'members';
    else
      raise exception 'kind is channel, dm, group_dm, subject or inbox' using errcode = '22023', hint = 'MESSAGING_KIND_INVALID';
  end case;
  if v_id is null then
    begin
      insert into "better_supabase"."conversations" ("tenant_id", "kind", "access", "subject_type", "subject_id", "title", "member_key", "created_by")
      values (open_conversation.tenant, open_conversation.kind, v_access,
        nullif(open_conversation.attrs ->> 'subjectType', ''), nullif(open_conversation.attrs ->> 'subjectId', ''),
        nullif(trim(open_conversation.attrs ->> 'title'), ''), v_key, auth.uid())
      returning "id" into v_id;
      v_created := true;
    exception when unique_violation then
      select c."id" into v_id from "better_supabase"."conversations" c
      where c."tenant_id" = open_conversation.tenant and c."kind" = open_conversation.kind
        and (c."member_key" = v_key or (c."subject_type" = open_conversation.attrs ->> 'subjectType' and c."subject_id" = open_conversation.attrs ->> 'subjectId'));
    when check_violation then
      raise exception 'a conversation field has an invalid value' using errcode = '22023', hint = 'MESSAGING_CONVERSATION_INVALID';
    end;
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = v_id;
  if v_created then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id", "role")
    select v_id, open_conversation.tenant, x, case when x = auth.uid() then 'owner' else 'member' end from unnest(v_users) x
    on conflict do nothing;
    null;
  end if;
  return to_jsonb(v_conv);
end;
$$;
revoke execute on function "better_supabase"."open_conversation"(uuid, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."open_conversation"(uuid, text, jsonb, uuid[]) to authenticated, service_role;

-- Adds members. A member adds others to a members-only conversation, anyone
-- who reads a tenant one joins it (users is the caller), and a moderator adds
-- anyone. Direct messages keep their members. Returns how many joined.
create or replace function "better_supabase"."add_conversation_members"(conversation uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations";
  v_user uuid;
  v_added integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = add_conversation_members.conversation;
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_conv."kind" in ('dm', 'group_dm', 'subject') then
    raise exception 'this conversation''s members can''t change' using errcode = '22023', hint = 'MESSAGING_MEMBERS_FIXED';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or "better_supabase"."can_conversation"(v_conv."id", 'moderate')
    or ("better_supabase"."can_conversation"(v_conv."id", 'send') and (v_conv."access" = 'members' or add_conversation_members.users <@ array[auth.uid()]))
    or (v_conv."access" = 'tenant' and v_conv."archived_at" is null and add_conversation_members.users <@ array[auth.uid()])) then
    raise exception 'not allowed to add members here' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  for v_user in select distinct x from unnest(add_conversation_members.users) x where x is not null loop
    if not coalesce(better_supabase.can_user(v_user, 'tenant', v_conv."tenant_id", 'messages.read'), false) then
      raise exception 'every member must be able to read messages in the organization' using errcode = '22023', hint = 'MESSAGING_MEMBER_INVALID';
    end if;
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", v_user)
    on conflict do nothing;
    if found then
      v_added := v_added + 1;
      null;
    end if;
  end loop;
  return v_added;
end;
$$;
revoke execute on function "better_supabase"."add_conversation_members"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."add_conversation_members"(uuid, uuid[]) to authenticated, service_role;

-- Removes a member: the member leaves, or a moderator or the conversation's
-- owner removes them.
create or replace function "better_supabase"."remove_conversation_member"(conversation uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = remove_conversation_member.conversation;
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_conv."kind" in ('dm', 'group_dm') then
    raise exception 'this conversation''s members can''t change' using errcode = '22023', hint = 'MESSAGING_MEMBERS_FIXED';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or remove_conversation_member.member = auth.uid()
    or "better_supabase"."can_conversation"(v_conv."id", 'moderate')
    or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = auth.uid() and k."role" = 'owner')) then
    raise exception 'not allowed to remove this member' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  delete from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = remove_conversation_member.member;
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_conversation_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_conversation_member"(uuid, uuid) to authenticated, service_role;

-- Archives a conversation (read-only from then on) or restores it: its owner
-- or a moderator.
create or replace function "better_supabase"."archive_conversation"(conversation uuid, archived boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = archive_conversation.conversation;
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or "better_supabase"."can_conversation"(v_conv."id", 'moderate')
    or v_conv."created_by" = auth.uid()
    or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = auth.uid() and k."role" = 'owner')) then
    raise exception 'not allowed to archive this conversation' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  update "better_supabase"."conversations" c
  set "archived_at" = case when archive_conversation.archived then coalesce(c."archived_at", now()) end, "updated_at" = now()
  where c."id" = v_conv."id"
  returning * into v_conv;
  if archive_conversation.archived then
    null;
  end if;
  return archive_conversation.archived;
end;
$$;
revoke execute on function "better_supabase"."archive_conversation"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_conversation"(uuid, boolean) to authenticated, service_role;

-- The caller's conversations, latest message first: those they are a member
-- of, with kinds when given. Each has unread, the caller's unread top-level
-- messages, and mentions, how many of those mention them.
create or replace function "better_supabase"."list_conversations"(tenant uuid, kinds text[] default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    to_jsonb(c) || jsonb_build_object(
      'unread', u.unread,
      'mentions', u.mentions,
      'lastReadAt', k."last_read_at",
      'notify', k."notify"
    ) order by c."last_message_at" desc nulls last, c."id"), '[]'::jsonb)
  from (
    select c.* from "better_supabase"."conversations" c
    join "better_supabase"."conversation_members" k on k."conversation_id" = c."id" and k."user_id" = auth.uid()
    where c."tenant_id" = list_conversations.tenant
      and (list_conversations.kinds is null or c."kind" = any (list_conversations.kinds))
    order by c."last_message_at" desc nulls last, c."id"
    limit least(greatest(coalesce(list_conversations.max_rows, 100), 1), 500)
  ) c
  join "better_supabase"."conversation_members" k on k."conversation_id" = c."id" and k."user_id" = auth.uid()
  cross join lateral (
    select count(*) as unread,
      count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) as mentions
    from "better_supabase"."messages" m
    where m."conversation_id" = c."id"
      and (m."thread_id" is null or m."broadcast")
      and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz)
      and m."deleted_at" is null
      and m."author_id" is distinct from auth.uid()
  ) u
$$;
revoke execute on function "better_supabase"."list_conversations"(uuid, text[], integer) from public, anon;
grant execute on function "better_supabase"."list_conversations"(uuid, text[], integer) to authenticated, service_role;

-- Unread top-level messages and mentions per member conversation of the
-- caller in a tenant: { conversationId: { unread, mentions } }, for badges.
create or replace function "better_supabase"."unread_counts"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(k."conversation_id"::text, jsonb_build_object('unread', u.unread, 'mentions', u.mentions)), '{}'::jsonb)
  from "better_supabase"."conversation_members" k
  cross join lateral (
    select count(*) as unread,
      count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) as mentions
    from "better_supabase"."messages" m
    where m."conversation_id" = k."conversation_id"
      and (m."thread_id" is null or m."broadcast")
      and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz)
      and m."deleted_at" is null
      and m."author_id" is distinct from auth.uid()
  ) u
  where k."user_id" = auth.uid()
    and k."tenant_id" = unread_counts.tenant
    and u.unread > 0
$$;
revoke execute on function "better_supabase"."unread_counts"(uuid) from public, anon;
grant execute on function "better_supabase"."unread_counts"(uuid) to authenticated, service_role;

-- Marks a conversation (thread null) or a thread read up to read_at, default
-- now. A member's conversation marker lives on their member row; everyone
-- else's, and every thread marker, in thread_reads. Markers only move forward.
create or replace function "better_supabase"."mark_read"(conversation uuid, thread uuid default null, read_at timestamptz default null)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_at timestamptz := least(coalesce(mark_read.read_at, now()), now());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to mark messages read' using errcode = '42501', hint = 'MESSAGING_SIGNED_OUT';
  end if;
  select c."tenant_id" into v_tenant from "better_supabase"."conversations" c where c."id" = mark_read.conversation;
  if v_tenant is null or not "better_supabase"."can_conversation"(mark_read.conversation, 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if mark_read.thread is null then
    update "better_supabase"."conversation_members" k set "last_read_at" = greatest(coalesce(k."last_read_at", v_at), v_at)
    where k."conversation_id" = mark_read.conversation and k."user_id" = auth.uid();
    if found then
      return v_at;
    end if;
  elsif not exists (select 1 from "better_supabase"."messages" m where m."id" = mark_read.thread and m."conversation_id" = mark_read.conversation and m."thread_id" is null) then
    raise exception 'no such thread in this conversation' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  insert into "better_supabase"."thread_reads" ("tenant_id", "user_id", "conversation_id", "thread_id", "last_read_at")
  values (v_tenant, auth.uid(), mark_read.conversation, mark_read.thread, v_at)
  on conflict ("user_id", "conversation_id", "thread_id")
  do update set "last_read_at" = greatest("better_supabase"."thread_reads"."last_read_at", excluded."last_read_at");
  return v_at;
end;
$$;
revoke execute on function "better_supabase"."mark_read"(uuid, uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."mark_read"(uuid, uuid, timestamptz) to authenticated, service_role;

-- Where user (default the caller) has read a conversation to: the member
-- marker, else the thread_reads one. For counters such as record_summary.
create or replace function "better_supabase"."conversation_read_at"(conversation uuid, member uuid default null)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = conversation_read_at.conversation and k."user_id" = coalesce(conversation_read_at.member, auth.uid())),
    (select r."last_read_at" from "better_supabase"."thread_reads" r where r."conversation_id" = conversation_read_at.conversation and r."user_id" = coalesce(conversation_read_at.member, auth.uid()) and r."thread_id" is null)
  )
$$;
revoke execute on function "better_supabase"."conversation_read_at"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."conversation_read_at"(uuid, uuid) to authenticated, service_role;

-- Sets how a member hears of a conversation: all, mentions or none.
create or replace function "better_supabase"."set_conversation_notify"(conversation uuid, level text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if set_conversation_notify.level not in ('all', 'mentions', 'none') then
    raise exception 'level is all, mentions or none' using errcode = '22023', hint = 'MESSAGING_NOTIFY_INVALID';
  end if;
  update "better_supabase"."conversation_members" k set "notify" = set_conversation_notify.level
  where k."conversation_id" = set_conversation_notify.conversation and k."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."set_conversation_notify"(uuid, text) from public, anon;
grant execute on function "better_supabase"."set_conversation_notify"(uuid, text) to authenticated, service_role;

-- Broadcasts that the caller is typing (or stopped) on the conversation's
-- private topic, for clients that don't send the broadcast themselves. The
-- service names who types in actor (a bot's name), default 'bot'.
drop function if exists "better_supabase"."set_typing"(uuid, boolean);
create or replace function "better_supabase"."set_typing"(conversation uuid, typing boolean default true, actor text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_who text;
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(set_typing.actor, 'bot');
  elsif auth.uid() is null or not "better_supabase"."can_conversation"(set_typing.conversation, 'send') then
    return false;
  else
    v_who := auth.uid()::text;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    return false;
  end if;
  perform realtime.send(
    jsonb_build_object('conversationId', set_typing.conversation, 'userId', v_who, 'typing', coalesce(set_typing.typing, true)),
    'typing',
    'messages:' || set_typing.conversation::text,
    true
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_typing"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."set_typing"(uuid, boolean, text) to authenticated, service_role;


-- The mentions in a body: @[Name](user:<id>) or @[Name](<id>) users,
-- @[Name](subject:<type>/<id>) records, and @channel or @here.
create or replace function "better_supabase"."parse_mentions"(body text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'users', coalesce((
      select jsonb_agg(distinct lower(m[1]))
      from regexp_matches(parse_mentions.body, '@\[[^\]\n]{1,100}\]\((?:user:)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)', 'gi') m
    ), '[]'::jsonb),
    'subjects', coalesce((
      select jsonb_agg(distinct jsonb_build_object('type', m[1], 'id', m[2]))
      from regexp_matches(parse_mentions.body, '@\[[^\]\n]{1,100}\]\(subject:([a-z][a-z0-9_-]{0,62})/([^)\s]{1,200})\)', 'g') m
    ), '[]'::jsonb),
    'scope', case
      when parse_mentions.body ~ '(^|[^\w@])@channel\M' then 'channel'
      when parse_mentions.body ~ '(^|[^\w@])@here\M' then 'here'
    end
  )
$$;
revoke execute on function "better_supabase"."parse_mentions"(text) from public, anon;
grant execute on function "better_supabase"."parse_mentions"(text) to authenticated, service_role;

-- Whether a file anchor has a valid shape: an attachmentId, and optionally a
-- page from 1, a region as fractions of the page or frame (x, y, width,
-- height, inside 0 to 1), and a time span in seconds (start from 0, end
-- after start).
create or replace function "better_supabase"."messaging_file_anchor_valid"(anchor jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_typeof(anchor) = 'object'
    and anchor ->> 'kind' = 'file'
    and coalesce(anchor ->> 'attachmentId', '') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    and (anchor -> 'page' is null
      or (jsonb_typeof(anchor -> 'page') = 'number' and (anchor ->> 'page')::numeric >= 1
        and (anchor ->> 'page')::numeric = trunc((anchor ->> 'page')::numeric)))
    and (anchor -> 'region' is null
      or (jsonb_typeof(anchor -> 'region') = 'object'
        and jsonb_typeof(anchor -> 'region' -> 'x') = 'number'
        and jsonb_typeof(anchor -> 'region' -> 'y') = 'number'
        and jsonb_typeof(anchor -> 'region' -> 'width') = 'number'
        and jsonb_typeof(anchor -> 'region' -> 'height') = 'number'
        and (anchor -> 'region' ->> 'x')::numeric >= 0
        and (anchor -> 'region' ->> 'y')::numeric >= 0
        and (anchor -> 'region' ->> 'width')::numeric > 0
        and (anchor -> 'region' ->> 'height')::numeric > 0
        and (anchor -> 'region' ->> 'x')::numeric + (anchor -> 'region' ->> 'width')::numeric <= 1
        and (anchor -> 'region' ->> 'y')::numeric + (anchor -> 'region' ->> 'height')::numeric <= 1))
    and (anchor -> 'start' is null
      or (jsonb_typeof(anchor -> 'start') = 'number' and (anchor ->> 'start')::numeric >= 0))
    and (anchor -> 'end' is null
      or (jsonb_typeof(anchor -> 'start') = 'number' and jsonb_typeof(anchor -> 'end') = 'number'
        and (anchor ->> 'end')::numeric > (anchor ->> 'start')::numeric)),
    false)
$$;
revoke execute on function "better_supabase"."messaging_file_anchor_valid"(jsonb) from public, anon;
grant execute on function "better_supabase"."messaging_file_anchor_valid"(jsonb) to authenticated, service_role;

-- Stores the records a sent message mentions, at most 20 of registered
-- subject types, in place of the ones stored before. A deleted or unsent
-- message keeps none.
create or replace function "better_supabase"."index_record_mentions"(message uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."message_record_mentions" x where x."message_id" = index_record_mentions.message;
  insert into "better_supabase"."message_record_mentions" ("tenant_id", "message_id", "conversation_id", "subject_type", "subject_id", "created_at")
  select m."tenant_id", m."id", m."conversation_id", r.subject_type, r.subject_id, m."sent_at"
  from "better_supabase"."messages" m
  cross join lateral (
    select s ->> 'type' as subject_type, s ->> 'id' as subject_id
    from jsonb_array_elements("better_supabase"."parse_mentions"(m."body") -> 'subjects') s
    where s ->> 'type' = any ("better_supabase"."subject_types"())
    limit 20
  ) r
  where m."id" = index_record_mentions.message
    and m."sent_at" is not null and m."deleted_at" is null
  on conflict do nothing;
end;
$$;
revoke execute on function "better_supabase"."index_record_mentions"(uuid) from public, anon, authenticated;

-- The sent messages that mention a record, newest first: before
-- (before, before_id) when given. Each item has the message and its
-- conversation's id, kind, title and record. Runs as the caller, so it lists
-- the messages they read, and nothing when they can't read the record.
create or replace function "better_supabase"."list_record_mentions"(subject_type text, subject_id text, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case when not coalesce("better_supabase"."can_subject"(list_record_mentions.subject_type, list_record_mentions.subject_id, 'read'), false)
    then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'message', "better_supabase"."messaging_messages_json"(array[p.message]) -> 0,
        'conversation', jsonb_build_object('id', c."id", 'kind', c."kind", 'title', c."title", 'subject_type', c."subject_type", 'subject_id', c."subject_id")
      ) order by p.created_at desc, p.message desc)
      from (
        select x."message_id" as message, x."conversation_id" as conversation, x."created_at" as created_at
        from "better_supabase"."message_record_mentions" x
        where x."subject_type" = list_record_mentions.subject_type and x."subject_id" = list_record_mentions.subject_id
          and (list_record_mentions.before is null
            or (x."created_at", x."message_id") < (list_record_mentions.before, coalesce(list_record_mentions.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
        order by x."created_at" desc, x."message_id" desc
        limit least(greatest(coalesce(list_record_mentions.max_rows, 20), 1), 100)
      ) p
      join "better_supabase"."conversations" c on c."id" = p.conversation
    ), '[]'::jsonb)
  end
$$;
revoke execute on function "better_supabase"."list_record_mentions"(text, text, timestamptz, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_record_mentions"(text, text, timestamptz, uuid, integer) to authenticated, service_role;

-- Sends a message. attrs: parentId (a reply), document (rich text next to
-- body as plain text), anchor (where on the record a top-level message
-- points, such as a text range), mentions (user ids, merged with the body's
-- markup), broadcast (a reply also shown in the conversation), scheduledFor (sends
-- later) and fields (the extra columns). attachments: ids of files the caller
-- uploaded to the conversation. Returns the message.
create or replace function "better_supabase"."send_message"(conversation uuid, body text, attrs jsonb default '{}', attachments uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv "better_supabase"."conversations";
  v_id uuid;
  v_parent uuid := nullif(send_message.attrs ->> 'parentId', '')::uuid;
  v_root uuid;
  v_parsed jsonb := "better_supabase"."parse_mentions"(send_message.body);
  v_mentions uuid[];
  v_scheduled timestamptz := nullif(send_message.attrs ->> 'scheduledFor', '')::timestamptz;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = send_message.conversation;
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_conv."access" = 'tenant' and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and v_conv."archived_at" is null
    and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.send'), false) then
    perform "better_supabase"."add_conversation_members"(v_conv."id", array[auth.uid()]);
  end if;
  if not "better_supabase"."can_conversation"(v_conv."id", 'send') then
    raise exception 'not allowed to send messages here' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if nullif(trim(coalesce(send_message.body, '')), '') is null and cardinality(coalesce(send_message.attachments, '{}')) = 0 then
    raise exception 'a message needs a body or a file' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  if v_parent is not null then
    select m."thread_id" into v_root from "better_supabase"."messages" m
    where m."id" = v_parent and m."conversation_id" = v_conv."id"
      and m."sent_at" is not null and m."deleted_at" is null;
    if not found then
      raise exception 'reply to a sent message in the same conversation' using errcode = '22023', hint = 'MESSAGING_PARENT_INVALID';
    end if;
    -- One level of threads: a reply to a reply joins the root's thread.
    v_parent := coalesce(v_root, v_parent);
  end if;
  if v_parent is null and send_message.attrs -> 'anchor' ->> 'kind' = 'file' then
    if not "better_supabase"."messaging_file_anchor_valid"(send_message.attrs -> 'anchor') then
      raise exception 'a file anchor needs an attachmentId, a page from 1, a region inside 0 to 1 and a time span from 0' using errcode = '22023', hint = 'MESSAGING_ANCHOR_INVALID';
    end if;
    raise exception 'install the attachments block to anchor a message to a file' using errcode = '22023', hint = 'MESSAGING_ATTACHMENTS_UNAVAILABLE';
  end if;
  if v_scheduled is not null and v_scheduled <= now() then
    v_scheduled := null;
  end if;
  v_mentions := array(
    select distinct x from (
      select (jsonb_array_elements_text(coalesce(send_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
      union
      select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
    ) s
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_send"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using send_message.conversation, send_message.body, send_message.attrs;
    end if;
  end;
  begin
    insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor",
      "mentions", "mention_scope", "broadcast", "scheduled_for", "sent_at")
    values (v_conv."tenant_id", v_conv."id", v_parent, case when v_parent is null then null else coalesce(v_root, v_parent) end,
      auth.uid(), coalesce(send_message.body, ''), send_message.attrs -> 'document',
      case when v_parent is null then send_message.attrs -> 'anchor' end, v_mentions,
      case when v_conv."access" = 'subject' then null else v_parsed ->> 'scope' end,
      v_parent is not null and coalesce((send_message.attrs ->> 'broadcast')::boolean, false),
      v_scheduled, case when v_scheduled is null then now() end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  update "better_supabase"."messages" x set "app_note" = case when (send_message.attrs -> 'fields') ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."messages", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((send_message.attrs -> 'fields')) e where e.key in ('app_note'))) r
  where x."id" = v_id;
  if cardinality(coalesce(send_message.attachments, '{}')) > 0 then
    raise exception 'install the attachments block to send files' using errcode = '22023', hint = 'MESSAGING_ATTACHMENTS_UNAVAILABLE';
  end if;
  if v_scheduled is null then
    perform "better_supabase"."messaging_message_sent"(v_id);
  else
    null;
  end if;
  return "better_supabase"."messaging_messages_json"(array[v_id]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."send_message"(uuid, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."send_message"(uuid, text, jsonb, uuid[]) to authenticated, service_role;

-- Sends the scheduled messages that are due, oldest first, at most max_rows.
-- The jobs queue (options.scheduleQueue) or a cron calls it as the service
-- role. Returns how many it sent.
create or replace function "better_supabase"."publish_due_messages"(max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_sent integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'publish_due_messages runs as the service role' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  for v_id in
    select m."id" from "better_supabase"."messages" m
    where m."sent_at" is null and m."deleted_at" is null and m."scheduled_for" <= now()
    order by m."scheduled_for", m."id"
    limit least(greatest(coalesce(publish_due_messages.max_rows, 100), 1), 1000)
    for update skip locked
  loop
    update "better_supabase"."messages" m set "sent_at" = now() where m."id" = v_id;
    perform "better_supabase"."messaging_message_sent"(v_id);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;
revoke execute on function "better_supabase"."publish_due_messages"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."publish_due_messages"(integer) to service_role;

-- Edits the caller's own message; the old body goes to
-- message_edits. attrs: document (null removes it), mentions, fields.
create or replace function "better_supabase"."edit_message"(message uuid, body text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg "better_supabase"."messages";
  v_parsed jsonb := "better_supabase"."parse_mentions"(edit_message.body);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = edit_message.message and m."author_id" = auth.uid() and m."deleted_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    raise exception 'no message of yours has this id' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_msg."sent_at" is not null and not (true) then
    raise exception 'this message can no longer be edited' using errcode = '55000', hint = 'MESSAGING_EDIT_CLOSED';
  end if;
  if nullif(trim(coalesce(edit_message.body, '')), '') is null then
    raise exception 'a message needs a body' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_edit"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using edit_message.message, edit_message.body;
    end if;
  end;
  insert into "better_supabase"."message_edits" ("tenant_id", "message_id", "body", "document", "edited_by")
  values (v_msg."tenant_id", v_msg."id", v_msg."body", v_msg."document", auth.uid());
  begin
    update "better_supabase"."messages" m set
      "body" = edit_message.body,
      "document" = case when edit_message.attrs ? 'document' then edit_message.attrs -> 'document' else m."document" end,
      "mentions" = array(
        select distinct x from (
          select (jsonb_array_elements_text(coalesce(edit_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
          union
          select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
        ) s
      ),
      "edited_at" = now()
    where m."id" = v_msg."id"
    returning * into v_msg;
  exception when check_violation or invalid_text_representation then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  update "better_supabase"."messages" x set "app_note" = case when (edit_message.attrs -> 'fields') ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."messages", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((edit_message.attrs -> 'fields')) e where e.key in ('app_note'))) r
  where x."id" = v_msg."id";
  if v_msg."sent_at" is not null then
    perform "better_supabase"."index_record_mentions"(v_msg."id");
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_edit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."edit_message"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."edit_message"(uuid, text, jsonb) to authenticated, service_role;

-- Deletes a message: its author or a moderator. It stays as a placeholder
-- (empty body, deleted_at) so its thread keeps its place, and its files go.
create or replace function "better_supabase"."delete_message"(message uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = delete_message.message and m."deleted_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_msg."author_id" = auth.uid() or "better_supabase"."can_conversation"(v_msg."conversation_id", 'moderate')) then
    raise exception 'not allowed to delete this message' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  update "better_supabase"."messages" m set "body" = '', "document" = null, "mentions" = '{}', "mention_scope" = null,
    "pinned_at" = null, "pinned_by" = null, "deleted_at" = now()
  where m."id" = v_msg."id"
  returning * into v_msg;
  delete from "better_supabase"."message_edits" x where x."message_id" = v_msg."id";
  delete from "better_supabase"."message_record_mentions" x where x."message_id" = v_msg."id";
  if v_msg."sent_at" is not null then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_message"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_message"(uuid) to authenticated, service_role;

-- Pins or unpins a message: anyone who may send to the conversation.
create or replace function "better_supabase"."pin_message"(message uuid, pinned boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = pin_message.message and m."deleted_at" is null and m."sent_at" is not null;
  if not found or not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'no such message you can pin' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  update "better_supabase"."messages" m
  set "pinned_at" = case when pin_message.pinned then coalesce(m."pinned_at", now()) end,
    "pinned_by" = case when pin_message.pinned then coalesce(m."pinned_by", auth.uid()) end
  where m."id" = v_msg."id"
  returning * into v_msg;
  null;
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."pin_message"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."pin_message"(uuid, boolean) to authenticated, service_role;

-- Resolves a thread (its root message) or opens it again: the root's author,
-- or anyone who may send to the conversation.
create or replace function "better_supabase"."resolve_message"(message uuid, resolved boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = resolve_message.message and m."thread_id" is null and m."deleted_at" is null and m."sent_at" is not null;
  if not found or not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'no such thread you can resolve' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  update "better_supabase"."messages" m
  set "resolved_at" = case when resolve_message.resolved then coalesce(m."resolved_at", now()) end,
    "resolved_by" = case when resolve_message.resolved then coalesce(m."resolved_by", auth.uid()) end
  where m."id" = v_msg."id"
  returning * into v_msg;
  null;
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."resolve_message"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."resolve_message"(uuid, boolean) to authenticated, service_role;

-- A page of a conversation's top-level messages (and replies sent to it too),
-- oldest first: the newest max_rows before (before, before_id), or with
-- after, the oldest after (after, after_id). Scheduled messages show to their
-- author only, after the sent ones.
create or replace function "better_supabase"."list_messages"(conversation uuid, after timestamptz default null, after_id uuid default null, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."messaging_messages_json"(array(
    select p."id" from (
      select m."id" from "better_supabase"."messages" m
      where m."conversation_id" = list_messages.conversation
        and (m."thread_id" is null or m."broadcast")
        and m."sent_at" is not null
        and (list_messages.after is null
          or (m."sent_at", m."id") > (list_messages.after, coalesce(list_messages.after_id, '00000000-0000-0000-0000-000000000000'::uuid)))
        and (list_messages.before is null
          or (m."sent_at", m."id") < (list_messages.before, coalesce(list_messages.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
      order by
        case when list_messages.after is null then m."sent_at" end desc,
        case when list_messages.after is null then m."id" end desc,
        m."sent_at", m."id"
      limit least(greatest(coalesce(list_messages.max_rows, 50), 1), 200)
    ) p
    union all
    select m."id" from "better_supabase"."messages" m
    where m."conversation_id" = list_messages.conversation
      and m."sent_at" is null and m."deleted_at" is null
      and m."author_id" = auth.uid()
      and list_messages.after is null and list_messages.before is null
  ))
$$;
revoke execute on function "better_supabase"."list_messages"(uuid, timestamptz, uuid, timestamptz, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_messages"(uuid, timestamptz, uuid, timestamptz, uuid, integer) to authenticated, service_role;

-- A thread's replies, oldest first, after (after, after_id) when given.
create or replace function "better_supabase"."list_replies"(message uuid, after timestamptz default null, after_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."messaging_messages_json"(array(
    select m."id" from "better_supabase"."messages" m
    where m."thread_id" = list_replies.message
      and (m."sent_at" is not null or m."author_id" = auth.uid())
      and (list_replies.after is null
        or (m."sent_at", m."id") > (list_replies.after, coalesce(list_replies.after_id, '00000000-0000-0000-0000-000000000000'::uuid)))
    order by m."sent_at" nulls last, m."id"
    limit least(greatest(coalesce(list_replies.max_rows, 100), 1), 500)
  ))
$$;
revoke execute on function "better_supabase"."list_replies"(uuid, timestamptz, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_replies"(uuid, timestamptz, uuid, integer) to authenticated, service_role;

-- The top-level messages anchored to a file, oldest first: the comments on
-- its pages, regions and moments. Only the conversations the caller can read.
create or replace function "better_supabase"."list_file_anchors"(attachment uuid, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."messaging_messages_json"(array(
    select m."id" from "better_supabase"."messages" m
    where m."anchor" ->> 'kind' = 'file'
      and m."anchor" ->> 'attachmentId' = list_file_anchors.attachment::text
      and m."sent_at" is not null and m."deleted_at" is null
    order by m."sent_at", m."id"
    limit least(greatest(coalesce(list_file_anchors.max_rows, 100), 1), 500)
  ))
$$;
revoke execute on function "better_supabase"."list_file_anchors"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_file_anchors"(uuid, integer) to authenticated, service_role;

-- One message the caller can read, or null: for a Realtime ping's id.
create or replace function "better_supabase"."get_message"(message uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."messaging_messages_json"(array[get_message.message]) -> 0
$$;
revoke execute on function "better_supabase"."get_message"(uuid) from public, anon;
grant execute on function "better_supabase"."get_message"(uuid) to authenticated, service_role;

-- A message's earlier versions, newest first.
create or replace function "better_supabase"."list_message_edits"(message uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."edited_at" desc), '[]'::jsonb)
  from "better_supabase"."message_edits" x where x."message_id" = list_message_edits.message
$$;
revoke execute on function "better_supabase"."list_message_edits"(uuid) from public, anon;
grant execute on function "better_supabase"."list_message_edits"(uuid) to authenticated, service_role;

-- Pinned messages of a conversation, latest pin first.
create or replace function "better_supabase"."list_pinned_messages"(conversation uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."messaging_messages_json"(array(
    select m."id" from "better_supabase"."messages" m
    where m."conversation_id" = list_pinned_messages.conversation and m."pinned_at" is not null
    order by m."pinned_at" desc limit 100
  ))
$$;
revoke execute on function "better_supabase"."list_pinned_messages"(uuid) from public, anon;
grant execute on function "better_supabase"."list_pinned_messages"(uuid) to authenticated, service_role;


-- The summary of a thread (by its root message) or of a conversation's
-- top-level messages (thread null), or null. stale is true once a message in
-- scope was sent after through_at, or edited or deleted after the summary was
-- saved. Notes never count. Runs as the caller, so it shows only summaries of
-- conversations they read.
create or replace function "better_supabase"."thread_summary"(conversation uuid default null, thread uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(s) || jsonb_build_object(
    'stale', exists (
      select 1 from "better_supabase"."messages" m
      where m."conversation_id" = s."conversation_id"
        and m."kind" = 'message' and m."sent_at" is not null
        and case when s."thread_id" is null then m."thread_id" is null
          else m."id" = s."thread_id" or m."thread_id" = s."thread_id" end
        and (m."sent_at" > s."through_at"
          or m."edited_at" > s."updated_at"
          or m."deleted_at" > s."updated_at")
    )
  )
  from "better_supabase"."thread_summaries" s
  where s."conversation_id" = coalesce(thread_summary.conversation,
      (select m."conversation_id" from "better_supabase"."messages" m where m."id" = thread_summary.thread))
    and s."thread_id" is not distinct from thread_summary.thread
$$;
revoke execute on function "better_supabase"."thread_summary"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."thread_summary"(uuid, uuid) to authenticated, service_role;

-- Saves the summary of a thread (by its sent root message) or of a
-- conversation (thread null), in place of the one saved before. attrs: model,
-- messageCount and throughAt (when the newest summarized message was sent).
-- The service role calls it after the app read the messages as the user.
-- Returns the summary as thread_summary does.
create or replace function "better_supabase"."save_thread_summary"(conversation uuid, thread uuid, summary text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_conversation uuid;
  v_tenant uuid;
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'save_thread_summary runs as the service role' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if save_thread_summary.thread is null then
    select c."id", c."tenant_id" into v_conversation, v_tenant
    from "better_supabase"."conversations" c where c."id" = save_thread_summary.conversation;
  else
    select m."conversation_id", m."tenant_id" into v_conversation, v_tenant
    from "better_supabase"."messages" m
    where m."id" = save_thread_summary.thread and m."thread_id" is null and m."sent_at" is not null
      and (save_thread_summary.conversation is null or m."conversation_id" = save_thread_summary.conversation);
  end if;
  if v_conversation is null then
    raise exception 'no such conversation or thread root' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  begin
    v_count := coalesce((save_thread_summary.attrs ->> 'messageCount')::integer, 0);
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_count := -1;
  end;
  if char_length(btrim(coalesce(save_thread_summary.summary, ''))) not between 1 and 20000
    or char_length(save_thread_summary.attrs ->> 'model') > 200
    or v_count < 0
    or save_thread_summary.attrs ->> 'throughAt' is null then
    raise exception 'a summary needs 1 to 20000 characters, a message count and throughAt' using errcode = '22023', hint = 'MESSAGING_SUMMARY_INVALID';
  end if;
  insert into "better_supabase"."thread_summaries" ("tenant_id", "conversation_id", "thread_id", "summary", "model", "message_count", "through_at")
  values (v_tenant, v_conversation, save_thread_summary.thread, btrim(save_thread_summary.summary),
    save_thread_summary.attrs ->> 'model', v_count, (save_thread_summary.attrs ->> 'throughAt')::timestamptz)
  on conflict ("conversation_id", "thread_id") do update
  set "summary" = excluded."summary",
    "model" = excluded."model",
    "message_count" = excluded."message_count",
    "through_at" = excluded."through_at",
    "updated_at" = now();
  return "better_supabase"."thread_summary"(v_conversation, save_thread_summary.thread);
end;
$$;
revoke execute on function "better_supabase"."save_thread_summary"(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."save_thread_summary"(uuid, uuid, text, jsonb) to service_role;



-- Whether the caller reads conversation `id` (text, from a topic name).
create or replace function "better_supabase"."conversation_topic_allowed"(id text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when conversation_topic_allowed.id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then exists (select 1 from "better_supabase"."conversations" c where c."id" = conversation_topic_allowed.id::uuid)
    else false
  end
$$;
revoke execute on function "better_supabase"."conversation_topic_allowed"(text) from public, anon;
grant execute on function "better_supabase"."conversation_topic_allowed"(text) to authenticated, service_role;

create or replace function "better_supabase"."messaging_message_broadcast"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null and new."sent_at" is not null then
    perform realtime.send(
      jsonb_build_object('conversationId', new."conversation_id", 'messageId', new."id", 'threadId', new."thread_id"),
      case when tg_op = 'INSERT' or old."sent_at" is null then 'message' when new."deleted_at" is not null then 'message_deleted' else 'message_updated' end,
      'messages:' || new."conversation_id"::text,
      true
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."messaging_message_broadcast"() from public, anon, authenticated;
drop trigger if exists "bsb_messaging_message_broadcast" on "better_supabase"."messages";
create trigger "bsb_messaging_message_broadcast" after insert or update on "better_supabase"."messages"
  for each row execute function "better_supabase"."messaging_message_broadcast"();

do $$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_messaging_receive on realtime.messages;
create policy bsb_messaging_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like 'messages:' || '%'
        and "better_supabase"."conversation_topic_allowed"(substr((select realtime.topic()), 10)));
        drop policy if exists bsb_messaging_broadcast on realtime.messages;
create policy bsb_messaging_broadcast on realtime.messages
  for insert to authenticated
  with check ((realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like 'messages:' || '%'
        and "better_supabase"."conversation_topic_allowed"(substr((select realtime.topic()), 10))) and (select better_supabase.actor_may_write()));
  end if;
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
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
drop policy if exists bsb_tenant_scope on "better_supabase"."conversations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."conversations";
create policy bsb_tenant_scope_select on "better_supabase"."conversations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("better_supabase"."conversations"."tenant_id" in (select better_supabase.tenant_ids_with('messages.read'))
    and case "better_supabase"."conversations"."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"("better_supabase"."conversations"."id")
      when 'subject' then coalesce("better_supabase"."can_subject"("better_supabase"."conversations"."subject_type", "better_supabase"."conversations"."subject_id", 'read'), false)
      else false
    end))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."conversations";
create policy bsb_tenant_scope_insert on "better_supabase"."conversations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."conversations";
create policy bsb_tenant_scope_update on "better_supabase"."conversations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."conversations";
create policy bsb_tenant_scope_delete on "better_supabase"."conversations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."conversation_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."conversation_members";
create policy bsb_tenant_scope_select on "better_supabase"."conversation_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
  or exists (select 1 from "better_supabase"."conversations" c where c."id" = "conversation_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."conversation_members";
create policy bsb_tenant_scope_insert on "better_supabase"."conversation_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."conversation_members";
create policy bsb_tenant_scope_update on "better_supabase"."conversation_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."conversation_members";
create policy bsb_tenant_scope_delete on "better_supabase"."conversation_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."messages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."messages";
create policy bsb_tenant_scope_select on "better_supabase"."messages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("sent_at" is not null or "author_id" = (select auth.uid()))
  and exists (select 1 from "better_supabase"."conversations" c where c."id" = "conversation_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."messages";
create policy bsb_tenant_scope_insert on "better_supabase"."messages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."messages";
create policy bsb_tenant_scope_update on "better_supabase"."messages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."messages";
create policy bsb_tenant_scope_delete on "better_supabase"."messages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."message_edits";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."message_edits";
create policy bsb_tenant_scope_select on "better_supabase"."message_edits" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."messages" m where m."id" = "message_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."message_edits";
create policy bsb_tenant_scope_insert on "better_supabase"."message_edits" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."message_edits";
create policy bsb_tenant_scope_update on "better_supabase"."message_edits" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."message_edits";
create policy bsb_tenant_scope_delete on "better_supabase"."message_edits" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."thread_reads";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."thread_reads";
create policy bsb_tenant_scope_select on "better_supabase"."thread_reads" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."thread_reads";
create policy bsb_tenant_scope_insert on "better_supabase"."thread_reads" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."thread_reads";
create policy bsb_tenant_scope_update on "better_supabase"."thread_reads" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."thread_reads";
create policy bsb_tenant_scope_delete on "better_supabase"."thread_reads" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."message_record_mentions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."message_record_mentions";
create policy bsb_tenant_scope_select on "better_supabase"."message_record_mentions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."messages" m where m."id" = "message_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."message_record_mentions";
create policy bsb_tenant_scope_insert on "better_supabase"."message_record_mentions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."message_record_mentions";
create policy bsb_tenant_scope_update on "better_supabase"."message_record_mentions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."message_record_mentions";
create policy bsb_tenant_scope_delete on "better_supabase"."message_record_mentions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."thread_summaries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."thread_summaries";
create policy bsb_tenant_scope_select on "better_supabase"."thread_summaries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."conversations" c where c."id" = "conversation_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."thread_summaries";
create policy bsb_tenant_scope_insert on "better_supabase"."thread_summaries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."thread_summaries";
create policy bsb_tenant_scope_update on "better_supabase"."thread_summaries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."thread_summaries";
create policy bsb_tenant_scope_delete on "better_supabase"."thread_summaries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_129_messaging.sql
-- better-supabase module: messaging
-- @bsb-block-data messaging
-- @bsb-hash sha256:f6f663ad751dca539974d5acd6bfa3535c76b9f8c683cccee28ef362685c9b84
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('messaging', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
