# 1174: BS427 compares resolved values

- Status: accepted
- Date: 2026-11-22
- Amends: 1164

## Context

BS427 compared a config entry with the provider's value by `JSON.stringify`
equality, so the same value written with another key order, another order of
`active` values, extra white space or another case in unquoted SQL never
matched. `blocks.permissions.activeTenant` was not checked at all, and the BS409
fix text did not name the provider fact.

## Decision

Two values are equal when they resolve to the same thing: object keys sorted,
`undefined` entries dropped, `active` values sorted, and the SQL templates in
`where`, `canAssign`, `canAssignFor` and the claims hook name compared as
tokens (white space ignored, unquoted words folded to lower case, string
literals, quoted identifiers and placeholders kept). `codemod config --prune`
uses the same function.

A column string (`schema.table.column`) and an active row (`{ table, id,
disabledAt }`) stay unequal. The plan asked for the string to be parsed into the
row form, but a missing row disables a tenant or user only in the row form, so
the two render different SQL and removing one would change the output.

`blocks.permissions.activeTenant` set to `"resolver"` is reported as a restated
default. The config does not inherit the provider's
`tokenHook.activeOrganizationFrom`, so a provider value other than the default
is not a restatement; BS409 still compares the two. Its fix text now names the
provider fact, and the docs say `"resolver"` means the request.

## Consequences

BS427 reports more restatements, each safe to remove. The value `"resolver"`
keeps its name, so `apiVersion` stays 1.
