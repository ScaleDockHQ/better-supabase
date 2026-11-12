import "server-only";
import type {
  QualificationGapStatus,
  QualificationStatus,
} from "better-supabase/blocks/qualifications";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import { readMemberNames } from "@/features/people/member-names";
import { bsb } from "@/lib/supabase/server";

import type { QualificationTypeRow } from "./qualifications-types-list";

import { QUALIFICATIONS_TAG } from "./qualifications-cache";

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
  cacheTag(QUALIFICATIONS_TAG);
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
  cacheTag(QUALIFICATIONS_TAG);
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

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/** Every qualification type of the organization; the list kit pages them. */
export async function readQualificationTypeRows(
  db: Db,
  organizationId: string,
): Promise<readonly QualificationTypeRow[]> {
  const types = await db.qualifications
    .types({ organizationId, includeArchived: true })
    .orThrow();

  return types.map((type): QualificationTypeRow => ({
    id: type.id,
    key: type.key,
    name: type.name,
    validForMonths: type.validForMonths ?? null,
    evidenceRequired: type.evidenceRequired,
    archived: type.archivedAt !== undefined,
  }));
}

async function loadTypes(): Promise<readonly QualificationTypeRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(QUALIFICATIONS_TAG);
  const tenant = tenantOf(session);

  return tenant ? readQualificationTypeRows(db, tenant) : null;
}

export function getQualificationTypes(): Promise<
  Loaded<readonly QualificationTypeRow[]>
> {
  return settle(loadTypes);
}

export interface QualificationTypeDetailData {
  readonly row: QualificationTypeRow;
  readonly description: string | null;
  readonly holderTypes: readonly string[];
  readonly requirements: readonly {
    readonly id: string;
    readonly targetType: string;
    readonly targetValue: string;
  }[];
  /** Members who hold a valid qualification of the type today. */
  readonly holders: readonly { readonly id: string; readonly name: string }[];
  readonly gaps: readonly {
    readonly key: string;
    readonly holderTitle: string;
    readonly status: QualificationGapStatus;
    readonly expiresOn: string | null;
  }[];
}

async function loadType(
  id: string,
): Promise<QualificationTypeDetailData | "not-found" | null> {
  "use cache: private";
  const scope = await bsb.cached();
  const { session, db } = scope;
  cacheTag(QUALIFICATIONS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const types = await db.qualifications
    .types({ organizationId: tenant, includeArchived: true })
    .orThrow();

  const type = types.find((entry) => entry.id === id);

  if (!type) {
    return "not-found";
  }

  const [requirements, holderIds, gaps, names] = await Promise.all([
    db.qualifications.requirements(id).orThrow(),
    db.qualifications
      .qualifiedHolders({ organizationId: tenant, typeKey: type.key })
      .orThrow(),
    db.qualifications
      .gaps({ organizationId: tenant, typeKey: type.key })
      .orThrow(),
    readMemberNames(scope, tenant),
  ]);

  return {
    row: {
      id: type.id,
      key: type.key,
      name: type.name,
      validForMonths: type.validForMonths ?? null,
      evidenceRequired: type.evidenceRequired,
      archived: type.archivedAt !== undefined,
    },
    description: type.description ?? null,
    holderTypes: type.holderTypes,
    requirements: requirements.map((requirement) => ({
      id: requirement.id,
      targetType: requirement.targetType,
      targetValue: requirement.targetValue,
    })),
    holders: holderIds.map((holderId) => ({
      id: holderId,
      name: names.get(holderId) ?? holderId,
    })),
    gaps: gaps.map((gap) => ({
      key: gap.holderId,
      holderTitle: gap.holderTitle,
      status: gap.status,
      expiresOn: gap.expiresOn?.toString() ?? null,
    })),
  };
}

export function getQualificationType(
  id: string,
): Promise<Loaded<QualificationTypeDetailData | "not-found">> {
  return settle(() => loadType(id));
}
