# 0822: Bind the remaining blocks through a subject read

- Status: accepted
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

## Consequences

Invoices, quotes and deals landed first (K3a): `list({ subject, limit })` over
`list_invoices_for_subject`, `list_quotes_for_subject` and
`list_deals_for_subject`, in migrations `20261215000001` and `20261215000002`.
The invoices and quotes reads are security definer and check the read key on
the organization. The deals read runs as the caller so the table's row level
security decides which deals show. `list` is the verb because the data contract
retires `forSubject` (`tests/blocks/data-contract.test-d.ts`). A later lane that
gives these blocks a general `list` extends the same method.

### K3b: bookings, expenses, leave and risks

The reads differ from the first plan because the blocks already hold most of
what they need.

| Block    | Read                              | Subject and limit                                                                  |
| -------- | --------------------------------- | ---------------------------------------------------------------------------------- |
| bookings | `forCustomer({ subject, limit })` | the customer's user id; `list` already takes a range, so the verb is `forCustomer` |
| expenses | `list({ userId })`, no new method | the member's user id; reports belong to a member, not an employee                  |
| leave    | `forOwner({ subject, limit })`    | `employee` filters by `employee_id`, any other type by user id                     |
| risks    | `linkedTo({ subject, limit })`    | any record a relation from the risk points to                                      |

Expenses and leave need no migration: `list_expense_reports` and
`list_leave_requests` already filter by `user_id`, and the leave function takes
`employee_id` when the table's owner is the employee. The limit is that a leave
table keyed by user only has no `employee_id` argument, so an `employee` subject
fails there and the page binds to the member instead (recorded in the leave
docs). Risks gets no new columns: a risk already links to records through the
relations block, so `list_risks_for_subject` reads those links, and without
relations the read does not exist, so EX-1237 holds for risks only where the
relations block is installed. The new functions are `list_bookings_for_customer`
(invoker, so policies decide) and `list_risks_for_subject` (definer, checks
`risks.read`), in migration `20261215140009`.
