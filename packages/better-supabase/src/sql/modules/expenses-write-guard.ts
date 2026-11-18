import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail } from "../shared.ts";

/**
 * The trigger that guards every write to a standalone expense (ADR 1090):
 * clients never write its status, decision or reimbursement columns; the owner
 * changes only in draft; the amount, currency, category and owner are frozen
 * once approved; a status moves only along the allowed transitions; and the
 * trigger stamps who decided or reimbursed, and when.
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
  },
): string {
  const { status, forbidden, owners, createOthers, updateOthers } = args;
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
    end if;
    return new;
  end if;
  v_from := ${status("old")};
  if v_client and (v_from is distinct from v_to or ${row("new", stamps)} is distinct from ${row("old", stamps)}) then
    ${forbidden("an expense's status, decision and reimbursement change only through the expense functions")}
  end if;
  if pg_trigger_depth() = 1 and ${row("new", owners)} is distinct from ${row("old", owners)} then
    if v_from <> 'draft' then
      ${fail("EXPENSE_LOCKED", "an expense changes owner only in draft", "55000")}
    end if;
    if v_client and not (${ctx.can("tenant", `old.${e("tenant")}`, createOthers)} or ${ctx.can("tenant", `old.${e("tenant")}`, updateOthers)}) then
      ${forbidden("not allowed to change the owner of this expense")}
    end if;
  end if;
  if pg_trigger_depth() = 1 and v_from in ('approved', 'reimbursed') and ${row("new", frozen)} is distinct from ${row("old", frozen)} then
    ${fail("EXPENSE_LOCKED", "an approved expense keeps its amount, currency, category and owner; reopen it first", "55000")}
  end if;
  if v_from is not distinct from v_to then
    return new;
  end if;
  if (v_from, v_to) not in (${transitions}) then
    ${fail("EXPENSE_TRANSITION_INVALID", "this status change is not allowed for an expense", "55000")}
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
