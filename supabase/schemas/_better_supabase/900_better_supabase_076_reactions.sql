-- better-supabase module: reactions
-- @bsb-block reactions@2 managed
-- @bsb-hash sha256:f16c76e7b277c54c32c54ba7db25e497aef3b7900fcc1f4b307d622d274eae53
-- Emoji reactions and up or down votes on any subject and on messages, with per-tenant custom emoji, counts and a vote score per subject under the subject's own read rules and a realtime topic per tenant.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."reactions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reactions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reactions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reactions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reactions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."reaction_scores";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."reaction_scores";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reaction_scores";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."reaction_scores";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reaction_scores";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."custom_emoji";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."custom_emoji";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."custom_emoji";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."custom_emoji";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."custom_emoji";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."reactions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "actor" text not null,
  "user_id" uuid,
  "kind" text not null default 'emoji' check ("kind" in ('emoji', 'vote')),
  "emoji" text not null check (length("emoji") between 1 and 64 and "emoji" !~ '\s'),
  -- A vote's direction; an emoji counts once.
  "value" smallint not null default 1 check ("value" in (-1, 1)),
  "created_at" timestamptz not null default now(),
  check ("kind" = 'emoji' and "value" = 1 or "kind" = 'vote' and "emoji" = 'vote')
);
create unique index if not exists "reactions_actor_idx" on "better_supabase"."reactions" ("subject_type", "subject_id", "actor", "kind", "emoji");
create index if not exists "reactions_tenant_idx" on "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id");
create index if not exists "reactions_user_idx" on "better_supabase"."reactions" ("user_id");
alter table "better_supabase"."reactions" enable row level security;
revoke all on "better_supabase"."reactions" from anon;
grant select, insert, delete on "better_supabase"."reactions" to authenticated;
grant all on "better_supabase"."reactions" to service_role;

-- Each subject's vote score (up minus down), kept by reactions_tally so lists
-- can sort by it.
create table if not exists "better_supabase"."reaction_scores" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "score" integer not null default 0,
  "up" integer not null default 0 check ("up" >= 0),
  "down" integer not null default 0 check ("down" >= 0),
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "subject_type", "subject_id")
);
create index if not exists "reaction_scores_rank_idx" on "better_supabase"."reaction_scores" ("tenant_id", "subject_type", "score" desc);
alter table "better_supabase"."reaction_scores" enable row level security;
revoke all on "better_supabase"."reaction_scores" from public, anon, authenticated;
grant select on "better_supabase"."reaction_scores" to authenticated;
grant all on "better_supabase"."reaction_scores" to service_role;

create table if not exists "better_supabase"."custom_emoji" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shortcode" text not null check ("shortcode" ~ '^[a-z0-9_+-]{1,32}$'),
  "attachment_id" uuid,
  "url" text check ("url" ~ '^https://'),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "shortcode"),
  check ("attachment_id" is not null or "url" is not null)
);
alter table "better_supabase"."custom_emoji" enable row level security;
revoke all on "better_supabase"."custom_emoji" from public, anon, authenticated;
grant select on "better_supabase"."custom_emoji" to authenticated;
grant all on "better_supabase"."custom_emoji" to service_role;
drop policy if exists custom_emoji_read on "better_supabase"."custom_emoji";
create policy custom_emoji_read on "better_supabase"."custom_emoji"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('reactions.read')));

