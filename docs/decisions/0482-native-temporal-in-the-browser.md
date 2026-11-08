# 0482: Use the runtime's Temporal in the browser and load the polyfill only when it is missing

- Status: accepted
- Date: 2026-11-08
- Amends: 0005

## Context

`temporal-polyfill` was imported statically by the browser app (`client-app.ts`)
and by 16 components, so every route that ran the client shipped 54 KB raw even
in browsers with native `Temporal` (Chrome and Firefox).

## Decision

Browser code in the example reads the global `Temporal`; `createSupabase` falls
back to `globalThis.Temporal` already, so the library is unchanged. The `(app)`
data providers wrap their children in `components/temporal-gate.tsx`, which
starts `import("temporal-polyfill/global")` when `Temporal` is missing and
suspends its subtree until it arrives. The server keeps the named import and also
imports `temporal-polyfill/global` in `lib/supabase/app.ts`, so Node 24 renders
without waiting. The only new lazy imports are in the example app; the library's
list in `.agents/rules/lazy-imports.mdc` is unchanged.

## Alternatives considered

An option on `createSupabase` that takes a loader. Rejected: the library already
reads the global at call time, and the gate also covers components that use
`Temporal` directly.

## Consequences

Browsers with native `Temporal` save 54 KB raw (20 KB brotli) on app routes.
Safari fetches the polyfill chunk while it hydrates and the subtree hydrates
after it arrives; the server HTML stays on screen meanwhile.
