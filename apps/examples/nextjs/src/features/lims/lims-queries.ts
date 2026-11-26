import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { postgres, userClaims } from "@/features/developer/postgres";
import { getAllPages } from "@/lib/read-all-pages";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

export type SampleStatus =
  | "registered"
  | "in_testing"
  | "completed"
  | "released"
  | "rejected";

/** A sample as the overview shows it, serializable. */
export interface SampleRow {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly kind: string | null;
  readonly lot: string | null;
  readonly status: SampleStatus;
  readonly receivedOn: string;
}

export interface MethodRow {
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly unit: string | null;
  readonly lowerLimit: number | null;
  readonly upperLimit: number | null;
}

export async function getMethods(): Promise<readonly MethodRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.lims());

  if (!tenantOf(session)) {
    return null;
  }

  const methods = await getAllPages((page) => db.lims.methodPage(page));

  return methods.map((row) => ({
    id: row.id,
    key: row.key,
    name: row.name,
    unit: row.unit ?? null,
    lowerLimit: row.lowerLimit ?? null,
    upperLimit: row.upperLimit ?? null,
  }));
}

export interface ResultRow {
  readonly id: string;
  readonly methodId: string;
  readonly value: number;
  readonly outcome: "in_spec" | "out_of_spec";
  readonly caseId: string | null;
  readonly note: string | null;
  readonly testedAt: string;
}

export interface SampleFull extends SampleRow {
  readonly notes: string | null;
  readonly rejectionReason: string | null;
  readonly completedAt: string | null;
  readonly releasedAt: string | null;
  readonly results: readonly ResultRow[];
}

/** One sample with its results, newest first. */
export async function loadSample(
  id: string,
): Promise<SampleFull | null | undefined> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.lims());

  if (!tenantOf(session)) {
    return null;
  }

  const found = await db.lims.getSample(id);

  if (!found.ok) {
    if (found.error.kind === "not_found") {
      return undefined;
    }

    throw new Error(found.error.message);
  }

  const sample = found.data;

  return {
    id: sample.id,
    number: sample.number,
    title: sample.title,
    kind: sample.kind ?? null,
    lot: sample.lot ?? null,
    status: sample.status,
    receivedOn: sample.receivedOn.toString(),
    notes: sample.notes ?? null,
    rejectionReason: sample.rejectionReason ?? null,
    completedAt: sample.completedAt?.toString() ?? null,
    releasedAt: sample.releasedAt?.toString() ?? null,
    results: sample.results.map((row) => ({
      id: row.id,
      methodId: row.methodId,
      value: row.value,
      outcome: row.outcome,
      caseId: row.caseId ?? null,
      note: row.note ?? null,
      testedAt: row.testedAt.toString(),
    })),
  };
}

export interface InstrumentOption {
  readonly id: string;
  readonly name: string;
}

/**
 * The assets that hold a valid calibration today. The block refuses a result
 * from any other instrument, so the form offers only these. The assets block
 * has no list call here, so the names come from the caller's connection
 * (EX-1106).
 */
export async function getInstruments(): Promise<
  readonly InstrumentOption[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.lims());
  const tenant = tenantOf(session);
  const connection = postgres();
  const claims = userClaims(session);

  if (!tenant || !connection || !claims) {
    return null;
  }

  const assets = await connection.asUser(claims).queryRaw<InstrumentOption>(
    `select id, name from better_supabase.assets
     where tenant_id = $1 and retired_at is null order by name limit 50`,
    [tenant],
  );

  const qualified = await db.lims.listQualifiedInstruments().orThrow();
  const ids = new Set(qualified);

  return assets.filter((asset) => ids.has(asset.id));
}
