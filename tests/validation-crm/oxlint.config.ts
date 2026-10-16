import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, settings } from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root],
  settings,
  ignorePatterns,
  overrides: [
    {
      // Ported app code reads its env where it creates the client, as
      // the production apps it came from do.
      files: ["**/*.{ts,tsx}"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
