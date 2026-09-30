import { defineConfig } from "oxlint";

import {
  core,
  ignorePatterns,
  library,
  node,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, library],
  ignorePatterns: [...ignorePatterns],
  overrides: [
    {
      // Build-time switches for CI and the e2e suite, read while Next loads the config.
      files: ["src/next-config.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
