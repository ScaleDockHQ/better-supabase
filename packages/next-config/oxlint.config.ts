import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, {
  ignorePatterns,
  library,
  settings,
} from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root, library],
  settings,
  ignorePatterns,
  overrides: [
    {
      // Build-time switches for CI and the e2e suite, read while Next loads the config.
      files: ["src/next-config.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
