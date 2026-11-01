-- ==== alone: schema supabase/schemas/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block deals@1 managed
-- @bsb-hash sha256:5b20024bc5b83d6b609b3e0869170cc3c34d861ec707a046cf5d2f7e77badbf4
-- Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."deals" from public, anon, authenticated;
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
revoke all on "better_supabase"."deal_contacts" from public, anon, authenticated;
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
revoke all on "better_supabase"."deal_members" from public, anon, authenticated;
grant select on "better_supabase"."deal_members" to authenticated;
grant all on "better_supabase"."deal_members" to service_role;

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
drop policy if exists deals_read on "better_supabase"."deals";
create policy deals_read on "better_supabase"."deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')));
drop policy if exists deal_contacts_read on "better_supabase"."deal_contacts";
create policy deal_contacts_read on "better_supabase"."deal_contacts"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'));
drop policy if exists deal_members_read on "better_supabase"."deal_members";
create policy deal_members_read on "better_supabase"."deal_members"
  for select to authenticated
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
      null;
    else
      null;
    end if;
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
  if v_company_id is not null and not false then
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
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id", "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period", "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind", "flags", "source", "note", "created_by")
    values (create_deal.tenant,
      v_seq,
      v_identifier,
      trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end,
      v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion',
      create_deal.attrs ->> 'priority',
      create_deal.attrs ->> 'product',
      (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0),
      coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')),
      coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid,
      (create_deal.attrs ->> 'stageId')::uuid,
      (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast',
      (create_deal.attrs ->> 'closeOn')::date,
      create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz,
      create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source',
      create_deal.attrs ->> 'note',
      auth.uid())
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
  null;
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
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not false then
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
    null;
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
  select * into v_row from "better_supabase"."deals" x where x."id" = close_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  select * into v_row from "better_supabase"."deals" x where x."id" = reopen_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not false then
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
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
revoke all on "better_supabase"."deal_lines" from public, anon, authenticated;
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
  if not exists (select 1 from "better_supabase"."deals" x where x."id" = v_parent and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      x.ordinality::integer
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
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_deal.archived then
    null;
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
  null;
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
    'noNextStep', x."next_at" is null,
    'overdue', coalesce(x."next_at" < now(), false)
  ) order by x."expected_close_on", x."id"), '[]'::jsonb)
  from "better_supabase"."deals" x
  left join "better_supabase"."pipeline_stages" st on st."id" = x."stage_id"
  where x."pipeline_id" = deal_health.pipeline and x."outcome" = 'open' and x."archived_at" is null);
