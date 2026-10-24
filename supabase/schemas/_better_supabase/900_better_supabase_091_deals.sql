-- better-supabase module: deals
-- @bsb-block deals@1 managed
-- @bsb-hash sha256:c135d2d3a61b003e0ee167c1291cdc3861a9fa66a0ddfb451fa2deb8c1f82f2a
-- Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Deals on pipelines: an amount in minor units, a company and contacts, a
-- forecast call, close-date slips, a next step and line items.

create table if not exists "better_supabase"."deals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "name" text not null check (length("name") between 1 and 300),
  "company_type" text,
  "company_id" text,
  "motion" text,
  "priority" text,
  "owner_user_id" uuid,
  "product" text,
  "seats" integer check ("seats" >= 0),
  "amount" bigint not null default 0 check ("amount" >= 0),
  "existing_amount" bigint not null default 0 check ("existing_amount" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "value_period" text not null default 'one_time' check ("value_period" in ('one_time', 'monthly', 'annual')),
  "amount_source" text not null default 'manual' check ("amount_source" in ('manual', 'line_items')),
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "outcome" text not null default 'open' check ("outcome" in ('open', 'won', 'lost')),
  "probability" smallint check ("probability" >= 0 and "probability" <= 100),
  "forecast_category" text check ("forecast_category" in ('commit', 'best_case', 'pipeline', 'omit')),
  "opened_on" date not null default current_date,
  "expected_close_on" date not null,
  "slipped_from" date,
  "push_count" integer not null default 0,
  "closed_at" timestamptz,
  "next_step" text,
  "next_at" timestamptz,
  "next_kind" text,
  "flags" text[] not null default '{}',
  "source" text,
  "note" text,
  "lost_reason" text,
  "locked" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "list_total" bigint not null default 0,
  "discount_total" bigint not null default 0,
  "subtotal" bigint not null default 0,
  "tax_total" bigint not null default 0,
  "total" bigint not null default 0,
  unique ("tenant_id", "number"),
  check (("company_type" is null) = ("company_id" is null))
);
create index if not exists deals_pipeline_stage_idx on "better_supabase"."deals" ("pipeline_id", "stage_id", "rank");
create index if not exists deals_tenant_close_idx on "better_supabase"."deals" ("tenant_id", "expected_close_on") where "outcome" = 'open';
create index if not exists deals_owner_idx on "better_supabase"."deals" ("owner_user_id");
create index if not exists deals_company_idx on "better_supabase"."deals" ("company_type", "company_id");
alter table "better_supabase"."deals" enable row level security;
revoke all on "better_supabase"."deals" from anon, authenticated;
grant select on "better_supabase"."deals" to authenticated;
grant all on "better_supabase"."deals" to service_role;

create table if not exists "better_supabase"."deal_contacts" (
  "tenant_id" uuid not null,
  "deal_id" uuid not null references "better_supabase"."deals" ("id") on delete cascade,
  "contact_type" text not null,
  "contact_id" text not null,
  "role" text,
  "is_primary" boolean not null default false,
  primary key ("deal_id", "contact_type", "contact_id")
);
create index if not exists deal_contacts_contact_idx on "better_supabase"."deal_contacts" ("contact_type", "contact_id");
create unique index if not exists deal_contacts_primary_idx on "better_supabase"."deal_contacts" ("deal_id") where "is_primary";
alter table "better_supabase"."deal_contacts" enable row level security;
revoke all on "better_supabase"."deal_contacts" from anon, authenticated;
grant select on "better_supabase"."deal_contacts" to authenticated;
grant all on "better_supabase"."deal_contacts" to service_role;

create table if not exists "better_supabase"."deal_members" (
  "tenant_id" uuid not null,
  "deal_id" uuid not null references "better_supabase"."deals" ("id") on delete cascade,
  "user_id" uuid not null,
  "role" text,
  primary key ("deal_id", "user_id")
);
create index if not exists deal_members_user_idx on "better_supabase"."deal_members" ("user_id");
alter table "better_supabase"."deal_members" enable row level security;
revoke all on "better_supabase"."deal_members" from anon, authenticated;
grant select on "better_supabase"."deal_members" to authenticated;
grant all on "better_supabase"."deal_members" to service_role;

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
drop policy if exists deals_read on "better_supabase"."deals";
create policy deals_read on "better_supabase"."deals" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')));
drop policy if exists deal_contacts_read on "better_supabase"."deal_contacts";
create policy deal_contacts_read on "better_supabase"."deal_contacts" for select to authenticated
using (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'));
drop policy if exists deal_members_read on "better_supabase"."deal_members";
create policy deal_members_read on "better_supabase"."deal_members" for select to authenticated
using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('deals.read')));

