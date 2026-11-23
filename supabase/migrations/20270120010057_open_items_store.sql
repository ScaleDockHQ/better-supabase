SET local check_function_bodies = off;

DROP TRIGGER "bsb_invoice_open_items_refresh" ON "better_supabase"."invoices";

CREATE OR REPLACE FUNCTION api.open_items_drift (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_items_drift"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.import_integrity (
  tenant uuid,
  source text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "better_supabase"."import_records" d
      where d."tenant_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
    union all
    select 'unbalanced_ledger', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select e."transaction_id"::text as sample from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where y."tenant_id" = import_integrity.tenant
      group by e."transaction_id"
      having sum(e."amount") <> 0
    ) q
    union all
    select 'negative_invoice', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."invoices" where "tenant_id" = import_integrity.tenant and "total" < 0 and "kind"::text is distinct from 'credit_note'
    union all
    select 'issued_without_number', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."invoices" where "tenant_id" = import_integrity.tenant and "status"::text in ('issued', 'partially_paid', 'paid') and nullif("identifier"::text, '') is null
    union all
    select 'open_items_drift', 'error', jsonb_array_length(d.rows)::integer, (
        select coalesce(jsonb_agg(r ->> 'documentId'), '[]'::jsonb) from jsonb_array_elements(d.rows) r
      ) from (select "better_supabase"."open_items_drift_rows"(import_integrity.tenant) as rows) d
    union all
    select 'archived_without_date', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."companies" where "tenant_id" = import_integrity.tenant and "lifecycle"::text = 'archived' and "archived_at" is null
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_items_drift (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_items_drift.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return "better_supabase"."open_items_drift_rows"(open_items_drift.tenant);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_items_drift_rows (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := open_items_drift_rows.tenant;
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'documentType', coalesce(s.document_type, f.document_type), 'documentId', coalesce(s.document, f.document),
        'stored', s.balance::text, 'fold', f.balance::text)
      order by coalesce(s.document_type, f.document_type), coalesce(s.document, f.document))
    from (
      select e."document_type" as document_type, e."document_id" as document, e."party_id" as party,
        e."gross" as gross, e."balance" as balance
      from "better_supabase"."invoice_open_items" e where e."tenant_id" = v_tenant
    ) s
    full join (select 'invoice'::text as document_type, x."id" as document, coalesce(x."company_id"::text, x."contact_id"::text) as party,
      (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint as gross, (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::bigint as balance
    from "better_supabase"."invoices" x
    where x."tenant_id" = v_tenant
      and x."kind" = 'invoice'
      and x."status" in ('issued', 'partially_paid', 'paid')
      and x."issued_on" is not null
      and (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <> 0
    union all
    select 'unallocated_payment'::text, a."id", a."holder_id", c.amount, c.amount
    from "better_supabase"."ledger_accounts" a
    cross join lateral (
      select coalesce(sum(e."amount"), 0)::bigint as amount from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where e."account_id" = a."id" and (y."effective_at" at time zone 'UTC')::date <= current_date
    ) c
    where a."tenant_id" = v_tenant and a."managed_by" = 'invoices'
      and a."holder_type" = 'invoice_party' and c.amount < 0) f
      on f.document_type = s.document_type and f.document = s.document
    where s.document is null or f.document is null
      or s.balance <> f.balance or s.gross <> f.gross or s.party is distinct from f.party
    limit 100
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_items_for_party (
  tenant   uuid,
  party_id text DEFAULT NULL::text,
  as_of    date DEFAULT NULL::date,
  side     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_as_of date := coalesce(open_items_for_party.as_of, current_date);
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', open_items_for_party.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if open_items_for_party.side is not null and open_items_for_party.side not in ('customer', 'supplier') then
    raise exception 'side is customer or supplier' using errcode = '22023', hint = 'INVOICE_OPEN_ITEMS_INVALID';
  end if;
  
  if v_as_of = current_date then
    return coalesce((
      select jsonb_agg(s.item order by s.ord_side, s.ord_party, s.ord_due nulls last, s.ord_document)
      from (
        select jsonb_build_object(
            'side', e."side", 'partyId', e."party_id", 'documentType', e."document_type", 'documentId', e."document_id",
            'currency', e."currency", 'issuedOn', e."issued_on", 'dueOn', e."due_on",
            'amount', e."gross"::text, 'balance', e."balance"::text,
            'daysOverdue', case when e."due_on" is null then 0 else v_as_of - e."due_on" end,
            'bucket', case when e."document_type" = 'unallocated_payment' then 'unallocated'
              when case when e."due_on" is null then 0 else v_as_of - e."due_on" end <= 0 then 'current'
              when case when e."due_on" is null then 0 else v_as_of - e."due_on" end <= 30 then 'days1To30' when case when e."due_on" is null then 0 else v_as_of - e."due_on" end <= 60 then 'days31To60'
              when case when e."due_on" is null then 0 else v_as_of - e."due_on" end <= 90 then 'days61To90' else 'over90' end)
            || coalesce(case when x."id" is null then null else jsonb_build_object('identifier', x."identifier"::text, 'discountDueOn', x."discount_due_on", 'discountAmount', coalesce(x."discount_amount_early", 0)::bigint::text, 'legalEntityId', x.legal_entity_id, 'approvalStatus', case when x."direction" = 'purchase' then "better_supabase"."invoice_approval_state"(x."id") ->> 'status' end) end, '{}'::jsonb) as item,
          e."side" as ord_side, e."party_id" as ord_party, e."due_on" as ord_due, e."document_id" as ord_document
        from "better_supabase"."invoice_open_items" e
        left join "better_supabase"."invoices" x on e."document_type" = 'invoice' and x."id" = e."document_id"
        where e."tenant_id" = open_items_for_party.tenant
          and e."balance" <> 0
          and (e."document_type" = 'unallocated_payment' or e."issued_on" <= v_as_of)
          and (open_items_for_party.party_id is null or e."party_id" = open_items_for_party.party_id)
          and (open_items_for_party.side is null or e."side" = open_items_for_party.side)
      ) s
    ), '[]'::jsonb);
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'side', e.side, 'partyId', e.party, 'documentType', e.document_type, 'documentId', e.id,
        'identifier', e.identifier, 'currency', e.currency, 'issuedOn', e.issued_on, 'dueOn', e.due_on,
        'amount', e.gross::text, 'balance', e.balance::text, 'daysOverdue', e.days,
        'bucket', case when e.document_type = 'unallocated_payment' then 'unallocated'
          when e.days <= 0 then 'current' when e.days <= 30 then 'days1To30' when e.days <= 60 then 'days31To60'
          when e.days <= 90 then 'days61To90' else 'over90' end,
        'discountDueOn', e.discount_due_on, 'discountAmount', e.discount_amount::text,
        'legalEntityId', e.entity, 'approvalStatus', e.approval)
      order by e.side, e.party, e.due_on nulls last, e.id)
    from (
      select d.*, case when d.due_on is null then 0 else v_as_of - d.due_on end as days
      from (
        select 'invoice'::text as document_type, x."id" as id, case when x."direction" = 'purchase' then 'supplier' else 'customer' end as side, coalesce(x."company_id"::text, x."contact_id"::text) as party,
          x."identifier"::text as identifier, x."currency"::text as currency, x."issued_on" as issued_on, x."due_on" as due_on,
          (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint as gross,
          case when open_items_for_party.as_of is null or open_items_for_party.as_of = current_date
            then (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::bigint
            else (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - (select coalesce(-sum(e."amount"), 0)::bigint from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text
        and (y."effective_at" at time zone 'UTC')::date <= v_as_of))::bigint
          end as balance,
          x."discount_due_on" as discount_due_on,
          coalesce(x."discount_amount_early", 0)::bigint as discount_amount,
          x.legal_entity_id as entity,
          case when x."direction" = 'purchase' then "better_supabase"."invoice_approval_state"(x."id") ->> 'status' end as approval
        from "better_supabase"."invoices" x
        where x."tenant_id" = open_items_for_party.tenant
          and x."kind" = 'invoice'
          and x."status" in ('issued', 'partially_paid', 'paid')
          and x."issued_on" <= v_as_of
          and (open_items_for_party.party_id is null or (x."company_id"::text = open_items_for_party.party_id or x."contact_id"::text = open_items_for_party.party_id))
        union all
        select 'unallocated_payment'::text, a."id", 'customer'::text, a."holder_id", null::text, a."unit"::text,
          null::date, null::date, (-c.amount)::bigint, (-c.amount)::bigint, null::date, 0::bigint, null::uuid, null::text
        from "better_supabase"."ledger_accounts" a
        cross join lateral (
          select coalesce(-sum(e."amount"), 0)::bigint as amount from "better_supabase"."ledger_entries" e
          join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
          where e."account_id" = a."id" and (y."effective_at" at time zone 'UTC')::date <= v_as_of
        ) c
        where a."tenant_id" = open_items_for_party.tenant and a."managed_by" = 'invoices'
          and a."holder_type" = 'invoice_party'
          and (open_items_for_party.party_id is null or a."holder_id" = open_items_for_party.party_id)
          and c.amount > 0
      ) d
      where d.balance <> 0
    ) e
    where open_items_for_party.side is null or e.side = open_items_for_party.side
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_items_page (
  tenant    uuid,
  side      text    DEFAULT NULL::text,
  party_id  text    DEFAULT NULL::text,
  "limit"   integer DEFAULT 50,
  "offset"  integer DEFAULT 0,
  count_cap integer DEFAULT 10000
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_total integer;
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_items_page.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  select count(*) into v_total from "better_supabase"."invoice_open_items" e
  where e."tenant_id" = open_items_page.tenant
    and e."balance" <> 0
    and (e."document_type" = 'unallocated_payment' or e."issued_on" <= current_date)
    and (open_items_page.party_id is null or e."party_id" = open_items_page.party_id)
    and (open_items_page.side is null or e."side" = open_items_page.side);
  select coalesce(jsonb_agg(row_to_json(p)), '[]'::jsonb) into v_rows from (
    select e."side" as side, e."party_id" as "partyId", e."document_type" as "documentType",
      e."document_id" as "documentId", e."currency" as currency, e."due_on" as "dueOn",
      e."issued_on" as "issuedOn", e."gross"::text as amount, e."balance"::text as balance
    from "better_supabase"."invoice_open_items" e
    where e."tenant_id" = open_items_page.tenant
      and e."balance" <> 0
      and (e."document_type" = 'unallocated_payment' or e."issued_on" <= current_date)
      and (open_items_page.party_id is null or e."party_id" = open_items_page.party_id)
      and (open_items_page.side is null or e."side" = open_items_page.side)
    order by e."due_on" nulls last, e."document_id"
    limit least(greatest(coalesce(open_items_page."limit", 50), 1), 200)
    offset greatest(coalesce(open_items_page."offset", 0), 0)
  ) p;
  return jsonb_build_object('rows', v_rows, 'total', least(v_total, coalesce(open_items_page.count_cap, 10000)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rebuild_open_items (
  tenant uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', rebuild_open_items.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return "better_supabase"."rebuild_open_items_of"(rebuild_open_items.tenant);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rebuild_open_items_of (
  tenant uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."invoice_open_items" e where e."tenant_id" = rebuild_open_items_of.tenant;
  insert into "better_supabase"."invoice_open_items" ("tenant_id", "party_id", "side", "document_type", "document_id", "currency", "due_on", "issued_on", "gross", "balance")
  select x."tenant_id", coalesce(x."company_id"::text, x."contact_id"::text), case when x."direction" = 'purchase' then 'supplier' else 'customer' end, 'invoice', x."id", x."currency"::text,
    x."due_on", x."issued_on", (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint, (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::bigint
  from "better_supabase"."invoices" x
  where x."tenant_id" = rebuild_open_items_of.tenant
    and x."kind" = 'invoice'
    and x."status" in ('issued', 'partially_paid', 'paid')
    and x."issued_on" is not null
    and (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <> 0
  union all
  select a."tenant_id", a."holder_id", 'customer', 'unallocated_payment', a."id", a."unit"::text,
    null::date, null::date, b."balance"::bigint, b."balance"::bigint
  from "better_supabase"."ledger_accounts" a
  join "better_supabase"."ledger_balances" b on b."account_id" = a."id"
  where a."tenant_id" = rebuild_open_items_of.tenant
    and a."managed_by" = 'invoices'
    and a."holder_type" = 'invoice_party'
    and b."balance" < 0;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refresh_open_credit()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not exists (
    select 1 from "better_supabase"."ledger_accounts" a
    where a."id" = new."account_id"
      and a."managed_by" = 'invoices' and a."holder_type" = 'invoice_party'
  ) then
    return null;
  end if;
  delete from "better_supabase"."invoice_open_items" e
  where e."document_id" = new."account_id" and e."document_type" = 'unallocated_payment';
  insert into "better_supabase"."invoice_open_items" ("tenant_id", "party_id", "side", "document_type", "document_id", "currency", "due_on", "issued_on", "gross", "balance")
  select a."tenant_id", a."holder_id", 'customer', 'unallocated_payment', a."id", a."unit"::text,
    null::date, null::date, b."balance"::bigint, b."balance"::bigint
  from "better_supabase"."ledger_accounts" a
  join "better_supabase"."ledger_balances" b on b."account_id" = a."id"
  where a."id" = new."account_id"
    and a."managed_by" = 'invoices'
    and a."holder_type" = 'invoice_party'
    and b."balance" < 0;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refresh_open_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE' then
    delete from "better_supabase"."invoice_open_items" e
    where e."document_id" = old."id" and e."document_type" = 'invoice';
    return null;
  end if;
  perform "better_supabase"."refresh_open_item_of"(new."id");
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refresh_open_item_charge()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform "better_supabase"."refresh_open_item_of"(old."invoice_id");
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform "better_supabase"."refresh_open_item_of"(new."invoice_id");
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refresh_open_item_of (
  invoice uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  delete from "better_supabase"."invoice_open_items" e
  where e."document_id" = refresh_open_item_of.invoice and e."document_type" = 'invoice';
  insert into "better_supabase"."invoice_open_items" ("tenant_id", "party_id", "side", "document_type", "document_id", "currency", "due_on", "issued_on", "gross", "balance")
  select x."tenant_id", coalesce(x."company_id"::text, x."contact_id"::text), case when x."direction" = 'purchase' then 'supplier' else 'customer' end, 'invoice', x."id", x."currency"::text,
    x."due_on", x."issued_on", (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint, (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::bigint
  from "better_supabase"."invoices" x
  where x."id" = refresh_open_item_of.invoice
    and x."kind" = 'invoice'
    and x."status" in ('issued', 'partially_paid', 'paid')
    and x."issued_on" is not null
    and (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <> 0;
end;
$function$;

ALTER TABLE "better_supabase"."invoice_open_items"
  ADD CONSTRAINT "bsb_invoice_open_items_document_type_check" CHECK ((document_type = ANY (ARRAY['invoice'::text, 'unallocated_payment'::text])));

CREATE TRIGGER bsb_invoice_open_items_charge
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.invoice_charges
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.refresh_open_item_charge();

CREATE TRIGGER bsb_invoice_open_items_refresh
  AFTER INSERT OR DELETE OR UPDATE OF status, paid_total, total, credited_total, due_on, issued_on, kind, currency, company_id, contact_id, direction ON better_supabase.invoices
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.refresh_open_item();

CREATE TRIGGER bsb_invoice_open_items_credit
  AFTER INSERT OR UPDATE OF balance ON better_supabase.ledger_balances
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.refresh_open_credit();

REVOKE ALL ON FUNCTION "api"."open_items_drift"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_items_drift"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_items_drift"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_items_drift"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_items_drift_rows"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."rebuild_open_items_of"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."refresh_open_credit"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."refresh_open_item"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."refresh_open_item_charge"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."refresh_open_item_of"(uuid) FROM PUBLIC;
