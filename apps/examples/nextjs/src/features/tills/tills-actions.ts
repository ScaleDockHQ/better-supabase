"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/** Adds a euro till without a cash account, so it books nothing in accounting. */
export const createTill = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.minLength(1), v.maxLength(100)),
    }),
    requireTenant: true,
    permission: "tills.manage",
  },
  async ({ name }, { db }) => {
    const till = await db.tills.createTill({ name, currency: "EUR" });

    return till.ok ? ok({ id: till.data.id }) : till;
  },
);
