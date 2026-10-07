-- better-supabase module: comments (0.5.1)
-- @bs-module comments@3 managed
-- Comments on any subject in a tenant, with replies, mentions that notify (with the notifications module) and comment.* outbox events, plus an activity_entries feed that activitySink() fills from outbox events.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Comments on any subject in a tenant. options.subjects maps each subject
-- type to its table, so the policies require that the caller can read the
-- subject; without it any subject type is accepted.
create table if not exists "better_supabase"."comments" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "author_id" uuid references auth.users (id) on delete set null default auth.uid(),
  "body" text not null check (length("body") <= 10000),
  "document" jsonb,
  "mentions" uuid[] not null default '{}',
  "parent_id" uuid references "better_supabase"."comments" ("id") on delete cascade,
  -- clock_timestamp keeps a thread in order within one transaction.
  "created_at" timestamptz not null default clock_timestamp(),
  "edited_at" timestamptz,
  "deleted_at" timestamptz,
  check ("deleted_at" is not null or length(btrim("body")) > 0)
);
alter table "better_supabase"."comments" add column if not exists "document" jsonb;
create index if not exists comments_subject_idx on "better_supabase"."comments" ("organization_id", "subject_type", "subject_id", "created_at");
create index if not exists comments_author_idx on "better_supabase"."comments" ("author_id");
create index if not exists comments_parent_idx on "better_supabase"."comments" ("parent_id");
alter table "better_supabase"."comments" enable row level security;
revoke all on "better_supabase"."comments" from anon, authenticated;
grant select on "better_supabase"."comments" to authenticated;
grant insert ("organization_id", "subject_type", "subject_id", "body", "document", "mentions", "parent_id") on "better_supabase"."comments" to authenticated;
grant update ("body", "document", "mentions", "deleted_at") on "better_supabase"."comments" to authenticated;
grant all on "better_supabase"."comments" to service_role;

-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission.
create or replace function "better_supabase"."comment_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select true
$$;

drop policy if exists "comments_read" on "better_supabase"."comments";
create policy "comments_read" on "better_supabase"."comments" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('comments.read')));
drop policy if exists "comments_insert" on "better_supabase"."comments";
create policy "comments_insert" on "better_supabase"."comments" for insert to authenticated
  with check (
    "author_id" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'comments.create'), false)
  );
