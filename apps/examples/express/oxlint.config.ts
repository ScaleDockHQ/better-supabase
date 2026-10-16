import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, settings } from "../../../oxlint.config.ts";

export default defineConfig({
  extends: [root],
  settings,
  ignorePatterns,
  overrides: [
    {
      // Examples read env where they create the client, the way the
      // generated templates do, so they stay copyable.
      files: ["**/*.{ts,tsx}"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // Express 5 passes a rejected handler promise to the error handler,
      // which this rule predates (2 findings, the async routes in app.ts).
      files: ["src/app.ts"],
      rules: { "oxc/no-async-endpoint-handlers": "off" },
    },
  ],
});