-- Whether the caller sees the subject. It runs as the caller, so the subject
-- tables' policies apply. plpgsql, so a subject table a later module creates
-- (messages) binds late.
create or replace function "better_supabase"."reaction_subject_visible"(subject_type text, subject_id text, tenant uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return case reaction_subject_visible.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'forms.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'manufacturing.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null and (coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    else false
  end;
end;
$$;
revoke execute on function "better_supabase"."reaction_subject_visible"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."reaction_subject_visible"(text, text, uuid) to authenticated, service_role;

drop policy if exists reactions_read on "better_supabase"."reactions";
create policy reactions_read on "better_supabase"."reactions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('reactions.read')) and "better_supabase"."reaction_subject_visible"("subject_type", "subject_id", "tenant_id"));
drop policy if exists reactions_insert on "better_supabase"."reactions";
create policy reactions_insert on "better_supabase"."reactions"
  for insert to authenticated
  with check (("user_id" = (select auth.uid())
    and "actor" = (select auth.uid())::text
    and "tenant_id" in (select better_supabase.tenant_ids_with('reactions.create'))
    and "better_supabase"."reaction_subject_visible"("subject_type", "subject_id", "tenant_id")) and (select better_supabase.actor_may_write()));
drop policy if exists reactions_delete on "better_supabase"."reactions";
create policy reactions_delete on "better_supabase"."reactions"
  for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

drop policy if exists reaction_scores_read on "better_supabase"."reaction_scores";
create policy reaction_scores_read on "better_supabase"."reaction_scores"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('reactions.read')) and "better_supabase"."reaction_subject_visible"("subject_type", "subject_id", "tenant_id"));

drop trigger if exists "bsb_reactions_check" on "better_supabase"."reactions";
drop trigger if exists "bsb_reactions_tally" on "better_supabase"."reactions";
drop trigger if exists "bsb_reactions_changed" on "better_supabase"."reactions";

-- A custom emoji's :shortcode: must exist in the reaction's tenant.
create or replace function "better_supabase"."reactions_check"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."emoji" ~ '^:[a-z0-9_+-]{1,32}:$' and not exists (
    select 1 from "better_supabase"."custom_emoji" x
    where x."tenant_id" = new."tenant_id" and x."shortcode" = trim(both ':' from new."emoji")
  ) then
    raise exception 'unknown custom emoji' using errcode = '22023', hint = 'REACTION_INVALID';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."reactions_check"() from public, anon, authenticated;
create trigger "bsb_reactions_check"
  before insert on "better_supabase"."reactions"
  for each row execute function "better_supabase"."reactions_check"();

-- Records reaction.added and reaction.removed, then tells the tenant's topic
-- which subject changed. The payload carries ids only.
create or replace function "better_supabase"."reactions_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reactions"%rowtype;
begin
  if current_setting('better_supabase.bsb_reactions_backfill', true) = 'on' then
    return null;
  end if;
  if tg_op = 'INSERT' then
    v_row := new;
    perform "better_supabase".emit_event('reaction.added', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'emoji', v_row."emoji", 'actor', v_row."actor", 'kind', v_row."kind", 'value', v_row."value"), 'reactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reactions');
  else
    v_row := old;
    perform "better_supabase".emit_event('reaction.removed', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'emoji', v_row."emoji", 'actor', v_row."actor", 'kind', v_row."kind", 'value', v_row."value"), 'reactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/reactions');
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'reactions:' || v_row."tenant_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reactions_changed"() from public, anon, authenticated;
create trigger "bsb_reactions_changed"
  after insert or delete on "better_supabase"."reactions"
  for each row execute function "better_supabase"."reactions_changed"();

-- Keeps reaction_scores in step with the vote rows; a subject without votes
-- has no row.
create or replace function "better_supabase"."reactions_tally"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."reactions"%rowtype;
  v_sign integer;
begin
  if tg_op = 'INSERT' then
    v_row := new;
    v_sign := 1;
  else
    v_row := old;
    v_sign := -1;
  end if;
  if v_row."kind" <> 'vote' then
    return null;
  end if;
  insert into "better_supabase"."reaction_scores" as x ("tenant_id", "subject_type", "subject_id", "score", "up", "down")
  values (v_row."tenant_id", v_row."subject_type", v_row."subject_id", v_sign * v_row."value",
    case when v_row."value" > 0 then greatest(v_sign, 0) else 0 end,
    case when v_row."value" < 0 then greatest(v_sign, 0) else 0 end)
  on conflict ("tenant_id", "subject_type", "subject_id") do update set
    "score" = x."score" + v_sign * v_row."value",
    "up" = x."up" + case when v_row."value" > 0 then v_sign else 0 end,
    "down" = x."down" + case when v_row."value" < 0 then v_sign else 0 end,
    "updated_at" = now();
  delete from "better_supabase"."reaction_scores" x
  where x."tenant_id" = v_row."tenant_id" and x."subject_type" = v_row."subject_type"
    and x."subject_id" = v_row."subject_id" and x."up" = 0 and x."down" = 0;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reactions_tally"() from public, anon, authenticated;
