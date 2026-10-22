-- better-supabase sql upgrade: steps that run before the schema diff.

-- inbox: version 3 to 4. The inbox moves onto the messaging core: each conversation becomes a core conversation of kind inbox with the same id, messages and notes become core messages with the same ids and their inbox fields in inbox_message_details, participants and read markers become conversation members, files become pending attachments for pending_inbox_files to import, and reactions move to the message.
-- The messaging tables and the inbox details, so the messages can move before the module files run.
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
revoke all on "better_supabase"."conversations" from anon, authenticated;
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
revoke all on "better_supabase"."conversation_members" from anon, authenticated;
grant select on "better_supabase"."conversation_members" to authenticated;
grant all on "better_supabase"."conversation_members" to service_role;

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
create index if not exists messaging_messages_pinned_idx on "better_supabase"."messages" ("conversation_id", "pinned_at" desc) where "pinned_at" is not null;
alter table "better_supabase"."messages" enable row level security;
revoke all on "better_supabase"."messages" from anon, authenticated;
grant select on "better_supabase"."messages" to authenticated;
grant all on "better_supabase"."messages" to service_role;

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
revoke all on "better_supabase"."message_edits" from anon, authenticated;
grant select on "better_supabase"."message_edits" to authenticated;
grant all on "better_supabase"."message_edits" to service_role;

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
revoke all on "better_supabase"."thread_reads" from anon, authenticated;
grant select on "better_supabase"."thread_reads" to authenticated;
grant all on "better_supabase"."thread_reads" to service_role;
alter table "better_supabase"."messages" add column if not exists "kind" text not null default 'message' check ("kind" in ('message', 'note'));
create table if not exists "better_supabase"."inbox_message_details" (
  "message_id" uuid primary key,
  "tenant_id" uuid not null,
  "conversation_id" uuid not null references "better_supabase"."inbox_conversations" ("id") on delete cascade,
  "direction" text not null check ("direction" in ('inbound', 'outbound')),
  "author_type" text not null check ("author_type" in ('contact', 'agent', 'bot', 'system')),
  "format" text not null default 'text' check ("format" in ('text', 'markdown')),
  "external_id" text,
  "reply_to" uuid,
  "metadata" jsonb not null default '{}'::jsonb
);
create unique index if not exists inbox_message_details_external_idx on "better_supabase"."inbox_message_details" ("conversation_id", "external_id") where "external_id" is not null;
create index if not exists inbox_message_details_conversation_idx on "better_supabase"."inbox_message_details" ("conversation_id");
create index if not exists inbox_message_details_reply_idx on "better_supabase"."inbox_message_details" ("reply_to") where "reply_to" is not null;

