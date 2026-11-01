-- ==== alone: schema supabase/schemas/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block posts@1 managed
-- @bsb-hash sha256:4634cdad03cee9264faa8d8070e94eaf8c7cbe3d6be6287e8de5bcc4bdef583b
-- Forum threads and feedback posts on boards. Replies are comments on the messaging core, votes are reactions, and each post is a moderation item members can report. Feedback posts move through a status from open to done.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Forum and feedback posts on boards. Replies are comments, votes are
-- reactions, and each post is a moderation item.
create table if not exists "better_supabase"."post_boards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- forum: discussion threads; feedback: ideas members vote on, with a status.
  "kind" text not null default 'forum' check ("kind" in ('forum', 'feedback')),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

create table if not exists "better_supabase"."posts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "board_id" uuid not null references "better_supabase"."post_boards" ("id") on delete cascade,
  "author_id" uuid references auth.users (id) on delete set null,
  "title" text not null check (length("title") between 1 and 300),
  "body" text not null default '' check (length("body") <= 20000),
  "status" text not null default 'open' check ("status" in ('open', 'under_review', 'planned', 'in_progress', 'done', 'closed')),
  -- The moderation item's status, kept in step by a trigger.
  "moderation_status" text not null default 'visible' check ("moderation_status" in ('visible', 'pending', 'hidden', 'removed')),
  "pinned_at" timestamptz,
  "locked_at" timestamptz,
  "merged_into_id" uuid references "better_supabase"."posts" ("id") on delete set null check ("merged_into_id" is distinct from "id"),
  "reply_count" integer not null default 0,
  "last_activity_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "posts_board_idx" on "better_supabase"."posts" ("board_id", "pinned_at" desc nulls last, "last_activity_at" desc);
create index if not exists "posts_tenant_idx" on "better_supabase"."posts" ("tenant_id", "created_at" desc);
create index if not exists "posts_author_idx" on "better_supabase"."posts" ("author_id");
create index if not exists "posts_merged_idx" on "better_supabase"."posts" ("merged_into_id");

alter table "better_supabase"."post_boards" enable row level security;
revoke all on "better_supabase"."post_boards" from public, anon, authenticated;
grant select on "better_supabase"."post_boards" to authenticated;
grant all on "better_supabase"."post_boards" to service_role;
drop policy if exists "post_boards_read" on "better_supabase"."post_boards";
create policy post_boards_read on "better_supabase"."post_boards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')));
alter table "better_supabase"."posts" enable row level security;
revoke all on "better_supabase"."posts" from public, anon, authenticated;
grant select on "better_supabase"."posts" to authenticated;
grant all on "better_supabase"."posts" to service_role;
drop policy if exists "posts_read" on "better_supabase"."posts";
create policy posts_read on "better_supabase"."posts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ));

-- Creates or changes a board. board is { id?, key, name, description, kind,
-- archived }; keys left out keep their value, and the key can't change.
create or replace function "better_supabase"."save_post_board"(tenant uuid, board jsonb)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_post_board.tenant is not null and coalesce(better_supabase.can('tenant', save_post_board.tenant, 'posts.manage'), false))) then
    raise exception 'not allowed to manage boards' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(save_post_board.board) is distinct from 'object' then
    raise exception 'board must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_id := nullif(save_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."post_boards" x where x."id" = v_id and x."tenant_id" = save_post_board.tenant for update;
    if v_old."id" is null then
      raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
    end if;
    if save_post_board.board ? 'key' and save_post_board.board ->> 'key' is distinct from v_old."key" then
      raise exception 'a board''s key can''t change' using errcode = '22023', hint = 'POST_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", save_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(save_post_board.board ->> 'name'), ''), v_old."name");
  v_kind := coalesce(save_post_board.board ->> 'kind', v_old."kind", 'forum');
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
    values (save_post_board.tenant, v_key, v_name, nullif(trim(save_post_board.board ->> 'description'), ''), v_kind,
      case when coalesce((save_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."post_boards" x set
      "name" = v_name,
      "description" = case when save_post_board.board ? 'description' then nullif(trim(save_post_board.board ->> 'description'), '') else x."description" end,
      "kind" = v_kind,
      "archived_at" = case when save_post_board.board ? 'archived' then case when (save_post_board.board ->> 'archived')::boolean then coalesce(x."archived_at", now()) end else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'kind', v_row."kind", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_post_board"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_post_board"(uuid, jsonb) to authenticated, service_role;

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
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
    null;
  elsif v_row."pinned_at" is distinct from v_old."pinned_at" or v_row."locked_at" is distinct from v_old."locked_at" then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
  if v_target."id" = v_row."id" or v_target."merged_into_id" is not null then
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
  null;
  return jsonb_build_object('id', v_target."id", 'organizationId', v_target."tenant_id", 'boardId', v_target."board_id", 'authorId', v_target."author_id", 'mine', coalesce(v_target."author_id" = (select auth.uid()), false), 'title', v_target."title", 'body', v_target."body", 'status', v_target."status", 'moderation', v_target."moderation_status", 'pinnedAt', v_target."pinned_at", 'lockedAt', v_target."locked_at", 'mergedIntoId', v_target."merged_into_id", 'replyCount', v_target."reply_count", 'lastActivityAt', v_target."last_activity_at", 'createdAt', v_target."created_at", 'updatedAt', v_target."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_target."tenant_id", 'post', v_target."id"::text));
end;
$$;
revoke execute on function "better_supabase"."merge_posts"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_posts"(uuid, uuid) to authenticated, service_role;

-- Deletes a post with its votes: its author, or a moderator. False when
-- there was none.
create or replace function "better_supabase"."delete_post"(post_id uuid)
returns boolean
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
  select * into v_row from "better_supabase"."posts" x where x."id" = delete_post.post_id for update;
  if not found then
    return false;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to delete this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  delete from "better_supabase"."posts" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_post"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_post"(uuid) to authenticated, service_role;
-- One post the caller reads, with its vote tally and the caller's vote, or
-- null.
create or replace function "better_supabase"."get_post"(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
-- merged?, limit?, offset? }: sort active (pinned first, then the latest
-- activity; the default), new or top (most votes). Merged posts only with
-- merged true.
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
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
-- Returns the post's tally. A merged post takes no votes.
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
begin
  select x."tenant_id", x."merged_into_id" into v_tenant, v_merged
  from "better_supabase"."posts" x where x."id" = vote_on_post.post_id and x."moderation_status" = 'visible';
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if v_merged is not null then
    raise exception 'the post was merged; vote on the post it was merged into' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return "better_supabase"."vote"(v_tenant, 'post', vote_on_post.post_id::text, vote_on_post.value);
end;
$$;
revoke execute on function "better_supabase"."vote_on_post"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."vote_on_post"(uuid, integer) to authenticated, service_role;

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
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_moderated" on "better_supabase"."moderation_items";
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
drop trigger if exists "bsb_posts_removed" on "better_supabase"."posts";
create trigger "bsb_posts_removed"
  after delete on "better_supabase"."posts"
  for each row execute function "better_supabase"."posts_removed"();

-- Refuses a reply on a locked, merged or hidden post, unless a moderator
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
  if (v_post."locked_at" is not null or v_post."merged_into_id" is not null or v_post."moderation_status" <> 'visible')
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_post."tenant_id", 'posts.moderate'), false)) then
    raise exception 'the post is locked' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."posts_reply_guard"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_reply_guard" on "better_supabase"."messages";
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
        and m."sent_at" is not null and m."deleted_at" is null
    ),
    "last_activity_at" = greatest(x."last_activity_at", coalesce(new."sent_at", x."last_activity_at"))
  from "better_supabase"."conversations" c
  where c."id" = new."conversation_id" and c."subject_type" = 'post'
    and x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_replied"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_replied" on "better_supabase"."messages";
create trigger "bsb_posts_replied"
  after insert or update of "sent_at", "deleted_at" on "better_supabase"."messages"
  for each row execute function "better_supabase"."posts_replied"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
create policy bsb_tenant_scope_select on "better_supabase"."post_boards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
create policy bsb_tenant_scope_insert on "better_supabase"."post_boards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
create policy bsb_tenant_scope_update on "better_supabase"."post_boards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
create policy bsb_tenant_scope_delete on "better_supabase"."post_boards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
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
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
create policy bsb_tenant_scope_insert on "better_supabase"."posts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
create policy bsb_tenant_scope_update on "better_supabase"."posts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
create policy bsb_tenant_scope_delete on "better_supabase"."posts" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block-data posts
-- @bsb-hash sha256:cf3d9eb13597345e8c143e55724f0dfbbb72694518788ae9544aa9820b826e8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block posts@1 managed
-- @bsb-hash sha256:bfbcfa0202f5bac390bac976e68a7e9e4879f31de6cea17f0abed90c3c055289
-- Forum threads and feedback posts on boards. Replies are comments on the messaging core, votes are reactions, and each post is a moderation item members can report. Feedback posts move through a status from open to done.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Forum and feedback posts on boards. Replies are comments, votes are
-- reactions, and each post is a moderation item.
create table if not exists "better_supabase"."post_boards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- forum: discussion threads; feedback: ideas members vote on, with a status.
  "kind" text not null default 'forum' check ("kind" in ('forum', 'feedback')),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

