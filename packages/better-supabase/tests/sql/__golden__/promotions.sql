-- ==== alone: schema supabase/schemas/900_better_supabase_85_promotions.sql
-- better-supabase module: promotions
-- @bsb-block promotions@1 managed
-- Percentage, fixed and free-shipping promotions, automatic or by code, with usage limits and stacking rules, priced into orders carts.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Promotions (percentage, fixed or free shipping), automatic or by code,
-- with usage limits and stacking rules; orders prices carts with them.

create table if not exists "better_supabase"."promotions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "description" text check (length("description") <= 2000),
  "kind" text not null check ("kind" in ('percentage', 'fixed', 'free_shipping')),
  "percent" numeric(5, 2) check ("percent" > 0 and "percent" <= 100),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint check ("amount" > 0),
  "min_subtotal" bigint check ("min_subtotal" > 0),
  "scope" text not null default 'order' check ("scope" in ('order', 'products', 'categories', 'collections')),
  "target_ids" uuid[] not null default '{}',
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "usage_limit" integer check ("usage_limit" > 0),
  "per_customer_limit" integer check ("per_customer_limit" > 0),
  "redemptions" integer not null default 0 check ("redemptions" >= 0),
  "stackable" boolean not null default false,
  "priority" integer not null default 0,
  "automatic" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("kind" = 'percentage') = ("percent" is not null)),
  check (("kind" = 'fixed') = ("amount" is not null)),
  check (("amount" is null and "min_subtotal" is null) or "currency" is not null),
  check ("ends_at" is null or "starts_at" is null or "ends_at" > "starts_at")
);
create index if not exists promotions_tenant_idx on "better_supabase"."promotions" ("tenant_id", "active", "automatic");
alter table "better_supabase"."promotions" enable row level security;
revoke all on "better_supabase"."promotions" from anon, authenticated;
grant select on "better_supabase"."promotions" to authenticated;
grant all on "better_supabase"."promotions" to service_role;
drop policy if exists promotions_read on "better_supabase"."promotions";
create policy promotions_read on "better_supabase"."promotions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')));

create table if not exists "better_supabase"."promotion_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "promotion_id" uuid not null references "better_supabase"."promotions" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Z0-9_-]{3,40}$'),
  "usage_limit" integer check ("usage_limit" > 0),
  "redemptions" integer not null default 0 check ("redemptions" >= 0),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
create index if not exists promotion_codes_promotion_idx on "better_supabase"."promotion_codes" ("promotion_id");
alter table "better_supabase"."promotion_codes" enable row level security;
revoke all on "better_supabase"."promotion_codes" from anon, authenticated;
grant select on "better_supabase"."promotion_codes" to authenticated;
grant all on "better_supabase"."promotion_codes" to service_role;
drop policy if exists promotion_codes_read on "better_supabase"."promotion_codes";
create policy promotion_codes_read on "better_supabase"."promotion_codes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')));

create table if not exists "better_supabase"."cart_promotion_codes" (
  "tenant_id" uuid not null,
  "cart_id" uuid not null references "better_supabase"."carts" ("id") on delete cascade,
  "code_id" uuid not null references "better_supabase"."promotion_codes" ("id") on delete cascade,
  "created_at" timestamptz not null default now(),
  primary key ("cart_id", "code_id")
);
create index if not exists cart_promotion_codes_code_idx on "better_supabase"."cart_promotion_codes" ("code_id");
alter table "better_supabase"."cart_promotion_codes" enable row level security;
revoke all on "better_supabase"."cart_promotion_codes" from anon, authenticated;
grant select on "better_supabase"."cart_promotion_codes" to authenticated;
grant all on "better_supabase"."cart_promotion_codes" to service_role;
drop policy if exists cart_promotion_codes_read on "better_supabase"."cart_promotion_codes";
create policy cart_promotion_codes_read on "better_supabase"."cart_promotion_codes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')) or exists (select 1 from "better_supabase"."carts" x where x."id" = "cart_id" and x."user_id" = (select auth.uid())));

create table if not exists "better_supabase"."promotion_redemptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "promotion_id" uuid not null references "better_supabase"."promotions" ("id"),
  "code_id" uuid references "better_supabase"."promotion_codes" ("id") on delete set null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "customer_id" uuid references auth.users (id) on delete set null,
  "email" text,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint not null check ("amount" >= 0),
  "status" text not null default 'redeemed' check ("status" in ('redeemed', 'released')),
  "created_at" timestamptz not null default now(),
  "released_at" timestamptz,
  unique ("order_id", "promotion_id")
);
create index if not exists promotion_redemptions_promotion_idx on "better_supabase"."promotion_redemptions" ("promotion_id", "status");
create index if not exists promotion_redemptions_customer_idx on "better_supabase"."promotion_redemptions" ("customer_id");
create index if not exists promotion_redemptions_code_idx on "better_supabase"."promotion_redemptions" ("code_id");
alter table "better_supabase"."promotion_redemptions" enable row level security;
revoke all on "better_supabase"."promotion_redemptions" from anon, authenticated;
grant select on "better_supabase"."promotion_redemptions" to authenticated;
grant all on "better_supabase"."promotion_redemptions" to service_role;
drop policy if exists promotion_redemptions_read on "better_supabase"."promotion_redemptions";
create policy promotion_redemptions_read on "better_supabase"."promotion_redemptions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')) or "customer_id" = (select auth.uid()));

