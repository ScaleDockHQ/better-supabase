# 0400: Count the remaining do blocks and let the webhook fan-out honour the provider's wildcards

- Status: accepted
- Date: 2026-11-08
- Amends: 0251, 0252, 0254, 0372

## Context

ADR 0250 left `do` blocks that create objects and `execute format` loops in the
generated schema files and said the count may only fall. Nothing held that
number: doctor counts the blocks of app files, not the ones the library writes.
A recount over the files generated for this repository and the four validation
fixtures found 27 top-level `do` blocks, 6 of them with `execute format`.

ADR 0372 lets a provider say which wildcard grants `permission_matches` honours,
but `publish_webhook_event` built the grants an endpoint may hold with `*` and
every `prefix.*` written in, so a provider that sets `wildcards: "none"` still
matched an event's read permission through a wildcard.

## Decision

`tests/sql/static-ddl.test.ts` counts the top-level `do` blocks, and the ones
that run `execute format`, in the `900_better_supabase_*` schema files of this
repository and of each `tests/validation-*` fixture. `tests/sql/practices.test.ts`
gains the same two rules over the schema files of the module goldens. Both
baselines (`static-ddl-baseline.json`, `practices-baseline.json`) record the
count and may only fall; `UPDATE_PRACTICES=1` rewrites them after a drop.

The blocks that a schema diff can replace are gone, 23 of 27:

- `ctx.rerunnable` (the migrations workflow) is the only layout that writes a
  repair for an older install. The declarative layouts leave it to the diff:
  the notifications priority check that drops itself when its values changed,
  the attachments `drop expression` on `object_path`, and the numbering key
  swap on an app's own sequences table.
- The catalog's row level security loop is plain `alter table`, `revoke` and
  `grant` statements per table, and its audit registration is the static
  `bsb_audit` trigger of ADR 0252 with the `access` category.
- `webhook-inbox` writes its unique constraint as one `add constraint`.
- Statements that read or change rows go to the module's data file: the
  attachments path recompute (now only for rows whose path differs from the
  template, instead of every row when the comment changed) and the storage
  status backfill, the legal-entities duplicate-number warning, and the vector
  search index notice.
- The profiles username check stays `not valid` and nothing validates it. A
  validated check made pg-delta plan a drop and add on every run once the data
  migration validated it, and a failed validation only ever downgraded to a
  warning. The docs say how to validate it.

`BlockSqlContext` gains `rerunnable` and `wildcards`. `wildcards` is the
provider's setting (`all` by default); `publish_webhook_event` builds the
grants it matches by it: `*` and the prefixes for `all`, the prefixes for
`prefix`, the key alone for `none`. Unset keeps every generated function byte
for byte. The typing of permission keys from the provider key union (ADR 0323)
already covers `blocks.*.permissions`, the role lists and `recordTypes`, and the
generated `*` floor now follows the provider in the one place that hard-coded it.

## What remains

Four `do` blocks, three of them with `execute format`:

- **legal-entities (3, all with `execute format`).** When `options.on` names
  invoices, quotes or orders, the module swaps each table's unique key over
  tenant and number for one that adds the legal entity. The old key is a
  constraint or index that another module's file creates, under a name the
  legal-entities file can't see, so the block finds it in the catalog at run
  time. A static form needs the owning modules to write the entity-scoped key
  themselves when `legal-entities` is installed, which is the cross-module
  contract of ADR 0196 and its own change.
- **search (1, no `execute format`).** A `search.watch` entry names a table that
  may come from an optional module or an app file this render can't see, so
  the trigger is created only if `to_regclass` finds the table. It becomes a
  plain `create trigger` once the subject registry knows which tables the
  layout declares.

A role that holds every key the provider lists, as the owner floor of the
`roles` model, stays out of scope as in ADR 0372.

## Alternatives considered

Moving the legal-entities swap to the data file would leave the schema file
declaring the old key and the diff dropping the swapped one. Keeping the profiles
validation in the data file made the diff unstable, as above. Counting only the
goldens misses the `permissions`, `search` and `legal-entities` files, which
need options the goldens don't set, so the fixtures are counted as well.

## Consequences

The repository's `supabase/` folder and the CentraKit, CRM, declarative and
Lienlink fixtures are regenerated. One migration swaps the five catalog audit
triggers and makes the profiles check `not valid`; one data migration carries
the changed data files. `supabase db schema declarative sync --strict-coverage`
reports no changes and the 178 pgTAP files pass. Installed apps run
`better-supabase upgrade`, then the Supabase CLI sync, then `add --adopt`.