create table if not exists "better_supabase"."posts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "board_id" uuid not null references "better_supabase"."post_boards" ("id") on delete cascade,
  "author_id" uuid references auth.users (id) on delete set null,
  "title" text not null check (length("title") between 1 and 300),
  "body" text not null default '' check (length("body") <= 20000),
  "status" text not null default 'open' check ("status" in ('open', 'under_review', 'planned', 'in_progress', 'done', 'closed')),
  -- The moderation item's status, kept in step by a trigger.
  "moderation_status" text not null default 'visible' check ("moderation_status" in ('visible', 'pending', 'hidden', 'removed')),
  "pinned_at" timestamptz,
  "locked_at" timestamptz,
  "merged_into_id" uuid references "better_supabase"."posts" ("id") on delete set null check ("merged_into_id" is distinct from "id"),
  "reply_count" integer not null default 0,
  "last_activity_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "posts_board_idx" on "better_supabase"."posts" ("board_id", "pinned_at" desc nulls last, "last_activity_at" desc);
create index if not exists "posts_tenant_idx" on "better_supabase"."posts" ("tenant_id", "created_at" desc);
create index if not exists "posts_author_idx" on "better_supabase"."posts" ("author_id");
create index if not exists "posts_merged_idx" on "better_supabase"."posts" ("merged_into_id");

alter table "better_supabase"."post_boards" enable row level security;
revoke all on "better_supabase"."post_boards" from public, anon, authenticated;
grant select on "better_supabase"."post_boards" to authenticated;
grant all on "better_supabase"."post_boards" to service_role;
drop policy if exists "post_boards_read" on "better_supabase"."post_boards";
create policy post_boards_read on "better_supabase"."post_boards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')));
alter table "better_supabase"."posts" enable row level security;
revoke all on "better_supabase"."posts" from public, anon, authenticated;
grant select on "better_supabase"."posts" to authenticated;
grant all on "better_supabase"."posts" to service_role;
drop policy if exists "posts_read" on "better_supabase"."posts";
create policy posts_read on "better_supabase"."posts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ));

-- Creates or changes a board. board is { id?, key, name, description, kind,
-- archived }; keys left out keep their value, and the key can't change.
create or replace function "better_supabase"."save_post_board"(tenant uuid, board jsonb)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_post_board.tenant is not null and coalesce(better_supabase.can('tenant', save_post_board.tenant, 'posts.manage'), false))) then
    raise exception 'not allowed to manage boards' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(save_post_board.board) is distinct from 'object' then
    raise exception 'board must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_id := nullif(save_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."post_boards" x where x."id" = v_id and x."tenant_id" = save_post_board.tenant for update;
    if v_old."id" is null then
      raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
    end if;
    if save_post_board.board ? 'key' and save_post_board.board ->> 'key' is distinct from v_old."key" then
      raise exception 'a board''s key can''t change' using errcode = '22023', hint = 'POST_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", save_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(save_post_board.board ->> 'name'), ''), v_old."name");
  v_kind := coalesce(save_post_board.board ->> 'kind', v_old."kind", 'forum');
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
    values (save_post_board.tenant, v_key, v_name, nullif(trim(save_post_board.board ->> 'description'), ''), v_kind,
      case when coalesce((save_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."post_boards" x set
      "name" = v_name,
      "description" = case when save_post_board.board ? 'description' then nullif(trim(save_post_board.board ->> 'description'), '') else x."description" end,
      "kind" = v_kind,
      "archived_at" = case when save_post_board.board ? 'archived' then case when (save_post_board.board ->> 'archived')::boolean then coalesce(x."archived_at", now()) end else x."archived_at" end,
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
revoke execute on function "better_supabase"."save_post_board"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_post_board"(uuid, jsonb) to authenticated, service_role;

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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
  if v_target."id" = v_row."id" or v_target."merged_into_id" is not null then
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
  return jsonb_build_object('id', v_target."id", 'organizationId', v_target."tenant_id", 'boardId', v_target."board_id", 'authorId', v_target."author_id", 'mine', coalesce(v_target."author_id" = (select auth.uid()), false), 'title', v_target."title", 'body', v_target."body", 'status', v_target."status", 'moderation', v_target."moderation_status", 'pinnedAt', v_target."pinned_at", 'lockedAt', v_target."locked_at", 'mergedIntoId', v_target."merged_into_id", 'replyCount', v_target."reply_count", 'lastActivityAt', v_target."last_activity_at", 'createdAt', v_target."created_at", 'updatedAt', v_target."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_target."tenant_id", 'post', v_target."id"::text));
end;
$$;
revoke execute on function "better_supabase"."merge_posts"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_posts"(uuid, uuid) to authenticated, service_role;

-- Deletes a post with its votes: its author, or a moderator. False when
-- there was none.
create or replace function "better_supabase"."delete_post"(post_id uuid)
returns boolean
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
  select * into v_row from "better_supabase"."posts" x where x."id" = delete_post.post_id for update;
  if not found then
    return false;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to delete this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  delete from "better_supabase"."posts" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('post.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id"), 'posts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post.deleted',
    category => 'data',
    target_type => 'post',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'deleted a post',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'status', v_row."status", 'moderation', v_row."moderation_status", 'mergedIntoId', v_row."merged_into_id")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_post"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_post"(uuid) to authenticated, service_role;
-- One post the caller reads, with its vote tally and the caller's vote, or
-- null.
create or replace function "better_supabase"."get_post"(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
-- merged?, limit?, offset? }: sort active (pinned first, then the latest
-- activity; the default), new or top (most votes). Merged posts only with
-- merged true.
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
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
-- Returns the post's tally. A merged post takes no votes.
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
begin
  select x."tenant_id", x."merged_into_id" into v_tenant, v_merged
  from "better_supabase"."posts" x where x."id" = vote_on_post.post_id and x."moderation_status" = 'visible';
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if v_merged is not null then
    raise exception 'the post was merged; vote on the post it was merged into' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return "better_supabase"."vote"(v_tenant, 'post', vote_on_post.post_id::text, vote_on_post.value);
end;
$$;
revoke execute on function "better_supabase"."vote_on_post"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."vote_on_post"(uuid, integer) to authenticated, service_role;

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
drop trigger if exists "bsb_posts_moderated" on "better_supabase"."moderation_items";
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
drop trigger if exists "bsb_posts_removed" on "better_supabase"."posts";
create trigger "bsb_posts_removed"
  after delete on "better_supabase"."posts"
  for each row execute function "better_supabase"."posts_removed"();

-- Refuses a reply on a locked, merged or hidden post, unless a moderator
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
  if (v_post."locked_at" is not null or v_post."merged_into_id" is not null or v_post."moderation_status" <> 'visible')
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_post."tenant_id", 'posts.moderate'), false)) then
    raise exception 'the post is locked' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."posts_reply_guard"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_reply_guard" on "better_supabase"."messages";
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
        and m."sent_at" is not null and m."deleted_at" is null
    ),
    "last_activity_at" = greatest(x."last_activity_at", coalesce(new."sent_at", x."last_activity_at"))
  from "better_supabase"."conversations" c
  where c."id" = new."conversation_id" and c."subject_type" = 'post'
    and x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_replied"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_replied" on "better_supabase"."messages";
create trigger "bsb_posts_replied"
  after insert or update of "sent_at", "deleted_at" on "better_supabase"."messages"
  for each row execute function "better_supabase"."posts_replied"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
