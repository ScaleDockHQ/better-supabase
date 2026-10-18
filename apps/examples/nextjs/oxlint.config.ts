import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, {
  ignorePatterns,
  next,
  react,
  shadcn,
  settings,
} from "../../../oxlint.config.ts";

export default defineConfig({
  extends: [root, react, next, shadcn],
  settings,
  ignorePatterns: [
    ...ignorePatterns,
    // Copied from the shadcn and ReUI registries by `shadcn add`.
    "src/components/ui/**",
    "src/components/reui/**",
    "src/hooks/use-mobile.ts",
    // Served as is. push-sw.js runs in a service worker, which the app's
    // DOM-typed tsconfig can't type.
    "public/**",
  ],
  overrides: [
    {
      // Examples read env where they create the client, the way the
      // generated templates do, so they stay copyable.
      files: ["**/*.{ts,tsx}"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // Relation counts and aggregates are part of the repository API.
      files: ["**/*.{ts,tsx}"],
      rules: {
        "no-underscore-dangle": [
          "error",
          { allow: ["_count", "_sum", "_avg", "_min", "_max"] },
        ],
      },
    },
  ],
});
