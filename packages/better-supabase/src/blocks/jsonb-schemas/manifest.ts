import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `jsonb-schemas` block's manifest (ADR 0029). */
export const jsonbSchemasBlock: Block<"jsonb-schemas"> = defineBlock({
  name: "jsonb-schemas",
  sql: ["jsonb-schemas"],
  category: "database",
  entities: { jsonb_schema: { mutability: "read-only" } },
  description:
    "pg_jsonschema check constraints for jsonb columns with a `schema` in the `json` config, so the database enforces the same shape as the types. A trigger reports what failed through jsonschema_validation_errors, which the client maps to a validation error.",
});
