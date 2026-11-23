# 1220: Drive roles can live without grant rows

- Status: accepted
- Date: 2026-11-23
- Supersedes: the drive `grants` mode part of [0586](0586-drive-grants-and-block-client-views-stay-deferred.md)

## Context

ADR 0586 deferred a drive mode without the grants table until the provider
contract typed a role as a function of `(user, node)`. The scale report
(BS-10) asked for it again: an app whose roles already live in a role table or
a relation graph kept an unused `drive_grants` table, and `drive_share` wrote
rows the app's role function then ignored, so two places claimed to decide
access.

`options.roleFunctions.node` already returned the role, as a named function or
as `{ rows, roles }` over the provider's `rowsWith`. The second form maps
permission keys to roles, so a provider whose roles are not permission keys had
to ship a hand-written function.

## Decision

- `AuthorizationProvider.functions.roleOn` (API 1, optional) is a template
  with `{user}`, `{resource}` and `{id}` that returns the role `{user}` holds
  on one row as text, or null. It is plain data like every other template, and
  `testAuthorizationProvider` checks that it names all three placeholders.
- `roleFunctions.node: { rows }` without `roles` calls `roleOn`. A value
  outside the drive's `roles` counts as no role. `roleFunctions` keeps its
  other two forms.
- `blocks.drive.options.grants` is `"table"` (the default) or `"roles"`. With
  `"roles"` the grants table is omitted through a new `omitWhen` field on a
  block table spec, so the context reports it as absent everywhere: no DDL, no
  lifecycle entry, no `database.types.ts` entry with `principalType` and
  `principalId`. It needs `roleFunctions.node`, and refuses `uploadRole` and a
  `tables.grants` mapping, since both need grant rows.
- In roles mode `drive_role` and `drive_readable_ids` read the role function
  only, `drive_grants(node)` lists each active member the role function gives
  a role (as a non-inherited `user` principal, so the client keeps one shape),
  `drive_share` and `drive_unshare` refuse with `DRIVE_SHARING_EXTERNAL`
  (SQLSTATE `0A000`), `drive_shared` lists items the role function opens, the
  purge trigger has no grant rows to delete, and `drive_transfer_ownership`
  moves drive grants and drive owners only. Access requests stay unavailable
  with a node role function, as before.
- With `roleFunctions.node` in table mode, `drive_role` no longer renders the
  grant query after the role function's early return. The default
  configuration renders the same SQL as before, and the golden files did not
  change.

## Consequences

An app that sets `grants: "roles"` drops `drive_grants` in its next schema
diff, so it moves any rows it still needs to its role source first. Sharing UI
built on `drive_share` stops working in that mode by design: the role source
is the one place to change access. Drive-level grants (`drive_drive_grants`)
are not covered; a drive role function already replaces them for reads.
