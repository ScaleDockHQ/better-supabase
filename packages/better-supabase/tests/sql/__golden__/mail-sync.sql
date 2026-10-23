-- ==== alone: schema supabase/schemas/900_better_supabase_132_mail_sync.sql
-- better-supabase module: mail-sync
-- @bsb-block mail-sync@1 managed
-- Gmail, Outlook and other mailboxes synced per member through their own OAuth grant: threads and messages linked to the people and companies they involve, logged as email engagements, and a record of the mail members send, with opens and clicks per message and per template version.
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
-- Gmail, Outlook and other mailboxes synced per member: threads and messages
-- linked to the people and companies they involve, logged as engagements.
create table if not exists "better_supabase"."mail_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9-]{0,39}$'),
  "address" text not null check ("address" = lower("address") and "address" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object'),
  "share" text not null default 'records' check ("share" in ('records', 'private')),
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'error', 'disconnected')),
  "sync_cursor" text,
  "last_synced_at" timestamptz,
  "last_error" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "address")
);
create index if not exists mail_accounts_user_idx on "better_supabase"."mail_accounts" ("user_id");
create index if not exists mail_accounts_due_idx on "better_supabase"."mail_accounts" ("last_synced_at" nulls first) where "status" = 'active';
alter table "better_supabase"."mail_accounts" enable row level security;
revoke all on "better_supabase"."mail_accounts" from anon, authenticated;
grant select on "better_supabase"."mail_accounts" to authenticated;
grant all on "better_supabase"."mail_accounts" to service_role;
create table if not exists "better_supabase"."mail_threads" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."mail_accounts" ("id") on delete cascade,
  "external_id" text not null,
  "subject" text,
  "snippet" text,
  "last_message_at" timestamptz,
  "message_count" integer not null default 0,
  "engagement_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("account_id", "external_id")
);
create index if not exists mail_threads_tenant_recent_idx on "better_supabase"."mail_threads" ("tenant_id", "last_message_at" desc);
create index if not exists mail_threads_engagement_idx on "better_supabase"."mail_threads" ("engagement_id") where "engagement_id" is not null;
alter table "better_supabase"."mail_threads" enable row level security;
revoke all on "better_supabase"."mail_threads" from anon, authenticated;
grant select on "better_supabase"."mail_threads" to authenticated;
grant all on "better_supabase"."mail_threads" to service_role;
create table if not exists "better_supabase"."mail_messages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."mail_accounts" ("id") on delete cascade,
  "thread_id" uuid not null references "better_supabase"."mail_threads" ("id") on delete cascade,
  "external_id" text not null,
  "rfc_message_id" text,
  "direction" text not null check ("direction" in ('inbound', 'outbound')),
  "from_address" text,
  "from_name" text,
  "to_addresses" text[] not null default '{}',
  "cc_addresses" text[] not null default '{}',
  "subject" text,
  "snippet" text,
  "body_text" text,
  "body_html" text,
  "sent_at" timestamptz not null,
  "template_version_id" uuid,
  "tracking_hash" text check ("tracking_hash" ~ '^[0-9a-f]{64}$'),
  "opened_at" timestamptz,
  "open_count" integer not null default 0,
  "clicked_at" timestamptz,
  "click_count" integer not null default 0,
  "created_at" timestamptz not null default now(),
  unique ("account_id", "external_id")
);
create index if not exists mail_messages_thread_idx on "better_supabase"."mail_messages" ("thread_id", "sent_at");
create index if not exists mail_messages_rfc_idx on "better_supabase"."mail_messages" ("account_id", "rfc_message_id") where "rfc_message_id" is not null;
create unique index if not exists mail_messages_tracking_idx on "better_supabase"."mail_messages" ("tracking_hash") where "tracking_hash" is not null;
create index if not exists mail_messages_template_idx on "better_supabase"."mail_messages" ("tenant_id", "template_version_id") where "template_version_id" is not null;
alter table "better_supabase"."mail_messages" enable row level security;
revoke all on "better_supabase"."mail_messages" from anon, authenticated;
grant select on "better_supabase"."mail_messages" to authenticated;
grant all on "better_supabase"."mail_messages" to service_role;
create table if not exists "better_supabase"."mail_tracked_links" (
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."mail_messages" ("id") on delete cascade,
  "position" integer not null check ("position" >= 0),
  "url" text not null check ("url" ~* '^https?://' and length("url") <= 2048),
  "click_count" integer not null default 0,
  "created_at" timestamptz not null default now(),
  primary key ("message_id", "position")
);
alter table "better_supabase"."mail_tracked_links" enable row level security;
revoke all on "better_supabase"."mail_tracked_links" from anon, authenticated;
grant select on "better_supabase"."mail_tracked_links" to authenticated;
grant all on "better_supabase"."mail_tracked_links" to service_role;
create table if not exists "better_supabase"."mail_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."mail_messages" ("id") on delete cascade,
  "kind" text not null check ("kind" in ('open', 'click')),
  "position" integer,
  "user_agent" text check (length("user_agent") <= 300),
  "occurred_at" timestamptz not null default now()
);
create index if not exists mail_tracking_events_message_idx on "better_supabase"."mail_tracking_events" ("message_id", "occurred_at");
alter table "better_supabase"."mail_tracking_events" enable row level security;
revoke all on "better_supabase"."mail_tracking_events" from anon, authenticated;
grant select on "better_supabase"."mail_tracking_events" to authenticated;
grant all on "better_supabase"."mail_tracking_events" to service_role;
create table if not exists "better_supabase"."mail_thread_subjects" (
  "tenant_id" uuid not null,
  "thread_id" uuid not null references "better_supabase"."mail_threads" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "source" text not null default 'match' check ("source" in ('match', 'manual')),
  "created_at" timestamptz not null default now(),
  primary key ("thread_id", "subject_type", "subject_id")
);
create index if not exists mail_thread_subjects_subject_idx on "better_supabase"."mail_thread_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."mail_thread_subjects" enable row level security;
revoke all on "better_supabase"."mail_thread_subjects" from anon, authenticated;
grant select on "better_supabase"."mail_thread_subjects" to authenticated;
grant all on "better_supabase"."mail_thread_subjects" to service_role;

-- Whether the caller may read a thread: its mailbox is theirs, or the mailbox
-- shares with records and the caller can read one of the thread's records.
create or replace function "better_supabase"."mail_thread_visible"(thread uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."mail_threads" x
    join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
    where x."id" = $1
      and (k."user_id" = auth.uid() or (
        k."share" = 'records'
        and coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.read'), false)
        and exists (
          select 1 from "better_supabase"."mail_thread_subjects" s
          where s."thread_id" = x."id"
            and "better_supabase"."can_subject"(s."subject_type", s."subject_id", 'read')
        )
      ))
  )
$$;
revoke execute on function "better_supabase"."mail_thread_visible"(uuid) from public, anon;
grant execute on function "better_supabase"."mail_thread_visible"(uuid) to authenticated, service_role;

drop policy if exists mail_accounts_read on "better_supabase"."mail_accounts";
create policy mail_accounts_read on "better_supabase"."mail_accounts" for select to authenticated
using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('mail.manage')));
drop policy if exists mail_threads_read on "better_supabase"."mail_threads";
create policy mail_threads_read on "better_supabase"."mail_threads" for select to authenticated
using ("better_supabase"."mail_thread_visible"("id"));
drop policy if exists mail_messages_read on "better_supabase"."mail_messages";
create policy mail_messages_read on "better_supabase"."mail_messages" for select to authenticated
using ("better_supabase"."mail_thread_visible"("thread_id"));
drop policy if exists mail_thread_subjects_read on "better_supabase"."mail_thread_subjects";
create policy mail_thread_subjects_read on "better_supabase"."mail_thread_subjects" for select to authenticated
using ("better_supabase"."mail_thread_visible"("thread_id"));
drop policy if exists mail_tracked_links_read on "better_supabase"."mail_tracked_links";
create policy mail_tracked_links_read on "better_supabase"."mail_tracked_links" for select to authenticated
using (exists (select 1 from "better_supabase"."mail_messages" y where y."id" = "message_id" and "better_supabase"."mail_thread_visible"(y."thread_id")));
drop policy if exists mail_tracking_events_read on "better_supabase"."mail_tracking_events";
create policy mail_tracking_events_read on "better_supabase"."mail_tracking_events" for select to authenticated
using (exists (select 1 from "better_supabase"."mail_messages" y where y."id" = "message_id" and "better_supabase"."mail_thread_visible"(y."thread_id")));

-- Stores a message on its account: message is { externalId, threadId,
-- messageId, direction, from: { address, name }, to, cc, subject, snippet,
-- text, html, sentAt, templateVersionId, trackingHash }. Returns { id, threadId, created, direction }.
create or replace function "better_supabase"."store_mail_message"(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account record;
  v_external text := nullif(trim(store_mail_message.message ->> 'externalId'), '');
  v_thread_ref text := coalesce(nullif(trim(store_mail_message.message ->> 'threadId'), ''), nullif(trim(store_mail_message.message ->> 'externalId'), ''));
  v_rfc text := nullif(trim(store_mail_message.message ->> 'messageId'), '');
  v_from text := lower(coalesce(nullif(trim(store_mail_message.message -> 'from' ->> 'address'), ''), case when jsonb_typeof(store_mail_message.message -> 'from') = 'string' then nullif(trim(store_mail_message.message ->> 'from'), '') end));
  v_direction text := nullif(trim(store_mail_message.message ->> 'direction'), '');
  v_template text := nullif(trim(store_mail_message.message ->> 'templateVersionId'), '');
  v_hash text := lower(nullif(trim(store_mail_message.message ->> 'trackingHash'), ''));
  v_sent timestamptz;
  v_thread uuid;
  v_id uuid;
begin
  select k."id" as id, k."tenant_id" as tenant, k."address" as address into v_account
  from "better_supabase"."mail_accounts" k where k."id" = store_mail_message.account;
  if jsonb_typeof(store_mail_message.message) <> 'object' or v_external is null or nullif(trim(store_mail_message.message ->> 'sentAt'), '') is null then
    raise exception 'a message needs an externalId and a sentAt' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if v_template is not null and v_template !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'templateVersionId is a uuid' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  v_sent := (nullif(trim(store_mail_message.message ->> 'sentAt'), ''))::timestamptz;
  v_direction := coalesce(v_direction, case when v_from = v_account.address then 'outbound' else 'inbound' end);
  if v_direction not in ('inbound', 'outbound') then
    raise exception 'direction is inbound or outbound' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  insert into "better_supabase"."mail_threads" ("tenant_id", "account_id", "external_id")
  values (v_account.tenant, v_account.id, v_thread_ref)
  on conflict ("account_id", "external_id") do update set "updated_at" = now()
  returning "id" into v_thread;
  select y."id" into v_id from "better_supabase"."mail_messages" y
  where y."account_id" = v_account.id
    and (y."external_id" = v_external or (v_rfc is not null and y."rfc_message_id" = v_rfc))
  order by y."external_id" = v_external desc
  limit 1;
  if v_id is not null then
    update "better_supabase"."mail_messages" y set "external_id" = v_external, "rfc_message_id" = coalesce(v_rfc, y."rfc_message_id")
    where y."id" = v_id
      and not exists (select 1 from "better_supabase"."mail_messages" z where z."account_id" = v_account.id and z."external_id" = v_external and z."id" <> v_id);
    return jsonb_build_object('id', v_id, 'threadId', (select y."thread_id" from "better_supabase"."mail_messages" y where y."id" = v_id), 'created', false, 'direction', v_direction);
  end if;
  insert into "better_supabase"."mail_messages" ("tenant_id", "account_id", "thread_id", "external_id", "rfc_message_id", "direction",
    "from_address", "from_name", "to_addresses", "cc_addresses", "subject", "snippet", "body_text", "body_html", "sent_at",
    "template_version_id", "tracking_hash")
  values (v_account.tenant, v_account.id, v_thread, v_external, v_rfc, v_direction,
    v_from, nullif(trim(store_mail_message.message -> 'from' ->> 'name'), ''), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'to') = 'array' then store_mail_message.message -> 'to' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'cc') = 'array' then store_mail_message.message -> 'cc' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'),
    nullif(trim(store_mail_message.message ->> 'subject'), ''), left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500), store_mail_message.message ->> 'text', store_mail_message.message ->> 'html', v_sent,
    v_template::uuid, case when v_direction = 'outbound' then v_hash end)
  returning "id" into v_id;
  update "better_supabase"."mail_threads" x set
    "subject" = coalesce(x."subject", nullif(trim(store_mail_message.message ->> 'subject'), '')),
    "snippet" = case when x."last_message_at" is null or v_sent >= x."last_message_at" then left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500) else x."snippet" end,
    "last_message_at" = greatest(x."last_message_at", v_sent),
    "message_count" = x."message_count" + 1,
    "updated_at" = now()
  where x."id" = v_thread;
  return jsonb_build_object('id', v_id, 'threadId', v_thread, 'created', true, 'direction', v_direction);
end;
$$;
revoke execute on function "better_supabase"."store_mail_message"(uuid, jsonb) from public, anon, authenticated;

