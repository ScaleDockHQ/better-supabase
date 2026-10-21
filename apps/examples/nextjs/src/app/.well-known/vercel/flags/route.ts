import { getProviderData } from "better-supabase/flags-sdk";
import { mergeProviderData } from "flags";
import {
  createFlagsDiscoveryEndpoint,
  getProviderData as getDeclaredFlags,
} from "flags/next";

import { betaPage, bsFlags, pricingBanner } from "@/flags";

/**
 * Flags Explorer's discovery endpoint. It answers only requests signed with
 * FLAGS_SECRET (`verifyAccess`), and lists the declared flags merged with every
 * flag in the flags module, including ones no code declares yet.
 */
// SAFETY: flags 4.3 types a declared flag's `origin` as `... | undefined`,
// which `exactOptionalPropertyTypes` rejects for `KeyedFlagDefinitionType`;
// getProviderData reads it as optional.
const declared = { betaPage, pricingBanner } as Parameters<
  typeof getDeclaredFlags
>[0];

export const GET = createFlagsDiscoveryEndpoint(async () =>
  mergeProviderData([
    getDeclaredFlags(declared),
    await getProviderData(bsFlags),
  ]),
);
