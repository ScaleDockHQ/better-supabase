# 0394: Infer the notifications block and the settings schemas

## Status

Accepted

## Context

ADR 0370 cascades notifications once the block is installed, and ADR 0371 left settings out because `blocks.settings.options.schemas` takes a runtime value. An app that named `notifications` in a PowerSync stream or the browser client blocks still had to list the block as well, and an app that exports `defineSettings()` repeated that export in the config.

## Decision

Config resolution adds `notifications` to the blocks when `gen.powersync.instances` or `gen.clientBlocks` names it. A topic template alone does not install it, since templates exist with or without the block, as it does for `vector-search` (ADR 0322). The CLI config loader reads the new `settings` option of `standardSchema()`, a `./path.ts#export` string like `json`, imports that module and passes the `defineSettings()` result as `schemas` to each `settings` instance that sets none. A `schemas` option in the config wins. An export that is not a settings definition fails with `config_invalid`.

## Consequences

Two config lines disappear from apps that use them. The settings import runs only in the CLI, so the config file itself still imports no app code. The other inference items stay with their own decisions.
