SET local check_function_bodies = off;

DROP POLICY "bsb_deadlines_read" ON "better_supabase"."deadlines";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."deadlines";

DROP POLICY "bsb_deal_contacts_read" ON "better_supabase"."deal_contacts";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."deal_contacts";

DROP POLICY "bsb_knowledge_documents_read" ON "better_supabase"."knowledge_documents";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."knowledge_documents";

DROP INDEX "better_supabase"."access_requests_tenant_idx";

DROP INDEX "better_supabase"."activities_tenant_created_idx";

DROP INDEX "better_supabase"."ai_batches_tenant_idx";

DROP INDEX "better_supabase"."ai_moderation_events_tenant_idx";

DROP INDEX "better_supabase"."commission_plans_tenant_idx";

DROP INDEX "better_supabase"."expense_reports_tenant_idx";

DROP INDEX "better_supabase"."invoice_dunning_runs_tenant_idx";

DROP INDEX "better_supabase"."moderation_appeals_tenant_idx";

DROP INDEX "better_supabase"."moderation_statements_tenant_idx";

DROP INDEX "better_supabase"."passes_tenant_idx";

DROP INDEX "better_supabase"."posts_tenant_idx";

DROP INDEX "better_supabase"."shipments_tenant_idx";

DROP INDEX "better_supabase"."webhook_deliveries_tenant_created_idx";

DROP INDEX "better_supabase"."work_orders_tenant_idx";

DROP INDEX "better_supabase"."workflow_runs_tenant_idx";

CREATE OR REPLACE FUNCTION better_supabase.approval_fact (
  tenant    uuid,
  kind      text,
  value     text,
  requester uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
  v_key text := 'approvals.f' || md5(format('%s|%s|%s|%s|%s', v_me, approval_fact.tenant, approval_fact.kind, approval_fact.value, approval_fact.requester));
  v_stamp text := statement_timestamp()::text || '/' || coalesce(better_supabase.memo_get('approvals.gen'), '0');
  v_hit text := better_supabase.memo_slot_get(v_key);
  v_result boolean;
begin
  if v_hit is not null and split_part(v_hit, '|', 1) = v_stamp then
    return split_part(v_hit, '|', 2) = 't';
  end if;
  v_result := coalesce(case approval_fact.kind
    when 'role' then exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = approval_fact.tenant and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (approval_fact.value)::text or r."key" = (approval_fact.value)::text) order by (r."id"::text = (approval_fact.value)::text) desc limit 1)
    )
    when 'team' then exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = approval_fact.value and tm."user_id" = v_me)
    when 'manager' then (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = approval_fact.tenant and (case when approval_fact.value is not null then me."id"::text = approval_fact.value else me."user_id" = approval_fact.requester end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = approval_fact.tenant and mm."user_id" = v_me
    ))
    else false
  end, false);
  perform better_supabase.memo_slot_set(v_key, v_stamp || '|' || case when v_result then 't' else 'f' end);
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_row_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  entry_id "better_supabase"."audit_events"."id"%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant uuid;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  v_integration boolean := better_supabase.import_run() is not null;
  v_label text;
  path_value text;
  path_step jsonb;
