# 0586: Keep the drive grants mode and block client reads through views deferred

## Status

Accepted. Amends ADR 0270, 0393 and 0471.

## Context

The plan asks to revisit two items: a drive `grants` mode (ADR 0270, 0393), and projection views for block clients, with the condition that the design keeps the static-module rule (ADR 0250, 0471).

## Decision

Neither lands in this change, and each has a stated reason.

- Drive `grants` mode. `options.roleFunctions` already lets the app or the authorization provider answer a user's role on a node or drive. A mode without the grants table changes the sharing, offboarding, access-audit and link functions: more than sixty statements across the drive modules, each reading `drive_grants`. The change needs a role source that is a function of `(user, node)`, which the provider contract (ADR 0114) does not yet type for drive. It waits for that contract, then lands as one change with its own golden files.
- Block clients through views. A block's SQL functions carry their own tenant checks and are generated as static module files, so they cannot name an app view: the view may be renamed, dropped or absent, and `upgrade` would then write a module that fails at run time. Two designs were considered. A per-instance `readFrom` option that renders a second read function over the view breaks the rule, since the module text depends on an object the app owns. A generated read in the app's `lib/` over the typed client (`db.<view>`) keeps the rule, and ADR 0471 already ships it for lists. What it lacks is the block functions' derived fields, which a view cannot compute without the function. No design keeps both, so the block clients stay on the block table.

## Consequences

Both stay in the deferred list of ADR 0393 with these reasons. The typed client reads views today, and `roleFunctions` covers drive roles.
