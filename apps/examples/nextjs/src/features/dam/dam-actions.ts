"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/** Revokes a usage right. It stays in the history as revoked. */
export const revokeUsageRight = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "dam.write",
  },
  async ({ id }, { db }) => {
    const revoked = await db.dam.revokeRight(id);

    return revoked.ok ? ok({ id: revoked.data.id }) : revoked;
  },
);
