import { describe, expect, it } from "vitest";

import type { PresetCatalog } from "../../src/preset/catalog-types.ts";
import type { Preset } from "../../src/preset/fields.ts";

import { DEFAULT_CONVENTIONS } from "../../src/preset/fields.ts";
import {
  namedPreset,
  PRESET_NAMES,
  PRESETS,
} from "../../src/preset/presets.ts";
import {
  listNames,
  presetBlockConflict,
  resolvePreset,
} from "../../src/preset/resolve.ts";
import { renderModules, resolveModules } from "../../src/sql/index.ts";

const preset = (
  blocks: readonly string[],
  conventions: Partial<Preset> = {},
): Preset => ({
  ...DEFAULT_CONVENTIONS,
  ...conventions,
  blocks,
});

describe("resolvePreset", () => {
  it("adds what comments requires, with a reason per block", () => {
    const resolved = resolvePreset(preset(["comments"]));
    expect(resolved.blocks.map((block) => [block.name, block.reason])).toEqual([
      ["updated-at", "required by tenant"],
      ["tenant", "required by access and comments"],
      ["access", "required by comments"],
      ["comments", "selected"],
    ]);
    expect(resolved.blocks.at(-1)).toMatchObject({
      selected: true,
      requiredBy: [],
      category: "collaboration",
      title: expect.any(String),
    });
    expect(resolved.conflicts).toEqual([]);
    expect(resolved.manifests.map((manifest) => manifest.name)).toEqual([
      "access",
      "comments",
      "tenant",
      "updated-at",
    ]);
  });

  it("lists the soft integrations active between blocks in the set", () => {
    const resolved = resolvePreset(preset(["comments", "notifications"]));
    expect(resolved.integrations).toContainEqual({
      from: "comments",
      to: "notifications",
    });
    expect(resolved.integrations).toContainEqual({
      from: "notifications",
      to: "access",
    });
    expect(
      resolved.integrations.some((each) => each.to === "jsonb-schemas"),
    ).toBe(false);
  });

  it("takes access requires from the access model", () => {
    const roles = resolvePreset(preset(["access"]));
    expect(roles.blocks.map((block) => block.name)).toEqual([
      "updated-at",
      "tenant",
      "access",
    ]);
    const provider = resolvePreset(preset(["access"], { access: "provider" }));
    expect(provider.blocks.map((block) => block.name)).toEqual(["access"]);
  });

  it("refuses blocks that need tenants under a user or no scope", () => {
    const resolved = resolvePreset(
      preset(["profiles", "organizations", "tenant", "drive"], {
        scope: "user",
      }),
    );
    expect(resolved.blocks.map((block) => block.name)).toEqual(["profiles"]);
    expect(resolved.conflicts).toEqual([
      {
        block: "organizations",
        reason: 'it needs tenants, and scope "user" has none',
      },
      { block: "tenant", reason: 'scope "user" has no tenants' },
      {
        block: "drive",
        reason: 'it needs tenants, and scope "user" has none',
      },
    ]);
    expect(
      presetBlockConflict({ scope: "none", access: "roles" }, "push"),
    ).toBe(undefined);
    expect(
      presetBlockConflict({ scope: "tenant", access: "roles" }, "comments"),
    ).toBe(undefined);
  });

  it("runs tags, comments and notifications without tenants per user or in one space", () => {
    for (const scope of ["user", "none"] as const) {
      const resolved = resolvePreset(
        preset(["tags", "comments", "notifications"], { scope }),
      );
      expect(resolved.conflicts).toEqual([]);
      const names = resolved.blocks.map((block) => block.name);
      expect(names).toEqual(
        expect.arrayContaining(["tags", "comments", "notifications"]),
      );
      expect(names).not.toContain("tenant");
      expect(names).not.toContain("access");
    }
    expect(
      resolvePreset(preset(["tags"])).blocks.map((block) => block.name),
    ).toEqual(expect.arrayContaining(["tenant", "access"]));
  });

  it("refuses a tenant name a block's tables already use", () => {
    expect(
      resolvePreset(preset(["teams"], { tenantName: "team" })).conflicts,
    ).toEqual([
      {
        block: "teams",
        field: "tenantName",
        reason:
          'tenant name "team" renames organizations to teams, the table the teams block already writes',
      },
    ]);
    expect(
      resolvePreset(preset(["teams"], { tenantName: "workspace" })).conflicts,
    ).toEqual([]);
  });

  it("reports unknown blocks", () => {
    expect(resolvePreset(preset(["nope"])).conflicts).toEqual([
      { block: "nope", reason: '"nope" is not a block' },
    ]);
  });

  it("reports frameworks and platforms that don't fit together", () => {
    expect(
      resolvePreset(preset([], { framework: "expo", platforms: "web" }))
        .conflicts,
    ).toEqual([
      {
        field: "platforms",
        reason: "Expo builds a native app: choose native or both",
      },
    ]);
    expect(
      resolvePreset(preset([], { framework: "next", platforms: "native" }))
        .conflicts,
    ).toEqual([
      {
        field: "framework",
        reason: "a native-only app runs on Expo, not next",
      },
    ]);
    expect(
      resolvePreset(preset([], { framework: "next", platforms: "both" }))
        .conflicts,
    ).toEqual([]);
  });

  it("reports a required port no block in the set provides", () => {
    const catalog: PresetCatalog = {
      blocks: [
        {
          name: "a",
          title: "A",
          category: "work",
          requires: [],
          integrates: [],
          manifest: "a",
        },
        {
          name: "b",
          title: "B",
          category: "work",
          requires: [],
          integrates: [],
          manifest: "b",
        },
      ],
      manifests: [
        {
          name: "a",
          sql: ["a"],
          category: "work",
          client: null,
          consumes: { notifier: "required", files: "optional" },
          provides: [],
        },
        {
          name: "b",
          sql: ["b"],
          category: "work",
          client: null,
          consumes: {},
          provides: ["notifier"],
        },
      ],
      glue: [],
    };
    expect(resolvePreset(preset(["a"]), catalog).conflicts).toEqual([
      {
        block: "a",
        reason: "it needs a notifier port, and no selected block provides one",
      },
    ]);
    expect(resolvePreset(preset(["a", "b"]), catalog).conflicts).toEqual([]);
  });
});

describe("named presets", () => {
  it.each(PRESET_NAMES)("%s resolves without conflicts and renders", (name) => {
    const resolved = resolvePreset(namedPreset(name));
    expect(resolved.conflicts).toEqual([]);
    const names = resolved.blocks.map((block) => block.name);
    // The resolver agrees with the SQL registry on the full set.
    expect(names.toSorted()).toEqual(
      resolveModules(PRESETS[name].blocks)
        .map((module) => module.name)
        .toSorted(),
    );
    expect(renderModules(names).length).toBeGreaterThan(0);
  });

  it("builds every other preset on saas", () => {
    for (const name of PRESET_NAMES) {
      if (name === "minimal" || name === "saas") continue;
      expect(PRESETS[name].blocks).toEqual(
        expect.arrayContaining([...PRESETS.saas.blocks]),
      );
    }
  });
});

describe("listNames", () => {
  it("joins names as prose", () => {
    expect(listNames([])).toBe("");
    expect(listNames(["a"])).toBe("a");
    expect(listNames(["a", "b"])).toBe("a and b");
    expect(listNames(["a", "b", "c"])).toBe("a, b and c");
  });
});
