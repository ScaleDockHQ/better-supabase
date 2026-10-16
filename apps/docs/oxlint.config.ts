import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, {
  ignorePatterns,
  next,
  react,
  settings,
} from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root, react, next],
  settings,
  ignorePatterns,
  overrides: [
    {
      // env.ts is the app's only reader of process.env.
      files: ["env.ts"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // It renders outside the root layout, and /llms.txt is a route handler,
      // not a page; plain anchors load them in full (2 findings).
      files: ["app/global-not-found.tsx"],
      rules: { "nextjs/no-html-link-for-pages": "off" },
    },
  ],
});
