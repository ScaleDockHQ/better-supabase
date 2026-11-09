# 0590: Keep same_tenant on owned tables and record the 0.58 upgrade checks

- Status: accepted
- Date: 2026-11-09

## Context

The CentraKit upgrade to 0.58 found 189 `bsb_same_tenant_*` triggers on the app's
own tables, because `blocks.memberships.options.sameTenant` defaults to every
foreign key between two tenant tables (ADR 0098). The plan asked whether that
default should be opt-in for app-owned tables, or a statement-level check.

It also asked whether an app that declares `unit` and `discount_kind` on its own
line tables conflicts with the columns invoices and quotes add.

## Decision

The default stays. A PGlite run of the generated trigger on a 1,000-row insert
and a 1,000-row update over one checked key took 9 ms and 8 ms without it, and
39 ms and 31 ms with it: about 30 microseconds a row for each key. That is a
cost per checked write, not per table, so a batch of 1,000 rows over three
checked keys adds about 100 ms. The check refuses a reference to another
tenant's row for every writer, the service role included, and that is the
reason the default exists. An app that cannot afford it on a hot table lists the
keys it wants in `sameTenant`, or sets `sameTenant: false`. A statement-level
check over transition tables would cut the per-row planning cost, and it stays
open until a measured batch on CentraKit shows the triggers dominate (the status
note's `EXPLAIN (ANALYZE, BUFFERS)` of one import batch comes first).

Owned line tables do not conflict. When the app declares `unit` and
`discount_kind`, quotes still render `add column if not exists` for both, which
changes nothing at run time. `codemod owned-columns` writes the same statements
into the app's files, so a declarative diff holds one definition of each column.
The block's check constraints (`bsb_<table>_unit`, `bsb_<table>_discount_kind`)
land on the app's column; they are named, so an app that stores longer units or
other discount kinds drops them there.

`same_tenant` itself changes in two ways. A referenced row without a tenant, such
as a global role, passes. A deferrable foreign key gets a constraint trigger that
runs at commit, so a child row may come before its parent in one transaction.

## Alternatives considered

Opt-in on app-owned tables: it removes the cost and the protection together, and
the tables the app writes through the service role are the ones that need it.

Statement-level triggers now: they need a second function and a transition-table
trigger per key, and no measurement says the row triggers are the cost of an
import batch.

## Consequences

Apps keep the check and its cost. The PGlite test in
`tests/sql/modules/tenant-same-behavior.test.ts` pins the shared-row and
deferrable cases. Revisit the default when a batch profile on CentraKit puts the
same_tenant triggers above the item loop.

Not done in the same change, and left for the next plan: pinning the old default
names of existing app tables in `codemod naming` (drive `deleted_at`, the actor
columns of scorecards and status history), renaming block column names in the
app's own SQL and seeds, a trace diff of the runtime program between 0.57 and
0.58 (346k to 405k types), a server bench program with a check time above the
calibration floor, and a profile of the `gen` and `upgrade --check` times.
