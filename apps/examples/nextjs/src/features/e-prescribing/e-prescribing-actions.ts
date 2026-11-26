"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Signs a draft. Only its prescriber signs; the database refuses anyone else. */
export const signPrescription = bsb.action(
  {
    input: v.object({ prescriptionId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "e_prescribing.sign",
  },
  async ({ prescriptionId }, { db, auth }) => {
    const prescription = await db.ePrescribing.sign(prescriptionId);

    if (!prescription.ok) {
      return prescription;
    }

    await refreshCaller(auth, [tags.prescriptions()]);

    return ok({ id: prescription.data.id });
  },
);

/** Cancels a draft; a signed or sent prescription is cancelled with a reason. */
export const cancelPrescription = bsb.action(
  {
    input: v.object({ prescriptionId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "e_prescribing.write",
  },
  async ({ prescriptionId }, { db, auth }) => {
    const prescription = await db.ePrescribing.cancel({ prescriptionId });

    if (!prescription.ok) {
      return prescription;
    }

    await refreshCaller(auth, [tags.prescriptions()]);

    return ok({ id: prescription.data.id });
  },
);
