import type { BlockSqlContext } from "./context.ts";

import {
  countedLine,
  declared,
  lineAmount,
  lineDiscount,
} from "./line-items-sql.ts";
import { userGrant } from "./shared.ts";

/**
 * The totals of one record's lines per billing party: who pays, the net amount
 * after line discounts and the cost the lines carry. It runs as the caller, so
 * the lines' own policies decide what is counted.
 */
export function billingPartyReportSql(
  ctx: BlockSqlContext,
  options: {
    readonly name: string;
    readonly argument: string;
    readonly lines: string;
  },
): string {
  const { lines } = options;
  const col = (column: string): string => ctx.col(lines, column);
  const has = (column: string): boolean => declared(ctx, lines, column);
  const amount = lineAmount(ctx, lines, "l");
  const percent = has("discountBps") ? `l.${col("discountBps")}` : null;
  const net = `(${amount} - ${lineDiscount(ctx, lines, "l", amount, percent)})`;
  const party = has("billingParty") ? `l.${col("billingParty")}` : "'customer'";
  const partyId = has("billingPartyId") ? `l.${col("billingPartyId")}` : "null";

  const accountId = has("billingAccountId")
    ? `l.${col("billingAccountId")}::text`
    : "null";

  const cost = has("unitCost")
    ? `round(l.${col("quantity")} * l.${col("unitCost")})`
    : "0";

  return `
-- Totals and cost of one record's lines per billing party (ADR 0141). It runs
-- as the caller, so only lines the caller can read count.
create or replace function ${options.name}(${options.argument} uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(g.row order by g.party, g.party_id, g.account_id), '[]'::jsonb)
  from (
    select ${party} as party, ${partyId} as party_id, ${accountId} as account_id,
      jsonb_build_object(
        'billingParty', ${party}, 'billingPartyId', ${partyId}, 'billingAccountId', ${accountId},
        'lines', count(*), 'net', sum(${net})::text, 'cost', sum(${cost})::text
      ) as row
    from ${ctx.table(lines)} l
    where l.${col("parent")} = ${options.argument} and ${countedLine(ctx, lines, "l")}
    group by 1, 2, 3
  ) g
$$;
${userGrant(`${options.name}(uuid)`)}
`;
}
