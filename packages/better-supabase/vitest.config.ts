import { env } from "node:process";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Node 24 has no Temporal; Node 26 ignores the polyfill.
    setupFiles: ["./tests/setup/temporal.ts"],
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          include: ["tests/**/*.test.ts"],
          exclude: ["tests/**/*.integration.test.ts"],
          typecheck: {
            enabled: true,
            include: ["tests/**/*.test-d.ts"],
            ignoreSourceErrors: true,
          },
        },
      },
      {
        extends: true,
        test: {
          name: "integration",
          include: ["tests/**/*.integration.test.ts"],
          // The suites share one database; counts must not race with writes.
          fileParallelism: false,
        },
      },
    ],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      exclude: ["src/cli/bin.ts"],
      reporter: ["text-summary", "json-summary", "json", "html"],
      // Unit tests alone must hold these; the floor is 90/90/90/80.
      // autoUpdate raises them when coverage grows, in whole percents.
      // The top-level numbers count every file, CLI included; the src/cli set
      // also holds the CLI to its own numbers.
      thresholds: {
        statements: 96,
        lines: 97,
        functions: 98,
        branches: 90,
        "src/cli/**": {
          statements: 97,
          lines: 98,
          functions: 98,
          branches: 89,
        },
        // CI never rewrites this file: it is an input of the cached test task.
        autoUpdate: env.CI ? false : (next: number) => Math.floor(next),
      },
    },
  },
});
