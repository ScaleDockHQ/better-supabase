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
    "components/ui/**",
    "components/reui/**",
  ],
  overrides: [
    {
      // Base UI buttons with `render={<a />}` take their label from the
      // children at runtime, which the rule cannot see (11 findings).
      files: ["**/*.tsx"],
      rules: { "jsx-a11y/control-has-associated-label": "off" },
    },
    {
      // env.ts is the app's only reader of process.env.
      files: ["env.ts"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // next/og renders with Satori, which only reads inline styles.
      files: ["app/icon.tsx", "lib/og.tsx"],
      rules: { "shadcn/no-inline-styles": "off" },
    },
  ],
});
