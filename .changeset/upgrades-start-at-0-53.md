---
"better-supabase": minor
---

Upgrades start at 0.53. An app on an older version upgrades to 0.53 first. This release removes `$apiResult`, the `triggerSql` overload, the module `version` option, the `openapi` config key (use `specs`), the `canApprove` template and `approvals.distinctApprover` (`isApprover` always refuses the requester), `BLOCK_EVENT_RENAMES`, the 0.15 block renames, the moved-command table, the codemods 0.4 to 0.53 and doctor BS415, BS418 and BS509. The migration guides before 0.53 are gone.
