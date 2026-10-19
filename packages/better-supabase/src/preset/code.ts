import type { Preset, PresetCodeField, PresetFieldKey } from "./fields.ts";

import { PRESET_BLOCKS } from "./blocks.ts";
import {
  DEFAULT_CONVENTIONS,
  PRESET_FIELDS,
  PRESET_VERSION,
} from "./fields.ts";

const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/** What `decodePreset` returns. */
export interface DecodedPreset {
  readonly preset: Preset;
  /** The code version the code was written with. */
  readonly version: number;
  /** Fields the code's version predates, set to their defaults. */
  readonly derived: readonly PresetFieldKey[];
}

/** The fields and blocks a code is read against; tests pass their own. */
export interface PresetLayout {
  readonly fields: readonly PresetCodeField[];
  readonly blocks: readonly (string | null)[];
  readonly version: number;
}

const LAYOUT: PresetLayout = {
  fields: PRESET_FIELDS,
  blocks: PRESET_BLOCKS,
  version: PRESET_VERSION,
};

function toBase62(value: bigint): string {
  if (value === 0n) {
    return "0";
  }

  let out = "";
  let rest = value;

  while (rest > 0n) {
    out = BASE62.charAt(Number(rest % 62n)) + out;
    rest /= 62n;
  }

  return out;
}

/** `text` holds only base62 digits (`isPresetCode`). */
function fromBase62(text: string): bigint {
  let value = 0n;

  for (const char of text) {
    value = value * 62n + BigInt(BASE62.indexOf(char));
  }

  return value;
}

const mask = (bits: number): bigint => (1n << BigInt(bits)) - 1n;

/** The conventions as a record, for reading a field by its key. */
function valueOf(
  preset: Partial<Preset>,
  key: string,
): string | readonly string[] | undefined {
  const entry: unknown = Object.entries(preset).find(
    ([name]) => name === key,
  )?.[1];

  if (typeof entry === "string") {
    return entry;
  }

  return Array.isArray(entry) &&
    entry.every((each): each is string => typeof each === "string")
    ? entry
    : undefined;
}

function indexIn(field: PresetCodeField, value: string): number {
  const index = field.values.indexOf(value);

  if (index === -1) {
    throw new TypeError(
      `Preset ${field.key} "${value}" is not one of ${field.values.join(", ")}.`,
    );
  }

  return index;
}

/**
 * The preset as a code: a version character, then base62 of one BigInt that
 * holds each field's value index and a bit per selected block.
 */
export function encodePreset(
  preset: Partial<Preset>,
  layout: PresetLayout = LAYOUT,
): string {
  return encodeWith((key) => valueOf(preset, key), preset.blocks ?? [], layout);
}

function encodeWith(
  read: (key: string) => string | readonly string[] | undefined,
  blocks: readonly string[],
  layout: PresetLayout,
): string {
  let value = 0n;
  let offset = 0n;

  for (const field of layout.fields) {
    const given = read(field.key) ?? field.default;
    let bits: bigint;

    if (field.multi === true) {
      const list = typeof given === "string" ? [given] : given;
      bits = 0n;

      for (const each of list) {
        bits |= 1n << BigInt(indexIn(field, each));
      }
    } else {
      bits = BigInt(indexIn(field, typeof given === "string" ? given : ""));
    }

    value |= bits << offset;
    offset += BigInt(field.bits);
  }

  for (const name of new Set(blocks)) {
    const index = layout.blocks.indexOf(name);

    if (index === -1) {
      throw new TypeError(
        `Preset block "${name}" is not a block. Blocks: ${layout.blocks.filter((each) => each !== null).join(", ")}`,
      );
    }

    value |= 1n << (offset + BigInt(index));
  }

  return BASE62.charAt(layout.version) + toBase62(value);
}

/**
 * The preset with one convention set to `value`, checked against the field:
 * a value the field doesn't list throws. For a field that takes several
 * values (`integrations`), `value` switches that one on or off.
 */
export function withPresetField(
  preset: Preset,
  key: PresetFieldKey,
  value: string,
): Preset {
  const field = LAYOUT.fields.find((each) => each.key === key);
  const current = valueOf(preset, key);
  let next: string | readonly string[] = value;

  if (field?.multi === true) {
    const list = typeof current === "string" ? [current] : (current ?? []);
    next = list.includes(value)
      ? list.filter((each) => each !== value)
      : [...list, value];
  }

  const code = encodeWith(
    (name) => (name === key ? next : valueOf(preset, name)),
    preset.blocks,
    LAYOUT,
  );

  return { ...decodePreset(code).preset, blocks: preset.blocks };
}

/**
 * Reads a code from `encodePreset`. A code from an older version decodes
 * with the fields it predates at their defaults, listed in `derived`. A
 * code from a newer release throws, naming the upgrade.
 */
export function decodePreset(
  code: string,
  layout: PresetLayout = LAYOUT,
): DecodedPreset {
  const version = BASE62.indexOf(code.charAt(0));

  if (!isPresetCode(code)) {
    throw new TypeError(
      `"${code}" is not a preset code: a code starts with its version, such as "${BASE62.charAt(layout.version)}".`,
    );
  }

  if (version > layout.version) {
    throw new TypeError(
      `Preset code "${code}" is version ${String(version)}; this better-supabase reads up to ${String(layout.version)}. Upgrade better-supabase.`,
    );
  }

  let value = fromBase62(code.slice(1));
  const conventions: Record<string, string | readonly string[]> = {};
  const derived: PresetFieldKey[] = [];

  for (const field of layout.fields) {
    if (field.since > version) {
      conventions[field.key] = field.default;
      // SAFETY: the layout's fields are `PRESET_FIELDS`, or a test's copy
      // with the same keys.
      derived.push(field.key as PresetFieldKey);
      continue;
    }

    const bits = value & mask(field.bits);
    value >>= BigInt(field.bits);

    if (field.multi === true) {
      const list: string[] = [];
      field.values.forEach((each, index) => {
        if ((bits >> BigInt(index)) & 1n) {
          list.push(each);
        }
      });

      if (bits >> BigInt(field.values.length) !== 0n) {
        newer(code, field.key);
      }

      conventions[field.key] = list;
    } else {
      const each = field.values[Number(bits)];

      if (each === undefined) {
        newer(code, field.key);
      }

      conventions[field.key] = each;
    }
  }

  const blocks: string[] = [];

  for (let index = 0; value > 0n; index += 1, value >>= 1n) {
    if ((value & 1n) === 0n) {
      continue;
    }

    if (index >= layout.blocks.length) {
      newer(code, "blocks");
    }

    const name = layout.blocks[index];

    if (name !== null && name !== undefined) {
      blocks.push(name);
    }
  }

  return {
    // Every field in the layout was read or defaulted above, each to one of
    // its own values.
    preset: { ...DEFAULT_CONVENTIONS, ...conventions, blocks },
    version,
    derived,
  };
}

function newer(code: string, key: string): never {
  throw new TypeError(
    `Preset code "${code}" sets a ${key} value this better-supabase doesn't know. Upgrade better-supabase.`,
  );
}

/**
 * Whether `value` reads as a preset code rather than a preset name: a
 * version character (`1` to `9`, then `A` to `Z`) and base62 digits.
 */
export function isPresetCode(value: string): boolean {
  return /^[1-9A-Z][0-9A-Za-z]+$/.test(value);
}
