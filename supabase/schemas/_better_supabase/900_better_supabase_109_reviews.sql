-- better-supabase module: reviews
-- @bsb-block reviews@2 managed
-- @bsb-hash sha256:e059222ba564d64b57ee281a8d38d359d8fa5ff19eb89fc9c8741e465f8514e6
-- Ratings and reviews of catalog products and other subjects: one per user and subject, verified against paid orders, moderated before or after publishing through the moderation block, with a per-subject aggregate public storefronts can read.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."reviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null constraint bsb_reviews_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null constraint bsb_reviews_subject_id_check check (length("subject_id") >= 1 and length("subject_id") <= 200),
  "author_id" uuid references auth.users (id) on delete cascade,
  "author_name" text constraint bsb_reviews_author_name_check check ("author_name" is null or length("author_name") <= 100),
  "rating" smallint not null constraint bsb_reviews_rating_check check ("rating" >= 1 and "rating" <= 5),
  "title" text constraint bsb_reviews_title_check check ("title" is null or length("title") <= 200),
  "body" text constraint bsb_reviews_body_check check ("body" is null or length("body") <= 5000),
  "status" text not null default 'pending' constraint bsb_reviews_status_check check ("status" in ('pending', 'published', 'rejected')),
  "verified" boolean not null default false,
  "rejection_reason" text constraint bsb_reviews_rejection_reason_check check ("rejection_reason" is null or length("rejection_reason") <= 1000),
  "reply" text constraint bsb_reviews_reply_check check ("reply" is null or length("reply") <= 5000),
  "replied_by" uuid,
  "replied_at" timestamptz,
  "published_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "subject_type", "subject_id", "author_id")
);
create index "reviews_subject_idx" on "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "status", "created_at" desc);
create index "reviews_queue_idx" on "better_supabase"."reviews" ("tenant_id", "status", "created_at" desc);
create index "reviews_author_idx" on "better_supabase"."reviews" ("author_id");
alter table "better_supabase"."reviews" enable row level security;
revoke all on "better_supabase"."reviews" from public, anon, authenticated;
grant all on "better_supabase"."reviews" to service_role;

create table "better_supabase"."review_stats" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "review_count" integer not null default 0,
  "rating_total" bigint not null default 0,
  "histogram" jsonb not null default '{}'::jsonb,
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "subject_type", "subject_id")
);
alter table "better_supabase"."review_stats" enable row level security;
revoke all on "better_supabase"."review_stats" from public, anon, authenticated;
grant all on "better_supabase"."review_stats" to service_role;

-- Whether the caller may read and review a subject: an active product on a
-- published public storefront or in a catalog the caller reads, or a
-- registered subject in an organization the caller belongs to. plpgsql, so
-- a subject table a later module creates (messages) binds late.
create or replace function "better_supabase"."review_subject_readable"(tenant uuid, subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce(case review_subject_readable.subject_type
    when 'product' then exists (select 1 from "better_supabase"."products" p where p."id"::text = review_subject_readable.subject_id and p."tenant_id" = review_subject_readable.tenant and p."status" = 'active' and (coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'catalog.read'), false)))
    else (auth.uid() is not null and exists (select 1 from "public"."memberships" m where m."organization_id" = review_subject_readable.tenant and m."user_id" = auth.uid()) and case review_subject_readable.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'tasks.read'), false)
    when 'work_project' then exists (select 1 from "better_supabase"."work_projects" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'invoices.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (review_subject_readable.subject_id)::uuid and s."organization_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant and (coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (review_subject_readable.subject_id)::uuid and s."id" = review_subject_readable.tenant)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (review_subject_readable.subject_id)::uuid and s."tenant_id" = review_subject_readable.tenant) and coalesce(better_supabase.can('tenant', review_subject_readable.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (review_subject_readable.subject_id)::uuid and s."organization_id" = review_subject_readable.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (review_subject_readable.subject_id)::uuid and s."organization_id" = review_subject_readable.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (review_subject_readable.subject_id)::uuid and s."organization_id" = review_subject_readable.tenant)
    else false
  end)
  end, false);
end;
$$;
revoke execute on function "better_supabase"."review_subject_readable"(uuid, text, text) from public, anon, authenticated;

