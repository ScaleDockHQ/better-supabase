import "server-only";
import type { PrescriptionStatus } from "better-supabase/blocks/e-prescribing";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { orMissing } from "@/lib/or-missing";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** One prescription for its page, serializable. */
export interface PrescriptionDetail {
  readonly id: string;
  readonly status: PrescriptionStatus;
  readonly clientId: string | null;
  readonly clientName: string | null;
  readonly medication: string | null;
  readonly dose: string | null;
  readonly route: string | null;
  readonly prescriber: string | null;
  readonly signedAt: string | null;
  readonly sentAt: string | null;
  readonly dispensedAt: string | null;
  readonly cancelReason: string | null;
  readonly deliveryError: string | null;
}

/**
 * The prescription; `undefined` when it does not exist, `null` without an
 * organization.
 */
export async function getPrescription(
  id: string,
): Promise<PrescriptionDetail | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.prescriptions(), tags.customers());

  if (!tenantOf(session)) {
    return null;
  }

  const prescription = orMissing(await db.ePrescribing.get(id));

  if (prescription === undefined) {
    return undefined;
  }

  const isClient = prescription.subject.type === "customer";

  const [client] = isClient
    ? await db.customers
        .list({
          select: ["id", "name"],
          where: { id: prescription.subject.id },
          limit: 1,
        })
        .orThrow()
    : [];

  const { order } = prescription;

  return {
    id: prescription.id,
    status: prescription.status,
    clientId: isClient ? prescription.subject.id : null,
    clientName: client?.name ?? null,
    medication: order?.medicationName ?? null,
    dose: order ? `${order.dose} ${order.doseUnit}` : null,
    route: order?.route ?? null,
    prescriber: prescription.prescriberName ?? null,
    signedAt: prescription.signedAt?.toString() ?? null,
    sentAt: prescription.sentAt?.toString() ?? null,
    dispensedAt: prescription.dispensedAt?.toString() ?? null,
    cancelReason: prescription.cancelReason ?? null,
    deliveryError: prescription.deliveryError ?? null,
  };
}
