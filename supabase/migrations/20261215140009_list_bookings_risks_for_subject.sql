SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.list_bookings_for_customer (
  tenant    uuid,
  customer  text,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_bookings_for_customer"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_risks_for_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_risks_for_subject"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_bookings_for_customer (
  tenant    uuid,
  customer  text,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(z.item order by z.starts desc, z.id desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") as item, lower(bk."during") as starts, bk."id" as id
    from "better_supabase"."bookings" bk
    where bk."tenant_id" = list_bookings_for_customer.tenant
      and bk."customer_id"::text = list_bookings_for_customer.customer
    order by lower(bk."during") desc, bk."id" desc
    limit least(greatest(coalesce(list_bookings_for_customer.page_size, 50), 1), 200)
  ) z
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_risks_for_subject (
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
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_risks_for_subject.tenant is not null and coalesce(better_supabase.can('tenant', list_risks_for_subject.tenant, 'risks.read'), false))) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(z.item order by z.score desc, z.seq, z.id)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, coalesce(x."residual_score", -1) as score, x."sequence" as seq, x."id" as id
      from "better_supabase"."risks" x
      where x."tenant_id" = list_risks_for_subject.tenant
        and x."archived_at" is null and x."status" <> 'closed'
        and exists (
          select 1 from "better_supabase"."relations" l
          where l."tenant_id" = x."tenant_id"
            and l."source_type" = 'risk' and l."source_id" = x."id"::text
            and l."target_type" = list_risks_for_subject.subject_type and l."target_id"::text = list_risks_for_subject.subject_id)
      order by coalesce(x."residual_score", -1) desc, x."sequence", x."id"
      limit least(greatest(coalesce(list_risks_for_subject.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_bookings_for_customer"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_bookings_for_customer"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_risks_for_subject"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_risks_for_subject"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_bookings_for_customer"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_bookings_for_customer"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_risks_for_subject"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_risks_for_subject"(uuid, text, text, integer) TO "authenticated", "service_role";
