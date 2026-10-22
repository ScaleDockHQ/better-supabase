import { describe, it } from "vitest";

import { defineConfig } from "../../src/config/resolve.ts";

describe("defineConfig instances", () => {
  it("types a named instance's options from its block", () => {
    defineConfig({
      blocks: {
        tasks: {},
        maintenance: { block: "tasks", options: { prefix: "MR-" } },
      },
    });

    defineConfig({
      blocks: {
        // @ts-expect-error -- prefix is a string option of tasks.
        maintenance: { block: "tasks", options: { prefix: 1 } },
      },
    });
  });

  it("types uses as the config's instance names", () => {
    defineConfig({
      blocks: {
        pipelines: {},
        maintenanceStages: { block: "pipelines" },
        maintenance: {
          block: "tasks",
          uses: { pipelines: "maintenanceStages" },
        },
      },
    });

    defineConfig({
      blocks: {
        pipelines: {},
        // @ts-expect-error -- "stages" is not an instance in this config.
        maintenance: { block: "tasks", uses: { pipelines: "stages" } },
      },
    });
  });

  it("rejects a block that doesn't exist", () => {
    defineConfig({
      // @ts-expect-error -- "taskz" is not a block.
      blocks: { maintenance: { block: "taskz" } },
    });
  });
});
