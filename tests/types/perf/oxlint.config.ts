import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, settings } from "../../../oxlint.config.ts";

export default defineConfig({
  extends: [root],
  settings,
  ignorePatterns,
  overrides: [
    {
      // BENCH_UPDATE switches the benchmark to rewriting its baseline.
      files: ["bench.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
