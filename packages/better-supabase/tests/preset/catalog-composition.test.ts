import { describe, expect, it } from "vitest";

import { PORT_NAMES } from "../../src/blocks/ports.ts";
import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";
import { SQL_MODULES } from "../../src/sql/index.ts";

describe("the catalog's composition data", () => {
  it("lists every port a manifest provides or consumes by a known name", () => {
    for (const manifest of PRESET_CATALOG.manifests) {
      for (const port of [
        ...manifest.provides,
        ...Object.keys(manifest.consumes),
      ]) {
        expect(PORT_NAMES).toContain(port);
      }
    }
  });

  it("keeps the ports that were missing from the catalog", () => {
    const provided = PRESET_CATALOG.manifests.flatMap((each) => each.provides);

    expect(provided).toContain("mailer");
    expect(provided).toContain("recordAccess");
  });

  it("names a generic block for every contribution", () => {
    for (const block of PRESET_CATALOG.blocks) {
      for (const target of block.contributes ?? []) {
        expect(Object.keys(SQL_MODULES)).toContain(target);
      }
    }
  });

  it("fires only events some block declares", () => {
    const events = new Set(
      PRESET_CATALOG.manifests.flatMap((each) => each.events?.types ?? []),
    );

    for (const manifest of PRESET_CATALOG.manifests) {
      for (const automation of manifest.automations ?? []) {
        expect(events.has(automation.trigger)).toBe(true);
      }
    }
  });

  it("gives every automation a unique key", () => {
    const keys = PRESET_CATALOG.manifests.flatMap((each) =>
      (each.automations ?? []).map((automation) => automation.key),
    );

    expect(new Set(keys).size).toBe(keys.length);
  });
});
