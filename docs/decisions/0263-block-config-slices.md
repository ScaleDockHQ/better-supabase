# 0263: Write block config slices as exports of one module and import them per record

- Status: accepted
- Date: 2026-11-07
- Amends: 0232, 0262

## Context

`blockConfig` is one object that lists every installed instance's schema, API
schema, names and options. A client component that reads
`blockConfig.settings.api`, and every generated record file, loads all of it:
17.6 KB minified in the Next.js example, on every route.

## Decision

`gen.blockModules: true` writes `blocks/slices.ts`, one `<instance>Config`
export per instance, and `blocks/permissions.ts` with `permissions` and
`PermissionKey`. `blocks.config.ts` composes `blockConfig` from the slices for
the server. A record file imports the slices of the blocks it binds and the
permissions, and passes `config: { <instance>: <slice> }`. The client's
`blocks` option takes the slices its hooks use. `createRecordProvider` merges
the record's slices under the client's, so a record works with a client that
lists only some of them.

The slices share one module instead of the file per instance the plan sketched.
A first version wrote `blocks/<instance>.ts`: the auth routes shrank by 9 KB,
and the app routes, which render records bound to most blocks, grew by 1.6 KB
because each of the roughly 50 modules adds a wrapper to its chunk. One module
with a named export per slice has no such wrapper, and Turbopack drops the
exports no client file imports.

The example's client components import their slice (`settingsConfig.api`)
instead of `blockConfig`. One component that still imports `blockConfig` puts
every slice back in its route, so `tests/next-build` asserts that the login
route ships at most 30 slices and no route ships the `ai-chat` slice.

## Not done here

The plan also replaces `RenamedType` with concrete interfaces per instance and
puts each instance's client and controller factories in its module. Those need
the block API types written out per instance, which `gen` cannot read from the
block sources without a type extraction step, and are still open.

## Consequences

First-load JavaScript of the Next.js example drops by about 24 KB raw and 3.7 KB
brotli on every route. The option is off by default; fixtures and the other
examples keep `blocks.config.ts` as one object.
