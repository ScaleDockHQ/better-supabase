# 1232: Gate registry reads with a set and check the subject in a plpgsql function

- Status: accepted
- Date: 2026-11-25

## Context

`docs/agents/one-round-trip-after.md` found that the slow care and funding
routes (`/funding`, `/care/[clientId]`, `/medications`, `/care`) lose their time
to planning, not to execution. Each read policy of a table that points at a
registry subject (`funding_awards`, `medication_orders`, `observations`,
`consents`, `field_changes`, `pipeline_stage_history`, `sla_clocks`) carried a
`case subject_type` over the 55 registry types, about 16 KB of SQL, and the
restrictive `bsb_tenant_scope_select` policy copied it (ADR 0104). Postgres
plans every branch of an inline `case` for every statement, so one signed-in
read of one table planned 110 subqueries before it touched a row.

Measured as the signed-in admin of the seed tenant with
`explain (analyze, buffers, summary)`, on one database, with the old policies
frozen on a copy of each table:

| Table               | Planning before | Planning buffers before | Planning after | Planning buffers after |
| ------------------- | --------------- | ----------------------- | -------------- | ---------------------- |
| `funding_awards`    | 18.4 ms         | 9,723                   | 2.2 ms         | 1,172                  |
| `medication_orders` | 16.3 ms         | 8,478                   | 2.2 ms         | 1,197                  |
| `observations`      | 20.0 ms         | 8,474                   | 2.3 ms         | 1,202                  |
| `consents`          | 16.6 ms         | 8,468                   | 2.2 ms         | 1,210                  |
| `field_changes`     | 15.0 ms         | 7,613                   | 2.1 ms         | 1,124                  |

ADR 0424 rules out the obvious fix: calling a plpgsql function per row from the
policy made the same read take 32 s instead of 73 ms. ADR 0426 and ADR 1218 say
what to do instead: check tenants as a set, and keep the cost in what the
predicate does.

The deliveries read policy also compared a column with itself
(`x."tenant_id" = "tenant_id"`), because the unqualified name resolved to the
award alias. The award is unique by id and the foreign key ties it to the
delivery's tenant, so the check held no information, but it read as a tenant
check.

## Decision

For a tenant scope, `registryReadable` (in `modules/attachments-app.ts`) splits
the registry types in three.

- The open types (record grants, a team check or an own read, such as
  `customer`) keep their inline `exists` branch in a small `case`. A first
  version sent every row through the function and read 12,000 customer awards in
  3.5 s against 30 ms inline, the ADR 0424 regression, so these stay inline.

- The gated types are the tenant types that read with one permission key, have
  no record grants and no team check. A policy checks their permission as a set:
  `(tenant, subject_type) in (select tenant, type from tenant_ids_with('key')
  cross join unnest(types) union all ...)`, with a first branch that lets a row
  of any other type through to the function. The planner turns the set into one
  hashed subplan per distinct key and never plans the per-type branches.
- Every other row (the `else` of that `case`) calls one generated plpgsql function per module
  (`funding_subject_readable`, `medications_subject_readable` and the like).
  Its body is a `case` of statements, so a call plans only the branch of the
  type it reads. A gated type checks that the subject row is visible (its own
  policies apply) and in the same tenant. Other types keep the record grant,
  team and `can_subject` checks they had.

The set is a precondition and the function does the row check, so the policy
returns a row only when both pass. A gated type with a key the caller lacks fails
the set. Any other type is decided by the function, as the CASE decided it.

The deliveries policy qualifies both columns with the delivery table. Seven
modules gain a generated function and list it under `internal`, so no `api.*`
wrapper is generated. `knowledge` and `deals` keep the inline form because they
have no tenant scope to gate. The migration
`20270120010069_registry_subject_readable_gate.sql` replaces the policies and
the functions; no data moves.

## Alternatives considered

- A plpgsql function per row with no gate. ADR 0424 measured this at 32 s
  against 73 ms; the gate keeps the per-row call cheap by deciding the
  permission once per statement.
- `can_subject` per row. It plans and runs the whole registry for every row and
  answers the same question as the CASE; it stays only as the fallback for types
  a later module registers.
- A per-block `on` list that names the types a table can hold. It makes the
  policy smaller but moves a registry fact into every call site, and a type
  added later would not be covered.
- Keeping the CASE and trimming it by module. The branches are the cost, not
  their number, so it only moves the problem.

## Consequences

Planning a read of these tables takes about 2 ms, from 15 to 20 ms. The
restrictive scope policy inherits the same predicate. Row execution of customer subjects improves, from 26 to 42 ms to 13 ms for 12,000
awards. A row of a gated type (a message, a company) now calls the function,
which costs a statement per row; a table holding thousands of those reads
slower than inline, and the scale test prints the customer numbers beside
`can_subject`.

The behavior is the same for the roles in
`supabase/tests/database/registry_subject_readable_equivalence.test.sql`, which
reads every registry type, a missing subject, a subject of another tenant and an
unknown type as four roles against the frozen CASE policy, and finds no award
that one form shows and the other hides.

The `deadlines` policy still inlines the CASE through its own path
(`subjectPolicy`) and plans in 20 ms; it is the next table to move onto this
form. Adopters run `better-supabase upgrade` and apply the migration. Revisit if a type registers
a permission that needs a record grant: it leaves the gate and falls to the
function, which costs nothing in planning.
