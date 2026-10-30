import type { AccountingSource } from "../accounting-sources-sql.ts";
import type { BlockSqlContext } from "../context.ts";

/**
 * What leases books in accounting: each posted rent charge in the sales journal
 * (receivable against revenue) and each rent payment in the bank journal (bank
 * against the receivable).
 */
export function leaseAccountingSources(
  ctx: BlockSqlContext,
): readonly AccountingSource[] {
  const leases = ctx.table("leases");
  const charges = ctx.table("charges");
  const l = (column: string): string => ctx.col("leases", column);
  const c = (column: string): string => ctx.col("charges", column);
  const ledger = ctx.of("ledger");
  const tx = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);

  return [
    {
      source: "lease_rent",
      journal: "sales",
      fn: "accounting_lease_rent_lines",
      comment:
        "The entry of a posted rent charge for accounting: the tenant's receivable\nagainst rent revenue.",
      body: `  select jsonb_build_object(
    'organizationId', y.${c("tenant")},
    'entryDate', y.${c("periodStart")},
    'currency', y.${c("currency")},
    'memo', left('Rent from ' || y.${c("periodStart")}::text || ': ' || coalesce(v.${l("title")}, ''), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'receivable', 'debit', y.${c("amount")}::text, 'partyId', v.${l("partyId")}),
      jsonb_build_object('role', 'revenue', 'credit', y.${c("amount")}::text))
  )
  from ${charges} y join ${leases} v on v.${l("id")} = y.${c("lease")}
  where y.${c("id")}::text = source_id and y.${c("amount")} <> 0`,
    },
    {
      source: "lease_payment",
      journal: "bank",
      fn: "accounting_lease_payment_lines",
      comment:
        "The entry of a rent payment for accounting: bank against the tenant's\nreceivable.",
      body: `  select jsonb_build_object(
    'organizationId', v.${l("tenant")},
    'entryDate', (y.${tx("effectiveAt")} at time zone 'UTC')::date,
    'currency', v.${l("currency")},
    'reference', y.${tx("metadata")} ->> 'reference',
    'memo', left('Rent payment: ' || coalesce(v.${l("title")}, ''), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', v.${l("partyId")}))
  )
  from ${ledger.table("transactions")} y
  join ${leases} v on v.${l("id")}::text = y.${tx("referenceId")}
  cross join lateral (
    select sum(e.${le("amount")}) as amount from ${ledger.table("entries")} e
    where e.${le("transaction")} = y.${tx("id")} and e.${le("amount")} > 0
  ) p
  where y.${tx("id")}::text = source_id and y.${tx("referenceType")} = 'leases' and y.${tx("kind")} = 'lease.payment'
    and p.amount <> 0`,
    },
  ];
}
