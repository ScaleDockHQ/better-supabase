# 0132: Build quality management from five cross-cutting blocks

- Status: accepted
- Date: 2026-10-29

## Context

A quality management system (ISO 9001, ISO 13485, ISO 45001 and their
audits) needs controlled documents, read-and-understood records, a CAPA
process, complaints, change control, internal and supplier audits, a risk
register and a training matrix. Products usually ship each of these as its
own module with its own record, its own workflow and its own links between
them.

The library already has most of the parts: `compliance` for controls and
policies, `tasks` for actions, `forms` for checklists, `pipelines` and
`state-machine` for stages, `approvals`, `versions`, `relations`,
`courses`, `incidents` for software outages, and `drive` for files. What it
lacks are the records that tie them together, and the QMS products that
copy one module per process would add five near-identical CAPA-like blocks.

## Decision

Five blocks cover the gap, each usable outside quality management:

- `acknowledgements` records that a person read and understood one version
  of any record (a policy, a controlled document, a work instruction). It
  replaces the compliance block's own policy acknowledgements.
- `cases` is one record type, with tenant-editable kinds, for
  nonconformities, complaints, safety incidents, near misses, observations,
  improvements, change requests and audit findings. Each kind has its own
  pipeline and its close rules (root cause, actions as tasks, an
  effectiveness check, revised documents). It replaces separate CAPA,
  change, complaint and safety-incident modules. `incidents` stays for
  software outages and status pages.
- `inspections` plans audit programs and runs audits and inspections with a
  checklist form, findings and a case per nonconformity.
- `risks` keeps a register scored on a tenant-defined matrix, with
  assessments, treatments, reviews and a heatmap.
- `qualifications` records which person, company or asset holds which
  qualification, what each role, team or asset kind requires, and the gaps.

Traceability between them runs through `relations` kinds that each block
contributes (`affects`, `assesses`, `mitigated_by`, `materialized_as`), not
through foreign keys between blocks, so each block installs alone and the
links appear when both sides are installed.

The audit block is called `inspections` because `audit` is already the audit
log's entity and event prefix (`audit.*`); a second `audit` entity would
clash with it under ADR 0130.

## Alternatives considered

- **One `qms` block with every table.** It would duplicate tasks, forms and
  approvals, and an app that only wants complaints or a training matrix
  would install all of it.
- **One block per process (CAPA, complaints, change control, safety).** They
  share the same lifecycle and close rules; five blocks would diverge, and
  reporting across them would need a union of five tables.
- **Use `incidents` for nonconformities.** Its model is an outage with a
  timeline and a status page; quality cases need kinds, root causes and
  effectiveness checks it doesn't have.
- **Call the audit block `audits`.** The plural reads well but collides with
  the audit log's names.

## Consequences

A `qms` preset wires the five blocks with drive's controlled documents (ADR
0133), and each block also serves other presets: cases for help desks and
field service, qualifications for care and staffing, risks for compliance.
Compliance moves its acknowledgements onto the new block in a breaking
change with a data migration. Reports across processes read one `cases`
table. Revisit when a regulated domain needs a record with rules that a case
kind can't express.
