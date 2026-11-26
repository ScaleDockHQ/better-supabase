# 1259. Directives for scope helpers (proposed, not built)

Date: 2026-11-26

## Status

Proposed

## Context

The plan ends with `"use auth"`, `"use tenant"` and `"use permissions"` as sugar over the
scope helpers and the action shell. The functions stay the documented form.

## Decision

Compile each directive to the matching call (`withContext`, the tenant scope and the
permission gate) in a build transform wired by `withBetterSupabase`, with a Vitest
transform that applies the same rewrite in tests.

A Next.js SWC plugin is a Rust and WASM artifact pinned to each Next.js release (Next
16.4.6 today). It cannot be built or verified in this repository's Node-only toolchain,
and a directive cannot carry a typed permission ref, so `"use permissions"` would need
a string key the type checker never sees.

## Consequences

Nothing ships in this change. Before building: decide the pinning policy per Next.js
release, whether `"use permissions"` takes a string key, and whether the transform
should run through the oxc parser the CLI already pins instead of SWC. Until then the
documented form is the helper functions.
