import type { JsonSchemaSource } from "./types/codegen.ts";

/**
 * The JSON Schema document for a `json[...].schema` entry. A Standard
 * Schema converts for `target` (2020-12 by default); a JSON Schema object is
 * returned as it is.
 */
export function resolveJsonSchema(
  source: JsonSchemaSource,
  target: "draft-2020-12" | "draft-07" | "openapi-3.0" = "draft-2020-12",
): Readonly<Record<string, unknown>> {
  // SAFETY: a Standard Schema carries ~standard; any other source is a JSON
  // Schema object without it.
  const standard = (source as { "~standard"?: unknown })["~standard"];
  if (standard === undefined) return source;
  // SAFETY: Standard JSON Schema puts jsonSchema.input on ~standard; its
  // absence is handled below.
  const jsonSchema = (standard as { jsonSchema?: unknown }).jsonSchema as
    | { input?: (options: { target: string }) => Record<string, unknown> }
    | undefined;
  if (typeof jsonSchema?.input !== "function") {
    throw new TypeError(
      "json[...].schema: this Standard Schema library does not implement Standard JSON Schema; pass a JSON Schema object instead",
    );
  }
  return jsonSchema.input({ target });
}
