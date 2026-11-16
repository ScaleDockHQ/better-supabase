SET local check_function_bodies = off;

DROP FUNCTION "api"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text);

DROP FUNCTION "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text);

CREATE OR REPLACE FUNCTION api.get_inbox (
  inbox uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_inbox"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_message_template (
  template uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_message_template"($1) $function$;

CREATE OR REPLACE FUNCTION api.inbox_conversation_tagged (
  conversation uuid,
  tag_ids      uuid[]
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."inbox_conversation_tagged"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_inboxes (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_inboxes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_message_templates (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_message_templates"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_workflow_definitions (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_workflow_definitions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.workflow_runs_list (
  tenant         uuid                     DEFAULT NULL::uuid,
  definition     text                     DEFAULT NULL::text,
  status         text                     DEFAULT NULL::text,
  max            integer                  DEFAULT 50,
  before         timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type   text                     DEFAULT NULL::text,
  subject_id     text                     DEFAULT NULL::text,
  mode           text                     DEFAULT 'live'::text,
  definition_ids text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_runs_list"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_inbox (
  inbox uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
begin
  select to_jsonb(x) into v_row from "better_supabase"."inboxes" x where x."id" = get_inbox.inbox;
  if v_row is null then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_message_template (
  template uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
begin
  select to_jsonb(x) into v_row from "better_supabase"."inbox_message_templates" x where x."id" = get_message_template.template;
  if v_row is null then
    raise exception 'message template not found' using errcode = 'P0002', hint = 'INBOX_TEMPLATE_NOT_FOUND';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_conversation_tagged (
  conversation uuid,
  tag_ids      uuid[]
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1
    from "better_supabase"."inbox_conversations" v
    join "better_supabase"."taggings" g on g."subject_type" = 'conversation' and g."subject_id" = v."id"::text
    where v."id" = inbox_conversation_tagged.conversation
      and g."tag_id" = any (inbox_conversation_tagged.tag_ids)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false), false))
  );
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_inbox_conversations (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_inbox_conversations.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_assignee text := nullif(coalesce(v_filters #>> '{assignee,0}', v_filters ->> 'assignee'), '');
  v_sla_minutes integer;
  v_tags uuid[];
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
  if (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) and exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'priority') = 'array' then v_filters -> 'priority' when jsonb_typeof(v_filters -> 'priority') in ('string', 'number') then jsonb_build_array(v_filters -> 'priority') else '[]'::jsonb end) s where s not in ('low', 'normal', 'high', 'urgent')) then
    raise exception 'priority is low, normal, high or urgent' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) and exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'sla') = 'array' then v_filters -> 'sla' when jsonb_typeof(v_filters -> 'sla') in ('string', 'number') then jsonb_build_array(v_filters -> 'sla') else '[]'::jsonb end) s where s not in ('ok', 'due', 'breached', 'met')) then
    raise exception 'sla is ok, due, breached or met' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'tagId') = 'array' then v_filters -> 'tagId' when jsonb_typeof(v_filters -> 'tagId') in ('string', 'number') then jsonb_build_array(v_filters -> 'tagId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'tagId is a uuid' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if (v_filters -> 'tagId' is not null and jsonb_typeof(v_filters -> 'tagId') <> 'null' and not (jsonb_typeof(v_filters -> 'tagId') = 'array' and jsonb_array_length(v_filters -> 'tagId') = 0)) then
    v_tags := array(select jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'tagId') = 'array' then v_filters -> 'tagId' else jsonb_build_array(v_filters -> 'tagId') end))::uuid[];
  end if;
  v_sla_minutes := 60;
  if nullif(coalesce(v_filters #>> '{slaMinutes,0}', v_filters ->> 'slaMinutes'), '') is not null then
    if nullif(coalesce(v_filters #>> '{slaMinutes,0}', v_filters ->> 'slaMinutes'), '') !~ '^[1-9][0-9]{0,5}$' then
      raise exception 'slaMinutes is a whole number of minutes, at least 1' using errcode = '22023', hint = 'INBOX_INVALID';
    end if;
    v_sla_minutes := nullif(coalesce(v_filters #>> '{slaMinutes,0}', v_filters ->> 'slaMinutes'), '')::integer;
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then v_filters -> 'inboxId' when jsonb_typeof(v_filters -> 'inboxId') in ('string', 'number') then jsonb_build_array(v_filters -> 'inboxId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'teamId') = 'array' then v_filters -> 'teamId' when jsonb_typeof(v_filters -> 'teamId') in ('string', 'number') then jsonb_build_array(v_filters -> 'teamId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'contactId') = 'array' then v_filters -> 'contactId' when jsonb_typeof(v_filters -> 'contactId') in ('string', 'number') then jsonb_build_array(v_filters -> 'contactId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'inboxId, teamId and contactId are uuids' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_assignee is not null and v_assignee not in ('me', 'unassigned') and v_assignee !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    raise exception 'assignee is me, unassigned or an id' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'inboxId', 'priority', 'sla') then
      raise exception 'facet is one of status, inboxId, priority, sla' using errcode = '22023', hint = 'INBOX_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'inboxId' then (x."inbox_id")::text when 'priority' then (x."priority")::text when 'sla' then ((case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end))::text end) as v
      from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
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
      select 1 from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('lastMessageAt', 'createdAt') then
    raise exception 'sort is one of lastMessageAt, createdAt' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."inbox_conversation_json"(x."id") || jsonb_build_object('unread', x."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz)) as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
        and (v_after is null or (x."last_message_at" >= (v_after ->> 0)::timestamptz and ((x."last_message_at" > (v_after ->> 0)::timestamptz) or (x."last_message_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."last_message_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."inbox_conversation_json"(x."id") || jsonb_build_object('unread', x."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz)) as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
        and (v_after is null or (x."last_message_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."last_message_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."inbox_conversation_json"(x."id") || jsonb_build_object('unread', x."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz)) as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
        and (v_after is null or (x."last_message_at" >= (v_after ->> 0)::timestamptz and ((x."last_message_at" > (v_after ->> 0)::timestamptz) or (x."last_message_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."last_message_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."inbox_conversation_json"(x."id") || jsonb_build_object('unread', x."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz)) as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
        and (v_after is null or (x."last_message_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."last_message_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."inbox_conversation_json"(x."id") || jsonb_build_object('unread', x."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."inbox_conversation_json"(x."id") || jsonb_build_object('unread', x."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority" = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'sla' is not null and jsonb_typeof(v_filters -> 'sla') <> 'null' and not (jsonb_typeof(v_filters -> 'sla') = 'array' and jsonb_array_length(v_filters -> 'sla') = 0)) or (case when x."first_response_at" is not null or x."last_inbound_at" is null or x."status" = 'resolved' then 'met'
      when now() - x."last_inbound_at" >= make_interval(mins => v_sla_minutes) then 'breached'
      when now() - x."last_inbound_at" >= make_interval(secs => v_sla_minutes * 30) then 'due'
      else 'ok' end) = any((case when jsonb_typeof(v_filters -> 'sla') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sla')) else array[v_filters ->> 'sla'] end)::text[]))
        and (v_tags is null or "better_supabase"."inbox_conversation_tagged"(x."id", v_tags))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_inboxes (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_inboxes.filters, '{}'::jsonb);
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'channel') = 'array' then v_filters -> 'channel' when jsonb_typeof(v_filters -> 'channel') in ('string', 'number') then jsonb_build_array(v_filters -> 'channel') else '[]'::jsonb end) s where s not in ('in_app', 'email', 'whatsapp', 'slack', 'sms')) or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'botMode') = 'array' then v_filters -> 'botMode' when jsonb_typeof(v_filters -> 'botMode') in ('string', 'number') then jsonb_build_array(v_filters -> 'botMode') else '[]'::jsonb end) s where s not in ('bot', 'human', 'paused')) then
    raise exception 'channel and botMode name a channel and a bot mode' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('channel', 'botMode') then
      raise exception 'facet is one of channel, botMode' using errcode = '22023', hint = 'INBOX_INVALID';
    end if;
    with s as (
      select (case v_facet when 'channel' then (x."channel")::text when 'botMode' then (x."bot_mode")::text end) as v
      from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
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
      select 1 from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
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
      select 1 from "better_supabase"."inboxes" x
      where x."tenant_id" = page_inboxes.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'botMode' is not null and jsonb_typeof(v_filters -> 'botMode') <> 'null' and not (jsonb_typeof(v_filters -> 'botMode') = 'array' and jsonb_array_length(v_filters -> 'botMode') = 0)) or x."bot_mode" = any((case when jsonb_typeof(v_filters -> 'botMode') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'botMode')) else array[v_filters ->> 'botMode'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."channel_address" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_message_templates (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_message_templates.filters, '{}'::jsonb);
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then v_filters -> 'inboxId' when jsonb_typeof(v_filters -> 'inboxId') in ('string', 'number') then jsonb_build_array(v_filters -> 'inboxId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'inboxId is a uuid' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('channel', 'language') then
      raise exception 'facet is one of channel, language' using errcode = '22023', hint = 'INBOX_INVALID';
    end if;
    with s as (
      select (case v_facet when 'channel' then (x."channel")::text when 'language' then (x."language")::text end) as v
      from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
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
      select 1 from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INBOX_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
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
      select 1 from "better_supabase"."inbox_message_templates" x
      where x."tenant_id" = page_message_templates.tenant
        and (not (v_filters -> 'channel' is not null and jsonb_typeof(v_filters -> 'channel') <> 'null' and not (jsonb_typeof(v_filters -> 'channel') = 'array' and jsonb_array_length(v_filters -> 'channel') = 0)) or x."channel" = any((case when jsonb_typeof(v_filters -> 'channel') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'channel')) else array[v_filters ->> 'channel'] end)::text[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or x."language" = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_workflow_definitions (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_workflow_definitions.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('state') then
      raise exception 'facet is one of state' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
    end if;
    with s as (
      select (case v_facet when 'state' then ((case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end))::text end) as v
      from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
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
      select 1 from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'createdAt') then
    raise exception 'sort is one of name, updatedAt, createdAt' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'purpose', x."purpose",
    'isDefault', x."is_default",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published'),
      'behind', coalesce((select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published') > x."forked_from_version", false),
      'optedOut', case when page_workflow_definitions.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = page_workflow_definitions.tenant and oo."definition_id" = x."id") end) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'purpose', x."purpose",
    'isDefault', x."is_default",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published'),
      'behind', coalesce((select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published') > x."forked_from_version", false),
      'optedOut', case when page_workflow_definitions.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = page_workflow_definitions.tenant and oo."definition_id" = x."id") end) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'purpose', x."purpose",
    'isDefault', x."is_default",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published'),
      'behind', coalesce((select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published') > x."forked_from_version", false),
      'optedOut', case when page_workflow_definitions.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = page_workflow_definitions.tenant and oo."definition_id" = x."id") end) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'purpose', x."purpose",
    'isDefault', x."is_default",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published'),
      'behind', coalesce((select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published') > x."forked_from_version", false),
      'optedOut', case when page_workflow_definitions.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = page_workflow_definitions.tenant and oo."definition_id" = x."id") end) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'purpose', x."purpose",
    'isDefault', x."is_default",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published'),
      'behind', coalesce((select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published') > x."forked_from_version", false),
      'optedOut', case when page_workflow_definitions.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = page_workflow_definitions.tenant and oo."definition_id" = x."id") end) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'purpose', x."purpose",
    'isDefault', x."is_default",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published'),
      'behind', coalesce((select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published') > x."forked_from_version", false),
      'optedOut', case when page_workflow_definitions.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = page_workflow_definitions.tenant and oo."definition_id" = x."id") end) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'purpose', x."purpose",
    'isDefault', x."is_default",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published'),
      'behind', coalesce((select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published') > x."forked_from_version", false),
      'optedOut', case when page_workflow_definitions.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = page_workflow_definitions.tenant and oo."definition_id" = x."id") end) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WORKFLOW_LIST_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'subjectTypes', to_jsonb(x."subject_types"),
    'scope', x."scope",
    'forkedFrom', x."forked_from",
    'forkedFromVersion', x."forked_from_version",
    'restricted', x."restricted",
    'purpose', x."purpose",
    'isDefault', x."is_default",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft'),
      'upstreamVersion', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published'),
      'behind', coalesce((select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."forked_from" and y."status" = 'published') > x."forked_from_version", false),
      'optedOut', case when page_workflow_definitions.tenant is null then null else exists (select 1 from "better_supabase"."workflow_opt_outs" oo where oo."tenant_id" = page_workflow_definitions.tenant and oo."definition_id" = x."id") end) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
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
      select 1 from "better_supabase"."workflow_definitions" x
      where (page_workflow_definitions.tenant is null or x."tenant_id" = page_workflow_definitions.tenant or x."scope" = 'system')
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (case when (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published') is not null then 'published' when exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft') then 'draft' else 'new' end) = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_list (
  tenant         uuid                     DEFAULT NULL::uuid,
  definition     text                     DEFAULT NULL::text,
  status         text                     DEFAULT NULL::text,
  max            integer                  DEFAULT 50,
  before         timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type   text                     DEFAULT NULL::text,
  subject_id     text                     DEFAULT NULL::text,
  mode           text                     DEFAULT 'live'::text,
  definition_ids text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at",
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'mode', x."mode",
    'triggerNode', x."trigger_node",
    'idempotencyKey', x."idempotency_key"
  ) order by x."created_at" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."workflow_runs" y
    where (workflow_runs_list.tenant is null or y."tenant_id" = workflow_runs_list.tenant)
      and (workflow_runs_list.definition is null or y."definition" = workflow_runs_list.definition)
      and (workflow_runs_list.status is null or y."status" = workflow_runs_list.status)
      and (workflow_runs_list.before is null or y."created_at" < workflow_runs_list.before)
      and (workflow_runs_list.definition_ids is null or cardinality(workflow_runs_list.definition_ids) = 0 or y."attributes" ->> 'bsb.definition' = any (workflow_runs_list.definition_ids))
      and (workflow_runs_list.subject_type is null or y."subject_type" = workflow_runs_list.subject_type)
      and (workflow_runs_list.subject_id is null or y."subject_id" = workflow_runs_list.subject_id)
      and (workflow_runs_list.mode is null or y."mode" = workflow_runs_list.mode)
    order by y."created_at" desc
    limit least(greatest(coalesce(workflow_runs_list.max, 50), 1), 500)
  ) x;
$function$;

CREATE INDEX workflow_runs_definition_id_idx ON better_supabase.workflow_runs USING btree (((attributes ->> 'bsb.definition'::text)), created_at DESC, id DESC);

REVOKE ALL ON FUNCTION "api"."get_inbox"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_inbox"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_message_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_message_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."inbox_conversation_tagged"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."inbox_conversation_tagged"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_inboxes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_inboxes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_message_templates"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_message_templates"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_workflow_definitions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_workflow_definitions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_inbox"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_inbox"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_message_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_message_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_conversation_tagged"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_conversation_tagged"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_inboxes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_inboxes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_message_templates"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_message_templates"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_workflow_definitions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_workflow_definitions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone, text, text, text, text[]) TO "authenticated", "service_role";
