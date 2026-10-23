"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

/**
 * The editor saves through the browser client; this drops the caller's cached
 * rule list, so the next page shows the change.
 */
export const rulesChanged = bsb.action(
  { input: v.object({}), requireOrganization: true },
  // oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refreshCaller() returns nothing to await
  async (_input, { auth }) => {
    refreshCaller(auth);

    return ok(null);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryRules() {
  refresh();
}
