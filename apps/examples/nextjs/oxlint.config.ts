import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, {
  ignorePatterns,
  next,
  playwright,
  react,
  shadcn,
  settings,
} from "../../../oxlint.config.ts";

export default defineConfig({
  extends: [root, react, next, shadcn, playwright],
  settings,
  ignorePatterns: [
    ...ignorePatterns,
    // Copied from the shadcn and ReUI registries by `shadcn add`.
    "src/components/ui/**",
    "src/components/reui/**",
    "src/lib/highlighter.tsx",
    "src/hooks/use-mobile.ts",
    // Copied from the better-supabase registry; packages/registry lints the
    // items and its tests keep these copies identical.
    "src/hooks/use-*.ts",
    // Served as is. sw.js runs in a service worker, which the app's
    // DOM-typed tsconfig can't type.
    "public/**",
  ],
  jsPlugins: [
    {
      name: "i18n-extract",
      specifier: "../../../scripts/oxlint/i18n-extract.ts",
    },
  ],
  rules: {
    // The message extractor skips a t(...) whose t is a parameter (EX-1602).
    "i18n-extract/no-translator-parameter": "error",
  },
  overrides: [
    {
      // `Route` is the typed-routes union only where `next dev` or `next
      // build` has written `.next/types`; on a clean checkout it is `string`
      // and the cast looks redundant, so `ultracite fix` stripped it and
      // typecheck then failed (1 finding).
      files: ["src/i18n/routing.ts"],
      rules: { "typescript/no-unnecessary-type-assertion": "off" },
    },
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
