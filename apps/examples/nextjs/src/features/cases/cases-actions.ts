"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Moves a case to another open stage of its pipeline. */
export const moveCase = bsb.blockAction(
  ({ db }) => db.cases,
  "move",
  {
    input: v.object({ caseId: Id, stageId: Id }),
    requireTenant: true,
    permission: "cases.read",
    tags: () => [tags.cases(), tags.inspections()],
    refresh: true,
    args: ({ caseId, stageId }) => [{ caseId, to: { stageId } }],
  },
  (moved) => ({ id: moved.id }),
);

/** Closes a case; the database refuses while a blocker remains. */
export const closeCase = bsb.blockAction(
  ({ db }) => db.cases,
  "close",
  {
    input: v.object({
      caseId: Id,
      note: v.optional(v.pipe(v.string(), v.maxLength(4000))),
    }),
    requireTenant: true,
    permission: "cases.read",
    tags: () => [tags.cases(), tags.inspections()],
    refresh: true,
  },
  (closed) => ({ id: closed.id, number: closed.number }),
);
