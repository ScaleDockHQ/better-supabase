-- ==== schema supabase/schemas/900_better_supabase_146_accounting.sql
-- better-supabase module: accounting
-- @bsb-block accounting@1 managed
-- @bsb-hash sha256:2f4004b70edf2b998c22b2498c1edd9070b4df876e50baf23b0e338a390c9873
-- Double-entry books: a chart of accounts with account roles, journals, fiscal years of periods, balanced journal entries numbered per journal and year, dimensions, exchange rates, tax codes, the trial balance, profit and loss, balance sheet and general ledger, the period and year-end close, entries booked from invoices, expenses, stock, rent and gifts, tax reports and budgets.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_settings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_settings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_settings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_settings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_settings";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_accounts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_accounts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_accounts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_accounts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_accounts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_account_roles";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_account_roles";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_account_roles";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_account_roles";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_account_roles";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_journals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_journals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_journals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_journals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_journals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_periods";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_periods";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_periods";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_periods";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_periods";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_entries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_entries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_entries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_entries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_entry_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_entry_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_entry_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_entry_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_entry_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_dimensions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_dimensions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_dimensions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_dimensions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_dimensions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_dimension_values";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_dimension_values";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_dimension_values";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_dimension_values";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_dimension_values";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_fx_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_fx_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_fx_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_fx_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_fx_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_tax_codes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_tax_codes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_tax_codes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_tax_codes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_tax_codes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_budgets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_budgets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_budgets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_budgets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_budgets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_budget_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_budget_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_budget_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_budget_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_budget_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Accounting: a chart of accounts with roles, journals, fiscal periods, and
-- balanced journal entries in minor units of the organization's functional
-- currency, with dimensions, exchange rates, tax codes, reports and the
-- period and year-end close, the documents other blocks book, tax reports
-- and budgets.

create table if not exists "better_supabase"."accounting_settings" (
  "tenant_id" uuid primary key,
  -- Every debit and credit is in minor units of this currency.
  "functional_currency" text not null check ("functional_currency" ~ '^[A-Z]{3}$'),
  "fiscal_year_start_month" smallint not null default 1 check ("fiscal_year_start_month" >= 1 and "fiscal_year_start_month" <= 12),
  -- Nothing posts on or before this date, whatever the period's status.
  "lock_date" date,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."accounting_settings" enable row level security;
revoke all on "better_supabase"."accounting_settings" from public, anon, authenticated;
grant select on "better_supabase"."accounting_settings" to authenticated;
grant all on "better_supabase"."accounting_settings" to service_role;
drop policy if exists accounting_settings_read on "better_supabase"."accounting_settings";
create policy accounting_settings_read on "better_supabase"."accounting_settings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null check (length("code") >= 1 and length("code") <= 50),
  "name" text not null check (length("name") >= 1 and length("name") <= 200),
  "type" text not null check ("type" in ('asset', 'liability', 'equity', 'income', 'expense')),
  "subtype" text,
  "parent_id" uuid references "better_supabase"."accounting_accounts" ("id") on delete restrict,
  -- Lines on the account must be in this currency; null takes any.
  "currency" text check ("currency" ~ '^[A-Z]{3}$'),
  "reconcilable" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
create index if not exists "accounting_accounts_parent_idx" on "better_supabase"."accounting_accounts" ("parent_id") where "parent_id" is not null;
alter table "better_supabase"."accounting_accounts" enable row level security;
revoke all on "better_supabase"."accounting_accounts" from public, anon, authenticated;
grant select on "better_supabase"."accounting_accounts" to authenticated;
grant all on "better_supabase"."accounting_accounts" to service_role;
drop policy if exists accounting_accounts_read on "better_supabase"."accounting_accounts";
create policy accounting_accounts_read on "better_supabase"."accounting_accounts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_account_roles" (
  "tenant_id" uuid not null,
  "role" text not null check ("role" in ('receivable', 'payable', 'bank', 'revenue', 'cogs', 'inventory', 'work_in_progress', 'tax_payable', 'tax_receivable', 'retained_earnings', 'fx_gain', 'fx_loss', 'fixed_asset', 'accumulated_depreciation', 'depreciation_expense', 'disposal_gain', 'disposal_loss', 'expense', 'suspense')),
  "account_id" uuid not null references "better_supabase"."accounting_accounts" ("id") on delete restrict,
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "role")
);
create index if not exists "accounting_account_roles_account_idx" on "better_supabase"."accounting_account_roles" ("account_id");
alter table "better_supabase"."accounting_account_roles" enable row level security;
revoke all on "better_supabase"."accounting_account_roles" from public, anon, authenticated;
grant select on "better_supabase"."accounting_account_roles" to authenticated;
grant all on "better_supabase"."accounting_account_roles" to service_role;
drop policy if exists accounting_account_roles_read on "better_supabase"."accounting_account_roles";
create policy accounting_account_roles_read on "better_supabase"."accounting_account_roles"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_journals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null check ("code" ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'),
  "name" text not null check (length("name") >= 1 and length("name") <= 200),
  "type" text not null check ("type" in ('sales', 'purchase', 'bank', 'cash', 'general')),
  -- The bank or cash account a bank or cash journal posts against.
  "default_account_id" uuid references "better_supabase"."accounting_accounts" ("id") on delete restrict,
  "currency" text check ("currency" ~ '^[A-Z]{3}$'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
create index if not exists "accounting_journals_account_idx" on "better_supabase"."accounting_journals" ("default_account_id") where "default_account_id" is not null;
alter table "better_supabase"."accounting_journals" enable row level security;
revoke all on "better_supabase"."accounting_journals" from public, anon, authenticated;
grant select on "better_supabase"."accounting_journals" to authenticated;
grant all on "better_supabase"."accounting_journals" to service_role;
drop policy if exists accounting_journals_read on "better_supabase"."accounting_journals";
create policy accounting_journals_read on "better_supabase"."accounting_journals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_periods" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The calendar year the fiscal year starts in.
  "fiscal_year" integer not null check ("fiscal_year" >= 1900 and "fiscal_year" <= 9999),
  "number" smallint not null check ("number" >= 1 and "number" <= 12),
  "starts_on" date not null,
  "ends_on" date not null,
  "status" text not null default 'open' check ("status" in ('open', 'closed')),
  "closed_at" timestamptz,
  "closed_by" uuid,
  "created_at" timestamptz not null default now(),
  check ("ends_on" >= "starts_on"),
  unique ("tenant_id", "fiscal_year", "number")
);
create index if not exists "accounting_periods_dates_idx" on "better_supabase"."accounting_periods" ("tenant_id", "starts_on", "ends_on");
alter table "better_supabase"."accounting_periods" enable row level security;
revoke all on "better_supabase"."accounting_periods" from public, anon, authenticated;
grant select on "better_supabase"."accounting_periods" to authenticated;
grant all on "better_supabase"."accounting_periods" to service_role;
drop policy if exists accounting_periods_read on "better_supabase"."accounting_periods";
create policy accounting_periods_read on "better_supabase"."accounting_periods"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "journal_id" uuid not null references "better_supabase"."accounting_journals" ("id") on delete restrict,
  "fiscal_year" integer,
  -- The entry's place in its journal and fiscal year, set when it posts.
  "sequence" integer,
  "number" text,
  "entry_date" date not null,
  "period_id" uuid references "better_supabase"."accounting_periods" ("id") on delete restrict,
  "status" text not null default 'draft' check ("status" in ('draft', 'posted', 'reversed')),
  "reference" text check ("reference" is null or length("reference") <= 200),
  -- The document the entry books, such as invoice and its id.
  "source_type" text check ("source_type" is null or "source_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "source_id" text,
  "reverses_id" uuid references "better_supabase"."accounting_entries" ("id") on delete restrict,
  "memo" text check ("memo" is null or length("memo") <= 2000),
  "posted_at" timestamptz,
  "posted_by" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("source_type" is null) = ("source_id" is null)),
  check ("status" = 'draft' or ("number" is not null and "period_id" is not null and "posted_at" is not null))
);
alter table "better_supabase"."accounting_entries" add column if not exists "app_note" text;
create unique index if not exists "accounting_entries_number_idx" on "better_supabase"."accounting_entries" ("journal_id", "fiscal_year", "sequence") where "sequence" is not null;
-- A document books once: a second entry for it waits until the first is reversed.
create unique index if not exists "accounting_entries_source_idx" on "better_supabase"."accounting_entries" ("tenant_id", "source_type", "source_id") where "source_type" is not null and "status" <> 'reversed';
create unique index if not exists "accounting_entries_reverses_idx" on "better_supabase"."accounting_entries" ("reverses_id") where "reverses_id" is not null;
create index if not exists "accounting_entries_date_idx" on "better_supabase"."accounting_entries" ("tenant_id", "entry_date" desc);
create index if not exists "accounting_entries_period_idx" on "better_supabase"."accounting_entries" ("period_id", "status");
alter table "better_supabase"."accounting_entries" enable row level security;
revoke all on "better_supabase"."accounting_entries" from public, anon, authenticated;
grant select on "better_supabase"."accounting_entries" to authenticated;
grant all on "better_supabase"."accounting_entries" to service_role;
drop policy if exists accounting_entries_read on "better_supabase"."accounting_entries";
create policy accounting_entries_read on "better_supabase"."accounting_entries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_dimensions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The key lines use in their dimensions object, such as project or department.
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") >= 1 and length("name") <= 200),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "better_supabase"."accounting_dimensions" enable row level security;
revoke all on "better_supabase"."accounting_dimensions" from public, anon, authenticated;
grant select on "better_supabase"."accounting_dimensions" to authenticated;
grant all on "better_supabase"."accounting_dimensions" to service_role;
drop policy if exists accounting_dimensions_read on "better_supabase"."accounting_dimensions";
create policy accounting_dimensions_read on "better_supabase"."accounting_dimensions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_dimension_values" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "dimension_id" uuid not null references "better_supabase"."accounting_dimensions" ("id") on delete cascade,
  "code" text not null check (length("code") >= 1 and length("code") <= 100),
  "name" text not null check (length("name") >= 1 and length("name") <= 200),
  "archived_at" timestamptz,
  unique ("dimension_id", "code")
);
alter table "better_supabase"."accounting_dimension_values" enable row level security;
revoke all on "better_supabase"."accounting_dimension_values" from public, anon, authenticated;
grant select on "better_supabase"."accounting_dimension_values" to authenticated;
grant all on "better_supabase"."accounting_dimension_values" to service_role;
drop policy if exists accounting_dimension_values_read on "better_supabase"."accounting_dimension_values";
create policy accounting_dimension_values_read on "better_supabase"."accounting_dimension_values"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_fx_rates" (
  "tenant_id" uuid not null,
  "base" text not null check ("base" ~ '^[A-Z]{3}$'),
  "quote" text not null check ("quote" ~ '^[A-Z]{3}$'),
  "on_date" date not null,
  -- One unit of base costs rate units of quote.
  "rate" numeric not null check ("rate" > 0),
  "created_at" timestamptz not null default now(),
  primary key ("tenant_id", "base", "quote", "on_date"),
  check ("base" <> "quote")
);
alter table "better_supabase"."accounting_fx_rates" enable row level security;
revoke all on "better_supabase"."accounting_fx_rates" from public, anon, authenticated;
grant select on "better_supabase"."accounting_fx_rates" to authenticated;
grant all on "better_supabase"."accounting_fx_rates" to service_role;
drop policy if exists accounting_fx_rates_read on "better_supabase"."accounting_fx_rates";
create policy accounting_fx_rates_read on "better_supabase"."accounting_fx_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_tax_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null check (length("code") >= 1 and length("code") <= 50),
  "name" text not null check (length("name") >= 1 and length("name") <= 200),
  -- Basis points: 2100 is 21%.
  "rate_bps" integer not null check ("rate_bps" >= 0 and "rate_bps" <= 100000),
  "kind" text not null check ("kind" in ('sales', 'purchase')),
  "account_id" uuid not null references "better_supabase"."accounting_accounts" ("id") on delete restrict,
  -- The boxes of a tax return the tax and its base count toward.
  "report_boxes" text[] not null default '{}',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
