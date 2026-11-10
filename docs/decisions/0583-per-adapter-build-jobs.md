# 0583: Build each example app that has a bundler in its own CI job

## Status

Accepted

## Context

The docs build had a CI job, but the Next.js and Vite examples built only inside `verify` through the Turbo cache, so a failing framework build showed up as one red step among many. The other examples (Hono, Express, Edge, MCP, oRPC, Expo, eve) have no build script, and SvelteKit, TanStack Start and React Router have no example app.

## Decision

`ci.yml` has an `Adapter build` job for `@better-supabase/example-vite-react`.
The Next.js example is built by `verify / test`, which reads the build to
check the route baselines, so CI does not build it a second time. A new
example with a build script joins the matrix, except a Next.js app whose
build `verify / test` already depends on.

## Not done

SvelteKit, TanStack Start, React Router, Solid Start, Nuxt and Astro have no example app, so they have no build. Adding them needs the frameworks in the dependency catalog under `minimumReleaseAge`, and `tests/validation-new-app` covers their `init` output until then.

## Consequences

A framework bundler failure names its framework in the check list. The Vite job adds one parallel runner per pull request that changes it. The Next.js build is the one `verify / test` already runs.
