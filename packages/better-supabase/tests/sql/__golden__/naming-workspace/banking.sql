-- ==== schema supabase/schemas/900_better_supabase_155_banking.sql
-- better-supabase module: banking
-- @bsb-block banking@1 managed
-- @bsb-hash sha256:a510dfddb32fd21309787f0edee9ff51ff54d18af51d032fa2bba087b2ca1232
-- Bank accounts with imported CAMT.053, MT940 and feed statements, matches of each transaction to invoices, expense reports and accounting entries with suggestions from RF and Dutch payment references, bank rules that book or set aside what they match, and a reconciliation status per account against the ledger.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."bank_accounts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_accounts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_accounts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_accounts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_accounts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."bank_rules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_rules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_rules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_rules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."bank_statements";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_statements";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_statements";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_statements";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_statements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."bank_transactions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_transactions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_transactions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_transactions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_transactions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."bank_matches";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_matches";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_matches";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_matches";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_matches";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Banking per organization: bank accounts, imported statements and their
-- transactions, matches to invoices, expense reports and accounting entries,
-- bank rules that book or set aside what they match, and reconciliation.

create table if not exists "better_supabase"."bank_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  -- Upper case without spaces; save_bank_account checks the ISO 13616 digits.
  "iban" text check ("iban" is null or "iban" ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
  "bic" text check ("bic" is null or "bic" ~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$'),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  -- The accounting journal the account's money moves through.
  "journal_id" uuid,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create unique index if not exists "bank_accounts_iban_key" on "better_supabase"."bank_accounts" ("tenant_id", "iban") where "iban" is not null;
create index if not exists "bank_accounts_tenant_idx" on "better_supabase"."bank_accounts" ("tenant_id", "name");
create index if not exists "bank_accounts_journal_idx" on "better_supabase"."bank_accounts" ("journal_id") where "journal_id" is not null;
alter table "better_supabase"."bank_accounts" enable row level security;
revoke all on "better_supabase"."bank_accounts" from public, anon, authenticated;
grant select on "better_supabase"."bank_accounts" to authenticated;
grant all on "better_supabase"."bank_accounts" to service_role;
drop policy if exists bank_accounts_read on "better_supabase"."bank_accounts";
create policy bank_accounts_read on "better_supabase"."bank_accounts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')));

create table if not exists "better_supabase"."bank_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  -- A filter tree (ADR 0046) over the transaction: amount, currency,
  -- counterpartyName, counterpartyIban, remittance and the rest.
  "conditions" jsonb not null default '{"type":"group","combinator":"and","rules":[]}'::jsonb,
  -- The ledger account a match books against; without one the rule ignores
  -- the transaction.
  "account_id" uuid,
  -- The party the booked line carries.
  "party_id" uuid,
  "dimensions" jsonb not null default '{}'::jsonb check (jsonb_typeof("dimensions") = 'object'),
  -- Lower runs first.
  "priority" integer not null default 100,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "bank_rules_tenant_idx" on "better_supabase"."bank_rules" ("tenant_id", "priority") where "active";
create index if not exists "bank_rules_account_idx" on "better_supabase"."bank_rules" ("account_id") where "account_id" is not null;
alter table "better_supabase"."bank_rules" enable row level security;
revoke all on "better_supabase"."bank_rules" from public, anon, authenticated;
grant select on "better_supabase"."bank_rules" to authenticated;
grant all on "better_supabase"."bank_rules" to service_role;
drop policy if exists bank_rules_read on "better_supabase"."bank_rules";
create policy bank_rules_read on "better_supabase"."bank_rules"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')));

create table if not exists "better_supabase"."bank_statements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null,
  -- The bank's statement id; an import with the same reference adds to it.
  "reference" text check ("reference" is null or length("reference") between 1 and 200),
  "from_on" date,
  "until_on" date,
  -- Minor units of the account's currency.
  "opening_balance" bigint,
  "closing_balance" bigint,
  "format" text not null check ("format" in ('camt053', 'mt940', 'csv', 'feed')),
  -- The file it was read from.
  "attachment_id" uuid,
  "imported_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("from_on" is null or "until_on" is null or "from_on" <= "until_on"),
  foreign key ("tenant_id", "account_id") references "better_supabase"."bank_accounts" ("tenant_id", "id") on delete cascade
);
create unique index if not exists "bank_statements_reference_key" on "better_supabase"."bank_statements" ("account_id", "reference") where "reference" is not null;
create index if not exists "bank_statements_parent_idx" on "better_supabase"."bank_statements" ("tenant_id", "account_id", "until_on");
create index if not exists "bank_statements_attachment_idx" on "better_supabase"."bank_statements" ("attachment_id") where "attachment_id" is not null;
alter table "better_supabase"."bank_statements" enable row level security;
revoke all on "better_supabase"."bank_statements" from public, anon, authenticated;
grant select on "better_supabase"."bank_statements" to authenticated;
grant all on "better_supabase"."bank_statements" to service_role;
drop policy if exists bank_statements_read on "better_supabase"."bank_statements";
create policy bank_statements_read on "better_supabase"."bank_statements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')));

create table if not exists "better_supabase"."bank_transactions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "account_id" uuid not null,
  "statement_id" uuid,
  "booked_on" date not null,
  "value_on" date,
  -- Minor units, negative for money out.
  "amount" bigint not null check ("amount" <> 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "counterparty_name" text check ("counterparty_name" is null or length("counterparty_name") <= 500),
  "counterparty_iban" text check ("counterparty_iban" is null or length("counterparty_iban") <= 34),
  -- The unstructured remittance information.
  "remittance" text check ("remittance" is null or length("remittance") <= 2000),
  -- An ISO 11649 RF creditor reference or a national one, such as a Dutch
  -- betalingskenmerk.
  "structured_reference" text check ("structured_reference" is null or length("structured_reference") <= 100),
  "end_to_end_id" text check ("end_to_end_id" is null or length("end_to_end_id") <= 100),
  -- The bank's id of the entry; importing it again adds nothing.
  "external_id" text not null check (length("external_id") between 1 and 200),
  "status" text not null default 'unmatched' check ("status" in ('unmatched', 'matched', 'ignored')),
  -- The bank rule that matched or ignored it.
  "rule_id" uuid,
  "matched_at" timestamptz,
  "matched_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  unique ("account_id", "external_id"),
  foreign key ("tenant_id", "account_id") references "better_supabase"."bank_accounts" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "statement_id") references "better_supabase"."bank_statements" ("tenant_id", "id") on delete set null ("statement_id"),
  foreign key ("tenant_id", "rule_id") references "better_supabase"."bank_rules" ("tenant_id", "id") on delete set null ("rule_id")
);
create index if not exists "bank_transactions_parent_idx" on "better_supabase"."bank_transactions" ("tenant_id", "account_id", "booked_on");
create index if not exists "bank_transactions_status_idx" on "better_supabase"."bank_transactions" ("tenant_id", "status", "booked_on");
create index if not exists "bank_transactions_statement_idx" on "better_supabase"."bank_transactions" ("tenant_id", "statement_id") where "statement_id" is not null;
create index if not exists "bank_transactions_rule_idx" on "better_supabase"."bank_transactions" ("tenant_id", "rule_id") where "rule_id" is not null;
create index if not exists "bank_transactions_iban_idx" on "better_supabase"."bank_transactions" ("tenant_id", "counterparty_iban") where "counterparty_iban" is not null;
alter table "better_supabase"."bank_transactions" enable row level security;
revoke all on "better_supabase"."bank_transactions" from public, anon, authenticated;
grant select on "better_supabase"."bank_transactions" to authenticated;
grant all on "better_supabase"."bank_transactions" to service_role;
drop policy if exists bank_transactions_read on "better_supabase"."bank_transactions";
create policy bank_transactions_read on "better_supabase"."bank_transactions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')));