create index if not exists "accounting_tax_codes_account_idx" on "better_supabase"."accounting_tax_codes" ("account_id");
alter table "better_supabase"."accounting_tax_codes" enable row level security;
revoke all on "better_supabase"."accounting_tax_codes" from public, anon, authenticated;
grant select on "better_supabase"."accounting_tax_codes" to authenticated;
grant all on "better_supabase"."accounting_tax_codes" to service_role;
drop policy if exists accounting_tax_codes_read on "better_supabase"."accounting_tax_codes";
create policy accounting_tax_codes_read on "better_supabase"."accounting_tax_codes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_entry_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "entry_id" uuid not null references "better_supabase"."accounting_entries" ("id") on delete cascade,
  "position" smallint not null default 0,
  "account_id" uuid not null references "better_supabase"."accounting_accounts" ("id") on delete restrict,
  -- Minor units of the functional currency; a line has one side.
  "debit" bigint not null default 0 check ("debit" >= 0),
  "credit" bigint not null default 0 check ("credit" >= 0),
  -- The transaction currency and its signed amount (positive is a debit).
  "currency" text not null check ("currency" ~ '^[A-Z]{3}$'),
  "amount_currency" bigint not null,
  "fx_rate" numeric check ("fx_rate" is null or "fx_rate" > 0),
  "tax_code_id" uuid references "better_supabase"."accounting_tax_codes" ("id") on delete restrict,
  -- The customer, supplier or employee the line concerns.
  "party_id" uuid,
  "dimensions" jsonb not null default '{}'::jsonb check (jsonb_typeof("dimensions") = 'object'),
  "description" text check ("description" is null or length("description") <= 500),
  check (("debit" = 0) <> ("credit" = 0))
);
create index if not exists "accounting_entry_lines_entry_idx" on "better_supabase"."accounting_entry_lines" ("entry_id", "position");
create index if not exists "accounting_entry_lines_account_idx" on "better_supabase"."accounting_entry_lines" ("account_id");
create index if not exists "accounting_entry_lines_party_idx" on "better_supabase"."accounting_entry_lines" ("tenant_id", "party_id") where "party_id" is not null;
create index if not exists "accounting_entry_lines_tax_idx" on "better_supabase"."accounting_entry_lines" ("tax_code_id") where "tax_code_id" is not null;
alter table "better_supabase"."accounting_entry_lines" enable row level security;
revoke all on "better_supabase"."accounting_entry_lines" from public, anon, authenticated;
grant select on "better_supabase"."accounting_entry_lines" to authenticated;
grant all on "better_supabase"."accounting_entry_lines" to service_role;
drop policy if exists accounting_entry_lines_read on "better_supabase"."accounting_entry_lines";
create policy accounting_entry_lines_read on "better_supabase"."accounting_entry_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

-- A posted entry changes only from posted to reversed; its lines never change.
create or replace function "better_supabase"."accounting_entry_guard"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old."status" = 'draft' then
    return new;
  end if;
  if tg_op = 'DELETE' and old."status" = 'draft' then
    return old;
  end if;
  if tg_op = 'UPDATE' and old."status" = 'posted' and new."status" = 'reversed'
    and (to_jsonb(new) - 'status' - 'updated_at')
      = (to_jsonb(old) - 'status' - 'updated_at') then
    return new;
  end if;
  raise exception 'a posted entry can''t be changed or deleted; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
end;
$$;
revoke execute on function "better_supabase"."accounting_entry_guard"() from public, anon, authenticated;
drop trigger if exists "bsb_accounting_entries_guard" on "better_supabase"."accounting_entries";
create trigger "bsb_accounting_entries_guard" before update or delete on "better_supabase"."accounting_entries"
  for each row execute function "better_supabase"."accounting_entry_guard"('tenant_id');

create or replace function "better_supabase"."accounting_entry_line_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry uuid := case when tg_op = 'DELETE' then old."entry_id" else new."entry_id" end;
begin
  if exists (select 1 from "better_supabase"."accounting_entries" y where y."id" = v_entry and y."status" <> 'draft')
    or (tg_op = 'UPDATE' and exists (select 1 from "better_supabase"."accounting_entries" y where y."id" = old."entry_id" and y."status" <> 'draft')) then
    raise exception 'the lines of a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke execute on function "better_supabase"."accounting_entry_line_guard"() from public, anon, authenticated;
drop trigger if exists "bsb_accounting_entry_lines_guard" on "better_supabase"."accounting_entry_lines";
create trigger "bsb_accounting_entry_lines_guard" before insert or update or delete on "better_supabase"."accounting_entry_lines"
  for each row execute function "better_supabase"."accounting_entry_line_guard"('tenant_id');

