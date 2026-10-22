import { describe, expect, it } from "vitest";

import type { CreateDesign } from "../../src/preset/index.ts";

import {
  decodeDesign,
  DESIGN_FILE,
  designFileSource,
  encodeDesign,
  namedPreset,
  parseDesign,
  readDesignFile,
  resolvePreset,
} from "../../src/preset/index.ts";

const DESIGN: CreateDesign = {
  appTables: {
    notes: {
      scope: "user",
      columns: { body: { type: "text", comment: "The note" } },
    },
  },
  positions: { "public.notes": [120, 40] },
};

describe("parseDesign", () => {
  it("accepts what decodeDesign accepts and drops empty parts", async () => {
    expect(parseDesign({ ...DESIGN, extraColumns: { profiles: {} } })).toEqual(
      DESIGN,
    );
    expect(parseDesign(DESIGN)).toEqual(
      await decodeDesign(await encodeDesign(DESIGN)),
    );
  });

  it("throws a TypeError naming the first problem", () => {
    expect(() => parseDesign(null)).toThrow("design must be an object");
    expect(() => parseDesign({ tables: {} })).toThrow(
      'design: unknown key "tables"',
    );
    expect(() =>
      parseDesign({ extraColumns: { nowhere: { tier: "text" } } }),
    ).toThrow('"nowhere" is not a block');
    expect(() => parseDesign({ version: 99 })).toThrow(
      "update better-supabase",
    );
  });
});

describe("design files", () => {
  const minimal = resolvePreset(namedPreset("minimal"));

  it("round-trips the preset and design, with the format version", () => {
    const text = designFileSource(minimal, DESIGN);
    const file: unknown = JSON.parse(text);

    expect(file).toEqual({ version: 7, preset: "minimal", ...DESIGN });
    expect(text.endsWith("}\n")).toBe(true);
    expect(readDesignFile(text)).toEqual({
      preset: namedPreset("minimal"),
      design: DESIGN,
    });
  });

  it("names the file Create downloads", () => {
    expect(DESIGN_FILE).toBe("better-supabase.design.json");
  });

  it("writes a preset object for a preset that isn't a named one", () => {
    const custom = resolvePreset({
      ...namedPreset("minimal"),
      casing: "camel",
      blocks: ["tags"],
    });

    const file: unknown = JSON.parse(designFileSource(custom, {}));

    expect(file).toEqual({
      version: 7,
      preset: { casing: "camel", blocks: ["tags"] },
    });
    expect(readDesignFile(JSON.stringify(file)).preset).toEqual(custom.preset);
  });

  it("reads a preset name and a file without a design", () => {
    expect(readDesignFile(JSON.stringify({ preset: "crm" }))).toEqual({
      preset: namedPreset("crm"),
      design: {},
    });
  });

  it("rejects text that isn't a design file", () => {
    expect(() => readDesignFile("{")).toThrow("not JSON");
    expect(() => readDesignFile("[]")).toThrow("design must be an object");
    expect(() => readDesignFile(JSON.stringify({}))).toThrow(
      "design file: preset is missing",
    );
    expect(() =>
      readDesignFile(JSON.stringify({ preset: "crm", extra: 1 })),
    ).toThrow('unknown key "extra"');
    expect(() =>
      readDesignFile(
        JSON.stringify({ preset: "1pWEF3d578B1iGt16", design: {} }),
      ),
    ).toThrow("better-supabase codemod 0.15");
  });

  it("refuses an invalid design when writing", () => {
    // SAFETY: the test passes a key a design doesn't have on purpose.
    const invalid = { tables: {} } as unknown as CreateDesign;

    expect(() => designFileSource(minimal, invalid)).toThrow(TypeError);
  });
});