create policy bsb_tenant_scope_select on "better_supabase"."post_boards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
create policy bsb_tenant_scope_insert on "better_supabase"."post_boards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
create policy bsb_tenant_scope_update on "better_supabase"."post_boards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
create policy bsb_tenant_scope_delete on "better_supabase"."post_boards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
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
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
create policy bsb_tenant_scope_insert on "better_supabase"."posts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
create policy bsb_tenant_scope_update on "better_supabase"."posts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
create policy bsb_tenant_scope_delete on "better_supabase"."posts" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block-data posts
-- @bsb-hash sha256:e93aba4eb51441ffda738822604d46c3140f5a7ceff1b471e867cd3e2706bbb5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.post_boards', target_type => 'post_board', event_prefix => 'post_board', deferred => true);
select better_supabase.audit('better_supabase.posts', target_type => 'post', event_prefix => 'post', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block posts@1 managed
-- @bsb-hash sha256:36c36010a51171fe37196ab0a670cdab87317de0ef0095ba192fa3f02b33cf63
-- Forum threads and feedback posts on boards. Replies are comments on the messaging core, votes are reactions, and each post is a moderation item members can report. Feedback posts move through a status from open to done.
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
    drop policy if exists bsb_tenant_scope on "app_private"."post_boards";
    drop policy if exists bsb_tenant_scope_select on "app_private"."post_boards";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."post_boards";
    drop policy if exists bsb_tenant_scope_update on "app_private"."post_boards";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."post_boards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."posts";
    drop policy if exists bsb_tenant_scope_select on "app_private"."posts";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."posts";
    drop policy if exists bsb_tenant_scope_update on "app_private"."posts";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."posts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Forum and feedback posts on boards. Replies are comments, votes are
-- reactions, and each post is a moderation item.
create table if not exists "app_private"."post_boards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- forum: discussion threads; feedback: ideas members vote on, with a status.
  "kind" text not null default 'forum' check ("kind" in ('forum', 'feedback')),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

create table if not exists "app_private"."posts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "board_id" uuid not null references "app_private"."post_boards" ("id") on delete cascade,
  "author_id" uuid references auth.users (id) on delete set null,
  "title" text not null check (length("title") between 1 and 300),
  "body" text not null default '' check (length("body") <= 20000),
  "status" text not null default 'open' check ("status" in ('open', 'under_review', 'planned', 'in_progress', 'done', 'closed')),
  -- The moderation item's status, kept in step by a trigger.
  "moderation_status" text not null default 'visible' check ("moderation_status" in ('visible', 'pending', 'hidden', 'removed')),
  "pinned_at" timestamptz,
  "locked_at" timestamptz,
  "merged_into_id" uuid references "app_private"."posts" ("id") on delete set null check ("merged_into_id" is distinct from "id"),
  "reply_count" integer not null default 0,
  "last_activity_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "posts_board_idx" on "app_private"."posts" ("board_id", "pinned_at" desc nulls last, "last_activity_at" desc);
create index if not exists "posts_tenant_idx" on "app_private"."posts" ("tenant_id", "created_at" desc);
create index if not exists "posts_author_idx" on "app_private"."posts" ("author_id");
create index if not exists "posts_merged_idx" on "app_private"."posts" ("merged_into_id");

alter table "app_private"."post_boards" enable row level security;
revoke all on "app_private"."post_boards" from public, anon, authenticated;
grant select on "app_private"."post_boards" to authenticated;
grant all on "app_private"."post_boards" to service_role;
drop policy if exists "post_boards_read" on "app_private"."post_boards";
create policy post_boards_read on "app_private"."post_boards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')));
alter table "app_private"."posts" enable row level security;
revoke all on "app_private"."posts" from public, anon, authenticated;
grant select on "app_private"."posts" to authenticated;
grant all on "app_private"."posts" to service_role;
drop policy if exists "posts_read" on "app_private"."posts";
create policy posts_read on "app_private"."posts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ));

-- Creates or changes a board. board is { id?, key, name, description, kind,
-- archived }; keys left out keep their value, and the key can't change.
create or replace function "app_private"."save_post_board"(tenant uuid, board jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "app_private"."post_boards";
  v_row "app_private"."post_boards";
  v_key text;
  v_name text;
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_post_board.tenant is not null and coalesce(better_supabase.can('tenant', save_post_board.tenant, 'posts.manage'), false))) then
    raise exception 'not allowed to manage boards' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(save_post_board.board) is distinct from 'object' then
    raise exception 'board must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_id := nullif(save_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "app_private"."post_boards" x where x."id" = v_id and x."tenant_id" = save_post_board.tenant for update;
    if v_old."id" is null then
      raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
    end if;
    if save_post_board.board ? 'key' and save_post_board.board ->> 'key' is distinct from v_old."key" then
      raise exception 'a board''s key can''t change' using errcode = '22023', hint = 'POST_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", save_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(save_post_board.board ->> 'name'), ''), v_old."name");
  v_kind := coalesce(save_post_board.board ->> 'kind', v_old."kind", 'forum');
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
    insert into "app_private"."post_boards" ("tenant_id", "key", "name", "description", "kind", "archived_at", "created_by")
    values (save_post_board.tenant, v_key, v_name, nullif(trim(save_post_board.board ->> 'description'), ''), v_kind,
      case when coalesce((save_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update "app_private"."post_boards" x set
      "name" = v_name,
      "description" = case when save_post_board.board ? 'description' then nullif(trim(save_post_board.board ->> 'description'), '') else x."description" end,
      "kind" = v_kind,
      "archived_at" = case when save_post_board.board ? 'archived' then case when (save_post_board.board ->> 'archived')::boolean then coalesce(x."archived_at", now()) end else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'kind', v_row."kind", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_post_board"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_post_board"(uuid, jsonb) to authenticated, service_role;

-- The organization's boards by name; archived ones only when asked.
create or replace function "app_private"."list_post_boards"(tenant uuid, archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "app_private"."post_boards" x
  where x."tenant_id" = list_post_boards.tenant
    and (coalesce(list_post_boards.archived, false) or x."archived_at" is null)
$$;
revoke execute on function "app_private"."list_post_boards"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_post_boards"(uuid, boolean) to authenticated, service_role;
-- A post the caller writes on a board: post is { title, body, fields }. It is
-- published at once, or held for a moderator when options.moderation is
-- "pre". Banned members can't post.
create or replace function "app_private"."create_post"(board_id uuid, post jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_me uuid := auth.uid();
  v_board "app_private"."post_boards";
  v_row "app_private"."posts";
  v_title text := trim(create_post.post ->> 'title');
  v_body text := coalesce(create_post.post ->> 'body', '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_board from "app_private"."post_boards" x where x."id" = create_post.board_id;
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
  insert into "app_private"."posts" ("tenant_id", "board_id", "author_id", "title", "body", "moderation_status")
  values (v_board."tenant_id", v_board."id", v_me, v_title, v_body, 'visible')
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'post', v_row."id"::text, v_me, 'visible');
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
end;
$$;
revoke execute on function "app_private"."create_post"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."create_post"(uuid, jsonb) to authenticated, service_role;

-- Changes a post's title, body or fields: its author while it isn't locked, or a
-- moderator. Under pre-moderation the author's edit goes back to the queue.
create or replace function "app_private"."update_post"(post_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."posts";
  v_moderator boolean;
  v_title text;
  v_body text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."posts" x where x."id" = update_post.post_id for update;
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
  v_title := case when update_post.attrs ? 'title' then trim(update_post.attrs ->> 'title') else v_row."title" end;
  v_body := case when update_post.attrs ? 'body' then coalesce(update_post.attrs ->> 'body', '') else v_row."body" end;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a post needs a title of 1 to 300 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if length(v_body) > 20000 then
    raise exception 'a post''s body is at most 20000 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  update "app_private"."posts" x set "title" = v_title, "body" = v_body, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
end;
$$;
revoke execute on function "app_private"."update_post"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_post"(uuid, jsonb) to authenticated, service_role;

-- Sets a post's status (open, under_review, planned, in_progress, done or
-- closed), pins or unpins it and locks or unlocks its replies. attrs is
-- { status?, pinned?, locked? }. Moderators only.
create or replace function "app_private"."set_post_state"(post_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."posts";
  v_old "app_private"."posts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."posts" x where x."id" = set_post_state.post_id for update;
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
  update "app_private"."posts" x set
    "status" = coalesce(set_post_state.attrs ->> 'status', x."status"),
    "pinned_at" = case when set_post_state.attrs ? 'pinned' then case when (set_post_state.attrs ->> 'pinned')::boolean then coalesce(x."pinned_at", now()) end else x."pinned_at" end,
    "locked_at" = case when set_post_state.attrs ? 'locked' then case when (set_post_state.attrs ->> 'locked')::boolean then coalesce(x."locked_at", now()) end else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" is distinct from v_old."status" then
    null;
  elsif v_row."pinned_at" is distinct from v_old."pinned_at" or v_row."locked_at" is distinct from v_old."locked_at" then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
exception when check_violation then
  raise exception 'unknown post status' using errcode = '22023', hint = 'POST_INVALID';
end;
$$;
revoke execute on function "app_private"."set_post_state"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_post_state"(uuid, jsonb) to authenticated, service_role;

-- Merges a duplicate into another post on the same board: the duplicate
-- closes and points at the other, and its votes move there unless the voter
-- already voted on it. Replies stay on the duplicate. Moderators only.
create or replace function "app_private"."merge_posts"(source_id uuid, target_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."posts";
  v_target "app_private"."posts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."posts" x where x."id" = merge_posts.source_id for update;
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  select * into v_target from "app_private"."posts" x where x."id" = merge_posts.target_id for update;
  if not found or v_target."board_id" is distinct from v_row."board_id" then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) then
    raise exception 'not allowed to moderate posts' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if v_target."id" = v_row."id" or v_target."merged_into_id" is not null then
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
  update "app_private"."posts" x set "merged_into_id" = v_target."id", "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "app_private"."posts" x set "merged_into_id" = v_target."id", "updated_at" = now()
  where x."merged_into_id" = v_row."id";
  null;
  return jsonb_build_object('id', v_target."id", 'organizationId', v_target."tenant_id", 'boardId', v_target."board_id", 'authorId', v_target."author_id", 'mine', coalesce(v_target."author_id" = (select auth.uid()), false), 'title', v_target."title", 'body', v_target."body", 'status', v_target."status", 'moderation', v_target."moderation_status", 'pinnedAt', v_target."pinned_at", 'lockedAt', v_target."locked_at", 'mergedIntoId', v_target."merged_into_id", 'replyCount', v_target."reply_count", 'lastActivityAt', v_target."last_activity_at", 'createdAt', v_target."created_at", 'updatedAt', v_target."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_target."tenant_id", 'post', v_target."id"::text));
end;
$$;
revoke execute on function "app_private"."merge_posts"(uuid, uuid) from public, anon;
grant execute on function "app_private"."merge_posts"(uuid, uuid) to authenticated, service_role;

-- Deletes a post with its votes: its author, or a moderator. False when
-- there was none.
create or replace function "app_private"."delete_post"(post_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."posts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."posts" x where x."id" = delete_post.post_id for update;
  if not found then
    return false;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to delete this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  delete from "app_private"."posts" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_post"(uuid) from public, anon;
grant execute on function "app_private"."delete_post"(uuid) to authenticated, service_role;
-- One post the caller reads, with its vote tally and the caller's vote, or
-- null.
create or replace function "app_private"."get_post"(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0)))
  from "app_private"."posts" x
  left join "better_supabase"."reaction_scores" s on s."tenant_id" = x."tenant_id" and s."subject_type" = 'post' and s."subject_id" = x."id"::text
  where x."id" = get_post.post_id
$$;
revoke execute on function "app_private"."get_post"(uuid) from public, anon;
grant execute on function "app_private"."get_post"(uuid) to authenticated, service_role;

-- Posts the caller reads. filter is { boardId?, status?, authorId?, sort?,
-- merged?, limit?, offset? }: sort active (pinned first, then the latest
-- activity; the default), new or top (most votes). Merged posts only with
-- merged true.
create or replace function "app_private"."list_posts"(tenant uuid, filter jsonb default '{}')
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
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
      from "app_private"."posts" x
      left join "better_supabase"."reaction_scores" s on s."tenant_id" = x."tenant_id" and s."subject_type" = 'post' and s."subject_id" = x."id"::text
      where x."tenant_id" = list_posts.tenant
        and (v_filter ->> 'boardId' is null or x."board_id" = (v_filter ->> 'boardId')::uuid)
        and (v_filter ->> 'status' is null or x."status" = v_filter ->> 'status')
        and (v_filter ->> 'authorId' is null or x."author_id" = (v_filter ->> 'authorId')::uuid)
        and (coalesce((v_filter ->> 'merged')::boolean, false) or x."merged_into_id" is null)
      order by n
      limit least(greatest(coalesce((v_filter ->> 'limit')::integer, 50), 1), 200)
      offset greatest(coalesce((v_filter ->> 'offset')::integer, 0), 0)
    ) e
  );
end;
$$;
revoke execute on function "app_private"."list_posts"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_posts"(uuid, jsonb) to authenticated, service_role;

-- Sets the caller's vote on a post they read: 1 up, -1 down, 0 clears it.
-- Returns the post's tally. A merged post takes no votes.
create or replace function "app_private"."vote_on_post"(post_id uuid, value integer)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_merged uuid;
begin
  select x."tenant_id", x."merged_into_id" into v_tenant, v_merged
  from "app_private"."posts" x where x."id" = vote_on_post.post_id and x."moderation_status" = 'visible';
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if v_merged is not null then
    raise exception 'the post was merged; vote on the post it was merged into' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return "better_supabase"."vote"(v_tenant, 'post', vote_on_post.post_id::text, vote_on_post.value);
end;
$$;
revoke execute on function "app_private"."vote_on_post"(uuid, integer) from public, anon;
grant execute on function "app_private"."vote_on_post"(uuid, integer) to authenticated, service_role;

-- Projects a post's moderation item onto the post. A moderator's decision
-- records post.moderated.
create or replace function "app_private"."posts_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."posts"%rowtype;
begin
  update "app_private"."posts" x set "moderation_status" = new."status"
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
    and x."moderation_status" is distinct from new."status"
  returning * into v_row;
  if v_row."id" is not null and new."decided_at" is not null then
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."posts_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_moderated" on "better_supabase"."moderation_items";
create trigger "bsb_posts_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'post')
  execute function "app_private"."posts_moderated"();

-- A deleted post takes its moderation item with it.
create or replace function "app_private"."posts_removed"()
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
revoke execute on function "app_private"."posts_removed"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_removed" on "app_private"."posts";
create trigger "bsb_posts_removed"
  after delete on "app_private"."posts"
  for each row execute function "app_private"."posts_removed"();

-- Refuses a reply on a locked, merged or hidden post, unless a moderator
-- writes it.
create or replace function "app_private"."posts_reply_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post "app_private"."posts"%rowtype;
begin
  select x.* into v_post
  from "better_supabase"."conversations" c
  join "app_private"."posts" x on x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id"
  where c."id" = new."conversation_id" and c."subject_type" = 'post';
  if v_post."id" is null then
    return new;
  end if;
  if (v_post."locked_at" is not null or v_post."merged_into_id" is not null or v_post."moderation_status" <> 'visible')
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_post."tenant_id", 'posts.moderate'), false)) then
    raise exception 'the post is locked' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return new;
end;
$$;
revoke execute on function "app_private"."posts_reply_guard"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_reply_guard" on "better_supabase"."messages";
create trigger "bsb_posts_reply_guard"
  before insert on "better_supabase"."messages"
  for each row execute function "app_private"."posts_reply_guard"();

-- Counts a post's sent, undeleted replies and moves its last activity.
create or replace function "app_private"."posts_replied"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "app_private"."posts" x set
    "reply_count" = (
      select count(*) from "better_supabase"."messages" m
      where m."conversation_id" = new."conversation_id"
        and m."sent_at" is not null and m."deleted_at" is null
    ),
    "last_activity_at" = greatest(x."last_activity_at", coalesce(new."sent_at", x."last_activity_at"))
  from "better_supabase"."conversations" c
  where c."id" = new."conversation_id" and c."subject_type" = 'post'
    and x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id";
  return null;
end;
$$;
revoke execute on function "app_private"."posts_replied"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_replied" on "better_supabase"."messages";
create trigger "bsb_posts_replied"
  after insert or update of "sent_at", "deleted_at" on "better_supabase"."messages"
  for each row execute function "app_private"."posts_replied"();

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
drop policy if exists bsb_tenant_scope on "app_private"."post_boards";
drop policy if exists bsb_tenant_scope_select on "app_private"."post_boards";
create policy bsb_tenant_scope_select on "app_private"."post_boards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."post_boards";
create policy bsb_tenant_scope_insert on "app_private"."post_boards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."post_boards";
create policy bsb_tenant_scope_update on "app_private"."post_boards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."post_boards";
create policy bsb_tenant_scope_delete on "app_private"."post_boards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."posts";
drop policy if exists bsb_tenant_scope_select on "app_private"."posts";
create policy bsb_tenant_scope_select on "app_private"."posts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."posts";
create policy bsb_tenant_scope_insert on "app_private"."posts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."posts";
create policy bsb_tenant_scope_update on "app_private"."posts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."posts";
create policy bsb_tenant_scope_delete on "app_private"."posts" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block-data posts
-- @bsb-hash sha256:cf3d9eb13597345e8c143e55724f0dfbbb72694518788ae9544aa9820b826e8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block posts@1 managed
-- @bsb-hash sha256:26d5ebdf3ac3e35e16188e8c5cfce9af18e813eed797e172623f77b43b58927b
-- Forum threads and feedback posts on boards. Replies are comments on the messaging core, votes are reactions, and each post is a moderation item members can report. Feedback posts move through a status from open to done.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Forum and feedback posts on boards. Replies are comments, votes are
-- reactions, and each post is a moderation item.
create table if not exists "better_supabase"."post_boards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- forum: discussion threads; feedback: ideas members vote on, with a status.
  "kind" text not null default 'forum' check ("kind" in ('forum', 'feedback')),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);

