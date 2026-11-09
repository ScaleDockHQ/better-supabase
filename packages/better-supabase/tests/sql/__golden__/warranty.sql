-- ==== alone: schema supabase/schemas/900_better_supabase_161_warranty.sql
-- better-supabase module: warranty
-- @bsb-block warranty@1 managed
-- @bsb-hash sha256:c2557321d3c2c2d15d0f1895813d6c3de7ab4a0ff00ba1e4f7ef1495c2391c8e
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warranty.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."warranty_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."warranty_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."warranty_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_161_warranty.sql
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

-- ==== with every module: schema supabase/schemas/900_better_supabase_161_warranty.sql
-- better-supabase module: warranty
-- @bsb-block warranty@1 managed
-- @bsb-hash sha256:d42c48a5220c2862273b74e5f60b514a9075705cd5af70f96afc775fedec61ad
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
  perform "better_supabase".emit_event('warranty_claim.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'assetId', v_row."asset_id", 'status', v_row."status"), 'warranty-claims/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warranty');
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
  perform "better_supabase".emit_event('warranty_claim.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'assetId', v_row."asset_id", 'status', v_row."status"), 'warranty-claims/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warranty');
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
    perform "better_supabase".emit_event('warranty_claim.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'assetId', v_row."asset_id", 'status', v_row."status"), 'warranty-claims/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warranty');
  else
    perform "better_supabase".emit_event('warranty_claim.decided', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'title', v_row."title", 'assetId', v_row."asset_id", 'status', v_row."status", 'decision', v_row."decision"), 'warranty-claims/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/warranty');
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warranty.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."warranty_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."warranty_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."warranty_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.warranty_claims deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"warranty_claim","event_prefix":"warranty_claim"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_161_warranty.sql
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

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_161_warranty.sql
-- better-supabase module: warranty
-- @bsb-block warranty@1 managed
-- @bsb-hash sha256:e03115b90f0ca7d147dac10723d938755aebf657fdcfef8d53bc78c4e977d367
-- Warranty claims for an asset: the supplier or manufacturer, the covered amount, a status, a decision and attachments on the claim.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Warranty claims: a supplier or manufacturer, an asset, a covered amount and
-- a decision. Status moves draft, submitted, approved or denied, then closed.

create table "app_private"."warranty_claims" (
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
create index "bsb_warranty_claims_asset_idx" on "app_private"."warranty_claims" ("tenant_id", "asset_id");
create index "bsb_warranty_claims_status_idx" on "app_private"."warranty_claims" ("tenant_id", "status");
alter table "app_private"."warranty_claims" enable row level security;
revoke all on "app_private"."warranty_claims" from public, anon, authenticated;
grant select on "app_private"."warranty_claims" to authenticated;
grant all on "app_private"."warranty_claims" to service_role;
create policy bsb_warranty_claims_read on "app_private"."warranty_claims"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('warranty.read')));

-- A draft claim for an asset, covered for amount in currency's minor units.
-- supplierId or manufacturer is required. Needs warranty.write.
create or replace function "app_private"."create_warranty_claim"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."warranty_claims";
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
  insert into "app_private"."warranty_claims" (
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
revoke execute on function "app_private"."create_warranty_claim"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."create_warranty_claim"(uuid, jsonb) to authenticated, service_role;

-- draft -> submitted. Needs warranty.write.
create or replace function "app_private"."submit_warranty_claim"(claim_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."warranty_claims";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."warranty_claims" x where x."id" = submit_warranty_claim.claim_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.read'), false))) then
    raise exception 'no such warranty claim' using errcode = 'P0002', hint = 'WARRANTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.write'), false))) then
    raise exception 'not allowed to write warranty claims' using errcode = '42501', hint = 'WARRANTY_FORBIDDEN';
  end if;
  if v_row."status" is distinct from 'draft' then
    raise exception 'that status change is not allowed' using errcode = '42501', hint = 'WARRANTY_TRANSITION';
  end if;
  update "app_private"."warranty_claims" x set "status" = 'submitted', "updated_at" = now()
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
revoke execute on function "app_private"."submit_warranty_claim"(uuid) from public, anon;
grant execute on function "app_private"."submit_warranty_claim"(uuid) to authenticated, service_role;

