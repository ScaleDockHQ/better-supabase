---
"better-supabase": minor
---

`comments`, `connectors` and `rate-limit` follow the block contract.

`createRateLimit` takes one options object: `createRateLimit({ sql: postgres.admin })` or `createRateLimit({ transport: rpcTransport(adminClient) })` replaces `createRateLimit(source, options)`, with `schema`, `mappers`, `hooks`, `logger` and `temporal` next to it. `createBlocks` builds the `rate-limit` block from its shared `transport`.

`comments` and `connectors` take `options.extraColumns` (on `comments` and `connector_servers`) and a Standard Schema `fields` option on `createComments` and `createConnectors`. `create` and `edit` of comments, and `servers.create` and `servers.update` of connectors, validate the `fields` they get and write them; every comment and server read returns the columns parsed under `fields`, and `comments.copy` copies them. `create_comment` and `edit_comment` take a `fields jsonb` argument only when extra columns are configured; `save_connector_server` takes them in its existing `fields` object.

Every SQL module that takes a `fields jsonb` argument for its extra columns now names it `fields`: `request_access`, `reserve_ai_file`, `store_ai_file`, `create_api_key`, `request_approval`, `create_attachment`, `save_product`, `create_collection` and `rename_collection` took `extra_fields` before. Each module drops the signature it doesn't create, so turning `extraColumns` on or off never leaves two overloads a call matches, and the module contracts list the argument when it exists.
