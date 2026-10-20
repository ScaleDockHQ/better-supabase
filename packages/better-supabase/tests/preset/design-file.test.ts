import { describe, expect, it } from "vitest";

import {
  type CreateDesign,
  decodeDesign,
  DESIGN_FILE,
  designFileSource,
  encodeDesign,
  encodePreset,
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

    expect(file).toEqual({
      preset: encodePreset(namedPreset("minimal")),
      design: { version: 1, ...DESIGN },
    });
    expect(text.endsWith("}\n")).toBe(true);
    expect(readDesignFile(text)).toEqual({
      preset: namedPreset("minimal"),
      design: DESIGN,
    });
  });

  it("names the file Create downloads", () => {
    expect(DESIGN_FILE).toBe("better-supabase.design.json");
  });

  it("reads a preset name and a file without a design", () => {
    expect(readDesignFile(JSON.stringify({ preset: "crm" }))).toEqual({
      preset: namedPreset("crm"),
      design: {},
    });
  });

  it("rejects text that isn't a design file", () => {
    expect(() => readDesignFile("{")).toThrow("not JSON");
    expect(() => readDesignFile("[]")).toThrow(
      "expected an object with preset and design",
    );
    expect(() => readDesignFile(JSON.stringify({ design: {} }))).toThrow(
      "preset must be a preset name or code",
    );
    expect(() =>
      readDesignFile(JSON.stringify({ preset: "crm", extra: 1 })),
    ).toThrow('unknown key "extra"');
    expect(() =>
      readDesignFile(JSON.stringify({ preset: "crm", design: { tables: {} } })),
    ).toThrow('design: unknown key "tables"');
  });

  it("refuses an invalid design when writing", () => {
    // SAFETY: the test passes a key a design doesn't have on purpose.
    const invalid = { tables: {} } as unknown as CreateDesign;

    expect(() => designFileSource(minimal, invalid)).toThrow(TypeError);
  });
});
