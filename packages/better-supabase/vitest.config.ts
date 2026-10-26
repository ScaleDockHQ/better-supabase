import { env } from "node:process";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Node 24 has no Temporal; Node 26 ignores the polyfill.
    setupFiles: ["./tests/setup/temporal.ts"],
    // The contract runners in @chat-adapter/tests call describe at import time; loaded
    // natively, they get a second vitest instance with no runner.
    server: { deps: { inline: ["@chat-adapter/tests"] } },
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          include: ["tests/**/*.test.ts"],
          exclude: ["tests/**/*.integration.test.ts"],
          // The first test in a CLI file pays the lazy command imports; with coverage on and
          // every workspace testing in parallel, that passes the 5 second default.
          testTimeout: 20_000,
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
      // Lines sit below statements because curly puts every if body on its
      // own line.
      thresholds: {
        statements: 97,
        lines: 89,
        functions: 100,
        branches: 91,
        "src/cli/**": {
          statements: 97,
          lines: 97,
          functions: 98,
          branches: 91,
        },
        // CI never rewrites this file: it is an input of the cached test task.
        autoUpdate: env.CI ? false : (next: number) => Math.floor(next),
      },
    },
  },
});
