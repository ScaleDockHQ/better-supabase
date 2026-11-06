SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.clone_invoice (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."clone_invoice"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.clone_maintenance_request (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."clone_maintenance_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.clone_quote (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."clone_quote"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.clone_row (
  target    regclass,
  source    uuid,
  overrides jsonb    DEFAULT NULL::jsonb
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."clone_row"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.clone_work_item (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."clone_work_item"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.template_table (
  target regclass
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."template_table"($1) $function$;

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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."invoices" x where x."id" = clone_invoice.source;
  if not found then
    raise exception 'no such invoice' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'invoices.write'), false)) then
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
  v_created := "better_supabase"."create_invoice"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object('title', v_src."title", 'currency', v_src."currency", 'templateId', null, 'sourceTemplateId', null)) || (coalesce(clone_invoice.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), null);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."invoice_lines"
  select (jsonb_populate_record(null::"better_supabase"."invoice_lines", to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), 'parent_id', v_id))).*
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."maintenance_requests" x where x."id" = clone_maintenance_request.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'facilities.write'), false)) then
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
  v_created := "better_supabase"."create_maintenance_request"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
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
  select c."tenant_id", v_id, c."title", false, c."rank"
  from "better_supabase"."maintenance_request_checklist_items" c where c."maintenance_request_id" = clone_maintenance_request.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select g."tenant_id", g."tag_id", g."subject_type", v_id::text
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = clone_quote.source;
  if not found then
    raise exception 'no such quote' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'quotes.write'), false)) then
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
  v_created := "better_supabase"."create_quote"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object('title', v_src."title", 'currency', v_src."currency", 'templateId', null, 'sourceTemplateId', null)) || (coalesce(clone_quote.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), null);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines"
  select (jsonb_populate_record(null::"better_supabase"."quote_lines", to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), 'parent_id', v_id))).*
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

CREATE OR REPLACE FUNCTION better_supabase.clone_row (
  target    regclass,
  source    uuid,
  overrides jsonb    DEFAULT NULL::jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
  v_new uuid := gen_random_uuid();
  v_template uuid;
  v_cols text;
  v_vals text;
  v_child record;
begin
  execute format('select to_jsonb(t) from %s t where t.id = $1', target) into v_row using source;
  if v_row is null then
    raise exception 'No such row' using errcode = 'P0002', hint = 'TEMPLATE_NOT_FOUND';
  end if;
  v_template := nullif(v_row ->> 'template_id', '')::uuid;
  v_row := v_row || coalesce(overrides, '{}'::jsonb) || jsonb_build_object('id', v_new);
  if not (coalesce(overrides, '{}'::jsonb) ? 'template_id') then
    v_row := v_row || jsonb_build_object('template_id', null);
  end if;
  if v_template is not null and not (coalesce(overrides, '{}'::jsonb) ? 'source_template_id') then
    v_row := v_row || jsonb_build_object('source_template_id', v_template);
  end if;
  select string_agg(format('%I', key), ', '), string_agg(format('%L', value), ', ')
    into v_cols, v_vals
    from jsonb_each_text(v_row);
  execute format('insert into %s (%s) values (%s)', target, v_cols, v_vals);
  for v_child in
    select c.conrelid::regclass as child, a.attname as parent
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.confrelid = target and c.contype = 'f' and c.conrelid <> target
  loop
    execute format(
      'insert into %s select (jsonb_populate_record(null::%s, to_jsonb(x) || jsonb_build_object(%L, $1, ''id'', gen_random_uuid()))).* from %s x where x.%I = $2',
      v_child.child, v_child.child, v_child.parent, v_child.child, v_child.parent
    ) using v_new, source;
  end loop;
  return v_new;
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."work_items" x where x."id" = clone_work_item.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'tasks.write'), false)) then
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
  v_created := "better_supabase"."create_work_item"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
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
  select c."tenant_id", v_id, c."title", false, c."rank"
  from "better_supabase"."work_item_checklist_items" c where c."work_item_id" = clone_work_item.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select g."tenant_id", g."tag_id", g."subject_type", v_id::text
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

