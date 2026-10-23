import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, react, settings } from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root, react],
  settings,
  ignorePatterns,
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
    {
      // The block hooks moved here from the library, which turns these rules
      // off for the same code (see its oxlint config and ADR 0002): they read
      // block settings as dictionaries and keep absent options absent under
      // exactOptionalPropertyTypes. Their tests replace React with a loose
      // stand-in. 88 findings in items/hooks and 100 in the tests when
      // measured.
      files: [
        "items/hooks/**/*.ts",
        "tests/hooks/**/*.ts",
        "tests/fixtures/**/*.ts",
      ],
      rules: {
        "anti-slop/no-conditional-empty-object-spread": "off",
        "anti-slop/no-known-value-widening": "off",
        "anti-slop/no-object-parameters": "off",
        "anti-slop/no-runtime-typeof": "off",
        "anti-slop/no-unknown-parameters": "off",
        "anti-slop/no-unknown-returns": "off",
        "anti-slop/no-unsafe-dictionary-type": "off",
      },
    },
  ],
});
