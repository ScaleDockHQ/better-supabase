"use server";

import type {
  ActionResult,
  ExistingAccount,
  SignedIn,
} from "better-supabase/next";

import { dbError, err } from "better-supabase";
import { botIdCheck } from "better-supabase/vercel-security";
import { checkBotId } from "botid/server";
import { hasLocale } from "next-intl";
import { headers } from "next/headers";

import { localizedPath, routing } from "@/i18n/routing";
import { bsbCore } from "@/lib/supabase/server-core";

const botCheck = botIdCheck({ checkBotId });

function homeOf(locale: string): string {
  // A literal `/en` would teach the client's route predictor that the first
  // path segment is the locale, so `/my-work` would prefetch the root page
  // (EX-1511); `localizedPath` leaves the default locale unprefixed.
  return localizedPath(
    hasLocale(routing.locales, locale) ? locale : routing.defaultLocale,
    "/",
  );
}

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
    { fallback: homeOf(input.locale) },
  );
}

/**
 * Signs up on the server once BotID's verdict says a person sent the form (the
 * sign-up form starts BotID for this POST). `full_name` goes to
 * `raw_user_meta_data`, which the profiles module copies into the profile. The
 * confirmation link lands on `/api/auth/callback`, which exchanges its code.
 */
export async function signUp(input: {
  readonly email: string;
  readonly password: string;
  readonly fullName: string;
  readonly locale: string;
}): Promise<ActionResult<SignedIn | ExistingAccount | null>> {
  const blocked = await botCheck();

  if (blocked) {
    return err(blocked);
  }

  const origin = (await headers()).get("origin");

  if (origin === null) {
    return err(dbError("invalid_input", "The request has no origin"));
  }

  const home = homeOf(input.locale);

  return bsbCore.signUp(
    {
      email: input.email,
      password: input.password,
      data: { full_name: input.fullName },
      redirectTo: `${origin}/api/auth/callback`,
      next: home,
    },
    { fallback: home },
  );
}
