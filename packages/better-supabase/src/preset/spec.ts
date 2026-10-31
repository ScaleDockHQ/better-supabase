import type { Preset, PresetConventions, PresetInstance } from "./fields.ts";
import type { PresetName } from "./presets.ts";

import { DEFAULT_CONVENTIONS, CONVENTION_FIELDS } from "./fields.ts";
import { isPresetName, namedPreset, PRESET_NAMES } from "./presets.ts";

/**
 * A preset written out: the conventions that differ from the defaults and the
 * selected blocks. It is what the config's `preset` key and a design's `preset`
 * key hold when the selection isn't a named preset.
 */
export type PresetSpec = Partial<PresetConventions> & {
  readonly blocks?: readonly string[];
  readonly instances?: Readonly<Record<string, PresetInstance>>;
};

const same = (
  left: string | readonly string[],
  right: string | readonly string[],
): boolean =>
  typeof left === "string" || typeof right === "string"
    ? left === right
    : left.length === right.length &&
      left.every((each) => right.includes(each));

/** Whether two presets select the same blocks with the same conventions. */
function samePreset(left: Preset, right: Preset): boolean {
  return (
    CONVENTION_FIELDS.every((field) =>
      same(left[field.key], right[field.key]),
    ) &&
    same(left.blocks, right.blocks) &&
    canonical(left.instances ?? {}) === canonical(right.instances ?? {})
  );
}

/** `value` as JSON with object keys sorted, so key order doesn't matter. */
function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, each: unknown) =>
    isRecord(each)
      ? Object.fromEntries(
          Object.entries(each).toSorted(([a], [b]) => (a < b ? -1 : 1)),
        )
      : each,
  );
}

/**
 * The preset as the config or a design writes it: its name when it is a named
 * preset as it ships, otherwise the conventions that differ from the defaults
 * and the selected blocks.
 */
export function presetSpec(preset: Preset): PresetName | PresetSpec {
  const named = PRESET_NAMES.find((name) =>
    samePreset(namedPreset(name), preset),
  );

  if (named !== undefined) {
    return named;
  }

  const conventions = Object.fromEntries(
    CONVENTION_FIELDS.flatMap((field) =>
      same(preset[field.key], DEFAULT_CONVENTIONS[field.key])
        ? []
        : [[field.key, preset[field.key]]],
    ),
  );

  return {
    ...conventions,
    ...(preset.blocks.length === 0 ? {} : { blocks: [...preset.blocks] }),
    ...(preset.instances === undefined ||
    Object.keys(preset.instances).length === 0
      ? {}
      : { instances: preset.instances }),
  };
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isStringList = (value: unknown): value is readonly string[] =>
  Array.isArray(value) && value.every((each) => typeof each === "string");

/**
 * Reads a preset object (`PresetSpec`) into a `Preset`, with the conventions it
 * leaves out at their defaults. Throws a TypeError naming the first key or
 * value that isn't one.
 */
export function presetFromSpec(value: unknown): Preset {
  if (!isRecord(value)) {
    throw new TypeError(
      `preset: expected a preset name (${PRESET_NAMES.join(", ")}) or an object of conventions and blocks.`,
    );
  }

  const conventions: Record<string, string | readonly string[]> = {};

  for (const [key, given] of Object.entries(value)) {
    if (key === "blocks") {
      if (!isStringList(given)) {
        throw new TypeError("preset.blocks: expected a list of block names.");
      }

      continue;
    }

    if (key === "instances") {
      instanceProblem(given);
      continue;
    }

    const field = CONVENTION_FIELDS.find((each) => each.key === key);

    if (field === undefined) {
      throw new TypeError(
        `preset.${key}: not a preset key. A preset object takes blocks, instances, ${CONVENTION_FIELDS.map((each) => each.key).join(", ")}.`,
      );
    }

    const list = field.multi === true ? given : [given];

    if (
      !isStringList(list) ||
      (field.multi !== true && typeof given !== "string") ||
      !list.every((each) => field.values.includes(each))
    ) {
      throw new TypeError(
        `preset.${key}: expected ${field.multi === true ? "a list of" : "one of"} ${field.values.join(", ")}.`,
      );
    }

    conventions[key] = typeof given === "string" ? given : list;
  }

  const blocks = value["blocks"];
  const instances = value["instances"];

  return {
    ...DEFAULT_CONVENTIONS,
    // SAFETY: each key is a field of `CONVENTION_FIELDS`, checked against its
    // values above.
    ...(conventions as Partial<PresetConventions>),
    blocks: isStringList(blocks) ? blocks : [],
    // SAFETY: `instanceProblem` checked each entry's keys and values.
    ...(isRecord(instances)
      ? { instances: instances as Readonly<Record<string, PresetInstance>> }
      : {}),
  };
}

const INSTANCE_KEYS = [
  "block",
  "names",
  "subjects",
  "options",
  "tables",
  "on",
  "uses",
];

const isStringRecord = (value: unknown): boolean =>
  isRecord(value) &&
  Object.values(value).every((each) => typeof each === "string");

/** `{ team?: { actions: string[] }, auditReads?: boolean }`, nothing else. */
const isSubjectSettings = (value: unknown): boolean =>
  isRecord(value) &&
  Object.entries(value).every(([key, each]) =>
    key === "auditReads"
      ? typeof each === "boolean"
      : key === "team" && isRecord(each) && isStringList(each["actions"]),
  );

function validInstanceValue(key: string, given: unknown): boolean {
  if (key === "block") {
    return typeof given === "string";
  }

  if (key === "names" || key === "uses") {
    return isStringRecord(given);
  }

  if (key === "on") {
    return isStringList(given) || isRecord(given);
  }

  if (key === "subjects") {
    return isRecord(given) && Object.values(given).every(isSubjectSettings);
  }

  if (key === "tables") {
    return (
      isRecord(given) &&
      Object.values(given).every(
        (each) => each === null || typeof each === "string",
      )
    );
  }

  return isRecord(given);
}

/** Throws a TypeError naming the first `instances` entry that isn't one. */
function instanceProblem(value: unknown): void {
  if (!isRecord(value)) {
    throw new TypeError(
      "preset.instances: expected an object of blocks entries.",
    );
  }

  for (const [name, entry] of Object.entries(value)) {
    if (!isRecord(entry)) {
      throw new TypeError(`preset.instances.${name}: expected an object.`);
    }

    for (const [key, given] of Object.entries(entry)) {
      if (!INSTANCE_KEYS.includes(key)) {
        throw new TypeError(
          `preset.instances.${name}.${key}: not an instance key. An instance takes ${INSTANCE_KEYS.join(", ")}.`,
        );
      }

      const valid = validInstanceValue(key, given);

      if (!valid) {
        throw new TypeError(
          `preset.instances.${name}.${key}: expected ${key === "block" ? "a block name" : "an object"}.`,
        );
      }
    }
  }
}

/** A preset name or object as a `Preset`. */
export function presetOfSpec(value: unknown): Preset {
  if (typeof value === "string") {
    if (isPresetName(value)) {
      return namedPreset(value);
    }

    throw new TypeError(
      /^[1-9A-Z][0-9A-Za-z]{4,}$/.test(value)
        ? `preset: "${value.slice(0, 20)}" is a preset code, which 0.15 no longer reads. Run \`better-supabase codemod 0.15\` to turn it into a preset object.`
        : `preset: "${value}" is not a preset name. Use one of ${PRESET_NAMES.join(", ")}, or an object of conventions and blocks.`,
    );
  }

  return presetFromSpec(value);
}
