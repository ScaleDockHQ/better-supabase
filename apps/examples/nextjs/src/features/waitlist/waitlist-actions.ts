"use server";

import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

/**
 * Adds an address to the waitlist, or returns its place when it is already
 * there. `api.join_waitlist` is granted to `anon`, so this works signed out.
 */
export const joinWaitlist = bsb.blockAction(
  ({ db }) => db.waitlist,
  "join",
  {
    input: v.object({
      email: v.pipe(v.string(), v.trim(), v.email(), v.maxLength(320)),
    }),
    allow: ["none", "user"],
    args: ({ email }) => [
      { email: email.toLowerCase(), referrer: "waitlist-page" },
    ],
  },
  (joined) => ({ position: joined.position ?? null, status: joined.status }),
);
