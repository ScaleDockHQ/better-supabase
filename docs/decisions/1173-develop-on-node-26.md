# 1173: Develop the repository on Node 26

- Status: accepted
- Date: 2026-11-22

## Context

Node 26 became the Active LTS line (codename Lithium) with v26.13.0 on 2026-10-28;
`nodejs.org/dist/index.json` lists v26.13.1 as the current release. Node 24 stays in
maintenance LTS. Node 26 ships `Temporal` natively, and `@types/node` is already on the
26 line in the `catalog:deps` block of `pnpm-workspace.yaml`.

## Decision

The repository toolchain moves to Node 26: `.node-version`, `.nvmrc`, and the root
`engines.node` and `devEngines.runtime` entries (`26.x`). CI reads `.node-version`, so it
follows. The published `engines.node` in `packages/better-supabase` stays `>=24`: raising
the floor rejects installs on a supported LTS and needs a breaking changeset and a
migration note, which nothing in the library requires.

## Alternatives considered

Raising the library floor to `>=26` was rejected because no code needs a Node 26 feature.
Keeping the toolchain on 24 was rejected because `@types/node` and the test setup already
assume 26.

## Consequences

CI no longer runs the suite on Node 24, so the `>=24` floor is covered only by the
Temporal polyfill path in `tests/setup/temporal.ts`. Add a Node 24 test lane if a
regression on 24 appears. Revisit the floor when Node 24 leaves maintenance in 2028-04.
