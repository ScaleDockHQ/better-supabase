import { isPlainObject } from "../core/clone.ts";

type Json = Record<string, unknown>;

/** Keywords whose value is one subschema. */
const SINGLE: ReadonlySet<string> = new Set([
  "items",
  "additionalProperties",
  "not",
]);

/** Keywords whose value is a list of subschemas. */
const LISTS: ReadonlySet<string> = new Set(["allOf", "anyOf", "oneOf"]);

/** 2020-12 keywords the OpenAPI 3.0 Schema Object does not have. */
const DROPPED: ReadonlySet<string> = new Set([
  "$schema",
  "$id",
  "$anchor",
  "$dynamicAnchor",
  "$dynamicRef",
  "$comment",
  "$defs",
  "$vocabulary",
  "prefixItems",
  "contains",
  "minContains",
  "maxContains",
  "propertyNames",
  "patternProperties",
  "dependentRequired",
  "dependentSchemas",
  "unevaluatedItems",
  "unevaluatedProperties",
  "if",
  "then",
  "else",
  "contentMediaType",
  "contentSchema",
]);

const isNullSchema = (value: unknown): boolean =>
  isPlainObject(value) &&
  value["type"] === "null" &&
  Object.keys(value).length === 1;

/**
 * Rewrites a JSON Schema 2020-12 schema into the OpenAPI 3.0 Schema Object:
 * `null` in `type` or in an `anyOf`/`oneOf` becomes `nullable`, a type list
 * becomes `anyOf`, `const` becomes a one-value `enum`, `examples` becomes
 * `example`, numeric `exclusiveMinimum`/`exclusiveMaximum` become the
 * boolean form, `contentEncoding: base64` becomes `format: byte`, and a
 * `$ref` with siblings is wrapped in `allOf`. Keywords 3.0 does not have
 * are left out. The input is not changed.
 */
export function toOpenApi30Schema(schema: Readonly<Json>): Json {
  const out: Json = {};
  let nullable = false;

  for (const [key, value] of Object.entries(schema)) {
    if (DROPPED.has(key)) {
      continue;
    }

    if (key === "properties" && isPlainObject(value)) {
      out[key] = Object.fromEntries(
        Object.entries(value).map(([name, child]) => [
          name,
          isPlainObject(child) ? toOpenApi30Schema(child) : child,
        ]),
      );
    } else if (SINGLE.has(key) && isPlainObject(value)) {
      out[key] = toOpenApi30Schema(value);
    } else if (LISTS.has(key) && Array.isArray(value)) {
      const branches: unknown[] = value;
      const rest = branches.filter((branch) => !isNullSchema(branch));

      if (key !== "allOf" && rest.length < branches.length) {
        nullable = true;
      }

      out[key] = rest.map((branch) =>
        isPlainObject(branch) ? toOpenApi30Schema(branch) : branch,
      );
    } else if (key === "examples" && Array.isArray(value)) {
      if (value.length > 0) {
        out["example"] = value[0];
      }
    } else if (
      (key === "exclusiveMinimum" || key === "exclusiveMaximum") &&
      typeof value === "number"
    ) {
      out[key === "exclusiveMinimum" ? "minimum" : "maximum"] = value;
      out[key] = true;
    } else if (key === "const") {
      out["enum"] = [value];
    } else if (key === "contentEncoding") {
      if (value === "base64" && schema["format"] === undefined) {
        out["format"] = "byte";
      }
    } else if (key === "type" && Array.isArray(value)) {
      const types: unknown[] = value;
      const rest = types.filter((type) => type !== "null");

      if (rest.length < types.length) {
        nullable = true;
      }

      if (rest.length === 1) {
        out["type"] = rest[0];
      } else if (rest.length > 1) {
        out["anyOf"] = rest.map((type) => ({ type }));
      }
    } else if (key === "type" && value === "null") {
      nullable = true;
      out["enum"] = [null];
    } else {
      out[key] = value;
    }
  }

  for (const key of ["anyOf", "oneOf"] as const) {
    const branches = out[key];

    if (!Array.isArray(branches) || branches.length !== 1) {
      continue;
    }

    const only: unknown = branches[0];

    if (!isPlainObject(only)) {
      continue;
    }

    delete out[key];

    if (typeof only["$ref"] === "string") {
      out["allOf"] = [only];
    } else {
      for (const [name, entry] of Object.entries(only)) {
        if (!(name in out)) {
          out[name] = entry;
        }
      }
    }
  }

  if (typeof out["$ref"] === "string" && Object.keys(out).length > 1) {
    const { $ref, ...siblings } = out;

    return {
      allOf: [{ $ref }],
      ...siblings,
      ...(nullable ? { nullable: true } : {}),
    };
  }

  if (nullable) {
    if (typeof out["$ref"] === "string") {
      return { allOf: [{ $ref: out["$ref"] }], nullable: true };
    }

    out["nullable"] = true;
  }

  return out;
}

