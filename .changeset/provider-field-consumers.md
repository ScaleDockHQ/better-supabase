---
"better-supabase": minor
---

The 0.26 provider fields now have readers. `memberships[].userKey` is the column the derived `memberIds` and `memberIdsFor` templates match against `auth.uid()`. A level key (`file.read@team`) is never `sqlComplete`, so policies refuse it, and an unlisted level counts as missing. `tokenHook.teamIdsTruncatedClaim` (and `permissions_truncated` from `truncatedClaim`) feed the hook plan, and `Bootstrap.teamIdsTruncated` reports a partial `team_ids` claim. The sessions `hook` option takes `teamIdsTruncatedClaim`. `approverFor` and `managedUsers` stay accept-and-validate (ADR 0520). `better-supabase upgrade` rewrites the `sessions` module only for apps that set `hook`; no data migration is needed.