create trigger "bsb_reactions_tally"
  after insert or delete on "better_supabase"."reactions"
  for each row execute function "better_supabase"."reactions_tally"();

-- One subject's reactions under the read policy: emoji, count, whether the
-- caller reacted and the first ten actors, most used first.
create or replace function "better_supabase"."reaction_list"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('emoji', g.emoji, 'count', g.n, 'reacted', g.mine, 'actors', g.actors) order by g.n desc, g.first, g.emoji), '[]'::jsonb)
  from (
    select r."emoji" as emoji, count(*)::integer as n, min(r."created_at") as first,
      coalesce(bool_or(r."user_id" = (select auth.uid())), false) as mine,
      (array_agg(r."actor" order by r."created_at"))[1:10] as actors
    from "better_supabase"."reactions" r
    where r."tenant_id" = reaction_list.tenant
      and r."subject_type" = reaction_list.subject_type
      and r."subject_id" = reaction_list.subject_id
      and r."kind" = 'emoji'
    group by r."emoji"
  ) g
$$;
revoke execute on function "better_supabase"."reaction_list"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."reaction_list"(uuid, text, text) to authenticated, service_role;

-- Adds (present) or removes the caller's reaction, then returns the
-- subject's reactions. It runs as the caller: the insert and delete
-- policies check the permission and that the caller sees the subject.
-- The service role passes the actor (default 'service').
create or replace function "better_supabase"."react"(tenant uuid, subject_type text, subject_id text, emoji text, present boolean default true, actor text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_actor text;
  v_user uuid;
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_actor := coalesce(react.actor, 'service');
  elsif react.actor is not null then
    raise exception 'only the service role reacts for another actor' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  elsif not (coalesce(better_supabase.can('tenant', react.tenant, 'reactions.create'), false) and "better_supabase"."reaction_subject_visible"(react.subject_type, react.subject_id, react.tenant)) then
    raise exception 'not allowed to react to this record' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  else
    v_user := (select auth.uid());
    v_actor := v_user::text;
  end if;
  if react.emoji is null or length(react.emoji) not between 1 and 64 or react.emoji ~ '\s' then
    raise exception 'emoji must be 1 to 64 characters without spaces' using errcode = '22023', hint = 'REACTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_react"(uuid, text, text, text, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::boolean)', v_hook::oid::regproc)
        using react.tenant, react.subject_type, react.subject_id, react.emoji, coalesce(react.present, true);
    end if;
  end;
  if coalesce(react.present, true) then
    insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "emoji")
    values (react.tenant, react.subject_type, react.subject_id, v_actor, v_user, react.emoji)
    on conflict do nothing;
  else
    delete from "better_supabase"."reactions" r
    where r."subject_type" = react.subject_type
      and r."subject_id" = react.subject_id
      and r."tenant_id" = react.tenant
      and r."actor" = v_actor
      and r."kind" = 'emoji'
      and r."emoji" = react.emoji;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_react"(uuid, text, text, text, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::boolean)', v_hook::oid::regproc)
        using react.tenant, react.subject_type, react.subject_id, react.emoji, coalesce(react.present, true);
    end if;
  end;
  return "better_supabase"."reaction_list"(react.tenant, react.subject_type, react.subject_id);
end;
$$;
revoke execute on function "better_supabase"."react"(uuid, text, text, text, boolean, text) from public, anon;
grant execute on function "better_supabase"."react"(uuid, text, text, text, boolean, text) to authenticated, service_role;

-- One subject's vote score under the read policy, with the caller's vote
-- (1, -1 or 0).
create or replace function "better_supabase"."vote_tally"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'score', coalesce(x."score", 0),
    'up', coalesce(x."up", 0),
    'down', coalesce(x."down", 0),
    'vote', coalesce((
      select r."value" from "better_supabase"."reactions" r
      where r."tenant_id" = vote_tally.tenant and r."subject_type" = vote_tally.subject_type
        and r."subject_id" = vote_tally.subject_id and r."kind" = 'vote'
        and r."user_id" = (select auth.uid())
    ), 0)
  )
  from (select 1) one
  left join "better_supabase"."reaction_scores" x on x."tenant_id" = vote_tally.tenant
    and x."subject_type" = vote_tally.subject_type and x."subject_id" = vote_tally.subject_id
