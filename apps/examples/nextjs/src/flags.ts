import type { FlagsSdkEntities } from "better-supabase/flags-sdk";

import { createClient } from "@supabase/supabase-js";
import { rpcTransport } from "better-supabase/blocks";
import {
  betterSupabaseAdapter,
  createIdentify,
} from "better-supabase/flags-sdk";
import { toSession } from "better-supabase/next";
import { dedupe, flag } from "flags/next";

import { env } from "@/env";
import "server-only";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

/**
 * `flag_definitions()` lists every override, so only the service role may call
 * it. Without the secret key every flag answers its `defaultValue`.
 */
function definitionsSource() {
  const url = env.NEXT_PUBLIC_SUPABASE_URL;
  const key = env.SUPABASE_SECRET_KEY;

  if (!url || !key) {
    return { definitions: [] };
  }

  const service = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return { transport: rpcTransport(service), schema: blockConfig.flags.api };
}

/** One provider for every flag: the definitions load once per 30 seconds. */
export const bsFlags = betterSupabaseAdapter(definitionsSource());

/**
 * The user, the active organization with its plans and roles, read from the
 * token in the cookie. The token is verified locally, so this never calls the
 * Auth server, in the proxy or in a page.
 */
const identify = dedupe(
  createIdentify({
    claims: async ({ headers }) => {
      const cookie = headers.get("cookie");

      if (!cookie) {
        return null;
      }

      const { auth } = await bsb.context(
        new Request("https://flags.invalid/", { headers: { cookie } }),
      );

      const session = toSession(auth);

      return session.kind === "user" ? session.claims : null;
    },
  }),
);

/**
 * A precomputed flag: the proxy evaluates it and the pricing page reads the
 * result from its `[code]` segment, so the page stays static. Target it by plan
 * with a `plans` rule on `pricing-banner`.
 */
export const pricingBanner = flag<boolean, FlagsSdkEntities>({
  key: "pricing-banner",
  description: "The upgrade banner on the pricing page",
  adapter: bsFlags(),
  defaultValue: false,
  options: [
    { value: false, label: "off" },
    { value: true, label: "on" },
  ],
  identify,
});

/**
 * A dynamic flag, read in a page at request time. It is the same flag the beta
 * page checks through `flag_enabled`, so both answer alike.
 */
export const betaPage = flag<boolean, FlagsSdkEntities>({
  key: "beta-page",
  description: "The beta page and its menu entry",
  adapter: bsFlags(),
  defaultValue: false,
  identify,
});

/** The flags the proxy precomputes for the pricing page. */
export const pricingFlags = [pricingBanner] as const;