-- submitted -> approved or denied, then either -> closed.
-- Approving or denying stores the decision. Needs warranty.decide.
-- The state machine allows the same edges when it is installed.
create or replace function "app_private"."decide_warranty_claim"(claim_id uuid, next_status text, decision text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."warranty_claims";
  v_decision text := nullif(btrim(decide_warranty_claim.decision), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."warranty_claims" x where x."id" = decide_warranty_claim.claim_id for update;
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
  update "app_private"."warranty_claims" x set
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
revoke execute on function "app_private"."decide_warranty_claim"(uuid, text, text) from public, anon;
grant execute on function "app_private"."decide_warranty_claim"(uuid, text, text) to authenticated, service_role;

-- Claims of an organization, newest first. filters is { status, assetId, limit, offset }.
-- Needs warranty.read.
create or replace function "app_private"."list_warranty_claims"(tenant uuid, filters jsonb default '{}')
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
      select * from "app_private"."warranty_claims" y
      where y."tenant_id" = list_warranty_claims.tenant
        and (v_status is null or y."status" = v_status)
        and (v_asset is null or y."asset_id" = v_asset::uuid)
      order by y."created_at" desc, y."id"
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_warranty_claims"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_warranty_claims"(uuid, jsonb) to authenticated, service_role;
create trigger bsb_transition_warranty_claim before insert or update of "status" on "app_private"."warranty_claims"
for each row execute function better_supabase.bsb_transition_warranty_claim();

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."warranty_claims" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warranty.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."warranty_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."warranty_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."warranty_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_161_warranty.sql
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

-- ==== api schema: schema supabase/schemas/900_better_supabase_161_warranty.sql
-- better-supabase module: warranty
-- @bsb-block warranty@1 managed
-- @bsb-hash sha256:c33a9e5036dc8758b9a3839602e30148db70de0ac290e60e36833a3e65e1d6b4
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warranty.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."warranty_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."warranty_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."warranty_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.warranty.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_warranty_claim"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_warranty_claim"($1, $2) $$;
revoke execute on function "api"."create_warranty_claim"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_warranty_claim"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."submit_warranty_claim"(claim_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."submit_warranty_claim"($1) $$;
revoke execute on function "api"."submit_warranty_claim"(uuid) from public, anon;
grant execute on function "api"."submit_warranty_claim"(uuid) to authenticated, service_role;

create or replace function "api"."decide_warranty_claim"(claim_id uuid, next_status text, decision text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_warranty_claim"($1, $2, $3) $$;
revoke execute on function "api"."decide_warranty_claim"(uuid, text, text) from public, anon;
grant execute on function "api"."decide_warranty_claim"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_warranty_claims"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_warranty_claims"($1, $2) $$;
revoke execute on function "api"."list_warranty_claims"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_warranty_claims"(uuid, jsonb) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_161_warranty.sql
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

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_161_warranty.sql
-- better-supabase module: warranty
-- @bsb-block warranty@1 managed
-- @bsb-hash sha256:bd6d07b0c1ef7718cba2281768decc107f691843c69de8356d663a4d1e94d5ca
-- Warranty claims for an asset: the supplier or manufacturer, the covered amount, a status, a decision and attachments on the claim.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warranty claims: a supplier or manufacturer, an asset, a covered amount and
-- a decision. Status moves draft, submitted, approved or denied, then closed.

-- better_supabase.warranty_claims is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."warranty_claims" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."warranty_claims" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."warranty_claims" add column if not exists "title" text constraint bsb_warranty_claims_title_check check (char_length("title") >= 1 and char_length("title") <= 200);
alter table "better_supabase"."warranty_claims" add column if not exists "supplier_id" uuid;
alter table "better_supabase"."warranty_claims" add column if not exists "manufacturer" text;
alter table "better_supabase"."warranty_claims" add column if not exists "asset_id" uuid;
alter table "better_supabase"."warranty_claims" add column if not exists "amount" bigint constraint bsb_warranty_claims_amount_check check ("amount" >= 0);
alter table "better_supabase"."warranty_claims" add column if not exists "currency" text constraint bsb_warranty_claims_currency_check check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."warranty_claims" add column if not exists "status" text not null default 'draft' constraint bsb_warranty_claims_status_check check ("status" in ('draft', 'submitted', 'approved', 'denied', 'closed'));
alter table "better_supabase"."warranty_claims" add column if not exists "decision" text;
alter table "better_supabase"."warranty_claims" add column if not exists "decided_at" timestamptz;
alter table "better_supabase"."warranty_claims" add column if not exists "decided_by" uuid;
alter table "better_supabase"."warranty_claims" add column if not exists "created_by" uuid;
alter table "better_supabase"."warranty_claims" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."warranty_claims" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "bsb_warranty_claims_asset_idx" on "better_supabase"."warranty_claims" ("tenant_id", "asset_id");
create index if not exists "bsb_warranty_claims_status_idx" on "better_supabase"."warranty_claims" ("tenant_id", "status");
alter table "better_supabase"."warranty_claims" enable row level security;
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
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('warranty.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."warranty_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."warranty_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."warranty_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_161_warranty.sql
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

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_161_warranty.sql
-- better-supabase module: warranty
-- @bsb-block warranty@1 managed
-- @bsb-hash sha256:a13d8ce1f827830e42ade8b22e7604e3a45b06f52d2916868a5424ec7b7d4258
-- Warranty claims for an asset: the supplier or manufacturer, the covered amount, a status, a decision and attachments on the claim.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warranty claims: a supplier or manufacturer, an asset, a covered amount and
-- a decision. Status moves draft, submitted, approved or denied, then closed.

create table "better_supabase"."warranty_claims" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
  unique ("org_id", "id")
);
create index "bsb_warranty_claims_asset_idx" on "better_supabase"."warranty_claims" ("org_id", "asset_id");
create index "bsb_warranty_claims_status_idx" on "better_supabase"."warranty_claims" ("org_id", "status");
alter table "better_supabase"."warranty_claims" enable row level security;
revoke all on "better_supabase"."warranty_claims" from public, anon, authenticated;
grant select on "better_supabase"."warranty_claims" to authenticated;
grant all on "better_supabase"."warranty_claims" to service_role;
create policy bsb_warranty_claims_read on "better_supabase"."warranty_claims"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('warranty.read')));

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
    "org_id", "title", "supplier_id", "manufacturer", "asset_id",
    "amount", "currency", "created_by"
  ) values (
    create_warranty_claim.tenant, v_title, v_supplier::uuid, v_manufacturer, v_asset::uuid,
    v_amount::bigint, v_currency, auth.uid()
  ) returning * into v_row;
  null;
  return jsonb_build_object(
    'id', v_row."id",
    'organizationId', v_row."org_id",
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'warranty.read'), false))) then
    raise exception 'no such warranty claim' using errcode = 'P0002', hint = 'WARRANTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'warranty.write'), false))) then
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
    'organizationId', v_row."org_id",
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'warranty.read'), false))) then
    raise exception 'no such warranty claim' using errcode = 'P0002', hint = 'WARRANTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'warranty.decide'), false))) then
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
    'organizationId', v_row."org_id",
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
    'organizationId', x."org_id",
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
      where y."org_id" = list_warranty_claims.tenant
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
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('warranty.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."warranty_claims" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."warranty_claims" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."warranty_claims" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_161_warranty.sql
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
