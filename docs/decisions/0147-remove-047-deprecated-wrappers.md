# 0147: Remove the deprecated 0.47 wrappers before release

- Status: accepted
- Date: 2026-10-30

## Context

0.47 deprecated the compliance acknowledgement wrappers and
`inbox.contacts.upsert`, to go in 0.48. 0.47 is not released and already
carries breaking changes, so keeping them for one more release only adds code
that nobody has used yet.

## Decision

- `acknowledgePolicy`, `acknowledgements(policyId)`, `policies(..., { pendingOnly })`
  and the `policySubjectType` option leave the compliance client.
- `inbox.contacts.upsert` and the `upsert_contact` SQL function leave the inbox.
- The migration guide lists them as removed in 0.47.
- Postmortem `actionItems` and the foreign key column renames stay deprecated
  until 0.48, because the copy step for action items must run on a database
  before the column goes. 0149 removes `actionItems` in 0.47 with an upgrade step.

## Alternatives considered

- **Keep every wrapper until 0.48.** Nobody can depend on a release that was
  never published.
