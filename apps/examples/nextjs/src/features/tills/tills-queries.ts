import "server-only";
import type { Money } from "better-supabase/commerce";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

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
export async function loadTills(): Promise<readonly TillRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(TILLS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const [tills, open] = await Promise.all([
    db.tills.listTills({ includeArchived: true }).orThrow(),
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

/**
 * The newest 200 sessions. `listSessions` filters by till and status but has no
 * text search, so the overview searches the till name on the server (EX-1105).
 */
export async function loadSessions(): Promise<
  readonly TillSessionRow[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(TILLS_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const [tills, sessions] = await Promise.all([
    db.tills.listTills({ includeArchived: true }).orThrow(),
    db.tills.listSessions({ limit: 200 }).orThrow(),
  ]);

  const names = new Map(tills.map((till) => [till.id, till.name]));

  return sessions.map((row) => ({
    id: row.id,
    tillId: row.tillId,
    till: names.get(row.tillId) ?? "",
    status: row.status,
    openingFloat: row.openingFloat,
    expected: row.expected,
    openedAt: row.openedAt.toString(),
    closedAt: row.closedAt?.toString() ?? null,
  }));
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
  const tills = await db.tills.listTills({ includeArchived: true }).orThrow();
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
