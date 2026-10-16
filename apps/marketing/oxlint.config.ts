import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, {
  ignorePatterns,
  next,
  react,
  shadcn,
  settings,
} from "../../oxlint.config.ts";

export default defineConfig({
  extends: [root, react, next, shadcn],
  settings,
  ignorePatterns: [...ignorePatterns, "components/ui/**", "components/reui/**"],
  overrides: [
    {
      // env.ts is the app's only reader of process.env.
      files: ["env.ts"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // next/og renders with Satori, which only reads inline styles.
      files: ["app/icon.tsx", "lib/og.tsx"],
      rules: { "shadcn/no-inline-styles": "off" },
    },
  ],
});
