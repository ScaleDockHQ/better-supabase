# 1108: Move table facts into table comments with @bsb tags

- Status: accepted
- Date: 2026-11-22

## Context

Audit exemptions, data lifecycle, Data API privileges and same-tenant checks describe one table, but lived in four config sections. A schema review could not see them next to the table.

## Decision

A `comment on table` holds the tags `audit-exempt`, `data-lifecycle`, `grant` and `same-tenant` (on a column), after one `@bsb`, separated by `;`. The config entry still works. For audit, lifecycle and privileges it wins when both exist; a same-tenant tag replaces the config entries for its column. `codemod table-tags` writes the comments into the schema file that creates the table and removes the config entry, and leaves `same-tenant` entries and the BS315 baseline alone. Doctor BS702 lists the facts a comment can hold and BS703 reports a tag that cannot take effect.

## Alternatives considered

A separate `.bsb.yaml` file was rejected because it is a second place to look. Moving same-tenant automatically was rejected: an entry can carry `where`, `match`, `hops`, `deferrable` and `shared`, and the one-line tag cannot be shown to render the same trigger for each.

## Consequences

The schema carries its own facts and the config loses four sections. A tag lives in a comment, so a schema file that is regenerated must keep it.
