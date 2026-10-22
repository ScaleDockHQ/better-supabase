import { describe, expect, it } from "vitest";

import {
  convertConfigPresetCode,
  convertDesignFile,
  decodeLegacyPresetCode,
  DESIGN_FILE_NAME,
  isLegacyPresetCode,
} from "../../src/cli/codemod-preset-code.ts";
import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";
import { presetOf } from "../../src/preset/index.ts";
import fixture from "./fixtures/preset-codes-0.14.json" with { type: "json" };

const codemod = CODEMODS["0.15"]!;

const sorted = (list: readonly string[]): string[] => list.toSorted();

describe("decodeLegacyPresetCode", () => {
  it.each(fixture.codes)("reads the 0.14 code of $name", ({ code, preset }) => {
    expect(isLegacyPresetCode(code)).toBe(true);

    const { blocks, ...fields } = decodeLegacyPresetCode(code);
    const { blocks: expected, ...expectedFields } = preset;

    expect(fields).toEqual(expectedFields);
    expect(sorted(blocks as readonly string[])).toEqual(sorted(expected));
  });

  it("doesn't take a preset name or a design code for a code", () => {
    expect(isLegacyPresetCode("saas")).toBe(false);
    expect(isLegacyPresetCode("0abc")).toBe(false);
  });
});

describe("convertConfigPresetCode", () => {
  it.each(fixture.codes)(
    "turns the code of $name into the preset it holds, in JSON",
    ({ code, preset }) => {
      const edit = convertConfigPresetCode(
        `${JSON.stringify({ preset: code }, null, 2)}\n`,
        true,
      );

      expect(edit.ok).toBe(true);

      const written = edit.ok ? JSON.parse(edit.text).preset : undefined;

      expect(sorted(presetOf(written).blocks)).toEqual(sorted(preset.blocks));
      expect(presetOf(written).framework).toBe(preset.framework);
    },
  );

  it("writes a preset object into better-supabase.config.ts", () => {
    const code = fixture.codes.find((each) => each.name === "conventions")!;

    const edit = convertConfigPresetCode(
      `import { defineConfig } from 'better-supabase/config';\n\nexport default defineConfig({\n  preset: '${code.code}',\n});\n`,
      false,
    );

    expect(edit.ok).toBe(true);
    expect(edit.ok ? edit.text : "").not.toContain(code.code);
    expect(edit.ok ? edit.text : "").toMatch(/preset: (?:\{|')/);
  });

  it("reads the code in a /create URL", () => {
    const edit = convertConfigPresetCode(
      `{ "preset": "https://bettersupabase.com/create?preset=${fixture.codes[0]!.code}" }\n`,
      true,
    );

    expect(edit.ok && JSON.parse(edit.text).preset).not.toMatch(/create/);
  });

  it("leaves a URL with a design for review", () => {
    const source = `{ "preset": "https://bettersupabase.com/create?preset=${fixture.codes[0]!.code}&design=0abc" }\n`;

    expect(convertConfigPresetCode(source, true)).toEqual({
      ok: true,
      text: source,
    });
  });

  it("leaves a preset name as it is", () => {
    const source = '{ "preset": "saas" }\n';

    expect(convertConfigPresetCode(source, true)).toEqual({
      ok: true,
      text: source,
    });
  });
});

describe("convertDesignFile", () => {
  it("moves the preset into the design", () => {
    const edit = convertDesignFile(
      JSON.stringify({
        preset: fixture.codes[0]!.code,
        design: { positions: { profiles: [0, 0] } },
      }),
    );

    expect(edit.ok).toBe(true);

    const written = edit.ok ? JSON.parse(edit.text) : {};

    expect(written.positions).toEqual({ profiles: [0, 0] });
    expect(written.design).toBeUndefined();
    expect(presetOf(written.preset).blocks).toEqual(["profiles"]);
  });

  it("runs on design files through the 0.15 codemod", () => {
    expect(DESIGN_FILE_NAME.test("app/better-supabase.design.json")).toBe(true);

    const result = applyCodemod(
      codemod,
      JSON.stringify({ preset: "saas", design: {} }),
      "better-supabase.design.json",
    );

    expect(JSON.parse(result.text)).toEqual({ preset: "saas" });
  });
});

describe("presetOf", () => {
  it("names the codemod for a 0.14 code", () => {
    expect(() => presetOf(fixture.codes[1]!.code)).toThrow(
      /better-supabase codemod 0\.15/,
    );
  });
});