create table if not exists "better_supabase"."bank_matches" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "transaction_id" uuid not null,
  "target_type" text not null check ("target_type" in ('invoice', 'accounting_entry', 'expense_report')),
  "target_id" uuid not null,
  -- Minor units with the transaction's sign; a transaction's matches add up to
  -- its amount.
  "amount" bigint not null check ("amount" <> 0),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  foreign key ("tenant_id", "transaction_id") references "better_supabase"."bank_transactions" ("tenant_id", "id") on delete cascade
);
create index if not exists "bank_matches_parent_idx" on "better_supabase"."bank_matches" ("tenant_id", "transaction_id");
create index if not exists "bank_matches_target_idx" on "better_supabase"."bank_matches" ("target_type", "target_id");
alter table "better_supabase"."bank_matches" enable row level security;
revoke all on "better_supabase"."bank_matches" from public, anon, authenticated;
grant select on "better_supabase"."bank_matches" to authenticated;
grant all on "better_supabase"."bank_matches" to service_role;
drop policy if exists bank_matches_read on "better_supabase"."bank_matches";
create policy bank_matches_read on "better_supabase"."bank_matches"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')));


-- The ISO 7064 MOD 97-10 remainder of letters and digits, letters counting as
-- 10 to 35, as IBAN and ISO 11649 check them. Null for any other character.
create or replace function "better_supabase"."bank_mod97"(value text)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rem integer := 0;
  v_n integer;
  v_char text;
begin
  if value is null or value = '' then
    return null;
  end if;
  foreach v_char in array regexp_split_to_array(value, '') loop
    if v_char between '0' and '9' then
      v_rem := (v_rem * 10 + ascii(v_char) - 48) % 97;
    elsif v_char between 'A' and 'Z' then
      v_n := ascii(v_char) - 55;
      v_rem := (v_rem * 100 + v_n) % 97;
    else
      return null;
    end if;
  end loop;
  return v_rem;
end;
$$;
revoke execute on function "better_supabase"."bank_mod97"(text) from public, anon, authenticated;

-- The payload of a structured payment reference: what follows RF and its
-- check digits in an ISO 11649 creditor reference, or the 15 digits after the
-- check digit of a 16-digit Dutch betalingskenmerk, without leading zeros.
-- Null when the check digits are wrong or the reference is neither.
create or replace function "better_supabase"."bank_reference"(reference text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_ref text := upper(regexp_replace(coalesce(reference, ''), '[^A-Za-z0-9]', '', 'g'));
  v_weights integer[] := array[2, 4, 8, 5, 10, 9, 7, 3, 6, 1, 2, 4, 8, 5, 10];
  v_sum integer := 0;
  v_check integer;
  v_i integer;
begin
  if v_ref ~ '^RF[0-9]{2}[A-Z0-9]{1,21}$' then
    if "better_supabase"."bank_mod97"(substr(v_ref, 5) || substr(v_ref, 1, 4)) = 1 then
      return substr(v_ref, 5);
    end if;
    return null;
  end if;
  if v_ref ~ '^[0-9]{16}$' then
    for v_i in 1..15 loop
      v_sum := v_sum + (ascii(substr(v_ref, 17 - v_i, 1)) - 48) * v_weights[v_i];
    end loop;
    v_check := 11 - v_sum % 11;
    v_check := case v_check when 10 then 1 when 11 then 0 else v_check end;
    if v_check = ascii(substr(v_ref, 1, 1)) - 48 then
      return nullif(ltrim(substr(v_ref, 2), '0'), '');
    end if;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."bank_reference"(text) from public, anon, authenticated;

-- Creates or updates a bank account: name, iban, bic, currency and the
-- accounting journal its money moves through. The IBAN is stored upper case
-- without spaces and must pass its ISO 13616 check digits.
create or replace function "better_supabase"."save_bank_account"(tenant uuid, input jsonb, account_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
  v_iban text;
  v_bic text;
  v_currency text;
  v_journal uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_bank_account.tenant is not null and coalesce(better_supabase.can('tenant', save_bank_account.tenant, 'banking.manage'), false))) then
    raise exception 'not allowed to manage bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if jsonb_typeof(save_bank_account.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  if save_bank_account.account_id is not null then
    select * into v_account from "better_supabase"."bank_accounts" x
    where x."id" = save_bank_account.account_id and x."tenant_id" = save_bank_account.tenant
    for update;
    if not found then
      raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
    end if;
  end if;
  v_iban := case when save_bank_account.input ? 'iban'
    then nullif(upper(regexp_replace(save_bank_account.input ->> 'iban', '\s', '', 'g')), '')
    else v_account."iban" end;
  if v_iban is not null and (v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'
    or "better_supabase"."bank_mod97"(substr(v_iban, 5) || substr(v_iban, 1, 4)) is distinct from 1) then
    raise exception 'the IBAN''s check digits don''t match' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  v_bic := case when save_bank_account.input ? 'bic'
    then nullif(upper(regexp_replace(save_bank_account.input ->> 'bic', '\s', '', 'g')), '')
    else v_account."bic" end;
  if v_bic is not null and v_bic !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then
    raise exception 'a BIC has 8 or 11 letters and digits' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  v_currency := upper(coalesce(save_bank_account.input ->> 'currency', v_account."currency"));
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'a bank account has an ISO 4217 currency' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  if v_account."id" is not null and v_currency <> v_account."currency" and exists (
    select 1 from "better_supabase"."bank_transactions" y where y."account_id" = v_account."id"
  ) then
    raise exception 'a bank account with transactions keeps its currency' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  end if;
  v_journal := case when save_bank_account.input ? 'journalId'
    then nullif(save_bank_account.input ->> 'journalId', '')::uuid
    else v_account."journal_id" end;
  if v_account."id" is null then
    insert into "better_supabase"."bank_accounts" ("tenant_id", "name", "iban", "bic", "currency", "journal_id")
    values (save_bank_account.tenant, trim(save_bank_account.input ->> 'name'), v_iban, v_bic, v_currency, v_journal)
    returning * into v_account;
  else
    update "better_supabase"."bank_accounts" x set
      "name" = coalesce(trim(save_bank_account.input ->> 'name'), x."name"),
      "iban" = v_iban,
      "bic" = v_bic,
      "currency" = v_currency,
      "journal_id" = v_journal,
      "archived_at" = case when save_bank_account.input ? 'archived'
        then case when (save_bank_account.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) end
        else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_account."id"
    returning * into v_account;
  end if;
  return jsonb_build_object('id', v_account."id", 'organizationId', v_account."tenant_id", 'name', v_account."name", 'iban', v_account."iban", 'bic', v_account."bic", 'currency', v_account."currency", 'journalId', v_account."journal_id", 'archivedAt', v_account."archived_at", 'createdAt', v_account."created_at", 'updatedAt', v_account."updated_at");
