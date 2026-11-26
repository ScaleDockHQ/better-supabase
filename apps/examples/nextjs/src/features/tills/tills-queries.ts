import "server-only";
import type { Money } from "better-supabase/commerce";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { getAllPages, getAllPagesResult } from "@/lib/read-all-pages";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import { TILLS_TAG } from "./tills-cache";

export interface TillRow {
  readonly id: string;
  readonly name: string;
  readonly location: string | null;
  readonly currency: string;
  readonly hasAccount: boolean;
  readonly archived: boolean;
  readonly open: boolean;
}

/** The tills, with whether one has a session open right now. */
export async function getTills(): Promise<readonly TillRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(TILLS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const [tills, open] = await Promise.all([
    getAllPages((page) =>
      db.tills.tillPage({ ...page, filters: { includeArchived: ["true"] } }),
    ),
    db.tills.listSessions({ status: "open", limit: 200 }).orThrow(),
  ]);

  const openTills = new Set(open.map((row) => row.tillId));

  return tills.map((till) => ({
    id: till.id,
    name: till.name,
    location: till.location ?? null,
    currency: till.currency,
    hasAccount: till.accountId !== undefined,
    archived: till.archivedAt !== undefined,
    open: openTills.has(till.id),
  }));
}

/** The ids of the tills with a session open right now. */
export async function getOpenTillIds(): Promise<readonly string[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(TILLS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const open = await db.tills
    .listSessions({ status: "open", limit: 200 })
    .orThrow();

  return open.map((row) => row.tillId);
}

export interface TillSessionRow {
  readonly id: string;
  readonly tillId: string;
  readonly till: string;
  readonly status: "open" | "closed";
  readonly openingFloat: Money;
  readonly expected: Money;
  readonly openedAt: string;
  readonly closedAt: string | null;
}

export interface MovementRow {
  readonly id: string;
  readonly kind: "cash_sale" | "cash_refund" | "cash_in" | "cash_out";
  readonly amount: Money;
  readonly reason: string | null;
  readonly reference: string | null;
  readonly createdAt: string;
}

export interface DepositRow {
  readonly id: string;
  readonly amount: Money;
  readonly depositedOn: string;
  readonly reference: string | null;
  readonly status: "pending" | "reconciled";
}

export interface CountSummary {
  readonly expected: Money;
  readonly counted: Money;
  readonly variance: Money;
  readonly countedAt: string;
  readonly notes: string | null;
}

export interface SessionFull extends TillSessionRow {
  readonly notes: string | null;
  readonly movements: readonly MovementRow[];
  readonly count: CountSummary | null;
  readonly deposits: readonly DepositRow[];
}

/** One session with its movements, closing count and deposits. */
export async function loadSession(
  id: string,
): Promise<SessionFull | null | undefined> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(TILLS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const found = await db.tills.getSession(id);

  if (!found.ok) {
    if (found.error.kind === "not_found") {
      return undefined;
    }

    throw new Error(found.error.message);
  }

  const row = found.data;

  const tills = await getAllPages((page) =>
    db.tills.tillPage({ ...page, filters: { includeArchived: ["true"] } }),
  );

  const till = tills.find((candidate) => candidate.id === row.tillId);

  return {
    id: row.id,
    tillId: row.tillId,
    till: till?.name ?? "",
    status: row.status,
    openingFloat: row.openingFloat,
    expected: row.expected,
    openedAt: row.openedAt.toString(),
    closedAt: row.closedAt?.toString() ?? null,
    notes: row.notes ?? null,
    movements: row.movements.map((movement) => ({
      id: movement.id,
      kind: movement.kind,
      amount: movement.amount,
      reason: movement.reason ?? null,
      reference: movement.reference ?? null,
      createdAt: movement.createdAt.toString(),
    })),
    count: row.count
      ? {
          expected: row.count.expected,
          counted: row.count.counted,
          variance: row.count.variance,
          countedAt: row.count.countedAt.toString(),
          notes: row.count.notes ?? null,
        }
      : null,
    deposits: row.deposits.map((deposit) => ({
      id: deposit.id,
      amount: deposit.amount,
      depositedOn: deposit.depositedOn.toString(),
      reference: deposit.reference ?? null,
      status: deposit.status,
    })),
  };
}

export interface BankTargets {
  readonly accounts: readonly { readonly id: string; readonly name: string }[];
  /** Unmatched transactions that took money in, newest first. */
  readonly transactions: readonly {
    readonly id: string;
    readonly label: string;
    readonly amount: Money;
  }[];
}

/**
 * The bank accounts and their unmatched incoming transactions, for the import
 * and the match of a cash deposit (EX-1113).
 */
export async function getBankTargets(): Promise<BankTargets | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(TILLS_TAG, tags.banking());

  if (!tenantOf(session)) {
    return null;
  }

  const accounts = await getAllPagesResult((page) =>
    db.banking.accountPage(page),
  ).orThrow();

  const lists = await Promise.all(
    accounts.map((account) =>
      db.banking
        .transactions({ accountId: account.id, status: "unmatched", limit: 50 })
        .orThrow(),
    ),
  );

  return {
    accounts: accounts.map((account) => ({
      id: account.id,
      name: account.name,
    })),
    transactions: lists
      .flat()
      .filter((row) => row.amount.amount > 0n)
      .map((row) => ({
        id: row.id,
        label: [
          row.bookedOn.toString(),
          row.counterpartyName ?? row.remittance ?? "",
        ]
          .filter(Boolean)
          .join(" "),
        amount: row.amount,
      })),
  };
}
