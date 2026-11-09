# 0434: No block policy calls can() per row, and the provider set helper is the template that serves

- Status: accepted
- Date: 2026-11-09
- Amends: 0426

## Context

The scale report asked for a provider placeholder for the provider's set helper so
that a block policy never renders a per-row provider call. ADR 0426 left the
attachments insert policy on `can()` because its permission is a `case` over the
subject type. A search of every module, with and without subjects, found that
policy as the only one left.

## Decision

- The attachments insert policy uses `memberOn`, the set form the read policy
  already uses: it renders the per-subject-type permission as a `case` over keys
  inside `tenant_ids_with`-based sets, so the upload check runs once per
  statement.
- `tenant_ids_with` is the provider set helper. Under the provider model it calls
  the provider's `idsWith` template once per statement, so a block policy that
  uses it never reaches a per-row provider call; no new placeholder is needed.
  The existing authorization template (`authorization.functions.idsWith`) is
  what a provider fills.
- The registry test now checks `with check` as well as `using`: no policy of any
  module may call `better_supabase.can('tenant', "<column>", ...)`. It passes for
  every module, with and without subjects.

## Measured

Plan shape only: the attachments insert policy has no `can(` call (pgTAP
`attachments_policy_inline`). Inserts are a few rows per statement, so there is no
timing to report; the benefit is the same as for reads (ADR 0424).

## Consequences

`better-supabase upgrade` rewrites the attachments module and the next schema
migration replaces one policy. No data migration.
