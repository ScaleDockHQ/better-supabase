import { defineConfig } from "oxlint";

import {
  core,
  node,
  react,
  test,
  ignorePatterns,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, react, test],
  ignorePatterns: [
    ...ignorePatterns,
    "**/*.generated.ts",
    "**/generated.ts",
    "**/generated.meta.*",
    "**/generated-*.ts",
    "**/database.types.ts",
  ],
  overrides: [
    {
      // env.ts is the app's only reader of process.env.
      files: ["env.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
