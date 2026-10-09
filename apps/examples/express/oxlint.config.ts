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
  overrides: [
    {
      // Examples read env where they create the client, the way the
      // generated templates do, so they stay copyable.
      files: ["**/*.{ts,tsx}"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // Express 5 passes a rejected handler promise to the error handler,
      // which this rule predates (2 findings, the async routes in app.ts).
      files: ["src/app.ts"],
      rules: { "oxc/no-async-endpoint-handlers": "off" },
    },
  ],
});
