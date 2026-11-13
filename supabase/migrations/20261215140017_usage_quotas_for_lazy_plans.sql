SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.usage_quotas_for (
  tenants uuid[],
  meters  text[]
)
  RETURNS TABLE (
    tenant      uuid,
    meter       text,
    quota_limit numeric,
    period      text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with t as materialized (
    select d.tenant, case when exists (select 1 from "better_supabase"."usage_quotas" pq where pq."meter" = any (usage_quotas_for.meters) and pq."tenant_id" is null and pq."plan" <> '*') then better_supabase.tenant_entitlements(d.tenant)::text[] end as entitled, case when exists (select 1 from "better_supabase"."usage_quotas" pq where pq."meter" = any (usage_quotas_for.meters) and pq."tenant_id" is null and pq."plan" <> '*') then better_supabase.tenant_plans(d.tenant)::text[] end as plans
    from (select distinct u.tenant from unnest(usage_quotas_for.tenants) u(tenant) where u.tenant is not null) d
  )
  select distinct on (t.tenant, q."meter") t.tenant, q."meter", q."limit", q."period"
  from t
  join "better_supabase"."usage_quotas" q on q."meter" = any (usage_quotas_for.meters)
    and (q."tenant_id" = t.tenant or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (t.entitled) or q."plan" = any (t.plans))))
  order by t.tenant, q."meter", (q."tenant_id" is not null) desc, q."limit" desc nulls first
$function$;
