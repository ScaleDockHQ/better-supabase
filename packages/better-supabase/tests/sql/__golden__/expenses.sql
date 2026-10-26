-- ==== alone: schema supabase/schemas/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block expenses@1 managed
-- @bsb-hash sha256:bfd96982be2f9692253ea645d75eafd1b8b9f0e46ac35182d0a50aa19d877cb4
-- Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Expenses: reports of lines in categories, spend policies checked on
-- submit, approval through the approvals block, and the approved total and
-- its reimbursement posted on the ledger.

-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
create table if not exists "better_supabase"."expense_categories" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "limit_amount" bigint check ("limit_amount" is null or "limit_amount" > 0),
  "receipt_over" bigint check ("receipt_over" is null or "receipt_over" >= 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  check (("limit_amount" is null and "receipt_over" is null) or "currency" is not null)
);
alter table "better_supabase"."expense_categories" enable row level security;
revoke all on "better_supabase"."expense_categories" from anon, authenticated;
grant select on "better_supabase"."expense_categories" to authenticated;
grant all on "better_supabase"."expense_categories" to service_role;
drop policy if exists "expense_categories_read" on "better_supabase"."expense_categories";
create policy "expense_categories_read" on "better_supabase"."expense_categories" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "better_supabase"."expense_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "title" text not null check (length("title") between 1 and 200),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "note" text check ("note" is null or length("note") <= 2000),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "approval_transaction_id" uuid,
  "reimbursed_at" timestamptz,
  "reimbursement_transaction_id" uuid,
  "cancelled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "expense_reports_tenant_idx" on "better_supabase"."expense_reports" ("tenant_id", "created_at" desc);
create index if not exists "expense_reports_user_idx" on "better_supabase"."expense_reports" ("user_id", "tenant_id");
create index if not exists "expense_reports_approval_idx" on "better_supabase"."expense_reports" ("approval_id") where "approval_id" is not null;
create index if not exists "expense_reports_approval_tx_idx" on "better_supabase"."expense_reports" ("approval_transaction_id") where "approval_transaction_id" is not null;
create index if not exists "expense_reports_reimbursement_idx" on "better_supabase"."expense_reports" ("reimbursement_transaction_id") where "reimbursement_transaction_id" is not null;
alter table "better_supabase"."expense_reports" enable row level security;
revoke all on "better_supabase"."expense_reports" from anon, authenticated;
grant select on "better_supabase"."expense_reports" to authenticated;
grant all on "better_supabase"."expense_reports" to service_role;
drop policy if exists "expense_reports_read" on "better_supabase"."expense_reports";
create policy "expense_reports_read" on "better_supabase"."expense_reports" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "better_supabase"."expense_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "report_id" uuid not null references "better_supabase"."expense_reports" ("id") on delete cascade,
  "category_id" uuid not null,
  "spent_on" date not null,
  "description" text not null check (length("description") between 1 and 500),
  "merchant" text check ("merchant" is null or length("merchant") <= 200),
  -- Minor units of the report's currency (ADR 0037).
  "amount" bigint not null check ("amount" > 0),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "category_id") references "better_supabase"."expense_categories" ("tenant_id", "id") on delete restrict
);
create index if not exists "expense_lines_report_idx" on "better_supabase"."expense_lines" ("report_id", "spent_on");
create index if not exists "expense_lines_category_idx" on "better_supabase"."expense_lines" ("tenant_id", "category_id");
alter table "better_supabase"."expense_lines" enable row level security;
revoke all on "better_supabase"."expense_lines" from anon, authenticated;
grant select on "better_supabase"."expense_lines" to authenticated;
grant all on "better_supabase"."expense_lines" to service_role;
drop policy if exists "expense_lines_read" on "better_supabase"."expense_lines";
create policy "expense_lines_read" on "better_supabase"."expense_lines" for select to authenticated
  using (
    exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read'))
  );

-- Creates or updates the category with this key and its spend policy.
create or replace function "better_supabase"."save_expense_category"(tenant uuid, key text, name text, currency text default null, limit_amount bigint default null, receipt_over bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_expense_category.tenant, 'expenses.manage'), false)) then
    raise exception 'not allowed to manage expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if save_expense_category.key is null or save_expense_category.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if nullif(trim(save_expense_category.name), '') is null then
    raise exception 'a category needs a name' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if (save_expense_category.limit_amount is not null or save_expense_category.receipt_over is not null)
    and (save_expense_category.currency is null or save_expense_category.currency !~ '^[A-Z]{3}$') then
    raise exception 'a limit or receipt threshold needs a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.limit_amount is not null and save_expense_category.limit_amount <= 0 then
    raise exception 'a limit is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null and save_expense_category.receipt_over < 0 then
    raise exception 'a receipt threshold is zero or more minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null then
    raise exception 'a receipt threshold needs the attachments block' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  insert into "better_supabase"."expense_categories" ("tenant_id", "key", "name", "currency", "limit_amount", "receipt_over")
  values (save_expense_category.tenant, save_expense_category.key, trim(save_expense_category.name), save_expense_category.currency,
    save_expense_category.limit_amount, save_expense_category.receipt_over)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "currency" = excluded."currency", "limit_amount" = excluded."limit_amount",
    "receipt_over" = excluded."receipt_over", "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) from public, anon;
grant execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) to authenticated, service_role;

create or replace function "better_supabase"."archive_expense_category"(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_categories" c where c."id" = archive_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "better_supabase"."expense_categories" c set "archived_at" = coalesce(c."archived_at", now()), "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_expense_categories"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.read'), false)) or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to read expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") order by c."name", c."id"), '[]'::jsonb)
    from "better_supabase"."expense_categories" c
    where c."tenant_id" = list_expense_categories.tenant
      and (coalesce(list_expense_categories.include_archived, false) or c."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_categories"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_expense_categories"(uuid, boolean) to authenticated, service_role;

-- The spend policy findings of a report, empty when it may be submitted:
-- a category total over its limit, a line over its category's receipt
-- threshold without a receipt, and a line in an archived category.
create or replace function "better_supabase"."expense_report_violations"(report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.v order by q.ord, q.at), '[]'::jsonb)
  from (
    select 1 as ord, min(l."created_at") as at, jsonb_build_object('kind', 'limit', 'categoryId', c."id", 'category', c."name",
        'limit', c."limit_amount"::text, 'total', sum(l."amount")::text, 'currency', c."currency") as v
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."limit_amount" is not null
      group by c."id"
      having sum(l."amount") > c."limit_amount"
    union all
    select 2, l."created_at", jsonb_build_object('kind', 'receipt', 'lineId', l."id", 'categoryId', c."id", 'category', c."name",
        'receiptOver', c."receipt_over"::text, 'amount', l."amount"::text, 'currency', c."currency")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."receipt_over" is not null
        and l."amount" > c."receipt_over" and 0 = 0
    union all
    select 3, min(l."created_at"), jsonb_build_object('kind', 'archived', 'categoryId', c."id", 'category', c."name")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."archived_at" is not null
      group by c."id"
  ) q;
$$;
revoke execute on function "better_supabase"."expense_report_violations"(uuid) from public, anon, authenticated;

-- Opens a draft report in one currency. fields: the extra columns to set.
drop function if exists "better_supabase"."create_expense_report"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."create_expense_report"(tenant uuid, title text, currency text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', create_expense_report.tenant, 'expenses.submit'), false) then
    raise exception 'not allowed to submit expenses here' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if nullif(trim(create_expense_report.title), '') is null then
    raise exception 'a report needs a title' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if create_expense_report.currency is null or create_expense_report.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  insert into "better_supabase"."expense_reports" ("tenant_id", "user_id", "title", "currency", "note")
  values (create_expense_report.tenant, auth.uid(), trim(create_expense_report.title), create_expense_report.currency,
    nullif(trim(create_expense_report.note), ''))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."add_expense_line"(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = add_expense_line.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = add_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.spent_on is null then
    raise exception 'a line needs spent_on' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if add_expense_line.currency is not null and add_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.amount is null or add_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if nullif(trim(add_expense_line.description), '') is null then
    raise exception 'a line needs a description' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  insert into "better_supabase"."expense_lines" ("tenant_id", "report_id", "category_id", "spent_on", "description", "merchant", "amount")
  values (v_row."tenant_id", v_row."id", v_category."id", add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), add_expense_line.amount)
  returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

-- Changes a line of a draft or rejected report; null keeps a value.
create or replace function "better_supabase"."update_expense_line"(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = update_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if update_expense_line.category_id is not null then
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = update_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  end if;
  if update_expense_line.currency is not null and update_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if update_expense_line.amount is not null and update_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  update "better_supabase"."expense_lines" l set
      "category_id" = coalesce(update_expense_line.category_id, l."category_id"),
      "spent_on" = coalesce(update_expense_line.spent_on, l."spent_on"),
      "amount" = coalesce(update_expense_line.amount, l."amount"),
      "description" = coalesce(nullif(trim(update_expense_line.description), ''), l."description"),
      "merchant" = coalesce(nullif(trim(update_expense_line.merchant), ''), l."merchant"),
      "updated_at" = now()
    where l."id" = v_line."id"
    returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_expense_line"(line_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = remove_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  delete from "better_supabase"."expense_lines" l where l."id" = v_line."id";
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."remove_expense_line"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_expense_line"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."check_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = check_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return "better_supabase"."expense_report_violations"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."check_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."check_expense_report"(uuid) to authenticated, service_role;

-- Submits a draft or rejected report for approval. Fails with
-- EXPENSE_POLICY_VIOLATION, listing the findings, while the report breaks
-- the spend policy.
create or replace function "better_supabase"."submit_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_violations jsonb;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = submit_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if not exists (select 1 from "better_supabase"."expense_lines" l where l."report_id" = v_row."id") then
    raise exception 'a report needs at least one line' using errcode = '22023', hint = 'EXPENSE_REPORT_EMPTY';
  end if;
  v_violations := "better_supabase"."expense_report_violations"(v_row."id");
  if jsonb_array_length(v_violations) > 0 then
    raise exception 'the report breaks the spend policy: %', v_violations::text using errcode = '22023', hint = 'EXPENSE_POLICY_VIOLATION';
  end if;
  v_request := "better_supabase"."open_approval"(
    v_row."tenant_id", 'expense_report', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"expenses.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_row."user_id", 'title', v_row."title", 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  update "better_supabase"."expense_reports" x set "approval_id" = (v_request ->> 'id')::uuid, "submitted_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."submit_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."submit_expense_report"(uuid) to authenticated, service_role;

-- Books an approved report once its approval is final: each category's
-- total on its expense account, the sum owed to the member on their payable
-- account. Approvals calls it; it isn't granted to anyone.
create or replace function "better_supabase"."approve_expense_report"(report_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."expense_reports" x
    where x."id" = approve_expense_report.report_id and x."approved_at" is null and x."cancelled_at" is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense', 'expenses:category:' || c."key" || ':' || v_row."currency", 'Expenses: ' || c."name", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', q.total) order by c."key")
    into v_lines
  from (
    select l."category_id" as category, sum(l."amount") as total
    from "better_supabase"."expense_lines" l where l."report_id" = v_row."id" group by l."category_id"
  ) q join "better_supabase"."expense_categories" c on c."id" = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)));
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.approved', v_lines,
    'expenses', v_row."id"::text, left('Expenses: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':approved', null,
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"));
  update "better_supabase"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
end;
$$;
revoke execute on function "better_supabase"."approve_expense_report"(uuid) from public, anon, authenticated;

-- Pays an approved report back: the member's payable account is settled
-- from expense cash.
create or replace function "better_supabase"."reimburse_expense_report"(report_id uuid, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = reimburse_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'not allowed to reimburse expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) <> 'approved' then
    raise exception 'only an approved report can be reimbursed' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) to authenticated, service_role;

-- Withdraws a report that isn't approved yet: its owner or a manager. A
-- pending approval is cancelled with it.
create or replace function "better_supabase"."cancel_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = cancel_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false))) then
    raise exception 'not allowed to cancel this expense report' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'submitted', 'rejected') then
    raise exception 'an approved, reimbursed or cancelled report can''t be cancelled' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  update "better_supabase"."expense_reports" x set "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_expense_report"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = get_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."get_expense_report"(uuid) to authenticated, service_role;

