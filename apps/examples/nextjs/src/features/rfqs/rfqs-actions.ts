"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/** Creates a draft request, which gets the next RFQ number. */
export const createRfq = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    permission: "rfqs.write",
  },
  async ({ title }, { db }) => {
    const rfq = await db.rfqs.createRfq({ input: { title, currency: "EUR" } });

    return rfq.ok ? ok({ id: rfq.data.id }) : rfq;
  },
);
