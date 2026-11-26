SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.create_payment_batch (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
  v_batch "better_supabase"."payment_batches"%rowtype;
  v_due date;
  v_exec date;
  v_reference text;
  v_ids uuid[];
  v_item record;
  v_creditor jsonb;
  v_iban text;
  v_total bigint := 0;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_payment_batch.tenant is not null and coalesce(better_supabase.can('tenant', create_payment_batch.tenant, 'banking.manage'), false))) then
    raise exception 'not allowed to create payment batches' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if jsonb_typeof(create_payment_batch.input) is distinct from 'object'
    or coalesce(create_payment_batch.input ->> 'accountId', '') !~ '^[0-9a-fA-F-]{36}$'
    or coalesce(create_payment_batch.input ->> 'dueBy', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or jsonb_typeof(create_payment_batch.input -> 'creditors') is distinct from 'object' then
    raise exception 'input needs accountId, dueBy and creditors' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  select * into v_account from "better_supabase"."bank_accounts" x
  where x."id" = (create_payment_batch.input ->> 'accountId')::uuid and x."tenant_id" = create_payment_batch.tenant and x."archived_at" is null;
  if not found then
    raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
  end if;
  if v_account."iban" is null then
    raise exception 'the bank account needs an IBAN to pay from' using errcode = '22023', hint = 'PAYMENT_BATCH_INVALID';
  end if;
  v_due := (create_payment_batch.input ->> 'dueBy')::date;
  v_exec := coalesce((create_payment_batch.input ->> 'executionOn')::date, current_date);
  v_reference := coalesce(nullif(trim(create_payment_batch.input ->> 'reference'), ''), 'Batch ' || to_char(v_exec, 'YYYY-MM-DD') || ' ' || left(gen_random_uuid()::text, 8));
  if jsonb_typeof(create_payment_batch.input -> 'invoiceIds') = 'array' then
    select array_agg(x.value::uuid) into v_ids from jsonb_array_elements_text(create_payment_batch.input -> 'invoiceIds') x;
  end if;
  insert into "better_supabase"."payment_batches" ("tenant_id", "bank_account_id", "reference", "message_id", "currency", "due_by", "execution_on", "total", "item_count", "created_by")
  values (create_payment_batch.tenant, v_account."id", v_reference, 'BSB' || replace(gen_random_uuid()::text, '-', ''), v_account."currency", v_due, v_exec, 1, 1, auth.uid())
  returning * into v_batch;
  for v_item in
    select r."documentId" as invoice_id, r."partyId" as party, r.identifier, r.balance::bigint as balance,
      r."discountDueOn" as discount_due_on, coalesce(r."discountAmount", 0)::bigint as discount_amount
    from jsonb_to_recordset("better_supabase"."open_items_for_party"(create_payment_batch.tenant, null, current_date, 'supplier'))
      as r("documentType" text, "documentId" uuid, "partyId" text, identifier text, currency text, "dueOn" date, balance bigint,
        "discountDueOn" date, "discountAmount" bigint, "approvalStatus" text)
    where r."documentType" = 'invoice' and r.currency = v_account."currency" and r.balance > 0
      and (v_ids is null or r."documentId" = any (v_ids))
      and (v_ids is not null or coalesce(r."approvalStatus", 'not_required') <> 'pending')
      and (r."dueOn" <= v_due or (r."discountDueOn" is not null and r."discountDueOn" >= v_exec and r."discountDueOn" <= v_due and r."discountAmount" > 0))
      and not exists (select 1 from "better_supabase"."payment_batch_items" y where y."invoice_id" = r."documentId" and y."status" in ('open', 'posted'))
    order by r."partyId", r."dueOn", r."documentId"
  loop
    if coalesce("better_supabase"."invoice_approval_state"(v_item.invoice_id) ->> 'status', 'not_required') = 'pending' then
      raise exception 'a bill in the batch still needs approval' using errcode = '55000', hint = 'PAYMENT_BATCH_APPROVAL_REQUIRED',
        detail = jsonb_build_object('invoiceId', v_item.invoice_id)::text;
    end if;
    v_creditor := create_payment_batch.input -> 'creditors' -> v_item.party;
    if jsonb_typeof(v_creditor) is distinct from 'object' or coalesce(trim(v_creditor ->> 'name'), '') = '' then
      raise exception 'a creditor is missing for a supplier in the batch' using errcode = '22023', hint = 'PAYMENT_BATCH_CREDITOR_MISSING',
        detail = jsonb_build_object('partyId', v_item.party)::text;
    end if;
    v_iban := upper(regexp_replace(coalesce(v_creditor ->> 'iban', ''), '\s', '', 'g'));
    if exists (select 1 from "better_supabase"."party_bank_accounts" x where x."tenant_id" = create_payment_batch.tenant and x."party_id"::text = v_item.party) then
      if v_iban = '' then
        select x."iban" into v_iban from "better_supabase"."party_bank_accounts" x where x."tenant_id" = create_payment_batch.tenant and x."party_id"::text = v_item.party
        order by x."is_primary" desc, x."iban" limit 1;
      elsif not exists (select 1 from "better_supabase"."party_bank_accounts" x where x."tenant_id" = create_payment_batch.tenant and x."party_id"::text = v_item.party and upper(regexp_replace(x."iban", '\s', '', 'g')) = v_iban) then
        raise exception 'the IBAN is not a registered bank account of the supplier' using errcode = '22023', hint = 'PAYMENT_BATCH_CREDITOR_INVALID',
          detail = jsonb_build_object('partyId', v_item.party)::text;
      end if;
      v_iban := upper(regexp_replace(v_iban, '\s', '', 'g'));
    end if;
    if v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' or "better_supabase"."bank_mod97"(substr(v_iban, 5) || substr(v_iban, 1, 4)) is distinct from 1 then
      raise exception 'a creditor has an invalid IBAN' using errcode = '22023', hint = 'PAYMENT_BATCH_CREDITOR_INVALID',
        detail = jsonb_build_object('partyId', v_item.party)::text;
    end if;
    insert into "better_supabase"."payment_batch_items" ("tenant_id", "batch_id", "invoice_id", "party_id", "creditor_name", "creditor_iban", "creditor_bic", "amount", "discount", "currency", "end_to_end_id", "remittance")
    values (create_payment_batch.tenant, v_batch."id", v_item.invoice_id, v_item.party, left(trim(v_creditor ->> 'name'), 140), v_iban,
      nullif(upper(regexp_replace(coalesce(v_creditor ->> 'bic', ''), '\s', '', 'g')), ''),
      v_item.balance - case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end,
      case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end,
      v_account."currency", replace(gen_random_uuid()::text, '-', ''), left(v_item.identifier, 140));
    v_total := v_total + v_item.balance - case when v_item.discount_due_on >= v_exec then v_item.discount_amount else 0 end;
    v_count := v_count + 1;
  end loop;
  if v_count = 0 then
    raise exception 'no approved open bill is due by that date' using errcode = '22023', hint = 'PAYMENT_BATCH_EMPTY';
  end if;
  update "better_supabase"."payment_batches" y set "total" = v_total, "item_count" = v_count where y."id" = v_batch."id" returning * into v_batch;
  return jsonb_build_object('id', v_batch."id", 'organizationId', v_batch."tenant_id", 'accountId', v_batch."bank_account_id", 'reference', v_batch."reference", 'messageId', v_batch."message_id", 'currency', v_batch."currency", 'dueBy', v_batch."due_by", 'executionOn', v_batch."execution_on", 'total', v_batch."total"::text, 'itemCount', v_batch."item_count", 'status', v_batch."status", 'transactionId', v_batch."bank_transaction_id", 'createdBy', v_batch."created_by", 'createdAt', v_batch."created_at", 'postedAt', v_batch."posted_at", 'reconciledAt', v_batch."reconciled_at", 'items', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'invoiceId', y."invoice_id", 'partyId', y."party_id", 'creditorName', y."creditor_name", 'creditorIban', y."creditor_iban", 'creditorBic', y."creditor_bic", 'amount', y."amount"::text, 'discount', y."discount"::text, 'currency', y."currency", 'endToEndId', y."end_to_end_id", 'remittance', y."remittance", 'status', y."status") order by y."creditor_name", y."id") from "better_supabase"."payment_batch_items" y where y."batch_id" = v_batch."id"), '[]'::jsonb));
end;
$function$;
