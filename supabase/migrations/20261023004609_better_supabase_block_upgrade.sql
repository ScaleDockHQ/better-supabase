-- better-supabase upgrade: steps that run before the schema diff.

-- admission-passes: version 1 to 2. Moves class credits from pass_credit_entries onto the ledger block.
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

do $upgrade$
begin
  if to_regclass('better_supabase.pass_credit_entries') is null then
    return;
  end if;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "holder_type", "holder_id", "owner_id", "allow_negative", "read_permission", "managed_by", "metadata")
  select distinct m.tenant_id, 'pass_credits', 'pass:' || m.pass_id::text, 'Pass credits', 'credit', 0, 'passes', m.pass_id::text, x."holder_user_id", true, 'passes.read', 'admission-passes',
    jsonb_build_object('passId', m.pass_id)
  from "better_supabase".pass_credit_entries m join "better_supabase"."passes" x on x."id" = m.pass_id
  on conflict do nothing;
  insert into "better_supabase"."ledger_accounts" ("tenant_id", "kind", "code", "name", "unit", "scale", "allow_negative", "read_permission", "managed_by")
  select distinct m.tenant_id, 'pass_credits_pool', 'pass-credits:pool', 'Pass credits pool', 'credit', 0, true, 'passes.read', 'admission-passes'
  from "better_supabase".pass_credit_entries m
  on conflict do nothing;
  insert into "better_supabase"."ledger_transactions" ("id", "tenant_id", "kind", "reference_type", "reference_id", "idempotency_key", "metadata", "effective_at", "actor_id", "created_at")
  select m.id, m.tenant_id, case when m.reason = 'booking' then 'pass.credit_used' else 'pass.credit_refunded' end,
    case when m.booking_id is not null then 'bookings' end, m.booking_id::text,
    case when m.booking_id is not null then 'pass-credit:' || m.booking_id::text || ':' || m.reason end,
    jsonb_build_object('passId', m.pass_id, 'reason', m.reason), m.created_at, m.created_by, m.created_at
  from "better_supabase".pass_credit_entries m
  on conflict do nothing;
  insert into "better_supabase"."ledger_entries" ("tenant_id", "transaction_id", "account_id", "amount", "unit", "created_at")
  select m.tenant_id, m.id, x."id", m.delta, 'credit', m.created_at
  from "better_supabase".pass_credit_entries m join "better_supabase"."ledger_accounts" x on x."tenant_id" = m.tenant_id and x."code" = 'pass:' || m.pass_id::text
  union all
  select m.tenant_id, m.id, x."id", -m.delta, 'credit', m.created_at
  from "better_supabase".pass_credit_entries m join "better_supabase"."ledger_accounts" x on x."tenant_id" = m.tenant_id and x."code" = 'pass-credits:pool';
  insert into "better_supabase"."ledger_balances" as x ("account_id", "tenant_id", "balance", "held")
select s.account, s.tenant, s.balance, coalesce((select sum(y."amount") from "better_supabase"."ledger_holds" y where y."account_id" = s.account and y."status" = 'active'), 0)
from (
  select z."account_id" as account, min(z."tenant_id"::text)::uuid as tenant, sum(z."amount") as balance
  from "better_supabase"."ledger_entries" z group by z."account_id"
) s
on conflict ("account_id") do update set "balance" = excluded."balance", "held" = excluded."held", "updated_at" = now();
  drop trigger if exists pass_credit_entries_refund on "better_supabase"."bookings";
  drop table "better_supabase".pass_credit_entries;
end;
$upgrade$;

-- leases: version 1 to 2. Drops the maintenance request functions and renames maintenance_requests to maintenance_requests_legacy for a tasks instance to take over.
alter table if exists "better_supabase".maintenance_requests rename to maintenance_requests_legacy;
drop function if exists "better_supabase"."file_maintenance_request"(uuid, uuid, text, text, text, uuid);
drop function if exists "better_supabase"."update_maintenance_request"(uuid, text, text, uuid);
drop function if exists "better_supabase"."list_maintenance_requests"(uuid, uuid, uuid, text, integer);

-- donations: version 1 to 2. Numbers receipts with the numbering block, starting after each organization's highest receipt.
create table if not exists "better_supabase"."number_sequences" (
  "tenant_id" uuid not null,
  "entity" text not null,
  "period" text not null default '',
  "last_number" bigint not null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "entity", "period")
);
alter table "better_supabase"."number_sequences" enable row level security;
revoke all on "better_supabase"."number_sequences" from anon, authenticated;
grant all on "better_supabase"."number_sequences" to service_role;

insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "period", "last_number")
select r."tenant_id", 'donation_receipt', '', max(r."sequence")
from "better_supabase"."donation_receipts" r
group by r."tenant_id"
on conflict ("tenant_id", "entity", "period")
do update set "last_number" = greatest("better_supabase"."number_sequences"."last_number", excluded."last_number");
