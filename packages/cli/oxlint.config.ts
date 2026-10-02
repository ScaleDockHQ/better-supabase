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
  overrides: [
    {
      // The CLI reads its environment: DATABASE_URL, SUPABASE_BIN and CI.
      files: ["src/run.ts", "src/bin.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
