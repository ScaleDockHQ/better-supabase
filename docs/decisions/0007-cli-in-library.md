# 0007: Ship the CLI inside better-supabase

- Status: accepted
- Date: 2026-10-03

## Context

ADR 0003 moved the CLI to its own package, `@better-supabase/cli`, so the
CLI could take dependencies (citty, c12, Valibot, clack and the rest)
without adding them to every app's runtime install (invariant 1). The two
packages were released together through a Changesets `fixed` group.

The 0.3.0 release published `better-supabase` but not the CLI: npm answered
the CLI's first publish with a 404, because trusted publishing is set up
per package on npmjs.com and the package did not exist yet. The first
release would have needed a manual publish, and until then every install
command in the docs pointed at a package that did not exist.
Two packages also meant two install lines, two versions to keep in step in
an app, and `npx @better-supabase/cli init` instead of
`npx better-supabase init`.

## Decision

The CLI lives in `packages/better-supabase/src/cli`, its tests in
`tests/cli`, and the package ships the `better-supabase` bin
(`bin/better-supabase.js`, which imports `dist/cli/bin.js`). Its public API
(`run`, `registerCommand`, `defineCliCommand`, introspection and codegen) is
the `better-supabase/cli` subpath. `@better-supabase/cli` is gone, and the
`fixed` group with it.

`tsdown.config.ts` builds the CLI in a second config, on the Node platform.
The CLI's packages are devDependencies, and the build inlines them: the
`deps.onlyBundle` list names every package that may end up in the bundle,
so a new CLI dependency fails the build until it is listed. Apps install no
CLI dependency, which keeps invariant 1. c12's optional peers (`dotenv`,
`giget`, `jiti` and `magicast`) stay external, because c12 loads each one
through `import()` with a fallback. `@supabase/postgrest-typegen` was
already a dependency of the library and stays external, as do `pg` and
`@supabase/config`, which are optional peers.

The CLI imports the library through its entry files only, and the
`library-entries` plugin in the CLI build turns those imports back into
`better-supabase/*` specifiers. At run time the CLI loads the same modules
as the app's config, so `defineSchema` and the SQL kit exist once.
`tests/cli/imports.test.ts` fails on an import that reaches past an entry.

The CLI keeps its coverage thresholds as a `src/cli/**` set in
`vitest.config.ts`; the top-level thresholds cover the rest of the library,
so neither set went down. Its lint overrides moved into the library's
`oxlint.config.ts`.

`scripts/sync-versions.ts` writes the package version into both `VERSION`
constants, the plugin manifests and `server.json`; `pnpm version-packages`
runs it after `changeset version`. Before this, every `VERSION` was
`0.0.0` in the published build, including the one stamped into SQL kit
files and doctor reports.

## Alternatives considered

- Publish `@better-supabase/cli` by hand once, then let trusted publishing
  take over. It fixes the release, but keeps the two install lines and the
  version pairing in every app.
- Move the CLI into the library and list its packages as dependencies. Every
  app would install citty, c12, clack, Valibot and the rest at runtime,
  which breaks invariant 1.
- Keep `packages/cli` as a private workspace and copy its build into the
  library. The library build would depend on a package that depends on the
  library, a cycle in the Turbo task graph.

## Consequences

One package, one install line, and `npx better-supabase init` works. The
tarball grows by the CLI's bundle (about 670 KB unpacked in `dist/cli`), which
runtime entries never load. The CLI startup baseline in `tests/bundle` now
counts citty, c12 and clack, which it left out when they were dependencies,
so it reads 59 KB gzip instead of 12 KB for about the same work.

Bundled packages get updates only when the library is released, so a
security fix in a CLI dependency needs a better-supabase release instead of
a lockfile refresh in the app. Revisit this if the CLI's dependencies start
to need fixes faster than the library ships.

## Addendum: postgrest-typegen as an optional peer

`@supabase/postgrest-typegen` moved from `dependencies` to an optional peer,
pinned to the same exact version in the `peers` catalog. Apps that only use
the runtime entries (an Expo app, an edge function) no longer install it or
its arktype dependency. The CLI loads it in `src/cli/introspect/typegen.ts`
and stops with an install message naming the pinned version when it is
missing; `init` adds it next to `pg`. The published types reference a copy
of `GeneratorMetadata` in `src/config/generator-metadata.ts`, and
`tests/config/generator-metadata.test-d.ts` fails when the copy and the
pinned package disagree. It stays external to the CLI bundle, so the
version an app installs is the one that writes its `database.types.ts`.
