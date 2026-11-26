"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Records that the action a deadline asks for was taken. */
export const satisfyDeadline = bsb.action(
  {
    input: v.object({ deadlineId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "deadlines.write",
    tags: () => [tags.deadlines()],
    refresh: true,
  },
  async ({ deadlineId }, { db }) => {
    const satisfied = await db.deadlines.satisfy({ deadlineId });

    if (!satisfied.ok) {
      return satisfied;
    }

    return ok({ state: satisfied.data.state });
  },
);
