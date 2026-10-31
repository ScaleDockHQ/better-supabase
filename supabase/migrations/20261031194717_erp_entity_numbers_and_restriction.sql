SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."invoices"
  DROP CONSTRAINT "invoices_tenant_id_direction_kind_number_key";

ALTER TABLE "better_supabase"."orders"
  DROP CONSTRAINT "orders_tenant_id_invoice_number_key";

ALTER TABLE "better_supabase"."orders"
  DROP CONSTRAINT "orders_tenant_id_number_key";

ALTER TABLE "better_supabase"."quotes"
  DROP CONSTRAINT "quotes_tenant_id_number_revision_key";

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
  v_restriction integer;
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
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount", coalesce((select z."credit_restriction_bps" from "better_supabase"."payment_terms" z where z."id" = x."payment_terms_id"), 0)
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
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
      sum(round((round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
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
      s.tax - round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end))) as tax
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
  v_restriction integer;
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
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount", 0
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
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
      sum(round((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
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
      s.tax - round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end))) as tax
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

CREATE UNIQUE INDEX invoices_tenant_id_direction_kind_number_key ON better_supabase.invoices
  USING btree (tenant_id, direction, kind, number, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE UNIQUE INDEX orders_tenant_id_invoice_number_key ON better_supabase.orders
  USING btree (tenant_id, invoice_number, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE UNIQUE INDEX orders_tenant_id_number_key ON better_supabase.orders USING btree (tenant_id, number, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE UNIQUE INDEX quotes_tenant_id_number_revision_key ON better_supabase.quotes
  USING btree (tenant_id, number, revision, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid));