end;
$$;
revoke execute on function "better_supabase"."deal_health"(uuid) from public, anon;
grant execute on function "better_supabase"."deal_health"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
create policy bsb_tenant_scope_select on "better_supabase"."deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
create policy bsb_tenant_scope_insert on "better_supabase"."deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
create policy bsb_tenant_scope_update on "better_supabase"."deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
create policy bsb_tenant_scope_delete on "better_supabase"."deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_select on "better_supabase"."deal_contacts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_contacts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_update on "better_supabase"."deal_contacts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_contacts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
create policy bsb_tenant_scope_select on "better_supabase"."deal_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
create policy bsb_tenant_scope_update on "better_supabase"."deal_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_select on "better_supabase"."deal_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_update on "better_supabase"."deal_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:bc42cb9cecbcea4c32998adc94b1f530ec22c47381cf471722c5a14acedbe624
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block deals@1 managed
-- @bsb-hash sha256:3747ce5d6f905f4ee2f3f27b66091a4ac494e7a9ea83fd1743e1a2d6e4b93ae1
-- Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."deals" from public, anon, authenticated;
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
revoke all on "better_supabase"."deal_contacts" from public, anon, authenticated;
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
revoke all on "better_supabase"."deal_members" from public, anon, authenticated;
grant select on "better_supabase"."deal_members" to authenticated;
grant all on "better_supabase"."deal_members" to service_role;

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
drop policy if exists deals_read on "better_supabase"."deals";
create policy deals_read on "better_supabase"."deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')));
drop policy if exists deal_contacts_read on "better_supabase"."deal_contacts";
create policy deal_contacts_read on "better_supabase"."deal_contacts"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'));
drop policy if exists deal_members_read on "better_supabase"."deal_members";
create policy deal_members_read on "better_supabase"."deal_members"
  for select to authenticated
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
    if better_supabase.import_run() is null then
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
  if v_company_id is not null and not false then
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
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id", "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period", "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind", "flags", "source", "note", "created_by")
    values (create_deal.tenant,
      v_seq,
      v_identifier,
      trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end,
      v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion',
      create_deal.attrs ->> 'priority',
      create_deal.attrs ->> 'product',
      (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0),
      coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')),
      coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid,
      (create_deal.attrs ->> 'stageId')::uuid,
      (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast',
      (create_deal.attrs ->> 'closeOn')::date,
      create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz,
      create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source',
      create_deal.attrs ->> 'note',
      auth.uid())
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
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not false then
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
  select * into v_row from "better_supabase"."deals" x where x."id" = close_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  select * into v_row from "better_supabase"."deals" x where x."id" = reopen_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not false then
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
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
revoke all on "better_supabase"."deal_lines" from public, anon, authenticated;
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
  if not exists (select 1 from "better_supabase"."deals" x where x."id" = v_parent and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      x.ordinality::integer
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
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  left join lateral (select "better_supabase"."next_activity"('deal', x."id"::text) as e) ne on true
  where x."pipeline_id" = deal_health.pipeline and x."outcome" = 'open' and x."archived_at" is null);
end;
$$;
revoke execute on function "better_supabase"."deal_health"(uuid) from public, anon;
grant execute on function "better_supabase"."deal_health"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
create policy bsb_tenant_scope_select on "better_supabase"."deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
create policy bsb_tenant_scope_insert on "better_supabase"."deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
create policy bsb_tenant_scope_update on "better_supabase"."deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
create policy bsb_tenant_scope_delete on "better_supabase"."deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_select on "better_supabase"."deal_contacts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_contacts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_update on "better_supabase"."deal_contacts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_contacts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
create policy bsb_tenant_scope_select on "better_supabase"."deal_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
create policy bsb_tenant_scope_update on "better_supabase"."deal_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_select on "better_supabase"."deal_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_update on "better_supabase"."deal_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:49c83bad4d4b53c4051e1d5ebc7fefa63bd25abd0c9109519f21f622fd4aed58
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.deals', target_type => 'deal', event_prefix => 'deal', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block deals@1 managed
-- @bsb-hash sha256:71d3f6f4ea41622d6693cabae5d62775006a0afdd93059e6b709f5015e1248ad
-- Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "app_private"."deals";
    drop policy if exists bsb_tenant_scope_select on "app_private"."deals";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."deals";
    drop policy if exists bsb_tenant_scope_update on "app_private"."deals";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."deals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."deal_contacts";
    drop policy if exists bsb_tenant_scope_select on "app_private"."deal_contacts";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."deal_contacts";
    drop policy if exists bsb_tenant_scope_update on "app_private"."deal_contacts";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."deal_contacts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."deal_members";
    drop policy if exists bsb_tenant_scope_select on "app_private"."deal_members";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."deal_members";
    drop policy if exists bsb_tenant_scope_update on "app_private"."deal_members";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."deal_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."deal_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."deal_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."deal_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."deal_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."deal_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Deals on pipelines: an amount in minor units, a company and contacts, a
-- forecast call, close-date slips, a next step and line items.

create table if not exists "app_private"."deals" (
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
create index if not exists deals_pipeline_stage_idx on "app_private"."deals" ("pipeline_id", "stage_id", "rank");
create index if not exists deals_tenant_close_idx on "app_private"."deals" ("tenant_id", "expected_close_on") where "outcome" = 'open';
create index if not exists deals_owner_idx on "app_private"."deals" ("owner_user_id");
create index if not exists deals_company_idx on "app_private"."deals" ("company_type", "company_id");
alter table "app_private"."deals" enable row level security;
revoke all on "app_private"."deals" from public, anon, authenticated;
grant select on "app_private"."deals" to authenticated;
grant all on "app_private"."deals" to service_role;

create table if not exists "app_private"."deal_contacts" (
  "tenant_id" uuid not null,
  "deal_id" uuid not null references "app_private"."deals" ("id") on delete cascade,
  "contact_type" text not null,
  "contact_id" text not null,
  "role" text,
  "is_primary" boolean not null default false,
  primary key ("deal_id", "contact_type", "contact_id")
);
create index if not exists deal_contacts_contact_idx on "app_private"."deal_contacts" ("contact_type", "contact_id");
create unique index if not exists deal_contacts_primary_idx on "app_private"."deal_contacts" ("deal_id") where "is_primary";
alter table "app_private"."deal_contacts" enable row level security;
revoke all on "app_private"."deal_contacts" from public, anon, authenticated;
grant select on "app_private"."deal_contacts" to authenticated;
grant all on "app_private"."deal_contacts" to service_role;

create table if not exists "app_private"."deal_members" (
  "tenant_id" uuid not null,
  "deal_id" uuid not null references "app_private"."deals" ("id") on delete cascade,
  "user_id" uuid not null,
  "role" text,
  primary key ("deal_id", "user_id")
);
create index if not exists deal_members_user_idx on "app_private"."deal_members" ("user_id");
alter table "app_private"."deal_members" enable row level security;
revoke all on "app_private"."deal_members" from public, anon, authenticated;
grant select on "app_private"."deal_members" to authenticated;
grant all on "app_private"."deal_members" to service_role;

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
drop policy if exists deals_read on "app_private"."deals";
create policy deals_read on "app_private"."deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')));
drop policy if exists deal_contacts_read on "app_private"."deal_contacts";
create policy deal_contacts_read on "app_private"."deal_contacts"
  for select to authenticated
  using (exists (select 1 from "app_private"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'));
drop policy if exists deal_members_read on "app_private"."deal_members";
create policy deal_members_read on "app_private"."deal_members"
  for select to authenticated
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
      null;
    else
      null;
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_deal_guard() from public, anon, authenticated;
drop trigger if exists bsb_deal_guard on "app_private"."deals";
create trigger bsb_deal_guard before insert or update on "app_private"."deals"
for each row execute function better_supabase.bsb_deal_guard();

-- Creates a deal. attrs: name, closeOn (required), amount (minor units),
-- currency, company { type, id }, ownerId, motion, priority, product, seats,
-- existingAmount, valuePeriod, pipelineId, stageId, probability, forecast,
-- nextStep, nextAt, nextKind, flags, source, note and the extra columns by
-- name. contacts: a list of { type, id, role, primary }.
create or replace function "app_private"."create_deal"(tenant uuid, attrs jsonb, contacts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deal uuid;
  v_seq bigint;
  v_identifier text;
  v_row "app_private"."deals";
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
  if v_company_id is not null and not false then
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
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "app_private"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  end if;
  begin
    insert into "app_private"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id", "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period", "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind", "flags", "source", "note", "created_by")
    values (create_deal.tenant,
      v_seq,
      v_identifier,
      trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end,
      v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion',
      create_deal.attrs ->> 'priority',
      create_deal.attrs ->> 'product',
      (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0),
      coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')),
      coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid,
      (create_deal.attrs ->> 'stageId')::uuid,
      (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast',
      (create_deal.attrs ->> 'closeOn')::date,
      create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz,
      create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source',
      create_deal.attrs ->> 'note',
      auth.uid())
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
    perform "app_private"."set_deal_contacts"(v_deal, create_deal.contacts);
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_deal;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "app_private"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "app_private"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "app_private"."deals" x where x."id" = v_deal);
end;
$$;
revoke execute on function "app_private"."create_deal"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."create_deal"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Applies a batch of { dealId, field, value } changes, each on its own:
-- a change that fails is rejected with its reason and the others stay.
-- Returns { accepted: [{ dealId, field }], rejected: [{ dealId, field, hint, reason }] }.
create or replace function "app_private"."update_deals"(changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_change jsonb;
  v_deal uuid;
  v_field text;
  v_row "app_private"."deals";
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
      select * into v_row from "app_private"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "app_private"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not false then
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
        update "app_private"."deals" x set "name" = trim(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'motion' then
        update "app_private"."deals" x set "motion" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'priority' then
        update "app_private"."deals" x set "priority" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'ownerId' then
        update "app_private"."deals" x set "owner_user_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'product' then
        update "app_private"."deals" x set "product" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'seats' then
        update "app_private"."deals" x set "seats" = (v_change -> 'value' #>> '{}')::integer where x."id" = v_deal returning * into v_row;
      when 'amount' then
        update "app_private"."deals" x set "amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'existingAmount' then
        update "app_private"."deals" x set "existing_amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'currency' then
        update "app_private"."deals" x set "currency" = upper(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'valuePeriod' then
        update "app_private"."deals" x set "value_period" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'amountSource' then
        update "app_private"."deals" x set "amount_source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'stageId' then
        update "app_private"."deals" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'probability' then
        update "app_private"."deals" x set "probability" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_deal returning * into v_row;
      when 'forecast' then
        update "app_private"."deals" x set "forecast_category" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'closeOn' then
        update "app_private"."deals" x set "expected_close_on" = (v_change -> 'value' #>> '{}')::date where x."id" = v_deal returning * into v_row;
      when 'nextStep' then
        update "app_private"."deals" x set "next_step" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'nextAt' then
        update "app_private"."deals" x set "next_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_deal returning * into v_row;
      when 'nextKind' then
        update "app_private"."deals" x set "next_kind" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'flags' then
        update "app_private"."deals" x set "flags" = coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(v_change -> 'value') when 'array' then v_change -> 'value' else '[]' end)), '{}') where x."id" = v_deal returning * into v_row;
      when 'source' then
        update "app_private"."deals" x set "source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'note' then
        update "app_private"."deals" x set "note" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'lostReason' then
        update "app_private"."deals" x set "lost_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'company' then
        update "app_private"."deals" x set "company_type" = v_change -> 'value' ->> 'type', "company_id" = v_change -> 'value' ->> 'id' where x."id" = v_deal returning * into v_row;
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
  for v_row in select * from "app_private"."deals" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$$;
revoke execute on function "app_private"."update_deals"(jsonb) from public, anon;
grant execute on function "app_private"."update_deals"(jsonb) to authenticated, service_role;

-- Closes a deal as won or lost: it moves to the first success or failure
-- stage of its pipeline, which sets its outcome.
create or replace function "app_private"."close_deal"(deal uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."deals";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."deals" x where x."id" = close_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "app_private"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
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
  update "app_private"."deals" x set "stage_id" = v_stage,
    "lost_reason" = case when close_deal.outcome = 'lost' then nullif(trim(close_deal.reason), '') end,
    "note" = case when close_deal.outcome = 'won' then coalesce(nullif(trim(close_deal.reason), ''), x."note") else x."note" end
  where x."id" = close_deal.deal;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "app_private"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "app_private"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "app_private"."deals" x where x."id" = close_deal.deal);
end;
$$;
revoke execute on function "app_private"."close_deal"(uuid, text, text) from public, anon;
grant execute on function "app_private"."close_deal"(uuid, text, text) to authenticated, service_role;

-- Opens a closed deal again in stage, or its pipeline's first open stage.
create or replace function "app_private"."reopen_deal"(deal uuid, stage uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."deals";
  v_stage uuid := reopen_deal.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."deals" x where x."id" = reopen_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "app_private"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_row."id" is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if v_stage is null then
    select st."id" into v_stage from "better_supabase"."pipeline_stages" st
    where st."pipeline_id" = v_row."pipeline_id" and st."archived_at" is null and st."outcome" = 'open'
    order by st."rank" collate "C" limit 1;
  end if;
  update "app_private"."deals" x set "stage_id" = v_stage where x."id" = reopen_deal.deal;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "app_private"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "app_private"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "app_private"."deals" x where x."id" = reopen_deal.deal);
end;
$$;
revoke execute on function "app_private"."reopen_deal"(uuid, uuid) from public, anon;
grant execute on function "app_private"."reopen_deal"(uuid, uuid) to authenticated, service_role;

-- Replaces a deal's contacts with a list of { type, id, role, primary }.
create or replace function "app_private"."set_deal_contacts"(deal uuid, contacts jsonb)
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
  select x."tenant_id" into v_tenant from "app_private"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "app_private"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not false then
      raise exception 'a contact is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_CONTACT_FORBIDDEN';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(set_deal_contacts.contacts) x where coalesce((x.value ->> 'primary')::boolean, false)) > 1 then
    raise exception 'a deal has one primary contact' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  delete from "app_private"."deal_contacts" x where x."deal_id" = v_deal;
  insert into "app_private"."deal_contacts" ("tenant_id", "deal_id", "contact_type", "contact_id", "role", "is_primary")
  select v_tenant, v_deal, coalesce(x.value ->> 'type', 'person'), x.value ->> 'id', x.value ->> 'role', coalesce((x.value ->> 'primary')::boolean, false)
  from jsonb_array_elements(set_deal_contacts.contacts) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."set_deal_contacts"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_deal_contacts"(uuid, jsonb) to authenticated, service_role;

-- Replaces a deal's team with a list of { userId, role }. Each member
-- watches the deal.
create or replace function "app_private"."set_deal_members"(deal uuid, members jsonb)
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
  select x."tenant_id" into v_tenant from "app_private"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "app_private"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_members.members, '[]')) <> 'array' then
    raise exception 'members must be a list of { userId, role }' using errcode = '22023', hint = 'DEAL_MEMBERS_INVALID';
  end if;
  delete from "app_private"."deal_members" x where x."deal_id" = v_deal;
  insert into "app_private"."deal_members" ("tenant_id", "deal_id", "user_id", "role")
  select v_tenant, v_deal, (x.value ->> 'userId')::uuid, x.value ->> 'role'
  from jsonb_array_elements(set_deal_members.members) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."set_deal_members"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_deal_members"(uuid, jsonb) to authenticated, service_role;
create table if not exists "app_private"."deal_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "app_private"."deals" ("id") on delete cascade,
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
create index if not exists "deal_lines_parent_idx" on "app_private"."deal_lines" ("parent_id", "position");
alter table "app_private"."deal_lines" enable row level security;
revoke all on "app_private"."deal_lines" from public, anon, authenticated;
grant select on "app_private"."deal_lines" to authenticated;
grant all on "app_private"."deal_lines" to service_role;
drop policy if exists "deal_lines_read" on "app_private"."deal_lines";
create policy "deal_lines_read" on "app_private"."deal_lines" for select to authenticated
using (exists (select 1 from "app_private"."deals" x where x."id" = "parent_id"));

-- Writes a record's totals from its lines. A record without lines keeps
-- zero totals.
create or replace function "app_private"."set_deal_lines_recount"(parent uuid)
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
  from "app_private"."deal_lines" l where l."parent_id" = set_deal_lines_recount.parent;
  update "app_private"."deals" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_list - v_discount,
    "tax_total" = v_tax,
    "total" = v_list - v_discount + v_tax,
    "amount" = case when x."amount_source" = 'line_items' then v_list - v_discount else x."amount" end
  where x."id" = set_deal_lines_recount.parent;
end;
$$;
revoke execute on function "app_private"."set_deal_lines_recount"(uuid) from public, anon, authenticated;

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
    perform "app_private"."set_deal_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_deal_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_deal_lines_totals on "app_private"."deal_lines";
drop trigger if exists bsb_deal_lines_totals_insert on "app_private"."deal_lines";
drop trigger if exists bsb_deal_lines_totals_update on "app_private"."deal_lines";
drop trigger if exists bsb_deal_lines_totals_delete on "app_private"."deal_lines";
create trigger bsb_deal_lines_totals_insert after insert on "app_private"."deal_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_deal_lines_totals();
create trigger bsb_deal_lines_totals_update after update on "app_private"."deal_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_deal_lines_totals();
create trigger bsb_deal_lines_totals_delete after delete on "app_private"."deal_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_deal_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function "app_private"."set_deal_lines"(parent uuid, lines jsonb)
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
  select x."tenant_id", x."currency" into v_tenant, v_currency from "app_private"."deals" x where x."id" = v_parent and not (x."locked");
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "app_private"."deals" x where x."id" = v_parent and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "app_private"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))) then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_deal_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "app_private"."deal_lines" l where l."parent_id" = v_parent;
  begin
    insert into "app_private"."deal_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_deal_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "app_private"."set_deal_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "app_private"."deals" x where x."id" = v_parent);
