import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, settings } from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root],
  settings,
  ignorePatterns,
  overrides: [
    {
      // The tests read SUPABASE_DB_URL, as the package's integration tests do.
      files: ["**/*.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
