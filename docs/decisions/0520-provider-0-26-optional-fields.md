# 0520: Accept the 0.26 provider fields as optional additions

- Status: accepted
- Date: 2026-11-08
- Amends: 0011, 0114

## Context

[Issue 729](https://github.com/ScaleDockHQ/better-supabase/issues/729) asks
better-supabase to accept the fields an authorization library fills from one
definition, without requiring them and without a new `apiVersion`. Three gaps
remained: the entitlements mode refused a provider that listed its membership
rows but no `memberIds` template, the bootstrap subject always carried every
tenant, and `tools/list` of 300 tools made one `evaluations` call per distinct
permission.

## Decision

The provider contract stays `apiVersion: 1` and gains optional fields only:

- `functions.subjectForTenant` (`{tenant}`, `{scope}`), `functions.approverFor`
  and `functions.managedUsers`; `memberships[].userKey` and `suspension.userKey`;
  `permissions[].levels` with `<permission>@<level>` keys
  (`permissionLevelKey`, `splitPermissionLevel`); `tokenHook.teamIdsTruncatedClaim`;
  `personas: "roles"` with `fixtureRoles` (`resolvePersonas`).
- `memberIds` and `memberIdsFor` are derived from `memberships` for the tenant
  scope when the provider leaves them out (`providerFunctions` in
  `cli/authorization.ts`). A template the provider sets wins.
- `suspension.userKey` becomes `blocks.permissions.disabled.userKey` unless the
  config sets it. BS426 reports a `disabled` value equal to the provider's.
- A bootstrap call that names a tenant calls `subjectForTenant` when the target
  uses the provider's `subject`, and returns `null` for a tenant the template
  refuses.
- `outcomesOfMany` sends every check of `tools/list` in one `evaluations` call.
  An authorizer without `evaluations` is called once per tool.

`memberships[].userKey`, `approverFor`, `managedUsers`, `levels` and
`teamIdsTruncatedClaim` are accepted and validated; no module reads them yet.
They are the slots a library fills, and the schema, the placeholder table and
the docs list them so a provider can set them today.

## Alternatives considered

- A `checkMany` method on `Authorizer`. Rejected: AuthZEN Access Evaluations
  already takes a different action per request, so the existing optional
  `evaluations` method is the batch contract.
- Requiring `memberIds` whenever `memberships` is set. Rejected: the rows say
  how to read members, so a second template is a copy that goes stale.

## Consequences

A provider that fills the new fields works on better-supabase 0.58, and an older
better-supabase ignores them. `upgrade` rewrites the `sessions` module (the
bootstrap wrapper) only for an app that sets `subjectForTenant`, and no data
migration is needed. Tests: `tests/cli/provider-row-contract.test.ts`,
`tests/mcp/permissions.test.ts`.