-- Creates or updates a promotion. data holds name, description, kind
-- (percentage, fixed or free_shipping), percent, currency, amount and
-- minSubtotal (minor units as text), scope (order, products, categories or
-- collections) with targets, startsAt, endsAt, usageLimit,
-- perCustomerLimit, stackable, priority, automatic and active.
drop function if exists "better_supabase"."save_promotion"(uuid, uuid, jsonb, jsonb);
create or replace function "better_supabase"."save_promotion"(tenant uuid, promotion uuid, data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := save_promotion.tenant;
  v_id uuid := save_promotion.promotion;
  v_kind text := data ->> 'kind';
  v_scope text := coalesce(data ->> 'scope', 'order');
  v_currency text := data ->> 'currency';
  v_percent numeric;
  v_targets uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_id is not null then
    select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = v_id for update;
    if not found or v_tenant is distinct from save_promotion.tenant then
      raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
    end if;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if jsonb_typeof(data) is distinct from 'object' then
    raise exception 'data is an object' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind is null or v_kind not in ('percentage', 'fixed', 'free_shipping') then
    raise exception 'kind is percentage, fixed or free_shipping' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind = 'percentage' then
    if coalesce(data ->> 'percent', '') !~ '^[0-9]{1,3}([.][0-9]{1,2})?$' or (data ->> 'percent')::numeric <= 0 or (data ->> 'percent')::numeric > 100 then
      raise exception 'percent is a number above 0 and at most 100, with up to two decimals' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
    end if;
    v_percent := (data ->> 'percent')::numeric;
  end if;
  if v_kind = 'fixed' and ((case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) is null or (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) <= 0) then
    raise exception 'a fixed promotion has an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if data ? 'minSubtotal' and data ->> 'minSubtotal' is not null and ((case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) is null or (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) <= 0) then
    raise exception 'minSubtotal is an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (v_kind = 'fixed' or data ->> 'minSubtotal' is not null) and (v_currency is null or "better_supabase"."currency_minor_units"(v_currency) is null) then
    raise exception 'an amount needs an ISO 4217 currency' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope not in ('order', 'products', 'categories', 'collections') then
    raise exception 'scope is order, products, categories, collections' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if jsonb_typeof(coalesce(data -> 'targets', '[]'::jsonb)) <> 'array' then
    raise exception 'targets is an array of ids' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  select coalesce(array_agg(distinct e::uuid), '{}') into v_targets
  from jsonb_array_elements_text(coalesce(data -> 'targets', '[]'::jsonb)) e;
  if (v_scope = 'order') <> (cardinality(v_targets) = 0) then
    raise exception 'an order promotion has no targets; the other scopes need at least one' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope <> 'order' and cardinality(v_targets) <> (case v_scope
    when 'products' then (select count(*) from "better_supabase"."products" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'categories' then (select count(*) from "better_supabase"."categories" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'collections' then (select count(*) from "better_supabase"."collections" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    else 0 end) then
    raise exception 'every target is a product, category or collection of this organization' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (data ->> 'startsAt') is not null and (data ->> 'endsAt') is not null
    and (data ->> 'endsAt')::timestamptz <= (data ->> 'startsAt')::timestamptz then
    raise exception 'endsAt is after startsAt' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if coalesce((data ->> 'usageLimit')::integer, 1) < 1 or coalesce((data ->> 'perCustomerLimit')::integer, 1) < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  if v_id is null then
    insert into "better_supabase"."promotions" ("tenant_id", "name", "description", "kind", "percent", "currency", "amount", "min_subtotal", "scope", "target_ids", "starts_at", "ends_at", "usage_limit", "per_customer_limit", "stackable", "priority", "automatic", "active")
    values (v_tenant, data ->> 'name', data ->> 'description', v_kind, v_percent, case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end, case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end, (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end), v_scope, v_targets, (data ->> 'startsAt')::timestamptz, (data ->> 'endsAt')::timestamptz, (data ->> 'usageLimit')::integer, (data ->> 'perCustomerLimit')::integer, coalesce((data ->> 'stackable')::boolean, false), coalesce((data ->> 'priority')::integer, 0), coalesce((data ->> 'automatic')::boolean, false), coalesce((data ->> 'active')::boolean, true))
    returning "id" into v_id;
  else
    update "better_supabase"."promotions" x set
      "name" = data ->> 'name',
      "description" = data ->> 'description',
      "kind" = v_kind,
      "percent" = v_percent,
      "currency" = case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end,
      "amount" = case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end,
      "min_subtotal" = (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end),
      "scope" = v_scope,
      "target_ids" = v_targets,
      "starts_at" = (data ->> 'startsAt')::timestamptz,
      "ends_at" = (data ->> 'endsAt')::timestamptz,
      "usage_limit" = (data ->> 'usageLimit')::integer,
      "per_customer_limit" = (data ->> 'perCustomerLimit')::integer,
      "stackable" = coalesce((data ->> 'stackable')::boolean, false),
      "priority" = coalesce((data ->> 'priority')::integer, 0),
      "automatic" = coalesce((data ->> 'automatic')::boolean, false),
      "active" = coalesce((data ->> 'active')::boolean, true),
      "updated_at" = now()
    where x."id" = v_id;
  end if;
  if coalesce((data ->> 'active')::boolean, true) then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_promotion"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_promotion"(uuid, uuid, jsonb) to authenticated, service_role;

-- before_promotion_activate(promotion) runs after the write, so it reads
-- the promotion as it will be; raising refuses the activation.
create or replace function "better_supabase"."set_promotion_active"(promotion uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = set_promotion_active.promotion;
  if not found then
    raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  update "better_supabase"."promotions" x set "active" = set_promotion_active.active, "updated_at" = now()
  where x."id" = set_promotion_active.promotion;
  if set_promotion_active.active then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using set_promotion_active.promotion;
    end if;
  end;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_promotion_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_promotion_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a promotion nobody redeemed; deactivate one that was.
create or replace function "better_supabase"."delete_promotion"(promotion uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = delete_promotion.promotion;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."promotion_redemptions" x where x."promotion_id" = delete_promotion.promotion) then
    raise exception 'the promotion was redeemed; deactivate it instead' using errcode = '55000', hint = 'PROMOTIONS_IN_USE';
  end if;
  delete from "better_supabase"."promotions" x where x."id" = delete_promotion.promotion;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_promotion"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_promotion"(uuid) to authenticated, service_role;

-- Adds codes to a promotion: the given ones, or count generated ones of
-- the prefix and eight random characters. Codes are stored upper case and
-- are unique per organization.
create or replace function "better_supabase"."create_promotion_codes"(promotion uuid, codes text[] default null,
  count integer default null, prefix text default null, usage_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_code text;
  v_id uuid;
  v_out jsonb := '[]';
  v_prefix text := coalesce(upper(btrim(create_promotion_codes.prefix)), '');
  v_bytes bytea;
  v_attempts integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = create_promotion_codes.promotion;
  if not found then
    raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if (create_promotion_codes.codes is null) = (create_promotion_codes.count is null) then
    raise exception 'pass codes or a count' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.count is not null and (create_promotion_codes.count < 1 or create_promotion_codes.count > 10000) then
    raise exception 'count is from 1 to 10000' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.usage_limit is not null and create_promotion_codes.usage_limit < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_prefix !~ '^[A-Z0-9_-]{0,32}$' then
    raise exception 'a prefix has up to 32 letters, digits, dashes or underscores' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.codes is not null then
    foreach v_code in array create_promotion_codes.codes loop
      v_code := upper(btrim(v_code));
      if v_code is null or v_code !~ '^[A-Z0-9_-]{3,40}$' then
        raise exception 'a code has 3 to 40 letters, digits, dashes or underscores' using errcode = '22023', hint = 'PROMOTIONS_CODE_FORMAT';
      end if;
      begin
        insert into "better_supabase"."promotion_codes" ("tenant_id", "promotion_id", "code", "usage_limit")
        values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
        returning "id" into v_id;
      exception when unique_violation then
        raise exception 'another promotion uses this code' using errcode = '23505', hint = 'PROMOTIONS_CODE_TAKEN';
      end;
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
    end loop;
    return v_out;
  end if;
  while jsonb_array_length(v_out) < create_promotion_codes.count loop
    v_attempts := v_attempts + 1;
    if v_attempts > create_promotion_codes.count * 4 + 10 then
      raise exception 'couldn''t generate enough unique codes; use a longer prefix' using errcode = '55000', hint = 'PROMOTIONS_CODE_SPACE';
    end if;
    v_bytes := extensions.gen_random_bytes(8);
    v_code := v_prefix;
    for i in 0..7 loop
      v_code := v_code || substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    insert into "better_supabase"."promotion_codes" ("tenant_id", "promotion_id", "code", "usage_limit")
    values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
    on conflict do nothing
    returning "id" into v_id;
    if v_id is not null then
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
      v_id := null;
    end if;
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."create_promotion_codes"(uuid, text[], integer, text, integer) from public, anon;
grant execute on function "better_supabase"."create_promotion_codes"(uuid, text[], integer, text, integer) to authenticated, service_role;

-- Deletes a code nobody redeemed.
create or replace function "better_supabase"."delete_promotion_code"(code uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_used integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."redemptions" into v_tenant, v_used from "better_supabase"."promotion_codes" x where x."id" = delete_promotion_code.code;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if v_used > 0 then
    raise exception 'the code was redeemed' using errcode = '55000', hint = 'PROMOTIONS_IN_USE';
  end if;
  delete from "better_supabase"."promotion_codes" x where x."id" = delete_promotion_code.code;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_promotion_code"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_promotion_code"(uuid) to authenticated, service_role;

-- Puts a code on the caller's open cart. Whether it applies (minimum
-- subtotal, products, stacking) shows when the cart is priced.
create or replace function "better_supabase"."apply_promotion_code"(cart uuid, code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_code record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status
  into v_cart from "better_supabase"."carts" x where x."id" = apply_promotion_code.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  select k."id" as id, k."code" as code, k."promotion_id" as promotion,
    k."usage_limit" as code_limit, k."redemptions" as code_used,
    x."usage_limit" as usage_limit, x."redemptions" as used
  into v_code
  from "better_supabase"."promotion_codes" k join "better_supabase"."promotions" x on x."id" = k."promotion_id"
  where k."tenant_id" = v_cart.tenant and k."code" = upper(btrim(apply_promotion_code.code))
    and x."active" and (x."starts_at" is null or x."starts_at" <= now())
    and (x."ends_at" is null or x."ends_at" > now());
  if not found then
    raise exception 'this code is unknown or no longer valid' using errcode = 'P0002', hint = 'PROMOTIONS_CODE_INVALID';
  end if;
  if (v_code.code_limit is not null and v_code.code_used >= v_code.code_limit)
    or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
    raise exception 'this code was used up' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
  end if;
  if (select count(*) from "better_supabase"."cart_promotion_codes" x where x."cart_id" = apply_promotion_code.cart and x."code_id" <> v_code.id) >= 5 then
    raise exception 'a cart holds up to 5 codes' using errcode = '55000', hint = 'PROMOTIONS_TOO_MANY_CODES';
  end if;
  insert into "better_supabase"."cart_promotion_codes" ("tenant_id", "cart_id", "code_id")
  values (v_cart.tenant, apply_promotion_code.cart, v_code.id)
  on conflict do nothing;
  return jsonb_build_object('codeId', v_code.id, 'code', v_code.code, 'promotionId', v_code.promotion);
end;
$$;
revoke execute on function "better_supabase"."apply_promotion_code"(uuid, text) from public, anon;
grant execute on function "better_supabase"."apply_promotion_code"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_promotion_code"(cart uuid, code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."user_id" as owner, x."status" as status
  into v_cart from "better_supabase"."carts" x where x."id" = remove_promotion_code.cart;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  delete from "better_supabase"."cart_promotion_codes" x
  where x."cart_id" = remove_promotion_code.cart
    and x."code_id" in (select k."id" from "better_supabase"."promotion_codes" k where k."code" = upper(btrim(remove_promotion_code.code)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_promotion_code"(uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_promotion_code"(uuid, text) to authenticated, service_role;

-- Rounds half to even, like money everywhere else in the commerce blocks.
create or replace function "better_supabase"."round_half_even"(p_value numeric)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value - floor(p_value) > 0.5 then floor(p_value)::bigint + 1
    when p_value - floor(p_value) < 0.5 then floor(p_value)::bigint
    when floor(p_value)::bigint % 2 = 0 then floor(p_value)::bigint
    else floor(p_value)::bigint + 1
  end
$$;
revoke execute on function "better_supabase"."round_half_even"(numeric) from public, anon, authenticated;

-- The cart's discounts: lines maps a line id to its discount, applied
-- lists the promotions in the order they applied, and problems the codes
-- that don't apply. Promotions run by priority (highest first); a
-- promotion that isn't stackable never combines with another. p_lines
-- are the priced lines (id, productId, subtotal as text). Internal: the
-- orders cart_totals calls it.
create or replace function "better_supabase"."cart_discounts"(p_cart uuid, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_promo record;
  v_reason text;
  v_eligible text[];
  v_base bigint;
  v_rem jsonb;
  v_disc jsonb := '{}';
  v_applied jsonb := '[]';
  v_problems jsonb := '[]';
  v_free boolean := false;
  v_stackable boolean := true;
  v_amount bigint;
  v_left bigint;
  v_share bigint;
  v_line_rem bigint;
  v_id text;
begin
  select x."tenant_id" as tenant, x."user_id" as owner, x."currency" as currency, x."email" as email
  into v_cart from "better_supabase"."carts" x where x."id" = p_cart;
  select coalesce(jsonb_object_agg(e ->> 'id', (e ->> 'subtotal')::bigint), '{}') into v_rem
  from jsonb_array_elements(p_lines) e;
  for v_promo in
    select x."id" as id, x."name" as name, x."kind" as kind, x."percent" as percent,
      x."currency" as currency, x."amount" as amount, x."min_subtotal" as min_subtotal,
      x."scope" as scope, x."target_ids" as targets, x."usage_limit" as usage_limit,
      x."per_customer_limit" as per_customer_limit, x."redemptions" as used, x."stackable" as stackable,
      x."automatic" as automatic,
      (x."active" and (x."starts_at" is null or x."starts_at" <= now())
        and (x."ends_at" is null or x."ends_at" > now())) as live,
      code.id as code_id, code.code as code, code.usage_limit as code_limit, code.used as code_used
    from "better_supabase"."promotions" x
    left join lateral (
      select k."id" as id, k."code" as code, k."usage_limit" as usage_limit, k."redemptions" as used
      from "better_supabase"."cart_promotion_codes" y join "better_supabase"."promotion_codes" k on k."id" = y."code_id"
      where y."cart_id" = p_cart and k."promotion_id" = x."id"
      order by y."created_at", k."id"
      limit 1
    ) code on true
    where x."tenant_id" = v_cart.tenant and (code.id is not null or (x."automatic" and x."active"))
    order by x."priority" desc, x."created_at", x."id"
  loop
    v_reason := null;
    if not v_promo.live then
      v_reason := 'expired';
    elsif (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.code_limit is not null and v_promo.code_used >= v_promo.code_limit)
      or (v_promo.per_customer_limit is not null
        and (select count(*) from "better_supabase"."promotion_redemptions" y where y."promotion_id" = v_promo.id and y."status" = 'redeemed'
      and (y."customer_id" = v_cart.owner or (v_cart.email is not null and lower(y."email") = lower(v_cart.email)))) >= v_promo.per_customer_limit) then
      v_reason := 'limit_reached';
    elsif v_promo.currency is not null and v_promo.currency <> v_cart.currency then
      v_reason := 'currency';
    else
      select coalesce(array_agg(e ->> 'id' order by n), '{}'), coalesce(sum((e ->> 'subtotal')::bigint), 0)
      into v_eligible, v_base
      from jsonb_array_elements(p_lines) with ordinality as l(e, n)
      where v_promo.scope = 'order'
      or (v_promo.scope = 'products' and (e ->> 'productId')::uuid = any (v_promo.targets))
      or (v_promo.scope = 'categories' and exists (
      with recursive d (id) as (
        select unnest(v_promo.targets)
        union
        select x."id" from "better_supabase"."categories" x join d on x."parent_id" = d.id
      )
      select 1 from "better_supabase"."product_categories" y where y."product_id" = (e ->> 'productId')::uuid and y."category_id" in (select id from d)
    ))
      or (v_promo.scope = 'collections' and exists (select 1 from "better_supabase"."collection_products" y where y."product_id" = (e ->> 'productId')::uuid and y."collection_id" = any (v_promo.targets)));
      if cardinality(v_eligible) = 0 then
        v_reason := 'not_applicable';
      elsif v_promo.min_subtotal is not null and v_base < v_promo.min_subtotal then
        v_reason := 'min_subtotal';
      elsif jsonb_array_length(v_applied) > 0 and not (v_stackable and v_promo.stackable) then
        v_reason := 'not_combinable';
      end if;
    end if;
    if v_reason is not null then
      if v_promo.code_id is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'promotion_unavailable',
          'promotionId', v_promo.id, 'code', v_promo.code, 'reason', v_reason));
      end if;
      continue;
    end if;
    v_amount := 0;
    if v_promo.kind = 'percentage' then
      foreach v_id in array v_eligible loop
        v_line_rem := (v_rem ->> v_id)::bigint;
        v_share := least("better_supabase"."round_half_even"(v_line_rem * v_promo.percent / 100), v_line_rem);
        v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
        v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
        v_amount := v_amount + v_share;
      end loop;
    elsif v_promo.kind = 'fixed' then
      select coalesce(sum((v_rem ->> e)::bigint), 0) into v_base from unnest(v_eligible) e;
      v_left := least(v_promo.amount, v_base);
      if v_base > 0 then
        foreach v_id in array v_eligible loop
          v_line_rem := (v_rem ->> v_id)::bigint;
          v_share := floor(least(v_promo.amount, v_base)::numeric * v_line_rem / v_base)::bigint;
          v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
          v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
          v_left := v_left - v_share;
        end loop;
        foreach v_id in array v_eligible loop
          exit when v_left = 0;
          if (v_rem ->> v_id)::bigint > 0 then
            v_rem := jsonb_set(v_rem, array[v_id], to_jsonb((v_rem ->> v_id)::bigint - 1));
            v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + 1));
            v_left := v_left - 1;
          end if;
        end loop;
        v_amount := least(v_promo.amount, v_base);
      end if;
    else
      v_free := true;
    end if;
    v_stackable := v_stackable and v_promo.stackable;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('promotionId', v_promo.id, 'name', v_promo.name,
      'kind', v_promo.kind, 'codeId', v_promo.code_id, 'code', v_promo.code, 'amount', v_amount::text));
  end loop;
  select coalesce(jsonb_object_agg(key, value #>> '{}'), '{}') into v_disc from jsonb_each(v_disc);
  return jsonb_build_object('lines', v_disc, 'applied', v_applied, 'freeShipping', v_free, 'problems', v_problems);
end;
$$;
revoke execute on function "better_supabase"."cart_discounts"(uuid, jsonb) from public, anon, authenticated;

-- Records the order's promotions inside checkout. The promotion row lock
-- keeps usage limits under concurrent checkouts; a limit reached since the
-- cart was priced fails the checkout (PROMOTIONS_LIMIT_REACHED).
-- Internal: the orders place_order calls it.
create or replace function "better_supabase"."redeem_promotions"(p_order uuid, p_applied jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_entry jsonb;
  v_promo record;
  v_code record;
  v_id uuid;
  v_count integer := 0;
begin
  select x."id" as id, x."tenant_id" as tenant, x."customer_id" as customer, x."email" as email,
    x."currency" as currency
  into v_order from "better_supabase"."orders" x where x."id" = p_order;
  for v_entry in select e from jsonb_array_elements(coalesce(p_applied, '[]'::jsonb)) e loop
    select x."id" as id, x."usage_limit" as usage_limit, x."per_customer_limit" as per_customer_limit,
      x."redemptions" as used
    into v_promo from "better_supabase"."promotions" x where x."id" = (v_entry ->> 'promotionId')::uuid for update;
    if not found or (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.per_customer_limit is not null
        and (select count(*) from "better_supabase"."promotion_redemptions" y where y."promotion_id" = v_promo.id and y."status" = 'redeemed'
      and (y."customer_id" = v_order.customer or (v_order.email is not null and lower(y."email") = lower(v_order.email)))) >= v_promo.per_customer_limit) then
      raise exception 'a promotion on this cart reached its usage limit' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
    end if;
    if v_entry ->> 'codeId' is not null then
      select x."usage_limit" as usage_limit, x."redemptions" as used
      into v_code from "better_supabase"."promotion_codes" x where x."id" = (v_entry ->> 'codeId')::uuid for update;
      if not found or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
        raise exception 'a code on this cart was used up' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
      end if;
      update "better_supabase"."promotion_codes" x set "redemptions" = x."redemptions" + 1 where x."id" = (v_entry ->> 'codeId')::uuid;
    end if;
    update "better_supabase"."promotions" x set "redemptions" = x."redemptions" + 1 where x."id" = v_promo.id;
    insert into "better_supabase"."promotion_redemptions" ("tenant_id", "promotion_id", "code_id", "order_id", "customer_id",
      "email", "currency", "amount")
    values (v_order.tenant, v_promo.id, (v_entry ->> 'codeId')::uuid, v_order.id, v_order.customer, v_order.email,
      v_order.currency, (v_entry ->> 'amount')::bigint)
    returning "id" into v_id;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."redeem_promotions"(uuid, jsonb) from public, anon, authenticated;

-- Gives a cancelled order's redemptions back to their limits. Internal:
-- the orders cancel_order and expire_orders call it.
create or replace function "better_supabase"."release_promotions"(p_order uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    update "better_supabase"."promotion_redemptions" x set "status" = 'released', "released_at" = now()
    where x."order_id" = p_order and x."status" = 'redeemed'
    returning x."promotion_id" as promotion, x."code_id" as code
  loop
    update "better_supabase"."promotions" x set "redemptions" = greatest(x."redemptions" - 1, 0) where x."id" = v_row.promotion;
    if v_row.code is not null then
      update "better_supabase"."promotion_codes" x set "redemptions" = greatest(x."redemptions" - 1, 0) where x."id" = v_row.code;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."release_promotions"(uuid) from public, anon, authenticated;

-- Moves the codes of a cart merged into another, up to what a cart
-- holds. Internal: the orders merge_carts calls it.
create or replace function "better_supabase"."move_cart_codes"(p_from uuid, p_to uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into "better_supabase"."cart_promotion_codes" ("tenant_id", "cart_id", "code_id")
  select x."tenant_id", p_to, x."code_id"
  from "better_supabase"."cart_promotion_codes" x
  where x."cart_id" = p_from
    and not exists (select 1 from "better_supabase"."cart_promotion_codes" y where y."cart_id" = p_to and y."code_id" = x."code_id")
  order by x."created_at"
  limit greatest(5 - (select count(*) from "better_supabase"."cart_promotion_codes" y where y."cart_id" = p_to), 0);
  get diagnostics v_count = row_count;
  delete from "better_supabase"."cart_promotion_codes" x where x."cart_id" = p_from;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."move_cart_codes"(uuid, uuid) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_85_promotions.sql
-- better-supabase module: promotions
-- @bsb-block-data promotions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('promotions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_85_promotions.sql
-- better-supabase module: promotions
-- @bsb-block promotions@1 managed
-- Percentage, fixed and free-shipping promotions, automatic or by code, with usage limits and stacking rules, priced into orders carts.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Promotions (percentage, fixed or free shipping), automatic or by code,
-- with usage limits and stacking rules; orders prices carts with them.

create table if not exists "better_supabase"."promotions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "description" text check (length("description") <= 2000),
  "kind" text not null check ("kind" in ('percentage', 'fixed', 'free_shipping')),
  "percent" numeric(5, 2) check ("percent" > 0 and "percent" <= 100),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint check ("amount" > 0),
  "min_subtotal" bigint check ("min_subtotal" > 0),
  "scope" text not null default 'order' check ("scope" in ('order', 'products', 'categories', 'collections')),
  "target_ids" uuid[] not null default '{}',
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "usage_limit" integer check ("usage_limit" > 0),
  "per_customer_limit" integer check ("per_customer_limit" > 0),
  "redemptions" integer not null default 0 check ("redemptions" >= 0),
  "stackable" boolean not null default false,
  "priority" integer not null default 0,
  "automatic" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("kind" = 'percentage') = ("percent" is not null)),
  check (("kind" = 'fixed') = ("amount" is not null)),
  check (("amount" is null and "min_subtotal" is null) or "currency" is not null),
  check ("ends_at" is null or "starts_at" is null or "ends_at" > "starts_at")
);
create index if not exists promotions_tenant_idx on "better_supabase"."promotions" ("tenant_id", "active", "automatic");
alter table "better_supabase"."promotions" enable row level security;
revoke all on "better_supabase"."promotions" from anon, authenticated;
grant select on "better_supabase"."promotions" to authenticated;
grant all on "better_supabase"."promotions" to service_role;
drop policy if exists promotions_read on "better_supabase"."promotions";
create policy promotions_read on "better_supabase"."promotions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')));

create table if not exists "better_supabase"."promotion_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "promotion_id" uuid not null references "better_supabase"."promotions" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Z0-9_-]{3,40}$'),
  "usage_limit" integer check ("usage_limit" > 0),
  "redemptions" integer not null default 0 check ("redemptions" >= 0),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
create index if not exists promotion_codes_promotion_idx on "better_supabase"."promotion_codes" ("promotion_id");
alter table "better_supabase"."promotion_codes" enable row level security;
revoke all on "better_supabase"."promotion_codes" from anon, authenticated;
grant select on "better_supabase"."promotion_codes" to authenticated;
grant all on "better_supabase"."promotion_codes" to service_role;
drop policy if exists promotion_codes_read on "better_supabase"."promotion_codes";
create policy promotion_codes_read on "better_supabase"."promotion_codes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')));

create table if not exists "better_supabase"."cart_promotion_codes" (
  "tenant_id" uuid not null,
  "cart_id" uuid not null references "better_supabase"."carts" ("id") on delete cascade,
  "code_id" uuid not null references "better_supabase"."promotion_codes" ("id") on delete cascade,
  "created_at" timestamptz not null default now(),
  primary key ("cart_id", "code_id")
);
create index if not exists cart_promotion_codes_code_idx on "better_supabase"."cart_promotion_codes" ("code_id");
alter table "better_supabase"."cart_promotion_codes" enable row level security;
revoke all on "better_supabase"."cart_promotion_codes" from anon, authenticated;
grant select on "better_supabase"."cart_promotion_codes" to authenticated;
grant all on "better_supabase"."cart_promotion_codes" to service_role;
drop policy if exists cart_promotion_codes_read on "better_supabase"."cart_promotion_codes";
create policy cart_promotion_codes_read on "better_supabase"."cart_promotion_codes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')) or exists (select 1 from "better_supabase"."carts" x where x."id" = "cart_id" and x."user_id" = (select auth.uid())));

create table if not exists "better_supabase"."promotion_redemptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "promotion_id" uuid not null references "better_supabase"."promotions" ("id"),
  "code_id" uuid references "better_supabase"."promotion_codes" ("id") on delete set null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "customer_id" uuid references auth.users (id) on delete set null,
  "email" text,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint not null check ("amount" >= 0),
  "status" text not null default 'redeemed' check ("status" in ('redeemed', 'released')),
  "created_at" timestamptz not null default now(),
  "released_at" timestamptz,
  unique ("order_id", "promotion_id")
);
create index if not exists promotion_redemptions_promotion_idx on "better_supabase"."promotion_redemptions" ("promotion_id", "status");
create index if not exists promotion_redemptions_customer_idx on "better_supabase"."promotion_redemptions" ("customer_id");
create index if not exists promotion_redemptions_code_idx on "better_supabase"."promotion_redemptions" ("code_id");
alter table "better_supabase"."promotion_redemptions" enable row level security;
revoke all on "better_supabase"."promotion_redemptions" from anon, authenticated;
grant select on "better_supabase"."promotion_redemptions" to authenticated;
grant all on "better_supabase"."promotion_redemptions" to service_role;
drop policy if exists promotion_redemptions_read on "better_supabase"."promotion_redemptions";
create policy promotion_redemptions_read on "better_supabase"."promotion_redemptions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')) or "customer_id" = (select auth.uid()));

-- Creates or updates a promotion. data holds name, description, kind
-- (percentage, fixed or free_shipping), percent, currency, amount and
-- minSubtotal (minor units as text), scope (order, products, categories or
-- collections) with targets, startsAt, endsAt, usageLimit,
-- perCustomerLimit, stackable, priority, automatic and active.
drop function if exists "better_supabase"."save_promotion"(uuid, uuid, jsonb, jsonb);
create or replace function "better_supabase"."save_promotion"(tenant uuid, promotion uuid, data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := save_promotion.tenant;
  v_id uuid := save_promotion.promotion;
  v_kind text := data ->> 'kind';
  v_scope text := coalesce(data ->> 'scope', 'order');
  v_currency text := data ->> 'currency';
  v_percent numeric;
  v_targets uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_id is not null then
    select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = v_id for update;
    if not found or v_tenant is distinct from save_promotion.tenant then
      raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
    end if;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if jsonb_typeof(data) is distinct from 'object' then
    raise exception 'data is an object' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind is null or v_kind not in ('percentage', 'fixed', 'free_shipping') then
    raise exception 'kind is percentage, fixed or free_shipping' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind = 'percentage' then
    if coalesce(data ->> 'percent', '') !~ '^[0-9]{1,3}([.][0-9]{1,2})?$' or (data ->> 'percent')::numeric <= 0 or (data ->> 'percent')::numeric > 100 then
      raise exception 'percent is a number above 0 and at most 100, with up to two decimals' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
    end if;
    v_percent := (data ->> 'percent')::numeric;
  end if;
  if v_kind = 'fixed' and ((case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) is null or (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) <= 0) then
    raise exception 'a fixed promotion has an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if data ? 'minSubtotal' and data ->> 'minSubtotal' is not null and ((case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) is null or (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) <= 0) then
    raise exception 'minSubtotal is an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (v_kind = 'fixed' or data ->> 'minSubtotal' is not null) and (v_currency is null or "better_supabase"."currency_minor_units"(v_currency) is null) then
    raise exception 'an amount needs an ISO 4217 currency' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope not in ('order', 'products', 'categories', 'collections') then
    raise exception 'scope is order, products, categories, collections' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if jsonb_typeof(coalesce(data -> 'targets', '[]'::jsonb)) <> 'array' then
    raise exception 'targets is an array of ids' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  select coalesce(array_agg(distinct e::uuid), '{}') into v_targets
  from jsonb_array_elements_text(coalesce(data -> 'targets', '[]'::jsonb)) e;
  if (v_scope = 'order') <> (cardinality(v_targets) = 0) then
    raise exception 'an order promotion has no targets; the other scopes need at least one' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope <> 'order' and cardinality(v_targets) <> (case v_scope
    when 'products' then (select count(*) from "better_supabase"."products" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'categories' then (select count(*) from "better_supabase"."categories" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'collections' then (select count(*) from "better_supabase"."collections" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    else 0 end) then
    raise exception 'every target is a product, category or collection of this organization' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (data ->> 'startsAt') is not null and (data ->> 'endsAt') is not null
    and (data ->> 'endsAt')::timestamptz <= (data ->> 'startsAt')::timestamptz then
    raise exception 'endsAt is after startsAt' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if coalesce((data ->> 'usageLimit')::integer, 1) < 1 or coalesce((data ->> 'perCustomerLimit')::integer, 1) < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  if v_id is null then
    insert into "better_supabase"."promotions" ("tenant_id", "name", "description", "kind", "percent", "currency", "amount", "min_subtotal", "scope", "target_ids", "starts_at", "ends_at", "usage_limit", "per_customer_limit", "stackable", "priority", "automatic", "active")
    values (v_tenant, data ->> 'name', data ->> 'description', v_kind, v_percent, case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end, case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end, (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end), v_scope, v_targets, (data ->> 'startsAt')::timestamptz, (data ->> 'endsAt')::timestamptz, (data ->> 'usageLimit')::integer, (data ->> 'perCustomerLimit')::integer, coalesce((data ->> 'stackable')::boolean, false), coalesce((data ->> 'priority')::integer, 0), coalesce((data ->> 'automatic')::boolean, false), coalesce((data ->> 'active')::boolean, true))
    returning "id" into v_id;
  else
    update "better_supabase"."promotions" x set
      "name" = data ->> 'name',
      "description" = data ->> 'description',
      "kind" = v_kind,
      "percent" = v_percent,
      "currency" = case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end,
      "amount" = case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end,
      "min_subtotal" = (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end),
      "scope" = v_scope,
      "target_ids" = v_targets,
      "starts_at" = (data ->> 'startsAt')::timestamptz,
      "ends_at" = (data ->> 'endsAt')::timestamptz,
      "usage_limit" = (data ->> 'usageLimit')::integer,
      "per_customer_limit" = (data ->> 'perCustomerLimit')::integer,
      "stackable" = coalesce((data ->> 'stackable')::boolean, false),
      "priority" = coalesce((data ->> 'priority')::integer, 0),
      "automatic" = coalesce((data ->> 'automatic')::boolean, false),
      "active" = coalesce((data ->> 'active')::boolean, true),
      "updated_at" = now()
    where x."id" = v_id;
  end if;
  if coalesce((data ->> 'active')::boolean, true) then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_promotion"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_promotion"(uuid, uuid, jsonb) to authenticated, service_role;

-- before_promotion_activate(promotion) runs after the write, so it reads
-- the promotion as it will be; raising refuses the activation.
create or replace function "better_supabase"."set_promotion_active"(promotion uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = set_promotion_active.promotion;
  if not found then
    raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  update "better_supabase"."promotions" x set "active" = set_promotion_active.active, "updated_at" = now()
  where x."id" = set_promotion_active.promotion;
  if set_promotion_active.active then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using set_promotion_active.promotion;
    end if;
  end;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_promotion_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_promotion_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a promotion nobody redeemed; deactivate one that was.
create or replace function "better_supabase"."delete_promotion"(promotion uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = delete_promotion.promotion;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."promotion_redemptions" x where x."promotion_id" = delete_promotion.promotion) then
    raise exception 'the promotion was redeemed; deactivate it instead' using errcode = '55000', hint = 'PROMOTIONS_IN_USE';
  end if;
  delete from "better_supabase"."promotions" x where x."id" = delete_promotion.promotion;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_promotion"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_promotion"(uuid) to authenticated, service_role;

-- Adds codes to a promotion: the given ones, or count generated ones of
-- the prefix and eight random characters. Codes are stored upper case and
-- are unique per organization.
create or replace function "better_supabase"."create_promotion_codes"(promotion uuid, codes text[] default null,
  count integer default null, prefix text default null, usage_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_code text;
  v_id uuid;
  v_out jsonb := '[]';
  v_prefix text := coalesce(upper(btrim(create_promotion_codes.prefix)), '');
  v_bytes bytea;
  v_attempts integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = create_promotion_codes.promotion;
  if not found then
    raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if (create_promotion_codes.codes is null) = (create_promotion_codes.count is null) then
    raise exception 'pass codes or a count' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.count is not null and (create_promotion_codes.count < 1 or create_promotion_codes.count > 10000) then
    raise exception 'count is from 1 to 10000' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.usage_limit is not null and create_promotion_codes.usage_limit < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_prefix !~ '^[A-Z0-9_-]{0,32}$' then
    raise exception 'a prefix has up to 32 letters, digits, dashes or underscores' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.codes is not null then
    foreach v_code in array create_promotion_codes.codes loop
      v_code := upper(btrim(v_code));
      if v_code is null or v_code !~ '^[A-Z0-9_-]{3,40}$' then
        raise exception 'a code has 3 to 40 letters, digits, dashes or underscores' using errcode = '22023', hint = 'PROMOTIONS_CODE_FORMAT';
      end if;
      begin
        insert into "better_supabase"."promotion_codes" ("tenant_id", "promotion_id", "code", "usage_limit")
        values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
        returning "id" into v_id;
      exception when unique_violation then
        raise exception 'another promotion uses this code' using errcode = '23505', hint = 'PROMOTIONS_CODE_TAKEN';
      end;
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
    end loop;
    return v_out;
  end if;
  while jsonb_array_length(v_out) < create_promotion_codes.count loop
    v_attempts := v_attempts + 1;
    if v_attempts > create_promotion_codes.count * 4 + 10 then
      raise exception 'couldn''t generate enough unique codes; use a longer prefix' using errcode = '55000', hint = 'PROMOTIONS_CODE_SPACE';
    end if;
    v_bytes := extensions.gen_random_bytes(8);
    v_code := v_prefix;
    for i in 0..7 loop
      v_code := v_code || substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    insert into "better_supabase"."promotion_codes" ("tenant_id", "promotion_id", "code", "usage_limit")
    values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
    on conflict do nothing
    returning "id" into v_id;
    if v_id is not null then
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
      v_id := null;
    end if;
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."create_promotion_codes"(uuid, text[], integer, text, integer) from public, anon;
grant execute on function "better_supabase"."create_promotion_codes"(uuid, text[], integer, text, integer) to authenticated, service_role;

-- Deletes a code nobody redeemed.
create or replace function "better_supabase"."delete_promotion_code"(code uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_used integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."redemptions" into v_tenant, v_used from "better_supabase"."promotion_codes" x where x."id" = delete_promotion_code.code;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if v_used > 0 then
    raise exception 'the code was redeemed' using errcode = '55000', hint = 'PROMOTIONS_IN_USE';
  end if;
  delete from "better_supabase"."promotion_codes" x where x."id" = delete_promotion_code.code;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_promotion_code"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_promotion_code"(uuid) to authenticated, service_role;

-- Puts a code on the caller's open cart. Whether it applies (minimum
-- subtotal, products, stacking) shows when the cart is priced.
create or replace function "better_supabase"."apply_promotion_code"(cart uuid, code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_code record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status
  into v_cart from "better_supabase"."carts" x where x."id" = apply_promotion_code.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  select k."id" as id, k."code" as code, k."promotion_id" as promotion,
    k."usage_limit" as code_limit, k."redemptions" as code_used,
    x."usage_limit" as usage_limit, x."redemptions" as used
  into v_code
  from "better_supabase"."promotion_codes" k join "better_supabase"."promotions" x on x."id" = k."promotion_id"
  where k."tenant_id" = v_cart.tenant and k."code" = upper(btrim(apply_promotion_code.code))
    and x."active" and (x."starts_at" is null or x."starts_at" <= now())
    and (x."ends_at" is null or x."ends_at" > now());
  if not found then
    raise exception 'this code is unknown or no longer valid' using errcode = 'P0002', hint = 'PROMOTIONS_CODE_INVALID';
  end if;
  if (v_code.code_limit is not null and v_code.code_used >= v_code.code_limit)
    or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
    raise exception 'this code was used up' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
  end if;
  if (select count(*) from "better_supabase"."cart_promotion_codes" x where x."cart_id" = apply_promotion_code.cart and x."code_id" <> v_code.id) >= 5 then
    raise exception 'a cart holds up to 5 codes' using errcode = '55000', hint = 'PROMOTIONS_TOO_MANY_CODES';
  end if;
  insert into "better_supabase"."cart_promotion_codes" ("tenant_id", "cart_id", "code_id")
  values (v_cart.tenant, apply_promotion_code.cart, v_code.id)
  on conflict do nothing;
  return jsonb_build_object('codeId', v_code.id, 'code', v_code.code, 'promotionId', v_code.promotion);
end;
$$;
revoke execute on function "better_supabase"."apply_promotion_code"(uuid, text) from public, anon;
grant execute on function "better_supabase"."apply_promotion_code"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_promotion_code"(cart uuid, code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."user_id" as owner, x."status" as status
  into v_cart from "better_supabase"."carts" x where x."id" = remove_promotion_code.cart;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  delete from "better_supabase"."cart_promotion_codes" x
  where x."cart_id" = remove_promotion_code.cart
    and x."code_id" in (select k."id" from "better_supabase"."promotion_codes" k where k."code" = upper(btrim(remove_promotion_code.code)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_promotion_code"(uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_promotion_code"(uuid, text) to authenticated, service_role;

-- Rounds half to even, like money everywhere else in the commerce blocks.
create or replace function "better_supabase"."round_half_even"(p_value numeric)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value - floor(p_value) > 0.5 then floor(p_value)::bigint + 1
    when p_value - floor(p_value) < 0.5 then floor(p_value)::bigint
    when floor(p_value)::bigint % 2 = 0 then floor(p_value)::bigint
    else floor(p_value)::bigint + 1
  end
$$;
revoke execute on function "better_supabase"."round_half_even"(numeric) from public, anon, authenticated;

-- The cart's discounts: lines maps a line id to its discount, applied
-- lists the promotions in the order they applied, and problems the codes
-- that don't apply. Promotions run by priority (highest first); a
-- promotion that isn't stackable never combines with another. p_lines
-- are the priced lines (id, productId, subtotal as text). Internal: the
-- orders cart_totals calls it.
create or replace function "better_supabase"."cart_discounts"(p_cart uuid, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_promo record;
  v_reason text;
  v_eligible text[];
  v_base bigint;
  v_rem jsonb;
  v_disc jsonb := '{}';
  v_applied jsonb := '[]';
  v_problems jsonb := '[]';
  v_free boolean := false;
  v_stackable boolean := true;
  v_amount bigint;
  v_left bigint;
  v_share bigint;
  v_line_rem bigint;
  v_id text;
begin
  select x."tenant_id" as tenant, x."user_id" as owner, x."currency" as currency, x."email" as email
  into v_cart from "better_supabase"."carts" x where x."id" = p_cart;
  select coalesce(jsonb_object_agg(e ->> 'id', (e ->> 'subtotal')::bigint), '{}') into v_rem
  from jsonb_array_elements(p_lines) e;
  for v_promo in
    select x."id" as id, x."name" as name, x."kind" as kind, x."percent" as percent,
      x."currency" as currency, x."amount" as amount, x."min_subtotal" as min_subtotal,
      x."scope" as scope, x."target_ids" as targets, x."usage_limit" as usage_limit,
      x."per_customer_limit" as per_customer_limit, x."redemptions" as used, x."stackable" as stackable,
      x."automatic" as automatic,
      (x."active" and (x."starts_at" is null or x."starts_at" <= now())
        and (x."ends_at" is null or x."ends_at" > now())) as live,
      code.id as code_id, code.code as code, code.usage_limit as code_limit, code.used as code_used
    from "better_supabase"."promotions" x
    left join lateral (
      select k."id" as id, k."code" as code, k."usage_limit" as usage_limit, k."redemptions" as used
      from "better_supabase"."cart_promotion_codes" y join "better_supabase"."promotion_codes" k on k."id" = y."code_id"
      where y."cart_id" = p_cart and k."promotion_id" = x."id"
      order by y."created_at", k."id"
      limit 1
    ) code on true
    where x."tenant_id" = v_cart.tenant and (code.id is not null or (x."automatic" and x."active"))
    order by x."priority" desc, x."created_at", x."id"
  loop
    v_reason := null;
    if not v_promo.live then
      v_reason := 'expired';
    elsif (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.code_limit is not null and v_promo.code_used >= v_promo.code_limit)
      or (v_promo.per_customer_limit is not null
        and (select count(*) from "better_supabase"."promotion_redemptions" y where y."promotion_id" = v_promo.id and y."status" = 'redeemed'
      and (y."customer_id" = v_cart.owner or (v_cart.email is not null and lower(y."email") = lower(v_cart.email)))) >= v_promo.per_customer_limit) then
      v_reason := 'limit_reached';
    elsif v_promo.currency is not null and v_promo.currency <> v_cart.currency then
      v_reason := 'currency';
    else
      select coalesce(array_agg(e ->> 'id' order by n), '{}'), coalesce(sum((e ->> 'subtotal')::bigint), 0)
      into v_eligible, v_base
      from jsonb_array_elements(p_lines) with ordinality as l(e, n)
      where v_promo.scope = 'order'
      or (v_promo.scope = 'products' and (e ->> 'productId')::uuid = any (v_promo.targets))
      or (v_promo.scope = 'categories' and exists (
      with recursive d (id) as (
        select unnest(v_promo.targets)
        union
        select x."id" from "better_supabase"."categories" x join d on x."parent_id" = d.id
      )
      select 1 from "better_supabase"."product_categories" y where y."product_id" = (e ->> 'productId')::uuid and y."category_id" in (select id from d)
    ))
      or (v_promo.scope = 'collections' and exists (select 1 from "better_supabase"."collection_products" y where y."product_id" = (e ->> 'productId')::uuid and y."collection_id" = any (v_promo.targets)));
      if cardinality(v_eligible) = 0 then
        v_reason := 'not_applicable';
      elsif v_promo.min_subtotal is not null and v_base < v_promo.min_subtotal then
        v_reason := 'min_subtotal';
      elsif jsonb_array_length(v_applied) > 0 and not (v_stackable and v_promo.stackable) then
        v_reason := 'not_combinable';
      end if;
    end if;
    if v_reason is not null then
      if v_promo.code_id is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'promotion_unavailable',
          'promotionId', v_promo.id, 'code', v_promo.code, 'reason', v_reason));
      end if;
      continue;
    end if;
    v_amount := 0;
    if v_promo.kind = 'percentage' then
      foreach v_id in array v_eligible loop
        v_line_rem := (v_rem ->> v_id)::bigint;
        v_share := least("better_supabase"."round_half_even"(v_line_rem * v_promo.percent / 100), v_line_rem);
        v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
        v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
        v_amount := v_amount + v_share;
      end loop;
    elsif v_promo.kind = 'fixed' then
      select coalesce(sum((v_rem ->> e)::bigint), 0) into v_base from unnest(v_eligible) e;
      v_left := least(v_promo.amount, v_base);
      if v_base > 0 then
        foreach v_id in array v_eligible loop
          v_line_rem := (v_rem ->> v_id)::bigint;
          v_share := floor(least(v_promo.amount, v_base)::numeric * v_line_rem / v_base)::bigint;
          v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
          v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
          v_left := v_left - v_share;
        end loop;
        foreach v_id in array v_eligible loop
          exit when v_left = 0;
          if (v_rem ->> v_id)::bigint > 0 then
            v_rem := jsonb_set(v_rem, array[v_id], to_jsonb((v_rem ->> v_id)::bigint - 1));
            v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + 1));
            v_left := v_left - 1;
          end if;
        end loop;
        v_amount := least(v_promo.amount, v_base);
      end if;
    else
      v_free := true;
    end if;
    v_stackable := v_stackable and v_promo.stackable;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('promotionId', v_promo.id, 'name', v_promo.name,
      'kind', v_promo.kind, 'codeId', v_promo.code_id, 'code', v_promo.code, 'amount', v_amount::text));
  end loop;
  select coalesce(jsonb_object_agg(key, value #>> '{}'), '{}') into v_disc from jsonb_each(v_disc);
  return jsonb_build_object('lines', v_disc, 'applied', v_applied, 'freeShipping', v_free, 'problems', v_problems);
end;
$$;
revoke execute on function "better_supabase"."cart_discounts"(uuid, jsonb) from public, anon, authenticated;

-- Records the order's promotions inside checkout. The promotion row lock
-- keeps usage limits under concurrent checkouts; a limit reached since the
-- cart was priced fails the checkout (PROMOTIONS_LIMIT_REACHED).
-- Internal: the orders place_order calls it.
create or replace function "better_supabase"."redeem_promotions"(p_order uuid, p_applied jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_entry jsonb;
  v_promo record;
  v_code record;
  v_id uuid;
  v_count integer := 0;
begin
  select x."id" as id, x."tenant_id" as tenant, x."customer_id" as customer, x."email" as email,
    x."currency" as currency
  into v_order from "better_supabase"."orders" x where x."id" = p_order;
  for v_entry in select e from jsonb_array_elements(coalesce(p_applied, '[]'::jsonb)) e loop
    select x."id" as id, x."usage_limit" as usage_limit, x."per_customer_limit" as per_customer_limit,
      x."redemptions" as used
    into v_promo from "better_supabase"."promotions" x where x."id" = (v_entry ->> 'promotionId')::uuid for update;
    if not found or (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.per_customer_limit is not null
        and (select count(*) from "better_supabase"."promotion_redemptions" y where y."promotion_id" = v_promo.id and y."status" = 'redeemed'
      and (y."customer_id" = v_order.customer or (v_order.email is not null and lower(y."email") = lower(v_order.email)))) >= v_promo.per_customer_limit) then
      raise exception 'a promotion on this cart reached its usage limit' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
    end if;
    if v_entry ->> 'codeId' is not null then
      select x."usage_limit" as usage_limit, x."redemptions" as used
      into v_code from "better_supabase"."promotion_codes" x where x."id" = (v_entry ->> 'codeId')::uuid for update;
      if not found or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
        raise exception 'a code on this cart was used up' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
      end if;
      update "better_supabase"."promotion_codes" x set "redemptions" = x."redemptions" + 1 where x."id" = (v_entry ->> 'codeId')::uuid;
    end if;
    update "better_supabase"."promotions" x set "redemptions" = x."redemptions" + 1 where x."id" = v_promo.id;
    insert into "better_supabase"."promotion_redemptions" ("tenant_id", "promotion_id", "code_id", "order_id", "customer_id",
      "email", "currency", "amount")
    values (v_order.tenant, v_promo.id, (v_entry ->> 'codeId')::uuid, v_order.id, v_order.customer, v_order.email,
      v_order.currency, (v_entry ->> 'amount')::bigint)
    returning "id" into v_id;
    perform "better_supabase".emit_event('promotion.redeemed', jsonb_build_object('organizationId', v_order.tenant, 'id', v_id, 'promotionId', v_promo.id, 'code', v_entry ->> 'code', 'orderId', v_order.id, 'currency', v_order.currency, 'amount', v_entry ->> 'amount'), 'promotion-redemptions/' || v_id::text, (v_order.tenant)::text, null, 'better-supabase/promotions');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."redeem_promotions"(uuid, jsonb) from public, anon, authenticated;

-- Gives a cancelled order's redemptions back to their limits. Internal:
-- the orders cancel_order and expire_orders call it.
create or replace function "better_supabase"."release_promotions"(p_order uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    update "better_supabase"."promotion_redemptions" x set "status" = 'released', "released_at" = now()
    where x."order_id" = p_order and x."status" = 'redeemed'
    returning x."promotion_id" as promotion, x."code_id" as code
  loop
    update "better_supabase"."promotions" x set "redemptions" = greatest(x."redemptions" - 1, 0) where x."id" = v_row.promotion;
    if v_row.code is not null then
      update "better_supabase"."promotion_codes" x set "redemptions" = greatest(x."redemptions" - 1, 0) where x."id" = v_row.code;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."release_promotions"(uuid) from public, anon, authenticated;

-- Moves the codes of a cart merged into another, up to what a cart
-- holds. Internal: the orders merge_carts calls it.
create or replace function "better_supabase"."move_cart_codes"(p_from uuid, p_to uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into "better_supabase"."cart_promotion_codes" ("tenant_id", "cart_id", "code_id")
  select x."tenant_id", p_to, x."code_id"
  from "better_supabase"."cart_promotion_codes" x
  where x."cart_id" = p_from
    and not exists (select 1 from "better_supabase"."cart_promotion_codes" y where y."cart_id" = p_to and y."code_id" = x."code_id")
  order by x."created_at"
  limit greatest(5 - (select count(*) from "better_supabase"."cart_promotion_codes" y where y."cart_id" = p_to), 0);
  get diagnostics v_count = row_count;
  delete from "better_supabase"."cart_promotion_codes" x where x."cart_id" = p_from;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."move_cart_codes"(uuid, uuid) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_85_promotions.sql
-- better-supabase module: promotions
-- @bsb-block-data promotions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('promotions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_85_promotions.sql
-- better-supabase module: promotions
-- @bsb-block promotions@1 managed
-- Percentage, fixed and free-shipping promotions, automatic or by code, with usage limits and stacking rules, priced into orders carts.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Promotions (percentage, fixed or free shipping), automatic or by code,
-- with usage limits and stacking rules; orders prices carts with them.

create table if not exists "app_private"."promotions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "description" text check (length("description") <= 2000),
  "kind" text not null check ("kind" in ('percentage', 'fixed', 'free_shipping')),
  "percent" numeric(5, 2) check ("percent" > 0 and "percent" <= 100),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint check ("amount" > 0),
  "min_subtotal" bigint check ("min_subtotal" > 0),
  "scope" text not null default 'order' check ("scope" in ('order', 'products', 'categories', 'collections')),
  "target_ids" uuid[] not null default '{}',
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "usage_limit" integer check ("usage_limit" > 0),
  "per_customer_limit" integer check ("per_customer_limit" > 0),
  "redemptions" integer not null default 0 check ("redemptions" >= 0),
  "stackable" boolean not null default false,
  "priority" integer not null default 0,
  "automatic" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("kind" = 'percentage') = ("percent" is not null)),
  check (("kind" = 'fixed') = ("amount" is not null)),
  check (("amount" is null and "min_subtotal" is null) or "currency" is not null),
  check ("ends_at" is null or "starts_at" is null or "ends_at" > "starts_at")
);
create index if not exists promotions_tenant_idx on "app_private"."promotions" ("tenant_id", "active", "automatic");
alter table "app_private"."promotions" enable row level security;
revoke all on "app_private"."promotions" from anon, authenticated;
grant select on "app_private"."promotions" to authenticated;
grant all on "app_private"."promotions" to service_role;
drop policy if exists promotions_read on "app_private"."promotions";
create policy promotions_read on "app_private"."promotions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')));

create table if not exists "app_private"."promotion_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "promotion_id" uuid not null references "app_private"."promotions" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Z0-9_-]{3,40}$'),
  "usage_limit" integer check ("usage_limit" > 0),
  "redemptions" integer not null default 0 check ("redemptions" >= 0),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
create index if not exists promotion_codes_promotion_idx on "app_private"."promotion_codes" ("promotion_id");
alter table "app_private"."promotion_codes" enable row level security;
revoke all on "app_private"."promotion_codes" from anon, authenticated;
grant select on "app_private"."promotion_codes" to authenticated;
grant all on "app_private"."promotion_codes" to service_role;
drop policy if exists promotion_codes_read on "app_private"."promotion_codes";
create policy promotion_codes_read on "app_private"."promotion_codes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')));

create table if not exists "app_private"."cart_promotion_codes" (
  "tenant_id" uuid not null,
  "cart_id" uuid not null references "better_supabase"."carts" ("id") on delete cascade,
  "code_id" uuid not null references "app_private"."promotion_codes" ("id") on delete cascade,
  "created_at" timestamptz not null default now(),
  primary key ("cart_id", "code_id")
);
create index if not exists cart_promotion_codes_code_idx on "app_private"."cart_promotion_codes" ("code_id");
alter table "app_private"."cart_promotion_codes" enable row level security;
revoke all on "app_private"."cart_promotion_codes" from anon, authenticated;
grant select on "app_private"."cart_promotion_codes" to authenticated;
grant all on "app_private"."cart_promotion_codes" to service_role;
drop policy if exists cart_promotion_codes_read on "app_private"."cart_promotion_codes";
create policy cart_promotion_codes_read on "app_private"."cart_promotion_codes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')) or exists (select 1 from "better_supabase"."carts" x where x."id" = "cart_id" and x."user_id" = (select auth.uid())));

create table if not exists "app_private"."promotion_redemptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "promotion_id" uuid not null references "app_private"."promotions" ("id"),
  "code_id" uuid references "app_private"."promotion_codes" ("id") on delete set null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "customer_id" uuid references auth.users (id) on delete set null,
  "email" text,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint not null check ("amount" >= 0),
  "status" text not null default 'redeemed' check ("status" in ('redeemed', 'released')),
  "created_at" timestamptz not null default now(),
  "released_at" timestamptz,
  unique ("order_id", "promotion_id")
);
create index if not exists promotion_redemptions_promotion_idx on "app_private"."promotion_redemptions" ("promotion_id", "status");
create index if not exists promotion_redemptions_customer_idx on "app_private"."promotion_redemptions" ("customer_id");
create index if not exists promotion_redemptions_code_idx on "app_private"."promotion_redemptions" ("code_id");
alter table "app_private"."promotion_redemptions" enable row level security;
revoke all on "app_private"."promotion_redemptions" from anon, authenticated;
grant select on "app_private"."promotion_redemptions" to authenticated;
grant all on "app_private"."promotion_redemptions" to service_role;
drop policy if exists promotion_redemptions_read on "app_private"."promotion_redemptions";
create policy promotion_redemptions_read on "app_private"."promotion_redemptions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')) or "customer_id" = (select auth.uid()));

-- Creates or updates a promotion. data holds name, description, kind
-- (percentage, fixed or free_shipping), percent, currency, amount and
-- minSubtotal (minor units as text), scope (order, products, categories or
-- collections) with targets, startsAt, endsAt, usageLimit,
-- perCustomerLimit, stackable, priority, automatic and active.
drop function if exists "app_private"."save_promotion"(uuid, uuid, jsonb, jsonb);
create or replace function "app_private"."save_promotion"(tenant uuid, promotion uuid, data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := save_promotion.tenant;
  v_id uuid := save_promotion.promotion;
  v_kind text := data ->> 'kind';
  v_scope text := coalesce(data ->> 'scope', 'order');
  v_currency text := data ->> 'currency';
  v_percent numeric;
  v_targets uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_id is not null then
    select x."tenant_id" into v_tenant from "app_private"."promotions" x where x."id" = v_id for update;
    if not found or v_tenant is distinct from save_promotion.tenant then
      raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
    end if;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if jsonb_typeof(data) is distinct from 'object' then
    raise exception 'data is an object' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind is null or v_kind not in ('percentage', 'fixed', 'free_shipping') then
    raise exception 'kind is percentage, fixed or free_shipping' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind = 'percentage' then
    if coalesce(data ->> 'percent', '') !~ '^[0-9]{1,3}([.][0-9]{1,2})?$' or (data ->> 'percent')::numeric <= 0 or (data ->> 'percent')::numeric > 100 then
      raise exception 'percent is a number above 0 and at most 100, with up to two decimals' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
    end if;
    v_percent := (data ->> 'percent')::numeric;
  end if;
  if v_kind = 'fixed' and ((case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) is null or (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) <= 0) then
    raise exception 'a fixed promotion has an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if data ? 'minSubtotal' and data ->> 'minSubtotal' is not null and ((case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) is null or (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) <= 0) then
    raise exception 'minSubtotal is an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (v_kind = 'fixed' or data ->> 'minSubtotal' is not null) and (v_currency is null or "better_supabase"."currency_minor_units"(v_currency) is null) then
    raise exception 'an amount needs an ISO 4217 currency' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope not in ('order', 'products', 'categories', 'collections') then
    raise exception 'scope is order, products, categories, collections' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if jsonb_typeof(coalesce(data -> 'targets', '[]'::jsonb)) <> 'array' then
    raise exception 'targets is an array of ids' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  select coalesce(array_agg(distinct e::uuid), '{}') into v_targets
  from jsonb_array_elements_text(coalesce(data -> 'targets', '[]'::jsonb)) e;
  if (v_scope = 'order') <> (cardinality(v_targets) = 0) then
    raise exception 'an order promotion has no targets; the other scopes need at least one' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope <> 'order' and cardinality(v_targets) <> (case v_scope
    when 'products' then (select count(*) from "better_supabase"."products" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'categories' then (select count(*) from "better_supabase"."categories" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'collections' then (select count(*) from "better_supabase"."collections" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    else 0 end) then
    raise exception 'every target is a product, category or collection of this organization' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (data ->> 'startsAt') is not null and (data ->> 'endsAt') is not null
    and (data ->> 'endsAt')::timestamptz <= (data ->> 'startsAt')::timestamptz then
    raise exception 'endsAt is after startsAt' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if coalesce((data ->> 'usageLimit')::integer, 1) < 1 or coalesce((data ->> 'perCustomerLimit')::integer, 1) < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  if v_id is null then
    insert into "app_private"."promotions" ("tenant_id", "name", "description", "kind", "percent", "currency", "amount", "min_subtotal", "scope", "target_ids", "starts_at", "ends_at", "usage_limit", "per_customer_limit", "stackable", "priority", "automatic", "active")
    values (v_tenant, data ->> 'name', data ->> 'description', v_kind, v_percent, case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end, case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end, (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end), v_scope, v_targets, (data ->> 'startsAt')::timestamptz, (data ->> 'endsAt')::timestamptz, (data ->> 'usageLimit')::integer, (data ->> 'perCustomerLimit')::integer, coalesce((data ->> 'stackable')::boolean, false), coalesce((data ->> 'priority')::integer, 0), coalesce((data ->> 'automatic')::boolean, false), coalesce((data ->> 'active')::boolean, true))
    returning "id" into v_id;
  else
    update "app_private"."promotions" x set
      "name" = data ->> 'name',
      "description" = data ->> 'description',
      "kind" = v_kind,
      "percent" = v_percent,
      "currency" = case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end,
      "amount" = case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end,
      "min_subtotal" = (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end),
      "scope" = v_scope,
      "target_ids" = v_targets,
      "starts_at" = (data ->> 'startsAt')::timestamptz,
      "ends_at" = (data ->> 'endsAt')::timestamptz,
      "usage_limit" = (data ->> 'usageLimit')::integer,
      "per_customer_limit" = (data ->> 'perCustomerLimit')::integer,
      "stackable" = coalesce((data ->> 'stackable')::boolean, false),
      "priority" = coalesce((data ->> 'priority')::integer, 0),
      "automatic" = coalesce((data ->> 'automatic')::boolean, false),
      "active" = coalesce((data ->> 'active')::boolean, true),
      "updated_at" = now()
    where x."id" = v_id;
  end if;
  if coalesce((data ->> 'active')::boolean, true) then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "app_private"."save_promotion"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_promotion"(uuid, uuid, jsonb) to authenticated, service_role;

-- before_promotion_activate(promotion) runs after the write, so it reads
-- the promotion as it will be; raising refuses the activation.
create or replace function "app_private"."set_promotion_active"(promotion uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "app_private"."promotions" x where x."id" = set_promotion_active.promotion;
  if not found then
    raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  update "app_private"."promotions" x set "active" = set_promotion_active.active, "updated_at" = now()
  where x."id" = set_promotion_active.promotion;
  if set_promotion_active.active then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using set_promotion_active.promotion;
    end if;
  end;
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."set_promotion_active"(uuid, boolean) from public, anon;
grant execute on function "app_private"."set_promotion_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a promotion nobody redeemed; deactivate one that was.
create or replace function "app_private"."delete_promotion"(promotion uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "app_private"."promotions" x where x."id" = delete_promotion.promotion;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if exists (select 1 from "app_private"."promotion_redemptions" x where x."promotion_id" = delete_promotion.promotion) then
    raise exception 'the promotion was redeemed; deactivate it instead' using errcode = '55000', hint = 'PROMOTIONS_IN_USE';
  end if;
  delete from "app_private"."promotions" x where x."id" = delete_promotion.promotion;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_promotion"(uuid) from public, anon;
grant execute on function "app_private"."delete_promotion"(uuid) to authenticated, service_role;

-- Adds codes to a promotion: the given ones, or count generated ones of
-- the prefix and eight random characters. Codes are stored upper case and
-- are unique per organization.
create or replace function "app_private"."create_promotion_codes"(promotion uuid, codes text[] default null,
  count integer default null, prefix text default null, usage_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_code text;
  v_id uuid;
  v_out jsonb := '[]';
  v_prefix text := coalesce(upper(btrim(create_promotion_codes.prefix)), '');
  v_bytes bytea;
  v_attempts integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "app_private"."promotions" x where x."id" = create_promotion_codes.promotion;
  if not found then
    raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if (create_promotion_codes.codes is null) = (create_promotion_codes.count is null) then
    raise exception 'pass codes or a count' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.count is not null and (create_promotion_codes.count < 1 or create_promotion_codes.count > 10000) then
    raise exception 'count is from 1 to 10000' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.usage_limit is not null and create_promotion_codes.usage_limit < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_prefix !~ '^[A-Z0-9_-]{0,32}$' then
    raise exception 'a prefix has up to 32 letters, digits, dashes or underscores' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.codes is not null then
    foreach v_code in array create_promotion_codes.codes loop
      v_code := upper(btrim(v_code));
      if v_code is null or v_code !~ '^[A-Z0-9_-]{3,40}$' then
        raise exception 'a code has 3 to 40 letters, digits, dashes or underscores' using errcode = '22023', hint = 'PROMOTIONS_CODE_FORMAT';
      end if;
      begin
        insert into "app_private"."promotion_codes" ("tenant_id", "promotion_id", "code", "usage_limit")
        values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
        returning "id" into v_id;
      exception when unique_violation then
        raise exception 'another promotion uses this code' using errcode = '23505', hint = 'PROMOTIONS_CODE_TAKEN';
      end;
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
    end loop;
    return v_out;
  end if;
  while jsonb_array_length(v_out) < create_promotion_codes.count loop
    v_attempts := v_attempts + 1;
    if v_attempts > create_promotion_codes.count * 4 + 10 then
      raise exception 'couldn''t generate enough unique codes; use a longer prefix' using errcode = '55000', hint = 'PROMOTIONS_CODE_SPACE';
    end if;
    v_bytes := extensions.gen_random_bytes(8);
    v_code := v_prefix;
    for i in 0..7 loop
      v_code := v_code || substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    insert into "app_private"."promotion_codes" ("tenant_id", "promotion_id", "code", "usage_limit")
    values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
    on conflict do nothing
    returning "id" into v_id;
    if v_id is not null then
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
      v_id := null;
    end if;
  end loop;
  return v_out;
end;
$$;
revoke execute on function "app_private"."create_promotion_codes"(uuid, text[], integer, text, integer) from public, anon;
grant execute on function "app_private"."create_promotion_codes"(uuid, text[], integer, text, integer) to authenticated, service_role;

-- Deletes a code nobody redeemed.
create or replace function "app_private"."delete_promotion_code"(code uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_used integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."redemptions" into v_tenant, v_used from "app_private"."promotion_codes" x where x."id" = delete_promotion_code.code;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if v_used > 0 then
    raise exception 'the code was redeemed' using errcode = '55000', hint = 'PROMOTIONS_IN_USE';
  end if;
  delete from "app_private"."promotion_codes" x where x."id" = delete_promotion_code.code;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_promotion_code"(uuid) from public, anon;
grant execute on function "app_private"."delete_promotion_code"(uuid) to authenticated, service_role;

-- Puts a code on the caller's open cart. Whether it applies (minimum
-- subtotal, products, stacking) shows when the cart is priced.
create or replace function "app_private"."apply_promotion_code"(cart uuid, code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_code record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status
  into v_cart from "better_supabase"."carts" x where x."id" = apply_promotion_code.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  select k."id" as id, k."code" as code, k."promotion_id" as promotion,
    k."usage_limit" as code_limit, k."redemptions" as code_used,
    x."usage_limit" as usage_limit, x."redemptions" as used
  into v_code
  from "app_private"."promotion_codes" k join "app_private"."promotions" x on x."id" = k."promotion_id"
  where k."tenant_id" = v_cart.tenant and k."code" = upper(btrim(apply_promotion_code.code))
    and x."active" and (x."starts_at" is null or x."starts_at" <= now())
    and (x."ends_at" is null or x."ends_at" > now());
  if not found then
    raise exception 'this code is unknown or no longer valid' using errcode = 'P0002', hint = 'PROMOTIONS_CODE_INVALID';
  end if;
  if (v_code.code_limit is not null and v_code.code_used >= v_code.code_limit)
    or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
    raise exception 'this code was used up' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
  end if;
  if (select count(*) from "app_private"."cart_promotion_codes" x where x."cart_id" = apply_promotion_code.cart and x."code_id" <> v_code.id) >= 5 then
    raise exception 'a cart holds up to 5 codes' using errcode = '55000', hint = 'PROMOTIONS_TOO_MANY_CODES';
  end if;
  insert into "app_private"."cart_promotion_codes" ("tenant_id", "cart_id", "code_id")
  values (v_cart.tenant, apply_promotion_code.cart, v_code.id)
  on conflict do nothing;
  return jsonb_build_object('codeId', v_code.id, 'code', v_code.code, 'promotionId', v_code.promotion);
end;
$$;
revoke execute on function "app_private"."apply_promotion_code"(uuid, text) from public, anon;
grant execute on function "app_private"."apply_promotion_code"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."remove_promotion_code"(cart uuid, code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."user_id" as owner, x."status" as status
  into v_cart from "better_supabase"."carts" x where x."id" = remove_promotion_code.cart;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  delete from "app_private"."cart_promotion_codes" x
  where x."cart_id" = remove_promotion_code.cart
    and x."code_id" in (select k."id" from "app_private"."promotion_codes" k where k."code" = upper(btrim(remove_promotion_code.code)));
  return found;
end;
$$;
revoke execute on function "app_private"."remove_promotion_code"(uuid, text) from public, anon;
grant execute on function "app_private"."remove_promotion_code"(uuid, text) to authenticated, service_role;

-- Rounds half to even, like money everywhere else in the commerce blocks.
create or replace function "app_private"."round_half_even"(p_value numeric)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value - floor(p_value) > 0.5 then floor(p_value)::bigint + 1
    when p_value - floor(p_value) < 0.5 then floor(p_value)::bigint
    when floor(p_value)::bigint % 2 = 0 then floor(p_value)::bigint
    else floor(p_value)::bigint + 1
  end
$$;
revoke execute on function "app_private"."round_half_even"(numeric) from public, anon, authenticated;

-- The cart's discounts: lines maps a line id to its discount, applied
-- lists the promotions in the order they applied, and problems the codes
-- that don't apply. Promotions run by priority (highest first); a
-- promotion that isn't stackable never combines with another. p_lines
-- are the priced lines (id, productId, subtotal as text). Internal: the
-- orders cart_totals calls it.
create or replace function "app_private"."cart_discounts"(p_cart uuid, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_promo record;
  v_reason text;
  v_eligible text[];
  v_base bigint;
  v_rem jsonb;
  v_disc jsonb := '{}';
  v_applied jsonb := '[]';
  v_problems jsonb := '[]';
  v_free boolean := false;
  v_stackable boolean := true;
  v_amount bigint;
  v_left bigint;
  v_share bigint;
  v_line_rem bigint;
  v_id text;
begin
  select x."tenant_id" as tenant, x."user_id" as owner, x."currency" as currency, x."email" as email
  into v_cart from "better_supabase"."carts" x where x."id" = p_cart;
  select coalesce(jsonb_object_agg(e ->> 'id', (e ->> 'subtotal')::bigint), '{}') into v_rem
  from jsonb_array_elements(p_lines) e;
  for v_promo in
    select x."id" as id, x."name" as name, x."kind" as kind, x."percent" as percent,
      x."currency" as currency, x."amount" as amount, x."min_subtotal" as min_subtotal,
      x."scope" as scope, x."target_ids" as targets, x."usage_limit" as usage_limit,
      x."per_customer_limit" as per_customer_limit, x."redemptions" as used, x."stackable" as stackable,
      x."automatic" as automatic,
      (x."active" and (x."starts_at" is null or x."starts_at" <= now())
        and (x."ends_at" is null or x."ends_at" > now())) as live,
      code.id as code_id, code.code as code, code.usage_limit as code_limit, code.used as code_used
    from "app_private"."promotions" x
    left join lateral (
      select k."id" as id, k."code" as code, k."usage_limit" as usage_limit, k."redemptions" as used
      from "app_private"."cart_promotion_codes" y join "app_private"."promotion_codes" k on k."id" = y."code_id"
      where y."cart_id" = p_cart and k."promotion_id" = x."id"
      order by y."created_at", k."id"
      limit 1
    ) code on true
    where x."tenant_id" = v_cart.tenant and (code.id is not null or (x."automatic" and x."active"))
    order by x."priority" desc, x."created_at", x."id"
  loop
    v_reason := null;
    if not v_promo.live then
      v_reason := 'expired';
    elsif (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.code_limit is not null and v_promo.code_used >= v_promo.code_limit)
      or (v_promo.per_customer_limit is not null
        and (select count(*) from "app_private"."promotion_redemptions" y where y."promotion_id" = v_promo.id and y."status" = 'redeemed'
      and (y."customer_id" = v_cart.owner or (v_cart.email is not null and lower(y."email") = lower(v_cart.email)))) >= v_promo.per_customer_limit) then
      v_reason := 'limit_reached';
    elsif v_promo.currency is not null and v_promo.currency <> v_cart.currency then
      v_reason := 'currency';
    else
      select coalesce(array_agg(e ->> 'id' order by n), '{}'), coalesce(sum((e ->> 'subtotal')::bigint), 0)
      into v_eligible, v_base
      from jsonb_array_elements(p_lines) with ordinality as l(e, n)
      where v_promo.scope = 'order'
      or (v_promo.scope = 'products' and (e ->> 'productId')::uuid = any (v_promo.targets))
      or (v_promo.scope = 'categories' and exists (
      with recursive d (id) as (
        select unnest(v_promo.targets)
        union
        select x."id" from "better_supabase"."categories" x join d on x."parent_id" = d.id
      )
      select 1 from "better_supabase"."product_categories" y where y."product_id" = (e ->> 'productId')::uuid and y."category_id" in (select id from d)
    ))
      or (v_promo.scope = 'collections' and exists (select 1 from "better_supabase"."collection_products" y where y."product_id" = (e ->> 'productId')::uuid and y."collection_id" = any (v_promo.targets)));
      if cardinality(v_eligible) = 0 then
        v_reason := 'not_applicable';
      elsif v_promo.min_subtotal is not null and v_base < v_promo.min_subtotal then
        v_reason := 'min_subtotal';
      elsif jsonb_array_length(v_applied) > 0 and not (v_stackable and v_promo.stackable) then
        v_reason := 'not_combinable';
      end if;
    end if;
    if v_reason is not null then
      if v_promo.code_id is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'promotion_unavailable',
          'promotionId', v_promo.id, 'code', v_promo.code, 'reason', v_reason));
      end if;
      continue;
    end if;
    v_amount := 0;
    if v_promo.kind = 'percentage' then
      foreach v_id in array v_eligible loop
        v_line_rem := (v_rem ->> v_id)::bigint;
        v_share := least("app_private"."round_half_even"(v_line_rem * v_promo.percent / 100), v_line_rem);
        v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
        v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
        v_amount := v_amount + v_share;
      end loop;
    elsif v_promo.kind = 'fixed' then
      select coalesce(sum((v_rem ->> e)::bigint), 0) into v_base from unnest(v_eligible) e;
      v_left := least(v_promo.amount, v_base);
      if v_base > 0 then
        foreach v_id in array v_eligible loop
          v_line_rem := (v_rem ->> v_id)::bigint;
          v_share := floor(least(v_promo.amount, v_base)::numeric * v_line_rem / v_base)::bigint;
          v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
          v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
          v_left := v_left - v_share;
        end loop;
        foreach v_id in array v_eligible loop
          exit when v_left = 0;
          if (v_rem ->> v_id)::bigint > 0 then
            v_rem := jsonb_set(v_rem, array[v_id], to_jsonb((v_rem ->> v_id)::bigint - 1));
            v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + 1));
            v_left := v_left - 1;
          end if;
        end loop;
        v_amount := least(v_promo.amount, v_base);
      end if;
    else
      v_free := true;
    end if;
    v_stackable := v_stackable and v_promo.stackable;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('promotionId', v_promo.id, 'name', v_promo.name,
      'kind', v_promo.kind, 'codeId', v_promo.code_id, 'code', v_promo.code, 'amount', v_amount::text));
  end loop;
  select coalesce(jsonb_object_agg(key, value #>> '{}'), '{}') into v_disc from jsonb_each(v_disc);
  return jsonb_build_object('lines', v_disc, 'applied', v_applied, 'freeShipping', v_free, 'problems', v_problems);
end;
$$;
revoke execute on function "app_private"."cart_discounts"(uuid, jsonb) from public, anon, authenticated;

-- Records the order's promotions inside checkout. The promotion row lock
-- keeps usage limits under concurrent checkouts; a limit reached since the
-- cart was priced fails the checkout (PROMOTIONS_LIMIT_REACHED).
-- Internal: the orders place_order calls it.
create or replace function "app_private"."redeem_promotions"(p_order uuid, p_applied jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_entry jsonb;
  v_promo record;
  v_code record;
  v_id uuid;
  v_count integer := 0;
begin
  select x."id" as id, x."tenant_id" as tenant, x."customer_id" as customer, x."email" as email,
    x."currency" as currency
  into v_order from "better_supabase"."orders" x where x."id" = p_order;
  for v_entry in select e from jsonb_array_elements(coalesce(p_applied, '[]'::jsonb)) e loop
    select x."id" as id, x."usage_limit" as usage_limit, x."per_customer_limit" as per_customer_limit,
      x."redemptions" as used
    into v_promo from "app_private"."promotions" x where x."id" = (v_entry ->> 'promotionId')::uuid for update;
    if not found or (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.per_customer_limit is not null
        and (select count(*) from "app_private"."promotion_redemptions" y where y."promotion_id" = v_promo.id and y."status" = 'redeemed'
      and (y."customer_id" = v_order.customer or (v_order.email is not null and lower(y."email") = lower(v_order.email)))) >= v_promo.per_customer_limit) then
      raise exception 'a promotion on this cart reached its usage limit' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
    end if;
    if v_entry ->> 'codeId' is not null then
      select x."usage_limit" as usage_limit, x."redemptions" as used
      into v_code from "app_private"."promotion_codes" x where x."id" = (v_entry ->> 'codeId')::uuid for update;
      if not found or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
        raise exception 'a code on this cart was used up' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
      end if;
      update "app_private"."promotion_codes" x set "redemptions" = x."redemptions" + 1 where x."id" = (v_entry ->> 'codeId')::uuid;
    end if;
    update "app_private"."promotions" x set "redemptions" = x."redemptions" + 1 where x."id" = v_promo.id;
    insert into "app_private"."promotion_redemptions" ("tenant_id", "promotion_id", "code_id", "order_id", "customer_id",
      "email", "currency", "amount")
    values (v_order.tenant, v_promo.id, (v_entry ->> 'codeId')::uuid, v_order.id, v_order.customer, v_order.email,
      v_order.currency, (v_entry ->> 'amount')::bigint)
    returning "id" into v_id;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."redeem_promotions"(uuid, jsonb) from public, anon, authenticated;

-- Gives a cancelled order's redemptions back to their limits. Internal:
-- the orders cancel_order and expire_orders call it.
create or replace function "app_private"."release_promotions"(p_order uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    update "app_private"."promotion_redemptions" x set "status" = 'released', "released_at" = now()
    where x."order_id" = p_order and x."status" = 'redeemed'
    returning x."promotion_id" as promotion, x."code_id" as code
  loop
    update "app_private"."promotions" x set "redemptions" = greatest(x."redemptions" - 1, 0) where x."id" = v_row.promotion;
    if v_row.code is not null then
      update "app_private"."promotion_codes" x set "redemptions" = greatest(x."redemptions" - 1, 0) where x."id" = v_row.code;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."release_promotions"(uuid) from public, anon, authenticated;

-- Moves the codes of a cart merged into another, up to what a cart
-- holds. Internal: the orders merge_carts calls it.
create or replace function "app_private"."move_cart_codes"(p_from uuid, p_to uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into "app_private"."cart_promotion_codes" ("tenant_id", "cart_id", "code_id")
  select x."tenant_id", p_to, x."code_id"
  from "app_private"."cart_promotion_codes" x
  where x."cart_id" = p_from
    and not exists (select 1 from "app_private"."cart_promotion_codes" y where y."cart_id" = p_to and y."code_id" = x."code_id")
  order by x."created_at"
  limit greatest(5 - (select count(*) from "app_private"."cart_promotion_codes" y where y."cart_id" = p_to), 0);
  get diagnostics v_count = row_count;
  delete from "app_private"."cart_promotion_codes" x where x."cart_id" = p_from;
  return v_count;
end;
$$;
revoke execute on function "app_private"."move_cart_codes"(uuid, uuid) from public, anon, authenticated;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_85_promotions.sql
-- better-supabase module: promotions
-- @bsb-block-data promotions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('promotions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_85_promotions.sql
-- better-supabase module: promotions
-- @bsb-block promotions@1 managed
-- Percentage, fixed and free-shipping promotions, automatic or by code, with usage limits and stacking rules, priced into orders carts.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
-- Promotions (percentage, fixed or free shipping), automatic or by code,
-- with usage limits and stacking rules; orders prices carts with them.

create table if not exists "better_supabase"."promotions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "description" text check (length("description") <= 2000),
  "kind" text not null check ("kind" in ('percentage', 'fixed', 'free_shipping')),
  "percent" numeric(5, 2) check ("percent" > 0 and "percent" <= 100),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint check ("amount" > 0),
  "min_subtotal" bigint check ("min_subtotal" > 0),
  "scope" text not null default 'order' check ("scope" in ('order', 'products', 'categories', 'collections')),
  "target_ids" uuid[] not null default '{}',
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "usage_limit" integer check ("usage_limit" > 0),
  "per_customer_limit" integer check ("per_customer_limit" > 0),
  "redemptions" integer not null default 0 check ("redemptions" >= 0),
  "stackable" boolean not null default false,
  "priority" integer not null default 0,
  "automatic" boolean not null default false,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("kind" = 'percentage') = ("percent" is not null)),
  check (("kind" = 'fixed') = ("amount" is not null)),
  check (("amount" is null and "min_subtotal" is null) or "currency" is not null),
  check ("ends_at" is null or "starts_at" is null or "ends_at" > "starts_at")
);
create index if not exists promotions_tenant_idx on "better_supabase"."promotions" ("tenant_id", "active", "automatic");
alter table "better_supabase"."promotions" enable row level security;
revoke all on "better_supabase"."promotions" from anon, authenticated;
grant select on "better_supabase"."promotions" to authenticated;
grant all on "better_supabase"."promotions" to service_role;
drop policy if exists promotions_read on "better_supabase"."promotions";
create policy promotions_read on "better_supabase"."promotions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')));

create table if not exists "better_supabase"."promotion_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "promotion_id" uuid not null references "better_supabase"."promotions" ("id") on delete cascade,
  "code" text not null check ("code" ~ '^[A-Z0-9_-]{3,40}$'),
  "usage_limit" integer check ("usage_limit" > 0),
  "redemptions" integer not null default 0 check ("redemptions" >= 0),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
create index if not exists promotion_codes_promotion_idx on "better_supabase"."promotion_codes" ("promotion_id");
alter table "better_supabase"."promotion_codes" enable row level security;
revoke all on "better_supabase"."promotion_codes" from anon, authenticated;
grant select on "better_supabase"."promotion_codes" to authenticated;
grant all on "better_supabase"."promotion_codes" to service_role;
drop policy if exists promotion_codes_read on "better_supabase"."promotion_codes";
create policy promotion_codes_read on "better_supabase"."promotion_codes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')));

create table if not exists "better_supabase"."cart_promotion_codes" (
  "tenant_id" uuid not null,
  "cart_id" uuid not null references "better_supabase"."carts" ("id") on delete cascade,
  "code_id" uuid not null references "better_supabase"."promotion_codes" ("id") on delete cascade,
  "created_at" timestamptz not null default now(),
  primary key ("cart_id", "code_id")
);
create index if not exists cart_promotion_codes_code_idx on "better_supabase"."cart_promotion_codes" ("code_id");
alter table "better_supabase"."cart_promotion_codes" enable row level security;
revoke all on "better_supabase"."cart_promotion_codes" from anon, authenticated;
grant select on "better_supabase"."cart_promotion_codes" to authenticated;
grant all on "better_supabase"."cart_promotion_codes" to service_role;
drop policy if exists cart_promotion_codes_read on "better_supabase"."cart_promotion_codes";
create policy cart_promotion_codes_read on "better_supabase"."cart_promotion_codes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')) or exists (select 1 from "better_supabase"."carts" x where x."id" = "cart_id" and x."user_id" = (select auth.uid())));

create table if not exists "better_supabase"."promotion_redemptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "promotion_id" uuid not null references "better_supabase"."promotions" ("id"),
  "code_id" uuid references "better_supabase"."promotion_codes" ("id") on delete set null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "customer_id" uuid references auth.users (id) on delete set null,
  "email" text,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint not null check ("amount" >= 0),
  "status" text not null default 'redeemed' check ("status" in ('redeemed', 'released')),
  "created_at" timestamptz not null default now(),
  "released_at" timestamptz,
  unique ("order_id", "promotion_id")
);
create index if not exists promotion_redemptions_promotion_idx on "better_supabase"."promotion_redemptions" ("promotion_id", "status");
create index if not exists promotion_redemptions_customer_idx on "better_supabase"."promotion_redemptions" ("customer_id");
create index if not exists promotion_redemptions_code_idx on "better_supabase"."promotion_redemptions" ("code_id");
alter table "better_supabase"."promotion_redemptions" enable row level security;
revoke all on "better_supabase"."promotion_redemptions" from anon, authenticated;
grant select on "better_supabase"."promotion_redemptions" to authenticated;
grant all on "better_supabase"."promotion_redemptions" to service_role;
drop policy if exists promotion_redemptions_read on "better_supabase"."promotion_redemptions";
create policy promotion_redemptions_read on "better_supabase"."promotion_redemptions" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('promotions.read')) or "customer_id" = (select auth.uid()));

-- Creates or updates a promotion. data holds name, description, kind
-- (percentage, fixed or free_shipping), percent, currency, amount and
-- minSubtotal (minor units as text), scope (order, products, categories or
-- collections) with targets, startsAt, endsAt, usageLimit,
-- perCustomerLimit, stackable, priority, automatic and active.
drop function if exists "better_supabase"."save_promotion"(uuid, uuid, jsonb, jsonb);
create or replace function "better_supabase"."save_promotion"(tenant uuid, promotion uuid, data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := save_promotion.tenant;
  v_id uuid := save_promotion.promotion;
  v_kind text := data ->> 'kind';
  v_scope text := coalesce(data ->> 'scope', 'order');
  v_currency text := data ->> 'currency';
  v_percent numeric;
  v_targets uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_id is not null then
    select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = v_id for update;
    if not found or v_tenant is distinct from save_promotion.tenant then
      raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
    end if;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if jsonb_typeof(data) is distinct from 'object' then
    raise exception 'data is an object' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind is null or v_kind not in ('percentage', 'fixed', 'free_shipping') then
    raise exception 'kind is percentage, fixed or free_shipping' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind = 'percentage' then
    if coalesce(data ->> 'percent', '') !~ '^[0-9]{1,3}([.][0-9]{1,2})?$' or (data ->> 'percent')::numeric <= 0 or (data ->> 'percent')::numeric > 100 then
      raise exception 'percent is a number above 0 and at most 100, with up to two decimals' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
    end if;
    v_percent := (data ->> 'percent')::numeric;
  end if;
  if v_kind = 'fixed' and ((case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) is null or (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) <= 0) then
    raise exception 'a fixed promotion has an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if data ? 'minSubtotal' and data ->> 'minSubtotal' is not null and ((case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) is null or (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) <= 0) then
    raise exception 'minSubtotal is an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (v_kind = 'fixed' or data ->> 'minSubtotal' is not null) and (v_currency is null or "better_supabase"."currency_minor_units"(v_currency) is null) then
    raise exception 'an amount needs an ISO 4217 currency' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope not in ('order', 'products', 'categories', 'collections') then
    raise exception 'scope is order, products, categories, collections' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if jsonb_typeof(coalesce(data -> 'targets', '[]'::jsonb)) <> 'array' then
    raise exception 'targets is an array of ids' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  select coalesce(array_agg(distinct e::uuid), '{}') into v_targets
  from jsonb_array_elements_text(coalesce(data -> 'targets', '[]'::jsonb)) e;
  if (v_scope = 'order') <> (cardinality(v_targets) = 0) then
    raise exception 'an order promotion has no targets; the other scopes need at least one' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope <> 'order' and cardinality(v_targets) <> (case v_scope
    when 'products' then (select count(*) from "better_supabase"."products" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'categories' then (select count(*) from "better_supabase"."categories" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'collections' then (select count(*) from "better_supabase"."collections" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    else 0 end) then
    raise exception 'every target is a product, category or collection of this organization' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (data ->> 'startsAt') is not null and (data ->> 'endsAt') is not null
    and (data ->> 'endsAt')::timestamptz <= (data ->> 'startsAt')::timestamptz then
    raise exception 'endsAt is after startsAt' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if coalesce((data ->> 'usageLimit')::integer, 1) < 1 or coalesce((data ->> 'perCustomerLimit')::integer, 1) < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  if v_id is null then
    insert into "better_supabase"."promotions" ("tenant_id", "name", "description", "kind", "percent", "currency", "amount", "min_subtotal", "scope", "target_ids", "starts_at", "ends_at", "usage_limit", "per_customer_limit", "stackable", "priority", "automatic", "active")
    values (v_tenant, data ->> 'name', data ->> 'description', v_kind, v_percent, case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end, case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end, (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end), v_scope, v_targets, (data ->> 'startsAt')::timestamptz, (data ->> 'endsAt')::timestamptz, (data ->> 'usageLimit')::integer, (data ->> 'perCustomerLimit')::integer, coalesce((data ->> 'stackable')::boolean, false), coalesce((data ->> 'priority')::integer, 0), coalesce((data ->> 'automatic')::boolean, false), coalesce((data ->> 'active')::boolean, true))
    returning "id" into v_id;
  else
    update "better_supabase"."promotions" x set
      "name" = data ->> 'name',
      "description" = data ->> 'description',
      "kind" = v_kind,
      "percent" = v_percent,
      "currency" = case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end,
      "amount" = case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end,
      "min_subtotal" = (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end),
      "scope" = v_scope,
      "target_ids" = v_targets,
      "starts_at" = (data ->> 'startsAt')::timestamptz,
      "ends_at" = (data ->> 'endsAt')::timestamptz,
      "usage_limit" = (data ->> 'usageLimit')::integer,
      "per_customer_limit" = (data ->> 'perCustomerLimit')::integer,
      "stackable" = coalesce((data ->> 'stackable')::boolean, false),
      "priority" = coalesce((data ->> 'priority')::integer, 0),
      "automatic" = coalesce((data ->> 'automatic')::boolean, false),
      "active" = coalesce((data ->> 'active')::boolean, true),
      "updated_at" = now()
    where x."id" = v_id;
  end if;
  if coalesce((data ->> 'active')::boolean, true) then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_promotion"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_promotion"(uuid, uuid, jsonb) to authenticated, service_role;

-- before_promotion_activate(promotion) runs after the write, so it reads
-- the promotion as it will be; raising refuses the activation.
create or replace function "better_supabase"."set_promotion_active"(promotion uuid, active boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = set_promotion_active.promotion;
  if not found then
    raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  update "better_supabase"."promotions" x set "active" = set_promotion_active.active, "updated_at" = now()
  where x."id" = set_promotion_active.promotion;
  if set_promotion_active.active then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using set_promotion_active.promotion;
    end if;
  end;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_promotion_active"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."set_promotion_active"(uuid, boolean) to authenticated, service_role;

-- Deletes a promotion nobody redeemed; deactivate one that was.
create or replace function "better_supabase"."delete_promotion"(promotion uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = delete_promotion.promotion;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."promotion_redemptions" x where x."promotion_id" = delete_promotion.promotion) then
    raise exception 'the promotion was redeemed; deactivate it instead' using errcode = '55000', hint = 'PROMOTIONS_IN_USE';
  end if;
  delete from "better_supabase"."promotions" x where x."id" = delete_promotion.promotion;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_promotion"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_promotion"(uuid) to authenticated, service_role;

-- Adds codes to a promotion: the given ones, or count generated ones of
-- the prefix and eight random characters. Codes are stored upper case and
-- are unique per organization.
create or replace function "better_supabase"."create_promotion_codes"(promotion uuid, codes text[] default null,
  count integer default null, prefix text default null, usage_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_code text;
  v_id uuid;
  v_out jsonb := '[]';
  v_prefix text := coalesce(upper(btrim(create_promotion_codes.prefix)), '');
  v_bytes bytea;
  v_attempts integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = create_promotion_codes.promotion;
  if not found then
    raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if (create_promotion_codes.codes is null) = (create_promotion_codes.count is null) then
    raise exception 'pass codes or a count' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.count is not null and (create_promotion_codes.count < 1 or create_promotion_codes.count > 10000) then
    raise exception 'count is from 1 to 10000' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.usage_limit is not null and create_promotion_codes.usage_limit < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_prefix !~ '^[A-Z0-9_-]{0,32}$' then
    raise exception 'a prefix has up to 32 letters, digits, dashes or underscores' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if create_promotion_codes.codes is not null then
    foreach v_code in array create_promotion_codes.codes loop
      v_code := upper(btrim(v_code));
      if v_code is null or v_code !~ '^[A-Z0-9_-]{3,40}$' then
        raise exception 'a code has 3 to 40 letters, digits, dashes or underscores' using errcode = '22023', hint = 'PROMOTIONS_CODE_FORMAT';
      end if;
      begin
        insert into "better_supabase"."promotion_codes" ("tenant_id", "promotion_id", "code", "usage_limit")
        values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
        returning "id" into v_id;
      exception when unique_violation then
        raise exception 'another promotion uses this code' using errcode = '23505', hint = 'PROMOTIONS_CODE_TAKEN';
      end;
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
    end loop;
    return v_out;
  end if;
  while jsonb_array_length(v_out) < create_promotion_codes.count loop
    v_attempts := v_attempts + 1;
    if v_attempts > create_promotion_codes.count * 4 + 10 then
      raise exception 'couldn''t generate enough unique codes; use a longer prefix' using errcode = '55000', hint = 'PROMOTIONS_CODE_SPACE';
    end if;
    v_bytes := extensions.gen_random_bytes(8);
    v_code := v_prefix;
    for i in 0..7 loop
      v_code := v_code || substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    insert into "better_supabase"."promotion_codes" ("tenant_id", "promotion_id", "code", "usage_limit")
    values (v_tenant, create_promotion_codes.promotion, v_code, create_promotion_codes.usage_limit)
    on conflict do nothing
    returning "id" into v_id;
    if v_id is not null then
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', v_id, 'code', v_code));
      v_id := null;
    end if;
  end loop;
  return v_out;
end;
$$;
revoke execute on function "better_supabase"."create_promotion_codes"(uuid, text[], integer, text, integer) from public, anon;
grant execute on function "better_supabase"."create_promotion_codes"(uuid, text[], integer, text, integer) to authenticated, service_role;

-- Deletes a code nobody redeemed.
create or replace function "better_supabase"."delete_promotion_code"(code uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_used integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."redemptions" into v_tenant, v_used from "better_supabase"."promotion_codes" x where x."id" = delete_promotion_code.code;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if v_used > 0 then
    raise exception 'the code was redeemed' using errcode = '55000', hint = 'PROMOTIONS_IN_USE';
  end if;
  delete from "better_supabase"."promotion_codes" x where x."id" = delete_promotion_code.code;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_promotion_code"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_promotion_code"(uuid) to authenticated, service_role;

-- Puts a code on the caller's open cart. Whether it applies (minimum
-- subtotal, products, stacking) shows when the cart is priced.
create or replace function "better_supabase"."apply_promotion_code"(cart uuid, code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_code record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status
  into v_cart from "better_supabase"."carts" x where x."id" = apply_promotion_code.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  select k."id" as id, k."code" as code, k."promotion_id" as promotion,
    k."usage_limit" as code_limit, k."redemptions" as code_used,
    x."usage_limit" as usage_limit, x."redemptions" as used
  into v_code
  from "better_supabase"."promotion_codes" k join "better_supabase"."promotions" x on x."id" = k."promotion_id"
  where k."tenant_id" = v_cart.tenant and k."code" = upper(btrim(apply_promotion_code.code))
    and x."active" and (x."starts_at" is null or x."starts_at" <= now())
    and (x."ends_at" is null or x."ends_at" > now());
  if not found then
    raise exception 'this code is unknown or no longer valid' using errcode = 'P0002', hint = 'PROMOTIONS_CODE_INVALID';
  end if;
  if (v_code.code_limit is not null and v_code.code_used >= v_code.code_limit)
    or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
    raise exception 'this code was used up' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
  end if;
  if (select count(*) from "better_supabase"."cart_promotion_codes" x where x."cart_id" = apply_promotion_code.cart and x."code_id" <> v_code.id) >= 5 then
    raise exception 'a cart holds up to 5 codes' using errcode = '55000', hint = 'PROMOTIONS_TOO_MANY_CODES';
  end if;
  insert into "better_supabase"."cart_promotion_codes" ("tenant_id", "cart_id", "code_id")
  values (v_cart.tenant, apply_promotion_code.cart, v_code.id)
  on conflict do nothing;
  return jsonb_build_object('codeId', v_code.id, 'code', v_code.code, 'promotionId', v_code.promotion);
end;
$$;
revoke execute on function "better_supabase"."apply_promotion_code"(uuid, text) from public, anon;
grant execute on function "better_supabase"."apply_promotion_code"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_promotion_code"(cart uuid, code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."user_id" as owner, x."status" as status
  into v_cart from "better_supabase"."carts" x where x."id" = remove_promotion_code.cart;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  delete from "better_supabase"."cart_promotion_codes" x
  where x."cart_id" = remove_promotion_code.cart
    and x."code_id" in (select k."id" from "better_supabase"."promotion_codes" k where k."code" = upper(btrim(remove_promotion_code.code)));
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_promotion_code"(uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_promotion_code"(uuid, text) to authenticated, service_role;

-- Rounds half to even, like money everywhere else in the commerce blocks.
create or replace function "better_supabase"."round_half_even"(p_value numeric)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value - floor(p_value) > 0.5 then floor(p_value)::bigint + 1
    when p_value - floor(p_value) < 0.5 then floor(p_value)::bigint
    when floor(p_value)::bigint % 2 = 0 then floor(p_value)::bigint
    else floor(p_value)::bigint + 1
  end
$$;
revoke execute on function "better_supabase"."round_half_even"(numeric) from public, anon, authenticated;

-- The cart's discounts: lines maps a line id to its discount, applied
-- lists the promotions in the order they applied, and problems the codes
-- that don't apply. Promotions run by priority (highest first); a
-- promotion that isn't stackable never combines with another. p_lines
-- are the priced lines (id, productId, subtotal as text). Internal: the
-- orders cart_totals calls it.
create or replace function "better_supabase"."cart_discounts"(p_cart uuid, p_lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_promo record;
  v_reason text;
  v_eligible text[];
  v_base bigint;
  v_rem jsonb;
  v_disc jsonb := '{}';
  v_applied jsonb := '[]';
  v_problems jsonb := '[]';
  v_free boolean := false;
  v_stackable boolean := true;
  v_amount bigint;
  v_left bigint;
  v_share bigint;
  v_line_rem bigint;
  v_id text;
begin
  select x."tenant_id" as tenant, x."user_id" as owner, x."currency" as currency, x."email" as email
  into v_cart from "better_supabase"."carts" x where x."id" = p_cart;
  select coalesce(jsonb_object_agg(e ->> 'id', (e ->> 'subtotal')::bigint), '{}') into v_rem
  from jsonb_array_elements(p_lines) e;
  for v_promo in
    select x."id" as id, x."name" as name, x."kind" as kind, x."percent" as percent,
      x."currency" as currency, x."amount" as amount, x."min_subtotal" as min_subtotal,
      x."scope" as scope, x."target_ids" as targets, x."usage_limit" as usage_limit,
      x."per_customer_limit" as per_customer_limit, x."redemptions" as used, x."stackable" as stackable,
      x."automatic" as automatic,
      (x."active" and (x."starts_at" is null or x."starts_at" <= now())
        and (x."ends_at" is null or x."ends_at" > now())) as live,
      code.id as code_id, code.code as code, code.usage_limit as code_limit, code.used as code_used
    from "better_supabase"."promotions" x
    left join lateral (
      select k."id" as id, k."code" as code, k."usage_limit" as usage_limit, k."redemptions" as used
      from "better_supabase"."cart_promotion_codes" y join "better_supabase"."promotion_codes" k on k."id" = y."code_id"
      where y."cart_id" = p_cart and k."promotion_id" = x."id"
      order by y."created_at", k."id"
      limit 1
    ) code on true
    where x."tenant_id" = v_cart.tenant and (code.id is not null or (x."automatic" and x."active"))
    order by x."priority" desc, x."created_at", x."id"
  loop
    v_reason := null;
    if not v_promo.live then
      v_reason := 'expired';
    elsif (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.code_limit is not null and v_promo.code_used >= v_promo.code_limit)
      or (v_promo.per_customer_limit is not null
        and (select count(*) from "better_supabase"."promotion_redemptions" y where y."promotion_id" = v_promo.id and y."status" = 'redeemed'
      and (y."customer_id" = v_cart.owner or (v_cart.email is not null and lower(y."email") = lower(v_cart.email)))) >= v_promo.per_customer_limit) then
      v_reason := 'limit_reached';
    elsif v_promo.currency is not null and v_promo.currency <> v_cart.currency then
      v_reason := 'currency';
    else
      select coalesce(array_agg(e ->> 'id' order by n), '{}'), coalesce(sum((e ->> 'subtotal')::bigint), 0)
      into v_eligible, v_base
      from jsonb_array_elements(p_lines) with ordinality as l(e, n)
      where v_promo.scope = 'order'
      or (v_promo.scope = 'products' and (e ->> 'productId')::uuid = any (v_promo.targets))
      or (v_promo.scope = 'categories' and exists (
      with recursive d (id) as (
        select unnest(v_promo.targets)
        union
        select x."id" from "better_supabase"."categories" x join d on x."parent_id" = d.id
      )
      select 1 from "better_supabase"."product_categories" y where y."product_id" = (e ->> 'productId')::uuid and y."category_id" in (select id from d)
    ))
      or (v_promo.scope = 'collections' and exists (select 1 from "better_supabase"."collection_products" y where y."product_id" = (e ->> 'productId')::uuid and y."collection_id" = any (v_promo.targets)));
      if cardinality(v_eligible) = 0 then
        v_reason := 'not_applicable';
      elsif v_promo.min_subtotal is not null and v_base < v_promo.min_subtotal then
        v_reason := 'min_subtotal';
      elsif jsonb_array_length(v_applied) > 0 and not (v_stackable and v_promo.stackable) then
        v_reason := 'not_combinable';
      end if;
    end if;
    if v_reason is not null then
      if v_promo.code_id is not null then
        v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'promotion_unavailable',
          'promotionId', v_promo.id, 'code', v_promo.code, 'reason', v_reason));
      end if;
      continue;
    end if;
    v_amount := 0;
    if v_promo.kind = 'percentage' then
      foreach v_id in array v_eligible loop
        v_line_rem := (v_rem ->> v_id)::bigint;
        v_share := least("better_supabase"."round_half_even"(v_line_rem * v_promo.percent / 100), v_line_rem);
        v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
        v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
        v_amount := v_amount + v_share;
      end loop;
    elsif v_promo.kind = 'fixed' then
      select coalesce(sum((v_rem ->> e)::bigint), 0) into v_base from unnest(v_eligible) e;
      v_left := least(v_promo.amount, v_base);
      if v_base > 0 then
        foreach v_id in array v_eligible loop
          v_line_rem := (v_rem ->> v_id)::bigint;
          v_share := floor(least(v_promo.amount, v_base)::numeric * v_line_rem / v_base)::bigint;
          v_rem := jsonb_set(v_rem, array[v_id], to_jsonb(v_line_rem - v_share));
          v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + v_share));
          v_left := v_left - v_share;
        end loop;
        foreach v_id in array v_eligible loop
          exit when v_left = 0;
          if (v_rem ->> v_id)::bigint > 0 then
            v_rem := jsonb_set(v_rem, array[v_id], to_jsonb((v_rem ->> v_id)::bigint - 1));
            v_disc := jsonb_set(v_disc, array[v_id], to_jsonb(coalesce((v_disc ->> v_id)::bigint, 0) + 1));
            v_left := v_left - 1;
          end if;
        end loop;
        v_amount := least(v_promo.amount, v_base);
      end if;
    else
      v_free := true;
    end if;
    v_stackable := v_stackable and v_promo.stackable;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('promotionId', v_promo.id, 'name', v_promo.name,
      'kind', v_promo.kind, 'codeId', v_promo.code_id, 'code', v_promo.code, 'amount', v_amount::text));
  end loop;
  select coalesce(jsonb_object_agg(key, value #>> '{}'), '{}') into v_disc from jsonb_each(v_disc);
  return jsonb_build_object('lines', v_disc, 'applied', v_applied, 'freeShipping', v_free, 'problems', v_problems);
end;
$$;
revoke execute on function "better_supabase"."cart_discounts"(uuid, jsonb) from public, anon, authenticated;

-- Records the order's promotions inside checkout. The promotion row lock
-- keeps usage limits under concurrent checkouts; a limit reached since the
-- cart was priced fails the checkout (PROMOTIONS_LIMIT_REACHED).
-- Internal: the orders place_order calls it.
create or replace function "better_supabase"."redeem_promotions"(p_order uuid, p_applied jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_entry jsonb;
  v_promo record;
  v_code record;
  v_id uuid;
  v_count integer := 0;
begin
  select x."id" as id, x."tenant_id" as tenant, x."customer_id" as customer, x."email" as email,
    x."currency" as currency
  into v_order from "better_supabase"."orders" x where x."id" = p_order;
  for v_entry in select e from jsonb_array_elements(coalesce(p_applied, '[]'::jsonb)) e loop
    select x."id" as id, x."usage_limit" as usage_limit, x."per_customer_limit" as per_customer_limit,
      x."redemptions" as used
    into v_promo from "better_supabase"."promotions" x where x."id" = (v_entry ->> 'promotionId')::uuid for update;
    if not found or (v_promo.usage_limit is not null and v_promo.used >= v_promo.usage_limit)
      or (v_promo.per_customer_limit is not null
        and (select count(*) from "better_supabase"."promotion_redemptions" y where y."promotion_id" = v_promo.id and y."status" = 'redeemed'
      and (y."customer_id" = v_order.customer or (v_order.email is not null and lower(y."email") = lower(v_order.email)))) >= v_promo.per_customer_limit) then
      raise exception 'a promotion on this cart reached its usage limit' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
    end if;
    if v_entry ->> 'codeId' is not null then
      select x."usage_limit" as usage_limit, x."redemptions" as used
      into v_code from "better_supabase"."promotion_codes" x where x."id" = (v_entry ->> 'codeId')::uuid for update;
      if not found or (v_code.usage_limit is not null and v_code.used >= v_code.usage_limit) then
        raise exception 'a code on this cart was used up' using errcode = '55000', hint = 'PROMOTIONS_LIMIT_REACHED';
      end if;
      update "better_supabase"."promotion_codes" x set "redemptions" = x."redemptions" + 1 where x."id" = (v_entry ->> 'codeId')::uuid;
    end if;
    update "better_supabase"."promotions" x set "redemptions" = x."redemptions" + 1 where x."id" = v_promo.id;
    insert into "better_supabase"."promotion_redemptions" ("tenant_id", "promotion_id", "code_id", "order_id", "customer_id",
      "email", "currency", "amount")
    values (v_order.tenant, v_promo.id, (v_entry ->> 'codeId')::uuid, v_order.id, v_order.customer, v_order.email,
      v_order.currency, (v_entry ->> 'amount')::bigint)
    returning "id" into v_id;
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."redeem_promotions"(uuid, jsonb) from public, anon, authenticated;

-- Gives a cancelled order's redemptions back to their limits. Internal:
-- the orders cancel_order and expire_orders call it.
create or replace function "better_supabase"."release_promotions"(p_order uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    update "better_supabase"."promotion_redemptions" x set "status" = 'released', "released_at" = now()
    where x."order_id" = p_order and x."status" = 'redeemed'
    returning x."promotion_id" as promotion, x."code_id" as code
  loop
    update "better_supabase"."promotions" x set "redemptions" = greatest(x."redemptions" - 1, 0) where x."id" = v_row.promotion;
    if v_row.code is not null then
      update "better_supabase"."promotion_codes" x set "redemptions" = greatest(x."redemptions" - 1, 0) where x."id" = v_row.code;
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."release_promotions"(uuid) from public, anon, authenticated;

-- Moves the codes of a cart merged into another, up to what a cart
-- holds. Internal: the orders merge_carts calls it.
create or replace function "better_supabase"."move_cart_codes"(p_from uuid, p_to uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into "better_supabase"."cart_promotion_codes" ("tenant_id", "cart_id", "code_id")
  select x."tenant_id", p_to, x."code_id"
  from "better_supabase"."cart_promotion_codes" x
  where x."cart_id" = p_from
    and not exists (select 1 from "better_supabase"."cart_promotion_codes" y where y."cart_id" = p_to and y."code_id" = x."code_id")
  order by x."created_at"
  limit greatest(5 - (select count(*) from "better_supabase"."cart_promotion_codes" y where y."cart_id" = p_to), 0);
  get diagnostics v_count = row_count;
  delete from "better_supabase"."cart_promotion_codes" x where x."cart_id" = p_from;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."move_cart_codes"(uuid, uuid) from public, anon, authenticated;

-- blocks.promotions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."save_promotion"(uuid, uuid, jsonb, jsonb);

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

create or replace function "api"."save_promotion"(tenant uuid, promotion uuid, data jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_promotion"($1, $2, $3) $$;
revoke execute on function "api"."save_promotion"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_promotion"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_promotion_active"(promotion uuid, active boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_promotion_active"($1, $2) $$;
revoke execute on function "api"."set_promotion_active"(uuid, boolean) from public, anon;
grant execute on function "api"."set_promotion_active"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."delete_promotion"(promotion uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_promotion"($1) $$;
revoke execute on function "api"."delete_promotion"(uuid) from public, anon;
grant execute on function "api"."delete_promotion"(uuid) to authenticated, service_role;

create or replace function "api"."create_promotion_codes"(promotion uuid, codes text[] default null, count integer default null, prefix text default null, usage_limit integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_promotion_codes"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."create_promotion_codes"(uuid, text[], integer, text, integer) from public, anon;
grant execute on function "api"."create_promotion_codes"(uuid, text[], integer, text, integer) to authenticated, service_role;

create or replace function "api"."delete_promotion_code"(code uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_promotion_code"($1) $$;
revoke execute on function "api"."delete_promotion_code"(uuid) from public, anon;
grant execute on function "api"."delete_promotion_code"(uuid) to authenticated, service_role;

create or replace function "api"."apply_promotion_code"(cart uuid, code text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."apply_promotion_code"($1, $2) $$;
revoke execute on function "api"."apply_promotion_code"(uuid, text) from public, anon;
grant execute on function "api"."apply_promotion_code"(uuid, text) to authenticated, service_role;

create or replace function "api"."remove_promotion_code"(cart uuid, code text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_promotion_code"($1, $2) $$;
revoke execute on function "api"."remove_promotion_code"(uuid, text) from public, anon;
grant execute on function "api"."remove_promotion_code"(uuid, text) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_85_promotions.sql
-- better-supabase module: promotions
-- @bsb-block-data promotions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('promotions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