-- Reports, newest first: the caller's, or everyone's (or one member's) with
-- expenses.read.
create or replace function "better_supabase"."list_expense_reports"(tenant uuid, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.read'), false));
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to list expense reports' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if not v_reader and (coalesce(list_expense_reports.everyone, false) or (list_expense_reports.user_id is not null and list_expense_reports.user_id <> auth.uid())) then
    raise exception 'not allowed to read another member''s expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'title', q."title", 'currency', q."currency", 'note', q."note", 'status', (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = q."id"), 0)::text, 'approvalId', q."approval_id", 'submittedAt', q."submitted_at", 'approvedAt', q."approved_at", 'approvalTransactionId', q."approval_transaction_id", 'reimbursedAt', q."reimbursed_at", 'reimbursementTransactionId', q."reimbursement_transaction_id", 'cancelledAt', q."cancelled_at", 'createdAt', q."created_at", 'updatedAt', q."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = q."id")) as item, q."created_at" as created, q."id" as id
      from "better_supabase"."expense_reports" q
      left join "better_supabase"."approval_requests" p on p."id" = q."approval_id"
      where q."tenant_id" = list_expense_reports.tenant
        and (case
          when coalesce(list_expense_reports.everyone, false) then true
          when list_expense_reports.user_id is not null then q."user_id" = list_expense_reports.user_id
          else q."user_id" = auth.uid()
        end)
        and (list_expense_reports.status is null or (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) = list_expense_reports.status)
      order by q."created_at" desc, q."id"
      limit least(greatest(coalesce(list_expense_reports.page_size, 100), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_select on "better_supabase"."expense_categories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_categories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_update on "better_supabase"."expense_categories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_categories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_select on "better_supabase"."expense_reports" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_reports" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_update on "better_supabase"."expense_reports" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_reports" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_select on "better_supabase"."expense_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_update on "better_supabase"."expense_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_lines" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:acad5782117da37aa32eb5b47f0372cb87a9105ea9687dd5f8de16d1ca73932f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block expenses@1 managed
-- @bsb-hash sha256:2fcc8e992d6e3198e6740dfcebeb0692bd7057e14c226f3678241419d13c29ac
-- Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Expenses: reports of lines in categories, spend policies checked on
-- submit, approval through the approvals block, and the approved total and
-- its reimbursement posted on the ledger.

-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
create table if not exists "better_supabase"."expense_categories" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "limit_amount" bigint check ("limit_amount" is null or "limit_amount" > 0),
  "receipt_over" bigint check ("receipt_over" is null or "receipt_over" >= 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  check (("limit_amount" is null and "receipt_over" is null) or "currency" is not null)
);
alter table "better_supabase"."expense_categories" enable row level security;
revoke all on "better_supabase"."expense_categories" from anon, authenticated;
grant select on "better_supabase"."expense_categories" to authenticated;
grant all on "better_supabase"."expense_categories" to service_role;
drop policy if exists "expense_categories_read" on "better_supabase"."expense_categories";
create policy "expense_categories_read" on "better_supabase"."expense_categories" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "better_supabase"."expense_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "title" text not null check (length("title") between 1 and 200),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "note" text check ("note" is null or length("note") <= 2000),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "approval_transaction_id" uuid,
  "reimbursed_at" timestamptz,
  "reimbursement_transaction_id" uuid,
  "cancelled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "expense_reports_tenant_idx" on "better_supabase"."expense_reports" ("tenant_id", "created_at" desc);
create index if not exists "expense_reports_user_idx" on "better_supabase"."expense_reports" ("user_id", "tenant_id");
create index if not exists "expense_reports_approval_idx" on "better_supabase"."expense_reports" ("approval_id") where "approval_id" is not null;
create index if not exists "expense_reports_approval_tx_idx" on "better_supabase"."expense_reports" ("approval_transaction_id") where "approval_transaction_id" is not null;
create index if not exists "expense_reports_reimbursement_idx" on "better_supabase"."expense_reports" ("reimbursement_transaction_id") where "reimbursement_transaction_id" is not null;
alter table "better_supabase"."expense_reports" enable row level security;
revoke all on "better_supabase"."expense_reports" from anon, authenticated;
grant select on "better_supabase"."expense_reports" to authenticated;
grant all on "better_supabase"."expense_reports" to service_role;
drop policy if exists "expense_reports_read" on "better_supabase"."expense_reports";
create policy "expense_reports_read" on "better_supabase"."expense_reports" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "better_supabase"."expense_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "report_id" uuid not null references "better_supabase"."expense_reports" ("id") on delete cascade,
  "category_id" uuid not null,
  "spent_on" date not null,
  "description" text not null check (length("description") between 1 and 500),
  "merchant" text check ("merchant" is null or length("merchant") <= 200),
  -- Minor units of the report's currency (ADR 0037).
  "amount" bigint not null check ("amount" > 0),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "category_id") references "better_supabase"."expense_categories" ("tenant_id", "id") on delete restrict
);
create index if not exists "expense_lines_report_idx" on "better_supabase"."expense_lines" ("report_id", "spent_on");
create index if not exists "expense_lines_category_idx" on "better_supabase"."expense_lines" ("tenant_id", "category_id");
alter table "better_supabase"."expense_lines" enable row level security;
revoke all on "better_supabase"."expense_lines" from anon, authenticated;
grant select on "better_supabase"."expense_lines" to authenticated;
grant all on "better_supabase"."expense_lines" to service_role;
drop policy if exists "expense_lines_read" on "better_supabase"."expense_lines";
create policy "expense_lines_read" on "better_supabase"."expense_lines" for select to authenticated
  using (
    exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read'))
  );

-- Creates or updates the category with this key and its spend policy.
create or replace function "better_supabase"."save_expense_category"(tenant uuid, key text, name text, currency text default null, limit_amount bigint default null, receipt_over bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_expense_category.tenant, 'expenses.manage'), false)) then
    raise exception 'not allowed to manage expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if save_expense_category.key is null or save_expense_category.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if nullif(trim(save_expense_category.name), '') is null then
    raise exception 'a category needs a name' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if (save_expense_category.limit_amount is not null or save_expense_category.receipt_over is not null)
    and (save_expense_category.currency is null or save_expense_category.currency !~ '^[A-Z]{3}$') then
    raise exception 'a limit or receipt threshold needs a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.limit_amount is not null and save_expense_category.limit_amount <= 0 then
    raise exception 'a limit is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null and save_expense_category.receipt_over < 0 then
    raise exception 'a receipt threshold is zero or more minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  insert into "better_supabase"."expense_categories" ("tenant_id", "key", "name", "currency", "limit_amount", "receipt_over")
  values (save_expense_category.tenant, save_expense_category.key, trim(save_expense_category.name), save_expense_category.currency,
    save_expense_category.limit_amount, save_expense_category.receipt_over)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "currency" = excluded."currency", "limit_amount" = excluded."limit_amount",
    "receipt_over" = excluded."receipt_over", "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) from public, anon;
grant execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) to authenticated, service_role;

