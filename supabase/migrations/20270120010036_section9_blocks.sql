SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."tax_rates"
  DROP CONSTRAINT "tax_rates_tax_code_id_fkey";

ALTER TABLE "better_supabase"."tax_rates"
  DROP CONSTRAINT "tax_rates_tenant_code_fkey";

CREATE OR REPLACE FUNCTION better_supabase.cancel_import_run (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_run "better_supabase"."import_runs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."import_runs" r where r."id" = cancel_import_run.id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_run."tenant_id", 'imports.manage'), false)) then
    raise exception 'not allowed to cancel this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if v_run."status" not in ('pending', 'running') then
    raise exception 'this import already finished' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "better_supabase"."import_runs" r set "status" = 'canceled', "finished_at" = now()
  where r."id" = cancel_import_run.id;

  if v_run."dry_run" then
    delete from "better_supabase"."import_chunks" x where x."run_id" = cancel_import_run.id;
    delete from "better_supabase".import_run_issues i where i."run_id" = cancel_import_run.id;
  end if;
  perform "better_supabase"."search_refresh_run"(cancel_import_run.id);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clone_invoice (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."invoices";
  v_created jsonb;
  v_id uuid;
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."invoices" x where x."id" = clone_invoice.source;
  if not found then
    raise exception 'no such invoice' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_invoice.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or v_src."template_id" is not null) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_invoice.source, clone_invoice.overrides;
    end if;
  end;
  v_created := "better_supabase"."create_invoice"(v_tenant, jsonb_strip_nulls(jsonb_build_object('note', v_src."note", 'termsDays', v_src."terms_days", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount", 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount", 'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'title', v_src."title", 'currency', v_src."currency", 'templateId', null, 'sourceTemplateId', null)) || (coalesce(clone_invoice.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), null);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."invoice_lines"
  select (jsonb_populate_record(null::"better_supabase"."invoice_lines", to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), 'parent_id', v_id, 'tenant_id', v_tenant))).*
  from "better_supabase"."invoice_lines" l where l."parent_id" = clone_invoice.source;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clone_maintenance_request (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."maintenance_requests"%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."maintenance_requests" x where x."id" = clone_maintenance_request.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_maintenance_request.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'facilities.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_maintenance_request.source, clone_maintenance_request.overrides;
    end if;
  end;
  select coalesce(array_agg(ra."user_id"), '{}') into v_users from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = v_src."id";
  v_created := "better_supabase"."create_maintenance_request"(v_tenant, jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title",
    'body', v_src."body",
    'parentId', v_src."parent_id",
    'teamId', v_src."team_id",
    'dueAt', v_src."due_at",
    'priority', v_src."priority",
    'templateId', null,
    'sourceTemplateId', null
  )) || (coalesce(clone_maintenance_request.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), v_users);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."maintenance_request_checklist_items" ("tenant_id", "maintenance_request_id", "title", "done", "rank")
  select v_tenant, v_id, c."title", false, c."rank"
  from "better_supabase"."maintenance_request_checklist_items" c where c."maintenance_request_id" = clone_maintenance_request.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select v_tenant, g."tag_id", g."subject_type", v_id::text
  from "better_supabase"."taggings" g
  where g."subject_type" = 'maintenance_request' and g."subject_id" = clone_maintenance_request.source::text;
  for v_child in select c."id" from "better_supabase"."maintenance_requests" c where c."parent_id" = clone_maintenance_request.source loop
    v_copy := "better_supabase"."clone_maintenance_request"(v_child, coalesce(clone_maintenance_request.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update "better_supabase"."maintenance_requests" x set "parent_id" = v_id where x."id" = (v_copy ->> 'id')::uuid;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clone_quote (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."quotes";
  v_created jsonb;
  v_id uuid;
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = clone_quote.source;
  if not found then
    raise exception 'no such quote' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_quote.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or v_src."template_id" is not null) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_quote.source, clone_quote.overrides;
    end if;
  end;
  v_created := "better_supabase"."create_quote"(v_tenant, jsonb_strip_nulls(jsonb_build_object('terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount", 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount", 'depositRequired', v_src."deposit_required", 'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'title', v_src."title", 'currency', v_src."currency", 'templateId', null, 'sourceTemplateId', null)) || (coalesce(clone_quote.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), null);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines"
  select (jsonb_populate_record(null::"better_supabase"."quote_lines", to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), 'parent_id', v_id, 'tenant_id', v_tenant))).*
  from "better_supabase"."quote_lines" l where l."parent_id" = clone_quote.source;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return v_created;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clone_work_item (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."work_items"%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."work_items" x where x."id" = clone_work_item.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_work_item.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_work_item.source, clone_work_item.overrides;
    end if;
  end;
  select coalesce(array_agg(ra."user_id"), '{}') into v_users from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = v_src."id";
  v_created := "better_supabase"."create_work_item"(v_tenant, jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title",
    'body', v_src."body",
    'parentId', v_src."parent_id",
    'teamId', v_src."team_id",
    'dueAt', v_src."due_at",
    'priority', v_src."priority",
    'templateId', null,
    'sourceTemplateId', null
  )) || (coalesce(clone_work_item.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), v_users);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "done", "rank")
  select v_tenant, v_id, c."title", false, c."rank"
  from "better_supabase"."work_item_checklist_items" c where c."work_item_id" = clone_work_item.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select v_tenant, g."tag_id", g."subject_type", v_id::text
  from "better_supabase"."taggings" g
  where g."subject_type" = 'work_item' and g."subject_id" = clone_work_item.source::text;
  for v_child in select c."id" from "better_supabase"."work_items" c where c."parent_id" = clone_work_item.source loop
    v_copy := "better_supabase"."clone_work_item"(v_child, coalesce(clone_work_item.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update "better_supabase"."work_items" x set "parent_id" = v_id where x."id" = (v_copy ->> 'id')::uuid;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enqueue_import_chunks (
  run    uuid,
  entity text,
  chunks integer
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
  v_chunk integer;
  v_failed integer[];
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = enqueue_import_chunks.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if enqueue_import_chunks.chunks is null or enqueue_import_chunks.chunks < 1 then
    raise exception 'chunks must be at least 1' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select coalesce(array_agg(x."chunk"), '{}') into v_failed from "better_supabase"."import_chunks" x
  where x."run_id" = enqueue_import_chunks.run and x."entity" = enqueue_import_chunks.entity
    and x."status" = 'failed';
  -- A failed chunk goes back to pending, with a new job, so a retry reaches it.
  update "better_supabase"."import_chunks" x set "status" = 'pending', "claimed_at" = null,
    "done_at" = null, "result" = null
  where x."run_id" = enqueue_import_chunks.run and x."entity" = enqueue_import_chunks.entity
    and x."status" = 'failed';
  for v_chunk in 0 .. enqueue_import_chunks.chunks - 1 loop
    if v_chunk = any (v_failed) then
      perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text || ':retry:' || extract(epoch from clock_timestamp())::text, dedupe_running => false);
    else
      perform "better_supabase"."enqueue_job"(queue => 'imports', payload => jsonb_build_object('run', v_run."id", 'entity', enqueue_import_chunks.entity, 'chunk', v_chunk), dedupe_key => v_run."id"::text || ':' || enqueue_import_chunks.entity || ':' || v_chunk::text, dedupe_running => false);
    end if;
  end loop;
  return enqueue_import_chunks.chunks;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_apply_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_source_at timestamptz;
  v_diff jsonb := '[]'::jsonb;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_owned text;
  v_natural text;
  v_ref_map jsonb := '{}'::jsonb;
  v_resolved jsonb := '{}'::jsonb;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_conflict_keys jsonb := '[]'::jsonb;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_issue text;
  v_message text;
  v_hint text;
  v_known jsonb;
  v_seen text[] := '{}';
  v_slot text;
  v_pending jsonb[] := '{}';
  v_calls jsonb[] := '{}';
  v_pending_keys text[] := '{}';
  v_raw jsonb;
  v_results jsonb[];
  v_p jsonb;
  v_i integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['organization_profile', 'attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'party_discount_group', 'product', 'product_category', 'stock_count', 'stock_allocation', 'order', 'payment_term', 'document_delivery_preference', 'party', 'party_contact', 'contact_method', 'party_location', 'party_bank_account', 'quote', 'invoice', 'credit_note', 'open_item', 'invoice_allocation', 'meter_reading', 'due_check', 'asset', 'asset_identifier', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer', 'customer_row']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  v_ref_map := coalesce((
    select jsonb_object_agg(wanted.field || chr(31) || wanted.key, found."subject_id")
    from (
      select ref.field, ref.entity, item.value -> 'refs' ->> ref.field as key
      from jsonb_array_elements(v_items) item(value)
      cross join (values ('supplier', 'supplier', 'supplier_item'), ('customer', 'customer', 'supplier_item'), ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
      where ref.target = v_entity
    ) wanted
    join "better_supabase"."import_records" found
      on found."tenant_id" = v_run."tenant_id"
      and found."source" = v_run."source"
      and found."entity" = wanted.entity
      and found."external_key" = wanted.key
    where wanted.key is not null
  ), '{}'::jsonb);
  v_known := coalesce((
    select jsonb_object_agg(k."scope" || chr(31) || k."external_key", to_jsonb(k))
    from "better_supabase"."import_records" k
    where k."tenant_id" = v_run."tenant_id" and k."source" = v_run."source"
      and k."entity" = v_entity and k."role" = 'primary'
      and (k."scope", k."external_key") in (
        select coalesce(e.value ->> 'scope', ''), e.value ->> 'key' from jsonb_array_elements(v_items) e
      )
  ), '{}'::jsonb);

  for v_item in
    select e.value from jsonb_array_elements(v_items) e
    order by e.value #>> '{data,orderBy}', e.value #>> '{data,readAt}', e.value ->> 'key'
  loop
    v_issue := null;
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', 'IMPORT_ITEM_INVALID', 'an item needs a key and a data object');
      continue;
    end if;

    if v_scope || chr(31) || v_key = any (v_pending_keys) then
      if cardinality(v_pending) > 0 then
          begin
            case v_entity
          when 'customer' then
            v_subject_type := 'customer';
            v_raw := "public"."import_customer_batch"(v_run_id, to_jsonb(v_calls));
            else
              v_raw := null;
            end case;
            if jsonb_typeof(v_raw) is distinct from 'array' or jsonb_array_length(v_raw) <> cardinality(v_pending) then
              raise exception 'a batch target returns one result per item' using errcode = '22023';
            end if;
            v_results := array(select e.value from jsonb_array_elements(v_raw) e);
          exception when others then
            v_results := null;
          end;
          for v_i in 1 .. cardinality(v_pending) loop
            v_p := v_pending[v_i];
            v_key := v_p ->> 'key';
            v_scope := v_p ->> 'scope';
            v_hash := v_p ->> 'hash';
            v_found := (v_p ->> 'found')::boolean;
            v_subject_id := v_p ->> 'subjectId';
            begin
              if v_results is null then
                v_call := v_calls[v_i];
                case v_entity
      when 'organization_profile' then
        v_subject_type := 'organization_profile';
        v_out := "better_supabase"."import_organization_profile"(v_run_id, v_call, v_subject_id);
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'party_discount_group' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party_discount_group"(v_run_id, v_call, v_subject_id);
      when 'product' then
        v_subject_type := 'product';
        v_out := "better_supabase"."import_product"(v_run_id, v_call, v_subject_id);
      when 'product_category' then
        v_subject_type := 'product_category';
        v_out := "better_supabase"."import_product_category"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'stock_allocation' then
        v_subject_type := 'stock_allocation';
        v_out := "better_supabase"."import_stock_allocation"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'party' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party"(v_run_id, v_call, v_subject_id);
      when 'party_contact' then
        v_subject_type := 'party_contact';
        v_out := "better_supabase"."import_party_contact"(v_run_id, v_call, v_subject_id);
      when 'contact_method' then
        v_subject_type := 'contact_method';
        v_out := "better_supabase"."import_contact_method"(v_run_id, v_call, v_subject_id);
      when 'party_location' then
        v_subject_type := 'party_location';
        v_out := "better_supabase"."import_party_location"(v_run_id, v_call, v_subject_id);
      when 'party_bank_account' then
        v_subject_type := 'party_bank_account';
        v_out := "better_supabase"."import_party_bank_account"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'invoice_allocation' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_allocation"(v_run_id, v_call, v_subject_id);
      when 'meter_reading' then
        v_subject_type := 'meter_reading';
        v_out := "better_supabase"."import_meter_reading"(v_run_id, v_call, v_subject_id);
      when 'due_check' then
        v_subject_type := 'due_check';
        v_out := "better_supabase"."import_due_check"(v_run_id, v_call, v_subject_id);
      when 'asset' then
        v_subject_type := 'asset';
        v_out := "better_supabase"."import_asset"(v_run_id, v_call, v_subject_id);
      when 'asset_identifier' then
        v_subject_type := 'asset_identifier';
        v_out := "better_supabase"."import_asset_identifier"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      when 'customer_row' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;
              else
                v_out := v_results[v_i];
                if jsonb_typeof(v_out) = 'object' and v_out ? 'error' then
                  raise exception '%', coalesce(v_out -> 'error' ->> 'message', 'the import target refused the item')
                    using hint = coalesce(v_out -> 'error' ->> 'code', 'IMPORT_ITEM_INVALID');
                end if;
              end if;
              v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
            exception when others then
              get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
              v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
            end;
          end loop;
          v_pending := '{}';
          v_calls := '{}';
          v_pending_keys := '{}';
        end if;
    end if;

    begin
      v_done := false;
      v_slot := v_scope || chr(31) || v_key;
      if v_slot = any (v_seen) then
        select * into v_rec from "better_supabase"."import_records" x
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
          and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
        v_found := found;
      elsif v_known ? v_slot then
        v_rec := jsonb_populate_record(null::"better_supabase"."import_records", v_known -> v_slot);
        v_found := true;
      else
        v_rec := null;
        v_found := false;
      end if;
      v_seen := v_seen || v_slot;
      v_source_at := nullif(v_item ->> 'sourceUpdatedAt', '')::timestamptz;
      if v_found and v_source_at is not null and v_rec."source_updated_at" is not null and v_source_at <= v_rec."source_updated_at" then
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');
      end if;

      if v_done then
        null;
      elsif not v_found then
        v_natural := null;
        case v_entity
        when 'party_bank_account' then
          v_natural := "better_supabase"."party_bank_account_id"(v_run."tenant_id", v_item);
          else null;
        end case;
        if v_natural is not null then
          v_found := true;
          v_rec."subject_id" := v_natural;
          v_rec."content_hash" := '';
        end if;
      end if;

      if v_done then
        null;
      elsif not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_imported_updated_at"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."went_missing_at" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        v_owned := null;
        case v_entity
        when 'organization_profile' then
          v_current := "better_supabase"."organization_profile_updated_at"(v_rec."subject_id");
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'discount_group' then
          v_current := "better_supabase"."discount_group_updated_at"(v_rec."subject_id");
        when 'discount_rule' then
          v_current := "better_supabase"."discount_rule_updated_at"(v_rec."subject_id");
        when 'product' then
          v_current := "better_supabase"."product_updated_at"(v_rec."subject_id");
        when 'product_category' then
          v_current := "better_supabase"."product_category_updated_at"(v_rec."subject_id");
        when 'stock_count' then
          v_current := "better_supabase"."stock_count_updated_at"(v_rec."subject_id");
        when 'stock_allocation' then
          v_current := "better_supabase"."stock_allocation_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'payment_term' then
          v_current := "better_supabase"."payment_term_updated_at"(v_rec."subject_id");
        when 'document_delivery_preference' then
          v_current := "better_supabase"."document_delivery_preference_updated_at"(v_rec."subject_id");
        when 'party' then
          v_current := "better_supabase"."party_updated_at"(v_rec."subject_id");
        when 'party_contact' then
          v_current := "better_supabase"."party_contact_updated_at"(v_rec."subject_id");
        when 'contact_method' then
          v_current := "better_supabase"."contact_method_updated_at"(v_rec."subject_id");
        when 'party_location' then
          v_current := "better_supabase"."party_location_updated_at"(v_rec."subject_id");
        when 'party_bank_account' then
          v_current := "better_supabase"."party_bank_account_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'open_item' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'invoice_allocation' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'due_check' then
          v_current := "better_supabase"."due_check_updated_at"(v_rec."subject_id");
        when 'asset' then
          v_current := "better_supabase"."asset_updated_at"(v_rec."subject_id");
        when 'asset_identifier' then
          v_current := "better_supabase"."asset_identifier_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'document_template' then
          v_current := "better_supabase"."document_template_updated_at"(v_rec."subject_id");
        when 'document_text_block' then
          v_current := "better_supabase"."document_text_block_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
        when 'customer_row' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        null;
        if v_owned is not null and v_rec."owned_hash" is not null and v_owned is distinct from v_rec."owned_hash" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        elsif v_owned is not null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "subject_imported_updated_at" = v_current, "owned_hash" = v_owned
          where x."id" = v_rec."id";
        elsif v_owned is null and v_current is not null and v_rec."subject_imported_updated_at" is not null and v_current > v_rec."subject_imported_updated_at" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "went_missing_at" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_issue := 'conflict';
          v_done := true;
        end if;
      end if;

      if v_issue = 'conflict' then
        if jsonb_array_length(v_conflict_keys) < 100 then
          v_conflict_keys := v_conflict_keys || to_jsonb(v_key);
        end if;
        perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_key, 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
      else
        perform "better_supabase"."import_clear_issues"(v_run_id, v_entity, v_key);
      end if;

      if not v_done and v_run."dry_run" and jsonb_typeof(v_item -> 'previous') = 'object' and jsonb_array_length(v_diff) < 20 then
        v_diff := v_diff || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'fields', (
          select coalesce(jsonb_agg(jsonb_build_object('field', k, 'old', v_item -> 'previous' -> k, 'new', v_data -> k)), '[]'::jsonb)
          from jsonb_object_keys(v_data) k where (v_data -> k) is distinct from (v_item -> 'previous' -> k))));
      end if;
      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        v_resolved := coalesce((
    select jsonb_object_agg(ref.field, v_ref_map ->> (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field)))
    from (values ('supplier', 'supplier', 'supplier_item'), ('customer', 'customer', 'supplier_item'), ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
    where ref.target = v_entity
      and v_item -> 'refs' ->> ref.field is not null
      and v_ref_map ? (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field))
  ), '{}'::jsonb);
  v_warnings := v_warnings || coalesce((
    select jsonb_agg(jsonb_build_object(
      'entity', v_entity,
      'key', v_item -> 'refs' ->> ref.field,
      'code', 'IMPORT_REF_MISSING',
      'message', 'missing ref ' || ref.field
    ))
    from (values ('supplier', 'supplier', 'supplier_item'), ('customer', 'customer', 'supplier_item'), ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
    where ref.target = v_entity
      and v_item -> 'refs' ->> ref.field is not null
      and not (v_ref_map ? (ref.field || chr(31) || (v_item -> 'refs' ->> ref.field)))
  ), '[]'::jsonb);
  v_call := v_call || jsonb_build_object('resolved', v_resolved);
        if v_entity = any (array['customer']::text[]) then
            v_pending := v_pending || jsonb_build_object('subjectId', v_subject_id, 'found', v_found, 'key', v_key, 'scope', v_scope, 'hash', v_hash);
            v_calls := v_calls || (v_call || jsonb_build_object('subjectId', v_subject_id));
            v_pending_keys := v_pending_keys || (v_scope || chr(31) || v_key);
          else
            case v_entity
      when 'organization_profile' then
        v_subject_type := 'organization_profile';
        v_out := "better_supabase"."import_organization_profile"(v_run_id, v_call, v_subject_id);
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'party_discount_group' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party_discount_group"(v_run_id, v_call, v_subject_id);
      when 'product' then
        v_subject_type := 'product';
        v_out := "better_supabase"."import_product"(v_run_id, v_call, v_subject_id);
      when 'product_category' then
        v_subject_type := 'product_category';
        v_out := "better_supabase"."import_product_category"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'stock_allocation' then
        v_subject_type := 'stock_allocation';
        v_out := "better_supabase"."import_stock_allocation"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'party' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party"(v_run_id, v_call, v_subject_id);
      when 'party_contact' then
        v_subject_type := 'party_contact';
        v_out := "better_supabase"."import_party_contact"(v_run_id, v_call, v_subject_id);
      when 'contact_method' then
        v_subject_type := 'contact_method';
        v_out := "better_supabase"."import_contact_method"(v_run_id, v_call, v_subject_id);
      when 'party_location' then
        v_subject_type := 'party_location';
        v_out := "better_supabase"."import_party_location"(v_run_id, v_call, v_subject_id);
      when 'party_bank_account' then
        v_subject_type := 'party_bank_account';
        v_out := "better_supabase"."import_party_bank_account"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'invoice_allocation' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_allocation"(v_run_id, v_call, v_subject_id);
      when 'meter_reading' then
        v_subject_type := 'meter_reading';
        v_out := "better_supabase"."import_meter_reading"(v_run_id, v_call, v_subject_id);
      when 'due_check' then
        v_subject_type := 'due_check';
        v_out := "better_supabase"."import_due_check"(v_run_id, v_call, v_subject_id);
      when 'asset' then
        v_subject_type := 'asset';
        v_out := "better_supabase"."import_asset"(v_run_id, v_call, v_subject_id);
      when 'asset_identifier' then
        v_subject_type := 'asset_identifier';
        v_out := "better_supabase"."import_asset_identifier"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      when 'customer_row' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

            v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
          end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, coalesce(v_key, ''), 'error', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), v_message);
    end;
  end loop;

  if cardinality(v_pending) > 0 then
          begin
            case v_entity
          when 'customer' then
            v_subject_type := 'customer';
            v_raw := "public"."import_customer_batch"(v_run_id, to_jsonb(v_calls));
            else
              v_raw := null;
            end case;
            if jsonb_typeof(v_raw) is distinct from 'array' or jsonb_array_length(v_raw) <> cardinality(v_pending) then
              raise exception 'a batch target returns one result per item' using errcode = '22023';
            end if;
            v_results := array(select e.value from jsonb_array_elements(v_raw) e);
          exception when others then
            v_results := null;
          end;
          for v_i in 1 .. cardinality(v_pending) loop
            v_p := v_pending[v_i];
            v_key := v_p ->> 'key';
            v_scope := v_p ->> 'scope';
            v_hash := v_p ->> 'hash';
            v_found := (v_p ->> 'found')::boolean;
            v_subject_id := v_p ->> 'subjectId';
            begin
              if v_results is null then
                v_call := v_calls[v_i];
                case v_entity
      when 'organization_profile' then
        v_subject_type := 'organization_profile';
        v_out := "better_supabase"."import_organization_profile"(v_run_id, v_call, v_subject_id);
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'discount_group' then
        v_subject_type := 'discount_group';
        v_out := "better_supabase"."import_discount_group"(v_run_id, v_call, v_subject_id);
      when 'discount_rule' then
        v_subject_type := 'discount_rule';
        v_out := "better_supabase"."import_discount_rule"(v_run_id, v_call, v_subject_id);
      when 'party_discount_group' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party_discount_group"(v_run_id, v_call, v_subject_id);
      when 'product' then
        v_subject_type := 'product';
        v_out := "better_supabase"."import_product"(v_run_id, v_call, v_subject_id);
      when 'product_category' then
        v_subject_type := 'product_category';
        v_out := "better_supabase"."import_product_category"(v_run_id, v_call, v_subject_id);
      when 'stock_count' then
        v_subject_type := 'stock_count';
        v_out := "better_supabase"."import_stock_count"(v_run_id, v_call, v_subject_id);
      when 'stock_allocation' then
        v_subject_type := 'stock_allocation';
        v_out := "better_supabase"."import_stock_allocation"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'party' then
        v_subject_type := 'party';
        v_out := "better_supabase"."import_party"(v_run_id, v_call, v_subject_id);
      when 'party_contact' then
        v_subject_type := 'party_contact';
        v_out := "better_supabase"."import_party_contact"(v_run_id, v_call, v_subject_id);
      when 'contact_method' then
        v_subject_type := 'contact_method';
        v_out := "better_supabase"."import_contact_method"(v_run_id, v_call, v_subject_id);
      when 'party_location' then
        v_subject_type := 'party_location';
        v_out := "better_supabase"."import_party_location"(v_run_id, v_call, v_subject_id);
      when 'party_bank_account' then
        v_subject_type := 'party_bank_account';
        v_out := "better_supabase"."import_party_bank_account"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'open_item' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_open_item"(v_run_id, v_call, v_subject_id);
      when 'invoice_allocation' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_allocation"(v_run_id, v_call, v_subject_id);
      when 'meter_reading' then
        v_subject_type := 'meter_reading';
        v_out := "better_supabase"."import_meter_reading"(v_run_id, v_call, v_subject_id);
      when 'due_check' then
        v_subject_type := 'due_check';
        v_out := "better_supabase"."import_due_check"(v_run_id, v_call, v_subject_id);
      when 'asset' then
        v_subject_type := 'asset';
        v_out := "better_supabase"."import_asset"(v_run_id, v_call, v_subject_id);
      when 'asset_identifier' then
        v_subject_type := 'asset_identifier';
        v_out := "better_supabase"."import_asset_identifier"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      when 'customer_row' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;
              else
                v_out := v_results[v_i];
                if jsonb_typeof(v_out) = 'object' and v_out ? 'error' then
                  raise exception '%', coalesce(v_out -> 'error' ->> 'message', 'the import target refused the item')
                    using hint = coalesce(v_out -> 'error' ->> 'code', 'IMPORT_ITEM_INVALID');
                end if;
              end if;
              v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
  if not exists (
    select 1 from jsonb_array_elements(v_subjects) s
    where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
  ) then
    raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
    if jsonb_typeof(v_subject -> 'warnings') = 'array' then
      v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
    end if;
    insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_imported_updated_at", "source_updated_at", "went_missing_at")
    values (
      v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
      coalesce(v_subject ->> 'role', 'primary'),
      coalesce(v_subject ->> 'subjectType', v_subject_type),
      v_subject ->> 'subjectId',
      v_hash, v_run_id, v_run_id,
      coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
      v_source_at,
      null
    )
    on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
      "subject_type" = excluded."subject_type",
      "subject_id" = excluded."subject_id",
      "content_hash" = excluded."content_hash",
      "last_run_id" = excluded."last_run_id",
      "subject_imported_updated_at" = excluded."subject_imported_updated_at",
      "source_updated_at" = coalesce(excluded."source_updated_at", "better_supabase"."import_records"."source_updated_at"),
      "went_missing_at" = null;
  end loop;

  if v_found then
    v_updated := v_updated + 1;
  else
    v_inserted := v_inserted + 1;
  end if;
  
            exception when others then
              get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
              v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
            end;
          end loop;
          v_pending := '{}';
          v_calls := '{}';
          v_pending_keys := '{}';
        end if;

  perform "better_supabase"."import_note_warnings"(v_run_id, v_entity, v_warnings);

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_conflict_keys) > 0 then jsonb_build_object('conflictKeys', v_conflict_keys) else '{}'::jsonb end || case when jsonb_array_length(v_diff) > 0 then jsonb_build_object('diff', v_diff) else '{}'::jsonb end || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_supplier_item (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_supplier_item.item ->> 'tenant')::uuid;
  v_data jsonb := import_supplier_item.item -> 'data';
  v_supplier uuid;
  v_merged jsonb;
  v_code text;
  v_price text;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_supplier := coalesce(
      nullif(v_data ->> 'supplierId', '')::uuid,
      nullif(import_supplier_item.item -> 'resolved' ->> 'supplier', '')::uuid,
      nullif(import_supplier_item.item -> 'resolved' ->> 'customer', '')::uuid
    );
  exception when invalid_text_representation then
    raise exception 'supplierId must be a uuid' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_supplier is null then
    raise exception 'a supplier item needs a supplierId, or a supplier or customer ref that an earlier entity imported' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_merged := (case when jsonb_typeof(v_data -> 'row') = 'object' then "better_supabase"."supplier_item_from_row"(v_tenant, v_supplier, v_data -> 'row') else '{}'::jsonb end) || (v_data - 'row' - 'supplierId');
  v_code := nullif(btrim(v_merged ->> 'code'), '');
  v_price := v_merged ->> 'price';
  if v_code is null or length(v_code) > 100 then
    raise exception 'a supplier item needs a code of up to 100 characters' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_price is not null and v_price !~ '^[0-9]{1,18}$' then
    raise exception 'price is a whole number of minor units' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_merged ->> 'currency' is not null and "better_supabase"."currency_minor_units"(upper(v_merged ->> 'currency')) is null then
    raise exception 'not an ISO 4217 currency code' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if import_supplier_item.subject_id is null then
    insert into "better_supabase"."supplier_items" as x ("tenant_id", "supplier_id", "code", "description", "price", "currency", "unit", "keywords_text")
    values (v_tenant, v_supplier, v_code, v_merged ->> 'description', v_price::bigint, upper(v_merged ->> 'currency'), v_merged ->> 'unit', v_merged ->> 'keywords')
    on conflict ("tenant_id", "supplier_id", "code") do update set "description" = excluded."description", "price" = excluded."price",
      "currency" = excluded."currency", "unit" = excluded."unit", "keywords_text" = excluded."keywords_text", "updated_at" = now()
    returning x."id", x."updated_at" into v_id, v_updated;
  else
    update "better_supabase"."supplier_items" x set "supplier_id" = v_supplier, "code" = v_code, "description" = v_merged ->> 'description', "price" = v_price::bigint,
      "currency" = upper(v_merged ->> 'currency'), "unit" = v_merged ->> 'unit', "keywords_text" = v_merged ->> 'keywords', "updated_at" = now()
    where x."id" = import_supplier_item.subject_id::uuid and x."tenant_id" = v_tenant
    returning x."id", x."updated_at" into v_id, v_updated;
    if not found then
      raise exception 'the supplier item no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_upsert_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_upsert_batch.run;
  v_entity text := import_upsert_batch.entity;
  v_run "better_supabase"."import_runs";
  v_result jsonb;
  v_row jsonb;
  v_name text;
  v_previous jsonb := '{}'::jsonb;
