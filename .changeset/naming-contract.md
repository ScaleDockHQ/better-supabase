---
"better-supabase": minor
---

Permission keys now follow one convention: `<area>.<verb>`, where the area is the block name in snake_case and the verb is `read`, `write`, `delete`, `manage` or a verb of the domain. A block installed as a named instance checks its own area (`tickets.read` for a `tickets` instance of `tasks`). Run `better-supabase codemod 0.46` to rename the keys in your code, config and SQL; it also renames `createOAuthServer` and the oauth-server block's `OAuth` types.

| Old                                 | New                                                |
| ----------------------------------- | -------------------------------------------------- |
| `parties.*`                         | `contacts.*`                                       |
| `engagements.*`                     | `activities.*`                                     |
| `rules.read`, `rules.edit`          | `automations.read`, `automations.write`            |
| `rules.publish`, `rules.admin`      | `automations.publish`, `automations.manage`        |
| `controls.*`                        | `compliance.*`                                     |
| `support.start`, `.read`, `.revoke` | `impersonation.start`, `.read`, `.revoke`          |
| `work_items.*`                      | `tasks.*`                                          |
| `targets.*`                         | `goals.*`                                          |
| `views.*`                           | `saved_views.*`                                    |
| `history.read`                      | `field_history.read`                               |
| `mail.*`                            | `mail_sync.*`                                      |
| `number_sequences.assign`           | `numbering.assign`                                 |
| `service_principals.*`              | `service_accounts.*`                               |
| `activity.read`                     | `timeline.read`                                    |
| `segments.edit`                     | `segments.write`                                   |
| `ai_chat.admin`                     | `ai_chat.manage`                                   |
| `custom_fields.sensitive.read`      | `custom_fields.read_sensitive`                     |
| `employees.view_sensitive`          | `employees.read_sensitive`                         |
| `workflow.edit`, `workflow.publish` | `workflow_editor.write`, `workflow_editor.publish` |
| `workflow.read`, `.run`, `.admin`   | `workflows.*` and `workflow_editor.*`              |
| `ai.*`, `ai.read`, `ai.create`, ... | one area per AI block (`agents`, `knowledge`, ...) |
| `organization.export`               | `data_lifecycle.export`                            |
| `members.invite` for waitlist codes | `waitlist.invite`                                  |

Old keys keep working until the next minor: roles that list one get the new keys, `permissionMatches` accepts both with a warning, and doctor reports them (BS422). With the catalog access model, `upgrade` renders a data step that renames the stored permission rows and copies their role and override links. `PERMISSION_KEY_RENAMES` and `PERMISSION_KEY_SPLITS` (`better-supabase/blocks/permissions`) and `EVENT_TYPE_RENAMES`, `HINT_RENAMES`, `SUBJECT_TYPE_RENAMES` and `renamed` (`better-supabase`) export the maps.
