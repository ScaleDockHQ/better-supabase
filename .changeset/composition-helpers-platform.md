---
"better-supabase": minor
---

Platform blocks gain helpers that replace calls to several methods or raw `$api` and `$rpc`, each
taking one object and returning a Result. New: a `sessions` client (`listMine`, `end`, `endOthers`),
`profiles.setAvatar` with the `avatarUploader` and `avatarColumn` options, `flags.isEnabled` and
`flags.tenantsWith`, `webhooks.createEndpoint({ withSecret })` and `webhooks.setEnabled`,
`organizations.owner` and `organizations.memberRoles` (with the `ownerRole` option),
`teams.setMembers` and `teams.setArchived`, `entitlements.seatsLeft`, the onboarding step option
`completeOn`, `audit.correlated`, `dataLifecycle.exportNow` and `billing.startTrial`. Run
`better-supabase upgrade` to regenerate the onboarding module.
