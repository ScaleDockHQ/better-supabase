# 1030: Declare seed values per field and seed the remaining example pages

- Status: accepted
- Date: 2026-11-15

## Context

ADR 0879 writes `<name>.seed.ts` from the required fields of a block's input
schema, with generated values. Three kinds of page stayed out (EX-1264): the
risks page, whose `category` takes one of the categories the block is
configured with, the pages whose block exports no input schema (periods,
commissions, referrals, invitations), and the `app.*` pages. The example kept
their rows in `seed.sql` per phase. A page that set `seed` on a block with no
table, as the invitations page did, wrote no file and reported nothing.

## Decision

`seed` on `EntityPage` gains four optional keys. The descriptor stays at
`apiVersion: 1` because nothing that existed changes meaning.

- `fields` sets the value of an input field by name. A scalar is the value of
  every row, and a list gives row `i` the value at `i` modulo its length. A field
  it names is seeded even when it is optional, and it must be an input field that
  is a column of the table. An empty list stops `gen`.
- `rows` declares explicit rows for a block whose input schema does not fit. They
  replace the generated rows, so `demo` and `fields` stay unset. A key is what
  the app's insert call reads, usually a database column.
- `table` (`schema.table`) and `tenant` name the table when the block declares
  none for the entity. The organizations block declares none for its
  invitations.
- A `seed` with no table now stops `gen` with `config_invalid`.

The periods block exports `periodInputSchema` (`kind`, `startsOn`, `endsOn`),
registered as the `period` entity's input. Commissions and referrals keep no
input schema: an accrual takes `source: { type, id }` and an attribution takes a
code, which are not columns of the rows they write, so those pages use `rows`.

`pnpm db:seed:pages` gains targets for risks (`create_risk`), periods
(`create_period`), commissions (`accrue_commission`), referrals
(`attribute_referral`) and invitations (`create_invitation`). Each target names
the identity columns of a row, and a row whose identity the table already holds
is skipped, so the script stays repeatable. The hand-written periods, accruals
and attribution in `finance-demo.sql` and `example.sql` are deleted.

## Alternatives considered

- Input schemas for commissions, referrals and invitations. Each changes a
  block's public contract for a seed, and the accrual and the attribution do not
  map to table columns.
- A `seed.sql` generator. The seed tiers belong to the app, and the rows must
  run through the block's functions.
- `apiVersion: 2`. The new keys are optional and no output changes for a
  descriptor that does not use them.

## Consequences

The periods, risks, commissions, referrals and invitations pages seed through
`db:seed:pages`, and a fresh reset shows those pages empty until it runs. The
open invitation with the known token (`/invite/seed-invitation-acme`), the
commission plans and the referral code stay in the SQL seeds because accruals
and attributions need them. The `app.*` pages stay hand-written: their rows are
linked by generated ids (a deal to a stage and a company), and a row keyed by
database column does not carry that. EX-1264 stays deferred for them.

The periods page now has an input schema, so `gen` writes `periods.form.ts` and
the example's `generated.zod.ts` gains `periodInput`. The messages for the
form fields join the `.po` files when the example builds.
