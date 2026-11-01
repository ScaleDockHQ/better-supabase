"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Moves a case to another open stage of its pipeline. */
export const moveCase = bsb.action(
  {
    input: v.object({ caseId: Id, stageId: Id }),
    requireTenant: true,
    permission: "cases.read",
  },
  async ({ caseId, stageId }, { db, auth }) => {
    const moved = await db.cases.move({ caseId, to: { stageId } });

    if (!moved.ok) {
      return moved;
    }

    await refreshCaller(auth);

    return ok({ id: moved.data.id });
  },
);

/** Closes a case; the database refuses while a blocker remains. */
export const closeCase = bsb.action(
  {
    input: v.object({
      caseId: Id,
      note: v.optional(v.pipe(v.string(), v.maxLength(4000))),
    }),
    requireTenant: true,
    permission: "cases.read",
  },
  async ({ caseId, note }, { db, auth }) => {
    const closed = await db.cases.close({ caseId, note });

    if (!closed.ok) {
      return closed;
    }

    await refreshCaller(auth);

    return ok({ id: closed.data.id, number: closed.data.number });
  },
);
