"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/**
 * Records a note as evidence on a control. With `evidenceTaskId` it answers
 * that task, so the task's due date moves one interval past today.
 */
export const addControlEvidence = bsb.blockAction(
  ({ db }) => db.compliance,
  "addEvidence",
  {
    input: v.object({
      controlId: v.pipe(v.string(), v.uuid()),
      evidenceTaskId: v.optional(v.pipe(v.string(), v.uuid())),
      note: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(4000)),
    }),
    requireTenant: true,
    permission: "compliance.collect",
    tags: () => [tags.compliance()],
    refresh: true,
    args: ({ controlId, evidenceTaskId, note }) => [
      {
        controlId,
        input:
          evidenceTaskId === undefined ? { note } : { note, evidenceTaskId },
      },
    ],
  },
  (added) => ({ id: added.id }),
);
