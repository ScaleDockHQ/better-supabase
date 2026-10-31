import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

/**
 * What tills books in accounting, for a till that names its cash account: the
 * difference of a closing count in the cash journal (an overage is cash against
 * suspense, a shortage the reverse), and a cash deposit in the bank journal
 * (bank against the till's cash account).
 */
export function tillsAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  const tills = ctx.table("tills");
  const sessions = ctx.table("sessions");
  const counts = ctx.table("counts");
  const deposits = ctx.table("deposits");
  const t = (column: string): string => ctx.col("tills", column);
  const s = (column: string): string => ctx.col("sessions", column);
  const c = (column: string): string => ctx.col("counts", column);
  const d = (column: string): string => ctx.col("deposits", column);

  return [
    {
      source: "till_count",
      journal: "cash",
      fn: "accounting_till_count_lines",
      comment:
        "The entry of a till count's difference for accounting: cash against suspense\nfor an overage, suspense against cash for a shortage.",
      body: `  select jsonb_build_object(
    'organizationId', v.${c("tenant")},
    'entryDate', (v.${c("countedAt")} at time zone 'UTC')::date,
    'currency', x.${t("currency")},
    'reference', left(v.${c("session")}::text, 8),
    'memo', left('Till count: ' || x.${t("name")}, 500),
    'lines', case when v.${c("variance")} > 0 then jsonb_build_array(
      jsonb_build_object('accountId', x.${t("account")}, 'debit', v.${c("variance")}::text),
      jsonb_build_object('role', 'suspense', 'credit', v.${c("variance")}::text))
    else jsonb_build_array(
      jsonb_build_object('role', 'suspense', 'debit', (-v.${c("variance")})::text),
      jsonb_build_object('accountId', x.${t("account")}, 'credit', (-v.${c("variance")})::text))
    end
  )
  from ${counts} v
  join ${sessions} y on y.${s("id")} = v.${c("session")}
  join ${tills} x on x.${t("id")} = y.${s("till")}
  where v.${c("id")}::text = source_id and v.${c("variance")} <> 0 and x.${t("account")} is not null`,
    },
    {
      source: "till_deposit",
      journal: "bank",
      fn: "accounting_till_deposit_lines",
      comment:
        "The entry of a cash deposit for accounting: bank against the till's cash\naccount.",
      body: `  select jsonb_build_object(
    'organizationId', v.${d("tenant")},
    'entryDate', v.${d("depositedOn")},
    'currency', x.${t("currency")},
    'reference', left(coalesce(v.${d("reference")}, v.${d("id")}::text), 100),
    'memo', left('Cash deposit: ' || x.${t("name")}, 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', v.${d("amount")}::text),
      jsonb_build_object('accountId', x.${t("account")}, 'credit', v.${d("amount")}::text))
  )
  from ${deposits} v
  join ${sessions} y on y.${s("id")} = v.${d("session")}
  join ${tills} x on x.${t("id")} = y.${s("till")}
  where v.${d("id")}::text = source_id and x.${t("account")} is not null`,
    },
  ];
}