create or replace function better_supabase.bsb_deal_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims text;
begin
  if tg_op = 'INSERT' then
    new."closed_at" := case when new."outcome" <> 'open' then now() end;
    if new."owner_user_id" is not null then
      insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
    end if;
    return new;
  end if;
  if old."locked" and not (auth.role() = 'service_role') and (
      new."name" is distinct from old."name"
      or new."company_type" is distinct from old."company_type"
      or new."company_id" is distinct from old."company_id"
      or new."motion" is distinct from old."motion"
      or new."priority" is distinct from old."priority"
      or new."owner_user_id" is distinct from old."owner_user_id"
      or new."product" is distinct from old."product"
      or new."seats" is distinct from old."seats"
      or new."amount" is distinct from old."amount"
      or new."existing_amount" is distinct from old."existing_amount"
      or new."currency" is distinct from old."currency"
      or new."value_period" is distinct from old."value_period"
      or new."pipeline_id" is distinct from old."pipeline_id"
      or new."stage_id" is distinct from old."stage_id"
      or new."probability" is distinct from old."probability"
      or new."forecast_category" is distinct from old."forecast_category"
      or new."expected_close_on" is distinct from old."expected_close_on"
      or new."next_step" is distinct from old."next_step"
      or new."next_at" is distinct from old."next_at"
      or new."next_kind" is distinct from old."next_kind"
      or new."flags" is distinct from old."flags"
      or new."source" is distinct from old."source"
      or new."lost_reason" is distinct from old."lost_reason"
    ) then
    raise exception 'the deal is locked; only its note can change' using errcode = '55000', hint = 'DEAL_LOCKED';
  end if;
  if new."opened_on" is distinct from old."opened_on" and not (auth.role() = 'service_role') then
    raise exception 'the open date never moves' using errcode = '22023', hint = 'DEAL_OPENED_ON_FIXED';
  end if;
  if new."expected_close_on" > old."expected_close_on" and old."outcome" = 'open' then
    new."slipped_from" := coalesce(old."slipped_from", old."expected_close_on");
    new."push_count" := old."push_count" + 1;
  end if;
  if new."forecast_category" is distinct from old."forecast_category" and new."outcome" <> 'open' and old."outcome" <> 'open' then
    raise exception 'a closed deal is called by its stage, not a forecast' using errcode = '22023', hint = 'DEAL_FORECAST_CLOSED';
  end if;
  if new."outcome" is distinct from old."outcome" then
    new."closed_at" := case when new."outcome" <> 'open' then now() end;
    if new."outcome" = 'open' then
      new."lost_reason" := null;
      perform "better_supabase".emit_event('deal.reopened', jsonb_build_object('organizationId', new."tenant_id", 'dealId', new."id", 'subjectType', 'deal', 'subjectId', new."id"::text, 'name', new."name"), 'deals/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/deals');
    else
      perform "better_supabase".emit_event('deal.closed', jsonb_build_object('organizationId', new."tenant_id", 'dealId', new."id", 'subjectType', 'deal', 'subjectId', new."id"::text, 'name', new."name", 'outcome', new."outcome", 'amount', new."amount"::text, 'currency', new."currency", 'reason', new."lost_reason"), 'deals/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/deals');
    end if;
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'deal.closed',
      'tenant', new."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'deal',
      'subject_id', new."id"::text,
      'summary', new."name",
      'key', 'deal.outcome:' || new."id"::text || ':' || new."outcome" || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('dealId', new."id", 'outcome', new."outcome")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if new."owner_user_id" is not null and new."owner_user_id" is distinct from old."owner_user_id" then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_user_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_deal_guard() from public, anon, authenticated;
drop trigger if exists bsb_deal_guard on "better_supabase"."deals";
create trigger bsb_deal_guard before insert or update on "better_supabase"."deals"
for each row execute function better_supabase.bsb_deal_guard();

