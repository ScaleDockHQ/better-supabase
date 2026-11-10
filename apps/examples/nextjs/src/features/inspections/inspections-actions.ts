"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { CASES_TAG } from "@/features/cases/cases-cache";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { INSPECTIONS_TAG } from "./inspections-cache";

const Id = v.pipe(v.string(), v.uuid());

/** Opens a case for a finding through the cases block. */
export const raiseFindingCase = bsb.action(
  {
    input: v.object({ findingId: Id }),
    requireTenant: true,
    permission: "inspections.write",
  },
  async ({ findingId }, { db, auth }) => {
    const raised = await db.inspections.raiseCase({ findingId });

    if (!raised.ok) {
      return raised;
    }

    await refreshCaller(auth, [INSPECTIONS_TAG, CASES_TAG]);

    return ok({ number: raised.data.number });
  },
);

/** Closes an inspection; the database refuses while a finding needs a case. */
export const closeInspection = bsb.action(
  {
    input: v.object({ inspectionId: Id }),
    requireTenant: true,
    permission: "inspections.write",
  },
  async ({ inspectionId }, { db, auth }) => {
    const closed = await db.inspections.close(inspectionId);

    if (!closed.ok) {
      return closed;
    }

    await refreshCaller(auth, [INSPECTIONS_TAG, CASES_TAG]);

    return ok({ number: closed.data.number });
  },
);
