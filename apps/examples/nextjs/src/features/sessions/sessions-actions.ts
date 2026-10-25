"use server";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

/**
 * Ends one of the caller's sessions on another device. Its refresh token stops
 * working at once; its access token lasts until it expires.
 */
export const endSession = bsb.action(
  { input: v.object({ id: v.pipe(v.string(), v.uuid()) }) },
  async ({ id }, { db, auth }) => {
    const ended = await db.$api("end_my_session", { session: id });

    if (!ended.ok) {
      return ended;
    }

    if (ended.data !== true) {
      return err(dbError("not_found", "Session not found"));
    }

    refreshCaller(auth);

    return ok(true);
  },
);
