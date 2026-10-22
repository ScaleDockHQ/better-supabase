-- The composition migrations after this one were generated on branches where
-- the inbox still kept its own inbox_messages table, and inbox_on_core moved
-- its messages onto messaging first. Their SQL functions and data steps read
-- that table, so this puts back an empty one of the same shape. A later
-- reconciling migration drops it again.
create table if not exists "better_supabase"."inbox_messages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "conversation_id" uuid not null,
  "direction" text not null,
  "kind" text not null default 'message',
  "author_type" text not null,
  "author_id" uuid,
  "body" text not null default '',
  "format" text not null default 'text',
  "attachments" jsonb not null default '[]'::jsonb,
  "reactions" jsonb not null default '{}'::jsonb,
  "mentions" uuid[] not null default '{}',
  "external_id" text,
  "reply_to" uuid,
  "metadata" jsonb not null default '{}'::jsonb,
  "created_at" timestamptz not null default clock_timestamp(),
  "edited_at" timestamptz,
  "deleted_at" timestamptz
);

alter table "better_supabase"."inbox_messages" enable row level security;