-- Connects the caller's mailbox: credential_ref names the OAuth grant the
-- app stored for them. share is records (members who can read a linked
-- record see its threads) or private. Connecting again updates the grant.
create or replace function "better_supabase"."connect_mail_account"(tenant uuid, provider text, address text, credential_ref jsonb, share text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."mail_accounts";
  v_address text := lower(trim(connect_mail_account.address));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', connect_mail_account.tenant, 'mail.connect'), false) then
    raise exception 'not allowed to connect a mailbox' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if connect_mail_account.provider is null or connect_mail_account.provider !~ '^[a-z][a-z0-9-]{0,39}$' then
    raise exception 'provider is a lowercase name' using errcode = '22023', hint = 'MAIL_PROVIDER_INVALID';
  end if;
  if v_address is null or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception 'address is an email address' using errcode = '22023', hint = 'MAIL_ADDRESS_INVALID';
  end if;
  if coalesce(connect_mail_account.share, 'records') not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  if jsonb_typeof(connect_mail_account.credential_ref) is distinct from 'object' then
    raise exception 'credential_ref is a credential reference' using errcode = '22023', hint = 'MAIL_CREDENTIAL_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and connect_mail_account.credential_ref is not null and jsonb_typeof(connect_mail_account.credential_ref) <> 'null'
    and (jsonb_typeof(connect_mail_account.credential_ref -> 'tenant') is distinct from 'string' or (connect_mail_account.credential_ref ->> 'tenant') is distinct from (connect_mail_account.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', connect_mail_account.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  insert into "better_supabase"."mail_accounts" as x ("tenant_id", "user_id", "provider", "address", "credential_ref", "share")
  values (connect_mail_account.tenant, auth.uid(), connect_mail_account.provider, v_address, connect_mail_account.credential_ref, coalesce(connect_mail_account.share, 'records'))
  on conflict ("tenant_id", "user_id", "address") do update set
    "provider" = excluded."provider",
    "credential_ref" = excluded."credential_ref",
    "share" = excluded."share",
    "status" = 'active',
    "sync_cursor" = case when x."provider" = excluded."provider" then x."sync_cursor" end,
    "last_error" = null,
    "updated_at" = now()
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."connect_mail_account"(uuid, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."connect_mail_account"(uuid, text, text, jsonb, text) to authenticated, service_role;

-- Changes who sees a mailbox's threads (share) and pauses or resumes its
-- sync; null leaves a setting as it is. Only the mailbox's member may.
create or replace function "better_supabase"."update_mail_account"(account uuid, share text, paused boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if update_mail_account.share is not null and update_mail_account.share not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  update "better_supabase"."mail_accounts" x set
    "share" = coalesce(update_mail_account.share, x."share"),
    "status" = case
      when update_mail_account.paused then 'paused'
      when update_mail_account.paused = false and x."status" = 'paused' then 'active'
      else x."status" end,
    "updated_at" = now()
  where x."id" = update_mail_account.account and x."user_id" = auth.uid() and x."status" <> 'disconnected'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."update_mail_account"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."update_mail_account"(uuid, text, boolean) to authenticated, service_role;

-- Stops syncing a mailbox. Its member or a member with mail.manage may.
-- purge deletes the mailbox with its threads and messages.
create or replace function "better_supabase"."disconnect_mail_account"(account uuid, purge boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."mail_accounts" x
  where x."id" = disconnect_mail_account.account
    and (x."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.manage'), false));
  if v_row."id" is null then
    return false;
  end if;
  if coalesce(disconnect_mail_account.purge, false) then
    delete from "better_supabase"."mail_accounts" x where x."id" = v_row."id";
  else
    update "better_supabase"."mail_accounts" x set "status" = 'disconnected', "sync_cursor" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."disconnect_mail_account"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."disconnect_mail_account"(uuid, boolean) to authenticated, service_role;

-- The caller's mailboxes in a tenant; with mail.manage, every member's.
create or replace function "better_supabase"."mail_accounts_of"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at", x."id"), '[]'::jsonb)
  from "better_supabase"."mail_accounts" x
  where x."tenant_id" = mail_accounts_of.tenant
$$;
revoke execute on function "better_supabase"."mail_accounts_of"(uuid) from public, anon;
grant execute on function "better_supabase"."mail_accounts_of"(uuid) to authenticated, service_role;

-- One mailbox the caller can see, or null.
create or replace function "better_supabase"."get_mail_account"(account uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) from "better_supabase"."mail_accounts" x where x."id" = get_mail_account.account
$$;
revoke execute on function "better_supabase"."get_mail_account"(uuid) from public, anon;
grant execute on function "better_supabase"."get_mail_account"(uuid) to authenticated, service_role;

-- For the sync job: active mailboxes not synced within stale_after, the
-- longest waiting first, with their grant and cursor.
create or replace function "better_supabase"."due_mail_accounts"(max_count integer, stale_after interval)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(p) order by p."last_synced_at" nulls first, p."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."status" = 'active'
        and (x."last_synced_at" is null or x."last_synced_at" < now() - coalesce(due_mail_accounts.stale_after, interval '5 minutes'))
      order by x."last_synced_at" nulls first, x."id"
      limit least(greatest(coalesce(due_mail_accounts.max_count, 25), 1), 500)
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."due_mail_accounts"(integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."due_mail_accounts"(integer, interval) to service_role;

-- For the sync job: marks a mailbox active, paused or failed with an error
-- (a failed one waits for its member to connect it again).
create or replace function "better_supabase"."set_mail_account_status"(account uuid, status text, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if set_mail_account_status.status not in ('active', 'paused', 'error') then
    raise exception 'status is active, paused or error' using errcode = '22023', hint = 'MAIL_STATUS_INVALID';
  end if;
  update "better_supabase"."mail_accounts" x set
    "status" = set_mail_account_status.status,
    "last_error" = left(set_mail_account_status.error, 1000),
    "last_synced_at" = now(),
    "updated_at" = now()
  where x."id" = set_mail_account_status.account and x."status" <> 'disconnected';
  return found;
end;
$$;
revoke execute on function "better_supabase"."set_mail_account_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_mail_account_status"(uuid, text, text) to service_role;

-- For the sync job: stores up to 500 provider messages on a mailbox,
-- links their threads to records and logs them, then saves the cursor the
-- next sync starts from. Returns { stored, threads }.
create or replace function "better_supabase"."ingest_mail"(account uuid, messages jsonb, next_cursor text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_item jsonb;
  v_stored jsonb;
  v_new jsonb := '[]'::jsonb;
  v_threads uuid[] := '{}';
  v_thread uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "better_supabase"."mail_accounts" k where k."id" = ingest_mail.account and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such connected mailbox' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(ingest_mail.messages, '[]')) <> 'array' then
    raise exception 'messages is a list' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if jsonb_array_length(coalesce(ingest_mail.messages, '[]')) > 500 then
    raise exception 'at most 500 messages per call' using errcode = '22023', hint = 'MAIL_BATCH_TOO_LARGE';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(ingest_mail.messages, '[]')) loop
    v_stored := "better_supabase"."store_mail_message"(v_account.id, v_item);
    if not ((v_stored ->> 'threadId')::uuid = any (v_threads)) then
      v_threads := v_threads || (v_stored ->> 'threadId')::uuid;
    end if;
    if (v_stored ->> 'created')::boolean then
      v_new := v_new || jsonb_build_array(v_stored || jsonb_build_object('fromAddress', lower(coalesce(v_item -> 'from' ->> 'address', v_item ->> 'from'))));
    end if;
  end loop;
  foreach v_thread in array v_threads loop
    null;
    null;
  end loop;
  for v_stored in select value from jsonb_array_elements(v_new) loop
    if v_stored ->> 'direction' = 'outbound' then
      null;
    else
      null;
    end if;
  end loop;
  update "better_supabase"."mail_accounts" x set
    "sync_cursor" = coalesce(ingest_mail.next_cursor, x."sync_cursor"),
    "last_synced_at" = now(),
    "status" = case when x."status" = 'error' then 'active' else x."status" end,
    "last_error" = null,
    "updated_at" = now()
  where x."id" = v_account.id;
  return jsonb_build_object('stored', jsonb_array_length(v_new), 'threads', coalesce(array_length(v_threads, 1), 0));
end;
$$;
revoke execute on function "better_supabase"."ingest_mail"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_mail"(uuid, jsonb, text) to service_role;

-- Records a message the caller sent from their mailbox through the provider
-- (the block's send does both), so it shows on the thread before the next
-- sync. The service role records for any mailbox, as a server-side sender
-- such as the sequences runner does. Returns the stored message.
create or replace function "better_supabase"."record_sent_mail"(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_stored jsonb;
  v_thread uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "better_supabase"."mail_accounts" k
  where k."id" = record_sent_mail.account and (k."user_id" = auth.uid() or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_account.tenant, 'mail.send'), false) then
    raise exception 'not allowed to send mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  v_stored := "better_supabase"."store_mail_message"(v_account.id, coalesce(record_sent_mail.message, '{}'::jsonb) || '{"direction": "outbound"}'::jsonb);
  v_thread := (v_stored ->> 'threadId')::uuid;
  
  
  if (v_stored ->> 'created')::boolean then
    if jsonb_typeof(record_sent_mail.message -> 'trackedLinks') = 'array' then
      insert into "better_supabase"."mail_tracked_links" ("tenant_id", "message_id", "position", "url")
      select v_account.tenant, (v_stored ->> 'id')::uuid, (u.ord - 1)::integer, u.value #>> '{}'
      from jsonb_array_elements(record_sent_mail.message -> 'trackedLinks') with ordinality u (value, ord);
    end if;
    v_stored := v_stored || jsonb_build_object('fromAddress', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = v_account.id));
    null;
  end if;
  return (select to_jsonb(y) from "better_supabase"."mail_messages" y where y."id" = (v_stored ->> 'id')::uuid);
end;
$$;
revoke execute on function "better_supabase"."record_sent_mail"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."record_sent_mail"(uuid, jsonb) to authenticated, service_role;

-- Links a thread of the caller's mailbox to records ([{ type, id }]) by
-- hand, for senders no person matches, and logs it on them.
create or replace function "better_supabase"."link_mail_thread"(thread uuid, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_thread uuid := link_mail_thread.thread;
  v_tenant uuid;
  v_item jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant
  from "better_supabase"."mail_threads" x join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = v_thread and k."user_id" = auth.uid();
  if v_tenant is null then
    raise exception 'no such thread in your mailbox' using errcode = 'P0002', hint = 'MAIL_THREAD_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(link_mail_thread.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'MAIL_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(link_mail_thread.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'MAIL_SUBJECT_FORBIDDEN';
    end if;
    insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id", "source")
    values (v_tenant, v_thread, v_item ->> 'type', v_item ->> 'id', 'manual')
    on conflict ("thread_id", "subject_type", "subject_id") do update set "source" = 'manual';
  end loop;
  
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) from "better_supabase"."mail_threads" x where x."id" = v_thread);
end;
$$;
revoke execute on function "better_supabase"."link_mail_thread"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."link_mail_thread"(uuid, jsonb) to authenticated, service_role;

-- Removes a record from a thread of the caller's mailbox.
create or replace function "better_supabase"."unlink_mail_thread"(thread uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."mail_thread_subjects" s
  using "better_supabase"."mail_threads" x, "better_supabase"."mail_accounts" k
  where s."thread_id" = unlink_mail_thread.thread
    and s."subject_type" = unlink_mail_thread.subject_type and s."subject_id" = unlink_mail_thread.subject_id
    and x."id" = s."thread_id" and k."id" = x."account_id" and k."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."unlink_mail_thread"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."unlink_mail_thread"(uuid, text, text) to authenticated, service_role;

-- A record's threads the caller can see, the latest message first. before
-- continues after the last thread of the previous page.
create or replace function "better_supabase"."mail_threads_of"(subject_type text, subject_id text, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "better_supabase"."mail_threads" x
    join "better_supabase"."mail_thread_subjects" s on s."thread_id" = x."id"
    where s."subject_type" = mail_threads_of.subject_type and s."subject_id" = mail_threads_of.subject_id
      and (mail_threads_of.before is null or x."last_message_at" < mail_threads_of.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(mail_threads_of.page_size, 25), 1), 100)
  ) p
$$;
revoke execute on function "better_supabase"."mail_threads_of"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."mail_threads_of"(text, text, timestamptz, integer) to authenticated, service_role;

-- The threads the caller can see in a tenant, or in one mailbox, the
-- latest message first.
create or replace function "better_supabase"."list_mail_threads"(tenant uuid, account uuid, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "better_supabase"."mail_threads" x
    where x."tenant_id" = list_mail_threads.tenant
      and (list_mail_threads.account is null or x."account_id" = list_mail_threads.account)
      and (list_mail_threads.before is null or x."last_message_at" < list_mail_threads.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(list_mail_threads.page_size, 25), 1), 100)
  ) p
$$;
revoke execute on function "better_supabase"."list_mail_threads"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_mail_threads"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- A thread with its messages, oldest first; null when the caller can't see it.
create or replace function "better_supabase"."get_mail_thread"(thread uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('messages', coalesce((
    select jsonb_agg(to_jsonb(y) order by y."sent_at", y."id")
    from "better_supabase"."mail_messages" y where y."thread_id" = x."id"
  ), '[]'::jsonb))
  from "better_supabase"."mail_threads" x
  where x."id" = get_mail_thread.thread
$$;
revoke execute on function "better_supabase"."get_mail_thread"(uuid) from public, anon;
grant execute on function "better_supabase"."get_mail_thread"(uuid) to authenticated, service_role;

-- For the tracking route: records an open of the tracked message whose token
-- hashes to hash, or a click on its link at index link. Returns { messageId,
-- url } (url, the stored link, for a click), or null for an unknown token.
create or replace function "better_supabase"."track_mail"(hash text, kind text, link integer, user_agent text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message record;
  v_url text;
  v_event uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role records tracking' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if track_mail.kind is null or track_mail.kind not in ('open', 'click') then
    raise exception 'kind is open or click' using errcode = '22023', hint = 'MAIL_TRACKING_INVALID';
  end if;
  select y."id" as id, y."tenant_id" as tenant, y."account_id" as account, y."thread_id" as thread,
    y."template_version_id" as template, y."opened_at" as opened, x."user_id" as owner
  into v_message
  from "better_supabase"."mail_messages" y join "better_supabase"."mail_accounts" x on x."id" = y."account_id"
  where y."tracking_hash" = lower(track_mail.hash) and y."direction" = 'outbound';
  if v_message.id is null then
    return null;
  end if;
  if track_mail.kind = 'click' then
    update "better_supabase"."mail_tracked_links" u set "click_count" = u."click_count" + 1
    where u."message_id" = v_message.id and u."position" = track_mail.link
    returning u."url" into v_url;
    if v_url is null then
      return null;
    end if;
  end if;
  insert into "better_supabase"."mail_tracking_events" ("tenant_id", "message_id", "kind", "position", "user_agent")
  values (v_message.tenant, v_message.id, track_mail.kind, case when track_mail.kind = 'click' then track_mail.link end, left(track_mail.user_agent, 300))
  returning "id" into v_event;
  update "better_supabase"."mail_messages" y set
    "opened_at" = coalesce(y."opened_at", now()),
    "open_count" = y."open_count" + case when track_mail.kind = 'open' then 1 else 0 end,
    "clicked_at" = case when track_mail.kind = 'click' then coalesce(y."clicked_at", now()) else y."clicked_at" end,
    "click_count" = y."click_count" + case when track_mail.kind = 'click' then 1 else 0 end
  where y."id" = v_message.id;
  if track_mail.kind = 'click' then
    null;
  elsif v_message.opened is null then
    null;
  end if;
  return jsonb_build_object('messageId', v_message.id, 'url', v_url);
end;
$$;
revoke execute on function "better_supabase"."track_mail"(text, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."track_mail"(text, text, integer, text) to service_role;

-- Per template version, how many messages members sent from shared
-- mailboxes since a time, and how many were opened, clicked and replied to.
create or replace function "better_supabase"."mail_template_stats"(tenant uuid, since timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.can('tenant', mail_template_stats.tenant, 'mail.read'), false) then
    raise exception 'not allowed to read mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('templateVersionId', p.template, 'sent', p.sent, 'opened', p.opened, 'clicked', p.clicked, 'replied', p.replied) order by p.sent desc, p.template), '[]'::jsonb)
    from (
      select y."template_version_id" as template, count(*) as sent, count(y."opened_at") as opened, count(y."clicked_at") as clicked,
        count(*) filter (where exists (
          select 1 from "better_supabase"."mail_messages" r
          where r."thread_id" = y."thread_id" and r."direction" = 'inbound' and r."sent_at" > y."sent_at"
        )) as replied
      from "better_supabase"."mail_messages" y join "better_supabase"."mail_accounts" x on x."id" = y."account_id"
      where y."tenant_id" = mail_template_stats.tenant and y."direction" = 'outbound'
        and y."template_version_id" is not null
        and (x."share" = 'records' or x."user_id" = auth.uid())
        and (mail_template_stats.since is null or y."sent_at" >= mail_template_stats.since)
      group by y."template_version_id"
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."mail_template_stats"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."mail_template_stats"(uuid, timestamptz) to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_132_mail_sync.sql
-- better-supabase module: mail-sync
-- @bsb-block-data mail-sync
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_132_mail_sync.sql
-- better-supabase module: mail-sync
-- @bsb-block mail-sync@1 managed
-- Gmail, Outlook and other mailboxes synced per member through their own OAuth grant: threads and messages linked to the people and companies they involve, logged as email engagements, and a record of the mail members send, with opens and clicks per message and per template version.
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
-- Gmail, Outlook and other mailboxes synced per member: threads and messages
-- linked to the people and companies they involve, logged as engagements.
create table if not exists "better_supabase"."mail_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9-]{0,39}$'),
  "address" text not null check ("address" = lower("address") and "address" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object'),
  "share" text not null default 'records' check ("share" in ('records', 'private')),
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'error', 'disconnected')),
  "sync_cursor" text,
  "last_synced_at" timestamptz,
  "last_error" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "address")
);
create index if not exists mail_accounts_user_idx on "better_supabase"."mail_accounts" ("user_id");
create index if not exists mail_accounts_due_idx on "better_supabase"."mail_accounts" ("last_synced_at" nulls first) where "status" = 'active';
alter table "better_supabase"."mail_accounts" enable row level security;
revoke all on "better_supabase"."mail_accounts" from anon, authenticated;
grant select on "better_supabase"."mail_accounts" to authenticated;
grant all on "better_supabase"."mail_accounts" to service_role;
create table if not exists "better_supabase"."mail_threads" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."mail_accounts" ("id") on delete cascade,
  "external_id" text not null,
  "subject" text,
  "snippet" text,
  "last_message_at" timestamptz,
  "message_count" integer not null default 0,
  "engagement_id" uuid references "better_supabase"."engagements" ("id") on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("account_id", "external_id")
);
create index if not exists mail_threads_tenant_recent_idx on "better_supabase"."mail_threads" ("tenant_id", "last_message_at" desc);
create index if not exists mail_threads_engagement_idx on "better_supabase"."mail_threads" ("engagement_id") where "engagement_id" is not null;
alter table "better_supabase"."mail_threads" enable row level security;
revoke all on "better_supabase"."mail_threads" from anon, authenticated;
grant select on "better_supabase"."mail_threads" to authenticated;
grant all on "better_supabase"."mail_threads" to service_role;
create table if not exists "better_supabase"."mail_messages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."mail_accounts" ("id") on delete cascade,
  "thread_id" uuid not null references "better_supabase"."mail_threads" ("id") on delete cascade,
  "external_id" text not null,
  "rfc_message_id" text,
  "direction" text not null check ("direction" in ('inbound', 'outbound')),
  "from_address" text,
  "from_name" text,
  "to_addresses" text[] not null default '{}',
  "cc_addresses" text[] not null default '{}',
  "subject" text,
  "snippet" text,
  "body_text" text,
  "body_html" text,
  "sent_at" timestamptz not null,
  "template_version_id" uuid,
  "tracking_hash" text check ("tracking_hash" ~ '^[0-9a-f]{64}$'),
  "opened_at" timestamptz,
  "open_count" integer not null default 0,
  "clicked_at" timestamptz,
  "click_count" integer not null default 0,
  "created_at" timestamptz not null default now(),
  unique ("account_id", "external_id")
);
create index if not exists mail_messages_thread_idx on "better_supabase"."mail_messages" ("thread_id", "sent_at");
create index if not exists mail_messages_rfc_idx on "better_supabase"."mail_messages" ("account_id", "rfc_message_id") where "rfc_message_id" is not null;
create unique index if not exists mail_messages_tracking_idx on "better_supabase"."mail_messages" ("tracking_hash") where "tracking_hash" is not null;
create index if not exists mail_messages_template_idx on "better_supabase"."mail_messages" ("tenant_id", "template_version_id") where "template_version_id" is not null;
alter table "better_supabase"."mail_messages" enable row level security;
revoke all on "better_supabase"."mail_messages" from anon, authenticated;
grant select on "better_supabase"."mail_messages" to authenticated;
grant all on "better_supabase"."mail_messages" to service_role;
create table if not exists "better_supabase"."mail_tracked_links" (
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."mail_messages" ("id") on delete cascade,
  "position" integer not null check ("position" >= 0),
  "url" text not null check ("url" ~* '^https?://' and length("url") <= 2048),
  "click_count" integer not null default 0,
  "created_at" timestamptz not null default now(),
  primary key ("message_id", "position")
);
alter table "better_supabase"."mail_tracked_links" enable row level security;
revoke all on "better_supabase"."mail_tracked_links" from anon, authenticated;
grant select on "better_supabase"."mail_tracked_links" to authenticated;
grant all on "better_supabase"."mail_tracked_links" to service_role;
create table if not exists "better_supabase"."mail_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."mail_messages" ("id") on delete cascade,
  "kind" text not null check ("kind" in ('open', 'click')),
  "position" integer,
  "user_agent" text check (length("user_agent") <= 300),
  "occurred_at" timestamptz not null default now()
);
create index if not exists mail_tracking_events_message_idx on "better_supabase"."mail_tracking_events" ("message_id", "occurred_at");
alter table "better_supabase"."mail_tracking_events" enable row level security;
revoke all on "better_supabase"."mail_tracking_events" from anon, authenticated;
grant select on "better_supabase"."mail_tracking_events" to authenticated;
grant all on "better_supabase"."mail_tracking_events" to service_role;
create table if not exists "better_supabase"."mail_thread_subjects" (
  "tenant_id" uuid not null,
  "thread_id" uuid not null references "better_supabase"."mail_threads" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "source" text not null default 'match' check ("source" in ('match', 'manual')),
  "created_at" timestamptz not null default now(),
  primary key ("thread_id", "subject_type", "subject_id")
);
create index if not exists mail_thread_subjects_subject_idx on "better_supabase"."mail_thread_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."mail_thread_subjects" enable row level security;
revoke all on "better_supabase"."mail_thread_subjects" from anon, authenticated;
grant select on "better_supabase"."mail_thread_subjects" to authenticated;
grant all on "better_supabase"."mail_thread_subjects" to service_role;

-- Whether the caller may read a thread: its mailbox is theirs, or the mailbox
-- shares with records and the caller can read one of the thread's records.
create or replace function "better_supabase"."mail_thread_visible"(thread uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."mail_threads" x
    join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
    where x."id" = $1
      and (k."user_id" = auth.uid() or (
        k."share" = 'records'
        and coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.read'), false)
        and exists (
          select 1 from "better_supabase"."mail_thread_subjects" s
          where s."thread_id" = x."id"
            and "better_supabase"."can_subject"(s."subject_type", s."subject_id", 'read')
        )
      ))
  )
$$;
revoke execute on function "better_supabase"."mail_thread_visible"(uuid) from public, anon;
grant execute on function "better_supabase"."mail_thread_visible"(uuid) to authenticated, service_role;

drop policy if exists mail_accounts_read on "better_supabase"."mail_accounts";
create policy mail_accounts_read on "better_supabase"."mail_accounts" for select to authenticated
using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('mail.manage')));
drop policy if exists mail_threads_read on "better_supabase"."mail_threads";
create policy mail_threads_read on "better_supabase"."mail_threads" for select to authenticated
using ("better_supabase"."mail_thread_visible"("id"));
drop policy if exists mail_messages_read on "better_supabase"."mail_messages";
create policy mail_messages_read on "better_supabase"."mail_messages" for select to authenticated
using ("better_supabase"."mail_thread_visible"("thread_id"));
drop policy if exists mail_thread_subjects_read on "better_supabase"."mail_thread_subjects";
create policy mail_thread_subjects_read on "better_supabase"."mail_thread_subjects" for select to authenticated
using ("better_supabase"."mail_thread_visible"("thread_id"));
drop policy if exists mail_tracked_links_read on "better_supabase"."mail_tracked_links";
create policy mail_tracked_links_read on "better_supabase"."mail_tracked_links" for select to authenticated
using (exists (select 1 from "better_supabase"."mail_messages" y where y."id" = "message_id" and "better_supabase"."mail_thread_visible"(y."thread_id")));
drop policy if exists mail_tracking_events_read on "better_supabase"."mail_tracking_events";
create policy mail_tracking_events_read on "better_supabase"."mail_tracking_events" for select to authenticated
using (exists (select 1 from "better_supabase"."mail_messages" y where y."id" = "message_id" and "better_supabase"."mail_thread_visible"(y."thread_id")));

-- Stores a message on its account: message is { externalId, threadId,
-- messageId, direction, from: { address, name }, to, cc, subject, snippet,
-- text, html, sentAt, templateVersionId, trackingHash }. Returns { id, threadId, created, direction }.
create or replace function "better_supabase"."store_mail_message"(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account record;
  v_external text := nullif(trim(store_mail_message.message ->> 'externalId'), '');
  v_thread_ref text := coalesce(nullif(trim(store_mail_message.message ->> 'threadId'), ''), nullif(trim(store_mail_message.message ->> 'externalId'), ''));
  v_rfc text := nullif(trim(store_mail_message.message ->> 'messageId'), '');
  v_from text := lower(coalesce(nullif(trim(store_mail_message.message -> 'from' ->> 'address'), ''), case when jsonb_typeof(store_mail_message.message -> 'from') = 'string' then nullif(trim(store_mail_message.message ->> 'from'), '') end));
  v_direction text := nullif(trim(store_mail_message.message ->> 'direction'), '');
  v_template text := nullif(trim(store_mail_message.message ->> 'templateVersionId'), '');
  v_hash text := lower(nullif(trim(store_mail_message.message ->> 'trackingHash'), ''));
  v_sent timestamptz;
  v_thread uuid;
  v_id uuid;
begin
  select k."id" as id, k."tenant_id" as tenant, k."address" as address into v_account
  from "better_supabase"."mail_accounts" k where k."id" = store_mail_message.account;
  if jsonb_typeof(store_mail_message.message) <> 'object' or v_external is null or nullif(trim(store_mail_message.message ->> 'sentAt'), '') is null then
    raise exception 'a message needs an externalId and a sentAt' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if v_template is not null and v_template !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'templateVersionId is a uuid' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  v_sent := (nullif(trim(store_mail_message.message ->> 'sentAt'), ''))::timestamptz;
  v_direction := coalesce(v_direction, case when v_from = v_account.address then 'outbound' else 'inbound' end);
  if v_direction not in ('inbound', 'outbound') then
    raise exception 'direction is inbound or outbound' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  insert into "better_supabase"."mail_threads" ("tenant_id", "account_id", "external_id")
  values (v_account.tenant, v_account.id, v_thread_ref)
  on conflict ("account_id", "external_id") do update set "updated_at" = now()
  returning "id" into v_thread;
  select y."id" into v_id from "better_supabase"."mail_messages" y
  where y."account_id" = v_account.id
    and (y."external_id" = v_external or (v_rfc is not null and y."rfc_message_id" = v_rfc))
  order by y."external_id" = v_external desc
  limit 1;
  if v_id is not null then
    update "better_supabase"."mail_messages" y set "external_id" = v_external, "rfc_message_id" = coalesce(v_rfc, y."rfc_message_id")
    where y."id" = v_id
      and not exists (select 1 from "better_supabase"."mail_messages" z where z."account_id" = v_account.id and z."external_id" = v_external and z."id" <> v_id);
    return jsonb_build_object('id', v_id, 'threadId', (select y."thread_id" from "better_supabase"."mail_messages" y where y."id" = v_id), 'created', false, 'direction', v_direction);
  end if;
  insert into "better_supabase"."mail_messages" ("tenant_id", "account_id", "thread_id", "external_id", "rfc_message_id", "direction",
    "from_address", "from_name", "to_addresses", "cc_addresses", "subject", "snippet", "body_text", "body_html", "sent_at",
    "template_version_id", "tracking_hash")
  values (v_account.tenant, v_account.id, v_thread, v_external, v_rfc, v_direction,
    v_from, nullif(trim(store_mail_message.message -> 'from' ->> 'name'), ''), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'to') = 'array' then store_mail_message.message -> 'to' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'cc') = 'array' then store_mail_message.message -> 'cc' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'),
    nullif(trim(store_mail_message.message ->> 'subject'), ''), left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500), store_mail_message.message ->> 'text', store_mail_message.message ->> 'html', v_sent,
    v_template::uuid, case when v_direction = 'outbound' then v_hash end)
  returning "id" into v_id;
  update "better_supabase"."mail_threads" x set
    "subject" = coalesce(x."subject", nullif(trim(store_mail_message.message ->> 'subject'), '')),
    "snippet" = case when x."last_message_at" is null or v_sent >= x."last_message_at" then left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500) else x."snippet" end,
    "last_message_at" = greatest(x."last_message_at", v_sent),
    "message_count" = x."message_count" + 1,
    "updated_at" = now()
  where x."id" = v_thread;
  return jsonb_build_object('id', v_id, 'threadId', v_thread, 'created', true, 'direction', v_direction);
end;
$$;
revoke execute on function "better_supabase"."store_mail_message"(uuid, jsonb) from public, anon, authenticated;

-- Links a thread to the parties its addresses name; manual links stay.
create or replace function "better_supabase"."match_mail_thread"(thread uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_thread uuid := match_mail_thread.thread;
  v_tenant uuid;
  v_own text;
  v_addresses text[];
begin
  select x."tenant_id", k."address" into v_tenant, v_own
  from "better_supabase"."mail_threads" x join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = v_thread;
  select coalesce(array_agg(distinct v.address), '{}') into v_addresses
  from "better_supabase"."mail_messages" y
  cross join lateral unnest(array[y."from_address"] || y."to_addresses" || y."cc_addresses") as v(address)
  where y."thread_id" = v_thread and v.address is not null and v.address <> v_own;
  insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id")
  select v_tenant, v_thread, 'person', p."id"::text
  from "better_supabase"."people" p
  where p."tenant_id" = v_tenant and p."archived_at" is null
    and lower(p."email") = any (v_addresses)
  on conflict do nothing;
  insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id")
  select v_tenant, v_thread, 'company', cp."company_id"::text
  from "better_supabase"."company_people" cp
  join "better_supabase"."people" p on p."id" = cp."person_id"
  where p."tenant_id" = v_tenant and p."archived_at" is null
    and lower(p."email") = any (v_addresses)
  on conflict do nothing;
  insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id")
  select v_tenant, v_thread, 'company', c."id"::text
  from "better_supabase"."companies" c
  where c."tenant_id" = v_tenant and c."archived_at" is null
    and c."domain" is not null
    and lower(c."domain") = any (select split_part(x, '@', 2) from unnest(v_addresses) x)
  on conflict do nothing;
end;
$$;
revoke execute on function "better_supabase"."match_mail_thread"(uuid) from public, anon, authenticated;

-- Logs or updates the thread's engagement; private mailboxes log none.
create or replace function "better_supabase"."log_mail_thread"(thread uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_subjects jsonb;
  v_result jsonb;
  v_claims text;
begin
  select x."id" as id, x."tenant_id" as tenant, x."subject" as subject, x."snippet" as snippet,
    x."last_message_at" as at, k."user_id" as owner, k."share" as share
  into v_row
  from "better_supabase"."mail_threads" x join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = log_mail_thread.thread;
  if v_row.id is null or v_row.share <> 'records' then
    return;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id"), '[]'::jsonb)
  into v_subjects
  from "better_supabase"."mail_thread_subjects" s where s."thread_id" = v_row.id;
  if jsonb_array_length(v_subjects) = 0 then
    return;
  end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_result := "better_supabase"."log_engagement"(v_row.tenant, jsonb_build_object(
    'type', 'email',
    'title', coalesce(nullif(trim(v_row.subject), ''), '(no subject)'),
    'body', v_row.snippet,
    'ownerId', v_row.owner,
    'doneAt', v_row.at,
    'externalRef', 'mail:' || v_row.id::text
  ), v_subjects);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  update "better_supabase"."mail_threads" x set "engagement_id" = (v_result ->> 'id')::uuid
  where x."id" = v_row.id;
end;
$$;
revoke execute on function "better_supabase"."log_mail_thread"(uuid) from public, anon, authenticated;

-- Connects the caller's mailbox: credential_ref names the OAuth grant the
-- app stored for them. share is records (members who can read a linked
-- record see its threads) or private. Connecting again updates the grant.
create or replace function "better_supabase"."connect_mail_account"(tenant uuid, provider text, address text, credential_ref jsonb, share text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."mail_accounts";
  v_address text := lower(trim(connect_mail_account.address));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', connect_mail_account.tenant, 'mail.connect'), false) then
    raise exception 'not allowed to connect a mailbox' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if connect_mail_account.provider is null or connect_mail_account.provider !~ '^[a-z][a-z0-9-]{0,39}$' then
    raise exception 'provider is a lowercase name' using errcode = '22023', hint = 'MAIL_PROVIDER_INVALID';
  end if;
  if v_address is null or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception 'address is an email address' using errcode = '22023', hint = 'MAIL_ADDRESS_INVALID';
  end if;
  if coalesce(connect_mail_account.share, 'records') not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  if jsonb_typeof(connect_mail_account.credential_ref) is distinct from 'object' then
    raise exception 'credential_ref is a credential reference' using errcode = '22023', hint = 'MAIL_CREDENTIAL_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and connect_mail_account.credential_ref is not null and jsonb_typeof(connect_mail_account.credential_ref) <> 'null'
    and (jsonb_typeof(connect_mail_account.credential_ref -> 'tenant') is distinct from 'string' or (connect_mail_account.credential_ref ->> 'tenant') is distinct from (connect_mail_account.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', connect_mail_account.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  insert into "better_supabase"."mail_accounts" as x ("tenant_id", "user_id", "provider", "address", "credential_ref", "share")
  values (connect_mail_account.tenant, auth.uid(), connect_mail_account.provider, v_address, connect_mail_account.credential_ref, coalesce(connect_mail_account.share, 'records'))
  on conflict ("tenant_id", "user_id", "address") do update set
    "provider" = excluded."provider",
    "credential_ref" = excluded."credential_ref",
    "share" = excluded."share",
    "status" = 'active',
    "sync_cursor" = case when x."provider" = excluded."provider" then x."sync_cursor" end,
    "last_error" = null,
    "updated_at" = now()
  returning * into v_row;
  perform "better_supabase".emit_event('mail_account.connected', jsonb_build_object('organizationId', v_row."tenant_id", 'accountId', v_row."id", 'userId', v_row."user_id", 'provider', v_row."provider", 'address', v_row."address"), 'mail-accounts/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/mail-sync');
  perform better_supabase.audit_event(
    event_type => 'mail_account.connected',
    category => 'integration',
    target_type => 'mail_account',
    record_id => v_row."id"::text,
    target_label => v_row."address",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'accountId', v_row."id", 'userId', v_row."user_id", 'provider', v_row."provider", 'address', v_row."address")
  );
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."connect_mail_account"(uuid, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."connect_mail_account"(uuid, text, text, jsonb, text) to authenticated, service_role;

-- Changes who sees a mailbox's threads (share) and pauses or resumes its
-- sync; null leaves a setting as it is. Only the mailbox's member may.
create or replace function "better_supabase"."update_mail_account"(account uuid, share text, paused boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if update_mail_account.share is not null and update_mail_account.share not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  update "better_supabase"."mail_accounts" x set
    "share" = coalesce(update_mail_account.share, x."share"),
    "status" = case
      when update_mail_account.paused then 'paused'
      when update_mail_account.paused = false and x."status" = 'paused' then 'active'
      else x."status" end,
    "updated_at" = now()
  where x."id" = update_mail_account.account and x."user_id" = auth.uid() and x."status" <> 'disconnected'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."update_mail_account"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."update_mail_account"(uuid, text, boolean) to authenticated, service_role;

-- Stops syncing a mailbox. Its member or a member with mail.manage may.
-- purge deletes the mailbox with its threads and messages.
create or replace function "better_supabase"."disconnect_mail_account"(account uuid, purge boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."mail_accounts" x
  where x."id" = disconnect_mail_account.account
    and (x."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.manage'), false));
  if v_row."id" is null then
    return false;
  end if;
  if coalesce(disconnect_mail_account.purge, false) then
    delete from "better_supabase"."mail_accounts" x where x."id" = v_row."id";
  else
    update "better_supabase"."mail_accounts" x set "status" = 'disconnected', "sync_cursor" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
  perform "better_supabase".emit_event('mail_account.disconnected', jsonb_build_object('organizationId', v_row."tenant_id", 'accountId', v_row."id", 'userId', v_row."user_id", 'provider', v_row."provider", 'address', v_row."address"), 'mail-accounts/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/mail-sync');
  perform better_supabase.audit_event(
    event_type => 'mail_account.disconnected',
    category => 'integration',
    target_type => 'mail_account',
    record_id => v_row."id"::text,
    target_label => v_row."address",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'accountId', v_row."id", 'userId', v_row."user_id", 'provider', v_row."provider", 'address', v_row."address")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."disconnect_mail_account"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."disconnect_mail_account"(uuid, boolean) to authenticated, service_role;

-- The caller's mailboxes in a tenant; with mail.manage, every member's.
create or replace function "better_supabase"."mail_accounts_of"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at", x."id"), '[]'::jsonb)
  from "better_supabase"."mail_accounts" x
  where x."tenant_id" = mail_accounts_of.tenant
$$;
revoke execute on function "better_supabase"."mail_accounts_of"(uuid) from public, anon;
grant execute on function "better_supabase"."mail_accounts_of"(uuid) to authenticated, service_role;

-- One mailbox the caller can see, or null.
create or replace function "better_supabase"."get_mail_account"(account uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) from "better_supabase"."mail_accounts" x where x."id" = get_mail_account.account
$$;
revoke execute on function "better_supabase"."get_mail_account"(uuid) from public, anon;
grant execute on function "better_supabase"."get_mail_account"(uuid) to authenticated, service_role;

-- For the sync job: active mailboxes not synced within stale_after, the
-- longest waiting first, with their grant and cursor.
create or replace function "better_supabase"."due_mail_accounts"(max_count integer, stale_after interval)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(p) order by p."last_synced_at" nulls first, p."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."status" = 'active'
        and (x."last_synced_at" is null or x."last_synced_at" < now() - coalesce(due_mail_accounts.stale_after, interval '5 minutes'))
      order by x."last_synced_at" nulls first, x."id"
      limit least(greatest(coalesce(due_mail_accounts.max_count, 25), 1), 500)
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."due_mail_accounts"(integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."due_mail_accounts"(integer, interval) to service_role;

-- For the sync job: marks a mailbox active, paused or failed with an error
-- (a failed one waits for its member to connect it again).
create or replace function "better_supabase"."set_mail_account_status"(account uuid, status text, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if set_mail_account_status.status not in ('active', 'paused', 'error') then
    raise exception 'status is active, paused or error' using errcode = '22023', hint = 'MAIL_STATUS_INVALID';
  end if;
  update "better_supabase"."mail_accounts" x set
    "status" = set_mail_account_status.status,
    "last_error" = left(set_mail_account_status.error, 1000),
    "last_synced_at" = now(),
    "updated_at" = now()
  where x."id" = set_mail_account_status.account and x."status" <> 'disconnected';
  return found;
end;
$$;
revoke execute on function "better_supabase"."set_mail_account_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_mail_account_status"(uuid, text, text) to service_role;

-- For the sync job: stores up to 500 provider messages on a mailbox,
-- links their threads to records and logs them, then saves the cursor the
-- next sync starts from. Returns { stored, threads }.
create or replace function "better_supabase"."ingest_mail"(account uuid, messages jsonb, next_cursor text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_item jsonb;
  v_stored jsonb;
  v_new jsonb := '[]'::jsonb;
  v_threads uuid[] := '{}';
  v_thread uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "better_supabase"."mail_accounts" k where k."id" = ingest_mail.account and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such connected mailbox' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(ingest_mail.messages, '[]')) <> 'array' then
    raise exception 'messages is a list' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if jsonb_array_length(coalesce(ingest_mail.messages, '[]')) > 500 then
    raise exception 'at most 500 messages per call' using errcode = '22023', hint = 'MAIL_BATCH_TOO_LARGE';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(ingest_mail.messages, '[]')) loop
    v_stored := "better_supabase"."store_mail_message"(v_account.id, v_item);
    if not ((v_stored ->> 'threadId')::uuid = any (v_threads)) then
      v_threads := v_threads || (v_stored ->> 'threadId')::uuid;
    end if;
    if (v_stored ->> 'created')::boolean then
      v_new := v_new || jsonb_build_array(v_stored || jsonb_build_object('fromAddress', lower(coalesce(v_item -> 'from' ->> 'address', v_item ->> 'from'))));
    end if;
  end loop;
  foreach v_thread in array v_threads loop
    perform "better_supabase"."match_mail_thread"(v_thread);
    perform "better_supabase"."log_mail_thread"(v_thread);
  end loop;
  for v_stored in select value from jsonb_array_elements(v_new) loop
    if v_stored ->> 'direction' = 'outbound' then
      perform "better_supabase".emit_event('mail_message.sent', jsonb_build_object('organizationId', v_account.tenant, 'accountId', v_account.id, 'userId', v_account.owner, 'threadId', v_stored ->> 'threadId', 'messageId', v_stored ->> 'id', 'direction', v_stored ->> 'direction', 'fromAddress', v_stored ->> 'fromAddress', 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = (v_stored ->> 'threadId')::uuid), '[]'::jsonb)), 'mail-messages/' || (v_stored ->> 'id'), (v_account.tenant::text)::text, 'mail_message:' || (v_stored ->> 'id'), 'better-supabase/mail-sync');
    else
      perform "better_supabase".emit_event('mail_message.received', jsonb_build_object('organizationId', v_account.tenant, 'accountId', v_account.id, 'userId', v_account.owner, 'threadId', v_stored ->> 'threadId', 'messageId', v_stored ->> 'id', 'direction', v_stored ->> 'direction', 'fromAddress', v_stored ->> 'fromAddress', 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = (v_stored ->> 'threadId')::uuid), '[]'::jsonb)), 'mail-messages/' || (v_stored ->> 'id'), (v_account.tenant::text)::text, 'mail_message:' || (v_stored ->> 'id'), 'better-supabase/mail-sync');
    end if;
  end loop;
  update "better_supabase"."mail_accounts" x set
    "sync_cursor" = coalesce(ingest_mail.next_cursor, x."sync_cursor"),
    "last_synced_at" = now(),
    "status" = case when x."status" = 'error' then 'active' else x."status" end,
    "last_error" = null,
    "updated_at" = now()
  where x."id" = v_account.id;
  return jsonb_build_object('stored', jsonb_array_length(v_new), 'threads', coalesce(array_length(v_threads, 1), 0));
end;
$$;
revoke execute on function "better_supabase"."ingest_mail"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_mail"(uuid, jsonb, text) to service_role;

-- Records a message the caller sent from their mailbox through the provider
-- (the block's send does both), so it shows on the thread before the next
-- sync. The service role records for any mailbox, as a server-side sender
-- such as the sequences runner does. Returns the stored message.
create or replace function "better_supabase"."record_sent_mail"(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_stored jsonb;
  v_thread uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "better_supabase"."mail_accounts" k
  where k."id" = record_sent_mail.account and (k."user_id" = auth.uid() or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_account.tenant, 'mail.send'), false) then
    raise exception 'not allowed to send mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  v_stored := "better_supabase"."store_mail_message"(v_account.id, coalesce(record_sent_mail.message, '{}'::jsonb) || '{"direction": "outbound"}'::jsonb);
  v_thread := (v_stored ->> 'threadId')::uuid;
  perform "better_supabase"."match_mail_thread"(v_thread);
  perform "better_supabase"."log_mail_thread"(v_thread);
  if (v_stored ->> 'created')::boolean then
    if jsonb_typeof(record_sent_mail.message -> 'trackedLinks') = 'array' then
      insert into "better_supabase"."mail_tracked_links" ("tenant_id", "message_id", "position", "url")
      select v_account.tenant, (v_stored ->> 'id')::uuid, (u.ord - 1)::integer, u.value #>> '{}'
      from jsonb_array_elements(record_sent_mail.message -> 'trackedLinks') with ordinality u (value, ord);
    end if;
    v_stored := v_stored || jsonb_build_object('fromAddress', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = v_account.id));
    perform "better_supabase".emit_event('mail_message.sent', jsonb_build_object('organizationId', v_account.tenant, 'accountId', v_account.id, 'userId', v_account.owner, 'threadId', v_stored ->> 'threadId', 'messageId', v_stored ->> 'id', 'direction', v_stored ->> 'direction', 'fromAddress', v_stored ->> 'fromAddress', 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = (v_stored ->> 'threadId')::uuid), '[]'::jsonb)), 'mail-messages/' || (v_stored ->> 'id'), (v_account.tenant::text)::text, 'mail_message:' || (v_stored ->> 'id'), 'better-supabase/mail-sync');
  end if;
  return (select to_jsonb(y) from "better_supabase"."mail_messages" y where y."id" = (v_stored ->> 'id')::uuid);
end;
$$;
revoke execute on function "better_supabase"."record_sent_mail"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."record_sent_mail"(uuid, jsonb) to authenticated, service_role;

-- Links a thread of the caller's mailbox to records ([{ type, id }]) by
-- hand, for senders no person matches, and logs it on them.
create or replace function "better_supabase"."link_mail_thread"(thread uuid, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_thread uuid := link_mail_thread.thread;
  v_tenant uuid;
  v_item jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant
  from "better_supabase"."mail_threads" x join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = v_thread and k."user_id" = auth.uid();
  if v_tenant is null then
    raise exception 'no such thread in your mailbox' using errcode = 'P0002', hint = 'MAIL_THREAD_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(link_mail_thread.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'MAIL_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(link_mail_thread.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'MAIL_SUBJECT_FORBIDDEN';
    end if;
    insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id", "source")
    values (v_tenant, v_thread, v_item ->> 'type', v_item ->> 'id', 'manual')
    on conflict ("thread_id", "subject_type", "subject_id") do update set "source" = 'manual';
  end loop;
  perform "better_supabase"."log_mail_thread"(v_thread);
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) from "better_supabase"."mail_threads" x where x."id" = v_thread);
end;
$$;
revoke execute on function "better_supabase"."link_mail_thread"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."link_mail_thread"(uuid, jsonb) to authenticated, service_role;

-- Removes a record from a thread of the caller's mailbox.
create or replace function "better_supabase"."unlink_mail_thread"(thread uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."mail_thread_subjects" s
  using "better_supabase"."mail_threads" x, "better_supabase"."mail_accounts" k
  where s."thread_id" = unlink_mail_thread.thread
    and s."subject_type" = unlink_mail_thread.subject_type and s."subject_id" = unlink_mail_thread.subject_id
    and x."id" = s."thread_id" and k."id" = x."account_id" and k."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."unlink_mail_thread"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."unlink_mail_thread"(uuid, text, text) to authenticated, service_role;

-- A record's threads the caller can see, the latest message first. before
-- continues after the last thread of the previous page.
create or replace function "better_supabase"."mail_threads_of"(subject_type text, subject_id text, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "better_supabase"."mail_threads" x
    join "better_supabase"."mail_thread_subjects" s on s."thread_id" = x."id"
    where s."subject_type" = mail_threads_of.subject_type and s."subject_id" = mail_threads_of.subject_id
      and (mail_threads_of.before is null or x."last_message_at" < mail_threads_of.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(mail_threads_of.page_size, 25), 1), 100)
  ) p
$$;
revoke execute on function "better_supabase"."mail_threads_of"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."mail_threads_of"(text, text, timestamptz, integer) to authenticated, service_role;

-- The threads the caller can see in a tenant, or in one mailbox, the
-- latest message first.
create or replace function "better_supabase"."list_mail_threads"(tenant uuid, account uuid, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "better_supabase"."mail_threads" x
    where x."tenant_id" = list_mail_threads.tenant
      and (list_mail_threads.account is null or x."account_id" = list_mail_threads.account)
      and (list_mail_threads.before is null or x."last_message_at" < list_mail_threads.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(list_mail_threads.page_size, 25), 1), 100)
  ) p
$$;
revoke execute on function "better_supabase"."list_mail_threads"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_mail_threads"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- A thread with its messages, oldest first; null when the caller can't see it.
create or replace function "better_supabase"."get_mail_thread"(thread uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('messages', coalesce((
    select jsonb_agg(to_jsonb(y) order by y."sent_at", y."id")
    from "better_supabase"."mail_messages" y where y."thread_id" = x."id"
  ), '[]'::jsonb))
  from "better_supabase"."mail_threads" x
  where x."id" = get_mail_thread.thread
$$;
revoke execute on function "better_supabase"."get_mail_thread"(uuid) from public, anon;
grant execute on function "better_supabase"."get_mail_thread"(uuid) to authenticated, service_role;

-- For the tracking route: records an open of the tracked message whose token
-- hashes to hash, or a click on its link at index link. Returns { messageId,
-- url } (url, the stored link, for a click), or null for an unknown token.
create or replace function "better_supabase"."track_mail"(hash text, kind text, link integer, user_agent text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message record;
  v_url text;
  v_event uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role records tracking' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if track_mail.kind is null or track_mail.kind not in ('open', 'click') then
    raise exception 'kind is open or click' using errcode = '22023', hint = 'MAIL_TRACKING_INVALID';
  end if;
  select y."id" as id, y."tenant_id" as tenant, y."account_id" as account, y."thread_id" as thread,
    y."template_version_id" as template, y."opened_at" as opened, x."user_id" as owner
  into v_message
  from "better_supabase"."mail_messages" y join "better_supabase"."mail_accounts" x on x."id" = y."account_id"
  where y."tracking_hash" = lower(track_mail.hash) and y."direction" = 'outbound';
  if v_message.id is null then
    return null;
  end if;
  if track_mail.kind = 'click' then
    update "better_supabase"."mail_tracked_links" u set "click_count" = u."click_count" + 1
    where u."message_id" = v_message.id and u."position" = track_mail.link
    returning u."url" into v_url;
    if v_url is null then
      return null;
    end if;
  end if;
  insert into "better_supabase"."mail_tracking_events" ("tenant_id", "message_id", "kind", "position", "user_agent")
  values (v_message.tenant, v_message.id, track_mail.kind, case when track_mail.kind = 'click' then track_mail.link end, left(track_mail.user_agent, 300))
  returning "id" into v_event;
  update "better_supabase"."mail_messages" y set
    "opened_at" = coalesce(y."opened_at", now()),
    "open_count" = y."open_count" + case when track_mail.kind = 'open' then 1 else 0 end,
    "clicked_at" = case when track_mail.kind = 'click' then coalesce(y."clicked_at", now()) else y."clicked_at" end,
    "click_count" = y."click_count" + case when track_mail.kind = 'click' then 1 else 0 end
  where y."id" = v_message.id;
  if track_mail.kind = 'click' then
    perform "better_supabase".emit_event('mail_message.clicked', jsonb_build_object('organizationId', v_message.tenant, 'accountId', v_message.account, 'userId', v_message.owner, 'threadId', v_message.thread, 'messageId', v_message.id, 'templateVersionId', v_message.template, 'url', v_url, 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = v_message.thread), '[]'::jsonb)), 'mail-messages/' || v_message.id, (v_message.tenant::text)::text, 'mail_message_clicked:' || v_event, 'better-supabase/mail-sync');
  elsif v_message.opened is null then
    perform "better_supabase".emit_event('mail_message.opened', jsonb_build_object('organizationId', v_message.tenant, 'accountId', v_message.account, 'userId', v_message.owner, 'threadId', v_message.thread, 'messageId', v_message.id, 'templateVersionId', v_message.template, 'url', null::text, 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = v_message.thread), '[]'::jsonb)), 'mail-messages/' || v_message.id, (v_message.tenant::text)::text, 'mail_message_opened:' || v_message.id, 'better-supabase/mail-sync');
  end if;
  return jsonb_build_object('messageId', v_message.id, 'url', v_url);
end;
$$;
revoke execute on function "better_supabase"."track_mail"(text, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."track_mail"(text, text, integer, text) to service_role;

-- Per template version, how many messages members sent from shared
-- mailboxes since a time, and how many were opened, clicked and replied to.
create or replace function "better_supabase"."mail_template_stats"(tenant uuid, since timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.can('tenant', mail_template_stats.tenant, 'mail.read'), false) then
    raise exception 'not allowed to read mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('templateVersionId', p.template, 'sent', p.sent, 'opened', p.opened, 'clicked', p.clicked, 'replied', p.replied) order by p.sent desc, p.template), '[]'::jsonb)
    from (
      select y."template_version_id" as template, count(*) as sent, count(y."opened_at") as opened, count(y."clicked_at") as clicked,
        count(*) filter (where exists (
          select 1 from "better_supabase"."mail_messages" r
          where r."thread_id" = y."thread_id" and r."direction" = 'inbound' and r."sent_at" > y."sent_at"
        )) as replied
      from "better_supabase"."mail_messages" y join "better_supabase"."mail_accounts" x on x."id" = y."account_id"
      where y."tenant_id" = mail_template_stats.tenant and y."direction" = 'outbound'
        and y."template_version_id" is not null
        and (x."share" = 'records' or x."user_id" = auth.uid())
        and (mail_template_stats.since is null or y."sent_at" >= mail_template_stats.since)
      group by y."template_version_id"
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."mail_template_stats"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."mail_template_stats"(uuid, timestamptz) to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_132_mail_sync.sql
-- better-supabase module: mail-sync
-- @bsb-block-data mail-sync
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_132_mail_sync.sql
-- better-supabase module: mail-sync
-- @bsb-block mail-sync@1 managed
-- Gmail, Outlook and other mailboxes synced per member through their own OAuth grant: threads and messages linked to the people and companies they involve, logged as email engagements, and a record of the mail members send, with opens and clicks per message and per template version.
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
-- Gmail, Outlook and other mailboxes synced per member: threads and messages
-- linked to the people and companies they involve, logged as engagements.
create table if not exists "app_private"."mail_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9-]{0,39}$'),
  "address" text not null check ("address" = lower("address") and "address" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object'),
  "share" text not null default 'records' check ("share" in ('records', 'private')),
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'error', 'disconnected')),
  "sync_cursor" text,
  "last_synced_at" timestamptz,
  "last_error" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "address")
);
create index if not exists mail_accounts_user_idx on "app_private"."mail_accounts" ("user_id");
create index if not exists mail_accounts_due_idx on "app_private"."mail_accounts" ("last_synced_at" nulls first) where "status" = 'active';
alter table "app_private"."mail_accounts" enable row level security;
revoke all on "app_private"."mail_accounts" from anon, authenticated;
grant select on "app_private"."mail_accounts" to authenticated;
grant all on "app_private"."mail_accounts" to service_role;
create table if not exists "app_private"."mail_threads" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "app_private"."mail_accounts" ("id") on delete cascade,
  "external_id" text not null,
  "subject" text,
  "snippet" text,
  "last_message_at" timestamptz,
  "message_count" integer not null default 0,
  "engagement_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("account_id", "external_id")
);
create index if not exists mail_threads_tenant_recent_idx on "app_private"."mail_threads" ("tenant_id", "last_message_at" desc);
create index if not exists mail_threads_engagement_idx on "app_private"."mail_threads" ("engagement_id") where "engagement_id" is not null;
alter table "app_private"."mail_threads" enable row level security;
revoke all on "app_private"."mail_threads" from anon, authenticated;
grant select on "app_private"."mail_threads" to authenticated;
grant all on "app_private"."mail_threads" to service_role;
create table if not exists "app_private"."mail_messages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "app_private"."mail_accounts" ("id") on delete cascade,
  "thread_id" uuid not null references "app_private"."mail_threads" ("id") on delete cascade,
  "external_id" text not null,
  "rfc_message_id" text,
  "direction" text not null check ("direction" in ('inbound', 'outbound')),
  "from_address" text,
  "from_name" text,
  "to_addresses" text[] not null default '{}',
  "cc_addresses" text[] not null default '{}',
  "subject" text,
  "snippet" text,
  "body_text" text,
  "body_html" text,
  "sent_at" timestamptz not null,
  "template_version_id" uuid,
  "tracking_hash" text check ("tracking_hash" ~ '^[0-9a-f]{64}$'),
  "opened_at" timestamptz,
  "open_count" integer not null default 0,
  "clicked_at" timestamptz,
  "click_count" integer not null default 0,
  "created_at" timestamptz not null default now(),
  unique ("account_id", "external_id")
);
create index if not exists mail_messages_thread_idx on "app_private"."mail_messages" ("thread_id", "sent_at");
create index if not exists mail_messages_rfc_idx on "app_private"."mail_messages" ("account_id", "rfc_message_id") where "rfc_message_id" is not null;
create unique index if not exists mail_messages_tracking_idx on "app_private"."mail_messages" ("tracking_hash") where "tracking_hash" is not null;
create index if not exists mail_messages_template_idx on "app_private"."mail_messages" ("tenant_id", "template_version_id") where "template_version_id" is not null;
alter table "app_private"."mail_messages" enable row level security;
revoke all on "app_private"."mail_messages" from anon, authenticated;
grant select on "app_private"."mail_messages" to authenticated;
grant all on "app_private"."mail_messages" to service_role;
create table if not exists "app_private"."mail_tracked_links" (
  "tenant_id" uuid not null,
  "message_id" uuid not null references "app_private"."mail_messages" ("id") on delete cascade,
  "position" integer not null check ("position" >= 0),
  "url" text not null check ("url" ~* '^https?://' and length("url") <= 2048),
  "click_count" integer not null default 0,
  "created_at" timestamptz not null default now(),
  primary key ("message_id", "position")
);
alter table "app_private"."mail_tracked_links" enable row level security;
revoke all on "app_private"."mail_tracked_links" from anon, authenticated;
grant select on "app_private"."mail_tracked_links" to authenticated;
grant all on "app_private"."mail_tracked_links" to service_role;
create table if not exists "app_private"."mail_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "message_id" uuid not null references "app_private"."mail_messages" ("id") on delete cascade,
  "kind" text not null check ("kind" in ('open', 'click')),
  "position" integer,
  "user_agent" text check (length("user_agent") <= 300),
  "occurred_at" timestamptz not null default now()
);
create index if not exists mail_tracking_events_message_idx on "app_private"."mail_tracking_events" ("message_id", "occurred_at");
alter table "app_private"."mail_tracking_events" enable row level security;
revoke all on "app_private"."mail_tracking_events" from anon, authenticated;
grant select on "app_private"."mail_tracking_events" to authenticated;
grant all on "app_private"."mail_tracking_events" to service_role;
create table if not exists "app_private"."mail_thread_subjects" (
  "tenant_id" uuid not null,
  "thread_id" uuid not null references "app_private"."mail_threads" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "source" text not null default 'match' check ("source" in ('match', 'manual')),
  "created_at" timestamptz not null default now(),
  primary key ("thread_id", "subject_type", "subject_id")
);
create index if not exists mail_thread_subjects_subject_idx on "app_private"."mail_thread_subjects" ("subject_type", "subject_id");
alter table "app_private"."mail_thread_subjects" enable row level security;
revoke all on "app_private"."mail_thread_subjects" from anon, authenticated;
grant select on "app_private"."mail_thread_subjects" to authenticated;
grant all on "app_private"."mail_thread_subjects" to service_role;

