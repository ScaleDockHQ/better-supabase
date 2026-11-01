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

/** A prescription as the list shows it, serializable. */
export interface PrescriptionRow {
  readonly id: string;
  readonly subject: string;
  readonly medication: string | null;
  readonly status: "draft" | "signed" | "sent" | "dispensed" | "cancelled";
  readonly prescriberId: string;
}

async function loadPrescriptions(): Promise<readonly PrescriptionRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const prescriptions = await db.ePrescribing.list({ limit: 100 }).orThrow();

  return prescriptions.map((prescription) => ({
    id: prescription.id,
    subject: `${prescription.subject.type} ${prescription.subject.id.slice(0, 8)}`,
    medication: prescription.order?.medicationName ?? null,
    status: prescription.status,
    prescriberId: prescription.prescriberId,
  }));
}

/** The organization's prescriptions, newest first. */
export function getPrescriptions(): Promise<
  Loaded<readonly PrescriptionRow[]>
> {
  return settle(loadPrescriptions);
}
