"use server";

import type { ActionResult, SignedIn } from "better-supabase/next";

import { hasLocale } from "next-intl";

import { routing } from "@/i18n/routing";
import { bsb } from "@/lib/supabase/server";

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
  return bsb.signInWithPassword(
    { email: input.email, password: input.password, next: input.next },
    {
      fallback: `/${hasLocale(routing.locales, input.locale) ? input.locale : routing.defaultLocale}`,
    },
  );
}
