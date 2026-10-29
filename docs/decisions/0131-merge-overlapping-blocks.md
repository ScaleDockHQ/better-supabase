# 0131: Move overlapping block tables onto the block that owns the concept

- Status: accepted
- Date: 2026-10-29

## Context

The naming audit behind ADR 0130 found blocks that keep their own copy of a
concept another block already owns:

- `inbox` owns `contacts` and `contact_identities`, while the `contacts`
  block owns `people` and links them to inbox contacts through
  `person_inbox_contacts`. An app with both has two records for one person.
- `sequences` tracks who is in a sequence in `sequence_enrollments`, although
  it already requires `enrollments`, which `courses` uses for the same job
  (`course:<id>`, ADR 0085).
- `ai-files` keeps `ai_document_versions` beside the `versions` block.
- Incident postmortems store their action items in an `action_items` jsonb
  column, so they can't be assigned, tracked or listed like tasks.
- Compliance policy acknowledgements live in `policy_acknowledgements`,
  which no other record can use.

Each copy has its own functions, events and permissions, so the overlaps
grow with every feature added to either side.

## Decision

Four refactors move the copies onto the owning block, each with a data
migration and one minor of deprecated client wrappers:

1. Inbox contacts move onto `contacts`. `inbox` requires `contacts`,
   conversations point at `people`, and `contact_identities` becomes
   `person_identities`, owned by `contacts`. The data step creates a person
   for each inbox contact without one (matched on email first), copies the
   identities, repoints conversations and drops `person_inbox_contacts` and
   the inbox contact tables.
2. Sequences move onto `enrollments`. A sequence enrollment is an
   `enrollments` row with program key `sequence:<sequence id>`, and the
   sequence step maps onto the enrollment step's assignee and due date (ADR
   0121). `sequence_enrollments` is copied and dropped.
3. AI file versions move onto `versions`. Each `ai_document_versions` row
   becomes a `versions` row with subject type `ai_document`, and `ai-files`
   requires `versions`.
4. Incident postmortem actions become tasks. When `tasks` is installed,
   `incident_postmortem_actions` links a postmortem to the tasks it creates;
   the `action_items` column stays readable for one minor and is no longer
   written.

Compliance policy acknowledgements move onto the new `acknowledgements`
block (ADR 0132) rather than a refactor of their own.

These overlaps stay as they are, recorded on the roadmap for later plans:
`collections` and `saved-views`; the `pipelines` and `state-machine` stage
tables; the schedule engines (`reminders`, `calendar`, `ai-schedules`, queue
schedules, workflow schedules); `workflows`, `workflow-editor`,
`workflow-sdk`, `automations` and `sequences`; the credential blocks
(`api-keys`, `service-accounts`, `oauth-server`, `signing-keys`,
`credentials`, `ai-keys`); `sso` domains and `domains` hostnames.

## Alternatives considered

- **Leave the copies and document which one to use.** Apps that install both
  sides would still hold two records for one person or one version history,
  and every feature would still be built twice.
- **Merge the blocks themselves** (inbox into contacts, sequences into
  enrollments). The blocks do different jobs; only the overlapping tables
  move.
- **Do all overlaps at once.** The ones left for later need design work of
  their own (one schedule engine, one workflow stack), and bundling them
  would hold back the four moves that are mechanical.

## Consequences

Each refactor is a breaking change with a migration test that seeds the old
rows, runs the data step and checks the new ones. Apps that call the moved
client methods get deprecated wrappers for one minor, then must call the
owning block's client. A person, a version history and an enrollment exist
once, so search, merges, exports and permissions apply to them without
extra work.
