import { defineConfig } from "oxlint";

import {
  core,
  node,
  test,
  ignorePatterns,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, test],
  ignorePatterns: [
    ...ignorePatterns,
    "**/*.generated.ts",
    "**/generated.ts",
    "**/generated.meta.*",
    "**/generated-*.ts",
    "**/database.types.ts",
  ],
});
