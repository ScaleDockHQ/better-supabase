import { workflow } from "@workflow/vitest";
import { defineConfig } from "vitest/config";

// Run with `vitest run -c vitest.workflow.config.ts`; the *.runtime.ts files stay out of the unit project.
// Real-runtime tests for the workflow-sdk helpers: the plugin compiles the
// "use workflow" files in tests/workflow-vitest/workflows and runs them on a local world.
export default defineConfig({
  plugins: [workflow()],
  test: {
    include: ["tests/workflow-vitest/**/*.runtime.ts"],
    testTimeout: 60_000,
  },
});
