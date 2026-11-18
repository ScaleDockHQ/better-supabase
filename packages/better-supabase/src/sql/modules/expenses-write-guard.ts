import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { conflict } from "../shared.ts";

/**
 * The trigger that guards every write to a standalone expense (ADR 1090):
 * clients never write its status, decision or reimbursement columns; the owner
 * changes only in draft; the amount, currency, category and owner are frozen
 * once approved; a status moves only along the allowed transitions; the trigger
 * stamps who created, decided or reimbursed, and when.
 */
export function expenseGuardSql(
  ctx: BlockSqlContext,
  args: {
    /** The status of a row alias as text. */
    readonly status: (row: string) => string;
    readonly forbidden: (message: string) => string;
    /** The logical owner columns. */
    readonly owners: readonly string[];
    readonly createOthers: string;
    readonly updateOthers: string;
    /** The owner's user id of a row alias. */
    readonly requester: (row: string) => string;
  },
): string {
  const { status, forbidden, owners, createOthers, updateOthers, requester } =
    args;

  const table = ctx.table("expenses");
  const e = (column: string): string => ctx.col("expenses", column);
  const has = (column: string): boolean => ctx.has("expenses", column);
  const fn = (name: string): string => ctx.fn(name);

  // The columns only the expense functions and this trigger write.
  const stamps = [
    "submittedAt",
    "approvedAt",
    "rejectedAt",
    "decidedBy",
    "decidedAt",
    "decisionNote",
    "reimbursedAt",
    "reimbursedBy",
    "reimbursement",
  ].filter((column) => has(column));

  const row = (alias: string, columns: readonly string[]): string =>
    `(${columns.map((column) => `${alias}.${e(column)}`).join(", ")})`;

  const frozen = [
    "amount",
    "currency",
    ...(has("category") ? ["category"] : []),
    ...owners,
  ];

  const clear = (columns: readonly string[]): string =>
    columns
      .filter((column) => has(column))
      .map((column) => `\n      new.${e(column)} := null;`)
      .join("");

  // A client's insert records the caller as the creator; a trusted writer may
  // name one, else the caller or the owner. Clients never change it.
  const creator = has("createdBy") ? e("createdBy") : undefined;

  const stampCreator =
    creator === undefined
      ? ""
      : `
    if v_client then
      new.${creator} := auth.uid();
    else
      new.${creator} := coalesce(new.${creator}, auth.uid(), ${requester("new")});
    end if;`;

  const freezeCreator =
    creator === undefined
      ? ""
      : `
  if v_client and new.${creator} is distinct from old.${creator} then
    ${forbidden("an expense's creator never changes")}
  end if;`;

  const stampBy = (column: string): string =>
    has(column)
      ? `
      if new.${e(column)} is not distinct from old.${e(column)} then
        new.${e(column)} := auth.uid();
      end if;`
      : "";

  const transitions = [
    ["draft", "submitted"],
    ["submitted", "draft"],
    ["submitted", "approved"],
    ["submitted", "rejected"],
    ["rejected", "draft"],
    ["rejected", "submitted"],
    ["approved", "submitted"],
    ["approved", "reimbursed"],
    ["reimbursed", "approved"],
  ]
    .map(([from = "", to = ""]) => `(${sqlString(from)}, ${sqlString(to)})`)
    .join(", ");

  // Security invoker on purpose: current_user tells a client's own write
  // (authenticated or anon) from one through a security definer function.
  return `
-- Guards every write to an expense (ADR 1090): clients never write its status,
-- decision or reimbursement columns, only the expense functions do; the owner
-- changes only in draft and with the create or update key; the amount,
-- currency, category and owner are frozen once approved; a status moves only
-- along the allowed transitions, and this trigger stamps who decided or
-- reimbursed and when, and clears the decision on a reopen.
create or replace function ${fn("expense_guard")}()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_client boolean := current_user::text in ('authenticated', 'anon') and pg_trigger_depth() = 1;
  v_from text;
  v_to text := ${status("new")};
begin
  if tg_op = 'INSERT' then
    if v_client and (v_to <> 'draft' or coalesce(${stamps.map((column) => `new.${e(column)}::text`).join(", ")}) is not null) then
      ${forbidden("a new expense starts as a draft; the expense functions submit and decide it")}
    end if;${stampCreator}
    return new;
  end if;
  v_from := ${status("old")};
  if v_client and (v_from is distinct from v_to or ${row("new", stamps)} is distinct from ${row("old", stamps)}) then
    ${forbidden("an expense's status, decision and reimbursement change only through the expense functions")}
  end if;${freezeCreator}
  if pg_trigger_depth() = 1 and ${row("new", owners)} is distinct from ${row("old", owners)} then
    if v_from <> 'draft' then
      ${conflict("EXPENSE_LOCKED", "an expense changes owner only in draft")}
    end if;
    if v_client and not (${ctx.can("tenant", `old.${e("tenant")}`, createOthers)} or ${ctx.can("tenant", `old.${e("tenant")}`, updateOthers)}) then
      ${forbidden("not allowed to change the owner of this expense")}
    end if;
  end if;
  if pg_trigger_depth() = 1 and v_from in ('approved', 'reimbursed') and ${row("new", frozen)} is distinct from ${row("old", frozen)} then
    ${conflict("EXPENSE_LOCKED", "an approved expense keeps its amount, currency, category and owner; reopen it first")}
  end if;
  if v_client and v_from <> 'draft' and ${row("new", frozen)} is distinct from ${row("old", frozen)} then
    ${conflict("EXPENSE_LOCKED", "a submitted expense keeps its amount, currency, category and owner; withdraw it to draft first")}
  end if;
  if v_from is not distinct from v_to then
    return new;
  end if;
  if (v_from, v_to) not in (${transitions}) then
    ${conflict("EXPENSE_TRANSITION_INVALID", "this status change is not allowed for an expense")}
  end if;
  if v_from = 'reimbursed' then
      new.${e("reimbursedAt")} := null;${clear(["reimbursedBy", "reimbursement"])}
  elsif v_to in ('approved', 'rejected') then${
    has("decidedAt")
      ? `
      new.${e("decidedAt")} := now();`
      : ""
  }${stampBy("decidedBy")}
  elsif v_to in ('draft', 'submitted') then${clear(["decidedBy", "decidedAt", "decisionNote", "approvedAt", "rejectedAt"])}
  else
      new.${e("reimbursedAt")} := coalesce(new.${e("reimbursedAt")}, now());${stampBy("reimbursedBy")}
  end if;
  return new;
end;
$$;
revoke execute on function ${fn("expense_guard")}() from public, anon, authenticated;
drop trigger if exists ${ctx.naming.rename("bsb_expense_guard")} on ${table};
create trigger ${ctx.naming.rename("bsb_expense_guard")}
  before insert or update on ${table}
  for each row execute function ${fn("expense_guard")}();
`;
}

