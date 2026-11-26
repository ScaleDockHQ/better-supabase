"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Opens a case for a finding through the cases block. */
export const raiseFindingCase = bsb.action(
  {
    input: v.object({ findingId: Id }),
    requireTenant: true,
    permission: "inspections.write",
    tags: () => [tags.inspections(), tags.cases()],
    refresh: true,
  },
  async ({ findingId }, { db }) => {
    const raised = await db.inspections.raiseCase({ findingId });

    if (!raised.ok) {
      return raised;
    }

    return ok({ number: raised.data.number });
  },
);

/** Closes an inspection; the database refuses while a finding needs a case. */
export const closeInspection = bsb.action(
  {
    input: v.object({ inspectionId: Id }),
    requireTenant: true,
    permission: "inspections.write",
    tags: () => [tags.inspections(), tags.cases()],
    refresh: true,
  },
  async ({ inspectionId }, { db }) => {
    const closed = await db.inspections.close(inspectionId);

    if (!closed.ok) {
      return closed;
    }

    return ok({ number: closed.data.number });
  },
);
