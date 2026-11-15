SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_post"(uuid);

DROP FUNCTION "better_supabase"."delete_post"(uuid);

ALTER TABLE "better_supabase"."posts"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_post (
  post_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_post"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_post (
  post_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_post"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_post (
  post_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_post"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_post (
  post_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_post (
  board_id uuid,
  post     jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_post (
  post_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'boardId', x."board_id", 'authorId', x."author_id", 'mine', coalesce(x."author_id" = (select auth.uid()), false), 'title', x."title", 'body', x."body", 'status', x."status", 'moderation', x."moderation_status", 'pinnedAt', x."pinned_at", 'lockedAt', x."locked_at", 'archivedAt', x."archived_at", 'mergedIntoId', x."merged_into_id", 'replyCount', x."reply_count", 'lastActivityAt', x."last_activity_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('votes', jsonb_build_object('score', coalesce(s."score", 0), 'up', coalesce(s."up", 0), 'down', coalesce(s."down", 0), 'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = x."tenant_id" and r."subject_type" = 'post'
        and r."subject_id" = x."id"::text and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0)))
  from "better_supabase"."posts" x
  left join "better_supabase"."reaction_scores" s on s."tenant_id" = x."tenant_id" and s."subject_type" = 'post' and s."subject_id" = x."id"::text
  where x."id" = get_post.post_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_posts (
  tenant uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_posts (
  source_id uuid,
  target_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.posts_reply_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_post (
  post_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_post (
  post_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_post_state (
  post_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_post (
  post_id uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.vote_on_post (
  post_id uuid,
  value   integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
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
$function$;

REVOKE ALL ON FUNCTION "api"."archive_post"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_post"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_post"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_post"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_post"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_post"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_post"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_post"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_post"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_post"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_post"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_post"(uuid) TO "authenticated", "service_role";
