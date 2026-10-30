-- better-supabase module: comments
-- @bsb-block comments@8 managed
-- @bsb-hash sha256:a5fcc07da00b052016b7b5fba9fa82a2c5a2709e40d1b2b13385c3a6d3b3348b
-- Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."comment_tasks";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."comment_tasks";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."comment_tasks";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."comment_tasks";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."comment_tasks";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Comments are a record's conversation (kind subject) on the messaging core:
-- whoever reads the record reads its comments. These functions open it,
-- expand mention groups, list a record's thread flat with its record, and
-- copy it; edits, deletes, pins, resolving and read markers go through the
-- messaging functions (edit_message, delete_message, pin_message,
-- resolve_message, mark_read). Every function is PL/pgSQL because the
-- messaging tables come later in the schema.

-- The work item a comment was turned into (assign_comment).
create table if not exists "better_supabase"."comment_tasks" (
  "message_id" uuid primary key,
  "organization_id" uuid not null,
  "task_id" uuid not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now()
);
create index if not exists comment_tasks_task_idx on "better_supabase"."comment_tasks" ("task_id");
alter table "better_supabase"."comment_tasks" enable row level security;
revoke all on "better_supabase"."comment_tasks" from public, anon, authenticated;
grant select on "better_supabase"."comment_tasks" to authenticated;
grant insert ("message_id", "organization_id", "task_id") on "better_supabase"."comment_tasks" to authenticated;
grant all on "better_supabase"."comment_tasks" to service_role;

