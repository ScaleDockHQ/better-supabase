# 1260. Batch a record page's binding reads in one call

Date: 2026-11-26

## Status

Accepted

## Context

A record detail page shows several bindings (tags, custom fields, files,
relations, versions). `bsb.record(type).get` loaded each binding through its
block client, and each client made its own PostgREST RPC. The customer page made
13 database calls and the deal page 12, most of them one-row reads that ran at
the same time. Read sets already fold related reads into one stable
function, but they are compiled per page from a fixed list, and a record page's
bindings depend on the caller's permissions and on what the page asks for.

## Decision

The `read-sets` module writes `read_batch(calls jsonb)`: a `stable`, `security
invoker` plpgsql function with an empty `search_path` that takes an array of
`{ fn, args }`, at most 50, and returns one entry per call, in order: `{ data }`,
`{ error: { code, message, details, hint } }` or `{ skipped: true }`. With
`api` set it is exposed in the API schema like the module's other client
functions (`CLIENT_FUNCTIONS`).

The function adds no access. It runs as the caller, so the caller's execute
grants and RLS apply to every inner call, as they do for a direct Data API call.
It looks functions up only in the schema the Data API exposes (the API schema
when the config sets `api`, the module schema otherwise), so it reaches no
function the Data API hides. It runs only plain functions (`prokind = 'f'`) that
are `stable` or `immutable`, return `jsonb`, don't return a set and whose
argument names cover the keys passed, and never itself. Any other call is
skipped, not run. Each call runs in its own exception block, so one failure
doesn't fail the batch.

On the client, `readBatch` (`src/core/read-batch.ts`, internal) wraps the block
transport for one `get` or `timeline`. Every binding load is a participant; once
each participant has queued a read or is waiting on one, the queue goes out as
one `read_batch` call. A group of one goes direct. A data entry resolves, an
error entry rejects with the same error a direct call gives, so `blockCall`
maps it to the same `DbError`. A skipped call reruns direct, and the process
remembers it, so the next batch sends it direct alongside. When the function is
missing (`PGRST202` or `42883`) every call goes direct and the schema is
remembered. Hidden bindings never run.

## Alternatives considered

One read set per page. It needs a definition per page and per permission
shape, and a read set can't call `volatile` reads, so a page with subject read
logging would still make the same calls.

Next.js request dedupe. `fetch` dedupe only merges identical requests, and the
bindings are different RPCs, so it removes nothing here.

A function per record type that reads every binding. It ties the database
schema to the app's record types and must be regenerated when a page adds a
binding.

## Consequences

The example's detail pages make fewer calls: the customer page goes from 13 to
8 and the deal page from 12 to 8. A page has to ask for all of its bindings in
one `get` (the example does this with a `cache()`d loader per record) to get the
saving. Reads that write (`volatile`, such as `get_field_values` with read
logging on) still run on their own. A new read function that returns `jsonb`
and is `stable` joins the batch without changes; one that doesn't is skipped
and runs direct.
