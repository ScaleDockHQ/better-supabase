---
"better-supabase": patch
---

Leave request notes are private: `list`, `requestPage` and `get` return `note`
only to the requester, their manager and members with `leave.approve` or
`leave.manage`, and `null` to other readers, and `q` no longer matches notes
the caller can't read. `get_leave_request` checks the caller itself instead of
relying on the table's read policy. A block table listed in `expose` keeps the
privileges the grants module writes: the block no longer adds its own
table-wide select grant, so `select(*, -note, -decision_note)` closes direct
reads of the note columns.
