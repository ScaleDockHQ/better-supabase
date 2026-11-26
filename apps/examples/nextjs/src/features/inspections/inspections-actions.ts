"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Opens a case for a finding through the cases block. */
export const raiseFindingCase = bsb.blockAction(
  ({ db }) => db.inspections,
  "raiseCase",
  {
    input: v.object({ findingId: Id }),
    requireTenant: true,
    permission: "inspections.write",
    tags: () => [tags.inspections(), tags.cases()],
    refresh: true,
  },
  (raised) => ({ number: raised.number }),
);

/** Closes an inspection; the database refuses while a finding needs a case. */
export const closeInspection = bsb.blockAction(
  ({ db }) => db.inspections,
  "close",
  {
    input: v.object({ inspectionId: Id }),
    requireTenant: true,
    permission: "inspections.write",
    tags: () => [tags.inspections(), tags.cases()],
    refresh: true,
    args: ({ inspectionId }) => [inspectionId],
  },
  (closed) => ({ number: closed.number }),
);