create table if not exists "better_supabase"."posts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "board_id" uuid not null references "better_supabase"."post_boards" ("id") on delete cascade,
  "author_id" uuid references auth.users (id) on delete set null,
  "title" text not null check (length("title") between 1 and 300),
  "body" text not null default '' check (length("body") <= 20000),
  "status" text not null default 'open' check ("status" in ('open', 'under_review', 'planned', 'in_progress', 'done', 'closed')),
  -- The moderation item's status, kept in step by a trigger.
  "moderation_status" text not null default 'visible' check ("moderation_status" in ('visible', 'pending', 'hidden', 'removed')),
  "pinned_at" timestamptz,
  "locked_at" timestamptz,
  "merged_into_id" uuid references "better_supabase"."posts" ("id") on delete set null check ("merged_into_id" is distinct from "id"),
  "reply_count" integer not null default 0,
  "last_activity_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "posts_board_idx" on "better_supabase"."posts" ("board_id", "pinned_at" desc nulls last, "last_activity_at" desc);
create index if not exists "posts_tenant_idx" on "better_supabase"."posts" ("tenant_id", "created_at" desc);
create index if not exists "posts_author_idx" on "better_supabase"."posts" ("author_id");
create index if not exists "posts_merged_idx" on "better_supabase"."posts" ("merged_into_id");

