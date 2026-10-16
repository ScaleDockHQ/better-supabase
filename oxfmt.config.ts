import { type OxfmtConfig, defineConfig } from "oxfmt";
import ultracite from "ultracite/oxfmt";

import { ignorePatterns } from "./oxlint.config.ts";

const config: OxfmtConfig = defineConfig({
  ...ultracite,
  trailingComma: "all",
  // Ultracite's "never" would rewrap every Markdown and MDX file.
  proseWrap: "preserve",
  ignorePatterns: [
    ...ignorePatterns,
    "packages/better-supabase/tests/fixtures/generated*",
    "apps/examples/**/lib/supabase/generated.*",
    "apps/examples/monorepo/runtime/src/generated.*",
    "tests/validation-*/src/**/generated.*",
    "packages/better-supabase/api/**",
    "packages/better-supabase/tests/standards/schemas/**",
    "packages/better-supabase/src/cli/spec/schemas/**",
    "apps/marketing/components/ui/**",
    "apps/marketing/components/reui/**",
    "apps/marketing/public/r/**",
    "CHANGELOG.md",
  ],
  sortImports: {
    internalPattern: ["@/", "@better-supabase/"],
    groups: [
      "type-import",
      ["value-builtin", "value-external"],
      "type-internal",
      "value-internal",
      ["type-parent", "type-sibling", "type-index"],
      ["value-parent", "value-sibling", "value-index"],
      "unknown",
    ],
  },
  sortPackageJson: { sortScripts: true },
});

export default config;
