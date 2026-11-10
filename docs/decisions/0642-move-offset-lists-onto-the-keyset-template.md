# 0642: Move offset lists onto the keyset template and warn about row triggers that ignore imports

- Status: accepted
- Date: 2026-11-10
- Amends: 0637

## Context

ADR 0637 added the list template and moved risks, meetings, inspections and warranty claims onto it.
About twenty offset lists remained. The performance audit asked for the rest to move, and accepted
that callers of the old shape may break. The same audit asked for a doctor rule for app row triggers
that run once per imported row.

## Decision

**Four more lists use the template.** `list_rfqs`, `list_samples`, `list_till_sessions` and
`list_calibrations` render their paging through `listDeclare` and `listBody`. Each has a list index
that ends in the id (`tenant, sequence desc, id` and `tenant, opened_at desc, id`). `offset` stays an
option next to `after`, as ADR 0637 decided, and the two do not combine. The default result is still
the plain array. The sort now breaks ties on the id, so rows that shared a `performed_at` or an
`opened_at` come back in id order, which is the order the old query used.

Each block client gets a typed page method: `rfqs.rfqPage`, `lims.samplePage`, `tills.sessionPage` and
`maintenance.calibrationPage`. They return `ListPage` with `hasMore` and `nextCursor`, and `total` when
asked.

**What breaks.** A caller that passed both `offset` and `after` is refused with the block's invalid
error. The migration is to keep `offset` where page numbers matter, or to
switch to `after` and the page method.

**Doctor BS633.** An app row trigger (not named `bsb_*`) whose function in the schema files never calls
`better_supabase.importing()` is reported at info level. Functions outside the schema files are not
judged.

## Not done

The other offset lists (bookings, calendar, automations, imports, agent checkout, warehouse picking,
usage rights, appraisals, maintenance plans and the rest), `defineListQuery` relation filters, date
buckets, free multi-sort, the id-RPC source and the export route helper, the `rpc`, `rollup stored` and
`copy` tags, several `gen` output targets and broadcast triggers from `defineTopic`. They are recorded
in the performance plan. The usage rights and maintenance plan lists sort on nullable keys and need the
`coalesce` form first.

## Consequences

The four lists seek into their index at any depth instead of reading the skipped rows. The generated SQL
of four modules grows by the template's declarations, which the golden files show.