begin
  -- No row lock here: two batches of one run write at the same time, and the
  -- counts update at the end is the only statement that locks the run row.
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  if coalesce((v_run."plan" ->> 'unordered')::boolean, false) is distinct from true
    and jsonb_typeof(v_run."plan" -> 'waves') = 'array'
    and exists (
      select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as w(wave, n)
      where w.wave ? v_entity and exists (
        select 1 from jsonb_array_elements(v_run."plan" -> 'waves') with ordinality as earlier(wave, n)
        cross join lateral jsonb_array_elements_text(earlier.wave) dep(entity)
        join "better_supabase"."import_chunks" c on c."run_id" = v_run_id
          and c."entity" = dep.entity and c."status" <> 'done'
        where earlier.n < w.n)) then
    raise exception 'an earlier import wave still has open chunks' using errcode = '55000', hint = 'IMPORT_DEPENDENCY_OPEN';
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    v_previous := v_previous || jsonb_build_object(v_name, coalesce(current_setting(v_name, true), ''));
  end loop;
  perform "better_supabase"."begin_import_session"(v_run_id);
  perform set_config('better_supabase.search_deferred', 'on', true);

  if v_run."dry_run" then
    begin
      v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
      raise exception 'dry run' using errcode = 'BSDRY';
    exception when sqlstate 'BSDRY' then
      null;
    end;
  else
    v_result := "better_supabase"."import_apply_batch"(v_run_id, v_entity, import_upsert_batch.items);
  end if;

  if v_run."dry_run" then
    for v_row in select e.value from jsonb_array_elements(coalesce(v_result -> 'conflictKeys', '[]'::jsonb)) e loop
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_row #>> '{}', 'conflict', 'IMPORT_CONFLICT', 'the subject changed after the last import');
    end loop;
    for v_row in select e.value from jsonb_array_elements(coalesce(v_result -> 'errors', '[]'::jsonb)) e loop
      perform "better_supabase"."import_note_issue"(v_run_id, v_entity, v_row ->> 'key', 'error', coalesce(nullif(v_row ->> 'code', ''), 'IMPORT_ITEM_INVALID'), coalesce(v_row ->> 'message', ''));
    end loop;
    perform "better_supabase"."import_note_warnings"(v_run_id, v_entity, v_result -> 'warnings');
  end if;

  foreach v_name in array array['better_supabase.import_run', 'better_supabase.correlation_id', 'better_supabase.import_events', 'better_supabase.import_audit', 'better_supabase.search_deferred'] loop
    perform set_config(v_name, v_previous ->> v_name, true);
  end loop;

  update "better_supabase"."import_runs" r set
    "counts" = jsonb_set(r."counts", array[v_entity], jsonb_build_object(
      'inserted', coalesce(r."counts" -> v_entity ->> 'inserted', '0')::integer + coalesce((v_result ->> 'inserted')::integer, 0),
      'updated', coalesce(r."counts" -> v_entity ->> 'updated', '0')::integer + coalesce((v_result ->> 'updated')::integer, 0),
      'unchanged', coalesce(r."counts" -> v_entity ->> 'unchanged', '0')::integer + coalesce((v_result ->> 'unchanged')::integer, 0),
      'conflicted', coalesce(r."counts" -> v_entity ->> 'conflicted', '0')::integer + coalesce((v_result ->> 'conflicted')::integer, 0),
      'missing', coalesce((r."counts" -> v_entity ->> 'missing')::integer, 0)
    )),
    "errors" = r."errors" || coalesce(v_result -> 'errors', '[]'::jsonb),
    "diff" = (select coalesce(jsonb_agg(d.value), '[]'::jsonb) from (
      select value from jsonb_array_elements(r."diff" || coalesce(v_result -> 'diff', '[]'::jsonb)) value limit 100
    ) d)
  where r."id" = v_run_id;
  return v_result || jsonb_build_object('dryRun', v_run."dry_run");
end;
$function$;

ALTER TABLE "better_supabase"."tax_rates"
  ADD CONSTRAINT "tax_rates_tenant_code_fkey" FOREIGN KEY (tax_code_id, tenant_id) REFERENCES better_supabase.tax_codes(id, tenant_id) ON DELETE CASCADE;
