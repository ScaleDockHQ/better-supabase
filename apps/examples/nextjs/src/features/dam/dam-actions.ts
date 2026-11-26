"use server";

import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/** Revokes a usage right. It stays in the history as revoked. */
export const revokeUsageRight = bsb.blockAction(
  ({ db }) => db.dam,
  "revokeRight",
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "dam.write",
    args: ({ id }) => [id],
  },
  (revoked) => ({ id: revoked.id }),
);
