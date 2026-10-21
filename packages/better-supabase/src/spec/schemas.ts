import type { StandardJSONSchemaV1 } from "@standard-schema/spec";

import type { SchemaMeta } from "../schema/types.ts";
import type { JsonSchema } from "./model.ts";

import { buildJsonSchema } from "../generators/json-schema.ts";

/** `customer_tags` to `CustomerTags`. */
export function pascal(value: string): string {
  return value.replaceAll(
    /(^|[_\-.\s])(\w)/g,
    (_, _sep: string, char: string) => char.toUpperCase(),
  );
}

export const schemaRef = (name: string): JsonSchema => ({
  $ref: `#/components/schemas/${name}`,
});

const tableDefs = new WeakMap<
  SchemaMeta,
  Map<string, Readonly<Record<string, JsonSchema>>>
>();

/**
 * The 2020-12 `$defs` for every table (`customersRow`, `customersInsert`),
 * built once per metadata object and JSON column config.
 */
export function tableSchemas(
  meta: SchemaMeta,
  json: Readonly<Record<string, unknown>> = {},
): Readonly<Record<string, JsonSchema>> {
  let byJson = tableDefs.get(meta);

  if (!byJson) {
    byJson = new Map();
    tableDefs.set(meta, byJson);
  }

  const key = JSON.stringify(json);
  let defs = byJson.get(key);

  if (!defs) {
    // SAFETY: buildJsonSchema always returns a $defs object of JSON schemas.
    defs = buildJsonSchema({ meta, config: { json } })["$defs"] as Record<
      string,
      JsonSchema
    >;
    byJson.set(key, defs);
  }

  return defs;
}

/** A Standard Schema, or anything else that might carry `~standard`. */
export interface StandardLike {
  readonly "~standard": object;
}

export interface ConvertedSchema {
  readonly schema: JsonSchema;
  /** The component name from the schema's own `$id` or `id` metadata. */
  readonly name?: string;
}

const converted = new WeakMap<object, Map<string, ConvertedSchema | null>>();

function nameOf(schema: JsonSchema): string | undefined {
  const id = schema["$id"] ?? schema["id"];

  if (typeof id !== "string" || id === "") {
    return undefined;
  }

  const last = id.split(/[/#]/u).findLast((part) => part !== "") ?? id;

  return last.replace(/\.(?:schema\.)?json$/u, "");
}

/**
 * Converts a Standard Schema through Standard JSON Schema (2020-12), or
 * `undefined` when the library does not implement it. The schema's `$id`, `id`
 * and `$schema` are lifted out: the id becomes the component name.
 */
export function convertStandard(
  schema: StandardLike,
  direction: "input" | "output",
): ConvertedSchema | undefined {
  let cache = converted.get(schema);

  if (!cache) {
    cache = new Map();
    converted.set(schema, cache);
  }

  const hit = cache.get(direction);

  if (hit !== undefined) {
    return hit ?? undefined;
  }

  // SAFETY: every Standard JSON Schema field on ~standard is optional, and a
  // missing jsonSchema is handled below.
  const standard = schema["~standard"] as Partial<StandardJSONSchemaV1.Props>;
  const convert = standard.jsonSchema?.[direction];

  if (typeof convert !== "function") {
    cache.set(direction, null);

    return undefined;
  }

  const raw = convert({ target: "draft-2020-12" });
  const name = nameOf(raw);
  const { $schema: _schema, $id: _id, id: _plainId, ...rest } = raw;
  const result = { schema: rest, ...(name ? { name } : {}) };
  cache.set(direction, result);

  return result;
}
