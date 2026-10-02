import { defineConfig } from "vitest/config";

// Workspace packages resolve to their TypeScript source, so tests run without
// building them first. The rest is Vite's default server condition list.
const conditions = [
  "@better-supabase/source",
  "module",
  "node",
  "development|production",
];

export default defineConfig({
  resolve: { conditions },
  ssr: { resolve: { conditions } },
  test: {
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          include: ["tests/**/*.test.ts"],
          exclude: ["tests/**/*.integration.test.ts"],
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
      exclude: ["src/bin.ts"],
      reporter: ["text-summary", "json-summary", "json", "html"],
      // Unit tests alone must hold these; the floor is 90/90/90/80.
      // autoUpdate raises them when coverage grows, in whole percents.
      thresholds: {
        statements: 96,
        lines: 97,
        functions: 98,
        branches: 88,
        autoUpdate: (next: number) => Math.floor(next),
      },
    },
  },
});
