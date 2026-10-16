import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, {
  ignorePatterns,
  react,
  settings,
} from "../../../oxlint.config.ts";

export default defineConfig({
  extends: [root, react],
  settings,
  ignorePatterns,
  overrides: [
    {
      // Examples read env where they create the client, the way the
      // generated templates do, so they stay copyable.
      files: ["**/*.{ts,tsx}"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});
