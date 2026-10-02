import type { KnipConfig } from "knip";

const exampleIgnore = ["**/database.types.ts", "**/generated.ts"];

// better-supabase loads @supabase/server and @supabase/ssr as optional peers.
const serverExample = {
  entry: ["better-supabase.config.ts"],
  ignore: exampleIgnore,
  ignoreDependencies: ["@supabase/server"],
};
const edgeExample = {
  ...serverExample,
  entry: ["better-supabase.config.ts", "supabase/functions/*/index.ts"],
};
const browserExample = {
  entry: ["better-supabase.config.ts"],
  ignore: exampleIgnore,
  ignoreDependencies: ["@supabase/ssr"],
};

const config: KnipConfig = {
  treatConfigHintsAsErrors: true,
  tags: ["-internal"],
  // The Vercel CLI runs from the user's machine (`pnpm env:pull`).
  ignoreBinaries: ["vercel"],
  ignoreIssues: {
    // `better-supabase init` writes these; gen --check fails on hand edits.
    "apps/examples/*/src/lib/{supabase,hooks}.ts": ["exports", "types"],
    // Fumadocs looks up `useMDXComponents` by name.
    "apps/docs/components/mdx.tsx": ["exports", "duplicates"],
    // Oxlint JS plugins load the default export; the named one is for imports.
    "packages/better-supabase/src/lint/index.ts": ["duplicates"],
  },
  workspaces: {
    ".": {
      entry: ["scripts/*.{ts,mjs}"],
    },
    "packages/better-supabase": {
      entry: [
        "src/index.ts",
        "src/*/index.ts",
        "src/*/*/index.ts",
        "src/react/{server,session}.ts",
      ],
      ignore: [
        "tests/fixtures/generated*.ts",
        "tests/fixtures/database.types.ts",
      ],
    },
    "packages/cli": {
      entry: ["scripts/*.ts"],
      // Peers of @supabase/config, which supabase-toml.ts loads lazily.
      ignoreDependencies: [
        "@supabase/config",
        "effect",
        "@effect/platform-node",
      ],
    },
    "packages/ox-config": {
      // JS plugins are loaded by specifier through import.meta.resolve.
      ignoreDependencies: [
        "@shadcn/lint",
        "eslint-plugin-playwright",
        "oxlint-plugin-react-doctor",
      ],
    },
    "packages/typescript-config": {},
    "apps/docs": {
      // Twoslash snippets import better-supabase; twoslash is a peer of fumadocs-twoslash.
      ignoreDependencies: ["better-supabase", "twoslash"],
    },
    "apps/marketing": {
      ignore: ["components/ui/**", "components/reui/**"],
    },
    "apps/examples/edge": edgeExample,
    "apps/examples/mcp": edgeExample,
    "apps/examples/hono-api": serverExample,
    "apps/examples/orpc-api": serverExample,
    "apps/examples/nextjs": {
      ...browserExample,
      entry: ["better-supabase.config.ts", "src/image-loader.ts"],
    },
    "apps/examples/vite-react": browserExample,
    "tests/bundle": {
      // The size and export checks resolve the built package by name.
      ignoreDependencies: ["better-supabase"],
    },
    "tests/e2e": {
      ignoreBinaries: ["next"],
    },
    "tests/types/shared": {
      entry: ["*.ts"],
    },
    "tests/types/ts-*": {
      ignoreDependencies: ["@better-supabase/types-shared"],
    },
    "tests/types/perf": {},
    // Modules ported from production apps; their exports are the app's API.
    "tests/validation-*": {
      entry: ["src/**/*.ts"],
    },
  },
};

export default config;
