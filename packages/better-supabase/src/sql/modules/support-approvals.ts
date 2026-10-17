import type { ModuleContext } from "../context.ts";

/**
 * The callbacks the approvals module makes for a support request it filed.
 * `approver` is the approver check against the request row `v_row`.
 */
export function supportApprovalFunctions(
  ctx: ModuleContext,
  approver: string,
): string {
  const requests = ctx.table("requests");
  const c = (logical: string) => ctx.col("requests", logical);

  return `

-- Whether the caller may approve the waiting request: never its requester.
create or replace function ${ctx.fn("support_request_approvable")}(request_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${requests};
begin
  select * into v_row from ${requests} x where x.${c("id")} = support_request_approvable.request_id;
  return found and v_row.${c("approvedBy")} is null and v_row.${c("session")} is null
    and v_row.${c("expiresAt")} > now()
    and (select auth.uid()) is not null and v_row.${c("admin")} <> (select auth.uid())
    and coalesce(${approver}, false);
end;
$$;
revoke execute on function ${ctx.fn("support_request_approvable")}(uuid) from public, anon, authenticated;

-- Closes a waiting request whose approval was rejected, so no start uses it.
create or replace function ${ctx.fn("close_support_request")}(request_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update ${requests} x set ${c("expiresAt")} = least(x.${c("expiresAt")}, now())
  where x.${c("id")} = $1 and x.${c("approvedBy")} is null and x.${c("session")} is null;
$$;
revoke execute on function ${ctx.fn("close_support_request")}(uuid) from public, anon, authenticated;`;
}
