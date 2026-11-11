-- ==== alone: schema supabase/schemas/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block comments@9 managed
-- @bsb-hash sha256:7f1cdf120668d4264db5af96cdae87346be6745a0de6d1dbaee4576f52cce4a0
-- Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Comments are a record's conversation (kind subject) on the messaging core:
-- whoever reads the record reads its comments. These functions open it,
-- expand mention groups, list a record's thread flat with its record, and
-- copy it; edits, deletes, pins, resolving and read markers go through the
-- messaging functions (edit_message, delete_message, pin_message,
-- resolve_message, mark_read). Every function is PL/pgSQL because the
-- messaging tables come later in the schema.

-- The work item a comment was turned into (assign_comment).
create table "better_supabase"."comment_tasks" (
  "message_id" uuid primary key,
  "tenant_id" uuid not null,
  "task_id" uuid not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now()
);
create index comment_tasks_task_idx on "better_supabase"."comment_tasks" ("task_id");
alter table "better_supabase"."comment_tasks" enable row level security;
revoke all on "better_supabase"."comment_tasks" from public, anon, authenticated;
grant select on "better_supabase"."comment_tasks" to authenticated;
grant insert ("message_id", "tenant_id", "task_id") on "better_supabase"."comment_tasks" to authenticated;
grant all on "better_supabase"."comment_tasks" to service_role;

-- Whether the caller reads a message in this tenant: the messages policy
-- decides.

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

create policy bsb_comment_tasks_read on "better_supabase"."comment_tasks"
  for select to authenticated
  using ("better_supabase"."comment_message_readable"("message_id", "tenant_id"));
create policy bsb_comment_tasks_insert on "better_supabase"."comment_tasks"
  for insert to authenticated
  with check (("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "tenant_id")) and (select better_supabase.actor_may_write()));

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
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json"(comments_json.ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (comments_json.ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."comments_json"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comments_json"(uuid[]) to authenticated, service_role;

-- A page of a record conversation's sent comment ids, as their owner, once
-- the conversation passes the read check.
create or replace function "better_supabase"."comment_page"(
  conversation uuid,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = comment_page.conversation and c."kind" = 'subject'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
  ) then
    return '{}'::uuid[];
  end if;
  return array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = comment_page.conversation and x."sent_at" is not null
      and (coalesce(comment_page.include_deleted, true) or x."archived_at" is null)
      and (comment_page.after is null
        or (x."sent_at", x."id") > (comment_page.after, coalesce(comment_page.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(comment_page.max_rows, 100), 1), 500)
    offset greatest(coalesce(comment_page.skip, 0), 0)
  );
end;
$$;
revoke execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body;
    end if;
  end;
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_msg ->> 'id')::uuid;
    end if;
  end;
  return "better_supabase"."comments_json"(array[(v_msg ->> 'id')::uuid]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) to authenticated, service_role;


-- A record's comments and replies in one list, oldest first; deleted ones
-- stay as placeholders so replies keep their parent, unless include_deleted
-- is false. Page with after and after_id (the last comment's sent_at and id)
-- or skip (an offset).

create or replace function "better_supabase"."list_comments"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."comments_json"("better_supabase"."comment_page"(v_conv, list_comments.after, list_comments.max_rows, list_comments.skip, list_comments.after_id, list_comments.include_deleted));
end;
$$;
revoke execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

-- list_comments without any check, as the owner. Only for the app's own
-- security definer function after it checked that the caller reads the
-- record and holds the comment read key in its tenant. Service role only.
create or replace function "better_supabase"."list_comments_unchecked"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conv uuid;
  v_ids uuid[];
begin
  select c."id" into v_conv from "better_supabase"."conversations" c
  where c."tenant_id" = list_comments_unchecked.tenant and c."kind" = 'subject'
    and c."subject_type" = list_comments_unchecked.subject_type and c."subject_id" = list_comments_unchecked.subject_id;
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  v_ids := array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (coalesce(list_comments_unchecked.include_deleted, true) or x."archived_at" is null)
      and (list_comments_unchecked.after is null
        or (x."sent_at", x."id") > (list_comments_unchecked.after, coalesce(list_comments_unchecked.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments_unchecked.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments_unchecked.skip, 0), 0)
  );
  return (
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json_unchecked"(v_ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (v_ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to service_role;

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
      and x."sent_at" is not null and x."archived_at" is null
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_file_comments.max_rows, 100), 1), 500)
  ));
end;
$$;
revoke execute on function "better_supabase"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_file_comments"(uuid, integer) to authenticated, service_role;

-- The number of sent, not deleted comments per conversation, as their
-- owner, for the conversations of the list that pass the read check.
create or replace function "better_supabase"."comment_count_rows"(conversations uuid[])
returns table (id uuid, n bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select x."conversation_id", count(*) from "better_supabase"."messages" x
  where x."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (comment_count_rows.conversations) and c."kind" = 'subject'
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
    ))
    and x."sent_at" is not null and x."archived_at" is null
  group by x."conversation_id";
end;
$$;
revoke execute on function "better_supabase"."comment_count_rows"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comment_count_rows"(uuid[]) to authenticated, service_role;

