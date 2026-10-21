/* oxlint-disable eslint/no-bitwise -- design codes are bigint bit fields. */

import { describe, expect, it } from "vitest";

import type { PresetLayout } from "../../src/preset/code.ts";
import type { Preset } from "../../src/preset/fields.ts";

import { PRESET_BLOCKS } from "../../src/preset/blocks.ts";
import {
  decodePreset,
  encodePreset,
  isPresetCode,
  withPresetField,
} from "../../src/preset/code.ts";
import {
  DEFAULT_CONVENTIONS,
  PRESET_FIELDS,
  PRESET_VERSION,
} from "../../src/preset/fields.ts";
import { namedPreset, PRESET_NAMES } from "../../src/preset/presets.ts";
import fixture from "./fixtures/codes-v1.json" with { type: "json" };

const inBlockOrder = (blocks: readonly string[]): string[] =>
  [...new Set(blocks)].toSorted(
    (a, b) => PRESET_BLOCKS.indexOf(a) - PRESET_BLOCKS.indexOf(b),
  );

describe("encodePreset and decodePreset", () => {
  it.each(PRESET_NAMES)("round-trips the %s preset", (name) => {
    const preset = namedPreset(name);
    const code = encodePreset(preset);
    expect(isPresetCode(code)).toBe(true);
    expect(code.charAt(0)).toBe("1");
    const decoded = decodePreset(code);
    expect(decoded).toEqual({
      preset: { ...preset, blocks: inBlockOrder(preset.blocks) },
      version: PRESET_VERSION,
      derived: [],
    });
  });

  it("round-trips every value of every field", () => {
    for (const field of PRESET_FIELDS) {
      for (const value of field.values) {
        const preset = {
          ...DEFAULT_CONVENTIONS,
          [field.key]: field.multi === true ? [value] : value,
          blocks: ["comments"],
        };

        expect(decodePreset(encodePreset(preset)).preset).toEqual(preset);
      }
    }
  });

  it("keeps several values of a multi field, in field order", () => {
    const preset: Preset = {
      ...DEFAULT_CONVENTIONS,
      integrations: ["react", "next", "mcp"],
      blocks: [],
    };

    expect(decodePreset(encodePreset(preset)).preset.integrations).toEqual([
      "next",
      "mcp",
      "react",
    ]);
  });

  it("fills unset fields with their defaults and drops duplicate blocks", () => {
    const code = encodePreset({ blocks: ["tags", "tags"] });
    expect(decodePreset(code).preset).toEqual({
      ...DEFAULT_CONVENTIONS,
      blocks: ["tags"],
    });
    expect(encodePreset({ blocks: [] })).toBe("10");
    expect(decodePreset("10").preset.blocks).toEqual([]);
  });

  it("rejects unknown blocks and values when encoding", () => {
    expect(() => encodePreset({ blocks: ["nope"] })).toThrow(
      'Preset block "nope" is not a block.',
    );
    expect(() =>
      encodePreset({ blocks: [], casing: "kebab" as Preset["casing"] }),
    ).toThrow('Preset casing "kebab" is not one of snake, camel.');
    expect(() =>
      encodePreset({
        blocks: [],
        framework: ["next"] as unknown as Preset["framework"],
      }),
    ).toThrow("Preset framework");
    expect(() =>
      encodePreset({
        blocks: [],
        integrations: "next" as unknown as Preset["integrations"],
      }),
    ).not.toThrow();
  });

  it("rejects what is not a code, and codes from a newer release", () => {
    expect(() => decodePreset("saas")).toThrow(
      '"saas" is not a preset code: a code starts with its version, such as "1".',
    );
    expect(() => decodePreset("1")).toThrow("is not a preset code");
    expect(() => decodePreset("9abc")).toThrow(
      "is version 9; this better-supabase reads up to 1. Upgrade better-supabase.",
    );
    expect(() => decodePreset("1a-b")).toThrow("is not a preset code");
    // casing index 3 is past its two values.
    const casingOffset = 5n + 2n;
    const code = `1${toBase62(3n << casingOffset)}`;
    expect(() => decodePreset(code)).toThrow(
      "sets a casing value this better-supabase doesn't know",
    );

    const blockOffset = BigInt(
      PRESET_FIELDS.reduce((sum, field) => sum + field.bits, 0),
    );

    const beyond = `1${toBase62(1n << (blockOffset + BigInt(PRESET_BLOCKS.length)))}`;
    expect(() => decodePreset(beyond)).toThrow("sets a blocks value");
    const integrations = `1${toBase62(1n << (blockOffset - 1n))}`;
    expect(() => decodePreset(integrations)).toThrow(
      "sets a integrations value",
    );
  });

  it("tells codes from preset names", () => {
    expect(isPresetCode("saas")).toBe(false);
    expect(isPresetCode("ai")).toBe(false);
    expect(isPresetCode("1abc")).toBe(true);
    expect(isPresetCode("1")).toBe(false);
  });
});