-- Whether the caller may read a thread: its mailbox is theirs, or the mailbox
-- shares with records and the caller can read one of the thread's records.
create or replace function "app_private"."mail_thread_visible"(thread uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "app_private"."mail_threads" x
    join "app_private"."mail_accounts" k on k."id" = x."account_id"
    where x."id" = $1
      and (k."user_id" = auth.uid() or (
        k."share" = 'records'
        and coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.read'), false)
        and exists (
          select 1 from "app_private"."mail_thread_subjects" s
          where s."thread_id" = x."id"
            and "better_supabase"."can_subject"(s."subject_type", s."subject_id", 'read')
        )
      ))
  )
$$;
revoke execute on function "app_private"."mail_thread_visible"(uuid) from public, anon;
grant execute on function "app_private"."mail_thread_visible"(uuid) to authenticated, service_role;

drop policy if exists mail_accounts_read on "app_private"."mail_accounts";
create policy mail_accounts_read on "app_private"."mail_accounts" for select to authenticated
using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('mail.manage')));
drop policy if exists mail_threads_read on "app_private"."mail_threads";
create policy mail_threads_read on "app_private"."mail_threads" for select to authenticated
using ("app_private"."mail_thread_visible"("id"));
drop policy if exists mail_messages_read on "app_private"."mail_messages";
create policy mail_messages_read on "app_private"."mail_messages" for select to authenticated
using ("app_private"."mail_thread_visible"("thread_id"));
drop policy if exists mail_thread_subjects_read on "app_private"."mail_thread_subjects";
create policy mail_thread_subjects_read on "app_private"."mail_thread_subjects" for select to authenticated
using ("app_private"."mail_thread_visible"("thread_id"));
drop policy if exists mail_tracked_links_read on "app_private"."mail_tracked_links";
create policy mail_tracked_links_read on "app_private"."mail_tracked_links" for select to authenticated
using (exists (select 1 from "app_private"."mail_messages" y where y."id" = "message_id" and "app_private"."mail_thread_visible"(y."thread_id")));
drop policy if exists mail_tracking_events_read on "app_private"."mail_tracking_events";
create policy mail_tracking_events_read on "app_private"."mail_tracking_events" for select to authenticated
using (exists (select 1 from "app_private"."mail_messages" y where y."id" = "message_id" and "app_private"."mail_thread_visible"(y."thread_id")));