-- Comments per record the caller can read, for counters in a list:
-- { subject_id: count }, deleted ones left out. The records' conversations
-- are read under the caller's policies, then counted by key.
create or replace function "better_supabase"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    with c as materialized (
      select c."id" as id, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."tenant_id" = comment_counts.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_counts.subject_type
        and c."subject_id" = any (comment_counts.subject_ids)
    )
    select coalesce(jsonb_object_agg(c.subject_id, n.n), '{}'::jsonb)
    from c
    join "better_supabase"."comment_count_rows"(array(select c.id from c)) n on n.id = c.id
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
    insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor", "mentions", "reply_count", "last_reply_at", "reply_user_ids", "sent_at", "edited_at", "archived_at", "created_at")
    select n.new_id, y."tenant_id", v_to, p.new_id, r.new_id, y."author_id",
      y."body", y."document", y."anchor", y."mentions", y."reply_count", y."last_reply_at", y."reply_user_ids", y."sent_at", y."edited_at", y."archived_at", y."created_at"
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."comment_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("better_supabase"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."comment_tasks" as restrictive
  for insert to public
  with check (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_update on "better_supabase"."comment_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."comment_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block-data comments
-- @bsb-hash sha256:b88720e1f8db856027df7f4a32cd82bc30bc62603e455805ccbce770f292744d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block comments@9 managed
-- @bsb-hash sha256:eb81eb89c884517ed1f8abd2609de4c158333ae2963b13f3edb6b9e99f3996dc
-- Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Comments are a record's conversation (kind subject) on the messaging core:
-- whoever reads the record reads its comments. These functions open it,
-- expand mention groups, list a record's thread flat with its record, and
-- copy it; edits, deletes, pins, resolving and read markers go through the
-- messaging functions (edit_message, delete_message, pin_message,
-- resolve_message, mark_read). Every function is PL/pgSQL because the
-- messaging tables come later in the schema.

-- The work item a comment was turned into (assign_comment).
create table "better_supabase"."comment_tasks" (
  "message_id" uuid primary key,
  "tenant_id" uuid not null,
  "task_id" uuid not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now()
);
create index comment_tasks_task_idx on "better_supabase"."comment_tasks" ("task_id");
alter table "better_supabase"."comment_tasks" enable row level security;
revoke all on "better_supabase"."comment_tasks" from public, anon, authenticated;
grant select on "better_supabase"."comment_tasks" to authenticated;
grant insert ("message_id", "tenant_id", "task_id") on "better_supabase"."comment_tasks" to authenticated;
grant all on "better_supabase"."comment_tasks" to service_role;

-- Whether the caller reads a message in this tenant: the messages policy
-- decides.

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

create policy bsb_comment_tasks_read on "better_supabase"."comment_tasks"
  for select to authenticated
  using ("better_supabase"."comment_message_readable"("message_id", "tenant_id"));
create policy bsb_comment_tasks_insert on "better_supabase"."comment_tasks"
  for insert to authenticated
  with check (("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "tenant_id")) and (select better_supabase.actor_may_write()));

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
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json"(comments_json.ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (comments_json.ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."comments_json"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comments_json"(uuid[]) to authenticated, service_role;

-- A page of a record conversation's sent comment ids, as their owner, once
-- the conversation passes the read check.
create or replace function "better_supabase"."comment_page"(
  conversation uuid,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = comment_page.conversation and c."kind" = 'subject'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end)
    or (c."kind" = 'subject' and ((c."tenant_id")::text, (c."subject_type")::text, (c."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) end))
  ) then
    return '{}'::uuid[];
  end if;
  return array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = comment_page.conversation and x."sent_at" is not null
  and (x."kind" = 'message' or "better_supabase"."inbox_note_readable"(x."conversation_id"))
      and (coalesce(comment_page.include_deleted, true) or x."archived_at" is null)
      and (comment_page.after is null
        or (x."sent_at", x."id") > (comment_page.after, coalesce(comment_page.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(comment_page.max_rows, 100), 1), 500)
    offset greatest(coalesce(comment_page.skip, 0), 0)
  );
end;
$$;
revoke execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body;
    end if;
  end;
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_msg ->> 'id')::uuid;
    end if;
  end;
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
    and x."sent_at" is not null and x."archived_at" is null;
  if not found then
    return;
  end if;
  select * into v_conv from "better_supabase"."conversations" c
  where c."id" = v_msg."conversation_id" and c."kind" = 'subject';
  if not found then
    return;
  end if;
  foreach v_user in array array(select distinct x from unnest(array[v_msg."author_id"] || v_msg."mentions") x where x = v_msg."author_id" or coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)) loop
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (v_conv."tenant_id", v_user, v_conv."subject_type", v_conv."subject_id", 'participating')
    on conflict do nothing;
  end loop;
  if (exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."subject_type" = v_conv."subject_type" and s."subject_id" = v_conv."subject_id" and s."tenant_id" = v_conv."tenant_id"
        and s."level" in ('all', 'participating')
        and not s."user_id" = any (array[v_msg."author_id"] || v_msg."mentions")
    ) or to_regprocedure('"public"."notification_audience"(jsonb)') is not null) then
    if better_supabase.import_run() is null then
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
  end if;
end;
$$;
revoke execute on function "better_supabase"."comment_sent"(uuid) from public, anon;
grant execute on function "better_supabase"."comment_sent"(uuid) to authenticated, service_role;

-- A record's comments and replies in one list, oldest first; deleted ones
-- stay as placeholders so replies keep their parent, unless include_deleted
-- is false. Page with after and after_id (the last comment's sent_at and id)
-- or skip (an offset).

create or replace function "better_supabase"."list_comments"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."comments_json"("better_supabase"."comment_page"(v_conv, list_comments.after, list_comments.max_rows, list_comments.skip, list_comments.after_id, list_comments.include_deleted));
end;
$$;
revoke execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

-- list_comments without any check, as the owner. Only for the app's own
-- security definer function after it checked that the caller reads the
-- record and holds the comment read key in its tenant. Service role only.
create or replace function "better_supabase"."list_comments_unchecked"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conv uuid;
  v_ids uuid[];
begin
  select c."id" into v_conv from "better_supabase"."conversations" c
  where c."tenant_id" = list_comments_unchecked.tenant and c."kind" = 'subject'
    and c."subject_type" = list_comments_unchecked.subject_type and c."subject_id" = list_comments_unchecked.subject_id;
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  v_ids := array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (coalesce(list_comments_unchecked.include_deleted, true) or x."archived_at" is null)
      and (list_comments_unchecked.after is null
        or (x."sent_at", x."id") > (list_comments_unchecked.after, coalesce(list_comments_unchecked.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments_unchecked.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments_unchecked.skip, 0), 0)
  );
  return (
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json_unchecked"(v_ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (v_ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to service_role;

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
      and x."sent_at" is not null and x."archived_at" is null
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_file_comments.max_rows, 100), 1), 500)
  ));
