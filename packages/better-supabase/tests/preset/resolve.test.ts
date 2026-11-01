import { describe, expect, it } from "vitest";

import type { PresetCatalog } from "../../src/preset/catalog-types.ts";
import type { Preset } from "../../src/preset/fields.ts";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
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
import { renderBlocks, resolveBlocks } from "../../src/sql/index.ts";

const preset = (
  blocks: readonly string[],
  conventions: Partial<Preset> = {},
): Preset => ({ ...DEFAULT_CONVENTIONS, ...conventions, blocks });

describe("resolvePreset", () => {
  it("adds what comments requires, with a reason per block", () => {
    const resolved = resolvePreset(preset(["comments"]));
    expect(resolved.blocks.map((block) => [block.name, block.reason])).toEqual([
      ["updated-at", "required by memberships"],
      ["memberships", "required by permissions, comments and messaging"],
      ["permissions", "required by comments, subjects and messaging"],
      ["comments", "selected"],
      ["subjects", "required by comments and messaging"],
      ["messaging", "required by comments"],
    ]);
    expect(resolved.blocks.find((block) => block.selected)).toMatchObject({
      selected: true,
      requiredBy: [],
      category: "collaboration",
      title: expect.any(String),
    });
    expect(resolved.conflicts).toEqual([]);
    expect(resolved.manifests.map((manifest) => manifest.name)).toEqual([
      "permissions",
      "comments",
      "messaging",
      "subjects",
      "memberships",
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
      to: "permissions",
    });
    expect(
      resolved.integrations.some((each) => each.to === "jsonb-schemas"),
    ).toBe(false);
  });

  it("takes access requires from the permissions model", () => {
    const roles = resolvePreset(preset(["permissions"]));
    expect(roles.blocks.map((block) => block.name)).toEqual([
      "updated-at",
      "memberships",
      "permissions",
    ]);

    const provider = resolvePreset(
      preset(["permissions"], { access: "provider" }),
    );

    expect(provider.blocks.map((block) => block.name)).toEqual(["permissions"]);
  });

  it("refuses blocks that need tenants under a user or no scope", () => {
    const resolved = resolvePreset(
      preset(["profiles", "organizations", "memberships", "drive"], {
        scope: "user",
      }),
    );

    expect(resolved.blocks.map((block) => block.name)).toEqual(["profiles"]);
    expect(resolved.conflicts).toEqual([
      {
        block: "organizations",
        reason: 'it needs tenants, and scope "user" has none',
      },
      { block: "memberships", reason: 'scope "user" has no tenants' },
      { block: "drive", reason: 'it needs tenants, and scope "user" has none' },
    ]);
    expect(
      presetBlockConflict({ scope: "none", access: "roles" }, "push"),
    ).toBeUndefined();
    expect(
      presetBlockConflict({ scope: "tenant", access: "roles" }, "comments"),
    ).toBeUndefined();
  });

  it("runs tags and notifications without tenants per user or in one space, but not comments", () => {
    for (const scope of ["user", "none"] as const) {
      const resolved = resolvePreset(
        preset(["tags", "notifications"], { scope }),
      );

      expect(resolved.conflicts).toEqual([]);
      expect(resolvePreset(preset(["comments"], { scope })).conflicts).toEqual([
        {
          block: "comments",
          reason: `it needs tenants, and scope "${scope}" has none`,
        },
      ]);
      const names = resolved.blocks.map((block) => block.name);
      expect(names).toEqual(expect.arrayContaining(["tags", "notifications"]));
      expect(names).not.toContain("memberships");
      expect(names).not.toContain("permissions");
    }

    expect(
      resolvePreset(preset(["tags"])).blocks.map((block) => block.name),
    ).toEqual(expect.arrayContaining(["memberships", "permissions"]));
  });

  it("refuses a tenant name a block's tables already use", () => {
    expect(
      resolvePreset(preset(["teams"], { tenantName: "team" })).conflicts,
    ).toEqual([
      {
        block: "teams",
        field: "tenantName",
        reason:
          'tenant name "team" renames the tenant tables and columns to names the teams block already uses',
      },
    ]);
    expect(
      resolvePreset(preset(["teams"], { tenantName: "workspace" })).conflicts,
    ).toEqual([]);
    expect(
      resolvePreset(preset(["profiles"], { tenantName: "team" })).conflicts.map(
        (conflict) => conflict.block,
      ),
    ).toEqual(["profiles"]);
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

/** `names` with each composite replaced by the blocks it is made of. */
const withoutComposites = (names: readonly string[]): string[] =>
  names.flatMap((name) => {
    if (name === "support") {
      // The inbox block also installs the Chat SDK state tables.
      return ["chat-sdk-state", ...withoutComposites(PARTS_OF(name))];
    }

    if (name === "saas") {
      // `invitations` is an SQL module of `organizations`, not a part.
      return ["invitations", ...withoutComposites(PARTS_OF(name))];
    }

    const parts = Object.keys(
      BLOCK_MANIFESTS.find((block) => block.name === name)?.composes ?? {},
    );

    return parts.length === 0 ? [name] : withoutComposites(parts);
  });

const PARTS_OF = (name: string): string[] =>
  Object.keys(
    BLOCK_MANIFESTS.find((block) => block.name === name)?.composes ?? {},
  );

describe("named presets", () => {
  it.each(PRESET_NAMES)("%s resolves without conflicts and renders", (name) => {
    const resolved = resolvePreset(namedPreset(name));
    expect(resolved.conflicts).toEqual([]);
    const names = resolved.blocks.map((block) => block.name);
    // The resolver agrees with the SQL registry on the full set.
    const { instances = {} } = PRESETS[name];
    const blocks = withoutComposites(PRESETS[name].blocks);
    const own = new Set(resolveBlocks(blocks).map((module) => module.name));

    const extra = Object.entries(instances).map(
      ([key, instance]) => instance.block ?? key,
    );

    expect(names.toSorted()).toEqual(
      resolveBlocks([...blocks, ...extra])
        .map((module) => module.name)
        .filter((each) => own.has(each) || !extra.includes(each))
        .toSorted(),
    );
    expect(renderBlocks(names).length).toBeGreaterThan(0);
  });

  it("builds every preset after the starters on saas", () => {
    for (const name of PRESET_NAMES) {
      if (PRESETS[name].group === "starters") {
        continue;
      }

      const installed = resolvePreset(namedPreset(name)).blocks.map(
        (block) => block.name,
      );

      expect(installed).toEqual(
        expect.arrayContaining(
          resolvePreset(namedPreset("saas")).blocks.map((block) => block.name),
        ),
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
