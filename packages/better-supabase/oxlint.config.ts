import { defineConfig } from "oxlint";

import {
  core,
  ignorePatterns,
  library,
  node,
  react,
  restrictedImportPaths,
  restrictedImportPatterns,
  test,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, library, react, test],
  ignorePatterns: [
    ...ignorePatterns,
    "**/*.generated.ts",
    "**/database.types.ts",
    // Generated fixtures open with a blanket disable for consumers' linters.
    "tests/fixtures/generated*",
    "api/**",
  ],
  rules: {
    // Bundlers read `/* @__PURE__ */` only right before the call it marks.
    "no-inline-comments": ["error", { ignorePattern: "^ @__PURE__ $" }],
    // The core decodes PostgREST, Auth, webhook and storage payloads without
    // a schema dependency (invariant 1), and the CLI's introspection and
    // doctor read catalog rows, config.toml and splinter JSON, so their
    // decoders take `unknown`, branch on `typeof` and build rows as
    // dictionaries. Findings when measured, tests included (core plus CLI):
    // no-runtime-typeof 280, no-unsafe-dictionary-type 249,
    // no-unknown-parameters 238, no-unknown-returns 69,
    // no-known-value-widening 66 and no-object-parameters 29 (core only).
    // Backlog in docs/decisions/0002.
    "anti-slop/no-runtime-typeof": "off",
    "anti-slop/no-unsafe-dictionary-type": "off",
    "anti-slop/no-unknown-parameters": "off",
    "anti-slop/no-unknown-returns": "off",
    "anti-slop/no-known-value-widening": "off",
    "anti-slop/no-object-parameters": "off",
    // exactOptionalPropertyTypes forbids `key: undefined`, and these spreads
    // are how an absent option stays absent; 199 findings when measured
    // (127 core, 72 CLI).
    "anti-slop/no-conditional-empty-object-spread": "off",
  },
  overrides: [
    {
      // The React hook and React Compiler rules assume React components;
      // these bindings run under Vue, Solid and Svelte, where setup()
      // functions and getters in objects are the idiom. 13 findings when
      // measured (10 react/todo, 3 react/rules-of-hooks).
      files: [
        "src/{vue,solid,svelte}/**/*.ts",
        "tests/{vue,solid,svelte}/**/*.ts",
      ],
      rules: { "react/rules-of-hooks": "off", "react/todo": "off" },
    },
    {
      // The SQL blocks are one registry of SQL modules (src/sql/registry.ts registry,
      // AGENTS.md); its SQL text is the bulk of the file.
      files: ["src/sql/registry.ts"],
      rules: { "eslint/max-lines": "off" },
    },
    {
      // Relation counts and aggregates are part of the repository API.
      files: ["src/**/*.{ts,tsx}", "tests/**/*.{ts,tsx}"],
      rules: {
        "no-underscore-dangle": [
          "error",
          { allow: ["_count", "_sum", "_avg", "_min", "_max"] },
        ],
      },
    },
    {
      // Runtime entries run on every WinterTC runtime (AGENTS.md invariant 6).
      files: [
        "src/index.ts",
        "src/{ai-sdk,auth,bridges,casing,chat-sdk,client,compile,config,core,edge,elysia,env,events,generators,h3,hono,ir,jobs,lint,list,mcp,next,openapi,orpc,otel,plugins,query,react,react-router,realtime,schema,server,sql,ssr,storage,sveltekit,tanstack-start,webhooks}/**/*.{ts,tsx}",
      ],
      excludeFiles: ["**/*.test.ts", "**/*.test-d.ts", "**/tests/**"],
      rules: {
        "no-restricted-imports": [
          "error",
          {
            paths: [...restrictedImportPaths],
            patterns: [
              ...restrictedImportPatterns,
              {
                group: ["node:*"],
                message:
                  "Runtime entries import no Node built-ins; move this to cli, postgres or testing.",
              },
            ],
          },
        ],
      },
    },
    {
      // Blocks, streams and credentials stay SDK-neutral (ADR 0010): each SDK
      // gets an adapter subpath (`src/ai-sdk`, `src/vercel-connect`) that
      // depends on them, never the other way round. 0 findings when added.
      files: [
        "src/blocks/**/*.{ts,tsx}",
        "src/streams/**/*.{ts,tsx}",
        "src/credentials/**/*.{ts,tsx}",
      ],
      rules: {
        "no-restricted-imports": [
          "error",
          {
            paths: [
              ...restrictedImportPaths,
              ...["ai", "workflow", "chat", "@vercel/connect", "eve"].map(
                (name) => ({
                  name,
                  message:
                    "Blocks stay SDK-neutral (ADR 0010); put SDK code in an adapter subpath.",
                }),
              ),
            ],
            patterns: [
              ...restrictedImportPatterns,
              {
                group: [
                  "ai/*",
                  "@ai-sdk/*",
                  "workflow/*",
                  "@workflow/*",
                  "chat/*",
                ],
                message:
                  "Blocks stay SDK-neutral (ADR 0010); put SDK code in an adapter subpath.",
              },
            ],
          },
        ],
      },
    },
    {
      // The library's env boundary: optional connection defaults for the
      // local stack, NODE_ENV development detection and the CLI environment.
      files: [
        "src/postgres/pool.ts",
        "src/testing/**",
        "src/next/create.ts",
        "src/server/respond.ts",
        "src/core/events.ts",
        // The CLI reads its environment: DATABASE_URL, SUPABASE_BIN and CI.
        "src/cli/run.ts",
        "src/cli/bin.ts",
        // The Supabase World reads its options as the Workflow SDK's worlds do.
        "src/workflow-sdk/world/world.ts",
        "scripts/gen-workflow-ddl.ts",
      ],
      rules: { "node/no-process-env": "off" },
    },
    {
      // ESLint and oxlint load plugins from the module's default export, and
      // WORKFLOW_TARGET_WORLD loads a World factory from it.
      files: ["src/lint/index.ts", "src/workflow-sdk/world/index.ts"],
      rules: {
        "import/no-default-export": "off",
      },
    },
  ],
});
