# 0069: Keep document suggestions outside the update log until an editor accepts them

- Status: accepted
- Date: 2026-10-22

## Context

Phase 7 of the SaaS parity track asks for a suggestion mode in documents
and for named versions. A document is a Yjs update log (ADR 0022): every
update in `document_updates` is part of the document the moment it is
stored, and the database never parses Yjs. Suggestions have to come from
people who may only read the subject, and must not change the document
until an editor agrees.

## Decision

A suggestion is a Yjs update stored in a new `document_suggestions` table,
not in the log. `suggest_document_change` takes it from anyone who may read
the document and holds `documents.suggest` (members get it by default).
`decide_document_suggestion` accepts, rejects or withdraws it; accepting
appends the stored bytes to the log with the author as actor, so the merge
is the normal CRDT merge and history shows who wrote the change. A decided
suggestion is final. The provider collects local edits as a draft in
suggest mode and submits them as one merged update.

Named versions reuse the versions module: a name is the version's label,
`name_document_version` sets or clears it, and frozen versions keep theirs.

## Alternatives considered

- Suggestions as marks inside the Yjs document (the way some editors track
  changes): every client would need the editor's suggestion schema, the
  database couldn't check who may suggest, and a reader would need write
  access to the log.
- A branch per suggestion as a second document: accept would need a
  three-way merge in the client and doubles storage for long documents.
- A separate table for named versions: the versions module already stores
  labels, frozen flags and retention.

## Consequences

An accepted suggestion applies on top of whatever the document became after
it was made, so it merges like a late edit; editors see the result, not a
diff, and review happens before accepting. The example shows the summary
only; rendering a preview of the change is left to the editor integration.
Suggestion payloads count toward `maxUpdateBytes` like any update.
