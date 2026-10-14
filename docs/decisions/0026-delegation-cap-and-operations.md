# 0026: Narrow delegated tokens inside the access functions, and name every checked action in one operations table

- Status: accepted
- Date: 2026-10-14

## Context

An OAuth client or agent acts with a delegated token: a `client_id` or an
RFC 8693 `act` chain, and the scopes the user granted it. Before 0.9 the
scopes were checked only where a policy called `token_scope_allows(scope)`,
so every policy that asked `member_can` gave the client all of the user's
permissions. Jobs and workflows queued by such a token ran as the user
alone.

Modules also named the permission each action checks in several places:
`MODULE_PERMISSIONS` for the SQL, literal keys in MCP tools, agent tools and
workflow-builder nodes, and a provider's own catalog. A provider that
renamed a key had to find every one of them, and nothing listed what an
app's modules check.

## Decision

The access functions narrow a delegated token in every access model.
`member_can`, `member_can_while_deleting`, `platform_can` and
`tenant_ids_with` ask `better_supabase.cap_allows(permission)`, which is true
only when one of the token's scopes maps to the permission
(`authorization.delegation.scopes`, merged with
`sql.modules.access.scopes`) and the `bs_permission_cap` claim, when set,
allows it. `forContext(context, { permissions })` sets that claim, a job
queued under a cap keeps it, and a cap only ever narrows (`narrowCap` in
`src/auth/delegation.ts`). A provider that maps scopes at runtime sets the
`delegation.permissions` hook on its `AuthorizationHooks`; `forContext`
caps a delegated context to the keys it returns, and a throw grants nothing.

Every action a module checks is a row in `OPERATIONS`
(`src/sql/modules/access-model.ts`), keyed `<module>.<action>`, with the
permission key it checks by default. A provider's `operations` map renames
keys, `better_supabase.operation_permission(op)` resolves one in SQL, and
MCP tools, agent tools and workflow-builder steps take an optional
`operation` that resolves the same way. Under the provider model the tenant
role helpers (`member_organization_ids`, `has_organization_role`,
`organization_member_role`) read membership from the provider, and doctor
rule BS334 points policies that check a role name at `tenant_ids_with` or
`member_can`.

## Alternatives considered

Checking scopes only in PostgREST policies through `token_scope_allows`
leaves every `security definer` function and every job unnarrowed, which is
the gap this closes.

Letting a workflow-builder graph name an operation per node lets a graph
author pick a cheaper permission than the step needs. The operation lives
on the developer-defined step library entry instead.

Keeping `MODULE_PERMISSIONS` and adding a parallel map for tools keeps two
lists that drift; one table serves the SQL, the server and the provider.

## Consequences

A delegated token gets the overlap of its scopes and the user's roles in
every check, and work it queues stays as narrow. Apps with scopes that map
to no key now see refusals where the client used to pass; the 0.9 guide
lists the mapping to add. Adding a checked action means adding a row to
`OPERATIONS`, and a provider sees it in its `operations` map. We
would revisit the scope map if Supabase Auth starts issuing
`authorization_details` that name permission keys directly.
