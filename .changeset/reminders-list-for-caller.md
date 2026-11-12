---
"better-supabase": minor
---

`reminders.listForCaller()` returns every reminder the caller set in the tenant, with the subject each one is on. The `list_my_reminders` function takes its subject arguments as optional and adds `subjectType` and `subjectId` to each entry, so a "my reminders" page no longer needs one call per subject. Run `better-supabase gen` and `db diff` to pick up the new function.
