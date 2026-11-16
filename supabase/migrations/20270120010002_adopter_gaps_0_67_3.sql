SET local check_function_bodies = off;

DROP TRIGGER "bsb_audit" ON "better_supabase"."accounting_accounts";

DROP TRIGGER "bsb_audit" ON "better_supabase"."activities";

DROP TRIGGER "bsb_audit" ON "better_supabase"."advisory_products";

DROP TRIGGER "bsb_audit" ON "better_supabase"."agents";

DROP TRIGGER "bsb_audit" ON "better_supabase"."ai_chats";

DROP TRIGGER "bsb_audit" ON "better_supabase"."ai_projects";

DROP TRIGGER "bsb_audit" ON "better_supabase"."announcements";

DROP TRIGGER "bsb_audit" ON "better_supabase"."asset_locations";

DROP TRIGGER "bsb_audit" ON "better_supabase"."bank_accounts";

DROP TRIGGER "bsb_audit" ON "better_supabase"."bookings";

DROP TRIGGER "bsb_audit" ON "better_supabase"."care_plans";

DROP TRIGGER "bsb_audit" ON "better_supabase"."care_rules";

DROP TRIGGER "bsb_audit" ON "better_supabase"."case_kinds";

DROP TRIGGER "bsb_audit" ON "better_supabase"."cases";

DROP TRIGGER "bsb_audit" ON "better_supabase"."commission_plans";

DROP TRIGGER "bsb_audit" ON "better_supabase"."companies";

DROP TRIGGER "bsb_audit" ON "better_supabase"."compliance_policies";

DROP TRIGGER "bsb_audit" ON "better_supabase"."consent_purposes";

DROP TRIGGER "bsb_audit" ON "better_supabase"."conversations";

DROP TRIGGER "bsb_audit" ON "better_supabase"."deals";

DROP TRIGGER "bsb_audit" ON "better_supabase"."donation_funds";

DROP TRIGGER "bsb_audit" ON "better_supabase"."enrollment_programs";

DROP TRIGGER "bsb_audit" ON "better_supabase"."expense_categories";

DROP TRIGGER "bsb_audit" ON "better_supabase"."field_definitions";

DROP TRIGGER "bsb_audit" ON "better_supabase"."funding_claims";

DROP TRIGGER "bsb_audit" ON "better_supabase"."goals";

DROP TRIGGER "bsb_audit" ON "better_supabase"."inboxes";

DROP TRIGGER "bsb_audit" ON "better_supabase"."inspection_programs";

DROP TRIGGER "bsb_audit" ON "better_supabase"."invoices";

DROP TRIGGER "bsb_audit" ON "better_supabase"."leave_types";

DROP TRIGGER "bsb_audit" ON "better_supabase"."legal_entities";

DROP TRIGGER "bsb_audit" ON "better_supabase"."lims_methods";

DROP TRIGGER "bsb_audit" ON "better_supabase"."maintenance_plans";

DROP TRIGGER "bsb_audit" ON "better_supabase"."maintenance_requests";

DROP TRIGGER "bsb_audit" ON "better_supabase"."medications";

DROP TRIGGER "bsb_audit" ON "better_supabase"."meetings";

DROP TRIGGER "bsb_audit" ON "better_supabase"."observation_definitions";

DROP TRIGGER "bsb_audit" ON "better_supabase"."option_sets";

DROP TRIGGER "bsb_audit" ON "better_supabase"."people";

DROP TRIGGER "bsb_audit" ON "better_supabase"."pipelines";

DROP TRIGGER "bsb_audit" ON "better_supabase"."post_boards";

DROP TRIGGER "bsb_audit" ON "better_supabase"."posts";

DROP TRIGGER "bsb_audit" ON "better_supabase"."qualification_types";

DROP TRIGGER "bsb_audit" ON "better_supabase"."risks";

DROP TRIGGER "bsb_audit" ON "better_supabase"."score_models";

DROP TRIGGER "bsb_audit" ON "better_supabase"."shift_templates";

DROP TRIGGER "bsb_audit" ON "better_supabase"."shipments";

DROP TRIGGER "bsb_audit" ON "better_supabase"."sla_policies";

