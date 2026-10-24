-- ==== alone: schema supabase/schemas/900_better_supabase_80_ledger.sql
-- better-supabase module: ledger
-- @bsb-block ledger@1 managed
-- Double-entry accounts in a currency or a custom unit, balanced transactions, balances and holds. Credits, stock, leave balances and invoice payments post through it.
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
create table if not exists "better_supabase"."ledger_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "code" text not null check (length("code") between 1 and 200),
  "name" text not null check (length("name") between 1 and 200),
  -- An ISO 4217 code for money, or a custom unit such as item, days or points.
  "unit" text not null check ("unit" ~ '^([A-Z]{3}|[a-z][a-z0-9_]{0,31})$'),
  -- Decimal places of a custom unit: amounts are integers, 150 at scale 2 is 1.5.
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "holder_type" text,
  "holder_id" text,
  -- The member the account belongs to, who can read it without a permission.
  "owner_id" uuid,
  "allow_negative" boolean not null default false,
  -- A permission key that also grants reading the account.
  "read_permission" text,
  -- The module that posts to the account; post_ledger_transaction refuses it.
  "managed_by" text,
  "metadata" jsonb not null default '{}'::jsonb,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  check (("holder_type" is null) = ("holder_id" is null))
);
create index if not exists "ledger_accounts_holder_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "holder_type", "holder_id") where "holder_type" is not null;
create index if not exists "ledger_accounts_kind_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "kind");
create index if not exists "ledger_accounts_owner_idx" on "better_supabase"."ledger_accounts" ("owner_id") where "owner_id" is not null;

create table if not exists "better_supabase"."ledger_transactions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$'),
  "reference_type" text,
  "reference_id" text,
  "memo" text check ("memo" is null or length("memo") <= 2000),
  "idempotency_key" text,
  "reverses" uuid references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "metadata" jsonb not null default '{}'::jsonb,
  "effective_at" timestamptz not null default now(),
  "actor_id" uuid,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "ledger_transactions_key_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "idempotency_key") where "idempotency_key" is not null;
create unique index if not exists "ledger_transactions_reverses_idx" on "better_supabase"."ledger_transactions" ("reverses") where "reverses" is not null;
create index if not exists "ledger_transactions_reference_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "reference_type", "reference_id") where "reference_type" is not null;
create index if not exists "ledger_transactions_tenant_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "effective_at" desc);

create table if not exists "better_supabase"."ledger_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "transaction_id" uuid not null references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "account_id" uuid not null references "better_supabase"."ledger_accounts" ("id") on delete restrict,
  -- Signed, in the account's unit: the entries of a transaction sum to zero per unit.
  "amount" bigint not null check ("amount" <> 0),
  "unit" text not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "ledger_entries_account_idx" on "better_supabase"."ledger_entries" ("account_id", "created_at" desc);
create index if not exists "ledger_entries_transaction_idx" on "better_supabase"."ledger_entries" ("transaction_id");

create table if not exists "better_supabase"."ledger_balances" (
  "account_id" uuid primary key references "better_supabase"."ledger_accounts" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "balance" bigint not null default 0,
  -- The sum of the account's active holds.
  "held" bigint not null default 0 check ("held" >= 0),
  "available" bigint generated always as ("balance" - "held") stored,
  "updated_at" timestamptz not null default now()
);
create index if not exists "ledger_balances_tenant_idx" on "better_supabase"."ledger_balances" ("tenant_id");

create table if not exists "better_supabase"."ledger_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."ledger_accounts" ("id") on delete restrict,
  "amount" bigint not null check ("amount" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'captured', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz,
  "transaction_id" uuid references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "ledger_holds_account_idx" on "better_supabase"."ledger_holds" ("account_id", "status");
create index if not exists "ledger_holds_transaction_idx" on "better_supabase"."ledger_holds" ("transaction_id") where "transaction_id" is not null;
create index if not exists "ledger_holds_expiry_idx" on "better_supabase"."ledger_holds" ("expires_at") where "status" = 'active' and "expires_at" is not null;

alter table "better_supabase"."ledger_accounts" enable row level security;
revoke all on "better_supabase"."ledger_accounts" from anon, authenticated;
grant select on "better_supabase"."ledger_accounts" to authenticated;
grant all on "better_supabase"."ledger_accounts" to service_role;
create index if not exists "ledger_accounts_read_permission_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "read_permission") where "read_permission" is not null;
-- The (tenant, permission) pairs of account read permissions the caller
-- holds, so the policy checks each pair once per statement, not per row.
create or replace function "better_supabase"."ledger_read_grants"()
returns table (tenant uuid, permission text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select p.tenant, p.permission from (
    select distinct x."tenant_id" as tenant, x."read_permission" as permission
    from "better_supabase"."ledger_accounts" x
    where x."read_permission" is not null and x."tenant_id" in (select better_supabase.member_organization_ids())
  ) p
  where coalesce(better_supabase.can('tenant', p.tenant, p.permission), false);
end;
$$;
revoke execute on function "better_supabase"."ledger_read_grants"() from public, anon;
grant execute on function "better_supabase"."ledger_read_grants"() to authenticated, service_role;
drop policy if exists "ledger_accounts_read" on "better_supabase"."ledger_accounts";
create policy "ledger_accounts_read" on "better_supabase"."ledger_accounts" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or "owner_id" = (select auth.uid())
    or ("tenant_id", "read_permission") in (select g.tenant, g.permission from "better_supabase"."ledger_read_grants"() g));
alter table "better_supabase"."ledger_transactions" enable row level security;
revoke all on "better_supabase"."ledger_transactions" from anon, authenticated;
grant select on "better_supabase"."ledger_transactions" to authenticated;
grant all on "better_supabase"."ledger_transactions" to service_role;
drop policy if exists "ledger_transactions_read" on "better_supabase"."ledger_transactions";
create policy "ledger_transactions_read" on "better_supabase"."ledger_transactions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = "id"));
alter table "better_supabase"."ledger_entries" enable row level security;
revoke all on "better_supabase"."ledger_entries" from anon, authenticated;
grant select on "better_supabase"."ledger_entries" to authenticated;
grant all on "better_supabase"."ledger_entries" to service_role;
drop policy if exists "ledger_entries_read" on "better_supabase"."ledger_entries";
create policy "ledger_entries_read" on "better_supabase"."ledger_entries" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));
alter table "better_supabase"."ledger_balances" enable row level security;
revoke all on "better_supabase"."ledger_balances" from anon, authenticated;
grant select on "better_supabase"."ledger_balances" to authenticated;
grant all on "better_supabase"."ledger_balances" to service_role;
drop policy if exists "ledger_balances_read" on "better_supabase"."ledger_balances";
create policy "ledger_balances_read" on "better_supabase"."ledger_balances" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));
alter table "better_supabase"."ledger_holds" enable row level security;
revoke all on "better_supabase"."ledger_holds" from anon, authenticated;
grant select on "better_supabase"."ledger_holds" to authenticated;
grant all on "better_supabase"."ledger_holds" to service_role;
drop policy if exists "ledger_holds_read" on "better_supabase"."ledger_holds";
create policy "ledger_holds_read" on "better_supabase"."ledger_holds" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));

-- Entries and transactions are append-only: a reversal posts the opposite.
create or replace function "better_supabase"."ledger_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'ledger entries and transactions can''t be changed or deleted; post a reversal' using errcode = '55000', hint = 'LEDGER_APPEND_ONLY';
end;
$$;
revoke execute on function "better_supabase"."ledger_append_only"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_append_only" on "better_supabase"."ledger_entries";
create trigger "bsb_ledger_entries_append_only" before update or delete on "better_supabase"."ledger_entries"
  for each row execute function "better_supabase"."ledger_append_only"();
drop trigger if exists "bsb_ledger_transactions_append_only" on "better_supabase"."ledger_transactions";
create trigger "bsb_ledger_transactions_append_only" before update or delete on "better_supabase"."ledger_transactions"
  for each row execute function "better_supabase"."ledger_append_only"();

-- Keeps the account's balance and refuses to take an account that doesn't
-- allow it below zero (counting its holds).
create or replace function "better_supabase"."ledger_apply_entry"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available bigint;
begin
  insert into "better_supabase"."ledger_balances" as x ("account_id", "tenant_id", "balance")
  values (new."account_id", new."tenant_id", new."amount")
  on conflict ("account_id") do update set "balance" = x."balance" + excluded."balance", "updated_at" = now()
  returning x."balance" - x."held" into v_available;
  if new."amount" < 0 and v_available < 0 and not exists (
    select 1 from "better_supabase"."ledger_accounts" y where y."id" = new."account_id" and y."allow_negative"
  ) then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ledger_apply_entry"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_apply" on "better_supabase"."ledger_entries";
create trigger "bsb_ledger_entries_apply" after insert on "better_supabase"."ledger_entries"
  for each row execute function "better_supabase"."ledger_apply_entry"();

-- At commit, the entries of each transaction sum to zero per unit.
create or replace function "better_supabase"."ledger_check_balanced"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = new."transaction_id"
    group by y."unit" having sum(y."amount") <> 0
  ) then
    raise exception 'the entries of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ledger_check_balanced"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_balanced" on "better_supabase"."ledger_entries";
create constraint trigger "bsb_ledger_entries_balanced" after insert on "better_supabase"."ledger_entries"
  deferrable initially deferred
  for each row execute function "better_supabase"."ledger_check_balanced"();

-- The account with code, opened with the rest when it doesn't exist yet.
-- Modules that post to the ledger call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_account_for"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, managed_by text default null, metadata jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."ledger_accounts" x
    where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  if found then
    return v_id;
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "managed_by", "metadata")
  values (ledger_account_for.tenant, ledger_account_for.kind, ledger_account_for.code, ledger_account_for.name, ledger_account_for.unit,
    coalesce(ledger_account_for.scale, 0), ledger_account_for.holder_type, ledger_account_for.holder_id, ledger_account_for.owner_id,
    coalesce(ledger_account_for.allow_negative, false), ledger_account_for.read_permission, ledger_account_for.managed_by,
    coalesce(ledger_account_for.metadata, '{}'::jsonb))
  on conflict ("tenant_id", "code") do nothing
  returning "id" into v_id;
  if v_id is null then
    select x."id" into v_id from "better_supabase"."ledger_accounts" x
      where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ledger_account_for"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, text, jsonb) from public, anon, authenticated;

-- Posts a balanced transaction: lines is an array of {account, amount} with
-- signed integer amounts in each account's unit, summing to zero per unit.
-- With idempotency_key a second call returns the first transaction. Modules
-- that post to the ledger call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_post"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null, reverses uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if ledger_post.idempotency_key is not null then
    select x."id" into v_id from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = ledger_post.tenant and x."idempotency_key" = ledger_post.idempotency_key;
    if found then
      return v_id;
    end if;
  end if;
  if ledger_post.kind is null or ledger_post.kind !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$' then
    raise exception 'kind must be lowercase words joined by dots, such as credit.grant' using errcode = '22023', hint = 'LEDGER_KIND_INVALID';
  end if;
  if jsonb_typeof(ledger_post.lines) is distinct from 'array' or jsonb_array_length(ledger_post.lines) < 2 then
    raise exception 'a transaction needs at least two lines' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    where jsonb_typeof(l.value) is distinct from 'object'
      or coalesce(l.value ->> 'account', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(l.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
      or (l.value ->> 'amount')::bigint = 0
  ) then
    raise exception 'every line needs an account id and a non-zero integer amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    left join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
      and x."tenant_id" = ledger_post.tenant and x."closed_at" is null
    where x."id" is null
  ) then
    raise exception 'an account of the transaction doesn''t exist here or is closed' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
    group by x."unit" having sum((l.value ->> 'amount')::bigint) <> 0
  ) then
    raise exception 'the lines of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_ledger_transaction_post"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using ledger_post.tenant, ledger_post.kind, ledger_post.lines;
    end if;
  end;
  insert into "better_supabase"."ledger_transactions" ("tenant_id", "kind", "reference_type", "reference_id", "memo", "idempotency_key", "reverses", "metadata", "effective_at", "actor_id")
  values (ledger_post.tenant, ledger_post.kind, ledger_post.reference_type, ledger_post.reference_id, nullif(trim(ledger_post.memo), ''),
    ledger_post.idempotency_key, ledger_post.reverses, coalesce(ledger_post.metadata, '{}'::jsonb), coalesce(ledger_post.effective_at, now()), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."ledger_entries" ("tenant_id", "transaction_id", "account_id", "amount", "unit")
  select ledger_post.tenant, v_row."id", x."id", (l.value ->> 'amount')::bigint, x."unit"
  from jsonb_array_elements(ledger_post.lines) with ordinality as l(value, n)
  join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
  order by l.n;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_ledger_transaction_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."ledger_post"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb, uuid) from public, anon, authenticated;

-- Opens an account for the app's own use (credits, loyalty points, gift
-- cards, trust balances). code is unique per organization.
create or replace function "better_supabase"."open_ledger_account"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_ledger_account.tenant, 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."tenant_id" = open_ledger_account.tenant and x."code" = open_ledger_account.code) then
    raise exception 'an account with this code already exists' using errcode = '23505', hint = 'LEDGER_ACCOUNT_CODE_TAKEN';
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "metadata")
  values (open_ledger_account.tenant, open_ledger_account.kind, open_ledger_account.code, open_ledger_account.name, open_ledger_account.unit,
    coalesce(open_ledger_account.scale, 0), open_ledger_account.holder_type, open_ledger_account.holder_id, open_ledger_account.owner_id,
    coalesce(open_ledger_account.allow_negative, false), open_ledger_account.read_permission, coalesce(open_ledger_account.metadata, '{}'::jsonb))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$$;
revoke execute on function "better_supabase"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) from public, anon;
grant execute on function "better_supabase"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) to authenticated, service_role;