alter table "better_supabase"."post_boards" enable row level security;
revoke all on "better_supabase"."post_boards" from public, anon, authenticated;
grant select on "better_supabase"."post_boards" to authenticated;
grant all on "better_supabase"."post_boards" to service_role;
drop policy if exists "post_boards_read" on "better_supabase"."post_boards";
create policy post_boards_read on "better_supabase"."post_boards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')));
alter table "better_supabase"."posts" enable row level security;
revoke all on "better_supabase"."posts" from public, anon, authenticated;
grant select on "better_supabase"."posts" to authenticated;
grant all on "better_supabase"."posts" to service_role;
drop policy if exists "posts_read" on "better_supabase"."posts";
create policy posts_read on "better_supabase"."posts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ));

-- Creates or changes a board. board is { id?, key, name, description, kind,
-- archived }; keys left out keep their value, and the key can't change.
create or replace function "better_supabase"."save_post_board"(tenant uuid, board jsonb)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_post_board.tenant is not null and coalesce(better_supabase.can('tenant', save_post_board.tenant, 'posts.manage'), false))) then
    raise exception 'not allowed to manage boards' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(save_post_board.board) is distinct from 'object' then
    raise exception 'board must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_id := nullif(save_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."post_boards" x where x."id" = v_id and x."tenant_id" = save_post_board.tenant for update;
    if v_old."id" is null then
      raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
    end if;
    if save_post_board.board ? 'key' and save_post_board.board ->> 'key' is distinct from v_old."key" then
      raise exception 'a board''s key can''t change' using errcode = '22023', hint = 'POST_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", save_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(save_post_board.board ->> 'name'), ''), v_old."name");
  v_kind := coalesce(save_post_board.board ->> 'kind', v_old."kind", 'forum');
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
    values (save_post_board.tenant, v_key, v_name, nullif(trim(save_post_board.board ->> 'description'), ''), v_kind,
      case when coalesce((save_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."post_boards" x set
      "name" = v_name,
      "description" = case when save_post_board.board ? 'description' then nullif(trim(save_post_board.board ->> 'description'), '') else x."description" end,
      "kind" = v_kind,
      "archived_at" = case when save_post_board.board ? 'archived' then case when (save_post_board.board ->> 'archived')::boolean then coalesce(x."archived_at", now()) end else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'kind', v_row."kind", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_post_board"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_post_board"(uuid, jsonb) to authenticated, service_role;

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
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
    null;
  elsif v_row."pinned_at" is distinct from v_old."pinned_at" or v_row."locked_at" is distinct from v_old."locked_at" then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
  if v_target."id" = v_row."id" or v_target."merged_into_id" is not null then
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
  null;
  return jsonb_build_object('id', v_target."id", 'organizationId', v_target."tenant_id", 'boardId', v_target."board_id", 'authorId', v_target."author_id", 'mine', coalesce(v_target."author_id" = (select auth.uid()), false), 'title', v_target."title", 'body', v_target."body", 'status', v_target."status", 'moderation', v_target."moderation_status", 'pinnedAt', v_target."pinned_at", 'lockedAt', v_target."locked_at", 'mergedIntoId', v_target."merged_into_id", 'replyCount', v_target."reply_count", 'lastActivityAt', v_target."last_activity_at", 'createdAt', v_target."created_at", 'updatedAt', v_target."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_target."tenant_id", 'post', v_target."id"::text));
end;
$$;
revoke execute on function "better_supabase"."merge_posts"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_posts"(uuid, uuid) to authenticated, service_role;

-- Deletes a post with its votes: its author, or a moderator. False when
-- there was none.
create or replace function "better_supabase"."delete_post"(post_id uuid)
returns boolean
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
  select * into v_row from "better_supabase"."posts" x where x."id" = delete_post.post_id for update;
  if not found then
    return false;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to delete this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  delete from "better_supabase"."posts" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_post"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_post"(uuid) to authenticated, service_role;
-- One post the caller reads, with its vote tally and the caller's vote, or
-- null.
create or replace function "better_supabase"."get_post"(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
-- merged?, limit?, offset? }: sort active (pinned first, then the latest
-- activity; the default), new or top (most votes). Merged posts only with
-- merged true.
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
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
-- Returns the post's tally. A merged post takes no votes.
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
begin
  select x."tenant_id", x."merged_into_id" into v_tenant, v_merged
  from "better_supabase"."posts" x where x."id" = vote_on_post.post_id and x."moderation_status" = 'visible';
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if v_merged is not null then
    raise exception 'the post was merged; vote on the post it was merged into' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return "better_supabase"."vote"(v_tenant, 'post', vote_on_post.post_id::text, vote_on_post.value);
end;
$$;
revoke execute on function "better_supabase"."vote_on_post"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."vote_on_post"(uuid, integer) to authenticated, service_role;

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
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_moderated" on "better_supabase"."moderation_items";
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
drop trigger if exists "bsb_posts_removed" on "better_supabase"."posts";
create trigger "bsb_posts_removed"
  after delete on "better_supabase"."posts"
  for each row execute function "better_supabase"."posts_removed"();

-- Refuses a reply on a locked, merged or hidden post, unless a moderator
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
  if (v_post."locked_at" is not null or v_post."merged_into_id" is not null or v_post."moderation_status" <> 'visible')
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_post."tenant_id", 'posts.moderate'), false)) then
    raise exception 'the post is locked' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."posts_reply_guard"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_reply_guard" on "better_supabase"."messages";
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
        and m."sent_at" is not null and m."deleted_at" is null
    ),
    "last_activity_at" = greatest(x."last_activity_at", coalesce(new."sent_at", x."last_activity_at"))
  from "better_supabase"."conversations" c
  where c."id" = new."conversation_id" and c."subject_type" = 'post'
    and x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_replied"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_replied" on "better_supabase"."messages";
create trigger "bsb_posts_replied"
  after insert or update of "sent_at", "deleted_at" on "better_supabase"."messages"
  for each row execute function "better_supabase"."posts_replied"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
create policy bsb_tenant_scope_select on "better_supabase"."post_boards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
create policy bsb_tenant_scope_insert on "better_supabase"."post_boards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
create policy bsb_tenant_scope_update on "better_supabase"."post_boards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
create policy bsb_tenant_scope_delete on "better_supabase"."post_boards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
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
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
create policy bsb_tenant_scope_insert on "better_supabase"."posts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
create policy bsb_tenant_scope_update on "better_supabase"."posts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
create policy bsb_tenant_scope_delete on "better_supabase"."posts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.posts.api: entry points for the Data API.
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

