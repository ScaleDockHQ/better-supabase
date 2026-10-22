# 0072: Merge subject records through marked handler functions

- Status: accepted
- Date: 2026-10-22

## Context

The parties block merged duplicate companies and people, but it only moved
its own links. Comments, attachments, reactions, tags, relations and guest
grants stayed on the archived record, and every app had to move them from the
`company.merged` event. Assets and feedback ideas will need the same merge
once those blocks exist. A record merge that lists the modules it knows about
breaks whenever a module is added, renamed or left out of a layout, and the
modules render in separate files that a later `sql sync` can change one at a
time.

## Decision

Every module that stores rows per subject renders a handler,
`<module>_subject_merge(subject_table text, keep text, drop text)`, that maps
the subject table to its registered types and moves its rows. The handler
deletes the dropped record's rows that would duplicate the kept record's
under the module's unique key first. Each handler carries the comment
`better-supabase:subject-merge` and is revoked from every API role.

`better_supabase.merge_subject_refs(subject_table, keep, drop)` finds the
marked functions in `pg_proc` and runs each one. It only runs functions owned
by its own owner, so a marked function another role created can't run with
the owner's rights. It is granted to no API role; a record merge calls it
from a `security definer` function that has already checked the caller.

`recordMergeFunction` (`src/sql/subject-merge-sql.ts`) renders that record
merge: lock both rows, check they can be merged, clear the dropped record's
unique columns, fill the kept record's empty columns, move the module's own
links, call the dispatcher and record the event. Parties uses it for
`merge_companies` and `merge_people`. Apps add their own handler with the same
signature, comment and owner.

## Alternatives considered

- A registry table that modules insert their handler into: it needs data in
  every migration and goes stale when a module is removed without its data.
- One merge function per subject type that lists the modules: it has to be
  re-rendered whenever any module changes and couples parties to every
  module that attaches to records.
- Keep moving references from the `*.merged` events: each app repeats the
  same updates, outside the merge's transaction.

## Consequences

A merge moves every installed module's rows in one transaction, and a new
module only has to render a handler. Relation kinds with `single` or
`acyclic` aren't re-checked after a merge, and the comments activity feed
stays on the dropped record. Assets and feedback ideas should use
`recordMergeFunction` once they ship. We would revisit this if handlers need
an order, which the dispatcher doesn't guarantee.
