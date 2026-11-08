# 0582: Detect SvelteKit, TanStack Start and React Router with their own bindings

## Status

Accepted. Amends ADR 0332 and 0360.

## Context

The three supported meta-frameworks without a binding were detected by the library they sit on (`svelte`, `react`), so `init` wrote no server file for them and printed no server adapter. ADR 0360 made `templates` and `serverSubpath` work, but only a third party could use them.

## Decision

`BUILT_IN_FRAMEWORKS` lists `sveltekit` (detects `@sveltejs/kit`), `tanstack-start` (`@tanstack/react-start`) and `react-router` (`@react-router/dev`, framework mode) before the library bindings, because `detect` returns the first match. Each reuses its library's hooks through `hooksSubpath` and `hooksDirective`, names its server adapter through `serverSubpath`, and writes one create-once file from `src/plugins/framework-templates.ts`: `src/hooks.server.ts`, `lib/supabase/middleware.ts` and `lib/supabase/middleware.server.ts`. `init` writes `gen.hooks` with the binding's name. `tests/adapters/adapter-base-conformance.test.ts` pins the adapters that take their `expose` default from `adapterBase` and checks the refusal shape of the edge adapter (ADR 0450 left `adapterBase` without a conformance check).

## Alternatives considered

A public `testAdapterBase` kit: rejected, since each kit is a public export with a docs page and a snapshot, and only first-party adapters call `adapterBase`.

## Consequences

`gen.hooks` accepts three more names. A project that listed `hooks: "svelte"` keeps it. `init` in a new SvelteKit, TanStack Start or React Router app writes the server file the docs show. `tests/validation-new-app` asserts the file, the hint and the config key.
