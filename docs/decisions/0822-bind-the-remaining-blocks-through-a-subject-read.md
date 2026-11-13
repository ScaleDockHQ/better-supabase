# 0822: Bind the remaining blocks through a subject read

- Status: proposed
- Date: 2026-11-13

## Context

Invoices, quotes, deals, risks, leave, expenses and bookings have no record
binding (EX-1237). A binding's `load` gets the block client and the record, not an
organization id, and none of the seven clients has a read that takes a record.

## Decision

Each block gets a read that takes the record and resolves the organization from
the block's own `tenant` option, as its other calls do (`requireTenant(options.tenant)`
from `src/core/block-tenant.ts`; a call without a tenant fails with
`TENANT_REQUIRED`). The binding calls that read, so it never passes an
organization id and a record page of another organization reads nothing.

| Block    | Read                          | Subject it binds to                  |
| -------- | ----------------------------- | ------------------------------------ |
| invoices | `list({ subject })`           | the invoice's company or contact     |
| quotes   | `list({ subject })`           | the quote's company, contact or deal |
| deals    | `list({ subject })`           | the deal's company or contact        |
| expenses | `forEmployee({ employeeId })` | an employee                          |
| leave    | `forEmployee({ employeeId })` | an employee, in every owner mode     |
| bookings | `list({ subject })`           | the customer                         |
| risks    | `list({ subject })`           | the record a risk is about           |

Each read is a SQL function in the block's module (a new migration in slot
20261214), with a pgTAP test for the allowed and the forbidden caller, and a
client method with a unit test over a fake transport. Writes stay out of the
bindings where an input carries dates or money, which a Server Action cannot take.

Risks has no subject column. Adding `subject_type` and `subject_id` through a
migration is the decision; if the column can't be added without breaking an app's
own table, the binding does not apply and EX-1237 stays partly fixed for risks.
Leave filters by `employee_id` in every owner mode: where the table keys requests
by user, the read joins through the employee's `user_id`.

## Alternatives considered

Passing the organization id to the binding would change `defineRecordBinding` for
every block. Reading the table from the binding would skip the block's permission
checks and hooks.

## Consequences

Seven blocks gain a record section, the catalog records their writes, and each
manifest grows (ADR 0690 baseline reset in the PR that lands them).
