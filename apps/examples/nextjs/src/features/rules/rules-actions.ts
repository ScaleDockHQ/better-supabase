"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { tags } from "@/lib/supabase/generated.tags";
import { bsbCore } from "@/lib/supabase/server-core";

/**
 * The editor saves through the browser client; this drops the caller's cached
 * rule list, so the next page shows the change.
 */
export const rulesChanged = bsbCore.action(
  { input: v.object({}), requireTenant: true },
  async (_input, { auth }) => {
    await refreshCaller(auth, [tags.rules()]);

    return ok(null);
  },
);

// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryRules() {
  refresh();
}