-- Sets up accounting for an organization: its functional currency and the
-- month its fiscal year starts, then the generic chart, its account roles and the default journals when it has none.
-- Neither setting changes once entries post or periods exist.
create or replace function "better_supabase"."setup_accounting"(tenant uuid, functional_currency text default null, fiscal_year_start_month integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_settings"%rowtype;
  v_currency text := upper(coalesce(nullif(trim(setup_accounting.functional_currency), ''), 'EUR'));
  v_month integer := coalesce(setup_accounting.fiscal_year_start_month, 1);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', setup_accounting.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage accounting' using errcode = '42501', hint = 'ACCOUNTING_SETTING_FORBIDDEN';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'the functional currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
  end if;
  if v_month < 1 or v_month > 12 then
    raise exception 'the fiscal year starts in a month from 1 to 12' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
  end if;
  select * into v_row from "better_supabase"."accounting_settings" y where y."tenant_id" = setup_accounting.tenant for update;
  if found then
    if setup_accounting.functional_currency is not null and v_row."functional_currency" <> v_currency
      and exists (select 1 from "better_supabase"."accounting_entries" y where y."tenant_id" = setup_accounting.tenant and y."status" <> 'draft') then
      raise exception 'the functional currency can''t change once entries are posted' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
    end if;
    if setup_accounting.fiscal_year_start_month is not null and v_row."fiscal_year_start_month" <> v_month
      and exists (select 1 from "better_supabase"."accounting_periods" y where y."tenant_id" = setup_accounting.tenant) then
      raise exception 'the fiscal year start can''t change once periods exist' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
    end if;
    update "better_supabase"."accounting_settings" y set
      "functional_currency" = case when setup_accounting.functional_currency is null then y."functional_currency" else v_currency end,
      "fiscal_year_start_month" = case when setup_accounting.fiscal_year_start_month is null then y."fiscal_year_start_month" else v_month end,
      "updated_at" = now()
    where y."tenant_id" = setup_accounting.tenant
    returning * into v_row;
  else
    insert into "better_supabase"."accounting_settings" ("tenant_id", "functional_currency", "fiscal_year_start_month")
    values (setup_accounting.tenant, v_currency, v_month)
    returning * into v_row;
  end if;
  if not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = setup_accounting.tenant) then
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable")
    values
      (setup_accounting.tenant, '1000', 'Bank', 'asset', 'bank', true),
      (setup_accounting.tenant, '1100', 'Cash', 'asset', 'cash', false),
      (setup_accounting.tenant, '1200', 'Accounts receivable', 'asset', 'receivable', true),
      (setup_accounting.tenant, '1300', 'Inventory', 'asset', 'inventory', false),
      (setup_accounting.tenant, '1350', 'Work in progress', 'asset', 'inventory', false),
      (setup_accounting.tenant, '1400', 'Tax receivable', 'asset', 'current_asset', false),
      (setup_accounting.tenant, '1500', 'Fixed assets', 'asset', 'fixed_asset', false),
      (setup_accounting.tenant, '1510', 'Accumulated depreciation', 'asset', 'fixed_asset', false),
      (setup_accounting.tenant, '1900', 'Suspense', 'asset', 'current_asset', false),
      (setup_accounting.tenant, '2000', 'Accounts payable', 'liability', 'payable', true),
      (setup_accounting.tenant, '2100', 'Tax payable', 'liability', 'tax', false),
      (setup_accounting.tenant, '3000', 'Share capital', 'equity', 'equity', false),
      (setup_accounting.tenant, '3900', 'Retained earnings', 'equity', 'equity', false),
      (setup_accounting.tenant, '4000', 'Revenue', 'income', 'revenue', false),
      (setup_accounting.tenant, '4900', 'Exchange gains', 'income', 'other_income', false),
      (setup_accounting.tenant, '4910', 'Gains on asset disposals', 'income', 'other_income', false),
      (setup_accounting.tenant, '5000', 'Cost of goods sold', 'expense', 'cogs', false),
      (setup_accounting.tenant, '6000', 'Operating expenses', 'expense', 'operating_expense', false),
      (setup_accounting.tenant, '6800', 'Depreciation', 'expense', 'operating_expense', false),
      (setup_accounting.tenant, '6900', 'Exchange losses', 'expense', 'other_expense', false),
      (setup_accounting.tenant, '6910', 'Losses on asset disposals', 'expense', 'other_expense', false);
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select setup_accounting.tenant, c.role, y."id"
    from (values ('bank', '1000'), ('receivable', '1200'), ('inventory', '1300'), ('work_in_progress', '1350'), ('tax_receivable', '1400'), ('fixed_asset', '1500'), ('accumulated_depreciation', '1510'), ('suspense', '1900'), ('payable', '2000'), ('tax_payable', '2100'), ('retained_earnings', '3900'), ('revenue', '4000'), ('fx_gain', '4900'), ('disposal_gain', '4910'), ('cogs', '5000'), ('expense', '6000'), ('depreciation_expense', '6800'), ('fx_loss', '6900'), ('disposal_loss', '6910')) c (role, code)
    join "better_supabase"."accounting_accounts" y on y."tenant_id" = setup_accounting.tenant and y."code" = c.code
    on conflict ("tenant_id", "role") do nothing;
  end if;
  if not exists (select 1 from "better_supabase"."accounting_journals" y where y."tenant_id" = setup_accounting.tenant) then
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select setup_accounting.tenant, c.code, c.name, c.type,
      (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = setup_accounting.tenant and y."code" = c.account)
    from (values ('SAL', 'Sales', 'sales', null::text), ('PUR', 'Purchases', 'purchase', null::text), ('BNK', 'Bank', 'bank', '1000'), ('CSH', 'Cash', 'cash', '1100'), ('GEN', 'General', 'general', null::text)) c (code, name, type, account);
  end if;
  return jsonb_build_object('organizationId', v_row."tenant_id", 'functionalCurrency', v_row."functional_currency", 'fiscalYearStartMonth', v_row."fiscal_year_start_month", 'lockDate', v_row."lock_date", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."setup_accounting"(uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."setup_accounting"(uuid, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."get_accounting_settings"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('organizationId', x."tenant_id", 'functionalCurrency', x."functional_currency", 'fiscalYearStartMonth', x."fiscal_year_start_month", 'lockDate', x."lock_date", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."accounting_settings" x where x."tenant_id" = get_accounting_settings.tenant
$$;
revoke execute on function "better_supabase"."get_accounting_settings"(uuid) from public, anon;
grant execute on function "better_supabase"."get_accounting_settings"(uuid) to authenticated, service_role;

-- Nothing posts on or before the lock date; null unlocks.
create or replace function "better_supabase"."set_accounting_lock_date"(tenant uuid, lock_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_accounting_lock_date.tenant, 'accounting.close'), false)) then
    raise exception 'not allowed to close accounting periods' using errcode = '42501', hint = 'ACCOUNTING_SETTING_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = set_accounting_lock_date.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  update "better_supabase"."accounting_settings" y set "lock_date" = set_accounting_lock_date.lock_date, "updated_at" = now()
  where y."tenant_id" = set_accounting_lock_date.tenant
  returning * into v_settings;
  return jsonb_build_object('organizationId', v_settings."tenant_id", 'functionalCurrency', v_settings."functional_currency", 'fiscalYearStartMonth', v_settings."fiscal_year_start_month", 'lockDate', v_settings."lock_date", 'createdAt', v_settings."created_at", 'updatedAt', v_settings."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_accounting_lock_date"(uuid, date) from public, anon;
grant execute on function "better_supabase"."set_accounting_lock_date"(uuid, date) to authenticated, service_role;

-- Creates an account, or changes one (account_id, or the account with the code).
-- An account with posted lines keeps its type.
create or replace function "better_supabase"."save_accounting_account"(tenant uuid, code text, name text, type text, subtype text default null, parent_id uuid default null, currency text default null, reconcilable boolean default false, account_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_accounts"%rowtype;
  v_id uuid := save_accounting_account.account_id;
  v_currency text := upper(nullif(trim(save_accounting_account.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_account.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_ACCOUNT_FORBIDDEN';
  end if;
  if nullif(trim(save_accounting_account.code), '') is null or nullif(trim(save_accounting_account.name), '') is null then
    raise exception 'an account needs a code and a name' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if save_accounting_account.type is null or save_accounting_account.type not in ('asset', 'liability', 'equity', 'income', 'expense') then
    raise exception 'the account type is asset, liability, equity, income or expense' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if save_accounting_account.subtype is not null and save_accounting_account.subtype not in ('bank', 'cash', 'receivable', 'inventory', 'current_asset', 'fixed_asset', 'payable', 'tax', 'current_liability', 'long_term_liability', 'equity', 'revenue', 'other_income', 'cogs', 'operating_expense', 'other_expense') then
    raise exception 'the subtype isn''t one of blocks.accounting.options.subtypes' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
    raise exception 'the currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if v_id is null then
    select y."id" into v_id from "better_supabase"."accounting_accounts" y
    where y."tenant_id" = save_accounting_account.tenant and y."code" = trim(save_accounting_account.code);
  end if;
  if save_accounting_account.parent_id is not null then
    if not exists (select 1 from "better_supabase"."accounting_accounts" y where y."id" = save_accounting_account.parent_id and y."tenant_id" = save_accounting_account.tenant) then
      raise exception 'parent account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    if v_id is not null and exists (
      with recursive up (id) as (
        select save_accounting_account.parent_id
        union
        select y."parent_id" from "better_supabase"."accounting_accounts" y join up on y."id" = up.id where y."parent_id" is not null
      )
      select 1 from up where up.id = v_id
    ) then
      raise exception 'an account can''t be its own parent' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
    end if;
  end if;
  if v_id is null then
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "parent_id", "currency", "reconcilable")
    values (save_accounting_account.tenant, trim(save_accounting_account.code), trim(save_accounting_account.name), save_accounting_account.type,
      save_accounting_account.subtype, save_accounting_account.parent_id, v_currency, coalesce(save_accounting_account.reconcilable, false))
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."accounting_accounts" y where y."id" = v_id and y."tenant_id" = save_accounting_account.tenant for update;
    if not found then
      raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    if exists (
      select 1 from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
      where y."account_id" = v_id and z."status" <> 'draft'
        and (v_row."type" <> save_accounting_account.type or (v_currency is not null and y."currency" <> v_currency))
    ) then
      raise exception 'the account has posted lines, so its type and currency stay' using errcode = '55000', hint = 'ACCOUNTING_ACCOUNT_IN_USE';
    end if;
    update "better_supabase"."accounting_accounts" y set "code" = trim(save_accounting_account.code), "name" = trim(save_accounting_account.name),
      "type" = save_accounting_account.type, "subtype" = save_accounting_account.subtype, "parent_id" = save_accounting_account.parent_id,
      "currency" = v_currency, "reconcilable" = coalesce(save_accounting_account.reconcilable, false), "updated_at" = now()
    where y."id" = v_id
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'subtype', v_row."subtype", 'parentId', v_row."parent_id", 'currency', v_row."currency", 'reconcilable', v_row."reconcilable", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = v_row."id"), '[]'::jsonb), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid) to authenticated, service_role;

-- Archives an account (nothing posts to it), or restores it. An account
-- mapped to a role, a journal or a tax code stays.
create or replace function "better_supabase"."archive_accounting_account"(account_id uuid, archived boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_accounts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."accounting_accounts" y where y."id" = archive_accounting_account.account_id for update;
  if not found then
    raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_ACCOUNT_FORBIDDEN';
  end if;
  if coalesce(archive_accounting_account.archived, true) and (
    exists (select 1 from "better_supabase"."accounting_account_roles" y where y."account_id" = v_row."id")
    or exists (select 1 from "better_supabase"."accounting_journals" y where y."default_account_id" = v_row."id")
    or exists (select 1 from "better_supabase"."accounting_tax_codes" y where y."account_id" = v_row."id" and y."archived_at" is null)
  ) then
    raise exception 'the account is mapped to a role, a journal or a tax code' using errcode = '55000', hint = 'ACCOUNTING_ACCOUNT_IN_USE';
  end if;
  update "better_supabase"."accounting_accounts" y set "archived_at" = case when coalesce(archive_accounting_account.archived, true) then coalesce(y."archived_at", now()) end,
    "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'subtype', v_row."subtype", 'parentId', v_row."parent_id", 'currency', v_row."currency", 'reconcilable', v_row."reconcilable", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = v_row."id"), '[]'::jsonb), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_accounting_account"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_accounting_account"(uuid, boolean) to authenticated, service_role;

-- Maps a role (receivable, bank, retained_earnings) to an account; null unmaps it.
create or replace function "better_supabase"."set_accounting_account_role"(tenant uuid, role text, account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_accounting_account_role.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_ACCOUNT_FORBIDDEN';
  end if;
  if set_accounting_account_role.role is null or set_accounting_account_role.role not in ('receivable', 'payable', 'bank', 'revenue', 'cogs', 'inventory', 'work_in_progress', 'tax_payable', 'tax_receivable', 'retained_earnings', 'fx_gain', 'fx_loss', 'fixed_asset', 'accumulated_depreciation', 'depreciation_expense', 'disposal_gain', 'disposal_loss', 'expense', 'suspense') then
    raise exception 'unknown account role' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_ROLE_INVALID';
  end if;
  if set_accounting_account_role.account_id is null then
    delete from "better_supabase"."accounting_account_roles" y where y."tenant_id" = set_accounting_account_role.tenant and y."role" = set_accounting_account_role.role;
  else
    if not exists (
      select 1 from "better_supabase"."accounting_accounts" y where y."id" = set_accounting_account_role.account_id
        and y."tenant_id" = set_accounting_account_role.tenant and y."archived_at" is null
    ) then
      raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    values (set_accounting_account_role.tenant, set_accounting_account_role.role, set_accounting_account_role.account_id)
    on conflict ("tenant_id", "role") do update set "account_id" = excluded."account_id", "updated_at" = now();
  end if;
  return coalesce((
    select jsonb_object_agg(y."role", y."account_id") from "better_supabase"."accounting_account_roles" y where y."tenant_id" = set_accounting_account_role.tenant
  ), '{}'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."set_accounting_account_role"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."set_accounting_account_role"(uuid, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_accounting_accounts"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."accounting_accounts" x
  where x."tenant_id" = list_accounting_accounts.tenant
    and (coalesce(list_accounting_accounts.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_accounting_accounts"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_accounting_accounts"(uuid, boolean) to authenticated, service_role;

-- Creates a journal, or changes one (journal_id, or the journal with the code).
create or replace function "better_supabase"."save_accounting_journal"(tenant uuid, code text, name text, type text, default_account_id uuid default null, currency text default null, journal_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_journals"%rowtype;
  v_id uuid := save_accounting_journal.journal_id;
  v_code text := upper(trim(save_accounting_journal.code));
  v_currency text := upper(nullif(trim(save_accounting_journal.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_journal.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage journals' using errcode = '42501', hint = 'ACCOUNTING_JOURNAL_FORBIDDEN';
  end if;
  if v_code is null or v_code !~ '^[A-Z0-9][A-Z0-9_-]{0,15}$' or nullif(trim(save_accounting_journal.name), '') is null then
    raise exception 'a journal needs a short code (letters, digits, - and _) and a name' using errcode = '22023', hint = 'ACCOUNTING_JOURNAL_INVALID';
  end if;
  if save_accounting_journal.type is null or save_accounting_journal.type not in ('sales', 'purchase', 'bank', 'cash', 'general') then
    raise exception 'the journal type is sales, purchase, bank, cash or general' using errcode = '22023', hint = 'ACCOUNTING_JOURNAL_INVALID';
  end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
    raise exception 'the currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_JOURNAL_INVALID';
  end if;
  if save_accounting_journal.default_account_id is not null and not exists (
    select 1 from "better_supabase"."accounting_accounts" y where y."id" = save_accounting_journal.default_account_id
      and y."tenant_id" = save_accounting_journal.tenant and y."archived_at" is null
  ) then
    raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
  end if;
  if v_id is null then
    select y."id" into v_id from "better_supabase"."accounting_journals" y where y."tenant_id" = save_accounting_journal.tenant and y."code" = v_code;
  end if;
  if v_id is null then
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id", "currency")
    values (save_accounting_journal.tenant, v_code, trim(save_accounting_journal.name), save_accounting_journal.type, save_accounting_journal.default_account_id, v_currency)
    returning * into v_row;
  else
    update "better_supabase"."accounting_journals" y set "code" = v_code, "name" = trim(save_accounting_journal.name), "type" = save_accounting_journal.type,
      "default_account_id" = save_accounting_journal.default_account_id, "currency" = v_currency, "updated_at" = now()
    where y."id" = v_id and y."tenant_id" = save_accounting_journal.tenant
    returning * into v_row;
    if not found then
      raise exception 'journal not found' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'defaultAccountId', v_row."default_account_id", 'currency', v_row."currency", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_accounting_journals"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'defaultAccountId', x."default_account_id", 'currency', x."currency", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."accounting_journals" x
  where x."tenant_id" = list_accounting_journals.tenant
$$;
revoke execute on function "better_supabase"."list_accounting_journals"(uuid) from public, anon;
grant execute on function "better_supabase"."list_accounting_journals"(uuid) to authenticated, service_role;

-- Creates the twelve monthly periods of a fiscal year, from the start month of
-- the calendar year fiscal_year. Periods that exist stay as they are.
create or replace function "better_supabase"."open_fiscal_year"(tenant uuid, fiscal_year integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_start date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_fiscal_year.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if open_fiscal_year.fiscal_year is null or open_fiscal_year.fiscal_year < 1900 or open_fiscal_year.fiscal_year > 9998 then
    raise exception 'the fiscal year is a calendar year such as 2026' using errcode = '22023', hint = 'ACCOUNTING_PERIOD_INVALID';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = open_fiscal_year.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  v_start := make_date(open_fiscal_year.fiscal_year, v_settings."fiscal_year_start_month", 1);
  insert into "better_supabase"."accounting_periods" ("tenant_id", "fiscal_year", "number", "starts_on", "ends_on")
  select open_fiscal_year.tenant, open_fiscal_year.fiscal_year, n,
    (v_start + make_interval(months => n - 1))::date,
    (v_start + make_interval(months => n) - interval '1 day')::date
  from generate_series(1, 12) n
  on conflict ("tenant_id", "fiscal_year", "number") do nothing;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'fiscalYear', y."fiscal_year", 'number', y."number", 'startsOn', y."starts_on", 'endsOn', y."ends_on", 'status', y."status", 'closedAt', y."closed_at", 'closedBy', y."closed_by") order by y."number") from "better_supabase"."accounting_periods" y
    where y."tenant_id" = open_fiscal_year.tenant and y."fiscal_year" = open_fiscal_year.fiscal_year
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."open_fiscal_year"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."open_fiscal_year"(uuid, integer) to authenticated, service_role;

create or replace function "better_supabase"."list_accounting_periods"(tenant uuid, fiscal_year integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'fiscalYear', x."fiscal_year", 'number', x."number", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by") order by x."starts_on"), '[]'::jsonb)
  from "better_supabase"."accounting_periods" x
  where x."tenant_id" = list_accounting_periods.tenant
    and (list_accounting_periods.fiscal_year is null or x."fiscal_year" = list_accounting_periods.fiscal_year)
$$;
revoke execute on function "better_supabase"."list_accounting_periods"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_accounting_periods"(uuid, integer) to authenticated, service_role;

-- Creates or renames a dimension (project, department, cost center) by key.
create or replace function "better_supabase"."save_accounting_dimension"(tenant uuid, key text, name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_dimensions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_dimension.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage dimensions' using errcode = '42501', hint = 'ACCOUNTING_DIMENSION_FORBIDDEN';
  end if;
  if coalesce(save_accounting_dimension.key, '') !~ '^[a-z][a-z0-9_]{0,62}$' or nullif(trim(save_accounting_dimension.name), '') is null then
    raise exception 'a dimension needs a lower-case key and a name' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
  end if;
  insert into "better_supabase"."accounting_dimensions" ("tenant_id", "key", "name")
  values (save_accounting_dimension.tenant, save_accounting_dimension.key, trim(save_accounting_dimension.name))
  on conflict ("tenant_id", "key") do update set "name" = excluded."name"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'values', coalesce((select jsonb_agg(jsonb_build_object('id', dv."id", 'code', dv."code", 'name', dv."name", 'archivedAt', dv."archived_at") order by dv."code") from "better_supabase"."accounting_dimension_values" dv where dv."dimension_id" = v_row."id"), '[]'::jsonb), 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."save_accounting_dimension"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_accounting_dimension"(uuid, text, text) to authenticated, service_role;

-- Adds or renames a value of a dimension by code; archived values take no new lines.
create or replace function "better_supabase"."save_accounting_dimension_value"(dimension_id uuid, code text, name text, archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dimension "better_supabase"."accounting_dimensions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_dimension from "better_supabase"."accounting_dimensions" y where y."id" = save_accounting_dimension_value.dimension_id;
  if not found then
    raise exception 'dimension not found' using errcode = 'P0002', hint = 'ACCOUNTING_DIMENSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_dimension."tenant_id", 'accounting.manage'), false)) then
    raise exception 'not allowed to manage dimensions' using errcode = '42501', hint = 'ACCOUNTING_DIMENSION_FORBIDDEN';
  end if;
  if nullif(trim(save_accounting_dimension_value.code), '') is null or nullif(trim(save_accounting_dimension_value.name), '') is null then
    raise exception 'a dimension value needs a code and a name' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
  end if;
  insert into "better_supabase"."accounting_dimension_values" as y ("tenant_id", "dimension_id", "code", "name", "archived_at")
  values (v_dimension."tenant_id", v_dimension."id", trim(save_accounting_dimension_value.code), trim(save_accounting_dimension_value.name),
    case when coalesce(save_accounting_dimension_value.archived, false) then now() end)
  on conflict ("dimension_id", "code") do update
    set "name" = excluded."name", "archived_at" = case when excluded."archived_at" is null then null else coalesce(y."archived_at", excluded."archived_at") end;
  return jsonb_build_object('id', v_dimension."id", 'organizationId', v_dimension."tenant_id", 'key', v_dimension."key", 'name', v_dimension."name", 'values', coalesce((select jsonb_agg(jsonb_build_object('id', dv."id", 'code', dv."code", 'name', dv."name", 'archivedAt', dv."archived_at") order by dv."code") from "better_supabase"."accounting_dimension_values" dv where dv."dimension_id" = v_dimension."id"), '[]'::jsonb), 'createdAt', v_dimension."created_at");
end;
$$;
revoke execute on function "better_supabase"."save_accounting_dimension_value"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."save_accounting_dimension_value"(uuid, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."list_accounting_dimensions"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'values', coalesce((select jsonb_agg(jsonb_build_object('id', dv."id", 'code', dv."code", 'name', dv."name", 'archivedAt', dv."archived_at") order by dv."code") from "better_supabase"."accounting_dimension_values" dv where dv."dimension_id" = x."id"), '[]'::jsonb), 'createdAt', x."created_at") order by x."key"), '[]'::jsonb)
  from "better_supabase"."accounting_dimensions" x
  where x."tenant_id" = list_accounting_dimensions.tenant
$$;
revoke execute on function "better_supabase"."list_accounting_dimensions"(uuid) from public, anon;
grant execute on function "better_supabase"."list_accounting_dimensions"(uuid) to authenticated, service_role;

-- Creates or changes a tax code by code. rate_bps is basis points (2100 is 21%).
create or replace function "better_supabase"."save_accounting_tax_code"(tenant uuid, code text, name text, rate_bps integer, kind text, account_id uuid, report_boxes text[] default null, archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_tax_codes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_tax_code.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage tax codes' using errcode = '42501', hint = 'ACCOUNTING_TAX_CODE_FORBIDDEN';
  end if;
  if nullif(trim(save_accounting_tax_code.code), '') is null or nullif(trim(save_accounting_tax_code.name), '') is null
    or save_accounting_tax_code.rate_bps is null or save_accounting_tax_code.rate_bps < 0 or save_accounting_tax_code.rate_bps > 100000
    or save_accounting_tax_code.kind is null or save_accounting_tax_code.kind not in ('sales', 'purchase') then
    raise exception 'a tax code needs a code, a name, a rate in basis points and a kind (sales or purchase)' using errcode = '22023', hint = 'ACCOUNTING_TAX_CODE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."accounting_accounts" y where y."id" = save_accounting_tax_code.account_id
      and y."tenant_id" = save_accounting_tax_code.tenant and y."archived_at" is null
  ) then
    raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
  end if;
  insert into "better_supabase"."accounting_tax_codes" ("tenant_id", "code", "name", "rate_bps", "kind", "account_id", "report_boxes", "archived_at")
  values (save_accounting_tax_code.tenant, trim(save_accounting_tax_code.code), trim(save_accounting_tax_code.name), save_accounting_tax_code.rate_bps,
    save_accounting_tax_code.kind, save_accounting_tax_code.account_id, coalesce(save_accounting_tax_code.report_boxes, '{}'),
    case when coalesce(save_accounting_tax_code.archived, false) then now() end)
  on conflict ("tenant_id", "code") do update
    set "name" = excluded."name", "rate_bps" = excluded."rate_bps", "kind" = excluded."kind",
      "account_id" = excluded."account_id", "report_boxes" = excluded."report_boxes", "archived_at" = excluded."archived_at",
      "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'rateBps', v_row."rate_bps", 'kind', v_row."kind", 'accountId', v_row."account_id", 'reportBoxes', to_jsonb(v_row."report_boxes"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_accounting_tax_code"(uuid, text, text, integer, text, uuid, text[], boolean) from public, anon;
grant execute on function "better_supabase"."save_accounting_tax_code"(uuid, text, text, integer, text, uuid, text[], boolean) to authenticated, service_role;

create or replace function "better_supabase"."list_accounting_tax_codes"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'rateBps', x."rate_bps", 'kind', x."kind", 'accountId', x."account_id", 'reportBoxes', to_jsonb(x."report_boxes"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."accounting_tax_codes" x
  where x."tenant_id" = list_accounting_tax_codes.tenant
    and (coalesce(list_accounting_tax_codes.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_accounting_tax_codes"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_accounting_tax_codes"(uuid, boolean) to authenticated, service_role;

-- Records what one unit of base costs in quote on a date.
create or replace function "better_supabase"."set_accounting_fx_rate"(tenant uuid, base text, quote text, on_date date, rate numeric)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_base text := upper(trim(set_accounting_fx_rate.base));
  v_quote text := upper(trim(set_accounting_fx_rate.quote));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_accounting_fx_rate.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage exchange rates' using errcode = '42501', hint = 'ACCOUNTING_FX_RATE_FORBIDDEN';
  end if;
  if coalesce(v_base, '') !~ '^[A-Z]{3}$' or coalesce(v_quote, '') !~ '^[A-Z]{3}$' or v_base = v_quote
    or set_accounting_fx_rate.on_date is null or coalesce(set_accounting_fx_rate.rate, 0) <= 0 then
    raise exception 'a rate needs two different ISO 4217 codes, a date and a positive rate' using errcode = '22023', hint = 'ACCOUNTING_FX_RATE_INVALID';
  end if;
  insert into "better_supabase"."accounting_fx_rates" ("tenant_id", "base", "quote", "on_date", "rate")
  values (set_accounting_fx_rate.tenant, v_base, v_quote, set_accounting_fx_rate.on_date, set_accounting_fx_rate.rate)
  on conflict ("tenant_id", "base", "quote", "on_date") do update set "rate" = excluded."rate";
  return jsonb_build_object('organizationId', set_accounting_fx_rate.tenant, 'base', v_base, 'quote', v_quote,
    'onDate', set_accounting_fx_rate.on_date, 'rate', set_accounting_fx_rate.rate::text);
end;
$$;
revoke execute on function "better_supabase"."set_accounting_fx_rate"(uuid, text, text, date, numeric) from public, anon;
grant execute on function "better_supabase"."set_accounting_fx_rate"(uuid, text, text, date, numeric) to authenticated, service_role;

-- The rate on the date or the latest before it, or the inverse of the
-- opposite pair's; ACCOUNTING_FX_RATE_MISSING when neither has one.
create or replace function "better_supabase"."accounting_fx_rate"(tenant uuid, base text, quote text, on_date date)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_base text := upper(trim(accounting_fx_rate.base));
  v_quote text := upper(trim(accounting_fx_rate.quote));
  v_rate numeric;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', accounting_fx_rate.tenant, 'accounting.read'), false)) then
    raise exception 'not allowed to read accounting' using errcode = '42501', hint = 'ACCOUNTING_FX_RATE_FORBIDDEN';
  end if;
  if v_base = v_quote then
    return 1;
  end if;
  select y."rate" into v_rate from "better_supabase"."accounting_fx_rates" y
  where y."tenant_id" = accounting_fx_rate.tenant and y."base" = v_base and y."quote" = v_quote and y."on_date" <= accounting_fx_rate.on_date
  order by y."on_date" desc limit 1;
  if v_rate is null then
    select 1 / y."rate" into v_rate from "better_supabase"."accounting_fx_rates" y
    where y."tenant_id" = accounting_fx_rate.tenant and y."base" = v_quote and y."quote" = v_base and y."on_date" <= accounting_fx_rate.on_date
    order by y."on_date" desc limit 1;
  end if;
  if v_rate is null then
    raise exception 'no exchange rate for the currency pair on or before the date' using errcode = 'P0002', hint = 'ACCOUNTING_FX_RATE_MISSING';
  end if;
  return v_rate;
end;
$$;
revoke execute on function "better_supabase"."accounting_fx_rate"(uuid, text, text, date) from public, anon;
grant execute on function "better_supabase"."accounting_fx_rate"(uuid, text, text, date) to authenticated, service_role;

-- Posts a draft entry: balanced in the functional currency, dated in an open
-- period after the lock date, with known dimension values; then numbers it per
-- journal and fiscal year. Called by the posting, reversal and year close
-- functions; closing skips the period and lock date checks.
create or replace function "better_supabase"."accounting_post"(entry_id uuid, closing boolean default false)
returns "better_supabase"."accounting_entries"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_total numeric;
  v_credits numeric;
  v_count integer;
  v_sequence integer;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = accounting_post.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_row."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  select count(*), coalesce(sum(y."debit"), 0), coalesce(sum(y."credit"), 0) into v_count, v_total, v_credits
  from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
  if v_count < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if v_total <> v_credits then
    raise exception 'the debits and credits of the entry differ in the functional currency' using errcode = '23514', hint = 'ACCOUNTING_ENTRY_UNBALANCED';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_accounts" z on z."id" = y."account_id"
    where y."entry_id" = v_row."id" and z."archived_at" is not null
  ) then
    raise exception 'an account of the entry is archived' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entry_lines" y, jsonb_each(y."dimensions") dim
    where y."entry_id" = v_row."id"
      and (jsonb_typeof(dim.value) <> 'string' or not exists (
        select 1 from "better_supabase"."accounting_dimensions" z join "better_supabase"."accounting_dimension_values" w on w."dimension_id" = z."id"
        where z."tenant_id" = v_row."tenant_id" and z."key" = dim.key
          and w."code" = dim.value #>> '{}' and w."archived_at" is null
      ))
  ) then
    raise exception 'a line names a dimension or value that doesn''t exist or is archived' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y
  where y."tenant_id" = v_row."tenant_id" and v_row."entry_date" >= y."starts_on" and v_row."entry_date" <= y."ends_on";
  if not found then
    raise exception 'no period covers the entry date; open its fiscal year first' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not coalesce(accounting_post.closing, false) and (
    v_period."status" = 'closed'
    or (v_settings."lock_date" is not null and v_row."entry_date" <= v_settings."lock_date")
  ) then
    raise exception 'the entry date is in a closed period or on or before the lock date' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_accounting_entry_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select * into v_journal from "better_supabase"."accounting_journals" y where y."id" = v_row."journal_id";
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_journal."id"::text || ':' || v_period."fiscal_year"::text, 0));
  select coalesce(max(y."sequence"), 0) + 1 into v_sequence from "better_supabase"."accounting_entries" y
  where y."journal_id" = v_journal."id" and y."fiscal_year" = v_period."fiscal_year";
  update "better_supabase"."accounting_entries" y set "status" = 'posted', "fiscal_year" = v_period."fiscal_year", "sequence" = v_sequence,
    "number" = v_journal."code" || '-' || v_period."fiscal_year"::text || '-' || lpad(v_sequence::text, 5, '0'),
    "period_id" = v_period."id", "posted_at" = now(), "posted_by" = auth.uid(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_accounting_entry_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."accounting_post"(uuid, boolean) from public, anon, authenticated;

-- Creates a draft entry, or replaces a draft's header and lines (entry_id).
-- Each line names an account (accountId or accountCode) and a debit or a
-- credit in minor units of the functional currency. A line in another
-- currency gives amountCurrency (signed, positive is a debit) and either the
-- functional amount or an fxRate; without both, the rate on the entry date
-- converts it.
drop function if exists "better_supabase"."save_accounting_entry"(uuid, date, jsonb, text, text, text, text, uuid);
create or replace function "better_supabase"."save_accounting_entry"(journal_id uuid, entry_date date, lines jsonb, memo text default null, reference text default null, source_type text default null, source_id text default null, entry_id uuid default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_line record;
  v_account "better_supabase"."accounting_accounts"%rowtype;
  v_currency text;
  v_debit bigint;
  v_credit bigint;
  v_amount bigint;
  v_rate numeric;
  v_functional bigint;
  v_tax uuid;
  v_party uuid;
  v_dimensions jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_journal from "better_supabase"."accounting_journals" y where y."id" = save_accounting_entry.journal_id;
  if not found then
    raise exception 'journal not found' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_journal."tenant_id", 'accounting.write'), false)) then
    raise exception 'not allowed to write accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_journal."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  if save_accounting_entry.entry_date is null then
    raise exception 'an entry needs a date' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if jsonb_typeof(save_accounting_entry.lines) is distinct from 'array' or jsonb_array_length(save_accounting_entry.lines) < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if (save_accounting_entry.source_type is null) <> (save_accounting_entry.source_id is null)
    or coalesce(save_accounting_entry.source_type, 'x') !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'source_type (lower-case) and source_id go together' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if save_accounting_entry.source_type is not null and exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = v_journal."tenant_id" and y."source_type" = save_accounting_entry.source_type
      and y."source_id" = save_accounting_entry.source_id and y."status" <> 'reversed'
      and y."id" is distinct from save_accounting_entry.entry_id
  ) then
    raise exception 'the source already has an entry; reverse it first' using errcode = '23505', hint = 'ACCOUNTING_ENTRY_DUPLICATE';
  end if;
  if save_accounting_entry.entry_id is null then
    insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "source_type", "source_id", "memo", "created_by", "period_id")
    values (v_journal."tenant_id", v_journal."id", save_accounting_entry.entry_date, nullif(trim(save_accounting_entry.reference), ''),
      save_accounting_entry.source_type, save_accounting_entry.source_id, nullif(trim(save_accounting_entry.memo), ''), auth.uid(),
      (select y."id" from "better_supabase"."accounting_periods" y where y."tenant_id" = v_journal."tenant_id" and save_accounting_entry.entry_date >= y."starts_on" and save_accounting_entry.entry_date <= y."ends_on"))
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."accounting_entries" y where y."id" = save_accounting_entry.entry_id and y."tenant_id" = v_journal."tenant_id" for update;
    if not found then
      raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
    end if;
    delete from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
    update "better_supabase"."accounting_entries" y set "journal_id" = v_journal."id", "entry_date" = save_accounting_entry.entry_date,
      "reference" = nullif(trim(save_accounting_entry.reference), ''), "source_type" = save_accounting_entry.source_type,
      "source_id" = save_accounting_entry.source_id, "memo" = nullif(trim(save_accounting_entry.memo), ''),
      "period_id" = (select z."id" from "better_supabase"."accounting_periods" z where z."tenant_id" = v_journal."tenant_id" and save_accounting_entry.entry_date >= z."starts_on" and save_accounting_entry.entry_date <= z."ends_on"),
      "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  for v_line in select q.value, q.ordinality from jsonb_array_elements(save_accounting_entry.lines) with ordinality q loop
    if jsonb_typeof(v_line.value) is distinct from 'object' then
      raise exception 'every line is an object' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    if coalesce(v_line.value ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      select * into v_account from "better_supabase"."accounting_accounts" y where y."id" = (v_line.value ->> 'accountId')::uuid and y."tenant_id" = v_journal."tenant_id";
    else
      select * into v_account from "better_supabase"."accounting_accounts" y where y."code" = v_line.value ->> 'accountCode' and y."tenant_id" = v_journal."tenant_id";
    end if;
    if v_account."id" is null or v_account."archived_at" is not null then
      raise exception 'a line''s account doesn''t exist here or is archived' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    if coalesce(v_line.value ->> 'debit', '0') !~ '^[0-9]{1,18}$' or coalesce(v_line.value ->> 'credit', '0') !~ '^[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'amountCurrency', '0') !~ '^-?[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'fxRate', '1') !~ '^[0-9]+(\.[0-9]+)?$' then
      raise exception 'debit and credit are non-negative integers, amountCurrency an integer and fxRate a positive decimal' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_debit := coalesce((v_line.value ->> 'debit')::bigint, 0);
    v_credit := coalesce((v_line.value ->> 'credit')::bigint, 0);
    v_currency := upper(coalesce(nullif(v_line.value ->> 'currency', ''), v_settings."functional_currency"));
    if v_currency !~ '^[A-Z]{3}$' then
      raise exception 'a line''s currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    if v_account."currency" is not null and v_account."currency" <> v_currency then
      raise exception 'the account takes lines in its own currency only' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_rate := null;
    if v_currency = v_settings."functional_currency" then
      v_amount := v_debit - v_credit;
    else
      v_amount := (v_line.value ->> 'amountCurrency')::bigint;
      if v_amount is null or v_amount = 0 then
        raise exception 'a line in another currency needs a non-zero amountCurrency' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
      v_rate := coalesce((v_line.value ->> 'fxRate')::numeric,
        "better_supabase"."accounting_fx_rate"(v_journal."tenant_id", v_currency, v_settings."functional_currency", save_accounting_entry.entry_date));
      if v_rate <= 0 then
        raise exception 'fxRate must be positive' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
      if v_debit = 0 and v_credit = 0 then
        v_functional := round(abs(v_amount) * v_rate)::bigint;
        if v_amount > 0 then
          v_debit := v_functional;
        else
          v_credit := v_functional;
        end if;
      elsif (v_amount > 0) <> (v_debit > 0) then
        raise exception 'amountCurrency and the functional amount must be on the same side' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
    end if;
    if (v_debit = 0) = (v_credit = 0) then
      raise exception 'every line has either a debit or a credit' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_tax := null;
    if v_line.value ->> 'taxCodeId' is not null then
      select y."id" into v_tax from "better_supabase"."accounting_tax_codes" y
      where y."id"::text = v_line.value ->> 'taxCodeId' and y."tenant_id" = v_journal."tenant_id";
      if v_tax is null then
        raise exception 'tax code not found' using errcode = 'P0002', hint = 'ACCOUNTING_TAX_CODE_NOT_FOUND';
      end if;
    end if;
    if coalesce(v_line.value ->> 'partyId', '00000000-0000-0000-0000-000000000000') !~ '^[0-9a-fA-F-]{36}$' then
      raise exception 'partyId must be a uuid' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_party := (v_line.value ->> 'partyId')::uuid;
    v_dimensions := coalesce(v_line.value -> 'dimensions', '{}'::jsonb);
    if jsonb_typeof(v_dimensions) = 'null' then
      v_dimensions := '{}'::jsonb;
    end if;
    if jsonb_typeof(v_dimensions) <> 'object' then
      raise exception 'a line''s dimensions are an object of dimension keys to value codes' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
    end if;
    insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
      "amount_currency", "fx_rate", "tax_code_id", "party_id", "dimensions", "description")
    values (v_journal."tenant_id", v_row."id", v_line.ordinality, v_account."id", v_debit, v_credit, v_currency,
      v_amount, v_rate, v_tax, v_party, v_dimensions, nullif(trim(v_line.value ->> 'description'), ''));
  end loop;
  update "better_supabase"."accounting_entries" x set "app_note" = case when save_accounting_entry.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."accounting_entries", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(save_accounting_entry.fields) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."save_accounting_entry"(uuid, date, jsonb, text, text, text, text, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_accounting_entry"(uuid, date, jsonb, text, text, text, text, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."post_accounting_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = post_accounting_entry.entry_id;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  v_row := "better_supabase"."accounting_post"(v_row."id");
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."post_accounting_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."post_accounting_entry"(uuid) to authenticated, service_role;

-- Reverses a posted entry with a new entry of opposite lines, dated
-- entry_date (default the original's date), and marks the original reversed.
-- Called by reverse_accounting_entry and when a block undoes a document.
create or replace function "better_supabase"."accounting_reverse"(entry_id uuid, entry_date date default null)
returns "better_supabase"."accounting_entries"
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_reversal "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = accounting_reverse.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if v_row."status" = 'reversed' then
    raise exception 'the entry is already reversed' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_REVERSED';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted entry can be reversed; delete a draft instead' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_accounting_entry_reverse"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "reverses_id", "memo", "created_by")
  values (v_row."tenant_id", v_row."journal_id", coalesce(accounting_reverse.entry_date, v_row."entry_date"), v_row."number",
    v_row."id", 'Reversal of ' || v_row."number", auth.uid())
  returning * into v_reversal;
  insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
    "amount_currency", "fx_rate", "tax_code_id", "party_id", "dimensions", "description")
  select y."tenant_id", v_reversal."id", y."position", y."account_id", y."credit", y."debit", y."currency",
    -y."amount_currency", y."fx_rate", y."tax_code_id", y."party_id", y."dimensions", y."description"
  from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
  v_reversal := "better_supabase"."accounting_post"(v_reversal."id");
  update "better_supabase"."accounting_entries" y set "status" = 'reversed', "updated_at" = now() where y."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_accounting_entry_reverse"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_reversal;
end;
$$;
revoke execute on function "better_supabase"."accounting_reverse"(uuid, date) from public, anon, authenticated;

create or replace function "better_supabase"."reverse_accounting_entry"(entry_id uuid, entry_date date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = reverse_accounting_entry.entry_id;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  v_row := "better_supabase"."accounting_reverse"(v_row."id", reverse_accounting_entry.entry_date);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."reverse_accounting_entry"(uuid, date) from public, anon;
grant execute on function "better_supabase"."reverse_accounting_entry"(uuid, date) to authenticated, service_role;

create or replace function "better_supabase"."delete_accounting_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_json jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = delete_accounting_entry.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.write'), false)) then
    raise exception 'not allowed to write accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  v_json := jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', v_row."app_note"));
  delete from "better_supabase"."accounting_entries" y where y."id" = v_row."id";
  return v_json;
end;
$$;
revoke execute on function "better_supabase"."delete_accounting_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_accounting_entry"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_accounting_entry"(entry_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = x."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."accounting_entries" x where x."id" = get_accounting_entry.entry_id
$$;
revoke execute on function "better_supabase"."get_accounting_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."get_accounting_entry"(uuid) to authenticated, service_role;

-- Entries, the newest first, without their lines.
create or replace function "better_supabase"."list_accounting_entries"(tenant uuid, journal_id uuid default null, status text default null, since date default null, until date default null, page_size integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.entry order by z.entry_date desc, z.created_at desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'fields', jsonb_build_object('app_note', x."app_note")) as entry, x."entry_date" as entry_date, x."created_at" as created_at
    from "better_supabase"."accounting_entries" x
    where x."tenant_id" = list_accounting_entries.tenant
      and (list_accounting_entries.journal_id is null or x."journal_id" = list_accounting_entries.journal_id)
      and (list_accounting_entries.status is null or x."status" = list_accounting_entries.status)
      and (list_accounting_entries.since is null or x."entry_date" >= list_accounting_entries.since)
      and (list_accounting_entries.until is null or x."entry_date" <= list_accounting_entries.until)
    order by x."entry_date" desc, x."created_at" desc
    limit least(greatest(coalesce(list_accounting_entries.page_size, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."list_accounting_entries"(uuid, uuid, text, date, date, integer) from public, anon;
grant execute on function "better_supabase"."list_accounting_entries"(uuid, uuid, text, date, date, integer) to authenticated, service_role;

-- Books a block's document once: the block's lines function describes the
-- entry in the document's currency with account roles, and this resolves the
-- roles, tax codes and exchange rates, then saves the entry in the source's
-- journal type and posts it (autoPost) when its date falls in an open period
-- after the lock date. A document books once until its entry is reversed, so
-- calling it again returns the same entry. Returns null when the organization
-- hasn't set up accounting or the document has nothing to book.
create or replace function "better_supabase"."accounting_post_source"(source_type text, source_id text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc jsonb;
  v_kind text;
  v_tenant uuid;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_date date;
  v_line record;
  v_amount bigint;
  v_functional bigint;
  v_rate numeric;
  v_currency text;
  v_account uuid;
  v_tax "better_supabase"."accounting_tax_codes"%rowtype;
  v_diff bigint;
  v_largest integer;
  v_accounts uuid[] := '{}';
  v_functionals bigint[] := '{}';
  v_amounts bigint[] := '{}';
  v_currencies text[] := '{}';
  v_rates numeric[] := '{}';
  v_taxes uuid[] := '{}';
  v_parties uuid[] := '{}';
  v_dimensions jsonb[] := '{}';
  v_descriptions text[] := '{}';
begin
  if accounting_post_source.source_type is null or accounting_post_source.source_id is null
    or true then
    raise exception 'no installed block books this source type' using errcode = '22023', hint = 'ACCOUNTING_SOURCE_INVALID';
  end if;
  
  if v_doc is null or jsonb_typeof(v_doc -> 'lines') is distinct from 'array' then
    return null;
  end if;
  v_tenant := (v_doc ->> 'organizationId')::uuid;
  select * into v_settings from "better_supabase"."accounting_settings" y where y."tenant_id" = v_tenant;
  if not found then
    return null;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'accounting-source:' || v_tenant::text || ':' || accounting_post_source.source_type || ':' || accounting_post_source.source_id, 0));
  select * into v_row from "better_supabase"."accounting_entries" y
  where y."tenant_id" = v_tenant and y."source_type" = accounting_post_source.source_type
    and y."source_id" = accounting_post_source.source_id and y."status" <> 'reversed';
  if found then
    return v_row."id";
  end if;
  v_date := coalesce((v_doc ->> 'entryDate')::date, current_date);
  v_kind := coalesce(v_doc ->> 'journal', v_kind);
  if coalesce(v_doc ->> 'journalId', '') ~ '^[0-9a-fA-F-]{36}$' then
    select * into v_journal from "better_supabase"."accounting_journals" y
    where y."tenant_id" = v_tenant and y."id" = (v_doc ->> 'journalId')::uuid;
  end if;
  if v_journal."id" is null then
    select * into v_journal from "better_supabase"."accounting_journals" y
    where y."tenant_id" = v_tenant and y."type" = v_kind order by y."code" limit 1;
  end if;
  if v_journal."id" is null then
    raise exception 'the organization has no journal of the type this document books in' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  for v_line in select q.value from jsonb_array_elements(v_doc -> 'lines') q loop
    v_amount := coalesce((v_line.value ->> 'debit')::bigint, 0) - coalesce((v_line.value ->> 'credit')::bigint, 0);
    continue when v_amount = 0;
    v_tax := null;
    if v_line.value ->> 'taxCode' is not null then
      select * into v_tax from "better_supabase"."accounting_tax_codes" y
      where y."tenant_id" = v_tenant and y."code" = v_line.value ->> 'taxCode' and y."archived_at" is null;
    end if;
    if v_tax."id" is null and coalesce(v_line.value ->> 'taxRateBps', '') ~ '^[0-9]{1,6}$' then
      select * into v_tax from "better_supabase"."accounting_tax_codes" y
      where y."tenant_id" = v_tenant and y."rate_bps" = (v_line.value ->> 'taxRateBps')::integer
        and y."kind" = case when v_journal."type" = 'purchase' then 'purchase' else 'sales' end
        and y."archived_at" is null
      order by y."code" limit 1;
    end if;
    v_account := null;
    if v_line.value ->> 'role' in ('tax_payable', 'tax_receivable') and v_tax."id" is not null then
      v_account := v_tax."account_id";
    elsif coalesce(v_line.value ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      select y."id" into v_account from "better_supabase"."accounting_accounts" y where y."id" = (v_line.value ->> 'accountId')::uuid and y."tenant_id" = v_tenant and y."archived_at" is null;
    elsif v_line.value ->> 'accountCode' is not null then
      select y."id" into v_account from "better_supabase"."accounting_accounts" y where y."code" = v_line.value ->> 'accountCode' and y."tenant_id" = v_tenant and y."archived_at" is null;
    elsif v_line.value ->> 'role' is not null then
      select y."id" into v_account from "better_supabase"."accounting_account_roles" z join "better_supabase"."accounting_accounts" y on y."id" = z."account_id"
      where z."tenant_id" = v_tenant and z."role" = v_line.value ->> 'role' and y."archived_at" is null;
    end if;
    if v_account is null then
      select y."id" into v_account from "better_supabase"."accounting_account_roles" z join "better_supabase"."accounting_accounts" y on y."id" = z."account_id"
      where z."tenant_id" = v_tenant and z."role" = 'suspense' and y."archived_at" is null;
    end if;
    if v_account is null then
      raise exception 'no account plays the role a document line needs, and no account plays suspense' using errcode = 'P0002', hint = 'ACCOUNTING_ROLE_UNMAPPED';
    end if;
    v_currency := upper(coalesce(v_line.value ->> 'currency', v_doc ->> 'currency', v_settings."functional_currency"));
    v_rate := null;
    v_functional := v_amount;
    if v_currency <> v_settings."functional_currency" then
      v_rate := "better_supabase"."accounting_fx_rate"(v_tenant, v_currency, v_settings."functional_currency", v_date);
      v_functional := round(v_amount * v_rate)::bigint;
      continue when v_functional = 0;
    end if;
    v_accounts := v_accounts || v_account;
    v_functionals := v_functionals || v_functional;
    v_amounts := v_amounts || v_amount;
    v_currencies := v_currencies || v_currency;
    v_rates := v_rates || v_rate;
    v_taxes := v_taxes || v_tax."id";
    v_parties := v_parties || case when coalesce(v_line.value ->> 'partyId', '') ~ '^[0-9a-fA-F-]{36}$' then (v_line.value ->> 'partyId')::uuid end;
    v_dimensions := v_dimensions || case when jsonb_typeof(v_line.value -> 'dimensions') = 'object' then v_line.value -> 'dimensions' else '{}'::jsonb end;
    v_descriptions := v_descriptions || left(nullif(trim(v_line.value ->> 'description'), ''), 500);
  end loop;
  if coalesce(array_length(v_accounts, 1), 0) < 2 then
    return null;
  end if;
  -- Converting each line rounds on its own; the difference goes to the
  -- largest line on the side that is short.
  select coalesce(sum(u), 0) into v_diff from unnest(v_functionals) u;
  if v_diff <> 0 then
    select q.n into v_largest from unnest(v_functionals) with ordinality q(amount, n)
    where sign(q.amount) = -sign(v_diff) order by abs(q.amount) desc limit 1;
    if v_largest is null then
      raise exception 'the document''s lines don''t balance' using errcode = '23514', hint = 'ACCOUNTING_ENTRY_UNBALANCED';
    end if;
    v_functionals[v_largest] := v_functionals[v_largest] - v_diff;
  end if;
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "source_type", "source_id", "memo", "created_by", "period_id")
  values (v_tenant, v_journal."id", v_date, left(nullif(trim(v_doc ->> 'reference'), ''), 200),
    accounting_post_source.source_type, accounting_post_source.source_id, left(nullif(trim(v_doc ->> 'memo'), ''), 2000), auth.uid(),
    (select y."id" from "better_supabase"."accounting_periods" y where y."tenant_id" = v_tenant and v_date >= y."starts_on" and v_date <= y."ends_on"))
  returning * into v_row;
  insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
    "amount_currency", "fx_rate", "tax_code_id", "party_id", "dimensions", "description")
  select v_tenant, v_row."id", u.n, u.account, greatest(u.functional, 0), greatest(-u.functional, 0), u.currency,
    case when u.rate is null then u.functional else u.amount end, u.rate, u.tax, u.party, u.dimensions, u.description
  from unnest(v_accounts, v_functionals, v_amounts, v_currencies, v_rates, v_taxes, v_parties, v_dimensions, v_descriptions)
    with ordinality u(account, functional, amount, currency, rate, tax, party, dimensions, description, n);
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = v_row."period_id";
  if found and v_period."status" = 'open'
    and (v_settings."lock_date" is null or v_date > v_settings."lock_date") then
    perform "better_supabase"."accounting_post"(v_row."id");
  end if;
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."accounting_post_source"(text, text) from public, anon, authenticated;

-- Books a document a block didn't book when it happened, such as one from
-- before the organization set up accounting.
create or replace function "better_supabase"."post_accounting_source"(source_type text, source_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  v_id := "better_supabase"."accounting_post_source"(post_accounting_source.source_type, post_accounting_source.source_id);
  if v_id is null then
    return null;
  end if;
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = v_id;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."post_accounting_source"(text, text) from public, anon;
grant execute on function "better_supabase"."post_accounting_source"(text, text) to authenticated, service_role;

-- Undoes the entry of a document a block voided or reversed: deletes a draft,
-- or reverses a posted entry on entry_date (default today). Returns the
-- reversal, or null when there was nothing posted.
create or replace function "better_supabase"."accounting_reverse_source"(tenant uuid, source_type text, source_id text, entry_date date default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y
  where y."tenant_id" = accounting_reverse_source.tenant and y."source_type" = accounting_reverse_source.source_type
    and y."source_id" = accounting_reverse_source.source_id and y."status" <> 'reversed'
  for update;
  if not found then
    return null;
  end if;
  if v_row."status" = 'draft' then
    delete from "better_supabase"."accounting_entries" y where y."id" = v_row."id";
    return null;
  end if;
  return ("better_supabase"."accounting_reverse"(v_row."id", coalesce(accounting_reverse_source.entry_date, current_date)))."id";
end;
$$;
revoke execute on function "better_supabase"."accounting_reverse_source"(uuid, text, text, date) from public, anon, authenticated;

-- Keeps a dimension value in step with another block's record, such as a
-- project, so its documents can carry it: creates the dimension when it is
-- missing, and sets the value's name and whether it is archived.
create or replace function "better_supabase"."accounting_sync_dimension_value"(tenant uuid, dimension_key text, dimension_name text, code text, value_name text, archived boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dimension uuid;
begin
  insert into "better_supabase"."accounting_dimensions" ("tenant_id", "key", "name")
  values (accounting_sync_dimension_value.tenant, accounting_sync_dimension_value.dimension_key, accounting_sync_dimension_value.dimension_name)
  on conflict ("tenant_id", "key") do nothing;
  select y."id" into v_dimension from "better_supabase"."accounting_dimensions" y
  where y."tenant_id" = accounting_sync_dimension_value.tenant and y."key" = accounting_sync_dimension_value.dimension_key;
  insert into "better_supabase"."accounting_dimension_values" as y ("tenant_id", "dimension_id", "code", "name", "archived_at")
  values (accounting_sync_dimension_value.tenant, v_dimension, accounting_sync_dimension_value.code, left(accounting_sync_dimension_value.value_name, 200),
    case when accounting_sync_dimension_value.archived then now() end)
  on conflict ("dimension_id", "code") do update
    set "name" = excluded."name",
      "archived_at" = case when accounting_sync_dimension_value.archived then coalesce(y."archived_at", now()) end;
end;
$$;
revoke execute on function "better_supabase"."accounting_sync_dimension_value"(uuid, text, text, text, text, boolean) from public, anon, authenticated;

-- What keeps a period from closing: draft entries dated in it.
create or replace function "better_supabase"."accounting_period_close_blockers"(period_id uuid)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(array_remove(array[
    case when exists (
      select 1 from "better_supabase"."accounting_entries" y
      where y."tenant_id" = x."tenant_id" and y."status" = 'draft'
        and y."entry_date" >= x."starts_on" and y."entry_date" <= x."ends_on"
    ) then 'draft_entries' end
  ], null), '{}'::text[])
  from "better_supabase"."accounting_periods" x where x."id" = accounting_period_close_blockers.period_id
$$;
revoke execute on function "better_supabase"."accounting_period_close_blockers"(uuid) from public, anon;
grant execute on function "better_supabase"."accounting_period_close_blockers"(uuid) to authenticated, service_role;

-- Closes a period: nothing posts into it until it reopens. Closing a closed
-- period returns it unchanged.
create or replace function "better_supabase"."close_accounting_period"(period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_blockers text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = close_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to close accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if v_period."status" = 'closed' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by");
  end if;
  v_blockers := "better_supabase"."accounting_period_close_blockers"(v_period."id");
  if cardinality(v_blockers) > 0 then
    raise exception 'the period can''t close yet: %', array_to_string(v_blockers, ', ') using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSE_BLOCKED';
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
    where y."id" = v_period."id"
    returning * into v_period;
    null;
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by");
end;
$$;
revoke execute on function "better_supabase"."close_accounting_period"(uuid) from public, anon;
grant execute on function "better_supabase"."close_accounting_period"(uuid) to authenticated, service_role;

-- Reopens a closed period with a reason. A period on or before the lock date
-- stays closed; move the lock date first.
create or replace function "better_supabase"."reopen_accounting_period"(period_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = reopen_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to reopen accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if nullif(trim(reopen_accounting_period.reason), '') is null then
    raise exception 'reopening a period needs a reason' using errcode = '22023', hint = 'ACCOUNTING_PERIOD_INVALID';
  end if;
  if v_period."status" = 'open' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by");
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_period."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  if v_settings."lock_date" is not null and v_period."starts_on" <= v_settings."lock_date" then
    raise exception 'the period is on or before the lock date' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSED';
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'open', "closed_at" = null, "closed_by" = null
  where y."id" = v_period."id"
  returning * into v_period;
  null;
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by");
end;
$$;
revoke execute on function "better_supabase"."reopen_accounting_period"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_accounting_period"(uuid, text) to authenticated, service_role;

-- Closes a fiscal year: one closing entry in the first general journal moves
-- every income and expense balance to the retained earnings account, then
-- every period of the year closes. Reverse the closing entry to redo it.
create or replace function "better_supabase"."close_fiscal_year"(tenant uuid, fiscal_year integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_starts date;
  v_ends date;
  v_open integer;
  v_retained uuid;
  v_journal uuid;
  v_entry "better_supabase"."accounting_entries"%rowtype;
  v_net numeric;
  v_count integer;
  v_closing uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_fiscal_year.tenant, 'accounting.close'), false)) then
    raise exception 'not allowed to close fiscal years' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = close_fiscal_year.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  select min(y."starts_on"), max(y."ends_on"), count(*) filter (where y."status" = 'open')
  into v_starts, v_ends, v_open
  from "better_supabase"."accounting_periods" y where y."tenant_id" = close_fiscal_year.tenant and y."fiscal_year" = close_fiscal_year.fiscal_year;
  if v_starts is null then
    raise exception 'the fiscal year has no periods; open it first' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(close_fiscal_year.tenant::text || ':fiscal_year:' || close_fiscal_year.fiscal_year::text, 0));
  if exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = close_fiscal_year.tenant and y."source_type" = 'fiscal_year'
      and y."source_id" = close_fiscal_year.fiscal_year::text and y."status" <> 'reversed'
  ) then
    raise exception 'the fiscal year is already closed; reverse its closing entry to close it again' using errcode = '55000', hint = 'FISCAL_YEAR_CLOSED';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = close_fiscal_year.tenant and y."status" = 'draft'
      and y."entry_date" >= v_starts and y."entry_date" <= v_ends
  ) then
    raise exception 'the fiscal year can''t close yet: draft_entries' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSE_BLOCKED';
  end if;
  select y."account_id" into v_retained from "better_supabase"."accounting_account_roles" y
  where y."tenant_id" = close_fiscal_year.tenant and y."role" = 'retained_earnings';
  if v_retained is null then
    raise exception 'no account has the retained_earnings role' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_ROLE_MISSING';
  end if;
  select y."id" into v_journal from "better_supabase"."accounting_journals" y
  where y."tenant_id" = close_fiscal_year.tenant and y."type" = 'general'
  order by y."code" limit 1;
  if v_journal is null then
    raise exception 'the year-end close needs a general journal' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  select count(*), coalesce(sum(c.net), 0) into v_count, v_net from (select y."account_id" as account, sum(y."debit") - sum(y."credit") as net
    from "better_supabase"."accounting_entry_lines" y
    join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
    where z."tenant_id" = close_fiscal_year.tenant and z."fiscal_year" = close_fiscal_year.fiscal_year
      and z."status" in ('posted', 'reversed') and w."type" in ('income', 'expense')
    group by y."account_id"
    having sum(y."debit") <> sum(y."credit")) c;
  if v_count > 0 then
    insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "source_type", "source_id", "memo", "created_by")
    values (close_fiscal_year.tenant, v_journal, v_ends, 'fiscal_year', close_fiscal_year.fiscal_year::text,
      'Closing of fiscal year ' || close_fiscal_year.fiscal_year::text, auth.uid())
    returning * into v_entry;
    insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency", "amount_currency")
    select close_fiscal_year.tenant, v_entry."id", (row_number() over (order by w."code"))::smallint, c.account,
      greatest(-c.net, 0)::bigint, greatest(c.net, 0)::bigint, v_settings."functional_currency", (-c.net)::bigint
    from (select y."account_id" as account, sum(y."debit") - sum(y."credit") as net
    from "better_supabase"."accounting_entry_lines" y
    join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
    where z."tenant_id" = close_fiscal_year.tenant and z."fiscal_year" = close_fiscal_year.fiscal_year
      and z."status" in ('posted', 'reversed') and w."type" in ('income', 'expense')
    group by y."account_id"
    having sum(y."debit") <> sum(y."credit")) c join "better_supabase"."accounting_accounts" w on w."id" = c.account;
    if v_net <> 0 then
      insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency", "amount_currency")
      values (close_fiscal_year.tenant, v_entry."id", 32767, v_retained,
        greatest(v_net, 0)::bigint, greatest(-v_net, 0)::bigint, v_settings."functional_currency", v_net::bigint);
    end if;
    v_entry := "better_supabase"."accounting_post"(v_entry."id", true);
    v_closing := v_entry."id";
  elsif v_open = 0 then
    raise exception 'the fiscal year is already closed' using errcode = '55000', hint = 'FISCAL_YEAR_CLOSED';
  end if;
  for v_period in
    select * from "better_supabase"."accounting_periods" y
    where y."tenant_id" = close_fiscal_year.tenant and y."fiscal_year" = close_fiscal_year.fiscal_year and y."status" = 'open'
    order by y."number"
    for update
  loop
    update "better_supabase"."accounting_periods" y set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
    where y."id" = v_period."id"
    returning * into v_period;
    null;
  end loop;
  null;
  return jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing);
end;
$$;
revoke execute on function "better_supabase"."close_fiscal_year"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."close_fiscal_year"(uuid, integer) to authenticated, service_role;

-- Per account: the balance before since, the debits and credits from since
-- through until, and the closing balance; debit balances are positive. Lines
-- match when their dimensions contain the dimensions filter.
create or replace function "better_supabase"."accounting_trial_balance"(tenant uuid, since date default null, until date default null, dimensions jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with sums as (
    select y."account_id" as account,
      sum(case when z."entry_date" < accounting_trial_balance.since then y."debit" - y."credit" else 0 end) as opening,
      sum(case when accounting_trial_balance.since is null or z."entry_date" >= accounting_trial_balance.since then y."debit" else 0 end) as debit,
      sum(case when accounting_trial_balance.since is null or z."entry_date" >= accounting_trial_balance.since then y."credit" else 0 end) as credit
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_trial_balance.tenant and z."status" in ('posted', 'reversed')
      and y."dimensions" @> coalesce(accounting_trial_balance.dimensions, '{}'::jsonb)
      and (accounting_trial_balance.until is null or z."entry_date" <= accounting_trial_balance.until)
    group by y."account_id"
  )
  select jsonb_build_object(
    'accounts', coalesce(jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type",
      'opening', c.opening::text, 'debit', c.debit::text, 'credit', c.credit::text, 'closing', (c.opening + c.debit - c.credit)::text) order by w."code"), '[]'::jsonb),
    'totals', jsonb_build_object('opening', coalesce(sum(c.opening), 0)::text, 'debit', coalesce(sum(c.debit), 0)::text, 'credit', coalesce(sum(c.credit), 0)::text,
      'closing', coalesce(sum(c.opening + c.debit - c.credit), 0)::text)
  )
  from sums c join "better_supabase"."accounting_accounts" w on w."id" = c.account
$$;
revoke execute on function "better_supabase"."accounting_trial_balance"(uuid, date, date, jsonb) from public, anon;
grant execute on function "better_supabase"."accounting_trial_balance"(uuid, date, date, jsonb) to authenticated, service_role;

-- Income and expenses from since through until, without year-end closing
-- entries. Income counts credits, expenses debits.
create or replace function "better_supabase"."accounting_profit_and_loss"(tenant uuid, since date default null, until date default null, dimensions jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with sums as (
    select y."account_id" as account, sum(y."credit") - sum(y."debit") as credit_balance
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_profit_and_loss.tenant and z."status" in ('posted', 'reversed')
      and y."dimensions" @> coalesce(accounting_profit_and_loss.dimensions, '{}'::jsonb)
      and z."source_type" is distinct from 'fiscal_year'
      and (accounting_profit_and_loss.since is null or z."entry_date" >= accounting_profit_and_loss.since)
      and (accounting_profit_and_loss.until is null or z."entry_date" <= accounting_profit_and_loss.until)
    group by y."account_id"
  ),
  kept as (
    select w.*, c.credit_balance from sums c join "better_supabase"."accounting_accounts" w on w."id" = c.account
    where w."type" in ('income', 'expense') and c.credit_balance <> 0
  )
  select jsonb_build_object(
    'income', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (w.credit_balance)::text) order by w."code") from kept w where w."type" = 'income'), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (-w.credit_balance)::text) order by w."code") from kept w where w."type" = 'expense'), '[]'::jsonb),
    'totalIncome', coalesce((select sum(w.credit_balance) from kept w where w."type" = 'income'), 0)::text,
    'totalExpenses', coalesce((select -sum(w.credit_balance) from kept w where w."type" = 'expense'), 0)::text,
    'netIncome', coalesce((select sum(w.credit_balance) from kept w), 0)::text
  )