end;
$$;
revoke execute on function "app_private"."set_deal_lines"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_deal_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."archive_deal"(deal uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."deals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "app_private"."deals" x set "archived_at" = case when archive_deal.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "app_private"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_deal.archived then
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."archive_deal"(uuid, boolean) from public, anon;
grant execute on function "app_private"."archive_deal"(uuid, boolean) to authenticated, service_role;

-- Deletes a deal. Needs deals.manage, or the deal's owner.
create or replace function "app_private"."delete_deal"(deal uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."deals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "app_private"."deals" x
  where x."id" = delete_deal.deal
    and ((auth.role() = 'service_role') or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_deal"(uuid) from public, anon;
grant execute on function "app_private"."delete_deal"(uuid) to authenticated, service_role;

-- The forecast call for one currency between since and until: won deals
-- closed in the window, open deals closing in it by forecast category
-- (notCalled for none), later for open deals closing after it, and each
-- owner's split. target is the period goal in minor units; attainment is
-- won plus commit over it. Runs as the caller, so it sums what they see.
create or replace function "app_private"."deal_forecast"(tenant uuid, pipeline uuid, since date, until date, currency text, target bigint, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with scoped as (
    select * from "app_private"."deals" x
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
revoke execute on function "app_private"."deal_forecast"(uuid, uuid, date, date, text, bigint, uuid) from public, anon;
grant execute on function "app_private"."deal_forecast"(uuid, uuid, date, date, text, bigint, uuid) to authenticated, service_role;

-- The open deals of a pipeline the caller can see, with the checks a
-- forecast review runs: days in stage and rotting, a slipped close date,
-- no next step, and an overdue next step.
create or replace function "app_private"."deal_health"(pipeline uuid)
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
    'noNextStep', x."next_at" is null,
    'overdue', coalesce(x."next_at" < now(), false)
  ) order by x."expected_close_on", x."id"), '[]'::jsonb)
  from "app_private"."deals" x
  left join "better_supabase"."pipeline_stages" st on st."id" = x."stage_id"
  where x."pipeline_id" = deal_health.pipeline and x."outcome" = 'open' and x."archived_at" is null);
end;
$$;
revoke execute on function "app_private"."deal_health"(uuid) from public, anon;
grant execute on function "app_private"."deal_health"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."deals";
drop policy if exists bsb_tenant_scope_select on "app_private"."deals";
create policy bsb_tenant_scope_select on "app_private"."deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."deals";
create policy bsb_tenant_scope_insert on "app_private"."deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."deals";
create policy bsb_tenant_scope_update on "app_private"."deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."deals";
create policy bsb_tenant_scope_delete on "app_private"."deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."deal_contacts";
drop policy if exists bsb_tenant_scope_select on "app_private"."deal_contacts";
create policy bsb_tenant_scope_select on "app_private"."deal_contacts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "app_private"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."deal_contacts";
create policy bsb_tenant_scope_insert on "app_private"."deal_contacts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."deal_contacts";
create policy bsb_tenant_scope_update on "app_private"."deal_contacts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."deal_contacts";
create policy bsb_tenant_scope_delete on "app_private"."deal_contacts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."deal_members";
drop policy if exists bsb_tenant_scope_select on "app_private"."deal_members";
create policy bsb_tenant_scope_select on "app_private"."deal_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."deal_members";
create policy bsb_tenant_scope_insert on "app_private"."deal_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."deal_members";
create policy bsb_tenant_scope_update on "app_private"."deal_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."deal_members";
create policy bsb_tenant_scope_delete on "app_private"."deal_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."deal_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."deal_lines";
create policy bsb_tenant_scope_select on "app_private"."deal_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "app_private"."deals" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."deal_lines";
create policy bsb_tenant_scope_insert on "app_private"."deal_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."deal_lines";
create policy bsb_tenant_scope_update on "app_private"."deal_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."deal_lines";
create policy bsb_tenant_scope_delete on "app_private"."deal_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:bc42cb9cecbcea4c32998adc94b1f530ec22c47381cf471722c5a14acedbe624
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block deals@1 managed
-- @bsb-hash sha256:75f838930d834d9ee341f9634fae8eddc8eb16ca02a3920a1c256c0ef8196470
-- Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."deals" from public, anon, authenticated;
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
revoke all on "better_supabase"."deal_contacts" from public, anon, authenticated;
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
revoke all on "better_supabase"."deal_members" from public, anon, authenticated;
grant select on "better_supabase"."deal_members" to authenticated;
grant all on "better_supabase"."deal_members" to service_role;

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
drop policy if exists deals_read on "better_supabase"."deals";
create policy deals_read on "better_supabase"."deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')));
drop policy if exists deal_contacts_read on "better_supabase"."deal_contacts";
create policy deal_contacts_read on "better_supabase"."deal_contacts"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'));
drop policy if exists deal_members_read on "better_supabase"."deal_members";
create policy deal_members_read on "better_supabase"."deal_members"
  for select to authenticated
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
      null;
    else
      null;
    end if;
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
  if v_company_id is not null and not false then
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
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id", "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period", "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind", "flags", "source", "note", "created_by")
    values (create_deal.tenant,
      v_seq,
      v_identifier,
      trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end,
      v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion',
      create_deal.attrs ->> 'priority',
      create_deal.attrs ->> 'product',
      (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0),
      coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')),
      coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid,
      (create_deal.attrs ->> 'stageId')::uuid,
      (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast',
      (create_deal.attrs ->> 'closeOn')::date,
      create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz,
      create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source',
      create_deal.attrs ->> 'note',
      auth.uid())
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
  null;
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
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not false then
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
    null;
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
  select * into v_row from "better_supabase"."deals" x where x."id" = close_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  select * into v_row from "better_supabase"."deals" x where x."id" = reopen_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not false then
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
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
revoke all on "better_supabase"."deal_lines" from public, anon, authenticated;
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
  if not exists (select 1 from "better_supabase"."deals" x where x."id" = v_parent and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      x.ordinality::integer
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
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_deal.archived then
    null;
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
  null;
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
    'noNextStep', x."next_at" is null,
    'overdue', coalesce(x."next_at" < now(), false)
  ) order by x."expected_close_on", x."id"), '[]'::jsonb)
  from "better_supabase"."deals" x
  left join "better_supabase"."pipeline_stages" st on st."id" = x."stage_id"
  where x."pipeline_id" = deal_health.pipeline and x."outcome" = 'open' and x."archived_at" is null);
