# 0162: Care blocks sync offline through PowerSync

## Status

Accepted

## Context

Care staff record notes, vital signs and doses where the network is weak.
PowerSync bypasses row level security, and the care writes have rules a plain
row upload would break: a locked note, a dose that was already given, a reading
sent twice.

## Decision

`powersync streams` supports `activities`, `observations` and `medications`.
Each table streams the rows of the organizations where the user's role holds the
block's `read` key, so these blocks need the roles access model. Only open
progress notes and their links sync. Upload routes replay writes through the
block functions, never row by row: notes carry the local id as `externalRef`,
readings are checked for a duplicate first, and doses go through
`recordAdministration` or `recordAsNeeded`. `careUploadOutcome` turns clinical
conflicts into `conflict` so they reach `connector.rejected`.

## Consequences

Record-team limits are not applied on the device. The server picks the ids of
notes and observations, so a local row is replaced after the sync. Scheduled
doses are planned on the server and only recorded offline.
