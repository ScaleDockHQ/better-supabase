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
      // The src/cli set covers the CLI; the top-level numbers cover the rest.
      thresholds: {
        statements: 95,
        lines: 96,
        functions: 97,
        branches: 91,
        "src/cli/**": {
          statements: 96,
          lines: 97,
          functions: 98,
          branches: 88,
        },
        autoUpdate: (next: number) => Math.floor(next),
      },
    },
  },
});