-- Creates a deal. attrs: name, closeOn (required), amount (minor units),
-- currency, company { type, id }, ownerId, motion, priority, product, seats,
-- existingAmount, valuePeriod, pipelineId, stageId, probability, forecast,
-- nextStep, nextAt, nextKind, flags, source, note and the extra columns by
-- name. contacts: a list of { type, id, role, primary }.
create or replace function "better_supabase"."create_deal"(tenant uuid, attrs jsonb, contacts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deal uuid;
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."deals";
  v_company_type text := coalesce(create_deal.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_deal.attrs -> 'company' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_deal.tenant, 'deals.write'), false)) then
    raise exception 'not allowed to change deals' using errcode = '42501', hint = 'DEAL_FORBIDDEN';
  end if;
  if nullif(trim(create_deal.attrs ->> 'name'), '') is null or (create_deal.attrs ->> 'closeOn') is null then
    raise exception 'a deal needs a name and a close date' using errcode = '23502', hint = 'DEAL_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_deal.tenant, create_deal.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id",
      "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period",
      "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind",
      "flags", "source", "note", "created_by")
    values (create_deal.tenant, v_seq, v_identifier, trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion', create_deal.attrs ->> 'priority', create_deal.attrs ->> 'product', (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0), coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')), coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid, (create_deal.attrs ->> 'stageId')::uuid, (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast', (create_deal.attrs ->> 'closeOn')::date, create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz, create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source', create_deal.attrs ->> 'note', auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a deal field has an invalid value' using errcode = '22023', hint = 'DEAL_ATTRS_INVALID';
  end;
  v_deal := v_row."id";
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
  if create_deal.contacts is not null then
    perform "better_supabase"."set_deal_contacts"(v_deal, create_deal.contacts);
  end if;
  perform "better_supabase".emit_event('deal.created', jsonb_build_object('organizationId', create_deal.tenant, 'dealId', v_deal, 'subjectType', 'deal', 'subjectId', v_deal::text, 'name', v_row."name"), 'deals/' || v_deal::text, (create_deal.tenant::text)::text, null, 'better-supabase/deals');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_deal;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = v_deal);
