# 0831: Default search registration from the manifest entity and raise the server baselines

- Status: accepted
- Date: 2026-11-13

## Context

Search registration was missing on 20 modules (EX-100) and could not be replaced
by an app (EX-101). Each module repeated the title column, and the entity's
manifest `search` field (ADR 0689) was not read by anything.

## Decision

`withSearchDefault` (`src/blocks/entity-search.ts`) gives a subject whose SQL
module names no `search` its title column and the body columns the manifest
entity's `search` lists. `search: false` on the manifest entity keeps it out, and
a module's own `search` wins. `pnpm catalog` applies it, so the generated
catalog and every generated registry carry the default.

`blocks.<name>.names.<entity>.search` takes `{ title, body }` logical columns of
the entity's table, or `false`. A column the table lacks fails when the config
loads, and so does `search` on an entity that is not a subject.

The manifest fields of ADR 0830 grow the server chunk again. The baseline reset
follows ADR 0690: empty `server-baseline.json`, run `next build` and the update
script.

## Consequences

The `./blocks/subjects` size baseline moves from 31,813 to 33,812 B gzip for `label`, the party
core and the link types the entry re-exports.

Apps run `upgrade` and generate a migration for the new triggers and the two search functions
(`supabase/migrations/20261215000000_search_defaults_from_manifest.sql` for the example). An app that installs `search` indexes the 17 subjects that had no registration
by their title. A subject that must stay out sets `search: false` in the config.
