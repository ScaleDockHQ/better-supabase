import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { CreditEntryRow } from "./credits-list";

interface CreditEntryRaw extends AdminListRaw {
  readonly transaction_id: string;
  readonly kind: string;
  readonly memo: string | null;
  readonly amount: string;
  readonly reference: string | null;
  readonly effective_at: string;
}

/**
 * The entries of the organization's credit balance accounts, read as the
 * caller: the accounts name `billing.read` as their `read_permission`, so RLS
 * answers and the page's own check only decides what to render.
 */
export const creditEntrySource: AdminListSource<
  CreditEntryRaw,
  CreditEntryRow
> = {
  from: `better_supabase.ledger_entries e
    join better_supabase.ledger_accounts a on a.id = e.account_id
    join better_supabase.ledger_transactions t on t.id = e.transaction_id`,
  idColumn: "e.id",
  idType: "uuid",
  timeColumn: "e.effective_at",
  scope: "e.tenant_id::text = $1 and a.kind = 'credit_balance'",
  search: ["t.memo", "t.kind", "t.reference_id"],
  facetSql: { kind: "t.kind" },
  select: `t.id::text as transaction_id, t.kind, t.memo, e.amount::text as amount,
    nullif(concat_ws(' ', t.reference_type, t.reference_id), '') as reference,
    e.effective_at::text as effective_at`,
  map: (raw) => ({
    id: raw.id,
    transactionId: raw.transaction_id,
    kind: raw.kind,
    memo: raw.memo,
    amount: Number(raw.amount),
    reference: raw.reference,
    effectiveAt: raw.effective_at,
  }),
};