create or replace function "api"."save_post_board"(tenant uuid, board jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_post_board"($1, $2) $$;
revoke execute on function "api"."save_post_board"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_post_board"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_post_boards"(tenant uuid, archived boolean default false)
returns jsonb
language sql
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

create or replace function "api"."delete_post"(post_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_post"($1) $$;
revoke execute on function "api"."delete_post"(uuid) from public, anon;
grant execute on function "api"."delete_post"(uuid) to authenticated, service_role;

create or replace function "api"."get_post"(post_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_post"($1) $$;
revoke execute on function "api"."get_post"(uuid) from public, anon;
grant execute on function "api"."get_post"(uuid) to authenticated, service_role;

create or replace function "api"."list_posts"(tenant uuid, filter jsonb default '{}')
returns jsonb
language sql
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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block-data posts
-- @bsb-hash sha256:cf3d9eb13597345e8c143e55724f0dfbbb72694518788ae9544aa9820b826e8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block posts@1 managed
-- @bsb-hash sha256:7eeadb8ea6873b1fe767302b23d9661941bd582e6c73161aa8737b54e25bb9c7
-- Forum threads and feedback posts on boards. Replies are comments on the messaging core, votes are reactions, and each post is a moderation item members can report. Feedback posts move through a status from open to done.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Forum and feedback posts on boards. Replies are comments, votes are
-- reactions, and each post is a moderation item.
-- better_supabase.post_boards is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."post_boards" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."post_boards" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."post_boards" add column if not exists "key" text check ("key" ~ '^[a-z0-9][a-z0-9_-]{0,62}$');
alter table "better_supabase"."post_boards" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."post_boards" add column if not exists "description" text check ("description" is null or length("description") <= 2000);
alter table "better_supabase"."post_boards" add column if not exists "kind" text not null default 'forum' check ("kind" in ('forum', 'feedback'));
alter table "better_supabase"."post_boards" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."post_boards" add column if not exists "created_by" uuid;
alter table "better_supabase"."post_boards" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."post_boards" add column if not exists "updated_at" timestamptz not null default now();

-- better_supabase.posts is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."posts" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."posts" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."posts" add column if not exists "board_id" uuid references "better_supabase"."post_boards" ("id") on delete cascade;
alter table "better_supabase"."posts" add column if not exists "author_id" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."posts" add column if not exists "title" text check (length("title") between 1 and 300);
alter table "better_supabase"."posts" add column if not exists "body" text not null default '' check (length("body") <= 20000);
alter table "better_supabase"."posts" add column if not exists "status" text not null default 'open' check ("status" in ('open', 'under_review', 'planned', 'in_progress', 'done', 'closed'));
alter table "better_supabase"."posts" add column if not exists "moderation_status" text not null default 'visible' check ("moderation_status" in ('visible', 'pending', 'hidden', 'removed'));
alter table "better_supabase"."posts" add column if not exists "pinned_at" timestamptz;
alter table "better_supabase"."posts" add column if not exists "locked_at" timestamptz;
alter table "better_supabase"."posts" add column if not exists "merged_into_id" uuid references "better_supabase"."posts" ("id") on delete set null check ("merged_into_id" is distinct from "id");
alter table "better_supabase"."posts" add column if not exists "reply_count" integer not null default 0;
alter table "better_supabase"."posts" add column if not exists "last_activity_at" timestamptz not null default now();
alter table "better_supabase"."posts" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."posts" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "posts_board_idx" on "better_supabase"."posts" ("board_id", "pinned_at" desc nulls last, "last_activity_at" desc);
create index if not exists "posts_tenant_idx" on "better_supabase"."posts" ("tenant_id", "created_at" desc);
create index if not exists "posts_author_idx" on "better_supabase"."posts" ("author_id");
create index if not exists "posts_merged_idx" on "better_supabase"."posts" ("merged_into_id");

alter table "better_supabase"."post_boards" enable row level security;
grant select on "better_supabase"."post_boards" to authenticated;
grant all on "better_supabase"."post_boards" to service_role;
drop policy if exists bsb_post_boards_select on "better_supabase"."post_boards";
create policy bsb_post_boards_select on "better_supabase"."post_boards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')));
alter table "better_supabase"."posts" enable row level security;
grant select on "better_supabase"."posts" to authenticated;
grant all on "better_supabase"."posts" to service_role;
drop policy if exists bsb_posts_select on "better_supabase"."posts";
create policy bsb_posts_select on "better_supabase"."posts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "tenant_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ));

-- Creates or changes a board. board is { id?, key, name, description, kind,
-- archived }; keys left out keep their value, and the key can't change.
create or replace function "better_supabase"."save_post_board"(tenant uuid, board jsonb)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_post_board.tenant is not null and coalesce(better_supabase.can('tenant', save_post_board.tenant, 'posts.manage'), false))) then
    raise exception 'not allowed to manage boards' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(save_post_board.board) is distinct from 'object' then
    raise exception 'board must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_id := nullif(save_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."post_boards" x where x."id" = v_id and x."tenant_id" = save_post_board.tenant for update;
    if v_old."id" is null then
      raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
    end if;
    if save_post_board.board ? 'key' and save_post_board.board ->> 'key' is distinct from v_old."key" then
      raise exception 'a board''s key can''t change' using errcode = '22023', hint = 'POST_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", save_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(save_post_board.board ->> 'name'), ''), v_old."name");
  v_kind := coalesce(save_post_board.board ->> 'kind', v_old."kind"::text, 'forum');
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
    values (save_post_board.tenant, v_key, v_name, nullif(trim(save_post_board.board ->> 'description'), ''), better_supabase.as_column_type(v_kind, (null::"better_supabase"."post_boards")."kind"),
      case when coalesce((save_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."post_boards" x set
      "name" = v_name,
      "description" = case when save_post_board.board ? 'description' then nullif(trim(save_post_board.board ->> 'description'), '') else x."description" end,
      "kind" = better_supabase.as_column_type(v_kind, (null::"better_supabase"."post_boards")."kind"),
      "archived_at" = case when save_post_board.board ? 'archived' then case when (save_post_board.board ->> 'archived')::boolean then coalesce(x."archived_at", now()) end else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'kind', v_row."kind", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_post_board"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_post_board"(uuid, jsonb) to authenticated, service_role;

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
  values (v_board."tenant_id", v_board."id", v_me, v_title, v_body, better_supabase.as_column_type('visible', (null::"better_supabase"."posts")."moderation_status"))
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'post', v_row."id"::text, v_me, 'visible');
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
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
    "status" = coalesce(better_supabase.as_column_type(set_post_state.attrs ->> 'status', (null::"better_supabase"."posts")."status"), x."status"),
    "pinned_at" = case when set_post_state.attrs ? 'pinned' then case when (set_post_state.attrs ->> 'pinned')::boolean then coalesce(x."pinned_at", now()) end else x."pinned_at" end,
    "locked_at" = case when set_post_state.attrs ? 'locked' then case when (set_post_state.attrs ->> 'locked')::boolean then coalesce(x."locked_at", now()) end else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" is distinct from v_old."status" then
    null;
  elsif v_row."pinned_at" is distinct from v_old."pinned_at" or v_row."locked_at" is distinct from v_old."locked_at" then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."tenant_id", 'post', v_row."id"::text));
exception when check_violation or invalid_text_representation then
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
  if v_target."id" = v_row."id" or v_target."merged_into_id" is not null then
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
  update "better_supabase"."posts" x set "merged_into_id" = v_target."id", "status" = better_supabase.as_column_type('closed', (null::"better_supabase"."posts")."status"), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."posts" x set "merged_into_id" = v_target."id", "updated_at" = now()
  where x."merged_into_id" = v_row."id";
  null;
  return jsonb_build_object('id', v_target."id", 'organizationId', v_target."tenant_id", 'boardId', v_target."board_id", 'authorId', v_target."author_id", 'mine', coalesce(v_target."author_id" = (select auth.uid()), false), 'title', v_target."title", 'body', v_target."body", 'status', v_target."status", 'moderation', v_target."moderation_status", 'pinnedAt', v_target."pinned_at", 'lockedAt', v_target."locked_at", 'mergedIntoId', v_target."merged_into_id", 'replyCount', v_target."reply_count", 'lastActivityAt', v_target."last_activity_at", 'createdAt', v_target."created_at", 'updatedAt', v_target."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_target."tenant_id", 'post', v_target."id"::text));
end;
$$;
revoke execute on function "better_supabase"."merge_posts"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_posts"(uuid, uuid) to authenticated, service_role;

-- Deletes a post with its votes: its author, or a moderator. False when
-- there was none.
create or replace function "better_supabase"."delete_post"(post_id uuid)
returns boolean
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
  select * into v_row from "better_supabase"."posts" x where x."id" = delete_post.post_id for update;
  if not found then
    return false;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to delete this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  delete from "better_supabase"."posts" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_post"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_post"(uuid) to authenticated, service_role;
-- One post the caller reads, with its vote tally and the caller's vote, or
-- null.
create or replace function "better_supabase"."get_post"(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
-- merged?, limit?, offset? }: sort active (pinned first, then the latest
-- activity; the default), new or top (most votes). Merged posts only with
-- merged true.
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
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
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
        and (v_filter ->> 'status' is null or x."status"::text = v_filter ->> 'status')
        and (v_filter ->> 'authorId' is null or x."author_id" = (v_filter ->> 'authorId')::uuid)
        and (coalesce((v_filter ->> 'merged')::boolean, false) or x."merged_into_id" is null)
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
-- Returns the post's tally. A merged post takes no votes.
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
begin
  select x."tenant_id", x."merged_into_id" into v_tenant, v_merged
  from "better_supabase"."posts" x where x."id" = vote_on_post.post_id and x."moderation_status" = 'visible';
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if v_merged is not null then
    raise exception 'the post was merged; vote on the post it was merged into' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return "better_supabase"."vote"(v_tenant, 'post', vote_on_post.post_id::text, vote_on_post.value);
end;
$$;
revoke execute on function "better_supabase"."vote_on_post"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."vote_on_post"(uuid, integer) to authenticated, service_role;

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
  update "better_supabase"."posts" x set "moderation_status" = better_supabase.as_column_type(new."status", (null::"better_supabase"."posts")."moderation_status")
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
    and x."moderation_status"::text is distinct from new."status"
  returning * into v_row;
  if v_row."id" is not null and new."decided_at" is not null then
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_moderated" on "better_supabase"."moderation_items";
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
drop trigger if exists "bsb_posts_removed" on "better_supabase"."posts";
create trigger "bsb_posts_removed"
  after delete on "better_supabase"."posts"
  for each row execute function "better_supabase"."posts_removed"();

-- Refuses a reply on a locked, merged or hidden post, unless a moderator
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
  if (v_post."locked_at" is not null or v_post."merged_into_id" is not null or v_post."moderation_status" <> 'visible')
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_post."tenant_id", 'posts.moderate'), false)) then
    raise exception 'the post is locked' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."posts_reply_guard"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_reply_guard" on "better_supabase"."messages";
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
        and m."sent_at" is not null and m."deleted_at" is null
    ),
    "last_activity_at" = greatest(x."last_activity_at", coalesce(new."sent_at", x."last_activity_at"))
  from "better_supabase"."conversations" c
  where c."id" = new."conversation_id" and c."subject_type" = 'post'
    and x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_replied"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_replied" on "better_supabase"."messages";
