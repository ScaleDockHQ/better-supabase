import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, settings } from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root],
  settings,
  ignorePatterns,
});
