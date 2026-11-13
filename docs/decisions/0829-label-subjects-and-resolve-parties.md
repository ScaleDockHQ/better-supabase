# 0829: Label subjects in a batch and resolve parties

- Status: accepted
- Date: 2026-11-13

## Context

A subject reference is a type and an id. Reviews, segments, the inbox and the
portal showed raw ids because nothing turned a reference into text (EX-1296).
Contacts, people, employees, identities and profiles each model a person, and
detail pages joined them by hand to show a name and an avatar (EX-1295).

## Decision

`subjects.label(refs)` returns a `SubjectLabel` for every ref, keyed by
`subjectKey`: the title when the caller can read one, else the id with
`found: false`. It is TypeScript over `resolve`, so it needs no new SQL
function, and `batchSubjects` joins the labels of one tick into one
`subject_titles` call per 500 refs.

`createPartyResolver` in `src/core/party.ts` turns any subject into a `Party`
with a name, initials, an avatar URL and the subject's page. It takes
`subjects.label` and a reader per subject type for the types that store a name
and a picture. A reader's name wins over the label, and a type without a reader
keeps the label and has no avatar. The core imports no block, so an app wires
its own readers and the cores of `contacts`, `employees` and `identities` can
adopt it later.

## Alternatives considered

A SQL `subject_label` function that joins every registered type's name column
would give one round trip, but a title column is not a person's name for
every type, and the avatar column differs per table. Readers keep that
knowledge in the app or the block that owns the table.

## Consequences

`Subjects` gains `label`, so a hand-built `Subjects` double adds it.
`better-supabase/blocks/subjects` exports `createPartyResolver`, `initialsOf`
and the party types.
