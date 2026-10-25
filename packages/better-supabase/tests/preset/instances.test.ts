import { describe, expect, it } from "vitest";

import {
  canAddInstance,
  createQuery,
  instanceNameProblem,
  instancePrefix,
  installedBlocks,
  presetArgumentOf,
  presetOf,
  withEntityName,
  withInstance,
  withoutInstance,
} from "../../src/preset/index.ts";

describe("instance rules", () => {
  const preset = presetOf("saas");

  it("lets a core block install once and others repeat", () => {
    expect(canAddInstance("organizations")).toBe(false);
    expect(canAddInstance("pipelines")).toBe(true);
  });

  it("derives table prefixes from instance names", () => {
    expect(instancePrefix("hiring-pipelines")).toBe("hiring_pipelines");
    expect(instancePrefix("hiringPipelines")).toBe("hiring_pipelines");
  });

  it("refuses names that clash or are malformed", () => {
    expect(instanceNameProblem(preset, "Bad")).toBeDefined();
    expect(instanceNameProblem(preset, "organizations")).toContain(
      "block name",
    );
    expect(instanceNameProblem(preset, "talent")).toBeUndefined();
  });

  it("adds and removes an instance", () => {
    const added = withInstance(preset, "talent", { block: "pipelines" });

    expect(added.instances?.["talent"]?.block).toBe("pipelines");
    expect(withoutInstance(added, "talent").instances).toBeUndefined();
  });

  it("drops an entity name that equals the default", () => {
    const named = withEntityName(preset, "organizations", "organization", "x");

    expect(
      withEntityName(named, "organizations", "organization", undefined),
    ).toEqual(preset);
  });

  it("lists the installed blocks", () => {
    expect(installedBlocks(preset).has("organizations")).toBe(true);
  });
});

describe("create links", () => {
  it("writes a name for a named preset without a design", async () => {
    expect(await createQuery(presetOf("saas"))).toBe("preset=saas");
    expect(presetArgumentOf("preset=saas")).toBe("saas");
  });

  it("writes a design code and a quoted URL otherwise", async () => {
    const query = await createQuery(presetOf("saas"), {
      appTables: { tasks: { columns: {} } },
    });

    expect(query.startsWith("design=")).toBe(true);
    expect(presetArgumentOf(query)).toMatch(/^"https:\/\/.*\/create\?design=/u);
  });
});
