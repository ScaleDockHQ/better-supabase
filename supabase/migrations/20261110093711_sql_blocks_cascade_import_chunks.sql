SET local check_function_bodies = off;

DROP TRIGGER "bsb_approvals_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_attachments_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_comments_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_documents_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_notifications_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_reactions_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_relations_product_variant_cascade" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_approvals_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bsb_attachments_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bsb_comments_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bsb_documents_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bsb_notifications_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bsb_reactions_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bsb_relations_product_cascade" ON "better_supabase"."products";

DROP TRIGGER "bsb_notifications_change_request_cascade" ON "public"."change_requests";

DROP TRIGGER "bsb_notifications_customer_cascade" ON "public"."customers";

DROP TRIGGER "bsb_notifications_organization_cascade" ON "public"."organizations";

DROP TRIGGER "bsb_notifications_project_cascade" ON "public"."projects";

DROP TRIGGER "bsb_notifications_task_cascade" ON "public"."tasks";

ALTER TABLE "better_supabase"."import_chunks"
  DROP CONSTRAINT "bsb_import_chunks_status";

DROP FUNCTION "better_supabase"."approvals_subject_deleted"();

DROP FUNCTION "better_supabase"."attachments_subject_deleted"();

DROP FUNCTION "better_supabase"."comments_subject_deleted"();

DROP FUNCTION "better_supabase"."documents_subject_deleted"();

DROP FUNCTION "better_supabase"."notifications_subject_deleted"();

DROP FUNCTION "better_supabase"."reactions_subject_deleted"();

DROP FUNCTION "better_supabase"."relations_subject_deleted"();

