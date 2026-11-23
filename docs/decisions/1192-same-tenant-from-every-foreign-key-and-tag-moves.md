# 1192: Derive same-tenant checks from every foreign key and move entries by proof

- Status: accepted
- Date: 2026-11-22

## Context

`sameTenant.auto` (ADR 0320) derived a check only from single-column foreign
keys, so a composite key such as `(project_id, region)` needed a listed entry.
The `same-tenant` column tag (ADR 1166) always wrote `shared: true`, so a tagged
column let a referenced row with no tenant pass even when the referenced tenant
column is `not null`, which the derived entry refuses. The tag also could not
name the tenant columns, and the codemod left every config entry alone because
a one-line tag could not be shown to render the same trigger for each one.

## Decision

- The block derives an entry from every foreign key between two tenant tables.
  A composite key leads with its first column and checks the others as `match`
  pairs. A key with a nullable column besides the first stays with the database,
  because a foreign key does not check a row where one of its columns is null.
- A tag follows the nullability of the referenced tenant column, as a derived
  entry does. `shared=true` and `shared=false` decide it.
- The tag takes `tenant=` and `parent-tenant=`, and works on any foreign key
  that holds the column. A tag takes the place of the entry it replaces, so the
  statements keep their order.
- `codemod table-tags` moves a `sameTenant` entry into a tag when the memberships
  module renders the same trigger statement for that column with the entry and
  with the tag. A move that changes the statement, an entry equal to the derived
  one and a `through` hop with its own key column stay and are listed with the
  reason.

This reverses the second alternative of ADR 1166 with a proof per entry instead
of a blanket rule.

## Alternatives considered

- Move every entry without a proof: a `where` with a different alias or a
  `deferrable` the key does not carry would change the trigger silently.
- Derive composite keys as a second trigger per key: the trigger name is
  `bsb_same_tenant_<column>`, so two keys on one lead column would collide. The
  first key wins.

## Consequences

Projects with composite foreign keys get more triggers on the next `upgrade`.
A tagged column whose referenced tenant column is `not null` now refuses a row
with no tenant; `shared=true` keeps the old behavior.