end;
$$;
revoke execute on function "better_supabase"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_file_comments"(uuid, integer) to authenticated, service_role;

-- The number of sent, not deleted comments per conversation, as their
-- owner, for the conversations of the list that pass the read check.
create or replace function "better_supabase"."comment_count_rows"(conversations uuid[])
returns table (id uuid, n bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select x."conversation_id", count(*) from "better_supabase"."messages" x
  where x."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (comment_count_rows.conversations) and c."kind" = 'subject'
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end)
    or (c."kind" = 'subject' and ((c."tenant_id")::text, (c."subject_type")::text, (c."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) end))
    ))
    and x."sent_at" is not null and x."archived_at" is null
  and (x."kind" = 'message' or "better_supabase"."inbox_note_readable"(x."conversation_id"))
  group by x."conversation_id";
end;
$$;
revoke execute on function "better_supabase"."comment_count_rows"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comment_count_rows"(uuid[]) to authenticated, service_role;

-- Comments per record the caller can read, for counters in a list:
-- { subject_id: count }, deleted ones left out. The records' conversations
-- are read under the caller's policies, then counted by key.
create or replace function "better_supabase"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    with c as materialized (
      select c."id" as id, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."tenant_id" = comment_counts.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_counts.subject_type
        and c."subject_id" = any (comment_counts.subject_ids)
    )
    select coalesce(jsonb_object_agg(c.subject_id, n.n), '{}'::jsonb)
    from c
    join "better_supabase"."comment_count_rows"(array(select c.id from c)) n on n.id = c.id
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
    insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor", "mentions", "reply_count", "last_reply_at", "reply_user_ids", "sent_at", "edited_at", "archived_at", "created_at")
    select n.new_id, y."tenant_id", v_to, p.new_id, r.new_id, y."author_id",
      y."body", y."document", y."anchor", y."mentions", y."reply_count", y."last_reply_at", y."reply_user_ids", y."sent_at", y."edited_at", y."archived_at", y."created_at"
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
  where x."id" = assign_comment.message and x."sent_at" is not null and x."archived_at" is null;
  if not found then
    raise exception 'no comment you can read has this id' using errcode = 'P0002', hint = 'COMMENT_NOT_FOUND';
  end if;
  select t."task_id" into v_task from "better_supabase"."comment_tasks" t where t."message_id" = v_msg."id";
  if found then
    return v_task;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_assign"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using assign_comment.message, assign_comment.assignee;
    end if;
  end;
  v_task := ("better_supabase"."create_task"(
    v_msg."tenant_id",
    (coalesce(assign_comment.attrs, '{}') - 'title') || jsonb_build_object(
      'title', coalesce(nullif(trim(assign_comment.attrs ->> 'title'), ''), left(v_msg."body", 120)),
      'body', coalesce(assign_comment.attrs ->> 'body', v_msg."body")
    ),
    case when assign_comment.assignee is null then '{}'::uuid[] else array[assign_comment.assignee] end
  ) ->> 'id')::uuid;
  insert into "better_supabase"."comment_tasks" ("message_id", "tenant_id", "task_id")
  values (v_msg."id", v_msg."tenant_id", v_task);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_task;
    end if;
  end;
  return v_task;
end;
$$;
revoke execute on function "better_supabase"."assign_comment"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."assign_comment"(uuid, uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."comment_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("better_supabase"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."comment_tasks" as restrictive
  for insert to public
  with check (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_update on "better_supabase"."comment_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."comment_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block-data comments
-- @bsb-hash sha256:b88720e1f8db856027df7f4a32cd82bc30bc62603e455805ccbce770f292744d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block comments@9 managed
-- @bsb-hash sha256:fd51e789c5e5bf5a4dc9bb3f3eacdd35de0318da7f9be1794693d8d95dce220a
-- Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Comments are a record's conversation (kind subject) on the messaging core:
-- whoever reads the record reads its comments. These functions open it,
-- expand mention groups, list a record's thread flat with its record, and
-- copy it; edits, deletes, pins, resolving and read markers go through the
-- messaging functions (edit_message, delete_message, pin_message,
-- resolve_message, mark_read). Every function is PL/pgSQL because the
-- messaging tables come later in the schema.

-- The work item a comment was turned into (assign_comment).
create table "app_private"."comment_tasks" (
  "message_id" uuid primary key,
  "tenant_id" uuid not null,
  "task_id" uuid not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now()
);
create index comment_tasks_task_idx on "app_private"."comment_tasks" ("task_id");
alter table "app_private"."comment_tasks" enable row level security;
revoke all on "app_private"."comment_tasks" from public, anon, authenticated;
grant select on "app_private"."comment_tasks" to authenticated;
grant insert ("message_id", "tenant_id", "task_id") on "app_private"."comment_tasks" to authenticated;
grant all on "app_private"."comment_tasks" to service_role;

-- Whether the caller reads a message in this tenant: the messages policy
-- decides.

create or replace function "app_private"."comment_message_readable"(message uuid, tenant uuid)
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
revoke execute on function "app_private"."comment_message_readable"(uuid, uuid) from public, anon;
grant execute on function "app_private"."comment_message_readable"(uuid, uuid) to authenticated, service_role;

create policy bsb_comment_tasks_read on "app_private"."comment_tasks"
  for select to authenticated
  using ("app_private"."comment_message_readable"("message_id", "tenant_id"));
create policy bsb_comment_tasks_insert on "app_private"."comment_tasks"
  for insert to authenticated
  with check (("created_by" = (select auth.uid()) and "app_private"."comment_message_readable"("message_id", "tenant_id")) and (select better_supabase.actor_may_write()));

-- A record's conversation, or null before its first comment.
create or replace function "app_private"."comment_conversation"(tenant uuid, subject_type text, subject_id text)
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
revoke execute on function "app_private"."comment_conversation"(uuid, text, text) from public, anon;
grant execute on function "app_private"."comment_conversation"(uuid, text, text) to authenticated, service_role;

-- Messages as comments: each with its record and the work item it became.
create or replace function "app_private"."comments_json"(ids uuid[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json"(comments_json.ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "app_private"."comment_tasks" t
      where t."message_id" = any (comments_json.ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "app_private"."comments_json"(uuid[]) from public, anon;
grant execute on function "app_private"."comments_json"(uuid[]) to authenticated, service_role;

-- A page of a record conversation's sent comment ids, as their owner, once
-- the conversation passes the read check.
create or replace function "app_private"."comment_page"(
  conversation uuid,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = comment_page.conversation and c."kind" = 'subject'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
  ) then
    return '{}'::uuid[];
  end if;
  return array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = comment_page.conversation and x."sent_at" is not null
      and (coalesce(comment_page.include_deleted, true) or x."archived_at" is null)
      and (comment_page.after is null
        or (x."sent_at", x."id") > (comment_page.after, coalesce(comment_page.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(comment_page.max_rows, 100), 1), 500)
    offset greatest(coalesce(comment_page.skip, 0), 0)
  );
end;
$$;
revoke execute on function "app_private"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "app_private"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

-- One comment the caller reads, or null.
create or replace function "app_private"."get_comment"(message uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return "app_private"."comments_json"(array[get_comment.message]) -> 0;
end;
$$;
revoke execute on function "app_private"."get_comment"(uuid) from public, anon;
grant execute on function "app_private"."get_comment"(uuid) to authenticated, service_role;

-- Comments on a record. attrs: parentId (a reply; one level, so a reply to
-- a reply joins the root), document, anchor (where on the record it points),
-- mentions (user ids) and fields (the messaging extra
-- columns). attachments: files the caller uploaded to the conversation.

create or replace function "app_private"."create_comment"(
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body;
    end if;
  end;
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_msg ->> 'id')::uuid;
    end if;
  end;
  return "app_private"."comments_json"(array[(v_msg ->> 'id')::uuid]) -> 0;
end;
$$;
revoke execute on function "app_private"."create_comment"(uuid, text, text, text, jsonb, uuid[]) from public, anon;
grant execute on function "app_private"."create_comment"(uuid, text, text, text, jsonb, uuid[]) to authenticated, service_role;


-- A record's comments and replies in one list, oldest first; deleted ones
-- stay as placeholders so replies keep their parent, unless include_deleted
-- is false. Page with after and after_id (the last comment's sent_at and id)
-- or skip (an offset).

create or replace function "app_private"."list_comments"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conv uuid := "app_private"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  return "app_private"."comments_json"("app_private"."comment_page"(v_conv, list_comments.after, list_comments.max_rows, list_comments.skip, list_comments.after_id, list_comments.include_deleted));
end;
$$;
revoke execute on function "app_private"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "app_private"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

-- list_comments without any check, as the owner. Only for the app's own
-- security definer function after it checked that the caller reads the
-- record and holds the comment read key in its tenant. Service role only.
create or replace function "app_private"."list_comments_unchecked"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conv uuid;
  v_ids uuid[];
begin
  select c."id" into v_conv from "better_supabase"."conversations" c
  where c."tenant_id" = list_comments_unchecked.tenant and c."kind" = 'subject'
    and c."subject_type" = list_comments_unchecked.subject_type and c."subject_id" = list_comments_unchecked.subject_id;
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  v_ids := array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (coalesce(list_comments_unchecked.include_deleted, true) or x."archived_at" is null)
      and (list_comments_unchecked.after is null
        or (x."sent_at", x."id") > (list_comments_unchecked.after, coalesce(list_comments_unchecked.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments_unchecked.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments_unchecked.skip, 0), 0)
  );
  return (
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json_unchecked"(v_ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "app_private"."comment_tasks" t
      where t."message_id" = any (v_ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "app_private"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon, authenticated;
grant execute on function "app_private"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to service_role;

-- The top-level comments anchored to a file, oldest first: on its pages,
-- regions and moments, on any record the caller can read.
create or replace function "app_private"."list_file_comments"(attachment uuid, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return "app_private"."comments_json"(array(
    select x."id" from "better_supabase"."messages" x
    join "better_supabase"."conversations" c on c."id" = x."conversation_id" and c."kind" = 'subject'
    where x."anchor" ->> 'kind' = 'file'
      and x."anchor" ->> 'attachmentId' = list_file_comments.attachment::text
      and x."sent_at" is not null and x."archived_at" is null
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_file_comments.max_rows, 100), 1), 500)
  ));
end;
$$;
revoke execute on function "app_private"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "app_private"."list_file_comments"(uuid, integer) to authenticated, service_role;

-- The number of sent, not deleted comments per conversation, as their
-- owner, for the conversations of the list that pass the read check.
create or replace function "app_private"."comment_count_rows"(conversations uuid[])
returns table (id uuid, n bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select x."conversation_id", count(*) from "better_supabase"."messages" x
  where x."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (comment_count_rows.conversations) and c."kind" = 'subject'
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
    ))
    and x."sent_at" is not null and x."archived_at" is null
  group by x."conversation_id";
end;
$$;
revoke execute on function "app_private"."comment_count_rows"(uuid[]) from public, anon;
grant execute on function "app_private"."comment_count_rows"(uuid[]) to authenticated, service_role;

-- Comments per record the caller can read, for counters in a list:
-- { subject_id: count }, deleted ones left out. The records' conversations
-- are read under the caller's policies, then counted by key.
create or replace function "app_private"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    with c as materialized (
      select c."id" as id, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."tenant_id" = comment_counts.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_counts.subject_type
        and c."subject_id" = any (comment_counts.subject_ids)
    )
    select coalesce(jsonb_object_agg(c.subject_id, n.n), '{}'::jsonb)
    from c
    join "app_private"."comment_count_rows"(array(select c.id from c)) n on n.id = c.id
  );
end;
$$;
revoke execute on function "app_private"."comment_counts"(uuid, text, text[]) from public, anon;
grant execute on function "app_private"."comment_counts"(uuid, text, text[]) to authenticated, service_role;

-- Copies a record's comments to another record in the same tenant (a quote
-- duplicated into an invoice, say), keeping authors, times and replies.
-- Service role only: call it from the code that duplicates the record,
-- after it checked the caller may read both.
create or replace function "app_private"."copy_comments"(
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
    insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor", "mentions", "reply_count", "last_reply_at", "reply_user_ids", "sent_at", "edited_at", "archived_at", "created_at")
    select n.new_id, y."tenant_id", v_to, p.new_id, r.new_id, y."author_id",
      y."body", y."document", y."anchor", y."mentions", y."reply_count", y."last_reply_at", y."reply_user_ids", y."sent_at", y."edited_at", y."archived_at", y."created_at"
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
revoke execute on function "app_private"."copy_comments"(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."copy_comments"(uuid, text, text, text, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."comment_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("app_private"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_insert on "app_private"."comment_tasks" as restrictive
  for insert to public
  with check (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("created_by" = (select auth.uid()) and "app_private"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_update on "app_private"."comment_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."comment_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block-data comments
-- @bsb-hash sha256:b88720e1f8db856027df7f4a32cd82bc30bc62603e455805ccbce770f292744d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block comments@9 managed
-- @bsb-hash sha256:9af22fb79cbc56d0743155fb5faa942e15227a6b92c3f6e386520f8650e9c82f
-- Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Comments are a record's conversation (kind subject) on the messaging core:
-- whoever reads the record reads its comments. These functions open it,
-- expand mention groups, list a record's thread flat with its record, and
-- copy it; edits, deletes, pins, resolving and read markers go through the
-- messaging functions (edit_message, delete_message, pin_message,
-- resolve_message, mark_read). Every function is PL/pgSQL because the
-- messaging tables come later in the schema.

-- The work item a comment was turned into (assign_comment).
create table "better_supabase"."comment_tasks" (
  "message_id" uuid primary key,
  "tenant_id" uuid not null,
  "task_id" uuid not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now()
);
create index comment_tasks_task_idx on "better_supabase"."comment_tasks" ("task_id");
alter table "better_supabase"."comment_tasks" enable row level security;
revoke all on "better_supabase"."comment_tasks" from public, anon, authenticated;
grant select on "better_supabase"."comment_tasks" to authenticated;
grant insert ("message_id", "tenant_id", "task_id") on "better_supabase"."comment_tasks" to authenticated;
grant all on "better_supabase"."comment_tasks" to service_role;

-- Whether the caller reads a message in this tenant: the messages policy
-- decides.

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

create policy bsb_comment_tasks_read on "better_supabase"."comment_tasks"
  for select to authenticated
  using ("better_supabase"."comment_message_readable"("message_id", "tenant_id"));
create policy bsb_comment_tasks_insert on "better_supabase"."comment_tasks"
  for insert to authenticated
  with check (("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "tenant_id")) and (select better_supabase.actor_may_write()));

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
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json"(comments_json.ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (comments_json.ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."comments_json"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comments_json"(uuid[]) to authenticated, service_role;

-- A page of a record conversation's sent comment ids, as their owner, once
-- the conversation passes the read check.
create or replace function "better_supabase"."comment_page"(
  conversation uuid,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = comment_page.conversation and c."kind" = 'subject'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
  ) then
    return '{}'::uuid[];
  end if;
  return array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = comment_page.conversation and x."sent_at" is not null
      and (coalesce(comment_page.include_deleted, true) or x."archived_at" is null)
      and (comment_page.after is null
        or (x."sent_at", x."id") > (comment_page.after, coalesce(comment_page.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(comment_page.max_rows, 100), 1), 500)
    offset greatest(coalesce(comment_page.skip, 0), 0)
  );
end;
$$;
revoke execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body;
    end if;
  end;
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_msg ->> 'id')::uuid;
    end if;
  end;
  return "better_supabase"."comments_json"(array[(v_msg ->> 'id')::uuid]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) to authenticated, service_role;


-- A record's comments and replies in one list, oldest first; deleted ones
-- stay as placeholders so replies keep their parent, unless include_deleted
-- is false. Page with after and after_id (the last comment's sent_at and id)
-- or skip (an offset).

create or replace function "better_supabase"."list_comments"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."comments_json"("better_supabase"."comment_page"(v_conv, list_comments.after, list_comments.max_rows, list_comments.skip, list_comments.after_id, list_comments.include_deleted));
end;
$$;
revoke execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

-- list_comments without any check, as the owner. Only for the app's own
-- security definer function after it checked that the caller reads the
-- record and holds the comment read key in its tenant. Service role only.
create or replace function "better_supabase"."list_comments_unchecked"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conv uuid;
  v_ids uuid[];
begin
  select c."id" into v_conv from "better_supabase"."conversations" c
  where c."tenant_id" = list_comments_unchecked.tenant and c."kind" = 'subject'
    and c."subject_type" = list_comments_unchecked.subject_type and c."subject_id" = list_comments_unchecked.subject_id;
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  v_ids := array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (coalesce(list_comments_unchecked.include_deleted, true) or x."archived_at" is null)
      and (list_comments_unchecked.after is null
        or (x."sent_at", x."id") > (list_comments_unchecked.after, coalesce(list_comments_unchecked.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments_unchecked.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments_unchecked.skip, 0), 0)
  );
  return (
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json_unchecked"(v_ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (v_ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to service_role;

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
      and x."sent_at" is not null and x."archived_at" is null
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_file_comments.max_rows, 100), 1), 500)
  ));
end;
$$;
revoke execute on function "better_supabase"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_file_comments"(uuid, integer) to authenticated, service_role;

-- The number of sent, not deleted comments per conversation, as their
-- owner, for the conversations of the list that pass the read check.
create or replace function "better_supabase"."comment_count_rows"(conversations uuid[])
returns table (id uuid, n bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select x."conversation_id", count(*) from "better_supabase"."messages" x
  where x."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (comment_count_rows.conversations) and c."kind" = 'subject'
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
    ))
    and x."sent_at" is not null and x."archived_at" is null
  group by x."conversation_id";
end;
$$;
revoke execute on function "better_supabase"."comment_count_rows"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comment_count_rows"(uuid[]) to authenticated, service_role;

-- Comments per record the caller can read, for counters in a list:
-- { subject_id: count }, deleted ones left out. The records' conversations
-- are read under the caller's policies, then counted by key.
create or replace function "better_supabase"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    with c as materialized (
      select c."id" as id, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."tenant_id" = comment_counts.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_counts.subject_type
        and c."subject_id" = any (comment_counts.subject_ids)
    )
    select coalesce(jsonb_object_agg(c.subject_id, n.n), '{}'::jsonb)
    from c
    join "better_supabase"."comment_count_rows"(array(select c.id from c)) n on n.id = c.id
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
    insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor", "mentions", "reply_count", "last_reply_at", "reply_user_ids", "sent_at", "edited_at", "archived_at", "created_at")
    select n.new_id, y."tenant_id", v_to, p.new_id, r.new_id, y."author_id",
      y."body", y."document", y."anchor", y."mentions", y."reply_count", y."last_reply_at", y."reply_user_ids", y."sent_at", y."edited_at", y."archived_at", y."created_at"
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."comment_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("better_supabase"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."comment_tasks" as restrictive
  for insert to public
  with check (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_update on "better_supabase"."comment_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."comment_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.comments.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.


create or replace function "api"."comment_conversation"(tenant uuid, subject_type text, subject_id text)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."comment_conversation"($1, $2, $3) $$;
revoke execute on function "api"."comment_conversation"(uuid, text, text) from public, anon;
grant execute on function "api"."comment_conversation"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."get_comment"(message uuid)
returns jsonb
language sql
stable
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

create or replace function "api"."list_comments"(tenant uuid, subject_type text, subject_id text, after timestamptz default null, max_rows integer default 100, skip integer default 0, after_id uuid default null, include_deleted boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_comments"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "api"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

create or replace function "api"."list_file_comments"(attachment uuid, max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_file_comments"($1, $2) $$;
revoke execute on function "api"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "api"."list_file_comments"(uuid, integer) to authenticated, service_role;

create or replace function "api"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block-data comments
-- @bsb-hash sha256:b88720e1f8db856027df7f4a32cd82bc30bc62603e455805ccbce770f292744d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block comments@9 managed
-- @bsb-hash sha256:25c2398e1a28536884f218ec2f52e5306f0c296f093ce9251558c7bfa7e150bc
-- Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Comments are a record's conversation (kind subject) on the messaging core:
-- whoever reads the record reads its comments. These functions open it,
-- expand mention groups, list a record's thread flat with its record, and
-- copy it; edits, deletes, pins, resolving and read markers go through the
-- messaging functions (edit_message, delete_message, pin_message,
-- resolve_message, mark_read). Every function is PL/pgSQL because the
-- messaging tables come later in the schema.

-- The work item a comment was turned into (assign_comment).
-- better_supabase.comment_tasks is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."comment_tasks" add column if not exists "message_id" uuid;
alter table "better_supabase"."comment_tasks" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."comment_tasks" add column if not exists "task_id" uuid;
alter table "better_supabase"."comment_tasks" add column if not exists "created_by" uuid default auth.uid();
alter table "better_supabase"."comment_tasks" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "comment_tasks_message_id_key" on "better_supabase"."comment_tasks" ("message_id");
create index if not exists comment_tasks_task_idx on "better_supabase"."comment_tasks" ("task_id");
alter table "better_supabase"."comment_tasks" enable row level security;
grant select on "better_supabase"."comment_tasks" to authenticated;
grant insert ("message_id", "tenant_id", "task_id") on "better_supabase"."comment_tasks" to authenticated;
grant all on "better_supabase"."comment_tasks" to service_role;

-- Whether the caller reads a message in this tenant: the messages policy
-- decides.

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

create policy bsb_comment_tasks_select on "better_supabase"."comment_tasks"
  for select to authenticated
  using ("better_supabase"."comment_message_readable"("message_id", "tenant_id"));
create policy bsb_comment_tasks_insert on "better_supabase"."comment_tasks"
  for insert to authenticated
  with check (("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "tenant_id")) and (select better_supabase.actor_may_write()));

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
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json"(comments_json.ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (comments_json.ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."comments_json"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comments_json"(uuid[]) to authenticated, service_role;

-- A page of a record conversation's sent comment ids, as their owner, once
-- the conversation passes the read check.
create or replace function "better_supabase"."comment_page"(
  conversation uuid,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = comment_page.conversation and c."kind" = 'subject'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
  ) then
    return '{}'::uuid[];
  end if;
  return array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = comment_page.conversation and x."sent_at" is not null
      and (coalesce(comment_page.include_deleted, true) or x."archived_at" is null)
      and (comment_page.after is null
        or (x."sent_at", x."id") > (comment_page.after, coalesce(comment_page.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(comment_page.max_rows, 100), 1), 500)
    offset greatest(coalesce(comment_page.skip, 0), 0)
  );
end;
$$;
revoke execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body;
    end if;
  end;
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_msg ->> 'id')::uuid;
    end if;
  end;
  return "better_supabase"."comments_json"(array[(v_msg ->> 'id')::uuid]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) to authenticated, service_role;


-- A record's comments and replies in one list, oldest first; deleted ones
-- stay as placeholders so replies keep their parent, unless include_deleted
-- is false. Page with after and after_id (the last comment's sent_at and id)
-- or skip (an offset).

create or replace function "better_supabase"."list_comments"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."comments_json"("better_supabase"."comment_page"(v_conv, list_comments.after, list_comments.max_rows, list_comments.skip, list_comments.after_id, list_comments.include_deleted));
end;
$$;
revoke execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

-- list_comments without any check, as the owner. Only for the app's own
-- security definer function after it checked that the caller reads the
-- record and holds the comment read key in its tenant. Service role only.
create or replace function "better_supabase"."list_comments_unchecked"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conv uuid;
  v_ids uuid[];
begin
  select c."id" into v_conv from "better_supabase"."conversations" c
  where c."tenant_id" = list_comments_unchecked.tenant and c."kind" = 'subject'
    and c."subject_type" = list_comments_unchecked.subject_type and c."subject_id" = list_comments_unchecked.subject_id;
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  v_ids := array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (coalesce(list_comments_unchecked.include_deleted, true) or x."archived_at" is null)
      and (list_comments_unchecked.after is null
        or (x."sent_at", x."id") > (list_comments_unchecked.after, coalesce(list_comments_unchecked.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments_unchecked.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments_unchecked.skip, 0), 0)
  );
  return (
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json_unchecked"(v_ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (v_ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to service_role;

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
      and x."sent_at" is not null and x."archived_at" is null
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_file_comments.max_rows, 100), 1), 500)
  ));
end;
$$;
revoke execute on function "better_supabase"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_file_comments"(uuid, integer) to authenticated, service_role;

-- The number of sent, not deleted comments per conversation, as their
-- owner, for the conversations of the list that pass the read check.
create or replace function "better_supabase"."comment_count_rows"(conversations uuid[])
returns table (id uuid, n bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select x."conversation_id", count(*) from "better_supabase"."messages" x
  where x."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (comment_count_rows.conversations) and c."kind" = 'subject'
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
    ))
    and x."sent_at" is not null and x."archived_at" is null
  group by x."conversation_id";
end;
$$;
revoke execute on function "better_supabase"."comment_count_rows"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comment_count_rows"(uuid[]) to authenticated, service_role;

-- Comments per record the caller can read, for counters in a list:
-- { subject_id: count }, deleted ones left out. The records' conversations
-- are read under the caller's policies, then counted by key.
create or replace function "better_supabase"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    with c as materialized (
      select c."id" as id, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."tenant_id" = comment_counts.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_counts.subject_type
        and c."subject_id" = any (comment_counts.subject_ids)
    )
    select coalesce(jsonb_object_agg(c.subject_id, n.n), '{}'::jsonb)
    from c
    join "better_supabase"."comment_count_rows"(array(select c.id from c)) n on n.id = c.id
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
    insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor", "mentions", "reply_count", "last_reply_at", "reply_user_ids", "sent_at", "edited_at", "archived_at", "created_at")
    select n.new_id, y."tenant_id", v_to, p.new_id, r.new_id, y."author_id",
      y."body", y."document", y."anchor", y."mentions", y."reply_count", y."last_reply_at", y."reply_user_ids", y."sent_at", y."edited_at", y."archived_at", y."created_at"
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."comment_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("better_supabase"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."comment_tasks" as restrictive
  for insert to public
  with check (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "tenant_id"))
  );
create policy bsb_tenant_scope_update on "better_supabase"."comment_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."comment_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block-data comments
-- @bsb-hash sha256:b88720e1f8db856027df7f4a32cd82bc30bc62603e455805ccbce770f292744d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block comments@9 managed
-- @bsb-hash sha256:736f270eb4ab9676fa2e4f654cda87ee07a32a299c5b6b4329e5875352fd09f7
-- Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Comments are a record's conversation (kind subject) on the messaging core:
-- whoever reads the record reads its comments. These functions open it,
-- expand mention groups, list a record's thread flat with its record, and
-- copy it; edits, deletes, pins, resolving and read markers go through the
-- messaging functions (edit_message, delete_message, pin_message,
-- resolve_message, mark_read). Every function is PL/pgSQL because the
-- messaging tables come later in the schema.

-- The work item a comment was turned into (assign_comment).
create table "better_supabase"."comment_tasks" (
  "message_id" uuid primary key,
  "org_id" uuid not null,
  "task_id" uuid not null,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now()
);
create index comment_tasks_task_idx on "better_supabase"."comment_tasks" ("task_id");
alter table "better_supabase"."comment_tasks" enable row level security;
revoke all on "better_supabase"."comment_tasks" from public, anon, authenticated;
grant select on "better_supabase"."comment_tasks" to authenticated;
grant insert ("message_id", "org_id", "task_id") on "better_supabase"."comment_tasks" to authenticated;
grant all on "better_supabase"."comment_tasks" to service_role;

-- Whether the caller reads a message in this tenant: the messages policy
-- decides.

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
    where x."id" = comment_message_readable.message and x."org_id" = comment_message_readable.tenant
  );
end;
$$;
revoke execute on function "better_supabase"."comment_message_readable"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."comment_message_readable"(uuid, uuid) to authenticated, service_role;

create policy bsb_comment_tasks_read on "better_supabase"."comment_tasks"
  for select to authenticated
  using ("better_supabase"."comment_message_readable"("message_id", "org_id"));
create policy bsb_comment_tasks_insert on "better_supabase"."comment_tasks"
  for insert to authenticated
  with check (("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "org_id")) and (select better_supabase.actor_may_write()));

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
  where c."org_id" = comment_conversation.tenant and c."kind" = 'subject'
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
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json"(comments_json.ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (comments_json.ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."comments_json"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comments_json"(uuid[]) to authenticated, service_role;

-- A page of a record conversation's sent comment ids, as their owner, once
-- the conversation passes the read check.
create or replace function "better_supabase"."comment_page"(
  conversation uuid,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = comment_page.conversation and c."kind" = 'subject'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."org_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
  ) then
    return '{}'::uuid[];
  end if;
  return array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = comment_page.conversation and x."sent_at" is not null
      and (coalesce(comment_page.include_deleted, true) or x."archived_at" is null)
      and (comment_page.after is null
        or (x."sent_at", x."id") > (comment_page.after, coalesce(comment_page.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(comment_page.max_rows, 100), 1), 500)
    offset greatest(coalesce(comment_page.skip, 0), 0)
  );
end;
$$;
revoke execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."comment_page"(uuid, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body;
    end if;
  end;
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_msg ->> 'id')::uuid;
    end if;
  end;
  return "better_supabase"."comments_json"(array[(v_msg ->> 'id')::uuid]) -> 0;
end;
$$;
revoke execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) from public, anon;
grant execute on function "better_supabase"."create_comment"(uuid, text, text, text, jsonb, uuid[]) to authenticated, service_role;


-- A record's comments and replies in one list, oldest first; deleted ones
-- stay as placeholders so replies keep their parent, unless include_deleted
-- is false. Page with after and after_id (the last comment's sent_at and id)
-- or skip (an offset).

create or replace function "better_supabase"."list_comments"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."comments_json"("better_supabase"."comment_page"(v_conv, list_comments.after, list_comments.max_rows, list_comments.skip, list_comments.after_id, list_comments.include_deleted));
end;
$$;
revoke execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_comments"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to authenticated, service_role;

-- list_comments without any check, as the owner. Only for the app's own
-- security definer function after it checked that the caller reads the
-- record and holds the comment read key in its tenant. Service role only.
create or replace function "better_supabase"."list_comments_unchecked"(
  tenant uuid,
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_conv uuid;
  v_ids uuid[];
begin
  select c."id" into v_conv from "better_supabase"."conversations" c
  where c."org_id" = list_comments_unchecked.tenant and c."kind" = 'subject'
    and c."subject_type" = list_comments_unchecked.subject_type and c."subject_id" = list_comments_unchecked.subject_id;
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  v_ids := array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (coalesce(list_comments_unchecked.include_deleted, true) or x."archived_at" is null)
      and (list_comments_unchecked.after is null
        or (x."sent_at", x."id") > (list_comments_unchecked.after, coalesce(list_comments_unchecked.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments_unchecked.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments_unchecked.skip, 0), 0)
  );
  return (
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json_unchecked"(v_ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (v_ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$$;
revoke execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamptz, integer, integer, uuid, boolean) to service_role;

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
      and x."sent_at" is not null and x."archived_at" is null
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_file_comments.max_rows, 100), 1), 500)
  ));
end;
$$;
revoke execute on function "better_supabase"."list_file_comments"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_file_comments"(uuid, integer) to authenticated, service_role;

-- The number of sent, not deleted comments per conversation, as their
-- owner, for the conversations of the list that pass the read check.
create or replace function "better_supabase"."comment_count_rows"(conversations uuid[])
returns table (id uuid, n bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select x."conversation_id", count(*) from "better_supabase"."messages" x
  where x."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (comment_count_rows.conversations) and c."kind" = 'subject'
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', c."org_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end))
    ))
    and x."sent_at" is not null and x."archived_at" is null
  group by x."conversation_id";
end;
$$;
revoke execute on function "better_supabase"."comment_count_rows"(uuid[]) from public, anon;
grant execute on function "better_supabase"."comment_count_rows"(uuid[]) to authenticated, service_role;

-- Comments per record the caller can read, for counters in a list:
-- { subject_id: count }, deleted ones left out. The records' conversations
-- are read under the caller's policies, then counted by key.
create or replace function "better_supabase"."comment_counts"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    with c as materialized (
      select c."id" as id, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."org_id" = comment_counts.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_counts.subject_type
        and c."subject_id" = any (comment_counts.subject_ids)
    )
    select coalesce(jsonb_object_agg(c.subject_id, n.n), '{}'::jsonb)
    from c
    join "better_supabase"."comment_count_rows"(array(select c.id from c)) n on n.id = c.id
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
  where c."org_id" = copy_comments.tenant and c."kind" = 'subject'
    and c."subject_type" = copy_comments.from_type and c."subject_id" = copy_comments.from_id;
  if v_from is null then
    return 0;
  end if;
  insert into "better_supabase"."conversations" ("org_id", "kind", "access", "subject_type", "subject_id")
  values (copy_comments.tenant, 'subject', 'subject', copy_comments.to_type, copy_comments.to_id)
  on conflict do nothing;
  select c."id" into v_to from "better_supabase"."conversations" c
  where c."org_id" = copy_comments.tenant and c."kind" = 'subject'
    and c."subject_type" = copy_comments.to_type and c."subject_id" = copy_comments.to_id;
  with copies as materialized (
    select y."id" as old_id, gen_random_uuid() as new_id
    from "better_supabase"."messages" y
    where y."conversation_id" = v_from and y."sent_at" is not null
  ), inserted as (
    insert into "better_supabase"."messages" ("id", "org_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor", "mentions", "reply_count", "last_reply_at", "reply_user_ids", "sent_at", "edited_at", "archived_at", "created_at")
    select n.new_id, y."org_id", v_to, p.new_id, r.new_id, y."author_id",
      y."body", y."document", y."anchor", y."mentions", y."reply_count", y."last_reply_at", y."reply_user_ids", y."sent_at", y."edited_at", y."archived_at", y."created_at"
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."comment_tasks" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("better_supabase"."comment_message_readable"("message_id", "org_id"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."comment_tasks" as restrictive
  for insert to public
  with check (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("created_by" = (select auth.uid()) and "better_supabase"."comment_message_readable"("message_id", "org_id"))
  );
create policy bsb_tenant_scope_update on "better_supabase"."comment_tasks" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."comment_tasks" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_033_comments.sql
-- better-supabase module: comments
-- @bsb-block-data comments
-- @bsb-hash sha256:b88720e1f8db856027df7f4a32cd82bc30bc62603e455805ccbce770f292744d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('comments', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
