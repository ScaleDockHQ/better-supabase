SET local check_function_bodies = off;

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
  if coalesce(v_data ->> 'onTaken', 'fail') not in ('fail', 'next_free') then
    raise exception 'onTaken is fail or next_free' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_data ->> 'onTaken' = 'next_free' and exists (select 1 from "better_supabase"."quotes" y where y."tenant_id" = v_tenant and y."identifier" = v_number) then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_NUMBER_REASSIGNED', 'message', 'number ' || v_number || ' was taken; the next free number was issued'));
    v_number := null;
  end if;
  if v_number is not null then
    perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  end if;
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), replace('Quote {number}', '{number}', coalesce(v_number, ''))),
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
