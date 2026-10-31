import "server-only";
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

/** A sample as the list shows it, serializable. */
export interface SampleRow {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly lot: string | null;
  readonly status:
    | "registered"
    | "in_testing"
    | "completed"
    | "released"
    | "rejected";
  readonly receivedOn: string;
}

async function loadSamples(): Promise<readonly SampleRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const samples = await db.lims.listSamples({ limit: 100 }).orThrow();

  return samples.map((row) => ({
    id: row.id,
    number: row.number,
    title: row.title,
    lot: row.lot ?? null,
    status: row.status,
    receivedOn: row.receivedOn.toString(),
  }));
}

/** The organization's samples, newest first. */
export function getSamples(): Promise<Loaded<readonly SampleRow[]>> {
  return settle(loadSamples);
}
