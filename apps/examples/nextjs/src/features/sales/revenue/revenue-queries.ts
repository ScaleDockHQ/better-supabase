import "server-only";
import type { Money } from "better-supabase/commerce";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { getAllPages } from "@/lib/read-all-pages";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import { contractOf } from "../list-reads/contracts-reads";

export interface ContractRow {
  readonly id: string;
  readonly title: string;
  readonly status: string;
  readonly value: Money | null;
  readonly startsOn: string | null;
  readonly endsOn: string | null;
  readonly noticeDeadline: string | null;
  readonly autoRenew: boolean;
  readonly ownerId: string | null;
  readonly counterpartyId: string | null;
}

export interface ObligationRow {
  readonly id: string;
  readonly title: string;
  readonly status: string;
  readonly dueOn: string | null;
  readonly overdue: boolean;
}

export interface ContractDetail extends ContractRow {
  readonly description: string | null;
  readonly renewalMonths: number;
  readonly noticeDays: number;
  readonly renewedCount: number;
  readonly signedAt: string | null;
  readonly terminatedAt: string | null;
  readonly obligations: readonly ObligationRow[];
}

export async function getContract(
  id: string,
): Promise<ContractDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.sales(), tags.crm());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [contract, obligations] = await Promise.all([
    db.contracts.get(id).orThrow(),
    getAllPages((page) =>
      db.contracts.obligationPage({
        organizationId: tenant,
        filters: { contractId: [id] },
        ...page,
      }),
    ),
  ]);

  return {
    ...contractOf(contract),
    description: contract.description ?? null,
    renewalMonths: contract.renewalMonths,
    noticeDays: contract.noticeDays,
    renewedCount: contract.renewedCount,
    signedAt: contract.signedAt?.toString() ?? null,
    terminatedAt: contract.terminatedAt?.toString() ?? null,
    obligations: obligations.map((obligation) => ({
      id: obligation.id,
      title: obligation.title,
      status: obligation.status,
      dueOn: obligation.dueOn?.toString() ?? null,
      overdue: obligation.overdue,
    })),
  };
}

export interface CommissionRow {
  readonly id: string;
  readonly sellerId: string;
  readonly sourceType: string;
  readonly sourceId: string;
  readonly basis: Money;
  readonly amount: Money;
  readonly occurredOn: string;
  readonly status: string;
}

export interface StatementRow {
  readonly id: string;
  readonly sellerId: string;
  readonly startsOn: string;
  readonly endsOn: string;
  readonly status: string;
  readonly total: Money;
}

export interface StatementDetail extends StatementRow {
  readonly paidAt: string | null;
  readonly finalizedAt: string | null;
  readonly lines: readonly CommissionRow[];
}

export async function loadStatement(
  id: string,
): Promise<StatementDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.sales(), tags.crm());

  if (!tenantOf(session)) {
    return null;
  }

  const statement = await db.commissions.getStatement(id).orThrow();

  return {
    id: statement.id,
    sellerId: statement.sellerId,
    startsOn: statement.startsOn.toString(),
    endsOn: statement.endsOn.toString(),
    status: statement.status,
    total: statement.total,
    paidAt: statement.paidAt?.toString() ?? null,
    finalizedAt: statement.finalizedAt?.toString() ?? null,
    lines: statement.entries.map((commission) => ({
      id: commission.id,
      sellerId: commission.sellerId,
      sourceType: commission.sourceType,
      sourceId: commission.sourceId,
      basis: commission.basis,
      amount: commission.amount,
      occurredOn: commission.occurredOn.toString(),
      status: commission.status,
    })),
  };
}
