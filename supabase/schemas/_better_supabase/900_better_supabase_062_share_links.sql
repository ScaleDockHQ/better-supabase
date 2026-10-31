-- better-supabase module: share-links
-- @bsb-block share-links@1 managed
-- @bsb-hash sha256:257945b15920d1ec346f8f8ad2fe4a7a216ea2aed22833070c825d39591b42b5
-- Hashed share links, view counts and per-user state. The token is returned once. Resolving a link hashes the token the caller presents, so a stored plaintext token keeps working after it is hashed. A link can take a password, checked with bcrypt and rate-limited per link, and turn off downloads.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."share_links";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."share_links";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."share_links";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."share_links";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."share_links";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."share_links" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "token_hash" text not null unique,
  "role" text not null default 'view',
  "version" integer not null default 1,
  "expires_at" timestamptz,
  "revoked_at" timestamptz,
  "max_uses" integer,
  "created_by" uuid,
  "leaf_id" text
);
alter table "better_supabase"."share_links" add column if not exists "version_id" uuid;
alter table "better_supabase"."share_links" add column if not exists "use_count" integer not null default 0;
alter table "better_supabase"."share_links" add column if not exists "last_used_at" timestamptz;
alter table "better_supabase"."share_links" add column if not exists "password_hash" text;
alter table "better_supabase"."share_links" add column if not exists "download_allowed" boolean not null default true;
alter table "better_supabase"."share_links" enable row level security;
revoke all on "better_supabase"."share_links" from public, anon, authenticated;
grant select on "better_supabase"."share_links" to authenticated;
grant all on "better_supabase"."share_links" to service_role;
create index if not exists "share_links_subject_idx" on "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id");
create table if not exists "better_supabase"."subject_views" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "viewer_kind" text not null,
  "viewer" text,
  "first_viewed_at" timestamptz not null default now(),
  "last_viewed_at" timestamptz not null default now(),
  "view_count" integer not null default 1,
  unique ("tenant_id", "subject_type", "subject_id", "viewer_kind", "viewer")
);
alter table "better_supabase"."subject_views" enable row level security;
revoke all on "better_supabase"."subject_views" from public, anon, authenticated;
grant select on "better_supabase"."subject_views" to authenticated;
grant all on "better_supabase"."subject_views" to service_role;

create table if not exists "better_supabase"."subject_user_state" (
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid not null,
  "starred_at" timestamptz,
  "last_opened_at" timestamptz,
  primary key ("subject_type", "subject_id", "user_id")
);
alter table "better_supabase"."subject_user_state" enable row level security;
revoke all on "better_supabase"."subject_user_state" from public, anon, authenticated;
grant select on "better_supabase"."subject_user_state" to authenticated;
grant all on "better_supabase"."subject_user_state" to service_role;


drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, jsonb);
-- fields: the extra columns (blocks.share-links.options.extraColumns) to set.
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, jsonb);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, jsonb);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, boolean, jsonb);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, text, boolean);
drop function if exists "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, text, boolean, jsonb);
-- password: at least 8 characters; resolve_share_link then needs it.
-- download_allowed: false tells the block that serves the subject not to offer
-- a download.
create or replace function "better_supabase"."create_share_link"(tenant uuid, subject_type text, subject_id text, role text, version_id uuid default null, expires_at timestamptz default null, max_uses integer default null, password text default null, download_allowed boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_subject_ok boolean;
  v_password_hash text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_share_link.tenant, 'share_links.create'), false)) then
    raise exception 'not allowed to share' using errcode = '42501', hint = 'SHARE_FORBIDDEN';
  end if;
  if create_share_link.expires_at is not null and create_share_link.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'SHARE_EXPIRY_INVALID';
  end if;
  if create_share_link.max_uses is not null and create_share_link.max_uses < 1 then
    raise exception 'max_uses must be at least 1' using errcode = '22023', hint = 'SHARE_MAX_USES_INVALID';
  end if;
  if create_share_link.password is not null and char_length(create_share_link.password) < 8 then
    raise exception 'a link password needs at least 8 characters' using errcode = '22023', hint = 'SHARE_LINK_PASSWORD_INVALID';
  end if;

  if coalesce(create_share_link.role, 'view') <> all (case create_share_link.subject_type
    when 'ai-chat' then array['view']::text[]
    when 'calendar' then array['view']::text[]
    when 'booking_service' then array['view']::text[]
    when 'drive_node' then array['view', 'download', 'upload']::text[]
    when 'form' then array['respond']::text[]
    else array[coalesce(create_share_link.role, 'view')]
  end) then
    raise exception 'this subject type''s links can''t carry that role' using errcode = '22023', hint = 'SHARE_LINK_ROLE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    v_subject_ok := case create_share_link.subject_type
    when 'ai-chat' then exists (select 1 from "better_supabase".ai_chats s where s.id::text = create_share_link.subject_id and s.organization_id::text = create_share_link.tenant::text and s.owner_id = auth.uid())
    when 'calendar' then exists (select 1 from "better_supabase"."calendars" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'booking_service' then exists (select 1 from "better_supabase"."booking_services" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    when 'drive_node' then "better_supabase"."drive_share_link_allowed"(create_share_link.subject_id::text, create_share_link.tenant::text, coalesce(create_share_link.role, 'view'))
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id"::text = create_share_link.subject_id and s."tenant_id"::text = create_share_link.tenant::text)
    else case create_share_link.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'inspections.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'dam.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'customers.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_share_link.subject_id)::uuid and s."tenant_id" = create_share_link.tenant) and coalesce(better_supabase.can('tenant', create_share_link.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_share_link.subject_id)::uuid and s."organization_id" = create_share_link.tenant)
    else null
  end
  end;
    if v_subject_ok is null then
      raise exception 'this subject type can''t be shared' using errcode = '22023', hint = 'SHARE_SUBJECT_UNKNOWN';
    end if;
    if not v_subject_ok then
      raise exception 'the subject does not exist in this organization' using errcode = 'P0002', hint = 'SHARE_SUBJECT_NOT_FOUND';
    end if;
  end if;
  if create_share_link.version_id is not null then
    declare
      v_version jsonb := "better_supabase"."get_version"(create_share_link.version_id);
    begin
      if v_version ->> 'subjectType' is distinct from create_share_link.subject_type
        or v_version ->> 'subjectId' is distinct from create_share_link.subject_id then
        raise exception 'the version belongs to another subject' using errcode = '22023', hint = 'SHARE_VERSION_INVALID';
      end if;
    end;
  end if;
  if create_share_link.subject_type in ('calendar') then
    update "better_supabase"."share_links" x set "revoked_at" = now()
    where x."tenant_id" = create_share_link.tenant and x."subject_type" = create_share_link.subject_type
      and x."subject_id" = create_share_link.subject_id and x."created_by" is not distinct from auth.uid() and x."revoked_at" is null;
  end if;
  if create_share_link.password is not null then
    v_password_hash := extensions.crypt(create_share_link.password, extensions.gen_salt('bf'));
  end if;
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "expires_at", "max_uses", "created_by", "version_id", "password_hash", "download_allowed")
  values (create_share_link.tenant, create_share_link.subject_type, create_share_link.subject_id, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), coalesce(create_share_link.role, 'view'), create_share_link.expires_at, create_share_link.max_uses, auth.uid(), create_share_link.version_id, v_password_hash, coalesce(create_share_link.download_allowed, true))
  returning "id" into v_id;
  perform "better_supabase".emit_event('share_link.created', jsonb_build_object('organizationId', create_share_link.tenant, 'id', v_id, 'subjectType', create_share_link.subject_type, 'subjectId', create_share_link.subject_id), 'share-links/' || v_id::text, (create_share_link.tenant)::text, null, 'better-supabase/share-links');
  return jsonb_build_object('id', v_id, 'token', v_token);
end;
$$;
revoke execute on function "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, boolean) from public, anon;
grant execute on function "better_supabase"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, boolean) to authenticated, service_role;

-- The link's creator, or a caller who may create links in its tenant, may
-- revoke it. Anyone else gets SHARE_NOT_FOUND, so ids can't be probed.
create or replace function "better_supabase"."revoke_share_link"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_creator uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "created_by" into v_tenant, v_creator
  from "better_supabase"."share_links"
  where "id" = revoke_share_link.id and "revoked_at" is null
  for update;
  if not found or not (
    auth.role() = 'service_role'
    or (v_creator is not null and coalesce(v_creator = auth.uid(), false))
    or coalesce(better_supabase.can('tenant', v_tenant, 'share_links.create'), false)
  ) then
    raise exception 'share link not found' using errcode = 'P0002', hint = 'SHARE_NOT_FOUND';
  end if;
  update "better_supabase"."share_links" set "revoked_at" = now()
  where "id" = revoke_share_link.id;
  perform "better_supabase".emit_event('share_link.revoked', jsonb_build_object('organizationId', v_tenant, 'id', revoke_share_link.id), 'share-links/' || revoke_share_link.id::text, (v_tenant)::text, null, 'better-supabase/share-links');
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_share_link"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_share_link"(uuid) to authenticated, service_role;

