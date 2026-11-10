# 0660: Move the remaining paged offset lists onto the keyset template

- Status: accepted
- Date: 2026-11-10
- Amends: 0637, 0642

## Context

ADR 0642 moved four more lists onto the template and left the rest. Seven paged offset lists remain with
the plain `limit offset` form: checkout sessions, agent mandates, pick lists, appraisals, usage rights,
maintenance plans, and the import issue and diff lists. Bookings, calendar and automations have no paged
offset list: their lists are bounded by a date range or return a whole small set.

## Decision

**Six lists move.** `list_checkout_sessions`, `list_agent_mandates`, `list_pick_lists`,
`list_appraisals`, `list_usage_rights` and `list_maintenance_plans` render their paging through
`listDeclare` and `listBody`. Each has a list index that ends in the id, and `offset` stays next to
`after`.

**Nullable sort keys use the coalesce form.** Usage rights sort by `expires_on` with no expiry last, and
maintenance plans by `next_due_at` with none last. The key is `coalesce(column, 'infinity'::date)` (or
`timestamptz`), and the list index is an expression index on the same expression, so the planner seeks
into it. The cursor carries `infinity` as text and casts it back.

**The plans `due` filter moves into the query.** It used to filter the page after the limit, so a page
could hold fewer rows than its neighbours. It is now a predicate on the same plan view, so a page is full
and the keyset cursor is stable.

**Import lists stay as they are.** `list_import_issues` and `list_import_diff` take positional
`row_limit` and `row_offset` arguments and return `{ rows, total }`. Moving them changes the function
signature, which is a migration for every caller, so it needs its own decision.

Each block client gets a page method: `checkout.sessionPage`, `checkout.mandatePage`,
`warehouse.pickListPage`, `appraisals.appraisalPage`, `dam.rightPage` and `maintenance.planPage`.

## Consequences

Measured on the native stack with 60,000 rows in one tenant per table
(`supabase/tests/scale/scale_list_keyset_remaining.test.sql`, `bsb.scale_rows` 60000). The before
column ran the old functions on the same rows; the after column ran the template. One cold run each,
in milliseconds:

| Read                                      | Before | After |
| ----------------------------------------- | ------ | ----- |
| `list_usage_rights` first page of 20      | 13     | 2     |
| `list_usage_rights` deep offset page      | 18     | 10-23 |
| `list_usage_rights` deep keyset page      | n/a    | 1     |
| `list_maintenance_plans` first page of 20 | 12     | 2     |
| `list_maintenance_plans` deep offset page | 305    | 11-22 |
| `list_maintenance_plans` deep keyset page | n/a    | 1     |
| `list_appraisals` first page of 20        | 11     | 3     |
| `list_appraisals` deep offset page        | 9      | 9-17  |
| `list_pick_lists` first page of 20        | 7      | 1     |
| `list_pick_lists` deep offset page        | 8      | 6-15  |

The offset runs vary with machine load, so read them as the same order of magnitude. The plans list
gains most because its old sort had no index on the nullable due date. The plan `due` filter returns
full pages now.
A caller that passed both `offset` and `after` is refused, as in ADR 0642.