end;
$$;
revoke execute on function "better_supabase"."create_deal"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_deal"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Applies a batch of { dealId, field, value } changes, each on its own:
-- a change that fails is rejected with its reason and the others stay.
-- Returns { accepted: [{ dealId, field }], rejected: [{ dealId, field, hint, reason }] }.
create or replace function "better_supabase"."update_deals"(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_deal uuid;
  v_field text;
  v_row "better_supabase"."deals";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_deals.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { dealId, field, value }' using errcode = '22023', hint = 'DEAL_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_deals.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_deal := (v_change ->> 'dealId')::uuid;
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not (case (v_change -> 'value' ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"((v_change -> 'value' ->> 'type'), (v_change -> 'value' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
      end if;
      if v_field in ('amount', 'existingAmount') and jsonb_typeof(v_change -> 'value') = 'object' then
        if upper(v_change -> 'value' ->> 'currency') is distinct from v_row."currency" then
          raise exception 'an amount must be in the deal''s currency' using errcode = '22023', hint = 'DEAL_CURRENCY_MISMATCH';
        end if;
        v_change := jsonb_set(v_change, '{value}', v_change -> 'value' -> 'amount');
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_deal, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."deals" x set "name" = trim(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'motion' then
        update "better_supabase"."deals" x set "motion" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'priority' then
        update "better_supabase"."deals" x set "priority" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'ownerId' then
        update "better_supabase"."deals" x set "owner_user_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'product' then
        update "better_supabase"."deals" x set "product" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'seats' then
        update "better_supabase"."deals" x set "seats" = (v_change -> 'value' #>> '{}')::integer where x."id" = v_deal returning * into v_row;
      when 'amount' then
        update "better_supabase"."deals" x set "amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'existingAmount' then
        update "better_supabase"."deals" x set "existing_amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'currency' then
        update "better_supabase"."deals" x set "currency" = upper(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'valuePeriod' then
        update "better_supabase"."deals" x set "value_period" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'amountSource' then
        update "better_supabase"."deals" x set "amount_source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'stageId' then
        update "better_supabase"."deals" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'probability' then
        update "better_supabase"."deals" x set "probability" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_deal returning * into v_row;
      when 'forecast' then
        update "better_supabase"."deals" x set "forecast_category" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'closeOn' then
        update "better_supabase"."deals" x set "expected_close_on" = (v_change -> 'value' #>> '{}')::date where x."id" = v_deal returning * into v_row;
      when 'nextStep' then
        update "better_supabase"."deals" x set "next_step" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'nextAt' then
        update "better_supabase"."deals" x set "next_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_deal returning * into v_row;
      when 'nextKind' then
        update "better_supabase"."deals" x set "next_kind" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'flags' then
        update "better_supabase"."deals" x set "flags" = coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(v_change -> 'value') when 'array' then v_change -> 'value' else '[]' end)), '{}') where x."id" = v_deal returning * into v_row;
      when 'source' then
        update "better_supabase"."deals" x set "source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'note' then
        update "better_supabase"."deals" x set "note" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'lostReason' then
        update "better_supabase"."deals" x set "lost_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'company' then
        update "better_supabase"."deals" x set "company_type" = v_change -> 'value' ->> 'type', "company_id" = v_change -> 'value' ->> 'id' where x."id" = v_deal returning * into v_row;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'DEAL_FIELD_UNKNOWN';
      end case;
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('dealId', v_deal, 'field', v_field));
      v_touched := array_append(v_touched, v_deal);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_deal, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('dealId', v_change ->> 'dealId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."deals" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('deal.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'dealId')::uuid = v_row."id")), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "better_supabase"."update_deals"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_deals"(jsonb) to authenticated, service_role;

-- Closes a deal as won or lost: it moves to the first success or failure
-- stage of its pipeline, which sets its outcome.
create or replace function "better_supabase"."close_deal"(deal uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."deals";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."deals" x where x."id" = close_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_row."id" is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if close_deal.outcome not in ('won', 'lost') then
    raise exception 'close a deal as won or lost' using errcode = '22023', hint = 'DEAL_OUTCOME_INVALID';
  end if;
  select st."id" into v_stage from "better_supabase"."pipeline_stages" st
  where st."pipeline_id" = v_row."pipeline_id" and st."archived_at" is null
    and st."outcome" = case close_deal.outcome when 'won' then 'success' else 'failure' end
  order by st."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the pipeline has no stage for that outcome' using errcode = 'P0002', hint = 'DEAL_STAGE_MISSING';
  end if;
  update "better_supabase"."deals" x set "stage_id" = v_stage,
    "lost_reason" = case when close_deal.outcome = 'lost' then nullif(trim(close_deal.reason), '') end,
    "note" = case when close_deal.outcome = 'won' then coalesce(nullif(trim(close_deal.reason), ''), x."note") else x."note" end
  where x."id" = close_deal.deal;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = close_deal.deal);
end;
$$;
revoke execute on function "better_supabase"."close_deal"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."close_deal"(uuid, text, text) to authenticated, service_role;

-- Opens a closed deal again in stage, or its pipeline's first open stage.
create or replace function "better_supabase"."reopen_deal"(deal uuid, stage uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."deals";
  v_stage uuid := reopen_deal.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."deals" x where x."id" = reopen_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_row."id" is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if v_stage is null then
    select st."id" into v_stage from "better_supabase"."pipeline_stages" st
    where st."pipeline_id" = v_row."pipeline_id" and st."archived_at" is null and st."outcome" = 'open'
    order by st."rank" collate "C" limit 1;
  end if;
  update "better_supabase"."deals" x set "stage_id" = v_stage where x."id" = reopen_deal.deal;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = reopen_deal.deal);
end;
$$;
revoke execute on function "better_supabase"."reopen_deal"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."reopen_deal"(uuid, uuid) to authenticated, service_role;

-- Replaces a deal's contacts with a list of { type, id, role, primary }.
create or replace function "better_supabase"."set_deal_contacts"(deal uuid, contacts jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_deal uuid := set_deal_contacts.deal;
  v_item jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not (case coalesce(v_item ->> 'type', 'person')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(v_item ->> 'type', 'person'), (v_item ->> 'id'), 'read')) then
      raise exception 'a contact is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_CONTACT_FORBIDDEN';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(set_deal_contacts.contacts) x where coalesce((x.value ->> 'primary')::boolean, false)) > 1 then
    raise exception 'a deal has one primary contact' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  delete from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_contacts" ("tenant_id", "deal_id", "contact_type", "contact_id", "role", "is_primary")
  select v_tenant, v_deal, coalesce(x.value ->> 'type', 'person'), x.value ->> 'id', x.value ->> 'role', coalesce((x.value ->> 'primary')::boolean, false)
  from jsonb_array_elements(set_deal_contacts.contacts) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_deal_contacts"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_deal_contacts"(uuid, jsonb) to authenticated, service_role;

