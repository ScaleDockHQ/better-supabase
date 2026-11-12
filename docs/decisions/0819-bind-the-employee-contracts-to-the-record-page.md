# 0819: Bind the employee contracts to the record page

- Status: accepted
- Date: 2026-11-13

## Context

Eight blocks have no record binding: invoices, quotes, deals, risks, employees,
leave, expenses and bookings (EX-1237). A binding loads through the block's
client with the record as the subject. Of the eight, only employees has a client
read that takes a record id (`contracts(employeeId)`); the other seven read
through the organization, a pipeline or a table filter, so a binding needs a new
client method and a SQL read for the subject first.

## Decision

Lane K ships the bindings in steps. The first adds `employeeContractsBinding` for
the employee's page: it loads `contracts`, goes stale on `employee.updated` and
`employee.deleted`, and takes one write, `remove`, because adding a contract
carries dates and money that a Server Action can't. Its permission keys are
`contractsRead` and `contractsWrite`, the module's own keys.

The remaining seven wait for a subject-scoped read each (a client method, a SQL
function and a pgTAP test), the hook `status` union and the realtime hooks. The
audit's progress section keeps them open.

## Alternatives considered

Binding the seven with a table read from the binding would skip the SQL work, but
a binding must go through the block client so permissions and hooks apply.

## Consequences

Employees gets a record section. The catalog records one more binding and the
export list gains `employeeContractsBinding`. The manifest grows by one field, which
the server baseline absorbs (ADR 0690).
