import "server-only";
import type { FundingPeriod } from "better-supabase/blocks/funding";

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

/** An active award with the usage of its latest period, serializable. */
export interface AwardRow {
  readonly id: string;
  readonly product: string;
  readonly units: number;
  readonly period: FundingPeriod;
  readonly reference: string | null;
  readonly used: number;
  readonly over: number;
}

async function loadAwards(): Promise<readonly AwardRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const awards = await db.funding.awards(tenant).orThrow();

  return Promise.all(
    awards.slice(0, 20).map(async (award) => {
      const usage = await db.funding.usage(award.id).orThrow();
      const latest = usage.periods.at(-1);

      return {
        id: award.id,
        product: `${award.product.code} ${award.product.title}`,
        units: award.units,
        period: award.period,
        reference: award.reference ?? null,
        used: latest?.used ?? 0,
        over: latest?.over ?? 0,
      };
    }),
  );
}

/** The organization's first 20 awards with the usage of their latest period. */
export function getAwards(): Promise<Loaded<readonly AwardRow[]>> {
  return settle(loadAwards);
}