$$;
revoke execute on function "better_supabase"."accounting_profit_and_loss"(uuid, date, date, jsonb) from public, anon;
grant execute on function "better_supabase"."accounting_profit_and_loss"(uuid, date, date, jsonb) to authenticated, service_role;

-- Assets, liabilities and equity on as_of. Income and expenses not yet
-- closed into retained earnings count as current earnings under equity.
create or replace function "better_supabase"."accounting_balance_sheet"(tenant uuid, as_of date default null, dimensions jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with sums as (
    select y."account_id" as account, sum(y."debit") - sum(y."credit") as debit_balance
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_balance_sheet.tenant and z."status" in ('posted', 'reversed')
      and y."dimensions" @> coalesce(accounting_balance_sheet.dimensions, '{}'::jsonb)
      and z."entry_date" <= coalesce(accounting_balance_sheet.as_of, current_date)
    group by y."account_id"
  ),
  kept as (
    select w.*, c.debit_balance from sums c join "better_supabase"."accounting_accounts" w on w."id" = c.account
    where c.debit_balance <> 0
  ),
  totals as (
    select
      coalesce(sum(w.debit_balance) filter (where w."type" = 'asset'), 0) as assets,
      coalesce(-sum(w.debit_balance) filter (where w."type" = 'liability'), 0) as liabilities,
      coalesce(-sum(w.debit_balance) filter (where w."type" = 'equity'), 0) as equity,
      coalesce(-sum(w.debit_balance) filter (where w."type" in ('income', 'expense')), 0) as earnings
    from kept w
  )
  select jsonb_build_object(
    'asOf', coalesce(accounting_balance_sheet.as_of, current_date),
    'assets', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (w.debit_balance)::text) order by w."code") from kept w where w."type" = 'asset'), '[]'::jsonb),
    'liabilities', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (-w.debit_balance)::text) order by w."code") from kept w where w."type" = 'liability'), '[]'::jsonb),
    'equity', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (-w.debit_balance)::text) order by w."code") from kept w where w."type" = 'equity'), '[]'::jsonb),
    'currentEarnings', t.earnings::text,
    'totalAssets', t.assets::text,
    'totalLiabilities', t.liabilities::text,
    'totalEquity', (t.equity + t.earnings)::text,
    'balanced', t.assets = t.liabilities + t.equity + t.earnings
  )
  from totals t