exception
  when check_violation or not_null_violation then
    raise exception 'a bank account has a name of 1 to 200 characters' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  when unique_violation then
    raise exception 'the organization already has a bank account with this IBAN' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
  when invalid_text_representation then
    raise exception 'journalId must be a uuid' using errcode = '22023', hint = 'BANK_ACCOUNT_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_bank_account"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_bank_account"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_bank_accounts"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_bank_accounts.tenant is not null and coalesce(better_supabase.can('tenant', list_bank_accounts.tenant, 'banking.read'), false))) then
    raise exception 'not allowed to read bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'iban', x."iban", 'bic', x."bic", 'currency', x."currency", 'journalId', x."journal_id", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id")
    from "better_supabase"."bank_accounts" x
    where x."tenant_id" = list_bank_accounts.tenant
      and (list_bank_accounts.include_archived or x."archived_at" is null)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_bank_accounts"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_bank_accounts"(uuid, boolean) to authenticated, service_role;

-- Imports a statement or a feed's page of transactions into a bank account:
-- { reference, fromOn, untilOn, openingBalance, closingBalance, format,
-- attachmentId, transactions: [{ externalId, bookedOn, valueOn, amount,
-- currency, counterpartyName, counterpartyIban, remittance,
-- structuredReference, endToEndId }] }, amounts in minor units. A
-- transaction's externalId is unique per account, so importing the same file
-- or page again adds nothing; without one it is a hash of its fields and its
-- position. A statement reference the account already has adds to that
-- statement.
create or replace function "better_supabase"."import_bank_statement"(account_id uuid, statement jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
  v_statement "better_supabase"."bank_statements"%rowtype;
  v_reference text;
  v_format text;
  v_item record;
  v_amount text;
  v_currency text;
  v_external text;
  v_imported integer := 0;
  v_total integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_account from "better_supabase"."bank_accounts" x where x."id" = import_bank_statement.account_id for update;
  if not found then
    raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_account."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", 'banking.import'), false))) then
    raise exception 'not allowed to do this with bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if v_account."archived_at" is not null then
    raise exception 'an archived bank account takes no statements' using errcode = '22023', hint = 'BANK_STATEMENT_INVALID';
  end if;
  if jsonb_typeof(import_bank_statement.statement) is distinct from 'object'
    or jsonb_typeof(import_bank_statement.statement -> 'transactions') is distinct from 'array' then
    raise exception 'a statement is an object with a transactions array' using errcode = '22023', hint = 'BANK_STATEMENT_INVALID';
  end if;
  v_format := coalesce(import_bank_statement.statement ->> 'format', 'feed');
  if v_format not in ('camt053', 'mt940', 'csv', 'feed') then
    raise exception 'a statement''s format is camt053, mt940, csv or feed' using errcode = '22023', hint = 'BANK_STATEMENT_INVALID';
  end if;
  if coalesce(import_bank_statement.statement ->> 'openingBalance', '0') !~ '^-?[0-9]{1,18}$'
    or coalesce(import_bank_statement.statement ->> 'closingBalance', '0') !~ '^-?[0-9]{1,18}$'
    or coalesce(import_bank_statement.statement ->> 'fromOn', '2000-01-01') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or coalesce(import_bank_statement.statement ->> 'untilOn', '2000-01-01') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'balances are integers of minor units and dates are YYYY-MM-DD' using errcode = '22023', hint = 'BANK_STATEMENT_INVALID';
  end if;
  v_reference := left(nullif(trim(import_bank_statement.statement ->> 'reference'), ''), 200);
  if v_reference is not null then
    select * into v_statement from "better_supabase"."bank_statements" x
    where x."account_id" = v_account."id" and x."reference" = v_reference;
  end if;
  if v_statement."id" is null then
    insert into "better_supabase"."bank_statements" ("tenant_id", "account_id", "reference", "from_on", "until_on",
      "opening_balance", "closing_balance", "format", "attachment_id", "imported_by")
    values (v_account."tenant_id", v_account."id", v_reference,
      (import_bank_statement.statement ->> 'fromOn')::date, (import_bank_statement.statement ->> 'untilOn')::date,
      (import_bank_statement.statement ->> 'openingBalance')::bigint, (import_bank_statement.statement ->> 'closingBalance')::bigint,
      v_format, nullif(import_bank_statement.statement ->> 'attachmentId', '')::uuid, auth.uid())
    returning * into v_statement;
  end if;
  for v_item in
    select e.value as tx, e.ordinality as n
    from jsonb_array_elements(import_bank_statement.statement -> 'transactions') with ordinality e
  loop
    v_total := v_total + 1;
    v_amount := v_item.tx ->> 'amount';
    v_currency := upper(coalesce(v_item.tx ->> 'currency', v_account."currency"));
    if jsonb_typeof(v_item.tx) is distinct from 'object'
      or coalesce(v_amount, '') !~ '^-?[0-9]{1,18}$' or v_amount ~ '^-?0+$'
      or coalesce(v_item.tx ->> 'bookedOn', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      or coalesce(v_item.tx ->> 'valueOn', '2000-01-01') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      raise exception 'each transaction has a bookedOn date and a nonzero amount of minor units' using errcode = '22023', hint = 'BANK_STATEMENT_INVALID';
    end if;
    if v_currency <> v_account."currency" then
      raise exception 'a transaction is in its bank account''s currency' using errcode = '22023', hint = 'BANK_STATEMENT_INVALID';
    end if;
    v_external := coalesce(
      left(nullif(trim(v_item.tx ->> 'externalId'), ''), 200),
      md5(concat_ws('|', v_item.tx ->> 'bookedOn', v_amount, v_item.tx ->> 'counterpartyIban', v_item.tx ->> 'remittance',
        v_item.tx ->> 'structuredReference', v_item.tx ->> 'endToEndId', v_reference, v_item.n::text)));
    insert into "better_supabase"."bank_transactions" ("tenant_id", "account_id", "statement_id", "booked_on", "value_on", "amount",
      "currency", "counterparty_name", "counterparty_iban", "remittance", "structured_reference",
      "end_to_end_id", "external_id")
    values (v_account."tenant_id", v_account."id", v_statement."id", (v_item.tx ->> 'bookedOn')::date,
      (v_item.tx ->> 'valueOn')::date, v_amount::bigint, v_currency,
      left(nullif(trim(v_item.tx ->> 'counterpartyName'), ''), 500),
      left(nullif(upper(regexp_replace(coalesce(v_item.tx ->> 'counterpartyIban', ''), '\s', '', 'g')), ''), 34),
      left(nullif(trim(v_item.tx ->> 'remittance'), ''), 2000),
      left(nullif(trim(v_item.tx ->> 'structuredReference'), ''), 100),
      left(nullif(trim(v_item.tx ->> 'endToEndId'), ''), 100),
      v_external)
    on conflict ("account_id", "external_id") do nothing;
    if found then
      v_imported := v_imported + 1;
    end if;
  end loop;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_bank_statement_import"(uuid, integer)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::integer)', v_hook::oid::regproc)
        using v_statement."id", v_imported;
    end if;
  end;
  return jsonb_build_object('statement', jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'accountId', v_statement."account_id", 'reference', v_statement."reference", 'fromOn', v_statement."from_on", 'untilOn', v_statement."until_on", 'openingBalance', v_statement."opening_balance"::text, 'closingBalance', v_statement."closing_balance"::text, 'currency', (select z."currency" from "better_supabase"."bank_accounts" z where z."id" = v_statement."account_id"), 'format', v_statement."format", 'attachmentId', v_statement."attachment_id", 'importedBy', v_statement."imported_by", 'createdAt', v_statement."created_at"), 'imported', v_imported, 'skipped', v_total - v_imported);