-- Closes an account with a zero balance and no active holds.
create or replace function "better_supabase"."close_ledger_account"(account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ledger_accounts" x where x."id" = close_ledger_account.account_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or v_row."owner_id" = auth.uid() or (v_row."read_permission" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", v_row."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_row."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_row."id" for update;
  if coalesce(v_balance."balance", 0) <> 0 or coalesce(v_balance."held", 0) <> 0 then
    raise exception 'only an account with a zero balance and no holds can be closed' using errcode = '55000', hint = 'LEDGER_ACCOUNT_NOT_EMPTY';
  end if;
  if v_row."closed_at" is null then
    update "better_supabase"."ledger_accounts" x set "closed_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$$;
revoke execute on function "better_supabase"."close_ledger_account"(uuid) from public, anon;
grant execute on function "better_supabase"."close_ledger_account"(uuid) to authenticated, service_role;

-- Posts a balanced transaction to the app's own accounts. Accounts a block
-- manages (stock, leave, receivables) only move through that block.
create or replace function "better_supabase"."post_ledger_transaction"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_ledger_transaction.tenant, 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if jsonb_typeof(post_ledger_transaction.lines) = 'array' and exists (
    select 1 from jsonb_array_elements(post_ledger_transaction.lines) l
    join "better_supabase"."ledger_accounts" x on x."id"::text = l.value ->> 'account'
    where x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_id := "better_supabase"."ledger_post"(post_ledger_transaction.tenant, post_ledger_transaction.kind, post_ledger_transaction.lines,
    post_ledger_transaction.reference_type, post_ledger_transaction.reference_id, post_ledger_transaction.memo,
    post_ledger_transaction.idempotency_key, post_ledger_transaction.effective_at, post_ledger_transaction.metadata);
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) from public, anon;
grant execute on function "better_supabase"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) to authenticated, service_role;

-- Posts the opposite of a transaction. A transaction is reversed at most
-- once, and a reversal can't be reversed.
create or replace function "better_supabase"."reverse_ledger_transaction"(transaction_id uuid, memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "better_supabase"."ledger_transactions"%rowtype;
  v_row "better_supabase"."ledger_transactions"%rowtype;
  v_id uuid;
begin
  select * into v_old from "better_supabase"."ledger_transactions" x where x."id" = reverse_ledger_transaction.transaction_id;
  if not found then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_old."id" and x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  if v_old."reverses" is not null
    or exists (select 1 from "better_supabase"."ledger_transactions" x where x."reverses" = v_old."id") then
    raise exception 'this transaction is a reversal or is already reversed' using errcode = '55000', hint = 'LEDGER_ALREADY_REVERSED';
  end if;
  v_id := "better_supabase"."ledger_post"(v_old."tenant_id", v_old."kind",
    (select jsonb_agg(jsonb_build_object('account', y."account_id", 'amount', (-y."amount")::text) order by y."created_at", y."id")
      from "better_supabase"."ledger_entries" y where y."transaction_id" = v_old."id"),
    v_old."reference_type", v_old."reference_id", coalesce(reverse_ledger_transaction.memo, v_old."memo"),
    null, null, v_old."metadata", v_old."id");
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."reverse_ledger_transaction"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reverse_ledger_transaction"(uuid, text) to authenticated, service_role;

-- Sets aside part of an account's available balance until it is captured,
-- released or expires, without checking the caller. Modules that hold
-- amounts on their own accounts call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if ledger_hold.amount is null or ledger_hold.amount <= 0 then
    raise exception 'a hold needs an amount greater than zero' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  insert into "better_supabase"."ledger_balances" ("account_id", "tenant_id") values (v_account."id", v_account."tenant_id")
    on conflict ("account_id") do nothing;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_account."id" for update;
  if not v_account."allow_negative" and v_balance."balance" - v_balance."held" < ledger_hold.amount then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  update "better_supabase"."ledger_balances" x set "held" = x."held" + ledger_hold.amount, "updated_at" = now()
    where x."account_id" = v_account."id";
  insert into "better_supabase"."ledger_holds" ("tenant_id", "account_id", "amount", "reference_type", "reference_id", "expires_at", "created_by")
  values (v_account."tenant_id", v_account."id", ledger_hold.amount, ledger_hold.reference_type, ledger_hold.reference_id, ledger_hold.expires_at, auth.uid())
  returning * into v_row;
  null;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon, authenticated;

create or replace function "better_supabase"."place_ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = place_ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_account."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "better_supabase"."ledger_hold"(place_ledger_hold.account_id, place_ledger_hold.amount, place_ledger_hold.reference_type, place_ledger_hold.reference_id, place_ledger_hold.expires_at);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) to authenticated, service_role;

-- Frees an active hold: release by a caller, expire from expire_ledger_holds.
create or replace function "better_supabase"."ledger_unhold"(hold_id uuid, status text)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = ledger_unhold.hold_id for update;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'this hold is no longer active' using errcode = '55000', hint = 'LEDGER_HOLD_CLOSED';
  end if;
  update "better_supabase"."ledger_balances" x set "held" = x."held" - v_row."amount", "updated_at" = now()
    where x."account_id" = v_row."account_id";
  update "better_supabase"."ledger_holds" x set "status" = ledger_unhold.status, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_unhold"(uuid, text) from public, anon, authenticated;

-- Captures a hold without checking the caller: frees it and posts amount
-- (default all of it) from the held account to to_account. Modules call it;
-- it isn't granted to anyone.
create or replace function "better_supabase"."ledger_capture"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
  v_amount bigint;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = ledger_capture.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  v_amount := coalesce(ledger_capture.amount, v_row."amount");
  if v_amount <= 0 or v_amount > v_row."amount" then
    raise exception 'a capture takes more than zero and at most the held amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  v_row := "better_supabase"."ledger_unhold"(v_row."id", 'captured');
  update "better_supabase"."ledger_holds" x set "transaction_id" = "better_supabase"."ledger_post"(v_row."tenant_id", coalesce(ledger_capture.kind, 'ledger.capture'),
      jsonb_build_array(
        jsonb_build_object('account', v_row."account_id", 'amount', (-v_amount)::text),
        jsonb_build_object('account', ledger_capture.to_account, 'amount', v_amount::text)),
      v_row."reference_type", v_row."reference_id", ledger_capture.memo)
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_capture"(uuid, uuid, bigint, text, text) from public, anon, authenticated;

create or replace function "better_supabase"."capture_ledger_hold"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = capture_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."id" = capture_ledger_hold.to_account and x."managed_by" is not null) and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "better_supabase"."ledger_capture"(v_row."id", capture_ledger_hold.to_account, capture_ledger_hold.amount, capture_ledger_hold.kind, capture_ledger_hold.memo);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."capture_ledger_hold"(uuid, uuid, bigint, text, text) from public, anon;
grant execute on function "better_supabase"."capture_ledger_hold"(uuid, uuid, bigint, text, text) to authenticated, service_role;

-- Releases an active hold without checking the caller. Modules call it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."ledger_release"(hold_id uuid)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  v_row := "better_supabase"."ledger_unhold"(ledger_release.hold_id, 'released');
  null;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_release"(uuid) from public, anon, authenticated;

create or replace function "better_supabase"."release_ledger_hold"(hold_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = release_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  v_row := "better_supabase"."ledger_release"(v_row."id");
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."release_ledger_hold"(uuid) from public, anon;
grant execute on function "better_supabase"."release_ledger_hold"(uuid) to authenticated, service_role;

-- Releases the active holds past expires_at; a scheduled job runs it.
-- Returns how many it expired.
create or replace function "better_supabase"."expire_ledger_holds"(max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_holds"%rowtype;
  v_count integer := 0;
begin
  for v_id in
    select x."id" from "better_supabase"."ledger_holds" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit least(greatest(coalesce(expire_ledger_holds.max_rows, 500), 1), 5000)
    for update skip locked
  loop
    v_row := "better_supabase"."ledger_unhold"(v_id, 'expired');
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_ledger_holds"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_ledger_holds"(integer) to service_role;

-- The accounts the caller can read, with their balances: every account with
-- the read permission, else the caller's own and those a read permission of
-- another block grants. Without a tenant it lists a holder's accounts in
-- every tenant the caller can read them in.
create or replace function "better_supabase"."list_ledger_accounts"(tenant uuid, kind text default null, holder_type text default null, holder_id text default null, page_size integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.code), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'code', x."code", 'name', x."name", 'unit', x."unit", 'scale', x."scale", 'holderType', x."holder_type", 'holderId', x."holder_id", 'ownerId', x."owner_id", 'allowNegative', x."allow_negative", 'readPermission', x."read_permission", 'managedBy', x."managed_by", 'metadata', x."metadata", 'closedAt', x."closed_at", 'createdAt', x."created_at", 'balance', coalesce(y."balance", 0)::text, 'held', coalesce(y."held", 0)::text, 'available', coalesce(y."balance" - y."held", 0)::text) as item, x."code" as code
    from "better_supabase"."ledger_accounts" x
    left join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
    where (list_ledger_accounts.tenant is null or x."tenant_id" = list_ledger_accounts.tenant)
      and (list_ledger_accounts.kind is null or x."kind" = list_ledger_accounts.kind)
      and (list_ledger_accounts.holder_type is null or x."holder_type" = list_ledger_accounts.holder_type)
      and (list_ledger_accounts.holder_id is null or x."holder_id" = list_ledger_accounts.holder_id)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
    order by x."code"
    limit least(greatest(coalesce(list_ledger_accounts.page_size, 100), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_ledger_accounts"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_ledger_accounts"(uuid, text, text, text, integer) to authenticated, service_role;

-- An account's entries, newest first, with the transaction each belongs to.
-- before pages back from an entry's created_at.
create or replace function "better_supabase"."ledger_account_entries"(account_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_rows jsonb;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = ledger_account_entries.account_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.read'), false) or v_account."owner_id" = auth.uid() or (v_account."read_permission" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", v_account."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit",
        'transactionId', r."id", 'kind', r."kind", 'referenceType', r."reference_type", 'referenceId', r."reference_id",
        'memo', r."memo", 'reverses', r."reverses", 'metadata', r."metadata", 'effectiveAt', r."effective_at", 'createdAt', y."created_at") as item,
      y."created_at" as created, y."id" as id
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where y."account_id" = v_account."id"
      and (ledger_account_entries.before is null or y."created_at" < ledger_account_entries.before)
    order by y."created_at" desc, y."id" desc
    limit least(greatest(coalesce(ledger_account_entries.page_size, 50), 1), 500)
  ) z;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."ledger_account_entries"(uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."ledger_account_entries"(uuid, timestamptz, integer) to authenticated, service_role;

-- One transaction with its entries, for a caller who can read one of its
-- accounts.
create or replace function "better_supabase"."get_ledger_transaction"(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = get_ledger_transaction.transaction_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_row."id" and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
  )) then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_ledger_transaction"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ledger_transaction"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_accounts";
create policy bsb_tenant_scope on "better_supabase"."ledger_accounts" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or "owner_id" = (select auth.uid())
    or ("tenant_id", "read_permission") in (select g.tenant, g.permission from "better_supabase"."ledger_read_grants"() g))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_transactions";
create policy bsb_tenant_scope on "better_supabase"."ledger_transactions" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = "id"))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_entries";
create policy bsb_tenant_scope on "better_supabase"."ledger_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_balances";
create policy bsb_tenant_scope on "better_supabase"."ledger_balances" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_holds";
create policy bsb_tenant_scope on "better_supabase"."ledger_holds" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_80_ledger.sql
-- better-supabase module: ledger
-- @bsb-block-data ledger
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ledger', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_80_ledger.sql
-- better-supabase module: ledger
-- @bsb-block ledger@1 managed
-- Double-entry accounts in a currency or a custom unit, balanced transactions, balances and holds. Credits, stock, leave balances and invoice payments post through it.
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
create table if not exists "better_supabase"."ledger_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "code" text not null check (length("code") between 1 and 200),
  "name" text not null check (length("name") between 1 and 200),
  -- An ISO 4217 code for money, or a custom unit such as item, days or points.
  "unit" text not null check ("unit" ~ '^([A-Z]{3}|[a-z][a-z0-9_]{0,31})$'),
  -- Decimal places of a custom unit: amounts are integers, 150 at scale 2 is 1.5.
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "holder_type" text,
  "holder_id" text,
  -- The member the account belongs to, who can read it without a permission.
  "owner_id" uuid,
  "allow_negative" boolean not null default false,
  -- A permission key that also grants reading the account.
  "read_permission" text,
  -- The module that posts to the account; post_ledger_transaction refuses it.
  "managed_by" text,
  "metadata" jsonb not null default '{}'::jsonb,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  check (("holder_type" is null) = ("holder_id" is null))
);
create index if not exists "ledger_accounts_holder_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "holder_type", "holder_id") where "holder_type" is not null;
create index if not exists "ledger_accounts_kind_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "kind");
create index if not exists "ledger_accounts_owner_idx" on "better_supabase"."ledger_accounts" ("owner_id") where "owner_id" is not null;

create table if not exists "better_supabase"."ledger_transactions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$'),
  "reference_type" text,
  "reference_id" text,
  "memo" text check ("memo" is null or length("memo") <= 2000),
  "idempotency_key" text,
  "reverses" uuid references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "metadata" jsonb not null default '{}'::jsonb,
  "effective_at" timestamptz not null default now(),
  "actor_id" uuid,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "ledger_transactions_key_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "idempotency_key") where "idempotency_key" is not null;
create unique index if not exists "ledger_transactions_reverses_idx" on "better_supabase"."ledger_transactions" ("reverses") where "reverses" is not null;
create index if not exists "ledger_transactions_reference_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "reference_type", "reference_id") where "reference_type" is not null;
create index if not exists "ledger_transactions_tenant_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "effective_at" desc);

create table if not exists "better_supabase"."ledger_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "transaction_id" uuid not null references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "account_id" uuid not null references "better_supabase"."ledger_accounts" ("id") on delete restrict,
  -- Signed, in the account's unit: the entries of a transaction sum to zero per unit.
  "amount" bigint not null check ("amount" <> 0),
  "unit" text not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "ledger_entries_account_idx" on "better_supabase"."ledger_entries" ("account_id", "created_at" desc);
create index if not exists "ledger_entries_transaction_idx" on "better_supabase"."ledger_entries" ("transaction_id");

create table if not exists "better_supabase"."ledger_balances" (
  "account_id" uuid primary key references "better_supabase"."ledger_accounts" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "balance" bigint not null default 0,
  -- The sum of the account's active holds.
  "held" bigint not null default 0 check ("held" >= 0),
  "available" bigint generated always as ("balance" - "held") stored,
  "updated_at" timestamptz not null default now()
);
create index if not exists "ledger_balances_tenant_idx" on "better_supabase"."ledger_balances" ("tenant_id");

