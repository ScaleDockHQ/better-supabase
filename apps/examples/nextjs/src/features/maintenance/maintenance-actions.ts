"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/** Opens a dispatch work order for every plan that is due. */
export const generateWorkOrders = bsb.action(
  {
    input: v.object({}),
    requireTenant: true,
    permission: "maintenance.manage",
  },
  async (_input, { db }) => {
    const opened = await db.maintenance.generateWorkOrders();

    return opened.ok ? ok({ opened: opened.data.length }) : opened;
  },
);
