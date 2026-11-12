"use server";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { SUPPORT_TAG } from "./support-cache";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Asks for a read-only support session on a user. A second platform admin
 * approves it before the session can start.
 */
export const requestSupportSession = bsb.action(
  {
    input: v.object({
      target: Id,
      reason: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500)),
    }),
    permission: "impersonation.start",
  },
  async ({ target, reason }, { db, auth }) => {
    const response = await db.$client
      .schema("api")
      .rpc("request_support_session", { target, reason, read_only: true });

    if (response.error) {
      return err(dbError("forbidden", response.error.message));
    }

    await refreshCaller(auth, [SUPPORT_TAG]);

    return ok(target);
  },
);

/** Ends a support session before it expires. */
export const endSupportSession = bsb.action(
  { input: v.object({ sessionId: Id }), permission: "impersonation.revoke" },
  async ({ sessionId }, { db, auth }) => {
    const response = await db.$client
      .schema("api")
      .rpc("end_support_session", { session_id: sessionId });

    if (response.error) {
      return err(dbError("forbidden", response.error.message));
    }

    await refreshCaller(auth, [SUPPORT_TAG]);

    return ok(sessionId);
  },
);
