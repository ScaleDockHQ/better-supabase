"use server";

import { ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { bsbCore } from "@/lib/supabase/server-core";

import { aiCacheBlock } from "./ai-usage-server";

/**
 * Deletes the organization's cached model calls, so the next answers hit the
 * model.
 */
export const clearAiCache = bsbCore.action(
  { input: v.object({}), requireTenant: true, permission: "ai_chat.manage" },
  async (_input, { tenant }) => {
    const cleared = await aiCacheBlock().clear({ organizationId: tenant });

    if (!cleared.ok) {
      return cleared;
    }

    refresh();

    return ok(cleared.data);
  },
);