$$;
revoke execute on function "better_supabase"."accounting_balance_sheet"(uuid, date, jsonb) from public, anon;
grant execute on function "better_supabase"."accounting_balance_sheet"(uuid, date, jsonb) to authenticated, service_role;

-- One account's posted lines from since through until with a running
-- balance; debit balances are positive.
create or replace function "better_supabase"."accounting_general_ledger"(account_id uuid, since date default null, until date default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with account as (
    select w.* from "better_supabase"."accounting_accounts" w where w."id" = accounting_general_ledger.account_id
  ),
  booked as (
    select y.*, z."entry_date" as entry_date, z."number" as entry_number, z."journal_id" as journal_id, z."memo" as memo
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where y."account_id" = accounting_general_ledger.account_id and z."status" in ('posted', 'reversed')
      and (accounting_general_ledger.until is null or z."entry_date" <= accounting_general_ledger.until)
  ),
  opening as (
    select coalesce(sum(b."debit" - b."credit"), 0) as amount from booked b
    where b.entry_date < accounting_general_ledger.since
  ),
  period as (
    select b.*, (select o.amount from opening o) + sum(b."debit" - b."credit") over (order by b.entry_date, b.entry_number, b."position", b."id") as balance
    from booked b
    where accounting_general_ledger.since is null or b.entry_date >= accounting_general_ledger.since
  )
  select jsonb_build_object(
    'account', jsonb_build_object('id', w."id", 'code', w."code", 'name', w."name", 'type', w."type"),
    'opening', (select o.amount from opening o)::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('entryId', b."entry_id", 'number', b.entry_number, 'entryDate', b.entry_date, 'journalId', b.journal_id,
      'description', coalesce(b."description", b.memo), 'partyId', b."party_id", 'debit', b."debit"::text, 'credit', b."credit"::text, 'balance', b.balance::text)
      order by b.entry_date, b.entry_number, b."position", b."id") from period b), '[]'::jsonb),
    'closing', ((select o.amount from opening o) + coalesce((select sum(b."debit" - b."credit") from period b), 0))::text
  )
  from account w
