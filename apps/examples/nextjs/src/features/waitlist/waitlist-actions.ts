"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/**
 * Adds an address to the waitlist, or returns its place when it is already
 * there. `api.join_waitlist` is granted to `anon`, so this works signed out.
 */
export const joinWaitlist = bs.action(
  {
    input: v.object({
      email: v.pipe(v.string(), v.trim(), v.email(), v.maxLength(320)),
    }),
    allow: ["anon", "user"],
  },
  async ({ email }, { supabase }) => {
    const joined = await blocks(supabase).waitlist.join(email.toLowerCase(), {
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
