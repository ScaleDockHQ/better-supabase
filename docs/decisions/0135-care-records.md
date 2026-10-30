# 0135: Keep care records in domain-neutral blocks keyed on any subject

- Status: accepted
- Date: 2026-10-30

## Context

Care, support and welfare apps (home care, disability support, youth care,
mental health, social work, and also coaching and case management outside
healthcare) keep the same records about a client: a care plan with problems,
goals and actions, progress notes and observations, medications, consents
and the funding that pays for the care. Products in this space usually model
the client as a fixed `patient` table and copy one national format into
their schema (the Dutch zorgplan, the Omaha System, NANDA-I, ICF), which
ties the app to one country and one kind of client.

The library already keys records on the subject registry: tasks, approvals,
versions, signatures, relations and guests work on any registered subject.
A care block that owned its own client table would duplicate the app's
customers, residents or members, and would not reach the blocks that already
attach to them.

## Decision

Care records are blocks keyed on any subject (`subject_type`, `subject_id`),
never on a client table of their own. The first is `care-plans`
(`better-supabase/blocks/care-plans`): a plan per client with problems,
goals and actions, published as a frozen version, evaluated per goal and
agreed through the signatures block (meaning `agreed`). A restrictive
measure is an action of kind `measure` that waits for the approvals block
before it starts. Observations, medications, consents and funding follow as
their own blocks on the same rule.

Codes stay data, not schema: a problem stores a `code_system` and a `code`
from `options.codeSystems`, so an app picks Omaha, NANDA-I, ICF or its own
list without a migration. Interchange formats live outside the tables: FHIR
R4 mappers (`CarePlan`, `Goal`, `Observation`, `MedicationStatement`,
`Consent`) convert rows to resources, and a national format plugs in as a
port next to them. The mappers ship separately from the blocks.

## Alternatives considered

- A `patients` table owned by the care blocks. It lost because most apps
  already have a client record (a customer, a resident, a member) and would
  have to sync two tables, and because the other subject-keyed blocks could
  not see it.
- Storing FHIR resources as JSON columns. It lost because RLS, indexes and
  the tenant scope work on columns, and because FHIR is one interchange
  format among several national ones.
- One block for the whole care record. It lost because apps adopt the parts
  one at a time (a coaching app wants plans without medications), and the
  blocks already compose through the subject registry.

## Consequences

An app installs `care-plans` over its own client table and gets tasks,
approvals, signatures, versions and guest access on it without new wiring.
The code lists and the national formats are the app's choice. The cost is
that the blocks can't enforce clinical rules a fixed schema could (such as a
required diagnosis code), so apps add them through hooks or the
`fields` option. Revisit if a national format needs columns the generic
model can't hold.