DROP TRIGGER "bsb_audit" ON "better_supabase"."subject_collections";

DROP TRIGGER "bsb_audit" ON "better_supabase"."tax_codes";

DROP TRIGGER "bsb_audit" ON "better_supabase"."tills";

DROP TRIGGER "bsb_audit" ON "better_supabase"."time_entries";

DROP TRIGGER "bsb_audit" ON "better_supabase"."work_centers";

DROP TRIGGER "bsb_audit" ON "better_supabase"."work_items";

DROP TRIGGER "bsb_audit" ON "better_supabase"."work_projects";

CREATE OR REPLACE FUNCTION better_supabase.add_invoice_charge (
  invoice     uuid,
  amount      bigint,
  currency    text,
  description text,
  actor       jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_charge uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = add_invoice_charge.invoice for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    if v_row."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not charge this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes charges' using errcode = '55000', hint = 'INVOICE_NOT_CHARGEABLE';
  end if;
  if coalesce(add_invoice_charge.amount, 0) <= 0 then
    raise exception 'a charge has a positive amount' using errcode = '22023', hint = 'INVOICE_CHARGE_INVALID';
  end if;
  if upper(add_invoice_charge.currency) is distinct from v_row."currency" then
    raise exception 'a charge must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
  end if;
  if add_invoice_charge.actor is not null then
    if jsonb_typeof(add_invoice_charge.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(add_invoice_charge.actor ->> 'ip', '')::inet, nullif(add_invoice_charge.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(add_invoice_charge.actor::text, ''), true);
  insert into "better_supabase"."invoice_charges" ("tenant_id", "invoice_id", "amount", "currency", "description", "created_by")
  values (v_row."tenant_id", v_row."id", add_invoice_charge.amount, v_row."currency", nullif(trim(add_invoice_charge.description), ''), auth.uid())
  returning "id" into v_charge;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_charge', v_charge::text);
  end if;
  perform "better_supabase".emit_event('invoice.charged', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.charged',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice charged',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_invoice (
  invoice uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = archive_invoice.invoice for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    if v_row."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not archive this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    return true;
  end if;
  update "better_supabase"."invoices" x set "archived_at" = now(), "updated_at" = now() where x."id" = v_row."id";
  perform "better_supabase".emit_event('invoice.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit (
  target          regclass,
  ignore          text[]       DEFAULT '{}'::text[],
  replace_trigger boolean      DEFAULT false,
  redact          text[]       DEFAULT '{}'::text[],
  category        text         DEFAULT NULL::text,
  event_prefix    text         DEFAULT NULL::text,
  target_type     text         DEFAULT NULL::text,
  tenant_column   text         DEFAULT NULL::text,
  label_column    text         DEFAULT NULL::text,
  tenant_path     text         DEFAULT NULL::text,
  tenant_function regprocedure DEFAULT NULL::regprocedure,
  deferred        boolean      DEFAULT false,
  statement       boolean      DEFAULT false,
  archive_column  text         DEFAULT NULL::text,
  archive_value   text         DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  keys text[];
  path_steps jsonb := '[]';
  path_column text;
  parts text[];
  cur_rel regclass := target;
  cur_col text;
  ref_rel regclass;
  ref_col text;
  segment text;
  seg_table text;
  seg_read text;
  base_settings jsonb;
  trigger_kind text := case when audit.deferred then 'constraint ' else '' end;
  trigger_timing text := case when audit.deferred then 'deferrable initially deferred ' else '' end;
begin
  if audit.statement then
    if audit.deferred or audit.tenant_path is not null or audit.tenant_function is not null then
      raise exception 'audit(statement => true) does not combine with deferred, tenant_path or tenant_function';
    end if;
    if not exists (select 1 from pg_catalog.pg_index i where i.indrelid = audit.target and i.indisprimary) then
      raise exception 'audit(statement => true) needs a primary key on %', audit.target;
    end if;
  end if;
  if audit.tenant_path is not null then
    parts := regexp_split_to_array(btrim(audit.tenant_path), '\s*->\s*');
    if coalesce(array_length(parts, 1), 0) < 2 then
      raise exception 'tenant_path % needs a column and at least one table.column hop', audit.tenant_path;
    end if;
    path_column := parts[1];
    cur_col := path_column;
    for i in 2..array_length(parts, 1) loop
      segment := parts[i];
      seg_read := substring(segment from '[^.]+$');
      seg_table := substring(segment from '^(.*)\.[^.]+$');
      if seg_read is null or seg_table is null then
        raise exception 'tenant_path hop % must be table.column', segment;
      end if;
      select con.confrelid::regclass, a.attname::text into ref_rel, ref_col
      from pg_catalog.pg_constraint con
      join pg_catalog.pg_attribute a on a.attrelid = con.confrelid and a.attnum = con.confkey[1]
      where con.contype = 'f' and con.conrelid = cur_rel and array_length(con.conkey, 1) = 1
        and con.conkey[1] = (
          select c.attnum from pg_catalog.pg_attribute c
          where c.attrelid = cur_rel and c.attname = cur_col and not c.attisdropped
        );
      if ref_rel is null then
        raise exception 'tenant_path: % has no foreign key on column %', cur_rel, cur_col;
      end if;
      if pg_catalog.to_regclass(case when position('.' in seg_table) > 0 then seg_table else (select n.nspname from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.oid = audit.target) || '.' || seg_table end) is distinct from ref_rel then
        raise exception 'tenant_path: % does not reference %', cur_col, seg_table;
      end if;
      path_steps := path_steps || jsonb_build_array(jsonb_build_object('table', ref_rel::text, 'ref', ref_col, 'read', seg_read));
      cur_rel := ref_rel;
      cur_col := seg_read;
    end loop;
  end if;
  perform better_supabase.replace_equivalent_triggers(
    target, 'bsb_audit', 'audit', replace_trigger
  );
  select array_agg(c.attname::text order by k.ord) into keys
  from pg_catalog.pg_index i
  cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
  join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
  where i.indrelid = audit.target and i.indisprimary;
  delete from "better_supabase"."audited_tables" a where a."target" = audit.target;
  base_settings := jsonb_strip_nulls(jsonb_build_object(
    'ignore', to_jsonb(coalesce(audit.ignore, '{}')),
    'redact', to_jsonb(coalesce(audit.redact, '{}')),
    'key_columns', to_jsonb(keys),
    'category', audit.category,
    'event_prefix', audit.event_prefix,
    'target_type', audit.target_type,
    'tenant_column', audit.tenant_column,
    'label_column', audit.label_column,
    'tenant_path', case when audit.tenant_path is not null then jsonb_build_object('column', path_column, 'steps', path_steps) end,
    'tenant_function', audit.tenant_function::text,
    'archive_column', audit.archive_column,
    'archive_value', audit.archive_value
  ));
  execute format('drop trigger if exists bsb_audit on %s', target);
  execute format('drop trigger if exists bsb_audit_update on %s', target);
  execute format('drop trigger if exists bsb_audit_stmt_insert on %s', target);
  execute format('drop trigger if exists bsb_audit_stmt_update on %s', target);
  execute format('drop trigger if exists bsb_audit_stmt_delete on %s', target);
  if audit.statement then
    execute format(
      'create trigger bsb_audit_stmt_insert after insert on %s referencing new table as new_rows for each statement when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_statement_change(%L)',
      target, base_settings::text
    );
    execute format(
      'create trigger bsb_audit_stmt_update after update on %s referencing old table as old_rows new table as new_rows for each statement when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_statement_change(%L)',
      target, base_settings::text
    );
    execute format(
      'create trigger bsb_audit_stmt_delete after delete on %s referencing old table as old_rows for each statement when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_statement_change(%L)',
      target, base_settings::text
    );
  elsif cardinality(coalesce(audit.ignore, '{}')) > 0 then
    execute format(
      'create %strigger bsb_audit after insert or delete on %s %sfor each row when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_row_change(%L)',
      trigger_kind, target, trigger_timing, base_settings::text
    );
    execute format(
      'create %strigger bsb_audit_update after update on %s %sfor each row when (((to_jsonb(old) - %L::text[]) is distinct from (to_jsonb(new) - %L::text[])) and (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'')) execute function better_supabase.audit_row_change(%L)',
      trigger_kind, target, trigger_timing, audit.ignore, audit.ignore, base_settings::text
    );
  else
    execute format(
      'create %strigger bsb_audit after insert or update or delete on %s %sfor each row when (better_supabase.import_run() is null or current_setting(''better_supabase.import_audit'', true) is distinct from ''summary'') execute function better_supabase.audit_row_change(%L)',
      trigger_kind, target, trigger_timing, base_settings::text
    );
  end if;
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
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function,
      settings ->> 'archive_column' as archive_column, settings ->> 'archive_value' as archive_value
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function,
      null::text as archive_column, null::text as archive_value
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
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
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

CREATE OR REPLACE FUNCTION better_supabase.audit_statement_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  v_integration boolean := better_supabase.import_run() is not null;
begin
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
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function,
      settings ->> 'archive_column' as archive_column, settings ->> 'archive_value' as archive_value
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function,
      null::text as archive_column, null::text as archive_value
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if tg_op = 'INSERT' then
    with src as (
      select null::jsonb as old_row, to_jsonb(n) as new_row from new_rows n
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
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
    l.label,
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  elsif tg_op = 'DELETE' then
    with src as (
      select to_jsonb(o) as old_row, null::jsonb as new_row from old_rows o
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
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
    l.label,
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  else
    with src as (
      select o.j as old_row, n.j as new_row
      from (select to_jsonb(r) as j, (select string_agg(to_jsonb(r) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)) as k from old_rows r) o
      full join (select to_jsonb(r) as j, (select string_agg(to_jsonb(r) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)) as k from new_rows r) n on o.k = n.k
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then case when entry.archive_column is null then 'updated' when (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'archived' when (case when entry.archive_value is null then coalesce(old_row ->> entry.archive_column, 'false') <> 'false' else old_row ->> entry.archive_column is not distinct from entry.archive_value end) and not (case when entry.archive_value is null then coalesce(new_row ->> entry.archive_column, 'false') <> 'false' else new_row ->> entry.archive_column is not distinct from entry.archive_value end) then 'restored' else 'updated' end else 'deleted' end,
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
    l.label,
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.credit_invoice (
  invoice      uuid,
  lines        jsonb,
  note         text,
  fixed_number text  DEFAULT NULL::text,
  issued_on    date  DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_original "better_supabase"."invoices";
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if credit_invoice.fixed_number is not null and better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  select * into v_original from "better_supabase"."invoices" x where x."id" = credit_invoice.invoice;
  if v_original."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_original."tenant_id", case when v_original."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    if v_original."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_original."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not credit this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_original."kind" <> 'invoice' or v_original."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice is credited' using errcode = '55000', hint = 'INVOICE_NOT_CREDITABLE';
  end if;
  insert into "better_supabase"."invoices" ("tenant_id", "kind", "original_id", "title", "company_type", "company_id", "contact_type", "contact_id", legal_entity_id,
    "currency", "terms_days", "note", "prices_include_tax", "direction", "supplier_reference", "purchase_order_id", "dimensions", "created_by")
  values (v_original."tenant_id", 'credit_note', v_original."id", 'Credit for ' || coalesce(v_original."identifier", v_original."title"),
    v_original."company_type", v_original."company_id", v_original."contact_type", v_original."contact_id", v_original.legal_entity_id,
    v_original."currency", 0, nullif(trim(credit_invoice.note), ''), v_original."prices_include_tax", v_original."direction", v_original."supplier_reference", v_original."purchase_order_id", v_original."dimensions", auth.uid())
  returning * into v_row;
  if credit_invoice.lines is null then
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position")
    select x."tenant_id", v_row."id", x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position"
    from "better_supabase"."invoice_lines" x where x."parent_id" = v_original."id";
  else
    perform "better_supabase"."set_invoice_lines"(v_row."id", credit_invoice.lines);
  end if;
  perform "better_supabase".emit_event('invoice.created', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if credit_invoice.fixed_number is not null then
    perform "better_supabase"."issue_invoice"(v_row."id", coalesce(credit_invoice.issued_on, current_date), null, null, credit_invoice.fixed_number);
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_invoice (
  invoice uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = delete_invoice.invoice for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    if v_row."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not delete this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft is deleted; void an issued invoice' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  delete from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id";
  delete from "better_supabase"."invoice_lines" y where y."parent_id" = v_row."id";
  delete from "better_supabase"."relations" y
  where y."kind" = 'created_from' and y."source_type" = 'invoice' and y."source_id" = v_row."id"::text;
  delete from "better_supabase"."invoices" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('invoice.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.is_service_role()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') $function$;

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
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    if v_row."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not issue this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
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

CREATE OR REPLACE FUNCTION better_supabase.record_invoice_payment (
  invoice   uuid,
  amount    bigint,
  currency  text,
  paid_at   timestamp with time zone,
  method    text,
  reference text,
  note      text                     DEFAULT NULL::text,
  actor     jsonb                    DEFAULT NULL::jsonb,
  reason    text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_payment uuid;
  v_reference text;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = record_invoice_payment.invoice for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    if v_row."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not record a payment on this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes payments' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
  end if;
  if coalesce(record_invoice_payment.amount, 0) = 0 then
    raise exception 'a payment has an amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
  end if;
  if upper(record_invoice_payment.currency) is distinct from v_row."currency" then
    raise exception 'a payment must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
  end if;
  if v_row."direction" = 'purchase' and v_row."purchase_order_id" is not null and record_invoice_payment.amount > 0
    and "better_supabase"."invoice_match_result"(v_row."id") ->> 'status' <> 'matched'
    and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.override_match'), false)) then
    raise exception 'the bill doesn''t match its purchase order and receipts; someone with invoices.override_match can pay it' using errcode = '55000', hint = 'INVOICE_MATCH_FAILED';
  end if;
  if record_invoice_payment.actor is not null then
    if jsonb_typeof(record_invoice_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(record_invoice_payment.actor ->> 'ip', '')::inet, nullif(record_invoice_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(record_invoice_payment.actor::text, ''), true);
  -- A recorded reference is a replay that adds nothing, so it skips the check.
  v_reference := nullif(trim(record_invoice_payment.reference), '');
  if v_reference is not null and exists (
    select 1 from "better_supabase"."ledger_transactions" y
    where y."tenant_id" = v_row."tenant_id" and y."idempotency_key" = 'invoice-payment:' || v_reference
  ) then
    return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
  end if;
  if record_invoice_payment.amount < 0 and v_row."paid_total" + record_invoice_payment.amount < 0 then
    raise exception 'a refund can''t exceed what was paid' using errcode = '23514', hint = 'INVOICE_REFUND_TOO_LARGE';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_payment"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_row."id", record_invoice_payment.amount;
    end if;
  end;
  v_was := v_row."status";
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(record_invoice_payment.reason), ''), ''), true);
  v_payment := "better_supabase"."ledger_post"(v_row."tenant_id", case when record_invoice_payment.amount < 0 then 'invoice.refund' else 'invoice.payment' end,
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -record_invoice_payment.amount),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'cash',
      case when v_row."direction" = 'purchase' then 'invoices:paid:' || v_row."currency" else 'invoices:cash:' || v_row."currency" end, 'Invoice payments ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', record_invoice_payment.amount)),
    'invoices', v_row."id"::text, null,
    case when v_reference is not null then 'invoice-payment:' || v_reference end, coalesce(record_invoice_payment.paid_at, now()),
    jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', record_invoice_payment.method, 'reference', v_reference, 'note', nullif(trim(record_invoice_payment.note), ''))));
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_payment', v_payment::text);
  end if;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.payment_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'amount', record_invoice_payment.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."status" = 'paid' and v_was <> 'paid' then
    perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_payment"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_row."id", v_payment;
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
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_invoice (
  invoice uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = restore_invoice.invoice for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    if v_row."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not restore this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."archived_at" is null then
    return true;
  end if;
  update "better_supabase"."invoices" x set "archived_at" = null, "updated_at" = now() where x."id" = v_row."id";
  perform "better_supabase".emit_event('invoice.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_invoice (
  invoice uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_company_type text := coalesce(update_invoice.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := update_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(update_invoice.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := update_invoice.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = update_invoice.invoice for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    if v_row."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not edit this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft changes' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if jsonb_typeof(update_invoice.attrs) is distinct from 'object'
    or (update_invoice.attrs ? 'title' and nullif(trim(update_invoice.attrs ->> 'title'), '') is null) then
    raise exception 'attrs is an object, and a title isn''t empty' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if update_invoice.attrs ->> 'purchaseOrderId' is not null then
    if v_row."direction" is distinct from 'purchase' then
      raise exception 'only a purchase bill refers to a purchase order' using errcode = '22023', hint = 'INVOICE_PURCHASE_ORDER_INVALID';
    end if;
    if not exists (select 1 from "better_supabase"."purchase_orders" y where y."id"::text = (update_invoice.attrs ->> 'purchaseOrderId') and y."tenant_id" = v_row."tenant_id") then
      raise exception 'no such purchase order in this organization' using errcode = 'P0002', hint = 'INVOICE_PURCHASE_ORDER_NOT_FOUND';
    end if;
  end if;
  if update_invoice.attrs ? 'dimensions' and jsonb_typeof(update_invoice.attrs -> 'dimensions') not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (v_company_id)::uuid and s."id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (v_contact_id)::uuid and s."id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."invoices" x set
      "title" = case when update_invoice.attrs ? 'title' then trim(update_invoice.attrs ->> 'title') else x."title" end,
      "company_type" = case when update_invoice.attrs ? 'company' then case when v_company_id is null then null else v_company_type end else x."company_type" end,
      "company_id" = case when update_invoice.attrs ? 'company' then v_company_id else x."company_id" end,
      "contact_type" = case when update_invoice.attrs ? 'contact' then case when v_contact_id is null then null else v_contact_type end else x."contact_type" end,
      "contact_id" = case when update_invoice.attrs ? 'contact' then v_contact_id else x."contact_id" end,
      "terms_days" = case when update_invoice.attrs ? 'termsDays' then (update_invoice.attrs ->> 'termsDays')::integer else x."terms_days" end,
      "note" = case when update_invoice.attrs ? 'note' then update_invoice.attrs ->> 'note' else x."note" end,
      "deposit_bps" = case when update_invoice.attrs ? 'depositBps' then (update_invoice.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "prices_include_tax" = case when update_invoice.attrs ? 'pricesIncludeTax' then coalesce((update_invoice.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "deposit_amount" = case when update_invoice.attrs ? 'depositAmount' then (update_invoice.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "discount_bps" = case when update_invoice.attrs ? 'discountBps' then coalesce((update_invoice.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_invoice.attrs ? 'discountAmount' then coalesce((update_invoice.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "supplier_reference" = case when update_invoice.attrs ? 'supplierReference' then nullif(trim(update_invoice.attrs ->> 'supplierReference'), '') else x."supplier_reference" end,
      "purchase_order_id" = case when update_invoice.attrs ? 'purchaseOrderId' then (update_invoice.attrs ->> 'purchaseOrderId')::uuid else x."purchase_order_id" end,
      "dimensions" = case when update_invoice.attrs ? 'dimensions' then coalesce(nullif(update_invoice.attrs -> 'dimensions', 'null'::jsonb), '{}'::jsonb) else x."dimensions" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or not_null_violation or numeric_value_out_of_range then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  if update_invoice.attrs ? 'pricesIncludeTax' or update_invoice.attrs ? 'discountBps' or update_invoice.attrs ? 'discountAmount' then
    perform "better_supabase"."set_invoice_lines_recount"(v_row."id");
  end if;
  perform "better_supabase".emit_event('invoice.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.void_invoice (
  invoice uuid,
  reason  text,
  actor   jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = void_invoice.invoice for update;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when v_row."direction" = 'purchase' then 'invoices.purchase' else 'invoices.manage' end), false)) then
    if v_row."id" is not null and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)) then
      raise exception 'you may not void this invoice' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
    end if;
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'issued') or v_row."paid_total" <> 0 or v_row."credited_total" <> 0 then
    raise exception 'an invoice with payments or credits is credited, not voided' using errcode = '55000', hint = 'INVOICE_NOT_VOIDABLE';
  end if;
  if void_invoice.actor is not null then
    if jsonb_typeof(void_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(void_invoice.actor ->> 'ip', '')::inet, nullif(void_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(void_invoice.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(void_invoice.reason), ''), ''), true);
  update "better_supabase"."invoices" x set "status" = 'void', "voided_at" = now(),
    "void_reason" = nullif(trim(void_invoice.reason), ''), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice', v_row."id"::text);
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice_charge', c."id"::text)
  from "better_supabase"."invoice_charges" c where c."invoice_id" = v_row."id";
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.voided', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reason', v_row."void_reason"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.voided',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice voided',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reason', v_row."void_reason")
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.accounting_accounts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"accounting_account","event_prefix":"accounting_account","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.activities DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"activity","event_prefix":"activity","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.advisory_products DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"advisory_product","event_prefix":"advisory_product","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.agents DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"agent","event_prefix":"agent","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ai_chats DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"ai_chat","event_prefix":"ai_chat","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ai_projects DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"ai_project","event_prefix":"ai_project","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.announcements DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"announcement","event_prefix":"announcement","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.asset_locations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"asset_location","event_prefix":"asset_location","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bank_accounts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"bank_account","event_prefix":"bank_account","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bookings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"booking","event_prefix":"booking","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_plans DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"care_plan","event_prefix":"care_plan","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_rules DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"care_rule","event_prefix":"care_rule","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.case_kinds DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"case_kind","event_prefix":"case_kind","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.cases DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"case","event_prefix":"case","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.commission_plans DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"commission_plan","event_prefix":"commission_plan","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.companies DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"company","event_prefix":"company","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.compliance_policies DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"compliance_policy","event_prefix":"compliance_policy","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.consent_purposes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"consent_purpose","event_prefix":"consent_purpose","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.conversations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"conversation","event_prefix":"conversation","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.deals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"deal","event_prefix":"deal","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.donation_funds DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"donation_fund","event_prefix":"donation_fund","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.enrollment_programs DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"enrollment_program","event_prefix":"enrollment_program","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.expense_categories DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"expense_category","event_prefix":"expense_category","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.field_definitions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"field_definition","event_prefix":"field_definition","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.funding_claims DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"funding_claim","event_prefix":"funding_claim","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.goals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"goal","event_prefix":"goal","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inboxes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"inbox","event_prefix":"inbox","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inspection_programs DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"inspection_program","event_prefix":"inspection_program","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.invoices DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"invoice","event_prefix":"invoice","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.leave_types DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"leave_type","event_prefix":"leave_type","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.legal_entities DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"legal_entity","event_prefix":"legal_entity","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.lims_methods DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"lims_method","event_prefix":"lims_method","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_plans DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"maintenance_plan","event_prefix":"maintenance_plan","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_requests DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"maintenance_request","event_prefix":"maintenance_request","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.medications DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"medication","event_prefix":"medication","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.meetings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"meeting","event_prefix":"meeting","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.observation_definitions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"observation_definition","event_prefix":"observation_definition","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.option_sets DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"option_set","event_prefix":"option_set","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.people DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"person","event_prefix":"person","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.pipelines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"pipeline","event_prefix":"pipeline","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.post_boards DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"post_board","event_prefix":"post_board","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.posts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"post","event_prefix":"post","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.qualification_types DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"qualification_type","event_prefix":"qualification_type","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.risks DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"risk","event_prefix":"risk","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.score_models DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"score_model","event_prefix":"score_model","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shift_templates DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"shift_template","event_prefix":"shift_template","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shipments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"shipment","event_prefix":"shipment","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.sla_policies DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"sla_policy","event_prefix":"sla_policy","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.subject_collections DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"subject_collection","event_prefix":"subject_collection","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.tax_codes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"tax_code","event_prefix":"tax_code","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.tills DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"till","event_prefix":"till","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.time_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"time_entry","event_prefix":"time_entry","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_centers DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"work_center","event_prefix":"work_center","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_items DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"work_item","event_prefix":"work_item","archive_column":"archived_at"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_projects DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"project","event_prefix":"project","archive_column":"archived_at"}');

REVOKE ALL ON FUNCTION "better_supabase"."audit"(regclass, text[], boolean, text[], text, text, text, text, text, text, regprocedure, boolean, boolean, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."is_service_role"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."is_service_role"() TO "anon", "authenticated", "service_role";
