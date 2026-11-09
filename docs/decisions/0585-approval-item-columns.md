# 0585: Give approval items the app's columns, and leave hiring as it is

## Status

Accepted. Amends ADR 0269.

## Context

ADR 0269 left two work items open: extra columns on approval items, steps and decisions (requests and policies had them), and a hiring simplification the plan did not describe.

## Decision

- `approval_items` takes the columns the app's schema files add, as fields, the way requests and policies do (ADR 0256). `request_approval_items` writes each item's `fields` object, a key left out keeps the column's default, and the item JSON returns them under `fields`. `ApprovalItemInput.fields` and `ApprovalItem.fields` carry them in the TypeScript client, untyped, because an item has no `options.fields` schema. A table without extra columns renders the same SQL as before, so no golden file or fixture changes.
- Steps and decisions stay without app columns. Steps live inside the policy's `steps` array rather than a table, and decisions are append-only audit rows that the block writes in the decision functions; an app column there would need a second write path that no app asked for.
- Hiring: the plan names no concrete change, and `stages` and `hiringManager` exist. Nothing is added.

## Alternatives considered

A typed `options.itemFields` schema next to `options.fields`: rejected for now. It adds an option and a generic parameter to every approvals signature for a field set that an app can read as `Record<string, unknown>` and parse itself.

## Consequences

An app that tracks a cost center or a ticket id on each requested item declares the column on `approval_items` and passes it in `fields`. Run `better-supabase upgrade` to render the new reads and writes.
