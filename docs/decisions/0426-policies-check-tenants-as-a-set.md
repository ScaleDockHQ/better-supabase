# 0426: Check tenants as a set in block policies

- Status: accepted
- Date: 2026-11-08
- Amends: 0104

## Context

`better_supabase.can('tenant', "tenant_id", 'key')` with a column argument runs
once per row, even inside `(select ...)`. The access contract says to use
`tenant_id in (select better_supabase.tenant_ids_with('key'))` in a policy.
Searching the generated schema found two policies that still called `can` with a
column: the organization settings insert policy and the attachments insert
policy.

## Decision

The settings insert policy uses the set form (`ctx.scope.check`). The
attachments insert policy keeps `can(...)`: its permission is a `case` over
`subject_type` (`messages.send`, `expenses.submit`, `attachments.upload`), which
a set cannot express without one set per key; it is left as the next slice, with
the provider set-helper placeholder (a template for the provider's set helper so
a block policy never renders a per-row provider call), which is not built.

## Measured

Plan shape only: the settings insert policy has no `can(` call and carries
`tenant_ids_with` (pgTAP `settings_insert_set_check`). The settings table has
few rows, so there is no timing to report.

## Consequences

`better-supabase upgrade` rewrites the `settings` module and the next schema
migration replaces one policy. No data migration. The read-sets module is
regenerated too, because its count now uses the estimated mode (ADR 0425).
