"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/**
 * Adds an address to the waitlist, or returns its place when it is already
 * there. `api.join_waitlist` is granted to `anon`, so this works signed out.
 */
export const joinWaitlist = bsb.action(
  {
    input: v.object({
      email: v.pipe(v.string(), v.trim(), v.email(), v.maxLength(320)),
    }),
    allow: ["none", "user"],
  },
  async ({ email }, { db }) => {
    const joined = await db.waitlist.join(email.toLowerCase(), {
      referrer: "waitlist-page",
    });

    if (!joined.ok) {
      return joined;
    }

    return ok({
      position: joined.data.position ?? null,
      status: joined.data.status,
    });
  },
);
