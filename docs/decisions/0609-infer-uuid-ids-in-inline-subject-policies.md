# 0609: Infer a uuid subject id in the inline read policies

- Status: accepted
- Date: 2026-11-10

## Context

A subject without `idType` is compared as `s.id::text = subject_id`, which cannot use the subject
table's primary key. The registry already takes `idType`, but an app that never set it pays a scan
per row in every inline read policy. Casting `subject_id` to `uuid` for every subject is unsafe:
`subject_id` holds the text ids of every subject type, so a cast the planner evaluates for a row of
another type raises on a non-uuid id.

## Decision

`gen` reads the columns the app's own schema files declare as `uuid` into `layout.uuidColumns`. The
inline read policies (`inlineSubjectReadable`: attachments, reactions, scores) infer `idType: uuid`
for a subject whose id column is listed. The comparison is `s.id = (case when subject_id ~* '<uuid
shape>' then subject_id::uuid end)`. The cast sits in the branch for the subject's own type, and
the shape check turns a malformed stored id into null, so it reads as not found and never raises.
The comparison stays outside the `case`, so the primary key serves it.

Other templates (`subjectReadable` in the functions, versions, trash, reminders and the rest)
keep `s.id::text = value` unless `idType` is configured: they have no per-type branch to guard,
and a configured `idType` still works everywhere. A table a block creates, or an app that declares
the id column in a way the scan cannot read, keeps the text comparison.

## Consequences

An app that omitted `idType` for a uuid-keyed subject gets an index lookup in the read policies
after the next `upgrade`, with no config change. Generated output for apps that set `idType` or
declare no uuid id is unchanged.
