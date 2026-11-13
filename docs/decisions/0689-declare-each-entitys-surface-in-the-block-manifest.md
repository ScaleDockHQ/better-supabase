# 0689: Declare each entity's surface in the block manifest

- Status: accepted
- Date: 2026-11-12

## Context

The block consistency audit (`docs/agents/block-consistency-audit.md`) found that
every capability beyond create is partial across the 195 blocks, and that the
partial blocks differ from one capability to the next. The capability matrix came
from a static scan of method names, so a block that offers a capability under an
unusual name looked as if it lacked it, and nothing could tell an append-only
entity from one that is missing its update (EX-1208). 58 blocks had no events
module, and no check failed when a mutating method recorded no event (EX-1216).
The matrix itself could drift from the code (EX-1352).

## Decision

`defineBlock` takes `entities`, a record keyed by entity (its singular noun) of
`EntitySurface` (`src/blocks/entity-surface.ts`). Every field is optional:
`mutability`, `sorts`, `facets`, `search`, `permissions`, `personalData`,
`retention`, `realtime`, `offline`, `versioned`, `flag`, `meter`, `limit` and an
`emits` flag per method. `mutability` is `editable`, `append-only`,
`state-machine` or `read-only`; the fourth value covers entities that only the
block itself or another block writes, which the audit's three values left out.

Every block manifest declares its entities with `mutability` and, for the methods
it has, `emits`. The first values were derived from each block's SQL module,
events and input schemas, so a block's owner may correct them in review.
`tests/blocks/entity-surface.test.ts` fails when a block with SQL declares no
entity, when `mutability` or the key is invalid, when `emits: true` has no event
of the entity, and when a method is marked `emits: false` without being on
`tests/blocks/emit-gaps.ts`. That list holds today's gaps and only shrinks.

`pnpm catalog` generates the declared entity matrix into the audit report between
markers, and `pnpm catalog:check` (in `pnpm verify`) fails when it is stale. The
scanned tables stay as the baseline until lane P replaces them.

The core list contract types ship next to `ListPage` in
`src/core/block-helpers.ts` and in `better-supabase/blocks`: `PageOptions`
(`q`, `sort`, `filters` with list values, `after`, `limit`), `FacetResult` and
`Count` (`{ value, exact }`). They carry no implementation; lane G adds `page`,
`facets` and `count` over them. `renameBlock` renames the keys of `entities`.

## Alternatives considered

- Keep scanning method names. Rejected: it cannot tell absent from differently
  named, and it cannot fail a build.
- Derive the surface from SQL only. Rejected: sorts, facets and mutability are
  client contract, and the SQL modules do not state them.
- Make every field required now. Rejected: the later lanes (permissions, write
  safety, governance) fill the fields they own, and a required field would block
  them on one another.

## Consequences

The matrix, the generators and the later checks read one declaration. A new block
has to declare its entities to pass conformance. The derived `mutability` and
`emits` values are a first pass and can be wrong for a block; correcting one is a
manifest edit plus, for `emits`, the matching line in `emit-gaps.ts`. Revisit the
fourth mutability value if lane I (soft delete) makes `archive` the default.