CREATE OR REPLACE FUNCTION api.fail_import_chunk (
  run     uuid,
  entity  text,
  chunk   integer,
  message text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."fail_import_chunk"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.approvals_subject_deleted_product()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
begin
  delete from "better_supabase"."approval_requests" r where r."subject_type" = v_type and r."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approvals_subject_deleted_product_variant()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
begin
  delete from "better_supabase"."approval_requests" r where r."subject_type" = v_type and r."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachments_subject_deleted_product()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachments_subject_deleted_product_variant()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_subject_deleted_product()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."conversations" c where c."kind" = 'subject' and c."subject_type" = v_type and c."subject_id" = v_id;
  else
    delete from "better_supabase"."conversations" c where c."kind" = 'subject' and c."subject_type" = v_type and c."subject_id" = v_id and c."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_subject_deleted_product_variant()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."conversations" c where c."kind" = 'subject' and c."subject_type" = v_type and c."subject_id" = v_id;
  else
    delete from "better_supabase"."conversations" c where c."kind" = 'subject' and c."subject_type" = v_type and c."subject_id" = v_id and c."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.documents_subject_deleted_product()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
begin
  delete from "better_supabase"."documents" d where d."subject_type" = v_type and d."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.documents_subject_deleted_product_variant()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
begin
  delete from "better_supabase"."documents" d where d."subject_type" = v_type and d."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_retention_sweep (
  tenant     uuid    DEFAULT NULL::uuid,
  batch_size integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node uuid;
  v_binned integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'not allowed to sweep retention' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  for v_node in
    select x."id" from "better_supabase"."drive_nodes" x
    where (drive_retention_sweep.tenant is null or x."tenant_id" = drive_retention_sweep.tenant) and x."archived_at" is null
      and exists (
        select 1 from "better_supabase"."taggings" lg
        join "better_supabase"."tags" lt on lt."id" = lg."tag_id"
        where lg."subject_type" = 'drive_node' and lg."subject_id" = x."id"::text
          and "better_supabase"."retention_for_memo"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text) is not null
          and coalesce(x."updated_at", x."created_at") < now() - "better_supabase"."retention_for_memo"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text)
          and not "better_supabase"."is_held_memo"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text)
      )
      and not "better_supabase"."drive_node_held"(x."id")
    order by coalesce(x."updated_at", x."created_at"), x."id"
    limit least(greatest(coalesce(drive_retention_sweep.batch_size, 100), 1), 1000)
  loop
    begin
      perform "better_supabase"."drive_trash"(v_node);
      v_binned := v_binned + 1;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
  return v_binned;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fail_import_chunk (
  run     uuid,
  entity  text,
  chunk   integer,
  message text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  update "better_supabase"."import_chunks" x set "status" = 'failed', "done_at" = now(),
    "result" = jsonb_build_object('failed', true, 'message', left(coalesce(fail_import_chunk.message, ''), 500))
  where x."run_id" = fail_import_chunk.run and x."entity" = fail_import_chunk.entity
    and x."chunk" = fail_import_chunk.chunk and x."status" in ('pending', 'claimed', 'failed');
  return found;
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
  if v_entity <> all (array['organization_profile', 'attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'discount_group', 'discount_rule', 'party_discount_group', 'product', 'product_category', 'stock_count', 'order', 'payment_term', 'document_delivery_preference', 'party', 'party_contact', 'contact_method', 'party_location', 'party_bank_account', 'quote', 'invoice', 'credit_note', 'open_item', 'invoice_allocation', 'meter_reading', 'due_check', 'asset', 'asset_identifier', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer', 'customer_row']::text[]) then
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
            v_calls := v_calls || v_call;
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

CREATE OR REPLACE FUNCTION better_supabase.import_chunk_progress (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'pending', count(*) filter (where x."status" = 'pending'),
    'claimed', count(*) filter (where x."status" = 'claimed'),
    'done', count(*) filter (where x."status" = 'done'),
    'failed', count(*) filter (where x."status" = 'failed')
  )
  from "better_supabase"."import_chunks" x
  where x."run_id" = import_chunk_progress.run
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notifications_subject_deleted_change_request()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'change_request';
  v_id text := old."id"::text;
  v_tenant text := old."organization_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notifications_subject_deleted_customer()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'customer';
  v_id text := old."id"::text;
  v_tenant text := old."organization_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notifications_subject_deleted_organization()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'organization';
  v_id text := old."id"::text;
  v_tenant text := old."id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notifications_subject_deleted_product()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notifications_subject_deleted_product_variant()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notifications_subject_deleted_project()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'project';
  v_id text := old."id"::text;
  v_tenant text := old."organization_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notifications_subject_deleted_task()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'task';
  v_id text := old."id"::text;
  v_tenant text := old."organization_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."tenant_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.process_import_chunk (
  run    uuid,
  entity text,
  chunk  integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_done jsonb;
  v_claim jsonb;
  v_result jsonb;
begin
  select x."result" into v_done from "better_supabase"."import_chunks" x
  where x."run_id" = process_import_chunk.run and x."entity" = process_import_chunk.entity
    and x."chunk" = process_import_chunk.chunk and x."status" = 'done';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('done', true);
  end if;
  select x."result" into v_done from "better_supabase"."import_chunks" x
  where x."run_id" = process_import_chunk.run and x."entity" = process_import_chunk.entity
    and x."chunk" = process_import_chunk.chunk and x."status" = 'failed';
  if found then
    return coalesce(v_done, '{}'::jsonb) || jsonb_build_object('failed', true);
  end if;
  v_claim := "better_supabase"."claim_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk);
  if v_claim is null then
    return jsonb_build_object('skipped', true);
  end if;
  v_result := "better_supabase"."import_upsert_batch"(process_import_chunk.run, process_import_chunk.entity, v_claim -> 'items');
  perform "better_supabase"."complete_import_chunk"(process_import_chunk.run, process_import_chunk.entity, process_import_chunk.chunk, v_result);
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reactions_subject_deleted_product()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id;
  else
    delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id and r."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reactions_subject_deleted_product_variant()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id;
  else
    delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id and r."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relations_subject_deleted_product()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."relations" x
  where ((x."source_type" = v_type and x."source_id" = v_id)
     or (x."target_type" = v_type and x."target_id" = v_id));
  else
    delete from "better_supabase"."relations" x
  where ((x."source_type" = v_type and x."source_id" = v_id)
     or (x."target_type" = v_type and x."target_id" = v_id)) and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relations_subject_deleted_product_variant()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."relations" x
  where ((x."source_type" = v_type and x."source_id" = v_id)
     or (x."target_type" = v_type and x."target_id" = v_id));
  else
    delete from "better_supabase"."relations" x
  where ((x."source_type" = v_type and x."source_id" = v_id)
     or (x."target_type" = v_type and x."target_id" = v_id)) and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.store_import_chunk (
  run    uuid,
  entity text,
  chunk  integer,
  items  jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run "better_supabase"."import_runs";
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = store_import_chunk.run;
  if not found then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if store_import_chunk.chunk is null or store_import_chunk.chunk < 0 or jsonb_typeof(store_import_chunk.items) is distinct from 'array' then
    raise exception 'a chunk has a number from 0 and an array of items' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into "better_supabase"."import_chunks" ("run_id", "tenant_id", "entity", "chunk", "items")
  values (store_import_chunk.run, v_run."tenant_id", store_import_chunk.entity, store_import_chunk.chunk, store_import_chunk.items)
  on conflict ("run_id", "entity", "chunk") do update
    set "items" = excluded."items", "status" = 'pending', "claimed_at" = null, "result" = null, "done_at" = null
    where "better_supabase"."import_chunks"."status" <> 'done';
  return found;
end;
$function$;

ALTER TABLE "better_supabase"."import_chunks"
  ADD CONSTRAINT "bsb_import_chunks_status" CHECK ((status = ANY (ARRAY['pending'::text, 'claimed'::text, 'done'::text, 'failed'::text])));

CREATE INDEX approval_requests_subject_idx ON better_supabase.approval_requests USING btree (subject_type, subject_id);

CREATE INDEX relations_source_idx ON better_supabase.relations USING btree (tenant_id, source_type, source_id, kind);

CREATE TRIGGER bsb_approvals_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.approvals_subject_deleted_product_variant();

CREATE TRIGGER bsb_attachments_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_subject_deleted_product_variant();

CREATE TRIGGER bsb_comments_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_subject_deleted_product_variant();

CREATE TRIGGER bsb_documents_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.documents_subject_deleted_product_variant();

CREATE TRIGGER bsb_notifications_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted_product_variant();

CREATE TRIGGER bsb_reactions_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_subject_deleted_product_variant();

CREATE TRIGGER bsb_relations_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.relations_subject_deleted_product_variant();

CREATE TRIGGER bsb_approvals_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.approvals_subject_deleted_product();

CREATE TRIGGER bsb_attachments_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_subject_deleted_product();

CREATE TRIGGER bsb_comments_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_subject_deleted_product();

CREATE TRIGGER bsb_documents_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.documents_subject_deleted_product();

CREATE TRIGGER bsb_notifications_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted_product();

CREATE TRIGGER bsb_reactions_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_subject_deleted_product();

CREATE TRIGGER bsb_relations_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.relations_subject_deleted_product();

CREATE TRIGGER bsb_notifications_change_request_cascade
  AFTER DELETE ON public.change_requests
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted_change_request();

CREATE TRIGGER bsb_notifications_customer_cascade
  AFTER DELETE ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted_customer();

CREATE TRIGGER bsb_notifications_organization_cascade
  AFTER DELETE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted_organization();

CREATE TRIGGER bsb_notifications_project_cascade
  AFTER DELETE ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted_project();

CREATE TRIGGER bsb_notifications_task_cascade
  AFTER DELETE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.notifications_subject_deleted_task();

REVOKE ALL ON FUNCTION "api"."fail_import_chunk"(uuid, text, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."fail_import_chunk"(uuid, text, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approvals_subject_deleted_product"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."approvals_subject_deleted_product_variant"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."attachments_subject_deleted_product"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."attachments_subject_deleted_product_variant"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."comments_subject_deleted_product"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."comments_subject_deleted_product_variant"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."documents_subject_deleted_product"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."documents_subject_deleted_product_variant"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."fail_import_chunk"(uuid, text, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fail_import_chunk"(uuid, text, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notifications_subject_deleted_change_request"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."notifications_subject_deleted_customer"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."notifications_subject_deleted_organization"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."notifications_subject_deleted_product"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."notifications_subject_deleted_product_variant"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."notifications_subject_deleted_project"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."notifications_subject_deleted_task"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."reactions_subject_deleted_product"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."reactions_subject_deleted_product_variant"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."relations_subject_deleted_product"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."relations_subject_deleted_product_variant"() FROM PUBLIC;
