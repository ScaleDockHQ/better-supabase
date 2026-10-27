import { getProviderData } from "better-supabase/flags-sdk";
import { createFlagsDiscoveryEndpoint } from "flags/next";

import { betaPage, bsFlags, pricingBanner, signupWaitlist } from "@/flags";

/**
 * Flags Explorer's discovery endpoint. It answers only requests signed with
 * FLAGS_SECRET (`verifyAccess`), and lists the declared flags joined with every
 * flag in the flags module, including ones no code declares yet.
 */
export const GET = createFlagsDiscoveryEndpoint(() =>
  getProviderData(bsFlags, {
    flags: { betaPage, pricingBanner, signupWaitlist },
  }),
);