$$;
revoke execute on function "better_supabase"."vote_tally"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."vote_tally"(uuid, text, text) to authenticated, service_role;

-- Sets the caller's vote on a subject: 1 up, -1 down, 0 clears it. Returns
-- the subject's tally. It runs as the caller, like react; the service role
-- passes the actor (default 'service').
create or replace function "better_supabase"."vote"(tenant uuid, subject_type text, subject_id text, value integer, actor text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_actor text;
  v_user uuid;
begin
  if vote.value is null or vote.value not in (-1, 0, 1) then
    raise exception 'a vote is 1, -1 or 0' using errcode = '22023', hint = 'REACTION_INVALID';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_actor := coalesce(vote.actor, 'service');
  elsif vote.actor is not null then
    raise exception 'only the service role votes for another actor' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  elsif not (coalesce(better_supabase.can('tenant', vote.tenant, 'reactions.create'), false) and "better_supabase"."reaction_subject_visible"(vote.subject_type, vote.subject_id, vote.tenant)) then
    raise exception 'not allowed to react to this record' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  else
    v_user := (select auth.uid());
    v_actor := v_user::text;
  end if;
  if exists (
    select 1 from "better_supabase"."reactions" r
    where r."subject_type" = vote.subject_type and r."subject_id" = vote.subject_id
      and r."tenant_id" = vote.tenant and r."actor" = v_actor
      and r."kind" = 'vote' and r."value" = vote.value
  ) then
    return "better_supabase"."vote_tally"(vote.tenant, vote.subject_type, vote.subject_id);
  end if;
  delete from "better_supabase"."reactions" r
  where r."subject_type" = vote.subject_type and r."subject_id" = vote.subject_id
    and r."tenant_id" = vote.tenant and r."actor" = v_actor and r."kind" = 'vote';
  if vote.value <> 0 then
    insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "kind", "emoji", "value")
    values (vote.tenant, vote.subject_type, vote.subject_id, v_actor, v_user, 'vote', 'vote', vote.value);
  end if;
  return "better_supabase"."vote_tally"(vote.tenant, vote.subject_type, vote.subject_id);
end;
$$;
revoke execute on function "better_supabase"."vote"(uuid, text, text, integer, text) from public, anon;
grant execute on function "better_supabase"."vote"(uuid, text, text, integer, text) to authenticated, service_role;

-- The vote tallies of many subjects of one type, as { subjectId: tally }.
create or replace function "better_supabase"."vote_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "better_supabase"."vote_tally"(vote_summary.tenant, vote_summary.subject_type, s.id)), '{}'::jsonb)
  from (select distinct unnest(vote_summary.subject_ids[1:200]) as id) s
$$;
revoke execute on function "better_supabase"."vote_summary"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."vote_summary"(uuid, text, text[]) to authenticated, service_role;

-- The reactions of many subjects of one type, as { subjectId: [...] }.
create or replace function "better_supabase"."reaction_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(s.id, "better_supabase"."reaction_list"(reaction_summary.tenant, reaction_summary.subject_type, s.id)), '{}'::jsonb)
  from (select distinct unnest(reaction_summary.subject_ids[1:200]) as id) s
