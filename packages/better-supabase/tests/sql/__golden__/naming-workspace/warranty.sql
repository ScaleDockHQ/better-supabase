-- ==== schema supabase/schemas/900_better_supabase_161_warranty.sql
-- better-supabase module: warranty
-- @bsb-block warranty@1 managed
-- @bsb-hash sha256:ce594a3b5d7c78761a9e24f6ae64c5d80c84de6288bb2e22e1d93a711975d078
-- Warranty claims for an asset: the supplier or manufacturer, the covered amount, a status, a decision and attachments on the claim.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warranty claims: a supplier or manufacturer, an asset, a covered amount and
-- a decision. Status moves draft, submitted, approved or denied, then closed.

create table "better_supabase"."warranty_claims" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null constraint bsb_warranty_claims_title_check check (char_length("title") >= 1 and char_length("title") <= 200),
  "supplier_id" uuid,
  "manufacturer" text,
  "asset_id" uuid not null,
  "amount" bigint not null constraint bsb_warranty_claims_amount_check check ("amount" >= 0),
  "currency" text not null constraint bsb_warranty_claims_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "status" text not null default 'draft' constraint bsb_warranty_claims_status_check check ("status" in ('draft', 'submitted', 'approved', 'denied', 'closed')),
  "decision" text,
  "decided_at" timestamptz,
  "decided_by" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  -- A claim names the supplier, the manufacturer, or both.
  constraint bsb_warranty_claims_check check ("supplier_id" is not null or nullif(btrim("manufacturer"), '') is not null),
  unique ("tenant_id", "id")
);
create index "bsb_warranty_claims_asset_idx" on "better_supabase"."warranty_claims" ("tenant_id", "asset_id");
create index "bsb_warranty_claims_status_idx" on "better_supabase"."warranty_claims" ("tenant_id", "status");
alter table "better_supabase"."warranty_claims" enable row level security;
revoke all on "better_supabase"."warranty_claims" from public, anon, authenticated;
grant select on "better_supabase"."warranty_claims" to authenticated;
grant all on "better_supabase"."warranty_claims" to service_role;
create policy bsb_warranty_claims_read on "better_supabase"."warranty_claims"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('warranty.read')));

-- A draft claim for an asset, covered for amount in currency's minor units.
-- supplierId or manufacturer is required. Needs warranty.write.
create or replace function "better_supabase"."create_warranty_claim"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."warranty_claims";
  v_title text;
  v_asset text;
  v_supplier text;
  v_manufacturer text;
  v_amount text;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_warranty_claim.tenant is not null and coalesce(better_supabase.can('tenant', create_warranty_claim.tenant, 'warranty.write'), false))) then
    raise exception 'not allowed to write warranty claims' using errcode = '42501', hint = 'WARRANTY_FORBIDDEN';
  end if;
  if jsonb_typeof(create_warranty_claim.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  v_title := btrim(create_warranty_claim.input ->> 'title');
  v_asset := nullif(create_warranty_claim.input ->> 'assetId', '');
  v_supplier := nullif(create_warranty_claim.input ->> 'supplierId', '');
  v_manufacturer := nullif(btrim(create_warranty_claim.input ->> 'manufacturer'), '');
  v_amount := create_warranty_claim.input ->> 'amount';
  v_currency := upper(btrim(create_warranty_claim.input ->> 'currency'));
  if v_title is null or char_length(v_title) not between 1 and 200 then
    raise exception 'title must be 1 to 200 characters' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_asset is null or v_asset !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    raise exception 'assetId must be a uuid' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_supplier is not null and v_supplier !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    raise exception 'supplierId must be a uuid' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_supplier is null and v_manufacturer is null then
    raise exception 'a claim names a supplier or a manufacturer' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_amount is null or v_amount !~ '^[0-9]+$' then
    raise exception 'amount is minor units, as digits' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is an ISO 4217 code' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  insert into "better_supabase"."warranty_claims" (
    "tenant_id", "title", "supplier_id", "manufacturer", "asset_id",
    "amount", "currency", "created_by"
  ) values (
    create_warranty_claim.tenant, v_title, v_supplier::uuid, v_manufacturer, v_asset::uuid,
    v_amount::bigint, v_currency, auth.uid()
  ) returning * into v_row;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'organizationId', v_row."tenant_id",
    'title', v_row."title",
    'assetId', v_row."asset_id",
    'supplierId', v_row."supplier_id",
    'manufacturer', v_row."manufacturer",
    'amount', v_row."amount"::text,
    'currency', v_row."currency",
    'status', v_row."status",
    'decision', v_row."decision",
    'decidedAt', v_row."decided_at",
    'decidedBy', v_row."decided_by");
end;
$$;
revoke execute on function "better_supabase"."create_warranty_claim"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_warranty_claim"(uuid, jsonb) to authenticated, service_role;

