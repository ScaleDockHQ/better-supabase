# 0130: Merge overlapping blocks

- Status: accepted
- Date: 2026-10-28

## Context

Several blocks own a second copy of data another block already owns, or
keep a parallel record of the same work.

- `inbox` owns `contacts` and `contact_identities` next to the `contacts`
  block's `people`, with a `person_inbox_contacts` link table between them.
- `sequences` owns `sequence_enrollments` next to the `enrollments` block,
  which already tracks a subject through a program of steps.
- `ai-files` owns `ai_document_versions` next to the `versions` block.
- `incidents` keeps postmortem action items in a `jsonb` column while the
  `tasks` block owns tasks.
- `compliance` owns `policy_acknowledgements` next to the new
  `acknowledgements` block.

## Decision

Move each copy onto the block that owns the concept, with a data migration
and deprecated client wrappers for one minor.

- Inbox conversations point at `people.id`. `contact_identities` becomes
  `contacts`' `person_identities`, and the inbox contact methods move to
  `createContacts`.
- `sequences` uses `enrollments` rows keyed `sequence:<id>`, as `courses`
  uses `course:<id>`, and drops `sequence_enrollments`.
- `ai-files` stores versions through the `versions` module and drops
  `ai_document_versions`.
- `incidents` links postmortem actions to tasks through
  `incident_postmortem_actions` when `tasks` is installed. The
  `action_items` column stays readable for one minor.
- `compliance` assigns policies through `acknowledgements` and drops
  `policy_acknowledgements` and `acknowledge_policy`.

The overlaps left for later are recorded on the roadmap: `collections` and
`saved-views`; `pipelines` and `state-machine` stage tables; the schedule
engines (`reminders`, `calendar`, `ai-schedules`, queue and workflow
schedules); the automation stack (`workflows`, `workflow-editor`,
`workflow-sdk`, `automations`, `sequences`); the credential blocks; `sso`
domains and `domains` hostnames; and the docs folder moves for `incidents`,
`enrollments`, `lead-scoring`, `assignment`, `trash`, `versions` and
`imports`.

## Alternatives considered

- **Keep the copies and sync them.** Two writers per fact and a
  reconciliation job, for no gain.
- **Move the other way**, making `contacts` read inbox's tables. Inbox's
  contacts are channel addresses, not people; the person is the durable
  record.

## Consequences

One block owns each fact. Apps that read the removed tables or called the
removed functions move once, guided by the migration guide and the
deprecated wrappers. Inbox loses its own contact search, so it needs
`contacts` installed.
