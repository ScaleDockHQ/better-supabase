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
    "tests/fixtures/generated*.ts",
    "api/**",
  ],
  overrides: [
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
        "src/{auth,casing,client,compile,config,core,edge,env,events,generators,hono,ir,jobs,lint,list,mcp,next,openapi,orpc,otel,plugins,query,react,realtime,schema,server,sql,ssr,storage,webhooks}/**/*.{ts,tsx}",
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
      // The library's env boundary: optional connection defaults for the
      // local stack, NODE_ENV development detection and the CLI environment.
      files: [
        "src/postgres/pool.ts",
        "src/testing/**",
        "src/cli/run.ts",
        "src/next/create.ts",
        "src/server/respond.ts",
      ],
      rules: { "node/no-process-env": "off" },
    },
    {
      // ESLint and oxlint load plugins from the module's default export.
      files: ["src/lint/index.ts"],
      rules: {
        "import/no-default-export": "off",
      },
    },
  ],
});
