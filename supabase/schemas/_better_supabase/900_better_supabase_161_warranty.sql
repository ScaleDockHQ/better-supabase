-- better-supabase module: warranty
-- @bsb-block warranty@1 managed
-- @bsb-hash sha256:202ce5ca14b911d18ad4e3feb1e41c79e0a41f789b8dc7168743ad719820d03f
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

-- A claim by id. Needs warranty.read.
create or replace function "better_supabase"."get_warranty_claim"(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."warranty_claims";
begin
  select * into v_row from "better_supabase"."warranty_claims" x where x."id" = get_warranty_claim.claim_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.read'), false))) then
    raise exception 'no such warranty claim' using errcode = 'P0002', hint = 'WARRANTY_NOT_FOUND';
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
revoke execute on function "better_supabase"."get_warranty_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."get_warranty_claim"(uuid) to authenticated, service_role;

-- Claims of an organization, newest first. filters is { status, assetId (each a
-- value or a list of them), sort, direction, facet, count, limit, after,
-- offset, paged, total, totalCap } (ADR 0749).
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_warranty_claims.tenant is not null and coalesce(better_supabase.can('tenant', list_warranty_claims.tenant, 'warranty.read'), false))) then
    raise exception 'not allowed to read warranty claims' using errcode = '42501', hint = 'WARRANTY_FORBIDDEN';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'status') = 'array' then v_filters -> 'status' else jsonb_build_array(v_filters -> 'status') end) s
    where s not in ('draft', 'submitted', 'approved', 'denied', 'closed')
  ) then
    raise exception 'status is not a warranty status' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'assetId') = 'array' then v_filters -> 'assetId' else jsonb_build_array(v_filters -> 'assetId') end) s
    where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  ) then
    raise exception 'assetId must be a uuid' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'WARRANTY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
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
      select 1 from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'amount') then
    raise exception 'sort is one of createdAt, amount' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
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
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
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
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
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
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
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
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
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
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."amount")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."amount", x."id") > ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by x."amount" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'WARRANTY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
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
    'decidedBy', x."decided_by") as j, jsonb_build_array((x."amount")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
        and (v_after is null or (x."amount" <= (v_after ->> 0)::bigint and ((x."amount" < (v_after ->> 0)::bigint) or (x."amount" = (v_after ->> 0)::bigint and x."id" > (v_after ->> 1)::uuid))))
      order by x."amount" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."warranty_claims" x
      where x."tenant_id" = list_warranty_claims.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'assetId' is not null and jsonb_typeof(v_filters -> 'assetId') <> 'null' and not (jsonb_typeof(v_filters -> 'assetId') = 'array' and jsonb_array_length(v_filters -> 'assetId') = 0)) or x."asset_id" = any((case when jsonb_typeof(v_filters -> 'assetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assetId')) else array[v_filters ->> 'assetId'] end)::uuid[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
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
create trigger "bsb_search_warranty_claim_index"
  after insert or delete or update of "id", "tenant_id", "title", "manufacturer", "decision" on "better_supabase"."warranty_claims"
  for each row execute function "better_supabase"."search_index_row"('warranty_claim', 'id');

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.warranty_claims deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"warranty_claim","event_prefix":"warranty_claim"}');

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

create or replace function "api"."get_warranty_claim"(claim_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_warranty_claim"($1) $$;
revoke execute on function "api"."get_warranty_claim"(uuid) from public, anon;
grant execute on function "api"."get_warranty_claim"(uuid) to authenticated, service_role;

create or replace function "api"."list_warranty_claims"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_warranty_claims"($1, $2) $$;
revoke execute on function "api"."list_warranty_claims"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_warranty_claims"(uuid, jsonb) to authenticated, service_role;