do $$
begin
  if to_regclass('"better_supabase".inbox_messages') is null then
    return;
  end if;
  if to_regclass('"better_supabase"."attachments"') is null
    and exists (select 1 from "better_supabase".inbox_messages x where x.attachments <> '[]'::jsonb) then
    raise exception 'inbox: messages have files and the attachments table is missing'
      using hint = 'apply the attachments module first, then run sql upgrade again';
  end if;
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "last_message_at", "created_at")
  select v."id", v."tenant_id", 'inbox', 'tenant', v."last_message_at", v."created_at"
  from "better_supabase"."inbox_conversations" v
  on conflict do nothing;
  insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "author_id", "kind", "body", "mentions", "sent_at", "edited_at", "deleted_at", "created_at")
  select x.id, x.tenant_id, x.conversation_id, x.author_id, x.kind, left(x.body, 40000), x.mentions, x.created_at, x.edited_at, x.deleted_at, x.created_at
  from "better_supabase".inbox_messages x
  order by x.created_at, x.id
  on conflict do nothing;
  insert into "better_supabase"."inbox_message_details" ("message_id", "tenant_id", "conversation_id", "direction", "author_type", "format", "external_id", "reply_to", "metadata")
  select x.id, x.tenant_id, x.conversation_id, x.direction, x.author_type, x.format, x.external_id, x.reply_to, x.metadata
  from "better_supabase".inbox_messages x
  on conflict do nothing;
  insert into "better_supabase"."conversation_members" as k ("conversation_id", "tenant_id", "user_id", "last_read_at")
  select u.conversation, v."tenant_id", u.member, max(u.read_at)
  from (
    select p.conversation_id as conversation, p.user_id as member, null::timestamptz as read_at from "better_supabase".conversation_participants p
    union all
    select r.conversation_id, r.user_id, r.last_read_at from "better_supabase".conversation_reads r
    union all
    select x.conversation_id, x.author_id, null from "better_supabase".inbox_messages x where x.author_id is not null
    union all
    select w."id", c."user_id", null from "better_supabase"."inbox_conversations" w
    join "better_supabase"."contacts" c on c."id" = w."contact_id" where c."user_id" is not null
  ) u
  join "better_supabase"."inbox_conversations" v on v."id" = u.conversation
  where exists (select 1 from auth.users z where z.id = u.member)
  group by u.conversation, v."tenant_id", u.member
  on conflict ("conversation_id", "user_id") do update
    set "last_read_at" = greatest(k."last_read_at", excluded."last_read_at");
  if to_regclass('"better_supabase"."attachments"') is not null then
    insert into "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id", "name", "mime_type", "size", "uploaded_by", "scan_detail", "created_at")
    select x.tenant_id, 'message', x.id::text,
      left(coalesce(nullif(f ->> 'name', ''), 'file'), 255),
      case when lower(f ->> 'content_type') ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$' then lower(f ->> 'content_type') else 'application/octet-stream' end,
      coalesce((f ->> 'size')::bigint, 0),
      null,
      jsonb_build_object('source', case when f ? 'path'
        then jsonb_build_object('bucket', 'inbox-files', 'path', f ->> 'path', 'name', f ->> 'name', 'content_type', f ->> 'content_type', 'size', f -> 'size')
        else f end)::text,
      x.created_at
    from "better_supabase".inbox_messages x
    cross join lateral jsonb_array_elements(x.attachments) f
    where x.deleted_at is null and jsonb_typeof(f) = 'object' and (f ? 'path' or f ? 'url');
  end if;
  update "better_supabase"."reactions" x set "subject_type" = 'message' where x."subject_type" = 'inbox_message';
  perform set_config('better_supabase.bs_reactions_backfill', 'on', true);
  insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "emoji")
  select x.tenant_id, 'message', x.id::text, w.actor,
    case when w.actor ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then w.actor::uuid end,
    e.key
  from "better_supabase".inbox_messages x
  cross join lateral jsonb_each(x.reactions) e
  cross join lateral jsonb_array_elements_text(e.value) w(actor)
  where jsonb_typeof(e.value) = 'array' and length(e.key) between 1 and 64 and e.key !~ '\s' and e.key !~ '^:[a-z0-9_+-]{1,32}:$'
  on conflict do nothing;
  perform set_config('better_supabase.bs_reactions_backfill', '', true);
  drop table if exists "better_supabase".inbox_mentions cascade;
  drop table if exists "better_supabase".conversation_reads cascade;
  drop table if exists "better_supabase".conversation_participants cascade;
  drop table "better_supabase".inbox_messages cascade;
  alter table "better_supabase"."inbox_conversations" alter column "id" drop default;
end;
$$;
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists "bs_inbox_files_read" on storage.objects;
    drop policy if exists "bs_inbox_files_write" on storage.objects;
  end if;
end;
$$;
drop function if exists "better_supabase".react_to_message(uuid, text, boolean, text);
drop function if exists "better_supabase".set_inbox_typing(uuid, boolean, text);
drop function if exists "better_supabase".inbox_file_allowed(text, boolean);
drop function if exists "better_supabase".inbox_read_broadcast();
drop function if exists "better_supabase".inbox_contact_conversation_ids();
drop function if exists "better_supabase".inbox_add_message(uuid, jsonb, text, uuid, text);
