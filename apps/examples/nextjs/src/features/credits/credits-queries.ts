import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { readAdminRows } from "@/features/admin-lists/admin-detail-read";
import { loadAdminList } from "@/features/admin-lists/admin-list-load";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

import { creditList } from "./credits-list";
import { creditEntrySource } from "./credits-source";

export const CREDITS_TAG = "credits";

/**
 * The first page of credit entries; `null` without an organization or
 * `billing.read`.
 */
export async function getCreditEntries() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag(CREDITS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "billing.read")) {
    return null;
  }

  return loadAdminList({
    session: request.session,
    tenant,
    list: creditList,
    source: creditEntrySource,
    access: "admin",
    query: creditList.defaults,
  });
}

/** What the credit balance accounts hold now, summed per unit. */
export async function getCreditBalance() {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag(CREDITS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "billing.read")) {
    return null;
  }

  const [row] = await readAdminRows<{ balance: string; held: string }>(
    request.session,
    `select coalesce(sum(b.balance), 0)::text as balance, coalesce(sum(b.held), 0)::text as held
     from better_supabase.ledger_balances b
     join better_supabase.ledger_accounts a on a.id = b.account_id
     where a.kind = 'credit_balance' and a.tenant_id::text = $1`,
    [tenant],
  );

  return { balance: Number(row?.balance ?? 0), held: Number(row?.held ?? 0) };
}

export interface CreditTransaction {
  readonly id: string;
  readonly kind: string;
  readonly memo: string | null;
  readonly reference: string | null;
  readonly effectiveAt: string;
  readonly lines: readonly {
    readonly id: string;
    readonly account: string;
    readonly amount: number;
    readonly unit: string;
  }[];
}

interface TransactionRaw {
  readonly id: string;
  readonly kind: string;
  readonly memo: string | null;
  readonly reference: string | null;
  readonly effective_at: string;
  readonly lines: readonly {
    readonly id: string;
    readonly account: string;
    readonly amount: string;
    readonly unit: string;
  }[];
}

/** One credit transaction with its lines; `"forbidden"` without `billing.read`. */
export async function getCreditTransaction(
  id: string,
): Promise<CreditTransaction | "forbidden" | null> {
  "use cache: private";
  const request = await bsbShell.cached({ id });
  cacheTag(CREDITS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "billing.read")) {
    return "forbidden";
  }

  const [row] = await readAdminRows<TransactionRaw>(
    request.session,
    `select t.id::text as id, t.kind, t.memo,
       nullif(concat_ws(' ', t.reference_type, t.reference_id), '') as reference,
       t.effective_at::text as effective_at,
       (select jsonb_agg(jsonb_build_object('id', e.id, 'account', a.name, 'amount', e.amount::text, 'unit', e.unit)
                order by e.amount, e.id)
          from better_supabase.ledger_entries e
          join better_supabase.ledger_accounts a on a.id = e.account_id
         where e.transaction_id = t.id) as lines
     from better_supabase.ledger_transactions t
     where t.id::text = $2 and t.tenant_id::text = $1
       and exists (select 1 from better_supabase.ledger_entries e
                   join better_supabase.ledger_accounts a on a.id = e.account_id
                   where e.transaction_id = t.id and a.kind = 'credit_balance')`,
    [tenant, id],
  );

  if (!row) {
    return null;
  }

  return {
    id: row.id,
    kind: row.kind,
    memo: row.memo,
    reference: row.reference,
    effectiveAt: row.effective_at,
    lines: row.lines.map((line) => ({ ...line, amount: Number(line.amount) })),
  };
}