end;
$$;
revoke execute on function "better_supabase"."import_bank_statement"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."import_bank_statement"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."list_bank_statements"(account_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
begin
  select * into v_account from "better_supabase"."bank_accounts" x where x."id" = list_bank_statements.account_id;
  if not found then
    raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_account."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", 'banking.read'), false))) then
    raise exception 'not allowed to do this with bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'accountId', x."account_id", 'reference', x."reference", 'fromOn', x."from_on", 'untilOn', x."until_on", 'openingBalance', x."opening_balance"::text, 'closingBalance', x."closing_balance"::text, 'currency', (select z."currency" from "better_supabase"."bank_accounts" z where z."id" = x."account_id"), 'format', x."format", 'attachmentId', x."attachment_id", 'importedBy', x."imported_by", 'createdAt', x."created_at") order by x."until_on" desc nulls last, x."created_at" desc)
    from "better_supabase"."bank_statements" x where x."account_id" = v_account."id"
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_bank_statements"(uuid) from public, anon;
grant execute on function "better_supabase"."list_bank_statements"(uuid) to authenticated, service_role;

-- A bank account's transactions, newest first, with their matches. filter:
-- { status, since, until, limit (default 100, at most 500), offset }.
create or replace function "better_supabase"."list_bank_transactions"(account_id uuid, filter jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
  v_filter jsonb := coalesce(list_bank_transactions.filter, '{}'::jsonb);
begin
  select * into v_account from "better_supabase"."bank_accounts" x where x."id" = list_bank_transactions.account_id;
  if not found then
    raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_account."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", 'banking.read'), false))) then
    raise exception 'not allowed to do this with bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'accountId', x."account_id", 'statementId', x."statement_id", 'bookedOn', x."booked_on", 'valueOn', x."value_on", 'amount', x."amount"::text, 'currency', x."currency", 'counterpartyName', x."counterparty_name", 'counterpartyIban', x."counterparty_iban", 'remittance', x."remittance", 'structuredReference', x."structured_reference", 'endToEndId', x."end_to_end_id", 'externalId', x."external_id", 'status', x."status", 'ruleId', x."rule_id", 'matchedAt', x."matched_at", 'matchedBy', x."matched_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = x."id"), '[]'::jsonb)) order by x."booked_on" desc, x."created_at" desc, x."id")
    from (
      select * from "better_supabase"."bank_transactions" y
      where y."account_id" = v_account."id"
        and (v_filter ->> 'status' is null or y."status" = v_filter ->> 'status')
        and (v_filter ->> 'since' is null or y."booked_on" >= (v_filter ->> 'since')::date)
        and (v_filter ->> 'until' is null or y."booked_on" <= (v_filter ->> 'until')::date)
      order by y."booked_on" desc, y."created_at" desc, y."id"
      limit least(greatest(coalesce((v_filter ->> 'limit')::integer, 100), 1), 500)
      offset greatest(coalesce((v_filter ->> 'offset')::integer, 0), 0)
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_bank_transactions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_bank_transactions"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_bank_transaction"(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."bank_transactions"%rowtype;
begin
  select * into v_row from "better_supabase"."bank_transactions" x where x."id" = get_bank_transaction.transaction_id;
  if not found then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.read'), false))) then
    raise exception 'not allowed to read bank transactions' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'statementId', v_row."statement_id", 'bookedOn', v_row."booked_on", 'valueOn', v_row."value_on", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'counterpartyName', v_row."counterparty_name", 'counterpartyIban', v_row."counterparty_iban", 'remittance', v_row."remittance", 'structuredReference', v_row."structured_reference", 'endToEndId', v_row."end_to_end_id", 'externalId', v_row."external_id", 'status', v_row."status", 'ruleId', v_row."rule_id", 'matchedAt', v_row."matched_at", 'matchedBy', v_row."matched_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_bank_transaction"(uuid) from public, anon;
grant execute on function "better_supabase"."get_bank_transaction"(uuid) to authenticated, service_role;

-- Where a bank account stands on a day: the closing balance of the last
-- statement up to it, the sum of the transactions up to it, how many are
-- still unmatched, and with accounting the balance of the account's journal
-- account in the bank's currency. reconciled: nothing unmatched and the
-- statement agrees with the books.
create or replace function "better_supabase"."bank_reconciliation_status"(account_id uuid, as_of date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
  v_statement "better_supabase"."bank_statements"%rowtype;
  v_as_of date := coalesce(bank_reconciliation_status.as_of, current_date);
  v_total bigint;
  v_unmatched integer;
  v_unmatched_total bigint;
  v_ledger bigint;
begin
  select * into v_account from "better_supabase"."bank_accounts" x where x."id" = bank_reconciliation_status.account_id;
  if not found then
    raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_account."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", 'banking.read'), false))) then
    raise exception 'not allowed to do this with bank accounts' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  select * into v_statement from "better_supabase"."bank_statements" x
  where x."account_id" = v_account."id" and x."closing_balance" is not null
    and coalesce(x."until_on", x."created_at"::date) <= v_as_of
  order by coalesce(x."until_on", x."created_at"::date) desc, x."created_at" desc
  limit 1;
  select coalesce(sum(x."amount"), 0),
    count(*) filter (where x."status" = 'unmatched'),
    coalesce(sum(x."amount") filter (where x."status" = 'unmatched'), 0)
  into v_total, v_unmatched, v_unmatched_total
  from "better_supabase"."bank_transactions" x
  where x."account_id" = v_account."id" and x."booked_on" <= v_as_of;
  v_ledger := null::bigint;
  return jsonb_build_object(
    'accountId', v_account."id",
    'asOf', v_as_of,
    'currency', v_account."currency",
    'statementId', v_statement."id",
    'statementBalance', v_statement."closing_balance"::text,
    'transactionTotal', v_total::text,
    'unmatchedCount', v_unmatched,
    'unmatchedTotal', v_unmatched_total::text,
    'ledgerBalance', v_ledger::text,
    'difference', (v_statement."closing_balance" - v_ledger)::text,
    'reconciled', v_unmatched = 0 and coalesce(v_statement."closing_balance" = v_ledger, true));
