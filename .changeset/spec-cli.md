---
"better-supabase": minor
---

New `better-supabase spec emit`, `spec check` and `spec validate` commands. `spec emit` renders every output in the new `specs` config key (format, version, output file, overlays, JSON or YAML, and an optional reference page), applies the overlays and caches renders by content hash. `spec check` fails when a file on disk is out of date, `spec validate` checks each document against the official JSON Schema for its version, and every run writes a diagnostics manifest. `--fail-on`, `--ui`, `--watch` and `--manifest` cover CI, reference pages and local work. `openapi emit --check` now compares text the same way `spec check` does.

`better-supabase scaffold api` writes the resource routes and an OpenAPI route for Hono or Next.js: `lib/<name>.generated.ts` on every run and `lib/<name>.ts` once, for your own changes.

The `openapi` config key is deprecated. It still works and maps onto `specs`; move it to `specs.outputs` with `format: "openapi"`.
