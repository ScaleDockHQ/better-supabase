"use server";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

/**
 * Ends one of the caller's sessions on another device. Its refresh token stops
 * working at once; its access token lasts until it expires.
 */
export const endSession = bs.action(
  { input: v.object({ id: v.pipe(v.string(), v.uuid()) }) },
  async ({ id }, { supabase, auth }) => {
    const ended = await blocks(supabase).call("end_my_session", {
      session: id,
    });

    if (ended !== true) {
      return err(dbError("not_found", "Session not found"));
    }

    refreshCaller(auth);

    return ok(true);
  },
);
