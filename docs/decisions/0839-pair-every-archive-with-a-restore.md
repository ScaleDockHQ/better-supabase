# 0839: Pair every archive with a restore

- Status: accepted
- Date: 2026-11-14

## Context

The block consistency audit (EX-1206) counted 37 blocks that archive and
only 16 that restore. A record that was archived by mistake could only come
back through SQL, or by saving it again under the same key where the module
happened to un-archive on save. Archive and restore also recorded no event in
most reference-data blocks, so a sink never saw the change.

## Decision

Every `archive` has a `restore` that clears `archived_at` under the same
permission key as the archive (no new key: the key that hides a record also
brings it back). Each pair records `<entity>.archived` and
`<entity>.restored`, and writes an audit row in the same transaction.

Lane I ships this by category. The first slice covers the reference types
whose archive takes a single id and has no flag: `leave_type`,
`qualification_type`, `donation_fund` and `expense_category`. The client
methods are `restoreType`, `restoreType`, `restoreFund` and
`restoreCategory`, next to the existing `archive*` methods. Blocks whose
archive already takes an `archived` flag keep it and gain a `restore`
alias in a later slice. Slice two turns `delete` into `purge` where a record
has an archive, and slice three adopts the event verbs.

## Alternatives considered

An `archived` boolean on one function (as `archive_deal` does) needs no new
function, but it hides the intent in a flag and gives the restore no event of
its own. A separate `restore` key would let an app allow archive without
restore, which no block needs.

## Consequences

Four more `security-definer-functions` per block in the practices baseline.
Apps that read the event catalog see new event types. No existing call
changes, so this slice is not breaking.
