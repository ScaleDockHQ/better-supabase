# 0048: The Create core is a public subpath

- Status: accepted
- Date: 2026-10-19

## Context

Create kept its design model, schema parsing, previews, deploy plans, Supabase
OAuth and Management API client in `apps/marketing/lib`. A hosted app that
designs databases needs the same code, and copying it would let the two drift.

## Decision

The code moves into `better-supabase` as `better-supabase/create` and
`better-supabase/create/supabase`. Both run on every runtime and add no
dependency. Valibot readers became hand-written type guards, because the core
depends only on `@standard-schema/spec` and the Supabase packages.
`apps/marketing` imports from the subpaths. The canvas components and the
layout code stay in the app.

## Alternatives considered

A separate `@better-supabase/create` package: another package to version and
publish for code that already tracks the library's presets. A copy in the
hosted app: the two would drift.

## Consequences

The public API grows by two subpaths, covered by the export snapshot, the size
baseline and a docs page. Designs still stay out of a server, as ADR 0040
requires; the subpaths only provide the code.