create or replace function "better_supabase"."archive_expense_category"(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_categories" c where c."id" = archive_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "better_supabase"."expense_categories" c set "archived_at" = coalesce(c."archived_at", now()), "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_expense_categories"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.read'), false)) or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to read expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") order by c."name", c."id"), '[]'::jsonb)
    from "better_supabase"."expense_categories" c
    where c."tenant_id" = list_expense_categories.tenant
      and (coalesce(list_expense_categories.include_archived, false) or c."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_categories"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_expense_categories"(uuid, boolean) to authenticated, service_role;

-- The spend policy findings of a report, empty when it may be submitted:
-- a category total over its limit, a line over its category's receipt
-- threshold without a receipt, and a line in an archived category.
create or replace function "better_supabase"."expense_report_violations"(report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.v order by q.ord, q.at), '[]'::jsonb)
  from (
    select 1 as ord, min(l."created_at") as at, jsonb_build_object('kind', 'limit', 'categoryId', c."id", 'category', c."name",
        'limit', c."limit_amount"::text, 'total', sum(l."amount")::text, 'currency', c."currency") as v
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."limit_amount" is not null
      group by c."id"
      having sum(l."amount") > c."limit_amount"
    union all
    select 2, l."created_at", jsonb_build_object('kind', 'receipt', 'lineId', l."id", 'categoryId', c."id", 'category', c."name",
        'receiptOver', c."receipt_over"::text, 'amount', l."amount"::text, 'currency', c."currency")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."receipt_over" is not null
        and l."amount" > c."receipt_over" and (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected') = 0
    union all
    select 3, min(l."created_at"), jsonb_build_object('kind', 'archived', 'categoryId', c."id", 'category', c."name")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."archived_at" is not null
      group by c."id"
  ) q;
$$;
revoke execute on function "better_supabase"."expense_report_violations"(uuid) from public, anon, authenticated;

-- Opens a draft report in one currency. fields: the extra columns to set.
drop function if exists "better_supabase"."create_expense_report"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."create_expense_report"(tenant uuid, title text, currency text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', create_expense_report.tenant, 'expenses.submit'), false) then
    raise exception 'not allowed to submit expenses here' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if nullif(trim(create_expense_report.title), '') is null then
    raise exception 'a report needs a title' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if create_expense_report.currency is null or create_expense_report.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  insert into "better_supabase"."expense_reports" ("tenant_id", "user_id", "title", "currency", "note")
  values (create_expense_report.tenant, auth.uid(), trim(create_expense_report.title), create_expense_report.currency,
    nullif(trim(create_expense_report.note), ''))
  returning * into v_row;
  perform "better_supabase".emit_event('expense_report.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency"), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.created',
    category => 'data',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'created an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."add_expense_line"(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = add_expense_line.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = add_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.spent_on is null then
    raise exception 'a line needs spent_on' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if add_expense_line.currency is not null and add_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.amount is null or add_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if nullif(trim(add_expense_line.description), '') is null then
    raise exception 'a line needs a description' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  insert into "better_supabase"."expense_lines" ("tenant_id", "report_id", "category_id", "spent_on", "description", "merchant", "amount")
  values (v_row."tenant_id", v_row."id", v_category."id", add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), add_expense_line.amount)
  returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = v_line."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

-- Changes a line of a draft or rejected report; null keeps a value.
create or replace function "better_supabase"."update_expense_line"(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = update_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if update_expense_line.category_id is not null then
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = update_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  end if;
  if update_expense_line.currency is not null and update_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if update_expense_line.amount is not null and update_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  update "better_supabase"."expense_lines" l set
      "category_id" = coalesce(update_expense_line.category_id, l."category_id"),
      "spent_on" = coalesce(update_expense_line.spent_on, l."spent_on"),
      "amount" = coalesce(update_expense_line.amount, l."amount"),
      "description" = coalesce(nullif(trim(update_expense_line.description), ''), l."description"),
      "merchant" = coalesce(nullif(trim(update_expense_line.merchant), ''), l."merchant"),
      "updated_at" = now()
    where l."id" = v_line."id"
    returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = v_line."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_expense_line"(line_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = remove_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  delete from "better_supabase"."expense_lines" l where l."id" = v_line."id";
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."remove_expense_line"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_expense_line"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."check_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = check_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return "better_supabase"."expense_report_violations"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."check_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."check_expense_report"(uuid) to authenticated, service_role;

-- Submits a draft or rejected report for approval. Fails with
-- EXPENSE_POLICY_VIOLATION, listing the findings, while the report breaks
-- the spend policy.
create or replace function "better_supabase"."submit_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_violations jsonb;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = submit_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if not exists (select 1 from "better_supabase"."expense_lines" l where l."report_id" = v_row."id") then
    raise exception 'a report needs at least one line' using errcode = '22023', hint = 'EXPENSE_REPORT_EMPTY';
  end if;
  v_violations := "better_supabase"."expense_report_violations"(v_row."id");
  if jsonb_array_length(v_violations) > 0 then
    raise exception 'the report breaks the spend policy: %', v_violations::text using errcode = '22023', hint = 'EXPENSE_POLICY_VIOLATION';
  end if;
  v_request := "better_supabase"."open_approval"(
    v_row."tenant_id", 'expense_report', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"expenses.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_row."user_id", 'title', v_row."title", 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  update "better_supabase"."expense_reports" x set "approval_id" = (v_request ->> 'id')::uuid, "submitted_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  perform "better_supabase".emit_event('expense_report.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'approvalId', v_row."approval_id"), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.submitted',
    category => 'data',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'submitted an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."submit_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."submit_expense_report"(uuid) to authenticated, service_role;

-- Books an approved report once its approval is final: each category's
-- total on its expense account, the sum owed to the member on their payable
-- account. Approvals calls it; it isn't granted to anyone.
create or replace function "better_supabase"."approve_expense_report"(report_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."expense_reports" x
    where x."id" = approve_expense_report.report_id and x."approved_at" is null and x."cancelled_at" is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense', 'expenses:category:' || c."key" || ':' || v_row."currency", 'Expenses: ' || c."name", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', q.total) order by c."key")
    into v_lines
  from (
    select l."category_id" as category, sum(l."amount") as total
    from "better_supabase"."expense_lines" l where l."report_id" = v_row."id" group by l."category_id"
  ) q join "better_supabase"."expense_categories" c on c."id" = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)));
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.approved', v_lines,
    'expenses', v_row."id"::text, left('Expenses: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':approved', null,
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"));
  update "better_supabase"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  perform "better_supabase".emit_event('expense_report.approved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.approved',
    category => 'billing',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'approved an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx)
  );
end;
$$;
revoke execute on function "better_supabase"."approve_expense_report"(uuid) from public, anon, authenticated;

-- Pays an approved report back: the member's payable account is settled
-- from expense cash.
create or replace function "better_supabase"."reimburse_expense_report"(report_id uuid, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = reimburse_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'not allowed to reimburse expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) <> 'approved' then
    raise exception 'only an approved report can be reimbursed' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('expense_report.reimbursed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.reimbursed',
    category => 'billing',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'reimbursed an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency", 'transactionId', v_tx)
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) to authenticated, service_role;

-- Withdraws a report that isn't approved yet: its owner or a manager. A
-- pending approval is cancelled with it.
create or replace function "better_supabase"."cancel_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = cancel_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false))) then
    raise exception 'not allowed to cancel this expense report' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'submitted', 'rejected') then
    raise exception 'an approved, reimbursed or cancelled report can''t be cancelled' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  update "better_supabase"."expense_reports" x set "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  perform "better_supabase".emit_event('expense_report.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency"), 'expense-reports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/expenses');
  perform better_supabase.audit_event(
    event_type => 'expense_report.cancelled',
    category => 'data',
    target_type => 'expense_report',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'cancelled an expense report',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_expense_report"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = get_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."get_expense_report"(uuid) to authenticated, service_role;

-- Reports, newest first: the caller's, or everyone's (or one member's) with
-- expenses.read.
create or replace function "better_supabase"."list_expense_reports"(tenant uuid, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.read'), false));
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to list expense reports' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if not v_reader and (coalesce(list_expense_reports.everyone, false) or (list_expense_reports.user_id is not null and list_expense_reports.user_id <> auth.uid())) then
    raise exception 'not allowed to read another member''s expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'title', q."title", 'currency', q."currency", 'note', q."note", 'status', (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = q."id"), 0)::text, 'approvalId', q."approval_id", 'submittedAt', q."submitted_at", 'approvedAt', q."approved_at", 'approvalTransactionId', q."approval_transaction_id", 'reimbursedAt', q."reimbursed_at", 'reimbursementTransactionId', q."reimbursement_transaction_id", 'cancelledAt', q."cancelled_at", 'createdAt', q."created_at", 'updatedAt', q."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', (select count(*) from "better_supabase"."attachments" t where t."subject_type" = 'expense_line' and t."subject_id" = l."id"::text and t."uploaded_at" is not null and t."status" <> 'infected'), 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = q."id")) as item, q."created_at" as created, q."id" as id
      from "better_supabase"."expense_reports" q
      left join "better_supabase"."approval_requests" p on p."id" = q."approval_id"
      where q."tenant_id" = list_expense_reports.tenant
        and (case
          when coalesce(list_expense_reports.everyone, false) then true
          when list_expense_reports.user_id is not null then q."user_id" = list_expense_reports.user_id
          else q."user_id" = auth.uid()
        end)
        and (list_expense_reports.status is null or (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) = list_expense_reports.status)
      order by q."created_at" desc, q."id"
      limit least(greatest(coalesce(list_expense_reports.page_size, 100), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_select on "better_supabase"."expense_categories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_categories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_update on "better_supabase"."expense_categories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_categories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_select on "better_supabase"."expense_reports" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_reports" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_update on "better_supabase"."expense_reports" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_reports" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_select on "better_supabase"."expense_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_update on "better_supabase"."expense_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_lines" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:acad5782117da37aa32eb5b47f0372cb87a9105ea9687dd5f8de16d1ca73932f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block expenses@1 managed
-- @bsb-hash sha256:da848c231ae3c941d468d87fca82193fde81f4c561c83f60f0b9500d2b9109bf
-- Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units.
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
    drop policy if exists bsb_tenant_scope on "app_private"."expense_categories";
    drop policy if exists bsb_tenant_scope_select on "app_private"."expense_categories";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."expense_categories";
    drop policy if exists bsb_tenant_scope_update on "app_private"."expense_categories";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."expense_categories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."expense_reports";
    drop policy if exists bsb_tenant_scope_select on "app_private"."expense_reports";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."expense_reports";
    drop policy if exists bsb_tenant_scope_update on "app_private"."expense_reports";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."expense_reports";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."expense_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."expense_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."expense_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."expense_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."expense_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Expenses: reports of lines in categories, spend policies checked on
-- submit, approval through the approvals block, and the approved total and
-- its reimbursement posted on the ledger.

-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
create table if not exists "app_private"."expense_categories" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "limit_amount" bigint check ("limit_amount" is null or "limit_amount" > 0),
  "receipt_over" bigint check ("receipt_over" is null or "receipt_over" >= 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  check (("limit_amount" is null and "receipt_over" is null) or "currency" is not null)
);
alter table "app_private"."expense_categories" enable row level security;
revoke all on "app_private"."expense_categories" from anon, authenticated;
grant select on "app_private"."expense_categories" to authenticated;
grant all on "app_private"."expense_categories" to service_role;
drop policy if exists "expense_categories_read" on "app_private"."expense_categories";
create policy "expense_categories_read" on "app_private"."expense_categories" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "app_private"."expense_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "title" text not null check (length("title") between 1 and 200),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "note" text check ("note" is null or length("note") <= 2000),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "approval_transaction_id" uuid,
  "reimbursed_at" timestamptz,
  "reimbursement_transaction_id" uuid,
  "cancelled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "expense_reports_tenant_idx" on "app_private"."expense_reports" ("tenant_id", "created_at" desc);
create index if not exists "expense_reports_user_idx" on "app_private"."expense_reports" ("user_id", "tenant_id");
create index if not exists "expense_reports_approval_idx" on "app_private"."expense_reports" ("approval_id") where "approval_id" is not null;
create index if not exists "expense_reports_approval_tx_idx" on "app_private"."expense_reports" ("approval_transaction_id") where "approval_transaction_id" is not null;
create index if not exists "expense_reports_reimbursement_idx" on "app_private"."expense_reports" ("reimbursement_transaction_id") where "reimbursement_transaction_id" is not null;
alter table "app_private"."expense_reports" enable row level security;
revoke all on "app_private"."expense_reports" from anon, authenticated;
grant select on "app_private"."expense_reports" to authenticated;
grant all on "app_private"."expense_reports" to service_role;
drop policy if exists "expense_reports_read" on "app_private"."expense_reports";
create policy "expense_reports_read" on "app_private"."expense_reports" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "app_private"."expense_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "report_id" uuid not null references "app_private"."expense_reports" ("id") on delete cascade,
  "category_id" uuid not null,
  "spent_on" date not null,
  "description" text not null check (length("description") between 1 and 500),
  "merchant" text check ("merchant" is null or length("merchant") <= 200),
  -- Minor units of the report's currency (ADR 0037).
  "amount" bigint not null check ("amount" > 0),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "category_id") references "app_private"."expense_categories" ("tenant_id", "id") on delete restrict
);
create index if not exists "expense_lines_report_idx" on "app_private"."expense_lines" ("report_id", "spent_on");
create index if not exists "expense_lines_category_idx" on "app_private"."expense_lines" ("tenant_id", "category_id");
alter table "app_private"."expense_lines" enable row level security;
revoke all on "app_private"."expense_lines" from anon, authenticated;
grant select on "app_private"."expense_lines" to authenticated;
grant all on "app_private"."expense_lines" to service_role;
drop policy if exists "expense_lines_read" on "app_private"."expense_lines";
create policy "expense_lines_read" on "app_private"."expense_lines" for select to authenticated
  using (
    exists (select 1 from "app_private"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read'))
  );

-- Creates or updates the category with this key and its spend policy.
create or replace function "app_private"."save_expense_category"(tenant uuid, key text, name text, currency text default null, limit_amount bigint default null, receipt_over bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_expense_category.tenant, 'expenses.manage'), false)) then
    raise exception 'not allowed to manage expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if save_expense_category.key is null or save_expense_category.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if nullif(trim(save_expense_category.name), '') is null then
    raise exception 'a category needs a name' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if (save_expense_category.limit_amount is not null or save_expense_category.receipt_over is not null)
    and (save_expense_category.currency is null or save_expense_category.currency !~ '^[A-Z]{3}$') then
    raise exception 'a limit or receipt threshold needs a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.limit_amount is not null and save_expense_category.limit_amount <= 0 then
    raise exception 'a limit is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null and save_expense_category.receipt_over < 0 then
    raise exception 'a receipt threshold is zero or more minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null then
    raise exception 'a receipt threshold needs the attachments block' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  insert into "app_private"."expense_categories" ("tenant_id", "key", "name", "currency", "limit_amount", "receipt_over")
  values (save_expense_category.tenant, save_expense_category.key, trim(save_expense_category.name), save_expense_category.currency,
    save_expense_category.limit_amount, save_expense_category.receipt_over)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "currency" = excluded."currency", "limit_amount" = excluded."limit_amount",
    "receipt_over" = excluded."receipt_over", "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_expense_category"(uuid, text, text, text, bigint, bigint) from public, anon;
grant execute on function "app_private"."save_expense_category"(uuid, text, text, text, bigint, bigint) to authenticated, service_role;

create or replace function "app_private"."archive_expense_category"(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."expense_categories" c where c."id" = archive_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "app_private"."expense_categories" c set "archived_at" = coalesce(c."archived_at", now()), "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."archive_expense_category"(uuid) from public, anon;
grant execute on function "app_private"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_expense_categories"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.read'), false)) or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to read expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") order by c."name", c."id"), '[]'::jsonb)
    from "app_private"."expense_categories" c
    where c."tenant_id" = list_expense_categories.tenant
      and (coalesce(list_expense_categories.include_archived, false) or c."archived_at" is null)
  );
end;
$$;
revoke execute on function "app_private"."list_expense_categories"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_expense_categories"(uuid, boolean) to authenticated, service_role;

