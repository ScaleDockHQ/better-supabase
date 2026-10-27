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
    "apps/examples/*/src/lib/{supabase/index,supabase/hooks,hooks}.ts": [
      "exports",
      "types",
    ],
    // Fumadocs looks up `useMDXComponents` by name.
    "apps/docs/components/mdx.tsx": ["exports", "duplicates"],
    // Oxlint JS plugins load the default export; the named one is for imports.
    "packages/better-supabase/src/lint/index.ts": ["duplicates"],
    // WORKFLOW_TARGET_WORLD loads the default export; the named one is for imports.
    "packages/better-supabase/src/workflow-sdk/world/index.ts": ["duplicates"],
  },
  workspaces: {
    ".": { entry: ["scripts/*.{ts,mjs}"] },
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
      // and @next/playwright and @supabase/lite, which src/testing/instant.ts,
      // src/lite/runtime.ts and src/cli/lite.ts load by a variable specifier.
      // supports-color only pins debug's optional peer, so next resolves to
      // the examples' copy.
      ignoreDependencies: [
        "@next/playwright",
        "supports-color",
        "@supabase/lite",
        "@supabase/config",
        "effect",
        "@effect/platform-node",
      ],
    },
    "packages/typescript-config": {},
    "packages/next-config": {},
    // Registry items are copied into apps by the shadcn CLI, so each one is
    // an entry; the stubs stand in for the app files they import.
    "packages/registry": { entry: ["items/**/*.ts"] },
    "apps/docs": {},
    "apps/marketing": { ignore: ["components/ui/**", "components/reui/**"] },
    "apps/examples/edge": edgeExample,
    "apps/examples/mcp": edgeExample,
    "apps/examples/hono-api": serverExample,
    "apps/examples/express": {
      entry: ["better-supabase.config.ts"],
      ignore: exampleIgnore,
    },
    "apps/examples/content-mapper": {
      entry: ["better-supabase.config.ts"],
      ignore: ["**/generated.ts"],
    },
    "apps/examples/orpc-api": serverExample,
    "apps/examples/nextjs": {
      ...browserExample,
      ignore: [
        ...exampleIgnore,
        "src/components/ui/**",
        "src/components/reui/**",
        "src/lib/supabase/records/**",
        "src/lib/supabase/hooks.ts",
        // Copied from the registry, which knip checks as entries.
        "src/hooks/use-*.ts",
      ],
      // The browser loads the push worker by URL. `tsc` checks the type tests,
      // which the vitest config's `include` leaves out.
      entry: [
        "better-supabase.config.ts",
        "src/image-loader.ts",
        "public/push-sw.js",
        "tests/**/*.test-d.ts",
      ],
    },
    "apps/examples/vite-react": browserExample,
    // eve loads the agent's files by path, and the World by package name
    // from agent/agent.ts.
    "apps/examples/eve": { entry: ["agent/**/*.ts"] },
    "apps/examples/monorepo/runtime": serverExample,
    // Expo Router loads the routes by file name and Metro picks the
    // `.native` files on iOS and Android.
    "apps/examples/expo-powersync": {
      entry: [
        "better-supabase.config.ts",
        "src/app/**/*.{ts,tsx}",
        "src/**/*.native.{ts,tsx}",
      ],
      // The src/hooks files are copied from the registry, which knip checks.
      ignore: [
        ...exampleIgnore,
        "src/hooks/use-*.ts",
        "src/lib/supabase/records/**",
      ],
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
    "tests/types/shared": { entry: ["*.ts"] },
    // Type-only checks; `tsc` is the runner, so the exports are the checks.
    "tests/types/frameworks-previous": { entry: ["src/*.ts"] },
    "tests/types/ts-*": {
      ignoreDependencies: ["@better-supabase/types-shared"],
    },
    // gen writes mapper/, and equal.ts compares it with the shared output.
    "tests/types/ts-7.1": { entry: ["*.ts", "mapper/*.{ts,js}"] },
    // Modules ported from production apps; their exports are the app's API.
    "tests/validation-*": { entry: ["src/**/*.ts"] },
  },
};

export default config;