end;
$$;
revoke execute on function "better_supabase"."deal_health"(uuid) from public, anon;
grant execute on function "better_supabase"."deal_health"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
create policy bsb_tenant_scope_select on "better_supabase"."deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
create policy bsb_tenant_scope_insert on "better_supabase"."deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
create policy bsb_tenant_scope_update on "better_supabase"."deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
create policy bsb_tenant_scope_delete on "better_supabase"."deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_select on "better_supabase"."deal_contacts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_contacts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_update on "better_supabase"."deal_contacts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_contacts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
create policy bsb_tenant_scope_select on "better_supabase"."deal_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
create policy bsb_tenant_scope_update on "better_supabase"."deal_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_select on "better_supabase"."deal_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_update on "better_supabase"."deal_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.deals.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:bc42cb9cecbcea4c32998adc94b1f530ec22c47381cf471722c5a14acedbe624
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block deals@1 managed
-- @bsb-hash sha256:0ed7830ad6536f874fbe4f06d62757af72ad9fb0fbad55e3654d76310149460b
-- Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Deals on pipelines: an amount in minor units, a company and contacts, a
-- forecast call, close-date slips, a next step and line items.

-- better_supabase.deals is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."deals" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."deals" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."deals" add column if not exists "number" bigint;
alter table "better_supabase"."deals" add column if not exists "identifier" text;
alter table "better_supabase"."deals" add column if not exists "name" text check (length("name") between 1 and 300);
alter table "better_supabase"."deals" add column if not exists "company_type" text;
alter table "better_supabase"."deals" add column if not exists "company_id" text;
alter table "better_supabase"."deals" add column if not exists "motion" text;
alter table "better_supabase"."deals" add column if not exists "priority" text;
alter table "better_supabase"."deals" add column if not exists "owner_user_id" uuid;
alter table "better_supabase"."deals" add column if not exists "product" text;
alter table "better_supabase"."deals" add column if not exists "seats" integer check ("seats" >= 0);
alter table "better_supabase"."deals" add column if not exists "amount" bigint not null default 0 check ("amount" >= 0);
alter table "better_supabase"."deals" add column if not exists "existing_amount" bigint not null default 0 check ("existing_amount" >= 0);
alter table "better_supabase"."deals" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."deals" add column if not exists "value_period" text not null default 'one_time' check ("value_period" in ('one_time', 'monthly', 'annual'));
alter table "better_supabase"."deals" add column if not exists "amount_source" text not null default 'manual' check ("amount_source" in ('manual', 'line_items'));
alter table "better_supabase"."deals" add column if not exists "pipeline_id" uuid;
alter table "better_supabase"."deals" add column if not exists "stage_id" uuid;
alter table "better_supabase"."deals" add column if not exists "stage_entered_at" timestamptz;
alter table "better_supabase"."deals" add column if not exists "outcome" text not null default 'open' check ("outcome" in ('open', 'won', 'lost'));
alter table "better_supabase"."deals" add column if not exists "probability" smallint check ("probability" >= 0 and "probability" <= 100);
alter table "better_supabase"."deals" add column if not exists "forecast_category" text check ("forecast_category" in ('commit', 'best_case', 'pipeline', 'omit'));
alter table "better_supabase"."deals" add column if not exists "opened_on" date not null default current_date;
alter table "better_supabase"."deals" add column if not exists "expected_close_on" date;
alter table "better_supabase"."deals" add column if not exists "slipped_from" date;
alter table "better_supabase"."deals" add column if not exists "push_count" integer not null default 0;
alter table "better_supabase"."deals" add column if not exists "closed_at" timestamptz;
alter table "better_supabase"."deals" add column if not exists "next_step" text;
alter table "better_supabase"."deals" add column if not exists "next_at" timestamptz;
alter table "better_supabase"."deals" add column if not exists "next_kind" text;
alter table "better_supabase"."deals" add column if not exists "flags" text[] not null default '{}';
alter table "better_supabase"."deals" add column if not exists "source" text;
alter table "better_supabase"."deals" add column if not exists "note" text;
alter table "better_supabase"."deals" add column if not exists "lost_reason" text;
alter table "better_supabase"."deals" add column if not exists "locked" boolean not null default false;
alter table "better_supabase"."deals" add column if not exists "rank" text collate "C" not null default 'V';
alter table "better_supabase"."deals" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."deals" add column if not exists "created_by" uuid;
alter table "better_supabase"."deals" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."deals" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."deals" add column if not exists "list_total" bigint not null default 0;
alter table "better_supabase"."deals" add column if not exists "discount_total" bigint not null default 0;
alter table "better_supabase"."deals" add column if not exists "subtotal" bigint not null default 0;
alter table "better_supabase"."deals" add column if not exists "tax_total" bigint not null default 0;
alter table "better_supabase"."deals" add column if not exists "total" bigint not null default 0;
create index if not exists deals_pipeline_stage_idx on "better_supabase"."deals" ("pipeline_id", "stage_id", "rank");
create index if not exists deals_tenant_close_idx on "better_supabase"."deals" ("tenant_id", "expected_close_on") where "outcome" = 'open';
create index if not exists deals_owner_idx on "better_supabase"."deals" ("owner_user_id");
create index if not exists deals_company_idx on "better_supabase"."deals" ("company_type", "company_id");
alter table "better_supabase"."deals" enable row level security;
grant select on "better_supabase"."deals" to authenticated;
grant all on "better_supabase"."deals" to service_role;

