---
"better-supabase": minor
---

Breaking: `forms` gets `archiveSubmission` and `restoreSubmission`, and the hard
delete of a submission is `purge`, behind its own `permissions.purge` key (it
falls back to the review permission). An archived submission leaves
`listSubmissions` and `nps`; `listSubmissions` takes `includeArchived`, and
`FormSubmission` carries `archivedAt`.

| Before                                   | After                                  |
| ---------------------------------------- | -------------------------------------- |
| `forms.deleteSubmission(id)`             | `forms.purgeSubmission(id)`            |
| `delete_form_submission(submission_id)`  | `purge_form_submission(submission_id)` |
| event `form_submission.deleted`          | event `form_submission.purged`         |
| `hooks.deleteSubmission`                 | `hooks.purgeSubmission`                |
| `list_form_submissions` with 4 arguments | a fifth argument, `include_archived`   |

New events are `form_submission.archived` and `form_submission.restored`. A
draft is refused by `archiveSubmission`; a respondent still purges their own
draft. Run `better-supabase upgrade` and apply the migration. See the 0.66 to
0.67 guide.
