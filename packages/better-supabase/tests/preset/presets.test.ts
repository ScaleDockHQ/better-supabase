import { describe, expect, it } from "vitest";

import {
  DEFAULT_PRESET_NAME,
  defaultPreset,
  defaultPresetCode,
  encodePreset,
  isPresetName,
  namedPreset,
} from "../../src/preset/index.ts";

describe("the default preset", () => {
  it("is saas", () => {
    expect(DEFAULT_PRESET_NAME).toBe("saas");
    expect(isPresetName(DEFAULT_PRESET_NAME)).toBe(true);
    expect(defaultPreset()).toEqual(namedPreset("saas"));
  });

  it("keeps its code, so a stored default still opens", () => {
    expect(defaultPresetCode()).toBe("1pWEF3d578B1iGt16");
    expect(defaultPresetCode()).toBe(encodePreset(defaultPreset()));
  });
});