drop policy if exists "comments_update" on "better_supabase"."comments";
create policy "comments_update" on "better_supabase"."comments" for update to authenticated
  using ("author_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('comments.moderate')))
  with check ("author_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('comments.moderate')));

-- Keeps mentions to distinct members other than the author, a reply on its
-- parent's subject, and edited_at; a deleted comment keeps no body.
create or replace function "better_supabase"."comments_before_write"()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old."deleted_at" is not null then
    raise exception 'This comment was deleted' using errcode = 'P0001', hint = 'COMMENT_DELETED';
  end if;
  if new."deleted_at" is not null then
    new."body" := '';
    new."document" := null;
    new."mentions" := '{}';
    return new;
  end if;
  new."mentions" := array(
    select distinct x from unnest(new."mentions") x
    where x is not null and x is distinct from new."author_id"
    order by x
  );
  if tg_op = 'INSERT' and new."parent_id" is not null and not exists (
    select 1 from "better_supabase"."comments" p
    where p."id" = new."parent_id" and p."organization_id" = new."organization_id"
      and p."subject_type" = new."subject_type" and p."subject_id" = new."subject_id"
  ) then
    raise exception 'A reply must be on its parent''s subject' using errcode = '23514', hint = 'COMMENT_PARENT_MISMATCH';
  end if;
  if tg_op = 'UPDATE' and (new."body" is distinct from old."body" or new."document" is distinct from old."document" or new."mentions" is distinct from old."mentions") then
    if old."author_id" is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
      raise exception 'Only the author edits a comment' using errcode = '42501', hint = 'COMMENT_NOT_AUTHOR';
    end if;
    new."edited_at" := now();
  end if;
  return new;
end;
$$;
drop trigger if exists "bs_comments_before_write" on "better_supabase"."comments";
create trigger "bs_comments_before_write"
  before insert or update on "better_supabase"."comments"
  for each row execute function "better_supabase"."comments_before_write"();

-- Without notifications or the outbox there is nothing to send after a write.
drop trigger if exists "bs_comments_after_write" on "better_supabase"."comments";
drop function if exists "better_supabase"."comments_after_write"();

-- The functions run as the caller, so the policies above decide.
drop function if exists "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid);
drop function if exists "better_supabase"."edit_comment"(uuid, text, uuid[]);
create or replace function "better_supabase"."create_comment"(
  tenant uuid,
  subject_type text,
  subject_id text,
  body text,
  mentions uuid[] default '{}',
  parent uuid default null,
  document jsonb default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into "better_supabase"."comments" as x ("organization_id", "subject_type", "subject_id", "body", "document", "mentions", "parent_id")
  values (create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body, create_comment.document, coalesce(create_comment.mentions, '{}'), create_comment.parent)
  returning to_jsonb(x.*)
$$;

-- An edit keeps the document unless one is passed or clear_document is true.
create or replace function "better_supabase"."edit_comment"(id uuid, body text, mentions uuid[] default null, document jsonb default null, clear_document boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  update "better_supabase"."comments" x
  set "body" = edit_comment.body,
      "document" = case
        when coalesce(edit_comment.clear_document, false) then null
        else coalesce(edit_comment.document, x."document")
      end,
      "mentions" = coalesce(edit_comment.mentions, x."mentions")
  where x."id" = edit_comment.id
  returning to_jsonb(x.*)
$$;

-- Copies a subject's thread to another subject in the same tenant (a quote
-- duplicated into an invoice, say), keeping authors, times and replies.
-- Service role only: call it from the code that duplicates the record,
-- after it checked the caller may read both.
create or replace function "better_supabase"."copy_comments"(
  tenant uuid,
  from_type text,
  from_id text,
  to_type text,
  to_id text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  copied integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role copies comments' using errcode = '42501', hint = 'COMMENT_FORBIDDEN';
  end if;
  with copies as materialized (
    select y."id" as old_id, gen_random_uuid() as new_id
    from "better_supabase"."comments" y
    where y."organization_id" = copy_comments.tenant
      and y."subject_type" = copy_comments.from_type
      and y."subject_id" = copy_comments.from_id
  ), inserted as (
    insert into "better_supabase"."comments" ("id", "organization_id", "subject_type", "subject_id", "author_id", "body", "document", "mentions", "parent_id", "created_at", "edited_at", "deleted_at")
    select m.new_id, y."organization_id", copy_comments.to_type, copy_comments.to_id, y."author_id",
      y."body", y."document", '{}', p.new_id, y."created_at", y."edited_at", y."deleted_at"
    from "better_supabase"."comments" y
    join copies m on m.old_id = y."id"
    left join copies p on p.old_id = y."parent_id"
    order by y."created_at", y."id"
    returning 1
  )
  select count(*)::integer into copied from inserted;
  return copied;
end;
$$;

create or replace function "better_supabase"."delete_comment"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    update "better_supabase"."comments" x set "deleted_at" = now()
    where x."id" = delete_comment.id and x."deleted_at" is null
    returning 1
  )
  select exists (select 1 from removed)
$$;

-- A subject's thread, oldest first; deleted comments stay as placeholders
-- so replies keep their parent. Page with after (a cursor) or skip (an offset).
drop function if exists "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer);
create or replace function "better_supabase"."list_comments"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."created_at", x."id"), '[]'::jsonb)
  from (
    select * from "better_supabase"."comments" y
    where y."organization_id" = list_comments.tenant
      and y."subject_type" = list_comments.subject_type
      and y."subject_id" = list_comments.subject_id
      and (list_comments.after is null or y."created_at" > list_comments.after)
    order by y."created_at", y."id"
    limit least(greatest(coalesce(list_comments.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ) x
$$;

-- Comments per subject the caller can read, for counters in a list:
-- { subject_id: count }, deleted comments left out. Runs as the caller.
create or replace function "better_supabase"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.subject_id, x.n), '{}'::jsonb)
  from (
    select y."subject_id" as subject_id, count(*) as n
    from "better_supabase"."comments" y
    where y."organization_id" = comment_counts.tenant
      and y."subject_type" = comment_counts.subject_type
      and y."subject_id" = any (comment_counts.subject_ids)
      and y."deleted_at" is null
    group by 1
  ) x
$$;

-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists "better_supabase"."activity_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "event_id" text not null unique,
  "type" text not null,
  "actor_id" uuid references auth.users (id) on delete set null,
  "subject_type" text,
  "subject_id" text,
  "summary" text,
  "data" jsonb not null default '{}'::jsonb,
  "occurred_at" timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on "better_supabase"."activity_entries" ("organization_id", "occurred_at" desc, "id" desc);
create index if not exists activity_entries_subject_idx on "better_supabase"."activity_entries" ("organization_id", "subject_type", "subject_id");
create index if not exists activity_entries_actor_idx on "better_supabase"."activity_entries" ("actor_id");
alter table "better_supabase"."activity_entries" enable row level security;
revoke all on "better_supabase"."activity_entries" from anon, authenticated;
grant select on "better_supabase"."activity_entries" to authenticated;
grant all on "better_supabase"."activity_entries" to service_role;
drop policy if exists "activity_entries_read" on "better_supabase"."activity_entries";
create policy "activity_entries_read" on "better_supabase"."activity_entries" for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('activity.read')));

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function "better_supabase"."record_activity"(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into "better_supabase"."activity_entries" ("event_id", "organization_id", "type", "actor_id", "subject_type", "subject_id", "summary", "data", "occurred_at")
  select e ->> 'event_id', (e ->> 'organization_id')::uuid, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict ("event_id") do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back. Runs as the caller.
create or replace function "better_supabase"."list_activity"(
  tenant uuid,
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x."occurred_at" desc, x."id" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit least(greatest(coalesce(list_activity.max_rows, 50), 1), 500)
  ) x
$$;

revoke execute on function "better_supabase"."comment_subject_readable"(text, text, uuid) from public, anon;
revoke execute on function "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb) from public, anon;
revoke execute on function "better_supabase"."edit_comment"(uuid, text, uuid[], jsonb, boolean) from public, anon;
revoke execute on function "better_supabase"."copy_comments"(uuid, text, text, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer) from public, anon;
revoke execute on function "better_supabase"."delete_comment"(uuid) from public, anon;
revoke execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer) from public, anon;
revoke execute on function "better_supabase"."comment_counts"(uuid, text, text[]) from public, anon;
revoke execute on function "better_supabase"."record_activity"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."comment_subject_readable"(text, text, uuid) to authenticated, service_role;
grant execute on function "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."edit_comment"(uuid, text, uuid[], jsonb, boolean) to authenticated, service_role;
grant execute on function "better_supabase"."copy_comments"(uuid, text, text, text, text) to service_role;
grant execute on function "better_supabase"."list_activity"(uuid, text, text, timestamptz, integer) to authenticated, service_role;
grant execute on function "better_supabase"."delete_comment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer) to authenticated, service_role;
grant execute on function "better_supabase"."comment_counts"(uuid, text, text[]) to authenticated, service_role;
grant execute on function "better_supabase"."record_activity"(jsonb) to service_role;

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
