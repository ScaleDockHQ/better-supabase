---
"better-supabase": patch
---

`better-supabase/server` exports `PERMISSION_CAP_CLAIM` (`bsb_permission_cap`), the claim an `authorization.automation.runAs` hook puts the permission cap under. Through 0.15, `cap_allows` and `permissionCapOf` also read the 0.14 name, `bs_permission_cap`, when the new claim is missing, so a hook or a queued job that still carries the old name keeps its cap instead of running uncapped. `runAs` warns once when it gets only the old name.
