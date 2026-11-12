"use server";

import type { ActionResult, SignedIn } from "better-supabase/next";

import { hasLocale } from "next-intl";

import { localizedPath, routing } from "@/i18n/routing";
import { bsbCore } from "@/lib/supabase/server-core";

/**
 * Signs in on the server: one Auth call, the session cookies on this response,
 * and the verified session stored for the next render.
 */
export async function signInWithPassword(input: {
  readonly email: string;
  readonly password: string;
  readonly next: string | null;
  readonly locale: string;
}): Promise<ActionResult<SignedIn>> {
  return bsbCore.signInWithPassword(
    { email: input.email, password: input.password, next: input.next },
    {
      // A literal `/en` would teach the client's route predictor that the first
      // path segment is the locale, so `/my-work` would prefetch the root page
      // (EX-1511); `localizedPath` leaves the default locale unprefixed.
      fallback: localizedPath(
        hasLocale(routing.locales, input.locale)
          ? input.locale
          : routing.defaultLocale,
        "/",
      ),
    },
  );
}
