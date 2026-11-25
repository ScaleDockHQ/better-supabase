import type { BlockSqlContext } from "../context.ts";

import { userGrant } from "../shared.ts";
import { hasBatches } from "./banking-batches.ts";

/**
 * `pay_payment_batch`: `procurement.payDueBills` as one atomic function (ADR
 * 1235). It creates the batch with `create_payment_batch` and posts it with
 * `post_payment_batch`, so each keeps its own permission check, hooks and
 * events. A bill that needs approval refuses the post and rolls the batch back.
 * With `with_accounts` it also returns the bank accounts, which the client
 * needs to write the SEPA file.
 */
export function bankingPay(ctx: BlockSqlContext): string {
  if (!hasBatches(ctx)) {
    return "";
  }

  const fn = ctx.fn("pay_payment_batch");

  return `
-- Creates a draft payment batch (input as create_payment_batch) and posts it,
-- in one transaction. Returns { batch, accounts }; accounts (every bank
-- account, archived ones included) only when with_accounts is true.
create or replace function ${fn}(tenant ${ctx.idType}, input jsonb, with_accounts boolean default false)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_batch jsonb;
begin
  v_batch := ${ctx.fn("create_payment_batch")}(pay_payment_batch.tenant, pay_payment_batch.input);
  v_batch := ${ctx.fn("post_payment_batch")}((v_batch ->> 'id')::uuid);
  return jsonb_build_object(
    'batch', v_batch,
    'accounts', case when pay_payment_batch.with_accounts
      then ${ctx.fn("list_bank_accounts")}(pay_payment_batch.tenant, true)
      else '[]'::jsonb end);
end;
$$;
${userGrant(`${fn}(${ctx.idType}, jsonb, boolean)`)}
`;
}