create table if not exists "better_supabase"."ledger_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."ledger_accounts" ("id") on delete restrict,
  "amount" bigint not null check ("amount" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'captured', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz,
  "transaction_id" uuid references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "ledger_holds_account_idx" on "better_supabase"."ledger_holds" ("account_id", "status");
create index if not exists "ledger_holds_transaction_idx" on "better_supabase"."ledger_holds" ("transaction_id") where "transaction_id" is not null;
create index if not exists "ledger_holds_expiry_idx" on "better_supabase"."ledger_holds" ("expires_at") where "status" = 'active' and "expires_at" is not null;

alter table "better_supabase"."ledger_accounts" enable row level security;
revoke all on "better_supabase"."ledger_accounts" from anon, authenticated;
grant select on "better_supabase"."ledger_accounts" to authenticated;
grant all on "better_supabase"."ledger_accounts" to service_role;
create index if not exists "ledger_accounts_read_permission_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "read_permission") where "read_permission" is not null;
-- The (tenant, permission) pairs of account read permissions the caller
-- holds, so the policy checks each pair once per statement, not per row.
create or replace function "better_supabase"."ledger_read_grants"()
returns table (tenant uuid, permission text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select p.tenant, p.permission from (
    select distinct x."tenant_id" as tenant, x."read_permission" as permission
    from "better_supabase"."ledger_accounts" x
    where x."read_permission" is not null and x."tenant_id" in (select better_supabase.member_organization_ids())
  ) p
  where coalesce(better_supabase.can('tenant', p.tenant, p.permission), false);
end;
$$;
revoke execute on function "better_supabase"."ledger_read_grants"() from public, anon;
grant execute on function "better_supabase"."ledger_read_grants"() to authenticated, service_role;
drop policy if exists "ledger_accounts_read" on "better_supabase"."ledger_accounts";
create policy "ledger_accounts_read" on "better_supabase"."ledger_accounts" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or "owner_id" = (select auth.uid())
    or ("tenant_id", "read_permission") in (select g.tenant, g.permission from "better_supabase"."ledger_read_grants"() g));
alter table "better_supabase"."ledger_transactions" enable row level security;
revoke all on "better_supabase"."ledger_transactions" from anon, authenticated;
grant select on "better_supabase"."ledger_transactions" to authenticated;
grant all on "better_supabase"."ledger_transactions" to service_role;
drop policy if exists "ledger_transactions_read" on "better_supabase"."ledger_transactions";
create policy "ledger_transactions_read" on "better_supabase"."ledger_transactions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = "id"));
alter table "better_supabase"."ledger_entries" enable row level security;
revoke all on "better_supabase"."ledger_entries" from anon, authenticated;
grant select on "better_supabase"."ledger_entries" to authenticated;
grant all on "better_supabase"."ledger_entries" to service_role;
drop policy if exists "ledger_entries_read" on "better_supabase"."ledger_entries";
create policy "ledger_entries_read" on "better_supabase"."ledger_entries" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));
alter table "better_supabase"."ledger_balances" enable row level security;
revoke all on "better_supabase"."ledger_balances" from anon, authenticated;
grant select on "better_supabase"."ledger_balances" to authenticated;
grant all on "better_supabase"."ledger_balances" to service_role;
drop policy if exists "ledger_balances_read" on "better_supabase"."ledger_balances";
create policy "ledger_balances_read" on "better_supabase"."ledger_balances" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));
alter table "better_supabase"."ledger_holds" enable row level security;
revoke all on "better_supabase"."ledger_holds" from anon, authenticated;
grant select on "better_supabase"."ledger_holds" to authenticated;
grant all on "better_supabase"."ledger_holds" to service_role;
drop policy if exists "ledger_holds_read" on "better_supabase"."ledger_holds";
create policy "ledger_holds_read" on "better_supabase"."ledger_holds" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));

-- Entries and transactions are append-only: a reversal posts the opposite.
create or replace function "better_supabase"."ledger_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'ledger entries and transactions can''t be changed or deleted; post a reversal' using errcode = '55000', hint = 'LEDGER_APPEND_ONLY';
end;
$$;
revoke execute on function "better_supabase"."ledger_append_only"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_append_only" on "better_supabase"."ledger_entries";
create trigger "bsb_ledger_entries_append_only" before update or delete on "better_supabase"."ledger_entries"
  for each row execute function "better_supabase"."ledger_append_only"();
drop trigger if exists "bsb_ledger_transactions_append_only" on "better_supabase"."ledger_transactions";
create trigger "bsb_ledger_transactions_append_only" before update or delete on "better_supabase"."ledger_transactions"
  for each row execute function "better_supabase"."ledger_append_only"();

-- Keeps the account's balance and refuses to take an account that doesn't
-- allow it below zero (counting its holds).
create or replace function "better_supabase"."ledger_apply_entry"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available bigint;
begin
  insert into "better_supabase"."ledger_balances" as x ("account_id", "tenant_id", "balance")
  values (new."account_id", new."tenant_id", new."amount")
  on conflict ("account_id") do update set "balance" = x."balance" + excluded."balance", "updated_at" = now()
  returning x."balance" - x."held" into v_available;
  if new."amount" < 0 and v_available < 0 and not exists (
    select 1 from "better_supabase"."ledger_accounts" y where y."id" = new."account_id" and y."allow_negative"
  ) then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ledger_apply_entry"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_apply" on "better_supabase"."ledger_entries";
create trigger "bsb_ledger_entries_apply" after insert on "better_supabase"."ledger_entries"
  for each row execute function "better_supabase"."ledger_apply_entry"();

-- At commit, the entries of each transaction sum to zero per unit.
create or replace function "better_supabase"."ledger_check_balanced"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = new."transaction_id"
    group by y."unit" having sum(y."amount") <> 0
  ) then
    raise exception 'the entries of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ledger_check_balanced"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_balanced" on "better_supabase"."ledger_entries";
create constraint trigger "bsb_ledger_entries_balanced" after insert on "better_supabase"."ledger_entries"
  deferrable initially deferred
  for each row execute function "better_supabase"."ledger_check_balanced"();

-- The account with code, opened with the rest when it doesn't exist yet.
-- Modules that post to the ledger call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_account_for"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, managed_by text default null, metadata jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."ledger_accounts" x
    where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  if found then
    return v_id;
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "managed_by", "metadata")
  values (ledger_account_for.tenant, ledger_account_for.kind, ledger_account_for.code, ledger_account_for.name, ledger_account_for.unit,
    coalesce(ledger_account_for.scale, 0), ledger_account_for.holder_type, ledger_account_for.holder_id, ledger_account_for.owner_id,
    coalesce(ledger_account_for.allow_negative, false), ledger_account_for.read_permission, ledger_account_for.managed_by,
    coalesce(ledger_account_for.metadata, '{}'::jsonb))
  on conflict ("tenant_id", "code") do nothing
  returning "id" into v_id;
  if v_id is null then
    select x."id" into v_id from "better_supabase"."ledger_accounts" x
      where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ledger_account_for"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, text, jsonb) from public, anon, authenticated;

-- Posts a balanced transaction: lines is an array of {account, amount} with
-- signed integer amounts in each account's unit, summing to zero per unit.
-- With idempotency_key a second call returns the first transaction. Modules
-- that post to the ledger call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_post"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null, reverses uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if ledger_post.idempotency_key is not null then
    select x."id" into v_id from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = ledger_post.tenant and x."idempotency_key" = ledger_post.idempotency_key;
    if found then
      return v_id;
    end if;
  end if;
  if ledger_post.kind is null or ledger_post.kind !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$' then
    raise exception 'kind must be lowercase words joined by dots, such as credit.grant' using errcode = '22023', hint = 'LEDGER_KIND_INVALID';
  end if;
  if jsonb_typeof(ledger_post.lines) is distinct from 'array' or jsonb_array_length(ledger_post.lines) < 2 then
    raise exception 'a transaction needs at least two lines' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    where jsonb_typeof(l.value) is distinct from 'object'
      or coalesce(l.value ->> 'account', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(l.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
      or (l.value ->> 'amount')::bigint = 0
  ) then
    raise exception 'every line needs an account id and a non-zero integer amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    left join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
      and x."tenant_id" = ledger_post.tenant and x."closed_at" is null
    where x."id" is null
  ) then
    raise exception 'an account of the transaction doesn''t exist here or is closed' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
    group by x."unit" having sum((l.value ->> 'amount')::bigint) <> 0
  ) then
    raise exception 'the lines of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_ledger_transaction_post"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using ledger_post.tenant, ledger_post.kind, ledger_post.lines;
    end if;
  end;
  insert into "better_supabase"."ledger_transactions" ("tenant_id", "kind", "reference_type", "reference_id", "memo", "idempotency_key", "reverses", "metadata", "effective_at", "actor_id")
  values (ledger_post.tenant, ledger_post.kind, ledger_post.reference_type, ledger_post.reference_id, nullif(trim(ledger_post.memo), ''),
    ledger_post.idempotency_key, ledger_post.reverses, coalesce(ledger_post.metadata, '{}'::jsonb), coalesce(ledger_post.effective_at, now()), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."ledger_entries" ("tenant_id", "transaction_id", "account_id", "amount", "unit")
  select ledger_post.tenant, v_row."id", x."id", (l.value ->> 'amount')::bigint, x."unit"
  from jsonb_array_elements(ledger_post.lines) with ordinality as l(value, n)
  join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
  order by l.n;
  perform "better_supabase".emit_event('ledger_transaction.posted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id")), 'ledger-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_ledger_transaction_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."ledger_post"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb, uuid) from public, anon, authenticated;

-- Opens an account for the app's own use (credits, loyalty points, gift
-- cards, trust balances). code is unique per organization.
create or replace function "better_supabase"."open_ledger_account"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_ledger_account.tenant, 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."tenant_id" = open_ledger_account.tenant and x."code" = open_ledger_account.code) then
    raise exception 'an account with this code already exists' using errcode = '23505', hint = 'LEDGER_ACCOUNT_CODE_TAKEN';
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "metadata")
  values (open_ledger_account.tenant, open_ledger_account.kind, open_ledger_account.code, open_ledger_account.name, open_ledger_account.unit,
    coalesce(open_ledger_account.scale, 0), open_ledger_account.holder_type, open_ledger_account.holder_id, open_ledger_account.owner_id,
    coalesce(open_ledger_account.allow_negative, false), open_ledger_account.read_permission, coalesce(open_ledger_account.metadata, '{}'::jsonb))
  returning * into v_row;
  perform "better_supabase".emit_event('ledger_account.opened', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id"), 'ledger-accounts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_account.opened',
    category => 'billing',
    target_type => 'ledger_account',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'opened ledger account ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$$;
revoke execute on function "better_supabase"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) from public, anon;
grant execute on function "better_supabase"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) to authenticated, service_role;

-- Closes an account with a zero balance and no active holds.
create or replace function "better_supabase"."close_ledger_account"(account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ledger_accounts" x where x."id" = close_ledger_account.account_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or v_row."owner_id" = auth.uid() or (v_row."read_permission" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", v_row."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_row."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_row."id" for update;
  if coalesce(v_balance."balance", 0) <> 0 or coalesce(v_balance."held", 0) <> 0 then
    raise exception 'only an account with a zero balance and no holds can be closed' using errcode = '55000', hint = 'LEDGER_ACCOUNT_NOT_EMPTY';
  end if;
  if v_row."closed_at" is null then
    update "better_supabase"."ledger_accounts" x set "closed_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('ledger_account.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id"), 'ledger-accounts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_account.closed',
    category => 'billing',
    target_type => 'ledger_account',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'closed ledger account ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'code', v_row."code", 'unit', v_row."unit", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$$;
revoke execute on function "better_supabase"."close_ledger_account"(uuid) from public, anon;
grant execute on function "better_supabase"."close_ledger_account"(uuid) to authenticated, service_role;

-- Posts a balanced transaction to the app's own accounts. Accounts a block
-- manages (stock, leave, receivables) only move through that block.
create or replace function "better_supabase"."post_ledger_transaction"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_ledger_transaction.tenant, 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if jsonb_typeof(post_ledger_transaction.lines) = 'array' and exists (
    select 1 from jsonb_array_elements(post_ledger_transaction.lines) l
    join "better_supabase"."ledger_accounts" x on x."id"::text = l.value ->> 'account'
    where x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_id := "better_supabase"."ledger_post"(post_ledger_transaction.tenant, post_ledger_transaction.kind, post_ledger_transaction.lines,
    post_ledger_transaction.reference_type, post_ledger_transaction.reference_id, post_ledger_transaction.memo,
    post_ledger_transaction.idempotency_key, post_ledger_transaction.effective_at, post_ledger_transaction.metadata);
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) from public, anon;
grant execute on function "better_supabase"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) to authenticated, service_role;

