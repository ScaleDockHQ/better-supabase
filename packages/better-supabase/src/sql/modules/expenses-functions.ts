import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, pageSize, raise, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations, OPERATIONS } from "./access-model.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { EXPENSE_REPORT_SUBJECT } from "./approvals.ts";

/** One approver step: anyone with the approve permission. */
function expensePolicy(ctx: ModuleContext): string {
  const policy = policyOf(
    EXPENSE_REPORT_SUBJECT,
    "approve",
    {
      steps: [
        {
          approvers: {
            permission: ctx.permissionKey(
              "approve",
              OPERATIONS["expenses.approve"],
            ),
          },
        },
      ],
    },
    "blocks.expenses",
  );

  return policySnapshot(policy);
}

/** The expenses module's functions. */
export function expensesFunctions(ctx: ModuleContext): string {
  const approvals = ctx.of("approvals");
  const ledger = ctx.of("ledger");
  const categories = ctx.table("categories");
  const reports = ctx.table("reports");
  const lines = ctx.table("lines");
  const k = (column: string): string => ctx.col("categories", column);
  const r = (column: string): string => ctx.col("reports", column);
  const x = (column: string): string => ctx.col("lines", column);
  const ar = approvals.table("requests");
  const a = (column: string): string => approvals.col("requests", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const ops = moduleOperations("expenses");
  const read = ctx.permission("read", ops.read);
  const submit = ctx.permission("submit", ops.submit);
  const manage = ctx.permission("manage", ops.manage);
  const policy = expensePolicy(ctx);

  const attachments =
    ctx.installed("attachments") && ctx.of("attachments").mode !== "custom"
      ? ctx.of("attachments")
      : undefined;

  const lineType =
    ctx.resolved.entities["expense_line"]?.to.singular ?? "expense_line";

  const can = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("EXPENSES_FORBIDDEN", message);

  const invalid = (code: string, message: string): string =>
    fail(code, message, "22023");

  const status = (row: string, approval: string): string =>
    `case when ${row}.${r("cancelledAt")} is not null then 'cancelled' when ${row}.${r("reimbursedAt")} is not null then 'reimbursed' when ${row}.${r("approvedAt")} is not null then 'approved' when ${approval}.${a("status")} = 'pending' then 'submitted' when ${approval}.${a("status")} in ('rejected', 'expired') then 'rejected' else 'draft' end`;

  const total = (row: string): string =>
    `coalesce((select sum(y.${x("amount")}) from ${lines} y where y.${x("report")} = ${row}.${r("id")}), 0)`;

  const categoryJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${k("id")}, 'organizationId', ${row}.${k("tenant")}, 'key', ${row}.${k("key")}, 'name', ${row}.${k("name")}, 'currency', ${row}.${k("currency")}, 'limitAmount', ${row}.${k("limitAmount")}::text, 'receiptOver', ${row}.${k("receiptOver")}::text, 'archivedAt', ${row}.${k("archivedAt")}, 'createdAt', ${row}.${k("createdAt")}, 'updatedAt', ${row}.${k("updatedAt")})`;

  const receipts = (line: string): string =>
    attachments === undefined
      ? "0"
      : `(select count(*) from ${attachments.table("attachments")} t where t.${attachments.col("attachments", "subjectType")} = ${sqlString(lineType)} and t.${attachments.col("attachments", "subjectId")} = ${line}.${x("id")}::text and t.${attachments.col("attachments", "uploadedAt")} is not null and t.${attachments.col("attachments", "status")} <> 'infected')`;

  const lineJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${x("id")}, 'reportId', ${row}.${x("report")}, 'categoryId', ${row}.${x("category")}, 'spentOn', ${row}.${x("spentOn")}, 'description', ${row}.${x("description")}, 'merchant', ${row}.${x("merchant")}, 'amount', ${row}.${x("amount")}::text, 'currency', (select rc.${r("currency")} from ${reports} rc where rc.${r("id")} = ${row}.${x("report")}), 'receipts', ${receipts(row)}, 'createdAt', ${row}.${x("createdAt")}, 'updatedAt', ${row}.${x("updatedAt")})`;

  const reportJson = (row: string, approval: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'userId', ${row}.${r("user")}, 'title', ${row}.${r("title")}, 'currency', ${row}.${r("currency")}, 'note', ${row}.${r("note")}, 'status', ${status(row, approval)}, 'total', ${total(row)}::text, 'approvalId', ${row}.${r("approval")}, 'submittedAt', ${row}.${r("submittedAt")}, 'approvedAt', ${row}.${r("approvedAt")}, 'approvalTransactionId', ${row}.${r("approvalTransaction")}, 'reimbursedAt', ${row}.${r("reimbursedAt")}, 'reimbursementTransactionId', ${row}.${r("reimbursement")}, 'cancelledAt', ${row}.${r("cancelledAt")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${row}.${r("updatedAt")},
      'lines', (select coalesce(jsonb_agg(${lineJson("l")} order by l.${x("spentOn")}, l.${x("createdAt")}), '[]'::jsonb) from ${lines} l where l.${x("report")} = ${row}.${r("id")}))`;

  const reportRecord = (
    type: string,
    summary: string,
    extra = "",
    category: "billing" | "data" = "data",
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${r("tenant")}, 'id', v_row.${r("id")}, 'userId', v_row.${r("user")}, 'status', ${status("v_row", "v_approval")}, 'total', ${total("v_row")}::text, 'currency', v_row.${r("currency")}${extra})`,
      subject: `'expense-reports/' || v_row.${r("id")}::text`,
      tenant: `v_row.${r("tenant")}`,
      audit: {
        category,
        targetType: "expense_report",
        recordId: `v_row.${r("id")}::text`,
        targetLabel: `v_row.${r("title")}`,
        summary: `'${summary}'`,
      },
    });

  const account = (
    tenant: string,
    kind: string,
    code: string,
    name: string,
    currency: string,
    holder: string,
    owner: string,
  ): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, ${kind}, ${code}, ${name}, ${currency}::text, 0::smallint, ${holder}, ${owner}, true, ${read}, 'expenses', null)`;

  const payableAccount = (row: string): string =>
    account(
      `${row}.${r("tenant")}`,
      "'expense_payable'",
      `'expenses:payable:' || ${row}.${r("user")}::text || ':' || ${row}.${r("currency")}`,
      `'Expenses owed ' || ${row}.${r("currency")}`,
      `${row}.${r("currency")}`,
      `'users', ${row}.${r("user")}::text`,
      `${row}.${r("user")}`,
    );

  const cashAccount = (row: string): string =>
    account(
      `${row}.${r("tenant")}`,
      "'expense_cash'",
      `'expenses:cash:' || ${row}.${r("currency")}`,
      `'Expenses paid ' || ${row}.${r("currency")}`,
      `${row}.${r("currency")}`,
      "null, null",
      "null",
    );

  const categoryAccount = (row: string, category: string): string =>
    account(
      `${row}.${r("tenant")}`,
      "'expense'",
      `'expenses:category:' || ${category}.${k("key")} || ':' || ${row}.${r("currency")}`,
      `'Expenses: ' || ${category}.${k("name")}`,
      `${row}.${r("currency")}`,
      "null, null",
      "null",
    );

  const loadReport = (id: string, lock = false): string => `
  select * into v_row from ${reports} x where x.${r("id")} = ${id}${lock ? " for update" : ""};
  if not found then
    ${fail("EXPENSE_REPORT_NOT_FOUND", "no such expense report", "P0002")}
  end if;
  select * into v_approval from ${ar} p where p.${a("id")} = v_row.${r("approval")};`;

  const ownerOnly = `
  if not (v_row.${r("user")} = auth.uid() and ${ctx.can("tenant", `v_row.${r("tenant")}`, submit)}) then
    ${forbidden("only the member who owns the report can change it")}
  end if;`;

  const editable = `
  if ${status("v_row", "v_approval")} not in ('draft', 'rejected') then
    ${fail("EXPENSE_REPORT_LOCKED", "only a draft or rejected report can change", "55000")}
  end if;`;

  const reader = `
  if not (v_row.${r("user")} = auth.uid() or ${can(`v_row.${r("tenant")}`, read)}) then
    ${fail("EXPENSE_REPORT_NOT_FOUND", "no such expense report", "P0002")}
  end if;`;

  const categoryCheck = (category: string, tenant: string): string => `
  select * into v_category from ${categories} c
    where c.${k("id")} = ${category} and c.${k("tenant")} = ${tenant} and c.${k("archivedAt")} is null;
  if not found then
    ${invalid("EXPENSE_CATEGORY_INVALID", "the category is unknown, archived or not in this organization")}
  end if;
  if v_category.${k("currency")} is not null and v_category.${k("currency")} <> v_row.${r("currency")} then
    ${invalid("EXPENSE_CURRENCY_MISMATCH", "the category's policy is in another currency than the report")}
  end if;`;

  return `
