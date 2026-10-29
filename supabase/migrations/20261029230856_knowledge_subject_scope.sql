SET local check_function_bodies = off;

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."knowledge_documents";

DROP POLICY "knowledge_documents_read" ON "better_supabase"."knowledge_documents";

ALTER TABLE "better_supabase"."knowledge_documents"
  DROP CONSTRAINT "knowledge_documents_check";

ALTER TABLE "better_supabase"."knowledge_documents"
  DROP CONSTRAINT "knowledge_documents_scope_check";

DROP FUNCTION "api"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid, uuid);

DROP FUNCTION "api"."list_knowledge_documents"(uuid, text, uuid, integer, uuid);

DROP FUNCTION "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid, uuid);

DROP FUNCTION "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer, uuid);

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD COLUMN "subject_type" text;

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD COLUMN "subject_id" text;

CREATE OR REPLACE FUNCTION api.create_knowledge_document (
  tenant        uuid,
  title         text,
  scope         text  DEFAULT 'user'::text,
  scope_id      uuid  DEFAULT NULL::uuid,
  file_id       uuid  DEFAULT NULL::uuid,
  source        text  DEFAULT NULL::text,
  metadata      jsonb DEFAULT '{}'::jsonb,
  owner         uuid  DEFAULT NULL::uuid,
  collection_id uuid  DEFAULT NULL::uuid,
  subject_type  text  DEFAULT NULL::text,
  subject_id    text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_knowledge_document"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) $function$;

CREATE OR REPLACE FUNCTION api.knowledge_subject_readable (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."knowledge_subject_readable"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_knowledge_documents (
  tenant        uuid,
  scope         text    DEFAULT NULL::text,
  scope_id      uuid    DEFAULT NULL::uuid,
  max_rows      integer DEFAULT 100,
  collection_id uuid    DEFAULT NULL::uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_knowledge_documents"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION better_supabase.create_knowledge_document (
  tenant        uuid,
  title         text,
  scope         text  DEFAULT 'user'::text,
  scope_id      uuid  DEFAULT NULL::uuid,
  file_id       uuid  DEFAULT NULL::uuid,
  source        text  DEFAULT NULL::text,
  metadata      jsonb DEFAULT '{}'::jsonb,
  owner         uuid  DEFAULT NULL::uuid,
  collection_id uuid  DEFAULT NULL::uuid,
  subject_type  text  DEFAULT NULL::text,
  subject_id    text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_knowledge_document.owner else auth.uid() end;
  v_scope_id uuid := create_knowledge_document.scope_id;
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or create_knowledge_document.tenant is null or not coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.create'), false)) then
    raise exception 'you may not add knowledge here' using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.tenant is null then
    v_owner := null;
  end if;
  if create_knowledge_document.collection_id is not null and not exists (
    select 1 from "better_supabase"."knowledge_collections" kc
    where kc."id" = create_knowledge_document.collection_id
      and (kc."organization_id" is null or kc."organization_id" = create_knowledge_document.tenant)
      and "better_supabase"."knowledge_collection_readable"(kc."id")
  ) then
    raise exception 'collection % not found', create_knowledge_document.collection_id using errcode = 'P0002', hint = 'KNOWLEDGE_COLLECTION_NOT_FOUND';
  end if;
  if create_knowledge_document.scope in ('organization', 'agent') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.admin'), false)) then
    raise exception 'only admins add % knowledge', create_knowledge_document.scope using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.scope = 'user' then
    v_scope_id := coalesce(v_scope_id, v_owner);
    if v_scope_id is null or v_scope_id is distinct from v_owner then
      raise exception 'user knowledge belongs to its owner' using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
    end if;
  end if;
  if create_knowledge_document.scope is null
    or create_knowledge_document.scope not in ('organization', 'agent', 'project', 'chat', 'user', 'subject')
    or (create_knowledge_document.scope in ('organization', 'subject')) <> (v_scope_id is null) then
    raise exception '% knowledge needs %', create_knowledge_document.scope, case when create_knowledge_document.scope in ('organization', 'subject') then 'no scope_id' else 'a scope_id' end using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
  end if;
  if (create_knowledge_document.scope = 'subject') <> (create_knowledge_document.subject_type is not null and create_knowledge_document.subject_id is not null)
    or (create_knowledge_document.scope <> 'subject' and (create_knowledge_document.subject_type is not null or create_knowledge_document.subject_id is not null)) then
    raise exception 'subject knowledge needs subject_type and subject_id, and other scopes neither' using errcode = '22023', hint = 'KNOWLEDGE_DOCUMENT_INVALID';
  end if;
  if create_knowledge_document.scope = 'subject' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case create_knowledge_document.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."organization_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant and (coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."tenant_id" = create_knowledge_document.tenant) and coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."organization_id" = create_knowledge_document.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."organization_id" = create_knowledge_document.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_knowledge_document.subject_id)::uuid and s."organization_id" = create_knowledge_document.tenant)
    else false
  end) then
    raise exception 'record %:% not found', create_knowledge_document.subject_type, create_knowledge_document.subject_id using errcode = 'P0002', hint = 'KNOWLEDGE_DOCUMENT_SUBJECT_NOT_FOUND';
  end if;
  if create_knowledge_document.scope = 'chat' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_scope_id is not null and "better_supabase"."ai_chat_can_read"(v_scope_id))) then
    raise exception 'chat % not found', v_scope_id using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if file_id is not null and not exists (
    select 1 from "better_supabase"."ai_files" x
    where x."id" = create_knowledge_document.file_id
      and x."organization_id" = create_knowledge_document.tenant
      and x."status" = 'ready'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.admin'), false))
  ) then
    raise exception 'file % not found', file_id using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."knowledge_documents" ("organization_id", "owner_id", "scope", "scope_id", "file_id", "title", "collection_id", "source", "metadata", "subject_type", "subject_id")
  values (create_knowledge_document.tenant, v_owner, create_knowledge_document.scope, v_scope_id, create_knowledge_document.file_id, create_knowledge_document.title, create_knowledge_document.collection_id, create_knowledge_document.source, coalesce(create_knowledge_document.metadata, '{}'), create_knowledge_document.subject_type, create_knowledge_document.subject_id)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'collection_id', v_row."collection_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_knowledge_document (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."knowledge_documents" x where x."id" = get_knowledge_document.document_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.knowledge_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  scopes          jsonb             DEFAULT NULL::jsonb,
  k               integer           DEFAULT 8,
  filter          jsonb             DEFAULT NULL::jsonb,
  collections     uuid[]            DEFAULT NULL::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
  v_candidates integer := least(greatest(knowledge_search.k, 1) * 4, 400);
  v_scopes jsonb := case when jsonb_typeof(knowledge_search.scopes) = 'object' then knowledge_search.scopes -> 'items' else knowledge_search.scopes end;
  v_rows jsonb;
