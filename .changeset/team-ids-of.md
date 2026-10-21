---
"better-supabase": minor
---

Add `authorization.functions.teamIdsOf`, a template that returns the team ids
a user belongs to. Under the `provider` access model, `team_ids_of()` in the
`teams` block returns its set instead of reading `team_members`, and
`saved-views` and `collections` share with those teams even without the
`teams` block. Doctor BS417 warns when the provider declares a `team` scope,
one of those blocks is installed, and the template is unset.
