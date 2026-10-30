---
"better-supabase": minor
---

Records can have a team. Add `team: { actions: ["read", "write"] }` to a type in `config.subjects`, and `can_subject` and `can_subject_for` grant those actions to the users and teams on that record whose dates include today, next to the permission keys. The `subjects` block installs `subject_members` (a user or a team from the `teams` block, a role, `starts_on` and `ends_on`) with `add_subject_member`, `end_subject_member`, `list_subject_members` and `my_subjects`, and emits `subject_member.added` and `subject_member.ended`. Adding and ending a membership needs the new `subjects.manage` key (the `admin` role gets `subjects.*`) or `manage` on the record. Roles default to `lead` and `member`; `blocks.subjects.options.recordTeam.roles` changes them.

The client gets `subjects.members.add`, `end`, `list` and `mine`. When a type declares a team, the `represents` relation kind accepts only targets of such a type. With an authorization provider, list `subjects.manage` among its permissions or point `blocks.subjects.permissions.manage` at a key it has, or `upgrade` stops. Run `better-supabase upgrade` and generate a migration to pick up the table and functions.
