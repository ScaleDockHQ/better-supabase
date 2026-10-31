"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/** Registers a sample, which gets the next SMP number. */
export const registerSample = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    permission: "lims.write",
  },
  async ({ title }, { db }) => {
    const sample = await db.lims.registerSample({ title });

    return sample.ok ? ok({ id: sample.data.id }) : sample;
  },
);
