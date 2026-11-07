---
"better-supabase": minor
---

A column that references a user is named by its role, `<role>_id`, instead of `<role>_user_id`. Run `better-supabase codemod naming` to write the migration that renames the columns of an installed app, then `upgrade`; no data moves. SQL function parameters take the same names. `scim_group_members.scim_user_id` stays because it references `scim_users`.

| Old                                                             | New                                            |
| --------------------------------------------------------------- | ---------------------------------------------- |
| `owner_user_id`                                                 | `owner_id`                                     |
| `customer_user_id`, `reviewer_user_id`, `host_user_id`          | `customer_id`, `reviewer_id`, `host_id`        |
| `holder_user_id`, `assignee_user_id`, `speaker_user_id`         | `holder_id`, `assignee_id`, `speaker_id`       |
| `hiring_manager_user_id`, `referred_user_id`, `actor_user_id`   | `hiring_manager_id`, `referred_id`, `actor_id` |
| `from_user_id`, `to_user_id`                                    | `from_id`, `to_id`                             |
| `subject_user_id` (appraisals), `decided_user_id` (quotes)      | `appraisee_id`, `decider_id`                   |
| `given_by_user_id` (consents), `paused_by_user_id` (lifecycles) | `grantor_id`, `paused_by`                      |
