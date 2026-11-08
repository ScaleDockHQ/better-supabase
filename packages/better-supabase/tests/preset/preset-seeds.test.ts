import { describe, expect, it } from "vitest";

import type { PresetCatalog } from "../../src/preset/catalog-types.ts";

import { seedIssues } from "../../src/create/seed-issues.ts";
import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";
import { expandPreset, mergeSeedConfig } from "../../src/preset/config.ts";
import {
  PRESET_NAMES,
  PRESETS,
  namedPreset,
} from "../../src/preset/presets.ts";
import { resolvePreset } from "../../src/preset/resolve.ts";

/**
 * The `pipelines` (`b2b-sales`, `recruiting`) and `accounting` (`generic`)
 * modules declare their variants on other branches. The integrator flips this
 * to `true` once those branches are merged and the catalog is regenerated, so
 * the catalog assertion below runs.
 */
const PRESET_VARIANTS_IN_CATALOG = true;

const SEEDED = PRESET_NAMES.filter((name) => PRESETS[name].seeds !== undefined);

/** A catalog that declares every variant the presets name. */
function fakeCatalog(): Pick<PresetCatalog, "blocks"> {
  const declared = new Map<string, Set<string>>();

  for (const name of SEEDED) {
    for (const [block, variant] of Object.entries(
      PRESETS[name].seeds?.variants ?? {},
    )) {
      declared.set(block, (declared.get(block) ?? new Set()).add(variant));
    }
  }

  return {
    // SAFETY: the entries copy a real catalog block and replace its name and seeds.
    blocks: [...declared].map(([name, variants]) => ({
      ...(PRESET_CATALOG.blocks.find((block) => block.name === name) ??
        PRESET_CATALOG.blocks[0]),
      name,
      seeds: { variants: [...variants] },
    })) as PresetCatalog["blocks"],
  };
}

describe("named preset seeds", () => {
  it("lists variants for crm, ats and erp", () => {
    expect(PRESETS.crm.seeds).toEqual({ variants: { pipelines: "b2b-sales" } });
    expect(PRESETS.ats.seeds).toEqual({
      variants: { pipelines: "recruiting" },
    });
    expect(PRESETS.erp.seeds).toEqual({ variants: { accounting: "generic" } });
  });

  it("names only blocks the preset installs", () => {
    for (const name of SEEDED) {
      const installed = new Set(
        resolvePreset(namedPreset(name)).blocks.map((block) => block.name),
      );

      for (const block of Object.keys(PRESETS[name].seeds?.variants ?? {})) {
        expect([name, block, installed.has(block)]).toEqual([
          name,
          block,
          true,
        ]);
      }
    }
  });

  it("passes the seed check against a catalog that declares them", () => {
    for (const name of SEEDED) {
      expect(seedIssues({ ...PRESETS[name] }, fakeCatalog())).toEqual([]);
    }
  });

  it.skipIf(!PRESET_VARIANTS_IN_CATALOG)(
    "passes the seed check against the generated catalog",
    () => {
      for (const name of SEEDED) {
        expect(seedIssues({ ...PRESETS[name] })).toEqual([]);
      }
    },
  );
});

describe("mergeSeedConfig", () => {
  const installed = new Set(["pipelines"]);
  const preset = { variants: { pipelines: "b2b-sales", ghost: "x" } };

  it("fills the config from the preset and skips blocks it does not install", () => {
    expect(mergeSeedConfig(preset, undefined, installed)).toEqual({
      defaults: { variants: { pipelines: "b2b-sales" } },
    });
  });

  it("lets the app's variants and locale win", () => {
    expect(
      mergeSeedConfig(
        { ...preset, locale: "nl" },
        { defaults: { variants: { pipelines: "custom" }, onCreate: false } },
        installed,
      ),
    ).toEqual({
      defaults: {
        variants: { pipelines: "custom" },
        onCreate: false,
        locale: "nl",
      },
    });
  });

  it("keeps defaults off and leaves other seed keys alone", () => {
    expect(mergeSeedConfig(preset, { defaults: false }, installed)).toEqual({
      defaults: false,
    });
    expect(mergeSeedConfig(preset, { file: "x.sql" }, installed)).toEqual({
      file: "x.sql",
      defaults: { variants: { pipelines: "b2b-sales" } },
    });
  });

  it("returns the config as is without preset seeds", () => {
    const own = { file: "x.sql" };

    expect(mergeSeedConfig(undefined, own, installed)).toBe(own);
    expect(mergeSeedConfig({}, undefined, installed)).toBeUndefined();
  });
});

describe("expandPreset seeds", () => {
  it("writes the preset's variants under the app's seed config", () => {
    expect(expandPreset({ preset: "crm" }).database?.seed).toEqual({
      defaults: { variants: { pipelines: "b2b-sales" } },
    });
    expect(
      expandPreset({
        preset: "crm",
        database: { seed: { defaults: { variants: { pipelines: "mine" } } } },
      }).database?.seed?.defaults,
    ).toEqual({ variants: { pipelines: "mine" } });
  });

  it("adds nothing for a preset without seeds", () => {
    expect(expandPreset({ preset: "chat" }).database?.seed).toBeUndefined();
  });

  it("expands twice to the same config", () => {
    const once = expandPreset({ preset: "ats" });

    expect(expandPreset(once)).toEqual(once);
  });
});