-- The spend policy findings of a report, empty when it may be submitted:
-- a category total over its limit, a line over its category's receipt
-- threshold without a receipt, and a line in an archived category.
create or replace function "app_private"."expense_report_violations"(report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.v order by q.ord, q.at), '[]'::jsonb)
  from (
    select 1 as ord, min(l."created_at") as at, jsonb_build_object('kind', 'limit', 'categoryId', c."id", 'category', c."name",
        'limit', c."limit_amount"::text, 'total', sum(l."amount")::text, 'currency', c."currency") as v
      from "app_private"."expense_lines" l join "app_private"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."limit_amount" is not null
      group by c."id"
      having sum(l."amount") > c."limit_amount"
    union all
    select 2, l."created_at", jsonb_build_object('kind', 'receipt', 'lineId', l."id", 'categoryId', c."id", 'category', c."name",
        'receiptOver', c."receipt_over"::text, 'amount', l."amount"::text, 'currency', c."currency")
      from "app_private"."expense_lines" l join "app_private"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."receipt_over" is not null
        and l."amount" > c."receipt_over" and 0 = 0
    union all
    select 3, min(l."created_at"), jsonb_build_object('kind', 'archived', 'categoryId', c."id", 'category', c."name")
      from "app_private"."expense_lines" l join "app_private"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."archived_at" is not null
      group by c."id"
  ) q;
$$;
revoke execute on function "app_private"."expense_report_violations"(uuid) from public, anon, authenticated;

-- Opens a draft report in one currency. fields: the extra columns to set.
drop function if exists "app_private"."create_expense_report"(uuid, text, text, text, jsonb);
create or replace function "app_private"."create_expense_report"(tenant uuid, title text, currency text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', create_expense_report.tenant, 'expenses.submit'), false) then
    raise exception 'not allowed to submit expenses here' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if nullif(trim(create_expense_report.title), '') is null then
    raise exception 'a report needs a title' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if create_expense_report.currency is null or create_expense_report.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  insert into "app_private"."expense_reports" ("tenant_id", "user_id", "title", "currency", "note")
  values (create_expense_report.tenant, auth.uid(), trim(create_expense_report.title), create_expense_report.currency,
    nullif(trim(create_expense_report.note), ''))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "app_private"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "app_private"."create_expense_report"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."create_expense_report"(uuid, text, text, text) to authenticated, service_role;

create or replace function "app_private"."add_expense_line"(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "app_private"."expense_categories"%rowtype;
  v_line "app_private"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."expense_reports" x where x."id" = add_expense_line.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  select * into v_category from "app_private"."expense_categories" c
    where c."id" = add_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.spent_on is null then
    raise exception 'a line needs spent_on' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if add_expense_line.currency is not null and add_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.amount is null or add_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if nullif(trim(add_expense_line.description), '') is null then
    raise exception 'a line needs a description' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  insert into "app_private"."expense_lines" ("tenant_id", "report_id", "category_id", "spent_on", "description", "merchant", "amount")
  values (v_row."tenant_id", v_row."id", v_category."id", add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), add_expense_line.amount)
  returning * into v_line;
  update "app_private"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "app_private"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "app_private"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

-- Changes a line of a draft or rejected report; null keeps a value.
create or replace function "app_private"."update_expense_line"(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "app_private"."expense_categories"%rowtype;
  v_line "app_private"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "app_private"."expense_lines" l where l."id" = update_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "app_private"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if update_expense_line.category_id is not null then
  select * into v_category from "app_private"."expense_categories" c
    where c."id" = update_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  end if;
  if update_expense_line.currency is not null and update_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if update_expense_line.amount is not null and update_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  update "app_private"."expense_lines" l set
      "category_id" = coalesce(update_expense_line.category_id, l."category_id"),
      "spent_on" = coalesce(update_expense_line.spent_on, l."spent_on"),
      "amount" = coalesce(update_expense_line.amount, l."amount"),
      "description" = coalesce(nullif(trim(update_expense_line.description), ''), l."description"),
      "merchant" = coalesce(nullif(trim(update_expense_line.merchant), ''), l."merchant"),
      "updated_at" = now()
    where l."id" = v_line."id"
    returning * into v_line;
  update "app_private"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "app_private"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "app_private"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

create or replace function "app_private"."remove_expense_line"(line_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_line "app_private"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "app_private"."expense_lines" l where l."id" = remove_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "app_private"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  delete from "app_private"."expense_lines" l where l."id" = v_line."id";
  update "app_private"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "app_private"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "app_private"."remove_expense_line"(uuid) from public, anon;
grant execute on function "app_private"."remove_expense_line"(uuid) to authenticated, service_role;

create or replace function "app_private"."check_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "app_private"."expense_reports" x where x."id" = check_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return "app_private"."expense_report_violations"(v_row."id");
end;
$$;
revoke execute on function "app_private"."check_expense_report"(uuid) from public, anon;
grant execute on function "app_private"."check_expense_report"(uuid) to authenticated, service_role;

-- Submits a draft or rejected report for approval. Fails with
-- EXPENSE_POLICY_VIOLATION, listing the findings, while the report breaks
-- the spend policy.
create or replace function "app_private"."submit_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_violations jsonb;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."expense_reports" x where x."id" = submit_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if not exists (select 1 from "app_private"."expense_lines" l where l."report_id" = v_row."id") then
    raise exception 'a report needs at least one line' using errcode = '22023', hint = 'EXPENSE_REPORT_EMPTY';
  end if;
  v_violations := "app_private"."expense_report_violations"(v_row."id");
  if jsonb_array_length(v_violations) > 0 then
    raise exception 'the report breaks the spend policy: %', v_violations::text using errcode = '22023', hint = 'EXPENSE_POLICY_VIOLATION';
  end if;
  v_request := "better_supabase"."open_approval"(
    v_row."tenant_id", 'expense_report', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"expenses.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_row."user_id", 'title', v_row."title", 'total', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  update "app_private"."expense_reports" x set "approval_id" = (v_request ->> 'id')::uuid, "submitted_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "app_private"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "app_private"."submit_expense_report"(uuid) from public, anon;
grant execute on function "app_private"."submit_expense_report"(uuid) to authenticated, service_role;

-- Books an approved report once its approval is final: each category's
-- total on its expense account, the sum owed to the member on their payable
-- account. Approvals calls it; it isn't granted to anyone.
create or replace function "app_private"."approve_expense_report"(report_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from "app_private"."expense_reports" x
    where x."id" = approve_expense_report.report_id and x."approved_at" is null and x."cancelled_at" is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense', 'expenses:category:' || c."key" || ':' || v_row."currency", 'Expenses: ' || c."name", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', q.total) order by c."key")
    into v_lines
  from (
    select l."category_id" as category, sum(l."amount") as total
    from "app_private"."expense_lines" l where l."report_id" = v_row."id" group by l."category_id"
  ) q join "app_private"."expense_categories" c on c."id" = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)));
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.approved', v_lines,
    'expenses', v_row."id"::text, left('Expenses: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':approved', null,
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"));
  update "app_private"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
end;
$$;
revoke execute on function "app_private"."approve_expense_report"(uuid) from public, anon, authenticated;

-- Pays an approved report back: the member's payable account is settled
-- from expense cash.
create or replace function "app_private"."reimburse_expense_report"(report_id uuid, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."expense_reports" x where x."id" = reimburse_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'not allowed to reimburse expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) <> 'approved' then
    raise exception 'only an approved report can be reimbursed' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update "app_private"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "app_private"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "app_private"."reimburse_expense_report"(uuid, timestamptz, text) from public, anon;
grant execute on function "app_private"."reimburse_expense_report"(uuid, timestamptz, text) to authenticated, service_role;

-- Withdraws a report that isn't approved yet: its owner or a manager. A
-- pending approval is cancelled with it.
create or replace function "app_private"."cancel_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."expense_reports" x where x."id" = cancel_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false))) then
    raise exception 'not allowed to cancel this expense report' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'submitted', 'rejected') then
    raise exception 'an approved, reimbursed or cancelled report can''t be cancelled' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  update "app_private"."expense_reports" x set "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "app_private"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "app_private"."cancel_expense_report"(uuid) from public, anon;
grant execute on function "app_private"."cancel_expense_report"(uuid) to authenticated, service_role;

create or replace function "app_private"."get_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "app_private"."expense_reports" x where x."id" = get_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "app_private"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "app_private"."get_expense_report"(uuid) from public, anon;
grant execute on function "app_private"."get_expense_report"(uuid) to authenticated, service_role;

-- Reports, newest first: the caller's, or everyone's (or one member's) with
-- expenses.read.
create or replace function "app_private"."list_expense_reports"(tenant uuid, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.read'), false));
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to list expense reports' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if not v_reader and (coalesce(list_expense_reports.everyone, false) or (list_expense_reports.user_id is not null and list_expense_reports.user_id <> auth.uid())) then
    raise exception 'not allowed to read another member''s expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'title', q."title", 'currency', q."currency", 'note', q."note", 'status', (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "app_private"."expense_lines" y where y."report_id" = q."id"), 0)::text, 'approvalId', q."approval_id", 'submittedAt', q."submitted_at", 'approvedAt', q."approved_at", 'approvalTransactionId', q."approval_transaction_id", 'reimbursedAt', q."reimbursed_at", 'reimbursementTransactionId', q."reimbursement_transaction_id", 'cancelledAt', q."cancelled_at", 'createdAt', q."created_at", 'updatedAt', q."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "app_private"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "app_private"."expense_lines" l where l."report_id" = q."id")) as item, q."created_at" as created, q."id" as id
      from "app_private"."expense_reports" q
      left join "better_supabase"."approval_requests" p on p."id" = q."approval_id"
      where q."tenant_id" = list_expense_reports.tenant
        and (case
          when coalesce(list_expense_reports.everyone, false) then true
          when list_expense_reports.user_id is not null then q."user_id" = list_expense_reports.user_id
          else q."user_id" = auth.uid()
        end)
        and (list_expense_reports.status is null or (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) = list_expense_reports.status)
      order by q."created_at" desc, q."id"
      limit least(greatest(coalesce(list_expense_reports.page_size, 100), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "app_private"."list_expense_reports"(uuid, uuid, text, boolean, integer) from public, anon;
grant execute on function "app_private"."list_expense_reports"(uuid, uuid, text, boolean, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."expense_categories";
drop policy if exists bsb_tenant_scope_select on "app_private"."expense_categories";
create policy bsb_tenant_scope_select on "app_private"."expense_categories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."expense_categories";
create policy bsb_tenant_scope_insert on "app_private"."expense_categories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."expense_categories";
create policy bsb_tenant_scope_update on "app_private"."expense_categories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."expense_categories";
create policy bsb_tenant_scope_delete on "app_private"."expense_categories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."expense_reports";
drop policy if exists bsb_tenant_scope_select on "app_private"."expense_reports";
create policy bsb_tenant_scope_select on "app_private"."expense_reports" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."expense_reports";
create policy bsb_tenant_scope_insert on "app_private"."expense_reports" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."expense_reports";
create policy bsb_tenant_scope_update on "app_private"."expense_reports" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."expense_reports";
create policy bsb_tenant_scope_delete on "app_private"."expense_reports" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."expense_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."expense_lines";
create policy bsb_tenant_scope_select on "app_private"."expense_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "app_private"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."expense_lines";
create policy bsb_tenant_scope_insert on "app_private"."expense_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."expense_lines";
create policy bsb_tenant_scope_update on "app_private"."expense_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."expense_lines";
create policy bsb_tenant_scope_delete on "app_private"."expense_lines" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:acad5782117da37aa32eb5b47f0372cb87a9105ea9687dd5f8de16d1ca73932f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block expenses@1 managed
-- @bsb-hash sha256:978540dd8a0c7d52602c4bbfb33d800eb720f676a0d01ccd3a03513003c45102
-- Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Expenses: reports of lines in categories, spend policies checked on
-- submit, approval through the approvals block, and the approved total and
-- its reimbursement posted on the ledger.

-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
create table if not exists "better_supabase"."expense_categories" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "limit_amount" bigint check ("limit_amount" is null or "limit_amount" > 0),
  "receipt_over" bigint check ("receipt_over" is null or "receipt_over" >= 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  check (("limit_amount" is null and "receipt_over" is null) or "currency" is not null)
);
alter table "better_supabase"."expense_categories" enable row level security;
revoke all on "better_supabase"."expense_categories" from anon, authenticated;
grant select on "better_supabase"."expense_categories" to authenticated;
grant all on "better_supabase"."expense_categories" to service_role;
drop policy if exists "expense_categories_read" on "better_supabase"."expense_categories";
create policy "expense_categories_read" on "better_supabase"."expense_categories" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "better_supabase"."expense_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "title" text not null check (length("title") between 1 and 200),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "note" text check ("note" is null or length("note") <= 2000),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "approval_transaction_id" uuid,
  "reimbursed_at" timestamptz,
  "reimbursement_transaction_id" uuid,
  "cancelled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "expense_reports_tenant_idx" on "better_supabase"."expense_reports" ("tenant_id", "created_at" desc);
create index if not exists "expense_reports_user_idx" on "better_supabase"."expense_reports" ("user_id", "tenant_id");
create index if not exists "expense_reports_approval_idx" on "better_supabase"."expense_reports" ("approval_id") where "approval_id" is not null;
create index if not exists "expense_reports_approval_tx_idx" on "better_supabase"."expense_reports" ("approval_transaction_id") where "approval_transaction_id" is not null;
create index if not exists "expense_reports_reimbursement_idx" on "better_supabase"."expense_reports" ("reimbursement_transaction_id") where "reimbursement_transaction_id" is not null;
alter table "better_supabase"."expense_reports" enable row level security;
revoke all on "better_supabase"."expense_reports" from anon, authenticated;
grant select on "better_supabase"."expense_reports" to authenticated;
grant all on "better_supabase"."expense_reports" to service_role;
drop policy if exists "expense_reports_read" on "better_supabase"."expense_reports";
create policy "expense_reports_read" on "better_supabase"."expense_reports" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "better_supabase"."expense_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "report_id" uuid not null references "better_supabase"."expense_reports" ("id") on delete cascade,
  "category_id" uuid not null,
  "spent_on" date not null,
  "description" text not null check (length("description") between 1 and 500),
  "merchant" text check ("merchant" is null or length("merchant") <= 200),
  -- Minor units of the report's currency (ADR 0037).
  "amount" bigint not null check ("amount" > 0),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "category_id") references "better_supabase"."expense_categories" ("tenant_id", "id") on delete restrict
);
create index if not exists "expense_lines_report_idx" on "better_supabase"."expense_lines" ("report_id", "spent_on");
create index if not exists "expense_lines_category_idx" on "better_supabase"."expense_lines" ("tenant_id", "category_id");
alter table "better_supabase"."expense_lines" enable row level security;
revoke all on "better_supabase"."expense_lines" from anon, authenticated;
grant select on "better_supabase"."expense_lines" to authenticated;
grant all on "better_supabase"."expense_lines" to service_role;
drop policy if exists "expense_lines_read" on "better_supabase"."expense_lines";
create policy "expense_lines_read" on "better_supabase"."expense_lines" for select to authenticated
  using (
    exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read'))
  );

-- Creates or updates the category with this key and its spend policy.
create or replace function "better_supabase"."save_expense_category"(tenant uuid, key text, name text, currency text default null, limit_amount bigint default null, receipt_over bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_expense_category.tenant, 'expenses.manage'), false)) then
    raise exception 'not allowed to manage expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if save_expense_category.key is null or save_expense_category.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if nullif(trim(save_expense_category.name), '') is null then
    raise exception 'a category needs a name' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if (save_expense_category.limit_amount is not null or save_expense_category.receipt_over is not null)
    and (save_expense_category.currency is null or save_expense_category.currency !~ '^[A-Z]{3}$') then
    raise exception 'a limit or receipt threshold needs a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.limit_amount is not null and save_expense_category.limit_amount <= 0 then
    raise exception 'a limit is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null and save_expense_category.receipt_over < 0 then
    raise exception 'a receipt threshold is zero or more minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null then
    raise exception 'a receipt threshold needs the attachments block' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  insert into "better_supabase"."expense_categories" ("tenant_id", "key", "name", "currency", "limit_amount", "receipt_over")
  values (save_expense_category.tenant, save_expense_category.key, trim(save_expense_category.name), save_expense_category.currency,
    save_expense_category.limit_amount, save_expense_category.receipt_over)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "currency" = excluded."currency", "limit_amount" = excluded."limit_amount",
    "receipt_over" = excluded."receipt_over", "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) from public, anon;
grant execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) to authenticated, service_role;

create or replace function "better_supabase"."archive_expense_category"(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_categories" c where c."id" = archive_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "better_supabase"."expense_categories" c set "archived_at" = coalesce(c."archived_at", now()), "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_expense_categories"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.read'), false)) or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to read expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") order by c."name", c."id"), '[]'::jsonb)
    from "better_supabase"."expense_categories" c
    where c."tenant_id" = list_expense_categories.tenant
      and (coalesce(list_expense_categories.include_archived, false) or c."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_categories"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_expense_categories"(uuid, boolean) to authenticated, service_role;

-- The spend policy findings of a report, empty when it may be submitted:
-- a category total over its limit, a line over its category's receipt
-- threshold without a receipt, and a line in an archived category.
create or replace function "better_supabase"."expense_report_violations"(report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.v order by q.ord, q.at), '[]'::jsonb)
  from (
    select 1 as ord, min(l."created_at") as at, jsonb_build_object('kind', 'limit', 'categoryId', c."id", 'category', c."name",
        'limit', c."limit_amount"::text, 'total', sum(l."amount")::text, 'currency', c."currency") as v
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."limit_amount" is not null
      group by c."id"
      having sum(l."amount") > c."limit_amount"
    union all
    select 2, l."created_at", jsonb_build_object('kind', 'receipt', 'lineId', l."id", 'categoryId', c."id", 'category', c."name",
        'receiptOver', c."receipt_over"::text, 'amount', l."amount"::text, 'currency', c."currency")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."receipt_over" is not null
        and l."amount" > c."receipt_over" and 0 = 0
    union all
    select 3, min(l."created_at"), jsonb_build_object('kind', 'archived', 'categoryId', c."id", 'category', c."name")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."archived_at" is not null
      group by c."id"
  ) q;
