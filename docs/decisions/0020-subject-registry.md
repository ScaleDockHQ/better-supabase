# 0020: Declare subject types once in config.subjects

- Status: accepted
- Date: 2026-10-13

## Context

Tags, comments, attachments, reminders, the state machine, custom fields and
share links each take `options.subjects`, and an app that installs five of
them repeats the same `{ table, id, tenant, permission }` five times. The
copies drift, and nothing outside a module can ask what a subject is called,
where it lives in the app, or whether the caller may act on it. Later blocks
(approvals, trash, search, versions, activity feeds) need those three answers
for every subject type, and the frontend needs a typed `SubjectType`.

## Decision

`config.subjects` (`src/config/types/subjects.ts`) is the app-wide registry:
each type's table, id, id type, tenant, title column, URL template,
permission keys per action, scope, cascade, soft-delete column, search
columns and rank column. `subjectsOption` in `src/sql/subjects.ts` falls back
to it when a module's `subjects` option is unset, accepts a list of
registered names, and merges an object entry onto the registered one with
the module's keys winning. Modules whose subjects are not app records
(`webhooks-in`) pass `fallback: false`.

The `subjects` SQL module renders `subject_types`, `subject_title`,
`subject_url` and `can_subject` from the registry. They are security
invoker, so the subject table's policies decide visibility, and
`can_subject` adds the action's key through the access module's `can`.
`gen` emits `subjectTypes`, `SubjectType` and `SubjectRef` and passes
`SubjectType` as the fourth parameter of `Schema`, through `defineSchema`
rather than module augmentation (invariant 2). Doctor checks the registry
against the snapshot (BS331, BS332).

## Alternatives considered

- **Keep per-module options only.** Every new block would repeat the
  mapping, and there would be no single place to answer "what is this
  subject" for notifications, search or trash.
- **A `subjects` table filled at run time.** It would move a schema fact
  into data, `sql sync` could not check the columns, and the functions would
  need dynamic SQL for every lookup.
- **Security definer lookups.** They would read rows the caller cannot see,
  which is the opposite of what a title or URL for a notification needs.

## Consequences

A new subject-bound block reads the registry for free, and its docs can say
"register the type once". Changing the registry changes every module that
falls back to it, so `sql sync` rewrites those files together. A registry
entry cannot carry module-specific keys such as a table binding (ADR 0018);
those stay in the module's own `subjects` object, which merges over it.
Revisit if the registry needs per-environment differences.