-- Stores a message on its account: message is { externalId, threadId,
-- messageId, direction, from: { address, name }, to, cc, subject, snippet,
-- text, html, sentAt, templateVersionId, trackingHash }. Returns { id, threadId, created, direction }.
create or replace function "app_private"."store_mail_message"(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account record;
  v_external text := nullif(trim(store_mail_message.message ->> 'externalId'), '');
  v_thread_ref text := coalesce(nullif(trim(store_mail_message.message ->> 'threadId'), ''), nullif(trim(store_mail_message.message ->> 'externalId'), ''));
  v_rfc text := nullif(trim(store_mail_message.message ->> 'messageId'), '');
  v_from text := lower(coalesce(nullif(trim(store_mail_message.message -> 'from' ->> 'address'), ''), case when jsonb_typeof(store_mail_message.message -> 'from') = 'string' then nullif(trim(store_mail_message.message ->> 'from'), '') end));
  v_direction text := nullif(trim(store_mail_message.message ->> 'direction'), '');
  v_template text := nullif(trim(store_mail_message.message ->> 'templateVersionId'), '');
  v_hash text := lower(nullif(trim(store_mail_message.message ->> 'trackingHash'), ''));
  v_sent timestamptz;
  v_thread uuid;
  v_id uuid;
begin
  select k."id" as id, k."tenant_id" as tenant, k."address" as address into v_account
  from "app_private"."mail_accounts" k where k."id" = store_mail_message.account;
  if jsonb_typeof(store_mail_message.message) <> 'object' or v_external is null or nullif(trim(store_mail_message.message ->> 'sentAt'), '') is null then
    raise exception 'a message needs an externalId and a sentAt' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if v_template is not null and v_template !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'templateVersionId is a uuid' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  v_sent := (nullif(trim(store_mail_message.message ->> 'sentAt'), ''))::timestamptz;
  v_direction := coalesce(v_direction, case when v_from = v_account.address then 'outbound' else 'inbound' end);
  if v_direction not in ('inbound', 'outbound') then
    raise exception 'direction is inbound or outbound' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  insert into "app_private"."mail_threads" ("tenant_id", "account_id", "external_id")
  values (v_account.tenant, v_account.id, v_thread_ref)
  on conflict ("account_id", "external_id") do update set "updated_at" = now()
  returning "id" into v_thread;
  select y."id" into v_id from "app_private"."mail_messages" y
  where y."account_id" = v_account.id
    and (y."external_id" = v_external or (v_rfc is not null and y."rfc_message_id" = v_rfc))
  order by y."external_id" = v_external desc
  limit 1;
  if v_id is not null then
    update "app_private"."mail_messages" y set "external_id" = v_external, "rfc_message_id" = coalesce(v_rfc, y."rfc_message_id")
    where y."id" = v_id
      and not exists (select 1 from "app_private"."mail_messages" z where z."account_id" = v_account.id and z."external_id" = v_external and z."id" <> v_id);
    return jsonb_build_object('id', v_id, 'threadId', (select y."thread_id" from "app_private"."mail_messages" y where y."id" = v_id), 'created', false, 'direction', v_direction);
  end if;
  insert into "app_private"."mail_messages" ("tenant_id", "account_id", "thread_id", "external_id", "rfc_message_id", "direction",
    "from_address", "from_name", "to_addresses", "cc_addresses", "subject", "snippet", "body_text", "body_html", "sent_at",
    "template_version_id", "tracking_hash")
  values (v_account.tenant, v_account.id, v_thread, v_external, v_rfc, v_direction,
    v_from, nullif(trim(store_mail_message.message -> 'from' ->> 'name'), ''), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'to') = 'array' then store_mail_message.message -> 'to' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'cc') = 'array' then store_mail_message.message -> 'cc' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'),
    nullif(trim(store_mail_message.message ->> 'subject'), ''), left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500), store_mail_message.message ->> 'text', store_mail_message.message ->> 'html', v_sent,
    v_template::uuid, case when v_direction = 'outbound' then v_hash end)
  returning "id" into v_id;
  update "app_private"."mail_threads" x set
    "subject" = coalesce(x."subject", nullif(trim(store_mail_message.message ->> 'subject'), '')),
    "snippet" = case when x."last_message_at" is null or v_sent >= x."last_message_at" then left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500) else x."snippet" end,
    "last_message_at" = greatest(x."last_message_at", v_sent),
    "message_count" = x."message_count" + 1,
    "updated_at" = now()
  where x."id" = v_thread;
  return jsonb_build_object('id', v_id, 'threadId', v_thread, 'created', true, 'direction', v_direction);
