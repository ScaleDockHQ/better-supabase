import { defineConfig } from "oxlint";

import { core, ignorePatterns, node } from "@better-supabase/ox-config/oxlint";

// Root tooling only. Each workspace lints itself with its own
// oxlint.config.ts, which oxlint also picks up for staged files.
export default defineConfig({
  extends: [core, node],
  ignorePatterns: [...ignorePatterns, ".agents/**", ".cursor/**", ".claude/**"],
  overrides: [
    {
      // Config files are loaded through their default export.
      files: ["*.config.ts", "knip.mts"],
      rules: {
        "import/no-default-export": "off",
      },
    },
    {
      // Repo scripts are the env boundary for CI flags and stack URLs.
      files: ["scripts/**"],
      rules: {
        "node/no-process-env": "off",
      },
    },
  ],
});
