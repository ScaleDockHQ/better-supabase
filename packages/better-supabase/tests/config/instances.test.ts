import { describe, expect, it } from "vitest";

import {
  blocksByName,
  CORE_BLOCKS,
  instancePrefix,
  resolveInstances,
} from "../../src/config/instances.ts";
import { resolveConfig } from "../../src/config/resolve.ts";
import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";

describe("resolveInstances", () => {
  it("installs each listed block once under its own name", () => {
    expect(resolveInstances(["tags", "comments"])).toStrictEqual({
      tags: { name: "tags", block: "tags", uses: {}, config: {} },
      comments: { name: "comments", block: "comments", uses: {}, config: {} },
    });
  });

  it("reads block, on and uses from each instance", () => {
    const instances = resolveInstances({
      pipelines: {},
      maintenanceStages: { block: "pipelines" },
      tasks: { uses: { pipelines: "pipelines" } },
      maintenance: {
        block: "tasks",
        on: ["lease"],
        uses: { pipelines: "maintenanceStages" },
      },
    });

    expect(instances["maintenance"]).toStrictEqual({
      name: "maintenance",
      block: "tasks",
      on: ["lease"],
      uses: { pipelines: "maintenanceStages" },
      config: { on: ["lease"], uses: { pipelines: "maintenanceStages" } },
    });
    expect(instances["tasks"]?.uses).toStrictEqual({});
  });

  it("binds a dependency to its only instance when that has another name", () => {
    const instances = resolveInstances({
      stages: { block: "pipelines" },
      deals: {},
    });

    expect(instances["deals"]?.uses).toStrictEqual({ pipelines: "stages" });
  });

  it("rejects an instance name that is not an identifier", () => {
    expect(() => resolveInstances({ "Hiring pipelines": {} })).toThrow(
      "an instance name starts with a lowercase letter",
    );
  });

  it("rejects an unknown block", () => {
    expect(() => resolveInstances({ maintenance: { block: "taskz" } })).toThrow(
      'blocks.maintenance.block: "taskz" is not a block',
    );
  });

  it("installs a core block once, under its own name", () => {
    expect(() =>
      resolveInstances({ outbox: {}, events: { block: "outbox" } }),
    ).toThrow('blocks.events: "outbox" is a core block and installs once');
  });

  it("checks that uses names a dependency and one of its instances", () => {
    expect(() =>
      resolveInstances({ tags: { uses: { invoices: "invoices" } } }),
    ).toThrow('blocks.tags.uses.invoices: "tags" doesn\'t use "invoices"');

    expect(() =>
      resolveInstances({
        pipelines: {},
        tasks: {},
        maintenance: { block: "tasks", uses: { pipelines: "stages" } },
      }),
    ).toThrow('"stages" is not an instance of "pipelines"');
  });

  it("asks for uses when a required block is installed twice", () => {
    expect(() =>
      resolveInstances({
        pipelines: {},
        stages: { block: "pipelines" },
        deals: {},
      }),
    ).toThrow(
      'blocks.deals.uses.pipelines: "pipelines" is installed as "pipelines" and "stages"',
    );
  });

  it("names only real blocks as core blocks", () => {
    const blocks = new Set(PRESET_CATALOG.blocks.map((block) => block.name));

    expect([...CORE_BLOCKS].filter((name) => !blocks.has(name))).toStrictEqual(
      [],
    );
  });
});

describe("blocksByName", () => {
  it("keeps the instances named after their block", () => {
    const blocks = {
      labels: { block: "tags", options: { a: 1 } },
      tags: { options: { b: 2 } },
      files: { block: "attachments", options: { c: 3 } },
    };

    expect(blocksByName(resolveInstances(blocks))).toStrictEqual({
      tags: { options: { b: 2 } },
    });
  });
});

describe("instancePrefix", () => {
  it("writes the instance name in snake case", () => {
    expect(instancePrefix("hiring-pipelines")).toBe("hiring_pipelines");
    expect(instancePrefix("maintenanceStages")).toBe("maintenance_stages");
  });
});

describe("resolveConfig", () => {
  it("returns the instances and each block name once", () => {
    const config = resolveConfig(
      { blocks: { tags: {}, labels: { block: "tags" } } },
      "/app",
    );

    expect(config.blockNames).toStrictEqual(["tags"]);
    expect(Object.keys(config.instances)).toStrictEqual(["tags", "labels"]);
  });
});
