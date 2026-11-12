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
  // `init` output, compared byte for byte by the init fixture test.
  ignore: [".agents/**", "tests/init-fixture/**"],
  // The Vercel CLI runs from the user's machine (`pnpm env:pull`). The MCP
  // configs run shadcn with `pnpm --dir apps/marketing`, which declares it.
  ignoreBinaries: ["vercel", "shadcn", "ipcs"],
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
        // The @workflow/vitest runtime suite has its own config and runs through
        // `pnpm test:workflow`.
        "vitest.workflow.config.ts",
        "tests/workflow-vitest/**/*.ts",
      ],
      ignore: [
        "tests/fixtures/generated*.ts",
        "tests/fixtures/database.types.ts",
        // topic-policies.test.ts copies this file into a temp project by name.
        "tests/cli/fixtures/topics/broadcast-topic.mjs",
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
        // src/node/keep-alive-fetch.ts loads undici lazily as an optional peer.
        "undici",
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
        // The zod and nuqs generators write every table, used or not.
        "src/lib/supabase/generated.zod.ts",
        "src/lib/supabase/generated.nuqs.ts",
        // `gen.serverBlocks` writes `<name>Instances` and `<name>Blocks` for each set (ADR 0542).
        "src/lib/supabase/blocks.core.ts",
        "src/lib/supabase/blocks.api.ts",
        // Copied from the registry, which knip checks as entries.
        "src/hooks/use-*.ts",
        // The shadcn code block's highlighter; the block is not on a page yet.
        "src/lib/highlighter.tsx",
      ],
      // The shadcn CLI installed these for the parts under components/ui, which
      // knip skips, and for the chat tests. Phases 1 to 4 of the example plan
      // import them; drop an entry when a page imports its part.
      ignoreDependencies: [
        ...browserExample.ignoreDependencies,
        "react-day-picker",
        "shiki",
      ],
      // The browser loads the service worker by URL. `tsc` checks the type tests,
      // which the vitest config's `include` leaves out.
      entry: [
        "better-supabase.config.ts",
        "src/image-loader.ts",
        "public/sw.js",
        "tests/**/*.test-d.ts",
        // The composite actions are the runnable example the docs link to; no
        // page calls them yet.
        "src/features/composites/composites-actions.ts",
        // The docs recipes read these files; the pages use the server-rendered versions.
        "src/features/audit/components/audit-log-table.tsx",
        "src/features/shop/components/inventory-table.tsx",
        "src/features/notifications/components/notification-list.tsx",
        "src/features/workflows/builder/components/workflow-canvas.tsx",
        "src/features/workflows/components/workflow-runs.tsx",
        // The usage billing action is the example the usage docs link to.
        "src/features/billing/billing-actions.ts",
      ],
    },
    "apps/examples/vite-react": {
      ...browserExample,
      // The generated layout writes one module per table, and the SPA imports the
      // one table it reads (ADR 0262); the rest are the generator's output.
      ignore: [
        ...exampleIgnore,
        "src/lib/supabase/generated-schema.ts",
        "src/lib/supabase/generated.meta.js",
        "src/lib/supabase/generated.functions.js",
        "src/lib/supabase/tables/**",
      ],
    },
    // eve loads the agent's files by path, and the World by package name
    // from agent/agent.ts.
    "apps/examples/eve": {
      entry: ["agent/**/*.ts", "better-supabase.config.ts"],
      ignore: exampleIgnore,
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
      // The src/hooks files are copied from the registry, which knip checks.
      ignore: [
        ...exampleIgnore,
        "src/hooks/use-*.ts",
        "src/lib/supabase/records/**",
        // `better-supabase gen` writes the PowerSync schema with one export per table.
        "powersync/schema.ts",
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
    // The CLI loads the config file, not the tests.
    "tests/validation-declarative": {
      entry: ["src/**/*.ts", "better-supabase.config.ts"],
    },
    "tests/validation-lienlink": {
      entry: ["src/**/*.ts", "better-supabase.config.ts"],
    },
    "tests/validation-single-tenant": {
      entry: ["src/**/*.ts", "better-supabase.config.ts"],
    },
  },
};

export default config;