-- Whether the caller reads a message in this tenant: the messages policy
-- decides.
drop function if exists "better_supabase"."comment_message_readable"(uuid);
create or replace function "better_supabase"."comment_message_readable"(message uuid, tenant uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return exists (
    select 1 from "better_supabase"."messages" x
    where x."id" = comment_message_readable.message and x."tenant_id" = comment_message_readable.tenant
  );
end;
$$;
revoke execute on function "better_supabase"."comment_message_readable"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."comment_message_readable"(uuid, uuid) to authenticated, service_role;

drop policy if exists comment_tasks_read on "better_supabase"."comment_tasks";
create policy comment_tasks_read on "better_supabase"."comment_tasks"
  for select to authenticated
  using ("better_supabase"."comment_message_readable"("message_id", "organization_id"));
drop policy if exists comment_tasks_insert on "better_supabase"."comment_tasks";
create policy comment_tasks_insert on "better_supabase"."comment_tasks"
  for insert to authenticated
  with check (("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "organization_id")) and (select better_supabase.actor_may_write()));

-- A record's conversation, or null before its first comment.
create or replace function "better_supabase"."comment_conversation"(tenant uuid, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select c."id" into v_id from "better_supabase"."conversations" c
  where c."tenant_id" = comment_conversation.tenant and c."kind" = 'subject'
    and c."subject_type" = comment_conversation.subject_type and c."subject_id" = comment_conversation.subject_id;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."comment_conversation"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."comment_conversation"(uuid, text, text) to authenticated, service_role;

-- Messages as comments: each with its record and the work item it became.
create or replace function "better_supabase"."comments_json"(ids uuid[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c."subject_type",
      'subject_id', c."subject_id",
      'task_id', t."task_id"
    ) order by e.n), '[]'::jsonb)
    from jsonb_array_elements("better_supabase"."messaging_messages_json"(comments_json.ids)) with ordinality e(row, n)
    join "better_supabase"."conversations" c on c."id" = (e.row ->> 'conversation_id')::uuid
    left join "better_supabase"."comment_tasks" t on t."message_id" = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."comments_json"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comments_json"(uuid[]) to authenticated, service_role;

-- One comment the caller reads, or null.
create or replace function "better_supabase"."get_comment"(message uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return "better_supabase"."comments_json"(array[get_comment.message]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."get_comment"(uuid) from public, anon;
grant execute on function "better_supabase"."get_comment"(uuid) to authenticated, service_role;

-- Comments on a record. attrs: parentId (a reply; one level, so a reply to
-- a reply joins the root), document, anchor (where on the record it points),
-- mentions (user ids) and fields (the messaging extra
-- columns). attachments: files the caller uploaded to the conversation.
drop function if exists "better_supabase"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb);
create or replace function "better_supabase"."create_comment"(
  tenant uuid,
  subject_type text,
  subject_id text,
  body text,
  attrs jsonb default '{}',
  attachments uuid[] default '{}'
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_conv uuid;
  v_raw uuid[];
  v_mentions uuid[];
  v_msg jsonb;
begin
  v_conv := ("better_supabase"."open_conversation"(
    create_comment.tenant,
    'subject',
    jsonb_build_object('subjectType', create_comment.subject_type, 'subjectId', create_comment.subject_id),
    '{}'::uuid[]
  ) ->> 'id')::uuid;
  v_raw := array(
    select (jsonb_array_elements_text(coalesce(create_comment.attrs -> 'mentions', '[]'::jsonb)))::uuid
  );
  v_mentions := array(select distinct e.x from (
    select x from unnest(v_raw) x
  ) e(x) where e.x is not null);
  v_msg := "better_supabase"."send_message"(
    v_conv,
    create_comment.body,
    (coalesce(create_comment.attrs, '{}') - 'mentions' - 'broadcast' - 'scheduledFor') || jsonb_build_object('mentions', to_jsonb(v_mentions)),
    coalesce(create_comment.attachments, '{}')
  );
  perform "better_supabase"."comment_sent"((v_msg ->> 'id')::uuid);
  return "better_supabase"."comments_json"(array[(v_msg ->> 'id')::uuid]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) to authenticated, service_role;

-- After create_comment sends: the author and the mentioned members follow
-- the record (participating; a level they chose stays), and its followers
-- hear of the comment. Only the author of a sent message on a record calls
-- it with effect.
create or replace function "better_supabase"."comment_sent"(message uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg record;
  v_conv record;
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" x
  where x."id" = comment_sent.message and x."author_id" = auth.uid()
    and x."sent_at" is not null and x."deleted_at" is null;
  if not found then
    return;
  end if;
  select * into v_conv from "better_supabase"."conversations" c
  where c."id" = v_msg."conversation_id" and c."kind" = 'subject';
  if not found then
    return;
  end if;
  foreach v_user in array array(select distinct x from unnest(array[v_msg."author_id"] || v_msg."mentions") x where x = v_msg."author_id" or coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)) loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_conv."tenant_id", v_user, v_conv."subject_type", v_conv."subject_id", 'participating')
    on conflict do nothing;
  end loop;
  if (exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."subject_type" = v_conv."subject_type" and s."subject_id" = v_conv."subject_id" and s."organization_id" = v_conv."tenant_id"
        and s."level" in ('all', 'participating')
        and not s."user_id" = any (array[v_msg."author_id"] || v_msg."mentions")
    ) or to_regprocedure('"public"."notification_audience"(jsonb)') is not null) then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.posted',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', v_conv."subject_type",
      'subject_id', v_conv."subject_id",
      'subject_label', "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id"),
      'summary', left(v_msg."body", 140),
      'recipients', '[]'::jsonb,
      'exclude', to_jsonb(v_msg."mentions"),
      'key', 'comment.posted:' || v_msg."id"::text,
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
end;
$$;
revoke execute on function "better_supabase"."comment_sent"(uuid) from public, anon;
grant execute on function "better_supabase"."comment_sent"(uuid) to authenticated, service_role;

-- A record's comments and replies in one list, oldest first; deleted ones
-- stay as placeholders so replies keep their parent. Page with after and
-- after_id (the last comment's sent_at and id) or skip (an offset).
create or replace function "better_supabase"."list_comments"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  perform "better_supabase"."record_subject_read"(list_comments.subject_type, list_comments.subject_id, null, 'comments', 'list_comments');
  return "better_supabase"."comments_json"(array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (list_comments.after is null
        or (x."sent_at", x."id") > (list_comments.after, coalesce(list_comments.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ));
end;
$$;
revoke execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid) from public, anon;
grant execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid) to authenticated, service_role;

-- The top-level comments anchored to a file, oldest first: on its pages,
-- regions and moments, on any record the caller can read.
create or replace function "better_supabase"."list_file_comments"(attachment uuid, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return "better_supabase"."comments_json"(array(
    select x."id" from "better_supabase"."messages" x
    join "better_supabase"."conversations" c on c."id" = x."conversation_id" and c."kind" = 'subject'
    where x."anchor" ->> 'kind' = 'file'
      and x."anchor" ->> 'attachmentId' = list_file_comments.attachment::text
      and x."sent_at" is not null and x."deleted_at" is null
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_file_comments.max_rows, 100), 1), 500)
  ));
end;
$$;
revoke execute on function "better_supabase"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_file_comments"(uuid, integer) to authenticated, service_role;

-- Comments per record the caller can read, for counters in a list:
-- { subject_id: count }, deleted ones left out.
create or replace function "better_supabase"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    select coalesce(jsonb_object_agg(s.subject_id, s.n), '{}'::jsonb)
    from (
      select c."subject_id" as subject_id, count(*) as n
      from "better_supabase"."conversations" c
      join "better_supabase"."messages" x on x."conversation_id" = c."id"
      where c."tenant_id" = comment_counts.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_counts.subject_type
        and c."subject_id" = any (comment_counts.subject_ids)
        and x."sent_at" is not null and x."deleted_at" is null
      group by 1
    ) s
  );