-- Replaces a deal's team with a list of { userId, role }. Each member
-- watches the deal.
create or replace function "better_supabase"."set_deal_members"(deal uuid, members jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_deal uuid := set_deal_members.deal;
  v_user uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_members.members, '[]')) <> 'array' then
    raise exception 'members must be a list of { userId, role }' using errcode = '22023', hint = 'DEAL_MEMBERS_INVALID';
  end if;
  delete from "better_supabase"."deal_members" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_members" ("tenant_id", "deal_id", "user_id", "role")
  select v_tenant, v_deal, (x.value ->> 'userId')::uuid, x.value ->> 'role'
  from jsonb_array_elements(set_deal_members.members) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  for v_user in select (x.value ->> 'userId')::uuid from jsonb_array_elements(set_deal_members.members) x loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_tenant, v_user, 'deal', v_deal::text, 'participating')
    on conflict do nothing;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_deal_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_deal_members"(uuid, jsonb) to authenticated, service_role;
create table if not exists "better_supabase"."deal_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."deals" ("id") on delete cascade,
  "product_type" text,
  "product_id" text,
  "description" text not null check (length("description") between 1 and 2000),
  "quantity" numeric(18, 4) not null check ("quantity" > 0),
  "unit_amount" bigint not null,
  "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000),
  "tax_rate_bps" integer not null default 0 check ("tax_rate_bps" >= 0 and "tax_rate_bps" <= 100000),
  "tax_code" text,
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
create index if not exists "deal_lines_parent_idx" on "better_supabase"."deal_lines" ("parent_id", "position");
alter table "better_supabase"."deal_lines" enable row level security;
revoke all on "better_supabase"."deal_lines" from anon, authenticated;
grant select on "better_supabase"."deal_lines" to authenticated;
grant all on "better_supabase"."deal_lines" to service_role;
drop policy if exists "deal_lines_read" on "better_supabase"."deal_lines";
create policy "deal_lines_read" on "better_supabase"."deal_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."deals" x where x."id" = "parent_id"));

-- Writes a record's totals from its lines. A record without lines keeps
-- zero totals.
create or replace function "better_supabase"."set_deal_lines_recount"(parent uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list bigint;
  v_discount bigint;
  v_tax bigint;
begin
  select coalesce(sum(round(l."quantity" * l."unit_amount")), 0), coalesce(sum(round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)), 0), coalesce(sum(round((round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)) * l."tax_rate_bps" / 10000.0)), 0)
    into v_list, v_discount, v_tax
  from "better_supabase"."deal_lines" l where l."parent_id" = set_deal_lines_recount.parent;
  update "better_supabase"."deals" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_list - v_discount,
    "tax_total" = v_tax,
    "total" = v_list - v_discount + v_tax,
    "amount" = case when x."amount_source" = 'line_items' then v_list - v_discount else x."amount" end
  where x."id" = set_deal_lines_recount.parent;
