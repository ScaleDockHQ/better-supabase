SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.list_deals_for_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_deals_for_subject"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_quotes_for_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_quotes_for_subject"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_deals_for_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) as item, x."created_at" as created, x."id" as id
    from "better_supabase"."deals" x
    where x."tenant_id" = list_deals_for_subject.tenant
      and x."archived_at" is null
      and ((x."company_type" = list_deals_for_subject.subject_type and x."company_id"::text = list_deals_for_subject.subject_id)
        or exists (select 1 from "better_supabase"."deal_contacts" dc where dc."deal_id" = x."id"
          and dc."contact_type" = list_deals_for_subject.subject_type and dc."contact_id"::text = list_deals_for_subject.subject_id))
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(list_deals_for_subject.page_size, 50), 1), 200)
  ) z;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_quotes_for_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_quotes_for_subject.tenant, 'quotes.read'), false)) then
    raise exception 'not allowed to read this organization''s quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(z.item order by z.created desc, z.id desc)
    from (
      select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) as item, x."created_at" as created, x."id" as id
      from "better_supabase"."quotes" x
      where x."tenant_id" = list_quotes_for_subject.tenant
        and ((x."company_type" = list_quotes_for_subject.subject_type and x."company_id"::text = list_quotes_for_subject.subject_id) or (x."contact_type" = list_quotes_for_subject.subject_type and x."contact_id"::text = list_quotes_for_subject.subject_id))
      order by x."created_at" desc, x."id" desc
      limit least(greatest(coalesce(list_quotes_for_subject.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_deals_for_subject"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_deals_for_subject"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_quotes_for_subject"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_quotes_for_subject"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_deals_for_subject"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_deals_for_subject"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_quotes_for_subject"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_quotes_for_subject"(uuid, text, text, integer) TO "authenticated", "service_role";
