import { defineConfig } from "oxlint";

import {
  core,
  node,
  test,
  ignorePatterns,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, test],
  ignorePatterns,
  overrides: [
    {
      // The tests read SUPABASE_DB_URL, as the package's integration tests do.
      files: ["**/*.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
