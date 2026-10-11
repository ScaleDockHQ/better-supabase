# Vendored schemas

These are the official, unmodified schemas (plus one upstream migration and the SCIM RFCs, whose schemas are JSON inside the RFC text) the
standards suite validates output against. The formatter skips this folder, so each file keeps the
upstream bytes and `tests/standards/sources.test.ts` checks the SHA-256 below.
To move a pin, download the new file from its source, update this table and
the matching `SPEC_PINS` entry in one change.

| File | Version | Source | SHA-256 |
|---|---|---|---|
| `openapi-3.0.json` | OpenAPI 3.0, schema 2024-10-18 | https://spec.openapis.org/oas/3.0/schema/2024-10-18 | `2385f5bbb8c37878daae73baeabe7f34b2f022a4a8c049329ee61f71796f039c` |
| `openapi-3.1.json` | OpenAPI 3.1, schema 2026-08-03 | https://spec.openapis.org/oas/3.1/schema/2026-08-03 | `59f106413cb48c31299f96f024c938d3628aed6cd02cd14bcfb2fcaae7a130b6` |
| `openapi-3.2.json` | OpenAPI 3.2, schema 2026-08-30 | https://spec.openapis.org/oas/3.2/schema/2026-08-30 | `ec53db6e114b768ff2d273b232bda210f51b70c5e57d57ac8daf7e8496a6e073` |
| `overlay-1.0.json` | Overlay 1.0, schema 2026-04-01 | https://spec.openapis.org/overlay/1.0/schema/2026-04-01 | `78973008684ac8bab89321cf984cbd7682fc4702ff08a05ffa13db1ed9667d3d` |
| `overlay-1.1.json` | Overlay 1.1, schema 2026-04-01 | https://spec.openapis.org/overlay/1.1/schema/2026-04-01 | `f60356aef05d0f2dd0ca7ee7ecbe4d824938cc64ebf5c1b6793bbdb687808d13` |
| `overlay-1.2.json` | Overlay 1.2, schema 2026-08-08 | https://spec.openapis.org/overlay/1.2/schema/2026-08-08 | `4ace4f0fb3e797c5fec7669100e969cd7c187981cc98235ad6a4c5a590e655dd` |
| `arazzo-1.0.json` | Arazzo 1.0, schema 2025-10-15 | https://spec.openapis.org/arazzo/1.0/schema/2025-10-15 | `b8715bd824fffcb2accf5077977d37c9e7a15be60d785e7a3a51cf600fd46ad4` |
| `arazzo-1.1.json` | Arazzo 1.1, schema 2026-04-15 | https://spec.openapis.org/arazzo/1.1/schema/2026-04-15 | `37be908409bdb2f7bffe61fa23685c7e84cbeebfafac475a1d01dbc50ff7ab9e` |
| `asyncapi-3.0.0.json` | AsyncAPI 3.0.0, spec-json-schemas v6.11.1 | https://raw.githubusercontent.com/asyncapi/spec-json-schemas/v6.11.1/schemas/3.0.0.json | `d4571a420e6ffb7fcc7066c95a6db1202f299a3c51daa103d0706bf30f95e626` |
| `asyncapi-3.1.0.json` | AsyncAPI 3.1.0, spec-json-schemas v6.11.1 | https://raw.githubusercontent.com/asyncapi/spec-json-schemas/v6.11.1/schemas/3.1.0.json | `51d3274899ad2875f25c18fd1aef4d5512f0a97be785d519740bde55a4162f61` |
| `sarif-2.1.0.json` | SARIF 2.1.0 errata 01 | https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json | `c3b4bb2d6093897483348925aaa73af03b3e3f4bd4ca38cef26dcb4212a2682e` |
| `cloudevents-1.0.2.json` | CloudEvents 1.0.2 JSON format | https://raw.githubusercontent.com/cloudevents/spec/v1.0.2/cloudevents/formats/cloudevents.json | `e28a6d252d7b7238d176618f6bbf6cde570b26a867bc5241563aed34c9dd1d83` |
| `mcp-2026-07-28.json` | MCP 2026-07-28 | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2026-07-28/schema.json | `ef70b61f99b6d2e5e3b46863822eab08dff6a45bedc7a08914e0e5b133f40203` |
| `mcp-2025-11-25.json` | MCP 2025-11-25 | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2025-11-25/schema.json | `268a5f82ba70fd7e4b6dc4aa1e64f116f74b4d0edcb69dc046829c79dd4e97e7` |
| `mcp-2025-06-18.json` | MCP 2025-06-18 | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2025-06-18/schema.json | `af845e7e5b9d27107d1690f0936022546177a1403e63ffb11470135b296a2e01` |
| `mcp-2025-03-26.json` | MCP 2025-03-26 | https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/2025-03-26/schema.json | `e720669548c8100a4282c49e580efd6ddf7f28899ea786fc8db251dbdb356131` |
| `mcp-registry-server-2025-10-17.json` | MCP Registry `server.json` 2025-10-17 | https://static.modelcontextprotocol.io/schemas/2025-10-17/server.schema.json | `2cc1552fb3a00ad83d9ae4ee0445a21617098963b58e9bae7b94d680d841b4cc` |
| `stripe-sync-engine-0.48.5-active-entitlements.sql` | Stripe Sync Engine v0.48.5, migration `0038_active_entitlement.sql` (later migrations up to the tag only drop the `lookup_key` unique constraint) | https://raw.githubusercontent.com/supabase/stripe-sync-engine/v0.48.5/packages/sync-engine/src/database/migrations/0038_active_entitlement.sql | `0983c0401a597cd5f4e27466c661b01ac27c6ed021386a168cadd572ebc42ad2` |
| `rfc7643.txt` | RFC 7643, SCIM Core Schema | https://www.rfc-editor.org/rfc/rfc7643.txt | `df799c112a3fa5be3c0fe054c08b1f4eb5d07590c4c8343a014c4537bf638ae3` |
| `rfc7644.txt` | RFC 7644, SCIM Protocol | https://www.rfc-editor.org/rfc/rfc7644.txt | `b9078e016c98b86934a23c80926b74fc8b59885ab2943729ec2493c17488a09b` |

The SARIF and OpenAPI 3.0 schemas are draft-04. Draft-04 and draft-07 differ
in those files only in the `id` keyword (draft-07 calls it `$id`) and in the
boolean form of `exclusiveMinimum` and `exclusiveMaximum` (draft-07 takes the
bound itself), so the loader rewrites both and compiles the schema as
draft-07. The AsyncAPI schemas are draft-07 bundles whose definitions carry
their own `$id`, including a copy of the draft-07 meta-schema; Ajv already
registers that one, so the loader drops the copy. The JSON Schema 2020-12
meta-schema comes from `ajv/dist/2020`.

Ajv resolves `$dynamicRef` against the wrong scope in the OpenAPI schemas.
Each of them has one `$dynamicAnchor: meta`, so the loader rewrites
`$dynamicRef: "#meta"` to a `$ref` to that anchor's location, which has the
same meaning inside one document. The files on disk stay unchanged.

OpenAPI 3.3 has no published schema yet. The `3.3-preview` test removes the
draft-only fields and validates the rest against the 3.2 schema.