end;
$$;
revoke execute on function "better_supabase"."bank_reconciliation_status"(uuid, date) from public, anon;
grant execute on function "better_supabase"."bank_reconciliation_status"(uuid, date) to authenticated, service_role;


-- Matches a bank rule's filter tree against a transaction's fields (ADR 0046).
create or replace function "better_supabase"."bank_rule_condition"(node jsonb, payload jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_child jsonb;
  v_any boolean := false;
  v_all boolean := true;
  v_result boolean;
  v_op text;
  v_value jsonb;
  v_at jsonb;
  v_text text;
  v_other text;
  v_numeric boolean;
  v_empty boolean;
begin
  if jsonb_typeof(node) is distinct from 'object' then
    raise exception 'conditions must be a filter tree of known operators' using errcode = '22023', hint = 'BANK_RULE_INVALID';
  end if;
  if node ->> 'type' = 'group' then
    if jsonb_typeof(node -> 'rules') is distinct from 'array'
      or coalesce(node ->> 'combinator', 'and') not in ('and', 'or') then
      raise exception 'conditions must be a filter tree of known operators' using errcode = '22023', hint = 'BANK_RULE_INVALID';
    end if;
    for v_child in select e.value from jsonb_array_elements(node -> 'rules') e loop
      v_result := "better_supabase"."bank_rule_condition"(v_child, payload);
      v_any := v_any or v_result;
      v_all := v_all and v_result;
    end loop;
    return case when coalesce(node ->> 'combinator', 'and') = 'or' then v_any else v_all end;
  end if;
  if node ->> 'type' is distinct from 'rule' or jsonb_typeof(node -> 'path') is distinct from 'array' then
    raise exception 'conditions must be a filter tree of known operators' using errcode = '22023', hint = 'BANK_RULE_INVALID';
  end if;
  v_op := coalesce(node ->> 'operator', '');
  v_value := node -> 'value';
  v_at := coalesce(payload, '{}'::jsonb) #> array(select jsonb_array_elements_text(node -> 'path'));
  v_text := v_at #>> '{}';
  v_other := v_value #>> '{}';
  v_numeric := jsonb_typeof(v_value) = 'number' and v_text ~ '^-?[0-9]+(\.[0-9]+)?$';
  v_empty := v_at is null or v_at = 'null'::jsonb or v_text = '' or v_at = '[]'::jsonb;
  v_result := case
    when v_op = '' then true
    when v_op = 'empty' then v_empty
    when v_op = 'not_empty' then not v_empty
    when v_op in ('is', 'eq') then case when v_numeric then v_text::numeric = v_other::numeric else v_text = v_other end
    when v_op in ('is_not', 'neq') then not coalesce(case when v_numeric then v_text::numeric = v_other::numeric else v_text = v_other end, false)
    when v_op in ('gt', 'is_after') then case when v_numeric then v_text::numeric > v_other::numeric else v_text > v_other end
    when v_op in ('gte', 'is_on_or_after') then case when v_numeric then v_text::numeric >= v_other::numeric else v_text >= v_other end
    when v_op in ('lt', 'is_before') then case when v_numeric then v_text::numeric < v_other::numeric else v_text < v_other end
    when v_op in ('lte', 'is_on_or_before') then case when v_numeric then v_text::numeric <= v_other::numeric else v_text <= v_other end
    when v_op in ('between', 'not_between') then
      jsonb_typeof(v_value) = 'array' and (
        case when jsonb_typeof(v_value -> 0) = 'number' and v_text ~ '^-?[0-9]+(\.[0-9]+)?$'
          then v_text::numeric between (v_value ->> 0)::numeric and (v_value ->> 1)::numeric
          else v_text between v_value ->> 0 and v_value ->> 1 end
      ) = (v_op = 'between')
    when v_op in ('is_any_of', 'is_none_of') then
      jsonb_typeof(v_value) = 'array'
        and exists (select 1 from jsonb_array_elements_text(v_value) e where e = v_text) = (v_op = 'is_any_of')
    when v_op in ('contains', 'not_contains') then
      (case when jsonb_typeof(v_at) = 'array' then v_at @> jsonb_build_array(v_value)
        else strpos(lower(v_text), lower(v_other)) > 0 end) = (v_op = 'contains')
    when v_op = 'starts_with' then left(lower(v_text), length(v_other)) = lower(v_other)
    when v_op = 'ends_with' then right(lower(v_text), length(v_other)) = lower(v_other)
    when v_op in ('has_any_of', 'has_none_of') then
      jsonb_typeof(v_at) = 'array' and jsonb_typeof(v_value) = 'array'
        and exists (select 1 from jsonb_array_elements(v_value) e where v_at @> jsonb_build_array(e.value)) = (v_op = 'has_any_of')
    when v_op = 'has_all_of' then
      jsonb_typeof(v_at) = 'array' and jsonb_typeof(v_value) = 'array' and v_at @> v_value
  end;
  if v_op not in ('', 'empty', 'not_empty', 'is', 'eq', 'is_not', 'neq', 'gt', 'is_after', 'gte', 'is_on_or_after', 'lt', 'is_before',
    'lte', 'is_on_or_before', 'between', 'not_between', 'is_any_of', 'is_none_of', 'contains', 'not_contains', 'starts_with',
    'ends_with', 'has_any_of', 'has_none_of', 'has_all_of') then
    raise exception 'conditions must be a filter tree of known operators' using errcode = '22023', hint = 'BANK_RULE_INVALID';
  end if;
  v_result := coalesce(v_result, false);
  return case when coalesce((node ->> 'negated')::boolean, false) then not v_result else v_result end;
end;
$$;
revoke execute on function "better_supabase"."bank_rule_condition"(jsonb, jsonb) from public, anon, authenticated;
-- Invoices a transaction may pay, best first: the structured reference names
-- the invoice (an RF creditor reference or a Dutch betalingskenmerk, checked),
-- the remittance carries its identifier, the open balance equals the amount,
-- or the counterparty's IBAN paid the same company or contact before.
create or replace function "better_supabase"."suggest_bank_matches"(transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."bank_transactions"%rowtype;
  v_ref text;
  v_text text;
begin
  select * into v_row from "better_supabase"."bank_transactions" x where x."id" = suggest_bank_matches.transaction_id;
  if not found then
    raise exception 'no such bank transaction' using errcode = 'P0002', hint = 'BANK_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.read'), false))) then
    raise exception 'not allowed to read bank transactions' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  v_ref := coalesce("better_supabase"."bank_reference"(v_row."structured_reference"),
    nullif(upper(regexp_replace(coalesce(v_row."structured_reference", ''), '[^A-Za-z0-9]', '', 'g')), ''));
  v_text := upper(regexp_replace(concat_ws(' ', v_row."remittance", v_row."structured_reference"), '[^A-Za-z0-9]', '', 'g'));
  return '[]'::jsonb;
