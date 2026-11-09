set lock_timeout = '5s';

create or replace function "better_supabase"."knowledge_search"(
  tenant uuid,
  query_embedding extensions.vector default null,
  query_text text default null,
  scopes jsonb default null,
  k integer default 8,
  filter jsonb default null,
  collections uuid[] default null,
  priority_order boolean default true
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
set plan_cache_mode = force_custom_plan
as $$
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
  v_candidates integer := least(greatest(knowledge_search.k, 1) * 4, 400);
  v_scopes jsonb := case when jsonb_typeof(knowledge_search.scopes) = 'object' then knowledge_search.scopes -> 'items' else knowledge_search.scopes end;
  v_rows jsonb;
begin
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with docs as materialized (
    select x."id" as id, x."tenant_id" as doc_tenant, x."title" as title, coalesce((select kc."priority" from "better_supabase"."knowledge_collections" kc where kc."id" = x."collection_id"), 0) as priority from "better_supabase"."knowledge_documents" x
    where (x."tenant_id" = knowledge_search.tenant or x."tenant_id" is null)
      and (x."collection_id" is null or exists (select 1 from "better_supabase"."knowledge_collections" kc where kc."id" = x."collection_id" and kc."visibility" <> 'disabled'))
      and (knowledge_search.collections is null or x."collection_id" = any(knowledge_search.collections))
      and (v_scopes is null or exists (
        select 1 from jsonb_array_elements(v_scopes) s
        where s.value ->> 'scope' = x."scope"
          and (s.value ->> 'scope' = 'subject' or s.value ->> 'id' is null or (s.value ->> 'id')::uuid = x."scope_id")
          and (s.value ->> 'scope' <> 'subject' or ((s.value ->> 'type' is null or s.value ->> 'type' = x."subject_type") and (s.value ->> 'id' is null or s.value ->> 'id' = x."subject_id")))
      ))
      and (knowledge_search.filter is null or x."metadata" @> knowledge_search.filter)
  ),
  vector_hits as materialized (
    select t."document_id" as document_id, t."idx" as idx, t."embedding" operator(extensions.<=>) knowledge_search.query_embedding as distance
    from "better_supabase"."knowledge_chunks" t
    where knowledge_search.query_embedding is not null and t."embedding" is not null
      and t."document_id" in (select docs.id from docs)
    order by t."embedding" operator(extensions.<=>) knowledge_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.document_id, h.idx, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_hits as materialized (
    select t."document_id" as document_id, t."idx" as idx, ts_rank_cd(t."tsv", q) as text_score
    from "better_supabase"."knowledge_chunks" t, websearch_to_tsquery('simple'::regconfig, knowledge_search.query_text) q
    where knowledge_search.query_text is not null and t."tsv" @@ q
      and t."document_id" in (select docs.id from docs)
    order by text_score desc
    limit v_candidates
  ),
  text_ranked as (
    select x.document_id, x.idx, row_number() over (order by x.text_score desc) as rank from text_hits x
  ),
  fused as (
    select coalesce(v.document_id, x.document_id) as document_id, coalesce(v.idx, x.idx) as idx,
      coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.document_id = v.document_id and x.idx = v.idx
  )
  select coalesce(jsonb_agg(jsonb_build_object('document_id', r.document_id, 'idx', r.idx, 'chunk_id', r.document_id::text || '#' || r.idx::text, 'organization_id', r.doc_tenant, 'content', r.content, 'metadata', r.metadata, 'title', r.title, 'score', r.score) order by r.rank_priority desc, r.score desc, r.document_id, r.idx), '[]')
  into v_rows
  from (
    select f.document_id, f.idx, t."content" as content, t."metadata" as metadata, docs.title, docs.doc_tenant,
      case when knowledge_search.priority_order then docs.priority else 0 end as rank_priority, f.score
    from fused f
    join "better_supabase"."knowledge_chunks" t on t."document_id" = f.document_id and t."idx" = f.idx
    join docs on docs.id = f.document_id
    order by rank_priority desc, f.score desc, f.document_id, f.idx
    limit least(greatest(knowledge_search.k, 1), 100)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
  return v_rows;
end;
$$;

create or replace function "better_supabase"."mark_notifications_read"(ids uuid[] default null, tenant uuid default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = now()
    where rc."user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and rc."id" in (
        select picked from unnest(mark_notifications_read.ids) picked
        union all
        select all_rc."id" from "better_supabase"."notification_recipients" all_rc
        where mark_notifications_read.ids is null and all_rc."user_id" = auth.uid() and all_rc."read_at" is null
      )
      and (mark_notifications_read.tenant is null or rc."tenant_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."tenant_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$$;

create or replace function "better_supabase"."list_notifications"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  before timestamptz default null,
  max_items integer default 50,
  before_id uuid default null,
  subject_types text[] default null,
  search text default null,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."tenant_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(list_notifications.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when list_notifications.dismissed is null then true else (rc."dismissed_at" is not null) = list_notifications.dismissed end
      and (list_notifications.read is null or (rc."read_at" is not null) = list_notifications.read)
      and (list_notifications.resolved is null or (rc."resolved_at" is not null) = list_notifications.resolved)
      and (list_notifications.tenant is null or rc."tenant_id" = list_notifications.tenant)
      and ev."type" = any(coalesce(list_notifications.types, array[ev."type"]))
      and (list_notifications.subject_types is null or ev."subject_type" = any(list_notifications.subject_types))
      and (list_notifications.search is null or btrim(list_notifications.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(list_notifications.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
      and (
        list_notifications.before is null
        or (rc."created_at", rc."id") < (list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid))
      )
    order by rc."created_at" desc, rc."id" desc
    limit least(coalesce(list_notifications.max_items, 50), 200)
  ) x
$$;

create or replace function "better_supabase"."notification_page"(
  tenant uuid default null,
  status text default 'all',
  types text[] default null,
  subject_types text[] default null,
  search text default null,
  max_items integer default 50,
  skip integer default 0,
  read boolean default null,
  resolved boolean default null,
  dismissed boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with matched as (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."tenant_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where rc."user_id" = auth.uid()
      and case when coalesce(notification_page.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when notification_page.dismissed is null then true else (rc."dismissed_at" is not null) = notification_page.dismissed end
      and (notification_page.read is null or (rc."read_at" is not null) = notification_page.read)
      and (notification_page.resolved is null or (rc."resolved_at" is not null) = notification_page.resolved)
      and (notification_page.tenant is null or rc."tenant_id" = notification_page.tenant)
      and ev."type" = any(coalesce(notification_page.types, array[ev."type"]))
      and (notification_page.subject_types is null or ev."subject_type" = any(notification_page.subject_types))
      and (notification_page.search is null or btrim(notification_page.search) = '' or concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%')
      and case coalesce(notification_page.status, 'all')
        when 'unread' then rc."read_at" is null
        when 'read' then rc."read_at" is not null
        when 'unresolved' then rc."resolved_at" is null
        else true
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(p.item order by p.created_at desc, p.id desc)
      from (
        select m.item, m.created_at, m.id from matched m
        order by m.created_at desc, m.id desc
        offset greatest(coalesce(notification_page.skip, 0), 0)
        limit least(greatest(coalesce(notification_page.max_items, 50), 1), 200)
      ) p
    ), '[]'),
    'total', (select count(*) from matched)
  )
$$;