end;
$$;
revoke execute on function "better_supabase"."set_deal_lines_recount"(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.bsb_deal_lines_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'
    when 'DELETE' then 'select distinct o."parent_id" from old_rows o order by 1'
    else 'select n."parent_id" from new_rows n union select o."parent_id" from old_rows o order by 1'
  end loop
    perform "better_supabase"."set_deal_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_deal_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_deal_lines_totals on "better_supabase"."deal_lines";
drop trigger if exists bsb_deal_lines_totals_insert on "better_supabase"."deal_lines";
drop trigger if exists bsb_deal_lines_totals_update on "better_supabase"."deal_lines";
drop trigger if exists bsb_deal_lines_totals_delete on "better_supabase"."deal_lines";
create trigger bsb_deal_lines_totals_insert after insert on "better_supabase"."deal_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_deal_lines_totals();
create trigger bsb_deal_lines_totals_update after update on "better_supabase"."deal_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_deal_lines_totals();
create trigger bsb_deal_lines_totals_delete after delete on "better_supabase"."deal_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_deal_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function "better_supabase"."set_deal_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_deal_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."deals" x where x."id" = v_parent and not (x."locked");
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."deals" x where x."id" = v_parent and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))) then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_deal_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."deal_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."deal_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select v_tenant, v_parent, x.value -> 'product' ->> 'type', x.value -> 'product' ->> 'id', x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1), (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0), coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode', x.ordinality::integer
    from jsonb_array_elements(coalesce(set_deal_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_deal_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."deals" x where x."id" = v_parent);
end;
$$;
revoke execute on function "better_supabase"."set_deal_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_deal_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."archive_deal"(deal uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."deals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."deals" x set "archived_at" = case when archive_deal.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_deal.archived then
    perform "better_supabase".emit_event('deal.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name"), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_deal"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_deal"(uuid, boolean) to authenticated, service_role;

-- Deletes a deal. Needs deals.manage, or the deal's owner.
create or replace function "better_supabase"."delete_deal"(deal uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."deals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."deals" x
  where x."id" = delete_deal.deal
    and ((auth.role() = 'service_role') or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('deal.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name"), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_deal"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_deal"(uuid) to authenticated, service_role;

-- The forecast call for one currency between since and until: won deals
-- closed in the window, open deals closing in it by forecast category
-- (notCalled for none), later for open deals closing after it, and each
-- owner's split. target is the period goal in minor units; attainment is
-- won plus commit over it. Runs as the caller, so it sums what they see.
create or replace function "better_supabase"."deal_forecast"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with scoped as (
    select * from "better_supabase"."deals" x
    where x."tenant_id" = deal_forecast.tenant
      and x."currency" = upper(deal_forecast.currency)
      and x."archived_at" is null
      and (deal_forecast.pipeline is null or x."pipeline_id" = deal_forecast.pipeline)
      and (deal_forecast.owner is null or x."owner_user_id" = deal_forecast.owner)
  ),
  totals as (
    select jsonb_build_object(
      'won', coalesce(sum(x."amount") filter (where x."outcome" = 'won' and x."closed_at"::date >= deal_forecast.since and x."closed_at"::date <= deal_forecast.until), 0)::text,
      'commit', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'commit'), 0)::text,
      'bestCase', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'best_case'), 0)::text,
      'pipeline', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'pipeline'), 0)::text,
      'notCalled', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" is null), 0)::text,
      'omit', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'omit'), 0)::text,
      'later', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" > deal_forecast.until), 0)::text
    ) as sums
    from scoped x
  ),
  owners as (
    select coalesce(jsonb_agg(o.value order by o.owner_id), '[]'::jsonb) as list
    from (
      select x."owner_user_id" as owner_id, jsonb_build_object('ownerId', x."owner_user_id", 
      'won', coalesce(sum(x."amount") filter (where x."outcome" = 'won' and x."closed_at"::date >= deal_forecast.since and x."closed_at"::date <= deal_forecast.until), 0)::text,
      'commit', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'commit'), 0)::text,
      'bestCase', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'best_case'), 0)::text,
      'pipeline', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'pipeline'), 0)::text,
      'notCalled', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" is null), 0)::text,
      'omit', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'omit'), 0)::text,
      'later', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" > deal_forecast.until), 0)::text
      ) as value
      from scoped x group by x."owner_user_id"
    ) o
  )
  select totals.sums || jsonb_build_object(
    'currency', upper(deal_forecast.currency),
    'target', deal_forecast.target::text,
    'attainment', case when coalesce(deal_forecast.target, 0) = 0 then null
      else round(((totals.sums ->> 'won')::numeric + (totals.sums ->> 'commit')::numeric) / deal_forecast.target, 4) end,
    'gap', case when deal_forecast.target is null then null
      else greatest(deal_forecast.target - (totals.sums ->> 'won')::bigint - (totals.sums ->> 'commit')::bigint, 0)::text end,
    'owners', owners.list)
  from totals, owners;
