# 0080: Store enrichment results per record and provider, and fill only empty columns

- Status: accepted
- Date: 2026-10-22

## Context

A CRM fills in what a member didn't type: a company's domain and industry, a
person's title and phone. Data vendors sell this as an HTTP API with a key,
rate limits and a match likelihood. The core must not depend on a vendor SDK
(ADR 0036), and a vendor's answer must not overwrite what a member entered.

## Decision

Add an `enrichment` block (`src/sql/modules/enrichment.ts`,
`src/blocks/enrichment/`). The app passes an `EnrichmentProvider` with
`apiVersion: 1`, a lowercase name and two lookups, `company` and `person`,
that return a profile or `undefined` for no match. The block ships
`peopleDataLabsEnrichment` over `fetch`, so no SDK peer is added.

`enrichment_target` reads the lookup input; the provider runs in
TypeScript; `record_enrichment` stores the result in `enrichments`, one row
per record and provider, replacing an older one. A match fills only null
columns that parties owns: a company's `domain` (lowercased, and only when
no other active company in the organization holds it) and `website`, a
person's `phone` and `title`. Everything else stays in the result's `data`.
Each result writes `party.enriched` with the filled columns.
`enrichment_due` lists records with no result from the provider or a stale
one, for a cron. The block adds `enrichment.read` and `enrichment.run`.

## Alternatives considered

- Calling the provider from Postgres with `pg_net`. The key would live in
  the database, retries and rate limits would run in SQL, and a custom
  provider would need SQL too.
- Writing every profile field onto the record as custom fields. It ties the
  record schema to one vendor and overwrites edits on the next refresh.
- Emitting `company.updated` for a fill. Handlers of that event expect a
  member's edit; `party.enriched` says where the values came from.

## Consequences

A second vendor plugs in without SQL, and results from several vendors sit
side by side. The record keeps a member's values, so a wrong value from a
vendor never replaces a right one, and a fix means clearing the column and
enriching again. Fields beyond the four columns are read from `of()` until
an app maps them into custom fields. There is no UI recipe yet, and the
block is only in the `everything` preset.