const mapEntries = (value: unknown, convert: (entry: Json) => Json): unknown =>
  isPlainObject(value)
    ? Object.fromEntries(
        Object.entries(value).map(([key, entry]) => [
          key,
          isPlainObject(entry) ? convert(entry) : entry,
        ]),
      )
    : value;

const withSchema = (holder: Json): Json => {
  const out: Json = { ...holder };

  for (const key of ["schema", "x-oai-itemSchema"] as const) {
    const schema = out[key];

    if (isPlainObject(schema)) {
      out[key] = toOpenApi30Schema(schema);
    }
  }

  if (isPlainObject(out["content"])) {
    out["content"] = mapEntries(out["content"], withSchema);
  }

  if (isPlainObject(out["headers"])) {
    out["headers"] = mapEntries(out["headers"], withSchema);
  }

  return out;
};

const lowerParameters = (value: unknown): unknown =>
  Array.isArray(value)
    ? value.map((entry: unknown) =>
        isPlainObject(entry) ? withSchema(entry) : entry,
      )
    : value;

const lowerOperation = (operation: Json): Json => {
  const out: Json = { ...operation };
  out["parameters"] = lowerParameters(out["parameters"]);

  if (out["parameters"] === undefined) {
    delete out["parameters"];
  }

  if (isPlainObject(out["requestBody"])) {
    out["requestBody"] = withSchema(out["requestBody"]);
  }

  if (isPlainObject(out["responses"])) {
    out["responses"] = mapEntries(out["responses"], withSchema);
  }

  return out;
};

const PATH_ITEM_LISTS = new Set(["parameters"]);

const lowerPathItem = (item: Json): Json => {
  const out: Json = {};

  for (const [key, value] of Object.entries(item)) {
    if (PATH_ITEM_LISTS.has(key)) {
      out[key] = lowerParameters(value);
    } else if (
      isPlainObject(value) &&
      !key.startsWith("x-") &&
      key !== "servers"
    ) {
      out[key] = lowerOperation(value);
    } else {
      out[key] = value;
    }
  }

  return out;
};

/** Lowers every Schema Object position of an OpenAPI document to the 3.0 dialect. */
export function lowerDocumentSchemas30(document: Json): Json {
  const out: Json = { ...document };

  if (isPlainObject(out["paths"])) {
    out["paths"] = mapEntries(out["paths"], lowerPathItem);
  }

  const components = out["components"];

  if (isPlainObject(components)) {
    const lowered: Json = {
      ...components,
      schemas: mapEntries(components["schemas"], toOpenApi30Schema),
    };

    for (const key of ["responses", "parameters", "requestBodies", "headers"]) {
      if (isPlainObject(components[key])) {
        lowered[key] = mapEntries(components[key], withSchema);
      }
    }

    if (lowered["schemas"] === undefined) {
      delete lowered["schemas"];
    }

    out["components"] = lowered;
  }

  return out;
}
