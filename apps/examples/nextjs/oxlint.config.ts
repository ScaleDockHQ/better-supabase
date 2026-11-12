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
  overrides: [
    {
      // The AI slices pass optional fields to block APIs under
      // exactOptionalPropertyTypes (37 conditional spreads) and read untyped
      // AI SDK parts, tool inputs and numeric jsonb columns at the edge
      // (7 unknown parameters, 10 typeof checks, 3 unknown dictionaries and
      // 3 unknown returns). Each reader narrows one value; a schema per
      // part would be longer than the check.
      files: [
        "src/features/{assistant,agents,prompts,evals,guardrails,ai-usage,knowledge}/**/*.{ts,tsx}",
      ],
      rules: {
        "anti-slop/no-conditional-empty-object-spread": "off",
        "anti-slop/no-unknown-parameters": "off",
        "anti-slop/no-unknown-returns": "off",
        "anti-slop/no-runtime-typeof": "off",
        "anti-slop/no-unsafe-dictionary-type": "off",
      },
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
