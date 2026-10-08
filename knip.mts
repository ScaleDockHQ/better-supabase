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
  ignoreExportsUsedInFile: { interface: true, type: true },
  // Vendored maintainer skills (ADR 0004) carry their own scripts.
  ignore: [".agents/**"],
  // The Vercel CLI runs from the user's machine (`pnpm env:pull`).
  ignoreBinaries: ["vercel"],
  ignoreIssues: {
    // `better-supabase init` writes these; gen --check fails on hand edits.
    "apps/examples/*/src/lib/{supabase/index,hooks}.ts": ["exports", "types"],
    // Fumadocs looks up `useMDXComponents` by name.
    "apps/docs/components/mdx.tsx": ["exports", "duplicates"],
    // Oxlint JS plugins load the default export; the named one is for imports.
    "packages/better-supabase/src/lint/index.ts": ["duplicates"],
    // WORKFLOW_TARGET_WORLD loads the default export; the named one is for imports.
    "packages/better-supabase/src/workflow-sdk/world/index.ts": ["duplicates"],
  },
  workspaces: {
    ".": {
      entry: ["scripts/*.{ts,mjs}"],
    },
    "packages/better-supabase": {
      entry: [
        "src/*/index.ts",
        "src/*/*/index.ts",
        "src/react/{server,session}.ts",
        "scripts/*.ts",
      ],
      ignore: [
        "tests/fixtures/generated*.ts",
        "tests/fixtures/database.types.ts",
      ],
      // Peers of @supabase/config, which src/cli/supabase-toml.ts loads lazily,
      // and @next/playwright, which src/testing/instant.ts loads by a variable
      // specifier.
      ignoreDependencies: [
        "@next/playwright",
        "@supabase/config",
        "effect",
        "@effect/platform-node",
      ],
    },
    "packages/ox-config": {
      // JS plugins are loaded by specifier through import.meta.resolve.
      ignoreDependencies: ["@shadcn/lint", "oxlint-plugin-react-doctor"],
    },
    "packages/typescript-config": {},
    "packages/next-config": {},
    "apps/docs": {},
    "apps/marketing": {
      ignore: ["components/ui/**", "components/reui/**"],
    },
    "apps/examples/edge": edgeExample,
    "apps/examples/mcp": edgeExample,
    "apps/examples/hono-api": serverExample,
    "apps/examples/orpc-api": serverExample,
    "apps/examples/nextjs": {
      ...browserExample,
      ignore: [...exampleIgnore, "src/components/ui/**"],
      // Knip's Playwright plugin finds the specs; the setup project is a
      // `testMatch` regex and `e2e/serve.ts` a `webServer` command, which it
      // can't read.
      entry: [
        "better-supabase.config.ts",
        "src/image-loader.ts",
        "e2e/auth.setup.ts",
        "e2e/serve.ts",
      ],
    },
    "apps/examples/vite-react": browserExample,
    // eve loads the agent's files by path, and the World by package name
    // from agent/agent.ts.
    "apps/examples/eve": {
      entry: ["agent/**/*.ts"],
    },
    "apps/examples/monorepo/runtime": serverExample,
    // Expo Router loads the routes by file name and Metro picks the
    // `.native` files on iOS and Android.
    "apps/examples/expo-powersync": {
      entry: [
        "better-supabase.config.ts",
        "src/app/**/*.{ts,tsx}",
        "src/**/*.native.{ts,tsx}",
      ],
      ignore: exampleIgnore,
      // @react-native/metro-config pins the optional peer of React Native's
      // CLI plugin to the React Native version.
      ignoreDependencies: [
        "@supabase/server",
        "@supabase/ssr",
        "@react-native/metro-config",
      ],
    },
    "tests/bundle": {
      // The size checks read the built packages from disk; the dependencies
      // make Turbo build them first.
      ignoreDependencies: ["better-supabase"],
    },
    "tests/types/shared": {
      entry: ["*.ts"],
    },
    "tests/types/ts-*": {
      ignoreDependencies: ["@better-supabase/types-shared"],
    },
    // Modules ported from production apps; their exports are the app's API.
    "tests/validation-*": {
      entry: ["src/**/*.ts"],
    },
  },
};

export default config;
