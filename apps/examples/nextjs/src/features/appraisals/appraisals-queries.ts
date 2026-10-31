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

/** An appraisal as the list shows it, serializable. */
export interface AppraisalRow {
  readonly id: string;
  readonly subjectUserId: string;
  readonly status:
    | "pending"
    | "reviewed"
    | "calibrated"
    | "awaiting_signoff"
    | "signed_off";
  /** The calibrated rating when there is one, else the review average. */
  readonly rating: string | null;
}

async function loadAppraisals(): Promise<readonly AppraisalRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const rows = await db.appraisals.listAppraisals({ limit: 200 }).orThrow();

  return rows.map((row) => ({
    id: row.id,
    subjectUserId: row.subjectUserId,
    status: row.status,
    rating: row.calibratedRating?.toString() ?? row.rating ?? null,
  }));
}

/** The appraisals the caller reads, newest first. */
export function getAppraisals(): Promise<Loaded<readonly AppraisalRow[]>> {
  return settle(loadAppraisals);
}
