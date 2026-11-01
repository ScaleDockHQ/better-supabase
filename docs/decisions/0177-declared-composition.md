# 0177: Block composition is declared: links, concerns, automations and composite blocks

- Status: accepted
- Date: 2026-11-01

## Context

Blocks compose today through `requires`, `integrates`, contributions and
instances, but most of the composition is written by hand inside SQL modules.
Conversions such as `order_from_quote` insert `created_from` links themselves.
Commercial parties are unchecked text pairs. Block tables have no row-level
audit or event trigger, so direct Data API writes go unrecorded. The manifest
`automations` field is never read, and the catalog cannot show what a block
fires, links to or contributes. Nothing lets one block be built from others
plus glue, so verticals such as a CRM are long preset lists with shared
constants.

## Decision

1. **Declared links.** A module's `NAMES` gain `links`. Each names a source
   entity, a target block entity and a kind: `reference` (a foreign key when the
   target is installed, otherwise a typed pair), `relation` (a contributed
   relation kind) or `conversion` (an action plus a `created_from` and
   `converted_to` link). One renderer replaces the inline
   `ctx.installed(x) ? ... : ""` pattern. `resolvePreset` adds `relations` when
   a declared link needs it.
2. **Concerns at the row level.** Every block table gets row-level audit and
   event triggers. A transaction-local `bsb.recorded` marker, set by
   `ctx.record`, keeps a row a block function already recorded from being
   recorded twice. The `@bsb audit`, `audit-reads`, `events` and `expose` tags
   become real, and `history` and `lifecycle` tags are added.
3. **Automations from one source.** The manifest `automations` field is the
   single source. The SQL modules that ship `automation_defaults` read it, the action
   registry is built from manifests, and the catalog lists automations, links,
   contributions and every port.
4. **Composite blocks.** `defineBlock` gains `composes`, `defaults`, an
   optional glue SQL module, an optional `create` that receives its parts'
   clients, and an optional `record`. A composite is an ordinary block: one
   manifest, one name, one docs page. Installing it installs its parts through
   the `requires` closure. Composites can compose composites and are singletons
   in the first version. `remove` leaves the parts unless `--with-parts` is
   passed.
5. **Helpers and composed reads.** Client methods take one object input.
   Helpers that must be all or nothing are SQL functions; others chain
   idempotent steps through the hooked clients. Blocks declare composed reads
   (`NAMES.reads`) that read sets and `bsb.bootstrap` can include, so a page
   loads in one call.

## Alternatives considered

- Packs as a layer above blocks. A second composition unit next to blocks
  duplicates presets, the config and Create. A composite block reuses all three.
- A graph command or panel in the CLI. Create already is the graph; it gets
  better edges.

## Consequences

- Amends 0029 (manifests gain composition fields), 0048 (events fire from
  every block table), 0093 (composites are blocks, not the removed sections)
  and 0102 (the `@bsb` tags are real).
- Client methods with two or more arguments change to one object input
  (breaking, with a codemod).
- Apps run `upgrade` and generate a migration for the new foreign keys and
  triggers.
