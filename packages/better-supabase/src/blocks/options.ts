import type { StandardSchemaV1 } from "../core/standard.ts";

import { isRecord } from "../core/guards.ts";

/**
 * What a SQL module option holds. `unknown` is an object or a value the
 * module checks itself; the JSON Schema leaves it open.
 */
export type OptionKind =
  | "string"
  | "boolean"
  | "number"
  | "strings"
  | "unknown";

/** One option of a SQL module (`blocks.<module>.options.<key>`). */
export interface OptionSpec<T = unknown> {
  readonly kind: OptionKind;
  /** The value the module uses when the config leaves the option out. */
  readonly default?: T;
  /**
   * The TypeScript side reads it too, such as `attachments.requireScan` or a
   * realtime topic: `gen` writes its resolved value to `blocks.generated.ts`,
   * and `defineBlocks` passes it to the block's creator.
   */
  readonly client: boolean;
}

/** What an option builder takes. */
export interface OptionInput<T> {
  readonly default?: T;
  /** See `OptionSpec.client`. */
  readonly client?: boolean;
}

function spec<T>(kind: OptionKind, input: OptionInput<T> = {}): OptionSpec<T> {
  return {
    kind,
    ...(input.default === undefined ? {} : { default: input.default }),
    client: input.client ?? false,
  };
}

/** The option builders a block's `options.ts` describes its SQL options with. */
export interface OptionBuilders {
  string(input?: OptionInput<string>): OptionSpec<string>;
  boolean(input?: OptionInput<boolean>): OptionSpec<boolean>;
  number(input?: OptionInput<number>): OptionSpec<number>;
  strings(
    input?: OptionInput<readonly string[]>,
  ): OptionSpec<readonly string[]>;
  unknown<T = unknown>(input?: OptionInput<T>): OptionSpec<T>;
}

export const option: OptionBuilders = {
  string: (input) => spec("string", input),
  boolean: (input) => spec("boolean", input),
  number: (input) => spec("number", input),
  strings: (input) => spec("strings", input),
  unknown: (input) => spec("unknown", input),
};

/** One `OptionSpec` per key of a module's options type. */
export type OptionSpecs<T> = {
  readonly [K in keyof T]-?: OptionSpec<Exclude<T[K], undefined>>;
};

/**
 * A SQL module's options: a Standard Schema typed `T` that refuses unknown
 * keys and values of the wrong kind, plus the option specs `gen` and the JSON
 * Schema read.
 */
export interface BlockOptionsSchema<
  T extends object = object,
> extends StandardSchemaV1<unknown, T> {
  readonly specs: Readonly<Record<string, OptionSpec>>;
}

function kindOf(value: unknown): OptionKind | undefined {
  if (typeof value === "string") {
    return "string";
  }

  if (typeof value === "boolean") {
    return "boolean";
  }

  if (typeof value === "number") {
    return "number";
  }

  if (
    Array.isArray(value) &&
    value.every((entry) => typeof entry === "string")
  ) {
    return "strings";
  }

  return undefined;
}

const KIND_LABEL: Readonly<Record<OptionKind, string>> = {
  string: "a string",
  boolean: "a boolean",
  number: "a number",
  strings: "a list of strings",
  unknown: "a value",
};

/** Describes a SQL module's options, typed by `T` (`blocks.<module>.options`). */
export function blockOptions<T extends object>(
  options: OptionSpecs<T>,
): BlockOptionsSchema<T> {
  const specs: Readonly<Record<string, OptionSpec>> = options;

  return {
    specs,
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate: (value) => {
        if (!isRecord(value)) {
          return { issues: [{ message: "Expected an object" }] };
        }

        const issues: StandardSchemaV1.Issue[] = [];

        for (const [key, entry] of Object.entries(value)) {
          const known = specs[key];

          if (known === undefined) {
            issues.push({ message: `Unknown option "${key}"`, path: [key] });
          } else if (
            known.kind !== "unknown" &&
            entry !== undefined &&
            kindOf(entry) !== known.kind
          ) {
            issues.push({
              message: `"${key}" must be ${KIND_LABEL[known.kind]}`,
              path: [key],
            });
          }
        }

        if (issues.length > 0) {
          return { issues };
        }

        // SAFETY: every key is one `specs` declares, and every value has the
        // kind its `OptionSpec` names, which is what `T` describes.
        return { value: value as T };
      },
    },
  };
}

/** The options of a module that has none. */
export const NO_OPTIONS: BlockOptionsSchema<Record<never, never>> =
  blockOptions<Record<never, never>>({});

const JSON_KIND: Readonly<Record<OptionKind, object>> = {
  string: { type: "string" },
  boolean: { type: "boolean" },
  number: { type: "number" },
  strings: { type: "array", items: { type: "string" } },
  unknown: {},
};

/** The JSON Schema of a module's options, for `schemas/config-v1.json`. */
export function optionsJsonSchema(
  schema: BlockOptionsSchema,
): Readonly<Record<string, unknown>> {
  return {
    type: "object",
    additionalProperties: false,
    properties: Object.fromEntries(
      Object.entries(schema.specs).map(([key, entry]) => [
        key,
        entry.default === undefined
          ? JSON_KIND[entry.kind]
          : { ...JSON_KIND[entry.kind], default: entry.default },
      ]),
    ),
  };
}
