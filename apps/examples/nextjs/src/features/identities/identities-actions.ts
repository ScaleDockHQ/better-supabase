"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { IDENTITIES_TAG } from "./identities-cache";

/**
 * Issues a one-time code. Sending it to the app's chat bot links that chat
 * account to this user.
 */
export const beginChatLink = bsb.action(
  {
    input: v.object({
      provider: v.picklist(["slack", "whatsapp", "telegram"]),
    }),
  },
  async ({ provider }, { db }) => {
    const issued = await db.$blocks.identities.beginLink({
      kind: "chat",
      provider,
    });

    if (!issued.ok) {
      return issued;
    }

    return ok({
      code: issued.data.code,
      expiresAt: issued.data.expiresAt.toString(),
    });
  },
);

/** Removes a linked identity. */
export const unlinkIdentity = bsb.action(
  { input: v.object({ id: v.pipe(v.string(), v.uuid()) }) },
  async ({ id }, { db, auth }) => {
    const unlinked = await db.$blocks.identities.unlink(id);

    if (!unlinked.ok) {
      return unlinked;
    }

    await refreshCaller(auth, [IDENTITIES_TAG]);

    return ok(unlinked.data);
  },
);
