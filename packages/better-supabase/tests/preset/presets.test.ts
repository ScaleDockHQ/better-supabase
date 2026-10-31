import { describe, expect, it } from "vitest";

import {
  DEFAULT_PRESET_NAME,
  defaultPreset,
  isPresetName,
  namedPreset,
} from "../../src/preset/index.ts";
import { resolvePreset } from "../../src/preset/resolve.ts";

describe("the default preset", () => {
  it("is saas", () => {
    expect(DEFAULT_PRESET_NAME).toBe("saas");
    expect(isPresetName(DEFAULT_PRESET_NAME)).toBe(true);
    expect(defaultPreset()).toEqual(namedPreset("saas"));
  });
});

describe("the psa, ats and intranet presets", () => {
  it.each([
    ["psa", ["billable-time", "time-tracking", "invoices", "shifts"]],
    ["ats", ["hiring", "bookings", "signatures"]],
    ["intranet", ["announcements", "acknowledgements", "knowledge"]],
  ] as const)("%s resolves with its own blocks", (name, expected) => {
    expect(isPresetName(name)).toBe(true);

    const resolved = resolvePreset(namedPreset(name)).blocks.map(
      (block) => block.name,
    );

    for (const block of expected) {
      expect(resolved).toContain(block);
    }
  });
});
