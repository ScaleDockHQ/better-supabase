SET local check_function_bodies = off;

DROP TRIGGER "bsb_search_customer_index" ON "public"."customers";

CREATE TABLE "better_supabase"."import_search_dirty" (
  "run_id"       uuid NOT NULL,
  "subject_type" text NOT NULL,
  "subject_id"   text NOT NULL,
  CONSTRAINT "import_search_dirty_pkey" PRIMARY KEY (run_id, subject_type, subject_id)
);

ALTER TABLE "better_supabase"."import_search_dirty"
  ENABLE ROW LEVEL SECURITY;

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
    raise exception 'this import already finished' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  update "better_supabase"."import_runs" r set "status" = 'canceled', "finished_at" = now()
  where r."id" = cancel_import_run.id;
  perform "better_supabase"."search_refresh_run"(cancel_import_run.id);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_import_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := finish_import_run.run;
  v_run "better_supabase"."import_runs";
  v_entity text;
  v_missing integer;
  v_total integer := 0;
  v_counts jsonb;
  v_outcome text := 'completed';
  v_expected integer;
  v_applied integer;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id for update;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  v_counts := v_run."counts";

  if v_run."full" then
    for v_entity in select k.key from jsonb_object_keys(v_run."counts") k(key) loop
      select count(*)::integer into v_missing from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
        and x."role" = 'primary' and x."last_run_id" <> v_run_id
        and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      if not v_run."dry_run" then
        update "better_supabase"."import_records" x set "went_missing_at" = coalesce(x."went_missing_at", now())
        where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."entity" = v_entity
          and x."last_run_id" <> v_run_id
          and x."scope" in (select y."scope" from "better_supabase"."import_records" y where y."tenant_id" = v_run."tenant_id" and y."source" = v_run."source" and y."entity" = v_entity and y."last_run_id" = v_run_id);
      end if;
      v_counts := jsonb_set(v_counts, array[v_entity, 'missing'], to_jsonb(v_missing));
    end loop;
  end if;

  if v_run."plan" is not null and jsonb_typeof(v_run."plan") = 'object' then
    for v_entity in select k.key from jsonb_object_keys(v_run."plan") k(key) loop
      v_expected := coalesce((v_run."plan" ->> v_entity)::integer, 0);
      v_applied := coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0)
        + coalesce((v_counts -> v_entity ->> 'unchanged')::integer, 0);
      if v_applied < v_expected then
        v_outcome := 'incomplete';
        v_counts := jsonb_set(coalesce(v_counts, '{}'::jsonb), array[v_entity, 'missing'], to_jsonb(v_expected - v_applied), true);
      end if;
    end loop;
  end if;
  if v_outcome = 'completed' and (
    jsonb_array_length(coalesce(v_run."errors", '[]'::jsonb)) > 0
    or exists (
      select 1 from jsonb_each(coalesce(v_counts, '{}'::jsonb)) v_entity_counts(key, value)
      where coalesce((v_entity_counts.value ->> 'conflicted')::integer, 0) > 0
    )
  ) then
    v_outcome := 'completed_with_issues';
  end if;

  update "better_supabase"."import_runs" r set "status" = 'completed', "outcome" = v_outcome, "finished_at" = now(), "counts" = v_counts
  where r."id" = v_run_id;

  if not v_run."dry_run" then
    for v_entity in select k.key from jsonb_object_keys(v_counts) k(key) loop
      v_total := v_total + coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0);
      perform "better_supabase".emit_event('import.entity_completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
      if coalesce((v_counts -> v_entity ->> 'inserted')::integer, 0) + coalesce((v_counts -> v_entity ->> 'updated')::integer, 0) > 0 then
        perform better_supabase.audit_event(
    event_type => 'import.entity_completed',
    category => 'integration',
    target_type => 'import',
    record_id => v_run_id::text,
    target_label => v_entity,
    summary => 'imported ' || v_entity,
    tenant => (v_run."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'entity', v_entity, 'counts', v_counts -> v_entity),
    idempotency_key => 'import:' || v_run_id::text || ':' || v_entity,
    actor_kind => 'integration',
    correlation_id => 'import:' || v_run_id::text
  );
      end if;
    end loop;
    perform "better_supabase".emit_event('import.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run_id, 'count', v_total), 'imports/' || v_run_id::text, (v_run."tenant_id")::text, null, 'better-supabase/imports');
  end if;
  perform "better_supabase"."search_refresh_run"(v_run_id);
  return v_counts;
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
      cross join (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
      where ref.target = v_entity
    ) wanted
    join "better_supabase"."import_records" found
      on found."tenant_id" = v_run."tenant_id"
      and found."source" = v_run."source"
      and found."entity" = wanted.entity
      and found."external_key" = wanted.key
    where wanted.key is not null
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
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;
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
    from (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
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
    from (values ('tax', 'tax_code', 'product'), ('product', 'product', 'product_category'), ('category', 'category', 'product_category'), ('billTo', 'party', 'party'), ('company', 'party', 'party_contact'), ('person', 'party', 'party_contact'), ('party', 'party', 'contact_method'), ('party', 'party', 'party_location'), ('party', 'party', 'party_bank_account'), ('asset', 'asset', 'due_check'), ('asset', 'asset', 'asset_identifier')) as ref(field, entity, target)
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
    raise exception 'the import is not running' using errcode = '55000', hint = 'IMPORT_RUN_NOT_RUNNING';
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

CREATE OR REPLACE FUNCTION better_supabase.search_enqueue (
  subject_type text,
  subject_id   text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_key text := search_enqueue.subject_type || E'\x1f' || search_enqueue.subject_id;
  v_name text := 'better_supabase.search_dirty_' || (hashtext(v_key) & 255)::text;
  v_dirty text;
  v_run text := nullif(current_setting('better_supabase.import_run', true), '');
begin
  if coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' and v_run is not null then
    insert into better_supabase.import_search_dirty (run_id, subject_type, subject_id)
    values (v_run::uuid, search_enqueue.subject_type, search_enqueue.subject_id)
    on conflict do nothing;
  elsif coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' then
    v_dirty := coalesce(current_setting(v_name, true), '');
    if position(E'\n' || v_key || E'\n' in E'\n' || v_dirty) = 0 then
      perform set_config(v_name, v_dirty || v_key || E'\n', true);
    end if;
  else
    perform "better_supabase"."search_refresh"(search_enqueue.subject_type, search_enqueue.subject_id);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_enqueue_many (
  subject_type text,
  subject_ids  text[]
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id text;
  v_run text := nullif(current_setting('better_supabase.import_run', true), '');
begin
  if coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' and v_run is not null then
    insert into better_supabase.import_search_dirty (run_id, subject_type, subject_id)
    select v_run::uuid, search_enqueue_many.subject_type, i.id
    from unnest(search_enqueue_many.subject_ids) i(id)
    on conflict do nothing;
    return;
  end if;
  foreach v_id in array coalesce(search_enqueue_many.subject_ids, '{}'::text[]) loop
    perform "better_supabase"."search_enqueue"(search_enqueue_many.subject_type, v_id);
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_index_stmt()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_key text := tg_argv[1];
  v_columns text[] := string_to_array(nullif(coalesce(tg_argv[2], ''), ''), ',');
  v_ids text[];
begin
  if tg_op = 'INSERT' then
    select array_agg(distinct to_jsonb(n) ->> v_key) into v_ids from new_rows n;
  elsif tg_op = 'DELETE' then
    select array_agg(distinct to_jsonb(o) ->> v_key) into v_ids from old_rows o;
  else
    with o as (select to_jsonb(r) as j from old_rows r),
      n as (select to_jsonb(r) as j from new_rows r)
    select array_agg(distinct x.id) into v_ids
    from (
      select n.j ->> v_key as id
      from n left join o on o.j ->> v_key = n.j ->> v_key
      where o.j is null or v_columns is null
        or exists (select 1 from unnest(v_columns) c where o.j -> c is distinct from n.j -> c)
      union
      select o.j ->> v_key
      from o left join n on n.j ->> v_key = o.j ->> v_key
      where n.j is null
    ) x;
  end if;
  perform "better_supabase"."search_enqueue_many"(tg_argv[0], array_remove(v_ids, null));
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh_run (
  run uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_count integer := 0;
  v_row record;
begin
  for v_row in
    delete from better_supabase.import_search_dirty d
    where d.run_id = search_refresh_run.run
    returning d.subject_type, d.subject_id
  loop
    if "better_supabase"."search_refresh"(v_row.subject_type, v_row.subject_id) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$function$;

CREATE TRIGGER bsb_search_customer_delete AFTER DELETE ON public.customers REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.search_index_stmt (
  'customer',
  'id'
);

CREATE TRIGGER bsb_search_customer_insert AFTER INSERT ON public.customers REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.search_index_stmt (
  'customer',
  'id'
);

CREATE TRIGGER bsb_search_customer_update AFTER UPDATE ON public.customers
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION better_supabase.search_index_stmt (
  'customer',
  'id',
  'id,organization_id,name,status,archived_at'
);

REVOKE ALL ON FUNCTION "better_supabase"."search_enqueue_many"(text, text[]) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."search_index_stmt"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."search_refresh_run"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_refresh_run"(uuid) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."import_search_dirty" TO "service_role";
