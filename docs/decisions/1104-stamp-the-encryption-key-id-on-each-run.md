# 1104: Stamp the encryption key id on each run and keep a key ring

- Status: accepted
- Date: 2026-11-20

## Context

The World encrypts run data with a key it derives per run (HKDF) from a master
key. Rotation needs more than one master key. The first ring chose the key by
the run's creation time, which the World reads from the run id, so a ring's
`from` dates decided every run's key. Moving one date, or inserting a key
between two, made the runs in that window unreadable. Run attributes are plain
text by design (`$eve.title` is one).

## Decision

`encryptionKeys` (`WORKFLOW_ENCRYPTION_KEYS`, or the Vault secret
`workflow_encryption_keys`) is a ring of `{ id, key, from }`. When the ring has
more than one key, the World stamps the chosen key's `id` on each new run as
the attribute `$bsb.key_id` and reads it before it falls back to the dates. A
ring of one key stamps nothing, and runs created before the ring had a second
key are matched by date. A stamped id that is no longer in the ring falls back
to the date and the read fails.

The missing-key warning stays: `world.start()` warns when no key is set outside
development and test. The eve World suite scans every `workflow` table for a
canary message sent with a key (nothing found) and without one (found), so the
scan is known to see what it looks for.

## Alternatives considered

- A key id column on `workflow_runs`. It would need a module version and a
  change to a table the Workflow SDK owns.
- Store the id in the encrypted payload. The World needs the id to find the key
  that opens the payload.
- Re-encrypt old runs on rotation. It rewrites every run and needs both keys
  at once anyway.

## Consequences

- Moving a `from` date no longer changes which key opens a stamped run.
- Keep every key until no run uses it. Group the runs in `workflow.workflow_runs`
  by the attribute `$bsb.key_id` to list the keys in use.
- Attributes, including the key id, are readable by anyone who can read the
  `workflow` schema, which the API roles cannot.