-- Posts the opposite of a transaction. A transaction is reversed at most
-- once, and a reversal can't be reversed.
create or replace function "better_supabase"."reverse_ledger_transaction"(transaction_id uuid, memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "better_supabase"."ledger_transactions"%rowtype;
  v_row "better_supabase"."ledger_transactions"%rowtype;
  v_id uuid;
begin
  select * into v_old from "better_supabase"."ledger_transactions" x where x."id" = reverse_ledger_transaction.transaction_id;
  if not found then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_old."id" and x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  if v_old."reverses" is not null
    or exists (select 1 from "better_supabase"."ledger_transactions" x where x."reverses" = v_old."id") then
    raise exception 'this transaction is a reversal or is already reversed' using errcode = '55000', hint = 'LEDGER_ALREADY_REVERSED';
  end if;
  v_id := "better_supabase"."ledger_post"(v_old."tenant_id", v_old."kind",
    (select jsonb_agg(jsonb_build_object('account', y."account_id", 'amount', (-y."amount")::text) order by y."created_at", y."id")
      from "better_supabase"."ledger_entries" y where y."transaction_id" = v_old."id"),
    v_old."reference_type", v_old."reference_id", coalesce(reverse_ledger_transaction.memo, v_old."memo"),
    null, null, v_old."metadata", v_old."id");
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  perform "better_supabase".emit_event('ledger_transaction.reversed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id")), 'ledger-transactions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  perform better_supabase.audit_event(
    event_type => 'ledger_transaction.reversed',
    category => 'billing',
    target_type => 'ledger_transaction',
    record_id => v_old."id"::text,
    summary => 'reversed a ' || v_old."kind" || ' transaction',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'reverses', v_row."reverses", 'entries', (select count(*)::integer from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."reverse_ledger_transaction"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reverse_ledger_transaction"(uuid, text) to authenticated, service_role;

-- Sets aside part of an account's available balance until it is captured,
-- released or expires, without checking the caller. Modules that hold
-- amounts on their own accounts call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if ledger_hold.amount is null or ledger_hold.amount <= 0 then
    raise exception 'a hold needs an amount greater than zero' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  insert into "better_supabase"."ledger_balances" ("account_id", "tenant_id") values (v_account."id", v_account."tenant_id")
    on conflict ("account_id") do nothing;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_account."id" for update;
  if not v_account."allow_negative" and v_balance."balance" - v_balance."held" < ledger_hold.amount then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  update "better_supabase"."ledger_balances" x set "held" = x."held" + ledger_hold.amount, "updated_at" = now()
    where x."account_id" = v_account."id";
  insert into "better_supabase"."ledger_holds" ("tenant_id", "account_id", "amount", "reference_type", "reference_id", "expires_at", "created_by")
  values (v_account."tenant_id", v_account."id", ledger_hold.amount, ledger_hold.reference_type, ledger_hold.reference_id, ledger_hold.expires_at, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('ledger_hold.placed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'transactionId', v_row."transaction_id"), 'ledger-holds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon, authenticated;

create or replace function "better_supabase"."place_ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = place_ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_account."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "better_supabase"."ledger_hold"(place_ledger_hold.account_id, place_ledger_hold.amount, place_ledger_hold.reference_type, place_ledger_hold.reference_id, place_ledger_hold.expires_at);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) to authenticated, service_role;

-- Frees an active hold: release by a caller, expire from expire_ledger_holds.
create or replace function "better_supabase"."ledger_unhold"(hold_id uuid, status text)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = ledger_unhold.hold_id for update;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'this hold is no longer active' using errcode = '55000', hint = 'LEDGER_HOLD_CLOSED';
  end if;
  update "better_supabase"."ledger_balances" x set "held" = x."held" - v_row."amount", "updated_at" = now()
    where x."account_id" = v_row."account_id";
  update "better_supabase"."ledger_holds" x set "status" = ledger_unhold.status, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_unhold"(uuid, text) from public, anon, authenticated;

-- Captures a hold without checking the caller: frees it and posts amount
-- (default all of it) from the held account to to_account. Modules call it;
-- it isn't granted to anyone.
create or replace function "better_supabase"."ledger_capture"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
  v_amount bigint;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = ledger_capture.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  v_amount := coalesce(ledger_capture.amount, v_row."amount");
  if v_amount <= 0 or v_amount > v_row."amount" then
    raise exception 'a capture takes more than zero and at most the held amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  v_row := "better_supabase"."ledger_unhold"(v_row."id", 'captured');
  update "better_supabase"."ledger_holds" x set "transaction_id" = "better_supabase"."ledger_post"(v_row."tenant_id", coalesce(ledger_capture.kind, 'ledger.capture'),
      jsonb_build_array(
        jsonb_build_object('account', v_row."account_id", 'amount', (-v_amount)::text),
        jsonb_build_object('account', ledger_capture.to_account, 'amount', v_amount::text)),
      v_row."reference_type", v_row."reference_id", ledger_capture.memo)
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('ledger_hold.captured', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'transactionId', v_row."transaction_id"), 'ledger-holds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_capture"(uuid, uuid, bigint, text, text) from public, anon, authenticated;

create or replace function "better_supabase"."capture_ledger_hold"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = capture_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."id" = capture_ledger_hold.to_account and x."managed_by" is not null) and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "better_supabase"."ledger_capture"(v_row."id", capture_ledger_hold.to_account, capture_ledger_hold.amount, capture_ledger_hold.kind, capture_ledger_hold.memo);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."capture_ledger_hold"(uuid, uuid, bigint, text, text) from public, anon;
grant execute on function "better_supabase"."capture_ledger_hold"(uuid, uuid, bigint, text, text) to authenticated, service_role;

-- Releases an active hold without checking the caller. Modules call it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."ledger_release"(hold_id uuid)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  v_row := "better_supabase"."ledger_unhold"(ledger_release.hold_id, 'released');
  perform "better_supabase".emit_event('ledger_hold.released', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'transactionId', v_row."transaction_id"), 'ledger-holds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_release"(uuid) from public, anon, authenticated;

create or replace function "better_supabase"."release_ledger_hold"(hold_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = release_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  v_row := "better_supabase"."ledger_release"(v_row."id");
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."release_ledger_hold"(uuid) from public, anon;
grant execute on function "better_supabase"."release_ledger_hold"(uuid) to authenticated, service_role;

-- Releases the active holds past expires_at; a scheduled job runs it.
-- Returns how many it expired.
create or replace function "better_supabase"."expire_ledger_holds"(max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_holds"%rowtype;
  v_count integer := 0;
begin
  for v_id in
    select x."id" from "better_supabase"."ledger_holds" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit least(greatest(coalesce(expire_ledger_holds.max_rows, 500), 1), 5000)
    for update skip locked
  loop
    v_row := "better_supabase"."ledger_unhold"(v_id, 'expired');
    perform "better_supabase".emit_event('ledger_hold.released', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'transactionId', v_row."transaction_id"), 'ledger-holds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ledger');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_ledger_holds"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_ledger_holds"(integer) to service_role;

-- The accounts the caller can read, with their balances: every account with
-- the read permission, else the caller's own and those a read permission of
-- another block grants. Without a tenant it lists a holder's accounts in
-- every tenant the caller can read them in.
create or replace function "better_supabase"."list_ledger_accounts"(tenant uuid, kind text default null, holder_type text default null, holder_id text default null, page_size integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.code), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'code', x."code", 'name', x."name", 'unit', x."unit", 'scale', x."scale", 'holderType', x."holder_type", 'holderId', x."holder_id", 'ownerId', x."owner_id", 'allowNegative', x."allow_negative", 'readPermission', x."read_permission", 'managedBy', x."managed_by", 'metadata', x."metadata", 'closedAt', x."closed_at", 'createdAt', x."created_at", 'balance', coalesce(y."balance", 0)::text, 'held', coalesce(y."held", 0)::text, 'available', coalesce(y."balance" - y."held", 0)::text) as item, x."code" as code
    from "better_supabase"."ledger_accounts" x
    left join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
    where (list_ledger_accounts.tenant is null or x."tenant_id" = list_ledger_accounts.tenant)
      and (list_ledger_accounts.kind is null or x."kind" = list_ledger_accounts.kind)
      and (list_ledger_accounts.holder_type is null or x."holder_type" = list_ledger_accounts.holder_type)
      and (list_ledger_accounts.holder_id is null or x."holder_id" = list_ledger_accounts.holder_id)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
    order by x."code"
    limit least(greatest(coalesce(list_ledger_accounts.page_size, 100), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_ledger_accounts"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_ledger_accounts"(uuid, text, text, text, integer) to authenticated, service_role;

-- An account's entries, newest first, with the transaction each belongs to.
-- before pages back from an entry's created_at.
create or replace function "better_supabase"."ledger_account_entries"(account_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_rows jsonb;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = ledger_account_entries.account_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.read'), false) or v_account."owner_id" = auth.uid() or (v_account."read_permission" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", v_account."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit",
        'transactionId', r."id", 'kind', r."kind", 'referenceType', r."reference_type", 'referenceId', r."reference_id",
        'memo', r."memo", 'reverses', r."reverses", 'metadata', r."metadata", 'effectiveAt', r."effective_at", 'createdAt', y."created_at") as item,
      y."created_at" as created, y."id" as id
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where y."account_id" = v_account."id"
      and (ledger_account_entries.before is null or y."created_at" < ledger_account_entries.before)
    order by y."created_at" desc, y."id" desc
    limit least(greatest(coalesce(ledger_account_entries.page_size, 50), 1), 500)
  ) z;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."ledger_account_entries"(uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."ledger_account_entries"(uuid, timestamptz, integer) to authenticated, service_role;

-- One transaction with its entries, for a caller who can read one of its
-- accounts.
create or replace function "better_supabase"."get_ledger_transaction"(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = get_ledger_transaction.transaction_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_row."id" and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
  )) then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_ledger_transaction"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ledger_transaction"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_accounts";
create policy bsb_tenant_scope on "better_supabase"."ledger_accounts" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or "owner_id" = (select auth.uid())
    or ("tenant_id", "read_permission") in (select g.tenant, g.permission from "better_supabase"."ledger_read_grants"() g))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_transactions";
create policy bsb_tenant_scope on "better_supabase"."ledger_transactions" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = "id"))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_entries";
create policy bsb_tenant_scope on "better_supabase"."ledger_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_balances";
create policy bsb_tenant_scope on "better_supabase"."ledger_balances" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_holds";
create policy bsb_tenant_scope on "better_supabase"."ledger_holds" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_80_ledger.sql
-- better-supabase module: ledger
-- @bsb-block-data ledger
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ledger', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_80_ledger.sql
-- better-supabase module: ledger
-- @bsb-block ledger@1 managed
-- Double-entry accounts in a currency or a custom unit, balanced transactions, balances and holds. Credits, stock, leave balances and invoice payments post through it.
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
create table if not exists "app_private"."ledger_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "code" text not null check (length("code") between 1 and 200),
  "name" text not null check (length("name") between 1 and 200),
  -- An ISO 4217 code for money, or a custom unit such as item, days or points.
  "unit" text not null check ("unit" ~ '^([A-Z]{3}|[a-z][a-z0-9_]{0,31})$'),
  -- Decimal places of a custom unit: amounts are integers, 150 at scale 2 is 1.5.
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "holder_type" text,
  "holder_id" text,
  -- The member the account belongs to, who can read it without a permission.
  "owner_id" uuid,
  "allow_negative" boolean not null default false,
  -- A permission key that also grants reading the account.
  "read_permission" text,
  -- The module that posts to the account; post_ledger_transaction refuses it.
  "managed_by" text,
  "metadata" jsonb not null default '{}'::jsonb,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  check (("holder_type" is null) = ("holder_id" is null))
);
create index if not exists "ledger_accounts_holder_idx" on "app_private"."ledger_accounts" ("tenant_id", "holder_type", "holder_id") where "holder_type" is not null;
create index if not exists "ledger_accounts_kind_idx" on "app_private"."ledger_accounts" ("tenant_id", "kind");
create index if not exists "ledger_accounts_owner_idx" on "app_private"."ledger_accounts" ("owner_id") where "owner_id" is not null;

create table if not exists "app_private"."ledger_transactions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$'),
  "reference_type" text,
  "reference_id" text,
  "memo" text check ("memo" is null or length("memo") <= 2000),
  "idempotency_key" text,
  "reverses" uuid references "app_private"."ledger_transactions" ("id") on delete restrict,
  "metadata" jsonb not null default '{}'::jsonb,
  "effective_at" timestamptz not null default now(),
  "actor_id" uuid,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "ledger_transactions_key_idx" on "app_private"."ledger_transactions" ("tenant_id", "idempotency_key") where "idempotency_key" is not null;
create unique index if not exists "ledger_transactions_reverses_idx" on "app_private"."ledger_transactions" ("reverses") where "reverses" is not null;
create index if not exists "ledger_transactions_reference_idx" on "app_private"."ledger_transactions" ("tenant_id", "reference_type", "reference_id") where "reference_type" is not null;
create index if not exists "ledger_transactions_tenant_idx" on "app_private"."ledger_transactions" ("tenant_id", "effective_at" desc);

create table if not exists "app_private"."ledger_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "transaction_id" uuid not null references "app_private"."ledger_transactions" ("id") on delete restrict,
  "account_id" uuid not null references "app_private"."ledger_accounts" ("id") on delete restrict,
  -- Signed, in the account's unit: the entries of a transaction sum to zero per unit.
  "amount" bigint not null check ("amount" <> 0),
  "unit" text not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "ledger_entries_account_idx" on "app_private"."ledger_entries" ("account_id", "created_at" desc);
create index if not exists "ledger_entries_transaction_idx" on "app_private"."ledger_entries" ("transaction_id");

create table if not exists "app_private"."ledger_balances" (
  "account_id" uuid primary key references "app_private"."ledger_accounts" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "balance" bigint not null default 0,
  -- The sum of the account's active holds.
  "held" bigint not null default 0 check ("held" >= 0),
  "available" bigint generated always as ("balance" - "held") stored,
  "updated_at" timestamptz not null default now()
);
create index if not exists "ledger_balances_tenant_idx" on "app_private"."ledger_balances" ("tenant_id");

create table if not exists "app_private"."ledger_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "app_private"."ledger_accounts" ("id") on delete restrict,
  "amount" bigint not null check ("amount" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'captured', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz,
  "transaction_id" uuid references "app_private"."ledger_transactions" ("id") on delete restrict,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "ledger_holds_account_idx" on "app_private"."ledger_holds" ("account_id", "status");
create index if not exists "ledger_holds_transaction_idx" on "app_private"."ledger_holds" ("transaction_id") where "transaction_id" is not null;
create index if not exists "ledger_holds_expiry_idx" on "app_private"."ledger_holds" ("expires_at") where "status" = 'active' and "expires_at" is not null;

alter table "app_private"."ledger_accounts" enable row level security;
revoke all on "app_private"."ledger_accounts" from anon, authenticated;
grant select on "app_private"."ledger_accounts" to authenticated;
grant all on "app_private"."ledger_accounts" to service_role;
create index if not exists "ledger_accounts_read_permission_idx" on "app_private"."ledger_accounts" ("tenant_id", "read_permission") where "read_permission" is not null;
-- The (tenant, permission) pairs of account read permissions the caller
-- holds, so the policy checks each pair once per statement, not per row.
create or replace function "app_private"."ledger_read_grants"()
returns table (tenant uuid, permission text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select p.tenant, p.permission from (
    select distinct x."tenant_id" as tenant, x."read_permission" as permission
    from "app_private"."ledger_accounts" x
    where x."read_permission" is not null and x."tenant_id" in (select better_supabase.member_organization_ids())
  ) p
  where coalesce(better_supabase.can('tenant', p.tenant, p.permission), false);
end;
$$;
revoke execute on function "app_private"."ledger_read_grants"() from public, anon;
grant execute on function "app_private"."ledger_read_grants"() to authenticated, service_role;
drop policy if exists "ledger_accounts_read" on "app_private"."ledger_accounts";
create policy "ledger_accounts_read" on "app_private"."ledger_accounts" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or "owner_id" = (select auth.uid())
    or ("tenant_id", "read_permission") in (select g.tenant, g.permission from "app_private"."ledger_read_grants"() g));
alter table "app_private"."ledger_transactions" enable row level security;
revoke all on "app_private"."ledger_transactions" from anon, authenticated;
grant select on "app_private"."ledger_transactions" to authenticated;
grant all on "app_private"."ledger_transactions" to service_role;
drop policy if exists "ledger_transactions_read" on "app_private"."ledger_transactions";
create policy "ledger_transactions_read" on "app_private"."ledger_transactions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "app_private"."ledger_entries" y where y."transaction_id" = "id"));
alter table "app_private"."ledger_entries" enable row level security;
revoke all on "app_private"."ledger_entries" from anon, authenticated;
grant select on "app_private"."ledger_entries" to authenticated;
grant all on "app_private"."ledger_entries" to service_role;
drop policy if exists "ledger_entries_read" on "app_private"."ledger_entries";
create policy "ledger_entries_read" on "app_private"."ledger_entries" for select to authenticated
  using ("account_id" in (select y."id" from "app_private"."ledger_accounts" y));
alter table "app_private"."ledger_balances" enable row level security;
revoke all on "app_private"."ledger_balances" from anon, authenticated;
grant select on "app_private"."ledger_balances" to authenticated;
grant all on "app_private"."ledger_balances" to service_role;
drop policy if exists "ledger_balances_read" on "app_private"."ledger_balances";
create policy "ledger_balances_read" on "app_private"."ledger_balances" for select to authenticated
  using ("account_id" in (select y."id" from "app_private"."ledger_accounts" y));
alter table "app_private"."ledger_holds" enable row level security;
revoke all on "app_private"."ledger_holds" from anon, authenticated;
grant select on "app_private"."ledger_holds" to authenticated;
grant all on "app_private"."ledger_holds" to service_role;
drop policy if exists "ledger_holds_read" on "app_private"."ledger_holds";
create policy "ledger_holds_read" on "app_private"."ledger_holds" for select to authenticated
  using ("account_id" in (select y."id" from "app_private"."ledger_accounts" y));

-- Entries and transactions are append-only: a reversal posts the opposite.
create or replace function "app_private"."ledger_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'ledger entries and transactions can''t be changed or deleted; post a reversal' using errcode = '55000', hint = 'LEDGER_APPEND_ONLY';
end;
$$;
revoke execute on function "app_private"."ledger_append_only"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_append_only" on "app_private"."ledger_entries";
create trigger "bsb_ledger_entries_append_only" before update or delete on "app_private"."ledger_entries"
  for each row execute function "app_private"."ledger_append_only"();
drop trigger if exists "bsb_ledger_transactions_append_only" on "app_private"."ledger_transactions";
create trigger "bsb_ledger_transactions_append_only" before update or delete on "app_private"."ledger_transactions"
  for each row execute function "app_private"."ledger_append_only"();

-- Keeps the account's balance and refuses to take an account that doesn't
-- allow it below zero (counting its holds).
create or replace function "app_private"."ledger_apply_entry"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available bigint;
begin
  insert into "app_private"."ledger_balances" as x ("account_id", "tenant_id", "balance")
  values (new."account_id", new."tenant_id", new."amount")
  on conflict ("account_id") do update set "balance" = x."balance" + excluded."balance", "updated_at" = now()
  returning x."balance" - x."held" into v_available;
  if new."amount" < 0 and v_available < 0 and not exists (
    select 1 from "app_private"."ledger_accounts" y where y."id" = new."account_id" and y."allow_negative"
  ) then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."ledger_apply_entry"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_apply" on "app_private"."ledger_entries";
create trigger "bsb_ledger_entries_apply" after insert on "app_private"."ledger_entries"
  for each row execute function "app_private"."ledger_apply_entry"();

-- At commit, the entries of each transaction sum to zero per unit.
create or replace function "app_private"."ledger_check_balanced"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from "app_private"."ledger_entries" y where y."transaction_id" = new."transaction_id"
    group by y."unit" having sum(y."amount") <> 0
  ) then
    raise exception 'the entries of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."ledger_check_balanced"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_balanced" on "app_private"."ledger_entries";
create constraint trigger "bsb_ledger_entries_balanced" after insert on "app_private"."ledger_entries"
  deferrable initially deferred
  for each row execute function "app_private"."ledger_check_balanced"();

-- The account with code, opened with the rest when it doesn't exist yet.
-- Modules that post to the ledger call it; it isn't granted to anyone.
create or replace function "app_private"."ledger_account_for"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, managed_by text default null, metadata jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  select x."id" into v_id from "app_private"."ledger_accounts" x
    where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  if found then
    return v_id;
  end if;
  insert into "app_private"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "managed_by", "metadata")
  values (ledger_account_for.tenant, ledger_account_for.kind, ledger_account_for.code, ledger_account_for.name, ledger_account_for.unit,
    coalesce(ledger_account_for.scale, 0), ledger_account_for.holder_type, ledger_account_for.holder_id, ledger_account_for.owner_id,
    coalesce(ledger_account_for.allow_negative, false), ledger_account_for.read_permission, ledger_account_for.managed_by,
    coalesce(ledger_account_for.metadata, '{}'::jsonb))
  on conflict ("tenant_id", "code") do nothing
  returning "id" into v_id;
  if v_id is null then
    select x."id" into v_id from "app_private"."ledger_accounts" x
      where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  end if;
  return v_id;
