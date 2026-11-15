SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_ai_project (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_project"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_provider_key (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_provider_key"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_task (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_task"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_conversation_summary (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_conversation_summary"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_guardrail_policy_by_id (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_guardrail_policy_by_id"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_knowledge_collection (
  collection_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_knowledge_collection"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_memory (
  memory_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_memory"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_agents (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_agents"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_ai_batches (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_ai_batches"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_ai_chats (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_ai_chats"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_ai_files (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_ai_files"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_ai_projects (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_ai_projects"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_ai_provider_keys (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_ai_provider_keys"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_ai_tasks (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_ai_tasks"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_channels (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_channels"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_conversations (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_conversations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_eval_datasets (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_eval_datasets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_eval_runs (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_eval_runs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_guardrail_decisions (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_guardrail_decisions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_guardrail_policies (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_guardrail_policies"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_inbox_conversations (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_inbox_conversations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_knowledge_collections (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_knowledge_collections"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_knowledge_documents (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_knowledge_documents"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_memories (
  tenant  uuid,
  ns      jsonb DEFAULT '{}'::jsonb,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_memories"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.page_post_boards (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_post_boards"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_posts (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_posts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_project (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_projects" x
  where x."id" = get_ai_project.id and x."owner_id" = (select auth.uid())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_provider_key (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_provider_keys" x where x."id" = get_ai_provider_key.id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_task (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  ))
  from "better_supabase"."ai_scheduled_tasks" x where x."id" = get_ai_task.id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_conversation_summary (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(c) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid() and m."conversation_id" = c."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid() and m."conversation_id" = c."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid())
    )
  from "better_supabase"."conversations" c
  where c."id" = get_conversation_summary.conversation
    and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_guardrail_policy_by_id (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") from "better_supabase"."guardrail_policies" x where x."id" = get_guardrail_policy_by_id.id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_knowledge_collection (
  collection_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."knowledge_collections" x where x."id" = get_knowledge_collection.collection_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_memory (
  memory_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."memories" x
  where x."id" = get_memory.memory_id and x."archived_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_agents (
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
  v_filters jsonb := coalesce(page_agents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_mode text := coalesce(nullif(coalesce(v_filters #>> '{mode,0}', v_filters ->> 'mode'), ''), 'store');
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
  if v_mode not in ('store', 'mine', 'installed') then
    raise exception 'mode is store, mine or installed' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'visibility') = 'array' then v_filters -> 'visibility' when jsonb_typeof(v_filters -> 'visibility') in ('string', 'number') then jsonb_build_array(v_filters -> 'visibility') else '[]'::jsonb end) s where s not in ('private', 'organization', 'public')) then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
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
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt', 'createdAt', 'installCount') then
    raise exception 'sort is one of name, updatedAt, createdAt, installCount' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at"), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."updated_at") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."published_at", x."updated_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."updated_at") <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."updated_at") < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."updated_at") = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."updated_at") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by coalesce(x."install_count", 0) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'installCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)) as j, jsonb_build_array((coalesce(x."install_count", 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (coalesce(x."install_count", 0) <= (v_after ->> 0)::integer and ((coalesce(x."install_count", 0) < (v_after ->> 0)::integer) or (coalesce(x."install_count", 0) = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."install_count", 0) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."agents" x
      where case v_mode
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = page_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = page_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = page_agents.tenant)
      end
        and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_ai_batches (
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
  v_filters jsonb := coalesce(page_ai_batches.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'provider') then
      raise exception 'facet is one of status, provider' using errcode = '22023', hint = 'AI_BATCH_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'provider' then (x."provider")::text end) as v
      from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
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
      select 1 from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'provider', 'status') then
    raise exception 'sort is one of createdAt, provider, status' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'provider' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."provider", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."provider" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'provider' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."provider" <= (v_after ->> 0)::text and ((x."provider" < (v_after ->> 0)::text) or (x."provider" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."provider" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'status' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."status")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."status", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."status" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'status' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_BATCH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."status")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (v_after is null or (x."status" <= (v_after ->> 0)::text and ((x."status" < (v_after ->> 0)::text) or (x."status" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."status" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."ai_batches" x
      where x."tenant_id" = page_ai_batches.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_ai_chats (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_filters jsonb := coalesce(page_ai_chats.filters, '{}'::jsonb);
  v_project text := nullif(coalesce(v_filters #>> '{projectId,0}', v_filters ->> 'projectId'), '');
  v_query tsquery;
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
  if v_uid is null then
    return case when v_paged then jsonb_build_object('items', '[]'::jsonb, 'hasMore', false, 'nextCursor', null) else '[]'::jsonb end;
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'projectId') = 'array' then v_filters -> 'projectId' when jsonb_typeof(v_filters -> 'projectId') in ('string', 'number') then jsonb_build_array(v_filters -> 'projectId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'projectId is a uuid' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if nullif(btrim(v_filters ->> 'search'), '') is not null then
    v_query := websearch_to_tsquery('simple'::regconfig, v_filters ->> 'search');
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('pinned', 'archived') then
      raise exception 'facet is one of pinned, archived' using errcode = '22023', hint = 'AI_CHAT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'pinned' then (x."pinned")::text when 'archived' then ((x."archived_at" is not null))::text end) as v
      from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
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
      select 1 from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('lastMessageAt', 'createdAt', 'title') then
    raise exception 'sort is one of lastMessageAt, createdAt, title' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'project_id', x."project_id", 'agent_id', x."agent_id", 'title', x."title", 'model', x."model", 'visibility', x."visibility", 'mode', x."mode", 'pinned', x."pinned", 'archived_at', x."archived_at", 'is_temporary', x."is_temporary", 'expires_at', x."expires_at", 'current_leaf_id', x."current_leaf_id", 'active_stream_id', x."active_stream_id", 'active_run_id', x."active_run_id", 'last_message_at', x."last_message_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
        and (v_after is null or (x."last_message_at" >= (v_after ->> 0)::timestamptz and ((x."last_message_at" > (v_after ->> 0)::timestamptz) or (x."last_message_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."last_message_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'project_id', x."project_id", 'agent_id', x."agent_id", 'title', x."title", 'model', x."model", 'visibility', x."visibility", 'mode', x."mode", 'pinned', x."pinned", 'archived_at', x."archived_at", 'is_temporary', x."is_temporary", 'expires_at', x."expires_at", 'current_leaf_id', x."current_leaf_id", 'active_stream_id', x."active_stream_id", 'active_run_id', x."active_run_id", 'last_message_at', x."last_message_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
        and (v_after is null or (x."last_message_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."last_message_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'project_id', x."project_id", 'agent_id', x."agent_id", 'title', x."title", 'model', x."model", 'visibility', x."visibility", 'mode', x."mode", 'pinned', x."pinned", 'archived_at', x."archived_at", 'is_temporary', x."is_temporary", 'expires_at', x."expires_at", 'current_leaf_id', x."current_leaf_id", 'active_stream_id', x."active_stream_id", 'active_run_id', x."active_run_id", 'last_message_at', x."last_message_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
        and (v_after is null or (x."last_message_at" >= (v_after ->> 0)::timestamptz and ((x."last_message_at" > (v_after ->> 0)::timestamptz) or (x."last_message_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."last_message_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'project_id', x."project_id", 'agent_id', x."agent_id", 'title', x."title", 'model', x."model", 'visibility', x."visibility", 'mode', x."mode", 'pinned', x."pinned", 'archived_at', x."archived_at", 'is_temporary', x."is_temporary", 'expires_at', x."expires_at", 'current_leaf_id', x."current_leaf_id", 'active_stream_id', x."active_stream_id", 'active_run_id', x."active_run_id", 'last_message_at', x."last_message_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."last_message_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
        and (v_after is null or (x."last_message_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."last_message_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'project_id', x."project_id", 'agent_id', x."agent_id", 'title', x."title", 'model', x."model", 'visibility', x."visibility", 'mode', x."mode", 'pinned', x."pinned", 'archived_at', x."archived_at", 'is_temporary', x."is_temporary", 'expires_at', x."expires_at", 'current_leaf_id', x."current_leaf_id", 'active_stream_id', x."active_stream_id", 'active_run_id', x."active_run_id", 'last_message_at', x."last_message_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'project_id', x."project_id", 'agent_id', x."agent_id", 'title', x."title", 'model', x."model", 'visibility', x."visibility", 'mode', x."mode", 'pinned', x."pinned", 'archived_at', x."archived_at", 'is_temporary', x."is_temporary", 'expires_at', x."expires_at", 'current_leaf_id', x."current_leaf_id", 'active_stream_id', x."active_stream_id", 'active_run_id', x."active_run_id", 'last_message_at', x."last_message_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'project_id', x."project_id", 'agent_id', x."agent_id", 'title', x."title", 'model', x."model", 'visibility', x."visibility", 'mode', x."mode", 'pinned', x."pinned", 'archived_at', x."archived_at", 'is_temporary', x."is_temporary", 'expires_at', x."expires_at", 'current_leaf_id', x."current_leaf_id", 'active_stream_id', x."active_stream_id", 'active_run_id', x."active_run_id", 'last_message_at', x."last_message_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(coalesce(x."title", '')))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
        and (v_after is null or (lower(coalesce(x."title", '')) >= (v_after ->> 0)::text and ((lower(coalesce(x."title", '')) > (v_after ->> 0)::text) or (lower(coalesce(x."title", '')) = (v_after ->> 0)::text and x."id" < (v_after ->> 1)::uuid))))
      order by lower(coalesce(x."title", '')) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'project_id', x."project_id", 'agent_id', x."agent_id", 'title', x."title", 'model', x."model", 'visibility', x."visibility", 'mode', x."mode", 'pinned', x."pinned", 'archived_at', x."archived_at", 'is_temporary', x."is_temporary", 'expires_at', x."expires_at", 'current_leaf_id', x."current_leaf_id", 'active_stream_id', x."active_stream_id", 'active_run_id', x."active_run_id", 'last_message_at', x."last_message_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(coalesce(x."title", '')))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
        and (v_after is null or (lower(coalesce(x."title", '')), x."id") < ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(coalesce(x."title", '')) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."ai_chats" x
      where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."tenant_id" is null or x."tenant_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."tenant_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
        and not x."is_temporary"
        and x."tenant_id" = page_ai_chats.tenant
        and (v_project is null or x."project_id" = v_project::uuid)
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_query is null or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_ai_files (
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
  v_filters jsonb := coalesce(page_ai_files.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_chat text := nullif(coalesce(v_filters #>> '{chatId,0}', v_filters ->> 'chatId'), '');
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'chatId') = 'array' then v_filters -> 'chatId' when jsonb_typeof(v_filters -> 'chatId') in ('string', 'number') then jsonb_build_array(v_filters -> 'chatId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'chatId is a uuid' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'source', 'mediaType') then
      raise exception 'facet is one of status, source, mediaType' using errcode = '22023', hint = 'AI_FILE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'source' then (x."source")::text when 'mediaType' then (x."media_type")::text end) as v
      from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
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
      select 1 from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'filename', 'size') then
    raise exception 'sort is one of createdAt, filename, size' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'filename' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") as j, jsonb_build_array((lower(x."filename"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
        and (v_after is null or (lower(x."filename"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."filename") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'filename' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") as j, jsonb_build_array((lower(x."filename"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
        and (v_after is null or (lower(x."filename") <= (v_after ->> 0)::text and ((lower(x."filename") < (v_after ->> 0)::text) or (lower(x."filename") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."filename") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'size' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") as j, jsonb_build_array((x."byte_size")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
        and (v_after is null or (x."byte_size", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."byte_size" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'size' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_FILE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") as j, jsonb_build_array((x."byte_size")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
        and (v_after is null or (x."byte_size" <= (v_after ->> 0)::bigint and ((x."byte_size" < (v_after ->> 0)::bigint) or (x."byte_size" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."byte_size" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."ai_files" x
      where x."tenant_id" = page_ai_files.tenant
        and (v_chat is null or x."chat_id" = v_chat::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'source' is not null and jsonb_typeof(v_filters -> 'source') <> 'null' and not (jsonb_typeof(v_filters -> 'source') = 'array' and jsonb_array_length(v_filters -> 'source') = 0)) or x."source"::text = any((case when jsonb_typeof(v_filters -> 'source') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'source')) else array[v_filters ->> 'source'] end)::text[]))
        and (not (v_filters -> 'mediaType' is not null and jsonb_typeof(v_filters -> 'mediaType') <> 'null' and not (jsonb_typeof(v_filters -> 'mediaType') = 'array' and jsonb_array_length(v_filters -> 'mediaType') = 0)) or x."media_type" = any((case when jsonb_typeof(v_filters -> 'mediaType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'mediaType')) else array[v_filters ->> 'mediaType'] end)::text[]))
        and (v_search is null or x."filename" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_ai_projects (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_uid uuid := (select auth.uid());
  v_filters jsonb := coalesce(page_ai_projects.filters, '{}'::jsonb);
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
  if v_uid is null then
    return case when v_paged then jsonb_build_object('items', '[]'::jsonb, 'hasMore', false, 'nextCursor', null) else '[]'::jsonb end;
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('pinned', 'archived') then
      raise exception 'facet is one of pinned, archived' using errcode = '22023', hint = 'AI_CHAT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'pinned' then (x."pinned")::text when 'archived' then ((x."archived_at" is not null))::text end) as v
      from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
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
      select 1 from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('updatedAt', 'name') then
    raise exception 'sort is one of updatedAt, name' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."pinned")::text, (x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."pinned" >= (v_after ->> 0)::boolean and ((x."pinned" > (v_after ->> 0)::boolean) or (x."pinned" = (v_after ->> 0)::boolean and x."updated_at" < (v_after ->> 1)::timestamptz) or (x."pinned" = (v_after ->> 0)::boolean and x."updated_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."pinned" asc, x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."pinned")::text, (x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."pinned" <= (v_after ->> 0)::boolean and ((x."pinned" < (v_after ->> 0)::boolean) or (x."pinned" = (v_after ->> 0)::boolean and x."updated_at" < (v_after ->> 1)::timestamptz) or (x."pinned" = (v_after ->> 0)::boolean and x."updated_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."pinned" desc, x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organization_id', x."tenant_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."ai_projects" x
      where x."owner_id" = v_uid
        and x."tenant_id" is not distinct from page_ai_projects.tenant
        and (not (v_filters -> 'pinned' is not null and jsonb_typeof(v_filters -> 'pinned') <> 'null' and not (jsonb_typeof(v_filters -> 'pinned') = 'array' and jsonb_array_length(v_filters -> 'pinned') = 0)) or x."pinned"::text = any((case when jsonb_typeof(v_filters -> 'pinned') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'pinned')) else array[v_filters ->> 'pinned'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else not (x."archived_at" is not null) end)
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_ai_provider_keys (
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
  v_filters jsonb := coalesce(page_ai_provider_keys.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('provider', 'enabled') then
      raise exception 'facet is one of provider, enabled' using errcode = '22023', hint = 'AI_KEYS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'provider' then (x."provider")::text when 'enabled' then (x."enabled"::text)::text end) as v
      from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
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
      select 1 from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('provider', 'name', 'createdAt') then
    raise exception 'sort is one of provider, name, createdAt' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."provider", lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."provider" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."provider" <= (v_after ->> 0)::text and ((x."provider" < (v_after ->> 0)::text) or (x."provider" = (v_after ->> 0)::text and lower(x."name") > (v_after ->> 1)::text) or (x."provider" = (v_after ->> 0)::text and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."provider" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'provider' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."provider", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."provider" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'provider' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."provider")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."provider" <= (v_after ->> 0)::text and ((x."provider" < (v_after ->> 0)::text) or (x."provider" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."provider" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_KEYS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
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
      select 1 from "better_supabase"."ai_provider_keys" x
      where x."tenant_id" = page_ai_provider_keys.tenant
        and (not (v_filters -> 'provider' is not null and jsonb_typeof(v_filters -> 'provider') <> 'null' and not (jsonb_typeof(v_filters -> 'provider') = 'array' and jsonb_array_length(v_filters -> 'provider') = 0)) or x."provider" = any((case when jsonb_typeof(v_filters -> 'provider') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provider')) else array[v_filters ->> 'provider'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."provider" ilike v_search or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_ai_tasks (
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
  v_filters jsonb := coalesce(page_ai_tasks.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('enabled') then
      raise exception 'facet is one of enabled' using errcode = '22023', hint = 'AI_TASK_INVALID';
    end if;
    with s as (
      select (case v_facet when 'enabled' then (x."enabled")::text end) as v
      from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
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
      select 1 from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'title', 'nextRunAt') then
    raise exception 'sort is one of createdAt, title, nextRunAt' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextRunAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((coalesce(x."next_run_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (coalesce(x."next_run_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."next_run_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextRunAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((coalesce(x."next_run_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (coalesce(x."next_run_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."next_run_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."next_run_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."next_run_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_channels (
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
  v_filters jsonb := coalesce(page_channels.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'CHANNEL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
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
      select 1 from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt', 'lastMessageAt') then
    raise exception 'sort is one of name, createdAt, lastMessageAt' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) from "better_supabase"."conversations" c where c."id" = x."id") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) from "better_supabase"."conversations" c where c."id" = x."id") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) from "better_supabase"."conversations" c where c."id" = x."id") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) from "better_supabase"."conversations" c where c."id" = x."id") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) from "better_supabase"."conversations" c where c."id" = x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) from "better_supabase"."conversations" c where c."id" = x."id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) from "better_supabase"."conversations" c where c."id" = x."id") as j, jsonb_build_array((coalesce((select c."last_message_at" from "better_supabase"."conversations" c where c."id" = x."id"), 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
        and (v_after is null or (coalesce((select c."last_message_at" from "better_supabase"."conversations" c where c."id" = x."id"), 'epoch'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce((select c."last_message_at" from "better_supabase"."conversations" c where c."id" = x."id"), 'epoch'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CHANNEL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select to_jsonb(x) || jsonb_build_object(
      'archivedAt', c."archived_at",
      'lastMessageAt', c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = c."id")
    ) from "better_supabase"."conversations" c where c."id" = x."id") as j, jsonb_build_array((coalesce((select c."last_message_at" from "better_supabase"."conversations" c where c."id" = x."id"), 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
        and (v_after is null or (coalesce((select c."last_message_at" from "better_supabase"."conversations" c where c."id" = x."id"), 'epoch'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce((select c."last_message_at" from "better_supabase"."conversations" c where c."id" = x."id"), 'epoch'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce((select c."last_message_at" from "better_supabase"."conversations" c where c."id" = x."id"), 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce((select c."last_message_at" from "better_supabase"."conversations" c where c."id" = x."id"), 'epoch'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."channels" x
      where x."tenant_id" = page_channels.tenant
        and exists (select 1 from "better_supabase"."conversations" c where c."id" = x."id" and (coalesce(nullif(coalesce(v_filters #>> '{includeArchived,0}', v_filters ->> 'includeArchived'), '') = 'true', false) or c."archived_at" is null))
        and (coalesce(nullif(coalesce(v_filters #>> '{browse,0}', v_filters ->> 'browse'), '') = 'true', false) or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()))
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility"::text = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."topic" ilike v_search or x."purpose" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_conversations (
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
  v_filters jsonb := coalesce(page_conversations.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'MESSAGING_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text end) as v
      from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
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
      select 1 from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('lastMessageAt', 'createdAt', 'title') then
    raise exception 'sort is one of lastMessageAt, createdAt, title' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
    ) as j, jsonb_build_array((coalesce(x."last_message_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."last_message_at", 'epoch'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."last_message_at", 'epoch'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
    ) as j, jsonb_build_array((coalesce(x."last_message_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."last_message_at", 'epoch'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."last_message_at", 'epoch'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."last_message_at", 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."last_message_at", 'epoch'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
    ) as j, jsonb_build_array((coalesce(x."last_message_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."last_message_at", 'epoch'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."last_message_at", 'epoch'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastMessageAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
    ) as j, jsonb_build_array((coalesce(x."last_message_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."last_message_at", 'epoch'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."last_message_at", 'epoch'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."last_message_at", 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."last_message_at", 'epoch'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
    ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
    ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
    ) as j, jsonb_build_array((lower(coalesce(x."title", '')))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(coalesce(x."title", '')), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(coalesce(x."title", '')) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MESSAGING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object(
      'unread', (select count(*) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'mentions', (select count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) from "better_supabase"."messages" m, "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid() and m."conversation_id" = x."id" and (m."thread_id" is null or m."broadcast") and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz) and m."archived_at" is null and m."author_id" is distinct from auth.uid()),
      'lastReadAt', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid()),
      'notify', (select k."notify" from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
    ) as j, jsonb_build_array((lower(coalesce(x."title", '')))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(coalesce(x."title", '')) <= (v_after ->> 0)::text and ((lower(coalesce(x."title", '')) < (v_after ->> 0)::text) or (lower(coalesce(x."title", '')) = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(coalesce(x."title", '')) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."conversations" x
      where x."tenant_id" = page_conversations.tenant
        and exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = x."id" and k."user_id" = auth.uid())
        and (case when not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then x."kind" <> 'inbox' else (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) end)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_eval_datasets (
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
  v_filters jsonb := coalesce(page_eval_datasets.filters, '{}'::jsonb);
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'id') = 'array' then v_filters -> 'id' when jsonb_typeof(v_filters -> 'id') in ('string', 'number') then jsonb_build_array(v_filters -> 'id') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'id is a uuid' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt', 'lastRunAt') then
    raise exception 'sort is one of name, createdAt, lastRunAt' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastRunAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastRunAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_eval_runs (
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
  v_filters jsonb := coalesce(page_eval_runs.filters, '{}'::jsonb);
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then v_filters -> 'datasetId' when jsonb_typeof(v_filters -> 'datasetId') in ('string', 'number') then jsonb_build_array(v_filters -> 'datasetId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'datasetId is a uuid' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'model', 'promptName') then
      raise exception 'facet is one of status, model, promptName' using errcode = '22023', hint = 'AI_EVAL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'model' then (x."model")::text when 'promptName' then (x."prompt_name")::text end) as v
      from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
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
      select 1 from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'finishedAt') then
    raise exception 'sort is one of createdAt, finishedAt' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'finishedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((coalesce(x."finished_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (coalesce(x."finished_at", 'epoch'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."finished_at", 'epoch'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."finished_at", 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."finished_at", 'epoch'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'finishedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((coalesce(x."finished_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (coalesce(x."finished_at", 'epoch'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."finished_at", 'epoch'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_guardrail_decisions (
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
  v_filters jsonb := coalesce(page_guardrail_decisions.filters, '{}'::jsonb);
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'decision') = 'array' then v_filters -> 'decision' when jsonb_typeof(v_filters -> 'decision') in ('string', 'number') then jsonb_build_array(v_filters -> 'decision') else '[]'::jsonb end) s where s not in ('allow', 'redact', 'block')) then
    raise exception 'decision is one of allow, redact, block' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('decision', 'stage') then
      raise exception 'facet is one of decision, stage' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'decision' then (x."decision")::text when 'stage' then (x."stage")::text end) as v
      from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
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
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'agent') then
    raise exception 'sort is one of createdAt, agent' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."agent" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'decision', x."decision", 'reasons', x."reasons", 'chat_id', x."chat_id", 'content_hash', x."content_hash", 'created_at', x."created_at") as j, jsonb_build_array((x."agent")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."agent" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_decisions" x
      where (page_guardrail_decisions.tenant is null or x."tenant_id" = page_guardrail_decisions.tenant)
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'decision' is not null and jsonb_typeof(v_filters -> 'decision') <> 'null' and not (jsonb_typeof(v_filters -> 'decision') = 'array' and jsonb_array_length(v_filters -> 'decision') = 0)) or x."decision" = any((case when jsonb_typeof(v_filters -> 'decision') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'decision')) else array[v_filters ->> 'decision'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_guardrail_policies (
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
  v_filters jsonb := coalesce(page_guardrail_policies.filters, '{}'::jsonb);
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'stage') = 'array' then v_filters -> 'stage' when jsonb_typeof(v_filters -> 'stage') in ('string', 'number') then jsonb_build_array(v_filters -> 'stage') else '[]'::jsonb end) s where s not in ('input', 'output')) then
    raise exception 'stage is one of input, output' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('stage', 'enabled') then
      raise exception 'facet is one of stage, enabled' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'stage' then (x."stage")::text when 'enabled' then (x."enabled")::text end) as v
      from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
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
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('agent', 'updatedAt') then
    raise exception 'sort is one of agent, updatedAt' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent", x."stage", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."agent" asc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'agent' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."agent")::text, (x."stage")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."agent" <= (v_after ->> 0)::text and ((x."agent" < (v_after ->> 0)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" > (v_after ->> 1)::text) or (x."agent" = (v_after ->> 0)::text and x."stage" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."agent" desc, x."stage" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."guardrail_policies" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_guardrail_policies.tenant::text, '')
        and (not (v_filters -> 'agent' is not null and jsonb_typeof(v_filters -> 'agent') <> 'null' and not (jsonb_typeof(v_filters -> 'agent') = 'array' and jsonb_array_length(v_filters -> 'agent') = 0)) or x."agent" = any((case when jsonb_typeof(v_filters -> 'agent') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'agent')) else array[v_filters ->> 'agent'] end)::text[]))
        and (not (v_filters -> 'stage' is not null and jsonb_typeof(v_filters -> 'stage') <> 'null' and not (jsonb_typeof(v_filters -> 'stage') = 'array' and jsonb_array_length(v_filters -> 'stage') = 0)) or x."stage" = any((case when jsonb_typeof(v_filters -> 'stage') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'stage')) else array[v_filters ->> 'stage'] end)::text[]))
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."agent" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
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
    if v_facet not in ('status', 'inboxId') then
      raise exception 'facet is one of status, inboxId' using errcode = '22023', hint = 'INBOX_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'inboxId' then (x."inbox_id")::text end) as v
      from "better_supabase"."inbox_conversations" x
      where (page_inbox_conversations.tenant is null or x."tenant_id" = page_inbox_conversations.tenant)
        and (not (v_filters -> 'inboxId' is not null and jsonb_typeof(v_filters -> 'inboxId') <> 'null' and not (jsonb_typeof(v_filters -> 'inboxId') = 'array' and jsonb_array_length(v_filters -> 'inboxId') = 0)) or x."inbox_id" = any((case when jsonb_typeof(v_filters -> 'inboxId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'inboxId')) else array[v_filters ->> 'inboxId'] end)::uuid[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'contactId' is not null and jsonb_typeof(v_filters -> 'contactId') <> 'null' and not (jsonb_typeof(v_filters -> 'contactId') = 'array' and jsonb_array_length(v_filters -> 'contactId') = 0)) or x."contact_id" = any((case when jsonb_typeof(v_filters -> 'contactId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'contactId')) else array[v_filters ->> 'contactId'] end)::uuid[]))
        and (case when not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then x."status" = 'open' when v_filters -> 'status' ? 'all' then true else (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) end)
        and (case v_assignee when 'me' then x."assignee_id" = (select auth.uid()) when 'unassigned' then x."assignee_id" is null else v_assignee is null or x."assignee_id" = v_assignee::uuid end)
        and (v_search is null or x."subject" ilike v_search or x."last_message_preview" ilike v_search or x."id" in (select m.conversation from "better_supabase"."inbox_contacts_json"(null, page_inbox_conversations.tenant, v_filters ->> 'search') m))
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
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_knowledge_collections (
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
  v_filters jsonb := coalesce(page_knowledge_collections.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('visibility') then
      raise exception 'facet is one of visibility' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'visibility' then (x."visibility")::text end) as v
      from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
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
      select 1 from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('priority', 'name', 'createdAt') then
    raise exception 'sort is one of priority, name, createdAt' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."priority")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."priority", lower(x."name"), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."priority" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."priority")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."priority" <= (v_after ->> 0)::integer and ((x."priority" < (v_after ->> 0)::integer) or (x."priority" = (v_after ->> 0)::integer and lower(x."name") > (v_after ->> 1)::text) or (x."priority" = (v_after ->> 0)::integer and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."priority" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'priority' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."priority")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."priority", lower(x."name"), x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by x."priority" asc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'priority' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."priority")::text, (lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."priority" <= (v_after ->> 0)::integer and ((x."priority" < (v_after ->> 0)::integer) or (x."priority" = (v_after ->> 0)::integer and lower(x."name") > (v_after ->> 1)::text) or (x."priority" = (v_after ->> 0)::integer and lower(x."name") = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by x."priority" desc, lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_COLLECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'visibility', x."visibility", 'priority', x."priority", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
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
      select 1 from "better_supabase"."knowledge_collections" x
      where (x."tenant_id" = page_knowledge_collections.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'visibility' is not null and jsonb_typeof(v_filters -> 'visibility') <> 'null' and not (jsonb_typeof(v_filters -> 'visibility') = 'array' and jsonb_array_length(v_filters -> 'visibility') = 0)) or x."visibility" = any((case when jsonb_typeof(v_filters -> 'visibility') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'visibility')) else array[v_filters ->> 'visibility'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_knowledge_documents (
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
  v_filters jsonb := coalesce(page_knowledge_documents.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_collection text := nullif(coalesce(v_filters #>> '{collectionId,0}', v_filters ->> 'collectionId'), '');
  v_scope_id text := nullif(coalesce(v_filters #>> '{scopeId,0}', v_filters ->> 'scopeId'), '');
  v_subject_type text := nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '');
  v_subject_id text := nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '');
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
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'collectionId') = 'array' then v_filters -> 'collectionId' when jsonb_typeof(v_filters -> 'collectionId') in ('string', 'number') then jsonb_build_array(v_filters -> 'collectionId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then v_filters -> 'scopeId' when jsonb_typeof(v_filters -> 'scopeId') in ('string', 'number') then jsonb_build_array(v_filters -> 'scopeId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'collectionId and scopeId are uuids' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('scope', 'status') then
      raise exception 'facet is one of scope, status' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'scope' then (x."scope")::text when 'status' then (x."status")::text end) as v
      from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
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
      select 1 from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'title') then
    raise exception 'sort is one of createdAt, title' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."knowledge_documents" x
      where (x."tenant_id" = page_knowledge_documents.tenant or (x."tenant_id" is null and v_collection is not null))
        and (v_collection is null or x."collection_id" = v_collection::uuid)
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or x."scope" = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_scope_id is null or x."scope_id" = v_scope_id::uuid)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_subject_type is null or x."subject_type" = v_subject_type)
        and (v_subject_id is null or x."subject_id" = v_subject_id)
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_memories (
  tenant  uuid,
  ns      jsonb DEFAULT '{}'::jsonb,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_filters jsonb := coalesce(page_memories.filters, '{}'::jsonb);
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
  v_scope := coalesce(page_memories.ns ->> 'scope', 'user');
  v_agent := (page_memories.ns ->> 'agent_id')::uuid;
  v_chat := (page_memories.ns ->> 'chat_id')::uuid;
  v_project := (page_memories.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(page_memories.ns ->> 'subject_type', '');
  v_subject_id := nullif(page_memories.ns ->> 'subject_id', '');
  v_private := coalesce((page_memories.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (page_memories.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', page_memories.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', page_memories.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'kind') = 'array' then v_filters -> 'kind' when jsonb_typeof(v_filters -> 'kind') in ('string', 'number') then jsonb_build_array(v_filters -> 'kind') else '[]'::jsonb end) s where s not in ('core', 'archival')) then
    raise exception 'kind is core or archival' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind', 'category') then
      raise exception 'facet is one of kind, category' using errcode = '22023', hint = 'MEMORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text when 'category' then (coalesce(x."category", ''))::text end) as v
      from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
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
      select 1 from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'updatedAt', 'path', 'useCount', 'lastUsedAt') then
    raise exception 'sort is one of createdAt, updatedAt, path, useCount, lastUsedAt' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (x."updated_at" >= (v_after ->> 0)::timestamptz and ((x."updated_at" > (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."updated_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'path' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((coalesce(x."path", ''))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (coalesce(x."path", '') >= (v_after ->> 0)::text and ((coalesce(x."path", '') > (v_after ->> 0)::text) or (coalesce(x."path", '') = (v_after ->> 0)::text and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."path", '') asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'path' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((coalesce(x."path", ''))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (coalesce(x."path", ''), x."id") < ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by coalesce(x."path", '') desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'useCount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."use_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (x."use_count" >= (v_after ->> 0)::integer and ((x."use_count" > (v_after ->> 0)::integer) or (x."use_count" = (v_after ->> 0)::integer and x."id" < (v_after ->> 1)::uuid))))
      order by x."use_count" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'useCount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((x."use_count")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (x."use_count", x."id") < ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."use_count" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastUsedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((coalesce(x."last_used_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (coalesce(x."last_used_at", 'epoch'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."last_used_at", 'epoch'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."last_used_at", 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."last_used_at", 'epoch'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastUsedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEMORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") as j, jsonb_build_array((coalesce(x."last_used_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
        and (v_after is null or (coalesce(x."last_used_at", 'epoch'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."last_used_at", 'epoch'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."memories" x
      where x."tenant_id" = page_memories.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
        and true and (x."expires_at" is null or x."expires_at" > now())
        and (case when (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) then (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[])) else x."kind" = 'archival' end)
        and (not (v_filters -> 'category' is not null and jsonb_typeof(v_filters -> 'category') <> 'null' and not (jsonb_typeof(v_filters -> 'category') = 'array' and jsonb_array_length(v_filters -> 'category') = 0)) or coalesce(x."category", '') = any((case when jsonb_typeof(v_filters -> 'category') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'category')) else array[v_filters ->> 'category'] end)::text[]))
        and (v_search is null or x."content" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_post_boards (
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind" = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."description" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_posts (
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_facets jsonb;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'conversation' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."title"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."conversations" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text, s."website"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."phone"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."activities" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'quote' then
      select s."tenant_id", s."title"::text, null, '/crm/quotes/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."quotes" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'ledger_account' then
      select s."tenant_id", s."name"::text, null, '/finance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."ledger_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'invoice' then
      select s."tenant_id", s."title"::text, null, '/finance/payables', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."invoices" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'rfq' then
      select s."tenant_id", s."title"::text, null, '/rfqs', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."rfqs" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'till' then
      select s."tenant_id", s."name"::text, null, '/tills', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tills" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'order' then
      select s."tenant_id", s."number"::text, null, '/shop/orders/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'booking' then
      select s."tenant_id", s."customer_name"::text, null, '/calendar', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bookings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."assets" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset_location' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."asset_locations" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lease' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."leases" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_report' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_reports" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_line' then
      select s."tenant_id", s."description"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_lines" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'donation_fund' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."donation_funds" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'warranty_claim' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."manufacturer"::text, s."decision"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."warranty_claims" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_order' then
      select s."tenant_id", s."title"::text, null, '/field/dispatch', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'shipment' then
      select s."tenant_id", s."reference"::text, null, '/field/shipments', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."shipments" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'contract' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."contracts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'control' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."controls" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'compliance_policy' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."compliance_policies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'qualification_type' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."name"::text, s."key"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."qualification_types" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'inspection_program' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_programs" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection_finding' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_findings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'form' then
      select s."tenant_id", s."title"::text, null, '/forms/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."forms" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting_decision' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meeting_decisions" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'maintenance_plan' then
      select s."tenant_id", s."title"::text, null, '/maintenance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."maintenance_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'dam_usage_right' then
      select s."tenant_id", s."licensee"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."dam_usage_rights" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lims_sample' then
      select s."tenant_id", s."title"::text, null, '/lims', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."lims_samples" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'tax_code' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tax_codes" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_center' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."name"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_centers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'bank_account' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."name"::text, s."iban"::text, s."holder"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bank_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'care_plan' then
      select s."tenant_id", s."title"::text, null, '/care-plans', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."care_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'incident' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."incidents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."tracking_id"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisories" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory_product' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisory_products" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'vulnerability' then
      select s."tenant_id", s."vuln_id"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."vulnerabilities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."content_entries" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'document' then
      select s."tenant_id", s."name"::text, null, '/documents/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."documents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text, jsonb_strip_nulls(jsonb_build_object('status', s."status"))
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id" = s."id"
        where s."id" = (search_refresh.subject_id)::uuid
        and f."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    when 'task' then
      select s."organization_id", s."title"::text, null, '/projects/' || s."project_id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."tasks" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.recordTypes' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at", "facets", "sort_key")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now(), v_facets, left("better_supabase"."search_normalize"(v_title), 200)
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "facets" = excluded."facets",
    "sort_key" = excluded."sort_key",
    "updated_at" = now()
  where ("better_supabase"."search_documents"."tenant_id", "better_supabase"."search_documents"."title", "better_supabase"."search_documents"."body", "better_supabase"."search_documents"."url", "better_supabase"."search_documents"."facets")
    is distinct from (excluded."tenant_id", excluded."title", excluded."body", excluded."url", excluded."facets");
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_ai_project"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_project"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_provider_key"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_provider_key"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_task"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_task"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_conversation_summary"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_conversation_summary"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_guardrail_policy_by_id"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_guardrail_policy_by_id"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_knowledge_collection"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_knowledge_collection"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_memory"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_memory"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_agents"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_agents"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_ai_batches"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_ai_batches"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_ai_chats"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_ai_chats"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_ai_files"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_ai_files"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_ai_projects"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_ai_projects"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_ai_provider_keys"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_ai_provider_keys"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_ai_tasks"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_ai_tasks"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_channels"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_channels"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_conversations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_conversations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_eval_datasets"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_eval_datasets"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."page_eval_runs"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_eval_runs"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."page_guardrail_decisions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_guardrail_decisions"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."page_guardrail_policies"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_guardrail_policies"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."page_inbox_conversations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_inbox_conversations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_knowledge_collections"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_knowledge_collections"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_knowledge_documents"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_knowledge_documents"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_memories"(uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_memories"(uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_post_boards"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_post_boards"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_posts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_posts"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_project"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_project"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_provider_key"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_provider_key"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_task"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_task"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_conversation_summary"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_conversation_summary"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_guardrail_policy_by_id"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_guardrail_policy_by_id"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_knowledge_collection"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_knowledge_collection"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_memory"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_memory"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_agents"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_agents"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_ai_batches"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_ai_batches"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_ai_chats"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_ai_chats"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_ai_files"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_ai_files"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_ai_projects"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_ai_projects"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_ai_provider_keys"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_ai_provider_keys"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_ai_tasks"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_ai_tasks"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_channels"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_channels"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_conversations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_conversations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_eval_datasets"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_eval_datasets"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_eval_runs"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_eval_runs"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_guardrail_decisions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_guardrail_decisions"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_guardrail_policies"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_guardrail_policies"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_inbox_conversations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_inbox_conversations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_knowledge_collections"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_knowledge_collections"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_knowledge_documents"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_knowledge_documents"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_memories"(uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_memories"(uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_post_boards"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_post_boards"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_posts"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_posts"(uuid, jsonb) TO "authenticated", "service_role";
