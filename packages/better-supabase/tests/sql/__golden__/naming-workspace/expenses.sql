-- ==== schema supabase/schemas/900_better_supabase_121_expenses.sql
-- better-supabase module: expenses
-- @bsb-block expenses@1 managed
-- @bsb-hash sha256:2a430490c322ce7b8aeea39279f5396ea464c806da3bbaea2b207c8b8c5bb032
-- Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units. Without reports, each expense is one row a member or an employee submits and the app decides.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Expenses: reports of lines in categories, spend policies checked on
-- submit, approval through the approvals block, and the approved total and
-- its reimbursement posted on the ledger.

-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
create table "better_supabase"."expense_categories" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null constraint bsb_expense_categories_key_check check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null constraint bsb_expense_categories_name_check check (length("name") >= 1 and length("name") <= 200),
  "currency" char(3) constraint bsb_expense_categories_currency_check check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "limit_amount" bigint constraint bsb_expense_categories_limit_amount_check check ("limit_amount" is null or "limit_amount" > 0),
  "receipt_over" bigint constraint bsb_expense_categories_receipt_over_check check ("receipt_over" is null or "receipt_over" >= 0),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  constraint bsb_expense_categories_check check (("limit_amount" is null and "receipt_over" is null) or "currency" is not null)
);
alter table "better_supabase"."expense_categories" enable row level security;
revoke all on "better_supabase"."expense_categories" from public, anon, authenticated;
grant select on "better_supabase"."expense_categories" to authenticated;
grant all on "better_supabase"."expense_categories" to service_role;
create policy bsb_expense_categories_read on "better_supabase"."expense_categories"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table "better_supabase"."expense_reports" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "title" text not null constraint bsb_expense_reports_title_check check (length("title") >= 1 and length("title") <= 200),
  "currency" char(3) not null constraint bsb_expense_reports_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "note" text constraint bsb_expense_reports_note_check check ("note" is null or length("note") <= 2000),
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
create index "expense_reports_tenant_idx" on "better_supabase"."expense_reports" ("tenant_id", "created_at" desc, "id" desc);
create index "expense_reports_user_idx" on "better_supabase"."expense_reports" ("user_id", "tenant_id");
create index "expense_reports_approval_idx" on "better_supabase"."expense_reports" ("approval_id") where "approval_id" is not null;
create index "expense_reports_approval_tx_idx" on "better_supabase"."expense_reports" ("approval_transaction_id") where "approval_transaction_id" is not null;
create index "expense_reports_reimbursement_idx" on "better_supabase"."expense_reports" ("reimbursement_transaction_id") where "reimbursement_transaction_id" is not null;
alter table "better_supabase"."expense_reports" enable row level security;
revoke all on "better_supabase"."expense_reports" from public, anon, authenticated;
grant select on "better_supabase"."expense_reports" to authenticated;
grant all on "better_supabase"."expense_reports" to service_role;
create policy bsb_expense_reports_read on "better_supabase"."expense_reports"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

create table "better_supabase"."expense_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "report_id" uuid not null references "better_supabase"."expense_reports" ("id") on delete cascade,
  "category_id" uuid not null,
  "spent_on" date not null,
  "description" text not null constraint bsb_expense_lines_description_check check (length("description") >= 1 and length("description") <= 500),
  "merchant" text constraint bsb_expense_lines_merchant_check check ("merchant" is null or length("merchant") <= 200),
  -- Minor units of the report's currency (ADR 0037).
  "amount" bigint not null constraint bsb_expense_lines_amount_check check ("amount" > 0),
  "dimensions" jsonb not null default '{}'::jsonb constraint bsb_expense_lines_dimensions_check check (jsonb_typeof("dimensions") = 'object'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "category_id") references "better_supabase"."expense_categories" ("tenant_id", "id") on delete restrict
);
create index "expense_lines_report_idx" on "better_supabase"."expense_lines" ("report_id", "spent_on");
create index "expense_lines_category_idx" on "better_supabase"."expense_lines" ("tenant_id", "category_id");
alter table "better_supabase"."expense_lines" enable row level security;
revoke all on "better_supabase"."expense_lines" from public, anon, authenticated;
grant select on "better_supabase"."expense_lines" to authenticated;
grant all on "better_supabase"."expense_lines" to service_role;
create policy bsb_expense_lines_read on "better_supabase"."expense_lines"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')));