end;
$$;
revoke execute on function "app_private"."store_mail_message"(uuid, jsonb) from public, anon, authenticated;

-- Connects the caller's mailbox: credential_ref names the OAuth grant the
-- app stored for them. share is records (members who can read a linked
-- record see its threads) or private. Connecting again updates the grant.
create or replace function "app_private"."connect_mail_account"(tenant uuid, provider text, address text, credential_ref jsonb, share text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."mail_accounts";
  v_address text := lower(trim(connect_mail_account.address));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', connect_mail_account.tenant, 'mail.connect'), false) then
    raise exception 'not allowed to connect a mailbox' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if connect_mail_account.provider is null or connect_mail_account.provider !~ '^[a-z][a-z0-9-]{0,39}$' then
    raise exception 'provider is a lowercase name' using errcode = '22023', hint = 'MAIL_PROVIDER_INVALID';
  end if;
  if v_address is null or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception 'address is an email address' using errcode = '22023', hint = 'MAIL_ADDRESS_INVALID';
  end if;
  if coalesce(connect_mail_account.share, 'records') not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  if jsonb_typeof(connect_mail_account.credential_ref) is distinct from 'object' then
    raise exception 'credential_ref is a credential reference' using errcode = '22023', hint = 'MAIL_CREDENTIAL_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and connect_mail_account.credential_ref is not null and jsonb_typeof(connect_mail_account.credential_ref) <> 'null'
    and (jsonb_typeof(connect_mail_account.credential_ref -> 'tenant') is distinct from 'string' or (connect_mail_account.credential_ref ->> 'tenant') is distinct from (connect_mail_account.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', connect_mail_account.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  insert into "app_private"."mail_accounts" as x ("tenant_id", "user_id", "provider", "address", "credential_ref", "share")
  values (connect_mail_account.tenant, auth.uid(), connect_mail_account.provider, v_address, connect_mail_account.credential_ref, coalesce(connect_mail_account.share, 'records'))
  on conflict ("tenant_id", "user_id", "address") do update set
    "provider" = excluded."provider",
    "credential_ref" = excluded."credential_ref",
    "share" = excluded."share",
    "status" = 'active',
    "sync_cursor" = case when x."provider" = excluded."provider" then x."sync_cursor" end,
    "last_error" = null,
    "updated_at" = now()
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."connect_mail_account"(uuid, text, text, jsonb, text) from public, anon;
grant execute on function "app_private"."connect_mail_account"(uuid, text, text, jsonb, text) to authenticated, service_role;

-- Changes who sees a mailbox's threads (share) and pauses or resumes its
-- sync; null leaves a setting as it is. Only the mailbox's member may.
create or replace function "app_private"."update_mail_account"(account uuid, share text, paused boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if update_mail_account.share is not null and update_mail_account.share not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  update "app_private"."mail_accounts" x set
    "share" = coalesce(update_mail_account.share, x."share"),
    "status" = case
      when update_mail_account.paused then 'paused'
      when update_mail_account.paused = false and x."status" = 'paused' then 'active'
      else x."status" end,
    "updated_at" = now()
  where x."id" = update_mail_account.account and x."user_id" = auth.uid() and x."status" <> 'disconnected'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."update_mail_account"(uuid, text, boolean) from public, anon;
grant execute on function "app_private"."update_mail_account"(uuid, text, boolean) to authenticated, service_role;

-- Stops syncing a mailbox. Its member or a member with mail.manage may.
-- purge deletes the mailbox with its threads and messages.
create or replace function "app_private"."disconnect_mail_account"(account uuid, purge boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."mail_accounts" x
  where x."id" = disconnect_mail_account.account
    and (x."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.manage'), false));
  if v_row."id" is null then
    return false;
  end if;
  if coalesce(disconnect_mail_account.purge, false) then
    delete from "app_private"."mail_accounts" x where x."id" = v_row."id";
  else
    update "app_private"."mail_accounts" x set "status" = 'disconnected', "sync_cursor" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."disconnect_mail_account"(uuid, boolean) from public, anon;
grant execute on function "app_private"."disconnect_mail_account"(uuid, boolean) to authenticated, service_role;

-- The caller's mailboxes in a tenant; with mail.manage, every member's.
create or replace function "app_private"."mail_accounts_of"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at", x."id"), '[]'::jsonb)
  from "app_private"."mail_accounts" x
  where x."tenant_id" = mail_accounts_of.tenant
$$;
revoke execute on function "app_private"."mail_accounts_of"(uuid) from public, anon;
grant execute on function "app_private"."mail_accounts_of"(uuid) to authenticated, service_role;

-- One mailbox the caller can see, or null.
create or replace function "app_private"."get_mail_account"(account uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) from "app_private"."mail_accounts" x where x."id" = get_mail_account.account
$$;
revoke execute on function "app_private"."get_mail_account"(uuid) from public, anon;
grant execute on function "app_private"."get_mail_account"(uuid) to authenticated, service_role;

-- For the sync job: active mailboxes not synced within stale_after, the
-- longest waiting first, with their grant and cursor.
create or replace function "app_private"."due_mail_accounts"(max_count integer, stale_after interval)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(p) order by p."last_synced_at" nulls first, p."id"), '[]'::jsonb)
    from (
      select * from "app_private"."mail_accounts" x
      where x."status" = 'active'
        and (x."last_synced_at" is null or x."last_synced_at" < now() - coalesce(due_mail_accounts.stale_after, interval '5 minutes'))
      order by x."last_synced_at" nulls first, x."id"
      limit least(greatest(coalesce(due_mail_accounts.max_count, 25), 1), 500)
    ) p
  );
end;
$$;
revoke execute on function "app_private"."due_mail_accounts"(integer, interval) from public, anon, authenticated;
grant execute on function "app_private"."due_mail_accounts"(integer, interval) to service_role;

-- For the sync job: marks a mailbox active, paused or failed with an error
-- (a failed one waits for its member to connect it again).
create or replace function "app_private"."set_mail_account_status"(account uuid, status text, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if set_mail_account_status.status not in ('active', 'paused', 'error') then
    raise exception 'status is active, paused or error' using errcode = '22023', hint = 'MAIL_STATUS_INVALID';
  end if;
  update "app_private"."mail_accounts" x set
    "status" = set_mail_account_status.status,
    "last_error" = left(set_mail_account_status.error, 1000),
    "last_synced_at" = now(),
    "updated_at" = now()
  where x."id" = set_mail_account_status.account and x."status" <> 'disconnected';
  return found;
end;
$$;
revoke execute on function "app_private"."set_mail_account_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "app_private"."set_mail_account_status"(uuid, text, text) to service_role;

-- For the sync job: stores up to 500 provider messages on a mailbox,
-- links their threads to records and logs them, then saves the cursor the
-- next sync starts from. Returns { stored, threads }.
create or replace function "app_private"."ingest_mail"(account uuid, messages jsonb, next_cursor text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_item jsonb;
  v_stored jsonb;
  v_new jsonb := '[]'::jsonb;
  v_threads uuid[] := '{}';
  v_thread uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "app_private"."mail_accounts" k where k."id" = ingest_mail.account and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such connected mailbox' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(ingest_mail.messages, '[]')) <> 'array' then
    raise exception 'messages is a list' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if jsonb_array_length(coalesce(ingest_mail.messages, '[]')) > 500 then
    raise exception 'at most 500 messages per call' using errcode = '22023', hint = 'MAIL_BATCH_TOO_LARGE';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(ingest_mail.messages, '[]')) loop
    v_stored := "app_private"."store_mail_message"(v_account.id, v_item);
    if not ((v_stored ->> 'threadId')::uuid = any (v_threads)) then
      v_threads := v_threads || (v_stored ->> 'threadId')::uuid;
    end if;
    if (v_stored ->> 'created')::boolean then
      v_new := v_new || jsonb_build_array(v_stored || jsonb_build_object('fromAddress', lower(coalesce(v_item -> 'from' ->> 'address', v_item ->> 'from'))));
    end if;
  end loop;
  foreach v_thread in array v_threads loop
    null;
    null;
  end loop;
  for v_stored in select value from jsonb_array_elements(v_new) loop
    if v_stored ->> 'direction' = 'outbound' then
      null;
    else
      null;
    end if;
  end loop;
  update "app_private"."mail_accounts" x set
    "sync_cursor" = coalesce(ingest_mail.next_cursor, x."sync_cursor"),
    "last_synced_at" = now(),
    "status" = case when x."status" = 'error' then 'active' else x."status" end,
    "last_error" = null,
    "updated_at" = now()
  where x."id" = v_account.id;
  return jsonb_build_object('stored', jsonb_array_length(v_new), 'threads', coalesce(array_length(v_threads, 1), 0));
end;
$$;
revoke execute on function "app_private"."ingest_mail"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private"."ingest_mail"(uuid, jsonb, text) to service_role;

-- Records a message the caller sent from their mailbox through the provider
-- (the block's send does both), so it shows on the thread before the next
-- sync. The service role records for any mailbox, as a server-side sender
-- such as the sequences runner does. Returns the stored message.
create or replace function "app_private"."record_sent_mail"(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_stored jsonb;
  v_thread uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "app_private"."mail_accounts" k
  where k."id" = record_sent_mail.account and (k."user_id" = auth.uid() or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_account.tenant, 'mail.send'), false) then
    raise exception 'not allowed to send mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  v_stored := "app_private"."store_mail_message"(v_account.id, coalesce(record_sent_mail.message, '{}'::jsonb) || '{"direction": "outbound"}'::jsonb);
  v_thread := (v_stored ->> 'threadId')::uuid;
  
  
  if (v_stored ->> 'created')::boolean then
    if jsonb_typeof(record_sent_mail.message -> 'trackedLinks') = 'array' then
      insert into "app_private"."mail_tracked_links" ("tenant_id", "message_id", "position", "url")
      select v_account.tenant, (v_stored ->> 'id')::uuid, (u.ord - 1)::integer, u.value #>> '{}'
      from jsonb_array_elements(record_sent_mail.message -> 'trackedLinks') with ordinality u (value, ord);
    end if;
    v_stored := v_stored || jsonb_build_object('fromAddress', (select k."address" from "app_private"."mail_accounts" k where k."id" = v_account.id));
    null;
  end if;
  return (select to_jsonb(y) from "app_private"."mail_messages" y where y."id" = (v_stored ->> 'id')::uuid);
end;
$$;
revoke execute on function "app_private"."record_sent_mail"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."record_sent_mail"(uuid, jsonb) to authenticated, service_role;

-- Links a thread of the caller's mailbox to records ([{ type, id }]) by
-- hand, for senders no person matches, and logs it on them.
create or replace function "app_private"."link_mail_thread"(thread uuid, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_thread uuid := link_mail_thread.thread;
  v_tenant uuid;
  v_item jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant
  from "app_private"."mail_threads" x join "app_private"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = v_thread and k."user_id" = auth.uid();
  if v_tenant is null then
    raise exception 'no such thread in your mailbox' using errcode = 'P0002', hint = 'MAIL_THREAD_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(link_mail_thread.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'MAIL_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(link_mail_thread.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'MAIL_SUBJECT_FORBIDDEN';
    end if;
    insert into "app_private"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id", "source")
    values (v_tenant, v_thread, v_item ->> 'type', v_item ->> 'id', 'manual')
    on conflict ("thread_id", "subject_type", "subject_id") do update set "source" = 'manual';
  end loop;
  
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "app_private"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) from "app_private"."mail_threads" x where x."id" = v_thread);
end;
$$;
revoke execute on function "app_private"."link_mail_thread"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."link_mail_thread"(uuid, jsonb) to authenticated, service_role;

-- Removes a record from a thread of the caller's mailbox.
create or replace function "app_private"."unlink_mail_thread"(thread uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "app_private"."mail_thread_subjects" s
  using "app_private"."mail_threads" x, "app_private"."mail_accounts" k
  where s."thread_id" = unlink_mail_thread.thread
    and s."subject_type" = unlink_mail_thread.subject_type and s."subject_id" = unlink_mail_thread.subject_id
    and x."id" = s."thread_id" and k."id" = x."account_id" and k."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "app_private"."unlink_mail_thread"(uuid, text, text) from public, anon;
grant execute on function "app_private"."unlink_mail_thread"(uuid, text, text) to authenticated, service_role;

-- A record's threads the caller can see, the latest message first. before
-- continues after the last thread of the previous page.
create or replace function "app_private"."mail_threads_of"(subject_type text, subject_id text, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "app_private"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "app_private"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "app_private"."mail_threads" x
    join "app_private"."mail_thread_subjects" s on s."thread_id" = x."id"
    where s."subject_type" = mail_threads_of.subject_type and s."subject_id" = mail_threads_of.subject_id
      and (mail_threads_of.before is null or x."last_message_at" < mail_threads_of.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(mail_threads_of.page_size, 25), 1), 100)
  ) p
$$;
revoke execute on function "app_private"."mail_threads_of"(text, text, timestamptz, integer) from public, anon;
grant execute on function "app_private"."mail_threads_of"(text, text, timestamptz, integer) to authenticated, service_role;

-- The threads the caller can see in a tenant, or in one mailbox, the
-- latest message first.
create or replace function "app_private"."list_mail_threads"(tenant uuid, account uuid, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "app_private"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "app_private"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "app_private"."mail_threads" x
    where x."tenant_id" = list_mail_threads.tenant
      and (list_mail_threads.account is null or x."account_id" = list_mail_threads.account)
      and (list_mail_threads.before is null or x."last_message_at" < list_mail_threads.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(list_mail_threads.page_size, 25), 1), 100)
  ) p
$$;
revoke execute on function "app_private"."list_mail_threads"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "app_private"."list_mail_threads"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- A thread with its messages, oldest first; null when the caller can't see it.
create or replace function "app_private"."get_mail_thread"(thread uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "app_private"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "app_private"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('messages', coalesce((
    select jsonb_agg(to_jsonb(y) order by y."sent_at", y."id")
    from "app_private"."mail_messages" y where y."thread_id" = x."id"
  ), '[]'::jsonb))
  from "app_private"."mail_threads" x
  where x."id" = get_mail_thread.thread
$$;
revoke execute on function "app_private"."get_mail_thread"(uuid) from public, anon;
grant execute on function "app_private"."get_mail_thread"(uuid) to authenticated, service_role;

-- For the tracking route: records an open of the tracked message whose token
-- hashes to hash, or a click on its link at index link. Returns { messageId,
-- url } (url, the stored link, for a click), or null for an unknown token.
create or replace function "app_private"."track_mail"(hash text, kind text, link integer, user_agent text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message record;
  v_url text;
  v_event uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role records tracking' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if track_mail.kind is null or track_mail.kind not in ('open', 'click') then
    raise exception 'kind is open or click' using errcode = '22023', hint = 'MAIL_TRACKING_INVALID';
  end if;
  select y."id" as id, y."tenant_id" as tenant, y."account_id" as account, y."thread_id" as thread,
    y."template_version_id" as template, y."opened_at" as opened, x."user_id" as owner
  into v_message
  from "app_private"."mail_messages" y join "app_private"."mail_accounts" x on x."id" = y."account_id"
  where y."tracking_hash" = lower(track_mail.hash) and y."direction" = 'outbound';
  if v_message.id is null then
    return null;
  end if;
  if track_mail.kind = 'click' then
    update "app_private"."mail_tracked_links" u set "click_count" = u."click_count" + 1
    where u."message_id" = v_message.id and u."position" = track_mail.link
    returning u."url" into v_url;
    if v_url is null then
      return null;
    end if;
  end if;
  insert into "app_private"."mail_tracking_events" ("tenant_id", "message_id", "kind", "position", "user_agent")
  values (v_message.tenant, v_message.id, track_mail.kind, case when track_mail.kind = 'click' then track_mail.link end, left(track_mail.user_agent, 300))
  returning "id" into v_event;
  update "app_private"."mail_messages" y set
    "opened_at" = coalesce(y."opened_at", now()),
    "open_count" = y."open_count" + case when track_mail.kind = 'open' then 1 else 0 end,
    "clicked_at" = case when track_mail.kind = 'click' then coalesce(y."clicked_at", now()) else y."clicked_at" end,
    "click_count" = y."click_count" + case when track_mail.kind = 'click' then 1 else 0 end
  where y."id" = v_message.id;
  if track_mail.kind = 'click' then
    null;
  elsif v_message.opened is null then
    null;
  end if;
  return jsonb_build_object('messageId', v_message.id, 'url', v_url);
end;
$$;
revoke execute on function "app_private"."track_mail"(text, text, integer, text) from public, anon, authenticated;
grant execute on function "app_private"."track_mail"(text, text, integer, text) to service_role;

-- Per template version, how many messages members sent from shared
-- mailboxes since a time, and how many were opened, clicked and replied to.
create or replace function "app_private"."mail_template_stats"(tenant uuid, since timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.can('tenant', mail_template_stats.tenant, 'mail.read'), false) then
    raise exception 'not allowed to read mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('templateVersionId', p.template, 'sent', p.sent, 'opened', p.opened, 'clicked', p.clicked, 'replied', p.replied) order by p.sent desc, p.template), '[]'::jsonb)
    from (
      select y."template_version_id" as template, count(*) as sent, count(y."opened_at") as opened, count(y."clicked_at") as clicked,
        count(*) filter (where exists (
          select 1 from "app_private"."mail_messages" r
          where r."thread_id" = y."thread_id" and r."direction" = 'inbound' and r."sent_at" > y."sent_at"
        )) as replied
      from "app_private"."mail_messages" y join "app_private"."mail_accounts" x on x."id" = y."account_id"
      where y."tenant_id" = mail_template_stats.tenant and y."direction" = 'outbound'
        and y."template_version_id" is not null
        and (x."share" = 'records' or x."user_id" = auth.uid())
        and (mail_template_stats.since is null or y."sent_at" >= mail_template_stats.since)
      group by y."template_version_id"
    ) p
  );
end;
$$;
revoke execute on function "app_private"."mail_template_stats"(uuid, timestamptz) from public, anon;
grant execute on function "app_private"."mail_template_stats"(uuid, timestamptz) to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_132_mail_sync.sql
-- better-supabase module: mail-sync
-- @bsb-block-data mail-sync
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_132_mail_sync.sql
-- better-supabase module: mail-sync
-- @bsb-block mail-sync@1 managed
-- Gmail, Outlook and other mailboxes synced per member through their own OAuth grant: threads and messages linked to the people and companies they involve, logged as email engagements, and a record of the mail members send, with opens and clicks per message and per template version.
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
-- Gmail, Outlook and other mailboxes synced per member: threads and messages
-- linked to the people and companies they involve, logged as engagements.
create table if not exists "better_supabase"."mail_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9-]{0,39}$'),
  "address" text not null check ("address" = lower("address") and "address" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "credential_ref" jsonb not null check (jsonb_typeof("credential_ref") = 'object'),
  "share" text not null default 'records' check ("share" in ('records', 'private')),
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'error', 'disconnected')),
  "sync_cursor" text,
  "last_synced_at" timestamptz,
  "last_error" text,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "address")
);
create index if not exists mail_accounts_user_idx on "better_supabase"."mail_accounts" ("user_id");
create index if not exists mail_accounts_due_idx on "better_supabase"."mail_accounts" ("last_synced_at" nulls first) where "status" = 'active';
alter table "better_supabase"."mail_accounts" enable row level security;
revoke all on "better_supabase"."mail_accounts" from anon, authenticated;
grant select on "better_supabase"."mail_accounts" to authenticated;
grant all on "better_supabase"."mail_accounts" to service_role;
create table if not exists "better_supabase"."mail_threads" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."mail_accounts" ("id") on delete cascade,
  "external_id" text not null,
  "subject" text,
  "snippet" text,
  "last_message_at" timestamptz,
  "message_count" integer not null default 0,
  "engagement_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("account_id", "external_id")
);
create index if not exists mail_threads_tenant_recent_idx on "better_supabase"."mail_threads" ("tenant_id", "last_message_at" desc);
create index if not exists mail_threads_engagement_idx on "better_supabase"."mail_threads" ("engagement_id") where "engagement_id" is not null;
alter table "better_supabase"."mail_threads" enable row level security;
revoke all on "better_supabase"."mail_threads" from anon, authenticated;
grant select on "better_supabase"."mail_threads" to authenticated;
grant all on "better_supabase"."mail_threads" to service_role;
create table if not exists "better_supabase"."mail_messages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."mail_accounts" ("id") on delete cascade,
  "thread_id" uuid not null references "better_supabase"."mail_threads" ("id") on delete cascade,
  "external_id" text not null,
  "rfc_message_id" text,
  "direction" text not null check ("direction" in ('inbound', 'outbound')),
  "from_address" text,
  "from_name" text,
  "to_addresses" text[] not null default '{}',
  "cc_addresses" text[] not null default '{}',
  "subject" text,
  "snippet" text,
  "body_text" text,
  "body_html" text,
  "sent_at" timestamptz not null,
  "template_version_id" uuid,
  "tracking_hash" text check ("tracking_hash" ~ '^[0-9a-f]{64}$'),
  "opened_at" timestamptz,
  "open_count" integer not null default 0,
  "clicked_at" timestamptz,
  "click_count" integer not null default 0,
  "created_at" timestamptz not null default now(),
  unique ("account_id", "external_id")
);
create index if not exists mail_messages_thread_idx on "better_supabase"."mail_messages" ("thread_id", "sent_at");
create index if not exists mail_messages_rfc_idx on "better_supabase"."mail_messages" ("account_id", "rfc_message_id") where "rfc_message_id" is not null;
create unique index if not exists mail_messages_tracking_idx on "better_supabase"."mail_messages" ("tracking_hash") where "tracking_hash" is not null;
create index if not exists mail_messages_template_idx on "better_supabase"."mail_messages" ("tenant_id", "template_version_id") where "template_version_id" is not null;
alter table "better_supabase"."mail_messages" enable row level security;
revoke all on "better_supabase"."mail_messages" from anon, authenticated;
grant select on "better_supabase"."mail_messages" to authenticated;
grant all on "better_supabase"."mail_messages" to service_role;
create table if not exists "better_supabase"."mail_tracked_links" (
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."mail_messages" ("id") on delete cascade,
  "position" integer not null check ("position" >= 0),
  "url" text not null check ("url" ~* '^https?://' and length("url") <= 2048),
  "click_count" integer not null default 0,
  "created_at" timestamptz not null default now(),
  primary key ("message_id", "position")
);
alter table "better_supabase"."mail_tracked_links" enable row level security;
revoke all on "better_supabase"."mail_tracked_links" from anon, authenticated;
grant select on "better_supabase"."mail_tracked_links" to authenticated;
grant all on "better_supabase"."mail_tracked_links" to service_role;
create table if not exists "better_supabase"."mail_tracking_events" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "message_id" uuid not null references "better_supabase"."mail_messages" ("id") on delete cascade,
  "kind" text not null check ("kind" in ('open', 'click')),
  "position" integer,
  "user_agent" text check (length("user_agent") <= 300),
  "occurred_at" timestamptz not null default now()
);
create index if not exists mail_tracking_events_message_idx on "better_supabase"."mail_tracking_events" ("message_id", "occurred_at");
alter table "better_supabase"."mail_tracking_events" enable row level security;
revoke all on "better_supabase"."mail_tracking_events" from anon, authenticated;
grant select on "better_supabase"."mail_tracking_events" to authenticated;
grant all on "better_supabase"."mail_tracking_events" to service_role;
create table if not exists "better_supabase"."mail_thread_subjects" (
  "tenant_id" uuid not null,
  "thread_id" uuid not null references "better_supabase"."mail_threads" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "source" text not null default 'match' check ("source" in ('match', 'manual')),
  "created_at" timestamptz not null default now(),
  primary key ("thread_id", "subject_type", "subject_id")
);
create index if not exists mail_thread_subjects_subject_idx on "better_supabase"."mail_thread_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."mail_thread_subjects" enable row level security;
revoke all on "better_supabase"."mail_thread_subjects" from anon, authenticated;
grant select on "better_supabase"."mail_thread_subjects" to authenticated;
grant all on "better_supabase"."mail_thread_subjects" to service_role;

