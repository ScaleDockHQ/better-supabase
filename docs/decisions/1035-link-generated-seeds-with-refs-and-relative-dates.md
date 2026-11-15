# 1035: Link generated seeds with refs and relative dates

- Status: accepted
- Date: 2026-11-15

## Context

ADR 1032 left the `app.*` pages of the example (customers, inbox, deals,
pipelines, segments, queues, scores, contracts) with hand-written rows in
`seed.sql` and `example.sql`, because their rows link generated ids: a deal
belongs to a pipeline stage, a commission accrues on a deal, and a segment, a
queue and a score model take nested JSON. A static `<name>.seed.ts` file holds
none of that, and a hand-written deal id was the only link.

## Decision

The descriptor stays at `apiVersion: 1`; every change is additive.

- A `seed.rows` value may be nested JSON (lists and objects), so a jsonb argument
  such as `conditions` or `members` is a row value.
- `seedRef(entity, name)` marks the id of a row that another page seeds, found by
  its name (the first identity column the runner names for that page). It is a
  plain object (`{ $seedRef: { entity, name } }`), so it is valid in the config
  JSON and in the generated file. The first draft used a function of a seed
  context (`rows: (seed) => [...]`); a function cannot be written into
  `schemas/config-v1.json` or a generated file, so a marker replaced it.
- `seedDate(days)` marks a day counted from the day the seed runs, so a close date
  or a contract end does not age.
- `gen` writes `dependsOn` (the entities a seed refers to) into the seed file, and
  stops with `config_invalid` when a ref names a page without a seed or the
  page itself. `orderSeeds` sorts seeds by `dependsOn` and throws on a cycle, and
  `resolveSeedValue` replaces the markers once the ids are known.
- `scripts/seed-entity-pages.ts` inserts pages in that order, looks each ref up
  in the table of the page it names, resolves refs and dates before it reads a
  row's identity (so a second run still adds nothing), and runs a call per row.
  A target may add an `after` statement for a change the create call does not take
  (a deal's stage age), and one finisher takes the forecast snapshot once the deals
  exist.

The pipelines, deals, segments, queues, scores and contracts pages move onto
generated seeds, and their SQL is deleted from `example.sql`. The commissions page
refers to its deals by name instead of by a fixed id.

Two pages stay hand-written. `app.customers` is `public.customers`, the fixture
table of the pgTAP suite: its fixed ids, `kvk` and primary contact are in
`seed.sql`, and the library reset that CI uses runs no page seeds. `app.inbox`
rows are conversations created by `record_inbound`, and the WhatsApp conversation
is backdated by an `UPDATE` after the call to close its 24 hour reply window,
which a seed row cannot express; the library seed holds the first conversation.

## Consequences

A deal no longer keeps a fixed id or the exact age it had, and the deals' numbers
come from `create_deal`. The seeds are generated from `crm-seeds.ts` in the
example, which keeps `better-supabase.config.ts` under the file length rule.
