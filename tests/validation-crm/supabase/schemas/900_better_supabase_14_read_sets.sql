-- better-supabase module: read-sets (0.5.1)
-- @bs-module read-sets@1 managed
-- One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

-- Functions for the read sets in `readSets` (better-supabase.config.ts); `gen` and `sql sync` rewrite them.
-- They are security invoker: RLS decides what each caller reads, as for any other query.

-- config.readSets
-- app_chrome
create or replace function public.rs_app_chrome(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'unread', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."notification_recipients" as t0 where (t0."recipient_user_id" = ((p->>'userId')::uuid) and t0."read_at" is null and t0."dismissed_at" is null))),
    'openTasks', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."tasks" as t0 where (t0."status" = any('{"todo","in_progress"}') and exists (select 1 from "public"."task_assignees" as t1 where t1."task_id" = t0."id" and t1."user_id" = ((p->>'userId')::uuid))))),
    'approvals', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."approval_requests" as t0 where (t0."status" = 'requested' and t0."approver_user_id" = ((p->>'userId')::uuid))))
  )
$rs$;
revoke execute on function public.rs_app_chrome(jsonb) from public, anon, authenticated;
grant execute on function public.rs_app_chrome(jsonb) to authenticated;

-- customer_detail
create or replace function public.rs_customer_detail(p jsonb)
  returns jsonb
  language sql stable security invoker set search_path = ''
as $rs$
  select jsonb_build_object(
    'customer', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('id', t0."id", 'companyName', t0."company_name", 'isBusiness', t0."is_business", 'status', t0."status", 'billingEmail', t0."billing_email", 'website', t0."website") as row from "public"."customers" as t0 where (t0."id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)) limit 1) s), 'count', null),
    'contacts', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('id', t0."id", 'jobTitle', t0."job_title", 'isPrimary', t0."is_primary", 'contactProfile', (select json_build_object('id', t1."id", 'firstName', t1."first_name", 'lastName', t1."last_name", 'displayName', t1."display_name", 'contactMethods', (select coalesce(json_agg(s.r order by s.o), '[]'::json) from (select json_build_object('id', t2."id", 'type', t2."type", 'value', t2."value", 'isPrimary', t2."is_primary") as r, row_number() over () as o from "public"."contact_methods" as t2 where t2."contact_profile_id" = t1."id") as s)) from "public"."contact_profiles" as t1 where t1."id" = t0."contact_profile_id" limit 1)) as row from "public"."customer_contacts" as t0 where (t0."customer_id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)) order by t0."is_primary" desc, t0."created_at" asc) s), 'count', null),
    'locations', jsonb_build_object('rows', (select coalesce(jsonb_agg(s.row), '[]'::jsonb) from (select json_build_object('id', t0."id", 'name', t0."name", 'addressLine1', t0."address_line1", 'addressCity', t0."address_city", 'isPrimary', t0."is_primary") as row from "public"."customer_locations" as t0 where (t0."customer_id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)) order by t0."is_primary" desc, t0."created_at" asc) s), 'count', null),
    'quotes', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."quotes" as t0 where (t0."customer_id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid)))),
    'invoices', jsonb_build_object('rows', '[]'::jsonb, 'count', (select count(*)::int as count from "public"."invoices" as t0 where (t0."customer_id" = ((p->>'customerId')::int8) and t0."organization_id" = ((p->>'organizationId')::uuid))))
  )
$rs$;
revoke execute on function public.rs_customer_detail(jsonb) from public, anon, authenticated;
grant execute on function public.rs_customer_detail(jsonb) to authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
