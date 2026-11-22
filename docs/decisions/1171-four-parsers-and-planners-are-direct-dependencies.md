# 1171: Make four parsers and planners direct dependencies of the CLI

- Status: accepted
- Date: 2026-11-22
- Amends: 0036
- Supersedes: 0108 (the packages are no longer optional peers)

## Context

Invariant 1 said the core depends only on `@standard-schema/spec` and the
Supabase packages, and everything else is an optional peer, lazily loaded or
typed structurally. `@supabase/pg-delta` and `@supabase/pg-topo` were optional
peers (ADR 0108), so an app that ran `better-supabase db diff` had to install
both and BS239 reported the apps that did not.

The cutover work reads SQL and TypeScript with parsers instead of hand-written
scanners. `@supabase/pg-parser` is WASM and `oxc-parser` is a native binding
per platform, so neither can be inlined into the CLI build. What each package
produces depends on its version: the migration pg-delta plans, the facts
pg-parser reads and the ranges oxc-parser returns all change between releases.
Most apps need all four for `gen`, `doctor` or `db diff`.

## Decision

The CLI and the Node entries may use a direct dependency when all three hold:
it cannot be inlined (native or WASM), the output depends on its version, and
most apps need it for `gen`, `doctor` or `db diff`.

Four packages meet that test, each pinned exactly in `catalog:deps`:

- `oxc-parser` 0.159.0 reads TypeScript.
- `@supabase/pg-parser` 0.1.7 reads SQL.
- `@supabase/pg-delta` 1.0.0-alpha.61 plans `db diff`.
- `@supabase/pg-topo` 1.0.0-alpha.8 is pg-delta's peer.

They stay external in `tsdown.config.ts` and none goes in `deps.onlyBundle`.
They load on first use with a comment, to keep CLI startup fast (invariant 12).
No runtime entry imports them; `tests/bundle/bundle.test.ts` and
`tests/standards/wintertc.test.ts` fail when one does. A test pins the
`dependencies` of the package to an allow list, so a fifth package needs a new
ADR.

`pg` stays an optional peer, because `better-supabase/postgres` hands the app
a `Pool` and the app owns that version. BS239 is retired and its code stays
reserved. BS709 reports an app that lists pg-delta or pg-topo itself, because
that writes the version twice.

A pg-delta or pg-topo alpha ships as a patch release after a plan-parity run on
the validation projects. An `oxc-parser` or pg-parser bump ships after the
parser corpora pass.

## Alternatives considered

- Keep the packages as optional peers. Rejected: the version decides the output,
  and an app on another alpha plans a different migration than the one the
  tests ran.
- Inline them. Rejected: a WASM module and a native binding cannot be bundled
  into one file without a custom loader and a copy step per platform.
- Add `@supabase/config`. Rejected: every module in 1.10 imports `effect`, a
  required peer of about 57 MB, so it stays an optional peer with the
  small-parser fallback.

## Consequences

Every install of `better-supabase` gains about 18 MB and a native binary,
including apps that stay on migra. Deployed functions do not grow. An app that
has its own copy of one package at another version installs two copies, which
BS709 reports. The pins are exact, so each bump is a better-supabase release.
