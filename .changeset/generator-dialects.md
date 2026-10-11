---
"better-supabase": minor
---

Table and column comments now reach the generated meta as `description` and `deprecated`, and the JSON Schema output marks deprecated tables and columns. `jsonSchema()` takes a `target` (`draft-2020-12`, `draft-07` or `openapi-3.0`, typed as `JsonSchemaTarget`). MCP tools take a `jsonSchemaTarget`, and `tools/list` converts tool schemas to draft-07 for clients on protocol revisions before 2025-11-25. `zod()` takes `flavor: "mini"` (typed as `ZodFlavor`) to generate Zod Mini schemas, and CloudEvents take a `dataschema` option that receives a `DataschemaContext`.
