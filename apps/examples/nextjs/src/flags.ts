import type { FlagsSdkEntities } from "better-supabase/flags-sdk";

import {
  createBetterSupabaseAdapter,
  createIdentify,
} from "better-supabase/flags-sdk";
import { dedupe, flag } from "flags/next";

import { env } from "@/env";
import "server-only";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

/** A signed-out visitor's stable id, so a percentage rollout keeps its bucket. */
export const VISITOR_COOKIE = "visitor-id";

/**
 * The user, the active organization with its plans and roles, read from the
 * token in the cookie, and the visitor cookie for signed-out requests. The
 * token is verified locally, so this never calls the Auth server.
 */
const identify = dedupe(
  createIdentify({
    server: bsb,
    visitor: ({ cookies }) => cookies.get(VISITOR_COOKIE)?.value,
  }),
);

/**
 * `flag_definitions()` lists every override, so only the service role may call
 * it. Without the secret key every flag answers its `defaultValue`.
 */
export const bsFlags =
  env.NEXT_PUBLIC_SUPABASE_URL && env.SUPABASE_SECRET_KEY
    ? createBetterSupabaseAdapter({
        url: env.NEXT_PUBLIC_SUPABASE_URL,
        secretKey: env.SUPABASE_SECRET_KEY,
        schema: blockConfig.flags.api,
        identify,
      })
    : createBetterSupabaseAdapter({ definitions: [], identify });

const onOff = [
  { value: false, label: "off" },
  { value: true, label: "on" },
];

/**
 * A precomputed flag: the proxy evaluates it and the pricing page reads the
 * result from its `[code]` segment, so the page stays static. Target it by plan
 * with a `plans` rule on `pricing-banner`.
 */
export const pricingBanner = flag<boolean, FlagsSdkEntities>({
  key: "pricing-banner",
  description: "The upgrade banner on the pricing page",
  adapter: bsFlags,
  defaultValue: false,
  options: onOff,
});

/**
 * A dynamic flag, read at request time by the beta page and the sidebar. RLS
 * reads the same flag through `flag_enabled`, so both answer alike.
 */
export const betaPage = flag<boolean, FlagsSdkEntities>({
  key: "beta-page",
  description: "The beta page and its menu entry",
  adapter: bsFlags,
  defaultValue: false,
  options: onOff,
});

/** Read in the proxy: on, `/signup` shows the waitlist instead. */
export const signupWaitlist = flag<boolean, FlagsSdkEntities>({
  key: "signup-waitlist",
  description: "Send sign-ups to the waitlist",
  adapter: bsFlags,
  defaultValue: false,
  options: onOff,
});

/** The flags the proxy precomputes for the pricing page. */
export const pricingFlags = [pricingBanner] as const;

/** The flags the sidebar reads in one batch. */
export const navFlags = { "beta-page": betaPage } as const;
