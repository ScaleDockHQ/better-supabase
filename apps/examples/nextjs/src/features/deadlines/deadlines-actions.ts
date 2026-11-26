"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Records that the action a deadline asks for was taken. */
export const satisfyDeadline = bsb.blockAction(
  ({ db }) => db.deadlines,
  "satisfy",
  {
    input: v.object({ deadlineId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "deadlines.write",
    tags: () => [tags.deadlines()],
    refresh: true,
  },
  (satisfied) => ({ state: satisfied.state }),
);
