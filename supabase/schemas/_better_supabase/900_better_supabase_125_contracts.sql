-- better-supabase module: contracts
-- @bsb-block contracts@1 managed
-- @bsb-hash sha256:68bb1d3daee09393f90811bf2b2442efe71634c14e2a8e11b039cf83e416c67a
-- Contracts with counterparties from draft through review and signature to active, expired or terminated, built on signatures, versions and reminders. Values are bigint minor units; renewal terms (auto-renew, renewal period, notice days) schedule a reminder before the notice deadline; obligations carry due dates and owners.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."contracts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."contracts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."contracts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."contracts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."contracts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."contract_obligations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."contract_obligations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."contract_obligations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."contract_obligations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."contract_obligations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Contracts: a lifecycle from draft to signed, renewal terms with reminders
-- before the notice deadline, and obligations with due dates and owners.

create table if not exists "better_supabase"."contracts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 10000),
  -- The other party: a registered subject (a company or person of the parties block, say).
  "counterparty_type" text,
  "counterparty_id" text,
  "owner_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'in_review', 'out_for_signature', 'active', 'expired', 'terminated')),
  -- The contract value in minor units of currency.
  "value" bigint check ("value" is null or "value" >= 0),
  "currency" text check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "starts_on" date,
  "ends_on" date,
  "auto_renew" boolean not null default false,
  -- How far an auto-renewal moves ends_on.
  "renewal_months" integer not null default 12 check ("renewal_months" between 1 and 120),
  -- How many days before ends_on notice of termination is due.
  "notice_days" integer not null default 30 check ("notice_days" between 0 and 3650),
  "renewed_count" integer not null default 0,
  "signature_request_id" uuid references "better_supabase"."signature_requests" ("id") on delete set null,
  "signed_at" timestamptz,
  "terminated_at" timestamptz,
  "termination_reason" text check ("termination_reason" is null or length("termination_reason") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("counterparty_type" is null) = ("counterparty_id" is null)),
  check (("value" is null) = ("currency" is null)),
  check ("ends_on" is null or "starts_on" is null or "ends_on" >= "starts_on"),
  unique ("tenant_id", "id")
);
create index if not exists "contracts_status_idx" on "better_supabase"."contracts" ("tenant_id", "status", "ends_on");
create index if not exists "contracts_counterparty_idx" on "better_supabase"."contracts" ("tenant_id", "counterparty_type", "counterparty_id") where "counterparty_type" is not null;
create index if not exists "contracts_owner_idx" on "better_supabase"."contracts" ("tenant_id", "owner_id") where "owner_id" is not null;
create index if not exists "contracts_signature_idx" on "better_supabase"."contracts" ("signature_request_id") where "signature_request_id" is not null;
alter table "better_supabase"."contracts" enable row level security;
revoke all on "better_supabase"."contracts" from anon, authenticated;
grant select on "better_supabase"."contracts" to authenticated;
grant all on "better_supabase"."contracts" to service_role;
drop policy if exists "contracts_read" on "better_supabase"."contracts";
create policy "contracts_read" on "better_supabase"."contracts" for select to authenticated
  using ("owner_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('contracts.read')));

create table if not exists "better_supabase"."contract_obligations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "contract_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 4000),
  "due_on" date,
  "owner_id" uuid,
  "status" text not null default 'open' check ("status" in ('open', 'done', 'waived')),
  "completed_at" timestamptz,
  "completed_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "contract_id") references "better_supabase"."contracts" ("tenant_id", "id") on delete cascade
);
create index if not exists "contract_obligations_parent_idx" on "better_supabase"."contract_obligations" ("tenant_id", "contract_id", "due_on");
create index if not exists "contract_obligations_owner_idx" on "better_supabase"."contract_obligations" ("tenant_id", "owner_id", "due_on") where "owner_id" is not null;
create index if not exists "contract_obligations_due_idx" on "better_supabase"."contract_obligations" ("tenant_id", "due_on") where "status" = 'open';
alter table "better_supabase"."contract_obligations" enable row level security;
revoke all on "better_supabase"."contract_obligations" from anon, authenticated;
grant select on "better_supabase"."contract_obligations" to authenticated;
grant all on "better_supabase"."contract_obligations" to service_role;
drop policy if exists "contract_obligations_read" on "better_supabase"."contract_obligations";
create policy "contract_obligations_read" on "better_supabase"."contract_obligations" for select to authenticated
  using ("owner_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('contracts.read')));

-- Keeps the contract's renewal reminder in step with its terms: while it is
-- active with an end date, the reminders block holds one occurrence at the
-- notice deadline and the owner a reminder before it (options.reminderDays).
create or replace function "better_supabase"."contract_schedule_renewal"(contract_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."contracts"%rowtype;
begin
  select * into v_row from "better_supabase"."contracts" x where x."id" = contract_schedule_renewal.contract_id;
  if not found then
    return;
  end if;
  if v_row."status" <> 'active' or v_row."ends_on" is null then
    delete from "better_supabase"."reminders" x where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'contract' and x."subject_id" = v_row."id"::text;
    delete from "better_supabase"."recurrence_rules" x where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'contract' and x."subject_id" = v_row."id"::text;
    return;
  end if;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid")
  values (v_row."tenant_id", 'contract', v_row."id"::text, ((case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end)::timestamp + interval '9 hours') at time zone 'UTC', 'UTC')
  on conflict ("tenant_id", "subject_type", "subject_id") do update
    set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid";
  if v_row."owner_id" is not null and not exists (
    select 1 from "better_supabase"."reminders" x
    where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'contract'
      and x."subject_id" = v_row."id"::text and x."user_id" = v_row."owner_id"
  ) then
    insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
    values (v_row."tenant_id", 'contract', v_row."id"::text, v_row."owner_id", 20160);
  end if;
end;
$$;
revoke execute on function "better_supabase"."contract_schedule_renewal"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."contract_schedule_renewal"(uuid) to service_role;

-- Moves a contract to a status, stamps the timestamps the status carries and
-- records contract.status_changed. Callers check permissions and transitions.
create or replace function "better_supabase"."contract_apply_status"(contract_id uuid, status text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."contracts"%rowtype;
  v_from text;
begin
  select * into v_row from "better_supabase"."contracts" x where x."id" = contract_apply_status.contract_id for update;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  v_from := v_row."status";
  if v_from = contract_apply_status.status then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."contracts" x set
    "status" = contract_apply_status.status,
    "starts_on" = case when contract_apply_status.status = 'active' then coalesce(x."starts_on", current_date) else x."starts_on" end,
    "signed_at" = case when contract_apply_status.status = 'active' and x."signature_request_id" is not null then now() else x."signed_at" end,
    "signature_request_id" = case when contract_apply_status.status in ('draft', 'in_review') then null else x."signature_request_id" end,
    "terminated_at" = case when contract_apply_status.status = 'terminated' then now() else x."terminated_at" end,
    "termination_reason" = case when contract_apply_status.status = 'terminated' then nullif(trim(contract_apply_status.reason), '') else x."termination_reason" end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase"."contract_schedule_renewal"(v_row."id");
  perform "better_supabase".emit_event('contract.status_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'status', v_row."status", 'previousStatus', v_from), 'contracts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract.status_changed',
    category => 'data',
    target_type => 'contract',
    record_id => v_row."id"::text,
    summary => 'moved contract ' || v_row."title" || ' from ' || v_from || ' to ' || v_row."status",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'status', v_row."status", 'previousStatus', v_from)
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."contract_apply_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."contract_apply_status"(uuid, text, text) to service_role;

-- Creates a draft contract. attrs: title (required), description,
-- counterpartyType and counterpartyId (a registered subject), ownerId, value
-- (minor units as text) and currency, startsOn, endsOn, autoRenew,
-- renewalMonths and noticeDays. fields: the extra columns to set.
drop function if exists "better_supabase"."create_contract"(uuid, jsonb, jsonb);
create or replace function "better_supabase"."create_contract"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."contracts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_contract.tenant, 'contracts.write'), false)) then
    raise exception 'not allowed to create contracts' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if jsonb_typeof(create_contract.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  v_row."tenant_id" := create_contract.tenant;
  v_row."auto_renew" := false;
  v_row."renewal_months" := 12;
  v_row."notice_days" := 30;
  v_row."owner_id" := auth.uid();
  v_row."title" := case when create_contract.attrs ? 'title' then (create_contract.attrs ->> 'title')::text else v_row."title" end;
  v_row."description" := case when create_contract.attrs ? 'description' then (create_contract.attrs ->> 'description')::text else v_row."description" end;
  v_row."counterparty_type" := case when create_contract.attrs ? 'counterpartyType' then (create_contract.attrs ->> 'counterpartyType')::text else v_row."counterparty_type" end;
  v_row."counterparty_id" := case when create_contract.attrs ? 'counterpartyId' then (create_contract.attrs ->> 'counterpartyId')::text else v_row."counterparty_id" end;
  v_row."owner_id" := case when create_contract.attrs ? 'ownerId' then (create_contract.attrs ->> 'ownerId')::uuid else v_row."owner_id" end;
  v_row."value" := case when create_contract.attrs ? 'value' then (create_contract.attrs ->> 'value')::bigint else v_row."value" end;
  v_row."currency" := case when create_contract.attrs ? 'currency' then (create_contract.attrs ->> 'currency')::text else v_row."currency" end;
  v_row."starts_on" := case when create_contract.attrs ? 'startsOn' then (create_contract.attrs ->> 'startsOn')::date else v_row."starts_on" end;
  v_row."ends_on" := case when create_contract.attrs ? 'endsOn' then (create_contract.attrs ->> 'endsOn')::date else v_row."ends_on" end;
  v_row."auto_renew" := case when create_contract.attrs ? 'autoRenew' then (create_contract.attrs ->> 'autoRenew')::boolean else v_row."auto_renew" end;
  v_row."renewal_months" := case when create_contract.attrs ? 'renewalMonths' then (create_contract.attrs ->> 'renewalMonths')::integer else v_row."renewal_months" end;
  v_row."notice_days" := case when create_contract.attrs ? 'noticeDays' then (create_contract.attrs ->> 'noticeDays')::integer else v_row."notice_days" end;
  v_row."title" := nullif(trim(v_row."title"), '');
  if v_row."title" is null then
    raise exception 'a contract needs a title' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."counterparty_type" is not null and not (case v_row."counterparty_type"
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_row."counterparty_type", v_row."counterparty_id", 'read')) then
    raise exception 'the counterparty is unknown or not in this organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."owner_id" is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."owner_id") then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  insert into "better_supabase"."contracts" ("tenant_id", "title", "description", "counterparty_type", "counterparty_id", "owner_id", "value", "currency", "starts_on", "ends_on", "auto_renew", "renewal_months", "notice_days", "created_by")
  values (v_row."tenant_id", v_row."title", v_row."description", v_row."counterparty_type", v_row."counterparty_id", v_row."owner_id", v_row."value", upper(v_row."currency"), v_row."starts_on", v_row."ends_on", coalesce(v_row."auto_renew", false), coalesce(v_row."renewal_months", 12), coalesce(v_row."notice_days", 30), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('contract.created', jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'title', v_row."title", 'status', v_row."status"), 'contracts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract.created',
    category => 'data',
    target_type => 'contract',
    record_id => v_row."id"::text,
    summary => 'created contract' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_contract"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_contract"(uuid, jsonb) to authenticated, service_role;

-- Changes a contract's terms while it is a draft or in review. An active
-- contract takes changes to its owner, description and renewal terms only,
-- and its renewal reminder moves with them.
drop function if exists "better_supabase"."update_contract"(uuid, jsonb, jsonb);
create or replace function "better_supabase"."update_contract"(contract_id uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."contracts"%rowtype;
  v_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contracts" x where x."id" = update_contract.contract_id for update;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.write'), false)) then
    raise exception 'not allowed to change contracts' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if jsonb_typeof(update_contract.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."status" not in ('draft', 'in_review', 'active') then
    raise exception 'this contract can no longer change' using errcode = '55000', hint = 'CONTRACT_LOCKED';
  end if;
  if v_row."status" = 'active' and exists (
    select 1 from jsonb_object_keys(update_contract.attrs) k
    where k not in ('description', 'ownerId', 'autoRenew', 'renewalMonths', 'noticeDays')
  ) then
    raise exception 'an active contract changes only its owner, description and renewal terms' using errcode = '55000', hint = 'CONTRACT_LOCKED';
  end if;
  v_owner := v_row."owner_id";
  v_row."title" := case when update_contract.attrs ? 'title' then (update_contract.attrs ->> 'title')::text else v_row."title" end;
  v_row."description" := case when update_contract.attrs ? 'description' then (update_contract.attrs ->> 'description')::text else v_row."description" end;
  v_row."counterparty_type" := case when update_contract.attrs ? 'counterpartyType' then (update_contract.attrs ->> 'counterpartyType')::text else v_row."counterparty_type" end;
  v_row."counterparty_id" := case when update_contract.attrs ? 'counterpartyId' then (update_contract.attrs ->> 'counterpartyId')::text else v_row."counterparty_id" end;
  v_row."owner_id" := case when update_contract.attrs ? 'ownerId' then (update_contract.attrs ->> 'ownerId')::uuid else v_row."owner_id" end;
  v_row."value" := case when update_contract.attrs ? 'value' then (update_contract.attrs ->> 'value')::bigint else v_row."value" end;
  v_row."currency" := case when update_contract.attrs ? 'currency' then (update_contract.attrs ->> 'currency')::text else v_row."currency" end;
  v_row."starts_on" := case when update_contract.attrs ? 'startsOn' then (update_contract.attrs ->> 'startsOn')::date else v_row."starts_on" end;
  v_row."ends_on" := case when update_contract.attrs ? 'endsOn' then (update_contract.attrs ->> 'endsOn')::date else v_row."ends_on" end;
  v_row."auto_renew" := case when update_contract.attrs ? 'autoRenew' then (update_contract.attrs ->> 'autoRenew')::boolean else v_row."auto_renew" end;
  v_row."renewal_months" := case when update_contract.attrs ? 'renewalMonths' then (update_contract.attrs ->> 'renewalMonths')::integer else v_row."renewal_months" end;
  v_row."notice_days" := case when update_contract.attrs ? 'noticeDays' then (update_contract.attrs ->> 'noticeDays')::integer else v_row."notice_days" end;
  v_row."title" := nullif(trim(v_row."title"), '');
  if v_row."title" is null then
    raise exception 'a contract needs a title' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."counterparty_type" is not null and not (case v_row."counterparty_type"
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."counterparty_id")::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."counterparty_id")::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_row."counterparty_type", v_row."counterparty_id", 'read')) then
    raise exception 'the counterparty is unknown or not in this organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if v_row."owner_id" is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."owner_id") then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  update "better_supabase"."contracts" x set
    "title" = v_row."title", "description" = v_row."description",
    "counterparty_type" = v_row."counterparty_type", "counterparty_id" = v_row."counterparty_id",
    "owner_id" = v_row."owner_id", "value" = v_row."value", "currency" = upper(v_row."currency"),
    "starts_on" = v_row."starts_on", "ends_on" = v_row."ends_on",
    "auto_renew" = coalesce(v_row."auto_renew", false), "renewal_months" = coalesce(v_row."renewal_months", 12),
    "notice_days" = coalesce(v_row."notice_days", 30), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if v_owner is distinct from v_row."owner_id" and v_row."owner_id" is not null then
    update "better_supabase"."reminders" x set "user_id" = v_row."owner_id"
      where x."tenant_id" = v_row."tenant_id" and x."subject_type" = 'contract'
        and x."subject_id" = v_row."id"::text and x."user_id" = v_owner
        and x."offset_minutes" = 20160;
  end if;
  perform "better_supabase"."contract_schedule_renewal"(v_row."id");
  perform "better_supabase".emit_event('contract.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'title', v_row."title", 'status', v_row."status"), 'contracts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract.updated',
    category => 'data',
    target_type => 'contract',
    record_id => v_row."id"::text,
    summary => 'updated contract' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_contract"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_contract"(uuid, jsonb) to authenticated, service_role;

-- Moves a contract through its lifecycle. action: submit (draft to review),
-- return (review to draft), activate (review to active, for a contract signed
-- elsewhere), recall (cancels the signature request, back to review) or
-- terminate (with an optional reason). Activate, recall and terminate need
-- the manage permission.
create or replace function "better_supabase"."transition_contract"(contract_id uuid, action text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."contracts"%rowtype;
  v_from text[];
  v_to text;
begin
  select * into v_row from "better_supabase"."contracts" x where x."id" = transition_contract.contract_id;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  case transition_contract.action
    when 'submit' then v_from := array['draft']; v_to := 'in_review';
    when 'return' then v_from := array['in_review']; v_to := 'draft';
    when 'activate' then v_from := array['in_review']; v_to := 'active';
    when 'recall' then v_from := array['out_for_signature']; v_to := 'in_review';
    when 'terminate' then v_from := array['draft', 'in_review', 'out_for_signature', 'active']; v_to := 'terminated';
    else
      raise exception 'action must be submit, return, activate, recall or terminate' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end case;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", case when transition_contract.action in ('submit', 'return') then 'contracts.write' else 'contracts.manage' end), false)) then
    raise exception 'not allowed to move this contract' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if not (v_row."status" = any (v_from)) then
    raise exception 'the contract can''t take this step from its status' using errcode = '55000', hint = 'CONTRACT_TRANSITION_INVALID';
  end if;
  if v_row."status" = 'out_for_signature' and v_row."signature_request_id" is not null then
    -- The signatures trigger moves a recalled contract back to review.
    perform "better_supabase"."cancel_signature_request"(v_row."signature_request_id");
    if transition_contract.action = 'recall' then
      return "better_supabase"."get_contract"(v_row."id");
    end if;
  end if;
  return "better_supabase"."contract_apply_status"(v_row."id", v_to, transition_contract.reason);
end;
$$;
revoke execute on function "better_supabase"."transition_contract"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."transition_contract"(uuid, text, text) to authenticated, service_role;

-- Freezes the contract as a version and asks members to sign it
-- (signatures block). The caller also needs the signatures request
-- permission. Signing completes it to active; a decline or cancel returns it
-- to review.
create or replace function "better_supabase"."send_contract_for_signature"(contract_id uuid, signers uuid[], sign_order text default 'parallel', message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."contracts"%rowtype;
  v_version uuid;
  v_request uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contracts" x where x."id" = send_contract_for_signature.contract_id for update;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.manage'), false)) then
    raise exception 'not allowed to send contracts for signature' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if v_row."status" <> 'in_review' then
    raise exception 'only a contract in review goes out for signature' using errcode = '55000', hint = 'CONTRACT_TRANSITION_INVALID';
  end if;
  v_version := ("better_supabase"."version_insert"(
    v_row."tenant_id", 'contract', v_row."id"::text,
    jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") - 'status' - 'updatedAt' - 'signatureRequestId' - 'renewedCount',
    null, 'Sent for signature', 'manual', true, auth.uid()
  ) ->> 'id')::uuid;
  v_request := ("better_supabase"."create_signature_request"(
    v_row."tenant_id", 'contract', v_row."id"::text,
    send_contract_for_signature.signers, v_version,
    coalesce(send_contract_for_signature.sign_order, 'parallel'), null,
    send_contract_for_signature.message
  ) ->> 'id')::uuid;
  update "better_supabase"."contracts" x set "signature_request_id" = v_request, "updated_at" = now()
    where x."id" = v_row."id";
  return "better_supabase"."contract_apply_status"(v_row."id", 'out_for_signature');
end;
$$;
revoke execute on function "better_supabase"."send_contract_for_signature"(uuid, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."send_contract_for_signature"(uuid, uuid[], text, text) to authenticated, service_role;

-- A settled signature request settles the contract waiting on it.
create or replace function "better_supabase"."contract_signature_settled"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select x."id" from "better_supabase"."contracts" x
    where x."signature_request_id" = new."id" and x."status" = 'out_for_signature'
  loop
    perform "better_supabase"."contract_apply_status"(v_id, case when new."status" = 'completed' then 'active' else 'in_review' end);
  end loop;
  return new;
end;
$$;
revoke execute on function "better_supabase"."contract_signature_settled"() from public, anon, authenticated;
drop trigger if exists "bsb_contracts_signature_settled" on "better_supabase"."signature_requests";
create trigger "bsb_contracts_signature_settled" after update of "status" on "better_supabase"."signature_requests"
  for each row when (old."status" = 'pending' and new."status" <> 'pending')
  execute function "better_supabase"."contract_signature_settled"();

create or replace function "better_supabase"."get_contract"(contract_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."contracts"%rowtype;
begin
  select * into v_row from "better_supabase"."contracts" x where x."id" = get_contract.contract_id;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'title', v_row."title", 'description', v_row."description", 'counterpartyType', v_row."counterparty_type", 'counterpartyId', v_row."counterparty_id", 'ownerId', v_row."owner_id", 'status', v_row."status", 'value', v_row."value"::text, 'currency', v_row."currency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'autoRenew', v_row."auto_renew", 'renewalMonths', v_row."renewal_months", 'noticeDays', v_row."notice_days", 'noticeDeadline', case when v_row."ends_on" is null then null else v_row."ends_on" - v_row."notice_days" end, 'renewedCount', v_row."renewed_count", 'signatureRequestId', v_row."signature_request_id", 'signedAt', v_row."signed_at", 'terminatedAt', v_row."terminated_at", 'terminationReason', v_row."termination_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_contract"(uuid) from public, anon;
grant execute on function "better_supabase"."get_contract"(uuid) to authenticated, service_role;

-- The contracts the caller can read, the newest first. A null tenant reads
-- every organization the caller can (a counterparty's record page).
-- renewing_before: active contracts whose notice deadline falls on or
-- before the date.
create or replace function "better_supabase"."list_contracts"(tenant uuid, status text default null, counterparty_type text default null, counterparty_id text default null, owner_id uuid default null, renewing_before date default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'counterpartyType', x."counterparty_type", 'counterpartyId', x."counterparty_id", 'ownerId', x."owner_id", 'status', x."status", 'value', x."value"::text, 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'autoRenew', x."auto_renew", 'renewalMonths', x."renewal_months", 'noticeDays', x."notice_days", 'noticeDeadline', case when x."ends_on" is null then null else x."ends_on" - x."notice_days" end, 'renewedCount', x."renewed_count", 'signatureRequestId', x."signature_request_id", 'signedAt', x."signed_at", 'terminatedAt', x."terminated_at", 'terminationReason', x."termination_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."contracts" y
    where (list_contracts.tenant is null or y."tenant_id" = list_contracts.tenant)
      and (list_contracts.status is null or y."status" = list_contracts.status)
      and (list_contracts.counterparty_type is null or (y."counterparty_type" = list_contracts.counterparty_type and y."counterparty_id" = list_contracts.counterparty_id))
      and (list_contracts.owner_id is null or y."owner_id" = list_contracts.owner_id)
      and (list_contracts.renewing_before is null or (y."status" = 'active' and case when y."ends_on" is null then null else y."ends_on" - y."notice_days" end <= list_contracts.renewing_before))
      and (list_contracts.before is null or y."created_at" < list_contracts.before)
    order by y."created_at" desc, y."id" desc
    limit least(greatest(coalesce(list_contracts.page_size, 50), 1), 200)
  ) x
$$;
revoke execute on function "better_supabase"."list_contracts"(uuid, text, text, text, uuid, date, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_contracts"(uuid, text, text, text, uuid, date, timestamptz, integer) to authenticated, service_role;

-- Renews or expires the active contracts that reached their end date: an
-- auto-renewing contract moves ends_on by its renewal period, any other
-- expires. Run it daily from a job; it returns the counts.
create or replace function "better_supabase"."run_contract_renewals"(as_of date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := coalesce(run_contract_renewals.as_of, current_date);
  v_row "better_supabase"."contracts"%rowtype;
  v_renewed integer := 0;
  v_expired integer := 0;
begin
  for v_row in
    select * from "better_supabase"."contracts" x
    where x."status" = 'active' and x."ends_on" < v_today
    for update skip locked
  loop
    if v_row."auto_renew" then
      while v_row."ends_on" < v_today loop
        v_row."ends_on" := (v_row."ends_on" + make_interval(months => v_row."renewal_months"))::date;
        v_row."renewed_count" := v_row."renewed_count" + 1;
      end loop;
      update "better_supabase"."contracts" x set "ends_on" = v_row."ends_on", "renewed_count" = v_row."renewed_count", "updated_at" = now()
        where x."id" = v_row."id";
      perform "better_supabase"."contract_schedule_renewal"(v_row."id");
      perform "better_supabase".emit_event('contract.renewed', jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'endsOn', v_row."ends_on", 'renewedCount', v_row."renewed_count"), 'contracts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract.renewed',
    category => 'data',
    target_type => 'contract',
    record_id => v_row."id"::text,
    summary => 'renewed contract ' || v_row."title" || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'contractId', v_row."id", 'endsOn', v_row."ends_on", 'renewedCount', v_row."renewed_count")
  );
      v_renewed := v_renewed + 1;
    else
      perform "better_supabase"."contract_apply_status"(v_row."id", 'expired');
      v_expired := v_expired + 1;
    end if;
  end loop;
  return jsonb_build_object('renewed', v_renewed, 'expired', v_expired);
end;
$$;
revoke execute on function "better_supabase"."run_contract_renewals"(date) from public, anon, authenticated;
grant execute on function "better_supabase"."run_contract_renewals"(date) to service_role;

-- Adds an obligation to a contract, or changes one (obligation_id).
create or replace function "better_supabase"."save_obligation"(contract_id uuid, title text, due_on date default null, owner_id uuid default null, description text default null, obligation_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_contract "better_supabase"."contracts"%rowtype;
  v_row "better_supabase"."contract_obligations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_contract from "better_supabase"."contracts" x where x."id" = save_obligation.contract_id;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_contract."tenant_id", 'contracts.write'), false)) then
    raise exception 'not allowed to change contract obligations' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if nullif(trim(save_obligation.title), '') is null then
    raise exception 'an obligation needs a title' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if save_obligation.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_contract."tenant_id" and m."user_id" = save_obligation.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if save_obligation.obligation_id is null then
    insert into "better_supabase"."contract_obligations" ("tenant_id", "contract_id", "title", "description", "due_on", "owner_id")
    values (v_contract."tenant_id", v_contract."id", trim(save_obligation.title), nullif(trim(save_obligation.description), ''), save_obligation.due_on, save_obligation.owner_id)
    returning * into v_row;
  else
    update "better_supabase"."contract_obligations" x set "title" = trim(save_obligation.title), "description" = nullif(trim(save_obligation.description), ''),
      "due_on" = save_obligation.due_on, "owner_id" = save_obligation.owner_id, "updated_at" = now()
      where x."id" = save_obligation.obligation_id and x."contract_id" = v_contract."id"
      returning * into v_row;
    if not found then
      raise exception 'obligation not found' using errcode = 'P0002', hint = 'OBLIGATION_NOT_FOUND';
    end if;
  end if;
  perform "better_supabase".emit_event('obligation.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status"), 'obligations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'obligation.saved',
    category => 'data',
    target_type => 'obligation',
    record_id => v_row."id"::text,
    summary => 'saved obligation' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'contractId', v_row."contract_id", 'title', v_row."title", 'description', v_row."description", 'dueOn', v_row."due_on", 'ownerId', v_row."owner_id", 'status', v_row."status", 'overdue', (v_row."status" = 'open' and v_row."due_on" < current_date), 'completedAt', v_row."completed_at", 'completedBy', v_row."completed_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_obligation"(uuid, text, date, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_obligation"(uuid, text, date, uuid, text, uuid) to authenticated, service_role;

-- Marks an obligation open, done or waived. Its owner may mark it too.
create or replace function "better_supabase"."set_obligation_status"(obligation_id uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."contract_obligations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contract_obligations" x where x."id" = set_obligation_status.obligation_id for update;
  if not found then
    raise exception 'obligation not found' using errcode = 'P0002', hint = 'OBLIGATION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.write'), false)) or v_row."owner_id" = auth.uid()) then
    raise exception 'not allowed to change this obligation' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if set_obligation_status.status is null or set_obligation_status.status not in ('open', 'done', 'waived') then
    raise exception 'status must be open, done or waived' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  update "better_supabase"."contract_obligations" x set "status" = set_obligation_status.status,
    "completed_at" = case when set_obligation_status.status = 'open' then null else now() end,
    "completed_by" = case when set_obligation_status.status = 'open' then null else auth.uid() end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('obligation.status_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status"), 'obligations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'obligation.status_changed',
    category => 'data',
    target_type => 'obligation',
    record_id => v_row."id"::text,
    summary => 'marked obligation' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'contractId', v_row."contract_id", 'title', v_row."title", 'description', v_row."description", 'dueOn', v_row."due_on", 'ownerId', v_row."owner_id", 'status', v_row."status", 'overdue', (v_row."status" = 'open' and v_row."due_on" < current_date), 'completedAt', v_row."completed_at", 'completedBy', v_row."completed_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_obligation_status"(uuid, text) from public, anon;
grant execute on function "better_supabase"."set_obligation_status"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_obligation"(obligation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."contract_obligations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contract_obligations" x where x."id" = delete_obligation.obligation_id;
  if not found then
    raise exception 'obligation not found' using errcode = 'P0002', hint = 'OBLIGATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.write'), false)) then
    raise exception 'not allowed to change contract obligations' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  delete from "better_supabase"."contract_obligations" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'contractId', v_row."contract_id", 'title', v_row."title", 'description', v_row."description", 'dueOn', v_row."due_on", 'ownerId', v_row."owner_id", 'status', v_row."status", 'overdue', (v_row."status" = 'open' and v_row."due_on" < current_date), 'completedAt', v_row."completed_at", 'completedBy', v_row."completed_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_obligation"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_obligation"(uuid) to authenticated, service_role;

-- The obligations the caller can read, the earliest due first.
create or replace function "better_supabase"."list_obligations"(tenant uuid, contract_id uuid default null, owner_id uuid default null, open_only boolean default false, due_before date default null, page_size integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'contractId', x."contract_id", 'title', x."title", 'description', x."description", 'dueOn', x."due_on", 'ownerId', x."owner_id", 'status', x."status", 'overdue', (x."status" = 'open' and x."due_on" < current_date), 'completedAt', x."completed_at", 'completedBy', x."completed_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."due_on" nulls last, x."created_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."contract_obligations" y
    where y."tenant_id" = list_obligations.tenant
      and (list_obligations.contract_id is null or y."contract_id" = list_obligations.contract_id)
      and (list_obligations.owner_id is null or y."owner_id" = list_obligations.owner_id)
      and (not coalesce(list_obligations.open_only, false) or y."status" = 'open')
      and (list_obligations.due_before is null or y."due_on" <= list_obligations.due_before)
    order by y."due_on" nulls last, y."created_at"
    limit least(greatest(coalesce(list_obligations.page_size, 100), 1), 500)
  ) x
$$;
revoke execute on function "better_supabase"."list_obligations"(uuid, uuid, uuid, boolean, date, integer) from public, anon;
grant execute on function "better_supabase"."list_obligations"(uuid, uuid, uuid, boolean, date, integer) to authenticated, service_role;

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."contracts_subject_merge"(subject_table text, keep text, drop text)
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
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.forms' then array['form'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."contracts" x set "counterparty_id" = v_keep where x."counterparty_type" = v_type and x."counterparty_id" = v_drop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."contracts_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."contracts_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

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
drop policy if exists bsb_tenant_scope on "better_supabase"."contracts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."contracts";
create policy bsb_tenant_scope_select on "better_supabase"."contracts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("owner_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('contracts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."contracts";
create policy bsb_tenant_scope_insert on "better_supabase"."contracts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."contracts";
create policy bsb_tenant_scope_update on "better_supabase"."contracts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."contracts";
create policy bsb_tenant_scope_delete on "better_supabase"."contracts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."contract_obligations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."contract_obligations";
create policy bsb_tenant_scope_select on "better_supabase"."contract_obligations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("owner_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('contracts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."contract_obligations";
create policy bsb_tenant_scope_insert on "better_supabase"."contract_obligations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."contract_obligations";
create policy bsb_tenant_scope_update on "better_supabase"."contract_obligations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."contract_obligations";
create policy bsb_tenant_scope_delete on "better_supabase"."contract_obligations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.contracts.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."contract_schedule_renewal"(uuid);
drop function if exists "api"."contract_apply_status"(uuid, text, text);

drop function if exists "api"."create_contract"(uuid, jsonb, jsonb);
drop function if exists "api"."update_contract"(uuid, jsonb, jsonb);

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

create or replace function "api"."create_contract"(tenant uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_contract"($1, $2) $$;
revoke execute on function "api"."create_contract"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_contract"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_contract"(contract_id uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_contract"($1, $2) $$;
revoke execute on function "api"."update_contract"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_contract"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."transition_contract"(contract_id uuid, action text, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."transition_contract"($1, $2, $3) $$;
revoke execute on function "api"."transition_contract"(uuid, text, text) from public, anon;
grant execute on function "api"."transition_contract"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."send_contract_for_signature"(contract_id uuid, signers uuid[], sign_order text default 'parallel', message text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."send_contract_for_signature"($1, $2, $3, $4) $$;
revoke execute on function "api"."send_contract_for_signature"(uuid, uuid[], text, text) from public, anon;
grant execute on function "api"."send_contract_for_signature"(uuid, uuid[], text, text) to authenticated, service_role;

create or replace function "api"."get_contract"(contract_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_contract"($1) $$;
revoke execute on function "api"."get_contract"(uuid) from public, anon;
grant execute on function "api"."get_contract"(uuid) to authenticated, service_role;

create or replace function "api"."list_contracts"(tenant uuid, status text default null, counterparty_type text default null, counterparty_id text default null, owner_id uuid default null, renewing_before date default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_contracts"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."list_contracts"(uuid, text, text, text, uuid, date, timestamptz, integer) from public, anon;
grant execute on function "api"."list_contracts"(uuid, text, text, text, uuid, date, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."run_contract_renewals"(as_of date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."run_contract_renewals"($1) $$;
revoke execute on function "api"."run_contract_renewals"(date) from public, anon, authenticated;
grant execute on function "api"."run_contract_renewals"(date) to service_role;

create or replace function "api"."save_obligation"(contract_id uuid, title text, due_on date default null, owner_id uuid default null, description text default null, obligation_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_obligation"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_obligation"(uuid, text, date, uuid, text, uuid) from public, anon;
grant execute on function "api"."save_obligation"(uuid, text, date, uuid, text, uuid) to authenticated, service_role;

create or replace function "api"."set_obligation_status"(obligation_id uuid, status text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_obligation_status"($1, $2) $$;
revoke execute on function "api"."set_obligation_status"(uuid, text) from public, anon;
grant execute on function "api"."set_obligation_status"(uuid, text) to authenticated, service_role;

create or replace function "api"."delete_obligation"(obligation_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_obligation"($1) $$;
revoke execute on function "api"."delete_obligation"(uuid) from public, anon;
grant execute on function "api"."delete_obligation"(uuid) to authenticated, service_role;

create or replace function "api"."list_obligations"(tenant uuid, contract_id uuid default null, owner_id uuid default null, open_only boolean default false, due_before date default null, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_obligations"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."list_obligations"(uuid, uuid, uuid, boolean, date, integer) from public, anon;
grant execute on function "api"."list_obligations"(uuid, uuid, uuid, boolean, date, integer) to authenticated, service_role;

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
