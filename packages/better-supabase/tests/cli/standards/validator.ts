import Ajv, { type ErrorObject, type ValidateFunction } from "ajv";
import addFormats from "ajv-formats";
import Ajv2020 from "ajv/dist/2020.js";
import { readFileSync } from "node:fs";

type Json = Record<string, unknown>;

/** Draft-07 (and draft-04, see SOURCES.md) schemas. */
const draft7 = new Ajv({ strict: false, allErrors: true });
/** JSON Schema 2020-12, the dialect of OpenAPI 3.1+ and current MCP. */
const draft2020 = new Ajv2020({ strict: false, allErrors: true });
addFormats(draft7);
addFormats(draft2020);

function vendored(file: string): Json {
  return JSON.parse(
    readFileSync(
      new URL(`../../standards/schemas/${file}`, import.meta.url),
      "utf8",
    ),
  ) as Json;
}

function engineFor(schema: Json): Ajv | Ajv2020 {
  return String(schema["$schema"] ?? "").includes("2020-12")
    ? draft2020
    : draft7;
}

/**
 * Ajv resolves `$dynamicRef` against the wrong scope for the OpenAPI schemas.
 * With one `$dynamicAnchor` of a name in the document, `$dynamicRef: "#name"`
 * means the same as a `$ref` to the anchor's location, so rewrite it.
 */
function staticDynamicRefs(schema: Json): void {
  const anchors = new Map<string, string>();
  const findAnchors = (node: unknown, pointer: string) => {
    if (!node || typeof node !== "object") return;
    for (const [key, value] of Object.entries(node)) {
      if (key === "$dynamicAnchor" && typeof value === "string") {
        if (anchors.has(value)) throw new Error(`Two $dynamicAnchor ${value}`);
        anchors.set(value, `#${pointer}`);
      } else findAnchors(value, `${pointer}/${key}`);
    }
  };
  findAnchors(schema, "");
  const rewrite = (node: unknown) => {
    if (!node || typeof node !== "object") return;
    const record = node as Json;
    const dynamic = record["$dynamicRef"];
    if (typeof dynamic === "string" && anchors.has(dynamic.slice(1))) {
      delete record["$dynamicRef"];
      record["$ref"] = anchors.get(dynamic.slice(1));
    }
    for (const value of Object.values(record)) rewrite(value);
  };
  rewrite(schema);
}

function load(file: string): { engine: Ajv | Ajv2020; key: string } {
  const schema = vendored(file);
  const engine = engineFor(schema);
  if (!engine.getSchema(file)) {
    if (String(schema["$schema"] ?? "").includes("draft-04")) {
      delete schema["$schema"];
      schema["$id"] = schema["id"];
      delete schema["id"];
    }
    if (file.startsWith("openapi-")) staticDynamicRefs(schema);
    engine.addSchema(schema, file);
  }
  return { engine, key: file };
}

/**
 * A validator for a vendored schema, or for one definition in it
 * (`definition` is a JSON pointer such as `#/$defs/InitializeResult`).
 */
export function validatorFor(file: string, definition = ""): ValidateFunction {
  const { engine, key } = load(file);
  const validate = engine.getSchema(`${key}${definition}`);
  if (!validate) throw new Error(`No schema ${key}${definition}`);
  return validate;
}

/** The 2020-12 meta-schema, to check that generated schemas are themselves valid. */
export function metaSchema2020(): ValidateFunction {
  const validate = draft2020.getSchema(
    "https://json-schema.org/draft/2020-12/schema",
  );
  if (!validate) throw new Error("ajv has no 2020-12 meta-schema");
  return validate;
}

/** Errors as readable lines, for `expect(...).toEqual([])`. */
export function problems(validate: ValidateFunction, value: unknown): string[] {
  if (validate(value)) return [];
  return (validate.errors ?? []).map(
    (error: ErrorObject) =>
      `${error.instancePath || "/"} ${error.message ?? ""} ${JSON.stringify(error.params)}`,
  );
}
