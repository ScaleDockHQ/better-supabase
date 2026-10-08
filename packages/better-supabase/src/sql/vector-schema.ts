import type { ModuleLayout } from "./registry.ts";

const VECTOR_SCHEMA = /^[a-z_][a-z0-9_]{0,62}$/;

/** The schema pgvector is installed in: `sql.modules.vector-search.options.schema`, then `vectorSchema`. */
export function vectorSchemaOf(layout: ModuleLayout): string {
  const option = layout.modules?.["vector-search"]?.options?.["schema"];
  const schema =
    option === undefined ? (layout.vectorSchema ?? "extensions") : option;
  if (typeof schema !== "string" || !VECTOR_SCHEMA.test(schema)) {
    throw new TypeError(
      "sql.modules.vector-search.options.schema must be the lowercase name of the schema pgvector is installed in",
    );
  }
  return schema;
}
