# 0332: Register framework bindings with defineFramework

- Status: accepted
- Date: 2026-11-07

## Context

The `gen.hooks` frameworks were a hard-coded union (`DataHooksFramework`), a
picklist in the config schema, a default in `resolveConfig` that listed the
adapters implying React, and a `config.hooks === "react"` check that wrote
`"use client"`. A new framework meant editing five lists, and a package outside
this repository could not add one.

## Decision

`defineFramework` in `better-supabase/plugins` builds a `FrameworkBinding` at
`apiVersion: 1`: `name`, `tier`, `detect`, `integrations`, `hooksSubpath` or
`hooksModule`, `hooksDirective`, `serverSubpath` and `templates`. The built-in
`react`, `svelte`, `vue` and `solid` bindings live in
`src/plugins/frameworks.ts` and use only that contract.

- `frameworks: [binding]` in `gen` registers a binding. `ResolvedConfig` keeps the
  registry as `frameworks`, and `hooks` is any registered name; `resolveConfig`
  refuses one nothing registers.
- The default framework comes from `integrations`, so `next`, `react` and `expo`
  select `react` because the binding says so.
- `emitHooks` takes the import and the directive from the binding.
- `detectProject` returns `hooksFramework` from the registry, and `init` writes
  `gen.hooks` for a detected framework that no adapter selects.
- The config schema lists the built-in names for completion and accepts any
  well-formed name, which `resolveConfig` checks against the registry.

## Not done

`serverSubpath` and `templates` are part of the contract and are printed with the
config, but the adapter tables and `init`'s integration templates still list
their frameworks themselves. The capability registry does not read bindings yet.

## Alternatives considered

- **Open the union to any string with no registry.** `gen` could not tell a typo
  from a package, and `init` could not detect anything.
- **Separate packages per framework.** One release train, as ADR 0047 chose for
  the CLI contract.

## Consequences

A third-party framework needs a config entry and a hooks module. Adding a
built-in framework is a binding and its runtime subpath instead of five lists. A
change to the binding contract needs a new `apiVersion`.
