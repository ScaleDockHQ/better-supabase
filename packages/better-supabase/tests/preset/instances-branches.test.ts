import { describe, expect, it } from "vitest";

import type { PresetCatalog } from "../../src/preset/catalog-types.ts";

import { presetOf } from "../../src/preset/index.ts";
import {
  blockEntities,
  blockRequires,
  entityName,
  instanceBlock,
  instanceNameProblem,
  instancesOf,
  presetInstances,
  withEntityName,
  withInstance,
  withoutInstance,
} from "../../src/preset/instances.ts";

describe("blockRequires", () => {
  it("reads the default catalog and merges access levels without repeats", () => {
    expect(blockRequires("invitations")).toContain("memberships");

    const catalog = {
      blocks: [
        {
          name: "a",
          requires: ["x", "y"],
          requiresByAccess: { one: ["y", "z"], two: ["x"] },
        },
        { name: "b" },
      ],
    } as unknown as PresetCatalog;

    expect(blockRequires("a", catalog)).toEqual(["x", "y", "z"]);
    expect(blockRequires("b", catalog)).toEqual([]);
    expect(blockRequires("missing", catalog)).toEqual([]);
  });
});

describe("blockEntities", () => {
  it("lists renamable entities and skips global or unknown ones", () => {
    expect(blockEntities("webhooks")).toEqual([
      {
        key: "webhook_endpoint",
        table: "endpoints",
        singular: "webhook_endpoint",
        required: true,
      },
    ]);
    expect(blockEntities("memberships")).toEqual([]);
    expect(blockEntities("no-such-block")).toEqual([]);
  });
});

describe("instance lookups", () => {
  const preset = {
    ...presetOf("saas"),
    instances: {
      alias: { block: "alias" },
      second: { block: "memberships", names: { organization: "team" } },
      plain: {},
    },
  };

  it("resolves the block an instance installs", () => {
    expect(instanceBlock(preset, "second")).toBe("memberships");
    expect(instanceBlock(preset, "plain")).toBe("plain");
    expect(instanceBlock(presetOf("saas"), "memberships")).toBe("memberships");
  });

  it("skips entries that only repeat their own block name", () => {
    const names = presetInstances(preset).map((each) => each.name);

    expect(names).toContain("second");
    expect(names).not.toContain("alias");
    expect(names).not.toContain("plain");
    expect(instancesOf(preset, "memberships").map((each) => each.name)).toEqual(
      expect.arrayContaining(["memberships", "second"]),
    );
  });

  it("reads an entity name only when one is set", () => {
    expect(entityName(preset, "second", "organization")).toBe("team");
    expect(entityName(preset, "second", "other")).toBeUndefined();
    expect(
      entityName(presetOf("saas"), "second", "organization"),
    ).toBeUndefined();
  });

  it("refuses a name an instance already uses", () => {
    expect(instanceNameProblem(preset, "second")).toContain("already");
  });
});

describe("withEntityName", () => {
  const base = presetOf("saas");

  it("sets, keeps siblings and resets to the default", () => {
    const named = withEntityName(base, "webhooks", "webhook_endpoint", "hook");

    expect(entityName(named, "webhooks", "webhook_endpoint")).toBe("hook");

    const both = withEntityName(named, "webhooks", "other", "thing");

    expect(entityName(both, "webhooks", "webhook_endpoint")).toBe("hook");
    expect(entityName(both, "webhooks", "other")).toBe("thing");

    const reset = withEntityName(both, "webhooks", "other", undefined);

    expect(entityName(reset, "webhooks", "other")).toBeUndefined();
    expect(entityName(reset, "webhooks", "webhook_endpoint")).toBe("hook");

    const fallback = withEntityName(
      named,
      "webhooks",
      "webhook_endpoint",
      "webhook_endpoint",
    );

    expect(fallback.instances).toBeUndefined();
  });

  it("keeps an instance's other settings and drops empty maps", () => {
    const withBlock = withInstance(base, "hiring", {
      block: "pipelines",
      names: { stage: "step" },
      uses: { memberships: "memberships" },
      on: ["a"],
    });

    const cleared = withEntityName(withBlock, "hiring", "stage", undefined);

    expect(cleared.instances?.["hiring"]).toEqual({
      block: "pipelines",
      uses: { memberships: "memberships" },
      on: ["a"],
    });
  });
});

describe("withInstance and withoutInstance", () => {
  const base = presetOf("saas");

  it("drops empty names, uses and on, but keeps filled ones", () => {
    const empty = withInstance(base, "extra", {
      block: "pipelines",
      names: {},
      uses: {},
      on: {},
    });

    expect(empty.instances?.["extra"]).toEqual({ block: "pipelines" });

    const emptyList = withInstance(base, "extra", {
      block: "pipelines",
      on: [],
    });

    expect(emptyList.instances?.["extra"]).toEqual({ block: "pipelines" });

    const filled = withInstance(base, "extra", {
      block: "pipelines",
      on: { a: {} },
    });

    expect(filled.instances?.["extra"]?.on).toEqual({ a: {} });
  });

  it("pins dependents to the first instance when a second one joins", () => {
    const next = withInstance(base, "teams", { block: "memberships" });

    const pinned = presetInstances(next)
      .filter(
        (each) =>
          each.name !== "teams" &&
          blockRequires(each.block).includes("memberships"),
      )
      .map((each) => next.instances?.[each.name]?.uses?.["memberships"]);

    expect(pinned.length).toBeGreaterThan(0);
    expect(pinned.every((target) => target === "memberships")).toBe(true);

    const already = withInstance(
      {
        ...base,
        instances: { invitations: { uses: { memberships: "elsewhere" } } },
      },
      "teams",
      { block: "memberships" },
    );

    expect(already.instances?.["invitations"]?.uses?.["memberships"]).toBe(
      "elsewhere",
    );
  });

  it("removes an instance with the uses that pointed at it", () => {
    const added = withInstance(base, "teams", { block: "memberships" });
    const removed = withoutInstance(added, "teams");

    expect(removed.instances).toBeUndefined();

    const other = withInstance(added, "more", {
      block: "memberships",
      uses: { memberships: "teams" },
    });

    const left = withoutInstance(other, "teams");

    expect(left.instances?.["more"]?.uses).toBeUndefined();
    expect(left.instances?.["teams"]).toBeUndefined();
  });
});
