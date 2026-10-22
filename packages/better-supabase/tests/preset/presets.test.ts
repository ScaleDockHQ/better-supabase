import { describe, expect, it } from "vitest";

import {
  DEFAULT_PRESET_NAME,
  defaultPreset,
  isPresetName,
  namedPreset,
} from "../../src/preset/index.ts";

describe("the default preset", () => {
  it("is saas", () => {
    expect(DEFAULT_PRESET_NAME).toBe("saas");
    expect(isPresetName(DEFAULT_PRESET_NAME)).toBe(true);
    expect(defaultPreset()).toEqual(namedPreset("saas"));
  });
});