end;
$$;
revoke execute on function "app_private"."ledger_account_for"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, text, jsonb) from public, anon, authenticated;

-- Posts a balanced transaction: lines is an array of {account, amount} with
-- signed integer amounts in each account's unit, summing to zero per unit.
-- With idempotency_key a second call returns the first transaction. Modules
-- that post to the ledger call it; it isn't granted to anyone.
create or replace function "app_private"."ledger_post"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null, reverses uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "app_private"."ledger_transactions"%rowtype;
begin
  if ledger_post.idempotency_key is not null then
    select x."id" into v_id from "app_private"."ledger_transactions" x
      where x."tenant_id" = ledger_post.tenant and x."idempotency_key" = ledger_post.idempotency_key;
    if found then
      return v_id;
    end if;
  end if;
  if ledger_post.kind is null or ledger_post.kind !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$' then
    raise exception 'kind must be lowercase words joined by dots, such as credit.grant' using errcode = '22023', hint = 'LEDGER_KIND_INVALID';
  end if;
  if jsonb_typeof(ledger_post.lines) is distinct from 'array' or jsonb_array_length(ledger_post.lines) < 2 then
    raise exception 'a transaction needs at least two lines' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    where jsonb_typeof(l.value) is distinct from 'object'
      or coalesce(l.value ->> 'account', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(l.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
      or (l.value ->> 'amount')::bigint = 0
  ) then
    raise exception 'every line needs an account id and a non-zero integer amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    left join "app_private"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
      and x."tenant_id" = ledger_post.tenant and x."closed_at" is null
    where x."id" is null
  ) then
    raise exception 'an account of the transaction doesn''t exist here or is closed' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    join "app_private"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
    group by x."unit" having sum((l.value ->> 'amount')::bigint) <> 0
  ) then
    raise exception 'the lines of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_ledger_transaction_post"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using ledger_post.tenant, ledger_post.kind, ledger_post.lines;
    end if;
  end;
  insert into "app_private"."ledger_transactions" ("tenant_id", "kind", "reference_type", "reference_id", "memo", "idempotency_key", "reverses", "metadata", "effective_at", "actor_id")
  values (ledger_post.tenant, ledger_post.kind, ledger_post.reference_type, ledger_post.reference_id, nullif(trim(ledger_post.memo), ''),
    ledger_post.idempotency_key, ledger_post.reverses, coalesce(ledger_post.metadata, '{}'::jsonb), coalesce(ledger_post.effective_at, now()), auth.uid())
  returning * into v_row;
  insert into "app_private"."ledger_entries" ("tenant_id", "transaction_id", "account_id", "amount", "unit")
  select ledger_post.tenant, v_row."id", x."id", (l.value ->> 'amount')::bigint, x."unit"
  from jsonb_array_elements(ledger_post.lines) with ordinality as l(value, n)
  join "app_private"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
  order by l.n;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_ledger_transaction_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row."id";
end;
$$;
revoke execute on function "app_private"."ledger_post"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb, uuid) from public, anon, authenticated;

-- Opens an account for the app's own use (credits, loyalty points, gift
-- cards, trust balances). code is unique per organization.
create or replace function "app_private"."open_ledger_account"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."ledger_accounts"%rowtype;
  v_balance "app_private"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_ledger_account.tenant, 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "app_private"."ledger_accounts" x where x."tenant_id" = open_ledger_account.tenant and x."code" = open_ledger_account.code) then
    raise exception 'an account with this code already exists' using errcode = '23505', hint = 'LEDGER_ACCOUNT_CODE_TAKEN';
  end if;
  insert into "app_private"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "metadata")
  values (open_ledger_account.tenant, open_ledger_account.kind, open_ledger_account.code, open_ledger_account.name, open_ledger_account.unit,
    coalesce(open_ledger_account.scale, 0), open_ledger_account.holder_type, open_ledger_account.holder_id, open_ledger_account.owner_id,
    coalesce(open_ledger_account.allow_negative, false), open_ledger_account.read_permission, coalesce(open_ledger_account.metadata, '{}'::jsonb))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$$;
revoke execute on function "app_private"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) from public, anon;
grant execute on function "app_private"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) to authenticated, service_role;

-- Closes an account with a zero balance and no active holds.
create or replace function "app_private"."close_ledger_account"(account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."ledger_accounts"%rowtype;
  v_balance "app_private"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."ledger_accounts" x where x."id" = close_ledger_account.account_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or v_row."owner_id" = auth.uid() or (v_row."read_permission" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", v_row."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_row."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  select * into v_balance from "app_private"."ledger_balances" x where x."account_id" = v_row."id" for update;
  if coalesce(v_balance."balance", 0) <> 0 or coalesce(v_balance."held", 0) <> 0 then
    raise exception 'only an account with a zero balance and no holds can be closed' using errcode = '55000', hint = 'LEDGER_ACCOUNT_NOT_EMPTY';
  end if;
  if v_row."closed_at" is null then
    update "app_private"."ledger_accounts" x set "closed_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$$;
revoke execute on function "app_private"."close_ledger_account"(uuid) from public, anon;
grant execute on function "app_private"."close_ledger_account"(uuid) to authenticated, service_role;

-- Posts a balanced transaction to the app's own accounts. Accounts a block
-- manages (stock, leave, receivables) only move through that block.
create or replace function "app_private"."post_ledger_transaction"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "app_private"."ledger_transactions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_ledger_transaction.tenant, 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if jsonb_typeof(post_ledger_transaction.lines) = 'array' and exists (
    select 1 from jsonb_array_elements(post_ledger_transaction.lines) l
    join "app_private"."ledger_accounts" x on x."id"::text = l.value ->> 'account'
    where x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_id := "app_private"."ledger_post"(post_ledger_transaction.tenant, post_ledger_transaction.kind, post_ledger_transaction.lines,
    post_ledger_transaction.reference_type, post_ledger_transaction.reference_id, post_ledger_transaction.memo,
    post_ledger_transaction.idempotency_key, post_ledger_transaction.effective_at, post_ledger_transaction.metadata);
  select * into v_row from "app_private"."ledger_transactions" x where x."id" = v_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "app_private"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) from public, anon;
grant execute on function "app_private"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) to authenticated, service_role;