-- Whether the caller may read a thread: its mailbox is theirs, or the mailbox
-- shares with records and the caller can read one of the thread's records.
create or replace function "better_supabase"."mail_thread_visible"(thread uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."mail_threads" x
    join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
    where x."id" = $1
      and (k."user_id" = auth.uid() or (
        k."share" = 'records'
        and coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.read'), false)
        and exists (
          select 1 from "better_supabase"."mail_thread_subjects" s
          where s."thread_id" = x."id"
            and "better_supabase"."can_subject"(s."subject_type", s."subject_id", 'read')
        )
      ))
  )
$$;
revoke execute on function "better_supabase"."mail_thread_visible"(uuid) from public, anon;
grant execute on function "better_supabase"."mail_thread_visible"(uuid) to authenticated, service_role;

drop policy if exists mail_accounts_read on "better_supabase"."mail_accounts";
create policy mail_accounts_read on "better_supabase"."mail_accounts" for select to authenticated
using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('mail.manage')));
drop policy if exists mail_threads_read on "better_supabase"."mail_threads";
create policy mail_threads_read on "better_supabase"."mail_threads" for select to authenticated
using ("better_supabase"."mail_thread_visible"("id"));
drop policy if exists mail_messages_read on "better_supabase"."mail_messages";
create policy mail_messages_read on "better_supabase"."mail_messages" for select to authenticated
using ("better_supabase"."mail_thread_visible"("thread_id"));
drop policy if exists mail_thread_subjects_read on "better_supabase"."mail_thread_subjects";
create policy mail_thread_subjects_read on "better_supabase"."mail_thread_subjects" for select to authenticated
using ("better_supabase"."mail_thread_visible"("thread_id"));
drop policy if exists mail_tracked_links_read on "better_supabase"."mail_tracked_links";
create policy mail_tracked_links_read on "better_supabase"."mail_tracked_links" for select to authenticated
using (exists (select 1 from "better_supabase"."mail_messages" y where y."id" = "message_id" and "better_supabase"."mail_thread_visible"(y."thread_id")));
drop policy if exists mail_tracking_events_read on "better_supabase"."mail_tracking_events";
create policy mail_tracking_events_read on "better_supabase"."mail_tracking_events" for select to authenticated
using (exists (select 1 from "better_supabase"."mail_messages" y where y."id" = "message_id" and "better_supabase"."mail_thread_visible"(y."thread_id")));