-- Each resolve counts one use, so a link with max_uses stops resolving once
-- it is spent. The row lock keeps two concurrent resolves from both taking
-- the last use. A link with a password returns only
-- { "passwordRequired": true } until the call passes the password, and
-- counts no use for it.
drop function if exists "better_supabase"."resolve_share_link"(text);
create or replace function "better_supabase"."resolve_share_link"(token text, password text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_link "better_supabase"."share_links"%rowtype;
  v_retry integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_link
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(resolve_share_link.token, 'utf8'), 'sha256'), 'hex')
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
  for update;
  if not found then
    return null;
  end if;
  if v_link."password_hash" is not null then
    if resolve_share_link.password is null then
      return jsonb_build_object('passwordRequired', true);
    end if;
    select greatest(1, ceil(extract(epoch from k."window_start" + k."period" - now()))::integer) into v_retry
    from "better_supabase"."rate_limits" k
    where k."scope" = 'share_link_password' and k."key" = v_link."id"::text
      and k."window_start" + k."period" > now()
      and k."hits" >= coalesce((select q."max_requests" from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password'), 10);
    if v_retry is not null then
      raise exception 'too many wrong passwords for this link' using errcode = 'BS429', hint = 'SHARE_LINK_RATE_LIMITED', detail = 'retry after ' || v_retry;
    end if;
    if extensions.crypt(resolve_share_link.password, v_link."password_hash") <> v_link."password_hash" then
      perform 1 from "better_supabase"."hit_rate_limit"('share_link_password', v_link."id"::text, case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password') then null else 10 end, case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'share_link_password') then null else interval '15 minutes' end);
      return jsonb_build_object('passwordRequired', true);
    end if;
  end if;
  update "better_supabase"."share_links" set "use_count" = "use_count" + 1, "last_used_at" = now() where "id" = v_link."id";
  return jsonb_build_object('id', v_link."id", 'organizationId', v_link."tenant_id", 'subjectType', v_link."subject_type", 'subjectId', v_link."subject_id", 'role', v_link."role", 'versionId', v_link."version_id", 'expiresAt', v_link."expires_at", 'maxUses', v_link."max_uses", 'downloadAllowed', v_link."download_allowed", 'passwordRequired', v_link."password_hash" is not null);
end;
$$;
revoke all on function "better_supabase"."resolve_share_link"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."resolve_share_link"(text, text) to anon, authenticated, service_role;

create or replace function "better_supabase"."record_view"(tenant uuid, subject_type text, subject_id text, viewer_kind text, viewer text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or record_view.tenant in (select better_supabase.member_organization_ids())) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'SHARE_FORBIDDEN';
  end if;
  insert into "better_supabase"."subject_views" ("tenant_id", "subject_type", "subject_id", "viewer_kind", "viewer")
  values (record_view.tenant, record_view.subject_type, record_view.subject_id, record_view.viewer_kind, record_view.viewer)
  on conflict ("tenant_id", "subject_type", "subject_id", "viewer_kind", "viewer")
  do update set "last_viewed_at" = now(), "view_count" = "better_supabase"."subject_views"."view_count" + 1;
  perform "better_supabase".emit_event('subject.viewed', jsonb_build_object('organizationId', record_view.tenant, 'subjectType', record_view.subject_type, 'subjectId', record_view.subject_id), 'views/' || record_view.subject_type || '/' || record_view.subject_id, (record_view.tenant)::text, null, 'better-supabase/share-links');
  return true;
end;
$$;
revoke execute on function "better_supabase"."record_view"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_view"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_share_links"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'role', l."role", 'expiresAt', l."expires_at", 'revokedAt', l."revoked_at", 'downloadAllowed', l."download_allowed", 'passwordRequired', l."password_hash" is not null)), '[]'::jsonb)
  from "better_supabase"."share_links" l
  where l."subject_type" = list_share_links.subject_type
    and l."subject_id" = list_share_links.subject_id
    and (
      auth.role() = 'service_role'
      or l."created_by" = (select auth.uid())
      or l."tenant_id" in (select better_supabase.tenant_ids_with('share_links.read'))
    )
$$;
revoke execute on function "better_supabase"."list_share_links"(text, text) from public, anon;
grant execute on function "better_supabase"."list_share_links"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."set_user_state"(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  insert into "better_supabase"."subject_user_state" ("subject_type", "subject_id", "user_id", "starred_at", "last_opened_at")
  values (set_user_state.subject_type, set_user_state.subject_id, auth.uid(), case when set_user_state.starred then now() else null end, now())
  on conflict ("subject_type", "subject_id", "user_id")
  do update set "starred_at" = excluded."starred_at", "last_opened_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_user_state"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_user_state"(text, text, boolean) to authenticated, service_role;

-- ai-chat sharing is this block. The old functions stay callable and write
-- share_links instead of ai_chat_shares.
do $$
begin
  if to_regclass('"better_supabase".ai_chat_shares') is not null then
    insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "created_by", "leaf_id")
    select c.organization_id, 'ai-chat', s.chat_id::text, s.token_hash, s.created_by, s.leaf_id
    from "better_supabase".ai_chat_shares s
    join "better_supabase".ai_chats c on c.id = s.chat_id
    on conflict ("token_hash") do nothing;
  end if;