-- Posts the opposite of a transaction. A transaction is reversed at most
-- once, and a reversal can't be reversed.
create or replace function "app_private"."reverse_ledger_transaction"(transaction_id uuid, memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "app_private"."ledger_transactions"%rowtype;
  v_row "app_private"."ledger_transactions"%rowtype;
  v_id uuid;
begin
  select * into v_old from "app_private"."ledger_transactions" x where x."id" = reverse_ledger_transaction.transaction_id;
  if not found then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (
    select 1 from "app_private"."ledger_entries" y join "app_private"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_old."id" and x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  if v_old."reverses" is not null
    or exists (select 1 from "app_private"."ledger_transactions" x where x."reverses" = v_old."id") then
    raise exception 'this transaction is a reversal or is already reversed' using errcode = '55000', hint = 'LEDGER_ALREADY_REVERSED';
  end if;
  v_id := "app_private"."ledger_post"(v_old."tenant_id", v_old."kind",
    (select jsonb_agg(jsonb_build_object('account', y."account_id", 'amount', (-y."amount")::text) order by y."created_at", y."id")
      from "app_private"."ledger_entries" y where y."transaction_id" = v_old."id"),
    v_old."reference_type", v_old."reference_id", coalesce(reverse_ledger_transaction.memo, v_old."memo"),
    null, null, v_old."metadata", v_old."id");
  select * into v_row from "app_private"."ledger_transactions" x where x."id" = v_id;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "app_private"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."reverse_ledger_transaction"(uuid, text) from public, anon;
grant execute on function "app_private"."reverse_ledger_transaction"(uuid, text) to authenticated, service_role;

-- Sets aside part of an account's available balance until it is captured,
-- released or expires, without checking the caller. Modules that hold
-- amounts on their own accounts call it; it isn't granted to anyone.
create or replace function "app_private"."ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns "app_private"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "app_private"."ledger_accounts"%rowtype;
  v_balance "app_private"."ledger_balances"%rowtype;
  v_row "app_private"."ledger_holds"%rowtype;
begin
  select * into v_account from "app_private"."ledger_accounts" x where x."id" = ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if ledger_hold.amount is null or ledger_hold.amount <= 0 then
    raise exception 'a hold needs an amount greater than zero' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  insert into "app_private"."ledger_balances" ("account_id", "tenant_id") values (v_account."id", v_account."tenant_id")
    on conflict ("account_id") do nothing;
  select * into v_balance from "app_private"."ledger_balances" x where x."account_id" = v_account."id" for update;
  if not v_account."allow_negative" and v_balance."balance" - v_balance."held" < ledger_hold.amount then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  update "app_private"."ledger_balances" x set "held" = x."held" + ledger_hold.amount, "updated_at" = now()
    where x."account_id" = v_account."id";
  insert into "app_private"."ledger_holds" ("tenant_id", "account_id", "amount", "reference_type", "reference_id", "expires_at", "created_by")
  values (v_account."tenant_id", v_account."id", ledger_hold.amount, ledger_hold.reference_type, ledger_hold.reference_id, ledger_hold.expires_at, auth.uid())
  returning * into v_row;
  null;
  return v_row;
end;
$$;
revoke execute on function "app_private"."ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon, authenticated;

create or replace function "app_private"."place_ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "app_private"."ledger_accounts"%rowtype;
  v_row "app_private"."ledger_holds"%rowtype;
begin
  select * into v_account from "app_private"."ledger_accounts" x where x."id" = place_ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_account."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "app_private"."ledger_hold"(place_ledger_hold.account_id, place_ledger_hold.amount, place_ledger_hold.reference_type, place_ledger_hold.reference_id, place_ledger_hold.expires_at);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon;
grant execute on function "app_private"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) to authenticated, service_role;

-- Frees an active hold: release by a caller, expire from expire_ledger_holds.
create or replace function "app_private"."ledger_unhold"(hold_id uuid, status text)
returns "app_private"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."ledger_holds"%rowtype;
begin
  select * into v_row from "app_private"."ledger_holds" x where x."id" = ledger_unhold.hold_id for update;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'this hold is no longer active' using errcode = '55000', hint = 'LEDGER_HOLD_CLOSED';
  end if;
  update "app_private"."ledger_balances" x set "held" = x."held" - v_row."amount", "updated_at" = now()
    where x."account_id" = v_row."account_id";
  update "app_private"."ledger_holds" x set "status" = ledger_unhold.status, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function "app_private"."ledger_unhold"(uuid, text) from public, anon, authenticated;

-- Captures a hold without checking the caller: frees it and posts amount
-- (default all of it) from the held account to to_account. Modules call it;
-- it isn't granted to anyone.
create or replace function "app_private"."ledger_capture"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns "app_private"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."ledger_holds"%rowtype;
  v_amount bigint;
begin
  select * into v_row from "app_private"."ledger_holds" x where x."id" = ledger_capture.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  v_amount := coalesce(ledger_capture.amount, v_row."amount");
  if v_amount <= 0 or v_amount > v_row."amount" then
    raise exception 'a capture takes more than zero and at most the held amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  v_row := "app_private"."ledger_unhold"(v_row."id", 'captured');
  update "app_private"."ledger_holds" x set "transaction_id" = "app_private"."ledger_post"(v_row."tenant_id", coalesce(ledger_capture.kind, 'ledger.capture'),
      jsonb_build_array(
        jsonb_build_object('account', v_row."account_id", 'amount', (-v_amount)::text),
        jsonb_build_object('account', ledger_capture.to_account, 'amount', v_amount::text)),
      v_row."reference_type", v_row."reference_id", ledger_capture.memo)
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return v_row;
end;
$$;
revoke execute on function "app_private"."ledger_capture"(uuid, uuid, bigint, text, text) from public, anon, authenticated;

create or replace function "app_private"."capture_ledger_hold"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."ledger_holds"%rowtype;
begin
  select * into v_row from "app_private"."ledger_holds" x where x."id" = capture_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "app_private"."ledger_accounts" x where x."id" = capture_ledger_hold.to_account and x."managed_by" is not null) and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "app_private"."ledger_capture"(v_row."id", capture_ledger_hold.to_account, capture_ledger_hold.amount, capture_ledger_hold.kind, capture_ledger_hold.memo);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."capture_ledger_hold"(uuid, uuid, bigint, text, text) from public, anon;
grant execute on function "app_private"."capture_ledger_hold"(uuid, uuid, bigint, text, text) to authenticated, service_role;

-- Releases an active hold without checking the caller. Modules call it; it
-- isn't granted to anyone.
create or replace function "app_private"."ledger_release"(hold_id uuid)
returns "app_private"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."ledger_holds"%rowtype;
begin
  v_row := "app_private"."ledger_unhold"(ledger_release.hold_id, 'released');
  null;
  return v_row;
end;
$$;
revoke execute on function "app_private"."ledger_release"(uuid) from public, anon, authenticated;

create or replace function "app_private"."release_ledger_hold"(hold_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."ledger_holds"%rowtype;
begin
  select * into v_row from "app_private"."ledger_holds" x where x."id" = release_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  v_row := "app_private"."ledger_release"(v_row."id");
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."release_ledger_hold"(uuid) from public, anon;
grant execute on function "app_private"."release_ledger_hold"(uuid) to authenticated, service_role;

-- Releases the active holds past expires_at; a scheduled job runs it.
-- Returns how many it expired.
create or replace function "app_private"."expire_ledger_holds"(max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "app_private"."ledger_holds"%rowtype;
  v_count integer := 0;
begin
  for v_id in
    select x."id" from "app_private"."ledger_holds" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit least(greatest(coalesce(expire_ledger_holds.max_rows, 500), 1), 5000)
    for update skip locked
  loop
    v_row := "app_private"."ledger_unhold"(v_id, 'expired');
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."expire_ledger_holds"(integer) from public, anon, authenticated;
grant execute on function "app_private"."expire_ledger_holds"(integer) to service_role;

-- The accounts the caller can read, with their balances: every account with
-- the read permission, else the caller's own and those a read permission of
-- another block grants. Without a tenant it lists a holder's accounts in
-- every tenant the caller can read them in.
create or replace function "app_private"."list_ledger_accounts"(tenant uuid, kind text default null, holder_type text default null, holder_id text default null, page_size integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.code), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'code', x."code", 'name', x."name", 'unit', x."unit", 'scale', x."scale", 'holderType', x."holder_type", 'holderId', x."holder_id", 'ownerId', x."owner_id", 'allowNegative', x."allow_negative", 'readPermission', x."read_permission", 'managedBy', x."managed_by", 'metadata', x."metadata", 'closedAt', x."closed_at", 'createdAt', x."created_at", 'balance', coalesce(y."balance", 0)::text, 'held', coalesce(y."held", 0)::text, 'available', coalesce(y."balance" - y."held", 0)::text) as item, x."code" as code
    from "app_private"."ledger_accounts" x
    left join "app_private"."ledger_balances" y on y."account_id" = x."id"
    where (list_ledger_accounts.tenant is null or x."tenant_id" = list_ledger_accounts.tenant)
      and (list_ledger_accounts.kind is null or x."kind" = list_ledger_accounts.kind)
      and (list_ledger_accounts.holder_type is null or x."holder_type" = list_ledger_accounts.holder_type)
      and (list_ledger_accounts.holder_id is null or x."holder_id" = list_ledger_accounts.holder_id)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
    order by x."code"
    limit least(greatest(coalesce(list_ledger_accounts.page_size, 100), 1), 1000)
  ) z
$$;
revoke execute on function "app_private"."list_ledger_accounts"(uuid, text, text, text, integer) from public, anon;
grant execute on function "app_private"."list_ledger_accounts"(uuid, text, text, text, integer) to authenticated, service_role;

-- An account's entries, newest first, with the transaction each belongs to.
-- before pages back from an entry's created_at.
create or replace function "app_private"."ledger_account_entries"(account_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "app_private"."ledger_accounts"%rowtype;
  v_rows jsonb;
begin
  select * into v_account from "app_private"."ledger_accounts" x where x."id" = ledger_account_entries.account_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.read'), false) or v_account."owner_id" = auth.uid() or (v_account."read_permission" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", v_account."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit",
        'transactionId', r."id", 'kind', r."kind", 'referenceType', r."reference_type", 'referenceId', r."reference_id",
        'memo', r."memo", 'reverses', r."reverses", 'metadata', r."metadata", 'effectiveAt', r."effective_at", 'createdAt', y."created_at") as item,
      y."created_at" as created, y."id" as id
    from "app_private"."ledger_entries" y
    join "app_private"."ledger_transactions" r on r."id" = y."transaction_id"
    where y."account_id" = v_account."id"
      and (ledger_account_entries.before is null or y."created_at" < ledger_account_entries.before)
    order by y."created_at" desc, y."id" desc
    limit least(greatest(coalesce(ledger_account_entries.page_size, 50), 1), 500)
  ) z;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."ledger_account_entries"(uuid, timestamptz, integer) from public, anon;
grant execute on function "app_private"."ledger_account_entries"(uuid, timestamptz, integer) to authenticated, service_role;

-- One transaction with its entries, for a caller who can read one of its
-- accounts.
create or replace function "app_private"."get_ledger_transaction"(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."ledger_transactions"%rowtype;
begin
  select * into v_row from "app_private"."ledger_transactions" x where x."id" = get_ledger_transaction.transaction_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or exists (
    select 1 from "app_private"."ledger_entries" y join "app_private"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_row."id" and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
  )) then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "app_private"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."get_ledger_transaction"(uuid) from public, anon;
grant execute on function "app_private"."get_ledger_transaction"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "app_private"."ledger_accounts";
create policy bsb_tenant_scope on "app_private"."ledger_accounts" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or "owner_id" = (select auth.uid())
    or ("tenant_id", "read_permission") in (select g.tenant, g.permission from "app_private"."ledger_read_grants"() g))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."ledger_transactions";
create policy bsb_tenant_scope on "app_private"."ledger_transactions" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "app_private"."ledger_entries" y where y."transaction_id" = "id"))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."ledger_entries";
create policy bsb_tenant_scope on "app_private"."ledger_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "app_private"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."ledger_balances";
create policy bsb_tenant_scope on "app_private"."ledger_balances" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "app_private"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."ledger_holds";
create policy bsb_tenant_scope on "app_private"."ledger_holds" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "app_private"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_80_ledger.sql
-- better-supabase module: ledger
-- @bsb-block-data ledger
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ledger', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_80_ledger.sql
-- better-supabase module: ledger
-- @bsb-block ledger@1 managed
-- Double-entry accounts in a currency or a custom unit, balanced transactions, balances and holds. Credits, stock, leave balances and invoice payments post through it.
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
create table if not exists "better_supabase"."ledger_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "code" text not null check (length("code") between 1 and 200),
  "name" text not null check (length("name") between 1 and 200),
  -- An ISO 4217 code for money, or a custom unit such as item, days or points.
  "unit" text not null check ("unit" ~ '^([A-Z]{3}|[a-z][a-z0-9_]{0,31})$'),
  -- Decimal places of a custom unit: amounts are integers, 150 at scale 2 is 1.5.
  "scale" smallint not null default 0 check ("scale" between 0 and 6),
  "holder_type" text,
  "holder_id" text,
  -- The member the account belongs to, who can read it without a permission.
  "owner_id" uuid,
  "allow_negative" boolean not null default false,
  -- A permission key that also grants reading the account.
  "read_permission" text,
  -- The module that posts to the account; post_ledger_transaction refuses it.
  "managed_by" text,
  "metadata" jsonb not null default '{}'::jsonb,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  check (("holder_type" is null) = ("holder_id" is null))
);
create index if not exists "ledger_accounts_holder_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "holder_type", "holder_id") where "holder_type" is not null;
create index if not exists "ledger_accounts_kind_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "kind");
create index if not exists "ledger_accounts_owner_idx" on "better_supabase"."ledger_accounts" ("owner_id") where "owner_id" is not null;

create table if not exists "better_supabase"."ledger_transactions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$'),
  "reference_type" text,
  "reference_id" text,
  "memo" text check ("memo" is null or length("memo") <= 2000),
  "idempotency_key" text,
  "reverses" uuid references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "metadata" jsonb not null default '{}'::jsonb,
  "effective_at" timestamptz not null default now(),
  "actor_id" uuid,
  "created_at" timestamptz not null default now()
);
create unique index if not exists "ledger_transactions_key_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "idempotency_key") where "idempotency_key" is not null;
create unique index if not exists "ledger_transactions_reverses_idx" on "better_supabase"."ledger_transactions" ("reverses") where "reverses" is not null;
create index if not exists "ledger_transactions_reference_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "reference_type", "reference_id") where "reference_type" is not null;
create index if not exists "ledger_transactions_tenant_idx" on "better_supabase"."ledger_transactions" ("tenant_id", "effective_at" desc);

create table if not exists "better_supabase"."ledger_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "transaction_id" uuid not null references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "account_id" uuid not null references "better_supabase"."ledger_accounts" ("id") on delete restrict,
  -- Signed, in the account's unit: the entries of a transaction sum to zero per unit.
  "amount" bigint not null check ("amount" <> 0),
  "unit" text not null,
  "created_at" timestamptz not null default now()
);
create index if not exists "ledger_entries_account_idx" on "better_supabase"."ledger_entries" ("account_id", "created_at" desc);
create index if not exists "ledger_entries_transaction_idx" on "better_supabase"."ledger_entries" ("transaction_id");

create table if not exists "better_supabase"."ledger_balances" (
  "account_id" uuid primary key references "better_supabase"."ledger_accounts" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "balance" bigint not null default 0,
  -- The sum of the account's active holds.
  "held" bigint not null default 0 check ("held" >= 0),
  "available" bigint generated always as ("balance" - "held") stored,
  "updated_at" timestamptz not null default now()
);
create index if not exists "ledger_balances_tenant_idx" on "better_supabase"."ledger_balances" ("tenant_id");

create table if not exists "better_supabase"."ledger_holds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null references "better_supabase"."ledger_accounts" ("id") on delete restrict,
  "amount" bigint not null check ("amount" > 0),
  "status" text not null default 'active' check ("status" in ('active', 'captured', 'released', 'expired')),
  "reference_type" text,
  "reference_id" text,
  "expires_at" timestamptz,
  "transaction_id" uuid references "better_supabase"."ledger_transactions" ("id") on delete restrict,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "ledger_holds_account_idx" on "better_supabase"."ledger_holds" ("account_id", "status");
create index if not exists "ledger_holds_transaction_idx" on "better_supabase"."ledger_holds" ("transaction_id") where "transaction_id" is not null;
create index if not exists "ledger_holds_expiry_idx" on "better_supabase"."ledger_holds" ("expires_at") where "status" = 'active' and "expires_at" is not null;

