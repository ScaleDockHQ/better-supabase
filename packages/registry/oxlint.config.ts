import { defineConfig } from "oxlint";

import {
  core,
  ignorePatterns,
  node,
  react,
  test,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, react, test],
  ignorePatterns: [...ignorePatterns],
  overrides: [
    {
      // Items are copied into apps, which read env where they create a
      // client, the way the generated templates do.
      // Turbo never runs them, so their keys belong in the app's turbo.json,
      // not this one (10 findings when measured).
      files: ["items/**/*.ts", "stubs/**/*.ts"],
      rules: {
        "node/no-process-env": "off",
        "turbo/no-undeclared-env-vars": "off",
      },
    },
  ],
});