-- Recounts one subject's published reviews into review_stats.
create or replace function "better_supabase"."review_stats_refresh"(tenant uuid, subject_type text, subject_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into "better_supabase"."review_stats" ("tenant_id", "subject_type", "subject_id", "review_count", "rating_total", "histogram", "updated_at")
  select review_stats_refresh.tenant, review_stats_refresh.subject_type, review_stats_refresh.subject_id,
    count(*)::integer, coalesce(sum(x."rating"), 0)::bigint,
    coalesce((select jsonb_object_agg(h.rating::text, h.n) from (
      select y."rating" as rating, count(*) as n from "better_supabase"."reviews" y
      where y."tenant_id" = review_stats_refresh.tenant and y."subject_type" = review_stats_refresh.subject_type
        and y."subject_id" = review_stats_refresh.subject_id and y."status" = 'published'
      group by y."rating"
    ) h), '{}'::jsonb),
    now()
  from "better_supabase"."reviews" x
  where x."tenant_id" = review_stats_refresh.tenant and x."subject_type" = review_stats_refresh.subject_type
    and x."subject_id" = review_stats_refresh.subject_id and x."status" = 'published'
  on conflict ("tenant_id", "subject_type", "subject_id") do update
    set "review_count" = excluded."review_count", "rating_total" = excluded."rating_total",
      "histogram" = excluded."histogram", "updated_at" = excluded."updated_at";
$$;
revoke execute on function "better_supabase"."review_stats_refresh"(uuid, text, text) from public, anon, authenticated;

-- Keeps review_stats in step with every write, including user purges.
create or replace function "better_supabase"."reviews_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform "better_supabase"."review_stats_refresh"(old."tenant_id", old."subject_type", old."subject_id");
  end if;
  if tg_op = 'DELETE' then
    delete from "better_supabase"."moderation_items" x
    where x."tenant_id" = old."tenant_id" and x."subject_type" = 'review' and x."subject_id" = old."id"::text;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform "better_supabase"."review_stats_refresh"(new."tenant_id", new."subject_type", new."subject_id");
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_changed"() from public, anon, authenticated;
create trigger "bsb_reviews_changed"
  after insert or update of "rating", "status" or delete on "better_supabase"."reviews"
  for each row execute function "better_supabase"."reviews_changed"();

-- Writes the caller's review of a subject, or replaces it: one review per
-- user and subject. Under pre-moderation (options.moderation "pre") it
-- waits for publish_review; under "post" it is published at once. verified
-- is true when the orders module shows a paid order for the product.

create or replace function "better_supabase"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_verified boolean;
  v_row "better_supabase"."reviews"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to write a review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if submit_review.rating is null or submit_review.rating not between 1 and 5 then
    raise exception 'rating must be from 1 to 5' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if length(submit_review.body) > 5000 then
    raise exception 'body must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not "better_supabase"."review_subject_readable"(submit_review.tenant, submit_review.subject_type, submit_review.subject_id) then
    raise exception 'not allowed to review this record' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  v_verified := coalesce(submit_review.subject_type = 'product' and submit_review.subject_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and exists (
    select 1 from "better_supabase"."orders" o
    join "better_supabase"."order_lines" l on l."order_id" = o."id"
    where o."tenant_id" = submit_review.tenant and o."customer_id" = v_me
      and o."paid_at" is not null and o."cancelled_at" is null
      and l."product_id" = submit_review.subject_id::uuid
  ), false);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_review_submit"(uuid, text, text, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::integer)', v_hook::oid::regproc)
        using submit_review.tenant, submit_review.subject_type, submit_review.subject_id, submit_review.rating;
    end if;
  end;
  insert into "better_supabase"."reviews" ("tenant_id", "subject_type", "subject_id", "author_id", "author_name", "rating", "title", "body", "status", "verified", "published_at")
  values (submit_review.tenant, submit_review.subject_type, submit_review.subject_id, v_me, nullif(trim(submit_review.author_name), ''), submit_review.rating, nullif(trim(submit_review.title), ''), nullif(trim(submit_review.body), ''), 'pending', v_verified, null)
  on conflict ("tenant_id", "subject_type", "subject_id", "author_id") do update
    set "rating" = excluded."rating", "title" = excluded."title", "body" = excluded."body", "author_name" = excluded."author_name", "verified" = excluded."verified", "status" = excluded."status", "published_at" = excluded."published_at", "rejection_reason" = null, "updated_at" = now()
  returning * into v_row;
  perform "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_me, 'pending');
  perform "better_supabase".emit_event('review.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_review_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "better_supabase"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

-- Deletes a review: its author, or a moderator.
create or replace function "better_supabase"."delete_review"(review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_mine boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = delete_review.review_id for update;
  if not found then
    return false;
  end if;
  v_mine := v_row."author_id" = auth.uid();
  if not (coalesce(v_mine, false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to delete this review' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  delete from "better_supabase"."reviews" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('review.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  perform better_supabase.audit_event(
    event_type => 'review.deleted',
    category => 'data',
    target_type => 'review',
    record_id => v_row."id"::text,
    summary => 'deleted a review',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_review"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_review"(uuid) to authenticated, service_role;

-- Projects a review's moderation item onto the review: visible publishes it,
-- hidden and removed reject it with the item's reason. A decision (from
-- publish_review, reject_review or the moderation block) records
-- review.published or review.rejected and tells the author.
create or replace function "better_supabase"."reviews_moderated"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_claims text;
begin
  update "better_supabase"."reviews" x
  set "status" = case new."status" when 'visible' then 'published' when 'pending' then 'pending' else 'rejected' end,
    "published_at" = case when new."status" = 'visible' then coalesce(x."published_at", now()) end,
    "rejection_reason" = case when new."status" in ('hidden', 'removed') then new."reason" end,
    "updated_at" = now()
  where x."id"::text = new."subject_id" and x."tenant_id" = new."tenant_id"
  returning * into v_row;
  if v_row."id" is null or new."decided_at" is null or old."status" = new."status" then
    return null;
  end if;
  if new."status" = 'visible' then
    perform "better_supabase".emit_event('review.published', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  perform better_supabase.audit_event(
    event_type => 'review.published',
    category => 'data',
    target_type => 'review',
    record_id => v_row."id"::text,
    summary => 'published a review',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified")
  );
  if v_row."author_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'review.published',
      'tenant', v_row."tenant_id",
      'subject_type', v_row."subject_type",
      'subject_id', v_row."subject_id",
      'summary', 'Your review was published',
      'recipients', jsonb_build_array(v_row."author_id"),
      'key', 'review.published:' || v_row."id"::text || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('reviewId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  elsif old."status" not in ('hidden', 'removed') then
    perform "better_supabase".emit_event('review.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  perform better_supabase.audit_event(
    event_type => 'review.rejected',
    category => 'data',
    target_type => 'review',
    record_id => v_row."id"::text,
    summary => 'rejected a review',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified")
  );
  if v_row."author_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'review.rejected',
      'tenant', v_row."tenant_id",
      'subject_type', v_row."subject_type",
      'subject_id', v_row."subject_id",
      'summary', 'Your review was not published',
      'recipients', jsonb_build_array(v_row."author_id"),
      'key', 'review.rejected:' || v_row."id"::text || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('reviewId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_moderated"() from public, anon, authenticated;
create trigger "bsb_reviews_moderated"
  after update of "status", "decided_at" on "better_supabase"."moderation_items"
  for each row when (new."subject_type" = 'review')
  execute function "better_supabase"."reviews_moderated"();

-- The moderation item of a review, created when the review predates it.
create or replace function "better_supabase"."review_moderation_item"(review_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_item uuid;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = review_moderation_item.review_id;
  select x."id" into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'review' and x."subject_id" = v_row."id"::text;
  if v_item is null then
    v_item := "better_supabase"."moderation_track"(v_row."tenant_id", 'review', v_row."id"::text, v_row."author_id",
      case when v_row."status" = 'published' then 'visible' else 'pending' end);
  end if;
  return v_item;
end;
$$;
revoke execute on function "better_supabase"."review_moderation_item"(uuid) from public, anon, authenticated;

-- Publishes a pending or rejected review: approves its moderation item.
create or replace function "better_supabase"."publish_review"(review_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'approve', null, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = publish_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."publish_review"(uuid) from public, anon;
grant execute on function "better_supabase"."publish_review"(uuid) to authenticated, service_role;

-- Rejects a review with an optional reason the author sees: hides its
-- moderation item.
create or replace function "better_supabase"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  perform "better_supabase"."moderation_apply"("better_supabase"."review_moderation_item"(v_row."id"), 'hide', reject_review.reason, false);
  select * into v_row from "better_supabase"."reviews" x where x."id" = reject_review.review_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reject_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reject_review"(uuid, text) to authenticated, service_role;

-- Sets the organization's public reply to a review; null removes it.
create or replace function "better_supabase"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."reviews" x where x."id" = reply_to_review.review_id for update;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if length(reply_to_review.reply) > 5000 then
    raise exception 'reply must be at most 5000 characters' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  update "better_supabase"."reviews" x
  set "reply" = nullif(trim(reply_to_review.reply), ''),
    "replied_by" = case when nullif(trim(reply_to_review.reply), '') is null then null else auth.uid() end,
    "replied_at" = case when nullif(trim(reply_to_review.reply), '') is null then null else now() end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('review.replied', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified"), 'reviews/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reviews');
  perform better_supabase.audit_event(
    event_type => 'review.replied',
    category => 'data',
    target_type => 'review',
    record_id => v_row."id"::text,
    summary => 'replied to a review',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'rating', v_row."rating", 'status', v_row."status", 'verified', v_row."verified")
  );
  if v_row."author_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'review.replied',
      'tenant', v_row."tenant_id",
      'subject_type', v_row."subject_type",
      'subject_id', v_row."subject_id",
      'summary', 'Your review has a reply',
      'recipients', jsonb_build_array(v_row."author_id"),
      'key', 'review.replied:' || v_row."id"::text || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('reviewId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reply_to_review"(uuid, text) to authenticated, service_role;

-- A subject's published reviews, newest first, for anyone who can read the
-- subject (anonymous visitors for a public storefront's products). Author
-- ids stay hidden; mine marks the caller's own review.
create or replace function "better_supabase"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(list_reviews.tenant, list_reviews.subject_type, list_reviews.subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.published desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."published_at" as published, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = list_reviews.tenant and x."subject_type" = list_reviews.subject_type
      and x."subject_id" = list_reviews.subject_id and x."status" = 'published'
      and (list_reviews.before is null or x."published_at" < list_reviews.before)
      and (list_reviews.rating is null or x."rating" = list_reviews.rating)
      and (list_reviews.verified is null or x."verified" = list_reviews.verified)
    order by x."published_at" desc, x."id" desc
    limit least(greatest(coalesce(list_reviews.page_size, 20), 1), 100)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "better_supabase"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

-- A subject's published reviews as a keyset page, newest first (ADR 1077), for
-- anyone who can read the subject. filters must hold subjectType and
-- subjectId, and may hold rating and verified (each a value or a list),
-- search, sort (publishedAt, rating), direction, facet, count, limit, after,
-- offset, paged, total, totalCap. Author ids stay hidden.
create or replace function "better_supabase"."page_reviews"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_reviews.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_subject_type text := nullif(coalesce(v_filters #>> '{subjectType,0}', v_filters ->> 'subjectType'), '');
  v_subject_id text := nullif(coalesce(v_filters #>> '{subjectId,0}', v_filters ->> 'subjectId'), '');
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 20), 1), 100);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if jsonb_typeof(v_filters) <> 'object' or v_subject_type is null or v_subject_id is null then
    raise exception 'filters must name one subjectType and one subjectId' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(page_reviews.tenant, v_subject_type, v_subject_id)) then
    raise exception 'not allowed to read this record''s reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('rating', 'verified') then
      raise exception 'facet is one of rating, verified' using errcode = '22023', hint = 'REVIEW_INVALID';
    end if;
    with s as (
      select (case v_facet when 'rating' then (x."rating"::text)::text when 'verified' then (x."verified"::text)::text end) as v
      from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('publishedAt', 'rating') then
    raise exception 'sort is one of publishedAt, rating' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."created_at") >= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."created_at") > (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."created_at") = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."created_at") asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."created_at"), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."created_at") desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."created_at") >= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", x."created_at") > (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", x."created_at") = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", x."created_at") asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."published_at", x."created_at"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (coalesce(x."published_at", x."created_at"), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", x."created_at") desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rating' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."rating")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (x."rating" >= (v_after ->> 0)::integer and ((x."rating" > (v_after ->> 0)::integer) or (x."rating" = (v_after ->> 0)::integer and x."id" < (v_after ->> 1)::uuid))))
      order by x."rating" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'rating' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REVIEW_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', null::uuid, 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."rating")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
        and (v_after is null or (x."rating", x."id") < ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."rating" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."reviews" x
      where x."tenant_id" = page_reviews.tenant
        and x."subject_type" = v_subject_type
        and x."subject_id" = v_subject_id
        and x."status" = 'published'
        and (not (v_filters -> 'rating' is not null and jsonb_typeof(v_filters -> 'rating') <> 'null' and not (jsonb_typeof(v_filters -> 'rating') = 'array' and jsonb_array_length(v_filters -> 'rating') = 0)) or x."rating"::text = any((case when jsonb_typeof(v_filters -> 'rating') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'rating')) else array[v_filters ->> 'rating'] end)::text[]))
        and (not (v_filters -> 'verified' is not null and jsonb_typeof(v_filters -> 'verified') <> 'null' and not (jsonb_typeof(v_filters -> 'verified') = 'array' and jsonb_array_length(v_filters -> 'verified') = 0)) or x."verified"::text = any((case when jsonb_typeof(v_filters -> 'verified') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'verified')) else array[v_filters ->> 'verified'] end)::text[]))
        and (v_search is null or coalesce(x."title", '') ilike v_search or coalesce(x."body", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_reviews"(uuid, jsonb) from public;
grant execute on function "better_supabase"."page_reviews"(uuid, jsonb) to anon, authenticated, service_role;

-- One review: the caller's own in any status, or a published one of a subject
-- the caller can read (author id hidden).
create or replace function "better_supabase"."get_review"(review_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reviews"%rowtype;
begin
  select * into v_row from "better_supabase"."reviews" x where x."id" = get_review.review_id;
  if not found then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  if coalesce(v_row."author_id" = auth.uid(), false) then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if v_row."status" <> 'published'
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(v_row."tenant_id", v_row."subject_type", v_row."subject_id")) then
    raise exception 'review not found' using errcode = 'P0002', hint = 'REVIEW_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', null::uuid, 'authorName', v_row."author_name", 'mine', coalesce(v_row."author_id" = auth.uid(), false), 'rating', v_row."rating", 'title', v_row."title", 'body', v_row."body", 'status', v_row."status", 'verified', v_row."verified", 'rejectionReason', v_row."rejection_reason", 'reply', v_row."reply", 'repliedAt', v_row."replied_at", 'publishedAt', v_row."published_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_review"(uuid) from public;
grant execute on function "better_supabase"."get_review"(uuid) to anon, authenticated, service_role;
-- The caller's own review of a subject in any status, or null.
create or replace function "better_supabase"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")
  from "better_supabase"."reviews" x
  where x."tenant_id" = my_review.tenant and x."subject_type" = my_review.subject_type
    and x."subject_id" = my_review.subject_id and x."author_id" = auth.uid()
$$;
revoke execute on function "better_supabase"."my_review"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."my_review"(uuid, text, text) to authenticated, service_role;

-- Reviews for moderators, newest first: pending by default. statuses is a list
-- of statuses and matches a review in any of them (ADR 1077); an empty list
-- leaves the status off, and it combines with status by and.

create or replace function "better_supabase"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null, statuses text[] default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', review_queue.tenant, 'reviews.manage'), false)) then
    raise exception 'not allowed to moderate reviews' using errcode = '42501', hint = 'REVIEW_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.created desc, q.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'authorId', x."author_id", 'authorName', x."author_name", 'mine', coalesce(x."author_id" = auth.uid(), false), 'rating', x."rating", 'title', x."title", 'body', x."body", 'status', x."status", 'verified', x."verified", 'rejectionReason', x."rejection_reason", 'reply', x."reply", 'repliedAt', x."replied_at", 'publishedAt', x."published_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
    from "better_supabase"."reviews" x
    where x."tenant_id" = review_queue.tenant
      and (review_queue.status is null or x."status" = review_queue.status)
      and (coalesce(cardinality(review_queue.statuses), 0) = 0 or x."status" in (select s from unnest(review_queue.statuses) s))
      and (review_queue.subject_type is null or x."subject_type" = review_queue.subject_type)
      and (review_queue.subject_id is null or x."subject_id" = review_queue.subject_id)
      and (review_queue.before is null or x."created_at" < review_queue.before)
    order by x."created_at" desc, x."id" desc
    limit least(greatest(coalesce(review_queue.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text, text[]) from public, anon;
grant execute on function "better_supabase"."review_queue"(uuid, text, integer, timestamptz, text, text, text[]) to authenticated, service_role;

-- The rating aggregate of up to 200 subjects of one type, as
-- { subjectId: { count, average, histogram } }, for the subjects the caller
-- can read. Subjects without published reviews are left out.
create or replace function "better_supabase"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x."subject_id", jsonb_build_object(
    'count', x."review_count",
    'average', case when x."review_count" = 0 then null else round(x."rating_total"::numeric / x."review_count", 2) end,
    'histogram', x."histogram"
  )), '{}'::jsonb)
  from "better_supabase"."review_stats" x
  where x."tenant_id" = review_summary.tenant and x."subject_type" = review_summary.subject_type
    and x."subject_id" = any (review_summary.subject_ids[1:200]) and x."review_count" > 0
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."review_subject_readable"(review_summary.tenant, review_summary.subject_type, x."subject_id"))
$$;
revoke execute on function "better_supabase"."review_summary"(uuid, text, text[]) from public;
grant execute on function "better_supabase"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;

-- on with cascade: deleting a subject row deletes its reviews rows.
create or replace function "better_supabase"."reviews_subject_deleted_product"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."reviews" x where x."subject_type" = v_type and x."subject_id" = v_id;
  delete from "better_supabase"."review_stats" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."reviews" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  delete from "better_supabase"."review_stats" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_subject_deleted_product"() from public, anon, authenticated;
create trigger "bsb_reviews_product_cascade"
  after delete on "better_supabase"."products"
  for each row execute function "better_supabase"."reviews_subject_deleted_product"();

create or replace function "better_supabase"."reviews_subject_deleted_product_variant"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."reviews" x where x."subject_type" = v_type and x."subject_id" = v_id;
  delete from "better_supabase"."review_stats" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."reviews" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  delete from "better_supabase"."review_stats" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reviews_subject_deleted_product_variant"() from public, anon, authenticated;
create trigger "bsb_reviews_product_variant_cascade"
  after delete on "better_supabase"."product_variants"
  for each row execute function "better_supabase"."reviews_subject_deleted_product_variant"();

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.reviews deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"review","event_prefix":"review"}');

-- blocks.reviews.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."submit_review"(tenant uuid, subject_type text, subject_id text, rating integer, body text default null, title text default null, author_name text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."submit_review"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."submit_review"(uuid, text, text, integer, text, text, text) from public, anon;
grant execute on function "api"."submit_review"(uuid, text, text, integer, text, text, text) to authenticated, service_role;

create or replace function "api"."delete_review"(review_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_review"($1) $$;
revoke execute on function "api"."delete_review"(uuid) from public, anon;
grant execute on function "api"."delete_review"(uuid) to authenticated, service_role;

create or replace function "api"."publish_review"(review_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_review"($1) $$;
revoke execute on function "api"."publish_review"(uuid) from public, anon;
grant execute on function "api"."publish_review"(uuid) to authenticated, service_role;

create or replace function "api"."reject_review"(review_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reject_review"($1, $2) $$;
revoke execute on function "api"."reject_review"(uuid, text) from public, anon;
grant execute on function "api"."reject_review"(uuid, text) to authenticated, service_role;

create or replace function "api"."reply_to_review"(review_id uuid, reply text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reply_to_review"($1, $2) $$;
revoke execute on function "api"."reply_to_review"(uuid, text) from public, anon;
grant execute on function "api"."reply_to_review"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_reviews"(tenant uuid, subject_type text, subject_id text, page_size integer default 20, before timestamptz default null, rating integer default null, verified boolean default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_reviews"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) from public;
grant execute on function "api"."list_reviews"(uuid, text, text, integer, timestamptz, integer, boolean) to anon, authenticated, service_role;

create or replace function "api"."page_reviews"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."page_reviews"($1, $2) $$;
revoke execute on function "api"."page_reviews"(uuid, jsonb) from public;
grant execute on function "api"."page_reviews"(uuid, jsonb) to anon, authenticated, service_role;

create or replace function "api"."get_review"(review_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_review"($1) $$;
revoke execute on function "api"."get_review"(uuid) from public;
grant execute on function "api"."get_review"(uuid) to anon, authenticated, service_role;

create or replace function "api"."my_review"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."my_review"($1, $2, $3) $$;
revoke execute on function "api"."my_review"(uuid, text, text) from public, anon;
grant execute on function "api"."my_review"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."review_queue"(tenant uuid, status text default 'pending', page_size integer default 50, before timestamptz default null, subject_type text default null, subject_id text default null, statuses text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."review_queue"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."review_queue"(uuid, text, integer, timestamptz, text, text, text[]) from public, anon;
grant execute on function "api"."review_queue"(uuid, text, integer, timestamptz, text, text, text[]) to authenticated, service_role;

create or replace function "api"."review_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."review_summary"($1, $2, $3) $$;
revoke execute on function "api"."review_summary"(uuid, text, text[]) from public;
grant execute on function "api"."review_summary"(uuid, text, text[]) to anon, authenticated, service_role;
