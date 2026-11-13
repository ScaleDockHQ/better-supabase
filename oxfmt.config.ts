import type { OxfmtConfig } from "oxfmt";

import { defineConfig } from "oxfmt";
import ultracite from "ultracite/oxfmt";

import { ignorePatterns } from "./oxlint.config.ts";

/** Each Tailwind app sorts classes against its own theme and utilities. */
function tailwindApp(
  files: string,
  stylesheet: string,
): NonNullable<OxfmtConfig["overrides"]>[number] {
  return { files: [files], options: { sortTailwindcss: { stylesheet } } };
}

const config: OxfmtConfig = defineConfig({
  ...ultracite,
  trailingComma: "all",
  // Ultracite's "never" would rewrap every Markdown and MDX file.
  proseWrap: "preserve",
  jsdoc: true,
  // An object literal that fits on one line goes on one line, whatever the
  // source wrote.
  objectWrap: "collapse",
  ignorePatterns: [
    ...ignorePatterns,
    "packages/better-supabase/tests/fixtures/generated*",
    "apps/examples/**/lib/supabase/generated.*",
    // `gen --check` compares the file with its own unformatted output, and the
    // wrapped comment of a longer block list differs from the formatted one.
    "apps/examples/nextjs/src/lib/supabase/blocks.api.ts",
    "apps/examples/monorepo/runtime/src/generated.*",
    "tests/validation-*/src/**/generated.*",
    // `gen --check` compares the file with its own unformatted output.
    "tests/types/**/blocks.config.ts",
    "apps/examples/**/lib/supabase/blocks.config.ts",
    "apps/examples/**/lib/supabase/blocks/*.ts",
    "apps/examples/**/lib/supabase/blocks.{core,shell}.ts",
    "tests/validation-*/src/blocks.config.ts",
    "tests/validation-*/src/wiring/*.blocks.config.ts",
    "packages/registry/stubs/lib/supabase/blocks.config.ts",
    // `introspect --check` compares the file byte for byte with its own output.
    "supabase/snapshot.json",
    // `catalog:check` compares it with `formatNameRegistry` byte for byte.
    "packages/better-supabase/src/blocks/name-registry.generated.ts",
    "packages/better-supabase/src/blocks/hint-codes.generated.ts",
    "packages/better-supabase/src/blocks/messages/hint-messages.generated.ts",
    // `recipes:check` compares it with the example sources, whose Tailwind
    // classes sort against the app's stylesheet, which this path can't see.
    "packages/better-supabase/skills/better-supabase/references/ui-recipes.md",
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
  overrides: [
    {
      // Generators write these with JSON.stringify, and their checks compare
      // the bytes.
      files: ["**/*.{json,jsonc,json5}"],
      options: { objectWrap: "preserve" },
    },
    tailwindApp("apps/docs/**", "./apps/docs/app/global.css"),
    tailwindApp("apps/marketing/**", "./apps/marketing/app/globals.css"),
    tailwindApp(
      "apps/examples/nextjs/**",
      "./apps/examples/nextjs/src/app/globals.css",
    ),
  ],
});

export default config;
