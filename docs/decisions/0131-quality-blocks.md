# 0131: Quality blocks

- Status: accepted
- Date: 2026-10-28

## Context

An ISO 9001 quality system, and the wider QHSE, KAM, GRC, EHS, ISMS, HCM and
CMMS systems built on the same patterns, need five things the catalog does
not have: proof that a person read a document, one record for every
nonconformity and complaint, audits and inspections with findings, a risk
register with assessments, and competence records.

Building them as vertical blocks would copy the same tables into each
vertical. The existing catalog already has the primitives they need:
`subjects`, `versions`, `pipelines`, `tasks`, `forms`, `relations`,
`approvals`, `numbering`, `drive`, `compliance` and `courses`.

## Decision

Five cross-cutting blocks, each installable on its own:

- `acknowledgements` records that a person read one version of a record.
- `cases` holds nonconformities, complaints, safety incidents, near misses,
  observations, improvements, change requests and audit findings, with a
  pipeline per kind, a root cause, actions as tasks, an effectiveness check
  and a closure guard.
- `inspections` holds audit and inspection programs, inspections, teams,
  checklist forms and findings that raise a case.
- `risks` holds matrices, a register, versioned assessments and barriers
  linked through `relations`.
- `qualifications` holds types, requirements, holdings for members,
  companies and assets, gaps and expiry.

Traceability runs through `relations` kinds (`affects`, `assesses`,
`mitigated_by`, `materialized_as`, `variant_of`), not through columns that
point at one block. `cases` replaces separate CAPA, change, complaint and
safety-incident modules. `incidents` stays for software outages and keeps
its postmortems.

The audit block is called `inspections`, not `audit`: `audit` is the audit
log's entity and event prefix, so a second `audit` entity would clash in
entity keys, events and hints. The page title is "Audits and inspections".

## Alternatives considered

- **One `quality` block.** It would install as one unit and force apps
  that only need a risk register to take cases and inspections too.
- **Vertical blocks per standard.** Four copies of the same tables, and
  every change lands four times.
- **Name it `audit`.** Clashes with the audit log's `audit.*` events and
  `audit` entity.

## Consequences

Each block composes with the others and with the existing catalog. A QMS
preset wires them together with `drive` controlled documents. Apps that
want only one of them install only that one. Revisit if the traceability
kinds need typed columns for query performance.
