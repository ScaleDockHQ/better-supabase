import { describe, expect, it } from "vitest";

import { INTEGRATION_NAMES } from "../../src/config/names.ts";
import { PRESET_BLOCKS } from "../../src/preset/blocks.ts";
import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";
import { PRESET_FIELDS } from "../../src/preset/fields.ts";
import { SQL_MODULES } from "../../src/sql/index.ts";

// `pnpm catalog:check` fails when catalog.generated.ts is stale.
describe("the preset catalog", () => {
  it("has a block for every SQL module", () => {
    expect(PRESET_CATALOG.blocks.map((block) => block.name).toSorted()).toEqual(
      Object.keys(SQL_MODULES).toSorted(),
    );
  });

  it("names a manifest for every block", () => {
    const manifests = new Set(
      PRESET_CATALOG.manifests.map((manifest) => manifest.name),
    );

    for (const block of PRESET_CATALOG.blocks) {
      expect(manifests).toContain(block.manifest);
    }
  });
});

describe("PRESET_BLOCKS", () => {
  it("lists every SQL module once, and nothing else", () => {
    const listed = PRESET_BLOCKS.filter((name) => name !== null);
    expect(new Set(listed).size).toBe(listed.length);
    expect(listed.toSorted()).toEqual(Object.keys(SQL_MODULES).toSorted());
  });
});

describe("PRESET_FIELDS", () => {
  it("fit each field's values in its bits", () => {
    for (const field of PRESET_FIELDS) {
      const capacity = field.multi === true ? field.bits : 2 ** field.bits;
      expect(field.values.length).toBeLessThanOrEqual(capacity);
      expect(new Set(field.values).size).toBe(field.values.length);
    }
  });

  it("covers every integration name", () => {
    const integrations = PRESET_FIELDS.find(
      (field) => field.key === "integrations",
    );

    expect(integrations?.values).toEqual(
      expect.arrayContaining([...INTEGRATION_NAMES]),
    );
  });
});
