---
"better-supabase": minor
---

The `engagements` SQL module and `better-supabase/blocks/engagements` log calls, emails, meetings, notes and tasks on one or more records registered in `config.subjects`, with an owner, a due time, an outcome and an external id that makes a repeat log an update. `of(subject)` reads a record's engagements, `next(subject)` its next planned step with an overdue flag, and `open(organizationId)` a member's open tasks. An engagement is visible to callers who can read one of its records, and assigning it to someone else notifies them.
