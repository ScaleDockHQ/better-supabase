-- better-supabase sql upgrade: steps that run before the schema diff.

-- comments: version 7 to 8. Comments move onto the messaging core: each record's comments become its subject conversation, comments become messages with the same ids, reactions and files on a comment move to the message, and the comments table and its functions go. The activity feed moves to the activity module with its table.
-- The messaging tables, so the comments can move before the module files run.
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

do $$
declare
  v_column text;
begin
  if to_regclass('"better_supabase".comments') is null then
    return;
  end if;
  insert into "better_supabase"."conversations" ("tenant_id", "kind", "access", "subject_type", "subject_id", "created_by", "last_message_at", "created_at")
  select x.organization_id, 'subject', 'subject', x.subject_type, x.subject_id,
    (array_agg(x.author_id order by x.created_at, x.id))[1],
    max(x.created_at) filter (where x.deleted_at is null), min(x.created_at)
  from "better_supabase".comments x
  group by x.organization_id, x.subject_type, x.subject_id
  on conflict do nothing;
  with recursive tree as (
    select c.id, c.id as root from "better_supabase".comments c where c.parent_id is null
    union all
    select c.id, t.root from "better_supabase".comments c join tree t on c.parent_id = t.id
  )
  insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "mentions", "sent_at", "edited_at", "deleted_at", "created_at")
  select x.id, x.organization_id, v."id", x.parent_id, case when x.parent_id is null then null else t.root end,
    x.author_id, x.body, x.document, x.mentions, x.created_at, x.edited_at, x.deleted_at, x.created_at
  from "better_supabase".comments x
  join tree t on t.id = x.id
  join "better_supabase"."conversations" v on v."tenant_id" = x.organization_id and v."kind" = 'subject'
    and v."subject_type" = x.subject_type and v."subject_id" = x.subject_id
  order by x.created_at, x.id
  on conflict do nothing;
  update "better_supabase"."messages" r set
    "reply_count" = (select count(*) from "better_supabase"."messages" x where x."thread_id" = r."id" and x."deleted_at" is null),
    "last_reply_at" = (select max(x."sent_at") from "better_supabase"."messages" x where x."thread_id" = r."id" and x."deleted_at" is null),
    "reply_user_ids" = array(
      select y.u from (
        select x."author_id" as u, min(x."sent_at") as first
        from "better_supabase"."messages" x
        where x."thread_id" = r."id" and x."deleted_at" is null and x."author_id" is not null
        group by x."author_id"
      ) y order by y.first limit 3
    )
  where r."id" in (select c.parent_id from "better_supabase".comments c where c.parent_id is not null);
  -- Extra columns the comments and the messages share by name.
  for v_column in
    select a.attname from pg_attribute a
    where a.attrelid = '"better_supabase".comments'::regclass and a.attnum > 0 and not a.attisdropped
      and not a.attname = any ('{id,organization_id,subject_type,subject_id,author_id,body,document,mentions,parent_id,created_at,edited_at,deleted_at}'::text[])
      and exists (
        select 1 from pg_attribute b
        where b.attrelid = '"better_supabase"."messages"'::regclass and b.attname = a.attname and not b.attisdropped
      )
  loop
    execute format('update %s m set %I = c.%I from %s c where c.id = m.id', '"better_supabase"."messages"', v_column, v_column, '"better_supabase".comments');
  end loop;
  if to_regclass('"better_supabase"."reactions"') is not null then
    update "better_supabase"."reactions" x set "subject_type" = 'message' where x."subject_type" = 'comment';
  end if;
  if to_regclass('"better_supabase"."attachments"') is not null then
    update "better_supabase"."attachments" x set "subject_type" = 'message' where x."subject_type" = 'comment';
  end if;
  drop table "better_supabase".comments cascade;
end;
$$;
drop function if exists "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb);
drop function if exists "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb, jsonb);
drop function if exists "better_supabase"."edit_comment"(uuid, text, uuid[], jsonb, boolean);
drop function if exists "better_supabase"."edit_comment"(uuid, text, uuid[], jsonb, boolean, jsonb);
drop function if exists "better_supabase"."delete_comment"(uuid);
drop function if exists "better_supabase"."comment_subject_readable"(text, text, uuid);
drop function if exists "better_supabase"."comment_authors"(uuid[]);
drop function if exists "better_supabase"."comments_before_write"();
drop function if exists "better_supabase"."comments_after_write"();
