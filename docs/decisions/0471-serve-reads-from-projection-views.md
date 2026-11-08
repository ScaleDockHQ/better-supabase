# 0471: Serve reads from projection views and invalidate them from the table

- Status: accepted
- Date: 2026-11-08
- Amends: 0392, 0393, 0420

## Context

The app owns `security_invoker` views over block tables (ADR 0391), and
clients read them. ADR 0392 and ADR 0393 deferred three things: moving
generated reads from the block table to the view, the cache tags of a read
served from a view, and attachment streams that name more than one subject.

## Decision

Reads already reach the view in the typed client: `gen` types every view in
`config.schemas` as a table (`kind: "view"`), so `db.jobAttachments` reads
`public.job_attachments`. The block clients run SQL functions that carry their
own tenant checks, so they stay on the block table, and a function body never
reads the app's view.

What was missing is below, and now exists.

- **Cache tags through views.** `gen` finds the views the app's schema files
  project over block tables (`projectionsOf`, the same reader the PowerSync
  streams use) and the typed key of each. The `tables` a generated block read
  lists (`reads.attachments.list`) also name those view keys. A read served
  from `jobAttachments` is tagged `bsb:jobAttachments`, and a block write that
  invalidates `attachments` reaches it through the read's table list.
- **Hooks follow the view.** `hooks.ts` writes no hooks for a block table that a
  view projects, when that table is in `config.schemas`. The view's hooks read
  it.
- **Writes go through `$blocks`.** BS351 also reports a write (`.from("view")`
  or `db.<view>.create()`) through a projection view, since the view is never
  the way to change a block's row.
- **Several subjects in one attachments stream.** A view whose `where` names
  several `subject_type` values (`in (...)` or `or`) gets one branch per type:
  `subject_type = 'job' AND subject_id IN (rows of jobs)`. A type with no
  registered subject, or with no tenant column, keeps only its type and the
  organization bound. A view that names no type, or none that is registered,
  stays organization-wide.

The subject registry check (BS382), the bypass check for helper calls (BS381)
and `positionalTeamWrites` (nothing to remove, ADR 0420) are unchanged.
`gen` refuses to overwrite a file it did not write, so a hand-written
`records/<type>.ts` is kept.

## Alternatives considered

Pointing block functions at the view would hide columns the block's own SQL
needs and would run its definer checks over a view with a second RLS layer.
Rewriting the function bodies per app also breaks the rule that module SQL is
static (ADR 0250). Tagging every block read with every view of the schema
over-invalidates, so only the views over a table the read lists are added.

## Consequences

A cached read of a projection view stays fresh after a block write without the
app naming the view anywhere. A table with several views lists all their keys.
A view the typed client does not key (outside `config.schemas`) adds nothing.
`tests/validation-lienlink` holds the `job_parties` child stream, the generated
reads and doctor on the committed app.
