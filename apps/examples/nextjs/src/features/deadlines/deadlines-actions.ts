"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { DEADLINES_TAG } from "./deadlines-cache";

/** Records that the action a deadline asks for was taken. */
export const satisfyDeadline = bsb.action(
  {
    input: v.object({ deadlineId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "deadlines.write",
  },
  async ({ deadlineId }, { db, auth }) => {
    const satisfied = await db.deadlines.satisfy({ deadlineId });

    if (!satisfied.ok) {
      return satisfied;
    }

    await refreshCaller(auth, [DEADLINES_TAG]);

    return ok({ state: satisfied.data.state });
  },
);