-- Creates or updates the category with this key and its spend policy. fields:
-- the extra columns (columns your schema files add) to set.

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
  insert into "better_supabase"."expense_categories" as x ("tenant_id", "key", "name", "currency", "limit_amount", "receipt_over")
  values (save_expense_category.tenant, save_expense_category.key, trim(save_expense_category.name), save_expense_category.currency, save_expense_category.limit_amount, save_expense_category.receipt_over)
  on conflict ("tenant_id", "key") do update set
    "name" = trim(save_expense_category.name), "currency" = save_expense_category.currency, "limit_amount" = save_expense_category.limit_amount, "receipt_over" = save_expense_category.receipt_over, "archived_at" = null, "updated_at" = now()
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
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_expense_category"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."restore_expense_category"(category_id uuid)
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
  select * into v_row from "better_supabase"."expense_categories" c where c."id" = restore_expense_category.category_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false)) then
    raise exception 'no such expense category you can manage' using errcode = 'P0002', hint = 'EXPENSE_CATEGORY_NOT_FOUND';
  end if;
  update "better_supabase"."expense_categories" c set "archived_at" = null, "updated_at" = now()
    where c."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'currency', v_row."currency", 'limitAmount', v_row."limit_amount"::text, 'receiptOver', v_row."receipt_over"::text, 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."restore_expense_category"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_expense_category"(uuid) to authenticated, service_role;

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

