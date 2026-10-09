"use server";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { bs } from "@/lib/supabase/server";

import { durable, durableContext } from "./durable-server";

/**
 * Decides an approval from the activity console. The turn continues in its
 * workflow once none of its approvals is pending; the chat page picks up
 * the answer when it opens.
 */
export const decideApproval = bs.action(
  {
    input: v.object({
      chatId: v.pipe(v.string(), v.uuid()),
      approvalId: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
      approved: v.boolean(),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "ai_chat.create"),
  },
  async ({ chatId, approvalId, approved }, { tenant, auth, supabase }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to decide approvals"));
    }
    const response = await durable().decide(
      chatId,
      [{ approvalId, approved }],
      durableContext(supabase, auth.user.id, tenant),
    );
    if (!response.ok) {
      return err(
        dbError("unexpected", `The approval failed (${response.status})`),
      );
    }
    refresh();
    return ok(approved);
  },
);