end;
$$;
revoke execute on function "better_supabase"."suggest_bank_matches"(uuid) from public, anon;
grant execute on function "better_supabase"."suggest_bank_matches"(uuid) to authenticated, service_role;

-- Matches an unmatched transaction: matches is [{ targetType, targetId,
-- amount }], amounts signed like the transaction in minor units, summing to
-- it (one match without an amount takes all of it). An invoice records a
-- payment (a refund for a purchase invoice paid out), an expense report is
-- reimbursed when it isn't yet, and an accounting entry is linked.
create or replace function "better_supabase"."match_bank_transaction"(transaction_id uuid, matches jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."bank_transactions"%rowtype;
  v_match "better_supabase"."bank_matches"%rowtype;
  v_reimbursed timestamptz;
  v_currency text;
  v_item jsonb;
  v_amount bigint;
  v_sum bigint := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."bank_transactions" x where x."id" = match_bank_transaction.transaction_id for update;
  if not found then
    raise exception 'no such bank transaction' using errcode = 'P0002', hint = 'BANK_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.reconcile'), false))) then
    raise exception 'not allowed to reconcile bank transactions' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if v_row."status" <> 'unmatched' then
    raise exception 'a % bank transaction can''t be matched', v_row."status" using errcode = '55000', hint = 'BANK_TRANSACTION_STATUS_INVALID', detail = jsonb_build_object('status', v_row."status", 'action', 'matched')::text;
  end if;
  if jsonb_typeof(match_bank_transaction.matches) is distinct from 'array' or jsonb_array_length(match_bank_transaction.matches) = 0 then
    raise exception 'matches is a non-empty array' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_bank_transaction_match"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_row."id", match_bank_transaction.matches;
    end if;
  end;
  for v_item in select value from jsonb_array_elements(match_bank_transaction.matches) loop
    if coalesce(v_item ->> 'targetType', '') not in ('')
      or coalesce(v_item ->> 'targetId', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(v_item ->> 'amount', '0') !~ '^-?[0-9]{1,18}$' then
      raise exception 'a match has a targetType (none installed), a targetId and an integer amount' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
    end if;
    v_amount := coalesce((v_item ->> 'amount')::bigint,
      case when jsonb_array_length(match_bank_transaction.matches) = 1 then v_row."amount" end);
    if v_amount is null or v_amount = 0 or sign(v_amount) <> sign(v_row."amount") then
      raise exception 'a match''s amount is nonzero and has the transaction''s sign' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
    end if;
    v_sum := v_sum + v_amount;
    insert into "better_supabase"."bank_matches" ("tenant_id", "transaction_id", "target_type", "target_id", "amount", "created_by")
    values (v_row."tenant_id", v_row."id", v_item ->> 'targetType', (v_item ->> 'targetId')::uuid, v_amount, auth.uid())
    returning * into v_match;
  end loop;
  if v_sum <> v_row."amount" then
    raise exception 'the matches must add up to the transaction''s amount' using errcode = '22023', hint = 'BANK_TRANSACTION_MATCH_INVALID';
  end if;
  update "better_supabase"."bank_transactions" x set "status" = 'matched', "matched_at" = now(), "matched_by" = auth.uid(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_bank_transaction_match"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'statementId', v_row."statement_id", 'bookedOn', v_row."booked_on", 'valueOn', v_row."value_on", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'counterpartyName', v_row."counterparty_name", 'counterpartyIban', v_row."counterparty_iban", 'remittance', v_row."remittance", 'structuredReference', v_row."structured_reference", 'endToEndId', v_row."end_to_end_id", 'externalId', v_row."external_id", 'status', v_row."status", 'ruleId', v_row."rule_id", 'matchedAt', v_row."matched_at", 'matchedBy', v_row."matched_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."match_bank_transaction"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."match_bank_transaction"(uuid, jsonb) to authenticated, service_role;

-- Undoes a match: an invoice payment is refunded, a rule's entry is reversed,
-- and the transaction is unmatched again. A reimbursed expense report stays
-- reimbursed.
create or replace function "better_supabase"."unmatch_bank_transaction"(transaction_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."bank_transactions"%rowtype;
  v_match "better_supabase"."bank_matches"%rowtype;
  v_reimbursed timestamptz;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."bank_transactions" x where x."id" = unmatch_bank_transaction.transaction_id for update;
  if not found then
    raise exception 'no such bank transaction' using errcode = 'P0002', hint = 'BANK_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.reconcile'), false))) then
    raise exception 'not allowed to reconcile bank transactions' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if v_row."status" <> 'matched' then
    raise exception 'a % bank transaction can''t be unmatched', v_row."status" using errcode = '55000', hint = 'BANK_TRANSACTION_STATUS_INVALID', detail = jsonb_build_object('status', v_row."status", 'action', 'unmatched')::text;
  end if;
  for v_match in select * from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id" order by y."created_at", y."id" loop
  end loop;
  if v_row."rule_id" is not null then
    null;
  end if;
  delete from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id";
  update "better_supabase"."bank_transactions" x set "status" = 'unmatched', "rule_id" = null, "matched_at" = null,
    "matched_by" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'statementId', v_row."statement_id", 'bookedOn', v_row."booked_on", 'valueOn', v_row."value_on", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'counterpartyName', v_row."counterparty_name", 'counterpartyIban', v_row."counterparty_iban", 'remittance', v_row."remittance", 'structuredReference', v_row."structured_reference", 'endToEndId', v_row."end_to_end_id", 'externalId', v_row."external_id", 'status', v_row."status", 'ruleId', v_row."rule_id", 'matchedAt', v_row."matched_at", 'matchedBy', v_row."matched_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."unmatch_bank_transaction"(uuid) from public, anon;
