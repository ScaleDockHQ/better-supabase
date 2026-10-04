# Vendored schemas

These are the official, unmodified schemas (and one upstream migration) the
standards suite validates output against. The formatter skips this folder, so each file keeps the
upstream bytes and `tests/standards/sources.test.ts` checks the SHA-256 below.
To move a pin, download the new file from its source, update this table and
the matching `SPEC_PINS` entry in one change.

| File | Version | Source | SHA-256 |
|---|---|---|---|
| `openapi-3.1.json` | OpenAPI 3.1, schema 2022-10-07 | https://spec.openapis.org/oas/3.1/schema/2022-10-07 | `da01ba28852cac0de53893797cb8d1942bc3b05084f526dcc216717dec314ed0` |
| `openapi-3.2.json` | OpenAPI 3.2, schema 2025-09-17 | https://spec.openapis.org/oas/3.2/schema/2025-09-17 | `0c9d74bf25f9b9388b2d81e421ef60fdefa9feffa94898dadfc501b342b3bfcc` |
| `sarif-2.1.0.json` | SARIF 2.1.0 errata 01 | https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json | `c3b4bb2d6093897483348925aaa73af03b3e3f4bd4ca38cef26dcb4212a2682e` |
| `cloudevents-1.0.2.json` | CloudEvents 1.0.2 JSON format | https://raw.githubusercontent.com/cloudevents/spec/v1.0.2/cloudevents/formats/cloudevents.json | `e28a6d252d7b7238d176618f6bbf6cde570b26a867bc5241563aed34c9dd1d83` |
| `mcp-2026-07-28.json` | MCP 2026-07-28 | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2026-07-28/schema.json | `ef70b61f99b6d2e5e3b46863822eab08dff6a45bedc7a08914e0e5b133f40203` |
| `mcp-2025-11-25.json` | MCP 2025-11-25 | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2025-11-25/schema.json | `268a5f82ba70fd7e4b6dc4aa1e64f116f74b4d0edcb69dc046829c79dd4e97e7` |
| `mcp-2025-06-18.json` | MCP 2025-06-18 | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2025-06-18/schema.json | `af845e7e5b9d27107d1690f0936022546177a1403e63ffb11470135b296a2e01` |
| `mcp-2025-03-26.json` | MCP 2025-03-26 | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2025-03-26/schema.json | `e720669548c8100a4282c49e580efd6ddf7f28899ea786fc8db251dbdb356131` |
| `mcp-registry-server-2025-10-17.json` | MCP Registry `server.json` 2025-10-17 | https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json | `2cc1552fb3a00ad83d9ae4ee0445a21617098963b58e9bae7b94d680d841b4cc` |
| `permdock-supabase-claims-v1.json` | PermDock Supabase claims v1, commit `a2971c91d3b5628082f13e8fe2b4b361fad296a9` | https://raw.githubusercontent.com/ScaleDockHQ/permdock/a2971c91d3b5628082f13e8fe2b4b361fad296a9/packages/permdock/schemas/supabase-claims-v1.json | `e65f4217ab3a435c1ddba73468e64f8218aba1adfadc5d5c5b7c9a5e6c517b69` |
| `stripe-sync-engine-0.48.5-active-entitlements.sql` | Stripe Sync Engine v0.48.5, migration `0038_active_entitlement.sql` (later migrations up to the tag only drop the `lookup_key` unique constraint) | https://raw.githubusercontent.com/supabase/stripe-sync-engine/v0.48.5/packages/sync-engine/src/database/migrations/0038_active_entitlement.sql | `0983c0401a597cd5f4e27466c661b01ac27c6ed021386a168cadd572ebc42ad2` |

The SARIF schema is draft-04. Draft-04 and draft-07 differ in that file only
in the `id` keyword (draft-07 calls it `$id`), so the loader renames it and
compiles the schema as draft-07. The JSON Schema 2020-12 meta-schema comes
from `ajv/dist/2020`.

Ajv resolves `$dynamicRef` against the wrong scope in the OpenAPI schemas.
Each of them has one `$dynamicAnchor: meta`, so the loader rewrites
`$dynamicRef: "#meta"` to a `$ref` to that anchor's location, which has the
same meaning inside one document. The files on disk stay unchanged.
