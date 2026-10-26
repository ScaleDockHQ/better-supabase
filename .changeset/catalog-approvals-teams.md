---
"better-supabase": patch
---

Fixes three block SQL bugs found by running the Next.js example on the `catalog` permissions model.

- Approval steps that name an approver role (`approvers: { role: "admin" }`) now work under `permissions.model: "catalog"`. The approvals block compared the role key to the membership's role id, which raised `operator does not exist: uuid = text` when it notified approvers or checked who may decide.
- Removing a member from an organization now also removes them from its teams. The teams block's `team_members` foreign key to the memberships table had no `on delete`, so deleting a membership of someone on a team failed. Run `better-supabase upgrade` and generate a migration to pick up `on delete cascade`.
- Turning the teams `patch` option off again drops the `create_team` overload that takes a `slug`, as turning it on already dropped the one without. Before, a database could end up with both, and calls to `create_team` failed as ambiguous.
