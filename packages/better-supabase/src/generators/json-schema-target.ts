import { isList } from "../core/guards.ts";

/** The JSON Schema dialects the generators and MCP emit. */
export type JsonSchemaTarget = "draft-2020-12" | "draft-07" | "openapi-3.0";

type JsonSchema = Record<string, unknown>;

function isObject(value: unknown): value is JsonSchema {
  return typeof value === "object" && value !== null && !isList(value);
}

/** Keywords whose value is one subschema. */
const SINGLE = new Set([
  "additionalProperties",
  "additionalItems",
  "contains",
  "propertyNames",
  "not",
  "if",
  "then",
  "else",
]);
/** Keywords whose value is a list of subschemas. */
const LISTS = new Set(["allOf", "anyOf", "oneOf"]);
/** Keywords whose value maps names to subschemas. */
const MAPS = new Set(["properties", "patternProperties", "definitions"]);
/** 2020-12 keywords draft-07 has no equivalent for; draft-07 would ignore them. */
const DROPPED = new Set([
  "$dynamicAnchor",
  "$anchor",
  "unevaluatedProperties",
  "unevaluatedItems",
]);

function mapValues(
  value: unknown,
  convert: (schema: JsonSchema) => JsonSchema,
): unknown {
  if (!isObject(value)) {
    return value;
  }
  return Object.fromEntries(
    Object.entries(value).map(([key, child]) => [
      key,
      isObject(child) ? convert(child) : child,
    ]),
  );
}

/**
 * Rewrites a 2020-12 schema into draft-07: `$defs` becomes `definitions`
 * (and `$ref`s into it follow), `prefixItems` becomes the array form of
 * `items`, `dependentRequired` and `dependentSchemas` become
 * `dependencies`, and keywords without a draft-07 form are left out. A
 * draft-07 schema passes through unchanged.
 */
export function toDraft07(schema: Readonly<JsonSchema>): JsonSchema {
  const out: JsonSchema = {};
  const dependencies: JsonSchema = {};
  for (const [key, value] of Object.entries(schema)) {
    if (DROPPED.has(key)) {
      continue;
    }
    if (key === "$schema") {
      continue;
    }
    if (key === "$defs") {
      out["definitions"] = mapValues(value, toDraft07);
    } else if (key === "$ref" || key === "$dynamicRef") {
      out["$ref"] =
        typeof value === "string"
          ? value.replace(/^#\/\$defs\//, "#/definitions/")
          : value;
    } else if (key === "prefixItems" && isList(value)) {
      out["items"] = value.map((item) =>
        isObject(item) ? toDraft07(item) : item,
      );
    } else if (key === "items") {
      const converted = isObject(value) ? toDraft07(value) : value;
      if (schema["prefixItems"] === undefined) {
        out["items"] = converted;
      } else {
        out["additionalItems"] = converted;
      }
    } else if (key === "dependentRequired" || key === "dependentSchemas") {
      Object.assign(dependencies, mapValues(value, toDraft07));
    } else if (SINGLE.has(key) && isObject(value)) {
      out[key] = toDraft07(value);
    } else if (LISTS.has(key) && isList(value)) {
      out[key] = value.map((item) => (isObject(item) ? toDraft07(item) : item));
    } else if (MAPS.has(key)) {
      out[key] = mapValues(value, toDraft07);
    } else {
      out[key] = value;
    }
  }
  if (Object.keys(dependencies).length > 0) {
    out["dependencies"] = {
      ...(isObject(out["dependencies"]) ? out["dependencies"] : {}),
      ...dependencies,
    };
  }
  return out;
}
