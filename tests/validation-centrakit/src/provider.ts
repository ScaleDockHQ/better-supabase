import type { AuthorizationProvider } from "better-supabase/config";

import { readFileSync } from "node:fs";

/**
 * CentraKit's authorization provider, read from the frozen snapshot of its
 * output. The README says where the snapshot comes from and how to refresh it.
 */
export function centrakitProvider(): AuthorizationProvider {
  // SAFETY: the snapshot is the provider's own output for API 1; resolveConfig
  // checks its apiVersion and doctor validates the rest.
  return JSON.parse(
    readFileSync(
      new URL("../authorization-provider.json", import.meta.url),
      "utf-8",
    ),
  ) as AuthorizationProvider;
}
