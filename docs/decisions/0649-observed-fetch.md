# 0649: Observe the server's Supabase requests with a fetch wrapper

- Status: accepted
- Date: 2026-11-10

## Context

`createServer({ fetch })` already routes every request of the Data API, Auth and Storage clients through
one `fetch`, but an app that wants to count, time or trace them had to write the wrapper itself, and
the common mistakes (logging the query string with the token, letting an observer throw into the
request, losing the original error) are easy to make. `p5b-runtime` listed `observedFetch`.

## Decision

`observedFetch({ onCall, fetch?, now? })` in `better-supabase/server` returns a `fetch` that calls
`onCall` after each request with the method, the URL without its query string, the status (or the
error name) and the duration. A throwing observer is ignored, a thrown request is rethrown unchanged,
and the response is returned as received. It imports nothing from Node and keeps the server entry
a runtime entry.

## Alternatives considered

- Record into `ctx.stats()`: the recorder counts tables, not requests, and is per context; the wrapper
  is per process. Feeding the recorder stays open.
- Put the observer on `ServerOptions`: it would need its own option beside `fetch`, and a wrapper
  composes with other wrappers.

## Consequences

One new export of `better-supabase/server` and two types. The context factory, route kit, API key on
`ctx.auth` (already `auth.kind === "apiKey"`) and batch block reads remain.