$$;
revoke execute on function "better_supabase"."expense_report_violations"(uuid) from public, anon, authenticated;

-- Opens a draft report in one currency. fields: the extra columns to set.
drop function if exists "better_supabase"."create_expense_report"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."create_expense_report"(tenant uuid, title text, currency text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', create_expense_report.tenant, 'expenses.submit'), false) then
    raise exception 'not allowed to submit expenses here' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if nullif(trim(create_expense_report.title), '') is null then
    raise exception 'a report needs a title' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if create_expense_report.currency is null or create_expense_report.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  insert into "better_supabase"."expense_reports" ("tenant_id", "user_id", "title", "currency", "note")
  values (create_expense_report.tenant, auth.uid(), trim(create_expense_report.title), create_expense_report.currency,
    nullif(trim(create_expense_report.note), ''))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."add_expense_line"(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = add_expense_line.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = add_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.spent_on is null then
    raise exception 'a line needs spent_on' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if add_expense_line.currency is not null and add_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.amount is null or add_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if nullif(trim(add_expense_line.description), '') is null then
    raise exception 'a line needs a description' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  insert into "better_supabase"."expense_lines" ("tenant_id", "report_id", "category_id", "spent_on", "description", "merchant", "amount")
  values (v_row."tenant_id", v_row."id", v_category."id", add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), add_expense_line.amount)
  returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

-- Changes a line of a draft or rejected report; null keeps a value.
create or replace function "better_supabase"."update_expense_line"(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = update_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if update_expense_line.category_id is not null then
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = update_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  end if;
  if update_expense_line.currency is not null and update_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if update_expense_line.amount is not null and update_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  update "better_supabase"."expense_lines" l set
      "category_id" = coalesce(update_expense_line.category_id, l."category_id"),
      "spent_on" = coalesce(update_expense_line.spent_on, l."spent_on"),
      "amount" = coalesce(update_expense_line.amount, l."amount"),
      "description" = coalesce(nullif(trim(update_expense_line.description), ''), l."description"),
      "merchant" = coalesce(nullif(trim(update_expense_line.merchant), ''), l."merchant"),
      "updated_at" = now()
    where l."id" = v_line."id"
    returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_expense_line"(line_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = remove_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  delete from "better_supabase"."expense_lines" l where l."id" = v_line."id";
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."remove_expense_line"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_expense_line"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."check_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = check_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return "better_supabase"."expense_report_violations"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."check_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."check_expense_report"(uuid) to authenticated, service_role;

-- Submits a draft or rejected report for approval. Fails with
-- EXPENSE_POLICY_VIOLATION, listing the findings, while the report breaks
-- the spend policy.
create or replace function "better_supabase"."submit_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_violations jsonb;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = submit_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if not exists (select 1 from "better_supabase"."expense_lines" l where l."report_id" = v_row."id") then
    raise exception 'a report needs at least one line' using errcode = '22023', hint = 'EXPENSE_REPORT_EMPTY';
  end if;
  v_violations := "better_supabase"."expense_report_violations"(v_row."id");
  if jsonb_array_length(v_violations) > 0 then
    raise exception 'the report breaks the spend policy: %', v_violations::text using errcode = '22023', hint = 'EXPENSE_POLICY_VIOLATION';
  end if;
  v_request := "better_supabase"."open_approval"(
    v_row."tenant_id", 'expense_report', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"expenses.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_row."user_id", 'title', v_row."title", 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  update "better_supabase"."expense_reports" x set "approval_id" = (v_request ->> 'id')::uuid, "submitted_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."submit_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."submit_expense_report"(uuid) to authenticated, service_role;

-- Books an approved report once its approval is final: each category's
-- total on its expense account, the sum owed to the member on their payable
-- account. Approvals calls it; it isn't granted to anyone.
create or replace function "better_supabase"."approve_expense_report"(report_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."expense_reports" x
    where x."id" = approve_expense_report.report_id and x."approved_at" is null and x."cancelled_at" is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense', 'expenses:category:' || c."key" || ':' || v_row."currency", 'Expenses: ' || c."name", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', q.total) order by c."key")
    into v_lines
  from (
    select l."category_id" as category, sum(l."amount") as total
    from "better_supabase"."expense_lines" l where l."report_id" = v_row."id" group by l."category_id"
  ) q join "better_supabase"."expense_categories" c on c."id" = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)));
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.approved', v_lines,
    'expenses', v_row."id"::text, left('Expenses: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':approved', null,
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"));
  update "better_supabase"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
end;
$$;
revoke execute on function "better_supabase"."approve_expense_report"(uuid) from public, anon, authenticated;

-- Pays an approved report back: the member's payable account is settled
-- from expense cash.
create or replace function "better_supabase"."reimburse_expense_report"(report_id uuid, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = reimburse_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'not allowed to reimburse expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) <> 'approved' then
    raise exception 'only an approved report can be reimbursed' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) to authenticated, service_role;

-- Withdraws a report that isn't approved yet: its owner or a manager. A
-- pending approval is cancelled with it.
create or replace function "better_supabase"."cancel_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = cancel_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false))) then
    raise exception 'not allowed to cancel this expense report' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'submitted', 'rejected') then
    raise exception 'an approved, reimbursed or cancelled report can''t be cancelled' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  update "better_supabase"."expense_reports" x set "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_expense_report"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = get_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."get_expense_report"(uuid) to authenticated, service_role;

