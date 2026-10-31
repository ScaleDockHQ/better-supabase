SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."invoice_lines"
  ADD COLUMN "discount_amount" bigint NOT NULL DEFAULT 0;

ALTER TABLE "better_supabase"."invoice_lines"
  ADD COLUMN "cost_source" text;

ALTER TABLE "better_supabase"."invoice_lines"
  ADD COLUMN "location_id" uuid;

ALTER TABLE "better_supabase"."invoice_lines"
  ADD COLUMN "bin_id" uuid;

ALTER TABLE "better_supabase"."invoice_lines"
  ADD COLUMN "billing_party" text NOT NULL DEFAULT 'customer'::text;

ALTER TABLE "better_supabase"."invoice_lines"
  ADD COLUMN "billing_party_id" text;

ALTER TABLE "better_supabase"."invoice_lines"
  ADD COLUMN "billing_account_id" uuid;

ALTER TABLE "better_supabase"."invoices"
  ADD COLUMN "buyer" jsonb;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "tax_code_id" uuid;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "unit_cost" bigint;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "cost_source" text;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "bin_id" uuid;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "billing_party" text NOT NULL DEFAULT 'customer'::text;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "billing_party_id" text;

ALTER TABLE "better_supabase"."order_lines"
  ADD COLUMN "billing_account_id" uuid;

ALTER TABLE "better_supabase"."orders"
  ADD COLUMN "buyer" jsonb;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "tax_code_id" uuid;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "unit_cost" bigint;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "discount_amount" bigint NOT NULL DEFAULT 0;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "cost_source" text;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "location_id" uuid;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "bin_id" uuid;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "billing_party" text NOT NULL DEFAULT 'customer'::text;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "billing_party_id" text;

ALTER TABLE "better_supabase"."quote_lines"
  ADD COLUMN "billing_account_id" uuid;

ALTER TABLE "better_supabase"."quotes"
  ADD COLUMN "buyer" jsonb;

