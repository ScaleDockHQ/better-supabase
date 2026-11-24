import { env } from "node:process";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Node 24 has no Temporal; Node 26 ignores the polyfill.
    // @chat-adapter/tests/setup registers the matchers its contract runners use.
    setupFiles: [
      "./tests/setup/temporal.ts",
      "./tests/setup/connection.ts",
      "@chat-adapter/tests/setup",
    ],
    // The contract runners in @chat-adapter/tests call describe at import time; loaded
    // natively, they get a second vitest instance with no runner.
    server: { deps: { inline: ["@chat-adapter/tests"] } },
    // On a laptop, one worker per core is slower: the workers starve each other and the
    // other Turbo tasks. CI runners have few cores and nothing else running.
    maxWorkers: env.CI ? undefined : "50%",
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          include: ["tests/**/*.test.ts"],
          exclude: ["tests/**/*.integration.test.ts"],
          // The first test in a CLI file pays the lazy command imports; with coverage on and
          // every workspace testing in parallel, that passes the 5 second default.
          // A beforeEach that runs a CLI command pays the same imports, and a hook has its own
          // 10 second default (remove.test.ts timed out there on a loaded runner).
          testTimeout: 20_000,
          hookTimeout: 20_000,
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
          globalSetup: ["./tests/integration/global-setup.ts"],
          // The suites share one database; counts must not race with writes.
          fileParallelism: false,
          // The doctor suite runs the whole rule set against the stack and took 5.2 s on a CI
          // runner (main, #1130 merge), just past the 5 second default.
          testTimeout: 20_000,
        },
      },
    ],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      exclude: ["src/cli/bin.ts"],
      // Nothing in CI reads the report files.
      reporter: env.CI
        ? ["text-summary"]
        : ["text-summary", "json-summary", "json", "html"],
      // Unit tests alone must hold these; the floor is 90/90/90/80.
      // The numbers are ceilings. Coverage that grows does not rewrite
      // this file, so a pull request does not conflict on them.
      // The top-level numbers count every file, CLI included; the src/cli set
      // also holds the CLI to its own numbers.
      // Lines sit below statements because curly puts every if body on its
      // own line.
      thresholds: {
        statements: 97,
        lines: 97,
        functions: 98,
        branches: 91,
        "src/cli/**": {
          statements: 97,
          lines: 97,
          functions: 98,
          branches: 91,
        },
        autoUpdate: false,
      },
    },
  },
});
