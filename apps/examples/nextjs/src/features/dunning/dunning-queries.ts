import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

import { DUNNING_TAG } from "./dunning-cache";

/** A reminder level, serializable. */
export interface DunningLevelRow {
  readonly level: number;
  readonly daysAfterDue: number;
  /** In minor units of the invoice's currency. */
  readonly fee: number;
  readonly final: boolean;
}

/** One run of the reminders, serializable. */
export interface DunningRunRow {
  readonly id: string;
  readonly asOf: string;
  readonly invoices: number;
  readonly customers: number;
}

export interface Collections {
  readonly levels: readonly DunningLevelRow[];
  readonly runs: readonly DunningRunRow[];
}

export type CollectionsLoaded =
  | { readonly kind: "ok"; readonly data: Collections }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

async function loadCollections(): Promise<Collections | null> {
  "use cache: private";
  cacheTag(DUNNING_TAG);
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [levels, runs] = await Promise.all([
    db.invoices.dunningLevels(tenant).orThrow(),
    db.invoices.dunningRuns({ organizationId: tenant, limit: 5 }).orThrow(),
  ]);

  return {
    levels: levels.map((level) => ({
      level: level.level,
      daysAfterDue: level.daysAfterDue,
      fee: Number(level.fee),
      final: level.final,
    })),
    runs: runs.map((run) => ({
      id: run.id,
      asOf: run.asOf.toString(),
      invoices: run.items,
      customers: run.customers,
    })),
  };
}

/**
 * The organization's reminder levels and its latest reminder runs. A failed
 * read becomes `{ kind: "error" }` and is never cached, so Retry reads again.
 */
export async function getCollections(): Promise<CollectionsLoaded> {
  try {
    const data = await loadCollections();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
