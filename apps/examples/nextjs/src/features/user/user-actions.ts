"use server";

import { dbError, err } from "better-supabase";
import { refresh } from "next/cache";

import { next } from "@/lib/supabase.server";

/**
 * Call after the browser client signs in or out. `refresh()` from a Server
 * Action clears the client router cache, including every private session
 * read, so the next render sees the new user.
 */
export async function sessionChanged(): Promise<void> {
  refresh();
}

/**
 * Deletes the signed-in user and their cached session; notifications cascade.
 * Customer logos belong to the organization, so no bucket is cleared. Needs
 * a verified second factor in this session.
 */
export const deleteMyAccount = next.action(
  { aal: "aal2" },
  async (_input, { auth }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to delete your account"));
    }
    return next.deleteAccount(auth.user.id, { cascades: ["notifications"] });
  },
);