begin
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with docs as materialized (
    select x."id" as id, x."title" as title, coalesce((select kc."priority" from "better_supabase"."knowledge_collections" kc where kc."id" = x."collection_id"), 0) as priority from "better_supabase"."knowledge_documents" x
    where (x."organization_id" = knowledge_search.tenant or x."organization_id" is null)
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
  select coalesce(jsonb_agg(jsonb_build_object('document_id', r.document_id, 'idx', r.idx, 'content', r.content, 'metadata', r.metadata, 'title', r.title, 'score', r.score) order by r.priority desc, r.score desc, r.document_id, r.idx), '[]')
  into v_rows
  from (
    select f.document_id, f.idx, t."content" as content, t."metadata" as metadata, docs.title, docs.priority, f.score
    from fused f
    join "better_supabase"."knowledge_chunks" t on t."document_id" = f.document_id and t."idx" = f.idx
    join docs on docs.id = f.document_id
    order by docs.priority desc, f.score desc, f.document_id, f.idx
    limit least(greatest(knowledge_search.k, 1), 100)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.knowledge_subject_readable (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return coalesce("better_supabase"."can_subject"(knowledge_subject_readable.subject_type, knowledge_subject_readable.subject_id, 'read'), false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_knowledge_documents (
  tenant        uuid,
  scope         text    DEFAULT NULL::text,
  scope_id      uuid    DEFAULT NULL::uuid,
  max_rows      integer DEFAULT 100,
  collection_id uuid    DEFAULT NULL::uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'scope_id', x."scope_id", 'file_id', x."file_id", 'title', x."title", 'source', x."source", 'metadata', x."metadata", 'status', x."status", 'error', x."error", 'chunk_count', x."chunk_count", 'embedding_model', x."embedding_model", 'collection_id', x."collection_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from (
    select * from "better_supabase"."knowledge_documents" y
    where (y."organization_id" = list_knowledge_documents.tenant or (y."organization_id" is null and list_knowledge_documents.collection_id is not null))
      and (list_knowledge_documents.collection_id is null or y."collection_id" = list_knowledge_documents.collection_id)
      and (list_knowledge_documents.scope is null or y."scope" = list_knowledge_documents.scope)
      and (list_knowledge_documents.scope_id is null or y."scope_id" = list_knowledge_documents.scope_id)
      and (list_knowledge_documents.subject_type is null or y."subject_type" = list_knowledge_documents.subject_type)
      and (list_knowledge_documents.subject_id is null or y."subject_id" = list_knowledge_documents.subject_id)
    order by y."created_at" desc
    limit least(greatest(list_knowledge_documents.max_rows, 1), 1000)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.write_knowledge_chunks (
  document_id uuid,
  chunks      jsonb,
  model       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
  v_count integer;
  v_keep boolean;
  v_items jsonb := case when jsonb_typeof(write_knowledge_chunks.chunks) = 'object' then write_knowledge_chunks.chunks -> 'items' else write_knowledge_chunks.chunks end;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = write_knowledge_chunks.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'KNOWLEDGE_NOT_FOUND';
  end if;
  if coalesce(jsonb_typeof(v_items), '') <> 'array' or jsonb_array_length(v_items) > 10000 then
    raise exception 'chunks must be an array of at most 10000 chunks' using errcode = '22023', hint = 'KNOWLEDGE_CHUNKS';
  end if;
  v_count := jsonb_array_length(v_items);
  v_keep := write_knowledge_chunks.model is not distinct from v_row."embedding_model" or write_knowledge_chunks.model is null;
  insert into "better_supabase"."knowledge_chunks" as t ("document_id", "idx", "content", "token_count", "metadata")
  select v_row."id", (e.ord - 1)::integer, e.value ->> 'content', (e.value ->> 'tokens')::integer, coalesce(e.value -> 'metadata', '{}')
  from jsonb_array_elements(v_items) with ordinality e(value, ord)
  on conflict ("document_id", "idx") do update set
    "content" = excluded."content",
    "token_count" = excluded."token_count",
    "metadata" = excluded."metadata",
    "embedding" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding" end,
    "embedding_hash" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding_hash" end;
  delete from "better_supabase"."knowledge_chunks" x where x."document_id" = v_row."id" and x."idx" >= v_count;
  update "better_supabase"."knowledge_documents" x set
    "status" = case when exists (select 1 from "better_supabase"."knowledge_chunks" p where p."document_id" = x."id" and p."embedding" is null) then 'pending' else 'ready' end,
    "error" = null,
    "chunk_count" = v_count,
    "embedding_model" = coalesce(write_knowledge_chunks.model, x."embedding_model"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" = 'pending' then
  perform "better_supabase"."enqueue_job"(queue => 'knowledge_embed', payload => jsonb_build_object('document_id', v_row."id"), dedupe_key => 'knowledge:' || v_row."id"::text, dedupe_running => false);
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'collection_id', v_row."collection_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD CONSTRAINT "knowledge_documents_check" CHECK (((scope = ANY (ARRAY['organization'::text, 'subject'::text])) = (scope_id IS NULL)));

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD CONSTRAINT "knowledge_documents_scope_check" CHECK ((scope = ANY (ARRAY['organization'::text, 'agent'::text, 'project'::text, 'chat'::text, 'user'::text, 'subject'::text])));

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD CONSTRAINT "knowledge_documents_subject_check" CHECK (((scope = 'subject'::text) = ((subject_type IS NOT NULL) AND (subject_id IS NOT NULL))));

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD CONSTRAINT "knowledge_documents_subject_id_check" CHECK (((length(subject_id) >= 1) AND (length(subject_id) <= 200)));

ALTER TABLE "better_supabase"."knowledge_documents"
  ADD CONSTRAINT "knowledge_documents_subject_type_check" CHECK (((length(subject_type) >= 1) AND (length(subject_type) <= 100)));

CREATE INDEX knowledge_documents_subject_idx ON better_supabase.knowledge_documents USING btree (subject_type, subject_id)
  WHERE (subject_type IS NOT NULL);

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."knowledge_documents"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((organization_id IS NULL) OR
CASE
    WHEN (scope = 'subject'::text) THEN better_supabase.knowledge_subject_readable(subject_type, subject_id)
    ELSE
      ((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = ANY (ARRAY['organization'::text, 'agent'::text])) AND (organization_id IN ( SELECT
      better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with))) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with))
      OR ((scope = 'chat'::text) AND ((scope_id IS NOT NULL) AND better_supabase.ai_chat_can_read(scope_id))))
END) AND ((collection_id IS NULL) OR better_supabase.knowledge_collection_readable(collection_id)))));

CREATE POLICY "knowledge_documents_read" ON "better_supabase"."knowledge_documents"
  FOR SELECT
  TO "authenticated"
  USING ((((organization_id IS NULL) OR
CASE
    WHEN (scope = 'subject'::text) THEN better_supabase.knowledge_subject_readable(subject_type, subject_id)
    ELSE
      ((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = ANY (ARRAY['organization'::text, 'agent'::text])) AND (organization_id IN ( SELECT
      better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with))) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with))
      OR ((scope = 'chat'::text) AND ((scope_id IS NOT NULL) AND better_supabase.ai_chat_can_read(scope_id))))
END) AND ((collection_id IS NULL) OR better_supabase.knowledge_collection_readable(collection_id))));

REVOKE ALL ON FUNCTION "api"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."knowledge_subject_readable"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."knowledge_subject_readable"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_knowledge_documents"(uuid, text, uuid, integer, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_knowledge_documents"(uuid, text, uuid, integer, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_knowledge_document"(uuid, text, text, uuid, uuid, text, jsonb, uuid, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."knowledge_subject_readable"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."knowledge_subject_readable"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_knowledge_documents"(uuid, text, uuid, integer, uuid, text, text) TO "authenticated", "service_role";
