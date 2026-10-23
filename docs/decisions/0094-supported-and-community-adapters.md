# 0094: Split the framework adapters into supported and community tiers

- Status: accepted
- Date: 2026-10-23

## Context

better-supabase ships fourteen framework adapters on the
`@supabase/middleware` entries from ADR 0008. They do not get the same care
today:

| Adapter        | Unit tests | `testAdapter` | Type tests        | Example app                | Integration |
| -------------- | ---------- | ------------- | ----------------- | -------------------------- | ----------- |
| Next.js        | yes        | yes           | own `test-d`      | `nextjs`                   | yes         |
| Hono           | yes        | yes           | own `test-d`      | `hono-api`, `monorepo/api` | yes         |
| Expo Router    | yes        | yes           | own `test-d`      | `expo-powersync`           | no          |
| SvelteKit      | yes        | yes           | yes, and previous | none                       | no          |
| TanStack Start | yes        | yes           | yes               | none                       | no          |
| React Router   | yes        | yes           | yes, and previous | none                       | no          |
| Edge           | yes        | yes           | own `test-d`      | `edge`                     | yes         |
| H3             | yes        | yes           | yes               | none                       | no          |
| Elysia         | yes        | yes           | yes               | none                       | no          |
| H3 1 and Nuxt  | yes        | no            | yes, and previous | none                       | no          |
| Node           | yes        | no            | yes               | `express`                  | no          |
| NestJS         | yes        | no            | no                | none                       | no          |
| Astro          | yes        | no            | yes               | none                       | no          |
| SolidStart     | yes        | no            | yes               | none                       | no          |

"Type tests" is `tests/frameworks.test-d.ts` or an adapter's own `test-d`
file; "previous" is `tests/types/frameworks-previous`. CI has no per-adapter
matrix: all of these run in the `test` and `typecheck` jobs. New guides
(blocks, the API layer, auth recipes) cannot be written and kept current for
every adapter, and users cannot tell which adapters get that work.

## Decision

The adapters fall into two tiers, listed in
`packages/better-supabase/tests/adapters/tiers.ts`.

Supported: `next`, `hono`, `expo`, `sveltekit`, `tanstack-start` and
`react-router`. Each gets the full test matrix (unit tests, a `testAdapter`
conformance run, type tests and an example app), a docs page that every new
guide covers, and triaged issues.

Community: `astro`, `edge`, `elysia`, `h3`, `h3/v1` (with `nuxt`), `nestjs`,
`node` and `solid-start`. Each keeps shipping in every release, keeps its
existing tests, and gets a smoke test in
`tests/adapters/community-smoke.test.ts` that serves one signed-in request
(the Nuxt module, which needs Nitro to serve, is installed and checked
instead). Its docs page opens with a community note that links the tiers on
`/docs/frameworks#adapter-tiers`. Fixes and new features may lag.

The tiers follow usage. An adapter moves up when many apps run it and moves
down when few do. A move happens in a minor release with a changeset, and
moving up means adding what the supported tier gets first.

## Alternatives considered

Keeping one tier promises a matrix the repo does not run, and grows with each
adapter. Removing the less used adapters would break apps that run them,
while their bridges are about ten lines on ADR 0008 and cost little to keep.
Moving community adapters to separate packages would add release and version
work for no change in what they do.

## Consequences

Guides, examples and conformance runs go where most apps are, and a user can
read the tier before picking a framework. SvelteKit, TanStack Start and React
Router have no example app yet, which the supported tier now asks for. A
community adapter can break in a way its smoke test misses; its existing unit
tests still run. Revisit the list when usage data changes or a framework
ships its own official bridge.