CREATE OR REPLACE FUNCTION better_supabase.decide_quote (
  quote    uuid,
  decision text,
  note     text,
  by       text,
  selected jsonb DEFAULT NULL::jsonb,
  actor    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_user_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_user_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_invoice (
  invoice      uuid,
  issued_on    date,
  due_on       date  DEFAULT NULL::date,
  actor        jsonb DEFAULT NULL::jsonb,
  fixed_number text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_original "better_supabase"."invoices";
  v_seq bigint;
  v_identifier text;
  v_issued_on date := coalesce(issue_invoice.issued_on, current_date);
  v_warnings jsonb;
  v_early_bps integer;
  v_early_days integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  
  if v_row."status" <> 'draft' then
    raise exception 'the invoice was already issued' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if not exists (select 1 from "better_supabase"."invoice_lines" x where x."parent_id" = v_row."id") then
    raise exception 'an invoice needs a line before it is issued' using errcode = '23514', hint = 'INVOICE_EMPTY';
  end if;
  if issue_invoice.due_on < v_issued_on then
    raise exception 'an invoice falls due on or after its issue date' using errcode = '22023', hint = 'INVOICE_DUE_INVALID';
  end if;
  if issue_invoice.actor is not null then
    if jsonb_typeof(issue_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(issue_invoice.actor ->> 'ip', '')::inet, nullif(issue_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(issue_invoice.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  perform "better_supabase"."issue_invoice_tax"(v_row."id", v_issued_on);
  select z."discount_bps", z."discount_days" into v_early_bps, v_early_days
  from "better_supabase"."payment_terms" z where z."id" = v_row."payment_terms_id";
  if v_row."kind" = 'credit_note' then
    select * into v_original from "better_supabase"."invoices" x where x."id" = v_row."original_id" for update;
    if v_row."total" > v_original."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_original."id"), 0) - v_original."credited_total" then
      raise exception 'a credit note can''t exceed the invoice''s total less its earlier credits' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
    end if;
    if v_row."direction" = 'purchase' then
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_credit_note' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'BCN-' || v_seq::text;
  end if;
    else
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'CN-' || v_seq::text;
  end if;
    end if;
  else
    if v_row."direction" = 'purchase' then
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_bill' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_bill' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_bill' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'BILL-' || v_seq::text;
  end if;
    else
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'invoice' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'invoice' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'INV-' || v_seq::text;
  end if;
    end if;
  end if;
  if v_row."kind" = 'invoice' and not v_row."direction" = 'purchase' and coalesce(v_row."company_id"::text, v_row."contact_id"::text) is not null then
    declare
      v_limit bigint;
      v_block text;
    begin
      select s.credit_limit, s.credit_block into v_limit, v_block from (select p."credit_limit", p."credit_currency", p."credit_block" from "better_supabase"."companies" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null union all select p."credit_limit", p."credit_currency", p."credit_block" from "better_supabase"."people" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null) s(credit_limit, credit_currency, credit_block)
      where s.credit_limit is not null and coalesce(s.credit_currency, v_row."currency") = v_row."currency"
      order by s.credit_limit limit 1;
      if v_limit is not null and v_block is distinct from 'none' and (select coalesce(sum((o."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = o."id"), 0) - o."credited_total" - o."paid_total")), 0) from "better_supabase"."invoices" o
        where o."tenant_id" = v_row."tenant_id" and o."id" <> v_row."id" and o."currency" = v_row."currency"
          and coalesce(o."company_id"::text, o."contact_id"::text) = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and not o."direction" = 'purchase'
          and o."kind" = 'invoice' and o."status" in ('issued', 'partially_paid')) + v_row."total" > v_limit and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'orders.override_credit'), false)) then
        if v_block = 'soft' then
          v_warnings := coalesce(v_warnings, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
            'code', 'INVOICE_CREDIT_LIMIT_EXCEEDED', 'message', 'this invoice takes the customer over their credit limit', 'limit', v_limit::text));
        else
          raise exception 'this invoice takes the customer over their credit limit' using errcode = '55000', hint = 'INVOICE_CREDIT_LIMIT_EXCEEDED';
        end if;
      end if;
    end;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = v_issued_on,
    "due_on" = coalesce(issue_invoice.due_on, v_issued_on + x."terms_days"),
    "discount_due_on" = case when coalesce(v_early_bps, 0) > 0 and x."kind" = 'invoice' then v_issued_on + v_early_days end,
    "discount_amount_early" = case when coalesce(v_early_bps, 0) > 0 and x."kind" = 'invoice'
      then ((x."total"::numeric * v_early_bps + 5000) / 10000)::bigint end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.issued', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'dueOn', v_row."due_on"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."kind" = 'credit_note' then
    update "better_supabase"."invoices" x set "credited_total" = x."credited_total" + v_row."total", "updated_at" = now()
    where x."id" = v_original."id"
    returning * into v_original;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_original."id"
  returning * into v_original;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_original."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_original;
    perform "better_supabase".emit_event('invoice.credited', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'creditNoteId', v_row."id", 'amount', v_row."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    if v_original."status" = 'paid' then
      perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'total', v_original."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    end if;
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice', v_row."id"::text);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb))|| case when v_warnings is null then '{}'::jsonb else jsonb_build_object('warnings', v_warnings) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_quote (
  quote uuid,
  actor jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested') or v_row."status" in ('rejected', 'withdrawn', 'expired')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "better_supabase"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "valid_until" = case when x."status" in ('rejected', 'withdrawn', 'expired') then greatest(x."valid_until", current_date + 30) else x."valid_until" end, "viewed_at" = case when x."status" in ('rejected', 'withdrawn', 'expired') then null else x."viewed_at" end, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."quote_versions" ("tenant_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."tenant_id", v_row."id", v_row."revision", (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  perform "better_supabase".emit_event('quote.sent', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.template_row_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if new.template_id is distinct from old.template_id then
    raise exception 'A row cannot change between a template and a live record' using errcode = '23514', hint = 'TEMPLATE_IMMUTABLE';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.template_table (
  target regclass
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  execute format('alter table %s add column if not exists template_id uuid unique references "better_supabase"."templates" (id) on delete cascade', target);
  execute format('alter table %s add column if not exists source_template_id uuid references "better_supabase"."templates" (id) on delete set null', target);
  execute format('drop trigger if exists bsb_template_row on %s', target);
  execute format('create trigger bsb_template_row before update of template_id on %s for each row execute function "better_supabase"."template_row_guard"()', target);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."clone_invoice"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."clone_invoice"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."clone_maintenance_request"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."clone_maintenance_request"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."clone_quote"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."clone_quote"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."clone_row"(regclass, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."clone_row"(regclass, uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."clone_work_item"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."clone_work_item"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."template_table"(regclass) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."template_table"(regclass) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."clone_invoice"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."clone_invoice"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."clone_maintenance_request"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."clone_maintenance_request"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."clone_quote"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."clone_quote"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."clone_row"(regclass, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."clone_row"(regclass, uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."clone_work_item"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."clone_work_item"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."template_row_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."template_table"(regclass) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."template_table"(regclass) TO "service_role";