$$;
revoke execute on function "better_supabase"."accounting_general_ledger"(uuid, date, date) from public, anon;
grant execute on function "better_supabase"."accounting_general_ledger"(uuid, date, date) to authenticated, service_role;

-- The tax return of a date range: a line with a tax code counts as tax when it
-- is on the code's account and as base otherwise. Sales count credits and
-- purchases debits, so a credit note lowers both.
create or replace function "better_supabase"."accounting_tax_report"(tenant uuid, since date, until date)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with booked as (
    select y."tax_code_id" as tax_code, y."account_id" as account, y."credit" - y."debit" as net
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_tax_report.tenant and z."status" in ('posted', 'reversed')
      and y."tax_code_id" is not null
      and z."entry_date" >= accounting_tax_report.since and z."entry_date" <= accounting_tax_report.until
  ),
  codes as (
    select w."id" as id, w."code" as code, w."name" as name, w."kind" as kind,
      w."rate_bps" as rate_bps, w."report_boxes" as boxes,
      (case when w."kind" = 'sales' then 1 else -1 end) * coalesce(sum(b.net) filter (where b.account <> w."account_id"), 0) as base,
      (case when w."kind" = 'sales' then 1 else -1 end) * coalesce(sum(b.net) filter (where b.account = w."account_id"), 0) as tax
    from booked b join "better_supabase"."accounting_tax_codes" w on w."id" = b.tax_code
    group by w."id"
  )
  select jsonb_build_object(
    'organizationId', accounting_tax_report.tenant,
    'since', accounting_tax_report.since,
    'until', accounting_tax_report.until,
    'currency', (select st."functional_currency" from "better_supabase"."accounting_settings" st where st."tenant_id" = accounting_tax_report.tenant),
    'codes', coalesce((select jsonb_agg(jsonb_build_object('taxCodeId', c.id, 'code', c.code, 'name', c.name, 'kind', c.kind,
      'rateBps', c.rate_bps, 'reportBoxes', to_jsonb(c.boxes), 'base', c.base::text, 'tax', c.tax::text) order by c.code) from codes c), '[]'::jsonb),
    'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box)
      from (select q.box, sum(c.base) as base, sum(c.tax) as tax from codes c cross join unnest(c.boxes) q(box) group by q.box) x), '[]'::jsonb),
    'salesTax', coalesce((select sum(c.tax) from codes c where c.kind = 'sales'), 0)::text,
    'purchaseTax', coalesce((select sum(c.tax) from codes c where c.kind = 'purchase'), 0)::text,
    'netTax', coalesce((select sum(case when c.kind = 'sales' then c.tax else -c.tax end) from codes c), 0)::text
  )