$$;
revoke execute on function "better_supabase"."reaction_summary"(uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."reaction_summary"(uuid, text, text[]) to authenticated, service_role;

create or replace function "better_supabase"."save_custom_emoji"(tenant uuid, shortcode text, attachment_id uuid default null, url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."custom_emoji"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_custom_emoji.tenant, 'reactions.manage'), false)) then
    raise exception 'not allowed to manage custom emoji' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  end if;
  insert into "better_supabase"."custom_emoji" ("tenant_id", "shortcode", "attachment_id", "url", "created_by")
  values (save_custom_emoji.tenant, lower(trim(both ':' from save_custom_emoji.shortcode)), save_custom_emoji.attachment_id, save_custom_emoji.url, auth.uid())
  on conflict ("tenant_id", "shortcode") do update
    set "attachment_id" = excluded."attachment_id", "url" = excluded."url"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'shortcode', v_row."shortcode", 'attachmentId', v_row."attachment_id", 'url', v_row."url", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."save_custom_emoji"(uuid, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."save_custom_emoji"(uuid, text, uuid, text) to authenticated, service_role;

-- Deletes a custom emoji and the reactions that used it.
create or replace function "better_supabase"."delete_custom_emoji"(emoji_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."custom_emoji"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."custom_emoji" x where x."id" = delete_custom_emoji.emoji_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'reactions.manage'), false)) then
    raise exception 'not allowed to manage custom emoji' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  end if;
  delete from "better_supabase"."reactions" r
    where r."tenant_id" = v_row."tenant_id" and r."emoji" = ':' || v_row."shortcode" || ':';
  delete from "better_supabase"."custom_emoji" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_custom_emoji"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_custom_emoji"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_custom_emoji"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'shortcode', x."shortcode", 'attachmentId', x."attachment_id", 'url', x."url", 'createdAt', x."created_at") order by x."shortcode"), '[]'::jsonb)
  from "better_supabase"."custom_emoji" x
  where x."tenant_id" = list_custom_emoji.tenant
$$;
revoke execute on function "better_supabase"."list_custom_emoji"(uuid) from public, anon;
grant execute on function "better_supabase"."list_custom_emoji"(uuid) to authenticated, service_role;

-- Members join reactions:{tenant}; payloads name the subject that changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_reactions_receive on realtime.messages;
create policy bsb_reactions_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'reactions:%'
        and substr((select realtime.topic()), 11) in (select x::text from better_supabase.tenant_ids_with('reactions.read') x));
  end if;
end;
$do$;

-- on with cascade: deleting a subject row deletes its reactions rows.
create or replace function "better_supabase"."reactions_subject_deleted"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id;
  return null;
end;
$$;
revoke execute on function "better_supabase"."reactions_subject_deleted"() from public, anon, authenticated;

drop trigger if exists "bsb_reactions_product_cascade" on "better_supabase"."products";
create trigger "bsb_reactions_product_cascade"
  after delete on "better_supabase"."products"
  for each row execute function "better_supabase"."reactions_subject_deleted"('product', 'id');

drop trigger if exists "bsb_reactions_product_variant_cascade" on "better_supabase"."product_variants";
create trigger "bsb_reactions_product_variant_cascade"
  after delete on "better_supabase"."product_variants"
  for each row execute function "better_supabase"."reactions_subject_deleted"('product_variant', 'id');

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."reactions_subject_merge"(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.activities' then array['activity'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.leases' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.compliance_policies' then array['compliance_policy'] when 'better_supabase.qualification_types' then array['qualification_type'] when 'better_supabase.risks' then array['risk'] when 'better_supabase.cases' then array['case'] when 'better_supabase.inspections' then array['inspection'] when 'better_supabase.inspection_programs' then array['inspection_program'] when 'better_supabase.inspection_findings' then array['inspection_finding'] when 'better_supabase.forms' then array['form'] when 'better_supabase.production_orders' then array['production_order'] when 'better_supabase.work_centers' then array['work_center'] when 'better_supabase.care_plans' then array['care_plan'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.change_requests' then array['change_request'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    delete from "better_supabase"."reactions" x where x."subject_type" = v_type and x."subject_id" = v_drop and exists (select 1 from "better_supabase"."reactions" y where y."subject_type" = v_type and y."subject_id" = v_keep and y."actor" is not distinct from x."actor" and y."emoji" is not distinct from x."emoji");
    update "better_supabase"."reactions" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."reactions_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."reactions_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

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
drop policy if exists bsb_tenant_scope on "better_supabase"."reactions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."reactions";
create policy bsb_tenant_scope_select on "better_supabase"."reactions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('reactions.read')) and "better_supabase"."reaction_subject_visible"("subject_type", "subject_id", "tenant_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reactions";
create policy bsb_tenant_scope_insert on "better_supabase"."reactions" as restrictive
  for insert to public
  with check (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid())
    and "actor" = (select auth.uid())::text
    and "tenant_id" in (select better_supabase.tenant_ids_with('reactions.create'))
    and "better_supabase"."reaction_subject_visible"("subject_type", "subject_id", "tenant_id"))
  );
