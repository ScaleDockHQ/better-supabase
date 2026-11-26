-- better-supabase module: posts
-- @bsb-block posts@1 managed
-- @bsb-hash sha256:ed5f9475b0eabed563b4a330ecee437544978f8bc7ef5d638ff0769311490185
-- Forum threads and feedback posts on boards. Replies are comments on the messaging core, votes are reactions, and each post is a moderation item members can report. Feedback posts move through a status from open to done.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Forum and feedback posts on boards. Replies are comments, votes are
-- reactions, and each post is a moderation item.
create table "better_supabase"."post_boards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null constraint bsb_post_boards_key_check check ("key" ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  "name" text not null constraint bsb_post_boards_name_check check (length("name") >= 1 and length("name") <= 200),
  "description" text constraint bsb_post_boards_description_check check ("description" is null or length("description") <= 2000),
  -- forum: discussion threads; feedback: ideas members vote on, with a status.
  "kind" text not null default 'forum' constraint bsb_post_boards_kind_check check ("kind" in ('forum', 'feedback')),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

create table "better_supabase"."posts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "board_id" uuid not null references "better_supabase"."post_boards" ("id") on delete cascade,
  "author_id" uuid references auth.users (id) on delete set null,
  "title" text not null constraint bsb_posts_title_check check (length("title") >= 1 and length("title") <= 300),
  "body" text not null default '' constraint bsb_posts_body_check check (length("body") <= 20000),
  "status" text not null default 'open' constraint bsb_posts_status_check check ("status" in ('open', 'under_review', 'planned', 'in_progress', 'done', 'closed')),
  -- The moderation item's status, kept in step by a trigger.
  "moderation_status" text not null default 'visible' constraint bsb_posts_moderation_status_check check ("moderation_status" in ('visible', 'pending', 'hidden', 'removed')),
  "pinned_at" timestamptz,
  "locked_at" timestamptz,
  "archived_at" timestamptz,
  "merged_into_id" uuid references "better_supabase"."posts" ("id") on delete set null constraint bsb_posts_check check ("merged_into_id" is distinct from "id"),
  "reply_count" integer not null default 0,
  "last_activity_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index "posts_board_idx" on "better_supabase"."posts" ("board_id", "pinned_at" desc nulls last, "last_activity_at" desc);
create index "posts_tenant_idx" on "better_supabase"."posts" ("tenant_id", "created_at" desc, "id" desc);
create index "posts_author_idx" on "better_supabase"."posts" ("author_id");
create index "posts_merged_idx" on "better_supabase"."posts" ("merged_into_id");

alter table "better_supabase"."post_boards" enable row level security;
revoke all on "better_supabase"."post_boards" from public, anon, authenticated;
grant select on "better_supabase"."post_boards" to authenticated;
grant all on "better_supabase"."post_boards" to service_role;
create policy bsb_post_boards_read on "better_supabase"."post_boards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')));
alter table "better_supabase"."posts" enable row level security;
revoke all on "better_supabase"."posts" from public, anon, authenticated;
grant select on "better_supabase"."posts" to authenticated;
grant all on "better_supabase"."posts" to service_role;
create policy bsb_posts_read on "better_supabase"."posts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ));