-- Creates or updates the category with this key and its spend policy.
create or replace function ${fn("save_expense_category")}(tenant ${idType}, key text, name text, currency text default null, limit_amount bigint default null, receipt_over bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${categories}%rowtype;
begin
  if not ${can("save_expense_category.tenant", manage)} then
    ${forbidden("not allowed to manage expense categories")}
  end if;
  if save_expense_category.key is null or save_expense_category.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${invalid("EXPENSE_CATEGORY_INVALID", "a key is lowercase letters, digits and underscores")}
  end if;
  if nullif(trim(save_expense_category.name), '') is null then
    ${invalid("EXPENSE_CATEGORY_INVALID", "a category needs a name")}
  end if;
  if (save_expense_category.limit_amount is not null or save_expense_category.receipt_over is not null)
    and (save_expense_category.currency is null or save_expense_category.currency !~ '^[A-Z]{3}$') then
    ${invalid("EXPENSE_CATEGORY_INVALID", "a limit or receipt threshold needs a three-letter currency code")}
  end if;
  if save_expense_category.limit_amount is not null and save_expense_category.limit_amount <= 0 then
    ${invalid("EXPENSE_CATEGORY_INVALID", "a limit is more than zero minor units")}
  end if;
  if save_expense_category.receipt_over is not null and save_expense_category.receipt_over < 0 then
    ${invalid("EXPENSE_CATEGORY_INVALID", "a receipt threshold is zero or more minor units")}
  end if;${
    attachments === undefined
      ? `
  if save_expense_category.receipt_over is not null then
    ${invalid("EXPENSE_CATEGORY_INVALID", "a receipt threshold needs the attachments block")}
  end if;`
      : ""
  }
  insert into ${categories} (${k("tenant")}, ${k("key")}, ${k("name")}, ${k("currency")}, ${k("limitAmount")}, ${k("receiptOver")})
  values (save_expense_category.tenant, save_expense_category.key, trim(save_expense_category.name), save_expense_category.currency,
    save_expense_category.limit_amount, save_expense_category.receipt_over)
  on conflict (${k("tenant")}, ${k("key")}) do update set
    ${k("name")} = excluded.${k("name")}, ${k("currency")} = excluded.${k("currency")}, ${k("limitAmount")} = excluded.${k("limitAmount")},
    ${k("receiptOver")} = excluded.${k("receiptOver")}, ${k("archivedAt")} = null, ${k("updatedAt")} = now()
  returning * into v_row;
  return ${categoryJson("v_row")};
end;
$$;
${userGrant(`${fn("save_expense_category")}(${idType}, text, text, text, bigint, bigint)`)}

create or replace function ${fn("archive_expense_category")}(category_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${categories}%rowtype;
begin
  select * into v_row from ${categories} c where c.${k("id")} = archive_expense_category.category_id for update;
  if not found or not ${can(`v_row.${k("tenant")}`, manage)} then
    ${fail("EXPENSE_CATEGORY_NOT_FOUND", "no such expense category you can manage", "P0002")}
  end if;
  update ${categories} c set ${k("archivedAt")} = coalesce(c.${k("archivedAt")}, now()), ${k("updatedAt")} = now()
    where c.${k("id")} = v_row.${k("id")}
    returning * into v_row;
  return ${categoryJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_expense_category")}(uuid)`)}

create or replace function ${fn("list_expense_categories")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${can("list_expense_categories.tenant", read)} or ${ctx.can("tenant", "list_expense_categories.tenant", submit)}) then
    ${forbidden("not allowed to read expense categories")}
  end if;
  return (
    select coalesce(jsonb_agg(${categoryJson("c")} order by c.${k("name")}, c.${k("id")}), '[]'::jsonb)
    from ${categories} c
    where c.${k("tenant")} = list_expense_categories.tenant
      and (coalesce(list_expense_categories.include_archived, false) or c.${k("archivedAt")} is null)
  );
end;
$$;
${userGrant(`${fn("list_expense_categories")}(${idType}, boolean)`)}

-- The spend policy findings of a report, empty when it may be submitted:
-- a category total over its limit, a line over its category's receipt
-- threshold without a receipt, and a line in an archived category.
create or replace function ${fn("expense_report_violations")}(report_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(q.v order by q.ord, q.at), '[]'::jsonb)
  from (
    select 1 as ord, min(l.${x("createdAt")}) as at, jsonb_build_object('kind', 'limit', 'categoryId', c.${k("id")}, 'category', c.${k("name")},
        'limit', c.${k("limitAmount")}::text, 'total', sum(l.${x("amount")})::text, 'currency', c.${k("currency")}) as v
      from ${lines} l join ${categories} c on c.${k("id")} = l.${x("category")}
      where l.${x("report")} = expense_report_violations.report_id and c.${k("limitAmount")} is not null
      group by c.${k("id")}
      having sum(l.${x("amount")}) > c.${k("limitAmount")}
    union all
    select 2, l.${x("createdAt")}, jsonb_build_object('kind', 'receipt', 'lineId', l.${x("id")}, 'categoryId', c.${k("id")}, 'category', c.${k("name")},
        'receiptOver', c.${k("receiptOver")}::text, 'amount', l.${x("amount")}::text, 'currency', c.${k("currency")})
      from ${lines} l join ${categories} c on c.${k("id")} = l.${x("category")}
      where l.${x("report")} = expense_report_violations.report_id and c.${k("receiptOver")} is not null
        and l.${x("amount")} > c.${k("receiptOver")} and ${receipts("l")} = 0
    union all
    select 3, min(l.${x("createdAt")}), jsonb_build_object('kind', 'archived', 'categoryId', c.${k("id")}, 'category', c.${k("name")})
      from ${lines} l join ${categories} c on c.${k("id")} = l.${x("category")}
      where l.${x("report")} = expense_report_violations.report_id and c.${k("archivedAt")} is not null
      group by c.${k("id")}
  ) q;
$$;
revoke execute on function ${fn("expense_report_violations")}(uuid) from public, anon, authenticated;

create or replace function ${fn("create_expense_report")}(tenant ${idType}, title text, currency text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
begin
  if auth.uid() is null or not ${ctx.can("tenant", "create_expense_report.tenant", submit)} then
    ${forbidden("not allowed to submit expenses here")}
  end if;
  if nullif(trim(create_expense_report.title), '') is null then
    ${invalid("EXPENSE_REPORT_INVALID", "a report needs a title")}
  end if;
  if create_expense_report.currency is null or create_expense_report.currency !~ '^[A-Z]{3}$' then
    ${invalid("EXPENSE_REPORT_INVALID", "currency must be a three-letter currency code")}
  end if;
  insert into ${reports} (${r("tenant")}, ${r("user")}, ${r("title")}, ${r("currency")}, ${r("note")})
  values (create_expense_report.tenant, auth.uid(), trim(create_expense_report.title), create_expense_report.currency,
    nullif(trim(create_expense_report.note), ''))
  returning * into v_row;
  ${reportRecord("expense_report.created", "created an expense report")}
  return ${reportJson("v_row", "v_approval")};
end;
$$;
${userGrant(`${fn("create_expense_report")}(${idType}, text, text, text)`)}

create or replace function ${fn("add_expense_line")}(report_id uuid, category_id uuid, spent_on date, amount bigint, description text, merchant text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
  v_category ${categories}%rowtype;
  v_line ${lines}%rowtype;
begin${loadReport("add_expense_line.report_id", true)}${ownerOnly}${editable}${categoryCheck("add_expense_line.category_id", `v_row.${r("tenant")}`)}
  if add_expense_line.spent_on is null then
    ${invalid("EXPENSE_LINE_INVALID", "a line needs spent_on")}
  end if;
  if add_expense_line.amount is null or add_expense_line.amount <= 0 then
    ${invalid("EXPENSE_LINE_INVALID", "an amount is more than zero minor units")}
  end if;
  if nullif(trim(add_expense_line.description), '') is null then
    ${invalid("EXPENSE_LINE_INVALID", "a line needs a description")}
  end if;
  insert into ${lines} (${x("tenant")}, ${x("report")}, ${x("category")}, ${x("spentOn")}, ${x("description")}, ${x("merchant")}, ${x("amount")})
  values (v_row.${r("tenant")}, v_row.${r("id")}, v_category.${k("id")}, add_expense_line.spent_on, trim(add_expense_line.description),
    nullif(trim(add_expense_line.merchant), ''), add_expense_line.amount)
  returning * into v_line;
  update ${reports} x set ${r("updatedAt")} = now() where x.${r("id")} = v_row.${r("id")};
  return ${lineJson("v_line")};
end;
$$;
${userGrant(`${fn("add_expense_line")}(uuid, uuid, date, bigint, text, text)`)}

-- Changes a line of a draft or rejected report; null keeps a value.
create or replace function ${fn("update_expense_line")}(line_id uuid, category_id uuid default null, spent_on date default null, amount bigint default null, description text default null, merchant text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
  v_category ${categories}%rowtype;
  v_line ${lines}%rowtype;
begin
  select * into v_line from ${lines} l where l.${x("id")} = update_expense_line.line_id;
  if not found then
    ${fail("EXPENSE_LINE_NOT_FOUND", "no such expense line", "P0002")}
  end if;${loadReport(`v_line.${x("report")}`, true)}${ownerOnly}${editable}
  if update_expense_line.category_id is not null then${categoryCheck("update_expense_line.category_id", `v_row.${r("tenant")}`)}
  end if;
  if update_expense_line.amount is not null and update_expense_line.amount <= 0 then
    ${invalid("EXPENSE_LINE_INVALID", "an amount is more than zero minor units")}
  end if;
  update ${lines} l set
      ${x("category")} = coalesce(update_expense_line.category_id, l.${x("category")}),
      ${x("spentOn")} = coalesce(update_expense_line.spent_on, l.${x("spentOn")}),
      ${x("amount")} = coalesce(update_expense_line.amount, l.${x("amount")}),
      ${x("description")} = coalesce(nullif(trim(update_expense_line.description), ''), l.${x("description")}),
      ${x("merchant")} = coalesce(nullif(trim(update_expense_line.merchant), ''), l.${x("merchant")}),
      ${x("updatedAt")} = now()
    where l.${x("id")} = v_line.${x("id")}
    returning * into v_line;
  update ${reports} x set ${r("updatedAt")} = now() where x.${r("id")} = v_row.${r("id")};
  return ${lineJson("v_line")};
end;
$$;
${userGrant(`${fn("update_expense_line")}(uuid, uuid, date, bigint, text, text)`)}

create or replace function ${fn("remove_expense_line")}(line_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
  v_line ${lines}%rowtype;
begin
  select * into v_line from ${lines} l where l.${x("id")} = remove_expense_line.line_id;
  if not found then
    ${fail("EXPENSE_LINE_NOT_FOUND", "no such expense line", "P0002")}
  end if;${loadReport(`v_line.${x("report")}`, true)}${ownerOnly}${editable}
  delete from ${lines} l where l.${x("id")} = v_line.${x("id")};
  update ${reports} x set ${r("updatedAt")} = now() where x.${r("id")} = v_row.${r("id")}
    returning * into v_row;
  return ${reportJson("v_row", "v_approval")};
end;
$$;
${userGrant(`${fn("remove_expense_line")}(uuid)`)}

create or replace function ${fn("check_expense_report")}(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
begin${loadReport("check_expense_report.report_id")}${reader}
  return ${fn("expense_report_violations")}(v_row.${r("id")});
end;
$$;
${userGrant(`${fn("check_expense_report")}(uuid)`)}

-- Submits a draft or rejected report for approval. Fails with
-- EXPENSE_POLICY_VIOLATION, listing the findings, while the report breaks
-- the spend policy.
create or replace function ${fn("submit_expense_report")}(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
  v_violations jsonb;
  v_request jsonb;
begin${loadReport("submit_expense_report.report_id", true)}${ownerOnly}${editable}
  if not exists (select 1 from ${lines} l where l.${x("report")} = v_row.${r("id")}) then
    ${invalid("EXPENSE_REPORT_EMPTY", "a report needs at least one line")}
  end if;
  v_violations := ${fn("expense_report_violations")}(v_row.${r("id")});
  if jsonb_array_length(v_violations) > 0 then
    ${raise("the report breaks the spend policy: %", "22023", "EXPENSE_POLICY_VIOLATION", "v_violations::text")}
  end if;
  v_request := ${approvals.fn("open_approval")}(
    v_row.${r("tenant")}, ${sqlString(EXPENSE_REPORT_SUBJECT)}, v_row.${r("id")}::text, 'approve',
    ${sqlString(policy)}::jsonb, v_row.${r("note")},
    jsonb_build_object('userId', v_row.${r("user")}, 'title', v_row.${r("title")}, 'total', ${total("v_row")}::text, 'currency', v_row.${r("currency")})
  );
  update ${reports} x set ${r("approval")} = (v_request ->> 'id')::uuid, ${r("submittedAt")} = now(), ${r("updatedAt")} = now()
    where x.${r("id")} = v_row.${r("id")}
    returning * into v_row;
  select * into v_approval from ${ar} p where p.${a("id")} = v_row.${r("approval")};
  ${reportRecord("expense_report.submitted", "submitted an expense report", `, 'approvalId', v_row.${r("approval")}`)}
  return ${reportJson("v_row", "v_approval")};
end;
$$;
${userGrant(`${fn("submit_expense_report")}(uuid)`)}

-- Books an approved report once its approval is final: each category's
-- total on its expense account, the sum owed to the member on their payable
-- account. Approvals calls it; it isn't granted to anyone.
create or replace function ${fn("approve_expense_report")}(report_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
  v_lines jsonb;
  v_tx uuid;
begin
  select * into v_row from ${reports} x
    where x.${r("id")} = approve_expense_report.report_id and x.${r("approvedAt")} is null and x.${r("cancelledAt")} is null
    for update;
  if not found then
    return;
  end if;
  select jsonb_agg(jsonb_build_object('account', ${categoryAccount("v_row", "c")}, 'amount', q.total) order by c.${k("key")})
    into v_lines
  from (
    select l.${x("category")} as category, sum(l.${x("amount")}) as total
    from ${lines} l where l.${x("report")} = v_row.${r("id")} group by l.${x("category")}
  ) q join ${categories} c on c.${k("id")} = q.category;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('account', ${payableAccount("v_row")}, 'amount', -${total("v_row")}));
  v_tx := ${ledger.fn("ledger_post")}(v_row.${r("tenant")}, 'expense.approved', v_lines,
    'expenses', v_row.${r("id")}::text, left('Expenses: ' || v_row.${r("title")}, 500), 'expense:' || v_row.${r("id")}::text || ':approved', null,
    jsonb_build_object('reportId', v_row.${r("id")}, 'userId', v_row.${r("user")}));
  update ${reports} x set ${r("approvedAt")} = now(), ${r("approvalTransaction")} = v_tx, ${r("updatedAt")} = now()
    where x.${r("id")} = v_row.${r("id")}
    returning * into v_row;
  select * into v_approval from ${ar} p where p.${a("id")} = v_row.${r("approval")};
  ${reportRecord("expense_report.approved", "approved an expense report", ", 'transactionId', v_tx", "billing")}
end;
$$;
revoke execute on function ${fn("approve_expense_report")}(uuid) from public, anon, authenticated;

-- Pays an approved report back: the member's payable account is settled
-- from expense cash.
create or replace function ${fn("reimburse_expense_report")}(report_id uuid, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
  v_tx uuid;
begin${loadReport("reimburse_expense_report.report_id", true)}
  if not ${can(`v_row.${r("tenant")}`, manage)} then
    ${forbidden("not allowed to reimburse expenses")}
  end if;
  if ${status("v_row", "v_approval")} <> 'approved' then
    ${fail("EXPENSE_REPORT_LOCKED", "only an approved report can be reimbursed", "55000")}
  end if;
  v_tx := ${ledger.fn("ledger_post")}(v_row.${r("tenant")}, 'expense.reimbursed',
    jsonb_build_array(
      jsonb_build_object('account', ${payableAccount("v_row")}, 'amount', ${total("v_row")}),
      jsonb_build_object('account', ${cashAccount("v_row")}, 'amount', -${total("v_row")})),
    'expenses', v_row.${r("id")}::text, left('Reimbursed: ' || v_row.${r("title")}, 500), 'expense:' || v_row.${r("id")}::text || ':reimbursed',
    reimburse_expense_report.paid_at,
    jsonb_strip_nulls(jsonb_build_object('reportId', v_row.${r("id")}, 'reference', nullif(trim(reimburse_expense_report.reference), ''))));
  update ${reports} x set ${r("reimbursedAt")} = coalesce(reimburse_expense_report.paid_at, now()), ${r("reimbursement")} = v_tx, ${r("updatedAt")} = now()
    where x.${r("id")} = v_row.${r("id")}
    returning * into v_row;
  ${reportRecord("expense_report.reimbursed", "reimbursed an expense report", ", 'transactionId', v_tx", "billing")}
  return ${reportJson("v_row", "v_approval")};
end;
$$;
${userGrant(`${fn("reimburse_expense_report")}(uuid, timestamptz, text)`)}

-- Withdraws a report that isn't approved yet: its owner or a manager. A
-- pending approval is cancelled with it.
create or replace function ${fn("cancel_expense_report")}(report_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
begin${loadReport("cancel_expense_report.report_id", true)}
  if not (v_row.${r("user")} = auth.uid() or ${can(`v_row.${r("tenant")}`, manage)}) then
    ${forbidden("not allowed to cancel this expense report")}
  end if;
  if ${status("v_row", "v_approval")} not in ('draft', 'submitted', 'rejected') then
    ${fail("EXPENSE_REPORT_LOCKED", "an approved, reimbursed or cancelled report can't be cancelled", "55000")}
  end if;
  update ${ar} p set ${a("status")} = 'cancelled', ${a("decidedAt")} = now()
    where p.${a("id")} = v_row.${r("approval")} and p.${a("status")} = 'pending';
  update ${reports} x set ${r("cancelledAt")} = now(), ${r("updatedAt")} = now()
    where x.${r("id")} = v_row.${r("id")}
    returning * into v_row;
  select * into v_approval from ${ar} p where p.${a("id")} = v_row.${r("approval")};
  ${reportRecord("expense_report.cancelled", "cancelled an expense report")}
  return ${reportJson("v_row", "v_approval")};
end;
$$;
${userGrant(`${fn("cancel_expense_report")}(uuid)`)}

create or replace function ${fn("get_expense_report")}(report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${reports}%rowtype;
  v_approval ${ar}%rowtype;
begin${loadReport("get_expense_report.report_id")}${reader}
  return ${reportJson("v_row", "v_approval")};
end;
$$;
${userGrant(`${fn("get_expense_report")}(uuid)`)}

-- Reports, newest first: the caller's, or everyone's (or one member's) with
-- expenses.read.
create or replace function ${fn("list_expense_reports")}(tenant ${idType}, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := ${can("list_expense_reports.tenant", read)};
begin
  if not (v_reader or ${ctx.can("tenant", "list_expense_reports.tenant", submit)}) then
    ${forbidden("not allowed to list expense reports")}
  end if;
  if not v_reader and (coalesce(list_expense_reports.everyone, false) or (list_expense_reports.user_id is not null and list_expense_reports.user_id <> auth.uid())) then
    ${forbidden("not allowed to read another member's expenses")}
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id), '[]'::jsonb)
    from (
      select ${reportJson("q", "p")} as item, q.${r("createdAt")} as created, q.${r("id")} as id
      from ${reports} q
      left join ${ar} p on p.${a("id")} = q.${r("approval")}
      where q.${r("tenant")} = list_expense_reports.tenant
        and (case
          when coalesce(list_expense_reports.everyone, false) then true
          when list_expense_reports.user_id is not null then q.${r("user")} = list_expense_reports.user_id
          else q.${r("user")} = auth.uid()
        end)
        and (list_expense_reports.status is null or ${status("q", "p")} = list_expense_reports.status)
      order by q.${r("createdAt")} desc, q.${r("id")}
      limit ${pageSize("list_expense_reports.page_size", 100, 500)}
    ) z
  );
end;
$$;
${userGrant(`${fn("list_expense_reports")}(${idType}, uuid, text, boolean, integer)`)}
`;
}
