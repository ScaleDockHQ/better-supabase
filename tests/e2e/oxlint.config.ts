import { defineConfig } from "oxlint";

import {
  core,
  node,
  playwright,
  test,
  ignorePatterns,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, test, playwright],
  ignorePatterns: [
    ...ignorePatterns,
    "**/*.generated.ts",
    "**/generated.ts",
    "**/generated-*.ts",
    "**/database.types.ts",
  ],
  overrides: [
    {
      // The stack config is the suite's env boundary.
      files: ["src/stack-config.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
