---
"better-supabase": minor
---

Add three blocks: `sequences` for multi-step outreach, `lead-scoring` for scores fed by segments, mail and enrichment, and `posts` for forum and feedback boards.

- `better-supabase/blocks/sequences` runs email, wait and task steps per contact as an enrollment program (`sequence:<id>`). `runDue()` sends due emails from the contact's mailbox through the new `mailer` port, which `mail-sync` provides, retries failed sends and ends a run when the contact replies. Task steps create work items when `work-items` is installed.
- `better-supabase/blocks/lead-scoring` scores people, and optionally companies, under a `scores` model. `leadRuleFields(subjectType)` adds the `segments`, `mail.*` and `enrichment.status` fields to the rule catalog, a trigger marks records whose columns, segments or mail changed, and `scoreDue()` rescores them.
- `better-supabase/blocks/posts` keeps boards and posts with votes from `reactions`, replies from `comments` and reports, hiding and bans from `moderation`. Moderators set a roadmap status, pin, lock and merge duplicates, and `moderation: "pre"` holds new posts for review.
- `mail-sync` lets the service role record a sent message for any connected mailbox, so a server-side sender such as the sequences runner can send on a member's behalf.
- The enrollments block refuses to complete or reset a step of a `sequence:` program, as it does for `course:` programs.
- The `sequence-builder` and `post-board` UI recipes show the blocks in the example app.