end;
$$;
revoke execute on function "better_supabase"."comment_counts"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."comment_counts"(uuid, text, text[]) to authenticated, service_role;

-- Copies a record's comments to another record in the same tenant (a quote
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
  v_from uuid;
  v_to uuid;
  v_copied integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role copies comments' using errcode = '42501', hint = 'COMMENT_FORBIDDEN';
  end if;
  select c."id" into v_from from "better_supabase"."conversations" c
  where c."tenant_id" = copy_comments.tenant and c."kind" = 'subject'
    and c."subject_type" = copy_comments.from_type and c."subject_id" = copy_comments.from_id;
  if v_from is null then
    return 0;
  end if;
  insert into "better_supabase"."conversations" ("tenant_id", "kind", "access", "subject_type", "subject_id")
  values (copy_comments.tenant, 'subject', 'subject', copy_comments.to_type, copy_comments.to_id)
  on conflict do nothing;
  select c."id" into v_to from "better_supabase"."conversations" c
  where c."tenant_id" = copy_comments.tenant and c."kind" = 'subject'
    and c."subject_type" = copy_comments.to_type and c."subject_id" = copy_comments.to_id;
  with copies as materialized (
    select y."id" as old_id, gen_random_uuid() as new_id
    from "better_supabase"."messages" y
    where y."conversation_id" = v_from and y."sent_at" is not null
  ), inserted as (
    insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor", "mentions", "reply_count", "last_reply_at", "reply_user_ids", "sent_at", "edited_at", "deleted_at", "created_at")
    select n.new_id, y."tenant_id", v_to, p.new_id, r.new_id, y."author_id",
      y."body", y."document", y."anchor", y."mentions", y."reply_count", y."last_reply_at", y."reply_user_ids", y."sent_at", y."edited_at", y."deleted_at", y."created_at"
    from "better_supabase"."messages" y
    join copies n on n.old_id = y."id"
    left join copies p on p.old_id = y."parent_id"
    left join copies r on r.old_id = y."thread_id"
    order by y."sent_at", y."id"
    returning 1
  )
  select count(*)::integer into v_copied from inserted;
  return v_copied;
end;
$$;
revoke execute on function "better_supabase"."copy_comments"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."copy_comments"(uuid, text, text, text, text) to service_role;