begin
  -- An import run with imports.audit 'summary' audits one entry per entity at
  -- its end instead of one per row (ADR 0141).
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0 then
    return null;
  end if;
  row_tenant := case when row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end;
  -- A child row without a tenant column: follow the foreign-key path
  -- registered through tenant_path, then the tenant function.
  if row_tenant is null and entry.tenant_path is not null then
    path_value := row_data ->> (entry.tenant_path ->> 'column');
    for path_step in select * from jsonb_array_elements(entry.tenant_path -> 'steps') loop
      exit when path_value is null;
      execute format('select %I::text from %s where %I::text = $1 limit 1',
        path_step ->> 'read', path_step ->> 'table', path_step ->> 'ref')
        into path_value using path_value;
    end loop;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is null and entry.tenant_function is not null then
    execute format('select %s($1)::text', (entry.tenant_function::regprocedure)::oid::regproc) into path_value using row_data;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is not null then
    v_label := better_supabase.memo_slot_get('audit.tenant_label.t' || replace(row_tenant::text, '-', ''));
    if v_label is null then
      v_label := (select o."name"::text from "public"."organizations" o where o."id" = row_tenant);
      perform better_supabase.memo_slot_set('audit.tenant_label.t' || replace(row_tenant::text, '-', ''), coalesce(v_label, ''));
    end if;
  end if;
  old_row := old_row - entry.ignore;
  new_row := new_row - entry.ignore;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  -- Redacted columns stay in changed, with their values masked.
  old_row := old_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where old_row ? k), '{}');
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    lower(tg_op),
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    v_label,
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
  )
  returning "id" into entry_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.is_held_memo (
  kind   text,
  tenant text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_key text := 'ih' || md5(statement_timestamp()::text || is_held_memo.kind || coalesce(is_held_memo.tenant, ''));
  v_memo text := better_supabase.memo_slot_get(v_key);
  v_held boolean;
begin
  if v_memo is not null then
    return v_memo = 't';
  end if;
  v_held := "better_supabase"."is_held"(is_held_memo.kind, is_held_memo.tenant);
  perform better_supabase.memo_slot_set(v_key, case when v_held then 't' else 'f' end);
  return v_held;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memo_slot_get (
  key text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select case when pg_catalog.split_part(v.slot, pg_catalog.chr(31), 1) = key
    then nullif(pg_catalog.substr(v.slot, pg_catalog.length(key) + 2), '') end
  from (select pg_catalog.current_setting('better_supabase.memo.s' || (pg_catalog.hashtext(key) & 255)::text, true) as slot) v
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memo_slot_set (
  key   text,
  value text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select pg_catalog.set_config('better_supabase.memo.s' || (pg_catalog.hashtext(key) & 255)::text, key || pg_catalog.chr(31) || coalesce(value, ''), true)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_message_written()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."sent_at" is null then
    return null;
  end if;
  if tg_op = 'INSERT' or old."sent_at" is null then
    update "better_supabase"."conversations" c set "last_message_at" = greatest(coalesce(c."last_message_at", new."sent_at"), new."sent_at"), "updated_at" = now()
    where c."id" = new."conversation_id";
  end if;
  if new."thread_id" is not null and (tg_op = 'INSERT' or old."sent_at" is null or new."archived_at" is distinct from old."archived_at") then
    -- A reply that is sent live and not deleted adds to the root's rollup in
    -- place. A delete, a restore or a reply sent before the newest one asks the
    -- replies again (ADR 0639).
    if new."archived_at" is null and (tg_op = 'INSERT' or old."sent_at" is null) then
      update "better_supabase"."messages" r set
        "reply_count" = r."reply_count" + 1,
        "last_reply_at" = greatest(r."last_reply_at", new."sent_at"),
        "reply_user_ids" = case
          when new."author_id" is null or new."author_id" = any (r."reply_user_ids") or cardinality(r."reply_user_ids") >= 3 then r."reply_user_ids"
          else r."reply_user_ids" || new."author_id"
        end
      where r."id" = new."thread_id"
        and (r."last_reply_at" is null or r."last_reply_at" <= new."sent_at");
      if found then
        return null;
      end if;
    end if;
    update "better_supabase"."messages" r set
      "reply_count" = (select count(*) from "better_supabase"."messages" x where x."thread_id" = r."id" and x."sent_at" is not null and x."archived_at" is null),
      "last_reply_at" = (select max(x."sent_at") from "better_supabase"."messages" x where x."thread_id" = r."id" and x."archived_at" is null),
      "reply_user_ids" = array(
        select y.u from (
          select x."author_id" as u, min(x."sent_at") as first
          from "better_supabase"."messages" x
          where x."thread_id" = r."id" and x."sent_at" is not null and x."archived_at" is null and x."author_id" is not null
          group by x."author_id"
        ) y order by y.first limit 3
      )
    where r."id" = new."thread_id";
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.retention_for_memo (
  kind   text,
  tenant text DEFAULT NULL::text
)
  RETURNS interval
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_key text := 'rf' || md5(statement_timestamp()::text || retention_for_memo.kind || coalesce(retention_for_memo.tenant, ''));
  v_memo text := better_supabase.memo_slot_get(v_key);
  v_keep interval;
begin
  if v_memo is not null then
    return nullif(v_memo, '-')::interval;
  end if;
  v_keep := "better_supabase"."retention_for"(retention_for_memo.kind, retention_for_memo.tenant);
  perform better_supabase.memo_slot_set(v_key, coalesce(v_keep::text, '-'));
  return v_keep;
end;
$function$;

CREATE INDEX access_requests_tenant_idx ON better_supabase.access_requests USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX activities_tenant_created_idx ON better_supabase.activities USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX ai_batches_tenant_idx ON better_supabase.ai_batches USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX ai_moderation_events_tenant_idx ON better_supabase.ai_moderation_events USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX commission_plans_tenant_idx ON better_supabase.commission_plans USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX expense_reports_tenant_idx ON better_supabase.expense_reports USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX invoice_dunning_runs_tenant_idx ON better_supabase.invoice_dunning_runs USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX messaging_messages_conversation_all_idx ON better_supabase.messages USING btree (conversation_id);

CREATE INDEX moderation_appeals_tenant_idx ON better_supabase.moderation_appeals USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX moderation_statements_tenant_idx ON better_supabase.moderation_statements USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX passes_tenant_idx ON better_supabase.passes USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX posts_tenant_idx ON better_supabase.posts USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX shipments_tenant_idx ON better_supabase.shipments USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX webhook_deliveries_tenant_created_idx ON better_supabase.webhook_deliveries USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX work_orders_tenant_idx ON better_supabase.work_orders USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX workflow_runs_tenant_idx ON better_supabase.workflow_runs USING btree (tenant_id, created_at DESC, id DESC);

CREATE POLICY "bsb_deadlines_read" ON "better_supabase"."deadlines"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('deadlines.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'rfq'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.rfqs s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('rfqs.read'::text) AS tenant_ids_with)))
    WHEN 'till'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tills s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tills.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'maintenance_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.maintenance_plans s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('maintenance.read'::text) AS tenant_ids_with)))
    WHEN 'dam_usage_right'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.dam_usage_rights s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dam.read'::text) AS tenant_ids_with)))
    WHEN 'lims_sample'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.lims_samples s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('lims.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id) AND ((deadlines.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.id = deadlines.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    ELSE better_supabase.deadline_subject_readable(subject_type, subject_id, tenant_id)
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."deadlines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('deadlines.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'rfq'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.rfqs s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('rfqs.read'::text) AS tenant_ids_with)))
    WHEN 'till'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tills s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tills.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'maintenance_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.maintenance_plans s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('maintenance.read'::text) AS tenant_ids_with)))
    WHEN 'dam_usage_right'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.dam_usage_rights s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dam.read'::text) AS tenant_ids_with)))
    WHEN 'lims_sample'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.lims_samples s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('lims.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id) AND ((deadlines.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.id = deadlines.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    ELSE better_supabase.deadline_subject_readable(subject_type, subject_id, tenant_id)
END)));

CREATE POLICY "bsb_deal_contacts_read" ON "better_supabase"."deal_contacts"
  FOR SELECT
  TO "authenticated"
  USING (((EXISTS ( SELECT 1
   FROM better_supabase.deals x
  WHERE (x.id = deal_contacts.deal_id))) AND
CASE contact_type
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.organization_id = deal_contacts.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, contact_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id) AND (((deal_contacts.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, deal_contacts.contact_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.id = deal_contacts.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.organization_id = deal_contacts.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.organization_id = deal_contacts.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.organization_id = deal_contacts.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(contact_type, contact_id, 'read'::text), false)
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."deal_contacts"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((EXISTS ( SELECT 1
   FROM better_supabase.deals x
  WHERE (x.id = deal_contacts.deal_id))) AND
CASE contact_type
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.organization_id = deal_contacts.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, contact_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (deal_contacts.contact_id)::uuid) AND (s.tenant_id = deal_contacts.tenant_id) AND (((deal_contacts.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, deal_contacts.contact_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.id = deal_contacts.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.organization_id = deal_contacts.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.organization_id = deal_contacts.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (deal_contacts.contact_id)::uuid) AND (s.organization_id = deal_contacts.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(contact_type, contact_id, 'read'::text), false)
END)));

CREATE POLICY "bsb_knowledge_documents_read" ON "better_supabase"."knowledge_documents"
  FOR SELECT
  TO "authenticated"
  USING ((((tenant_id IS NULL) OR
CASE
    WHEN (scope = 'subject'::text) THEN
    CASE subject_type
        WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
           FROM public.customers s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.organization_id = knowledge_documents.tenant_id)))) AND
            ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text,
            subject_id)))
        WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
           FROM better_supabase.drive_nodes s
          WHERE
            ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.tenant_id = knowledge_documents.tenant_id) AND (((knowledge_documents.tenant_id IN ( SELECT
            better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
            better_supabase.is_subject_member('drive_node'::text, knowledge_documents.subject_id)))))
        WHEN 'organization'::text THEN (EXISTS ( SELECT 1
           FROM public.organizations s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.id = knowledge_documents.tenant_id))))
        WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
           FROM public.change_requests s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.organization_id = knowledge_documents.tenant_id))))
        WHEN 'project'::text THEN (EXISTS ( SELECT 1
           FROM public.projects s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.organization_id = knowledge_documents.tenant_id))))
        WHEN 'task'::text THEN (EXISTS ( SELECT 1
           FROM public.tasks s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.organization_id = knowledge_documents.tenant_id))))
        ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
    END
    ELSE
      ((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = ANY (ARRAY['organization'::text, 'agent'::text])) AND (tenant_id IN ( SELECT
      better_supabase.tenant_ids_with('knowledge.read'::text) AS tenant_ids_with))) OR
      (tenant_id IN ( SELECT better_supabase.tenant_ids_with('knowledge.manage'::text) AS tenant_ids_with)) OR ((scope = 'chat'::text) AND ((scope_id IS
      NOT NULL) AND better_supabase.ai_chat_can_read(scope_id))))