-- Creates or changes a board. board is { id?, key, name, description, kind,
-- archived }; keys left out keep their value, and the key can't change.
create or replace function "better_supabase"."upsert_post_board"(tenant uuid, board jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."post_boards";
  v_row "better_supabase"."post_boards";
  v_key text;
  v_name text;
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (upsert_post_board.tenant is not null and coalesce(better_supabase.can('tenant', upsert_post_board.tenant, 'posts.manage'), false))) then
    raise exception 'not allowed to manage boards' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(upsert_post_board.board) is distinct from 'object' then
    raise exception 'board must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_id := nullif(upsert_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."post_boards" x where x."id" = v_id and x."tenant_id" = upsert_post_board.tenant for update;
    if v_old."id" is null then
      raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
    end if;
    if upsert_post_board.board ? 'key' and upsert_post_board.board ->> 'key' is distinct from v_old."key" then
      raise exception 'a board''s key can''t change' using errcode = '22023', hint = 'POST_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", upsert_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(upsert_post_board.board ->> 'name'), ''), v_old."name");
  v_kind := coalesce(upsert_post_board.board ->> 'kind', v_old."kind", 'forum');
  if v_key is null or v_key !~ '^[a-z0-9][a-z0-9_-]{0,62}$' then
    raise exception 'a board needs a key of lowercase letters, digits, dashes and underscores' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a board needs a name of at most 200 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_kind not in ('forum', 'feedback') then
    raise exception 'a board''s kind is forum or feedback' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."post_boards" ("tenant_id", "key", "name", "description", "kind", "archived_at", "created_by")
    values (upsert_post_board.tenant, v_key, v_name, nullif(trim(upsert_post_board.board ->> 'description'), ''), v_kind,
      case when coalesce((upsert_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."post_boards" x set
      "name" = v_name,
      "description" = case when upsert_post_board.board ? 'description' then nullif(trim(upsert_post_board.board ->> 'description'), '') else x."description" end,
      "kind" = v_kind,
      "archived_at" = case when upsert_post_board.board ? 'archived' then case when (upsert_post_board.board ->> 'archived')::boolean then coalesce(x."archived_at", now()) end else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('post_board.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'kind', v_row."kind"), 'post-boards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post_board.created',
    category => 'data',
    target_type => 'post_board',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created a board',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'kind', v_row."kind")
  );
  else
    perform "better_supabase".emit_event('post_board.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'kind', v_row."kind"), 'post-boards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post_board.updated',
    category => 'data',
    target_type => 'post_board',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated a board',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'kind', v_row."kind")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'kind', v_row."kind", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."upsert_post_board"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."upsert_post_board"(uuid, jsonb) to authenticated, service_role;

-- The organization's boards by name; archived ones only when asked.
create or replace function "better_supabase"."list_post_boards"(tenant uuid, archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."post_boards" x
  where x."tenant_id" = list_post_boards.tenant
    and (coalesce(list_post_boards.archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_post_boards"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_post_boards"(uuid, boolean) to authenticated, service_role;
-- A post the caller writes on a board: post is { title, body, fields }. It is
-- published at once, or held for a moderator when options.moderation is
-- "pre". Banned members can't post.
create or replace function "better_supabase"."create_post"(board_id uuid, post jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_me uuid := auth.uid();
  v_board "better_supabase"."post_boards";
  v_row "better_supabase"."posts";
  v_title text := trim(create_post.post ->> 'title');
  v_body text := coalesce(create_post.post ->> 'body', '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_board from "better_supabase"."post_boards" x where x."id" = create_post.board_id;
  if not found then
    raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_board."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_board."tenant_id", 'posts.write'), false))) or (v_me is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to post on this board' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if v_board."archived_at" is not null then
    raise exception 'the board is archived' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if "better_supabase"."moderation_banned"(v_board."tenant_id", v_me) then
    raise exception 'you are banned from posting in this organization' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a post needs a title of 1 to 300 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if length(v_body) > 20000 then
    raise exception 'a post''s body is at most 20000 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  insert into "better_supabase"."posts" ("tenant_id", "board_id", "author_id", "title", "body", "moderation_status")
  values (v_board."tenant_id", v_board."id", v_me, v_title, v_body, 'visible')
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'post', v_row."id"::text, v_me, 'visible');
  perform "better_supabase".emit_event('post.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'archivedAt', v_row."archived_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
end;
$$;
revoke execute on function "better_supabase"."create_post"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_post"(uuid, jsonb) to authenticated, service_role;

-- Changes a post's title, body or fields: its author while it isn't locked, or a
-- moderator. Under pre-moderation the author's edit goes back to the queue.
create or replace function "better_supabase"."update_post"(post_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."posts";
  v_moderator boolean;
  v_title text;
  v_body text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."posts" x where x."id" = update_post.post_id for update;
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  v_moderator := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false));
  if not v_moderator and (v_row."author_id" is distinct from auth.uid() or v_row."locked_at" is not null) then
    raise exception 'not allowed to change this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(update_post.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'the post is archived; restore it first' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_title := case when update_post.attrs ? 'title' then trim(update_post.attrs ->> 'title') else v_row."title" end;
  v_body := case when update_post.attrs ? 'body' then coalesce(update_post.attrs ->> 'body', '') else v_row."body" end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a post needs a title of 1 to 300 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if length(v_body) > 20000 then
    raise exception 'a post''s body is at most 20000 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  update "better_supabase"."posts" x set "title" = v_title, "body" = v_body, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('post.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'archivedAt', v_row."archived_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
end;
$$;
revoke execute on function "better_supabase"."update_post"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_post"(uuid, jsonb) to authenticated, service_role;

-- Sets a post's status (open, under_review, planned, in_progress, done or
-- closed), pins or unpins it and locks or unlocks its replies. attrs is
-- { status?, pinned?, locked? }. Moderators only.
create or replace function "better_supabase"."set_post_state"(post_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."posts";
  v_old "better_supabase"."posts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."posts" x where x."id" = set_post_state.post_id for update;
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) then
    raise exception 'not allowed to moderate posts' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(set_post_state.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_old := v_row;
  update "better_supabase"."posts" x set
    "status" = coalesce(set_post_state.attrs ->> 'status', x."status"),
    "pinned_at" = case when set_post_state.attrs ? 'pinned' then case when (set_post_state.attrs ->> 'pinned')::boolean then coalesce(x."pinned_at", now()) end else x."pinned_at" end,
    "locked_at" = case when set_post_state.attrs ? 'locked' then case when (set_post_state.attrs ->> 'locked')::boolean then coalesce(x."locked_at", now()) end else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" is distinct from v_old."status" then
    perform "better_supabase".emit_event('post.status_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post.status_changed',
    category => 'data',
    target_type => 'post',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'changed a post''s status',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id")
  );
  elsif v_row."pinned_at" is distinct from v_old."pinned_at" or v_row."locked_at" is distinct from v_old."locked_at" then
    perform "better_supabase".emit_event('post.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post.updated',
    category => 'data',
    target_type => 'post',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'pinned or locked a post',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'archivedAt', v_row."archived_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
exception when check_violation then
  raise exception 'unknown post status' using errcode = '22023', hint = 'POST_INVALID';
end;
$$;
revoke execute on function "better_supabase"."set_post_state"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_post_state"(uuid, jsonb) to authenticated, service_role;

-- Merges a duplicate into another post on the same board: the duplicate
-- closes and points at the other, and its votes move there unless the voter
-- already voted on it. Replies stay on the duplicate. Moderators only.
create or replace function "better_supabase"."merge_posts"(source_id uuid, target_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."posts";
  v_target "better_supabase"."posts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."posts" x where x."id" = merge_posts.source_id for update;
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  select * into v_target from "better_supabase"."posts" x where x."id" = merge_posts.target_id for update;
  if not found or v_target."board_id" is distinct from v_row."board_id" then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) then
    raise exception 'not allowed to moderate posts' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if v_target."id" = v_row."id" or v_target."merged_into_id" is not null or v_target."archived_at" is not null then
    raise exception 'merge into another post that wasn''t merged itself' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "kind", "emoji", "value")
  select r."tenant_id", r."subject_type", v_target."id"::text, r."actor", r."user_id", r."kind", r."emoji", r."value"
  from "better_supabase"."reactions" r
  where r."tenant_id" = v_row."tenant_id" and r."subject_type" = 'post'
    and r."subject_id" = v_row."id"::text and r."kind" = 'vote'
    and not exists (
      select 1 from "better_supabase"."reactions" t
      where t."tenant_id" = r."tenant_id" and t."subject_type" = 'post'
        and t."subject_id" = v_target."id"::text and t."kind" = 'vote' and t."actor" = r."actor"
    );
  delete from "better_supabase"."reactions" r
  where r."tenant_id" = v_row."tenant_id" and r."subject_type" = 'post'
    and r."subject_id" = v_row."id"::text and r."kind" = 'vote';
  update "better_supabase"."posts" x set "merged_into_id" = v_target."id", "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."posts" x set "merged_into_id" = v_target."id", "updated_at" = now()
  where x."merged_into_id" = v_row."id";
  perform "better_supabase".emit_event('post.merged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post.merged',
    category => 'data',
    target_type => 'post',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'merged a post',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id")
  );
  return jsonb_build_object('id', v_target."id", 'organizationId', v_target."tenant_id", 'boardId', v_target."board_id", 'authorId', v_target."author_id", 'mine', coalesce(v_target."author_id" = (select auth.uid()), false), 'title', v_target."title", 'body', v_target."body", 'status', v_target."status", 'moderation', v_target."moderation_status", 'pinnedAt', v_target."pinned_at", 'lockedAt', v_target."locked_at", 'archivedAt', v_target."archived_at", 'mergedIntoId', v_target."merged_into_id", 'replyCount', v_target."reply_count", 'lastActivityAt', v_target."last_activity_at", 'createdAt', v_target."created_at", 'updatedAt', v_target."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_target."tenant_id", 'post', v_target."id"::text));
end;
$$;
revoke execute on function "better_supabase"."merge_posts"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_posts"(uuid, uuid) to authenticated, service_role;


-- Archives a post: it leaves list_posts and keeps its replies and votes, but takes no new votes or replies. Its author or a moderator.
create or replace function "better_supabase"."archive_post"(post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."posts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."posts" x where x."id" = archive_post.post_id for update;
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to change this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'archivedAt', v_row."archived_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
  end if;
  update "better_supabase"."posts" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('post.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post.archived',
    category => 'data',
    target_type => 'post',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'post archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'archivedAt', v_row."archived_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
end;
$$;
revoke execute on function "better_supabase"."archive_post"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_post"(uuid) to authenticated, service_role;

-- Brings an archived post back to list_posts. Its author or a moderator.
create or replace function "better_supabase"."restore_post"(post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."posts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."posts" x where x."id" = restore_post.post_id for update;
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to change this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'archivedAt', v_row."archived_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
  end if;
  update "better_supabase"."posts" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('post.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post.restored',
    category => 'data',
    target_type => 'post',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'post restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'archivedAt', v_row."archived_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
end;
$$;
revoke execute on function "better_supabase"."restore_post"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_post"(uuid) to authenticated, service_role;

-- Removes a post for good, with its votes. Needs permissions.purge when the
-- app sets it; otherwise the post's author or a moderator.
create or replace function "better_supabase"."purge_post"(post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."posts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."posts" x where x."id" = purge_post.post_id for update;
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to purge this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  delete from "better_supabase"."posts" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('post.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post.purged',
    category => 'data',
    target_type => 'post',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'post purged',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'archivedAt', v_row."archived_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
end;
$$;
revoke execute on function "better_supabase"."purge_post"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_post"(uuid) to authenticated, service_role;
-- One post the caller reads, with its vote tally and the caller's vote, or
-- null.
create or replace function "better_supabase"."get_post"(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0)))
  from "better_supabase"."posts" x
  left join "better_supabase"."reaction_scores" s on s."tenant_id" = x."tenant_id" and s."subject_type" = 'post' and s."subject_id" = x."id"::text
  where x."id" = get_post.post_id
$$;
revoke execute on function "better_supabase"."get_post"(uuid) from public, anon;
grant execute on function "better_supabase"."get_post"(uuid) to authenticated, service_role;

-- Posts the caller reads. filter is { boardId?, status?, authorId?, sort?,
-- merged?, archived?, limit?, offset? }: sort active (pinned first, then the latest
-- activity; the default), new or top (most votes). Merged posts only with
-- merged true; archived posts are hidden unless archived is set (true lists
-- only the archived ones).
create or replace function "better_supabase"."list_posts"(tenant uuid, filter jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filter jsonb := coalesce(list_posts.filter, '{}'::jsonb);
  v_sort text := coalesce(v_filter ->> 'sort', 'active');
begin
  if v_sort not in ('active', 'new', 'top') then
    raise exception 'sort is active, new or top' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  return (
    select coalesce(jsonb_agg(e.row order by e.n), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as row,
        row_number() over (order by
          case when v_sort = 'active' then x."pinned_at" end desc nulls last,
          case when v_sort = 'top' then coalesce(s."score", 0) end desc,
          case when v_sort = 'active' then x."last_activity_at" end desc,
          x."created_at" desc, x."id") as n
      from "better_supabase"."posts" x
      left join "better_supabase"."reaction_scores" s on s."tenant_id" = x."tenant_id" and s."subject_type" = 'post' and s."subject_id" = x."id"::text
      where x."tenant_id" = list_posts.tenant
        and (v_filter ->> 'boardId' is null or x."board_id" = (v_filter ->> 'boardId')::uuid)
        and (v_filter ->> 'status' is null or x."status" = v_filter ->> 'status')
        and (v_filter ->> 'authorId' is null or x."author_id" = (v_filter ->> 'authorId')::uuid)
        and (coalesce((v_filter ->> 'merged')::boolean, false) or x."merged_into_id" is null)
        and (case when v_filter ? 'archived' then (x."archived_at" is not null) = (v_filter ->> 'archived')::boolean else x."archived_at" is null end)
      order by n
      limit least(greatest(coalesce((v_filter ->> 'limit')::integer, 50), 1), 200)
      offset greatest(coalesce((v_filter ->> 'offset')::integer, 0), 0)
    ) e
  );
end;
$$;
revoke execute on function "better_supabase"."list_posts"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_posts"(uuid, jsonb) to authenticated, service_role;

-- Sets the caller's vote on a post they read: 1 up, -1 down, 0 clears it.
-- Returns the post's tally. A merged or archived post takes no votes.
create or replace function "better_supabase"."vote_on_post"(post_id uuid, value integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_merged uuid;
  v_archived timestamptz;
begin
  select x."tenant_id", x."merged_into_id", x."archived_at" into v_tenant, v_merged, v_archived
  from "better_supabase"."posts" x where x."id" = vote_on_post.post_id and x."moderation_status" = 'visible';
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if v_merged is not null then
    raise exception 'the post was merged; vote on the post it was merged into' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if v_archived is not null then
    raise exception 'the post is archived' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return "better_supabase"."vote"(v_tenant, 'post', vote_on_post.post_id::text, vote_on_post.value);
end;
$$;
revoke execute on function "better_supabase"."vote_on_post"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."vote_on_post"(uuid, integer) to authenticated, service_role;
-- Posts the caller reads as a keyset page (ADR 1077). filters is { boardId,
-- status, authorId (each a value or a list), merged (true includes merged
-- posts), archived (true reads only archived posts), search (title, body),
-- sort (active, new, top; active by default: pinned first, then the latest
-- activity), direction, facet (status, boardId), count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "better_supabase"."page_posts"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_posts.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_archived boolean := coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'boardId') = 'array' then v_filters -> 'boardId' when jsonb_typeof(v_filters -> 'boardId') in ('string', 'number') then jsonb_build_array(v_filters -> 'boardId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'authorId') = 'array' then v_filters -> 'authorId' when jsonb_typeof(v_filters -> 'authorId') in ('string', 'number') then jsonb_build_array(v_filters -> 'authorId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'boardId and authorId are uuids' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'boardId') then
      raise exception 'facet is one of status, boardId' using errcode = '22023', hint = 'POST_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'boardId' then (x."board_id")::text end) as v
      from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('active', 'new', 'top') then
    raise exception 'sort is one of active, new, top' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as j, jsonb_build_array((coalesce(x."pinned_at", '-infinity'::timestamptz))::text, (coalesce(x."last_activity_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (coalesce(x."pinned_at", '-infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."pinned_at", '-infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."pinned_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and coalesce(x."last_activity_at", x."created_at") < (v_after ->> 1)::timestamptz) or (coalesce(x."pinned_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and coalesce(x."last_activity_at", x."created_at") = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."pinned_at", '-infinity'::timestamptz) asc, coalesce(x."last_activity_at", x."created_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as j, jsonb_build_array((coalesce(x."pinned_at", '-infinity'::timestamptz))::text, (coalesce(x."last_activity_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (coalesce(x."pinned_at", '-infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."pinned_at", '-infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."pinned_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and coalesce(x."last_activity_at", x."created_at") < (v_after ->> 1)::timestamptz) or (coalesce(x."pinned_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and coalesce(x."last_activity_at", x."created_at") = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."pinned_at", '-infinity'::timestamptz) desc, coalesce(x."last_activity_at", x."created_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'active' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as j, jsonb_build_array((coalesce(x."pinned_at", '-infinity'::timestamptz))::text, (coalesce(x."last_activity_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (coalesce(x."pinned_at", '-infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."pinned_at", '-infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."pinned_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and coalesce(x."last_activity_at", x."created_at") < (v_after ->> 1)::timestamptz) or (coalesce(x."pinned_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and coalesce(x."last_activity_at", x."created_at") = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."pinned_at", '-infinity'::timestamptz) asc, coalesce(x."last_activity_at", x."created_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'active' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as j, jsonb_build_array((coalesce(x."pinned_at", '-infinity'::timestamptz))::text, (coalesce(x."last_activity_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (coalesce(x."pinned_at", '-infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."pinned_at", '-infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."pinned_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and coalesce(x."last_activity_at", x."created_at") < (v_after ->> 1)::timestamptz) or (coalesce(x."pinned_at", '-infinity'::timestamptz) = (v_after ->> 0)::timestamptz and coalesce(x."last_activity_at", x."created_at") = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."pinned_at", '-infinity'::timestamptz) desc, coalesce(x."last_activity_at", x."created_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'new' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'new' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'top' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as j, jsonb_build_array((x.vote_score)::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x.vote_score >= (v_after ->> 0)::integer and ((x.vote_score > (v_after ->> 0)::integer) or (x.vote_score = (v_after ->> 0)::integer and x."created_at" < (v_after ->> 1)::timestamptz) or (x.vote_score = (v_after ->> 0)::integer and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x.vote_score asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'top' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', x.vote_score, 'up', x.vote_up, 'down', x.vote_down, 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as j, jsonb_build_array((x.vote_score)::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x.vote_score <= (v_after ->> 0)::integer and ((x.vote_score < (v_after ->> 0)::integer) or (x.vote_score = (v_after ->> 0)::integer and x."created_at" < (v_after ->> 1)::timestamptz) or (x.vote_score = (v_after ->> 0)::integer and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x.vote_score desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from (select t.*, coalesce(s."score", 0) as vote_score, coalesce(s."up", 0) as vote_up, coalesce(s."down", 0) as vote_down
    from "better_supabase"."posts" t
    left join "better_supabase"."reaction_scores" s on s."tenant_id" = t."tenant_id" and s."subject_type" = 'post' and s."subject_id" = t."id"::text) x
      where x."tenant_id" = page_posts.tenant
        and (not (v_filters -> 'boardId' is not null and jsonb_typeof(v_filters -> 'boardId') <> 'null' and not (jsonb_typeof(v_filters -> 'boardId') = 'array' and jsonb_array_length(v_filters -> 'boardId') = 0)) or x."board_id" = any((case when jsonb_typeof(v_filters -> 'boardId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'boardId')) else array[v_filters ->> 'boardId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'authorId' is not null and jsonb_typeof(v_filters -> 'authorId') <> 'null' and not (jsonb_typeof(v_filters -> 'authorId') = 'array' and jsonb_array_length(v_filters -> 'authorId') = 0)) or x."author_id" = any((case when jsonb_typeof(v_filters -> 'authorId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'authorId')) else array[v_filters ->> 'authorId'] end)::uuid[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{merged,0}', v_filters ->> 'merged'), '') = 'true', false) or x."merged_into_id" is null)
        and (case when v_archived then x."archived_at" is not null else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_posts"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_posts"(uuid, jsonb) to authenticated, service_role;

-- The organization's boards as a keyset page (ADR 1077), by name. filters is
-- { archived (true also reads archived boards), kind (a value or a list),
-- search (name, description), sort (name, createdAt), direction, facet (kind),
-- count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_post_boards"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_post_boards.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'POST_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text end) as v
      from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."post_boards" x
      where x."tenant_id" = page_post_boards.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or (x."kind")::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_post_boards"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_post_boards"(uuid, jsonb) to authenticated, service_role;

-- Projects a post's moderation item onto the post. A moderator's decision
-- records post.moderated.
create or replace function "better_supabase"."posts_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."posts"%rowtype;
begin
  update "better_supabase"."posts" x set "moderation_status" = new."status"
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
    and x."moderation_status" is distinct from new."status"
  returning * into v_row;
  if v_row."id" is not null and new."decided_at" is not null then
    perform "better_supabase".emit_event('post.moderated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_moderated"() from public, anon, authenticated;
create trigger "bsb_posts_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'post')
  execute function "better_supabase"."posts_moderated"();

-- A deleted post takes its moderation item with it.
create or replace function "better_supabase"."posts_removed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from "better_supabase"."moderation_items" x
  where x."tenant_id" = old."tenant_id" and x."subject_type" = 'post' and x."subject_id" = old."id"::text;
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_removed"() from public, anon, authenticated;
create trigger "bsb_posts_removed"
  after delete on "better_supabase"."posts"
  for each row execute function "better_supabase"."posts_removed"();

-- Refuses a reply on a locked, archived, merged or hidden post, unless a moderator
-- writes it.
create or replace function "better_supabase"."posts_reply_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post "better_supabase"."posts"%rowtype;
begin
  select x.* into v_post
  from "better_supabase"."conversations" c
  join "better_supabase"."posts" x on x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id"
  where c."id" = new."conversation_id" and c."subject_type" = 'post';
  if v_post."id" is null then
    return new;
  end if;
  if (v_post."locked_at" is not null or v_post."archived_at" is not null or v_post."merged_into_id" is not null or v_post."moderation_status" <> 'visible')
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_post."tenant_id", 'posts.moderate'), false)) then
    raise exception 'the post is locked' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."posts_reply_guard"() from public, anon, authenticated;
create trigger "bsb_posts_reply_guard"
  before insert on "better_supabase"."messages"
  for each row execute function "better_supabase"."posts_reply_guard"();

-- Counts a post's sent, undeleted replies and moves its last activity.
create or replace function "better_supabase"."posts_replied"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."posts" x set
    "reply_count" = (
      select count(*) from "better_supabase"."messages" m
      where m."conversation_id" = new."conversation_id"
        and m."sent_at" is not null and m."archived_at" is null
    ),
    "last_activity_at" = greatest(x."last_activity_at", coalesce(new."sent_at", x."last_activity_at"))
  from "better_supabase"."conversations" c
  where c."id" = new."conversation_id" and c."subject_type" = 'post'
    and x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_replied"() from public, anon, authenticated;
create trigger "bsb_posts_replied"
  after insert or update of "sent_at", "archived_at" on "better_supabase"."messages"
  for each row execute function "better_supabase"."posts_replied"();

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."post_boards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."post_boards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."post_boards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."post_boards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."posts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."posts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."posts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."posts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create trigger "bsb_search_post_index"
  after insert or delete on "better_supabase"."posts"
  for each row execute function "better_supabase"."search_index_row"('post', 'id');
create trigger "bsb_search_post_index_u"
  after update of "id", "tenant_id", "title", "body" on "better_supabase"."posts"
  for each row when (old."id" is distinct from new."id" or old."tenant_id" is distinct from new."tenant_id" or old."title" is distinct from new."title" or old."body" is distinct from new."body")
  execute function "better_supabase"."search_index_row"('post', 'id');

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.post_boards deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"post_board","event_prefix":"post_board","archive_column":"archived_at"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.posts deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"post","event_prefix":"post","archive_column":"archived_at"}');

-- blocks.posts.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."upsert_post_board"(tenant uuid, board jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."upsert_post_board"($1, $2) $$;
revoke execute on function "api"."upsert_post_board"(uuid, jsonb) from public, anon;
grant execute on function "api"."upsert_post_board"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_post_boards"(tenant uuid, archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_post_boards"($1, $2) $$;
revoke execute on function "api"."list_post_boards"(uuid, boolean) from public, anon;
grant execute on function "api"."list_post_boards"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."create_post"(board_id uuid, post jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_post"($1, $2) $$;
revoke execute on function "api"."create_post"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_post"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_post"(post_id uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_post"($1, $2) $$;
revoke execute on function "api"."update_post"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_post"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_post_state"(post_id uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_post_state"($1, $2) $$;
revoke execute on function "api"."set_post_state"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_post_state"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."merge_posts"(source_id uuid, target_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."merge_posts"($1, $2) $$;
revoke execute on function "api"."merge_posts"(uuid, uuid) from public, anon;
grant execute on function "api"."merge_posts"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."archive_post"(post_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_post"($1) $$;
revoke execute on function "api"."archive_post"(uuid) from public, anon;
grant execute on function "api"."archive_post"(uuid) to authenticated, service_role;

create or replace function "api"."restore_post"(post_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_post"($1) $$;
revoke execute on function "api"."restore_post"(uuid) from public, anon;
grant execute on function "api"."restore_post"(uuid) to authenticated, service_role;

create or replace function "api"."purge_post"(post_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_post"($1) $$;
revoke execute on function "api"."purge_post"(uuid) from public, anon;
grant execute on function "api"."purge_post"(uuid) to authenticated, service_role;

create or replace function "api"."get_post"(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_post"($1) $$;
revoke execute on function "api"."get_post"(uuid) from public, anon;
grant execute on function "api"."get_post"(uuid) to authenticated, service_role;

create or replace function "api"."list_posts"(tenant uuid, filter jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_posts"($1, $2) $$;
revoke execute on function "api"."list_posts"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_posts"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."vote_on_post"(post_id uuid, value integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."vote_on_post"($1, $2) $$;
revoke execute on function "api"."vote_on_post"(uuid, integer) from public, anon;
grant execute on function "api"."vote_on_post"(uuid, integer) to authenticated, service_role;

create or replace function "api"."page_posts"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_posts"($1, $2) $$;
revoke execute on function "api"."page_posts"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_posts"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."page_post_boards"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_post_boards"($1, $2) $$;
revoke execute on function "api"."page_post_boards"(uuid, jsonb) from public, anon;
grant execute on function "api"."page_post_boards"(uuid, jsonb) to authenticated, service_role;
