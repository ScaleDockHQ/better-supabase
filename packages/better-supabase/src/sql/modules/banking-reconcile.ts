import type { BlockSqlContext } from "../context.ts";

import { userGrant } from "../shared.ts";

/**
 * `reconcile_bank_account`: `finance.reconcile` as one atomic function (ADR
 * 1235). It reads the account's unmatched transactions, takes the best invoice
 * `suggest_bank_matches` finds for each and matches it with
 * `match_bank_transaction`, so each match keeps its own permission check, hooks
 * and events. A match that fails rolls back to its own savepoint and is listed
 * in `failed`; the others stay.
 */
export function bankingReconcile(ctx: BlockSqlContext): string {
  return `
-- Matches an account's unmatched transactions (newest first, line_limit of
-- them, default 20) to their best open invoice, in one transaction. A
-- transaction without a suggestion that scores min_score (default: any) is
-- listed in unmatched; a match that fails is listed in failed and the rest go
-- on. Returns { matched: [transaction], unmatched: [id], failed: [{
-- transactionId, message }] }.
create or replace function ${ctx.fn("reconcile_bank_account")}(account_id uuid, min_score numeric default null, line_limit integer default 20)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_line jsonb;
  v_best jsonb;
  v_matched jsonb := '[]'::jsonb;
  v_unmatched jsonb := '[]'::jsonb;
  v_failed jsonb := '[]'::jsonb;
begin
  for v_line in
    select value from jsonb_array_elements(${ctx.fn("list_bank_transactions")}(
      reconcile_bank_account.account_id,
      jsonb_build_object('status', 'unmatched', 'limit', coalesce(reconcile_bank_account.line_limit, 20))))
  loop
    v_best := ${ctx.fn("suggest_bank_matches")}((v_line ->> 'id')::uuid) -> 0;
    if v_best is null
      or (reconcile_bank_account.min_score is not null and (v_best ->> 'score')::numeric < reconcile_bank_account.min_score) then
      v_unmatched := v_unmatched || to_jsonb(v_line ->> 'id');
      continue;
    end if;
    begin
      v_matched := v_matched || ${ctx.fn("match_bank_transaction")}(
        (v_line ->> 'id')::uuid,
        jsonb_build_array(jsonb_build_object('targetType', 'invoice', 'targetId', v_best ->> 'targetId')));
    exception when others then
      v_failed := v_failed || jsonb_build_object('transactionId', v_line ->> 'id', 'message', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('matched', v_matched, 'unmatched', v_unmatched, 'failed', v_failed);
end;
$$;
${userGrant(`${ctx.fn("reconcile_bank_account")}(uuid, numeric, integer)`)}
`;
}