grant execute on function "better_supabase"."unmatch_bank_transaction"(uuid) to authenticated, service_role;

-- Sets an unmatched transaction aside (a transfer between own accounts, a
-- duplicate), or with ignored false brings it back.
create or replace function "better_supabase"."ignore_bank_transaction"(transaction_id uuid, ignored boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."bank_transactions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."bank_transactions" x where x."id" = ignore_bank_transaction.transaction_id for update;
  if not found then
    raise exception 'no such bank transaction' using errcode = 'P0002', hint = 'BANK_TRANSACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.reconcile'), false))) then
    raise exception 'not allowed to reconcile bank transactions' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if v_row."status" <> (case when ignore_bank_transaction.ignored then 'unmatched' else 'ignored' end) then
    raise exception 'a % bank transaction can''t be ignored', v_row."status" using errcode = '55000', hint = 'BANK_TRANSACTION_STATUS_INVALID', detail = jsonb_build_object('status', v_row."status", 'action', 'ignored')::text;
  end if;
  update "better_supabase"."bank_transactions" x set
    "status" = case when ignore_bank_transaction.ignored then 'ignored' else 'unmatched' end,
    "rule_id" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'accountId', v_row."account_id", 'statementId', v_row."statement_id", 'bookedOn', v_row."booked_on", 'valueOn', v_row."value_on", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'counterpartyName', v_row."counterparty_name", 'counterpartyIban', v_row."counterparty_iban", 'remittance', v_row."remittance", 'structuredReference', v_row."structured_reference", 'endToEndId', v_row."end_to_end_id", 'externalId', v_row."external_id", 'status', v_row."status", 'ruleId', v_row."rule_id", 'matchedAt', v_row."matched_at", 'matchedBy', v_row."matched_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'matches', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'transactionId', y."transaction_id", 'targetType', y."target_type", 'targetId', y."target_id", 'amount', y."amount"::text, 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."created_at", y."id") from "better_supabase"."bank_matches" y where y."transaction_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."ignore_bank_transaction"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."ignore_bank_transaction"(uuid, boolean) to authenticated, service_role;

-- Creates or updates a bank rule: { name, conditions (a filter tree over the
-- transaction), accountId, partyId, dimensions, priority, active }. A rule
-- with an account books the transactions it matches there; one without sets
-- them aside.
create or replace function "better_supabase"."save_bank_rule"(tenant uuid, input jsonb, rule_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rule "better_supabase"."bank_rules"%rowtype;
  v_tenant uuid := save_bank_rule.tenant;
  v_conditions jsonb;
  v_account uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_bank_rule.tenant is not null and coalesce(better_supabase.can('tenant', save_bank_rule.tenant, 'banking.manage'), false))) then
    raise exception 'not allowed to manage bank rules' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  if jsonb_typeof(save_bank_rule.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'BANK_RULE_INVALID';
  end if;
  if save_bank_rule.rule_id is not null then
    select * into v_rule from "better_supabase"."bank_rules" x
    where x."id" = save_bank_rule.rule_id and x."tenant_id" = save_bank_rule.tenant
    for update;
    if not found then
      raise exception 'no such bank rule' using errcode = 'P0002', hint = 'BANK_RULE_NOT_FOUND';
    end if;
  end if;
  v_conditions := coalesce(save_bank_rule.input -> 'conditions', v_rule."conditions", '{"type":"group","combinator":"and","rules":[]}'::jsonb);
  perform "better_supabase"."bank_rule_condition"(v_conditions, '{}'::jsonb);
  v_account := case when save_bank_rule.input ? 'accountId'
    then nullif(save_bank_rule.input ->> 'accountId', '')::uuid
    else v_rule."account_id" end;
  if v_account is not null then
    raise exception 'a rule books to an account only with the accounting block' using errcode = '22023', hint = 'BANK_RULE_INVALID';
  end if;
  if v_rule."id" is null then
    insert into "better_supabase"."bank_rules" ("tenant_id", "name", "conditions", "account_id", "party_id", "dimensions", "priority", "active")
    values (save_bank_rule.tenant, trim(save_bank_rule.input ->> 'name'), v_conditions, v_account,
      nullif(save_bank_rule.input ->> 'partyId', '')::uuid,
      coalesce(save_bank_rule.input -> 'dimensions', '{}'::jsonb),
      coalesce((save_bank_rule.input ->> 'priority')::integer, 100),
      coalesce((save_bank_rule.input ->> 'active')::boolean, true))
    returning * into v_rule;
  else
    update "better_supabase"."bank_rules" x set
      "name" = coalesce(trim(save_bank_rule.input ->> 'name'), x."name"),
      "conditions" = v_conditions,
      "account_id" = v_account,
      "party_id" = case when save_bank_rule.input ? 'partyId' then nullif(save_bank_rule.input ->> 'partyId', '')::uuid else x."party_id" end,
      "dimensions" = coalesce(save_bank_rule.input -> 'dimensions', x."dimensions"),
      "priority" = coalesce((save_bank_rule.input ->> 'priority')::integer, x."priority"),
      "active" = coalesce((save_bank_rule.input ->> 'active')::boolean, x."active"),
      "updated_at" = now()
    where x."id" = v_rule."id"
    returning * into v_rule;
  end if;
  return jsonb_build_object('id', v_rule."id", 'organizationId', v_rule."tenant_id", 'name', v_rule."name", 'conditions', v_rule."conditions", 'accountId', v_rule."account_id", 'partyId', v_rule."party_id", 'dimensions', v_rule."dimensions", 'priority', v_rule."priority", 'active', v_rule."active", 'createdAt', v_rule."created_at", 'updatedAt', v_rule."updated_at");
exception
  when check_violation or not_null_violation then
    raise exception 'a rule has a name of 1 to 200 characters, an object of dimensions and a priority' using errcode = '22023', hint = 'BANK_RULE_INVALID';
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'accountId and partyId are uuids, priority an integer and active a boolean' using errcode = '22023', hint = 'BANK_RULE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."save_bank_rule"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_bank_rule"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_bank_rules"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_bank_rules.tenant is not null and coalesce(better_supabase.can('tenant', list_bank_rules.tenant, 'banking.read'), false))) then
    raise exception 'not allowed to read bank rules' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'conditions', x."conditions", 'accountId', x."account_id", 'partyId', x."party_id", 'dimensions', x."dimensions", 'priority', x."priority", 'active', x."active", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."priority", x."created_at", x."id")
    from "better_supabase"."bank_rules" x where x."tenant_id" = list_bank_rules.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_bank_rules"(uuid) from public, anon;
