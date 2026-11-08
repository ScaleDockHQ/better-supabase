# 0372: Let a provider choose the wildcard grants permission_matches honours

## Status

Accepted

## Context

The plan says the `*` floor comes from the provider. The generated `better_supabase.permission_matches` always treated `*` as every key and `prefix.*` as a prefix, whatever the provider's grants hold, so a provider with exact keys still had a wildcard floor it never declared.

## Decision

ADR 0011 and ADR 0114 allow additive provider fields under `apiVersion: 1`. `AuthorizationProvider.wildcards` is `all` (the default, the existing function), `prefix` (no bare `*`) or `none` (exact key). The authorization pass copies it to the access provider, and the provider model renders `permission_matches` from it. The roles, catalog and custom models are unchanged, since the roles model's owner holds `*`. The TypeScript `permissionMatches` for delegated token caps is unchanged: it caps what a token may use and never widens a grant. The invitation SQL already comes from the provider's `platformRoles` and `functions`.

## Consequences

Unset keeps every generated function byte for byte. A provider that sets `none` or `prefix` gets a narrower function and the doctor and access matrix read it from the catalog. A fuller floor (a role that holds every key the provider lists) stays out of scope.
