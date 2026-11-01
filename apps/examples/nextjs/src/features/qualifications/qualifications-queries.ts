import "server-only";
import type {
  QualificationGapStatus,
  QualificationStatus,
} from "better-supabase/blocks/qualifications";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** A required qualification a member lacks or is about to lose, serializable. */
export interface GapRow {
  readonly key: string;
  readonly holderId: string;
  readonly holderTitle: string;
  readonly typeName: string;
  readonly status: QualificationGapStatus;
  readonly expiresOn: string | null;
}

export interface Matrix {
  /** How many qualification types the organization has. */
  readonly types: number;
  readonly gaps: readonly GapRow[];
}

async function loadMatrix(): Promise<Matrix | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [types, gaps] = await Promise.all([
    db.qualifications.types({ organizationId: tenant }).orThrow(),
    db.qualifications.gaps({ organizationId: tenant }).orThrow(),
  ]);

  return {
    types: types.length,
    gaps: gaps.map((gap) => ({
      key: `${gap.holderId}:${gap.typeKey}`,
      holderId: gap.holderId,
      holderTitle: gap.holderTitle,
      typeName: gap.typeName,
      status: gap.status,
      expiresOn: gap.expiresOn?.toString() ?? null,
    })),
  };
}

/** Every member's missing, expired and expiring qualifications. */
export function getMatrix(): Promise<Loaded<Matrix>> {
  return settle(loadMatrix);
}

/** One of the signed-in member's holdings, serializable. */
export interface HoldingRow {
  readonly id: string;
  readonly typeName: string;
  readonly status: QualificationStatus;
  readonly grantedOn: string;
  readonly expiresOn: string | null;
}

export interface MyQualificationsData {
  readonly holdings: readonly HoldingRow[];
  readonly gaps: readonly GapRow[];
}

async function loadMine(): Promise<MyQualificationsData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant || session.kind !== "user") {
    return null;
  }

  const [holdings, gaps] = await Promise.all([
    db.qualifications
      .of({ holderType: "member", holderId: session.user.id })
      .orThrow(),
    db.qualifications
      .gaps({
        organizationId: tenant,
        holderId: session.user.id,
        status: "missing",
      })
      .orThrow(),
  ]);

  return {
    holdings: holdings
      .filter((holding) => holding.organizationId === tenant)
      .map((holding) => ({
        id: holding.id,
        typeName: holding.typeName,
        status: holding.status,
        grantedOn: holding.grantedOn.toString(),
        expiresOn: holding.expiresOn?.toString() ?? null,
      })),
    gaps: gaps.map((gap) => ({
      key: gap.typeKey,
      holderId: gap.holderId,
      holderTitle: gap.holderTitle,
      typeName: gap.typeName,
      status: gap.status,
      expiresOn: gap.expiresOn?.toString() ?? null,
    })),
  };
}

/** The signed-in member's holdings and the required ones they never held. */
export function getMyQualifications(): Promise<Loaded<MyQualificationsData>> {
  return settle(loadMine);
}
