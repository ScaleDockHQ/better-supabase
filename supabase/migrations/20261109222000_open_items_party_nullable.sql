SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."invoice_open_items"
  ALTER COLUMN "party_id" DROP NOT NULL;

create or replace function "better_supabase"."refresh_open_item"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance bigint;
begin
  v_balance := (new."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = new."id"), 0) - new."credited_total" - new."paid_total");
  delete from "better_supabase"."invoice_open_items" x
  where x."document_id" = new."id" and x."document_type" = 'invoice';
  if new."status"::text in ('issued', 'partially_paid', 'paid') and v_balance <> 0 and new."issued_on" <= current_date then
    insert into "better_supabase"."invoice_open_items" ("tenant_id", "party_id", "side", "document_type", "document_id", "currency", "due_on", "issued_on", "gross", "balance")
    values (new."tenant_id", coalesce(new."company_id"::text, new."contact_id"::text), case when new."direction" = 'purchase' then 'supplier' else 'customer' end, 'invoice', new."id", new."currency"::text,
      new."due_on", new."issued_on", (new."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = new."id"), 0) - new."credited_total")::bigint, v_balance);
  end if;
  return null;
end;
$$;

create or replace function "better_supabase"."rebuild_open_items"(tenant uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if (select auth.role()) is distinct from 'service_role' and not coalesce(better_supabase.can('tenant', rebuild_open_items.tenant, 'invoices.read'), false) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  delete from "better_supabase"."invoice_open_items" x where x."tenant_id" = rebuild_open_items.tenant and x."document_type" = 'invoice';
  insert into "better_supabase"."invoice_open_items" ("tenant_id", "party_id", "side", "document_type", "document_id", "currency", "due_on", "issued_on", "gross", "balance")
  select x."tenant_id", coalesce(x."company_id"::text, x."contact_id"::text), case when x."direction" = 'purchase' then 'supplier' else 'customer' end, 'invoice', x."id", x."currency"::text,
    x."due_on", x."issued_on", (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint, (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::bigint
  from "better_supabase"."invoices" x
  where x."tenant_id" = rebuild_open_items.tenant
    and x."kind" = 'invoice'
    and x."status"::text in ('issued', 'partially_paid', 'paid')
    and x."issued_on" <= current_date
    and (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <> 0;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