$$;
revoke execute on function "better_supabase"."deal_forecast"(uuid, uuid, date, date, text, bigint, uuid) from public, anon;
grant execute on function "better_supabase"."deal_forecast"(uuid, uuid, date, date, text, bigint, uuid) to authenticated, service_role;

-- The open deals of a pipeline the caller can see, with the checks a
-- forecast review runs: days in stage and rotting, a slipped close date,
-- no next step, and an overdue next step.
create or replace function "better_supabase"."deal_health"(pipeline uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'dealId', x."id", 'identifier', x."identifier", 'name', x."name",
    'daysInStage', (extract(epoch from now() - coalesce(x."stage_entered_at", x."created_at")) / 86400)::integer,
    'rotting', st."rotting_after_days" is not null and now() - coalesce(x."stage_entered_at", x."created_at") > make_interval(days => st."rotting_after_days"),
    'slipped', x."push_count" > 0 or x."expected_close_on" < current_date,
    'noNextStep', x."next_at" is null and ne.e is null,
    'overdue', coalesce((x."next_at" < now() or coalesce((ne.e ->> 'overdue')::boolean, false)), false)
  ) order by x."expected_close_on", x."id"), '[]'::jsonb)
  from "better_supabase"."deals" x
  left join "better_supabase"."pipeline_stages" st on st."id" = x."stage_id"
  left join lateral (select "better_supabase"."next_engagement"('deal', x."id"::text) as e) ne on true
  where x."pipeline_id" = deal_health.pipeline and x."outcome" = 'open' and x."archived_at" is null);
end;
$$;
revoke execute on function "better_supabase"."deal_health"(uuid) from public, anon;
grant execute on function "better_supabase"."deal_health"(uuid) to authenticated, service_role;

drop trigger if exists "bsb_search_deal_index" on "better_supabase"."deals";
create trigger "bsb_search_deal_index"
  after insert or delete or update of "id", "tenant_id", "name", "identifier", "note", "archived_at" on "better_supabase"."deals"
  for each row execute function "better_supabase"."search_index_row"('deal', 'id');

-- blocks.deals.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."create_deal"(tenant uuid, attrs jsonb, contacts jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_deal"($1, $2, $3) $$;
revoke execute on function "api"."create_deal"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."create_deal"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_deals"(changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_deals"($1) $$;
revoke execute on function "api"."update_deals"(jsonb) from public, anon;
grant execute on function "api"."update_deals"(jsonb) to authenticated, service_role;

create or replace function "api"."close_deal"(deal uuid, outcome text, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_deal"($1, $2, $3) $$;
revoke execute on function "api"."close_deal"(uuid, text, text) from public, anon;
grant execute on function "api"."close_deal"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."reopen_deal"(deal uuid, stage uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reopen_deal"($1, $2) $$;
revoke execute on function "api"."reopen_deal"(uuid, uuid) from public, anon;
grant execute on function "api"."reopen_deal"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."set_deal_contacts"(deal uuid, contacts jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_deal_contacts"($1, $2) $$;
revoke execute on function "api"."set_deal_contacts"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_deal_contacts"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_deal_members"(deal uuid, members jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_deal_members"($1, $2) $$;
revoke execute on function "api"."set_deal_members"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_deal_members"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_deal_lines"(parent uuid, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_deal_lines"($1, $2) $$;
revoke execute on function "api"."set_deal_lines"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_deal_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."archive_deal"(deal uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_deal"($1, $2) $$;
revoke execute on function "api"."archive_deal"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_deal"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."delete_deal"(deal uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_deal"($1) $$;
revoke execute on function "api"."delete_deal"(uuid) from public, anon;
grant execute on function "api"."delete_deal"(uuid) to authenticated, service_role;

create or replace function "api"."deal_forecast"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint, owner uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."deal_forecast"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."deal_forecast"(uuid, uuid, date, date, text, bigint, uuid) from public, anon;
grant execute on function "api"."deal_forecast"(uuid, uuid, date, date, text, bigint, uuid) to authenticated, service_role;

create or replace function "api"."deal_health"(pipeline uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."deal_health"($1) $$;
revoke execute on function "api"."deal_health"(uuid) from public, anon;
grant execute on function "api"."deal_health"(uuid) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