-- Stores a message on its account: message is { externalId, threadId,
-- messageId, direction, from: { address, name }, to, cc, subject, snippet,
-- text, html, sentAt, templateVersionId, trackingHash }. Returns { id, threadId, created, direction }.
create or replace function "better_supabase"."store_mail_message"(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account record;
  v_external text := nullif(trim(store_mail_message.message ->> 'externalId'), '');
  v_thread_ref text := coalesce(nullif(trim(store_mail_message.message ->> 'threadId'), ''), nullif(trim(store_mail_message.message ->> 'externalId'), ''));
  v_rfc text := nullif(trim(store_mail_message.message ->> 'messageId'), '');
  v_from text := lower(coalesce(nullif(trim(store_mail_message.message -> 'from' ->> 'address'), ''), case when jsonb_typeof(store_mail_message.message -> 'from') = 'string' then nullif(trim(store_mail_message.message ->> 'from'), '') end));
  v_direction text := nullif(trim(store_mail_message.message ->> 'direction'), '');
  v_template text := nullif(trim(store_mail_message.message ->> 'templateVersionId'), '');
  v_hash text := lower(nullif(trim(store_mail_message.message ->> 'trackingHash'), ''));
  v_sent timestamptz;
  v_thread uuid;
  v_id uuid;
begin
  select k."id" as id, k."tenant_id" as tenant, k."address" as address into v_account
  from "better_supabase"."mail_accounts" k where k."id" = store_mail_message.account;
  if jsonb_typeof(store_mail_message.message) <> 'object' or v_external is null or nullif(trim(store_mail_message.message ->> 'sentAt'), '') is null then
    raise exception 'a message needs an externalId and a sentAt' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if v_template is not null and v_template !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'templateVersionId is a uuid' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  v_sent := (nullif(trim(store_mail_message.message ->> 'sentAt'), ''))::timestamptz;
  v_direction := coalesce(v_direction, case when v_from = v_account.address then 'outbound' else 'inbound' end);
  if v_direction not in ('inbound', 'outbound') then
    raise exception 'direction is inbound or outbound' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  insert into "better_supabase"."mail_threads" ("tenant_id", "account_id", "external_id")
  values (v_account.tenant, v_account.id, v_thread_ref)
  on conflict ("account_id", "external_id") do update set "updated_at" = now()
  returning "id" into v_thread;
  select y."id" into v_id from "better_supabase"."mail_messages" y
  where y."account_id" = v_account.id
    and (y."external_id" = v_external or (v_rfc is not null and y."rfc_message_id" = v_rfc))
  order by y."external_id" = v_external desc
  limit 1;
  if v_id is not null then
    update "better_supabase"."mail_messages" y set "external_id" = v_external, "rfc_message_id" = coalesce(v_rfc, y."rfc_message_id")
    where y."id" = v_id
      and not exists (select 1 from "better_supabase"."mail_messages" z where z."account_id" = v_account.id and z."external_id" = v_external and z."id" <> v_id);
    return jsonb_build_object('id', v_id, 'threadId', (select y."thread_id" from "better_supabase"."mail_messages" y where y."id" = v_id), 'created', false, 'direction', v_direction);
  end if;
  insert into "better_supabase"."mail_messages" ("tenant_id", "account_id", "thread_id", "external_id", "rfc_message_id", "direction",
    "from_address", "from_name", "to_addresses", "cc_addresses", "subject", "snippet", "body_text", "body_html", "sent_at",
    "template_version_id", "tracking_hash")
  values (v_account.tenant, v_account.id, v_thread, v_external, v_rfc, v_direction,
    v_from, nullif(trim(store_mail_message.message -> 'from' ->> 'name'), ''), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'to') = 'array' then store_mail_message.message -> 'to' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'cc') = 'array' then store_mail_message.message -> 'cc' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'),
    nullif(trim(store_mail_message.message ->> 'subject'), ''), left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500), store_mail_message.message ->> 'text', store_mail_message.message ->> 'html', v_sent,
    v_template::uuid, case when v_direction = 'outbound' then v_hash end)
  returning "id" into v_id;
  update "better_supabase"."mail_threads" x set
    "subject" = coalesce(x."subject", nullif(trim(store_mail_message.message ->> 'subject'), '')),
    "snippet" = case when x."last_message_at" is null or v_sent >= x."last_message_at" then left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500) else x."snippet" end,
    "last_message_at" = greatest(x."last_message_at", v_sent),
    "message_count" = x."message_count" + 1,
    "updated_at" = now()
  where x."id" = v_thread;
  return jsonb_build_object('id', v_id, 'threadId', v_thread, 'created', true, 'direction', v_direction);
end;
$$;
revoke execute on function "better_supabase"."store_mail_message"(uuid, jsonb) from public, anon, authenticated;

