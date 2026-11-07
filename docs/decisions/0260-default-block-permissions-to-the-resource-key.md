# 0260: Default a block's permission to the resource key the provider lists

- Status: accepted
- Date: 2026-11-07
- Amends: 0114

## Context

Under an authorization provider every block action checks `<block>.<action>`,
and a provider that names permissions after resources (`quote.send`, `tag.read`)
needed one `blocks.<name>.permissions` entry per action.

## Decision

`ctx.permissionKey` (`src/sql/context.ts`) keeps an explicit remap first. Without
one, and when the layout's `permissionCatalog` (the provider's keys) lacks the
block's own key but lists `<primary entity>.<action>`, it returns that key.
`moduleContext` passes `layout.permissionCatalog` into the context. With no
catalog, or with neither key listed, the key is the block's own, so the error that
names the key to remap is unchanged.

## Alternatives considered

Typing `blocks.<name>.permissions` from the provider's key union would move the
check to the compiler, but the keys live in the provider's JSON, and a generic
`defineConfig` over them is a type-performance risk the benchmark would have to
absorb first. It stays open, with the generated `*` floor and the invitation SQL.

## Consequences

A provider keyed by resource needs no remaps for the blocks whose primary entity
names its keys. The typing and the generated floor are not part of this change.
