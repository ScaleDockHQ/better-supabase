import { type OxfmtConfig, defineConfig } from "oxfmt";
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
    "apps/examples/monorepo/runtime/src/generated.*",
    "tests/validation-*/src/**/generated.*",
    // `introspect --check` compares the file byte for byte with its own output.
    "supabase/snapshot.json",
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