-- better_supabase.deal_contacts is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."deal_contacts" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."deal_contacts" add column if not exists "deal_id" uuid references "better_supabase"."deals" ("id") on delete cascade;
alter table "better_supabase"."deal_contacts" add column if not exists "contact_type" text;
alter table "better_supabase"."deal_contacts" add column if not exists "contact_id" text;
alter table "better_supabase"."deal_contacts" add column if not exists "role" text;
alter table "better_supabase"."deal_contacts" add column if not exists "is_primary" boolean not null default false;
create unique index if not exists "bsb_deal_contacts_contact_key" on "better_supabase"."deal_contacts" ("deal_id", "contact_type", "contact_id");
create index if not exists deal_contacts_contact_idx on "better_supabase"."deal_contacts" ("contact_type", "contact_id");
create unique index if not exists deal_contacts_primary_idx on "better_supabase"."deal_contacts" ("deal_id") where "is_primary";
alter table "better_supabase"."deal_contacts" enable row level security;
grant select on "better_supabase"."deal_contacts" to authenticated;
grant all on "better_supabase"."deal_contacts" to service_role;

-- better_supabase.deal_members is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."deal_members" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."deal_members" add column if not exists "deal_id" uuid references "better_supabase"."deals" ("id") on delete cascade;
alter table "better_supabase"."deal_members" add column if not exists "user_id" uuid;
alter table "better_supabase"."deal_members" add column if not exists "role" text;
create unique index if not exists "bsb_deal_members_user_key" on "better_supabase"."deal_members" ("deal_id", "user_id");
create index if not exists deal_members_user_idx on "better_supabase"."deal_members" ("user_id");
alter table "better_supabase"."deal_members" enable row level security;
grant select on "better_supabase"."deal_members" to authenticated;
grant all on "better_supabase"."deal_members" to service_role;

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
drop policy if exists bsb_deals_select on "better_supabase"."deals";
create policy bsb_deals_select on "better_supabase"."deals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')));
drop policy if exists bsb_deal_contacts_select on "better_supabase"."deal_contacts";
create policy bsb_deal_contacts_select on "better_supabase"."deal_contacts"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'));
drop policy if exists bsb_deal_members_select on "better_supabase"."deal_members";
create policy bsb_deal_members_select on "better_supabase"."deal_members"
  for select to authenticated
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
      null;
    else
      null;
    end if;
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
  if v_company_id is not null and not false then
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
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id", "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period", "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind", "flags", "source", "note", "created_by")
    values (create_deal.tenant,
      v_seq,
      v_identifier,
      trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end,
      v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion',
      create_deal.attrs ->> 'priority',
      create_deal.attrs ->> 'product',
      (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0),
      coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')),
      better_supabase.as_column_type(coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'), (null::"better_supabase"."deals")."value_period"),
      (create_deal.attrs ->> 'pipelineId')::uuid,
      (create_deal.attrs ->> 'stageId')::uuid,
      (create_deal.attrs ->> 'probability')::smallint,
      better_supabase.as_column_type(create_deal.attrs ->> 'forecast', (null::"better_supabase"."deals")."forecast_category"),
      (create_deal.attrs ->> 'closeOn')::date,
      create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz,
      create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source',
      create_deal.attrs ->> 'note',
      auth.uid())
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
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_deal;
    end if;
  end;
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'number', x."number"::text, 'identifier', x."identifier", 'name', x."name", 'company_type', x."company_type", 'company_id', x."company_id", 'motion', x."motion", 'priority', x."priority", 'owner_user_id', x."owner_user_id", 'product', x."product", 'seats', x."seats", 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'currency', x."currency", 'value_period', x."value_period", 'amount_source', x."amount_source", 'pipeline_id', x."pipeline_id", 'stage_id', x."stage_id", 'stage_entered_at', x."stage_entered_at", 'outcome', x."outcome", 'probability', x."probability", 'forecast_category', x."forecast_category", 'opened_on', x."opened_on", 'expected_close_on', x."expected_close_on", 'slipped_from', x."slipped_from", 'push_count', x."push_count", 'closed_at', x."closed_at", 'next_step', x."next_step", 'next_at', x."next_at", 'next_kind', x."next_kind", 'flags', x."flags", 'source', x."source", 'note', x."note", 'lost_reason', x."lost_reason", 'locked', x."locked", 'rank', x."rank", 'archived_at', x."archived_at", 'created_by', x."created_by", 'created_at', x."created_at") || jsonb_build_object('updated_at', x."updated_at", 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
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
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not false then
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
        update "better_supabase"."deals" x set "value_period" = better_supabase.as_column_type(nullif(trim(v_change -> 'value' #>> '{}'), ''), (null::"better_supabase"."deals")."value_period") where x."id" = v_deal returning * into v_row;
      when 'amountSource' then
        update "better_supabase"."deals" x set "amount_source" = better_supabase.as_column_type(nullif(trim(v_change -> 'value' #>> '{}'), ''), (null::"better_supabase"."deals")."amount_source") where x."id" = v_deal returning * into v_row;
      when 'stageId' then
        update "better_supabase"."deals" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'probability' then
        update "better_supabase"."deals" x set "probability" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_deal returning * into v_row;
      when 'forecast' then
        update "better_supabase"."deals" x set "forecast_category" = better_supabase.as_column_type(nullif(trim(v_change -> 'value' #>> '{}'), ''), (null::"better_supabase"."deals")."forecast_category") where x."id" = v_deal returning * into v_row;
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
    null;
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
  select * into v_row from "better_supabase"."deals" x where x."id" = close_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'number', x."number"::text, 'identifier', x."identifier", 'name', x."name", 'company_type', x."company_type", 'company_id', x."company_id", 'motion', x."motion", 'priority', x."priority", 'owner_user_id', x."owner_user_id", 'product', x."product", 'seats', x."seats", 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'currency', x."currency", 'value_period', x."value_period", 'amount_source', x."amount_source", 'pipeline_id', x."pipeline_id", 'stage_id', x."stage_id", 'stage_entered_at', x."stage_entered_at", 'outcome', x."outcome", 'probability', x."probability", 'forecast_category', x."forecast_category", 'opened_on', x."opened_on", 'expected_close_on', x."expected_close_on", 'slipped_from', x."slipped_from", 'push_count', x."push_count", 'closed_at', x."closed_at", 'next_step', x."next_step", 'next_at', x."next_at", 'next_kind', x."next_kind", 'flags', x."flags", 'source', x."source", 'note', x."note", 'lost_reason', x."lost_reason", 'locked', x."locked", 'rank', x."rank", 'archived_at', x."archived_at", 'created_by', x."created_by", 'created_at', x."created_at") || jsonb_build_object('updated_at', x."updated_at", 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
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
  select * into v_row from "better_supabase"."deals" x where x."id" = reopen_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  return (select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'number', x."number"::text, 'identifier', x."identifier", 'name', x."name", 'company_type', x."company_type", 'company_id', x."company_id", 'motion', x."motion", 'priority', x."priority", 'owner_user_id', x."owner_user_id", 'product', x."product", 'seats', x."seats", 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'currency', x."currency", 'value_period', x."value_period", 'amount_source', x."amount_source", 'pipeline_id', x."pipeline_id", 'stage_id', x."stage_id", 'stage_entered_at', x."stage_entered_at", 'outcome', x."outcome", 'probability', x."probability", 'forecast_category', x."forecast_category", 'opened_on', x."opened_on", 'expected_close_on', x."expected_close_on", 'slipped_from', x."slipped_from", 'push_count', x."push_count", 'closed_at', x."closed_at", 'next_step', x."next_step", 'next_at', x."next_at", 'next_kind', x."next_kind", 'flags', x."flags", 'source', x."source", 'note', x."note", 'lost_reason', x."lost_reason", 'locked', x."locked", 'rank', x."rank", 'archived_at', x."archived_at", 'created_by', x."created_by", 'created_at', x."created_at") || jsonb_build_object('updated_at', x."updated_at", 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
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
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not false then
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
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_deal_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_deal_members"(uuid, jsonb) to authenticated, service_role;
-- better_supabase.deal_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."deal_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."deal_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."deal_lines" add column if not exists "parent_id" uuid references "better_supabase"."deals" ("id") on delete cascade;
alter table "better_supabase"."deal_lines" add column if not exists "product_type" text;
alter table "better_supabase"."deal_lines" add column if not exists "product_id" text;
alter table "better_supabase"."deal_lines" add column if not exists "description" text check (length("description") between 1 and 2000);
alter table "better_supabase"."deal_lines" add column if not exists "quantity" numeric(18, 4) check ("quantity" > 0);
alter table "better_supabase"."deal_lines" add column if not exists "unit_amount" bigint;
alter table "better_supabase"."deal_lines" add column if not exists "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000);
alter table "better_supabase"."deal_lines" add column if not exists "tax_rate_bps" integer not null default 0 check ("tax_rate_bps" >= 0 and "tax_rate_bps" <= 100000);
alter table "better_supabase"."deal_lines" add column if not exists "tax_code" text;
alter table "better_supabase"."deal_lines" add column if not exists "position" integer;
alter table "better_supabase"."deal_lines" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "deal_lines_parent_idx" on "better_supabase"."deal_lines" ("parent_id", "position");
create unique index if not exists "bsb_deal_lines_position_key" on "better_supabase"."deal_lines" ("parent_id", "position");
alter table "better_supabase"."deal_lines" enable row level security;
grant select on "better_supabase"."deal_lines" to authenticated;
grant all on "better_supabase"."deal_lines" to service_role;
drop policy if exists bsb_deal_lines_select on "better_supabase"."deal_lines";
create policy bsb_deal_lines_select on "better_supabase"."deal_lines" for select to authenticated
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
  if not exists (select 1 from "better_supabase"."deals" x where x."id" = v_parent and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
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
  delete from "better_supabase"."deal_lines" l where l."parent_id" = v_parent and l."position" > jsonb_array_length(coalesce(set_deal_lines.lines, '[]'));
  begin
    insert into "better_supabase"."deal_lines" as l ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select v_tenant,
      v_parent,
      better_supabase.as_column_type(x.value -> 'product' ->> 'type', (null::"better_supabase"."deal_lines")."product_type"),
      better_supabase.as_column_type(x.value -> 'product' ->> 'id', (null::"better_supabase"."deal_lines")."product_id"),
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_deal_lines.lines, '[]')) with ordinality x
    on conflict ("parent_id", "position") do update set "product_type" = excluded."product_type", "product_id" = excluded."product_id", "description" = excluded."description", "quantity" = excluded."quantity", "unit_amount" = excluded."unit_amount", "discount_bps" = excluded."discount_bps", "tax_rate_bps" = excluded."tax_rate_bps", "tax_code" = excluded."tax_code";
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
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_deal.archived then
    null;
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
  null;
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
    'noNextStep', x."next_at" is null,
    'overdue', coalesce(x."next_at" < now(), false)
  ) order by x."expected_close_on", x."id"), '[]'::jsonb)
  from "better_supabase"."deals" x
  left join "better_supabase"."pipeline_stages" st on st."id" = x."stage_id"
  where x."pipeline_id" = deal_health.pipeline and x."outcome" = 'open' and x."archived_at" is null);
end;
$$;
revoke execute on function "better_supabase"."deal_health"(uuid) from public, anon;
grant execute on function "better_supabase"."deal_health"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
create policy bsb_tenant_scope_select on "better_supabase"."deals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
create policy bsb_tenant_scope_insert on "better_supabase"."deals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
create policy bsb_tenant_scope_update on "better_supabase"."deals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
create policy bsb_tenant_scope_delete on "better_supabase"."deals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_select on "better_supabase"."deal_contacts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_contacts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_update on "better_supabase"."deal_contacts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_contacts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
create policy bsb_tenant_scope_select on "better_supabase"."deal_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
create policy bsb_tenant_scope_update on "better_supabase"."deal_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_select on "better_supabase"."deal_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_update on "better_supabase"."deal_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:bc42cb9cecbcea4c32998adc94b1f530ec22c47381cf471722c5a14acedbe624
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block deals@1 managed
-- @bsb-hash sha256:bc754c003bfd7eb33722e784c2b9596c6f5a4ce46647f5b9b783d076a2cf9da1
-- Deals on pipelines: amounts in minor units, a company and contacts, a deal team, line items, forecast calls with attainment, close-date slips, a next step, locking and batched edits with per-change rejections.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Deals on pipelines: an amount in minor units, a company and contacts, a
-- forecast call, close-date slips, a next step and line items.

create table if not exists "better_supabase"."deals" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
  unique ("org_id", "number"),
  check (("company_type" is null) = ("company_id" is null))
);
create index if not exists deals_pipeline_stage_idx on "better_supabase"."deals" ("pipeline_id", "stage_id", "rank");
create index if not exists deals_tenant_close_idx on "better_supabase"."deals" ("org_id", "expected_close_on") where "outcome" = 'open';
create index if not exists deals_owner_idx on "better_supabase"."deals" ("owner_user_id");
create index if not exists deals_company_idx on "better_supabase"."deals" ("company_type", "company_id");
alter table "better_supabase"."deals" enable row level security;
revoke all on "better_supabase"."deals" from public, anon, authenticated;
grant select on "better_supabase"."deals" to authenticated;
grant all on "better_supabase"."deals" to service_role;

create table if not exists "better_supabase"."deal_contacts" (
  "org_id" uuid not null,
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
revoke all on "better_supabase"."deal_contacts" from public, anon, authenticated;
grant select on "better_supabase"."deal_contacts" to authenticated;
grant all on "better_supabase"."deal_contacts" to service_role;

create table if not exists "better_supabase"."deal_members" (
  "org_id" uuid not null,
  "deal_id" uuid not null references "better_supabase"."deals" ("id") on delete cascade,
  "user_id" uuid not null,
  "role" text,
  primary key ("deal_id", "user_id")
);
create index if not exists deal_members_user_idx on "better_supabase"."deal_members" ("user_id");
alter table "better_supabase"."deal_members" enable row level security;
revoke all on "better_supabase"."deal_members" from public, anon, authenticated;
grant select on "better_supabase"."deal_members" to authenticated;
grant all on "better_supabase"."deal_members" to service_role;

-- A deal is visible to members with deals.read; with readAll off, only to
-- its owner, its team and members with deals.manage. The team policy reads
-- no deal, so the two policies don't recurse.
drop policy if exists deals_read on "better_supabase"."deals";
create policy deals_read on "better_supabase"."deals"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('deals.read')));
drop policy if exists deal_contacts_read on "better_supabase"."deal_contacts";
create policy deal_contacts_read on "better_supabase"."deal_contacts"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'));
drop policy if exists deal_members_read on "better_supabase"."deal_members";
create policy deal_members_read on "better_supabase"."deal_members"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('deals.read')));

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
      null;
    else
      null;
    end if;
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
  if v_company_id is not null and not false then
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
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."org_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."deals" ("org_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id", "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period", "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind", "flags", "source", "note", "created_by")
    values (create_deal.tenant,
      v_seq,
      v_identifier,
      trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end,
      v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion',
      create_deal.attrs ->> 'priority',
      create_deal.attrs ->> 'product',
      (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0),
      coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')),
      coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid,
      (create_deal.attrs ->> 'stageId')::uuid,
      (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast',
      (create_deal.attrs ->> 'closeOn')::date,
      create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz,
      create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source',
      create_deal.attrs ->> 'note',
      auth.uid())
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
  null;
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
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."org_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."org_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not false then
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
    null;
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
  select * into v_row from "better_supabase"."deals" x where x."id" = close_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."org_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."org_id", 'deals.manage'), false)
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
  select * into v_row from "better_supabase"."deals" x where x."id" = reopen_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."org_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."org_id", 'deals.manage'), false)
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
  select x."org_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."org_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."org_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not false then
      raise exception 'a contact is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_CONTACT_FORBIDDEN';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(set_deal_contacts.contacts) x where coalesce((x.value ->> 'primary')::boolean, false)) > 1 then
    raise exception 'a deal has one primary contact' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  delete from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_contacts" ("org_id", "deal_id", "contact_type", "contact_id", "role", "is_primary")
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
  select x."org_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."org_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."org_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_members.members, '[]')) <> 'array' then
    raise exception 'members must be a list of { userId, role }' using errcode = '22023', hint = 'DEAL_MEMBERS_INVALID';
  end if;
  delete from "better_supabase"."deal_members" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_members" ("org_id", "deal_id", "user_id", "role")
  select v_tenant, v_deal, (x.value ->> 'userId')::uuid, x.value ->> 'role'
  from jsonb_array_elements(set_deal_members.members) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_deal_members"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_deal_members"(uuid, jsonb) to authenticated, service_role;
create table if not exists "better_supabase"."deal_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
revoke all on "better_supabase"."deal_lines" from public, anon, authenticated;
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
  select x."org_id", x."currency" into v_tenant, v_currency from "better_supabase"."deals" x where x."id" = v_parent and not (x."locked");
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."deals" x where x."id" = v_parent and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."org_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."org_id", 'deals.manage'), false)
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
    insert into "better_supabase"."deal_lines" ("org_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      x.ordinality::integer
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
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."org_id", 'deals.write'), false) and (true or coalesce(x."owner_user_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."org_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_deal.archived then
    null;
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
    and ((auth.role() = 'service_role') or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."org_id", 'deals.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  null;
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
    where x."org_id" = deal_forecast.tenant
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
    'noNextStep', x."next_at" is null,
    'overdue', coalesce(x."next_at" < now(), false)
  ) order by x."expected_close_on", x."id"), '[]'::jsonb)
  from "better_supabase"."deals" x
  left join "better_supabase"."pipeline_stages" st on st."id" = x."stage_id"
  where x."pipeline_id" = deal_health.pipeline and x."outcome" = 'open' and x."archived_at" is null);
