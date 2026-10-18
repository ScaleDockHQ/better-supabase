import {
  encodePreset,
  namedPreset,
  type Preset,
  PRESET_NAMES,
  PRESETS,
} from "better-supabase/preset";
import { describe, expect, test } from "vitest";

import {
  previewAccessProvider,
  previewFiles,
} from "../../lib/preview-provider";

const withProvider = (preset: Preset): string =>
  encodePreset({ ...preset, access: "provider" });

describe("previewFiles", () => {
  // sso needs roleOrder under access: provider; the next test covers that.
  test.each(
    PRESET_NAMES.filter((name) => !PRESETS[name].blocks.includes("sso")),
  )("renders the %s preset with access: provider", (name) => {
    expect(
      previewFiles(withProvider(namedPreset(name))).length,
    ).toBeGreaterThan(0);
  });

  test("keeps a real config error, such as sso without roleOrder", () => {
    expect(() => previewFiles(withProvider(namedPreset("everything")))).toThrow(
      /roleOrder/u,
    );
  });

  test("calls the placeholder functions only for access: provider", () => {
    const sql = (code: string): string =>
      previewFiles(code)
        .map((file) => file.contents)
        .join("\n");

    expect(sql(withProvider(namedPreset("saas")))).toContain(
      "provider.ids_with(",
    );
    expect(sql(encodePreset(namedPreset("saas")))).not.toContain(
      "provider.ids_with(",
    );
  });

  test("renders a bigint workspace tenant", () => {
    const code = withProvider({
      ...namedPreset("saas"),
      idType: "bigint",
      tenantName: "workspace",
    });

    expect(previewFiles(code).length).toBeGreaterThan(0);
  });
});

describe("previewAccessProvider", () => {
  test("uses the preset's tenant name and id type", () => {
    const provider = previewAccessProvider({
      ...namedPreset("saas"),
      idType: "bigint",
      tenantName: "workspace",
    });

    expect(provider.scope).toBe("workspace");
    expect(provider.idType).toBe("bigint");
  });
});