-- The organization's expense categories as a keyset page, by name (ADR 1077).
-- filters is { currency (a value or a list), archived (["true"] lists the
-- archived ones), search (name), sort (name, createdAt), direction, facet,
-- count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_expense_categories"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_expense_categories.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_expense_categories.tenant, 'expenses.read'), false)) or coalesce(better_supabase.can('tenant', page_expense_categories.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to read expense categories' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('currency') then
      raise exception 'facet is one of currency' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'currency' then (coalesce(c."currency", ''))::text end) as v
      from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
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
      select 1 from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((lower(c."name"))::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (lower(c."name"), c."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(c."name") asc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((lower(c."name"))::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (lower(c."name") <= (v_after ->> 0)::text and ((lower(c."name") < (v_after ->> 0)::text) or (lower(c."name") = (v_after ->> 0)::text and c."id" > (v_after ->> 1)::uuid))))
      order by lower(c."name") desc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((lower(c."name"))::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (lower(c."name"), c."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(c."name") asc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((lower(c."name"))::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (lower(c."name") <= (v_after ->> 0)::text and ((lower(c."name") < (v_after ->> 0)::text) or (lower(c."name") = (v_after ->> 0)::text and c."id" > (v_after ->> 1)::uuid))))
      order by lower(c."name") desc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((c."created_at")::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (c."created_at", c."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by c."created_at" asc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_CATEGORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'key', c."key", 'name', c."name", 'currency', c."currency", 'limitAmount', c."limit_amount"::text, 'receiptOver', c."receipt_over"::text, 'archivedAt', c."archived_at", 'createdAt', c."created_at", 'updatedAt', c."updated_at") as j, jsonb_build_array((c."created_at")::text, (c."id")::text) as k
    from (
      select * from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
        and (v_after is null or (c."created_at" <= (v_after ->> 0)::timestamptz and ((c."created_at" < (v_after ->> 0)::timestamptz) or (c."created_at" = (v_after ->> 0)::timestamptz and c."id" > (v_after ->> 1)::uuid))))
      order by c."created_at" desc, c."id" asc
      limit v_limit + 1 offset v_offset
    ) c
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."expense_categories" c
      where c."tenant_id" = page_expense_categories.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (c."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else c."archived_at" is null end)
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (c."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or c."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_expense_categories"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_expense_categories"(uuid, jsonb) to authenticated, service_role;

-- Whether a report is open to its owner (a draft or rejected one), locked
-- (approved, reimbursed or cancelled) or submitted. The guards below run as
-- the writer, who may not read the report or its approval request.
create or replace function "better_supabase"."expense_report_state"(report_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when (case when p."cancelled_at" is not null then 'cancelled' when p."reimbursed_at" is not null then 'reimbursed' when p."approved_at" is not null then 'approved' when p."submitted_at" is not null then 'submitted' else 'draft' end) in ('approved', 'reimbursed', 'cancelled') then 'locked' when ((case when p."cancelled_at" is not null then 'cancelled' when p."reimbursed_at" is not null then 'reimbursed' when p."approved_at" is not null then 'approved' when p."submitted_at" is not null then 'submitted' else 'draft' end) = 'draft' or ((case when p."cancelled_at" is not null then 'cancelled' when p."reimbursed_at" is not null then 'reimbursed' when p."approved_at" is not null then 'approved' when p."submitted_at" is not null then 'submitted' else 'draft' end) = 'submitted' and exists (select 1 from "better_supabase"."approval_requests" ap where ap."id" = p."approval_id" and ap."status" in ('rejected', 'expired')))) then 'open' else 'submitted' end
  from "better_supabase"."expense_reports" p where p."id" = expense_report_state.report_id
$$;
revoke execute on function "better_supabase"."expense_report_state"(uuid) from public, anon;
grant execute on function "better_supabase"."expense_report_state"(uuid) to authenticated, service_role;

-- Guards every write to an expense report (ADR 1090): clients never write its
-- stamp columns or its owner, a status moves only along the allowed
-- transitions, the trigger stamps the decider and clears a decision on a
-- resubmission, and the owner and currency are frozen once approved, and for a
-- client once submitted.
create or replace function "better_supabase"."expense_report_guard"()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_client boolean := current_user::text in ('authenticated', 'anon') and pg_trigger_depth() = 1;
  v_from text;
  v_to text := (case when new."cancelled_at" is not null then 'cancelled' when new."reimbursed_at" is not null then 'reimbursed' when new."approved_at" is not null then 'approved' when new."submitted_at" is not null then 'submitted' else 'draft' end);
begin
  if tg_op = 'INSERT' then
    if v_client and (coalesce(new."submitted_at"::text, new."approved_at"::text, new."approval_transaction_id"::text, new."reimbursed_at"::text, new."reimbursement_transaction_id"::text, new."cancelled_at"::text, new."approval_id"::text) is not null or new."user_id" is distinct from auth.uid()) then
      raise exception 'a new expense report is a draft of the caller; the expense functions submit and decide it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
    end if;
    return new;
  end if;
  v_from := (case when old."cancelled_at" is not null then 'cancelled' when old."reimbursed_at" is not null then 'reimbursed' when old."approved_at" is not null then 'approved' when old."submitted_at" is not null then 'submitted' else 'draft' end);
  if v_client and ((new."submitted_at", new."approved_at", new."approval_transaction_id", new."reimbursed_at", new."reimbursement_transaction_id", new."cancelled_at", new."approval_id") is distinct from (old."submitted_at", old."approved_at", old."approval_transaction_id", old."reimbursed_at", old."reimbursement_transaction_id", old."cancelled_at", old."approval_id") or new."user_id" is distinct from old."user_id") then
    raise exception 'an expense report''s owner, status and decision change only through the expense functions' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if pg_trigger_depth() = 1 and v_from in ('approved', 'reimbursed', 'cancelled') and (new."user_id", new."currency") is distinct from (old."user_id", old."currency") then
    raise exception 'an approved, reimbursed or cancelled report keeps its owner and currency' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if v_client and "better_supabase"."expense_report_state"(old."id") <> 'open' and (new."user_id", new."currency") is distinct from (old."user_id", old."currency") then
    raise exception 'a submitted report keeps its owner and currency' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  if v_from is not distinct from v_to then
    return new;
  end if;
  if (v_from, v_to) not in (('draft', 'submitted'), ('rejected', 'submitted'), ('submitted', 'approved'), ('submitted', 'rejected'), ('draft', 'cancelled'), ('submitted', 'cancelled'), ('rejected', 'cancelled'), ('approved', 'reimbursed')) then
    raise exception 'this status change is not allowed for an expense report' using errcode = 'PT409', hint = 'EXPENSE_TRANSITION_INVALID';
  end if;
  if v_to = 'submitted' then
    null;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."expense_report_guard"() from public, anon, authenticated;
create trigger bsb_expense_report_guard
  before insert or update on "better_supabase"."expense_reports"
  for each row execute function "better_supabase"."expense_report_guard"();

-- Keeps the lines of a report as they were once it is approved, and a client's
-- own writes to a submitted report's lines out.
create or replace function "better_supabase"."expense_line_guard"()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_client boolean := current_user::text in ('authenticated', 'anon');
  v_state text;
begin
  if pg_trigger_depth() > 1 then
    return coalesce(new, old);
  end if;
  foreach v_state in array array[
    case when tg_op <> 'INSERT' then "better_supabase"."expense_report_state"(old."report_id") end,
    case when tg_op <> 'DELETE' then "better_supabase"."expense_report_state"(new."report_id") end
  ] loop
    if v_state = 'locked' then
      raise exception 'an approved, reimbursed or cancelled report keeps its lines' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
    end if;
    if v_client and v_state is distinct from 'open' and v_state is not null then
      raise exception 'only a draft or rejected report''s lines change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
    end if;
  end loop;
  return coalesce(new, old);
end;
$$;
revoke execute on function "better_supabase"."expense_line_guard"() from public, anon, authenticated;
create trigger bsb_expense_line_guard
  before insert or update or delete on "better_supabase"."expense_lines"
  for each row execute function "better_supabase"."expense_line_guard"();

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
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_expense_report"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."add_expense_line"(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null, currency text default null, dimensions jsonb default null)
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
  if not (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
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
  if add_expense_line.dimensions is not null and jsonb_typeof(add_expense_line.dimensions) not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  insert into "better_supabase"."expense_lines" ("tenant_id", "report_id", "category_id", "spent_on", "description", "merchant", "dimensions", "amount")
  values (v_row."tenant_id", v_row."id", v_category."id", add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), coalesce(nullif(add_expense_line.dimensions, 'null'::jsonb), '{}'::jsonb), add_expense_line.amount)
  returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'dimensions', v_line."dimensions", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."add_expense_line"(uuid, uuid, date, bigint, text, text, text, jsonb) to authenticated, service_role;

-- Changes a line of a draft or rejected report; null keeps a value.
create or replace function "better_supabase"."update_expense_line"(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null, currency text default null, dimensions jsonb default null)
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
  if not (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
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
  if update_expense_line.dimensions is not null and jsonb_typeof(update_expense_line.dimensions) not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'EXPENSE_LINE_INVALID';
  end if;
  update "better_supabase"."expense_lines" l set
      "category_id" = coalesce(update_expense_line.category_id, l."category_id"),
      "spent_on" = coalesce(update_expense_line.spent_on, l."spent_on"),
      "amount" = coalesce(update_expense_line.amount, l."amount"),
      "description" = coalesce(nullif(trim(update_expense_line.description), ''), l."description"),
      "merchant" = coalesce(nullif(trim(update_expense_line.merchant), ''), l."merchant"),
      "dimensions" = coalesce(nullif(update_expense_line.dimensions, 'null'::jsonb), l."dimensions"),
      "updated_at" = now()
    where l."id" = v_line."id"
    returning * into v_line;
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_line."id", 'reportId', v_line."report_id", 'categoryId', v_line."category_id", 'spentOn', v_line."spent_on", 'description', v_line."description", 'merchant', v_line."merchant", 'dimensions', v_line."dimensions", 'amount', v_line."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = v_line."report_id"), 'receipts', 0, 'createdAt', v_line."created_at", 'updatedAt', v_line."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."update_expense_line"(uuid, uuid, date, bigint, text, text, text, jsonb) to authenticated, service_role;

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
  if not (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  delete from "better_supabase"."expense_lines" l where l."id" = v_line."id";
  update "better_supabase"."expense_reports" x set "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
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
  if not (coalesce(v_row."user_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
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
  if not (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.submit'), false)) then
    raise exception 'only the member who owns the report can change it' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'rejected') then
    raise exception 'only a draft or rejected report can change' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
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
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
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
    jsonb_build_object('reportId', v_row."id", 'userId', v_row."user_id"),
    memo_key => 'expense.approved', memo_params => jsonb_build_object('title', v_row."title"));
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
    raise exception 'only an approved report can be reimbursed' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_payable', 'expenses:payable:' || v_row."user_id"::text || ':' || v_row."currency", 'Expenses owed ' || v_row."currency", v_row."currency"::text, 0::smallint, 'users', v_row."user_id"::text, v_row."user_id", true, 'expenses.read', 'expenses', null), 'amount', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'expense_cash', 'expenses:cash:' || v_row."currency", 'Expenses paid ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'expenses.read', 'expenses', null), 'amount', -coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0))),
    'expenses', v_row."id"::text, left('Reimbursed: ' || v_row."title", 500), 'expense:' || v_row."id"::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row."id", 'reference', nullif(trim(reimburse_expense_report.reference), ''))),
    memo_key => 'expense.reimbursed', memo_params => jsonb_build_object('title', v_row."title"));
  update "better_supabase"."expense_reports" x set "reimbursed_at" = coalesce(reimburse_expense_report.paid_at, now()), "reimbursement_transaction_id" = v_tx, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
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
  if not (coalesce(v_row."user_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.manage'), false))) then
    raise exception 'not allowed to cancel this expense report' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) not in ('draft', 'submitted', 'rejected') then
    raise exception 'an approved, reimbursed or cancelled report can''t be cancelled' using errcode = 'PT409', hint = 'EXPENSE_REPORT_LOCKED';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  update "better_supabase"."expense_reports" x set "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" p where p."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
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
  if not (coalesce(v_row."user_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false))) then
    raise exception 'no such expense report' using errcode = 'P0002', hint = 'EXPENSE_REPORT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'title', v_row."title", 'currency', v_row."currency", 'note', v_row."note", 'status', (case when v_row."cancelled_at" is not null then 'cancelled' when v_row."reimbursed_at" is not null then 'reimbursed' when v_row."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = v_row."id"), 0)::text, 'approvalId', v_row."approval_id", 'submittedAt', v_row."submitted_at", 'approvedAt', v_row."approved_at", 'approvalTransactionId', v_row."approval_transaction_id", 'reimbursedAt', v_row."reimbursed_at", 'reimbursementTransactionId', v_row."reimbursement_transaction_id", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = v_row."id"));
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
  if not v_reader and (coalesce(list_expense_reports.everyone, false) or (list_expense_reports.user_id is not null and list_expense_reports.user_id is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s expenses' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'title', q."title", 'currency', q."currency", 'note', q."note", 'status', (case when q."cancelled_at" is not null then 'cancelled' when q."reimbursed_at" is not null then 'reimbursed' when q."approved_at" is not null then 'approved' when p."status" = 'pending' then 'submitted' when p."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = q."id"), 0)::text, 'approvalId', q."approval_id", 'submittedAt', q."submitted_at", 'approvedAt', q."approved_at", 'approvalTransactionId', q."approval_transaction_id", 'reimbursedAt', q."reimbursed_at", 'reimbursementTransactionId', q."reimbursement_transaction_id", 'cancelledAt', q."cancelled_at", 'createdAt', q."created_at", 'updatedAt', q."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = q."id")) as item, q."created_at" as created, q."id" as id
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

-- Reports as a keyset page, newest first: the caller's, or everyone's with
-- expenses.read unless filters.mine is true (ADR 1077). filters is { userId,
-- status, currency (each a value or a list), mine (["true"]), search (title),
-- sort (createdAt, title), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function "better_supabase"."page_expense_reports"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_expense_reports.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_reader boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_expense_reports.tenant, 'expenses.read'), false));
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
  if not (v_reader or coalesce(better_supabase.can('tenant', page_expense_reports.tenant, 'expenses.submit'), false)) then
    raise exception 'not allowed to list expense reports' using errcode = '42501', hint = 'EXPENSES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'currency') then
      raise exception 'facet is one of status, currency' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text when 'currency' then (x."currency")::text end) as v
      from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
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
      select 1 from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'title') then
    raise exception 'sort is one of createdAt, title' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EXPENSE_REPORT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'title', x."title", 'currency', x."currency", 'note', x."note", 'status', (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end), 'total', coalesce((select sum(y."amount") from "better_supabase"."expense_lines" y where y."report_id" = x."id"), 0)::text, 'approvalId', x."approval_id", 'submittedAt', x."submitted_at", 'approvedAt', x."approved_at", 'approvalTransactionId', x."approval_transaction_id", 'reimbursedAt', x."reimbursed_at", 'reimbursementTransactionId', x."reimbursement_transaction_id", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l."id", 'reportId', l."report_id", 'categoryId', l."category_id", 'spentOn', l."spent_on", 'description', l."description", 'merchant', l."merchant", 'dimensions', l."dimensions", 'amount', l."amount"::text, 'currency', (select rc."currency" from "better_supabase"."expense_reports" rc where rc."id" = l."report_id"), 'receipts', 0, 'createdAt', l."created_at", 'updatedAt', l."updated_at") order by l."spent_on", l."created_at"), '[]'::jsonb) from "better_supabase"."expense_lines" l where l."report_id" = x."id")) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."expense_reports" x
      where x."tenant_id" = page_expense_reports.tenant
        and ((v_reader and not coalesce(nullif(coalesce(v_filters #>> '{mine,0}', v_filters ->> 'mine'), '') = 'true', false)) or x."user_id" = auth.uid())
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id"::text = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or ((select (case when x."cancelled_at" is not null then 'cancelled' when x."reimbursed_at" is not null then 'reimbursed' when x."approved_at" is not null then 'approved' when ap."status" = 'pending' then 'submitted' when ap."status" in ('rejected', 'expired') then 'rejected' else 'draft' end) from (values (1)) d(n) left join "better_supabase"."approval_requests" ap on ap."id" = x."approval_id"))::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'currency' is not null and jsonb_typeof(v_filters -> 'currency') <> 'null' and not (jsonb_typeof(v_filters -> 'currency') = 'array' and jsonb_array_length(v_filters -> 'currency') = 0)) or (x."currency")::text = any((case when jsonb_typeof(v_filters -> 'currency') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'currency')) else array[v_filters ->> 'currency'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_expense_reports"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_expense_reports"(uuid, jsonb) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."expense_categories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."expense_categories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."expense_categories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."expense_categories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."expense_reports" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."expense_reports" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."expense_reports" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."expense_reports" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."expense_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or (exists (select 1 from "better_supabase"."expense_reports" p where p."id" = "report_id" and p."user_id" = (select auth.uid()))
    or "tenant_id" in (select better_supabase.tenant_ids_with('expenses.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."expense_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."expense_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."expense_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_121_expenses.sql
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