-- Turns a comment into a work item: the title (attrs.title, else the
-- comment's first 120 characters), its body, and assignee when given; the
-- other attrs go to create_task. A comment links to one work item;
-- assigning it again returns that one's id.
create or replace function "better_supabase"."assign_comment"(message uuid, assignee uuid default null, attrs jsonb default '{}')
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_msg record;
  v_task uuid;
begin
  select * into v_msg from "better_supabase"."messages" x
  where x."id" = assign_comment.message and x."sent_at" is not null and x."deleted_at" is null;
  if not found then
    raise exception 'no comment you can read has this id' using errcode = 'P0002', hint = 'COMMENT_NOT_FOUND';
  end if;
  select t."task_id" into v_task from "better_supabase"."comment_tasks" t where t."message_id" = v_msg."id";
  if found then
    return v_task;
  end if;
  v_task := ("better_supabase"."create_task"(
    v_msg."tenant_id",
    (coalesce(assign_comment.attrs, '{}') - 'title') || jsonb_build_object(
      'title', coalesce(nullif(trim(assign_comment.attrs ->> 'title'), ''), left(v_msg."body", 120)),
      'body', coalesce(assign_comment.attrs ->> 'body', v_msg."body")
    ),
    case when assign_comment.assignee is null then '{}'::uuid[] else array[assign_comment.assignee] end
  ) ->> 'id')::uuid;
  insert into "better_supabase"."comment_tasks" ("message_id", "organization_id", "task_id")
  values (v_msg."id", v_msg."tenant_id", v_task);
  return v_task;
end;
$$;
revoke execute on function "better_supabase"."assign_comment"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."assign_comment"(uuid, uuid, jsonb) to authenticated, service_role;
-- on with cascade: deleting a subject row deletes its comments rows.
create or replace function "better_supabase"."comments_subject_deleted"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
  v_tenant text := case when tg_nargs > 2 then to_jsonb(old) ->> tg_argv[2] end;
begin
  delete from "better_supabase"."conversations" c where c."kind" = 'subject' and c."subject_type" = v_type and c."subject_id" = v_id and (v_tenant is null or c."tenant_id"::text = v_tenant);
  return null;
end;
$$;
revoke execute on function "better_supabase"."comments_subject_deleted"() from public, anon, authenticated;

drop trigger if exists "bsb_comments_product_cascade" on "better_supabase"."products";
create trigger "bsb_comments_product_cascade"
  after delete on "better_supabase"."products"
  for each row execute function "better_supabase"."comments_subject_deleted"('product', 'id', 'tenant_id');

drop trigger if exists "bsb_comments_product_variant_cascade" on "better_supabase"."product_variants";
create trigger "bsb_comments_product_variant_cascade"
  after delete on "better_supabase"."product_variants"
  for each row execute function "better_supabase"."comments_subject_deleted"('product_variant', 'id', 'tenant_id');

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
drop policy if exists bsb_tenant_scope on "better_supabase"."comment_tasks";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."comment_tasks";
create policy bsb_tenant_scope_select on "better_supabase"."comment_tasks" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("better_supabase"."comment_message_readable"("message_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."comment_tasks";
create policy bsb_tenant_scope_insert on "better_supabase"."comment_tasks" as restrictive
  for insert to public
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_update on "better_supabase"."comment_tasks";
create policy bsb_tenant_scope_update on "better_supabase"."comment_tasks" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."comment_tasks";
create policy bsb_tenant_scope_delete on "better_supabase"."comment_tasks" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

-- blocks.comments.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."comment_message_readable"(uuid, uuid);
drop function if exists "api"."comments_json"(uuid[]);
drop function if exists "api"."comment_sent"(uuid);

drop function if exists "api"."create_comment"(uuid, text, text, text, uuid[], uuid, jsonb);

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

create or replace function "api"."comment_conversation"(tenant uuid, subject_type text, subject_id text)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."comment_conversation"($1, $2, $3) $$;
revoke execute on function "api"."comment_conversation"(uuid, text, text) from public, anon;
grant execute on function "api"."comment_conversation"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."get_comment"(message uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_comment"($1) $$;
revoke execute on function "api"."get_comment"(uuid) from public, anon;
grant execute on function "api"."get_comment"(uuid) to authenticated, service_role;

create or replace function "api"."create_comment"(tenant uuid, subject_type text, subject_id text, body text, attrs jsonb default '{}', attachments uuid[] default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_comment"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."create_comment"(uuid, text, text, text, jsonb, uuid[]) from public, anon;
grant execute on function "api"."create_comment"(uuid, text, text, text, jsonb, uuid[]) to authenticated, service_role;

create or replace function "api"."list_comments"(tenant uuid, subject_type text, subject_id text, after timestamptz default null, max_rows integer default 100, skip integer default 0, after_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_comments"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid) from public, anon;
grant execute on function "api"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid) to authenticated, service_role;

create or replace function "api"."list_file_comments"(attachment uuid, max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_file_comments"($1, $2) $$;
revoke execute on function "api"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "api"."list_file_comments"(uuid, integer) to authenticated, service_role;

create or replace function "api"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."comment_counts"($1, $2, $3) $$;
revoke execute on function "api"."comment_counts"(uuid, text, text[]) from public, anon;
grant execute on function "api"."comment_counts"(uuid, text, text[]) to authenticated, service_role;

create or replace function "api"."copy_comments"(tenant uuid, from_type text, from_id text, to_type text, to_id text)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."copy_comments"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."copy_comments"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."copy_comments"(uuid, text, text, text, text) to service_role;

create or replace function "api"."assign_comment"(message uuid, assignee uuid default null, attrs jsonb default '{}')
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."assign_comment"($1, $2, $3) $$;
revoke execute on function "api"."assign_comment"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."assign_comment"(uuid, uuid, jsonb) to authenticated, service_role;

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