grant execute on function "better_supabase"."list_bank_rules"(uuid) to authenticated, service_role;

-- Deletes a bank rule. Transactions it matched keep their entries and lose
-- the link to the rule.
create or replace function "better_supabase"."delete_bank_rule"(rule_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rule "better_supabase"."bank_rules"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_rule from "better_supabase"."bank_rules" x where x."id" = delete_bank_rule.rule_id for update;
  if not found then
    raise exception 'no such bank rule' using errcode = 'P0002', hint = 'BANK_RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_rule."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_rule."tenant_id", 'banking.manage'), false))) then
    raise exception 'not allowed to manage bank rules' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  delete from "better_supabase"."bank_rules" x where x."id" = v_rule."id";
end;
$$;
revoke execute on function "better_supabase"."delete_bank_rule"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_bank_rule"(uuid) to authenticated, service_role;

-- Runs the active bank rules over a bank account's unmatched transactions,
-- lowest priority first, the first matching rule winning: a rule with an
-- account books the transaction (with the accounting block), one without sets it aside.
create or replace function "better_supabase"."apply_bank_rules"(account_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_account "better_supabase"."bank_accounts"%rowtype;
  v_row "better_supabase"."bank_transactions"%rowtype;
  v_rule "better_supabase"."bank_rules"%rowtype;
  v_entry uuid;
  v_matched integer := 0;
  v_ignored integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_account from "better_supabase"."bank_accounts" x where x."id" = apply_bank_rules.account_id;
  if not found then
    raise exception 'no such bank account' using errcode = 'P0002', hint = 'BANK_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_account."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_account."tenant_id", 'banking.reconcile'), false))) then
    raise exception 'not allowed to reconcile bank transactions' using errcode = '42501', hint = 'BANKING_FORBIDDEN';
  end if;
  for v_row in
    select * from "better_supabase"."bank_transactions" x
    where x."account_id" = v_account."id" and x."status" = 'unmatched'
    order by x."booked_on", x."created_at"
    for update skip locked
  loop
    select * into v_rule from "better_supabase"."bank_rules" y
    where y."tenant_id" = v_row."tenant_id" and y."active"
      and "better_supabase"."bank_rule_condition"(y."conditions", jsonb_build_object('accountId', v_row."account_id", 'bookedOn', v_row."booked_on", 'valueOn', v_row."value_on", 'amount', v_row."amount", 'direction', case when v_row."amount" < 0 then 'out' else 'in' end, 'currency', v_row."currency", 'counterpartyName', v_row."counterparty_name", 'counterpartyIban', v_row."counterparty_iban", 'remittance', v_row."remittance", 'structuredReference', v_row."structured_reference", 'endToEndId', v_row."end_to_end_id"))
    order by y."priority", y."created_at", y."id"
    limit 1;
    if v_rule."id" is not null then
      update "better_supabase"."bank_transactions" x set "status" = 'ignored', "rule_id" = v_rule."id", "updated_at" = now()
      where x."id" = v_row."id";
      v_ignored := v_ignored + 1;
    end if;
  end loop;
  return jsonb_build_object('matched', v_matched, 'ignored', v_ignored);
end;
$$;
revoke execute on function "better_supabase"."apply_bank_rules"(uuid) from public, anon;
grant execute on function "better_supabase"."apply_bank_rules"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."bank_accounts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_accounts";
create policy bsb_tenant_scope_select on "better_supabase"."bank_accounts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_accounts";
create policy bsb_tenant_scope_insert on "better_supabase"."bank_accounts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_accounts";
create policy bsb_tenant_scope_update on "better_supabase"."bank_accounts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_accounts";
create policy bsb_tenant_scope_delete on "better_supabase"."bank_accounts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."bank_rules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_rules";
create policy bsb_tenant_scope_select on "better_supabase"."bank_rules" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_rules";
create policy bsb_tenant_scope_insert on "better_supabase"."bank_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_rules";
create policy bsb_tenant_scope_update on "better_supabase"."bank_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_rules";
create policy bsb_tenant_scope_delete on "better_supabase"."bank_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."bank_statements";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_statements";
create policy bsb_tenant_scope_select on "better_supabase"."bank_statements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_statements";
create policy bsb_tenant_scope_insert on "better_supabase"."bank_statements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_statements";
create policy bsb_tenant_scope_update on "better_supabase"."bank_statements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_statements";
create policy bsb_tenant_scope_delete on "better_supabase"."bank_statements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."bank_transactions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_transactions";
create policy bsb_tenant_scope_select on "better_supabase"."bank_transactions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_transactions";
create policy bsb_tenant_scope_insert on "better_supabase"."bank_transactions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_transactions";
create policy bsb_tenant_scope_update on "better_supabase"."bank_transactions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_transactions";
create policy bsb_tenant_scope_delete on "better_supabase"."bank_transactions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."bank_matches";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."bank_matches";
create policy bsb_tenant_scope_select on "better_supabase"."bank_matches" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('banking.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."bank_matches";
create policy bsb_tenant_scope_insert on "better_supabase"."bank_matches" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."bank_matches";
create policy bsb_tenant_scope_update on "better_supabase"."bank_matches" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."bank_matches";
create policy bsb_tenant_scope_delete on "better_supabase"."bank_matches" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_155_banking.sql
-- better-supabase module: banking
-- @bsb-block-data banking
-- @bsb-hash sha256:0104094d35c4212d5c0d1245406934860479cf630e6eb25c1d97901403901c73
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('banking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
