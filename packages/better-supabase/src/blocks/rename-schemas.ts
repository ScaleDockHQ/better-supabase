import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { EntityNames } from "../core/entity-naming.ts";
import type { StandardJSONSchemaV1 } from "../core/table-schema.ts";
import type {
  BlockSchemas,
  EntitySchema,
  EntitySchemas,
} from "./entity-schema.ts";

import { isList, isRecord } from "../core/guards.ts";
import { ENTITY_SCHEMA_KINDS } from "./entity-schema.ts";

/** Moves values between the caller's names and the block's own. */
export interface KeyTranslator {
  /** A value from the block, renamed for the caller. */
  forward(value: unknown): unknown;
  /** A value from the caller, renamed back for the block. */
  back(value: unknown): unknown;
}

/** A JSON Schema with renamed property names, `required` entries and titles. */
function renameJsonSchema(value: unknown, names: EntityNames): unknown {
  if (isList(value)) {
    return value.map((each) => renameJsonSchema(each, names));
  }

  if (!isRecord(value)) {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, each]) => {
      if (key === "properties" && isRecord(each)) {
        return [
          key,
          Object.fromEntries(
            Object.entries(each).map(([name, child]) => [
              names.rename(name),
              renameJsonSchema(child, names),
            ]),
          ),
        ];
      }

      if (key === "required" && isList(each)) {
        return [
          key,
          each.map((name) =>
            typeof name === "string" ? names.rename(name) : name,
          ),
        ];
      }

      if (key === "title" && typeof each === "string") {
        return [key, names.rename(each)];
      }

      return [key, renameJsonSchema(each, names)];
    }),
  );
}

function renamedResult(
  result: StandardSchemaV1.Result<unknown>,
  names: EntityNames,
  translate: KeyTranslator,
): StandardSchemaV1.Result<unknown> {
  if (result.issues !== undefined) {
    return {
      issues: result.issues.map((issue) => ({
        message: issue.message,
        path: (issue.path ?? []).map((part) =>
          typeof part === "string" ? names.rename(part) : part,
        ),
      })),
    };
  }

  return { value: translate.forward(result.value) };
}

function renameSchema(
  schema: EntitySchema<unknown>,
  names: EntityNames,
  translate: KeyTranslator,
): EntitySchema<unknown> {
  const standard = schema["~standard"];

  const convert =
    (direction: "input" | "output") =>
    (options: StandardJSONSchemaV1.Options): Record<string, unknown> => {
      const converted = renameJsonSchema(
        standard.jsonSchema[direction](options),
        names,
      );

      return isRecord(converted) ? { ...converted } : {};
    };

  return {
    "~standard": {
      version: 1,
      vendor: standard.vendor,
      validate: (input) => {
        const result = standard.validate(translate.back(input));

        return result instanceof Promise
          ? result.then((settled) => renamedResult(settled, names, translate))
          : renamedResult(result, names, translate);
      },
      jsonSchema: { input: convert("input"), output: convert("output") },
    },
  };
}

/**
 * A block's input schemas under the caller's names: entity keys, property
 * names, `required` entries and titles renamed, and values translated both ways
 * around the block's own validation.
 */
export function renameSchemas(
  schemas: BlockSchemas,
  names: EntityNames,
  translate: KeyTranslator,
): BlockSchemas {
  return Object.fromEntries(
    Object.entries(schemas).map(([entity, entry]) => {
      const renamed: Partial<
        Record<keyof EntitySchemas, EntitySchema<unknown>>
      > = {};

      for (const kind of ENTITY_SCHEMA_KINDS) {
        const schema = entry[kind];

        if (schema !== undefined) {
          renamed[kind] = renameSchema(schema, names, translate);
        }
      }

      const entitySchemas: EntitySchemas = renamed;

      return [names.rename(entity), entitySchemas];
    }),
  );
}
