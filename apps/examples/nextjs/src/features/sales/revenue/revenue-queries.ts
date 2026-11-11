import "server-only";
import type { Money } from "better-supabase/commerce";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { bsb } from "@/lib/supabase/server";

import { SALES_TAG } from "../sales-cache";

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

type ContractLike = {
  readonly id: string;
  readonly title: string;
  readonly status: string;
  readonly value?: Money | undefined;
  readonly startsOn?: { toString(): string } | undefined;
  readonly endsOn?: { toString(): string } | undefined;
  readonly noticeDeadline?: { toString(): string } | undefined;
  readonly autoRenew: boolean;
  readonly ownerId?: string | undefined;
  readonly counterparty?: { readonly id: string } | undefined;
};

function contractOf(contract: ContractLike): ContractRow {
  return {
    id: contract.id,
    title: contract.title,
    status: contract.status,
    value: contract.value ?? null,
    startsOn: contract.startsOn?.toString() ?? null,
    endsOn: contract.endsOn?.toString() ?? null,
    noticeDeadline: contract.noticeDeadline?.toString() ?? null,
    autoRenew: contract.autoRenew,
    ownerId: contract.ownerId ?? null,
    counterpartyId: contract.counterparty?.id ?? null,
  };
}

/** The newest 200 contracts; the overview filters and pages them. */
export async function loadContracts(): Promise<readonly ContractRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const contracts = await db.contracts
    .list({ organizationId: tenant, pageSize: 200 })
    .orThrow();

  return contracts.map(contractOf);
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

export async function loadContract(
  id: string,
): Promise<ContractDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [contract, obligations] = await Promise.all([
    db.contracts.get(id).orThrow(),
    db.contracts
      .obligations({ organizationId: tenant, contractId: id, pageSize: 100 })
      .orThrow(),
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

export interface CommissionPlanRow {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly rateBps: number | null;
  readonly tiers: number;
  readonly archived: boolean;
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

export interface CommissionsData {
  readonly plans: readonly CommissionPlanRow[];
  readonly commissions: readonly CommissionRow[];
  readonly statements: readonly StatementRow[];
}

/** Plans, the newest 200 commissions and the newest 100 statements. */
export async function loadCommissions(): Promise<CommissionsData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const [plans, commissions, statements] = await Promise.all([
    db.commissions.listPlans({ limit: 100 }).orThrow(),
    db.commissions.listCommissions({ limit: 200 }).orThrow(),
    db.commissions.listStatements({ limit: 100 }).orThrow(),
  ]);

  return {
    plans: plans.map((plan) => ({
      id: plan.id,
      name: plan.name,
      kind: plan.kind,
      rateBps: plan.rateBps ?? null,
      tiers: plan.tiers?.length ?? 0,
      archived: plan.archivedAt !== undefined,
    })),
    commissions: commissions.map((commission) => ({
      id: commission.id,
      sellerId: commission.sellerId,
      sourceType: commission.sourceType,
      sourceId: commission.sourceId,
      basis: commission.basis,
      amount: commission.amount,
      occurredOn: commission.occurredOn.toString(),
      status: commission.status,
    })),
    statements: statements.map((statement) => ({
      id: statement.id,
      sellerId: statement.sellerId,
      startsOn: statement.startsOn.toString(),
      endsOn: statement.endsOn.toString(),
      status: statement.status,
      total: statement.total,
    })),
  };
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
  cacheTag(SALES_TAG, CRM_TAG);

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

export interface ReferralCodeRow {
  readonly id: string;
  readonly code: string;
  readonly referrerId: string;
  readonly uses: number;
  readonly maxUses: number | null;
  readonly active: boolean;
  readonly expiresAt: string | null;
}

export interface ReferralRow {
  readonly id: string;
  readonly codeId: string;
  readonly referrerId: string;
  readonly referredEmail: string | null;
  readonly status: string;
  readonly createdAt: string;
}

export interface ReferralsData {
  readonly codes: readonly ReferralCodeRow[];
  readonly referrals: readonly ReferralRow[];
}

export async function loadReferrals(): Promise<ReferralsData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(SALES_TAG, CRM_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const [codes, referrals] = await Promise.all([
    db.referrals.listCodes({ limit: 200 }).orThrow(),
    db.referrals.listReferrals({ limit: 200 }).orThrow(),
  ]);

  return {
    codes: codes.map((code) => ({
      id: code.id,
      code: code.code,
      referrerId: code.referrerId,
      uses: code.uses,
      maxUses: code.maxUses ?? null,
      active: code.active,
      expiresAt: code.expiresAt?.toString() ?? null,
    })),
    referrals: referrals.map((referral) => ({
      id: referral.id,
      codeId: referral.codeId,
      referrerId: referral.referrerId,
      referredEmail: referral.referredEmail ?? null,
      status: referral.status,
      createdAt: referral.createdAt.toString(),
    })),
  };
}
