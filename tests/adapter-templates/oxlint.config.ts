import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, settings } from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root],
  settings,
  ignorePatterns,
  rules: {
    // An adapter decodes a provider's JSON without a schema dependency, so its
    // decoders take `unknown` and branch on `typeof`, and an absent option
    // stays absent through a conditional spread (exactOptionalPropertyTypes).
    // Findings when measured: no-conditional-empty-object-spread 21,
    // no-runtime-typeof 8, no-unknown-parameters 5, no-unsafe-dictionary-type 1,
    // no-known-value-widening 1. Same reason as packages/better-supabase.
    "anti-slop/no-conditional-empty-object-spread": "off",
    "anti-slop/no-runtime-typeof": "off",
    "anti-slop/no-unknown-parameters": "off",
    "anti-slop/no-unsafe-dictionary-type": "off",
    "anti-slop/no-known-value-widening": "off",
  },
});
