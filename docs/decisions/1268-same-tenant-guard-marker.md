# 1268: An app trigger turns a generated same-tenant check off only with a marker

- Status: accepted
- Date: 2026-11-27
- Amends: 0430

## Context

ADR 0430 let `sameTenant.auto` skip a foreign key column that any app trigger
reads or writes through `new.<column>` or `old.<column>`. An adopter's triggers
on chat messages and inbox threads read the thread column for other reasons, and
the generated `bsb_same_tenant_thread_id` and `bsb_same_tenant_chat_thread_id`
checks disappeared without a warning. A row could then point at a thread in
another organization.

## Decision

`sameTenant.auto` skips a column only when an app trigger function declares it
with `@bsb same-tenant-guard column=<column>[,<column>]`. Reading the column is
no longer enough. Doctor BS398 keeps warning when a marked trigger never
mentions the tenant column, and the new info finding BS733 lists every column a
marker turns the generated check off for. BS340 and BS217 accept a marked
trigger the way they accepted any touching trigger before.

## Consequences

An app whose trigger already guarded a column without the marker gets the
generated check back on the next `upgrade`; both checks run until the app adds
the marker or drops its own. The change can add a trigger, never remove one, so
it fails safe.
