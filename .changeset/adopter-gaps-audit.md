---
"better-supabase": minor
---

Approval policy steps take `approvers.decider: true`, so the `decider` option of the leave, expenses and time-entries blocks and leave's `selfDecideWhenTopOfChain` work with the approvals block, and time-entries gets a `decider` option. Attachments take `on.<type>.upload: "subject"` to make the subject row's own update policies decide who attaches and deletes files, and doctor BS345 accepts it. Organizations add `sole_owned_organizations(member)`, which lists the organizations whose last owner a member is. Bank accounts get a `position` column that `saveAccount` sets and lists sort by. An app that keeps `bank_accounts` in its own table adds a `position integer not null default 0` column before upgrading.
