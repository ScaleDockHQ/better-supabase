---
"better-supabase": patch
---

Fixes for blocks that run over the app's tables, and for the tenant scope.

- Blocks install in any order again. A block file that runs before memberships (such as audit) used to fail with "function better_supabase.member_organization_ids() does not exist"; each block that writes the tenant scope now creates an empty `member_organization_ids` first when it is missing.
- The rendered block files are the same whatever order the blocks are listed in, so their `@bsb-hash` no longer changes between runs.
- Channels cast the visibility they write, and the conversation access they set, to the column's type, so both can be enums of the app's. The hiring and deals pipelines use the tenant column `columns.<table>.tenant` maps, and inventory moves stock without a ledger `memo` column when `ledger.columns.transactions.memo` is `null`.
- The tags block no longer writes `create table if not exists  (` without a name when `tables.taggings` is `null`.
- When tenant and platform invitations share one table, the invitations block writes one `bsb_invitations_read` policy that reads both.
- The drive block's read policy calls `drive_readable_ids()` once per statement instead of `drive_can(id, ...)` for every row.
- Over your own tables, `profiles` no longer adds an `avatar_path` column it doesn't use, and `forms` scores submissions unless `columns.submissions` maps `score`, `maxScore` or `passed` to `null`. `add --adopt` lists a required column the block adds as `<column> (the block adds it)`.
- Doctor reports fewer false positives on the app's tables. BS309 skips an old name on a table of yours, BS207 no longer counts your policy next to a block's `bsb_` policy (BS347 reports it), BS347 skips a block policy whose condition is yours with more `and` operands, BS107 counts only your own policies, and BS206 no longer counts a helper called as `(select helper('constant'))`.