$$;
revoke execute on function "better_supabase"."accounting_tax_report"(uuid, date, date) from public, anon;
grant execute on function "better_supabase"."accounting_tax_report"(uuid, date, date) to authenticated, service_role;

create table if not exists "better_supabase"."accounting_budgets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") >= 1 and length("name") <= 200),
  "fiscal_year" integer not null check ("fiscal_year" >= 1900 and "fiscal_year" <= 9999),
  "status" text not null default 'draft' check ("status" in ('draft', 'approved', 'archived')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "fiscal_year", "name")
);
alter table "better_supabase"."accounting_budgets" enable row level security;
revoke all on "better_supabase"."accounting_budgets" from public, anon, authenticated;
grant select on "better_supabase"."accounting_budgets" to authenticated;
grant all on "better_supabase"."accounting_budgets" to service_role;
drop policy if exists accounting_budgets_read on "better_supabase"."accounting_budgets";
create policy accounting_budgets_read on "better_supabase"."accounting_budgets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

create table if not exists "better_supabase"."accounting_budget_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "budget_id" uuid not null references "better_supabase"."accounting_budgets" ("id") on delete cascade,
  "account_id" uuid not null references "better_supabase"."accounting_accounts" ("id") on delete restrict,
  -- The period of the budget's fiscal year, 1 to 12.
  "period_number" smallint not null check ("period_number" >= 1 and "period_number" <= 12),
  -- The dimension values the amount is for; actuals match lines that carry them.
  "dimensions" jsonb not null default '{}'::jsonb check (jsonb_typeof("dimensions") = 'object'),
  -- Minor units of the functional currency, in the account's natural sign.
  "amount" bigint not null,
  unique ("budget_id", "account_id", "period_number", "dimensions")
);
create index if not exists "accounting_budget_lines_account_idx" on "better_supabase"."accounting_budget_lines" ("account_id");
alter table "better_supabase"."accounting_budget_lines" enable row level security;
revoke all on "better_supabase"."accounting_budget_lines" from public, anon, authenticated;
grant select on "better_supabase"."accounting_budget_lines" to authenticated;
grant all on "better_supabase"."accounting_budget_lines" to service_role;
drop policy if exists accounting_budget_lines_read on "better_supabase"."accounting_budget_lines";
create policy accounting_budget_lines_read on "better_supabase"."accounting_budget_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')));