CREATE OR REPLACE FUNCTION api.document_totals_by_billing_party (
  document uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_totals_by_billing_party"($1) $function$;

CREATE OR REPLACE FUNCTION api.import_credit_note (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_credit_note"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_invoice (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_invoice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_order (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_order"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_quote (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_quote"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.invoice_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."invoice_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.order_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."order_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.quote_totals_by_billing_party (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."quote_totals_by_billing_party"($1) $function$;

CREATE OR REPLACE FUNCTION api.quote_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."quote_updated_at"($1) $function$;

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
  select * into v_original from "better_supabase"."invoices" x where x."id" = credit_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false));
  if v_original."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
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
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text) order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_totals_by_billing_party (
  document uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(g.row order by g.party, g.party_id, g.account_id), '[]'::jsonb)
  from (
    select l."billing_party" as party, l."billing_party_id" as party_id, l."billing_account_id"::text as account_id,
      jsonb_build_object(
        'billingParty', l."billing_party", 'billingPartyId', l."billing_party_id", 'billingAccountId', l."billing_account_id"::text,
        'lines', count(*), 'net', sum((round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "better_supabase"."invoice_lines" l
    where l."parent_id" = document and true
    group by 1, 2, 3
  ) g
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
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'order', 'quote', 'invoice', 'credit_note', 'tax_code', 'tax_rate', 'customer']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
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
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
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
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
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
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'customer' then
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
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_credit_note (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select "better_supabase"."import_invoice_document"(import_credit_note.item, import_credit_note.subject_id, true)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_invoice (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select "better_supabase"."import_invoice_document"(import_invoice.item, import_invoice.subject_id, false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_invoice_document (
  item       jsonb,
  subject_id text,
  v_credit   boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_invoice_document.item ->> 'tenant')::uuid;
  v_data jsonb := import_invoice_document.item -> 'data';
  v_status text := case when v_credit then 'issued' else coalesce(v_data ->> 'status', 'issued') end;
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_issued_on date;
  v_due_on date;
  v_original uuid;
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."invoices";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
  v_pay jsonb;
  v_index integer := 0;
begin
  if import_invoice_document.subject_id is not null then
    select * into v_row from "better_supabase"."invoices" x where x."id" = import_invoice_document.subject_id::uuid and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'the invoice no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source document changed after it was imported; an imported document is kept as imported, so void or credit it and import the correction as a new document')));
  end if;
  if v_status not in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible') then
    raise exception 'status is draft, issued, partially_paid, paid, void or uncollectible' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a document needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_status <> 'draft' and v_number is null then
    raise exception 'an issued document needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_issued_on := nullif(v_data ->> 'issuedOn', '')::date;
    v_due_on := nullif(v_data ->> 'dueOn', '')::date;
  exception when others then
    raise exception 'issuedOn and dueOn are dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_status <> 'draft' and v_issued_on is null then
    raise exception 'an issued document needs its issue date' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  if v_credit then
    v_original := coalesce(
      nullif(v_data ->> 'originalId', '')::uuid,
      (select x."id" from "better_supabase"."invoices" x where x."tenant_id" = v_tenant and x."identifier" = v_data ->> 'original' limit 1)
    );
    if v_original is null then
      raise exception 'a credit note names the invoice it credits (originalId or original)' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    v_made := "better_supabase"."credit_invoice"(v_original, v_data -> 'lines', nullif(v_data ->> 'note', ''), v_number, v_issued_on);
    v_id := (v_made ->> 'id')::uuid;
  else
    v_made := "better_supabase"."create_invoice"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'title', coalesce(nullif(v_data ->> 'title', ''), 'Invoice ' || coalesce(v_number, 'draft')),
      'currency', v_data -> 'currency',
      'termsDays', v_data -> 'termsDays',
      'note', v_data -> 'note',
      'company', v_data -> 'company',
      'contact', v_data -> 'contact',
      'origin', v_data -> 'origin',
      'direction', v_data -> 'direction',
      'pricesIncludeTax', v_data -> 'pricesIncludeTax',
      'discountBps', v_data -> 'discountBps',
      'discountAmount', v_data -> 'discountAmount')), v_data -> 'lines');
    v_id := (v_made ->> 'id')::uuid;
  end if;
  update "better_supabase"."invoices" x set legal_entity_id = case when v_credit then x.legal_entity_id else nullif(v_data ->> 'legalEntityId', '')::uuid end,
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' else x."buyer" end,
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, x."created_at")
  where x."id" = v_id;
  if v_status <> 'draft' and not v_credit then
    perform "better_supabase"."issue_invoice"(v_id, v_issued_on, v_due_on, null, v_number);
  end if;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(y."tax_code", '') || ':' || y."tax_rate_bps"::text as key, sum(y."net") as net, sum(y."tax") as tax
        from "better_supabase"."invoice_tax_lines" y where y."invoice_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."invoice_tax_lines" y where y."invoice_id" = v_id;
    insert into "better_supabase"."invoice_tax_lines" ("tenant_id", "invoice_id", "tax_rate_bps", "tax_code", "tax_code_id", "net", "tax", "gross", "discount", "show_tax")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), nullif(g.value ->> 'taxCodeId', '')::uuid,
      (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint),
      coalesce((g.value ->> 'discount')::bigint, 0), coalesce((g.value ->> 'showTax')::boolean, true)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."invoices" x set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, x."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, x."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, x."total")
    where x."id" = v_id;
  end if;
  if jsonb_typeof(v_data -> 'payments') = 'array' and jsonb_array_length(v_data -> 'payments') > 0 then
    if v_credit or v_status = 'draft' then
      raise exception 'only an issued invoice takes payments' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    for v_pay in select p.value from jsonb_array_elements(v_data -> 'payments') p loop
      v_index := v_index + 1;
      perform "better_supabase"."record_invoice_payment"(
        v_id, (v_pay ->> 'amount')::bigint, upper(coalesce(v_pay ->> 'currency', v_row."currency")),
        (v_pay ->> 'paidAt')::timestamptz, coalesce(nullif(v_pay ->> 'method', ''), 'import'),
        coalesce(nullif(v_pay ->> 'reference', ''), import_invoice_document.item ->> 'key' || ':payment:' || v_index::text),
        nullif(v_pay ->> 'note', ''), null, null);
    end loop;
    update "better_supabase"."invoices" x set "paid_at" = (select max((p.value ->> 'paidAt')::timestamptz) from jsonb_array_elements(v_data -> 'payments') p)
    where x."id" = v_id and x."paid_at" is not null and jsonb_typeof(v_data -> 'payments') = 'array';
  end if;
  if v_status = 'void' then
    perform "better_supabase"."void_invoice"(v_id, coalesce(nullif(v_data ->> 'voidReason', ''), 'imported as void'));
  elsif v_status = 'uncollectible' then
    perform "better_supabase"."write_off_invoice"(v_id, nullif(v_data ->> 'writeOffReason', ''));
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
  if v_status in ('partially_paid', 'paid') and v_row."status"::text <> v_status then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_STATUS_MISMATCH', 'message', 'the payments give the status ' || v_row."status"::text || ', not ' || v_status, 'status', v_row."status"::text));
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_order (
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
  v_tenant uuid := (import_order.item ->> 'tenant')::uuid;
  v_data jsonb := import_order.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_seq bigint;
  v_id uuid;
  v_inclusive boolean := coalesce((v_data ->> 'taxInclusive')::boolean, false);
  v_subtotal bigint;
  v_discount bigint;
  v_tax bigint;
  v_shipping bigint;
  v_total bigint;
  v_paid bigint := 0;
  v_paid_at timestamptz;
  v_given jsonb := v_data -> 'totals';
  v_warnings jsonb := '[]'::jsonb;
  v_updated timestamptz;
  v_pay jsonb;
  v_index integer := 0;
begin
  if import_order.subject_id is not null then
    select x."updated_at" into v_updated from "better_supabase"."orders" x where x."id" = import_order.subject_id::uuid and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'the order no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', import_order.subject_id, 'updatedAt', v_updated, 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source order changed after it was imported; an imported order is kept as imported')));
  end if;
  if v_number is null then
    raise exception 'an order needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'currency', '') !~ '^[A-Za-z]{3}$' then
    raise exception 'currency is an ISO 4217 code' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'an order needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_data -> 'lines') l
    where coalesce(l.value ->> 'title', '') = '' or coalesce(l.value ->> 'quantity', '') !~ '^[1-9][0-9]{0,8}$' or coalesce(l.value ->> 'unitAmount', '') !~ '^[0-9]{1,18}$'
  ) then
    raise exception 'a line needs a title, a whole quantity above zero and a unitAmount' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_data -> 'lines') l
    where l.value ->> 'billingParty' is not null and l.value ->> 'billingParty' not in ('customer', 'internal', 'own_warranty', 'supplier_warranty', 'cost_account')
      or l.value ->> 'costSource' is not null and l.value ->> 'costSource' not in ('catalog', 'average', 'manual', 'imported')
  ) then
    raise exception 'a line''s billingParty or costSource is not a known value' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  select coalesce(sum((l.value ->> 'unitAmount')::bigint * (l.value ->> 'quantity')::bigint), 0),
    coalesce(sum(coalesce((l.value ->> 'discount')::bigint, 0)), 0),
    coalesce(sum(coalesce((l.value ->> 'tax')::bigint, 0)), 0)
  into v_subtotal, v_discount, v_tax
  from jsonb_array_elements(v_data -> 'lines') l;
  v_shipping := coalesce((v_given ->> 'shippingTotal')::bigint, 0);
  v_total := v_subtotal - v_discount + v_shipping + case when v_inclusive then 0 else v_tax end;
  if jsonb_typeof(v_given) = 'object' then
    if coalesce((v_given ->> 'subtotal')::bigint, v_subtotal) <> v_subtotal
      or coalesce((v_given ->> 'discountTotal')::bigint, v_discount) <> v_discount
      or coalesce((v_given ->> 'taxTotal')::bigint, v_tax) <> v_tax
      or coalesce((v_given ->> 'total')::bigint, v_total) <> v_total then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_subtotal::text, 'discountTotal', v_discount::text, 'taxTotal', v_tax::text, 'total', v_total::text),
        'given', v_given));
    end if;
    v_subtotal := coalesce((v_given ->> 'subtotal')::bigint, v_subtotal);
    v_discount := coalesce((v_given ->> 'discountTotal')::bigint, v_discount);
    v_tax := coalesce((v_given ->> 'taxTotal')::bigint, v_tax);
    v_total := coalesce((v_given ->> 'total')::bigint, v_total);
  end if;
  if jsonb_typeof(v_data -> 'payments') = 'array' then
    select coalesce(sum((p.value ->> 'amount')::bigint), 0), max((p.value ->> 'paidAt')::timestamptz)
    into v_paid, v_paid_at from jsonb_array_elements(v_data -> 'payments') p;
  end if;

  if nullif(btrim(v_data ->> 'number'), '') is not null then
    perform set_config('better_supabase.fixed_number', 'order' || chr(31) || btrim(v_data ->> 'number'), true);
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_tenant::text || ':commerce:order', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = v_tenant;
  v_number := v_seq::text;
  end if;
  insert into "better_supabase"."orders" ("tenant_id", "number", "sequence", "customer_id", "email", "status", "currency", "subtotal", "discount_total", "shipping_total", "tax_total", "total", "paid_total", "tax_inclusive", "shipping_address", "billing_address", "tax", "invoice_number", "invoice_sequence", "invoiced_at", "placed_at", "paid_at", "fulfilled_at", "completed_at", "cancelled_at", "cancel_reason", "buyer", legal_entity_id)
  values (v_tenant, v_number, v_seq, nullif(v_data ->> 'customerId', '')::uuid, v_data ->> 'email', coalesce(v_data ->> 'status', 'confirmed'), upper(v_data ->> 'currency'), v_subtotal, v_discount, v_shipping, v_tax, v_total, v_paid, v_inclusive, v_data -> 'shippingAddress', v_data -> 'billingAddress', v_data -> 'taxLines', nullif(v_data ->> 'invoiceNumber', ''), substring(nullif(v_data ->> 'invoiceNumber', '') from '([0-9]+)$')::bigint, nullif(v_data ->> 'invoicedAt', '')::timestamptz, coalesce(nullif(v_data ->> 'placedAt', '')::timestamptz, now()), coalesce(nullif(v_data ->> 'paidAt', '')::timestamptz, v_paid_at), nullif(v_data ->> 'fulfilledAt', '')::timestamptz, nullif(v_data ->> 'completedAt', '')::timestamptz, nullif(v_data ->> 'cancelledAt', '')::timestamptz, nullif(v_data ->> 'cancelReason', ''), case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end, nullif(v_data ->> 'legalEntityId', '')::uuid)
  returning "id", "updated_at" into v_id, v_updated;

  insert into "better_supabase"."order_lines" ("tenant_id", "order_id", "position", "variant_id", "product_id", "sku", "title", "quantity", "unit_amount", "subtotal", "discount", "tax", "total", "requires_shipping", "location_id", "tax_code_id", "unit_cost", "cost_source", "bin_id", "billing_party", "billing_party_id", "billing_account_id")
  select v_tenant, v_id, e.n::integer, nullif(e.l ->> 'variantId', '')::uuid, nullif(e.l ->> 'productId', '')::uuid, coalesce(e.l ->> 'sku', ''), e.l ->> 'title', (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, coalesce((e.l ->> 'subtotal')::bigint, (e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::bigint), coalesce((e.l ->> 'discount')::bigint, 0), coalesce((e.l ->> 'tax')::bigint, 0), coalesce((e.l ->> 'total')::bigint, (e.l ->> 'unitAmount')::bigint * (e.l ->> 'quantity')::bigint - coalesce((e.l ->> 'discount')::bigint, 0)), coalesce((e.l ->> 'requiresShipping')::boolean, false), nullif(e.l ->> 'locationId', '')::uuid, nullif(e.l ->> 'taxCodeId', '')::uuid, (e.l ->> 'unitCost')::bigint, nullif(e.l ->> 'costSource', ''), nullif(e.l ->> 'binId', '')::uuid, coalesce(nullif(e.l ->> 'billingParty', ''), 'customer'), nullif(e.l ->> 'billingPartyId', ''), nullif(e.l ->> 'billingAccountId', '')::uuid
  from jsonb_array_elements(v_data -> 'lines') with ordinality as e(l, n);

  if jsonb_typeof(v_data -> 'payments') = 'array' then
    for v_pay in select e.value from jsonb_array_elements(v_data -> 'payments') e loop
      v_index := v_index + 1;
      insert into "better_supabase"."order_payments" ("tenant_id", "order_id", "provider", "reference", "status", "currency", "amount", "captured", "refunded", "created_at", "updated_at")
      values (v_tenant, v_id, coalesce(nullif(v_pay ->> 'provider', ''), 'import'),
        coalesce(nullif(v_pay ->> 'reference', ''), import_order.item ->> 'key' || ':payment:' || v_index::text),
        'succeeded', upper(v_data ->> 'currency'), (v_pay ->> 'amount')::bigint, (v_pay ->> 'amount')::bigint, 0,
        coalesce(nullif(v_pay ->> 'paidAt', '')::timestamptz, now()), coalesce(nullif(v_pay ->> 'paidAt', '')::timestamptz, now()));
    end loop;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated, 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_quote (
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
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "better_supabase"."quotes" y where y."id" = import_quote.subject_id::uuid and y."tenant_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Quote ' || v_number),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "better_supabase"."quotes" y set
    "status" = coalesce(v_data ->> 'status', 'draft'),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    legal_entity_id = nullif(v_data ->> 'legalEntityId', '')::uuid,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_from_quote (
  quote               uuid,
  deposit_bps         integer,
  deposit_amount      bigint  DEFAULT NULL::bigint,
  deposit_description text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_quote "better_supabase"."quotes";
  v_row "better_supabase"."invoices";
  v_lines jsonb;
  v_header jsonb := '{}'::jsonb;
begin
  select * into v_quote from "better_supabase"."quotes" x where x."id" = invoice_from_quote.quote;
  if v_quote."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_quote."tenant_id", 'invoices.write'), false)) then
    raise exception 'no such quote you can invoice' using errcode = 'P0002', hint = 'INVOICE_ORIGIN_NOT_FOUND';
  end if;
  if v_quote."status" <> 'accepted' then
    raise exception 'only an accepted quote is invoiced' using errcode = '55000', hint = 'INVOICE_QUOTE_NOT_ACCEPTED';
  end if;
  if invoice_from_quote.deposit_bps is not null and (invoice_from_quote.deposit_bps <= 0 or invoice_from_quote.deposit_bps >= 10000) then
    raise exception 'a deposit is between 0 and 100 percent' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_bps is not null and invoice_from_quote.deposit_amount is not null then
    raise exception 'a deposit is a share (deposit_bps) or an amount (deposit_amount), not both' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_amount is not null and (invoice_from_quote.deposit_amount <= 0 or invoice_from_quote.deposit_amount > v_quote."total") then
    raise exception 'a deposit amount is positive and at most the quote''s total' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_bps is null and invoice_from_quote.deposit_amount is null then
    select * into v_row from "better_supabase"."invoices" x
    where x."origin_type" = 'quote' and x."origin_id"::text = v_quote."id"::text
      and x."deposit_bps" is null and x."deposit_amount" is null and x."status" <> 'void' and x."kind" = 'invoice' and not (x."total" > 0 and x."credited_total" >= x."total")
    limit 1;
    if v_row."id" is not null then
      return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text) order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('description', x."description", 'quantity', x."quantity" * coalesce(x."periods", 1), 'unitAmount', x."unit_amount"::text,
        'discountBps', x."discount_bps", 'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code",
        'discountAmount', x."discount_amount", 'taxCodeId', x."tax_code_id", 'unitCost', x."unit_cost", 'costSource', x."cost_source", 'locationId', x."location_id", 'binId', x."bin_id", 'billingParty', x."billing_party", 'billingPartyId', x."billing_party_id", 'billingAccountId', x."billing_account_id",
        'product', case when x."product_type" is null then null else jsonb_build_object('type', x."product_type", 'id', x."product_id") end
      ) order by x."position"), '[]'::jsonb) into v_lines
    from "better_supabase"."quote_lines" x where x."parent_id" = v_quote."id" and (not x."optional" or x."selected");
    if not exists (select 1 from "better_supabase"."invoices" d where d."origin_type" = 'quote' and d."origin_id"::text = v_quote."id"::text and (d."deposit_bps" is not null or d."deposit_amount" is not null) and d."status" not in ('draft', 'void') and not (d."total" > 0 and d."credited_total" >= d."total")) then
      v_header := jsonb_build_object('discountBps', v_quote."discount_bps", 'discountAmount', v_quote."discount_amount"::text);
    else
      select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', 'Discount', 'quantity', 1, 'unitAmount', (-x."discount")::text,
          'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code") order by x."tax_rate_bps"), '[]'::jsonb)
        into v_lines
      from "better_supabase"."quote_tax_lines" x where x."parent_id" = v_quote."id" and x."discount" <> 0;
    end if;
    select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', replace(coalesce(nullif(trim(invoice_from_quote.deposit_description), ''), 'Deposit {identifier}'), '{identifier}', d."identifier"), 'quantity', 1, 'unitAmount', (-(case when d."prices_include_tax" = v_quote."prices_include_tax" then y.amount when d."prices_include_tax" then round(y.amount * 10000.0 / (10000 + y.rate))::bigint else round(y.amount * (10000 + y.rate) / 10000.0)::bigint end))::text,
        'taxRateBps', y.rate) order by d."identifier", y.rate), '[]'::jsonb)
      into v_lines
    from "better_supabase"."invoices" d
    cross join lateral (
      select dl."tax_rate_bps" as rate, sum(round(dl."quantity" * dl."unit_amount") - (round(round(dl."quantity" * dl."unit_amount") * dl."discount_bps" / 10000.0) + least(coalesce(dl."discount_amount", 0), greatest(round(dl."quantity" * dl."unit_amount") - round(round(dl."quantity" * dl."unit_amount") * dl."discount_bps" / 10000.0), 0))))::bigint as amount
      from "better_supabase"."invoice_lines" dl where dl."parent_id" = d."id" and true
      group by 1
    ) y
    where d."origin_type" = 'quote' and d."origin_id"::text = v_quote."id"::text and (d."deposit_bps" is not null or d."deposit_amount" is not null) and d."status" not in ('draft', 'void') and not (d."total" > 0 and d."credited_total" >= d."total") and y.amount <> 0;
  elsif invoice_from_quote.deposit_amount is not null then
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit of ' || v_quote."identifier",
      'quantity', 1,
      'unitAmount', (case when v_quote."prices_include_tax" or v_quote."total" = 0 then invoice_from_quote.deposit_amount
        else round(invoice_from_quote.deposit_amount::numeric * v_quote."subtotal" / v_quote."total")::bigint end)::text,
      'taxRateBps', case when v_quote."subtotal" = 0 then 0 else round(v_quote."tax_total" * 10000.0 / v_quote."subtotal")::integer end));
  else
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit ' || (invoice_from_quote.deposit_bps / 100.0)::text || '% of ' || v_quote."identifier",
      'quantity', 1,
      'unitAmount', round(case when v_quote."prices_include_tax" then v_quote."total" else v_quote."subtotal" end::numeric * invoice_from_quote.deposit_bps / 10000)::bigint::text,
      'taxRateBps', case when v_quote."subtotal" = 0 then 0 else round(v_quote."tax_total" * 10000.0 / v_quote."subtotal")::integer end));
  end if;
  v_row := null;
  return "better_supabase"."create_invoice"(v_quote."tenant_id", jsonb_build_object(
    'title', v_quote."title", 'currency', v_quote."currency", 'depositBps', invoice_from_quote.deposit_bps, 'depositAmount', invoice_from_quote.deposit_amount::text, 'pricesIncludeTax', v_quote."prices_include_tax",
    'company', case when v_quote."company_id" is null then null else jsonb_build_object('type', v_quote."company_type", 'id', v_quote."company_id") end,
    'contact', case when v_quote."contact_id" is null then null else jsonb_build_object('type', v_quote."contact_type", 'id', v_quote."contact_id") end,
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote."id"::text)) || v_header, v_lines);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_match_result (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_result jsonb;
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = invoice_match_result.invoice;
  if v_row."purchase_order_id" is null then
    return jsonb_build_object('invoiceId', v_row."id", 'currency', v_row."currency", 'purchaseOrderId', null, 'status', 'not_applicable', 'lines', '[]'::jsonb);
  end if;
  with billed as (
    select il."parent_id" as bill, (il."product_id")::text as variant, sum(il."quantity") as quantity,
      sum(case when b."prices_include_tax" then round((round(il."quantity" * il."unit_amount") - (round(round(il."quantity" * il."unit_amount") * il."discount_bps" / 10000.0) + least(coalesce(il."discount_amount", 0), greatest(round(il."quantity" * il."unit_amount") - round(round(il."quantity" * il."unit_amount") * il."discount_bps" / 10000.0), 0)))) * 10000.0 / (10000 + il."tax_rate_bps")) else round(il."quantity" * il."unit_amount") - (round(round(il."quantity" * il."unit_amount") * il."discount_bps" / 10000.0) + least(coalesce(il."discount_amount", 0), greatest(round(il."quantity" * il."unit_amount") - round(round(il."quantity" * il."unit_amount") * il."discount_bps" / 10000.0), 0))) end) as net
    from "better_supabase"."invoice_lines" il join "better_supabase"."invoices" b on b."id" = il."parent_id"
    where b."purchase_order_id" = v_row."purchase_order_id" and b."direction" = 'purchase'
      and b."kind" = 'invoice' and (b."id" = v_row."id" or b."status" in ('issued', 'partially_paid', 'paid'))
      and il."product_id" is not null
    group by 1, 2
  ),
  ordered as (
    select y."variant_id"::text as variant, sum(y."quantity_ordered") as ordered, sum(y."quantity_received") as received,
      sum(y."quantity_ordered" * y."unit_cost") / nullif(sum(y."quantity_ordered"), 0) as unit_cost
    from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = v_row."purchase_order_id"
    group by 1
  ),
  checked as (
    select x.variant, x.quantity, x.net, coalesce(o.ordered, 0) as ordered, coalesce(o.received, 0) as received,
      round(x.quantity * coalesce(o.unit_cost, 0)) as expected,
      (select coalesce(sum(e.quantity), 0) from billed e where e.variant = x.variant) as billed_total
    from billed x left join ordered o on o.variant = x.variant
    where x.bill = v_row."id"
  ),
  rated as (
    select c.*, case
      when c.received <= 0 then 'not_received'
      when c.billed_total > c.received then 'quantity_variance'
      when abs(c.net - c.expected) > greatest(round(c.expected * 100 / 10000.0), 500) then 'price_variance'
      else 'matched' end as status
    from checked c
  )
  select jsonb_build_object('invoiceId', v_row."id", 'currency', v_row."currency", 'purchaseOrderId', v_row."purchase_order_id",
    'status', coalesce((select r.status from rated r order by array_position(array['not_received', 'quantity_variance', 'price_variance', 'matched'], r.status) limit 1), 'matched'),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('variantId', r.variant, 'quantity', r.quantity::text, 'billedQuantity', r.billed_total::text,
      'orderedQuantity', r.ordered::text, 'receivedQuantity', r.received::text, 'amount', r.net::bigint::text, 'expectedAmount', r.expected::bigint::text, 'status', r.status) order by r.variant) from rated r), '[]'::jsonb))
  into v_result;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."invoices" x where x."id" = $1::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_invoice_tax (
  invoice uuid,
  on_date date
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_inv "better_supabase"."invoices"%rowtype;
  v_result jsonb;
begin
  select * into v_inv from "better_supabase"."invoices" x where x."id" = issue_invoice_tax.invoice;
  if not found then
    return;
  end if;
  -- A line that names a code by text takes the code's id and keeps its rate.
  update "better_supabase"."invoice_lines" x set "tax_code_id" = "better_supabase"."resolve_tax_code"(v_inv."tenant_id", x."tax_code", v_inv.legal_entity_id)
  where x."parent_id" = v_inv."id" and x."tax_code_id" is null and x."tax_code" is not null
    and "better_supabase"."resolve_tax_code"(v_inv."tenant_id", x."tax_code", v_inv.legal_entity_id) is not null;
  -- A line that names a code by id takes the code's text and its rate on the
  -- issue date; a margin scheme line charges nothing on top of its price.
  update "better_supabase"."invoice_lines" x set
    "tax_code" = y."code",
    "tax_rate_bps" = case when y."type" = 'margin' then 0 else coalesce("better_supabase"."tax_rate_on"(y."id", issue_invoice_tax.on_date), x."tax_rate_bps") end
  from "better_supabase"."tax_codes" y
  where x."parent_id" = v_inv."id" and x."tax_code_id" = y."id";
  select "better_supabase"."tax_compute_lines"(
    coalesce((select jsonb_agg(jsonb_build_object('quantity', x."quantity", 'unitAmount', x."unit_amount"::text, 'discountBps', x."discount_bps", 'discountAmount', x."discount_amount"::text, 'taxRateBps', x."tax_rate_bps", 'taxCodeId', x."tax_code_id", 'unitCost', x."unit_cost"::text) order by x."position") from "better_supabase"."invoice_lines" x
      where x."parent_id" = v_inv."id" and true), '[]'::jsonb),
    issue_invoice_tax.on_date, v_inv."prices_include_tax", 0,
    v_inv."discount_bps", v_inv."discount_amount")
  into v_result;
  delete from "better_supabase"."invoice_tax_lines" x where x."invoice_id" = v_inv."id";
  insert into "better_supabase"."invoice_tax_lines" ("tenant_id", "invoice_id", "tax_rate_bps", "tax_code", "tax_code_id", "net", "tax", "gross", "discount", "customer_vat_number", "show_tax")
  select v_inv."tenant_id", v_inv."id", g."rateBps", g.code, g."taxCodeId", g.net, g.tax, g.gross, g.discount, (select nullif(trim(z."vat_id"), '') from "better_supabase"."companies" z where z."id"::text = v_inv."company_id"::text), g."showTax"
  from jsonb_to_recordset(v_result -> 'groups') g("rateBps" integer, code text, "taxCodeId" uuid, net bigint, tax bigint, gross bigint, discount bigint, "showTax" boolean);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.order_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."orders" x where x."id" = $1::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.quote_totals_by_billing_party (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(g.row order by g.party, g.party_id, g.account_id), '[]'::jsonb)
  from (
    select l."billing_party" as party, l."billing_party_id" as party_id, l."billing_account_id"::text as account_id,
      jsonb_build_object(
        'billingParty', l."billing_party", 'billingPartyId', l."billing_party_id", 'billingAccountId', l."billing_account_id"::text,
        'lines', count(*), 'net', sum((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "better_supabase"."quote_lines" l
    where l."parent_id" = quote and (not l."optional" or l."selected")
    group by 1, 2, 3
  ) g
$function$;

CREATE OR REPLACE FUNCTION better_supabase.quote_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select y."updated_at" from "better_supabase"."quotes" y where y."id" = $1::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_invoice_lines (
  parent uuid,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid := set_invoice_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."invoices" x where x."id" = v_parent and not (x."status" <> 'draft');
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."invoices" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false))) then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_invoice_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_invoice_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."invoice_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position")
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      nullif(x.value ->> 'taxCodeId', '')::uuid,
      (x.value ->> 'unitCost')::bigint,
      coalesce((x.value ->> 'discountAmount')::bigint, 0),
      nullif(x.value ->> 'costSource', ''),
      nullif(x.value ->> 'locationId', '')::uuid,
      nullif(x.value ->> 'binId', '')::uuid,
      coalesce(nullif(x.value ->> 'billingParty', ''), 'customer'),
      nullif(x.value ->> 'billingPartyId', ''),
      nullif(x.value ->> 'billingAccountId', '')::uuid,
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_invoice_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_invoice_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."invoices" x where x."id" = v_parent);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_invoice_lines_recount (
  parent uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_inclusive boolean;
  v_record_bps integer;
  v_record_amount bigint;
  v_list bigint;
  v_line_discount bigint;
  v_net bigint;
  v_record_discount bigint;
  v_groups jsonb;
  v_discount bigint;
  v_subtotal bigint;
  v_tax bigint;
  v_total bigint;
begin
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount"
    into v_tenant, v_inclusive, v_record_bps, v_record_amount
  from "better_supabase"."invoices" x where x."id" = set_invoice_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "better_supabase"."invoice_lines" l where l."parent_id" = set_invoice_lines_recount.parent and true;
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * l."tax_rate_bps" / case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)) as tax
    from "better_supabase"."invoice_lines" l where l."parent_id" = set_invoice_lines_recount.parent and true
    group by 1, 2
  ), shared as (
    select g.rate, g.code, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first rows between unbounded preceding and current row)
  ), taxed as (
    select s.rate, s.code, s.share, s.amount - s.share as amount,
      s.tax - round(s.share * s.rate / case when v_inclusive then 10000.0 + s.rate else 10000.0 end) as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rate', x.rate,
      'code', x.code,
      'net', case when v_inclusive then x.amount - x.tax else x.amount end,
      'tax', x.tax,
      'discount', x.share,
      'gross', case when v_inclusive then x.amount else x.amount + x.tax end
    ) order by x.rate, x.code nulls first), '[]'::jsonb)
    into v_groups
  from taxed x;
  select coalesce(sum(r.net), 0), coalesce(sum(r.tax), 0), coalesce(sum(r.gross), 0)
    into v_subtotal, v_tax, v_total
  from jsonb_to_recordset(v_groups) r(net bigint, tax bigint, gross bigint);
  v_discount := v_line_discount + v_record_discount;
  update "better_supabase"."invoices" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total
  where x."id" = set_invoice_lines_recount.parent;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_quote_lines (
  parent uuid,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid := set_quote_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."quotes" x where x."id" = v_parent and not (not (x."status" in ('draft', 'changes_requested')));
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."quotes" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false))) then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_quote_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_quote_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."quote_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "section", "optional", "selected", "periods", "position")
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      coalesce(x.value ->> 'description', (select coalesce(v."title", (select p."title" from "better_supabase"."products" p where p."id" = v."product_id")) from "better_supabase"."product_variants" v where x.value -> 'product' ->> 'type' = 'product_variant' and v."id" = (x.value -> 'product' ->> 'id')::uuid and v."tenant_id" = v_tenant)),
      coalesce((x.value ->> 'quantity')::numeric, 1),
      coalesce((x.value ->> 'unitAmount')::bigint, (select ("better_supabase"."variant_price"(v."id", v_currency) ->> 'amount')::bigint from "better_supabase"."product_variants" v where x.value -> 'product' ->> 'type' = 'product_variant' and v."id" = (x.value -> 'product' ->> 'id')::uuid and v."tenant_id" = v_tenant)),
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      nullif(x.value ->> 'taxCodeId', '')::uuid,
      (x.value ->> 'unitCost')::bigint,
      coalesce((x.value ->> 'discountAmount')::bigint, 0),
      nullif(x.value ->> 'costSource', ''),
      nullif(x.value ->> 'locationId', '')::uuid,
      nullif(x.value ->> 'binId', '')::uuid,
      coalesce(nullif(x.value ->> 'billingParty', ''), 'customer'),
      nullif(x.value ->> 'billingPartyId', ''),
      nullif(x.value ->> 'billingAccountId', '')::uuid,
      nullif(trim(x.value ->> 'section'), ''),
      coalesce((x.value ->> 'optional')::boolean, false),
      coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false)),
      coalesce((x.value ->> 'periods')::integer, 1),
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_quote_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_quote_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."quotes" x where x."id" = v_parent);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_quote_lines_recount (
  parent uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_inclusive boolean;
  v_record_bps integer;
  v_record_amount bigint;
  v_list bigint;
  v_line_discount bigint;
  v_net bigint;
  v_record_discount bigint;
  v_groups jsonb;
  v_discount bigint;
  v_subtotal bigint;
  v_tax bigint;
  v_total bigint;
begin
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount"
    into v_tenant, v_inclusive, v_record_bps, v_record_amount
  from "better_supabase"."quotes" x where x."id" = set_quote_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected");
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * l."tax_rate_bps" / case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)) as tax
    from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected")
    group by 1, 2
  ), shared as (
    select g.rate, g.code, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first rows between unbounded preceding and current row)
  ), taxed as (
    select s.rate, s.code, s.share, s.amount - s.share as amount,
      s.tax - round(s.share * s.rate / case when v_inclusive then 10000.0 + s.rate else 10000.0 end) as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rate', x.rate,
      'code', x.code,
      'net', case when v_inclusive then x.amount - x.tax else x.amount end,
      'tax', x.tax,
      'discount', x.share,
      'gross', case when v_inclusive then x.amount else x.amount + x.tax end
    ) order by x.rate, x.code nulls first), '[]'::jsonb)
    into v_groups
  from taxed x;
  select coalesce(sum(r.net), 0), coalesce(sum(r.tax), 0), coalesce(sum(r.gross), 0)
    into v_subtotal, v_tax, v_total
  from jsonb_to_recordset(v_groups) r(net bigint, tax bigint, gross bigint);
  v_discount := v_line_discount + v_record_discount;
  delete from "better_supabase"."quote_tax_lines" x where x."parent_id" = set_quote_lines_recount.parent;
  insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
  select v_tenant, set_quote_lines_recount.parent, r.rate, r.code, r.net, r.tax, r.gross, r.discount
  from jsonb_to_recordset(v_groups) r(rate integer, code text, net bigint, tax bigint, gross bigint, discount bigint);
  update "better_supabase"."quotes" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total,
    "deposit_due" = case when x."deposit_amount" is not null then least(greatest(v_total, 0), x."deposit_amount") when x."deposit_bps" is not null then round(v_total * x."deposit_bps" / 10000.0)::bigint else 0 end
  where x."id" = set_quote_lines_recount.parent;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tax_compute_lines (
  lines                  jsonb,
  on_date                date,
  prices_include_tax     boolean,
  credit_restriction_bps integer,
  discount_bps           integer,
  discount_amount        bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_inclusive boolean := coalesce(tax_compute_lines.prices_include_tax, false);
  v_restriction integer := coalesce(tax_compute_lines.credit_restriction_bps, 0);
  v_on date := coalesce(tax_compute_lines.on_date, current_date);
  v_bps integer := coalesce(tax_compute_lines.discount_bps, 0);
  v_amount bigint := coalesce(tax_compute_lines.discount_amount, 0);
  v_lines jsonb;
  v_groups jsonb;
  v_net bigint;
  v_line_discount bigint;
  v_record_discount bigint;
begin
  if jsonb_typeof(tax_compute_lines.lines) is distinct from 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if v_restriction < 0 or v_restriction > 10000 then
    raise exception 'a credit restriction is 0 to 10000 basis points' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(tax_compute_lines.lines) x where jsonb_typeof(x.value) <> 'object') then
    raise exception 'every line must be an object' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    where x.value ->> 'taxCodeId' is not null
      and not exists (select 1 from "better_supabase"."tax_codes" y where y."id"::text = x.value ->> 'taxCodeId')
  ) then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
    where y."type" = 'margin' and x.value ->> 'unitCost' is null
  ) then
    raise exception 'a margin scheme line needs the unitCost of what it was bought for' using errcode = '22023', hint = 'TAX_MARGIN_COST_REQUIRED';
  end if;
  with src as (
    select x.ordinality as pos,
      coalesce((x.value ->> 'quantity')::numeric, 1) as qty,
      (x.value ->> 'unitAmount')::bigint as unit,
      coalesce((x.value ->> 'discountBps')::integer, 0) as disc_bps,
      coalesce((x.value ->> 'discountAmount')::bigint, 0) as disc_amount,
      coalesce((x.value ->> 'unitCost')::bigint, 0) as unit_cost,
      y."id" as code_id,
      y."code" as code,
      coalesce(y."type", 'sales') as type,
      case
        when y."id" is null then coalesce((x.value ->> 'taxRateBps')::integer, 0)
        when y."type" not in ('sales', 'purchase', 'margin') then 0
        else coalesce("better_supabase"."tax_rate_on"(y."id", v_on), (x.value ->> 'taxRateBps')::integer, -1)
      end as rate
    from jsonb_array_elements(tax_compute_lines.lines) with ordinality x
    left join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
  ), priced as (
    select s.*, round(s.qty * s.unit) as amount from src s
  ), discounted as (
    select p.*, least(p.amount, round(p.amount * p.disc_bps / 10000.0) + p.disc_amount) as disc from priced p
  ), counted as (
    select d.*, d.amount - d.disc as after, round(d.qty * d.unit_cost) as cost from discounted d
  ), taxed as (
    select n.pos, n.rate, n.code_id, n.code, n.type, n.after, n.disc,
      case
        when n.rate <= 0 then 0
        when n.type = 'margin' then round(greatest(n.after - n.cost, 0) * n.rate / (10000.0 + n.rate))
        else round(n.after * (10000 - v_restriction) * n.rate / (10000.0 * (case when v_inclusive then 10000.0 + n.rate else 10000.0 end)))
      end as tax
    from counted n
  )
  select coalesce(jsonb_agg(jsonb_build_object('pos', t.pos, 'rate', t.rate, 'codeId', t.code_id, 'code', t.code, 'type', t.type,
      'after', t.after::bigint, 'disc', t.disc::bigint, 'tax', t.tax::bigint) order by t.pos), '[]'::jsonb)
    into v_lines
  from taxed t;
  if exists (select 1 from jsonb_to_recordset(v_lines) r(rate integer) where r.rate < 0) then
    raise exception 'no rate of a line''s tax code covers the date, and the line gives no taxRateBps' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  select coalesce(sum(r.after), 0), coalesce(sum(r.disc), 0) into v_net, v_line_discount
  from jsonb_to_recordset(v_lines) r(after bigint, disc bigint);
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * v_bps / 10000.0)::bigint + v_amount)
    else 0
  end;
  with grouped as (
    select r.rate, r."codeId" as code_id, r.code, r.type, sum(r.after) as amount, sum(r.tax) as tax
    from jsonb_to_recordset(v_lines) r(rate integer, "codeId" uuid, code text, type text, after bigint, tax bigint)
    group by 1, 2, 3, 4
  ), shared as (
    select g.rate, g.code_id, g.code, g.type, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first, g.code_id nulls first rows between unbounded preceding and current row)
  ), reduced as (
    select s.rate, s.code_id, s.code, s.type, s.share, s.amount - s.share as amount,
      s.tax - case
        when s.rate <= 0 then 0
        when s.type = 'margin' then round(s.share * s.rate / (10000.0 + s.rate))
        else round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end)))
      end as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'taxCodeId', x.code_id,
      'code', x.code,
      'type', x.type,
      'rateBps', x.rate,
      'net', (case when v_inclusive or x.type = 'margin' then x.amount - x.tax else x.amount end)::text,
      'tax', x.tax::text,
      'gross', (case when v_inclusive or x.type = 'margin' then x.amount else x.amount + x.tax end)::text,
      'discount', x.share::text,
      'showTax', x.type <> 'margin'
    ) order by x.rate, x.code nulls first, x.code_id nulls first), '[]'::jsonb)
    into v_groups
  from reduced x;
  return jsonb_build_object(
    'groups', v_groups,
    'subtotal', (select coalesce(sum((g ->> 'net')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'taxTotal', (select coalesce(sum((g ->> 'tax')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'total', (select coalesce(sum((g ->> 'gross')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'discountTotal', (v_line_discount + v_record_discount)::text,
    'showTaxAmount', not exists (select 1 from jsonb_array_elements(v_groups) g where g ->> 'type' = 'margin')
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    raise exception 'quantity, unitAmount, discountBps, unitCost and taxRateBps must be numbers and taxCodeId a uuid' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
end;
$function$;

ALTER TABLE "better_supabase"."invoice_lines"
  ADD CONSTRAINT "invoice_lines_billing_party_check"
    CHECK ((billing_party = ANY (ARRAY['customer'::text, 'internal'::text, 'own_warranty'::text, 'supplier_warranty'::text, 'cost_account'::text])));

ALTER TABLE "better_supabase"."invoice_lines"
  ADD CONSTRAINT "invoice_lines_cost_source_check" CHECK ((cost_source = ANY (ARRAY['catalog'::text, 'average'::text, 'manual'::text, 'imported'::text])));

ALTER TABLE "better_supabase"."invoice_lines"
  ADD CONSTRAINT "invoice_lines_discount_amount_check" CHECK ((discount_amount >= 0));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "order_lines_billing_party_check"
    CHECK ((billing_party = ANY (ARRAY['customer'::text, 'internal'::text, 'own_warranty'::text, 'supplier_warranty'::text, 'cost_account'::text])));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "order_lines_cost_source_check" CHECK ((cost_source = ANY (ARRAY['catalog'::text, 'average'::text, 'manual'::text, 'imported'::text])));

ALTER TABLE "better_supabase"."order_lines"
  ADD CONSTRAINT "order_lines_unit_cost_check" CHECK ((unit_cost >= 0));

ALTER TABLE "better_supabase"."quote_lines"
  ADD CONSTRAINT "quote_lines_billing_party_check"
    CHECK ((billing_party = ANY (ARRAY['customer'::text, 'internal'::text, 'own_warranty'::text, 'supplier_warranty'::text, 'cost_account'::text])));

ALTER TABLE "better_supabase"."quote_lines"
  ADD CONSTRAINT "quote_lines_cost_source_check" CHECK ((cost_source = ANY (ARRAY['catalog'::text, 'average'::text, 'manual'::text, 'imported'::text])));

ALTER TABLE "better_supabase"."quote_lines"
  ADD CONSTRAINT "quote_lines_discount_amount_check" CHECK ((discount_amount >= 0));

REVOKE ALL ON FUNCTION "api"."document_totals_by_billing_party"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_totals_by_billing_party"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_credit_note"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_credit_note"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_invoice"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_invoice"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_order"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_order"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_quote"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_quote"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."invoice_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."invoice_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."order_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."order_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."quote_totals_by_billing_party"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."quote_totals_by_billing_party"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."quote_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."quote_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_totals_by_billing_party"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_totals_by_billing_party"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_credit_note"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_credit_note"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_invoice"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_invoice"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_invoice_document"(jsonb, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."import_order"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_order"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_quote"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_quote"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."invoice_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."invoice_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."order_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."order_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."quote_totals_by_billing_party"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."quote_totals_by_billing_party"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."quote_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."quote_updated_at"(text) TO "service_role";
