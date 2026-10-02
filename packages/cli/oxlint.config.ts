import { defineConfig } from "oxlint";

import {
  core,
  ignorePatterns,
  library,
  node,
  test,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, library, test],
  ignorePatterns,
  rules: {
    // Introspection and doctor read catalog rows, config.toml and splinter
    // JSON as untyped data. Findings when measured, tests included:
    // no-runtime-typeof 51, no-unsafe-dictionary-type 36,
    // no-unknown-parameters 30, no-known-value-widening 17 and
    // no-unknown-returns 10. Backlog in docs/decisions/0002.
    "anti-slop/no-runtime-typeof": "off",
    "anti-slop/no-unsafe-dictionary-type": "off",
    "anti-slop/no-unknown-parameters": "off",
    "anti-slop/no-known-value-widening": "off",
    "anti-slop/no-unknown-returns": "off",
    // exactOptionalPropertyTypes forbids `key: undefined`, and these spreads
    // are how an absent option stays absent; 72 findings when measured.
    "anti-slop/no-conditional-empty-object-spread": "off",
  },
  overrides: [
    {
      // The CLI reads its environment: DATABASE_URL, SUPABASE_BIN and CI.
      files: ["src/run.ts", "src/bin.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
