# Adapters

Framework adapters (`hono`, `edge`, `node`, `astro`, `nuxt` and the rest),
the clients (`client`, `client/native`) and the local-first entries
(`powersync`, `expo-sqlite`, `tanstack-db`).

## Shared guards

- Every server adapter takes the same guard options, `KitRequireOptions`
  (`roles`, `roleClaim`, `requireTenant`, `authorize`). Add a guard there,
  not in one adapter, so `bs.require`, `bs.authed`, `bs.routes` and the
  Next.js helpers stay in step.
- The fixture puts the role in the top-level `user_role` claim, so the
  examples pass `roleClaim: "user_role"`. The default is `app_metadata.role`;
  the top-level `role` claim is `authenticated` for every signed-in user.
- `bs.routes` types `ctx.params` from the route key. Keep the compiled
  routes typed with `never` params (`src/edge/routes.ts`): a cast from the
  key-typed map to a record of handlers is not comparable.

## Loading in Node

- `tests/bundle` imports each adapter in plain Node ESM (`NODE_LOADED`).
  A new adapter goes on that list. Import peers by the specifier Node
  resolves (`next/navigation`, not `next/navigation.js`).
- `./expo` stays off the list: expo-server 57's ESM build has extensionless
  relative imports that only Metro resolves.
- Frameworks are typed structurally where possible, so an adapter adds no
  peer. An SDK the adapter calls at runtime is an optional peer loaded
  lazily (invariant 12).

## Native and local-first

- `client/native`, `react/native` and `powersync/react` import React Native
  or Expo modules and never load in Node; test them with the fakes in
  `tests/fixtures` and keep their logic in modules that don't import those
  packages.
- Expo packages follow the SDK's version line (57.x). The trust policy
  (`trustPolicy: no-downgrade`) rejects some fresh releases; pin a release
  older than 30 days instead of an exception. Query versions with
  `curl https://registry.npmjs.org/<pkg>` when `pnpm view` fails.
- Queries over a local executor (PowerSync, expo-sqlite) get their own
  `scope` in `createQueries`, so local and PostgREST results never share a
  TanStack Query cache entry.

## Fixture modules for a block

- Install a block's SQL module from `apps/examples/nextjs` with
  `pnpm exec better-supabase sql sync`, then
  `SUPABASE_EXPERIMENTAL_STACK=1 pnpm supabase:sync <name>` (pg-delta needs
  the native stack on a VM without Docker).
- Run `pnpm exec better-supabase sql data` after that migration exists. A
  data migration stamped before the schema migration fails on reset; delete
  it and run the command again.
- On a VM where lefthook's `prepare` fails, install with `CI=1 pnpm install`.