-- draft -> submitted. Needs warranty.write.
create or replace function "better_supabase"."submit_warranty_claim"(claim_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."warranty_claims";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."warranty_claims" x where x."id" = submit_warranty_claim.claim_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.read'), false))) then
    raise exception 'no such warranty claim' using errcode = 'P0002', hint = 'WARRANTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.write'), false))) then
    raise exception 'not allowed to write warranty claims' using errcode = '42501', hint = 'WARRANTY_FORBIDDEN';
  end if;
  if v_row."status" is distinct from 'draft' then
    raise exception 'that status change is not allowed' using errcode = '42501', hint = 'WARRANTY_TRANSITION';
  end if;
  update "better_supabase"."warranty_claims" x set "status" = 'submitted', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'organizationId', v_row."tenant_id",
    'title', v_row."title",
    'assetId', v_row."asset_id",
    'supplierId', v_row."supplier_id",
    'manufacturer', v_row."manufacturer",
    'amount', v_row."amount"::text,
    'currency', v_row."currency",
    'status', v_row."status",
    'decision', v_row."decision",
    'decidedAt', v_row."decided_at",
    'decidedBy', v_row."decided_by");
end;
$$;
revoke execute on function "better_supabase"."submit_warranty_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."submit_warranty_claim"(uuid) to authenticated, service_role;

-- submitted -> approved or denied, then either -> closed.
-- Approving or denying stores the decision. Needs warranty.decide.
-- The state machine allows the same edges when it is installed.
create or replace function "better_supabase"."decide_warranty_claim"(claim_id uuid, next_status text, decision text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."warranty_claims";
  v_decision text := nullif(btrim(decide_warranty_claim.decision), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."warranty_claims" x where x."id" = decide_warranty_claim.claim_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.read'), false))) then
    raise exception 'no such warranty claim' using errcode = 'P0002', hint = 'WARRANTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.decide'), false))) then
    raise exception 'not allowed to decide warranty claims' using errcode = '42501', hint = 'WARRANTY_FORBIDDEN';
  end if;
  if not (
    (v_row."status" = 'submitted' and decide_warranty_claim.next_status in ('approved', 'denied'))
    or (v_row."status" in ('approved', 'denied') and decide_warranty_claim.next_status = 'closed')
  ) then
    raise exception 'that status change is not allowed' using errcode = '42501', hint = 'WARRANTY_TRANSITION';
  end if;
  if decide_warranty_claim.next_status in ('approved', 'denied') and v_decision is null then
    raise exception 'a decision says why the claim was approved or denied' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  update "better_supabase"."warranty_claims" x set
    "status" = decide_warranty_claim.next_status,
    "decision" = case when decide_warranty_claim.next_status in ('approved', 'denied') then v_decision else x."decision" end,
    "decided_at" = case when decide_warranty_claim.next_status in ('approved', 'denied') then now() else x."decided_at" end,
    "decided_by" = case when decide_warranty_claim.next_status in ('approved', 'denied') then auth.uid() else x."decided_by" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" = 'closed' then
    null;
  else
    null;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'organizationId', v_row."tenant_id",
    'title', v_row."title",
    'assetId', v_row."asset_id",
    'supplierId', v_row."supplier_id",
    'manufacturer', v_row."manufacturer",
    'amount', v_row."amount"::text,
    'currency', v_row."currency",
    'status', v_row."status",
    'decision', v_row."decision",
    'decidedAt', v_row."decided_at",
    'decidedBy', v_row."decided_by");
end;
$$;
revoke execute on function "better_supabase"."decide_warranty_claim"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_warranty_claim"(uuid, text, text) to authenticated, service_role;

-- Claims of an organization, newest first. filters is { status, assetId, limit, offset }.
-- Needs warranty.read.
create or replace function "better_supabase"."list_warranty_claims"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_warranty_claims.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_status text := nullif(v_filters ->> 'status', '');
  v_asset text := nullif(v_filters ->> 'assetId', '');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_warranty_claims.tenant is not null and coalesce(better_supabase.can('tenant', list_warranty_claims.tenant, 'warranty.read'), false))) then
    raise exception 'not allowed to read warranty claims' using errcode = '42501', hint = 'WARRANTY_FORBIDDEN';
  end if;
  if v_status is not null and v_status not in ('draft', 'submitted', 'approved', 'denied', 'closed') then
    raise exception 'status is not a warranty status' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_asset is not null and v_asset !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    raise exception 'assetId must be a uuid' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
    'id', x."id",
    'organizationId', x."tenant_id",
    'title', x."title",
    'assetId', x."asset_id",
    'supplierId', x."supplier_id",
    'manufacturer', x."manufacturer",
    'amount', x."amount"::text,
    'currency', x."currency",
    'status', x."status",
    'decision', x."decision",
    'decidedAt', x."decided_at",
    'decidedBy', x."decided_by") order by x."created_at" desc, x."id")
    from (
      select * from "better_supabase"."warranty_claims" y
      where y."tenant_id" = list_warranty_claims.tenant
        and (v_status is null or y."status" = v_status)
        and (v_asset is null or y."asset_id" = v_asset::uuid)
      order by y."created_at" desc, y."id"
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_warranty_claims"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_warranty_claims"(uuid, jsonb) to authenticated, service_role;
create trigger bsb_transition_warranty_claim before insert or update of "status" on "better_supabase"."warranty_claims"
for each row execute function better_supabase.bsb_transition_warranty_claim();

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."warranty_claims" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warranty.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."warranty_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."warranty_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."warranty_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_161_warranty.sql
-- better-supabase module: warranty
-- @bsb-block-data warranty
-- @bsb-hash sha256:411543576e589c7c77f423cb069ffdaa5d251fbb8b63d1529607528043cef875
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('warranty', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
