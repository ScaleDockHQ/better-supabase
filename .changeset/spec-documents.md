---
"better-supabase": minor
---

New `better-supabase/spec` subpath: `defineApi` builds one API model from the schema, resources, routes and plugin `describe` hooks, and renders it in any registered document format and version, with transforms, overlays and lint diagnostics. `defineDocumentFormat` adds a format of your own (`apiVersion: 1`), `serializeDocument` and `specResponse` serve a rendered document with a strong ETag, and `specReference` serves a reference page for Scalar, Swagger UI, Redoc, Stoplight Elements or RapiDoc, from jsDelivr at pinned versions with SRI hashes or from your own assets, with a CSP nonce.

`better-supabase/openapi` now renders OpenAPI 3.0, 3.1 and 3.2 from that model, and `3.3-preview` when you ask for it. `createOpenApi` keeps its signature and takes a `version` option. It now emits OpenAPI 3.1.2 by default (it emitted 3.1.1), so a snapshot of the `openapi` field changes. 3.0 output lowers schemas to the 3.0 Schema Object, and the 3.2 fields travel as `x-oai-*` extensions below 3.2. `openapiFormat` lints a document for duplicate operation ids, path parameters that don't match the template, unknown security schemes and `$ref`s that don't resolve. The tenant, soft delete and timestamps plugins describe their columns and headers in the document.