alter table "better_supabase"."ledger_accounts" enable row level security;
revoke all on "better_supabase"."ledger_accounts" from anon, authenticated;
grant select on "better_supabase"."ledger_accounts" to authenticated;
grant all on "better_supabase"."ledger_accounts" to service_role;
create index if not exists "ledger_accounts_read_permission_idx" on "better_supabase"."ledger_accounts" ("tenant_id", "read_permission") where "read_permission" is not null;
-- The (tenant, permission) pairs of account read permissions the caller
-- holds, so the policy checks each pair once per statement, not per row.
create or replace function "better_supabase"."ledger_read_grants"()
returns table (tenant uuid, permission text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select p.tenant, p.permission from (
    select distinct x."tenant_id" as tenant, x."read_permission" as permission
    from "better_supabase"."ledger_accounts" x
    where x."read_permission" is not null and x."tenant_id" in (select better_supabase.member_organization_ids())
  ) p
  where coalesce(better_supabase.can('tenant', p.tenant, p.permission), false);
end;
$$;
revoke execute on function "better_supabase"."ledger_read_grants"() from public, anon;
grant execute on function "better_supabase"."ledger_read_grants"() to authenticated, service_role;
drop policy if exists "ledger_accounts_read" on "better_supabase"."ledger_accounts";
create policy "ledger_accounts_read" on "better_supabase"."ledger_accounts" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or "owner_id" = (select auth.uid())
    or ("tenant_id", "read_permission") in (select g.tenant, g.permission from "better_supabase"."ledger_read_grants"() g));
alter table "better_supabase"."ledger_transactions" enable row level security;
revoke all on "better_supabase"."ledger_transactions" from anon, authenticated;
grant select on "better_supabase"."ledger_transactions" to authenticated;
grant all on "better_supabase"."ledger_transactions" to service_role;
drop policy if exists "ledger_transactions_read" on "better_supabase"."ledger_transactions";
create policy "ledger_transactions_read" on "better_supabase"."ledger_transactions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = "id"));
alter table "better_supabase"."ledger_entries" enable row level security;
revoke all on "better_supabase"."ledger_entries" from anon, authenticated;
grant select on "better_supabase"."ledger_entries" to authenticated;
grant all on "better_supabase"."ledger_entries" to service_role;
drop policy if exists "ledger_entries_read" on "better_supabase"."ledger_entries";
create policy "ledger_entries_read" on "better_supabase"."ledger_entries" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));
alter table "better_supabase"."ledger_balances" enable row level security;
revoke all on "better_supabase"."ledger_balances" from anon, authenticated;
grant select on "better_supabase"."ledger_balances" to authenticated;
grant all on "better_supabase"."ledger_balances" to service_role;
drop policy if exists "ledger_balances_read" on "better_supabase"."ledger_balances";
create policy "ledger_balances_read" on "better_supabase"."ledger_balances" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));
alter table "better_supabase"."ledger_holds" enable row level security;
revoke all on "better_supabase"."ledger_holds" from anon, authenticated;
grant select on "better_supabase"."ledger_holds" to authenticated;
grant all on "better_supabase"."ledger_holds" to service_role;
drop policy if exists "ledger_holds_read" on "better_supabase"."ledger_holds";
create policy "ledger_holds_read" on "better_supabase"."ledger_holds" for select to authenticated
  using ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y));

-- Entries and transactions are append-only: a reversal posts the opposite.
create or replace function "better_supabase"."ledger_append_only"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'ledger entries and transactions can''t be changed or deleted; post a reversal' using errcode = '55000', hint = 'LEDGER_APPEND_ONLY';
end;
$$;
revoke execute on function "better_supabase"."ledger_append_only"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_append_only" on "better_supabase"."ledger_entries";
create trigger "bsb_ledger_entries_append_only" before update or delete on "better_supabase"."ledger_entries"
  for each row execute function "better_supabase"."ledger_append_only"();
drop trigger if exists "bsb_ledger_transactions_append_only" on "better_supabase"."ledger_transactions";
create trigger "bsb_ledger_transactions_append_only" before update or delete on "better_supabase"."ledger_transactions"
  for each row execute function "better_supabase"."ledger_append_only"();

-- Keeps the account's balance and refuses to take an account that doesn't
-- allow it below zero (counting its holds).
create or replace function "better_supabase"."ledger_apply_entry"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_available bigint;
begin
  insert into "better_supabase"."ledger_balances" as x ("account_id", "tenant_id", "balance")
  values (new."account_id", new."tenant_id", new."amount")
  on conflict ("account_id") do update set "balance" = x."balance" + excluded."balance", "updated_at" = now()
  returning x."balance" - x."held" into v_available;
  if new."amount" < 0 and v_available < 0 and not exists (
    select 1 from "better_supabase"."ledger_accounts" y where y."id" = new."account_id" and y."allow_negative"
  ) then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ledger_apply_entry"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_apply" on "better_supabase"."ledger_entries";
create trigger "bsb_ledger_entries_apply" after insert on "better_supabase"."ledger_entries"
  for each row execute function "better_supabase"."ledger_apply_entry"();

-- At commit, the entries of each transaction sum to zero per unit.
create or replace function "better_supabase"."ledger_check_balanced"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = new."transaction_id"
    group by y."unit" having sum(y."amount") <> 0
  ) then
    raise exception 'the entries of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ledger_check_balanced"() from public, anon, authenticated;
drop trigger if exists "bsb_ledger_entries_balanced" on "better_supabase"."ledger_entries";
create constraint trigger "bsb_ledger_entries_balanced" after insert on "better_supabase"."ledger_entries"
  deferrable initially deferred
  for each row execute function "better_supabase"."ledger_check_balanced"();

-- The account with code, opened with the rest when it doesn't exist yet.
-- Modules that post to the ledger call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_account_for"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, managed_by text default null, metadata jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  select x."id" into v_id from "better_supabase"."ledger_accounts" x
    where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  if found then
    return v_id;
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "managed_by", "metadata")
  values (ledger_account_for.tenant, ledger_account_for.kind, ledger_account_for.code, ledger_account_for.name, ledger_account_for.unit,
    coalesce(ledger_account_for.scale, 0), ledger_account_for.holder_type, ledger_account_for.holder_id, ledger_account_for.owner_id,
    coalesce(ledger_account_for.allow_negative, false), ledger_account_for.read_permission, ledger_account_for.managed_by,
    coalesce(ledger_account_for.metadata, '{}'::jsonb))
  on conflict ("tenant_id", "code") do nothing
  returning "id" into v_id;
  if v_id is null then
    select x."id" into v_id from "better_supabase"."ledger_accounts" x
      where x."tenant_id" = ledger_account_for.tenant and x."code" = ledger_account_for.code;
  end if;
  return v_id;
end;
$$;
revoke execute on function "better_supabase"."ledger_account_for"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, text, jsonb) from public, anon, authenticated;

-- Posts a balanced transaction: lines is an array of {account, amount} with
-- signed integer amounts in each account's unit, summing to zero per unit.
-- With idempotency_key a second call returns the first transaction. Modules
-- that post to the ledger call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_post"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null, reverses uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if ledger_post.idempotency_key is not null then
    select x."id" into v_id from "better_supabase"."ledger_transactions" x
      where x."tenant_id" = ledger_post.tenant and x."idempotency_key" = ledger_post.idempotency_key;
    if found then
      return v_id;
    end if;
  end if;
  if ledger_post.kind is null or ledger_post.kind !~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$' then
    raise exception 'kind must be lowercase words joined by dots, such as credit.grant' using errcode = '22023', hint = 'LEDGER_KIND_INVALID';
  end if;
  if jsonb_typeof(ledger_post.lines) is distinct from 'array' or jsonb_array_length(ledger_post.lines) < 2 then
    raise exception 'a transaction needs at least two lines' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    where jsonb_typeof(l.value) is distinct from 'object'
      or coalesce(l.value ->> 'account', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(l.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
      or (l.value ->> 'amount')::bigint = 0
  ) then
    raise exception 'every line needs an account id and a non-zero integer amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    left join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
      and x."tenant_id" = ledger_post.tenant and x."closed_at" is null
    where x."id" is null
  ) then
    raise exception 'an account of the transaction doesn''t exist here or is closed' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(ledger_post.lines) l
    join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
    group by x."unit" having sum((l.value ->> 'amount')::bigint) <> 0
  ) then
    raise exception 'the lines of a ledger transaction must sum to zero per unit' using errcode = '23514', hint = 'LEDGER_UNBALANCED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_ledger_transaction_post"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using ledger_post.tenant, ledger_post.kind, ledger_post.lines;
    end if;
  end;
  insert into "better_supabase"."ledger_transactions" ("tenant_id", "kind", "reference_type", "reference_id", "memo", "idempotency_key", "reverses", "metadata", "effective_at", "actor_id")
  values (ledger_post.tenant, ledger_post.kind, ledger_post.reference_type, ledger_post.reference_id, nullif(trim(ledger_post.memo), ''),
    ledger_post.idempotency_key, ledger_post.reverses, coalesce(ledger_post.metadata, '{}'::jsonb), coalesce(ledger_post.effective_at, now()), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."ledger_entries" ("tenant_id", "transaction_id", "account_id", "amount", "unit")
  select ledger_post.tenant, v_row."id", x."id", (l.value ->> 'amount')::bigint, x."unit"
  from jsonb_array_elements(ledger_post.lines) with ordinality as l(value, n)
  join "better_supabase"."ledger_accounts" x on x."id" = (l.value ->> 'account')::uuid
  order by l.n;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_ledger_transaction_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."ledger_post"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb, uuid) from public, anon, authenticated;

-- Opens an account for the app's own use (credits, loyalty points, gift
-- cards, trust balances). code is unique per organization.
create or replace function "better_supabase"."open_ledger_account"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_ledger_account.tenant, 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."tenant_id" = open_ledger_account.tenant and x."code" = open_ledger_account.code) then
    raise exception 'an account with this code already exists' using errcode = '23505', hint = 'LEDGER_ACCOUNT_CODE_TAKEN';
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "metadata")
  values (open_ledger_account.tenant, open_ledger_account.kind, open_ledger_account.code, open_ledger_account.name, open_ledger_account.unit,
    coalesce(open_ledger_account.scale, 0), open_ledger_account.holder_type, open_ledger_account.holder_id, open_ledger_account.owner_id,
    coalesce(open_ledger_account.allow_negative, false), open_ledger_account.read_permission, coalesce(open_ledger_account.metadata, '{}'::jsonb))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$$;
revoke execute on function "better_supabase"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) from public, anon;
grant execute on function "better_supabase"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) to authenticated, service_role;

-- Closes an account with a zero balance and no active holds.
create or replace function "better_supabase"."close_ledger_account"(account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ledger_accounts" x where x."id" = close_ledger_account.account_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or v_row."owner_id" = auth.uid() or (v_row."read_permission" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", v_row."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.manage'), false)) then
    raise exception 'not allowed to manage ledger accounts' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_row."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_row."id" for update;
  if coalesce(v_balance."balance", 0) <> 0 or coalesce(v_balance."held", 0) <> 0 then
    raise exception 'only an account with a zero balance and no holds can be closed' using errcode = '55000', hint = 'LEDGER_ACCOUNT_NOT_EMPTY';
  end if;
  if v_row."closed_at" is null then
    update "better_supabase"."ledger_accounts" x set "closed_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'code', v_row."code", 'name', v_row."name", 'unit', v_row."unit", 'scale', v_row."scale", 'holderType', v_row."holder_type", 'holderId', v_row."holder_id", 'ownerId', v_row."owner_id", 'allowNegative', v_row."allow_negative", 'readPermission', v_row."read_permission", 'managedBy', v_row."managed_by", 'metadata', v_row."metadata", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'balance', coalesce(v_balance."balance", 0)::text, 'held', coalesce(v_balance."held", 0)::text, 'available', coalesce(v_balance."balance" - v_balance."held", 0)::text);
end;
$$;
revoke execute on function "better_supabase"."close_ledger_account"(uuid) from public, anon;
grant execute on function "better_supabase"."close_ledger_account"(uuid) to authenticated, service_role;

-- Posts a balanced transaction to the app's own accounts. Accounts a block
-- manages (stock, leave, receivables) only move through that block.
create or replace function "better_supabase"."post_ledger_transaction"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_ledger_transaction.tenant, 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if jsonb_typeof(post_ledger_transaction.lines) = 'array' and exists (
    select 1 from jsonb_array_elements(post_ledger_transaction.lines) l
    join "better_supabase"."ledger_accounts" x on x."id"::text = l.value ->> 'account'
    where x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_id := "better_supabase"."ledger_post"(post_ledger_transaction.tenant, post_ledger_transaction.kind, post_ledger_transaction.lines,
    post_ledger_transaction.reference_type, post_ledger_transaction.reference_id, post_ledger_transaction.memo,
    post_ledger_transaction.idempotency_key, post_ledger_transaction.effective_at, post_ledger_transaction.metadata);
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) from public, anon;
grant execute on function "better_supabase"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) to authenticated, service_role;

-- Posts the opposite of a transaction. A transaction is reversed at most
-- once, and a reversal can't be reversed.
create or replace function "better_supabase"."reverse_ledger_transaction"(transaction_id uuid, memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old "better_supabase"."ledger_transactions"%rowtype;
  v_row "better_supabase"."ledger_transactions"%rowtype;
  v_id uuid;
begin
  select * into v_old from "better_supabase"."ledger_transactions" x where x."id" = reverse_ledger_transaction.transaction_id;
  if not found then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_old."id" and x."managed_by" is not null
  ) then
    raise exception 'an account of the transaction belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  if v_old."reverses" is not null
    or exists (select 1 from "better_supabase"."ledger_transactions" x where x."reverses" = v_old."id") then
    raise exception 'this transaction is a reversal or is already reversed' using errcode = '55000', hint = 'LEDGER_ALREADY_REVERSED';
  end if;
  v_id := "better_supabase"."ledger_post"(v_old."tenant_id", v_old."kind",
    (select jsonb_agg(jsonb_build_object('account', y."account_id", 'amount', (-y."amount")::text) order by y."created_at", y."id")
      from "better_supabase"."ledger_entries" y where y."transaction_id" = v_old."id"),
    v_old."reference_type", v_old."reference_id", coalesce(reverse_ledger_transaction.memo, v_old."memo"),
    null, null, v_old."metadata", v_old."id");
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = v_id;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."reverse_ledger_transaction"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reverse_ledger_transaction"(uuid, text) to authenticated, service_role;