END) AND ((collection_id IS NULL) OR better_supabase.knowledge_collection_readable(collection_id))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."knowledge_documents"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IS NULL) OR
CASE
    WHEN (scope = 'subject'::text) THEN
    CASE subject_type
        WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
           FROM public.customers s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.organization_id = knowledge_documents.tenant_id)))) AND
            ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text,
            subject_id)))
        WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
           FROM better_supabase.drive_nodes s
          WHERE
            ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.tenant_id = knowledge_documents.tenant_id) AND (((knowledge_documents.tenant_id IN ( SELECT
            better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
            better_supabase.is_subject_member('drive_node'::text, knowledge_documents.subject_id)))))
        WHEN 'organization'::text THEN (EXISTS ( SELECT 1
           FROM public.organizations s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.id = knowledge_documents.tenant_id))))
        WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
           FROM public.change_requests s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.organization_id = knowledge_documents.tenant_id))))
        WHEN 'project'::text THEN (EXISTS ( SELECT 1
           FROM public.projects s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.organization_id = knowledge_documents.tenant_id))))
        WHEN 'task'::text THEN (EXISTS ( SELECT 1
           FROM public.tasks s
          WHERE ((s.id = (knowledge_documents.subject_id)::uuid) AND (s.organization_id = knowledge_documents.tenant_id))))
        ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
    END
    ELSE
      ((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = ANY (ARRAY['organization'::text, 'agent'::text])) AND (tenant_id IN ( SELECT
      better_supabase.tenant_ids_with('knowledge.read'::text) AS tenant_ids_with))) OR
      (tenant_id IN ( SELECT better_supabase.tenant_ids_with('knowledge.manage'::text) AS tenant_ids_with)) OR ((scope = 'chat'::text) AND ((scope_id IS
      NOT NULL) AND better_supabase.ai_chat_can_read(scope_id))))
END) AND ((collection_id IS NULL) OR better_supabase.knowledge_collection_readable(collection_id)))));