-- Connects the caller's mailbox: credential_ref names the OAuth grant the
-- app stored for them. share is records (members who can read a linked
-- record see its threads) or private. Connecting again updates the grant.
create or replace function "better_supabase"."connect_mail_account"(tenant uuid, provider text, address text, credential_ref jsonb, share text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."mail_accounts";
  v_address text := lower(trim(connect_mail_account.address));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', connect_mail_account.tenant, 'mail.connect'), false) then
    raise exception 'not allowed to connect a mailbox' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if connect_mail_account.provider is null or connect_mail_account.provider !~ '^[a-z][a-z0-9-]{0,39}$' then
    raise exception 'provider is a lowercase name' using errcode = '22023', hint = 'MAIL_PROVIDER_INVALID';
  end if;
  if v_address is null or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception 'address is an email address' using errcode = '22023', hint = 'MAIL_ADDRESS_INVALID';
  end if;
  if coalesce(connect_mail_account.share, 'records') not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  if jsonb_typeof(connect_mail_account.credential_ref) is distinct from 'object' then
    raise exception 'credential_ref is a credential reference' using errcode = '22023', hint = 'MAIL_CREDENTIAL_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and connect_mail_account.credential_ref is not null and jsonb_typeof(connect_mail_account.credential_ref) <> 'null'
    and (jsonb_typeof(connect_mail_account.credential_ref -> 'tenant') is distinct from 'string' or (connect_mail_account.credential_ref ->> 'tenant') is distinct from (connect_mail_account.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', connect_mail_account.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  insert into "better_supabase"."mail_accounts" as x ("tenant_id", "user_id", "provider", "address", "credential_ref", "share")
  values (connect_mail_account.tenant, auth.uid(), connect_mail_account.provider, v_address, connect_mail_account.credential_ref, coalesce(connect_mail_account.share, 'records'))
  on conflict ("tenant_id", "user_id", "address") do update set
    "provider" = excluded."provider",
    "credential_ref" = excluded."credential_ref",
    "share" = excluded."share",
    "status" = 'active',
    "sync_cursor" = case when x."provider" = excluded."provider" then x."sync_cursor" end,
    "last_error" = null,
    "updated_at" = now()
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."connect_mail_account"(uuid, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."connect_mail_account"(uuid, text, text, jsonb, text) to authenticated, service_role;

-- Changes who sees a mailbox's threads (share) and pauses or resumes its
-- sync; null leaves a setting as it is. Only the mailbox's member may.
create or replace function "better_supabase"."update_mail_account"(account uuid, share text, paused boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if update_mail_account.share is not null and update_mail_account.share not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  update "better_supabase"."mail_accounts" x set
    "share" = coalesce(update_mail_account.share, x."share"),
    "status" = case
      when update_mail_account.paused then 'paused'
      when update_mail_account.paused = false and x."status" = 'paused' then 'active'
      else x."status" end,
    "updated_at" = now()
  where x."id" = update_mail_account.account and x."user_id" = auth.uid() and x."status" <> 'disconnected'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."update_mail_account"(uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."update_mail_account"(uuid, text, boolean) to authenticated, service_role;

-- Stops syncing a mailbox. Its member or a member with mail.manage may.
-- purge deletes the mailbox with its threads and messages.
create or replace function "better_supabase"."disconnect_mail_account"(account uuid, purge boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."mail_accounts" x
  where x."id" = disconnect_mail_account.account
    and (x."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.manage'), false));
  if v_row."id" is null then
    return false;
  end if;
  if coalesce(disconnect_mail_account.purge, false) then
    delete from "better_supabase"."mail_accounts" x where x."id" = v_row."id";
  else
    update "better_supabase"."mail_accounts" x set "status" = 'disconnected', "sync_cursor" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."disconnect_mail_account"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."disconnect_mail_account"(uuid, boolean) to authenticated, service_role;

-- The caller's mailboxes in a tenant; with mail.manage, every member's.
create or replace function "better_supabase"."mail_accounts_of"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at", x."id"), '[]'::jsonb)
  from "better_supabase"."mail_accounts" x
  where x."tenant_id" = mail_accounts_of.tenant
$$;
revoke execute on function "better_supabase"."mail_accounts_of"(uuid) from public, anon;
grant execute on function "better_supabase"."mail_accounts_of"(uuid) to authenticated, service_role;

-- One mailbox the caller can see, or null.
create or replace function "better_supabase"."get_mail_account"(account uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) from "better_supabase"."mail_accounts" x where x."id" = get_mail_account.account
$$;
revoke execute on function "better_supabase"."get_mail_account"(uuid) from public, anon;
grant execute on function "better_supabase"."get_mail_account"(uuid) to authenticated, service_role;

-- For the sync job: active mailboxes not synced within stale_after, the
-- longest waiting first, with their grant and cursor.
create or replace function "better_supabase"."due_mail_accounts"(max_count integer, stale_after interval)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(p) order by p."last_synced_at" nulls first, p."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."status" = 'active'
        and (x."last_synced_at" is null or x."last_synced_at" < now() - coalesce(due_mail_accounts.stale_after, interval '5 minutes'))
      order by x."last_synced_at" nulls first, x."id"
      limit least(greatest(coalesce(due_mail_accounts.max_count, 25), 1), 500)
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."due_mail_accounts"(integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."due_mail_accounts"(integer, interval) to service_role;

-- For the sync job: marks a mailbox active, paused or failed with an error
-- (a failed one waits for its member to connect it again).
create or replace function "better_supabase"."set_mail_account_status"(account uuid, status text, error text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if set_mail_account_status.status not in ('active', 'paused', 'error') then
    raise exception 'status is active, paused or error' using errcode = '22023', hint = 'MAIL_STATUS_INVALID';
  end if;
  update "better_supabase"."mail_accounts" x set
    "status" = set_mail_account_status.status,
    "last_error" = left(set_mail_account_status.error, 1000),
    "last_synced_at" = now(),
    "updated_at" = now()
  where x."id" = set_mail_account_status.account and x."status" <> 'disconnected';
  return found;
end;
$$;
revoke execute on function "better_supabase"."set_mail_account_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."set_mail_account_status"(uuid, text, text) to service_role;

-- For the sync job: stores up to 500 provider messages on a mailbox,
-- links their threads to records and logs them, then saves the cursor the
-- next sync starts from. Returns { stored, threads }.
create or replace function "better_supabase"."ingest_mail"(account uuid, messages jsonb, next_cursor text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_item jsonb;
  v_stored jsonb;
  v_new jsonb := '[]'::jsonb;
  v_threads uuid[] := '{}';
  v_thread uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "better_supabase"."mail_accounts" k where k."id" = ingest_mail.account and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such connected mailbox' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(ingest_mail.messages, '[]')) <> 'array' then
    raise exception 'messages is a list' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if jsonb_array_length(coalesce(ingest_mail.messages, '[]')) > 500 then
    raise exception 'at most 500 messages per call' using errcode = '22023', hint = 'MAIL_BATCH_TOO_LARGE';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(ingest_mail.messages, '[]')) loop
    v_stored := "better_supabase"."store_mail_message"(v_account.id, v_item);
    if not ((v_stored ->> 'threadId')::uuid = any (v_threads)) then
      v_threads := v_threads || (v_stored ->> 'threadId')::uuid;
    end if;
    if (v_stored ->> 'created')::boolean then
      v_new := v_new || jsonb_build_array(v_stored || jsonb_build_object('fromAddress', lower(coalesce(v_item -> 'from' ->> 'address', v_item ->> 'from'))));
    end if;
  end loop;
  foreach v_thread in array v_threads loop
    null;
    null;
  end loop;
  for v_stored in select value from jsonb_array_elements(v_new) loop
    if v_stored ->> 'direction' = 'outbound' then
      null;
    else
      null;
    end if;
  end loop;
  update "better_supabase"."mail_accounts" x set
    "sync_cursor" = coalesce(ingest_mail.next_cursor, x."sync_cursor"),
    "last_synced_at" = now(),
    "status" = case when x."status" = 'error' then 'active' else x."status" end,
    "last_error" = null,
    "updated_at" = now()
  where x."id" = v_account.id;
  return jsonb_build_object('stored', jsonb_array_length(v_new), 'threads', coalesce(array_length(v_threads, 1), 0));
end;
$$;
revoke execute on function "better_supabase"."ingest_mail"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."ingest_mail"(uuid, jsonb, text) to service_role;

-- Records a message the caller sent from their mailbox through the provider
-- (the block's send does both), so it shows on the thread before the next
-- sync. The service role records for any mailbox, as a server-side sender
-- such as the sequences runner does. Returns the stored message.
create or replace function "better_supabase"."record_sent_mail"(account uuid, message jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
  v_stored jsonb;
  v_thread uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "better_supabase"."mail_accounts" k
  where k."id" = record_sent_mail.account and (k."user_id" = auth.uid() or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_account.tenant, 'mail.send'), false) then
    raise exception 'not allowed to send mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  v_stored := "better_supabase"."store_mail_message"(v_account.id, coalesce(record_sent_mail.message, '{}'::jsonb) || '{"direction": "outbound"}'::jsonb);
  v_thread := (v_stored ->> 'threadId')::uuid;
  
  
  if (v_stored ->> 'created')::boolean then
    if jsonb_typeof(record_sent_mail.message -> 'trackedLinks') = 'array' then
      insert into "better_supabase"."mail_tracked_links" ("tenant_id", "message_id", "position", "url")
      select v_account.tenant, (v_stored ->> 'id')::uuid, (u.ord - 1)::integer, u.value #>> '{}'
      from jsonb_array_elements(record_sent_mail.message -> 'trackedLinks') with ordinality u (value, ord);
    end if;
    v_stored := v_stored || jsonb_build_object('fromAddress', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = v_account.id));
    null;
  end if;
  return (select to_jsonb(y) from "better_supabase"."mail_messages" y where y."id" = (v_stored ->> 'id')::uuid);
end;
$$;
revoke execute on function "better_supabase"."record_sent_mail"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."record_sent_mail"(uuid, jsonb) to authenticated, service_role;

-- Links a thread of the caller's mailbox to records ([{ type, id }]) by
-- hand, for senders no person matches, and logs it on them.
create or replace function "better_supabase"."link_mail_thread"(thread uuid, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_thread uuid := link_mail_thread.thread;
  v_tenant uuid;
  v_item jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant
  from "better_supabase"."mail_threads" x join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = v_thread and k."user_id" = auth.uid();
  if v_tenant is null then
    raise exception 'no such thread in your mailbox' using errcode = 'P0002', hint = 'MAIL_THREAD_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(link_mail_thread.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'MAIL_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(link_mail_thread.subjects, '[]')) loop
    if not false then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'MAIL_SUBJECT_FORBIDDEN';
    end if;
    insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id", "source")
    values (v_tenant, v_thread, v_item ->> 'type', v_item ->> 'id', 'manual')
    on conflict ("thread_id", "subject_type", "subject_id") do update set "source" = 'manual';
  end loop;
  
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) from "better_supabase"."mail_threads" x where x."id" = v_thread);
end;
$$;
revoke execute on function "better_supabase"."link_mail_thread"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."link_mail_thread"(uuid, jsonb) to authenticated, service_role;

-- Removes a record from a thread of the caller's mailbox.
create or replace function "better_supabase"."unlink_mail_thread"(thread uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."mail_thread_subjects" s
  using "better_supabase"."mail_threads" x, "better_supabase"."mail_accounts" k
  where s."thread_id" = unlink_mail_thread.thread
    and s."subject_type" = unlink_mail_thread.subject_type and s."subject_id" = unlink_mail_thread.subject_id
    and x."id" = s."thread_id" and k."id" = x."account_id" and k."user_id" = auth.uid();
  return found;
end;
$$;
revoke execute on function "better_supabase"."unlink_mail_thread"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."unlink_mail_thread"(uuid, text, text) to authenticated, service_role;

-- A record's threads the caller can see, the latest message first. before
-- continues after the last thread of the previous page.
create or replace function "better_supabase"."mail_threads_of"(subject_type text, subject_id text, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "better_supabase"."mail_threads" x
    join "better_supabase"."mail_thread_subjects" s on s."thread_id" = x."id"
    where s."subject_type" = mail_threads_of.subject_type and s."subject_id" = mail_threads_of.subject_id
      and (mail_threads_of.before is null or x."last_message_at" < mail_threads_of.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(mail_threads_of.page_size, 25), 1), 100)
  ) p
$$;
revoke execute on function "better_supabase"."mail_threads_of"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."mail_threads_of"(text, text, timestamptz, integer) to authenticated, service_role;

-- The threads the caller can see in a tenant, or in one mailbox, the
-- latest message first.
create or replace function "better_supabase"."list_mail_threads"(tenant uuid, account uuid, before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "better_supabase"."mail_threads" x
    where x."tenant_id" = list_mail_threads.tenant
      and (list_mail_threads.account is null or x."account_id" = list_mail_threads.account)
      and (list_mail_threads.before is null or x."last_message_at" < list_mail_threads.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(list_mail_threads.page_size, 25), 1), 100)
  ) p
$$;
revoke execute on function "better_supabase"."list_mail_threads"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_mail_threads"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- A thread with its messages, oldest first; null when the caller can't see it.
create or replace function "better_supabase"."get_mail_thread"(thread uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('messages', coalesce((
    select jsonb_agg(to_jsonb(y) order by y."sent_at", y."id")
    from "better_supabase"."mail_messages" y where y."thread_id" = x."id"
  ), '[]'::jsonb))
  from "better_supabase"."mail_threads" x
  where x."id" = get_mail_thread.thread
$$;
revoke execute on function "better_supabase"."get_mail_thread"(uuid) from public, anon;
grant execute on function "better_supabase"."get_mail_thread"(uuid) to authenticated, service_role;

-- For the tracking route: records an open of the tracked message whose token
-- hashes to hash, or a click on its link at index link. Returns { messageId,
-- url } (url, the stored link, for a click), or null for an unknown token.
create or replace function "better_supabase"."track_mail"(hash text, kind text, link integer, user_agent text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message record;
  v_url text;
  v_event uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role records tracking' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if track_mail.kind is null or track_mail.kind not in ('open', 'click') then
    raise exception 'kind is open or click' using errcode = '22023', hint = 'MAIL_TRACKING_INVALID';
  end if;
  select y."id" as id, y."tenant_id" as tenant, y."account_id" as account, y."thread_id" as thread,
    y."template_version_id" as template, y."opened_at" as opened, x."user_id" as owner
  into v_message
  from "better_supabase"."mail_messages" y join "better_supabase"."mail_accounts" x on x."id" = y."account_id"
  where y."tracking_hash" = lower(track_mail.hash) and y."direction" = 'outbound';
  if v_message.id is null then
    return null;
  end if;
  if track_mail.kind = 'click' then
    update "better_supabase"."mail_tracked_links" u set "click_count" = u."click_count" + 1
    where u."message_id" = v_message.id and u."position" = track_mail.link
    returning u."url" into v_url;
    if v_url is null then
      return null;
    end if;
  end if;
  insert into "better_supabase"."mail_tracking_events" ("tenant_id", "message_id", "kind", "position", "user_agent")
  values (v_message.tenant, v_message.id, track_mail.kind, case when track_mail.kind = 'click' then track_mail.link end, left(track_mail.user_agent, 300))
  returning "id" into v_event;
  update "better_supabase"."mail_messages" y set
    "opened_at" = coalesce(y."opened_at", now()),
    "open_count" = y."open_count" + case when track_mail.kind = 'open' then 1 else 0 end,
    "clicked_at" = case when track_mail.kind = 'click' then coalesce(y."clicked_at", now()) else y."clicked_at" end,
    "click_count" = y."click_count" + case when track_mail.kind = 'click' then 1 else 0 end
  where y."id" = v_message.id;
  if track_mail.kind = 'click' then
    null;
  elsif v_message.opened is null then
    null;
  end if;
  return jsonb_build_object('messageId', v_message.id, 'url', v_url);
end;
$$;
revoke execute on function "better_supabase"."track_mail"(text, text, integer, text) from public, anon, authenticated;
grant execute on function "better_supabase"."track_mail"(text, text, integer, text) to service_role;

-- Per template version, how many messages members sent from shared
-- mailboxes since a time, and how many were opened, clicked and replied to.
create or replace function "better_supabase"."mail_template_stats"(tenant uuid, since timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.can('tenant', mail_template_stats.tenant, 'mail.read'), false) then
    raise exception 'not allowed to read mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('templateVersionId', p.template, 'sent', p.sent, 'opened', p.opened, 'clicked', p.clicked, 'replied', p.replied) order by p.sent desc, p.template), '[]'::jsonb)
    from (
      select y."template_version_id" as template, count(*) as sent, count(y."opened_at") as opened, count(y."clicked_at") as clicked,
        count(*) filter (where exists (
          select 1 from "better_supabase"."mail_messages" r
          where r."thread_id" = y."thread_id" and r."direction" = 'inbound' and r."sent_at" > y."sent_at"
        )) as replied
      from "better_supabase"."mail_messages" y join "better_supabase"."mail_accounts" x on x."id" = y."account_id"
      where y."tenant_id" = mail_template_stats.tenant and y."direction" = 'outbound'
        and y."template_version_id" is not null
        and (x."share" = 'records' or x."user_id" = auth.uid())
        and (mail_template_stats.since is null or y."sent_at" >= mail_template_stats.since)
      group by y."template_version_id"
    ) p
  );
end;
$$;
revoke execute on function "better_supabase"."mail_template_stats"(uuid, timestamptz) from public, anon;
grant execute on function "better_supabase"."mail_template_stats"(uuid, timestamptz) to authenticated, service_role;

-- blocks.mail-sync.api: entry points for the Data API.
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

create or replace function "api"."mail_thread_visible"(thread uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mail_thread_visible"($1) $$;
revoke execute on function "api"."mail_thread_visible"(uuid) from public, anon;
grant execute on function "api"."mail_thread_visible"(uuid) to authenticated, service_role;

create or replace function "api"."connect_mail_account"(tenant uuid, provider text, address text, credential_ref jsonb, share text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."connect_mail_account"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."connect_mail_account"(uuid, text, text, jsonb, text) from public, anon;
grant execute on function "api"."connect_mail_account"(uuid, text, text, jsonb, text) to authenticated, service_role;

create or replace function "api"."update_mail_account"(account uuid, share text, paused boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_mail_account"($1, $2, $3) $$;
revoke execute on function "api"."update_mail_account"(uuid, text, boolean) from public, anon;
grant execute on function "api"."update_mail_account"(uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."disconnect_mail_account"(account uuid, purge boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."disconnect_mail_account"($1, $2) $$;
revoke execute on function "api"."disconnect_mail_account"(uuid, boolean) from public, anon;
grant execute on function "api"."disconnect_mail_account"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."mail_accounts_of"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mail_accounts_of"($1) $$;
revoke execute on function "api"."mail_accounts_of"(uuid) from public, anon;
grant execute on function "api"."mail_accounts_of"(uuid) to authenticated, service_role;

create or replace function "api"."get_mail_account"(account uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_mail_account"($1) $$;
revoke execute on function "api"."get_mail_account"(uuid) from public, anon;
grant execute on function "api"."get_mail_account"(uuid) to authenticated, service_role;

create or replace function "api"."due_mail_accounts"(max_count integer, stale_after interval)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."due_mail_accounts"($1, $2) $$;
revoke execute on function "api"."due_mail_accounts"(integer, interval) from public, anon, authenticated;
grant execute on function "api"."due_mail_accounts"(integer, interval) to service_role;

create or replace function "api"."set_mail_account_status"(account uuid, status text, error text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_mail_account_status"($1, $2, $3) $$;
revoke execute on function "api"."set_mail_account_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."set_mail_account_status"(uuid, text, text) to service_role;

create or replace function "api"."ingest_mail"(account uuid, messages jsonb, next_cursor text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ingest_mail"($1, $2, $3) $$;
revoke execute on function "api"."ingest_mail"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."ingest_mail"(uuid, jsonb, text) to service_role;

create or replace function "api"."record_sent_mail"(account uuid, message jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_sent_mail"($1, $2) $$;
revoke execute on function "api"."record_sent_mail"(uuid, jsonb) from public, anon;
grant execute on function "api"."record_sent_mail"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."link_mail_thread"(thread uuid, subjects jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link_mail_thread"($1, $2) $$;
revoke execute on function "api"."link_mail_thread"(uuid, jsonb) from public, anon;
grant execute on function "api"."link_mail_thread"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."unlink_mail_thread"(thread uuid, subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unlink_mail_thread"($1, $2, $3) $$;
revoke execute on function "api"."unlink_mail_thread"(uuid, text, text) from public, anon;
grant execute on function "api"."unlink_mail_thread"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."mail_threads_of"(subject_type text, subject_id text, before timestamptz, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mail_threads_of"($1, $2, $3, $4) $$;
revoke execute on function "api"."mail_threads_of"(text, text, timestamptz, integer) from public, anon;
grant execute on function "api"."mail_threads_of"(text, text, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."list_mail_threads"(tenant uuid, account uuid, before timestamptz, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_mail_threads"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_mail_threads"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."list_mail_threads"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."get_mail_thread"(thread uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_mail_thread"($1) $$;
revoke execute on function "api"."get_mail_thread"(uuid) from public, anon;
grant execute on function "api"."get_mail_thread"(uuid) to authenticated, service_role;

create or replace function "api"."track_mail"(hash text, kind text, link integer, user_agent text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."track_mail"($1, $2, $3, $4) $$;
revoke execute on function "api"."track_mail"(text, text, integer, text) from public, anon, authenticated;
grant execute on function "api"."track_mail"(text, text, integer, text) to service_role;

create or replace function "api"."mail_template_stats"(tenant uuid, since timestamptz)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mail_template_stats"($1, $2) $$;
revoke execute on function "api"."mail_template_stats"(uuid, timestamptz) from public, anon;
grant execute on function "api"."mail_template_stats"(uuid, timestamptz) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_132_mail_sync.sql
-- better-supabase module: mail-sync
-- @bsb-block-data mail-sync
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
