import { describe, expect, it } from "vitest";

import type { PresetCatalog } from "../../src/preset/catalog-types.ts";
import type { Preset } from "../../src/preset/fields.ts";

import { blockClients } from "../../src/cli/commands/add.ts";
import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";
import { DEFAULT_CONVENTIONS } from "../../src/preset/fields.ts";
import { removeComposite, resolvePreset } from "../../src/preset/resolve.ts";

const catalog: PresetCatalog = {
  ...PRESET_CATALOG,
  manifests: [
    ...PRESET_CATALOG.manifests,
    {
      name: "talk",
      sql: [],
      category: "collaboration",
      client: null,
      consumes: {},
      provides: [],
      composes: ["comments", "tags"],
      defaults: { comments: { options: { mentions: true, depth: 2 } } },
    },
  ],
};

const preset = (
  blocks: readonly string[],
  extra: Partial<Preset> = {},
): Preset => ({ ...DEFAULT_CONVENTIONS, ...extra, blocks });

describe("composite blocks", () => {
  it("installs the parts and says why", () => {
    const resolved = resolvePreset(preset(["talk"]), catalog);
    const reasons = new Map(resolved.blocks.map((b) => [b.name, b.reason]));

    expect(reasons.get("comments")).toBe("part of talk");
    expect(reasons.get("tags")).toBe("part of talk");
    expect(resolved.composites.map((c) => c.name)).toEqual(["talk"]);
    expect(resolved.manifests.map((m) => m.name)).toContain("talk");
    expect(resolved.conflicts).toEqual([]);
  });

  it("lets the app win over a composite default, key by key", () => {
    const resolved = resolvePreset(
      preset(["talk"], { instances: { comments: { options: { depth: 5 } } } }),
      catalog,
    );

    expect(resolved.partOptions["comments"]).toEqual({
      mentions: true,
      depth: 5,
    });
  });

  it("keeps the parts when the composite goes", () => {
    const removal = removeComposite(preset(["talk"]), "talk", {}, catalog);

    expect(removal.blocks).toEqual(["comments", "tags"]);
    expect(removal.removed).toEqual([]);
  });

  it("takes the parts too with withParts, except those still needed", () => {
    const removal = removeComposite(
      preset(["talk", "tags"]),
      "talk",
      { withParts: true },
      catalog,
    );

    expect(removal.removed).toEqual(["comments"]);
    expect(removal.kept.map((k) => k.name)).toEqual(["tags"]);
  });

  it("refuses a block that is not a composite", () => {
    expect(() =>
      removeComposite(preset(["comments"]), "comments", {}, catalog),
    ).toThrow(/not a composite/u);
  });

  it("wires a composite's client in lib/blocks.ts next to its parts", () => {
    const withClient: PresetCatalog = {
      ...catalog,
      manifests: catalog.manifests.map((manifest) =>
        manifest.name === "talk"
          ? {
              ...manifest,
              client: {
                export: "talkBlock",
                subpath: "better-supabase/blocks/talk",
              },
            }
          : manifest,
      ),
    };

    const clients = blockClients(
      resolvePreset(preset(["talk"]), withClient).manifests,
    );

    expect(clients.map((client) => client.key)).toEqual(
      expect.arrayContaining(["talk", "comments", "tags"]),
    );
  });
});
