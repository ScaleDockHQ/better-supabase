# 0107: `designDataApi` stays in `create/lite`

- Status: accepted
- Date: 2026-10-26

## Context

`designDataApi` builds the Data API for a design on PGlite, next to `importProject`, `openSandbox`
and `verifyFiles`. A separate subpath would need an exports entry, a `tsdown` entry, a size
baseline, a snapshot and a docs page for one function.

## Decision

`designDataApi` stays exported from `better-supabase/create/lite`. All of its callers already load
that entry for PGlite.

## Alternatives considered

- A `better-supabase/create/data-api` subpath: a new public entry with no caller that needs the
  split.

## Consequences

Revisit when the entry's size baseline grows enough that callers of one function notice.
