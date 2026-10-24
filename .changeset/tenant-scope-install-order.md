---
"better-supabase": patch
---

Blocks install in any order again. A block file that runs before memberships (such as audit) used to fail with "function better_supabase.member_organization_ids() does not exist", because its `bsb_tenant_scope` policy calls that function. Each block that writes the tenant scope now creates an empty `member_organization_ids` first when it is missing, so the policy admits no rows until memberships installs and replaces it.

The tags block no longer writes `create table if not exists  (` without a name when `tables.taggings` is `null`; it leaves the taggings table out.

Doctor reports one of your policies next to a block's `bsb_<table>_<command>` policy on your table once. BS207 no longer counts that pair as an overlap, since BS347 already reports it when the block's condition is wider.
