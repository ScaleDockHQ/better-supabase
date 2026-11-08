---
"better-supabase": minor
---

Engagements are activities everywhere: the `engagement_subjects`, `engagement_recordings`, `engagement_notes` and `engagement_transcript_segments` tables are `activity_*`, the `Engagement*` types are `Activity*`, hint codes start with `ACTIVITY_`, and the mail-sync option `engagementType` is `activityType`. Three events use the lifecycle verbs. Run `better-supabase codemod naming`, then `upgrade`; no data moves.

| Old                                              | New                                                                                          |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| `engagement_subjects` and the other three tables | `activity_subjects`, `activity_recordings`, `activity_notes`, `activity_transcript_segments` |
| `EngagementInput`, `EngagementEventData`         | `ActivityInput`, `ActivityEventData`                                                         |
| `ENGAGEMENT_NO_TRANSCRIBER`                      | `ACTIVITY_NO_TRANSCRIBER`                                                                    |
| `blocks.mail-sync.options.engagementType`        | `blocks.mail-sync.options.activityType`                                                      |
| `vex_statement.saved`                            | `vex_statement.updated`                                                                      |
| `team_member.removed`                            | `team_member.deleted`                                                                        |
| `reaction.removed`                               | `reaction.deleted`                                                                           |
