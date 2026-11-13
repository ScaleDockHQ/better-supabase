# 0830: Declare links and concerns in the block manifest

- Status: accepted
- Date: 2026-11-13

## Context

ADR 0196 gave SQL modules declared links and row-level concerns, but only the
SQL `NAMES` carried the links, and the concerns were implied by `@bsb` tags and
table options. A manifest declared `sections` in 1 block, `automations` in 4 and
`composite` in 19, and no manifest named a link (EX-1292). The catalog and the
page generator could not read what a block links to without loading its SQL.

## Decision

`defineBlock` takes `links` (`BlockLink[]`, written with `blockLink`) and
`concerns` (`history`, `lifecycle`, `realtime`, `search`). `Block.links` and
`Block.concerns` default to empty lists. `concerns` omits `audit` and `events`
because every block table gets both (ADR 0196).

The SQL module's `NAMES.links` stays what the SQL renders from.
`tests/blocks/composition.test.ts` keeps the manifest equal to it: every block's
links equal its modules' links, every link points at entities that exist, and
`concerns` equals what the modules' entities and tables imply.

## Alternatives considered

Rendering the SQL from the manifest would remove the duplicate, but SQL modules
are loaded without the manifest, and the manifest would then have to be loaded
by the CLI's SQL path. The test costs one comparison instead.

## Consequences

115 manifests gain one or two lines, which grows the server chunk each `(app)`
route shares (ADR 0831 resets the baseline). Lane O1 takes over `lifecycle`
when retention declarations arrive.