end;
$$;
revoke execute on function "better_supabase"."deal_health"(uuid) from public, anon;
grant execute on function "better_supabase"."deal_health"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."deals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deals";
create policy bsb_tenant_scope_select on "better_supabase"."deals" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deals";
create policy bsb_tenant_scope_insert on "better_supabase"."deals" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deals";
create policy bsb_tenant_scope_update on "better_supabase"."deals" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deals";
create policy bsb_tenant_scope_delete on "better_supabase"."deals" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_contacts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_select on "better_supabase"."deal_contacts" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "deal_id") and "better_supabase"."can_subject"("contact_type", "contact_id", 'read'))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_contacts" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_update on "better_supabase"."deal_contacts" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_contacts";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_contacts" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_members";
create policy bsb_tenant_scope_select on "better_supabase"."deal_members" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('deals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_members";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_members" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_members";
create policy bsb_tenant_scope_update on "better_supabase"."deal_members" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_members";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_members" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."deal_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_select on "better_supabase"."deal_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."deals" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."deal_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_update on "better_supabase"."deal_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."deal_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."deal_lines" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_091_deals.sql
-- better-supabase module: deals
-- @bsb-block-data deals
-- @bsb-hash sha256:bc42cb9cecbcea4c32998adc94b1f530ec22c47381cf471722c5a14acedbe624
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('deals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
