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
    "**/generated-*.ts",
    "**/database.types.ts",
  ],
  overrides: [
    {
      // Ported app code reads its env where it creates the client, as
      // the production apps it came from do.
      files: ["**/*.{ts,tsx}"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
