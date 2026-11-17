---
"better-supabase": patch
---

Blocks no longer create an index that already exists. Two block statements that build the same index, such as the `invited_by` index of tenant and platform invitations sharing one table, now render once. Over an adopted table, a partial or `gin` index is left out when the app's index has the same method, columns and `where`, and an app index that only shares its name with a block index (such as `team_members_user_idx`) now counts as the app's, so `team_members_membership_idx` and `webhook_endpoints_types_idx` no longer duplicate the app's indexes and doctor BS200 stops reporting them.
