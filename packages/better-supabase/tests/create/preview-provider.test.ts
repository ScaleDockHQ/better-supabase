import { describe, expect, it } from "vitest";

import type { Preset, PresetName, PresetSpec } from "../../src/preset/index.ts";

import {
  previewAccessProvider,
  previewFiles,
  tableStatements,
} from "../../src/create/index.ts";
import {
  presetSpec,
  namedPreset,
  PRESET_NAMES,
  PRESETS,
} from "../../src/preset/index.ts";

const withProvider = (preset: Preset): PresetName | PresetSpec =>
  presetSpec({ ...preset, access: "provider" });

describe("previewFiles", () => {
  it("renders a design's app tables", () => {
    const files = previewFiles(presetSpec(namedPreset("saas")), {
      appTables: {
        projects: { columns: { title: { type: "text", nullable: false } } },
      },
    });

    const sql = tableStatements(files, "public.projects").join("\n");

    expect(sql).toMatch(/create table if not exists "public"\."projects"/u);
    expect(sql).toMatch(/"organization_id" uuid not null/u);
    expect(sql).toMatch(/add column if not exists "title" text not null;/u);
  });

  // sso needs roleOrder under access: provider; the next test covers that.
  it.each(PRESET_NAMES.filter((name) => !PRESETS[name].blocks.includes("sso")))(
    "renders the %s preset with access: provider",
    (name) => {
      expect(
        previewFiles(withProvider(namedPreset(name))).length,
      ).toBeGreaterThan(0);
    },
  );

  it("keeps a real config error, such as sso without roleOrder", () => {
    expect(() => previewFiles(withProvider(namedPreset("everything")))).toThrow(
      /roleOrder/u,
    );
  });

  it("calls the placeholder functions only for access: provider", () => {
    const sql = (spec: PresetName | PresetSpec): string =>
      previewFiles(spec)
        .map((file) => file.contents)
        .join("\n");

    expect(sql(withProvider(namedPreset("saas")))).toContain(
      "provider.ids_with(",
    );
    expect(sql(presetSpec(namedPreset("saas")))).not.toContain(
      "provider.ids_with(",
    );
  });

  it("renders a bigint workspace tenant", () => {
    const code = withProvider({
      ...namedPreset("saas"),
      idType: "bigint",
      tenantName: "workspace",
    });

    expect(previewFiles(code).length).toBeGreaterThan(0);
  });
});

describe("previewAccessProvider", () => {
  it("uses the preset's tenant name and id type", () => {
    const provider = previewAccessProvider({
      ...namedPreset("saas"),
      idType: "bigint",
      tenantName: "workspace",
    });

    expect(provider.scope).toBe("workspace");
    expect(provider.idType).toBe("bigint");
  });
});
