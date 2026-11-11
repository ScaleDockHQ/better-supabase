SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.comment_count_rows (
  conversations uuid[]
)
  RETURNS TABLE (
    id uuid,
    n  bigint
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  select x."conversation_id", count(*) from "better_supabase"."messages" x
  where x."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (comment_count_rows.conversations) and c."kind" = 'subject'
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else ((coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    or (c."access" = 'subject' and c."subject_type" in ('drive_node')))
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_counts (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_page (
  conversation    uuid,
  after           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows        integer                  DEFAULT 100,
  skip            integer                  DEFAULT 0,
  after_id        uuid                     DEFAULT NULL::uuid,
  include_deleted boolean                  DEFAULT true
)
  RETURNS uuid[]
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = comment_page.conversation and c."kind" = 'subject'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else ((coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    or (c."access" = 'subject' and c."subject_type" in ('drive_node')))
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_comments (
  tenant          uuid,
  subject_type    text,
  subject_id      text,
  after           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows        integer                  DEFAULT 100,
  skip            integer                  DEFAULT 0,
  after_id        uuid                     DEFAULT NULL::uuid,
  include_deleted boolean                  DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  perform "better_supabase"."record_subject_read"(list_comments.subject_type, list_comments.subject_id, null, 'comments', 'list_comments');
  return "better_supabase"."comments_json"("better_supabase"."comment_page"(v_conv, list_comments.after, list_comments.max_rows, list_comments.skip, list_comments.after_id, list_comments.include_deleted));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_comments_unchecked (
  tenant          uuid,
  subject_type    text,
  subject_id      text,
  after           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows        integer                  DEFAULT 100,
  skip            integer                  DEFAULT 0,
  after_id        uuid                     DEFAULT NULL::uuid,
  include_deleted boolean                  DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  perform "better_supabase"."record_subject_read"(list_comments_unchecked.subject_type, list_comments_unchecked.subject_id, null, 'comments', 'list_comments_unchecked');
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_record_mentions (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id    uuid                     DEFAULT NULL::uuid,
  max_rows     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case when not coalesce("better_supabase"."can_subject"(list_record_mentions.subject_type, list_record_mentions.subject_id, 'read'), false)
    then '[]'::jsonb
    else coalesce((
      with p as materialized (
        select x."message_id" as message, x."conversation_id" as conversation, x."created_at" as created_at
        from "better_supabase"."message_record_mentions" x
        where x."subject_type" = list_record_mentions.subject_type and x."subject_id" = list_record_mentions.subject_id
          and (list_record_mentions.before is null
            or (x."created_at", x."message_id") < (list_record_mentions.before, coalesce(list_record_mentions.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
        order by x."created_at" desc, x."message_id" desc
        limit least(greatest(coalesce(list_record_mentions.max_rows, 20), 1), 100)
      ),
      j as materialized (
        select e.row from jsonb_array_elements("better_supabase"."messaging_messages_json"(array(select p.message from p))) e(row)
      )
      select jsonb_agg(jsonb_build_object(
        'message', j.row,
        'conversation', jsonb_build_object('id', c."id", 'kind', c."kind", 'title', c."title", 'subject_type', c."subject_type", 'subject_id', c."subject_id")
      ) order by p.created_at desc, p.message desc)
      from p
      join "better_supabase"."conversations" c on c."id" = p.conversation
      left join j on (j.row ->> 'id')::uuid = p.message
    ), '[]'::jsonb)
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_message_rows (
  ids uuid[]
)
  RETURNS SETOF better_supabase.messages
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select m.* from "better_supabase"."messages" m
  where m."id" = any (messaging_message_rows.ids)
    and m."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct v."conversation_id" from "better_supabase"."messages" v where v."id" = any (messaging_message_rows.ids)))
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else ((coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    or (c."access" = 'subject' and c."subject_type" in ('drive_node')))
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end)
    or (c."kind" = 'subject' and ((c."tenant_id")::text, (c."subject_type")::text, (c."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) end))
    ))
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((m."sent_at" is not null or m."author_id" = (select auth.uid()))
  and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(m."conversation_id"))))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_messages_json (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with checked as materialized (
    select m.* from "better_supabase"."messaging_message_rows"(messaging_messages_json.ids) m
  ),
  page_rows as (
    select k.* from checked k
    where k."conversation_id" = any (array(
      select c."id" from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct v."conversation_id" from checked v))
    ))
  ),
  a as materialized (select "better_supabase"."message_authors"(messaging_messages_json.ids) as authors),
  f as materialized (
    select coalesce(jsonb_object_agg(g.id, g.files), '{}'::jsonb) as files
    from (
      select a."subject_id" as id, jsonb_agg(jsonb_build_object('id', a."id", 'name', a."name", 'mimeType', a."mime_type", 'size', a."size", 'status', a."status") order by a."created_at", a."id") as files
      from "better_supabase"."attachments" a
      where a."subject_type" = 'message'
        and a."subject_id" = any (array(select x."id"::text from page_rows x))
        and a."status" <> 'infected'
      group by a."subject_id"
    ) g
  ),
  r as materialized (
    select coalesce(jsonb_object_agg(g.tenant, "better_supabase"."reaction_summary"(g.tenant, 'message', g.ids)), '{}'::jsonb) as reactions
    from (
      select m."tenant_id" as tenant, array_agg(m."id"::text) as ids from page_rows m group by m."tenant_id"
    ) g
  )
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('author', a.authors -> x.id::text) || jsonb_build_object('attachments', coalesce(f.files -> x.id::text, '[]'::jsonb)) || jsonb_build_object('reactions', coalesce(r.reactions -> x."tenant_id"::text -> x.id::text, '[]'::jsonb)) order by coalesce(x."sent_at", x."scheduled_at", x."created_at"), x."id"), '[]'::jsonb)
  from page_rows x, a, f, r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_messages_json_unchecked (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with page_rows as (
    select m.* from "better_supabase"."messages" m where m."id" = any (messaging_messages_json_unchecked.ids)
  ),
  a as materialized (select "better_supabase"."message_authors"(messaging_messages_json_unchecked.ids) as authors),
  f as materialized (
    select coalesce(jsonb_object_agg(g.id, g.files), '{}'::jsonb) as files
    from (
      select a."subject_id" as id, jsonb_agg(jsonb_build_object('id', a."id", 'name', a."name", 'mimeType', a."mime_type", 'size', a."size", 'status', a."status") order by a."created_at", a."id") as files
      from "better_supabase"."attachments" a
      where a."subject_type" = 'message'
        and a."subject_id" = any (array(select x."id"::text from page_rows x))
        and a."status" <> 'infected'
      group by a."subject_id"
    ) g
  ),
  r as materialized (
    select coalesce(jsonb_object_agg(g.tenant, "better_supabase"."reaction_summary"(g.tenant, 'message', g.ids)), '{}'::jsonb) as reactions
    from (
      select m."tenant_id" as tenant, array_agg(m."id"::text) as ids from page_rows m group by m."tenant_id"
    ) g
  )
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object('author', a.authors -> x.id::text) || jsonb_build_object('attachments', coalesce(f.files -> x.id::text, '[]'::jsonb)) || jsonb_build_object('reactions', coalesce(r.reactions -> x."tenant_id"::text -> x.id::text, '[]'::jsonb)) order by coalesce(x."sent_at", x."scheduled_at", x."created_at"), x."id"), '[]'::jsonb)
  from page_rows x, a, f, r
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."comment_count_rows"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."comment_count_rows"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."comment_page"(uuid, timestamp WITH time zone, integer, integer, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."comment_page"(uuid, timestamp WITH time zone, integer, integer, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamp WITH time zone, integer, integer, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_comments_unchecked"(uuid, text, text, timestamp WITH time zone, integer, integer, uuid, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."messaging_message_rows"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."messaging_message_rows"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."messaging_messages_json_unchecked"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."messaging_messages_json_unchecked"(uuid[]) TO "service_role";