create trigger "bsb_posts_replied"
  after insert or update of "sent_at", "deleted_at" on "better_supabase"."messages"
  for each row execute function "better_supabase"."posts_replied"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
create policy bsb_tenant_scope_select on "better_supabase"."post_boards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('posts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
create policy bsb_tenant_scope_insert on "better_supabase"."post_boards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
create policy bsb_tenant_scope_update on "better_supabase"."post_boards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
create policy bsb_tenant_scope_delete on "better_supabase"."post_boards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
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
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
create policy bsb_tenant_scope_insert on "better_supabase"."posts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
create policy bsb_tenant_scope_update on "better_supabase"."posts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
create policy bsb_tenant_scope_delete on "better_supabase"."posts" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block-data posts
-- @bsb-hash sha256:cf3d9eb13597345e8c143e55724f0dfbbb72694518788ae9544aa9820b826e8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block posts@1 managed
-- @bsb-hash sha256:e6ced983387e1c1a6771fe4c0e7b06b30552db63bbb13d18697c8f9075dcfba3
-- Forum threads and feedback posts on boards. Replies are comments on the messaging core, votes are reactions, and each post is a moderation item members can report. Feedback posts move through a status from open to done.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Forum and feedback posts on boards. Replies are comments, votes are
-- reactions, and each post is a moderation item.
create table if not exists "better_supabase"."post_boards" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  -- forum: discussion threads; feedback: ideas members vote on, with a status.
  "kind" text not null default 'forum' check ("kind" in ('forum', 'feedback')),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key")
);

create table if not exists "better_supabase"."posts" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "board_id" uuid not null references "better_supabase"."post_boards" ("id") on delete cascade,
  "author_id" uuid references auth.users (id) on delete set null,
  "title" text not null check (length("title") between 1 and 300),
  "body" text not null default '' check (length("body") <= 20000),
  "status" text not null default 'open' check ("status" in ('open', 'under_review', 'planned', 'in_progress', 'done', 'closed')),
  -- The moderation item's status, kept in step by a trigger.
  "moderation_status" text not null default 'visible' check ("moderation_status" in ('visible', 'pending', 'hidden', 'removed')),
  "pinned_at" timestamptz,
  "locked_at" timestamptz,
  "merged_into_id" uuid references "better_supabase"."posts" ("id") on delete set null check ("merged_into_id" is distinct from "id"),
  "reply_count" integer not null default 0,
  "last_activity_at" timestamptz not null default now(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "posts_board_idx" on "better_supabase"."posts" ("board_id", "pinned_at" desc nulls last, "last_activity_at" desc);
create index if not exists "posts_tenant_idx" on "better_supabase"."posts" ("org_id", "created_at" desc);
create index if not exists "posts_author_idx" on "better_supabase"."posts" ("author_id");
create index if not exists "posts_merged_idx" on "better_supabase"."posts" ("merged_into_id");

alter table "better_supabase"."post_boards" enable row level security;
revoke all on "better_supabase"."post_boards" from public, anon, authenticated;
grant select on "better_supabase"."post_boards" to authenticated;
grant all on "better_supabase"."post_boards" to service_role;
drop policy if exists "post_boards_read" on "better_supabase"."post_boards";
create policy post_boards_read on "better_supabase"."post_boards"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('posts.read')));
alter table "better_supabase"."posts" enable row level security;
revoke all on "better_supabase"."posts" from public, anon, authenticated;
grant select on "better_supabase"."posts" to authenticated;
grant all on "better_supabase"."posts" to service_role;
drop policy if exists "posts_read" on "better_supabase"."posts";
create policy posts_read on "better_supabase"."posts"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "org_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ));

-- Creates or changes a board. board is { id?, key, name, description, kind,
-- archived }; keys left out keep their value, and the key can't change.
create or replace function "better_supabase"."save_post_board"(tenant uuid, board jsonb)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_post_board.tenant is not null and coalesce(better_supabase.can('tenant', save_post_board.tenant, 'posts.manage'), false))) then
    raise exception 'not allowed to manage boards' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(save_post_board.board) is distinct from 'object' then
    raise exception 'board must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_id := nullif(save_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."post_boards" x where x."id" = v_id and x."org_id" = save_post_board.tenant for update;
    if v_old."id" is null then
      raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
    end if;
    if save_post_board.board ? 'key' and save_post_board.board ->> 'key' is distinct from v_old."key" then
      raise exception 'a board''s key can''t change' using errcode = '22023', hint = 'POST_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", save_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(save_post_board.board ->> 'name'), ''), v_old."name");
  v_kind := coalesce(save_post_board.board ->> 'kind', v_old."kind", 'forum');
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
    insert into "better_supabase"."post_boards" ("org_id", "key", "name", "description", "kind", "archived_at", "created_by")
    values (save_post_board.tenant, v_key, v_name, nullif(trim(save_post_board.board ->> 'description'), ''), v_kind,
      case when coalesce((save_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."post_boards" x set
      "name" = v_name,
      "description" = case when save_post_board.board ? 'description' then nullif(trim(save_post_board.board ->> 'description'), '') else x."description" end,
      "kind" = v_kind,
      "archived_at" = case when save_post_board.board ? 'archived' then case when (save_post_board.board ->> 'archived')::boolean then coalesce(x."archived_at", now()) end else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'kind', v_row."kind", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_post_board"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_post_board"(uuid, jsonb) to authenticated, service_role;

-- The organization's boards by name; archived ones only when asked.
create or replace function "better_supabase"."list_post_boards"(tenant uuid, archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'description', x."description", 'kind', x."kind", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."post_boards" x
  where x."org_id" = list_post_boards.tenant
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_board."org_id" is not null and coalesce(better_supabase.can('tenant', v_board."org_id", 'posts.write'), false))) or (v_me is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to post on this board' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if v_board."archived_at" is not null then
    raise exception 'the board is archived' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if "better_supabase"."moderation_banned"(v_board."org_id", v_me) then
    raise exception 'you are banned from posting in this organization' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a post needs a title of 1 to 300 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if length(v_body) > 20000 then
    raise exception 'a post''s body is at most 20000 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  insert into "better_supabase"."posts" ("org_id", "board_id", "author_id", "title", "body", "moderation_status")
  values (v_board."org_id", v_board."id", v_me, v_title, v_body, 'visible')
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."org_id", 'post', v_row."id"::text, v_me, 'visible');
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."org_id", 'post', v_row."id"::text));
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
  v_moderator := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'posts.moderate'), false));
  if not v_moderator and (v_row."author_id" is distinct from auth.uid() or v_row."locked_at" is not null) then
    raise exception 'not allowed to change this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(update_post.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'POST_INVALID';
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
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."org_id", 'post', v_row."id"::text));
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'posts.moderate'), false)) then
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
    null;
  elsif v_row."pinned_at" is distinct from v_old."pinned_at" or v_row."locked_at" is distinct from v_old."locked_at" then
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'boardId', v_row."board_id", 'authorId', v_row."author_id", 'mine', coalesce(v_row."author_id" = (select auth.uid()), false), 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'moderation', v_row."moderation_status", 'pinnedAt', v_row."pinned_at", 'lockedAt', v_row."locked_at", 'mergedIntoId', v_row."merged_into_id", 'replyCount', v_row."reply_count", 'lastActivityAt', v_row."last_activity_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_row."org_id", 'post', v_row."id"::text));
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'posts.moderate'), false)) then
    raise exception 'not allowed to moderate posts' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if v_target."id" = v_row."id" or v_target."merged_into_id" is not null then
    raise exception 'merge into another post that wasn''t merged itself' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  insert into "better_supabase"."reactions" ("org_id", "subject_type", "subject_id", "actor", "user_id", "kind", "emoji", "value")
  select r."org_id", r."subject_type", v_target."id"::text, r."actor", r."user_id", r."kind", r."emoji", r."value"
  from "better_supabase"."reactions" r
  where r."org_id" = v_row."org_id" and r."subject_type" = 'post'
    and r."subject_id" = v_row."id"::text and r."kind" = 'vote'
    and not exists (
      select 1 from "better_supabase"."reactions" t
      where t."org_id" = r."org_id" and t."subject_type" = 'post'
        and t."subject_id" = v_target."id"::text and t."kind" = 'vote' and t."actor" = r."actor"
    );
  delete from "better_supabase"."reactions" r
  where r."org_id" = v_row."org_id" and r."subject_type" = 'post'
    and r."subject_id" = v_row."id"::text and r."kind" = 'vote';
  update "better_supabase"."posts" x set "merged_into_id" = v_target."id", "status" = 'closed', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."posts" x set "merged_into_id" = v_target."id", "updated_at" = now()
  where x."merged_into_id" = v_row."id";
  null;
  return jsonb_build_object('id', v_target."id", 'organizationId', v_target."org_id", 'boardId', v_target."board_id", 'authorId', v_target."author_id", 'mine', coalesce(v_target."author_id" = (select auth.uid()), false), 'title', v_target."title", 'body', v_target."body", 'status', v_target."status", 'moderation', v_target."moderation_status", 'pinnedAt', v_target."pinned_at", 'lockedAt', v_target."locked_at", 'mergedIntoId', v_target."merged_into_id", 'replyCount', v_target."reply_count", 'lastActivityAt', v_target."last_activity_at", 'createdAt', v_target."created_at", 'updatedAt', v_target."updated_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(v_target."org_id", 'post', v_target."id"::text));
end;
$$;
revoke execute on function "better_supabase"."merge_posts"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_posts"(uuid, uuid) to authenticated, service_role;

-- Deletes a post with its votes: its author, or a moderator. False when
-- there was none.
create or replace function "better_supabase"."delete_post"(post_id uuid)
returns boolean
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
  select * into v_row from "better_supabase"."posts" x where x."id" = delete_post.post_id for update;
  if not found then
    return false;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'posts.moderate'), false)) or coalesce(v_row."author_id" = auth.uid(), false)) then
    raise exception 'not allowed to delete this post' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  delete from "better_supabase"."posts" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_post"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_post"(uuid) to authenticated, service_role;