drop policy if exists bsb_tenant_scope_update on "better_supabase"."reactions";
create policy bsb_tenant_scope_update on "better_supabase"."reactions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reactions";
create policy bsb_tenant_scope_delete on "better_supabase"."reactions" as restrictive
  for delete to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."reaction_scores";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."reaction_scores";
create policy bsb_tenant_scope_select on "better_supabase"."reaction_scores" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('reactions.read')) and "better_supabase"."reaction_subject_visible"("subject_type", "subject_id", "tenant_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."reaction_scores";
create policy bsb_tenant_scope_insert on "better_supabase"."reaction_scores" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."reaction_scores";
create policy bsb_tenant_scope_update on "better_supabase"."reaction_scores" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."reaction_scores";
create policy bsb_tenant_scope_delete on "better_supabase"."reaction_scores" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."custom_emoji";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."custom_emoji";
create policy bsb_tenant_scope_select on "better_supabase"."custom_emoji" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('reactions.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."custom_emoji";
create policy bsb_tenant_scope_insert on "better_supabase"."custom_emoji" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."custom_emoji";
create policy bsb_tenant_scope_update on "better_supabase"."custom_emoji" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."custom_emoji";
create policy bsb_tenant_scope_delete on "better_supabase"."custom_emoji" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.reactions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."reaction_subject_visible"(text, text, uuid);

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

create or replace function "api"."reaction_list"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reaction_list"($1, $2, $3) $$;
revoke execute on function "api"."reaction_list"(uuid, text, text) from public, anon;
grant execute on function "api"."reaction_list"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."react"(tenant uuid, subject_type text, subject_id text, emoji text, present boolean default true, actor text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."react"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."react"(uuid, text, text, text, boolean, text) from public, anon;
grant execute on function "api"."react"(uuid, text, text, text, boolean, text) to authenticated, service_role;

create or replace function "api"."vote_tally"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."vote_tally"($1, $2, $3) $$;
revoke execute on function "api"."vote_tally"(uuid, text, text) from public, anon;
grant execute on function "api"."vote_tally"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."vote"(tenant uuid, subject_type text, subject_id text, value integer, actor text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."vote"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."vote"(uuid, text, text, integer, text) from public, anon;
grant execute on function "api"."vote"(uuid, text, text, integer, text) to authenticated, service_role;

create or replace function "api"."vote_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."vote_summary"($1, $2, $3) $$;
revoke execute on function "api"."vote_summary"(uuid, text, text[]) from public, anon;
grant execute on function "api"."vote_summary"(uuid, text, text[]) to authenticated, service_role;

create or replace function "api"."reaction_summary"(tenant uuid, subject_type text, subject_ids text[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reaction_summary"($1, $2, $3) $$;
revoke execute on function "api"."reaction_summary"(uuid, text, text[]) from public, anon;
grant execute on function "api"."reaction_summary"(uuid, text, text[]) to authenticated, service_role;

create or replace function "api"."save_custom_emoji"(tenant uuid, shortcode text, attachment_id uuid default null, url text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_custom_emoji"($1, $2, $3, $4) $$;
revoke execute on function "api"."save_custom_emoji"(uuid, text, uuid, text) from public, anon;
grant execute on function "api"."save_custom_emoji"(uuid, text, uuid, text) to authenticated, service_role;

create or replace function "api"."delete_custom_emoji"(emoji_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_custom_emoji"($1) $$;
revoke execute on function "api"."delete_custom_emoji"(uuid) from public, anon;
grant execute on function "api"."delete_custom_emoji"(uuid) to authenticated, service_role;

create or replace function "api"."list_custom_emoji"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_custom_emoji"($1) $$;
revoke execute on function "api"."list_custom_emoji"(uuid) from public, anon;
grant execute on function "api"."list_custom_emoji"(uuid) to authenticated, service_role;

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
