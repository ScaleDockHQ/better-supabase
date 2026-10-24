---
"better-supabase": patch
---

Blocks install in any order again. A block file that runs before memberships (such as audit) used to fail with "function better_supabase.member_organization_ids() does not exist", because its `bsb_tenant_scope` policy calls that function. Each block that writes the tenant scope now creates an empty `member_organization_ids` first when it is missing, so the policy admits no rows until memberships installs and replaces it.

The tags block no longer writes `create table if not exists  (` without a name when `tables.taggings` is `null`; it leaves the taggings table out.

Doctor reports one of your policies next to a block's `bsb_<table>_<command>` policy on your table once. BS207 no longer counts that pair as an overlap, since BS347 already reports it when the block's condition is wider.

When tenant and platform invitations share one table (`tables.platformInvitations` naming the tenant invitations table), the invitations block writes one `bsb_invitations_read` policy that reads both, instead of two permissive select policies that doctor BS207 reported.

The drive block's read policy calls the new `drive_readable_ids()` once per statement instead of `drive_can(id, ...)` for every row, so listing a large drive no longer walks each node's ancestors.

Doctor reports fewer false positives on the app's tables that blocks run over. BS347 skips a block policy whose condition is the app's with more `and` operands, such as the actor write check. BS107 counts only the app's own policies when it decides whether such a table is reported, since the block writes through its own functions. BS206 no longer counts a helper called as `(select helper('constant'))`, which runs once per statement.