-- Reports, newest first: the caller's, or everyone's (or one member's) with
-- expenses.read.
create or replace function "better_supabase"."list_expense_reports"(tenant uuid, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.read'), false));
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to list expense reports' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if not v_reader and (coalesce(list_expense_reports.everyone, false) or (list_expense_reports.user_id is not null and list_expense_reports.user_id <> auth.uid())) then
    raise exception 'not allowed to read another member''s expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'title', q."title", 'currency', q."currency", 'note', q."note", 'status', (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = q."id"), 0)::text, 'approvalId', q."approval_id", 'submittedAt', q."submitted_at", 'approvedAt', q."approved_at", 'approvalTransactionId', q."approval_transaction_id", 'reimbursedAt', q."reimbursed_at", 'reimbursementTransactionId', q."reimbursement_transaction_id", 'cancelledAt', q."cancelled_at", 'createdAt', q."created_at", 'updatedAt', q."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = q."id")) as item, q."created_at" as created, q."id" as id
      from "better_supabase"."expense_reports" q
      left join "better_supabase"."approval_requests" p on p."id" = q."approval_id"
      where q."tenant_id" = list_expense_reports.tenant
        and (case
          when coalesce(list_expense_reports.everyone, false) then true
          when list_expense_reports.user_id is not null then q."user_id" = list_expense_reports.user_id
          else q."user_id" = auth.uid()
        end)
        and (list_expense_reports.status is null or (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) = list_expense_reports.status)
      order by q."created_at" desc, q."id"
      limit least(greatest(coalesce(list_expense_reports.page_size, 100), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_select on "better_supabase"."expense_categories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_categories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_update on "better_supabase"."expense_categories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_categories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_select on "better_supabase"."expense_reports" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_reports" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_update on "better_supabase"."expense_reports" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_reports" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_select on "better_supabase"."expense_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_update on "better_supabase"."expense_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.expenses.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_expense_report"(uuid, text, text, text, jsonb);

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

create or replace function "api"."save_expense_category"(tenant uuid, key text, name text, currency text default null, limit_amount bigint default null, receipt_over bigint default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_expense_category"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."save_expense_category"(uuid, text, text, text, bigint, bigint) from public, anon;
grant execute on function "api"."save_expense_category"(uuid, text, text, text, bigint, bigint) to authenticated, service_role;

create or replace function "api"."archive_expense_category"(category_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_expense_category"($1) $$;
revoke execute on function "api"."archive_expense_category"(uuid) from public, anon;
grant execute on function "api"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "api"."list_expense_categories"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_expense_categories"($1, $2) $$;
revoke execute on function "api"."list_expense_categories"(uuid, boolean) from public, anon;
grant execute on function "api"."list_expense_categories"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."create_expense_report"(tenant uuid, title text, currency text, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_expense_report"($1, $2, $3, $4) $$;
revoke execute on function "api"."create_expense_report"(uuid, text, text, text) from public, anon;
grant execute on function "api"."create_expense_report"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."add_expense_line"(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null, currency text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_expense_line"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "api"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

create or replace function "api"."update_expense_line"(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null, currency text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_expense_line"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "api"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

create or replace function "api"."remove_expense_line"(line_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_expense_line"($1) $$;
revoke execute on function "api"."remove_expense_line"(uuid) from public, anon;
grant execute on function "api"."remove_expense_line"(uuid) to authenticated, service_role;

create or replace function "api"."check_expense_report"(report_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_expense_report"($1) $$;
revoke execute on function "api"."check_expense_report"(uuid) from public, anon;
grant execute on function "api"."check_expense_report"(uuid) to authenticated, service_role;

create or replace function "api"."submit_expense_report"(report_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."submit_expense_report"($1) $$;
revoke execute on function "api"."submit_expense_report"(uuid) from public, anon;
grant execute on function "api"."submit_expense_report"(uuid) to authenticated, service_role;

create or replace function "api"."reimburse_expense_report"(report_id uuid, paid_at timestamptz default null, reference text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reimburse_expense_report"($1, $2, $3) $$;
revoke execute on function "api"."reimburse_expense_report"(uuid, timestamptz, text) from public, anon;
grant execute on function "api"."reimburse_expense_report"(uuid, timestamptz, text) to authenticated, service_role;

create or replace function "api"."cancel_expense_report"(report_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_expense_report"($1) $$;
revoke execute on function "api"."cancel_expense_report"(uuid) from public, anon;
grant execute on function "api"."cancel_expense_report"(uuid) to authenticated, service_role;

create or replace function "api"."get_expense_report"(report_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_expense_report"($1) $$;
revoke execute on function "api"."get_expense_report"(uuid) from public, anon;
grant execute on function "api"."get_expense_report"(uuid) to authenticated, service_role;

create or replace function "api"."list_expense_reports"(tenant uuid, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_expense_reports"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_expense_reports"(uuid, uuid, text, boolean, integer) from public, anon;
grant execute on function "api"."list_expense_reports"(uuid, uuid, text, boolean, integer) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:acad5782117da37aa32eb5b47f0372cb87a9105ea9687dd5f8de16d1ca73932f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block expenses@1 managed
-- @bsb-hash sha256:26c7cf0a89bfaab1d191d340e12cebdbd8e044d285d021a61d9a80d1018ac8ae
-- Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Expenses: reports of lines in categories, spend policies checked on
-- submit, approval through the approvals block, and the approved total and
-- its reimbursement posted on the ledger.

-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
-- better_supabase.expense_categories is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."expense_categories" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."expense_categories" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."expense_categories" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."expense_categories" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."expense_categories" add column if not exists "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."expense_categories" add column if not exists "limit_amount" bigint check ("limit_amount" is null or "limit_amount" > 0);
alter table "better_supabase"."expense_categories" add column if not exists "receipt_over" bigint check ("receipt_over" is null or "receipt_over" >= 0);
alter table "better_supabase"."expense_categories" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."expense_categories" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."expense_categories" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "expense_categories_tenant_id_key_key" on "better_supabase"."expense_categories" ("tenant_id", "key");
create unique index if not exists "expense_categories_tenant_id_id_key" on "better_supabase"."expense_categories" ("tenant_id", "id");
alter table "better_supabase"."expense_categories" enable row level security;
grant select on "better_supabase"."expense_categories" to authenticated;
grant all on "better_supabase"."expense_categories" to service_role;
drop policy if exists bsb_expense_categories_select on "better_supabase"."expense_categories";
create policy bsb_expense_categories_select on "better_supabase"."expense_categories" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

-- better_supabase.expense_reports is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."expense_reports" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."expense_reports" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."expense_reports" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."expense_reports" add column if not exists "title" text check (length("title") between 1 and 200);
alter table "better_supabase"."expense_reports" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."expense_reports" add column if not exists "note" text check ("note" is null or length("note") <= 2000);
alter table "better_supabase"."expense_reports" add column if not exists "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null;
alter table "better_supabase"."expense_reports" add column if not exists "submitted_at" timestamptz;
alter table "better_supabase"."expense_reports" add column if not exists "approved_at" timestamptz;
alter table "better_supabase"."expense_reports" add column if not exists "approval_transaction_id" uuid;
alter table "better_supabase"."expense_reports" add column if not exists "reimbursed_at" timestamptz;
alter table "better_supabase"."expense_reports" add column if not exists "reimbursement_transaction_id" uuid;
alter table "better_supabase"."expense_reports" add column if not exists "cancelled_at" timestamptz;
alter table "better_supabase"."expense_reports" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."expense_reports" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "expense_reports_tenant_idx" on "better_supabase"."expense_reports" ("tenant_id", "created_at" desc);
create index if not exists "expense_reports_user_idx" on "better_supabase"."expense_reports" ("user_id", "tenant_id");
create index if not exists "expense_reports_approval_idx" on "better_supabase"."expense_reports" ("approval_id") where "approval_id" is not null;
create index if not exists "expense_reports_approval_tx_idx" on "better_supabase"."expense_reports" ("approval_transaction_id") where "approval_transaction_id" is not null;
create index if not exists "expense_reports_reimbursement_idx" on "better_supabase"."expense_reports" ("reimbursement_transaction_id") where "reimbursement_transaction_id" is not null;
alter table "better_supabase"."expense_reports" enable row level security;
grant select on "better_supabase"."expense_reports" to authenticated;
grant all on "better_supabase"."expense_reports" to service_role;
drop policy if exists bsb_expense_reports_select on "better_supabase"."expense_reports";
create policy bsb_expense_reports_select on "better_supabase"."expense_reports" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

-- better_supabase.expense_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."expense_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."expense_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."expense_lines" add column if not exists "report_id" uuid references "better_supabase"."expense_reports" ("id") on delete cascade;
alter table "better_supabase"."expense_lines" add column if not exists "category_id" uuid;
alter table "better_supabase"."expense_lines" add column if not exists "spent_on" date;
alter table "better_supabase"."expense_lines" add column if not exists "description" text check (length("description") between 1 and 500);
alter table "better_supabase"."expense_lines" add column if not exists "merchant" text check ("merchant" is null or length("merchant") <= 200);
alter table "better_supabase"."expense_lines" add column if not exists "amount" bigint check ("amount" > 0);
alter table "better_supabase"."expense_lines" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."expense_lines" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "expense_lines_report_idx" on "better_supabase"."expense_lines" ("report_id", "spent_on");
create index if not exists "expense_lines_category_idx" on "better_supabase"."expense_lines" ("tenant_id", "category_id");
alter table "better_supabase"."expense_lines" enable row level security;
grant select on "better_supabase"."expense_lines" to authenticated;
grant all on "better_supabase"."expense_lines" to service_role;
drop policy if exists bsb_expense_lines_select on "better_supabase"."expense_lines";
create policy bsb_expense_lines_select on "better_supabase"."expense_lines" for select to authenticated
  using (
    exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read'))
  );

-- Creates or updates the category with this key and its spend policy.
create or replace function "better_supabase"."save_expense_category"(tenant uuid, key text, name text, currency text default null, limit_amount bigint default null, receipt_over bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_expense_category.tenant, 'expenses.manage'), false)) then
    raise exception 'not allowed to manage expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if save_expense_category.key is null or save_expense_category.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if nullif(trim(save_expense_category.name), '') is null then
    raise exception 'a category needs a name' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if (save_expense_category.limit_amount is not null or save_expense_category.receipt_over is not null)
    and (save_expense_category.currency is null or save_expense_category.currency !~ '^[A-Z]{3}$') then
    raise exception 'a limit or receipt threshold needs a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.limit_amount is not null and save_expense_category.limit_amount <= 0 then
    raise exception 'a limit is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null and save_expense_category.receipt_over < 0 then
    raise exception 'a receipt threshold is zero or more minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null then
    raise exception 'a receipt threshold needs the attachments block' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  insert into "better_supabase"."expense_categories" ("tenant_id", "key", "name", "currency", "limit_amount", "receipt_over")
  values (save_expense_category.tenant, save_expense_category.key, trim(save_expense_category.name), save_expense_category.currency,
    save_expense_category.limit_amount, save_expense_category.receipt_over)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "currency" = excluded."currency", "limit_amount" = excluded."limit_amount",
    "receipt_over" = excluded."receipt_over", "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) from public, anon;
grant execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) to authenticated, service_role;

create or replace function "better_supabase"."archive_expense_category"(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_categories" c where c."id" = archive_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "better_supabase"."expense_categories" c set "archived_at" = coalesce(c."archived_at", now()), "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_expense_categories"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.read'), false)) or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to read expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") order by c."name", c."id"), '[]'::jsonb)
    from "better_supabase"."expense_categories" c
    where c."tenant_id" = list_expense_categories.tenant
      and (coalesce(list_expense_categories.include_archived, false) or c."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_categories"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_expense_categories"(uuid, boolean) to authenticated, service_role;

-- The spend policy findings of a report, empty when it may be submitted:
-- a category total over its limit, a line over its category's receipt
-- threshold without a receipt, and a line in an archived category.
create or replace function "better_supabase"."expense_report_violations"(report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.v order by q.ord, q.at), '[]'::jsonb)
  from (
    select 1 as ord, min(l."created_at") as at, jsonb_build_object('kind', 'limit', 'categoryId', c."id", 'category', c."name",
        'limit', c."limit_amount"::text, 'total', sum(l."amount")::text, 'currency', c."currency") as v
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."limit_amount" is not null
      group by c."id"
      having sum(l."amount") > c."limit_amount"
    union all
    select 2, l."created_at", jsonb_build_object('kind', 'receipt', 'lineId', l."id", 'categoryId', c."id", 'category', c."name",
        'receiptOver', c."receipt_over"::text, 'amount', l."amount"::text, 'currency', c."currency")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."receipt_over" is not null
        and l."amount" > c."receipt_over" and 0 = 0
    union all
    select 3, min(l."created_at"), jsonb_build_object('kind', 'archived', 'categoryId', c."id", 'category', c."name")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."archived_at" is not null
      group by c."id"
  ) q;
$$;
revoke execute on function "better_supabase"."expense_report_violations"(uuid) from public, anon, authenticated;

-- Opens a draft report in one currency. fields: the extra columns to set.
drop function if exists "better_supabase"."create_expense_report"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."create_expense_report"(tenant uuid, title text, currency text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', create_expense_report.tenant, 'expenses.submit'), false) then
    raise exception 'not allowed to submit expenses here' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if nullif(trim(create_expense_report.title), '') is null then
    raise exception 'a report needs a title' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if create_expense_report.currency is null or create_expense_report.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  insert into "better_supabase"."expense_reports" ("tenant_id", "user_id", "title", "currency", "note")
  values (create_expense_report.tenant, auth.uid(), trim(create_expense_report.title), create_expense_report.currency,
    nullif(trim(create_expense_report.note), ''))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."add_expense_line"(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = add_expense_line.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = add_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.spent_on is null then
    raise exception 'a line needs spent_on' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if add_expense_line.currency is not null and add_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.amount is null or add_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if nullif(trim(add_expense_line.description), '') is null then
    raise exception 'a line needs a description' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  insert into "better_supabase"."expense_lines" ("tenant_id", "report_id", "category_id", "spent_on", "description", "merchant", "amount")
  values (v_row."tenant_id", v_row."id", v_category."id", add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), add_expense_line.amount)
  returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

-- Changes a line of a draft or rejected report; null keeps a value.
create or replace function "better_supabase"."update_expense_line"(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = update_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if update_expense_line.category_id is not null then
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = update_expense_line.category_id and c."tenant_id" = v_row."tenant_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  end if;
  if update_expense_line.currency is not null and update_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if update_expense_line.amount is not null and update_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  update "better_supabase"."expense_lines" l set
      "category_id" = coalesce(update_expense_line.category_id, l."category_id"),
      "spent_on" = coalesce(update_expense_line.spent_on, l."spent_on"),
      "amount" = coalesce(update_expense_line.amount, l."amount"),
      "description" = coalesce(nullif(trim(update_expense_line.description), ''), l."description"),
      "merchant" = coalesce(nullif(trim(update_expense_line.merchant), ''), l."merchant"),
      "updated_at" = now()
    where l."id" = v_line."id"
    returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_expense_line"(line_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = remove_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  delete from "better_supabase"."expense_lines" l where l."id" = v_line."id";
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."remove_expense_line"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_expense_line"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."check_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = check_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return "better_supabase"."expense_report_violations"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."check_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."check_expense_report"(uuid) to authenticated, service_role;

-- Submits a draft or rejected report for approval. Fails with
-- EXPENSE_POLICY_VIOLATION, listing the findings, while the report breaks
-- the spend policy.
create or replace function "better_supabase"."submit_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_violations jsonb;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = submit_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if not exists (select 1 from "better_supabase"."expense_lines" l where l."report_id" = v_row."id") then
    raise exception 'a report needs at least one line' using errcode = '22023', hint = 'EXPENSE_REPORT_EMPTY';
  end if;
  v_violations := "better_supabase"."expense_report_violations"(v_row."id");
  if jsonb_array_length(v_violations) > 0 then
    raise exception 'the report breaks the spend policy: %', v_violations::text using errcode = '22023', hint = 'EXPENSE_POLICY_VIOLATION';
  end if;
  v_request := "better_supabase"."open_approval"(
    v_row."tenant_id", 'expense_report', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"expenses.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_row."user_id", 'title', v_row."title", 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  update "better_supabase"."expense_reports" x set "approval_id" = (v_request ->> 'id')::uuid, "submitted_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."submit_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."submit_expense_report"(uuid) to authenticated, service_role;

-- Books an approved report once its approval is final: each category's
-- total on its expense account, the sum owed to the member on their payable
-- account. Approvals calls it; it isn't granted to anyone.
create or replace function "better_supabase"."approve_expense_report"(report_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."expense_reports" x
    where x."id" = approve_expense_report.report_id and x."approved_at" is null and x."cancelled_at" is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense', 'expenses:category:' || c."key" || ':' || v_row."currency", 'Expenses: ' || c."name", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', q.total) order by c."key")
    into v_lines
  from (
    select l."category_id" as category, sum(l."amount") as total
    from "better_supabase"."expense_lines" l where l."report_id" = v_row."id" group by l."category_id"
  ) q join "better_supabase"."expense_categories" c on c."id" = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)));
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.approved', v_lines,
    'expenses', v_row."id"::text, left('Expenses: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':approved', null,
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"));
  update "better_supabase"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
end;
$$;
revoke execute on function "better_supabase"."approve_expense_report"(uuid) from public, anon, authenticated;

-- Pays an approved report back: the member's payable account is settled
-- from expense cash.
create or replace function "better_supabase"."reimburse_expense_report"(report_id uuid, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = reimburse_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'not allowed to reimburse expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) <> 'approved' then
    raise exception 'only an approved report can be reimbursed' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) to authenticated, service_role;

-- Withdraws a report that isn't approved yet: its owner or a manager. A
-- pending approval is cancelled with it.
create or replace function "better_supabase"."cancel_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = cancel_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false))) then
    raise exception 'not allowed to cancel this expense report' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'submitted', 'rejected') then
    raise exception 'an approved, reimbursed or cancelled report can''t be cancelled' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  update "better_supabase"."expense_reports" x set "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_expense_report"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = get_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."get_expense_report"(uuid) to authenticated, service_role;

-- Reports, newest first: the caller's, or everyone's (or one member's) with
-- expenses.read.
create or replace function "better_supabase"."list_expense_reports"(tenant uuid, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.read'), false));
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to list expense reports' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if not v_reader and (coalesce(list_expense_reports.everyone, false) or (list_expense_reports.user_id is not null and list_expense_reports.user_id <> auth.uid())) then
    raise exception 'not allowed to read another member''s expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'title', q."title", 'currency', q."currency", 'note', q."note", 'status', (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = q."id"), 0)::text, 'approvalId', q."approval_id", 'submittedAt', q."submitted_at", 'approvedAt', q."approved_at", 'approvalTransactionId', q."approval_transaction_id", 'reimbursedAt', q."reimbursed_at", 'reimbursementTransactionId', q."reimbursement_transaction_id", 'cancelledAt', q."cancelled_at", 'createdAt', q."created_at", 'updatedAt', q."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = q."id")) as item, q."created_at" as created, q."id" as id
      from "better_supabase"."expense_reports" q
      left join "better_supabase"."approval_requests" p on p."id" = q."approval_id"
      where q."tenant_id" = list_expense_reports.tenant
        and (case
          when coalesce(list_expense_reports.everyone, false) then true
          when list_expense_reports.user_id is not null then q."user_id" = list_expense_reports.user_id
          else q."user_id" = auth.uid()
        end)
        and (list_expense_reports.status is null or (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) = list_expense_reports.status)
      order by q."created_at" desc, q."id"
      limit least(greatest(coalesce(list_expense_reports.page_size, 100), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_select on "better_supabase"."expense_categories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_categories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_update on "better_supabase"."expense_categories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_categories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_select on "better_supabase"."expense_reports" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_reports" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_update on "better_supabase"."expense_reports" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_reports" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_select on "better_supabase"."expense_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_update on "better_supabase"."expense_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_lines" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:acad5782117da37aa32eb5b47f0372cb87a9105ea9687dd5f8de16d1ca73932f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block expenses@1 managed
-- @bsb-hash sha256:2a1c8080caeca9e5328b87111e95e9fd69936852371ca597341e72738c411e93
-- Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Expenses: reports of lines in categories, spend policies checked on
-- submit, approval through the approvals block, and the approved total and
-- its reimbursement posted on the ledger.

-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
create table if not exists "better_supabase"."expense_categories" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "limit_amount" bigint check ("limit_amount" is null or "limit_amount" > 0),
  "receipt_over" bigint check ("receipt_over" is null or "receipt_over" >= 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key"),
  unique ("org_id", "id"),
  check (("limit_amount" is null and "receipt_over" is null) or "currency" is not null)
);
alter table "better_supabase"."expense_categories" enable row level security;
revoke all on "better_supabase"."expense_categories" from anon, authenticated;
grant select on "better_supabase"."expense_categories" to authenticated;
grant all on "better_supabase"."expense_categories" to service_role;
drop policy if exists "expense_categories_read" on "better_supabase"."expense_categories";
create policy "expense_categories_read" on "better_supabase"."expense_categories" for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "better_supabase"."expense_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "title" text not null check (length("title") between 1 and 200),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "note" text check ("note" is null or length("note") <= 2000),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "approval_transaction_id" uuid,
  "reimbursed_at" timestamptz,
  "reimbursement_transaction_id" uuid,
  "cancelled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists "expense_reports_tenant_idx" on "better_supabase"."expense_reports" ("org_id", "created_at" desc);
create index if not exists "expense_reports_user_idx" on "better_supabase"."expense_reports" ("user_id", "org_id");
create index if not exists "expense_reports_approval_idx" on "better_supabase"."expense_reports" ("approval_id") where "approval_id" is not null;
create index if not exists "expense_reports_approval_tx_idx" on "better_supabase"."expense_reports" ("approval_transaction_id") where "approval_transaction_id" is not null;
create index if not exists "expense_reports_reimbursement_idx" on "better_supabase"."expense_reports" ("reimbursement_transaction_id") where "reimbursement_transaction_id" is not null;
alter table "better_supabase"."expense_reports" enable row level security;
revoke all on "better_supabase"."expense_reports" from anon, authenticated;
grant select on "better_supabase"."expense_reports" to authenticated;
grant all on "better_supabase"."expense_reports" to service_role;
drop policy if exists "expense_reports_read" on "better_supabase"."expense_reports";
create policy "expense_reports_read" on "better_supabase"."expense_reports" for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table if not exists "better_supabase"."expense_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "report_id" uuid not null references "better_supabase"."expense_reports" ("id") on delete cascade,
  "category_id" uuid not null,
  "spent_on" date not null,
  "description" text not null check (length("description") between 1 and 500),
  "merchant" text check ("merchant" is null or length("merchant") <= 200),
  -- Minor units of the report's currency (ADR 0037).
  "amount" bigint not null check ("amount" > 0),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("org_id", "category_id") references "better_supabase"."expense_categories" ("org_id", "id") on delete restrict
);
create index if not exists "expense_lines_report_idx" on "better_supabase"."expense_lines" ("report_id", "spent_on");
create index if not exists "expense_lines_category_idx" on "better_supabase"."expense_lines" ("org_id", "category_id");
alter table "better_supabase"."expense_lines" enable row level security;
revoke all on "better_supabase"."expense_lines" from anon, authenticated;
grant select on "better_supabase"."expense_lines" to authenticated;
grant all on "better_supabase"."expense_lines" to service_role;
drop policy if exists "expense_lines_read" on "better_supabase"."expense_lines";
create policy "expense_lines_read" on "better_supabase"."expense_lines" for select to authenticated
  using (
    exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "org_id" in (select better_supabase.tenant_ids_with('expenses.read'))
  );

-- Creates or updates the category with this key and its spend policy.
create or replace function "better_supabase"."save_expense_category"(tenant uuid, key text, name text, currency text default null, limit_amount bigint default null, receipt_over bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_expense_category.tenant, 'expenses.manage'), false)) then
    raise exception 'not allowed to manage expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if save_expense_category.key is null or save_expense_category.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if nullif(trim(save_expense_category.name), '') is null then
    raise exception 'a category needs a name' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if (save_expense_category.limit_amount is not null or save_expense_category.receipt_over is not null)
    and (save_expense_category.currency is null or save_expense_category.currency !~ '^[A-Z]{3}$') then
    raise exception 'a limit or receipt threshold needs a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.limit_amount is not null and save_expense_category.limit_amount <= 0 then
    raise exception 'a limit is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null and save_expense_category.receipt_over < 0 then
    raise exception 'a receipt threshold is zero or more minor units' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if save_expense_category.receipt_over is not null then
    raise exception 'a receipt threshold needs the attachments block' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  insert into "better_supabase"."expense_categories" ("org_id", "key", "name", "currency", "limit_amount", "receipt_over")
  values (save_expense_category.tenant, save_expense_category.key, trim(save_expense_category.name), save_expense_category.currency,
    save_expense_category.limit_amount, save_expense_category.receipt_over)
  on conflict ("org_id", "key") do update set
    "name" = excluded."name", "currency" = excluded."currency", "limit_amount" = excluded."limit_amount",
    "receipt_over" = excluded."receipt_over", "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) from public, anon;
grant execute on function "better_supabase"."save_expense_category"(uuid, text, text, text, bigint, bigint) to authenticated, service_role;

create or replace function "better_supabase"."archive_expense_category"(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_categories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_categories" c where c."id" = archive_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "better_supabase"."expense_categories" c set "archived_at" = coalesce(c."archived_at", now()), "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_expense_categories"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.read'), false)) or coalesce(better_supabase.can('tenant', list_expense_categories.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to read expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', c."id", 'organizationId', c."org_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") order by c."name", c."id"), '[]'::jsonb)
    from "better_supabase"."expense_categories" c
    where c."org_id" = list_expense_categories.tenant
      and (coalesce(list_expense_categories.include_archived, false) or c."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_categories"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_expense_categories"(uuid, boolean) to authenticated, service_role;

-- The spend policy findings of a report, empty when it may be submitted:
-- a category total over its limit, a line over its category's receipt
-- threshold without a receipt, and a line in an archived category.
create or replace function "better_supabase"."expense_report_violations"(report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.v order by q.ord, q.at), '[]'::jsonb)
  from (
    select 1 as ord, min(l."created_at") as at, jsonb_build_object('kind', 'limit', 'categoryId', c."id", 'category', c."name",
        'limit', c."limit_amount"::text, 'total', sum(l."amount")::text, 'currency', c."currency") as v
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."limit_amount" is not null
      group by c."id"
      having sum(l."amount") > c."limit_amount"
    union all
    select 2, l."created_at", jsonb_build_object('kind', 'receipt', 'lineId', l."id", 'categoryId', c."id", 'category', c."name",
        'receiptOver', c."receipt_over"::text, 'amount', l."amount"::text, 'currency', c."currency")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."receipt_over" is not null
        and l."amount" > c."receipt_over" and 0 = 0
    union all
    select 3, min(l."created_at"), jsonb_build_object('kind', 'archived', 'categoryId', c."id", 'category', c."name")
      from "better_supabase"."expense_lines" l join "better_supabase"."expense_categories" c on c."id" = l."category_id"
      where l."report_id" = expense_report_violations.report_id and c."archived_at" is not null
      group by c."id"
  ) q;
$$;
revoke execute on function "better_supabase"."expense_report_violations"(uuid) from public, anon, authenticated;

-- Opens a draft report in one currency. fields: the extra columns to set.
drop function if exists "better_supabase"."create_expense_report"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."create_expense_report"(tenant uuid, title text, currency text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', create_expense_report.tenant, 'expenses.submit'), false) then
    raise exception 'not allowed to submit expenses here' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if nullif(trim(create_expense_report.title), '') is null then
    raise exception 'a report needs a title' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if create_expense_report.currency is null or create_expense_report.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  insert into "better_supabase"."expense_reports" ("org_id", "user_id", "title", "currency", "note")
  values (create_expense_report.tenant, auth.uid(), trim(create_expense_report.title), create_expense_report.currency,
    nullif(trim(create_expense_report.note), ''))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."add_expense_line"(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = add_expense_line.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = add_expense_line.category_id and c."org_id" = v_row."org_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.spent_on is null then
    raise exception 'a line needs spent_on' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if add_expense_line.currency is not null and add_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if add_expense_line.amount is null or add_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  if nullif(trim(add_expense_line.description), '') is null then
    raise exception 'a line needs a description' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  insert into "better_supabase"."expense_lines" ("org_id", "report_id", "category_id", "spent_on", "description", "merchant", "amount")
  values (v_row."org_id", v_row."id", v_category."id", add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), add_expense_line.amount)
  returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

-- Changes a line of a draft or rejected report; null keeps a value.
create or replace function "better_supabase"."update_expense_line"(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_category "better_supabase"."expense_categories"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = update_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if update_expense_line.category_id is not null then
  select * into v_category from "better_supabase"."expense_categories" c
    where c."id" = update_expense_line.category_id and c."org_id" = v_row."org_id" and c."archived_at" is null;
  if not found then
    raise exception 'the category is unknown, archived or not in this organization' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_category."currency" is not null and v_category."currency" <> v_row."currency" then
    raise exception 'the category''s policy is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  end if;
  if update_expense_line.currency is not null and update_expense_line.currency <> v_row."currency" then
    raise exception 'the amount is in another currency than the report' using errcode = '22023', hint = 'EXPENSE_CURRENCY_MISMATCH';
  end if;
  if update_expense_line.amount is not null and update_expense_line.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  update "better_supabase"."expense_lines" l set
      "category_id" = coalesce(update_expense_line.category_id, l."category_id"),
      "spent_on" = coalesce(update_expense_line.spent_on, l."spent_on"),
      "amount" = coalesce(update_expense_line.amount, l."amount"),
      "description" = coalesce(nullif(trim(update_expense_line.description), ''), l."description"),
      "merchant" = coalesce(nullif(trim(update_expense_line.merchant), ''), l."merchant"),
      "updated_at" = now()
    where l."id" = v_line."id"
    returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."remove_expense_line"(line_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_line "better_supabase"."expense_lines"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_line from "better_supabase"."expense_lines" l where l."id" = remove_expense_line.line_id;
  if not found then
    raise exception 'no such expense line' using errcode = 'P0002', hint = 'EXPENSE_LINE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = v_line."report_id" for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  delete from "better_supabase"."expense_lines" l where l."id" = v_line."id";
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."remove_expense_line"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_expense_line"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."check_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = check_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return "better_supabase"."expense_report_violations"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."check_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."check_expense_report"(uuid) to authenticated, service_role;

-- Submits a draft or rejected report for approval. Fails with
-- EXPENSE_POLICY_VIOLATION, listing the findings, while the report breaks
-- the spend policy.
create or replace function "better_supabase"."submit_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_violations jsonb;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = submit_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if not exists (select 1 from "better_supabase"."expense_lines" l where l."report_id" = v_row."id") then
    raise exception 'a report needs at least one line' using errcode = '22023', hint = 'EXPENSE_REPORT_EMPTY';
  end if;
  v_violations := "better_supabase"."expense_report_violations"(v_row."id");
  if jsonb_array_length(v_violations) > 0 then
    raise exception 'the report breaks the spend policy: %', v_violations::text using errcode = '22023', hint = 'EXPENSE_POLICY_VIOLATION';
  end if;
  v_request := "better_supabase"."open_approval"(
    v_row."org_id", 'expense_report', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"expenses.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_row."user_id", 'title', v_row."title", 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'currency', v_row."currency")
  );
  update "better_supabase"."expense_reports" x set "approval_id" = (v_request ->> 'id')::uuid, "submitted_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."submit_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."submit_expense_report"(uuid) to authenticated, service_role;

-- Books an approved report once its approval is final: each category's
-- total on its expense account, the sum owed to the member on their payable
-- account. Approvals calls it; it isn't granted to anyone.
create or replace function "better_supabase"."approve_expense_report"(report_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."expense_reports" x
    where x."id" = approve_expense_report.report_id and x."approved_at" is null and x."cancelled_at" is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'expense', 'expenses:category:' || c."key" || ':' || v_row."currency", 'Expenses: ' || c."name", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', q.total) order by c."key")
    into v_lines
  from (
    select l."category_id" as category, sum(l."amount") as total
    from "better_supabase"."expense_lines" l where l."report_id" = v_row."id" group by l."category_id"
  ) q join "better_supabase"."expense_categories" c on c."id" = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)));
  v_tx := "better_supabase"."ledger_post"(v_row."org_id", 'expense.approved', v_lines,
    'expenses', v_row."id"::text, left('Expenses: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':approved', null,
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"));
  update "better_supabase"."expense_reports" x set "approved_at" = now(), "approval_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
end;
$$;
revoke execute on function "better_supabase"."approve_expense_report"(uuid) from public, anon, authenticated;

-- Pays an approved report back: the member's payable account is settled
-- from expense cash.
create or replace function "better_supabase"."reimburse_expense_report"(report_id uuid, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = reimburse_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.manage'), false)) then
    raise exception 'not allowed to reimburse expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) <> 'approved' then
    raise exception 'only an approved report can be reimbursed' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."org_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."reimburse_expense_report"(uuid, timestamptz, text) to authenticated, service_role;

-- Withdraws a report that isn't approved yet: its owner or a manager. A
-- pending approval is cancelled with it.
create or replace function "better_supabase"."cancel_expense_report"(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = cancel_expense_report.report_id for update;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.manage'), false))) then
    raise exception 'not allowed to cancel this expense report' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'submitted', 'rejected') then
    raise exception 'an approved, reimbursed or cancelled report can''t be cancelled' using errcode = '55000', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  update "better_supabase"."expense_reports" x set "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."cancel_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_expense_report"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_expense_report"(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."expense_reports"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."expense_reports" x where x."id" = get_expense_report.report_id;
  if not found then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  if not (v_row."user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_expense_report"(uuid) from public, anon;
grant execute on function "better_supabase"."get_expense_report"(uuid) to authenticated, service_role;

-- Reports, newest first: the caller's, or everyone's (or one member's) with
-- expenses.read.
create or replace function "better_supabase"."list_expense_reports"(tenant uuid, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.read'), false));
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_expense_reports.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to list expense reports' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if not v_reader and (coalesce(list_expense_reports.everyone, false) or (list_expense_reports.user_id is not null and list_expense_reports.user_id <> auth.uid())) then
    raise exception 'not allowed to read another member''s expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'userId', q."user_id", 'title', q."title", 'currency', q."currency", 'note', q."note", 'status', (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = q."id"), 0)::text, 'approvalId', q."approval_id", 'submittedAt', q."submitted_at", 'approvedAt', q."approved_at", 'approvalTransactionId', q."approval_transaction_id", 'reimbursedAt', q."reimbursed_at", 'reimbursementTransactionId', q."reimbursement_transaction_id", 'cancelledAt', q."cancelled_at", 'createdAt', q."created_at", 'updatedAt', q."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = q."id")) as item, q."created_at" as created, q."id" as id
      from "better_supabase"."expense_reports" q
      left join "better_supabase"."approval_requests" p on p."id" = q."approval_id"
      where q."org_id" = list_expense_reports.tenant
        and (case
          when coalesce(list_expense_reports.everyone, false) then true
          when list_expense_reports.user_id is not null then q."user_id" = list_expense_reports.user_id
          else q."user_id" = auth.uid()
        end)
        and (list_expense_reports.status is null or (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) = list_expense_reports.status)
      order by q."created_at" desc, q."id"
      limit least(greatest(coalesce(list_expense_reports.page_size, 100), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_expense_reports"(uuid, uuid, text, boolean, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_categories";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_select on "better_supabase"."expense_categories" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_categories" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_update on "better_supabase"."expense_categories" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_categories";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_categories" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_reports";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_select on "better_supabase"."expense_reports" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_reports" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_update on "better_supabase"."expense_reports" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_reports";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_reports" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."expense_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_select on "better_supabase"."expense_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "org_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."expense_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_update on "better_supabase"."expense_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."expense_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."expense_lines" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block-data expenses
-- @bsb-hash sha256:acad5782117da37aa32eb5b47f0372cb87a9105ea9687dd5f8de16d1ca73932f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('expenses', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