/**
 * The triggers that guard every write to an expense report and its lines,
 * mirroring the standalone rules (ADR 1090): clients never write a report's
 * stamp columns or its owner, a status moves only along the allowed
 * transitions, the trigger stamps who decided, and a report's currency, owner
 * and lines are frozen once approved, and for a client once submitted.
 */
export function expenseReportGuardSql(
  ctx: BlockSqlContext,
  args: {
    readonly forbidden: (message: string) => string;
    /** The approvals requests table and a column reader, when reports use it. */
    readonly approvals?: {
      readonly table: string;
      readonly col: (column: string) => string;
    };
  },
): string {
  const { forbidden, approvals } = args;
  const reports = ctx.table("reports");
  const lines = ctx.table("lines");
  const r = (column: string): string => ctx.col("reports", column);
  const x = (column: string): string => ctx.col("lines", column);
  const fn = (name: string): string => ctx.fn(name);

  // The report table has an approval column with the approvals block, and its
  // own decision columns without it.
  const has = (column: string): boolean =>
    ctx.has("reports", column) &&
    (column === "approval"
      ? approvals !== undefined
      : !["rejectedAt", "decidedBy", "decisionNote"].includes(column) ||
        approvals === undefined);

  const stamps = [
    "submittedAt",
    "approvedAt",
    "approvalTransaction",
    "reimbursedAt",
    "reimbursement",
    "cancelledAt",
    "rejectedAt",
    "decidedBy",
    "decisionNote",
    "approval",
  ].filter((column) => has(column));

  const row = (alias: string, columns: readonly string[]): string =>
    `(${columns.map((column) => `${alias}.${r(column)}`).join(", ")})`;

  const frozen = ["user", "currency"];

  // The status a report's own columns give, without its approval request.
  const status = (alias: string): string =>
    `(case when ${alias}.${r("cancelledAt")} is not null then 'cancelled' when ${alias}.${r("reimbursedAt")} is not null then 'reimbursed' when ${alias}.${r("approvedAt")} is not null then 'approved'${has("rejectedAt") ? ` when ${alias}.${r("rejectedAt")} is not null then 'rejected'` : ""} when ${alias}.${r("submittedAt")} is not null then 'submitted' else 'draft' end)`;

  // Whether the owner may still change the report: a draft, or a rejected one.
  const editable = (alias: string): string =>
    approvals === undefined
      ? `${status(alias)} in ('draft', 'rejected')`
      : `(${status(alias)} = 'draft' or (${status(alias)} = 'submitted' and exists (select 1 from ${approvals.table} ap where ap.${approvals.col("id")} = ${alias}.${r("approval")} and ap.${approvals.col("status")} in ('rejected', 'expired'))))`;

  const transitions = [
    ["draft", "submitted"],
    ["rejected", "submitted"],
    ["submitted", "approved"],
    ["submitted", "rejected"],
    ["draft", "cancelled"],
    ["submitted", "cancelled"],
    ["rejected", "cancelled"],
    ["approved", "reimbursed"],
  ]
    .map(([from = "", to = ""]) => `(${sqlString(from)}, ${sqlString(to)})`)
    .join(", ");

  const clear = (columns: readonly string[]): string =>
    columns
      .filter((column) => has(column))
      .map((column) => `\n    new.${r(column)} := null;`)
      .join("");

  const stampDecider = has("decidedBy")
    ? `
  if v_to in ('approved', 'rejected') and new.${r("decidedBy")} is not distinct from old.${r("decidedBy")} then
    new.${r("decidedBy")} := auth.uid();
  end if;`
    : "";

  const locked = conflict(
    "EXPENSE_REPORT_LOCKED",
    "an approved, reimbursed or cancelled report keeps its lines",
  );

  return `
-- Whether a report is open to its owner (a draft or rejected one), locked
-- (approved, reimbursed or cancelled) or submitted. The guards below run as
-- the writer, who may not read the report or its approval request.
create or replace function ${fn("expense_report_state")}(report_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when ${status("p")} in ('approved', 'reimbursed', 'cancelled') then 'locked' when ${editable("p")} then 'open' else 'submitted' end
  from ${reports} p where p.${r("id")} = expense_report_state.report_id
$$;
revoke execute on function ${fn("expense_report_state")}(uuid) from public, anon;
grant execute on function ${fn("expense_report_state")}(uuid) to authenticated, service_role;

-- Guards every write to an expense report (ADR 1090): clients never write its
-- stamp columns or its owner, a status moves only along the allowed
-- transitions, the trigger stamps the decider and clears a decision on a
-- resubmission, and the owner and currency are frozen once approved, and for a
-- client once submitted.
create or replace function ${fn("expense_report_guard")}()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_client boolean := current_user::text in ('authenticated', 'anon') and pg_trigger_depth() = 1;
  v_from text;
  v_to text := ${status("new")};
begin
  if tg_op = 'INSERT' then
    if v_client and (coalesce(${stamps.map((column) => `new.${r(column)}::text`).join(", ")}) is not null or new.${r("user")} is distinct from auth.uid()) then
      ${forbidden("a new expense report is a draft of the caller; the expense functions submit and decide it")}
    end if;
    return new;
  end if;
  v_from := ${status("old")};
  if v_client and (${row("new", stamps)} is distinct from ${row("old", stamps)} or new.${r("user")} is distinct from old.${r("user")}) then
    ${forbidden("an expense report's owner, status and decision change only through the expense functions")}
  end if;
  if pg_trigger_depth() = 1 and v_from in ('approved', 'reimbursed', 'cancelled') and ${row("new", frozen)} is distinct from ${row("old", frozen)} then
    ${conflict("EXPENSE_REPORT_LOCKED", "an approved, reimbursed or cancelled report keeps its owner and currency")}
  end if;
  if v_client and ${fn("expense_report_state")}(old.${r("id")}) <> 'open' and ${row("new", frozen)} is distinct from ${row("old", frozen)} then
    ${conflict("EXPENSE_REPORT_LOCKED", "a submitted report keeps its owner and currency")}
  end if;
  if v_from is not distinct from v_to then
    return new;
  end if;
  if (v_from, v_to) not in (${transitions}) then
    ${conflict("EXPENSE_TRANSITION_INVALID", "this status change is not allowed for an expense report")}
  end if;${stampDecider}
  if v_to = 'submitted' then${clear(["decidedBy", "decisionNote", "rejectedAt"]) || "\n    null;"}
  end if;
  return new;
end;
$$;
revoke execute on function ${fn("expense_report_guard")}() from public, anon, authenticated;
drop trigger if exists ${ctx.naming.rename("bsb_expense_report_guard")} on ${reports};
create trigger ${ctx.naming.rename("bsb_expense_report_guard")}
  before insert or update on ${reports}
  for each row execute function ${fn("expense_report_guard")}();

-- Keeps the lines of a report as they were once it is approved, and a client's
-- own writes to a submitted report's lines out.
create or replace function ${fn("expense_line_guard")}()
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
    case when tg_op <> 'INSERT' then ${fn("expense_report_state")}(old.${x("report")}) end,
    case when tg_op <> 'DELETE' then ${fn("expense_report_state")}(new.${x("report")}) end
  ] loop
    if v_state = 'locked' then
      ${locked}
    end if;
    if v_client and v_state is distinct from 'open' and v_state is not null then
      ${conflict("EXPENSE_REPORT_LOCKED", "only a draft or rejected report's lines change")}
    end if;
  end loop;
  return coalesce(new, old);
end;
$$;
revoke execute on function ${fn("expense_line_guard")}() from public, anon, authenticated;
drop trigger if exists ${ctx.naming.rename("bsb_expense_line_guard")} on ${lines};
create trigger ${ctx.naming.rename("bsb_expense_line_guard")}
  before insert or update or delete on ${lines}
  for each row execute function ${fn("expense_line_guard")}();
`;
}
