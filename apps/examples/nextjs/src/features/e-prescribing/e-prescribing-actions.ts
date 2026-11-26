"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Signs a draft. Only its prescriber signs; the database refuses anyone else. */
export const signPrescription = bsb.blockAction(
  ({ db }) => db.ePrescribing,
  "sign",
  {
    input: v.object({ prescriptionId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "e_prescribing.sign",
    tags: () => [tags.prescriptions()],
    refresh: true,
    args: ({ prescriptionId }) => [prescriptionId],
  },
  (prescription) => ({ id: prescription.id }),
);

/** Cancels a draft; a signed or sent prescription is cancelled with a reason. */
export const cancelPrescription = bsb.blockAction(
  ({ db }) => db.ePrescribing,
  "cancel",
  {
    input: v.object({ prescriptionId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "e_prescribing.write",
    tags: () => [tags.prescriptions()],
    refresh: true,
  },
  (prescription) => ({ id: prescription.id }),
);