describe("withPresetField", () => {
  const preset: Preset = {
    ...DEFAULT_CONVENTIONS,
    blocks: ["tags", "comments"],
  };

  it("sets one convention and keeps the block order", () => {
    expect(withPresetField(preset, "casing", "camel")).toEqual({
      ...preset,
      casing: "camel",
    });
  });

  it("switches a value of a multi field on and off", () => {
    const on = withPresetField(preset, "integrations", "mcp");
    expect(on.integrations).toEqual(["mcp"]);
    const both = withPresetField(on, "integrations", "next");
    expect(both.integrations).toEqual(["next", "mcp"]);
    expect(withPresetField(both, "integrations", "mcp").integrations).toEqual([
      "next",
    ]);
  });

  it("rejects a value the field doesn't list", () => {
    expect(() => withPresetField(preset, "access", "owner")).toThrow(
      'Preset access "owner" is not one of roles, catalog, provider, custom.',
    );
  });
});

describe("older codes and tombstones", () => {
  const v1: PresetLayout = {
    fields: [
      {
        key: "casing",
        values: ["snake", "camel"],
        default: "snake",
        bits: 1,
        since: 1,
      },
    ],
    blocks: ["tags", "comments"],
    version: 1,
  };

  const v2: PresetLayout = {
    fields: [
      ...v1.fields,
      {
        key: "api",
        values: ["none", "api"],
        default: "api",
        bits: 1,
        since: 2,
      },
    ],
    blocks: [null, "comments", "rank"],
    version: 2,
  };

  it("decodes a version 1 code with the newer fields as derived defaults", () => {
    const code = encodePreset(
      { casing: "camel", blocks: ["tags", "comments"] },
      v1,
    );

    const decoded = decodePreset(code, v2);
    expect(decoded.version).toBe(1);
    expect(decoded.derived).toEqual(["api"]);
    expect(decoded.preset.api).toBe("api");
    expect(decoded.preset.casing).toBe("camel");
    // `tags` became a tombstone; `comments` keeps its bit.
    expect(decoded.preset.blocks).toEqual(["comments"]);
  });

  it("reads a version 2 code with every field", () => {
    const code = encodePreset({ api: "none", blocks: ["rank"] }, v2);
    expect(code.charAt(0)).toBe("2");
    expect(decodePreset(code, v2)).toMatchObject({
      version: 2,
      derived: [],
      preset: { api: "none", blocks: ["rank"] },
    });
  });
});

describe("the frozen version 1 codes", () => {
  it("has one code per named preset", () => {
    expect(fixture.version).toBe(1);

    for (const name of PRESET_NAMES) {
      expect(fixture.codes.map((each) => each.name)).toContain(name);
    }
  });

  // A released code must decode to the same selection forever. Never edit
  // this fixture: add `codes-v2.json` when PRESET_VERSION moves.
  it.each(fixture.codes)("decodes $name ($code)", ({ code, preset }) => {
    expect(decodePreset(code).preset).toEqual(preset);
  });
});

function toBase62(value: bigint): string {
  const digits =
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

  let out = "";
  let rest = value;

  do {
    out = digits.charAt(Number(rest % 62n)) + out;
    rest /= 62n;
  } while (rest > 0n);

  return out;
}
