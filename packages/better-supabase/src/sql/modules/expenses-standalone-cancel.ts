/** What the cancellation function of a standalone expense needs from its module. */
interface CancelParts {
  readonly fn: (name: string) => string;
  readonly table: string;
  readonly e: (column: string) => string;
  readonly status: (row: string) => string;
  readonly setStatus: (label: string) => string;
  readonly record: (type: string, summary: string) => string;
}

/**
 * Applies the cancellation of an expense's approval request (cancel_approval):
 * a submitted expense goes back to draft, as withdraw_expense does. A decided
 * expense stays as it is. It isn't granted to anyone.
 */
export function expenseApprovalCancelled(parts: CancelParts): string {
  const { fn, table, e, status, setStatus, record } = parts;

  return `
create or replace function ${fn("expense_approval_cancelled")}(expense_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin
  select * into v_row from ${table} x where x.${e("id")} = expense_approval_cancelled.expense_id for update;
  if not found or ${status("v_row")} <> 'submitted' then
    return;
  end if;
  update ${table} x set ${e("submittedAt")} = null${setStatus("draft")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${record("expense.withdrawn", "withdrew an expense")}
end;
$$;
revoke execute on function ${fn("expense_approval_cancelled")}(uuid) from public, anon, authenticated;
`;
}