-- Sets aside part of an account's available balance until it is captured,
-- released or expires, without checking the caller. Modules that hold
-- amounts on their own accounts call it; it isn't granted to anyone.
create or replace function "better_supabase"."ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_balance "better_supabase"."ledger_balances"%rowtype;
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if ledger_hold.amount is null or ledger_hold.amount <= 0 then
    raise exception 'a hold needs an amount greater than zero' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  insert into "better_supabase"."ledger_balances" ("account_id", "tenant_id") values (v_account."id", v_account."tenant_id")
    on conflict ("account_id") do nothing;
  select * into v_balance from "better_supabase"."ledger_balances" x where x."account_id" = v_account."id" for update;
  if not v_account."allow_negative" and v_balance."balance" - v_balance."held" < ledger_hold.amount then
    raise exception 'the account doesn''t have enough available' using errcode = '23514', hint = 'LEDGER_INSUFFICIENT';
  end if;
  update "better_supabase"."ledger_balances" x set "held" = x."held" + ledger_hold.amount, "updated_at" = now()
    where x."account_id" = v_account."id";
  insert into "better_supabase"."ledger_holds" ("tenant_id", "account_id", "amount", "reference_type", "reference_id", "expires_at", "created_by")
  values (v_account."tenant_id", v_account."id", ledger_hold.amount, ledger_hold.reference_type, ledger_hold.reference_id, ledger_hold.expires_at, auth.uid())
  returning * into v_row;
  null;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon, authenticated;

create or replace function "better_supabase"."place_ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = place_ledger_hold.account_id;
  if not found or v_account."closed_at" is not null then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if v_account."managed_by" is not null and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "better_supabase"."ledger_hold"(place_ledger_hold.account_id, place_ledger_hold.amount, place_ledger_hold.reference_type, place_ledger_hold.reference_id, place_ledger_hold.expires_at);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) to authenticated, service_role;

-- Frees an active hold: release by a caller, expire from expire_ledger_holds.
create or replace function "better_supabase"."ledger_unhold"(hold_id uuid, status text)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = ledger_unhold.hold_id for update;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'this hold is no longer active' using errcode = '55000', hint = 'LEDGER_HOLD_CLOSED';
  end if;
  update "better_supabase"."ledger_balances" x set "held" = x."held" - v_row."amount", "updated_at" = now()
    where x."account_id" = v_row."account_id";
  update "better_supabase"."ledger_holds" x set "status" = ledger_unhold.status, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_unhold"(uuid, text) from public, anon, authenticated;

-- Captures a hold without checking the caller: frees it and posts amount
-- (default all of it) from the held account to to_account. Modules call it;
-- it isn't granted to anyone.
create or replace function "better_supabase"."ledger_capture"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
  v_amount bigint;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = ledger_capture.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  v_amount := coalesce(ledger_capture.amount, v_row."amount");
  if v_amount <= 0 or v_amount > v_row."amount" then
    raise exception 'a capture takes more than zero and at most the held amount' using errcode = '22023', hint = 'LEDGER_LINES_INVALID';
  end if;
  v_row := "better_supabase"."ledger_unhold"(v_row."id", 'captured');
  update "better_supabase"."ledger_holds" x set "transaction_id" = "better_supabase"."ledger_post"(v_row."tenant_id", coalesce(ledger_capture.kind, 'ledger.capture'),
      jsonb_build_array(
        jsonb_build_object('account', v_row."account_id", 'amount', (-v_amount)::text),
        jsonb_build_object('account', ledger_capture.to_account, 'amount', v_amount::text)),
      v_row."reference_type", v_row."reference_id", ledger_capture.memo)
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_capture"(uuid, uuid, bigint, text, text) from public, anon, authenticated;

create or replace function "better_supabase"."capture_ledger_hold"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = capture_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" x where x."id" = capture_ledger_hold.to_account and x."managed_by" is not null) and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'this account belongs to another block' using errcode = '55000', hint = 'LEDGER_ACCOUNT_MANAGED';
  end if;
  v_row := "better_supabase"."ledger_capture"(v_row."id", capture_ledger_hold.to_account, capture_ledger_hold.amount, capture_ledger_hold.kind, capture_ledger_hold.memo);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."capture_ledger_hold"(uuid, uuid, bigint, text, text) from public, anon;
grant execute on function "better_supabase"."capture_ledger_hold"(uuid, uuid, bigint, text, text) to authenticated, service_role;

-- Releases an active hold without checking the caller. Modules call it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."ledger_release"(hold_id uuid)
returns "better_supabase"."ledger_holds"
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  v_row := "better_supabase"."ledger_unhold"(ledger_release.hold_id, 'released');
  null;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."ledger_release"(uuid) from public, anon, authenticated;

create or replace function "better_supabase"."release_ledger_hold"(hold_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_holds"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_holds" x where x."id" = release_ledger_hold.hold_id;
  if not found then
    raise exception 'ledger hold not found' using errcode = 'P0002', hint = 'LEDGER_HOLD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.post'), false)) then
    raise exception 'not allowed to post ledger transactions' using errcode = '42501', hint = 'LEDGER_FORBIDDEN';
  end if;
  v_row := "better_supabase"."ledger_release"(v_row."id");
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'amount', v_row."amount"::text, 'status', v_row."status", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'expiresAt', v_row."expires_at", 'transactionId', v_row."transaction_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."release_ledger_hold"(uuid) from public, anon;
grant execute on function "better_supabase"."release_ledger_hold"(uuid) to authenticated, service_role;

-- Releases the active holds past expires_at; a scheduled job runs it.
-- Returns how many it expired.
create or replace function "better_supabase"."expire_ledger_holds"(max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."ledger_holds"%rowtype;
  v_count integer := 0;
begin
  for v_id in
    select x."id" from "better_supabase"."ledger_holds" x
    where x."status" = 'active' and x."expires_at" <= now()
    order by x."expires_at"
    limit least(greatest(coalesce(expire_ledger_holds.max_rows, 500), 1), 5000)
    for update skip locked
  loop
    v_row := "better_supabase"."ledger_unhold"(v_id, 'expired');
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_ledger_holds"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_ledger_holds"(integer) to service_role;

-- The accounts the caller can read, with their balances: every account with
-- the read permission, else the caller's own and those a read permission of
-- another block grants. Without a tenant it lists a holder's accounts in
-- every tenant the caller can read them in.
create or replace function "better_supabase"."list_ledger_accounts"(tenant uuid, kind text default null, holder_type text default null, holder_id text default null, page_size integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.code), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'code', x."code", 'name', x."name", 'unit', x."unit", 'scale', x."scale", 'holderType', x."holder_type", 'holderId', x."holder_id", 'ownerId', x."owner_id", 'allowNegative', x."allow_negative", 'readPermission', x."read_permission", 'managedBy', x."managed_by", 'metadata', x."metadata", 'closedAt', x."closed_at", 'createdAt', x."created_at", 'balance', coalesce(y."balance", 0)::text, 'held', coalesce(y."held", 0)::text, 'available', coalesce(y."balance" - y."held", 0)::text) as item, x."code" as code
    from "better_supabase"."ledger_accounts" x
    left join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
    where (list_ledger_accounts.tenant is null or x."tenant_id" = list_ledger_accounts.tenant)
      and (list_ledger_accounts.kind is null or x."kind" = list_ledger_accounts.kind)
      and (list_ledger_accounts.holder_type is null or x."holder_type" = list_ledger_accounts.holder_type)
      and (list_ledger_accounts.holder_id is null or x."holder_id" = list_ledger_accounts.holder_id)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
    order by x."code"
    limit least(greatest(coalesce(list_ledger_accounts.page_size, 100), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_ledger_accounts"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_ledger_accounts"(uuid, text, text, text, integer) to authenticated, service_role;

-- An account's entries, newest first, with the transaction each belongs to.
-- before pages back from an entry's created_at.
create or replace function "better_supabase"."ledger_account_entries"(account_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."ledger_accounts"%rowtype;
  v_rows jsonb;
begin
  select * into v_account from "better_supabase"."ledger_accounts" x where x."id" = ledger_account_entries.account_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_account."tenant_id", 'ledger.read'), false) or v_account."owner_id" = auth.uid() or (v_account."read_permission" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", v_account."read_permission"), false))) then
    raise exception 'ledger account not found' using errcode = 'P0002', hint = 'LEDGER_ACCOUNT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit",
        'transactionId', r."id", 'kind', r."kind", 'referenceType', r."reference_type", 'referenceId', r."reference_id",
        'memo', r."memo", 'reverses', r."reverses", 'metadata', r."metadata", 'effectiveAt', r."effective_at", 'createdAt', y."created_at") as item,
      y."created_at" as created, y."id" as id
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where y."account_id" = v_account."id"
      and (ledger_account_entries.before is null or y."created_at" < ledger_account_entries.before)
    order by y."created_at" desc, y."id" desc
    limit least(greatest(coalesce(ledger_account_entries.page_size, 50), 1), 500)
  ) z;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."ledger_account_entries"(uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."ledger_account_entries"(uuid, timestamptz, integer) to authenticated, service_role;

-- One transaction with its entries, for a caller who can read one of its
-- accounts.
create or replace function "better_supabase"."get_ledger_transaction"(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."ledger_transactions"%rowtype;
begin
  select * into v_row from "better_supabase"."ledger_transactions" x where x."id" = get_ledger_transaction.transaction_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false) or exists (
    select 1 from "better_supabase"."ledger_entries" y join "better_supabase"."ledger_accounts" x on x."id" = y."account_id"
    where y."transaction_id" = v_row."id" and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false) or x."owner_id" = auth.uid() or (x."read_permission" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", x."read_permission"), false)))
  )) then
    raise exception 'ledger transaction not found' using errcode = 'P0002', hint = 'LEDGER_TRANSACTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'referenceType', v_row."reference_type", 'referenceId', v_row."reference_id", 'memo', v_row."memo", 'idempotencyKey', v_row."idempotency_key", 'reverses', v_row."reverses", 'metadata', v_row."metadata", 'effectiveAt', v_row."effective_at", 'actorId', v_row."actor_id", 'createdAt', v_row."created_at", 'entries', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'accountId', y."account_id", 'amount', y."amount"::text, 'unit', y."unit") order by y."created_at", y."id") from "better_supabase"."ledger_entries" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_ledger_transaction"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ledger_transaction"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_accounts";
create policy bsb_tenant_scope on "better_supabase"."ledger_accounts" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or "owner_id" = (select auth.uid())
    or ("tenant_id", "read_permission") in (select g.tenant, g.permission from "better_supabase"."ledger_read_grants"() g))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_transactions";
create policy bsb_tenant_scope on "better_supabase"."ledger_transactions" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('ledger.read'))
    or exists (select 1 from "better_supabase"."ledger_entries" y where y."transaction_id" = "id"))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_entries";
create policy bsb_tenant_scope on "better_supabase"."ledger_entries" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_balances";
create policy bsb_tenant_scope on "better_supabase"."ledger_balances" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."ledger_holds";
create policy bsb_tenant_scope on "better_supabase"."ledger_holds" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("account_id" in (select y."id" from "better_supabase"."ledger_accounts" y))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.ledger.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."ledger_read_grants"();

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

create or replace function "api"."open_ledger_account"(tenant uuid, kind text, code text, name text, unit text, scale smallint default 0, holder_type text default null, holder_id text default null, owner_id uuid default null, allow_negative boolean default false, read_permission text default null, metadata jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_ledger_account"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $$;
revoke execute on function "api"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) from public, anon;
grant execute on function "api"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) to authenticated, service_role;

create or replace function "api"."close_ledger_account"(account_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_ledger_account"($1) $$;
revoke execute on function "api"."close_ledger_account"(uuid) from public, anon;
grant execute on function "api"."close_ledger_account"(uuid) to authenticated, service_role;

create or replace function "api"."post_ledger_transaction"(tenant uuid, kind text, lines jsonb, reference_type text default null, reference_id text default null, memo text default null, idempotency_key text default null, effective_at timestamptz default null, metadata jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."post_ledger_transaction"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) from public, anon;
grant execute on function "api"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamptz, jsonb) to authenticated, service_role;

create or replace function "api"."reverse_ledger_transaction"(transaction_id uuid, memo text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reverse_ledger_transaction"($1, $2) $$;
revoke execute on function "api"."reverse_ledger_transaction"(uuid, text) from public, anon;
grant execute on function "api"."reverse_ledger_transaction"(uuid, text) to authenticated, service_role;

create or replace function "api"."place_ledger_hold"(account_id uuid, amount bigint, reference_type text default null, reference_id text default null, expires_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."place_ledger_hold"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) from public, anon;
grant execute on function "api"."place_ledger_hold"(uuid, bigint, text, text, timestamptz) to authenticated, service_role;

create or replace function "api"."capture_ledger_hold"(hold_id uuid, to_account uuid, amount bigint default null, kind text default 'ledger.capture', memo text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."capture_ledger_hold"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."capture_ledger_hold"(uuid, uuid, bigint, text, text) from public, anon;
grant execute on function "api"."capture_ledger_hold"(uuid, uuid, bigint, text, text) to authenticated, service_role;

create or replace function "api"."release_ledger_hold"(hold_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_ledger_hold"($1) $$;
revoke execute on function "api"."release_ledger_hold"(uuid) from public, anon;
grant execute on function "api"."release_ledger_hold"(uuid) to authenticated, service_role;

create or replace function "api"."expire_ledger_holds"(max_rows integer default 500)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_ledger_holds"($1) $$;
revoke execute on function "api"."expire_ledger_holds"(integer) from public, anon, authenticated;
grant execute on function "api"."expire_ledger_holds"(integer) to service_role;

create or replace function "api"."list_ledger_accounts"(tenant uuid, kind text default null, holder_type text default null, holder_id text default null, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ledger_accounts"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_ledger_accounts"(uuid, text, text, text, integer) from public, anon;
grant execute on function "api"."list_ledger_accounts"(uuid, text, text, text, integer) to authenticated, service_role;

create or replace function "api"."ledger_account_entries"(account_id uuid, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ledger_account_entries"($1, $2, $3) $$;
revoke execute on function "api"."ledger_account_entries"(uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."ledger_account_entries"(uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."get_ledger_transaction"(transaction_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ledger_transaction"($1) $$;
revoke execute on function "api"."get_ledger_transaction"(uuid) from public, anon;
grant execute on function "api"."get_ledger_transaction"(uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_80_ledger.sql
-- better-supabase module: ledger
-- @bsb-block-data ledger
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ledger', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
