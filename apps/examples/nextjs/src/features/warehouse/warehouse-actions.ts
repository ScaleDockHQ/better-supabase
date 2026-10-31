"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/** Finishes a pick list: lines with less picked than asked for become short. */
export const completePickList = bsb.action(
  {
    input: v.object({ pickListId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "warehouse.pick",
  },
  async ({ pickListId }, { db }) => {
    const done = await db.warehouse.completePickList(pickListId);

    return done.ok ? ok({ status: done.data.status }) : done;
  },
);