-- Creates a budget, or renames it, moves its status (draft, approved,
-- archived) and, when lines is given, replaces its lines. Each line names an
-- account (accountId or accountCode), a periodNumber, an amount and optional
-- dimensions.
create or replace function "better_supabase"."save_accounting_budget"(tenant uuid, name text, fiscal_year integer, status text default null, lines jsonb default null, budget_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_budgets"%rowtype;
  v_line record;
  v_account uuid;
  v_created boolean := save_accounting_budget.budget_id is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_budget.tenant, 'accounting.write'), false)) then
    raise exception 'not allowed to write budgets' using errcode = '42501', hint = 'ACCOUNTING_BUDGET_FORBIDDEN';
  end if;
  if length(trim(coalesce(save_accounting_budget.name, ''))) not between 1 and 200
    or coalesce(save_accounting_budget.fiscal_year, 0) not between 1900 and 9999 then
    raise exception 'a budget needs a name of 1 to 200 characters and a fiscal year' using errcode = '22023', hint = 'ACCOUNTING_BUDGET_INVALID';
  end if;
  if coalesce(save_accounting_budget.status, 'draft') not in ('draft', 'approved', 'archived') then
    raise exception 'status must be draft, approved or archived' using errcode = '22023', hint = 'ACCOUNTING_BUDGET_INVALID';
  end if;
  if save_accounting_budget.lines is not null and jsonb_typeof(save_accounting_budget.lines) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'ACCOUNTING_BUDGET_INVALID';
  end if;
  if v_created then
    insert into "better_supabase"."accounting_budgets" ("tenant_id", "name", "fiscal_year", "status", "created_by")
    values (save_accounting_budget.tenant, trim(save_accounting_budget.name), save_accounting_budget.fiscal_year,
      coalesce(save_accounting_budget.status, 'draft'), auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."accounting_budgets" y set "name" = trim(save_accounting_budget.name), "fiscal_year" = save_accounting_budget.fiscal_year,
      "status" = coalesce(save_accounting_budget.status, y."status"), "updated_at" = now()
    where y."id" = save_accounting_budget.budget_id and y."tenant_id" = save_accounting_budget.tenant
    returning * into v_row;
    if not found then
      raise exception 'budget not found' using errcode = 'P0002', hint = 'ACCOUNTING_BUDGET_NOT_FOUND';
    end if;
  end if;
  if save_accounting_budget.lines is not null then
    delete from "better_supabase"."accounting_budget_lines" y where y."budget_id" = v_row."id";
    for v_line in select q.value from jsonb_array_elements(save_accounting_budget.lines) q loop
      if jsonb_typeof(v_line.value) is distinct from 'object'
        or coalesce(v_line.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_line.value ->> 'periodNumber', '') !~ '^([1-9]|1[0-2])$'
        or (v_line.value ? 'dimensions' and jsonb_typeof(v_line.value -> 'dimensions') <> 'object') then
        raise exception 'every line has an account, a periodNumber from 1 to 12, an integer amount and dimensions as an object' using errcode = '22023', hint = 'ACCOUNTING_BUDGET_INVALID';
      end if;
      select y."id" into v_account from "better_supabase"."accounting_accounts" y
      where y."tenant_id" = v_row."tenant_id"
        and (y."id"::text = v_line.value ->> 'accountId' or y."code" = v_line.value ->> 'accountCode');
      if v_account is null then
        raise exception 'a budget line''s account doesn''t exist here' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
      end if;
      insert into "better_supabase"."accounting_budget_lines" ("tenant_id", "budget_id", "account_id", "period_number", "dimensions", "amount")
      values (v_row."tenant_id", v_row."id", v_account, (v_line.value ->> 'periodNumber')::smallint,
        coalesce(v_line.value -> 'dimensions', '{}'::jsonb), (v_line.value ->> 'amount')::bigint)
      on conflict ("budget_id", "account_id", "period_number", "dimensions")
      do update set "amount" = "better_supabase"."accounting_budget_lines"."amount" + excluded."amount";
      v_account := null;
    end loop;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'fiscalYear', v_row."fiscal_year", 'status', v_row."status", 'total', coalesce((select sum(bt."amount") from "better_supabase"."accounting_budget_lines" bt where bt."budget_id" = v_row."id"), 0)::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', bx."id", 'accountId', bx."account_id", 'accountCode', ba."code", 'periodNumber', bx."period_number", 'dimensions', bx."dimensions", 'amount', bx."amount"::text) order by ba."code", bx."period_number", bx."id") from "better_supabase"."accounting_budget_lines" bx join "better_supabase"."accounting_accounts" ba on ba."id" = bx."account_id" where bx."budget_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."save_accounting_budget"(uuid, text, integer, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_accounting_budget"(uuid, text, integer, text, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_accounting_budget"(budget_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'fiscalYear', x."fiscal_year", 'status', x."status", 'total', coalesce((select sum(bt."amount") from "better_supabase"."accounting_budget_lines" bt where bt."budget_id" = x."id"), 0)::text, 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', bx."id", 'accountId', bx."account_id", 'accountCode', ba."code", 'periodNumber', bx."period_number", 'dimensions', bx."dimensions", 'amount', bx."amount"::text) order by ba."code", bx."period_number", bx."id") from "better_supabase"."accounting_budget_lines" bx join "better_supabase"."accounting_accounts" ba on ba."id" = bx."account_id" where bx."budget_id" = x."id"), '[]'::jsonb)) from "better_supabase"."accounting_budgets" x where x."id" = get_accounting_budget.budget_id
$$;
revoke execute on function "better_supabase"."get_accounting_budget"(uuid) from public, anon;
grant execute on function "better_supabase"."get_accounting_budget"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_accounting_budgets"(tenant uuid, fiscal_year integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'fiscalYear', x."fiscal_year", 'status', x."status", 'total', coalesce((select sum(bt."amount") from "better_supabase"."accounting_budget_lines" bt where bt."budget_id" = x."id"), 0)::text, 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."fiscal_year" desc, x."name"), '[]'::jsonb)
  from "better_supabase"."accounting_budgets" x
  where x."tenant_id" = list_accounting_budgets.tenant
    and (list_accounting_budgets.fiscal_year is null or x."fiscal_year" = list_accounting_budgets.fiscal_year)
$$;
revoke execute on function "better_supabase"."list_accounting_budgets"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_accounting_budgets"(uuid, integer) to authenticated, service_role;

-- The budget of each account and dimension set next to what posted entries
-- booked in the same periods of the fiscal year (one period, or all of them),
-- both in the account's natural sign, without year-end closing entries.
create or replace function "better_supabase"."accounting_budget_vs_actual"(budget_id uuid, period_number integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with budget as (
    select x.* from "better_supabase"."accounting_budgets" x where x."id" = accounting_budget_vs_actual.budget_id
  ),
  planned as (
    select y."account_id" as account, y."dimensions" as dimensions, sum(y."amount") as amount
    from "better_supabase"."accounting_budget_lines" y
    where y."budget_id" = accounting_budget_vs_actual.budget_id
      and (accounting_budget_vs_actual.period_number is null or y."period_number" = accounting_budget_vs_actual.period_number)
    group by y."account_id", y."dimensions"
  ),
  compared as (
    select q.account, q.dimensions, q.amount as budget, ac."code" as code, ac."name" as name, ac."type" as type,
      coalesce((
        select sum(case when ac."type" in ('liability', 'equity', 'income') then z."credit" - z."debit" else z."debit" - z."credit" end)
        from "better_supabase"."accounting_entry_lines" z
        join "better_supabase"."accounting_entries" w on w."id" = z."entry_id"
        join "better_supabase"."accounting_periods" v on v."id" = w."period_id"
        cross join budget g
        where z."account_id" = q.account and z."dimensions" @> q.dimensions
          and w."status" in ('posted', 'reversed') and w."source_type" is distinct from 'fiscal_year'
          and v."tenant_id" = g."tenant_id" and v."fiscal_year" = g."fiscal_year"
          and (accounting_budget_vs_actual.period_number is null or v."number" = accounting_budget_vs_actual.period_number)
      ), 0) as actual
    from planned q join "better_supabase"."accounting_accounts" ac on ac."id" = q.account
  )
  select jsonb_build_object(
    'budgetId', g."id",
    'name', g."name",
    'fiscalYear', g."fiscal_year",
    'periodNumber', accounting_budget_vs_actual.period_number,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('accountId', c.account, 'code', c.code, 'name', c.name, 'type', c.type,
      'dimensions', c.dimensions, 'budget', c.budget::text, 'actual', c.actual::text, 'variance', (c.actual - c.budget)::text)
      order by c.code, c.dimensions::text) from compared c), '[]'::jsonb),
    'budget', coalesce((select sum(c.budget) from compared c), 0)::text,
    'actual', coalesce((select sum(c.actual) from compared c), 0)::text
  )
  from budget g
$$;
revoke execute on function "better_supabase"."accounting_budget_vs_actual"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."accounting_budget_vs_actual"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_settings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_settings";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_settings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_settings";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_settings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_settings";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_settings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_settings";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_settings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_accounts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_accounts";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_accounts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_accounts";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_accounts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_accounts";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_accounts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_accounts";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_accounts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_account_roles";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_account_roles";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_account_roles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_account_roles";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_account_roles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_account_roles";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_account_roles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_account_roles";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_account_roles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_journals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_journals";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_journals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_journals";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_journals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_journals";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_journals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_journals";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_journals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_periods";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_periods";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_periods" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_periods";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_periods" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_periods";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_periods" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_periods";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_periods" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_entries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_entries";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_entries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_entries";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_entries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_entries";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_entries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_entries";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_entries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_entry_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_entry_lines";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_entry_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_entry_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_entry_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_entry_lines";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_entry_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_entry_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_entry_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_dimensions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_dimensions";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_dimensions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_dimensions";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_dimensions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_dimensions";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_dimensions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_dimensions";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_dimensions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_dimension_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_dimension_values";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_dimension_values" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_dimension_values";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_dimension_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_dimension_values";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_dimension_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_dimension_values";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_dimension_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_fx_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_fx_rates";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_fx_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_fx_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_fx_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_fx_rates";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_fx_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_fx_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_fx_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_tax_codes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_tax_codes";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_tax_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_tax_codes";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_tax_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_tax_codes";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_tax_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_tax_codes";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_tax_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_budgets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_budgets";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_budgets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_budgets";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_budgets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_budgets";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_budgets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_budgets";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_budgets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."accounting_budget_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."accounting_budget_lines";
create policy bsb_tenant_scope_select on "better_supabase"."accounting_budget_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('accounting.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."accounting_budget_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."accounting_budget_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."accounting_budget_lines";
create policy bsb_tenant_scope_update on "better_supabase"."accounting_budget_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."accounting_budget_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."accounting_budget_lines" as restrictive
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

-- ==== data supabase/better-supabase-data/900_better_supabase_146_accounting.sql
-- better-supabase module: accounting
-- @bsb-block-data accounting
-- @bsb-hash sha256:51851417a9dc349b1d7c5a2e3bd03d12ebf0417519b093f85ae57b6e24866f4a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Adds the disposal gain and loss accounts to existing charts of accounts.
insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable")
select s."tenant_id", c.code, c.name, c.type, c.subtype, false
from "better_supabase"."accounting_settings" s
cross join (values ('disposal_gain', '4910', 'Gains on asset disposals', 'income', 'other_income'), ('disposal_loss', '6910', 'Losses on asset disposals', 'expense', 'other_expense')) c (role, code, name, type, subtype)
where exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = s."tenant_id")
  and not exists (select 1 from "better_supabase"."accounting_account_roles" z where z."tenant_id" = s."tenant_id" and z."role" = c.role)
  and not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = s."tenant_id" and y."code" = c.code);
insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
select s."tenant_id", c.role, y."id"
from "better_supabase"."accounting_settings" s
cross join (values ('disposal_gain', '4910', 'Gains on asset disposals'), ('disposal_loss', '6910', 'Losses on asset disposals')) c (role, code, name)
join "better_supabase"."accounting_accounts" y on y."tenant_id" = s."tenant_id" and y."code" = c.code and y."name" = c.name
where not exists (select 1 from "better_supabase"."accounting_account_roles" z where z."tenant_id" = s."tenant_id" and z."role" = c.role)
on conflict ("tenant_id", "role") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('accounting', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
