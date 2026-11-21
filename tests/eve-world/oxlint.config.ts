import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, settings } from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root],
  settings,
  ignorePatterns,
  overrides: [
    {
      // The tests read SUPABASE_DB_URL, as the package's integration tests do.
      files: ["**/*.ts"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // The harness is a private fixture that parses eve's untyped stream lines and builds one
      // process environment. Findings when this was written: no-unsafe-dictionary-type 5,
      // no-conditional-empty-object-spread 6, no-runtime-typeof 4, no-known-value-widening 2,
      // require-readable-spacing 15, no-explicit-any 1, no-unsafe-argument 1,
      // no-unsafe-assignment 2, no-unsafe-member-access 3, require-await 1.
      files: ["**/*.ts"],
      rules: {
        "anti-slop/no-unsafe-dictionary-type": "off",
        "anti-slop/no-conditional-empty-object-spread": "off",
        "anti-slop/no-runtime-typeof": "off",
        "anti-slop/no-known-value-widening": "off",
        "anti-slop/require-readable-spacing": "off",
        "typescript/no-explicit-any": "off",
        "typescript/no-unsafe-argument": "off",
        "typescript/no-unsafe-assignment": "off",
        "typescript/no-unsafe-member-access": "off",
        "typescript/require-await": "off",
      },
    },
    {
      // eve names a tool after its file, so `delete_record.ts` cannot be kebab-case (1 finding),
      // and the fixture tools take zod schemas, as eve's own tools do (2 findings).
      files: ["agent/tools/*.ts"],
      rules: {
        "unicorn/filename-case": "off",
        "eslint/no-restricted-imports": "off",
      },
    },
  ],
});
