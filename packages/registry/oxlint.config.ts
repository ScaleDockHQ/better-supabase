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
  ],
});
