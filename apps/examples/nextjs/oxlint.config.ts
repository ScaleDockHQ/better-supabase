import { defineConfig } from "oxlint";

import {
  core,
  node,
  react,
  shadcn,
  test,
  ignorePatterns,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, react, shadcn, test],
  ignorePatterns: [
    ...ignorePatterns,
    "**/*.generated.ts",
    "**/generated.ts",
    "**/generated.meta.*",
    "**/generated-*.ts",
    "**/database.types.ts",
    // Copied from the shadcn registry by `shadcn add`.
    "src/components/ui/**",
    "src/hooks/use-mobile.ts",
  ],
  overrides: [
    {
      // Examples read env where they create the client, the way the
      // generated templates do, so they stay copyable.
      files: ["**/*.{ts,tsx}"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // Relation counts and aggregates are part of the repository API.
      files: ["**/*.{ts,tsx}"],
      rules: {
        "no-underscore-dangle": [
          "error",
          { allow: ["_count", "_sum", "_avg", "_min", "_max"] },
        ],
      },
    },
  ],
});
