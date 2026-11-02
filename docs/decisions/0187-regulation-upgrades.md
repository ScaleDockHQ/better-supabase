# 0187: Five blocks take on regulatory workflows

- Status: accepted
- Date: 2026-11-01

## Context

Five existing blocks sit on regulated processes but only store the records:
`moderation` (EU Digital Services Act), `incidents` (NIS2, DORA, Cyber Resilience Act),
`consents` (Global Privacy Control, IAB TCF and GPP), `data-lifecycle` (GDPR data subject
requests) and `compliance` (OSCAL). Apps had to build the deadlines, the evidence and the
exports themselves.

## Decision

Each block gains tables and functions in a new module file, so the existing files stay
readable and each module `version` goes up by one with an upgrade step. The tables are
created with `create table if not exists`, so the steps ship no SQL. Existing permission
keys cover the new functions, and no new `OPERATIONS` entries are needed.

- `moderation` 2: statements of reasons with the Article 17 fields, notices with trusted
  flaggers, appeals, and a transparency report as CSV.
- `incidents` 4: a regulatory profile per incident and one filing per deadline (NIS2 early
  warning at 24 hours, notification at 72 hours, final report one month later; DORA initial,
  intermediate and final reports; CRA early warning and notification). Each deadline is a
  `reminders` rule when that block is installed, and each submission is a recorded filing.
- `consents` 2: Sec-GPC as a refused consent, TC and GPP strings parsed in SQL and kept as
  evidence, and consent receipts with a SHA-256 digest.
- `data-lifecycle` 9: data subject requests with identity verification, a 30 day due date,
  one extension to three months, and fulfilment through the NDJSON export. Erasure is
  refused under a legal hold and otherwise records that the app deleted or anonymized the data.
- `compliance` 4: OSCAL catalog import, profile application and assessment results export.

Each followed specification is pinned in `SPEC_PINS` and listed on the standards page.

## Alternatives considered

- Edit the existing module files in place: it makes the diff of every block larger and hides
  which functions are new.
- Delete personal data inside `fulfil_data_subject_request`: the block can't know every table
  that holds a person's data, and the purge and anonymize functions already exist.
- Follow an OSCAL profile's import `href`: it needs a network call in the database.

## Consequences

The parsers read only the TCF core segment and the GPP header, not vendor sections or GPP
section ids. The plpgsql was checked by rendering tests and, for the parsers and the OSCAL
JSON paths, in PGlite. It was not run against the local stack. Revisit when a real stack
run is available, and when an app needs the TCF vendor sections.