end;
$$;
create or replace function "better_supabase"."share_ai_chat"(chat uuid, leaf text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tenant uuid;
  v_owner uuid;
  v_leaf text;
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select organization_id, owner_id, current_leaf_id into v_tenant, v_owner, v_leaf
  from "better_supabase".ai_chats where id = share_ai_chat.chat;
  if not found or v_owner is distinct from auth.uid() then
    raise exception 'no chat' using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_leaf);
  insert into "better_supabase"."share_links" ("tenant_id", "subject_type", "subject_id", "token_hash", "role", "created_by", "leaf_id")
  values (v_tenant, 'ai-chat', share_ai_chat.chat::text, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), 'view', auth.uid(), v_leaf)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf);
end;
$$;
revoke execute on function "better_supabase"."share_ai_chat"(uuid, text) from public, anon;
grant execute on function "better_supabase"."share_ai_chat"(uuid, text) to authenticated, service_role;
create or replace function "better_supabase"."revoke_ai_chat_share"(id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  return "better_supabase"."revoke_share_link"(revoke_ai_chat_share.id);
end;
$$;
create or replace function "better_supabase"."list_ai_chat_shares"(chat uuid)
returns jsonb
language sql stable security definer set search_path = '' as $$
  select "better_supabase"."list_share_links"('ai-chat', list_ai_chat_shares.chat::text)
$$;
create or replace function "better_supabase"."get_shared_ai_chat"(token text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_subject text;
  v_tenant text;
  v_leaf text;
  v_chat_id uuid;
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select l."subject_id", l."tenant_id"::text, l."leaf_id"
    into v_subject, v_tenant, v_leaf
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(get_shared_ai_chat.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'ai-chat'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if not found or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_chat_id := v_subject::uuid;
  -- The chat must still live in the tenant the link was created in.
  if not exists (select 1 from "better_supabase".ai_chats where id = v_chat_id and organization_id::text = v_tenant) then
    return null;
  end if;
  return jsonb_build_object(
    'chat', (select jsonb_build_object('id', id, 'title', title, 'model', model, 'created_at', created_at) from "better_supabase".ai_chats where id = v_chat_id),
    'leaf_id', v_leaf,
    'messages', "better_supabase"."ai_message_path_of"(v_chat_id, v_leaf, false)
  );
end;
$$;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."share_links";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."share_links";
create policy bsb_tenant_scope_select on "better_supabase"."share_links" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."share_links";
create policy bsb_tenant_scope_insert on "better_supabase"."share_links" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."share_links";
create policy bsb_tenant_scope_update on "better_supabase"."share_links" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."share_links";
create policy bsb_tenant_scope_delete on "better_supabase"."share_links" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.share-links.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_share_link"(uuid, text, text, text);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, jsonb);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, jsonb);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, jsonb);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, boolean, jsonb);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, text, boolean);
drop function if exists "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, text, boolean, jsonb);
drop function if exists "api"."resolve_share_link"(text);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."create_share_link"(tenant uuid, subject_type text, subject_id text, role text, version_id uuid default null, expires_at timestamptz default null, max_uses integer default null, password text default null, download_allowed boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_share_link"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, boolean) from public, anon;
grant execute on function "api"."create_share_link"(uuid, text, text, text, uuid, timestamptz, integer, text, boolean) to authenticated, service_role;

create or replace function "api"."revoke_share_link"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_share_link"($1) $$;
revoke execute on function "api"."revoke_share_link"(uuid) from public, anon;
grant execute on function "api"."revoke_share_link"(uuid) to authenticated, service_role;

create or replace function "api"."resolve_share_link"(token text, password text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_share_link"($1, $2) $$;
revoke execute on function "api"."resolve_share_link"(text, text) from public;
grant execute on function "api"."resolve_share_link"(text, text) to anon, authenticated, service_role;

create or replace function "api"."record_view"(tenant uuid, subject_type text, subject_id text, viewer_kind text, viewer text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_view"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."record_view"(uuid, text, text, text, text) from public, anon;
grant execute on function "api"."record_view"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "api"."list_share_links"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_share_links"($1, $2) $$;
revoke execute on function "api"."list_share_links"(text, text) from public, anon;
grant execute on function "api"."list_share_links"(text, text) to authenticated, service_role;

create or replace function "api"."set_user_state"(subject_type text, subject_id text, starred boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_user_state"($1, $2, $3) $$;
revoke execute on function "api"."set_user_state"(text, text, boolean) from public, anon;
grant execute on function "api"."set_user_state"(text, text, boolean) to authenticated, service_role;

create or replace function "api"."share_ai_chat"(chat uuid, leaf text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."share_ai_chat"($1, $2) $$;
revoke execute on function "api"."share_ai_chat"(uuid, text) from public, anon;
grant execute on function "api"."share_ai_chat"(uuid, text) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
