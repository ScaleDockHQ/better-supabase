SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.import_party_batch (
  run   uuid,
  items jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_party_batch"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.import_product_batch (
  run   uuid,
  items jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_product_batch"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.import_stock_allocation_batch (
  run   uuid,
  items jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_stock_allocation_batch"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.import_stock_count_batch (
  run   uuid,
  items jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_stock_count_batch"($1, $2) $function$;

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
          when 'product' then
            v_subject_type := 'product';
            v_raw := "better_supabase"."import_product_batch"(v_run_id, to_jsonb(v_calls));
        when 'stock_count' then
            v_subject_type := 'stock_count';
            v_raw := "better_supabase"."import_stock_count_batch"(v_run_id, to_jsonb(v_calls));
        when 'stock_allocation' then
            v_subject_type := 'stock_allocation';
            v_raw := "better_supabase"."import_stock_allocation_batch"(v_run_id, to_jsonb(v_calls));
        when 'party' then
            v_subject_type := 'party';
            v_raw := "better_supabase"."import_party_batch"(v_run_id, to_jsonb(v_calls));
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
        if v_entity = any (array['product', 'stock_count', 'stock_allocation', 'party', 'customer']::text[]) then
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
          when 'product' then
            v_subject_type := 'product';
            v_raw := "better_supabase"."import_product_batch"(v_run_id, to_jsonb(v_calls));
        when 'stock_count' then
            v_subject_type := 'stock_count';
            v_raw := "better_supabase"."import_stock_count_batch"(v_run_id, to_jsonb(v_calls));
        when 'stock_allocation' then
            v_subject_type := 'stock_allocation';
            v_raw := "better_supabase"."import_stock_allocation_batch"(v_run_id, to_jsonb(v_calls));
        when 'party' then
            v_subject_type := 'party';
            v_raw := "better_supabase"."import_party_batch"(v_run_id, to_jsonb(v_calls));
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

CREATE OR REPLACE FUNCTION better_supabase.import_party_batch (
  run   uuid,
  items jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  SET enable_nestloop TO 'off'
  AS $function$
declare
  v_done jsonb[] := array_fill(null::jsonb, array[jsonb_array_length(items)]);
  v_row record;
  v_call jsonb;
  v_message text;
  v_hint text;
begin
  for v_row in
    with src as (
      select o::int as n, gen_random_uuid() as id, e as item, (e ->> 'tenant')::uuid as v_tenant, e -> 'data' as v_data
      from jsonb_array_elements(items) with ordinality t(e, o)
      where jsonb_typeof(e -> 'data') = 'object'
    ), named as (
      select src.*, nullif(btrim(src.v_data ->> 'displayName'), '') as v_display,
        nullif(btrim(src.v_data ->> 'legalName'), '') as v_legal,
        nullif(btrim(concat_ws(' ', src.v_data ->> 'givenName', src.v_data ->> 'infix', src.v_data ->> 'lastName')), '') as v_person,
        nullif(btrim(src.v_data ->> 'number'), '') as v_number,
        nullif(lower(btrim(src.v_data ->> 'email')), '') as email
      from src
    ), kinds as (
      select named.*, coalesce(named.v_display, named.v_legal, named.v_person, named.v_number) as v_name,
        count(*) over (partition by named.v_tenant, named.email) as emails
      from named
    ), f as (
      select kinds.*, case coalesce(nullif(kinds.v_data ->> 'kind', ''), 'auto')
          when 'auto' then case when kinds.v_name ~* '\m(b\.?v\.?|n\.?v\.?|gmbh|ltd\.?|llc|inc\.?|bvba|vof|stichting|holding)\M' then 'company' else 'person' end
          else kinds.v_data ->> 'kind' end as kind
      from kinds
      where nullif(kinds.item ->> 'subjectId', '') is null and kinds.v_name is not null and length(kinds.v_name) <= 300
        and nullif(kinds.v_data ->> 'archivedAt', '') is null and nullif(kinds.v_data ->> 'billToId', '') is null
        and nullif(kinds.item -> 'resolved' ->> 'billTo', '') is null
    ), companies as (
      insert into "better_supabase"."companies" as x ("id", "tenant_id", "name", "legal_name", "vat_id", "registration_id", "phone", "billing_email", "bill_to_id", "lifecycle", "language", "roles", "customer_terms_id", "archived_at")
      select import_party.id, import_party.v_tenant, v_name, coalesce(v_legal, v_name), nullif(btrim(v_data ->> 'vatId'), ''), nullif(btrim(v_data ->> 'registrationId'), ''), better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), nullif(lower(btrim(v_data ->> 'billingEmail')), ''), nullif(coalesce(import_party.item -> 'resolved' ->> 'billTo', v_data ->> 'billToId'), '')::uuid, coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(btrim(v_data ->> 'language'), ''), case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, (select p."id" from "better_supabase"."payment_terms" p where p."tenant_id" = v_tenant and p."code" = nullif(btrim(v_data ->> 'termsCode'), '')), nullif(v_data ->> 'archivedAt', '')::timestamptz
      from f import_party
      where import_party.kind = 'company' and length(coalesce(import_party.v_legal, import_party.v_name)) <= 300 and jsonb_typeof(import_party.v_data -> 'roles') = 'array'
      returning x."id" as id, x."updated_at" as updated_at
    ), people as (
      insert into "better_supabase"."people" as x ("id", "tenant_id", "name", "given_name", "last_name", "initials", "infix", "email", "phone", "lifecycle", "language", "roles", "archived_at")
      select import_party.id, import_party.v_tenant, v_name, nullif(btrim(v_data ->> 'givenName'), ''), nullif(btrim(v_data ->> 'lastName'), ''), nullif(btrim(v_data ->> 'initials'), ''), nullif(btrim(v_data ->> 'infix'), ''), nullif(lower(btrim(v_data ->> 'email')), ''), better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(btrim(v_data ->> 'language'), ''), case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, nullif(v_data ->> 'archivedAt', '')::timestamptz
      from f import_party
      where import_party.kind = 'person' and jsonb_typeof(import_party.v_data -> 'roles') = 'array'
        and (import_party.email is null or (import_party.emails = 1 and import_party.email ~ '^[^@[:space:]]+@[^@[:space:]]+$'
          and (select y."id" from "better_supabase"."people" y where y."tenant_id" = import_party.v_tenant and y."email" = import_party.email and y."archived_at" is null limit 1) is null))
      returning x."id" as id, x."updated_at" as updated_at
    )
    select import_party.n, jsonb_build_object('subjectId', import_party.id, 'updatedAt', w.updated_at, 'warnings',
        case when import_party.v_display is null then jsonb_build_array(jsonb_build_object('code', 'IMPORT_NAME_FALLBACK', 'message', 'the party name came from a fallback')) else '[]'::jsonb end) as answer
    from f import_party join (select * from companies union all select * from people) w on w.id = import_party.id
  loop
    v_done[v_row.n] := v_row.answer;
  end loop;
  for v_i in 1 .. jsonb_array_length(items) loop
    if v_done[v_i] is null then
      v_call := items -> (v_i - 1);
      begin
        v_done[v_i] := "better_supabase"."import_party"(run, v_call, nullif(v_call ->> 'subjectId', ''));
      exception when others then
        get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
        v_done[v_i] := jsonb_build_object('error', jsonb_build_object('code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      end;
    end if;
  end loop;
  return to_jsonb(v_done);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_product_batch (
  run   uuid,
  items jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  SET enable_nestloop TO 'off'
  AS $function$
declare
  v_done jsonb[] := array_fill(null::jsonb, array[jsonb_array_length(items)]);
  v_row record;
  v_call jsonb;
  v_message text;
  v_hint text;
begin
  for v_row in
    with i as (
      select o::int as n, gen_random_uuid() as id, e, (e ->> 'tenant')::uuid as tenant, e -> 'data' as d,
        coalesce(e -> 'data' ->> 'name', e -> 'data' ->> 'title', '') as raw,
        nullif(btrim(e -> 'data' ->> 'sku'), '') as sku
      from jsonb_array_elements(items) with ordinality t(e, o)
      where jsonb_typeof(e -> 'data') = 'object'
    ), named as (
      select i.*, btrim(regexp_replace(regexp_replace(i.raw, '[[:cntrl:]]', '', 'g'), U&'[\+00E000-\+00F8FF]', '', 'g')) as name
      from i
    ), slugged as (
      select named.*, trim(both '-' from lower(regexp_replace(coalesce(nullif(named.d ->> 'slug', ''), named.name), '[^a-zA-Z0-9]+', '-', 'g'))) as slug
      from named
    ), counted as (
      select s.*, count(*) over (partition by s.tenant, s.slug) as slugs,
        count(*) over (partition by s.tenant, coalesce(s.sku, s.slug)) as skus,
        count(*) over (partition by s.tenant, s.sku) as own_skus
      from slugged s
    ), f as (
      select c.n, c.id, c.tenant, c.d, c.name, c.slug, c.sku, c.e,
        coalesce(case when pg_input_is_valid(coalesce(nullif(c.d ->> 'price', ''), ''), 'bigint') then (nullif(c.d ->> 'price', ''))::bigint end, case when pg_input_is_valid(coalesce(nullif(c.d ->> 'listPrice', ''), ''), 'bigint') then (nullif(c.d ->> 'listPrice', ''))::bigint end) as price
      from counted c
      where nullif(c.e ->> 'subjectId', '') is null
        and coalesce(c.e -> 'options' ->> 'priceFallback', 'false') = 'false'
        and pg_input_is_valid(coalesce(nullif(c.d ->> 'price', ''), '0'), 'bigint')
        and pg_input_is_valid(coalesce(nullif(c.d ->> 'listPrice', ''), '0'), 'bigint')
        and length(regexp_replace(c.raw, '[[:cntrl:][:space:]]', '', 'g')) * 2 >= length(regexp_replace(c.raw, '[[:space:]]', '', 'g'))
        and length(c.name) > 0
        and c.slugs = 1 and c.skus = 1 and (c.sku is null or c.own_skus = 1)
        and (select x."id" from "better_supabase"."products" x where x."tenant_id" = c.tenant and x."slug" = c.slug limit 1) is null
        and (select y."id" from "better_supabase"."product_variants" y where y."tenant_id" = c.tenant and y."sku" = coalesce(c.sku, c.slug) limit 1) is null
    ), written as (
      insert into "better_supabase"."products" as x ("id", "tenant_id", "title", "slug", "manufacturer", "model", "tax_code")
      select f.id, f.tenant, f.name, f.slug, nullif(btrim(f.d ->> 'manufacturer'), ''), nullif(btrim(f.d ->> 'model'), ''), nullif(coalesce(f.e -> 'resolved' ->> 'tax', f.d ->> 'taxCode'), '')
      from f
      returning x."id" as id, x."updated_at" as updated_at
    ), variant as (
      insert into "better_supabase"."product_variants" ("tenant_id", "product_id", "sku", "barcode")
      select f.tenant, f.id, coalesce(f.sku, f.slug), nullif(btrim(f.d ->> 'ean'), '')
      from f
    )
    select f.n, jsonb_build_object('subjectId', f.id, 'updatedAt', w.updated_at) as answer
    from f join written w on w.id = f.id
  loop
    v_done[v_row.n] := v_row.answer;
  end loop;
  for v_i in 1 .. jsonb_array_length(items) loop
    if v_done[v_i] is null then
      v_call := items -> (v_i - 1);
      begin
        v_done[v_i] := "better_supabase"."import_product"(run, v_call, nullif(v_call ->> 'subjectId', ''));
      exception when others then
        get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
        v_done[v_i] := jsonb_build_object('error', jsonb_build_object('code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      end;
    end if;
  end loop;
  return to_jsonb(v_done);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_stock_allocation_batch (
  run   uuid,
  items jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  SET enable_nestloop TO 'off'
  AS $function$
declare
  v_done jsonb[] := array_fill(null::jsonb, array[jsonb_array_length(items)]);
  v_row record;
  v_call jsonb;
  v_message text;
  v_hint text;
begin
  for v_row in
    with i as (
      select o::int as n, gen_random_uuid() as id, (e ->> 'tenant')::uuid as tenant, e -> 'data' as d,
        case when pg_input_is_valid(coalesce(e -> 'data' ->> 'variantId', ''), 'uuid') then (e -> 'data' ->> 'variantId')::uuid end as variant,
        case when pg_input_is_valid(coalesce(e -> 'data' ->> 'locationId', ''), 'uuid') then (e -> 'data' ->> 'locationId')::uuid end as location,
        case when pg_input_is_valid(coalesce(e -> 'data' ->> 'quantity', ''), 'numeric') then (e -> 'data' ->> 'quantity')::numeric end as quantity,
        case when pg_input_is_valid(coalesce(coalesce(e -> 'data' ->> 'allocated', '0'), ''), 'numeric') then (coalesce(e -> 'data' ->> 'allocated', '0'))::numeric end as allocated,
        case when pg_input_is_valid(coalesce(coalesce(e -> 'data' ->> 'fulfilled', '0'), ''), 'numeric') then (coalesce(e -> 'data' ->> 'fulfilled', '0'))::numeric end as fulfilled,
        coalesce(nullif(e -> 'data' ->> 'status', ''), 'open') as status
      from jsonb_array_elements(items) with ordinality t(e, o)
      where nullif(e ->> 'subjectId', '') is null
    ), f as (
      select i.n, i.id, i.tenant, i.variant, i.location, i.quantity, i.status,
        i.d ->> 'documentType' as document_type, i.d ->> 'documentId' as document_id, nullif(i.d ->> 'lineId', '') as line,
        case when i.status <> 'open' then 0 else i.allocated end as allocated,
        case when i.status = 'fulfilled' then i.quantity else i.fulfilled end as fulfilled
      from i
      where (select y."id" from "better_supabase"."product_variants" y where y."id" = i.variant and y."tenant_id" = i.tenant) is not null
        and (select x."id" from "better_supabase"."inventory_locations" x where x."id" = i.location and x."tenant_id" = i.tenant) is not null
        and i.status in ('open', 'fulfilled', 'released')
        and i.quantity > 0 and i.allocated >= 0 and i.fulfilled >= 0 and i.allocated + i.fulfilled <= i.quantity
        and coalesce(i.d ->> 'documentType', '') ~ '^[a-z][a-z0-9_]{0,62}$'
        and length(coalesce(i.d ->> 'documentId', '')) between 1 and 200
    ), levels as (
      insert into "better_supabase"."stock_levels" as x ("tenant_id", "variant_id", "location_id", "reserved")
      select f.tenant, f.variant, f.location, sum(f.allocated) from f group by 1, 2, 3
      on conflict ("variant_id", "location_id") do update
        set "reserved" = x."reserved" + excluded."reserved", "updated_at" = now()
    ), written as (
      insert into "better_supabase"."stock_allocations" as x ("id", "tenant_id", "variant_id", "location_id", "document_type", "document_id", "line_id",
        "quantity", "allocated", "fulfilled", "status")
      select f.id, f.tenant, f.variant, f.location, f.document_type, f.document_id, f.line, f.quantity, f.allocated, f.fulfilled, f.status from f
      returning x."id" as id, x."updated_at" as updated_at
    )
    select f.n, jsonb_build_object('subjectId', f.id::text, 'updatedAt', w.updated_at) as answer
    from f join written w on w.id = f.id
  loop
    v_done[v_row.n] := v_row.answer;
  end loop;
  for v_i in 1 .. jsonb_array_length(items) loop
    if v_done[v_i] is null then
      v_call := items -> (v_i - 1);
      begin
        v_done[v_i] := "better_supabase"."import_stock_allocation"(run, v_call, nullif(v_call ->> 'subjectId', ''));
      exception when others then
        get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
        v_done[v_i] := jsonb_build_object('error', jsonb_build_object('code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      end;
    end if;
  end loop;
  return to_jsonb(v_done);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_stock_count_batch (
  run   uuid,
  items jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  SET enable_nestloop TO 'off'
  AS $function$
declare
  v_done jsonb[] := array_fill(null::jsonb, array[jsonb_array_length(items)]);
  v_row record;
  v_call jsonb;
  v_message text;
  v_hint text;
begin
  for v_row in
    with i as (
      select o::int as n, gen_random_uuid() as id, (e ->> 'tenant')::uuid as tenant, e -> 'data' as d,
        case when pg_input_is_valid(coalesce(e -> 'data' ->> 'locationId', ''), 'uuid') then (e -> 'data' ->> 'locationId')::uuid end as location
      from jsonb_array_elements(items) with ordinality t(e, o)
      where nullif(e ->> 'subjectId', '') is null and jsonb_typeof(e -> 'data' -> 'lines') = 'array'
    ), f as (
      select i.n, i.id, i.tenant, i.location, i.d, nullif(btrim(i.d ->> 'note'), '') as note
      from i
      where (select x."id" from "better_supabase"."inventory_locations" x where x."id" = i.location and x."tenant_id" = i.tenant) is not null
        and (select count(*) = count(distinct case when pg_input_is_valid(coalesce(e.entry ->> 'variantId', ''), 'uuid') then (e.entry ->> 'variantId')::uuid end)
            and bool_and(jsonb_typeof(e.entry) = 'object'
              and not e.entry ?| array['binId', 'bin', 'lotId', 'lot', 'serial', 'sku']
              and pg_input_is_valid(coalesce(e.entry ->> 'counted', ''), 'numeric')
              and pg_input_is_valid(coalesce(e.entry ->> 'expected', '0'), 'numeric')
              and coalesce(case when pg_input_is_valid(coalesce(e.entry ->> 'counted', ''), 'numeric') then (e.entry ->> 'counted')::numeric end >= 0, false)
              and (select y."id" from "better_supabase"."product_variants" y
                where y."id" = case when pg_input_is_valid(coalesce(e.entry ->> 'variantId', ''), 'uuid') then (e.entry ->> 'variantId')::uuid end and y."tenant_id" = i.tenant) is not null)
          from jsonb_array_elements(i.d -> 'lines') e(entry))
    ), written as (
      insert into "better_supabase"."stock_counts" as x ("id", "tenant_id", "location_id", "note")
      select f.id, f.tenant, f.location, f.note from f
      returning x."id" as id, x."updated_at" as updated_at
    ), counted as (
      insert into "better_supabase"."stock_count_lines" ("tenant_id", "count_id", "variant_id", "expected", "counted")
      select f.tenant, f.id, (e.entry ->> 'variantId')::uuid,
        coalesce((e.entry ->> 'expected')::numeric,
          coalesce((select lv."on_hand" from "better_supabase"."stock_levels" lv where lv."variant_id" = (e.entry ->> 'variantId')::uuid and lv."location_id" = f.location), 0)
            - coalesce((select sum(y."on_hand") from "better_supabase"."stock_buckets" y where y."variant_id" = (e.entry ->> 'variantId')::uuid and y."location_id" = f.location), 0)),
        (e.entry ->> 'counted')::numeric
      from f cross join lateral jsonb_array_elements(f.d -> 'lines') e(entry)
    )
    select f.n, jsonb_build_object('subjectId', f.id::text, 'updatedAt', w.updated_at) as answer
    from f join written w on w.id = f.id
  loop
    v_done[v_row.n] := v_row.answer;
  end loop;
  for v_i in 1 .. jsonb_array_length(items) loop
    if v_done[v_i] is null then
      v_call := items -> (v_i - 1);
      begin
        v_done[v_i] := "better_supabase"."import_stock_count"(run, v_call, nullif(v_call ->> 'subjectId', ''));
      exception when others then
        get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
        v_done[v_i] := jsonb_build_object('error', jsonb_build_object('code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
      end;
    end if;
  end loop;
  return to_jsonb(v_done);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."import_party_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_party_batch"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_product_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_product_batch"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_stock_allocation_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_stock_allocation_batch"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_stock_count_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_stock_count_batch"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_party_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_party_batch"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_product_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_product_batch"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_stock_allocation_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_stock_allocation_batch"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_stock_count_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_stock_count_batch"(uuid, jsonb) TO "service_role";
