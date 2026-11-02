---
"better-supabase": minor
---

Remove the deprecated aliases and options that were due, and share helpers that several modules
had copied.

| Removed or changed                                                       | Use instead                                                           |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------- |
| `createOAuthServer` and the `OAuth*` type aliases                        | `createOauthServer` and the `Oauth*` types from `blocks/oauth-server` |
| `createRateLimit`, `rateLimited` and `RateLimit*` from `blocks/queue`    | the same names from `better-supabase/rate-limit`                      |
| `receiveEInvoices` options `xmlParser` and `FromUblOptions`              | pass `readUbl: (xml) => fromUbl(xml, options)`                        |
| outbox `legacyEventTypes` and the `currenttype` extension                | the event type `<prefix>.<entity>.<verb>`                             |
| `DbError.legacyHint`                                                     | `DbError.hint`                                                        |
| `SequenceEnrollmentEventData`                                            | `EnrollmentEventData` from `blocks/enrollments`                       |
| `workItemChecklistBinding`                                               | `taskChecklistBinding`                                                |
| `AssistantRunResult.toUIMessageStream`, `totalUsage`, `providerMetadata` | `stream`, `usage` and `finalStep`                                     |

New exports: `dbErrorOfStatus` (maps an HTTP status to a `DbError`). The SQL helper
`sha256Hex` in `sql/shared` is now `sha256HexSql`. The `maintenance` block calls
`better_supabase.rrule_occurrences` and drops `maintenance_rule_starts`; the migration
`20261102110000_maintenance_use_core_rrule.sql` applies this.
