# 1027: Close the vocabulary of event verbs that end a record (slice 5)

- Status: accepted
- Date: 2026-11-14
- Amends: 0699

## Context

ADR 0699 fixed the meaning of `cancelled`, `voided`, `closed`, `withdrawn`,
`revoked` and `rejected`, and `check:naming` banned the spellings that drifted
(`canceled`, `removed`, `saved`, `edited`, `upserted`). Lane I audited every
event type that ends a record to see whether blocks follow the meanings.

The audit counted about 110 ending events. All but two use a verb of ADR
0699 or a domain verb with its own meaning (`expired`, `revoked`, `disabled`,
`reversed`, `ended`, `retired`, `unenrolled`, `left`, `declined`, `denied`,
`refused`). `lease.terminated` and `medication_order.stopped` use verbs that
overlap `cancelled`, `closed` and `ended`.

## Decision

No event type is renamed. A rename changes the type a sink or outbox
consumer matches, and each of the two outliers ends a record after it took
effect, which none of the six verbs says: `cancelled` is for records that
never took effect and `closed` for a normal finish. Renaming them would trade
a precise name for a wrong one.

`check:naming` instead closes the door on new synonyms. The `bannedEnding`
keys of `api/naming.json` (`aborted`, `abandoned`, `dismissed`, `discarded`,
`deactivated`, `invalidated`, `finished`, `stopped`, `terminated`) fail with
the verb to write. `endingExceptions` lists the two types above by name, and
the check fails when a listed type no longer exists, so the list only
shrinks.

## Consequences

Nothing breaks: no event, method or SQL function changes, so there is no
changeset and no migration. A new ending event that needs one of the banned
verbs adds a row to `endingExceptions` with the reason in its pull request.