-- One post the caller reads, with its vote tally and the caller's vote, or
-- null.
create or replace function "better_supabase"."get_post"(post_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."org_id" = x."org_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0)))
  from "better_supabase"."posts" x
  left join "better_supabase"."reaction_scores" s on s."org_id" = x."org_id" and s."subject_type" = 'post' and s."subject_id" = x."id"::text
  where x."id" = get_post.post_id
$$;
revoke execute on function "better_supabase"."get_post"(uuid) from public, anon;
grant execute on function "better_supabase"."get_post"(uuid) to authenticated, service_role;

-- Posts the caller reads. filter is { boardId?, status?, authorId?, sort?,
-- merged?, limit?, offset? }: sort active (pinned first, then the latest
-- activity; the default), new or top (most votes). Merged posts only with
-- merged true.
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
      select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."org_id" = x."org_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0))) as row,
        row_number() over (order by
          case when v_sort = 'active' then x."pinned_at" end desc nulls last,
          case when v_sort = 'top' then coalesce(s."score", 0) end desc,
          case when v_sort = 'active' then x."last_activity_at" end desc,
          x."created_at" desc, x."id") as n
      from "better_supabase"."posts" x
      left join "better_supabase"."reaction_scores" s on s."org_id" = x."org_id" and s."subject_type" = 'post' and s."subject_id" = x."id"::text
      where x."org_id" = list_posts.tenant
        and (v_filter ->> 'boardId' is null or x."board_id" = (v_filter ->> 'boardId')::uuid)
        and (v_filter ->> 'status' is null or x."status" = v_filter ->> 'status')
        and (v_filter ->> 'authorId' is null or x."author_id" = (v_filter ->> 'authorId')::uuid)
        and (coalesce((v_filter ->> 'merged')::boolean, false) or x."merged_into_id" is null)
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
-- Returns the post's tally. A merged post takes no votes.
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
begin
  select x."org_id", x."merged_into_id" into v_tenant, v_merged
  from "better_supabase"."posts" x where x."id" = vote_on_post.post_id and x."moderation_status" = 'visible';
  if not found then
    raise exception 'no such post' using errcode = 'P0002', hint = 'POST_NOT_FOUND';
  end if;
  if v_merged is not null then
    raise exception 'the post was merged; vote on the post it was merged into' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return "better_supabase"."vote"(v_tenant, 'post', vote_on_post.post_id::text, vote_on_post.value);
end;
$$;
revoke execute on function "better_supabase"."vote_on_post"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."vote_on_post"(uuid, integer) to authenticated, service_role;

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
  where x."id"::text = new."subject_id" and x."org_id" = new."org_id"
    and x."moderation_status" is distinct from new."status"
  returning * into v_row;
  if v_row."id" is not null and new."decided_at" is not null then
    null;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_moderated"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_moderated" on "better_supabase"."moderation_items";
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
  where x."org_id" = old."org_id" and x."subject_type" = 'post' and x."subject_id" = old."id"::text;
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_removed"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_removed" on "better_supabase"."posts";
create trigger "bsb_posts_removed"
  after delete on "better_supabase"."posts"
  for each row execute function "better_supabase"."posts_removed"();

-- Refuses a reply on a locked, merged or hidden post, unless a moderator
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
  join "better_supabase"."posts" x on x."id"::text = c."subject_id" and x."org_id" = c."org_id"
  where c."id" = new."conversation_id" and c."subject_type" = 'post';
  if v_post."id" is null then
    return new;
  end if;
  if (v_post."locked_at" is not null or v_post."merged_into_id" is not null or v_post."moderation_status" <> 'visible')
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_post."org_id", 'posts.moderate'), false)) then
    raise exception 'the post is locked' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."posts_reply_guard"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_reply_guard" on "better_supabase"."messages";
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
        and m."sent_at" is not null and m."deleted_at" is null
    ),
    "last_activity_at" = greatest(x."last_activity_at", coalesce(new."sent_at", x."last_activity_at"))
  from "better_supabase"."conversations" c
  where c."id" = new."conversation_id" and c."subject_type" = 'post'
    and x."id"::text = c."subject_id" and x."org_id" = c."org_id";
  return null;
end;
$$;
revoke execute on function "better_supabase"."posts_replied"() from public, anon, authenticated;
drop trigger if exists "bsb_posts_replied" on "better_supabase"."messages";
create trigger "bsb_posts_replied"
  after insert or update of "sent_at", "deleted_at" on "better_supabase"."messages"
  for each row execute function "better_supabase"."posts_replied"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."post_boards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."post_boards";
create policy bsb_tenant_scope_select on "better_supabase"."post_boards" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('posts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."post_boards";
create policy bsb_tenant_scope_insert on "better_supabase"."post_boards" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."post_boards";
create policy bsb_tenant_scope_update on "better_supabase"."post_boards" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."post_boards";
create policy bsb_tenant_scope_delete on "better_supabase"."post_boards" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."posts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."posts";
create policy bsb_tenant_scope_select on "better_supabase"."posts" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('posts.read')) and (
    "moderation_status" = 'visible'
    or "author_id" = (select auth.uid())
    or "org_id" in (select better_supabase.tenant_ids_with('posts.moderate'))
  ))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."posts";
create policy bsb_tenant_scope_insert on "better_supabase"."posts" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."posts";
create policy bsb_tenant_scope_update on "better_supabase"."posts" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."posts";
create policy bsb_tenant_scope_delete on "better_supabase"."posts" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_140_posts.sql
-- better-supabase module: posts
-- @bsb-block-data posts
-- @bsb-hash sha256:cf3d9eb13597345e8c143e55724f0dfbbb72694518788ae9544aa9820b826e8d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('posts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
